"""Validate/export only our native enum coercion measurements; never infer PASS."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from marker_bytes import marker_payload, read_marker_bytes

EXPORT = "ENUM_COERCION_EXPORT "
DONE = "ENUM_COERCION_DONE "


def read_input_bytes(data):
    return read_marker_bytes(data, (EXPORT, DONE))


def reconstruct(text, run_id=None):
    packets, completions, issues, retained = {}, {}, [], []
    for line_number, line in enumerate(text.splitlines(), 1):
        for marker in (EXPORT, DONE):
            payload = marker_payload(line, marker)
            if payload is None:
                continue
            retained.append(marker + payload)
            try:
                record = json.loads(payload)
                run = record["run_id"]
                if not isinstance(run, str) or not run:
                    raise ValueError("missing/invalid run_id")
                if marker == DONE:
                    prior = completions.get(run)
                    if prior is not None and prior != record:
                        issues.append(f"conflicting completion marker for {run}")
                    completions[run] = record
                else:
                    offset, segment = record["i"], record["s"]
                    if not isinstance(offset, int) or isinstance(offset, bool) or offset < 1:
                        raise ValueError("invalid positive byte offset")
                    if not isinstance(segment, str):
                        raise ValueError("segment is not a string")
                    if record.get("n") != f"{offset:06d}":
                        raise ValueError("packet name does not match byte offset")
                    key = (run, offset)
                    if key in packets and packets[key] != segment:
                        issues.append(f"conflicting duplicate packet {key}")
                    packets[key] = segment
            except (ValueError, TypeError, KeyError) as exc:
                issues.append(f"malformed marker line {line_number}: {exc}")
            break
    runs = sorted({key[0] for key in packets} | set(completions))
    if run_id is None:
        if len(runs) != 1:
            return "", None, issues + [f"expected one run, found {runs}; specify --run-id"], retained
        run_id = runs[0]
    values, expected = [], 1
    for (run, offset), segment in sorted(packets.items()):
        if run != run_id:
            continue
        if offset != expected:
            issues.append(f"missing/overlapping segment: expected byte {expected}, received {offset}")
        values.append(segment)
        expected = offset + len(segment.encode("utf-8"))
    raw = "".join(values)
    done = completions.get(run_id)
    if done is None:
        issues.append("completion marker missing")
    elif done.get("bytes") != len(raw.encode("utf-8")):
        issues.append(f"byte count mismatch: reconstructed {len(raw.encode('utf-8'))}, advertised {done.get('bytes')}")
    return raw, done, issues, retained


def report(raw, done, issues):
    issues = list(issues)
    try:
        payload = json.loads(raw)
    except (ValueError, TypeError) as exc:
        payload = {}
        issues.append(f"raw JSON invalid: {exc}")
    rows = payload.get("rows", [])
    if not isinstance(rows, list):
        issues.append("rows is not a list")
        rows = []
    if payload.get("kind") != "enum_coercion_results" or payload.get("schema") != 1:
        issues.append("unknown/missing enum coercion result schema")
    if not payload.get("no_expected_outcomes"):
        issues.append("no_expected_outcomes provenance missing")
    if done:
        if payload.get("run_id") != done.get("run_id"):
            issues.append("payload/completion run_id mismatch")
        if done.get("rows") != len(rows):
            issues.append(f"row count mismatch: received {len(rows)}, advertised {done.get('rows')}")
        if payload.get("status") != done.get("status"):
            issues.append("payload/completion status mismatch")
    identities = set()
    for seq, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            issues.append(f"row {seq} is not an object")
            continue
        if row.get("seq") != seq:
            issues.append(f"row sequence gap: expected {seq}, received {row.get('seq')}")
        if row.get("run_id") != payload.get("run_id"):
            issues.append(f"row {seq} has mixed run_id")
        if row.get("id"):
            identity = (row.get("id"), row.get("context"))
            if identity in identities:
                issues.append(f"duplicate measurement identity {identity}")
            identities.add(identity)
    blocked_rows = sum(row.get("status") == "BLOCKED" for row in rows if isinstance(row, dict))
    if payload.get("blocked_rows") != blocked_rows:
        issues.append("blocked row count mismatch")
    if done and done.get("blocked_rows") != blocked_rows:
        issues.append("completion blocked row count mismatch")
    return {
        "schema": 1, "kind": "enum_coercion_evidence_report",
        "run_id": payload.get("run_id"), "studio_version": payload.get("studio_version"),
        "raw_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "raw_rows": len(rows), "blocked_rows": blocked_rows, "parser_issues": issues,
        "status": "BLOCKED" if issues or blocked_rows or payload.get("status") == "BLOCKED" else "OBSERVED",
        "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED",
        "contexts": dict(Counter(row.get("context", "manifest_or_fixture") for row in rows if isinstance(row, dict))),
        "native_pcall_outcomes": dict(Counter(str(row["ok"]) for row in rows if isinstance(row, dict) and "ok" in row)),
        "source_policy": "Only Bobux-authored black-box probe measurements; no original script Source, asset IDs or keyframes retained",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="fresh evidence stem, without suffix")
    parser.add_argument("--run-id")
    args = parser.parse_args()
    targets = [args.output.with_suffix(suffix) for suffix in (".export.log", ".raw.json", ".observed.json")]
    if any(path.exists() for path in targets):
        raise SystemExit("Refusing to overwrite evidence; select a new --output stem")
    text, encoding_issues = read_input_bytes(args.input.read_bytes())
    raw, done, issues, retained = reconstruct(text, args.run_id)
    issues = encoding_issues + issues
    data = report(raw, done, issues)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    targets[0].write_text("\n".join(retained) + "\n", encoding="utf-8", newline="")
    targets[1].write_text(raw, encoding="utf-8", newline="")
    targets[2].write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    raise SystemExit(0 if data["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
