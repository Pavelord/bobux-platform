#!/usr/bin/env python3
"""
rbxl_converter.py — Converts Roblox .rbxl / .rbxlx place files to intermediate JSON.

Usage:
    python rbxl_converter.py <input.rbxl|.rbxlx> <output.json>

The intermediate JSON is consumed by the Godot side of the Bobux RBXL Importer
(`instance_builder.gd` for the editor importer, `rbxl_runtime_importer.gd` for
the in-game Place Editor bridge).

References:
    * Binary format spec: http://dom.rojo.space/binary.html
    * Reference implementation: https://github.com/rojo-rbx/rbx-dom
"""

import sys
import os
import json
import struct
import io
import re
import math
import hashlib
import urllib.parse
import urllib.request
import time
import gzip
import sqlite3
import html
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed

_SERVER_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "server"))
if os.path.isdir(_SERVER_DIR) and _SERVER_DIR not in sys.path:
    sys.path.insert(0, _SERVER_DIR)
try:
    from asset_downloader import download_asset as _download_asset_via_shared_downloader
except Exception:
    _download_asset_via_shared_downloader = None

try:
    import lz4.block as lz4
except ImportError:
    lz4 = None

try:
    import zstandard as zstd
except ImportError:
    zstd = None  # ZSTD chunks will raise if encountered.
try:
    from compression import zstd as stdlib_zstd  # Python 3.14+
except ImportError:
    stdlib_zstd = None


COMPACT_STRING_PROPERTIES = {
    "PhysicalConfigData",
    "SmoothGrid",
    "MeshData",
    "MeshData2",
    "PhysicsGrid",
    "MaterialColors",
    "MaterialTable",
    "Tags",
    "AttributesSerialize",
    "AttributesReplicate",
}
MAX_INLINE_PROPERTY_STRING = 262144
GUI_ASSET_FETCH_LIMIT = 4096
ROBLOX_THUMBNAIL_BATCH_SIZE = 80
# A failed private/deleted asset used to be requested again on every import.
# Large places can contain hundreds of those references, turning every retry
# into minutes of identical HTTP timeouts. Authenticated imports bypass this
# negative cache so adding ROBLOX_COOKIE immediately retries private assets.
ASSET_RETRY_SECONDS = max(0, int(os.environ.get("RBXL_ASSET_RETRY_SECONDS", "1800")))
MESH_ASSET_FETCH_LIMIT = 512
TEXTURE_DIRECT_FETCH_LIMIT = 2048
ASSET_FETCH_WORKERS = max(4, min(24, int(os.environ.get("RBXL_ASSET_WORKERS", "12"))))
CONTROL_CHAR_PATTERN = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

# The thumbnail endpoint may report a removed asset as Completed while serving
# one of Roblox's generic file cards. Treating those cards as textures makes
# every removed decal look identical and hides the actual import failure.
ROBLOX_THUMBNAIL_PLACEHOLDER_SHA256 = {
    "1d0ed1f4f266f2bda38152763c28751d7df0eeac0faa28b5b77717363aded22d",
    "f4b869a9890fab346beb4d54e63360f2d848e1e42b35345c51675feb71da23d7",
    "79009604f993c216ebc192d598f69d66193edec2574f8718e873157af1e03c06",
}


# ── Low-level readers ────────────────────────────────────────────────────────

def read_u8(f):  return struct.unpack('B', f.read(1))[0]
def read_u16(f): return struct.unpack('<H', f.read(2))[0]
def read_u32(f): return struct.unpack('<I', f.read(4))[0]
def read_i32(f): return struct.unpack('<i', f.read(4))[0]
def read_f32(f): return struct.unpack('<f', f.read(4))[0]
def read_f64(f): return struct.unpack('<d', f.read(8))[0]


def read_roblox_string(f):
    """Roblox 'string' = u32 length + raw bytes (NOT null-terminated)."""
    return read_roblox_bytes(f).decode('utf-8', errors='replace')


def read_roblox_bytes(f):
    """Roblox raw byte string."""
    length = read_u32(f)
    raw = f.read(length)
    if len(raw) != length:
        raise EOFError("truncated Roblox string: expected %d bytes, got %d" % (length, len(raw)))
    return raw


def shared_string_to_json_value(raw):
    """Preserve binary SharedString payloads instead of corrupting them as UTF-8."""
    if not raw:
        return ""
    try:
        text = raw.decode("utf-8")
        if all((ch in ("\t", "\n", "\r") or ord(ch) >= 32) for ch in text):
            return text
    except UnicodeDecodeError:
        pass
    return {
        "__bobux_binary_base64": base64.b64encode(raw).decode("ascii"),
        "encoding": "base64",
        "byte_length": len(raw),
    }


def parse_referent(value, fallback):
    """Roblox XML referents are commonly `RBX123`, but may be plain integers."""
    if value is None:
        return fallback
    text = str(value).strip()
    if not text:
        return fallback
    # Referents are opaque identifiers. Only the *entire* old numeric form may
    # be interpreted as an integer; a UUID's trailing digits are not its ID.
    match = re.fullmatch(r'(?:RBX)?(-?\d+)', text)
    if match:
        try:
            return int(match.group(1))
        except ValueError:
            return fallback
    return fallback


def read_interleaved(f, count, byte_size=4):
    """Read `count * byte_size` bytes and undo Roblox byte interleaving.

    Roblox stores arrays of big-endian integers with bytes grouped by position
    rather than by element: for N elements of B bytes each, the stream is
    [b0_e0, b0_e1, ... b0_e(N-1), b1_e0, ...]. This restores element order and
    returns the big-endian unsigned integer values.
    """
    raw = f.read(count * byte_size)
    if len(raw) < count * byte_size:
        raise EOFError("unexpected end of interleaved array")
    result = []
    for i in range(count):
        val = 0
        for b in range(byte_size):
            val = (val << 8) | raw[b * count + i]
        result.append(val)
    return result


def untransform_i32(n):
    """Undo Roblox zigzag encoding of a signed 32-bit integer."""
    return (n >> 1) ^ -(n & 1)


def decode_roblox_float(n):
    """Undo Roblox's float32 storage: sign bit moved from bit 31 to bit 0.

    The stored bits are the float's IEEE-754 pattern rotated right by one.
    """
    rotated = ((n >> 1) | ((n & 1) << 31)) & 0xFFFFFFFF
    return struct.unpack('>f', struct.pack('>I', rotated))[0]


def decompress_chunk(raw, compressed_len, uncompressed_len):
    """Decompress a chunk payload. compressed_len == 0 means uncompressed."""
    if compressed_len == 0:
        return raw
    if raw[:4] == b'\x28\xb5\x2f\xfd':
        if zstd is None:
            if stdlib_zstd is not None:
                result = stdlib_zstd.decompress(raw)
                if len(result) != uncompressed_len:
                    raise ValueError("ZSTD chunk size mismatch")
                return result
            raise RuntimeError("ZSTD chunk found but zstandard not installed")
        dctx = zstd.ZstdDecompressor()
        return dctx.decompress(raw, max_output_size=uncompressed_len)
    # Raw LZ4 block (no frame header).
    if lz4 is not None:
        return lz4.decompress(raw, uncompressed_size=uncompressed_len)
    return decompress_lz4_block(raw, uncompressed_len)


def decompress_lz4_block(raw, expected_size):
    """Small dependency-free LZ4 block decoder.

    Roblox binary chunks use raw LZ4 blocks, not framed LZ4. This supports the
    token/literal/match format needed by .rbxl files and keeps .rbxl import
    working even when the optional `lz4` pip package is not installed.
    """
    out = bytearray()
    i = 0
    length = len(raw)
    while i < length:
        token = raw[i]
        i += 1

        literal_len = token >> 4
        if literal_len == 15:
            while i < length:
                extra = raw[i]
                i += 1
                literal_len += extra
                if extra != 255:
                    break
        if i + literal_len > length:
            raise EOFError("truncated LZ4 literals")
        out.extend(raw[i:i + literal_len])
        i += literal_len
        if i >= length:
            break

        if i + 2 > length:
            raise EOFError("truncated LZ4 match offset")
        offset = raw[i] | (raw[i + 1] << 8)
        i += 2
        if offset <= 0 or offset > len(out):
            raise ValueError("invalid LZ4 match offset")

        match_len = (token & 0x0F) + 4
        if (token & 0x0F) == 15:
            while i < length:
                extra = raw[i]
                i += 1
                match_len += extra
                if extra != 255:
                    break
        for _ in range(match_len):
            out.append(out[-offset])

    if expected_size >= 0 and len(out) != expected_size:
        raise ValueError("LZ4 size mismatch: expected %d, got %d" % (expected_size, len(out)))
    return bytes(out)


# ── CFrame special orientations ──────────────────────────────────────────────
IDENTITY_CFRAME_ROTATION = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def _matmul3(a, b):
    return [[sum(a[row][i] * b[i][col] for i in range(3)) for col in range(3)] for row in range(3)]


def _rotation_matrix_yxz(x_degrees, y_degrees, z_degrees):
    """Roblox binary CFrame special rotations use X/Y/Z degrees applied Y -> X -> Z."""
    x = math.radians(x_degrees)
    y = math.radians(y_degrees)
    z = math.radians(z_degrees)
    rx = [[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]]
    ry = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    rz = [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]]
    matrix = _matmul3(_matmul3(ry, rx), rz)
    return [[0 if abs(value) < 1e-6 else round(value, 6) for value in row] for row in matrix]


