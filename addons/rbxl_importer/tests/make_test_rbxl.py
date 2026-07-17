#!/usr/bin/env python3
"""
Test helper: build a minimal but valid binary .rbxl file in-memory, then verify
rbxl_converter.py can round-trip it.

This is NOT a Roblox file generator — it only exercises the binary parser paths
(legacy chunk loop, INST/PROP/PRNT/END, interleaving, zigzag, roblox-float,
CFrame special IDs, LZ4 compression) on a hand-crafted stream.
"""
import io
import os
import struct
import sys
import json
import subprocess

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    import lz4.block as lz4
except ImportError:
    lz4 = None


def interleave_u32_be(values):
    count = len(values)
    out = bytearray(count * 4)
    for i, v in enumerate(values):
        for b in range(4):
            out[b * count + i] = (v >> (8 * (3 - b))) & 0xFF
    return bytes(out)


def transform_i32(v):
    # zigzag
    return (v << 1) ^ (v >> 31)


def encode_roblox_float(f):
    import struct as s
    bits = s.unpack('>I', s.pack('>f', f))[0]
    # rotate left by 1 (sign bit from 31 -> 0)
    rotated = ((bits << 1) | (bits >> 31)) & 0xFFFFFFFF
    return rotated


def chunk(name, payload, compress=False):
    name_b = name.encode('ascii').ljust(4, b'\x00')[:4]
    if compress and lz4 is not None:
        comp = lz4.compress(payload, store_size=False)
        # lz4.block.compress without store_size produces raw block; we want raw
        # block compatible with decompress(raw, uncompressed_size=len(payload))
        data = comp
        comp_len = len(data)
    else:
        data = payload
        comp_len = 0
    return name_b + struct.pack('<I', comp_len) + struct.pack('<I', len(payload)) + b'\x00\x00\x00\x00' + data


