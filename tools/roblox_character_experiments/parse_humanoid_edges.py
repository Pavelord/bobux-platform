"""Strict own Humanoid edge telemetry decoder; observations never imply parity PASS."""
import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path

from marker_bytes import marker_payload, read_marker_bytes

EXPORT = "HUMANOID_EDGE_EXPORT "
DONE = "HUMANOID_EDGE_DONE "
METHODS = {"ChangeState", "GetState", "GetStateEnabled", "SetStateEnabled"}
ENABLED_IDS = {"numeric_string", "full_enum_string", "unknown_string", "canonical_name_control", "canonical_item_control", "canonical_number_control"}
RECEIVER_IDS = {"correct", "other_humanoid", "omitted", "shifted", "explicit_nil", "table", "part", "number", "enum_item"}
ARITY_IDS = {"missing", "one_nil", "state_only", "state_nil", "state_false", "state_true", "state_false_trailing_nil", "state_false_extra", "nil_false", "nil_nil", "nil_false_extra", "state_nil_extra"}


def decode(data, run_id=None, *, export_marker=EXPORT, done_marker=DONE):
    # Shared byte transport; schema-specific validation stays in each parser.
    EXPORT, DONE = export_marker, done_marker
    text, issues = read_marker_bytes(data, (EXPORT, DONE))
    packets, completions, retained = {}, {}, []
    for line_number, line in enumerate(text.splitlines(), 1):
        for marker in (EXPORT, DONE):
            payload = marker_payload(line, marker)
            if payload is None:
                continue
            retained.append(marker + payload)
            try:
                if len((marker + payload).encode("utf-8")) > 700:
                    raise ValueError("own marker exceeds 700 bytes")
                record = json.loads(payload)
                run = record["run_id"]
                if not isinstance(run, str) or not 1 <= len(run) <= 64:
                    raise ValueError("invalid run_id")
                if record.get("schema") != 1:
                    raise ValueError("unknown packet schema")
                if marker == DONE:
                    if run in completions and completions[run] != record:
                        issues.append(f"conflicting DONE for {run}")
                    completions[run] = record
                else:
                    seq, offset, segment = record["seq"], record["i"], record["s"]
                    if type(seq) is not int or seq < 1 or type(offset) is not int or offset < 1:
                        raise ValueError("invalid packet sequence/offset")
                    if not isinstance(segment, str) or not 1 <= len(segment) <= 400 or not segment.isascii():
                        raise ValueError("invalid ASCII segment")
                    if offset != (seq - 1) * 400 + 1:
                        raise ValueError("packet sequence/offset disagree")
                    key = (run, seq)
                    item = (offset, segment, len((marker + payload).encode("utf-8")))
                    if key in packets and packets[key] != item:
                        issues.append(f"conflicting duplicate packet {key}")
                    packets[key] = item
            except (ValueError, TypeError, KeyError) as exc:
                issues.append(f"malformed own marker {line_number}: {exc}")
            break
    runs = sorted(set(completions) | {key[0] for key in packets})
    if run_id is None:
        if len(runs) != 1:
            return b"", None, issues + [f"expected one run, got {runs}; select --run-id"], retained
        run_id = runs[0]
    selected = sorted((seq, item) for (run, seq), item in packets.items() if run == run_id)
    chunks, expected_seq, expected_offset = [], 1, 1
    for seq, (offset, segment, _) in selected:
        if seq != expected_seq or offset != expected_offset:
            issues.append(f"packet gap/overlap: wanted seq {expected_seq} at {expected_offset}, got {seq} at {offset}")
        chunks.append(segment)
        expected_seq, expected_offset = seq + 1, offset + len(segment)
    encoded = "".join(chunks)
    done = completions.get(run_id)
    if done is None:
        issues.append("DONE missing")
    else:
        if done.get("encoding") != "base64" or done.get("packet_bytes") != 400:
            issues.append("unknown encoding/packet size")
        if done.get("packets") != len(selected):
            issues.append("packet count mismatch")
        if done.get("encoded_bytes") != len(encoded):
            issues.append("encoded byte count mismatch")
        if done.get("max_export_line_bytes") != max((item[2] for _, item in selected), default=0):
            issues.append("maximum export line length mismatch")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError) as exc:
        raw = b""
        issues.append(f"invalid Base64: {exc}")
    if done is not None:
        if done.get("raw_bytes") != len(raw):
            issues.append("raw byte count mismatch")
        if done.get("raw_sha256") != hashlib.sha256(raw).hexdigest():
            issues.append("raw SHA256 mismatch")
    return raw, done, issues, retained