# Full lookup table for Roblox binary CFrame's 24 axis-aligned orientation IDs,
# copied from rojo-rbx/rbx-dom's Matrix3::from_basic_rotation_id. ID 0x00 is
# not in the table: it means a full 9-float matrix follows inline.
CFRAME_SPECIAL = {
    0x02: [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
    0x03: [[1, 0, 0], [0, 0, -1], [0, 1, 0]],
    0x05: [[1, 0, 0], [0, -1, 0], [0, 0, -1]],
    0x06: [[1, 0, 0], [0, 0, 1], [0, -1, 0]],
    0x07: [[0, 1, 0], [1, 0, 0], [0, 0, -1]],
    0x09: [[0, 0, 1], [1, 0, 0], [0, 1, 0]],
    0x0A: [[0, -1, 0], [1, 0, 0], [0, 0, 1]],
    0x0C: [[0, 0, -1], [1, 0, 0], [0, -1, 0]],
    0x0D: [[0, 1, 0], [0, 0, 1], [1, 0, 0]],
    0x0E: [[0, 0, -1], [0, 1, 0], [1, 0, 0]],
    0x10: [[0, -1, 0], [0, 0, -1], [1, 0, 0]],
    0x11: [[0, 0, 1], [0, -1, 0], [1, 0, 0]],
    0x14: [[-1, 0, 0], [0, 1, 0], [0, 0, -1]],
    0x15: [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    0x17: [[-1, 0, 0], [0, -1, 0], [0, 0, 1]],
    0x18: [[-1, 0, 0], [0, 0, -1], [0, -1, 0]],
    0x19: [[0, 1, 0], [-1, 0, 0], [0, 0, 1]],
    0x1B: [[0, 0, -1], [-1, 0, 0], [0, 1, 0]],
    0x1C: [[0, -1, 0], [-1, 0, 0], [0, 0, -1]],
    0x1E: [[0, 0, 1], [-1, 0, 0], [0, -1, 0]],
    0x1F: [[0, 1, 0], [0, 0, -1], [-1, 0, 0]],
    0x20: [[0, 0, 1], [0, 1, 0], [-1, 0, 0]],
    0x22: [[0, -1, 0], [0, 0, 1], [-1, 0, 0]],
    0x23: [[0, 0, -1], [0, -1, 0], [-1, 0, 0]],
}


# ── Property (PROP chunk) value parsers ──────────────────────────────────────

def parse_prop_values(f, type_id, count, shared_strings):
    if type_id == 0x01:  # String
        # Roblox uses the String wire type for binary Terrain/CSG/property
        # payloads too. Replacement UTF-8 decoding irreversibly lost bytes.
        return [shared_string_to_json_value(read_roblox_bytes(f)) for _ in range(count)]

    if type_id == 0x02:  # Bool
        return [bool(read_u8(f)) for _ in range(count)]

    if type_id == 0x03:  # Int32 (zigzag + interleave)
        nums = read_interleaved(f, count, 4)
        return [untransform_i32(n) for n in nums]

    if type_id == 0x04:  # Float32 (roblox float + interleave)
        nums = read_interleaved(f, count, 4)
        return [decode_roblox_float(n) for n in nums]

    if type_id == 0x05:  # Float64 (plain little-endian)
        return [read_f64(f) for _ in range(count)]

    if type_id == 0x06:  # UDim (scale:float, offset:i32)
        scales = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        offsets = [untransform_i32(n) for n in read_interleaved(f, count, 4)]
        return [{"scale": s, "offset": o} for s, o in zip(scales, offsets)]

    if type_id == 0x07:  # UDim2
        sx = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        sy = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        ox = [untransform_i32(n) for n in read_interleaved(f, count, 4)]
        oy = [untransform_i32(n) for n in read_interleaved(f, count, 4)]
        return [{"x": {"scale": sx[i], "offset": ox[i]},
                 "y": {"scale": sy[i], "offset": oy[i]}} for i in range(count)]

    if type_id == 0x08:  # Ray (origin + direction, each 3 f32 LE)
        out = []
        for _ in range(count):
            ox, oy, oz = read_f32(f), read_f32(f), read_f32(f)
            dx, dy, dz = read_f32(f), read_f32(f), read_f32(f)
            out.append({"origin": [ox, oy, oz], "direction": [dx, dy, dz]})
        return out

    if type_id == 0x09:  # Faces (u8 bitfield)
        return [read_u8(f) for _ in range(count)]

    if type_id == 0x0A:  # Axes (u8 bitfield)
        return [read_u8(f) for _ in range(count)]

    if type_id == 0x0B:  # BrickColor (untransformed u32)
        return read_interleaved(f, count, 4)

    if type_id == 0x0C:  # Color3 (3 roblox float arrays: R, G, B)
        rs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        gs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        bs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        return [[rs[i], gs[i], bs[i]] for i in range(count)]

    if type_id == 0x0D:  # Vector2
        xs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        ys = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        return [[xs[i], ys[i]] for i in range(count)]

    if type_id == 0x0E:  # Vector3
        xs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        ys = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        zs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        return [[xs[i], ys[i], zs[i]] for i in range(count)]

    if type_id == 0x10:  # CFrame
        # Consume exactly this array so OptionalCFrame can read its bool trailer.
        rotations = []
        for _ in range(count):
            sid = read_u8(f)
            if sid == 0x00:
                m = [read_f32(f) for _ in range(9)]
                rotations.append([m[0:3], m[3:6], m[6:9]])
            else:
                if sid not in CFRAME_SPECIAL:
                    raise ValueError("invalid CFrame rotation ID 0x%02X" % sid)
                rotations.append(CFRAME_SPECIAL[sid])

        px = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        py = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        pz = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        return [{"position": [px[i], py[i], pz[i]], "rotation": rotations[i]}
                for i in range(count)]

    if type_id == 0x11:  # Quaternion (unused by Roblox but spec-defined)
        xs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        ys = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        zs = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        ws = [decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
        return [[xs[i], ys[i], zs[i], ws[i]] for i in range(count)]

    if type_id == 0x12:  # Enum (u32 interleaved, NO zigzag)
        return list(read_interleaved(f, count, 4))

    if type_id == 0x13:  # Referent (i32 zigzag + interleave, delta-encoded)
        nums = read_interleaved(f, count, 4)
        acc = 0
        out = []
        for n in nums:
            acc += untransform_i32(n)
            out.append(acc)
        return out

    if type_id == 0x14:  # Vector3int16 (3 × i16 LE)
        out = []
        for _ in range(count):
            x, y, z = struct.unpack('<hhh', f.read(6))
            out.append([x, y, z])
        return out

    if type_id == 0x15:  # NumberSequence
        out = []
        for _ in range(count):
            n = read_u32(f)
            kp = []
            for _ in range(n):
                t = read_f32(f)
                v = read_f32(f)
                env = read_f32(f)
                kp.append({"time": t, "value": v, "envelope": env})
            out.append(kp)
        return out

    if type_id == 0x16:  # ColorSequence
        out = []
        for _ in range(count):
            n = read_u32(f)
            kp = []
            for _ in range(n):
                t = read_f32(f)
                r = read_f32(f)
                g = read_f32(f)
                b = read_f32(f)
                env = read_f32(f)
                kp.append({"time": t, "color": [r, g, b], "envelope": env})
            out.append(kp)
        return out

    if type_id == 0x17:  # NumberRange (2 × f32 LE)
        out = []
        for _ in range(count):
            a = read_f32(f)
            b = read_f32(f)
            out.append([a, b])
        return out

    if type_id == 0x18:  # Rect (four interleaved Roblox float arrays)
        components = [[decode_roblox_float(n) for n in read_interleaved(f, count, 4)]
                      for _ in range(4)]
        return [{"min": [components[0][i], components[1][i]],
                 "max": [components[2][i], components[3][i]]} for i in range(count)]

    if type_id == 0x19:  # PhysicalProperties (bool + optional custom values)
        out = []
        for _ in range(count):
            custom = read_u8(f)
            if not (custom & 1):
                out.append({"custom": False})
                continue
            entry = {"custom": True}
            for key in ("density", "friction", "elasticity", "frictionWeight", "elasticityWeight"):
                entry[key] = read_f32(f)
            entry["acousticAbsorption"] = read_f32(f) if custom & 2 else 1.0
            out.append(entry)
        return out

    if type_id == 0x1A:
        rs = f.read(count)
        gs = f.read(count)
        bs = f.read(count)
        if len(rs) < count or len(gs) < count or len(bs) < count:
            raise EOFError("Color3uint8 property too short for %d value(s)" % count)
        return [[rs[i] / 255.0, gs[i] / 255.0, bs[i] / 255.0] for i in range(count)]

    if type_id == 0x1B:  # Int64 (zigzag i64 + 8-byte interleave)
        nums = read_interleaved(f, count, 8)
        return [int((n >> 1) ^ -(n & 1)) for n in nums]

    if type_id == 0x1C:  # SharedString (u32 index into SSTR table)
        indices = read_interleaved(f, count, 4)
        if shared_strings:
            return [shared_strings[i] if i < len(shared_strings) else ""
                    for i in indices]
        return list(indices)

    if type_id == 0x1D:  # Bytecode is preserved as data, never executed here.
        return [shared_string_to_json_value(read_roblox_bytes(f)) for _ in range(count)]

    if type_id == 0x1E:  # OptionalCFrame: type marker, CFrames, bool marker, bools
        if read_u8(f) != 0x10:
            raise ValueError("OptionalCFrame is missing its CFrame type marker")
        cframes = parse_prop_values(f, 0x10, count, shared_strings)
        if read_u8(f) != 0x02:
            raise ValueError("OptionalCFrame is missing its Bool type marker")
        return [{"present": bool(read_u8(f)), "cframe": cframes[i]} for i in range(count)]

    if type_id == 0x1F:  # UniqueId: entire 16-byte records are interleaved.
        out = []
        for value in read_interleaved(f, count, 16):
            index, epoch, random = struct.unpack('>IIQ', value.to_bytes(16, 'big'))
            random = (random >> 1) | ((random & 1) << 63)
            if random >= (1 << 63):
                random -= 1 << 64
            out.append({"epoch": epoch, "index": index, "random": random})
        return out

    if type_id == 0x20:  # Font: sequential records, NOT component arrays.
        return [{"family": read_roblox_string(f), "weight": read_u16(f),
                 "style": read_u8(f), "cachedFaceId": read_roblox_string(f)}
                for _ in range(count)]

    if type_id == 0x21:  # SecurityCapabilities: transformed interleaved i64.
        return [untransform_i32(n) & 0xFFFFFFFFFFFFFFFF for n in read_interleaved(f, count, 8)]

    if type_id == 0x22:  # Content (ContentId continues to use String).
        sources = [untransform_i32(n) for n in read_interleaved(f, count, 4)]
        uris = [read_roblox_string(f) for _ in range(read_u32(f))]
        objects = parse_prop_values(f, 0x13, read_u32(f), shared_strings)
        parse_prop_values(f, 0x13, read_u32(f), shared_strings)  # external refs
        if sources.count(1) != len(uris) or sources.count(2) != len(objects):
            raise ValueError("Content source counts do not match their payloads")
        uri_iter, object_iter = iter(uris), iter(objects)
        out = []
        for source in sources:
            if source == 0:
                out.append("")
            elif source == 1:
                out.append(next(uri_iter))
            elif source == 2:
                out.append({"source": 2, "ref": next(object_iter)})
            else:
                raise ValueError("unknown Content source type %d" % source)
        return out

    raise ValueError("unknown property type 0x%02X" % type_id)


# ── Binary (.rbxl) parser ────────────────────────────────────────────────────

def parse_rbxl(filepath):
    with open(filepath, 'rb') as f:
        probe = f.read(256)
        magic = probe[:8]
        if magic == b'<roblox!':
            f.seek(8)
            return _parse_rbxl_binary(f)
        xml_probe = probe.lstrip(b'\xef\xbb\xbf\r\n\t ')
        if xml_probe.startswith(b'<?xml') or xml_probe.startswith(b'<roblox') or xml_probe.startswith(b'<!--'):
            f.seek(0)
            return parse_rbxlx(f.read().decode('utf-8', errors='replace'))
        raise ValueError("Unknown file format (magic=%r)" % magic)


def _parse_rbxl_binary(f):
    if f.read(6) != b'\x89\xff\x0d\x0a\x1a\x0a':
        raise ValueError("invalid Roblox binary signature")
    version = read_u16(f)
    class_count = read_i32(f)
    instance_count = read_i32(f)
    f.read(8)  # reserved

    classes = {}       # class_id → {class_name, is_service, referents}
    instances = {}     # referent → {class, properties}
    hierarchy = []
    shared_strings = []
    metadata = {}
    warnings = []
    saw_end = False

    while True:
        name_raw = f.read(4)
        if not name_raw:
            break
        if len(name_raw) < 4:
            raise EOFError("truncated Roblox chunk header")
        chunk_name = name_raw.rstrip(b'\x00').decode('ascii', errors='replace')
        compressed_len = read_u32(f)
        uncompressed_len = read_u32(f)
        f.read(4)  # reserved

        payload_len = compressed_len if compressed_len > 0 else uncompressed_len
        raw = f.read(payload_len)
        if len(raw) < payload_len:
            raise EOFError("truncated %s chunk" % chunk_name)

        if chunk_name == 'END':
            saw_end = True
            break

        try:
            data = decompress_chunk(raw, compressed_len, uncompressed_len)
        except Exception as e:
            # A partial scene must not replace a user's map with missing parts
            # or missing scripts while reporting a successful import.
            raise ValueError("decompress %s failed: %s" % (chunk_name, e)) from e

        buf = io.BytesIO(data)

        if chunk_name == 'META':
            count = read_u32(buf)
            for _ in range(count):
                k = read_roblox_string(buf)
                v = read_roblox_string(buf)
                metadata[k] = v

        elif chunk_name == 'SSTR':
            buf.read(4)  # version
            sstr_count = read_u32(buf)
            for _ in range(sstr_count):
                buf.read(16)  # MD5 hash
                shared_strings.append(shared_string_to_json_value(read_roblox_bytes(buf)))

        elif chunk_name == 'INST':
            class_id = read_u32(buf)
            class_name = read_roblox_string(buf)
            is_service = bool(read_u8(buf))
            inst_count = read_u32(buf)
            # Referents come first: interleaved u32 BE + zigzag + delta-decoded.
            refs_raw = read_interleaved(buf, inst_count, 4)
            acc = 0
            refs = []
            for r in refs_raw:
                acc += untransform_i32(r)
                refs.append(acc)
            # When the class is a service, Roblox appends one u8 per instance
            # marking the default service instance. We consume them but do not
            # use them for placement.
            if is_service and inst_count > 0:
                try:
                    for _ in range(inst_count):
                        read_u8(buf)
                except EOFError:
                    pass
            classes[class_id] = {
                'class_name': class_name,
                'is_service': is_service,
                'referents': refs,
            }
            for ref in refs:
                instances.setdefault(str(ref), {'class': class_name, 'properties': {}})

        elif chunk_name == 'PROP':
            class_id = read_u32(buf)
            prop_name = read_roblox_string(buf)
            type_id = read_u8(buf)
            if class_id not in classes:
                continue
            refs = classes[class_id]['referents']
            count = len(refs)
            try:
                values = parse_prop_values(buf, type_id, count, shared_strings)
                for i, ref in enumerate(refs):
                    ref_key = str(ref)
                    if ref_key in instances and i < len(values):
                        instances[ref_key]['properties'][prop_name] = values[i]
            except Exception as e:
                warnings.append("PROP %s type=0x%02X: %s" % (prop_name, type_id, e))

        elif chunk_name == 'PRNT':
            buf.read(1)  # version
            count = read_u32(buf)
            children_nums = [untransform_i32(n) for n in read_interleaved(buf, count, 4)]
            parents_nums = [untransform_i32(n) for n in read_interleaved(buf, count, 4)]
            c_acc = p_acc = 0
            for c, p in zip(children_nums, parents_nums):
                c_acc += c
                p_acc += p
                hierarchy.append({"child": c_acc, "parent": p_acc})

        else:
            warnings.append("unhandled chunk type: %s" % chunk_name)

    if not saw_end:
        raise EOFError("Roblox binary file is missing its END chunk")
    if len(instances) != instance_count or len(hierarchy) != instance_count:
        raise ValueError("incomplete Roblox instance hierarchy: expected %d, decoded %d instances / %d parents"
                         % (instance_count, len(instances), len(hierarchy)))
    return {
        "format": "binary",
        "version": version,
        "class_count_hint": class_count,
        "instance_count_hint": instance_count,
        "metadata": metadata,
        "classes": {str(k): v for k, v in classes.items()},
        "instances": instances,
        "hierarchy": hierarchy,
        "warnings": warnings,
    }


# ── XML (.rbxlx) parser ──────────────────────────────────────────────────────

def _sanitize_roblox_xml(xml_string, warnings):
    cleaned = "".join(
        ch for ch in xml_string
        if ch in ("\t", "\n", "\r") or ord(ch) >= 32
    )
    if cleaned != xml_string:
        warnings.append("XML control characters were stripped before parsing")
    # CDATA contains literal Lua source: escaping '&' here changes strings,
    # URLs and operators in otherwise valid scripts. Repair only XML text.
    sections = re.split(r'(<!\[CDATA\[.*?\]\]>|<!--.*?-->)', cleaned, flags=re.DOTALL)
    for i in range(0, len(sections), 2):
        sections[i] = re.sub(r'&(?!#\d+;|#x[0-9A-Fa-f]+;|amp;|lt;|gt;|apos;|quot;)',
                             '&amp;', sections[i])
    fixed = ''.join(sections)
    if fixed != cleaned:
        warnings.append("XML bare ampersands were escaped before parsing")
    return fixed


def parse_rbxlx(xml_string):
    import xml.etree.ElementTree as ET
    warnings = []
    xml_string = _sanitize_roblox_xml(xml_string, warnings)
    root = ET.fromstring(xml_string)
    instances = {}
    hierarchy = []
    # Build the complete referent table first: Ref properties can point
    # forward, and numeric, UUID and arbitrary string referents may coexist.
    items = list(root.iter('Item'))
    refs_by_item = {}
    refs_by_name = {}
    used_refs = set()
    reserved = {parse_referent(item.get('referent'), -1) for item in items}
    next_id = 0
    for item in items:
        raw_ref = (item.get('referent') or '').strip()
        if raw_ref and raw_ref in refs_by_name:
            raise ValueError("duplicate XML referent: %s" % raw_ref)
        ref = parse_referent(raw_ref, -1)
        if ref < 0 or ref in used_refs:
            while next_id in reserved or next_id in used_refs:
                next_id += 1
            ref = next_id
            next_id += 1
        used_refs.add(ref)
        refs_by_item[item] = ref
        if raw_ref:
            refs_by_name[raw_ref] = ref

    def text_of(child, default=''):
        return default if child is None or child.text is None else child.text.strip()

    def float_child(parent, child_name, default=0.0):
        return float_text(text_of(parent.find(child_name)), default)

    def int_text(value, default=0):
        try:
            return int(str(value or '').strip())
        except (TypeError, ValueError):
            return default

    def float_text(value, default=0.0):
        try:
            return float(str(value or '').strip())
        except (TypeError, ValueError):
            return default

    def resolve_ref(raw):
        return refs_by_name.get(raw.strip(), -1)

    def parse_content(prop):
        if prop is None:
            return ''
        for key in ('url', 'uri', 'Ref', 'null', 'binary', 'hash'):
            child = prop.find(key)
            if child is not None:
                if key == 'Ref':
                    return {"source": 2, "ref": resolve_ref(text_of(child))}
                return text_of(child) if key in ('url', 'uri') else ''
        return text_of(prop)

    def parse_cframe(prop):
        return {"position": [float_child(prop, k) for k in ('X', 'Y', 'Z')],
                "rotation": [[float_child(prop, 'R%d%d' % (r, c), 1.0 if r == c else 0.0)
                              for c in range(3)] for r in range(3)]}

    shared_strings = {}
    for entry in root.findall('./SharedStrings/SharedString'):
        shared_strings[entry.get('md5', '')] = shared_string_to_json_value(
            base64.b64decode(text_of(entry)))

    unknown_tags = set()
    def parse_property(prop):
        tag = prop.tag
        text = text_of(prop)
        if tag in ('string', 'ProtectedString'):
            return prop.text or ''  # whitespace is meaningful in strings/source
        if tag == 'bool':
            return text.lower() == 'true'
        if tag in ('int', 'int64', 'uint64', 'token', 'Enum', 'SecurityCapabilities'):
            return int_text(text)
        if tag in ('float', 'double'):
            return float_text(text)
        if tag == 'CoordinateFrame':
            return parse_cframe(prop)
        if tag == 'OptionalCoordinateFrame':
            cf = prop.find('CFrame')
            return {"present": cf is not None,
                    "cframe": parse_cframe(cf) if cf is not None else
                    {"position": [0, 0, 0], "rotation": IDENTITY_CFRAME_ROTATION}}
        if tag in ('Vector3', 'Vector3int16', 'Vector2'):
            keys = ('X', 'Y') if tag == 'Vector2' else ('X', 'Y', 'Z')
            return [float_child(prop, k) for k in keys]
        if tag == 'Color3':
            if len(prop) == 0:  # Legacy packed RGB form.
                packed = int_text(text)
                return [((packed >> shift) & 255) / 255.0 for shift in (16, 8, 0)]
            return [float_child(prop, k) for k in ('R', 'G', 'B')]
        if tag == 'Color3uint8':
            if prop.get('R') is not None:
                return [int_text(prop.get(k)) / 255.0 for k in ('R', 'G', 'B')]
            if len(prop):
                return [int_text(text_of(prop.find(k))) / 255.0 for k in ('R', 'G', 'B')]
            packed = int_text(text)
            return [((packed >> shift) & 255) / 255.0 for shift in (16, 8, 0)]
        if tag in ('Content', 'ContentId'):
            return parse_content(prop)
        if tag == 'Ref':
            return resolve_ref(text)
        if tag == 'UDim':
            return {"scale": float_child(prop, 'S'), "offset": int_text(text_of(prop.find('O')))}
        if tag == 'UDim2':
            return {axis.lower(): {"scale": float_child(prop, axis + 'S'),
                                   "offset": int_text(text_of(prop.find(axis + 'O')))}
                    for axis in ('X', 'Y')}
        if tag in ('NumberRange', 'NumberSequence', 'ColorSequence'):
            values = [float_text(v) for v in text.split()]
            if tag == 'NumberRange':
                return values[:2]
            stride = 3 if tag == 'NumberSequence' else 5
            if len(values) % stride:
                raise ValueError("invalid XML %s keypoints" % tag)
            return [{"time": values[i], "value": values[i + 1], "envelope": values[i + 2]}
                    if stride == 3 else {"time": values[i], "color": values[i + 1:i + 4],
                                         "envelope": values[i + 4]}
                    for i in range(0, len(values), stride)]
        if tag in ('Rect', 'Rect2D'):
            return {key: [float_child(prop.find(key), axis) for axis in ('X', 'Y')]
                    for key in ('min', 'max')}
        if tag == 'PhysicalProperties':
            custom = text_of(prop.find('CustomPhysics')).lower() == 'true'
            entry = {"custom": custom}
            if custom:
                for key in ('Density', 'Friction', 'Elasticity', 'FrictionWeight', 'ElasticityWeight', 'AcousticAbsorption'):
                    entry[key[0].lower() + key[1:]] = float_child(prop, key, 1.0 if key == 'AcousticAbsorption' else 0.0)
            return entry
        if tag == 'Font':
            return {"family": parse_content(prop.find('Family')),
                    "weight": int_text(text_of(prop.find('Weight')), 400),
                    "style": 1 if text_of(prop.find('Style')) == 'Italic' else 0,
                    "cachedFaceId": parse_content(prop.find('CachedFaceId'))}
        if tag in ('Faces', 'Axes'):
            return int_text(text_of(prop.find(tag.lower())))
        if tag in ('SharedString', 'NetAssetRef'):
            if text not in shared_strings:
                warnings.append("Missing XML SharedString: %s" % text)
            return shared_strings.get(text, '')
        if tag == 'BinaryString':
            return shared_string_to_json_value(base64.b64decode(text)) if text else ''
        if tag == 'UniqueId':
            return text
        # Preserve new types as structured data rather than silently deleting.
        unknown_tags.add(tag)
        return {"__bobux_xml_type": tag, "xml": ET.tostring(prop, encoding='unicode')}

    # Iterative traversal permits deep nested models without Python recursion limits.
    pending = [(item, -1) for item in reversed(root.findall('Item'))]
    while pending:
        item, parent_ref = pending.pop()
        ref = refs_by_item[item]
        props = {}
        props_node = item.find('Properties')
        if props_node is not None:
            for prop in props_node:
                props[prop.get('name', '')] = parse_property(prop)
        instances[str(ref)] = {'class': item.get('class', 'Unknown'), 'properties': props}
        hierarchy.append({'child': ref, 'parent': parent_ref})
        pending.extend((child, ref) for child in reversed(item.findall('Item')))
    if unknown_tags:
        warnings.append("XML property types preserved without runtime conversion: %s" % ', '.join(sorted(unknown_tags)))

    return {
        "format": "xml",
        "version": 0,
        "class_count_hint": 0,
        "instance_count_hint": len(instances),
        "metadata": {},
        "classes": {},
        "instances": instances,
        "hierarchy": hierarchy,
        "warnings": warnings,
    }


# ── Entry point ──────────────────────────────────────────────────────────────

def sanitize_for_strict_json(value, warnings, path="$", stats=None):
    """Return a JSON-safe copy for Godot's JSON parser.

    Roblox BinaryString-style properties can contain NUL/control bytes. Python
    can write them as valid JSON escapes, but Godot prints a warning for every
    decoded NUL. Keep ordinary text intact and strip only control bytes that
    should never be meaningful in Bobux's intermediate format.
    """
    if stats is None:
        stats = {"non_finite": 0, "control_strings": 0, "compacted_strings": 0}
    if isinstance(value, float):
        if not math.isfinite(value):
            stats["non_finite"] += 1
            if stats["non_finite"] <= 20:
                warnings.append("non-finite float at %s was replaced with 0.0" % path)
            return 0.0
        return value
    if isinstance(value, str):
        prop_name = path.rsplit(".", 1)[-1]
        if prop_name == "__bobux_binary_base64":
            return value
        should_compact = prop_name in COMPACT_STRING_PROPERTIES or (
            len(value) > MAX_INLINE_PROPERTY_STRING and prop_name not in ("Source", "lua_source")
        )
        if should_compact:
            stats["compacted_strings"] += 1
            digest = hashlib.sha1(value.encode("utf-8", errors="replace")).hexdigest()[:16]
            return "__bobux_blob__:%s:%d:%s" % (prop_name, len(value), digest)
        if CONTROL_CHAR_PATTERN.search(value) is None:
            return value
        stats["control_strings"] += 1
        return CONTROL_CHAR_PATTERN.sub("", value)
    if isinstance(value, dict):
        cleaned = {}
        for key, child in value.items():
            safe_key = str(key)
            cleaned[safe_key] = sanitize_for_strict_json(child, warnings, safe_key, stats)
        return cleaned
    if isinstance(value, (list, tuple)):
        return [
            sanitize_for_strict_json(child, warnings, path, stats)
            for child in value
        ]
    return value


def _content_to_string(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        for key in ("value", "url", "path", "asset_id", "id"):
            candidate = str(value.get(key, "")).strip()
            if candidate:
                return candidate
    if isinstance(value, (list, tuple)) and value:
        return _content_to_string(value[0])
    return str(value).strip()


def _extract_asset_id(value):
    text = _content_to_string(value)
    if not text:
        return ""
    match = re.search(r"(\d{4,})", text)
    return match.group(1) if match else ""


TEXTURE_ASSET_PROPERTIES_BY_CLASS = {
    "ImageLabel": ("Image", "HoverImage", "PressedImage"),
    "ImageButton": ("Image", "HoverImage", "PressedImage"),
    "Decal": ("Texture", "NormalMap", "MetalnessMap", "RoughnessMap", "TexturePack"),
    "Texture": ("Texture", "NormalMap", "MetalnessMap", "RoughnessMap", "TexturePack"),
    "Sky": ("SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "MoonTextureId", "SunTextureId"),
    "SpecialMesh": ("TextureId", "TextureID"),
    "MeshPart": ("TextureID", "TextureId"),
    "FileMesh": ("TextureId", "TextureID"),
    "ParticleEmitter": ("Texture",),
    "Trail": ("Texture",),
    "Beam": ("Texture",),
    "Tool": ("TextureId",),
}

EXACT_TEXTURE_CLASSES = {
    "Decal",
    "Texture",
    "Sky",
    "SpecialMesh",
    "MeshPart",
    "FileMesh",
    "ParticleEmitter",
    "Trail",
    "Beam",
    "Tool",
}

MESH_ASSET_PROPERTIES_BY_CLASS = {
	"SpecialMesh": ("MeshId", "MeshID"),
	"MeshPart": ("MeshId", "MeshID"),
	"FileMesh": ("MeshId", "MeshID"),
	"UnionOperation": ("MeshId", "MeshID", "AssetId", "SourceAssetId"),
	"NegateOperation": ("MeshId", "MeshID", "AssetId", "SourceAssetId"),
	"IntersectOperation": ("MeshId", "MeshID", "AssetId", "SourceAssetId"),
}


def _collect_gui_image_asset_ids(result, limit=GUI_ASSET_FETCH_LIMIT):
    return _collect_texture_asset_ids(result, limit)


def _collect_texture_asset_ids(result, limit=GUI_ASSET_FETCH_LIMIT):
    ids = []
    seen = set()
    for inst in result.get("instances", {}).values():
        if not isinstance(inst, dict):
            continue
        prop_names = TEXTURE_ASSET_PROPERTIES_BY_CLASS.get(inst.get("class"))
        if not prop_names:
            continue
        props = inst.get("properties", {})
        if not isinstance(props, dict):
            continue
        for prop_name in prop_names:
            asset_id = _extract_asset_id(props.get(prop_name, ""))
            if not asset_id or asset_id in seen:
                continue
            seen.add(asset_id)
            ids.append(asset_id)
            if len(ids) >= limit:
                return ids
    return ids


def _collect_exact_texture_asset_ids(result, limit=TEXTURE_DIRECT_FETCH_LIMIT):
    ids = []
    seen = set()
    for inst in result.get("instances", {}).values():
        if not isinstance(inst, dict):
            continue
        props = inst.get("properties", {})
        if not isinstance(props, dict):
            continue
        class_name = inst.get("class")
        prop_names = set(TEXTURE_ASSET_PROPERTIES_BY_CLASS.get(class_name, ()))
        if class_name in EXACT_TEXTURE_CLASSES:
            for prop_name in props.keys():
                lower_name = str(prop_name).lower()
                if "texture" in lower_name or "image" in lower_name or "skybox" in lower_name or lower_name.endswith("map"):
                    prop_names.add(prop_name)
        for prop_name in prop_names:
            asset_id = _extract_asset_id(props.get(prop_name, ""))
            if not asset_id or asset_id in seen:
                continue
            seen.add(asset_id)
            ids.append(asset_id)
            if len(ids) >= limit:
                return ids
    return ids


def _collect_mesh_asset_ids(result, limit=MESH_ASSET_FETCH_LIMIT):
    ids = []
    seen = set()
    for inst in result.get("instances", {}).values():
        if not isinstance(inst, dict):
            continue
        props = inst.get("properties", {})
        if not isinstance(props, dict):
            continue
        prop_names = set(MESH_ASSET_PROPERTIES_BY_CLASS.get(inst.get("class"), ()))
        for prop_name in props.keys():
            lower_name = str(prop_name).lower()
            if lower_name in ("meshid", "mesh_id", "filemesh") or lower_name.endswith("meshid"):
                prop_names.add(prop_name)
        for prop_name in prop_names:
            asset_id = _extract_asset_id(props.get(prop_name, ""))
            if not asset_id or asset_id in seen:
                continue
            seen.add(asset_id)
            ids.append(asset_id)
            if len(ids) >= limit:
                return ids
    return ids


def _collect_asset_id_set(result, collector):
    try:
        return set(str(asset_id) for asset_id in collector(result, 1000000))
    except TypeError:
        return set(str(asset_id) for asset_id in collector(result))


def _purge_texture_only_mesh_cache(result, cache_dir):
    if not cache_dir or not os.path.isdir(cache_dir):
        return 0
    texture_ids = _collect_asset_id_set(result, _collect_exact_texture_asset_ids)
    mesh_ids = _collect_asset_id_set(result, _collect_mesh_asset_ids)
    purged = 0
    for asset_id in sorted(texture_ids - mesh_ids):
        for ext in ("mesh", "mesh.json", "meshdata", "obj"):
            path = os.path.join(cache_dir, "%s.%s" % (asset_id, ext))
            if not os.path.isfile(path):
                continue
            try:
                os.remove(path)
                purged += 1
            except OSError:
                pass
    return purged


def _cached_image_exists(cache_dir, asset_id):
    for ext in ("png", "jpg", "jpeg", "webp"):
        if os.path.isfile(os.path.join(cache_dir, "%s.%s" % (asset_id, ext))):
            return True
    return False


def _cached_thumbnail_path(cache_dir, asset_id):
    for ext in ("png", "jpg", "jpeg", "webp"):
        path = os.path.join(cache_dir, "%s.%s" % (asset_id, ext))
        if _cached_image_file_is_valid(path):
            return path
    return ""


def _thumbnail_valid_marker_path(cache_dir, asset_id):
    return os.path.join(cache_dir, "%s.thumbnail.ok" % asset_id)


def _mark_thumbnail_valid(cache_dir, asset_id):
    try:
        with open(_thumbnail_valid_marker_path(cache_dir, asset_id), "w", encoding="utf-8") as marker:
            marker.write("validated\n")
    except OSError:
        pass


def _remove_cached_thumbnail(cache_dir, asset_id):
    removed = False
    for ext in ("png", "jpg", "jpeg", "webp"):
        path = os.path.join(cache_dir, "%s.%s" % (asset_id, ext))
        if not os.path.isfile(path):
            continue
        try:
            os.remove(path)
            removed = True
        except OSError:
            pass
    try:
        os.remove(_thumbnail_valid_marker_path(cache_dir, asset_id))
    except OSError:
        pass
    return removed


def _is_roblox_thumbnail_placeholder(payload):
    if not payload:
        return True
    return hashlib.sha256(payload).hexdigest().lower() in ROBLOX_THUMBNAIL_PLACEHOLDER_SHA256


def _cached_exact_image_exists(cache_dir, asset_id):
    for ext in ("asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp"):
        if _cached_image_file_is_valid(os.path.join(cache_dir, "%s.%s" % (asset_id, ext))):
            return True
    return False


def _cached_image_file_is_valid(path):
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as f:
            head = f.read(16)
    except OSError:
        return False
    return (
        head.startswith(b"\x89PNG\r\n\x1a\n")
        or head.startswith(b"\xff\xd8\xff")
        or (head.startswith(b"RIFF") and len(head) >= 12 and head[8:12] == b"WEBP")
    )


def _cached_mesh_exists(cache_dir, asset_id):
    for ext in ("mesh.json", "mesh", "meshdata", "obj"):
        if os.path.isfile(os.path.join(cache_dir, "%s.%s" % (asset_id, ext))):
            return True
    return False


def _cached_mesh_json_exists(cache_dir, asset_id):
    return os.path.isfile(os.path.join(cache_dir, "%s.mesh.json" % asset_id))


def _asset_missing_marker_path(cache_dir, asset_id):
    return os.path.join(cache_dir, "%s.missing" % asset_id)


def _asset_recently_failed(cache_dir, asset_id):
    if ASSET_RETRY_SECONDS <= 0 or _roblox_cookie_header():
        return False
    marker = _asset_missing_marker_path(cache_dir, asset_id)
    if not os.path.isfile(marker):
        return False
    try:
        return time.time() - os.path.getmtime(marker) < ASSET_RETRY_SECONDS
    except OSError:
        return False


def _mark_asset_failed(cache_dir, asset_id):
    try:
        with open(_asset_missing_marker_path(cache_dir, asset_id), "w", encoding="utf-8") as f:
            f.write("missing\n")
    except OSError:
        pass


def _download_url_bytes(url, timeout=8):
    req = urllib.request.Request(url, headers={
        "User-Agent": "BobuxRBXLImporter/1.0",
        "Accept": "image/png,image/jpeg,image/webp,application/json,*/*",
    })
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def _roblox_cookie_header():
    cookie = os.environ.get("ROBLOX_COOKIE", "").strip()
    if not cookie:
        return ""
    if cookie.startswith(".ROBLOSECURITY="):
        return cookie
    return ".ROBLOSECURITY=%s" % cookie


def _request_roblox_asset(asset_id, timeout=5, use_storage=True):
    if _download_asset_via_shared_downloader is not None:
        try:
            payload = _download_asset_via_shared_downloader(
                int(asset_id),
                request_timeout=timeout,
                cdn_timeout=timeout,
                use_storage=use_storage,
            )
            if payload:
                return _normalize_downloaded_asset_bytes(payload)
        except TypeError:
            try:
                payload = _download_asset_via_shared_downloader(int(asset_id))
                if payload:
                    return _normalize_downloaded_asset_bytes(payload)
            except Exception:
                pass
        except Exception:
            pass
    headers = {
        "User-Agent": "Roblox/WinInet",
        "Accept": "application/octet-stream,image/png,image/jpeg,image/webp,application/json,*/*",
    }
    cookie = _roblox_cookie_header()
    if cookie:
        headers["Cookie"] = cookie
    urls = [
        "https://assetdelivery.roblox.com/v1/asset/?id=%s" % asset_id,
        "https://assetdelivery.roblox.com/v2/asset/?id=%s" % asset_id,
    ]
    for url in urls:
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as response:
                data = response.read()
                content_type = (response.headers.get("Content-Type") or "").lower()
        except Exception:
            continue
        data = _normalize_downloaded_asset_bytes(data)
        stripped = data[:96].lstrip()
        if not data:
            continue
        if stripped.startswith(b"{"):
            nested = _download_asset_location_from_json(data, headers, timeout)
            if nested:
                return _normalize_downloaded_asset_bytes(nested)
            continue
        if stripped.startswith(b"<html") or stripped.startswith(b"<!DOCTYPE"):
            continue
        if "application/json" in content_type:
            nested = _download_asset_location_from_json(data, headers, timeout)
            if nested:
                return _normalize_downloaded_asset_bytes(nested)
            continue
        return data
    return b""


def _download_asset_location_from_json(payload, headers, timeout):
    try:
        data = json.loads(payload.decode("utf-8", errors="replace"))
    except Exception:
        return b""
    locations = []
    if isinstance(data, dict):
        if isinstance(data.get("locations"), list):
            locations = data.get("locations", [])
        elif isinstance(data.get("data"), dict) and isinstance(data["data"].get("locations"), list):
            locations = data["data"].get("locations", [])
    for item in locations:
        if not isinstance(item, dict):
            continue
        location = str(item.get("location", "")).strip()
        if not location:
            continue
        try:
            req = urllib.request.Request(location, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return response.read()
        except Exception:
            continue
    return b""


def _normalize_downloaded_asset_bytes(data):
    if not data:
        return b""
    if data[:2] == b"\x1f\x8b":
        try:
            return gzip.decompress(data)
        except Exception:
            return data
    return data


def _image_extension_for_payload(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "asset.png"
    if data.startswith(b"\xff\xd8\xff"):
        return "asset.jpg"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "asset.webp"
    return ""


def _mesh_payload_offset(data):
    candidates = []
    for marker in (b"version 1.00", b"version 1.01", b"version 2.00\n", b"version 3.00\n",
                   b"version 3.01\n", b"version 4.00\n", b"version 4.01\n", b"version 5.00\n"):
        idx = data.find(marker)
        if idx >= 0:
            candidates.append(idx)
    return min(candidates) if candidates else -1


def _extract_payload_body(data, wanted):
    data = _normalize_downloaded_asset_bytes(data)
    if wanted == "mesh":
        idx = _mesh_payload_offset(data)
        return data[idx:] if idx >= 0 else b""
    if wanted == "image":
        offsets = []
        png_idx = data.find(b"\x89PNG\r\n\x1a\n")
        if png_idx >= 0:
            offsets.append(png_idx)
        jpg_idx = data.find(b"\xff\xd8\xff")
        if jpg_idx >= 0:
            offsets.append(jpg_idx)
        riff_idx = data.find(b"RIFF")
        if riff_idx >= 0 and riff_idx + 12 <= len(data) and data[riff_idx + 8:riff_idx + 12] == b"WEBP":
            offsets.append(riff_idx)
        if not offsets:
            return b""
        return data[min(offsets):]
    return data


def _extract_nested_asset_ids_from_payload(data):
	data = _normalize_downloaded_asset_bytes(data)
	if not data:
		return []
	try:
		text = html.unescape(data[:262144].decode("utf-8", errors="ignore"))
	except Exception:
		return []
	ids = []
	for pattern in (
		r"rbxassetid://(\d+)",
		r"assetdelivery\.roblox\.com/[^\s\"'<>]*[?&]id=(\d+)",
		r"roblox\.com/asset/[^\s\"'<>]*[?&]id=(\d+)",
		r"roblox\.com/library/(\d+)",
		r"[?&]id=(\d{3,})",
	):
		for match in re.finditer(pattern, text, flags=re.IGNORECASE):
			asset_id = match.group(1)
			if asset_id not in ids:
				ids.append(asset_id)
	return ids


def _payload_matches_asset_kind(data, wanted):
	if wanted == "mesh":
		return bool(_extract_payload_body(data, "mesh"))
	if wanted == "image":
		return bool(_extract_payload_body(data, "image"))
	return bool(data)


def _resolve_roblox_asset_payload(asset_id, wanted, timeout=6, use_storage=True, depth=0, seen=None):
	if seen is None:
		seen = set()
	asset_key = str(asset_id).strip()
	if not asset_key or asset_key in seen or depth > 4:
		return b""
	seen.add(asset_key)
	payload = _request_roblox_asset(asset_key, timeout=timeout, use_storage=use_storage)
	if not payload:
		return b""
	payload = _normalize_downloaded_asset_bytes(payload)
	if _payload_matches_asset_kind(payload, wanted):
		return _extract_payload_body(payload, wanted)
	for nested_id in _extract_nested_asset_ids_from_payload(payload):
		resolved = _resolve_roblox_asset_payload(
			nested_id,
			wanted,
			timeout=timeout,
			use_storage=use_storage,
			depth=depth + 1,
			seen=seen,
		)
		if resolved:
			return resolved
	return b""


def resolve_roblox_asset_payload(asset_id, wanted, timeout=6, use_storage=True):
	return _resolve_roblox_asset_payload(asset_id, wanted, timeout=timeout, use_storage=use_storage)


def _read_f32_le(buf, offset):
    return struct.unpack_from("<f", buf, offset)[0], offset + 4


def _read_u8_buf(buf, offset):
    return buf[offset], offset + 1


def _read_u16_le(buf, offset):
    return struct.unpack_from("<H", buf, offset)[0], offset + 2


def _read_u32_le(buf, offset):
    return struct.unpack_from("<I", buf, offset)[0], offset + 4


def _parse_mesh_vertex2(buf, offset, full_vertex=True):
    pos = struct.unpack_from("<3f", buf, offset); offset += 12
    norm = struct.unpack_from("<3f", buf, offset); offset += 12
    uv = struct.unpack_from("<2f", buf, offset); offset += 8
    tangent = struct.unpack_from("<4b", buf, offset); offset += 4
    color = (255, 255, 255, 255)
    if full_vertex:
        color = struct.unpack_from("<4B", buf, offset); offset += 4
    return {
        "pos": [float(pos[0]), float(pos[1]), float(pos[2])],
        "norm": [float(norm[0]), float(norm[1]), float(norm[2])],
        "uv": [float(uv[0]), float(uv[1])],
        "color": [int(color[0]), int(color[1]), int(color[2]), int(color[3])],
        "tangent": [int(tangent[0]), int(tangent[1]), int(tangent[2]), int(tangent[3])],
    }, offset


def _parse_roblox_mesh_payload(data):
    data = _extract_payload_body(data, "mesh")
    if not data:
        raise ValueError("payload does not contain a Roblox mesh header")
    header_end = data.find(b"\n")
    if header_end < 0:
        raise ValueError("mesh version line is missing")
    revision = data[:header_end + 1].decode("ascii", errors="replace").strip()
    if revision in ("version 1.00", "version 1.01"):
        return _parse_roblox_mesh_v1(data, revision)
    offset = header_end + 1
    vertices = []
    faces = []
    if revision == "version 2.00":
        header_size, offset = _read_u16_le(data, offset)
        sizeof_vertex, offset = _read_u8_buf(data, offset)
        sizeof_face, offset = _read_u8_buf(data, offset)
        vertex_count, offset = _read_u32_le(data, offset)
        face_count, offset = _read_u32_le(data, offset)
        if header_size != 12 or sizeof_face != 12 or sizeof_vertex not in (36, 40):
            raise ValueError("unsupported mesh v2 header")
        vertices, offset = _parse_mesh_vertices2(data, offset, vertex_count, sizeof_vertex == 40)
        faces, offset = _parse_mesh_faces(data, offset, face_count, vertex_count)
    elif revision in ("version 3.00", "version 3.01"):
        header_size, offset = _read_u16_le(data, offset)
        sizeof_vertex, offset = _read_u8_buf(data, offset)
        sizeof_face, offset = _read_u8_buf(data, offset)
        sizeof_lod, offset = _read_u16_le(data, offset)
        lod_count, offset = _read_u16_le(data, offset)
        vertex_count, offset = _read_u32_le(data, offset)
        face_count, offset = _read_u32_le(data, offset)
        if header_size != 16 or sizeof_face != 12 or sizeof_lod != 4 or sizeof_vertex not in (36, 40):
            raise ValueError("unsupported mesh v3 header")
        vertices, offset = _parse_mesh_vertices2(data, offset, vertex_count, sizeof_vertex == 40)
        faces, offset = _parse_mesh_faces(data, offset, face_count, vertex_count)
        offset += lod_count * 4
    elif revision in ("version 4.00", "version 4.01"):
        header_size, offset = _read_u16_le(data, offset)
        lod_type, offset = _read_u16_le(data, offset)
        vertex_count, offset = _read_u32_le(data, offset)
        face_count, offset = _read_u32_le(data, offset)
        lod_count, offset = _read_u16_le(data, offset)
        bone_count, offset = _read_u16_le(data, offset)
        bone_names_len, offset = _read_u32_le(data, offset)
        subset_count, offset = _read_u16_le(data, offset)
        lod_hq_count, offset = _read_u8_buf(data, offset)
        padding, offset = _read_u8_buf(data, offset)
        if header_size != 24:
            raise ValueError("unsupported mesh v4 header")
        vertices, offset = _parse_mesh_vertices2(data, offset, vertex_count, True)
        if bone_count > 0:
            offset += vertex_count * 8
        faces, offset = _parse_mesh_faces(data, offset, face_count, vertex_count)
        offset += lod_count * 4
        offset += bone_count * 60
        offset += bone_names_len
        offset += subset_count * 72
    elif revision == "version 5.00":
        header_size, offset = _read_u16_le(data, offset)
        lod_type, offset = _read_u16_le(data, offset)
        vertex_count, offset = _read_u32_le(data, offset)
        face_count, offset = _read_u32_le(data, offset)
        lod_count, offset = _read_u16_le(data, offset)
        bone_count, offset = _read_u16_le(data, offset)
        bone_names_len, offset = _read_u32_le(data, offset)
        subset_count, offset = _read_u16_le(data, offset)
        lod_hq_count, offset = _read_u8_buf(data, offset)
        padding, offset = _read_u8_buf(data, offset)
        facs_format, offset = _read_u32_le(data, offset)
        sizeof_facs, offset = _read_u32_le(data, offset)
        if header_size != 32:
            raise ValueError("unsupported mesh v5 header")
        vertices, offset = _parse_mesh_vertices2(data, offset, vertex_count, True)
        if bone_count > 0:
            offset += vertex_count * 8
        faces, offset = _parse_mesh_faces(data, offset, face_count, vertex_count)
        offset += lod_count * 4
        offset += bone_count * 60
        offset += bone_names_len
        offset += subset_count * 72
        offset += sizeof_facs
    else:
        raise ValueError("unsupported Roblox mesh revision %s" % revision)
    return _normalize_roblox_mesh_for_godot(revision, vertices, faces)


def _parse_mesh_vertices2(data, offset, vertex_count, full_vertex):
    vertices = []
    for _ in range(vertex_count):
        vertex, offset = _parse_mesh_vertex2(data, offset, full_vertex)
        vertices.append(vertex)
    return vertices, offset


def _parse_mesh_faces(data, offset, face_count, vertex_count):
    faces = []
    for _ in range(face_count):
        a, b, c = struct.unpack_from("<3I", data, offset)
        offset += 12
        if a < vertex_count and b < vertex_count and c < vertex_count:
            faces.append((int(a), int(b), int(c)))
    return faces, offset


def _parse_roblox_mesh_v1(data, revision):
    text = data.decode("utf-8", errors="replace").splitlines()
    if len(text) < 3:
        raise ValueError("mesh v1 is truncated")
    face_count = int(text[1].strip())
    pattern = re.compile(r"\[(.*?),(.*?),(.*?)\]\[(.*?),(.*?),(.*?)\]\[(.*?),(.*?),(.*?)\]")
    vertices = []
    for match in pattern.finditer(text[2]):
        nums = [float(part.strip()) for part in match.groups()]
        pos = nums[0:3]
        if revision == "version 1.00":
            pos = [axis * 0.5 for axis in pos]
        uv = [nums[6], 1.0 - nums[7]]
        vertices.append({"pos": pos, "norm": nums[3:6], "uv": uv, "color": [255, 255, 255, 255]})
    if len(vertices) != face_count * 3:
        raise ValueError("mesh v1 vertex count mismatch")
    faces = [(i, i + 1, i + 2) for i in range(0, len(vertices), 3)]
    return _normalize_roblox_mesh_for_godot(revision, vertices, faces)


def _normalize_roblox_mesh_for_godot(revision, vertices, faces):
    if not vertices or not faces:
        raise ValueError("mesh has no drawable triangles")
    godot_positions = []
    godot_normals = []
    uvs = []
    colors = []
    for vertex in vertices:
        p = vertex["pos"]
        n = vertex.get("norm", [0.0, 1.0, 0.0])
        godot_positions.append([float(p[0]), float(p[1]), -float(p[2])])
        length = math.sqrt(float(n[0]) * float(n[0]) + float(n[1]) * float(n[1]) + float(n[2]) * float(n[2]))
        if length <= 1e-6:
            godot_normals.append([0.0, 1.0, 0.0])
        else:
            godot_normals.append([float(n[0]) / length, float(n[1]) / length, -float(n[2]) / length])
        uv = vertex.get("uv", [0.0, 0.0])
        uvs.append([float(uv[0]), float(uv[1])])
        col = vertex.get("color", [255, 255, 255, 255])
        colors.append([int(col[0]), int(col[1]), int(col[2]), int(col[3])])

    mins = [min(p[i] for p in godot_positions) for i in range(3)]
    maxs = [max(p[i] for p in godot_positions) for i in range(3)]
    center = [(mins[i] + maxs[i]) * 0.5 for i in range(3)]
    size = [max(maxs[i] - mins[i], 1e-6) for i in range(3)]
    flat_vertices = []
    flat_normals = []
    flat_uvs = []
    flat_colors = []
    for i, p in enumerate(godot_positions):
        flat_vertices.extend([(p[0] - center[0]) / size[0], (p[1] - center[1]) / size[1], (p[2] - center[2]) / size[2]])
        n = godot_normals[i]
        flat_normals.extend(n)
        uv = uvs[i]
        flat_uvs.extend(uv)
        flat_colors.extend(colors[i])
    flat_indices = []
    for a, b, c in faces:
        flat_indices.extend([a, c, b])
    return {
        "revision": revision,
        "normalized_to_unit_bounds": True,
        "source_bounds_min": mins,
        "source_bounds_max": maxs,
        "source_bounds_size": size,
        "vertex_count": len(vertices),
        "triangle_count": len(flat_indices) // 3,
        "vertices": flat_vertices,
        "normals": flat_normals,
        "uvs": flat_uvs,
        "colors": flat_colors,
        "indices": flat_indices,
    }


def _write_mesh_cache_asset(cache_dir, asset_id, payload):
    payload = _extract_payload_body(payload, "mesh")
    if not payload:
        return False
    raw_path = os.path.join(cache_dir, "%s.mesh" % asset_id)
    json_path = os.path.join(cache_dir, "%s.mesh.json" % asset_id)
    try:
        mesh_json = _parse_roblox_mesh_payload(payload)
        mesh_json["asset_id"] = str(asset_id)
        with open(raw_path, "wb") as out:
            out.write(payload)
        with open(json_path, "w", encoding="utf-8") as out:
            json.dump(mesh_json, out, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        return True
    except Exception:
        return False


def _ensure_mesh_json_from_raw(cache_dir, asset_id):
    if _cached_mesh_json_exists(cache_dir, asset_id):
        return True
    for ext in ("mesh", "meshdata"):
        raw_path = os.path.join(cache_dir, "%s.%s" % (asset_id, ext))
        if not os.path.isfile(raw_path):
            continue
        try:
            with open(raw_path, "rb") as f:
                payload = f.read()
            if _write_mesh_cache_asset(cache_dir, asset_id, payload):
                return True
        except OSError:
            continue
    return False


def _write_image_cache_asset(cache_dir, asset_id, payload):
    payload = _extract_payload_body(payload, "image")
    ext = _image_extension_for_payload(payload)
    if not ext:
        return False
    try:
        with open(os.path.join(cache_dir, "%s.%s" % (asset_id, ext)), "wb") as out:
            out.write(payload)
        return True
    except OSError:
        return False


def _extract_assets_from_roblox_storage(asset_ids, cache_dir, wanted):
    db_path = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "rbx-storage.db")
    if not os.path.isfile(db_path) or not asset_ids:
        return 0
    extracted = 0
    try:
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        for asset_id in asset_ids:
            if wanted == "mesh" and _cached_mesh_json_exists(cache_dir, asset_id):
                continue
            if wanted == "image" and _cached_exact_image_exists(cache_dir, asset_id):
                continue
            try:
                rows = cur.execute(
                    "select content from files where content is not null and instr(content, ?) > 0 limit 12",
                    (str(asset_id).encode("ascii", errors="ignore"),),
                ).fetchall()
            except Exception:
                rows = []
            for (content,) in rows:
                if wanted == "mesh" and _write_mesh_cache_asset(cache_dir, asset_id, content):
                    extracted += 1
                    break
                if wanted == "image" and _write_image_cache_asset(cache_dir, asset_id, content):
                    extracted += 1
                    break
        con.close()
    except Exception:
        return extracted
    return extracted


def _fetch_thumbnail_item(cache_dir, item):
	asset_id = str(item.get("targetId", "")).strip()
	state = str(item.get("state", "")).strip().lower()
	image_url = str(item.get("imageUrl", "")).strip()
	if not asset_id:
		return "ignored", asset_id
	if state != "completed" or not image_url:
		if state in ("blocked", "error", "inreview"):
			_remove_cached_thumbnail(cache_dir, asset_id)
		if not image_url or state in ("blocked", "error", "inreview"):
			_mark_asset_failed(cache_dir, asset_id)
			return "failed", asset_id
		return "ignored", asset_id
	cached_path = _cached_thumbnail_path(cache_dir, asset_id)
	if cached_path:
		try:
			with open(cached_path, "rb") as cached_file:
				cached_bytes = cached_file.read()
			if not _is_roblox_thumbnail_placeholder(cached_bytes):
				_mark_thumbnail_valid(cache_dir, asset_id)
				return "cached", asset_id
		except OSError:
			pass
		_remove_cached_thumbnail(cache_dir, asset_id)
	try:
		image_bytes = _download_url_bytes(image_url, timeout=8)
		if _is_roblox_thumbnail_placeholder(image_bytes):
			_mark_asset_failed(cache_dir, asset_id)
			return "failed", asset_id
		if image_bytes.startswith(b"\x89PNG") or image_bytes.startswith(b"\xff\xd8") or image_bytes.startswith(b"RIFF"):
			with open(os.path.join(cache_dir, "%s.png" % asset_id), "wb") as out:
				out.write(image_bytes)
			_mark_thumbnail_valid(cache_dir, asset_id)
			return "downloaded", asset_id
	except Exception:
		pass
	_mark_asset_failed(cache_dir, asset_id)
	return "failed", asset_id


def _fetch_gui_asset_thumbnails(result, cache_dir, warnings):
    if not cache_dir:
        return 0
    os.makedirs(cache_dir, exist_ok=True)
    asset_ids = [
        asset_id for asset_id in _collect_gui_image_asset_ids(result)
        if not _cached_exact_image_exists(cache_dir, asset_id)
        and not os.path.isfile(_thumbnail_valid_marker_path(cache_dir, asset_id))
        and not _asset_recently_failed(cache_dir, asset_id)
    ]
    if not asset_ids:
        return 0
    downloaded = 0
    failed = 0
    with ThreadPoolExecutor(max_workers=ASSET_FETCH_WORKERS) as pool:
        for start in range(0, len(asset_ids), ROBLOX_THUMBNAIL_BATCH_SIZE):
            batch = asset_ids[start:start + ROBLOX_THUMBNAIL_BATCH_SIZE]
            query = urllib.parse.urlencode({
                "assetIds": ",".join(batch),
                "size": "420x420",
                "format": "Png",
                "isCircular": "false",
            })
            url = "https://thumbnails.roblox.com/v1/assets?%s" % query
            try:
                payload = json.loads(_download_url_bytes(url, timeout=8).decode("utf-8", errors="replace"))
            except Exception:
                failed += len(batch)
                continue
            items = payload.get("data", [])
            seen_in_response = {str(item.get("targetId", "")).strip() for item in items}
            futures = [pool.submit(_fetch_thumbnail_item, cache_dir, item) for item in items]
            for future in as_completed(futures):
                try:
                    status, _asset_id = future.result()
                except Exception:
                    status = "failed"
                if status == "downloaded":
                    downloaded += 1
                elif status == "failed":
                    failed += 1
            for asset_id in batch:
                if asset_id not in seen_in_response and not _cached_image_exists(cache_dir, asset_id):
                    _mark_asset_failed(cache_dir, asset_id)
    if downloaded > 0:
        warnings.append("Downloaded %d Roblox texture thumbnail asset(s) into cache." % downloaded)
    if failed > 0:
        warnings.append("%d Roblox texture thumbnail asset(s) could not be downloaded and will use placeholders." % failed)
    return downloaded


def _fetch_texture_assets(result, cache_dir, warnings):
    if not cache_dir:
        return 0
    os.makedirs(cache_dir, exist_ok=True)
    texture_ids = [
        asset_id for asset_id in _collect_exact_texture_asset_ids(result, TEXTURE_DIRECT_FETCH_LIMIT)
        if not _cached_exact_image_exists(cache_dir, asset_id) and not _asset_recently_failed(cache_dir, "texture_%s" % asset_id)
    ]
    if not texture_ids:
        return 0
    extracted = 0
    downloaded = 0
    failed = 0
    with ThreadPoolExecutor(max_workers=ASSET_FETCH_WORKERS) as pool:
        futures = {pool.submit(_fetch_single_texture_asset, cache_dir, asset_id): asset_id for asset_id in texture_ids}
        for future in as_completed(futures):
            try:
                status = future.result()
            except Exception:
                status = "failed"
            if status == "downloaded":
                downloaded += 1
            elif status == "failed":
                failed += 1
    if extracted > 0:
        warnings.append("Extracted %d exact Roblox texture asset(s) from local Roblox cache." % extracted)
    if downloaded > 0:
        warnings.append("Downloaded %d exact Roblox texture asset(s) into cache." % downloaded)
    if failed > 0:
        warnings.append("%d Roblox texture asset(s) require auth or were unavailable; thumbnail fallback will be tried." % failed)
        if not _roblox_cookie_header():
            warnings.append("Set ROBLOX_COOKIE in the environment to let the importer download private Roblox texture assets you can access.")
    return extracted + downloaded


def _fetch_single_texture_asset(cache_dir, asset_id):
    if _cached_exact_image_exists(cache_dir, asset_id):
        return "cached"
    payload = resolve_roblox_asset_payload(asset_id, "image", timeout=6, use_storage=False)
    if not payload:
        _mark_asset_failed(cache_dir, "texture_%s" % asset_id)
        return "failed"
    if _write_image_cache_asset(cache_dir, asset_id, payload):
        return "downloaded"
    _mark_asset_failed(cache_dir, "texture_%s" % asset_id)
    return "failed"


def _fetch_mesh_assets(result, cache_dir, warnings):
    if not cache_dir:
        return 0
    os.makedirs(cache_dir, exist_ok=True)
    mesh_ids = [
        asset_id for asset_id in _collect_mesh_asset_ids(result)
        if not _cached_mesh_json_exists(cache_dir, asset_id) and not _asset_recently_failed(cache_dir, "mesh_%s" % asset_id)
    ]
    if not mesh_ids:
        return 0
    extracted = 0
    downloaded = 0
    failed = 0
    with ThreadPoolExecutor(max_workers=ASSET_FETCH_WORKERS) as pool:
        futures = {pool.submit(_fetch_single_mesh_asset, cache_dir, asset_id): asset_id for asset_id in mesh_ids}
        for future in as_completed(futures):
            try:
                status = future.result()
            except Exception:
                status = "failed"
            if status == "downloaded":
                downloaded += 1
            elif status == "failed":
                failed += 1
    if extracted > 0:
        warnings.append("Extracted %d exact Roblox mesh asset(s) from local Roblox cache." % extracted)
    if downloaded > 0:
        warnings.append("Downloaded %d exact Roblox mesh asset(s) into cache." % downloaded)
    if failed > 0:
        warnings.append("%d Roblox mesh asset(s) require auth or could not be downloaded; only fallback geometry can be used for them." % failed)
        if not _roblox_cookie_header():
            warnings.append("Set ROBLOX_COOKIE in the environment to let the importer download private Roblox mesh assets you can access.")
    return extracted + downloaded


def _fetch_single_mesh_asset(cache_dir, asset_id):
    if _ensure_mesh_json_from_raw(cache_dir, asset_id):
        return "cached"
    payload = resolve_roblox_asset_payload(asset_id, "mesh", timeout=8, use_storage=True)
    if payload and _write_mesh_cache_asset(cache_dir, asset_id, payload):
        return "downloaded"
    _mark_asset_failed(cache_dir, "mesh_%s" % asset_id)
    return "failed"


def main(argv):
    if len(argv) < 3:
        print("Usage: python rbxl_converter.py <input.rbxl|.rbxlx> <output.json>",
              file=sys.stderr)
        return 1

    input_path = argv[1]
    output_path = argv[2]
    asset_cache_dir = ""
    fetch_gui_assets = False
    if "--asset-cache-dir" in argv:
        idx = argv.index("--asset-cache-dir")
        if idx + 1 < len(argv):
            asset_cache_dir = argv[idx + 1]
    if "--fetch-gui-assets" in argv:
        fetch_gui_assets = True

    if not os.path.isfile(input_path):
        print("ERROR: input file not found: %s" % input_path, file=sys.stderr)
        return 1

    print("Parsing %s ..." % input_path)
    try:
        result = parse_rbxl(input_path)
    except Exception as e:
        print("ERROR: failed to parse: %s" % e, file=sys.stderr)
        return 1

    inst_count = len(result['instances'])
    part_count = sum(
        1 for v in result['instances'].values()
        if v.get('class') in ('Part', 'WedgePart', 'CornerWedgePart',
                              'TrussPart', 'SpawnLocation', 'VehicleSeat',
                              'Seat', 'MeshPart', 'UnionOperation',
                              'NegateOperation', 'IntersectOperation')
    )
    print("Found %d instances (%d parts)" % (inst_count, part_count))
    for w in result.get('warnings', []):
        print("WARNING: %s" % w, file=sys.stderr)

    warnings = result.setdefault('warnings', [])
    if fetch_gui_assets and asset_cache_dir:
        purged_bad_cache = _purge_texture_only_mesh_cache(result, asset_cache_dir)
        if purged_bad_cache > 0:
            warnings.append("Purged %d stale mesh cache file(s) that belonged to texture-only Roblox asset ids." % purged_bad_cache)
        _fetch_mesh_assets(result, asset_cache_dir, warnings)
        _fetch_texture_assets(result, asset_cache_dir, warnings)
        _fetch_gui_asset_thumbnails(result, asset_cache_dir, warnings)
    sanitize_stats = {"non_finite": 0, "control_strings": 0, "compacted_strings": 0}
    result = sanitize_for_strict_json(result, warnings, stats=sanitize_stats)
    warnings = result.setdefault('warnings', [])
    if sanitize_stats["non_finite"] > 20:
        warnings.append("%d additional non-finite float value(s) were replaced." % (sanitize_stats["non_finite"] - 20))
    if sanitize_stats["control_strings"] > 0:
        warnings.append("%d binary/control string value(s) were sanitized for Godot JSON." % sanitize_stats["control_strings"])
    if sanitize_stats["compacted_strings"] > 0:
        warnings.append("%d large Roblox binary blob string(s) were compacted for responsive import." % sanitize_stats["compacted_strings"])

    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    encoded_result = json.dumps(result, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(encoded_result)

    print("Written to %s" % output_path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
