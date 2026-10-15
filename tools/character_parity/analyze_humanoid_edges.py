"""Summarize verified native method observations without assuming physics parity."""
import argparse
import hashlib
import json
from pathlib import Path


def disabled(snapshot):
    return [item["Name"] for item in snapshot["canonical"]
            if item["result"]["ok"] and item["result"]["returns"][0].get("value") is False]


def summarize(raw_path, observed_path):
    raw = raw_path.read_bytes()
    payload = json.loads(raw)
    observed = json.loads(observed_path.read_text(encoding="utf-8"))
    digest = hashlib.sha256(raw).hexdigest()
    if observed["status"] != "OBSERVED" or observed["parser_issues"] or observed["raw_sha256"] != digest:
        raise ValueError("Verified native evidence and its exact SHA-256 are required")
    rows = payload["rows"]
    if len(rows) != 91 or payload["run_id"] != observed["run_id"]:
        raise ValueError("Unexpected evidence scope/run")
    strings, methods = [], []
    for row in rows:
        if row["kind"] == "enabled_string":
            strings.append({"id": row["id"], "raw_arg": row["raw_arg"],
                            "disabled_before": disabled(row["before"]),
                            "operations": [{"enabled": operation["enabled"], "call": operation["call"],
                                            "disabled_immediate": disabled(operation["immediate"]),
                                            "disabled_after_window": disabled(operation["after_window"]),
                                            "raw_getter_after_window": operation["after_window"]["raw_getter"],
                                            "events_after_immediate": operation["events_after_immediate"],
                                            "events_after_window": operation["events_after_window"],
                                            "heartbeat_dt": operation["heartbeat_dt"]}
                                           for operation in row["operations"]],
                            "events": row["events"]})
        elif row["kind"] == "method_call":
            methods.append({"method": row["method"], "category": row["category"], "id": row["id"],
                            "call": row["call"], "events": row["events"],
                            "target_disabled_after_window": disabled(row["after_window"]["target"]),
                            "other_disabled_after_window": disabled(row["after_window"]["other"]),
                            "heartbeat_dt": row["heartbeat_dt"]})
    return {"schema": 1, "status": "OBSERVED_NOT_PARITY_PASS", "run_id": payload["run_id"],
            "studio_version": payload["studio_version"], "date_utc": payload["date_utc"],
            "raw_path": raw_path.as_posix(), "raw_sha256": digest,
            "native_rows": len(rows), "enabled_inputs": strings, "method_calls": methods,
            "no_fit": True, "limitations": [
                "One observation per exact input case, not five independent repeats.",
                "Fresh unparented Humanoids: ChangeState physical effects NOT_OBSERVABLE.",
                "Signals observed immediately and for two subsequent Heartbeats only.",
                "Studio 0.743 evidence is kept separate from earlier 0.742 coercion data.",
                "No claim about script API routes outside these four Humanoid methods."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("--observed", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(args.raw, args.observed)
    with args.output.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("status", "run_id", "raw_sha256", "native_rows")}))


if __name__ == "__main__":
    main()