def report(raw, done, issues):
    issues = list(issues)
    try:
        payload = json.loads(raw.decode("utf-8", errors="strict"))
    except (ValueError, UnicodeError) as exc:
        payload = {}
        issues.append(f"invalid UTF-8/JSON raw: {exc}")
    rows = payload.get("rows", [])
    if not isinstance(rows, list):
        rows = []
        issues.append("rows is not a list")
    if payload.get("kind") != "humanoid_edge_results" or payload.get("schema") != 1:
        issues.append("unknown result schema")
    if payload.get("no_expected_outcomes") is not True:
        issues.append("observation-only provenance missing")
    if done:
        for field in ("run_id", "studio_version", "status", "enabled_cases", "receiver_cases", "arity_cases"):
            if done.get(field) != payload.get(field):
                issues.append(f"payload/DONE {field} mismatch")
        if done.get("records") != len(rows):
            issues.append("record count mismatch")
    if not payload.get("date_utc") or not (done or {}).get("date_utc"):
        issues.append("UTC date provenance missing")
    identities, events = set(), 0
    categories, outcomes = Counter(), Counter()
    for seq, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            issues.append(f"row {seq} is not an object")
            continue
        if row.get("seq") != seq or row.get("run_id") != payload.get("run_id"):
            issues.append(f"row {seq} sequence/run_id mismatch")
        if row.get("status") != "OBSERVED":
            issues.append(f"row {seq} unexpected status")
        identity = (row.get("kind"), row.get("method"), row.get("category"), row.get("id"))
        if identity in identities:
            issues.append(f"duplicate row identity {identity}")
        identities.add(identity)
        categories[row.get("kind", "missing")] += 1
        if "call" in row:
            outcomes[str(row["call"].get("ok"))] += 1
        if row.get("kind") == "enabled_string":
            if row.get("id") not in ENABLED_IDS:
                issues.append(f"row {seq} unknown enabled case")
            operations = row.get("operations", [])
            if [op.get("enabled") for op in operations] != [False, True]:
                issues.append(f"row {seq} missing false/true operation")
            for op in operations:
                outcomes[str(op.get("call", {}).get("ok"))] += 1
                if len(op.get("heartbeat_dt", [])) != 2:
                    issues.append(f"row {seq} incomplete signal window")
        elif row.get("kind") == "method_call":
            if row.get("method") not in METHODS:
                issues.append(f"row {seq} unknown method")
            expected = RECEIVER_IDS if row.get("category") == "receiver" else ARITY_IDS if row.get("category") == "arity" else set()
            if row.get("id") not in expected:
                issues.append(f"row {seq} unknown receiver/arity case")
            if len(row.get("heartbeat_dt", [])) != 2:
                issues.append(f"row {seq} incomplete signal window")
        for event_seq, event in enumerate(row.get("events", []), 1):
            events += 1
            args = event.get("args", {})
            if event.get("seq") != event_seq or args.get("n") != len(args.get("values", [])):
                issues.append(f"row {seq} event sequence/arity mismatch")
    expected_identities = {("manifest", None, None, None)}
    expected_identities |= {("enabled_string", None, None, case) for case in ENABLED_IDS}
    expected_identities |= {("method_call", method, "receiver", case) for method in METHODS for case in RECEIVER_IDS}
    expected_identities |= {("method_call", method, "arity", case) for method in METHODS for case in ARITY_IDS}
    if identities != expected_identities:
        issues.append("case identity coverage incomplete/extra")
    for field, expected in (("enabled_cases", 6), ("receiver_cases", 36), ("arity_cases", 48)):
        if payload.get(field) != expected:
            issues.append(f"{field} manifest count mismatch")
    return {"schema": 1, "kind": "humanoid_edge_evidence_report", "run_id": payload.get("run_id"),
            "studio_version": payload.get("studio_version"), "raw_sha256": hashlib.sha256(raw).hexdigest(),
            "raw_rows": len(rows), "native_signal_events": events, "native_pcall_outcomes": dict(outcomes),
            "categories": dict(categories), "parser_issues": issues,
            "status": "BLOCKED" if issues else "OBSERVED", "parity_status": "NOT_CALIBRATED",
            "physical_ChangeState_status": "NOT_OBSERVABLE_UNPARENTED_FIXTURE",
            "source_policy": "Only own black-box probe data; no original scripts/assets/keyframes exported"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="fresh evidence stem, no suffix")
    parser.add_argument("--run-id")
    args = parser.parse_args()
    paths = [args.output.with_suffix(suffix) for suffix in (".export.log", ".raw.json", ".observed.json")]
    if any(path.exists() for path in paths):
        raise SystemExit("Refusing to overwrite evidence; use a fresh output stem")
    raw, done, issues, retained = decode(args.input.read_bytes(), args.run_id)
    result = report(raw, done, issues)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    paths[0].write_text("\n".join(retained) + "\n", encoding="utf-8", newline="")
    paths[1].write_bytes(raw)
    paths[2].write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
