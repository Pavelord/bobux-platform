"""Parse saved Studio Output/native logs into evidence JSON and CSV.

No expected constants are substituted for missing experiments. Frame telemetry may
be exported from ordinary StringValue chunks if it was not printed by default.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics
from typing import Any

PREFIX = "HUMANOID_EXPERIMENT_JSON "
DECODER = json.JSONDecoder()


def read_log(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    return data.decode("utf-8-sig", errors="replace")


def parse_records(text: str) -> tuple[list[dict[str, Any]], list[str]]:
    records: list[dict[str, Any]] = []
    issues: list[str] = []
    position = 0
    seen: dict[tuple[str, int], int] = {}
    while True:
        start = text.find(PREFIX, position)
        if start < 0:
            break
        start += len(PREFIX)
        try:
            record, size = DECODER.raw_decode(text[start:].lstrip())
        except json.JSONDecodeError as error:
            issues.append(f"Malformed record at character {start}: {error.msg}")
            position = start
            continue
        position = start + size
        if not isinstance(record, dict) or "kind" not in record:
            issues.append(f"Non-record JSON at character {start}")
            continue
        if isinstance(record.get("seq"), int) and record.get("run_id"):
            identity = (record["run_id"], record["seq"])
            if identity in seen:
                # A compact Output record and its later raw chunk export share
                # identity; retain the richer original rather than losing data.
                index = seen[identity]
                if len(json.dumps(record)) > len(json.dumps(records[index])):
                    records[index] = record
                continue
            seen[identity] = len(records)
        records.append(record)
    return records, issues


def finite_numbers(values):
    return [float(value) for value in values if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)]


def summary(values):
    values = finite_numbers(values)
    if not values:
        return {"sample_count": 0, "median": None, "minimum": None, "maximum": None}
    return {"sample_count": len(values), "median": statistics.median(values), "minimum": min(values), "maximum": max(values)}


def evidence(records, input_path: Path, issues: list[str], run_id: str | None = None):
    runs = [r.get("run_id") for r in records if r["kind"] == "run_begin"]
    if not runs:
        raise ValueError("No real run_begin record found; no empirical result generated.")
    run_id = run_id or runs[-1]
    selected = [r for r in records if r.get("run_id") == run_id]
    begins = [r for r in selected if r["kind"] == "run_begin"]
    completed = [r for r in selected if r["kind"] == "run_result"]
    cases = completed[-1].get("cases") if completed else None
    if cases is None:
        cases = [r for r in selected if r["kind"] == "case_result"]
    failures = completed[-1].get("failures", []) if completed else [{"case": r.get("case"), "reason": r.get("reason")} for r in selected if r["kind"] == "failure"]
    groups: dict[str, list[dict]] = {}
    for case in cases:
        if case.get("status") != "measured":
            continue
        params = case.get("parameters", {})
        typ = params.get("type")
        if typ == "jump":
            key = json.dumps({"type": "jump", "gravity": params.get("gravity"), "UseJumpPower": params.get("UseJumpPower"),
                              "value": params.get("JumpPower") if params.get("UseJumpPower") else params.get("JumpHeight")}, sort_keys=True)
        elif typ == "drop":
            key = json.dumps({"type": "drop", "gravity": params.get("gravity"), "height": params.get("requested_root_height_above_standing")}, sort_keys=True)
        elif typ in ("climb", "swim"):
            key = json.dumps({"type": typ, "WalkSpeed": params.get("WalkSpeed"), "component": params.get("component"), "input": params.get("input")}, sort_keys=True)
        else:
            continue
        groups.setdefault(key, []).append(case)
    jumps, landed, locomotion = [], [], []
    for key, cases_in_group in groups.items():
        params = json.loads(key)
        if params["type"] == "jump":
            jumps.append({"parameters": params, "observed_apex_height_studs": summary(c.get("observed_apex_height") for c in cases_in_group),
                          "max_observed_vy_studs_per_second": summary(c.get("max_observed_vy") for c in cases_in_group),
                          "first_post_vy_studs_per_second": summary(c.get("first_post_vy") for c in cases_in_group),
                          "first_post_dt_sim_seconds": summary(c.get("first_post_simulation", {}).get("dt_sim_s") for c in cases_in_group),
                          "exact_initial_impulse_velocity": {"status": "unobservable_between_public_frame_callbacks", "value": None},
                          "case_names": [c["name"] for c in cases_in_group]})
        elif params["type"] == "drop":
            landed.append({"parameters": params, "landed_sim_seconds": summary(c.get("landed_sim_duration") for c in cases_in_group),
                           "landed_wall_seconds": summary(c.get("landed_wall_duration") for c in cases_in_group),
                           "case_names": [c["name"] for c in cases_in_group]})
        else:
            locomotion.append({"parameters": params, "observed_speed_studs_per_second": summary(c.get("observed_speed_median") for c in cases_in_group),
                               "observed_speed_ratio_to_WalkSpeed": summary(c.get("observed_speed_ratio_to_WalkSpeed") for c in cases_in_group),
                               "state_frame_sample_count": sum(c.get("state_sample_count", 0) for c in cases_in_group),
                               "case_names": [c["name"] for c in cases_in_group]})
    frame_records = [r for r in selected if r["kind"] == "frame"]
    if not frame_records:
        issues.append("Raw frame chunks absent from input; request/first-post snapshots and summaries retained. Export StringValue chunks for full frame CSV.")
    if not completed:
        issues.append("Run did not reach run_result; evidence is incomplete.")
    result = {"schema": 1, "source": "roblox_studio_black_box", "run_id": run_id,
              "input_log": str(input_path.resolve()), "status": completed[-1].get("status") if completed else "incomplete",
              "engine": begins[-1], "record_count": len(selected), "raw_frame_count": len(frame_records),
              "humanoid_defaults": [r for r in selected if r["kind"] == "humanoid_defaults"],
              "r6_parts": [r for r in selected if r["kind"] == "r6_parts"],
              "state_enum": [r for r in selected if r["kind"] == "enum_values"],
              "state_enabled_probe": [r for r in selected if r["kind"] in ("state_enabled_probe_result", "state_enabled_probe_call", "state_enabled_changed_probe_event")],
              "camera_properties": [r for r in selected if r["kind"] == "camera_player_defaults"],
              "measurements": {"jumps": jumps, "landed_by_drop_height": landed, "locomotion": locomotion},
              "cases": cases, "failures": failures, "parser_issues": issues,
              "limitations": ["Sampling is public PreSimulation/PostSimulation, not engine solver substeps.",
                              "State event timestamps are callback observations; wall-time duration includes scheduling variation.",
                              "Only automatically entered Climbing/Swimming frames count; no force-ChangeState motion is claimed.",
                              "Parameters are empirical only for the recorded engine version, R6 fixture, platform and sampled frame rate."]}
    return result, selected


def write_csv(path: Path, records):
    fields = ["run_id", "seq", "kind", "case", "frame", "phase", "wall_s", "sim_s", "dt_sim_s", "state", "state_value", "floor",
              "position_x", "position_y", "position_z", "velocity_x", "velocity_y", "velocity_z", "old", "new", "event", "value", "status"]
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for record in records:
            if record["kind"] not in ("frame", "state_changed", "humanoid_event", "jump_request_before", "jump_request_after", "case_result"):
                continue
            row = {key: record.get(key) for key in fields}
            snap = record.get("snapshot", record)
            for kind in ("position", "velocity"):
                value = snap.get(kind, [])
                for axis, component in zip("xyz", value):
                    row[f"{kind}_{axis}"] = component
            if "snapshot" in record:
                row["state"], row["state_value"], row["floor"] = snap.get("state"), snap.get("state_value"), snap.get("floor")
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--run-id")
    args = parser.parse_args()
    records, issues = parse_records(read_log(args.log))
    try:
        result, selected = evidence(records, args.log, issues, args.run_id)
    except ValueError as error:
        parser.error(str(error))
    output = args.output or args.log.with_suffix(".empirical.json")
    csv_path = args.csv or output.with_suffix(".csv")
    output.parent.mkdir(parents=True, exist_ok=True)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    write_csv(csv_path, selected)
    print(json.dumps({"json": str(output.resolve()), "csv": str(csv_path.resolve()), "status": result["status"],
                      "cases": len(result["cases"]), "failures": len(result["failures"]), "frames": result["raw_frame_count"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
