"""Verify public EncodingService Zstd/Base64 export of our own raw telemetry.

Transport integrity never means character parity PASS. Native run_result status
is retained. Only anchored own markers are decoded; no evidence is overwritten.
"""
import argparse
import base64
import binascii
import hashlib
import json
from pathlib import Path
import re

import zstandard as zstd

from marker_bytes import marker_payload, read_marker_bytes
import parse_output as plain

EXPORT = "CHARACTER_ZSTD_EXPORT "
DONE = "CHARACTER_ZSTD_DONE "
RAW_LIMIT = 128 * 1024 * 1024
ENCODED_LIMIT = 4 * ((RAW_LIMIT + 2) // 3)
NATIVE_LIMIT = 512 * 1024 * 1024
RECORD_LIMIT = 1000000


def integer(value, minimum=1, maximum=RAW_LIMIT):
    return type(value) is int and minimum <= value <= maximum


def valid_run(value):
    return isinstance(value, str) and 0 < len(value) <= 64


def sha(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def read_input_bytes(source):
    if len(source) > NATIVE_LIMIT:
        return "", ["native input exceeds 512 MiB size cap"]
    return read_marker_bytes(source, (EXPORT, DONE))


def decompress_limited(compressed, advertised_raw_bytes, limit=RAW_LIMIT):
    """Guard known frame size because zstandard ignores max_output_size for it."""
    if not 0 < advertised_raw_bytes <= limit:
        raise ValueError("advertised raw bytes exceed cap")
    params = zstd.get_frame_parameters(compressed)
    content_size = zstd.frame_content_size(compressed)
    unknown = content_size in (-1, zstd.CONTENTSIZE_UNKNOWN)
    if not unknown and (content_size > limit or content_size != advertised_raw_bytes):
        raise ValueError("Zstd frame content size differs from advertised raw bytes or exceeds cap")
    if params.window_size > limit:
        raise ValueError("Zstd frame window exceeds raw size cap")
    raw = zstd.ZstdDecompressor().decompress(compressed, max_output_size=advertised_raw_bytes, allow_extra_data=False)
    if len(raw) != advertised_raw_bytes or len(raw) > limit:
        raise ValueError("decompressed raw byte count mismatch")
    return raw


def reconstruct(text, run_id=None):
    packets, completions, retained, issues = {}, {}, [], []
    encoded_received = 0
    for line_number, line in enumerate(text.splitlines(), 1):
        for marker in (EXPORT, DONE):
            payload = marker_payload(line, marker)
            if payload is None:
                continue
            retained.append(marker + payload)
            try:
                record = json.loads(payload)
                if not isinstance(record, dict) or type(record.get("schema")) is not int or record["schema"] != 1 or not valid_run(record.get("run_id")):
                    raise ValueError("invalid marker schema/run_id")
                run = record["run_id"]
                if marker == DONE:
                    if run in completions and completions[run] != record:
                        raise ValueError("conflicting completion manifest")
                    completions[run] = record
                else:
                    if not integer(record.get("seq"), maximum=ENCODED_LIMIT) or not integer(record.get("i"), maximum=ENCODED_LIMIT):
                        raise ValueError("invalid positive sequence/encoded byte offset")
                    segment = record.get("s")
                    if not isinstance(segment, str) or not segment.isascii() or not 0 < len(segment) <= 700:
                        raise ValueError("segment must be 1..700 ASCII bytes")
                    key = (run, record["seq"])
                    value = (record["i"], segment)
                    if key in packets and packets[key] != value:
                        raise ValueError("conflicting duplicate packet")
                    if key not in packets:
                        encoded_received += len(segment)
                        if encoded_received > ENCODED_LIMIT:
                            raise ValueError("total encoded packets exceed cap")
                    packets[key] = value
            except (ValueError, TypeError, KeyError) as exc:
                issues.append(f"malformed compressed marker line {line_number}: {exc}")
            break
    runs = sorted({k[0] for k in packets} | set(completions))
    if run_id is None:
        if len(runs) != 1:
            return b"", None, issues + [f"expected one compressed run, found {runs}; specify --run-id"], retained
        run_id = runs[0]
    manifest = completions.get(run_id)
    if manifest is None:
        return b"", None, issues + ["compressed completion manifest missing"], retained
    fields = (("raw_bytes", RAW_LIMIT), ("compressed_bytes", RAW_LIMIT), ("encoded_bytes", ENCODED_LIMIT),
              ("raw_records", RECORD_LIMIT), ("packets", ENCODED_LIMIT))
    if any(not integer(manifest.get(name), maximum=cap) for name, cap in fields):
        issues.append("completion size/count fields invalid or exceed caps")
    if manifest.get("packet_bytes") not in (400, 700) or type(manifest.get("packet_bytes")) is not int:
        issues.append("unsupported packet_bytes")
    if (manifest.get("encoding"), manifest.get("compression"), manifest.get("compression_level")) != ("base64", "zstd", 3) or type(manifest.get("compression_level")) is not int:
        issues.append("unsupported compression policy")
    if not sha(manifest.get("raw_sha256")) or not sha(manifest.get("compressed_sha256")):
        issues.append("invalid/missing SHA256 hashes")
    if not isinstance(manifest.get("codec_policy"), str) or not manifest["codec_policy"]:
        issues.append("codec provenance missing")
    if issues:
        return b"", manifest, issues, retained
    selected = sorted((seq, offset, segment) for (run, seq), (offset, segment) in packets.items() if run == run_id)
    expected_seq, expected_offset = 1, 1
    pieces = []
    for seq, offset, segment in selected:
        if seq != expected_seq or offset != expected_offset:
            issues.append(f"missing/overlapping packet: expected seq {expected_seq}/byte {expected_offset}, received {seq}/{offset}")
        if seq < manifest["packets"] and len(segment) != manifest["packet_bytes"]:
            issues.append("short non-final encoded packet")
        if len(segment) > manifest["packet_bytes"]:
            issues.append("packet exceeds declared packet_bytes")
        pieces.append(segment)
        expected_seq, expected_offset = seq + 1, offset + len(segment)
    encoded = "".join(pieces)
    if len(selected) != manifest["packets"] or len(encoded) != manifest["encoded_bytes"]:
        issues.append("encoded packet count/byte count mismatch")
    if manifest["encoded_bytes"] != 4 * ((manifest["compressed_bytes"] + 2) // 3):
        issues.append("Base64 advertised size relation mismatch")
    if issues:
        return b"", manifest, issues, retained
    try:
        compressed = base64.b64decode(encoded, validate=True)
        if len(compressed) != manifest["compressed_bytes"]:
            raise ValueError("compressed byte count mismatch")
        if hashlib.sha256(compressed).hexdigest() != manifest["compressed_sha256"]:
            raise ValueError("compressed SHA256 mismatch")
        raw = decompress_limited(compressed, manifest["raw_bytes"])
        if hashlib.sha256(raw).hexdigest() != manifest["raw_sha256"]:
            raise ValueError("raw SHA256 mismatch")
    except (ValueError, binascii.Error, zstd.ZstdError) as exc:
        return b"", manifest, issues + [f"compressed integrity failure: {exc}"], retained
    return raw, manifest, issues, retained


def report(raw_bytes, manifest, issues):
    issues = list(issues)
    try:
        raw = raw_bytes.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raw = ""
        issues.append("decompressed own telemetry is not strict UTF-8")
    rows, raw_issues = plain.parse_raw(raw)
    issues.extend(raw_issues)
    if manifest:
        if len(rows) != manifest.get("raw_records"):
            issues.append("raw record count differs from compressed manifest")
        if any(row.get("run_id") != manifest.get("run_id") for row in rows):
            issues.append("raw records/transport run_id mismatch")
    integrity_issues = list(issues)
    data = plain.report(rows, raw, issues)
    data["raw_sha256"] = hashlib.sha256(raw_bytes).hexdigest()
    data["compressed_transport"] = {"status": "BLOCKED" if integrity_issues else "VERIFIED",
                                     "manifest": manifest, "integrity_issues": integrity_issues,
                                     "scope": "Byte-exact own telemetry transport; no parity PASS claim"}
    return raw, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--compare-raw", type=Path, help="Optional saved own raw file, read-only byte comparison")
    args = parser.parse_args()
    targets = [args.output.with_suffix(s) for s in (".export.log", ".raw.log", ".observed.json")]
    if any(path.exists() for path in targets):
        raise SystemExit("Refusing to overwrite evidence; select a fresh --output stem")
    if args.input.stat().st_size > NATIVE_LIMIT:
        raise SystemExit("BLOCKED: native input exceeds 512 MiB size cap")
    text, encoding_issues = read_input_bytes(args.input.read_bytes())
    raw_bytes, manifest, issues, retained = reconstruct(text, args.run_id)
    issues = encoding_issues + issues
    if args.compare_raw is not None:
        if args.compare_raw.stat().st_size > RAW_LIMIT:
            issues.append("saved own raw comparison exceeds 128 MiB cap")
        elif raw_bytes != args.compare_raw.read_bytes():
            issues.append("compressed export differs from saved own raw bytes")
    raw, data = report(raw_bytes, manifest, issues)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation protects evidence even if another writer raced checks.
    with targets[0].open("x", encoding="utf-8", newline="") as stream:
        stream.write("\n".join(retained) + "\n")
    with targets[1].open("xb") as stream:
        stream.write(raw_bytes)
    with targets[2].open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"run_id": data["run_id"], "status": data["status"], "raw_records": data["raw_records"],
                      "raw_sha256": data["raw_sha256"], "transport": data["compressed_transport"]["status"],
                      "parser_issues": data["parser_issues"]}, ensure_ascii=False))
    raise SystemExit(0 if data["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