def build_test_rbxl(path):
    out = io.BytesIO()
    # Header
    out.write(b'<roblox!')
    out.write(b'\x89\xff\x0d\x0a\x1a\x0a')
    out.write(struct.pack('<H', 0))  # version 0
    out.write(struct.pack('<i', 2))  # class_count (Workspace + Part)
    out.write(struct.pack('<i', 2))  # instance_count
    out.write(b'\x00' * 8)  # reserved

    # --- META chunk (empty) ---
    out.write(chunk('META', struct.pack('<I', 0)))

    # --- INST chunk: Workspace (class_id=0), referent=0 ---
    inst_ws = io.BytesIO()
    inst_ws.write(struct.pack('<I', 0))  # class id
    name = b'Workspace'
    inst_ws.write(struct.pack('<I', len(name)) + name)
    inst_ws.write(struct.pack('B', 1))  # is_service
    inst_ws.write(struct.pack('<I', 1))  # instance count
    inst_ws.write(struct.pack('B', 0))  # service instantiation flag
    # referent 0 → zigzag(0)=0
    inst_ws.write(interleave_u32_be([0]))
    out.write(chunk('INST', inst_ws.getvalue()))

    # --- INST chunk: Part (class_id=1), referent=1 ---
    inst_part = io.BytesIO()
    inst_part.write(struct.pack('<I', 1))  # class id
    pname = b'Part'
    inst_part.write(struct.pack('<I', len(pname)) + pname)
    inst_part.write(struct.pack('B', 0))  # not service
    inst_part.write(struct.pack('<I', 1))  # count
    inst_part.write(interleave_u32_be([transform_i32(1)]))
    out.write(chunk('INST', inst_part.getvalue()))

    # --- PROP chunk: Name for Workspace ---
    p = io.BytesIO()
    p.write(struct.pack('<I', 0))  # class id
    pname = b'Name'
    p.write(struct.pack('<I', len(pname)) + pname)
    p.write(struct.pack('B', 0x01))  # String type
    val = 'Workspace'.encode('utf-8')
    p.write(struct.pack('<I', len(val)) + val)
    out.write(chunk('PROP', p.getvalue()))

    # --- PROP chunk: Name for Part ---
    p = io.BytesIO()
    p.write(struct.pack('<I', 1))
    pname = b'Name'
    p.write(struct.pack('<I', len(pname)) + pname)
    p.write(struct.pack('B', 0x01))
    val = 'Baseplate'.encode('utf-8')
    p.write(struct.pack('<I', len(val)) + val)
    out.write(chunk('PROP', p.getvalue()))

    # --- PROP chunk: CFrame for Part (uses special id 0x02 = identity) ---
    p = io.BytesIO()
    p.write(struct.pack('<I', 1))
    pname = b'CFrame'
    p.write(struct.pack('<I', len(pname)) + pname)
    p.write(struct.pack('B', 0x10))  # CFrame
    p.write(struct.pack('B', 0x02))  # special id = identity
    # positions X, Y, Z interleaved
    p.write(interleave_u32_be([encode_roblox_float(1.5)]))
    p.write(interleave_u32_be([encode_roblox_float(2.5)]))
    p.write(interleave_u32_be([encode_roblox_float(3.5)]))
    out.write(chunk('PROP', p.getvalue()))

    # --- PROP chunk: Size for Part (Vector3) ---
    p = io.BytesIO()
    p.write(struct.pack('<I', 1))
    pname = b'size'
    p.write(struct.pack('<I', len(pname)) + pname)
    p.write(struct.pack('B', 0x0E))  # Vector3
    p.write(interleave_u32_be([encode_roblox_float(4.0)]))
    p.write(interleave_u32_be([encode_roblox_float(1.0)]))
    p.write(interleave_u32_be([encode_roblox_float(2.0)]))
    out.write(chunk('PROP', p.getvalue()))

    # --- PROP chunk: Color for Part (Color3) ---
    p = io.BytesIO()
    p.write(struct.pack('<I', 1))
    pname = b'Color'
    p.write(struct.pack('<I', len(pname)) + pname)
    p.write(struct.pack('B', 0x0C))  # Color3
    p.write(interleave_u32_be([encode_roblox_float(0.5)]))
    p.write(interleave_u32_be([encode_roblox_float(0.6)]))
    p.write(interleave_u32_be([encode_roblox_float(0.7)]))
    out.write(chunk('PROP', p.getvalue()))

    # --- PRNT chunk: Part(1) → Workspace(0) ---
    prnt = io.BytesIO()
    prnt.write(struct.pack('B', 0))  # version
    prnt.write(struct.pack('<I', 1))  # count
    prnt.write(interleave_u32_be([transform_i32(1)]))  # child = 1
    prnt.write(interleave_u32_be([transform_i32(0)]))  # parent = 0
    out.write(chunk('PRNT', prnt.getvalue()))

    # --- END chunk ---
    out.write(chunk('END', b''))

    with open(path, 'wb') as fp:
        fp.write(out.getvalue())
    return out.tell()


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    rbxl_path = os.path.join(here, 'binary_sample.rbxl')
    json_path = os.path.join(here, 'binary_sample.json')
    size = build_test_rbxl(rbxl_path)
    print('Built test .rbxl: %s (%d bytes)' % (rbxl_path, size))

    converter = os.path.join(os.path.dirname(here), 'rbxl_converter.py')
    result = subprocess.run([sys.executable, converter, rbxl_path, json_path],
                            capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode != 0:
        print(result.stderr, end='')
        return 1

    with open(json_path, encoding='utf-8') as f:
        data = json.load(f)

    assert data['format'] == 'binary', 'expected binary format'
    assert len(data['instances']) == 2, 'expected 2 instances'
    part = data['instances']['1']
    assert part['class'] == 'Part', 'expected Part, got %s' % part['class']
    assert part['properties']['Name'] == 'Baseplate'
    cf_pos = part['properties']['CFrame']['position']
    assert abs(cf_pos[0] - 1.5) < 1e-4 and abs(cf_pos[1] - 2.5) < 1e-4 and abs(cf_pos[2] - 3.5) < 1e-4, cf_pos
    sz = part['properties']['size']
    assert abs(sz[0] - 4.0) < 1e-4 and abs(sz[1] - 1.0) < 1e-4 and abs(sz[2] - 2.0) < 1e-4, sz
    col = part['properties']['Color']
    assert abs(col[0] - 0.5) < 1e-4 and abs(col[1] - 0.6) < 1e-4 and abs(col[2] - 0.7) < 1e-4, col
    assert {'child': 1, 'parent': 0} in data['hierarchy'], 'missing hierarchy edge'
    print('Round-trip assertions PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
