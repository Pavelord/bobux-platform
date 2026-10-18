"""Frozen bare-Humanoid RigType evidence validation, never Bobux parity/fitting.

Rules come from the own frozen probe. Target labels construct inputs; no
resulting R6/R15 value, native setter success or signal count is presumed.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import uuid

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "CHARACTER_EXPERIMENT_JSON "
REGISTRATION_SHA256 = "373875440df6200fef789a08d140899317a88cc96059d04f94106cf9ccd05f09"
FIXTURE_VERSION = "2026-10-17-a3-rig-type-edges-v1"
POINTS = ["before_setter", "immediate_after_setter", "after_Heartbeat_1", "after_Heartbeat_2"]
VARIANTS = ["matching_enum", "number", "bare_name", "numeric_string", "positive_fraction", "negative_fraction", "wrong_domain", "full_name_string", "nil", "boolean_false", "boolean_true", "empty_table", "negative_number", "invalid_number", "invalid_name", "nan", "positive_inf", "negative_inf"]
COUNT_KEYS = ("property_changed", "changed_total", "changed_rig_type")
CLOCK_KEYS = ("wall_s", "heartbeat_index", "heartbeat_sim_elapsed_s", "last_heartbeat_dt_sim_s")
KINDS = {"run_manifest", "run_result", "case_begin", "case_result", "blocked", "rig_type_fresh_observation", "rig_type_baseline_result", "rig_type_observation", "rig_type_setter_attempt", "rig_type_setter_return", "rig_type_event"}
EPSILON = 1e-6  # Fixed representation allowance, never fitted callback timing.
RAW_LIMIT = 32 * 1024 * 1024
RECORD_LIMIT = 20000


def obj(value):
    return value if isinstance(value, dict) else {}


def num(value):
    return type(value) in (int, float) and math.isfinite(value)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def equal(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if num(a) and num(b):
        return a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def require(issues, condition, message):
    if not condition:
        issues.append(message)


def strict_json(text):
    def pairs(values):
        result = {}
        for key, value in values:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result
    def nonfinite(value):
        raise ValueError("raw nonfinite JSON token: " + value)
    return json.loads(text, object_pairs_hook=pairs, parse_constant=nonfinite)


def read_json(path):
    if path.stat().st_size > RAW_LIMIT:
        raise ValueError("JSON exceeds 32 MiB cap")
    return strict_json(path.read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_raw(path):
    if path.stat().st_size > RAW_LIMIT:
        raise ValueError("raw exceeds 32 MiB cap")
    data = path.read_bytes()
    rows = []
    for line_index, line in enumerate(data.decode("utf-8", errors="strict").splitlines(), 1):
        if not line.startswith(PREFIX):
            raise ValueError(f"line {line_index}: missing anchored own marker")
        row = strict_json(line[len(PREFIX):])
        if not isinstance(row, dict):
            raise ValueError(f"line {line_index}: record must be an object")
        rows.append(row)
        if len(rows) > RECORD_LIMIT:
            raise ValueError("raw exceeds 20000-record cap")
    return rows, hashlib.sha256(data).hexdigest(), len(data)


def enum_tag(domain, name, value):
    return {"type": "EnumItem", "lua_type": "userdata", "Name": name, "Value": value, "EnumType": domain, "tostring": f"Enum.{domain}.{name}"}


def expected_input(case):
    target = case["target"]
    value = {"R6": 0, "R15": 1}[target]
    variant = case["variant"]
    if variant == "matching_enum": return enum_tag("HumanoidRigType", target, value)
    if variant == "wrong_domain": return enum_tag("CameraType", "Fixed", 0)
    if variant == "nil": return {"type": "nil", "is_nil": True}
    if variant in ("boolean_false", "boolean_true"): return {"type": "boolean", "value": variant == "boolean_true"}
    if variant == "empty_table": return {"type": "table", "empty": True, "content_policy": "No recursive table traversal"}
    if variant in ("nan", "positive_inf", "negative_inf"): return {"type": "number", "special": variant}
    if variant in ("bare_name", "numeric_string", "full_name_string", "invalid_name"):
        return {"type": "string", "value": {"bare_name": target, "numeric_string": str(value), "full_name_string": f"Enum.HumanoidRigType.{target}", "invalid_name": "BOBUX_NONEXISTENT_ITEM"}[variant]}
    return {"type": "number", "value": {"number": value, "positive_fraction": value + .5, "negative_fraction": -.5, "negative_number": -1, "invalid_number": 999999}[variant]}


def tag_issues(value, label):
    issues, value = [], obj(value)
    kind = value.get("type")
    if kind == "EnumItem":
        require(issues, set(value) == {"type", "lua_type", "Name", "Value", "EnumType", "tostring"}, label + ": enum tag fields differ")
        name, domain = value.get("Name"), value.get("EnumType")
        valid = isinstance(name, str) and isinstance(domain, str) and re.fullmatch(r"[A-Za-z_]\w*", name) and re.fullmatch(r"[A-Za-z_]\w*", domain)
        require(issues, valid and value.get("lua_type") == "userdata" and num(value.get("Value")) and float(value["Value"]).is_integer(), label + ": invalid enum identity schema")
        require(issues, value.get("tostring") == f"Enum.{domain}.{name}", label + ": enum tostring/domain/name mismatch")
    elif kind == "number":
        finite = set(value) == {"type", "value"} and num(value.get("value"))
        special = set(value) == {"type", "special"} and value.get("special") in ("nan", "positive_inf", "negative_inf")
        require(issues, finite or special, label + ": number must be finite or an exact nonfinite tag")
    elif kind in ("boolean", "string"):
        require(issues, set(value) == {"type", "value"} and type(value.get("value")) is (bool if kind == "boolean" else str), label + ": boolean/string tag lost its value/type")
    elif kind == "nil":
        require(issues, set(value) == {"type", "is_nil"} and value.get("is_nil") is True, label + ": explicit nil tag absent")
    elif kind == "table":
        require(issues, set(value) == {"type", "empty", "content_policy"} and type(value.get("empty")) is bool and value.get("content_policy") == "No recursive table traversal", label + ": table tag schema differs")
    else:
        issues.append(label + ": unobservable/unsupported scalar tag")
    return issues


def getter_issues(value, label, baseline=None):
    issues, value = [], obj(value)
    require(issues, value.get("ok") is True and set(value) == {"ok", "value"}, label + ": required getter unavailable or malformed")
    tag = obj(value.get("value"))
    issues.extend(tag_issues(tag, label))
    name = tag.get("Name")
    require(issues, name in ("R6", "R15") and equal(tag, enum_tag("HumanoidRigType", name, {"R6": 0, "R15": 1}.get(name))), label + ": getter is not a canonical HumanoidRigType")
    if baseline is not None:
        require(issues, equal(tag, enum_tag("HumanoidRigType", baseline, {"R6": 0, "R15": 1}[baseline])), label + ": controlled baseline differs")
    return issues


def tuple_issues(value, label):
    issues, value = [], obj(value)
    count, values = value.get("count"), value.get("values")
    require(issues, set(value) == {"count", "values"} and integer(count) and isinstance(values, list) and count == len(values), label + ": tuple count/trailing-nil arity differs")
    if isinstance(values, list):
        for index, item in enumerate(values): issues.extend(tag_issues(item, f"{label}/{index}"))
    return issues


def setter_issues(value, label):
    value, issues = obj(value), []
    if value.get("ok") is True:
        require(issues, set(value) == {"ok", "returns"} and equal(value.get("returns"), {"count": 0, "values": []}), label + ": own assignment closure must have zero successful returns")
    elif value.get("ok") is False:
        require(issues, set(value) == {"ok", "error"} and isinstance(value.get("error"), str) and 0 < len(value["error"]) <= 1200, label + ": failed setter must preserve its bounded error")
    else:
        issues.append(label + ": setter ok must be a boolean")
    return issues


def clock_issues(value, label):
    value = obj(value)
    valid = set(value) == set(CLOCK_KEYS) and integer(value.get("heartbeat_index")) and all(num(value.get(k)) and value[k] >= 0 for k in CLOCK_KEYS if k != "heartbeat_index")
    return [] if valid else [label + ": invalid finite wall/Heartbeat clock schema"]


def precedes(first, last):
    if clock_issues(first, "") or clock_issues(last, ""): return False
    return all(first[key] <= last[key] + (0 if key == "heartbeat_index" else EPSILON) for key in ("wall_s", "heartbeat_index", "heartbeat_sim_elapsed_s"))


def wait_issues(value, emitted, label):
    value, issues = obj(value), []
    require(issues, set(value) == {"before", "after", "wait_callback_dt_sim_s"} and num(value.get("wait_callback_dt_sim_s")) and value["wait_callback_dt_sim_s"] >= 0, label + ": actual Heartbeat wait/dt absent")
    issues.extend(clock_issues(value.get("before"), label + "/before"))
    issues.extend(clock_issues(value.get("after"), label + "/after"))
    require(issues, precedes(value.get("before"), value.get("after")) and precedes(value.get("after"), emitted), label + ": Heartbeat wait clocks do not bracket actual observation")
    return issues


def counts_issues(value, expected, label):
    valid = isinstance(value, dict) and set(value) == set(COUNT_KEYS) and all(integer(value.get(k)) for k in COUNT_KEYS)
    return [] if valid and equal(value, expected) else [label + ": callback counts do not match the recorded complete event stream"]


def one(rows, kind, issues, label):
    selected = [row for row in rows if row.get("kind") == kind]
    require(issues, len(selected) == 1, f"{label}: expected exactly one {kind}, found {len(selected)}")
    return selected[0] if len(selected) == 1 else {}


def registration_issues(plan):
    plan, issues = obj(plan), []
    require(issues, plan.get("fixture_version") == FIXTURE_VERSION and type(plan.get("schema")) is int and plan["schema"] == 1, "registration: wrong frozen fixture/schema")
    cases, sessions = plan.get("cases"), plan.get("sessions")
    expected = {(c, b, t, v) for c in ("fresh_unparented", "fresh_workspace") for b in ("R6", "R15") for t in ("R6", "R15") for v in VARIANTS}
    valid_cases = isinstance(cases, list) and len(cases) == 144 and all(isinstance(c, dict) for c in cases)
    require(issues, valid_cases, "registration: 144 case objects required")
    if valid_cases:
        combinations = [(c.get("context"), c.get("baseline"), c.get("target"), c.get("variant")) for c in cases]
        require(issues, all(all(isinstance(x, str) for x in row) for row in combinations) and set(combinations) == expected and len({c.get("id") for c in cases if isinstance(c.get("id"), str)}) == 144, "registration: exact 2x2x2x18 matrix/IDs differ")
        require(issues, all(type(c.get("ordinal")) is int and c["ordinal"] == index for index, c in enumerate(cases, 1)), "registration: frozen ordinal order differs")
    expected_sessions = [{"id": f"rig_type_edges_play{i}", "session_index": i, "split": "train" if i <= 3 else "holdout", "seed": 20261016} for i in range(1, 6)]
    require(issues, equal(sessions, expected_sessions), "registration: five session identities/splits differ")
    require(issues, equal(plan.get("required_points"), POINTS) and equal(plan.get("cases_per_Play"), 144) and equal(plan.get("required_independent_Play_sessions"), 5) and equal(plan.get("baseline_settle_Heartbeats"), 1) and equal(plan.get("observation_Heartbeats_after_setter"), 2), "registration: case/point/Heartbeat/session counts differ")
    require(issues, all(plan.get(key) is True for key in ("no_fit", "no_parity_pass_claim", "no_physical_rig_claim")), "registration: scope restrictions missing")
    hashes = obj(plan.get("fixture_source_sha256"))
    require(issues, set(hashes) == {"common.luau", "probe.server.luau", "serializer_test.luau"} and all(isinstance(x, str) and re.fullmatch("[0-9a-f]{64}", x) for x in hashes.values()), "registration: own source hashes absent/malformed")
    return issues


def parameters(case, config):
    return dict(case, rig=case["target"], split=config["split"], path="FRESH_SCALAR_HUMANOID_ONLY")


def analyze_case(stream, case, config, plan):
    name, issues = case["id"], []
    begin = one(stream, "case_begin", issues, name)
    finish = one(stream, "case_result", issues, name)
    fresh = one(stream, "rig_type_fresh_observation", issues, name)
    base = one(stream, "rig_type_baseline_result", issues, name)
    expected_params = parameters(case, config)
    for row in stream:
        if row.get("kind") != "blocked":
            require(issues, equal(row.get("parameters"), expected_params), name + ": case parameters differ")
    require(issues, stream and stream[0].get("kind") == "case_begin" and stream[-1].get("kind") == "case_result", name + ": case window unbracketed")
    for key in ("unparented_getter", "context_getter"):
        issues.extend(getter_issues(fresh.get(key), name + "/fresh/" + key))
    issues.extend(setter_issues(base.get("setter"), name + "/baseline/setter"))
    for key in ("getter_immediate", "getter_after_settle"):
        issues.extend(getter_issues(base.get(key), name + "/baseline/" + key, case["baseline"]))
    require(issues, obj(base.get("setter")).get("ok") is True and base.get("exact_tag_name_value_verified") is True, name + ": controlled baseline unavailable")
    issues.extend(wait_issues(base.get("settle_Heartbeat"), base.get("clock"), name + "/baseline/settle"))
    for key in ("setter_call_before", "setter_call_after"):
        issues.extend(clock_issues(base.get(key), name + "/baseline/" + key))
    require(issues, precedes(base.get("setter_call_before"), base.get("setter_call_after")) and precedes(base.get("setter_call_after"), obj(base.get("settle_Heartbeat")).get("before")), name + ": baseline setter/settle order differs")
    attempt = one(stream, "rig_type_setter_attempt", issues, name)
    returned = one(stream, "rig_type_setter_return", issues, name)
    observations = [row for row in stream if row.get("kind") == "rig_type_observation"]
    events = [row for row in stream if row.get("kind") == "rig_type_event"]
    require(issues, [row.get("point") for row in observations] == POINTS, name + ": four exact ordered observation points required")
    expected = expected_input(case)
    for row in (attempt, returned):
        issues.extend(tag_issues(row.get("input"), name + "/input"))
        require(issues, equal(row.get("input"), expected), name + ": own input tag does not match frozen construction")
    issues.extend(setter_issues(returned.get("setter"), name + "/target/setter"))
    issues.extend(getter_issues(returned.get("getter"), name + "/target/return_getter"))
    for key in ("setter_call_before", "setter_call_after"):
        issues.extend(clock_issues(returned.get(key), name + "/target/" + key))
    require(issues, precedes(attempt.get("clock"), returned.get("setter_call_before")) and precedes(returned.get("setter_call_before"), returned.get("setter_call_after")) and precedes(returned.get("setter_call_after"), returned.get("clock")), name + ": target setter clock bracket differs")
    point_rows = {row["point"]: row for row in observations if isinstance(row.get("point"), str)}
    seq_chain = [begin.get("seq"), fresh.get("seq"), base.get("seq"), obj(point_rows.get("before_setter")).get("seq"), attempt.get("seq"), returned.get("seq"), obj(point_rows.get("immediate_after_setter")).get("seq"), obj(point_rows.get("after_Heartbeat_1")).get("seq"), obj(point_rows.get("after_Heartbeat_2")).get("seq"), finish.get("seq")]
    require(issues, all(integer(seq, 1) for seq in seq_chain) and all(a < b for a, b in zip(seq_chain, seq_chain[1:])), name + ": source-defined case stages are out of order")
    counters = dict.fromkeys(COUNT_KEYS, 0)
    phase_limits = [attempt.get("seq", -1), returned.get("seq", -1), obj(point_rows.get("after_Heartbeat_1")).get("seq", -1), obj(point_rows.get("after_Heartbeat_2")).get("seq", -1)]
    for row in stream:
        label = f"{name}/seq{row.get('seq')}"
        if row.get("kind") == "rig_type_event":
            signal = row.get("signal")
            require(issues, signal in ("GetPropertyChangedSignal", "Changed"), label + ": unknown signal")
            issues.extend(tuple_issues(row.get("arguments"), label + "/arguments"))
            values = obj(row.get("arguments")).get("values")
            if signal == "GetPropertyChangedSignal":
                counters["property_changed"] += 1
            elif signal == "Changed":
                counters["changed_total"] += 1
                if isinstance(values, list) and values and equal(values[0], {"type": "string", "value": "RigType"}):
                    counters["changed_rig_type"] += 1
            issues.extend(getter_issues(row.get("getter"), label + "/event_getter"))
            if all(integer(value, 1) for value in phase_limits) and integer(row.get("seq"), 1):
                expected_phase = ("before_setter" if row["seq"] < phase_limits[0] else "setter_call" if row["seq"] < phase_limits[1] else "after_setter_return" if row["seq"] < phase_limits[2] else "after_Heartbeat_1" if row["seq"] < phase_limits[3] else "after_Heartbeat_2")
                require(issues, row.get("phase") == expected_phase, label + ": callback phase differs from source stage")
                if expected_phase == "setter_call":
                    require(issues, precedes(returned.get("setter_call_before"), row.get("clock")) and precedes(row.get("clock"), returned.get("setter_call_after")), label + ": callback outside setter call clocks")
        if row.get("kind") in ("rig_type_event", "rig_type_observation", "rig_type_setter_return"):
            issues.extend(counts_issues(row.get("counts"), counters, label))
    cap = obj(plan.get("limits")).get("recorded_events_per_case")
    require(issues, integer(cap) and len(events) <= cap, name + ": event cap exceeded/malformed")
    for row in observations:
        point = row.get("point")
        issues.extend(getter_issues(row.get("getter"), name + "/" + str(point), case["baseline"] if point == "before_setter" else None))
        require(issues, row.get("phase") == ("after_setter_return" if point == "immediate_after_setter" else point), name + ": observation phase differs")
        if point in ("after_Heartbeat_1", "after_Heartbeat_2"):
            issues.extend(wait_issues(row.get("Heartbeat_wait"), row.get("clock"), name + "/" + point))
        else:
            require(issues, "Heartbeat_wait" not in row, name + ": unexpected wait on immediate observation")
    require(issues, finish.get("status") == "OBSERVED" and finish.get("event_stream_truncated") is False and finish.get("setter_error_is_an_observation") is True and finish.get("no_physical_rig_claim") is True and finish.get("no_parity_pass_claim") is True, name + ": incomplete/blocked native case or scope tags missing")
    references = (equal(finish.get("baseline_seq"), base.get("seq")) and equal(finish.get("setter_attempt_seq"), attempt.get("seq")) and equal(finish.get("setter_return_seq"), returned.get("seq")) and equal(finish.get("observation_seqs"), [{"point": row.get("point"), "seq": row.get("seq")} for row in observations]) and equal(finish.get("event_seqs"), [row.get("seq") for row in events]))
    require(issues, references, name + ": result references omit/duplicate/misidentify source records")
    issues.extend(counts_issues(finish.get("final_counts"), counters, name + "/final_counts"))
    require(issues, type(finish.get("setter_ok")) is bool and finish.get("setter_ok") is obj(returned.get("setter")).get("ok"), name + ": setter success copy differs")
    return {"id": name, "ordinal": case["ordinal"], "parameters": expected_params, "status": "BLOCKED" if issues else "OBSERVED", "issues": issues,
            "fresh_observation": fresh, "baseline": base, "input": attempt.get("input"), "setter_return": returned,
            "observations": observations, "events": events, "final_counts": finish.get("final_counts"),
            "target_setter_status": finish.get("target_setter_status", "OBSERVED" if returned else "NOT_RUN")}


def analyze_rows(rows, observed, plan, raw_sha256, raw_bytes):
    issues = registration_issues(plan)
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        return {"status": "BLOCKED", "issues": issues + ["raw: record objects required"], "cases": []}
    plan = obj(plan)
    manifest = one(rows, "run_manifest", issues, "run")
    result = one(rows, "run_result", issues, "run")
    run_id = manifest.get("run_id")
    try: uuid.UUID(run_id)
    except (ValueError, TypeError, AttributeError): issues.append("run: invalid GUID")
    planned = plan.get("cases") if isinstance(plan.get("cases"), list) else []
    known_ids = {case["id"] for case in planned if isinstance(case, dict) and isinstance(case.get("id"), str)}
    previous_clock = None
    for index, row in enumerate(rows, 1):
        require(issues, type(row.get("schema")) is int and row["schema"] == 1 and type(row.get("seq")) is int and row["seq"] == index and row.get("run_id") == run_id and row.get("realm") == "server" and isinstance(row.get("kind"), str) and row["kind"] in KINDS, f"raw/{index}: schema/seq/GUID/realm/kind differs")
        issues.extend(clock_issues(row.get("clock"), f"raw/{index}"))
        if previous_clock is not None:
            require(issues, precedes(previous_clock, row.get("clock")), f"raw/{index}: clocks moved backwards")
        previous_clock = row.get("clock")
        if row.get("kind") not in ("run_manifest", "run_result"):
            require(issues, isinstance(row.get("case"), str) and row["case"] in known_ids, f"raw/{index}: unknown case ID")
    require(issues, bool(rows) and rows[0].get("kind") == "run_manifest" and rows[-1].get("kind") == "run_result" and manifest.get("case") == "startup", "run: manifest/startup/result do not bracket stream")
    require(issues, manifest.get("mode") == "rig_type_edges_a3" and equal(manifest.get("registration"), plan), "run: mode/frozen registration/source hashes differ")
    require(issues, isinstance(manifest.get("studio_version"), str) and bool(manifest.get("studio_version")), "run: native Studio version absent")
    try:
        stamp = datetime.fromisoformat(manifest.get("date_utc", "").replace("Z", "+00:00"))
        require(issues, stamp.utcoffset() is not None and stamp.utcoffset().total_seconds() == 0, "run: date is not UTC")
    except (ValueError, TypeError, AttributeError): issues.append("run: native UTC timestamp absent/malformed")
    config = obj(manifest.get("config"))
    sessions = plan.get("sessions", []) if isinstance(plan.get("sessions"), list) else []
    config_valid = sum(equal(config, session) for session in sessions) == 1
    require(issues, config_valid, "run: config/session split does not exactly match frozen registration")
    observed = obj(observed)
    require(issues, observed.get("status") == "OBSERVED" and observed.get("parser_issues") == [] and observed.get("run_id") == run_id and observed.get("raw_sha256") == raw_sha256 and equal(observed.get("raw_records"), len(rows)), "transport: parsed raw status/issues/identity/count differ")
    compressed = obj(observed.get("compressed_transport"))
    transport = obj(compressed.get("manifest"))
    require(issues, compressed.get("status") == "VERIFIED" and compressed.get("integrity_issues") == [] and all(equal(transport.get(k), v) for k, v in (("run_id", run_id), ("raw_sha256", raw_sha256), ("raw_bytes", raw_bytes), ("raw_records", len(rows)))), "transport: VERIFIED compressed manifest identity/bytes/count required")
    require(issues, equal(observed.get("run_result"), result), "transport: parsed run_result differs from raw")
    begins = [row for row in rows if row.get("kind") == "case_begin"]
    completed = [row for row in rows if row.get("kind") == "case_result"]
    planned_ids = [obj(case).get("id") for case in planned]
    require(issues, [row.get("case") for row in begins] == planned_ids and len(begins) == 144, "run: preregistered 144-case begin order differs")
    require(issues, [row.get("case") for row in completed] == planned_ids and len(completed) == 144, "run: preregistered 144-case result order differs")
    require(issues, result.get("status") == "OBSERVED" and equal(result.get("count"), 144) and equal(result.get("planned_cases"), 144) and equal(result.get("cases"), completed), "run: native completion/result copies differ or are BLOCKED")
    require(issues, equal(result.get("independent_play_sessions"), 1) and result.get("disposable_instances_are_not_independent_Play_sessions") is True and result.get("no_parity_pass_claim") is True and result.get("no_physical_rig_claim") is True, "run: independent-session/scope declarations differ")
    reasons = [row.get("reason") for row in rows if row.get("kind") == "blocked"]
    require(issues, equal(result.get("errors"), reasons) and reasons == [], "run: source blocked/errors recorded")
    cases = []
    if config_valid and not registration_issues(plan):
        for case in planned:
            stream = [row for row in rows if row.get("case") == case["id"] and row.get("kind") not in ("run_manifest", "run_result")]
            cases.append(analyze_case(stream, case, config, plan))
    blocked = sum(case["status"] == "BLOCKED" for case in cases)
    return {"schema": 1, "analysis_utc": datetime.now(timezone.utc).isoformat(), "status": "BLOCKED" if issues or blocked or len(cases) != 144 else "OBSERVED",
            "scope": "Fresh bare Humanoid scalar RigType getter/coercion/events only; no Player/skeleton/physical rig interpretation",
            "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED", "no_fit": True, "no_physical_rig_claim": True,
            "fixture_version": plan.get("fixture_version"), "registered_source_sha256": plan.get("fixture_source_sha256"),
            "run_id": run_id, "session_id": config.get("id"), "session_index": config.get("session_index"), "split": config.get("split"), "studio_version": manifest.get("studio_version"), "native_date_utc": manifest.get("date_utc"),
            "raw_sha256": raw_sha256, "raw_bytes": raw_bytes, "raw_records": len(rows), "issues": issues, "cases": cases,
            "counts": {"independent_Play_sessions": 1, "planned_scalar_cases": 144, "observed_scalar_cases": len(cases) - blocked, "blocked_scalar_cases": blocked, "scalar_instances_are_not_Play_repeats": True},
            "limitations": ["One Play is one independent repeat; require five distinct sessions separately per Studio version.", "Event order/counts/getter outcomes are observations, not expected native coercion behavior.", "Late callbacks beyond the two-Heartbeat window are not ruled out.", "Variable outcomes across five Plays require a separately preregistered >=10-Play extension before comparison or fitting.", "No Bobux parity, physical rig transformation or live-Player behavior is established."]}


def source_issues(plan):
    """Check only own frozen-source provenance; never start a native process."""
    issues = []
    source_dir = ROOT / "tools/roblox_character_experiments/rig_type_edges"
    paths = {source_dir / name: sha for name, sha in obj(plan.get("fixture_source_sha256")).items()}
    paths[source_dir / "build_place.py"] = plan.get("builder_sha256")
    paths[source_dir / "test_fixture.py"] = plan.get("source_test_sha256")
    transport = obj(plan.get("reused_transport"))
    for key in ("export", "parser"):
        path = transport.get(key)
        if isinstance(path, str): paths[ROOT / path] = transport.get(key + "_sha256")
        else: issues.append("source: transport path absent")
    for path, expected in paths.items():
        try: actual = digest(path)
        except OSError as error:
            issues.append(f"source: {path.name} unreadable: {error}")
            continue
        require(issues, isinstance(expected, str) and actual == expected, "source: frozen SHA256 differs for " + path.name)
    return issues


def outcome_signature(case):
    # Deliberately exclude timestamps/dt/record seq and independent split labels.
    # Keep every measured result, including error text, native event order/phase,
    # tuple arity/nil and getters; never normalize a surprising outcome away.
    fresh = obj(case.get("fresh_observation"))
    observed = {"fresh_getters": [fresh.get("unparented_getter"), fresh.get("context_getter")],
                "setter": obj(case.get("setter_return")).get("setter"),
                "getters": [obj(row).get("getter") for row in case.get("observations", [])],
                "events": [{key: obj(row).get(key) for key in ("signal", "phase", "arguments", "getter")} for row in case.get("events", [])],
                "final_counts": case.get("final_counts")}
    return hashlib.sha256(json.dumps(observed, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")).hexdigest()


def aggregate_reports(records, plan):
    """Only records already revalidated at load_report may enter the identity gate."""
    rejected = [{"analysis_path": row["analysis_path"], "issues": list(row["issues"])} for row in records if row["issues"]]
    eligible = [row for row in records if not row["issues"]]
    duplicates = {key: Counter(row["report"].get(key) for row in eligible) for key in ("run_id", "session_id", "raw_sha256")}
    accepted = []
    for row in eligible:
        report = row["report"]
        problems = [f"duplicate independent-Play identity: {key}" for key, counts in duplicates.items() if counts[report.get(key)] > 1]
        if problems:
            rejected.append({"analysis_path": row["analysis_path"], "issues": problems})
        else:
            accepted.append(row)
    versions = []
    grouped = defaultdict(list)
    for row in accepted: grouped[row["report"]["studio_version"]].append(row)
    planned_sessions = {row["id"]: row for row in plan["sessions"]}
    for version, inputs in sorted(grouped.items()):
        reports = [row["report"] for row in inputs]
        ids = {row["session_id"] for row in reports}
        complete = ids == set(planned_sessions) and len(reports) == 5
        signatures = defaultdict(lambda: defaultdict(list))
        for report in reports:
            for case in report["cases"]:
                signatures[case["id"]][outcome_signature(case)].append(report["session_id"])
        variations = [{"case_id": name, "distinct_outcomes": len(values),
                       "signatures": [{"sha256": sha, "sessions": sorted(ids)} for sha, ids in sorted(values.items())]}
                      for name, values in sorted(signatures.items()) if len(values) > 1]
        versions.append({"studio_version": version, "coverage_status": "OBSERVED" if complete else "BLOCKED_INCOMPLETE",
                         "observed_independent_Play_sessions": len(reports), "required_independent_Play_sessions": 5,
                         "train_sessions": sorted(row["session_id"] for row in reports if row["split"] == "train"),
                         "holdout_sessions": sorted(row["session_id"] for row in reports if row["split"] == "holdout"),
                         "not_run_session_ids": sorted(set(planned_sessions) - ids), "variable_case_outcomes": variations,
                         "separate_preregistered_10_Play_extension_required": complete and bool(variations),
                         "sessions": [{"session_id": row["report"]["session_id"], "run_id": row["report"]["run_id"], "raw_sha256": row["report"]["raw_sha256"],
                                       "analysis_path": row["analysis_path"], "analysis_sha256": row.get("analysis_sha256")} for row in inputs]})
    complete = len(versions) == 1 and versions[0]["coverage_status"] == "OBSERVED" and not rejected
    extension = any(version["separate_preregistered_10_Play_extension_required"] for version in versions)
    return {"schema": 1, "aggregate_utc": datetime.now(timezone.utc).isoformat(),
            "status": "BLOCKED_INPUT" if rejected else "BLOCKED_EXTENSION_REQUIRED" if extension else "OBSERVED" if complete else "BLOCKED_INCOMPLETE",
            "scope": "Five independent frozen bare-scalar Plays per Studio version only; versions never pooled",
            "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED", "no_fit": True, "no_physical_rig_claim": True,
            "registration_sha256": REGISTRATION_SHA256, "registered_source_sha256": plan["fixture_source_sha256"],
            "counts": {"submitted_reports": len(records), "observed_independent_Play_sessions": len(accepted), "required_Play_sessions_per_version": 5,
                       "observed_scalar_cases": len(accepted) * 144, "scalar_instances_are_not_Play_repeats": True},
            "input_issues": rejected, "versions": versions, "five_Play_matrix_complete": complete,
            "separate_preregistered_10_Play_extension_required": extension,
            "limitations": ["No native setter/getter/error/event outcome was presumed or fitted.", "Variable outcomes require a new preregistered >=10-Play extension; no adaptive rerun selection.",
                            "The two-Heartbeat event window does not exclude later callbacks.", "Only fresh bare Humanoids: no actual Player, physical rig conversion or Bobux parity claim."]}


def load_report(path, plan):
    record = {"analysis_path": str(path.resolve()), "analysis_sha256": None, "report": {}, "issues": []}
    try:
        report = read_json(path)
        if not isinstance(report, dict): raise ValueError("selected analysis JSON must be an object")
        if report.get("analyzer_source_sha256") != digest(Path(__file__)): raise ValueError("analysis source SHA256 differs")
        if report.get("registration_sha256") != REGISTRATION_SHA256: raise ValueError("analysis registration SHA256 differs")
        paths = obj(report.get("input_paths"))
        if digest(Path(paths["registration"])) != REGISTRATION_SHA256: raise ValueError("referenced registration bytes differ")
        rows, sha, size = load_raw(Path(paths["raw"]))
        fresh = analyze_rows(rows, read_json(Path(paths["observed"])), plan, sha, size)
        for key, value in fresh.items():
            if key != "analysis_utc" and not equal(report.get(key), value): record["issues"].append("report differs from raw reanalysis at " + key)
        if fresh["status"] != "OBSERVED": record["issues"].append("raw analysis is BLOCKED")
        record.update(report=report, analysis_sha256=digest(path))
    except (ValueError, TypeError, KeyError, AttributeError, OSError) as error:
        record["issues"].append(str(error))
    return record


def write_new(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    analyze = commands.add_parser("analyze")
    analyze.add_argument("raw", type=Path)
    analyze.add_argument("--observed", type=Path, required=True)
    combine = commands.add_parser("aggregate")
    combine.add_argument("--analyses", type=Path, nargs="+", required=True)
    for command in (analyze, combine):
        command.add_argument("--registration", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists(): raise SystemExit("Refusing to overwrite analysis/evidence")
    if digest(args.registration) != REGISTRATION_SHA256: raise SystemExit("Frozen registration bytes differ")
    plan = read_json(args.registration)
    provenance = source_issues(plan)
    if args.command == "analyze":
        rows, sha, size = load_raw(args.raw)
        report = analyze_rows(rows, read_json(args.observed), plan, sha, size)
        report["issues"].extend(provenance)
        if provenance: report["status"] = "BLOCKED"
        report["input_paths"] = {"raw": str(args.raw.resolve()), "observed": str(args.observed.resolve()), "registration": str(args.registration.resolve())}
    else:
        report = aggregate_reports([load_report(path, plan) for path in args.analyses], plan)
        if provenance:
            report["status"] = "BLOCKED_INPUT"
            report["input_issues"].append({"source_provenance": provenance})
    report.update(registration_sha256=REGISTRATION_SHA256, analyzer_source_sha256=digest(Path(__file__)))
    write_new(args.output, report)
    print(json.dumps({"output": str(args.output), "status": report["status"], "counts": report["counts"]}))
    raise SystemExit(0 if report["status"] == "OBSERVED" else 2)


if __name__ == "__main__": main()
