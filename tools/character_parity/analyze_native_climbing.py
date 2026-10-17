"""Derive observations from immutable own Studio telemetry; never fit a motor.

Only public movement/state/sensor facts are retained in the derived file. Native
pose, Motor6D transforms, original scripts and animation keyframes are not copied.
PostSimulation callbacks are observations, not engine solver substeps. Trials,
not callbacks, are the independent unit in condition-level distributions.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import statistics

PREFIX = "CHARACTER_EXPERIMENT_JSON "
MODES = ("Ladder", "ClassicLadder")


def distribution(values):
    finite = [v for v in values if isinstance(v, (int, float)) and math.isfinite(v)]
    if not finite:
        return None
    return {"n": len(finite), "min": min(finite), "median": statistics.median(finite),
            "max": max(finite)}


def enum_name(value):
    return value.get("Name", "NOT_OBSERVABLE") if isinstance(value, dict) else str(value)


def summarize_case(plan, begin, result, frames, blocked, events):
    post = [r for r in frames if r.get("phase") == "PostSimulation"]
    # Case ID is selected before reset, so filter events by the actual measured
    # sequence interval. Reset Freefall/Landed events must not become outcomes.
    measured_events = [r for r in events if begin and result and
                       begin["seq"] < r["seq"] < result["seq"]]
    reasons = []
    if not begin or not result:
        status = "BLOCKED"
        reasons.append("measured window not completed/started")
    elif result.get("status") != "OBSERVED":
        status = "BLOCKED"
        reasons.append(result.get("reason", "raw result was not OBSERVED"))
    elif not post:
        status = "BLOCKED"
        reasons.append("no PostSimulation observations")
    else:
        status = "OBSERVED"
    states = Counter(enum_name(r.get("state")) for r in post)
    dead_events = [r for r in measured_events if enum_name(r.get("new")) == "Dead"]
    if states.get("Dead") or dead_events:
        status = "BLOCKED"
        reasons.append("Dead observed inside measured window; lifecycle contaminated")
    if result and result.get("post_frames") != len(post):
        status = "BLOCKED"
        reasons.append("raw result post_frames differs from reconstructed callbacks")
    if blocked:
        reasons.extend(r.get("reason", "unknown blocking condition") for r in blocked)
        status = "BLOCKED"
    start_sim = begin.get("sim_s") if begin else None
    climb = [r for r in post if enum_name(r.get("state")) == "Climbing"]
    sensor_data = {}
    for mode in MODES:
        counts = Counter()
        parts = Counter()
        normals = Counter()
        hit_rows = []
        missing = 0
        for r in post:
            s = next((s for s in r.get("sensors", []) if s.get("mode") == mode), None)
            if s is None or s.get("status") == "NOT_OBSERVABLE":
                missing += 1
                continue
            hit = isinstance(s.get("SensedPart"), str) and bool(s["SensedPart"])
            native_climb = enum_name(r.get("state")) == "Climbing"
            counts[f"sensor_{'hit' if hit else 'nil'}__humanoid_{'Climbing' if native_climb else 'other'}"] += 1
            if hit:
                hit_rows.append(r)
                parts[s["SensedPart"]] += 1
                # Rounded for readable distribution only, not collision fitting.
                normal = s.get("HitNormal")
                if normal:
                    normals[json.dumps([round(v, 6) for v in normal])] += 1
        sensor_data[mode] = {
            "post_samples": len(post), "missing_or_unobservable": missing,
            "sensed_part_samples": len(hit_rows), "sensed_parts": dict(parts),
            "sensor_vs_native_state_counts": dict(sorted(counts.items())),
            "hit_normal_rounded_6dp_counts": dict(normals),
            "first_hit_delay_sim_s": hit_rows[0]["sim_s"] - start_sim if hit_rows and start_sim is not None else None,
        }
    mode_comparison = Counter()
    for row in post:
        pair = {s.get("mode"): s for s in row.get("sensors", [])}
        if any(m not in pair or pair[m].get("status") == "NOT_OBSERVABLE" for m in MODES):
            mode_comparison["not_comparable"] += 1
            continue
        a, b = (pair[m] for m in MODES)
        keys = ("SensedPart", "SensedMaterial", "HitNormal", "HitFrame")
        mode_comparison["same_public_query_values" if all(a.get(k) == b.get(k) for k in keys)
                        else "different_public_query_values"] += 1
    sequences = []
    for r in post:
        name = enum_name(r.get("state"))
        if not sequences or sequences[-1] != name:
            sequences.append(name)
    return {
        "id": plan["id"], "parameters": plan, "analysis_status": status,
        "raw_result_status": result.get("status") if result else None,
        "reasons": list(dict.fromkeys(reasons)),
        "measured_window_started": begin is not None,
        "begin_seq": begin.get("seq") if begin else None,
        "end_seq": result.get("seq") if result else None,
        "begin_wall_s": begin.get("wall_s") if begin else None,
        "end_wall_s": result.get("wall_s") if result else None,
        "duration_sim_s": result.get("duration_sim_s") if result else None,
        "duration_wall_s": result.get("duration_wall_s") if result else None,
        "post_callbacks": len(post), "post_dt_sim_s": distribution([r["dt_sim_s"] for r in post]),
        "input_counts": dict(Counter(json.dumps(r.get("input")) for r in post)),
        "state_counts": dict(states), "post_state_sequence": sequences,
        "measured_state_event_sequence": [{"old": enum_name(r.get("old")), "new": enum_name(r.get("new")),
                                            "delay_sim_s": r["sim_s"] - start_sim} for r in measured_events],
        "climbing_observed": bool(climb), "climbing_callbacks": len(climb),
        "climbing_callback_dt_sum_s": sum(r["dt_sim_s"] for r in climb),
        "first_climbing_delay_sim_s": climb[0]["sim_s"] - start_sim if climb and start_sim is not None else None,
        "climbing_vertical_speed_studs_per_s": distribution([r["linear_velocity"][1] for r in climb]),
        "raw_case_upper_median_climbing_speed": result.get("vertical_speed_median") if result else None,
        "raw_max_root_rise_studs": result.get("max_root_rise") if result else None,
        "root_y_range_studs": distribution([r["position"][1] for r in post]),
        "last_root_position_studs": post[-1]["position"] if post else None,
        "sensors": sensor_data,
        "Ladder_vs_ClassicLadder_post_comparison": dict(mode_comparison),
        "dead_post_callbacks": states.get("Dead", 0),
    }


def summarize_condition(cases):
    valid = [c for c in cases if c["analysis_status"] == "OBSERVED"]
    outcomes = Counter(str(c["climbing_observed"]) for c in valid)
    sensor_counts = {}
    for mode in MODES:
        counts = Counter()
        for c in valid:
            counts.update(c["sensors"][mode]["sensor_vs_native_state_counts"])
        sensor_counts[mode] = dict(sorted(counts.items()))
    return {
        "planned_trials": len(cases), "observed_valid_trials": len(valid),
        "blocked_trials": len(cases) - len(valid),
        "climbing_outcomes_valid_trials": dict(outcomes),
        "valid_ids": [c["id"] for c in valid],
        "blocked_ids": [c["id"] for c in cases if c["analysis_status"] != "OBSERVED"],
        "trial_median_climbing_speed_studs_per_s": distribution([
            c["climbing_vertical_speed_studs_per_s"]["median"] for c in valid
            if c["climbing_vertical_speed_studs_per_s"]]),
        "trial_max_root_rise_studs": distribution([c["raw_max_root_rise_studs"] for c in valid]),
        "trial_first_climbing_delay_sim_s": distribution([c["first_climbing_delay_sim_s"] for c in valid]),
        "trial_climbing_callback_dt_sum_s": distribution([c["climbing_callback_dt_sum_s"] for c in valid]),
        "diagnostic_sensor_vs_state_post_callback_counts": sensor_counts,
        "parity_status": "NOT_CALIBRATED",
    }


def analyze(path, observed_path=None):
    issues = []
    digest = hashlib.sha256()
    kinds = Counter()
    run_ids = set()
    begins, results = {}, {}
    frames, blocked, events = defaultdict(list), defaultdict(list), defaultdict(list)
    manifest, last, sensor_setup, interference = None, None, [], None
    next_seq = 1
    with path.open("rb") as handle:
        for line_number, line in enumerate(handle, 1):
            digest.update(line)
            text = line.decode("utf-8")
            if not text.startswith(PREFIX):
                issues.append(f"line {line_number}: not own raw marker")
                continue
            row = json.loads(text[len(PREFIX):])
            if row.get("seq") != next_seq:
                issues.append(f"sequence: expected {next_seq}, found {row.get('seq')}")
            next_seq += 1
            run_ids.add(row.get("run_id"))
            kind, case = row["kind"], row.get("case")
            kinds[kind] += 1
            if kind == "run_manifest":
                manifest = row
            elif kind == "run_result":
                last = row
            elif kind == "case_begin":
                if case in begins:
                    issues.append(f"duplicate case_begin {case}")
                begins[case] = row
            elif kind == "case_result":
                if case in results:
                    issues.append(f"duplicate case_result {case}")
                results[case] = row
            elif kind == "frame":
                frames[case].append(row)
            elif kind == "blocked":
                blocked[case].append(row)
            elif kind == "state_event":
                events[case].append(row)
            elif kind == "sensor_setup":
                sensor_setup.append({k: row[k] for k in ("mode", "properties", "settings_provenance",
                                                         "no_ControllerManager", "no_force_consumer") if k in row})
            elif kind == "interference":
                interference = {k: v for k, v in row.items() if k not in ("seq", "run_id", "schema", "frame", "wall_s", "sim_s", "case", "kind")}
    raw_hash = digest.hexdigest()
    if len(run_ids) != 1:
        issues.append("multiple/missing run IDs")
    if not manifest or not last:
        issues.append("missing manifest or run_result")
    if issues or not manifest:
        raise ValueError("BLOCKED integrity: " + "; ".join(issues))
    if observed_path:
        observed = json.loads(observed_path.read_text(encoding="utf-8"))
        if observed["raw_sha256"] != raw_hash or observed["raw_records"] != sum(kinds.values()):
            raise ValueError("BLOCKED integrity: prior observed report checksum/count mismatch")
    cases = [summarize_case(p, begins.get(p["id"]), results.get(p["id"]), frames[p["id"]],
                            blocked[p["id"]], events[p["id"]]) for p in manifest["matrix"]["cases"]]
    groups = defaultdict(list)
    for case in cases:
        p = case["parameters"]
        groups[(p["geometry"], p["WalkSpeed"], p["rig"])].append(case)
    conditions = []
    for (geometry, speed, rig), items in sorted(groups.items()):
        conditions.append({"geometry": geometry, "WalkSpeed": speed, "rig": rig,
                           "all": summarize_condition(items),
                           "train": summarize_condition([c for c in items if c["parameters"]["split"] == "train"]),
                           "holdout": summarize_condition([c for c in items if c["parameters"]["split"] == "holdout"]),
                           "calibration_gate": "BLOCKED" if len([c for c in items if c["analysis_status"] == "OBSERVED"]) < 5 else "OBSERVED_BASELINE_ONLY"})
    return {
        "schema": 1, "report_status": "IN_PROGRESS", "raw_path": str(path.as_posix()),
        "raw_sha256": raw_hash, "raw_bytes": path.stat().st_size, "raw_records": sum(kinds.values()),
        "raw_kind_counts": dict(kinds), "integrity_status": "PASS", "parser_issues": issues,
        "run_id": manifest["run_id"], "studio_version": manifest["studio_version"], "date_utc": manifest["date_utc"],
        "fixture_version": manifest["matrix"]["fixture_version"],
        "fixture_source_sha256": manifest["matrix"]["fixture_source_sha256"],
        "units": manifest["units"], "profile": manifest["standard_profile"],
        "geometry": manifest["matrix"]["fixture_geometry"], "sensor_setup": sensor_setup, "interference": interference,
        "counts": {"planned": len(cases), "windows_started": len(begins), "raw_case_results": len(results),
                   "valid_observed": sum(c["analysis_status"] == "OBSERVED" for c in cases),
                   "lifecycle_contaminated": sum(bool(c["dead_post_callbacks"]) for c in cases),
                   "not_started": sum(not c["measured_window_started"] for c in cases),
                   "analysis_blocked": sum(c["analysis_status"] == "BLOCKED" for c in cases)},
        "Ladder_vs_ClassicLadder_valid_post_comparison": dict(sum((Counter(c["Ladder_vs_ClassicLadder_post_comparison"])
            for c in cases if c["analysis_status"] == "OBSERVED"), Counter())),
        "run_result_status": last.get("status"), "conditions": conditions, "cases": cases,
        "no_fit": True, "holdout_used_for_parameter_tuning": False,
        "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED",
        "limitations": ["Five trials share one native Character; not independent respawns.",
                        "One R6 classic Humanoid profile, no NPC/network/R15 comparison.",
                        "Forward Move input only, no requested Jump; five geometries, fixed direction.",
                        "Diagnostic ControllerPartSensor does not supply force or control Humanoid.",
                        "PostSimulation callbacks are not solver substeps; sensor/state agreement is not causality.",
                        "Thresholds, automatic ledge-hand mechanics and hidden contacts are NOT_OBSERVABLE.",
                        "Current source files may differ; use source hashes embedded in this run's raw manifest."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("--observed", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = analyze(args.raw, args.observed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "integrity": data["integrity_status"],
                      "raw_sha256": data["raw_sha256"], "counts": data["counts"], "no_fit": True}))


if __name__ == "__main__":
    main()
