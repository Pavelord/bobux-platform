"""Pack/unpack byte-exact own UTF-8 telemetry inside this workspace.

One known-size Zstd frame; explicit CLI paths, no manifest-directed paths,
overwrites, recursive operations, or modifications to the original raw file.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

import zstandard as zstd

ROOT = Path(__file__).resolve().parents[2]
MAX_RAW_BYTES = 128 * 1024 * 1024
MAX_PACKED_BYTES = MAX_RAW_BYTES + 1024 * 1024
MAX_MANIFEST_BYTES = 64 * 1024
CODEC = {"name": "zstd", "level": 3, "write_content_size": True, "write_checksum": True, "single_frame": True}


def digest(value):
    return hashlib.sha256(value).hexdigest()


def workspace_path(value, workspace=ROOT):
    base = Path(workspace).resolve(strict=True)
    path = Path(value)
    resolved = (path if path.is_absolute() else base / path).resolve()
    try:
        resolved.relative_to(base)
    except ValueError as exc:
        raise ValueError("Path must stay inside the named workspace") from exc
    return resolved


def read_limited(path, maximum):
    if not path.is_file():
        raise ValueError(f"Expected an existing file: {path}")
    with path.open("rb") as stream:
        value = stream.read(maximum + 1)
    if not value or len(value) > maximum:
        raise ValueError(f"Empty file or file exceeds {maximum} byte cap: {path.name}")
    return value


def fresh_outputs(paths):
    if len(set(paths)) != len(paths):
        raise ValueError("Output paths must be distinct")
    for path in paths:
        if path.exists():
            raise ValueError(f"Refusing overwrite: {path}")
        if not path.parent.is_dir():
            raise ValueError(f"Output parent must already exist: {path.parent}")


def write_exclusive(values):
    """Only remove partial files exclusively created by this invocation."""
    fresh_outputs([path for path, _ in values])
    created = []
    try:
        for path, data in values:
            with path.open("xb") as stream:
                created.append(path)
                stream.write(data)
    except BaseException:
        for path in reversed(created):
            path.unlink()  # Individual new partial file; never recursive.
        raise


def decode_packed(packed, manifest):
    if not isinstance(manifest, dict) or manifest.get("schema") != 1 or type(manifest.get("schema")) is not int:
        raise ValueError("Unknown archive manifest schema")
    if manifest.get("kind") != "own_native_evidence_archive" or manifest.get("codec") != CODEC or manifest.get("strict_utf8") is not True:
        raise ValueError("Unknown archive codec/provenance policy")
    raw_size, packed_size = manifest.get("raw_bytes"), manifest.get("packed_bytes")
    if type(raw_size) is not int or not 0 < raw_size <= MAX_RAW_BYTES:
        raise ValueError("Raw size exceeds 128 MiB cap or is invalid")
    if type(packed_size) is not int or not 0 < packed_size <= MAX_PACKED_BYTES or packed_size != len(packed):
        raise ValueError("Packed size mismatch or cap exceeded")
    for key in ("raw_sha256", "packed_sha256"):
        if not isinstance(manifest.get(key), str) or re.fullmatch(r"[0-9a-f]{64}", manifest[key]) is None:
            raise ValueError(f"Invalid {key}")
    if digest(packed) != manifest["packed_sha256"]:
        raise ValueError("Packed SHA256 mismatch")
    # Reject unknown frame sizes: our packer always emits an exact content size.
    parameters = zstd.get_frame_parameters(packed)
    content_size = zstd.frame_content_size(packed)
    if content_size != raw_size or not 0 < content_size <= MAX_RAW_BYTES:
        raise ValueError("Zstd frame content size mismatch, unknown, or over cap")
    if parameters.window_size > MAX_RAW_BYTES or not parameters.has_checksum:
        raise ValueError("Zstd frame window exceeds cap or checksum missing")
    # For a known-size frame max_output_size alone is insufficient; header was
    # checked above. allow_extra_data=False rejects extra frames/trailing bytes.
    raw = zstd.ZstdDecompressor().decompress(packed, max_output_size=raw_size, allow_extra_data=False)
    if len(raw) != raw_size or digest(raw) != manifest["raw_sha256"]:
        raise ValueError("Raw byte size/SHA256 mismatch")
    raw.decode("utf-8", errors="strict")
    return raw


def pack(source, output, manifest_path, workspace=ROOT):
    source, output, manifest_path = [workspace_path(p, workspace) for p in (source, output, manifest_path)]
    if not source.name.endswith(".raw.log") or not output.name.endswith(".raw.log.zstd") or manifest_path.suffix != ".json":
        raise ValueError("Expected source .raw.log, output .raw.log.zstd, and explicit .json sidecar")
    if len({source, output, manifest_path}) != 3:
        raise ValueError("Input and output paths must be distinct")
    fresh_outputs([output, manifest_path])
    raw = read_limited(source, MAX_RAW_BYTES)
    raw.decode("utf-8", errors="strict")
    packed = zstd.ZstdCompressor(level=3, write_content_size=True, write_checksum=True).compress(raw)
    manifest = {"schema": 1, "kind": "own_native_evidence_archive", "source_basename": source.name,
                "raw_bytes": len(raw), "raw_sha256": digest(raw), "packed_bytes": len(packed), "packed_sha256": digest(packed),
                "codec": dict(CODEC), "strict_utf8": True,
                "zstandard_package_version": zstd.__version__,
                "scope": "Byte-exact storage of own native telemetry; no parity result"}
    if decode_packed(packed, manifest) != raw:
        raise ValueError("Pack self-verification is not byte exact")
    encoded = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    write_exclusive([(output, packed), (manifest_path, encoded)])
    return manifest


def unpack(source, manifest_path, output, workspace=ROOT):
    source, manifest_path, output = [workspace_path(p, workspace) for p in (source, manifest_path, output)]
    if not source.name.endswith(".raw.log.zstd") or manifest_path.suffix != ".json" or not output.name.endswith(".raw.log"):
        raise ValueError("Expected .raw.log.zstd source, explicit .json sidecar, and fresh .raw.log output")
    if len({source, manifest_path, output}) != 3:
        raise ValueError("Input and output paths must be distinct")
    fresh_outputs([output])
    manifest = json.loads(read_limited(manifest_path, MAX_MANIFEST_BYTES).decode("utf-8", errors="strict"))
    packed = read_limited(source, MAX_PACKED_BYTES)
    raw = decode_packed(packed, manifest)
    write_exclusive([(output, raw)])
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    for command in ("pack", "unpack"):
        command_parser = subcommands.add_parser(command)
        command_parser.add_argument("source", type=Path)
        command_parser.add_argument("--output", type=Path, required=True)
        command_parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = (pack(args.source, args.output, args.manifest) if args.command == "pack"
                  else unpack(args.source, args.manifest, args.output))
    except (ValueError, OSError, UnicodeError, zstd.ZstdError) as exc:
        parser.exit(2, f"BLOCKED: {exc}\n")
    print(json.dumps({"status": "BYTE_EXACT", "command": args.command, "output": str(args.output),
                      "raw_bytes": result["raw_bytes"], "raw_sha256": result["raw_sha256"],
                      "packed_bytes": result["packed_bytes"], "packed_sha256": result["packed_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
