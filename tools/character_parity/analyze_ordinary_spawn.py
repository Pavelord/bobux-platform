"""Strict read-only A2 observation analysis; never fit or claim Bobux parity.

Inputs are one completed ordinary-spawn raw log, its transport observed report,
and the frozen preregistration. Output is always a new file. Native inheritance
outcomes are retained as observations; only experiment identity/completeness and
registered inputs/readiness are validated. Ten respawns never become ten joins.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import uuid

PREFIX = "CHARACTER_EXPERIMENT_JSON "
RAW_LIMIT = 32 * 1024 * 1024
RECORD_LIMIT = 20000
# Fixed numeric representation allowance (one microsecond), not a fitted
# scheduler tolerance. Late callbacks have no upper bound; an observation
# labelled +3s cannot instead come from the first millisecond after spawning.
AGE_NUMERIC_EPSILON_S = 1e-6
EXPECTED_POINTS = ("CharacterAdded_immediate", "first_PostSimulation", "after_0.25s", "after_1s", "after_3s")
CORE_FIELDS = {
    "starter_player": ("LoadCharacterAppearance", "LuaCharacterController", "AutoJumpEnabled", "CharacterWalkSpeed", "CharacterJumpPower", "CharacterJumpHeight", "CharacterUseJumpPower", "CharacterMaxSlopeAngle", "CharacterBreakJointsOnDeath", "CameraMinZoomDistance", "CameraMaxZoomDistance", "CameraMode"),
    "player_properties": ("AutoJumpEnabled", "CameraMinZoomDistance", "CameraMaxZoomDistance", "CameraMode"),
    "humanoid": ("Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "HipHeight", "MaxSlopeAngle", "AutoJumpEnabled", "AutoRotate", "BreakJointsOnDeath", "RequiresNeck", "RigType"),
}
BOOL_FIELDS = {"LoadCharacterAppearance", "AutoJumpEnabled", "CharacterUseJumpPower", "CharacterBreakJointsOnDeath", "UseJumpPower", "AutoRotate", "BreakJointsOnDeath", "RequiresNeck"}
ENUM_FIELDS = {"LuaCharacterController", "CameraMode", "RigType"}
# CameraMode / HumanoidRigType definition pairs from pinned creator-docs
# 031b2f91d3d47274c255f3ed5691c29f792c181d (creator_docs_api.json).
# CharacterControlMode is deliberately only the registered Legacy=1 item,
# confirmed by native getter observations; this is not its full enum catalog.
ENUM_VALUES = {
    "LuaCharacterController": ("CharacterControlMode", {"Legacy": 1}),
    "CameraMode": ("CameraMode", {"Classic": 0, "LockFirstPerson": 1}),
    "RigType": ("HumanoidRigType", {"R6": 0, "R15": 1}),
}


def equal(a, b):
    """JSON semantic equality with bool kept distinct from 0/1."""
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isfinite(a) and math.isfinite(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value)


def config_equal(actual, registered):
    """Allow only HttpService's known empty-map round trip at prejoin_values.

    JSONDecode({}) is an empty Luau table; JSONEncode then emits []. This is
    observed in native default profiles. Do not generalize [] == {} elsewhere
    or permit a nonempty registered setting map to disappear.
    """
    if not isinstance(actual, dict) or not isinstance(registered, dict) or actual.keys() != registered.keys():
        return False
    return all((key == "prejoin_values" and registered[key] == {} and actual[key] == [])
               or equal(actual[key], registered[key]) for key in actual)


def registration_equal(actual, registered):
    if not isinstance(actual, dict) or not isinstance(registered, dict) or actual.keys() != registered.keys():
        return False
    for key in actual:
        if key == "cases":
            a, b = actual[key], registered[key]
            if not isinstance(a, list) or not isinstance(b, list) or len(a) != len(b) or not all(config_equal(x, y) for x, y in zip(a, b)):
                return False
        elif not equal(actual[key], registered[key]):
            return False
    return True


def load_raw(path):
    if path.stat().st_size > RAW_LIMIT:
        raise ValueError("raw exceeds registered analysis 32 MiB cap")
    data = path.read_bytes()
    text = data.decode("utf-8", errors="strict")
    rows = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.startswith(PREFIX):
            raise ValueError(f"line {number}: not an anchored own raw marker")
        row = json.loads(line[len(PREFIX):])
        if not isinstance(row, dict):
            raise ValueError(f"line {number}: record is not an object")
        rows.append(row)
        if len(rows) > RECORD_LIMIT:
            raise ValueError("raw record count exceeds cap")
    return rows, hashlib.sha256(data).hexdigest(), len(data)


def property_issues(values, field_names, location):
    issues = []
    if not isinstance(values, dict):
        return [f"{location}: property dictionary absent"]
    for name in field_names:
        if name not in values:
            issues.append(f"{location}.{name}: telemetry missing")
            continue
        value = values[name]
        if isinstance(value, dict) and value.get("status") == "NOT_OBSERVABLE":
            issues.append(f"{location}.{name}: required public field NOT_OBSERVABLE ({value.get('reason')})")
        elif name in BOOL_FIELDS and type(value) is not bool:
            issues.append(f"{location}.{name}: expected an observed boolean, including false")
        elif name in ENUM_FIELDS:
            domain, items = ENUM_VALUES[name]
            if not (isinstance(value, dict) and value.get("type") == "EnumItem" and value.get("EnumType") == domain
                    and isinstance(value.get("Name"), str) and value["Name"] in items and numeric(value.get("Value"))
                    and equal(value["Value"], items[value["Name"]])):
                issues.append(f"{location}.{name}: canonical native EnumItem domain/name/value absent or inconsistent")
        elif name not in BOOL_FIELDS | ENUM_FIELDS and not numeric(value):
            issues.append(f"{location}.{name}: finite observed scalar absent")
        if name == "LoadCharacterAppearance" and value is not False:
            issues.append(f"{location}.{name}: fixed fixture appearance-disabled input changed")
    return issues


def sequence_issues(rows, run_id, realm):
    issues = []
    if not rows:
        return [f"{realm}: no telemetry"]
    for expected, row in enumerate(rows, 1):
        if type(row.get("seq")) is not int or row.get("seq") != expected:
            issues.append(f"{realm}: seq expected {expected}, found {row.get('seq')}")
        if row.get("run_id") != run_id:
            issues.append(f"{realm}: mixed/missing run_id")
        if row.get("realm") != realm:
            issues.append(f"{realm}: incorrect realm tag")
    return issues


def one(rows, kind, realm, issues):
    selected = [r for r in rows if r.get("kind") == kind]
    if len(selected) != 1:
        issues.append(f"{realm}: expected one {kind}, found {len(selected)}")
        return {}
    return selected[0]


def observed_delta(before, after):
    if not isinstance(before, dict) or not isinstance(after, dict):
        return {"status": "NOT_OBSERVABLE"}
    return {key: {"before": before.get(key), "after": after.get(key)}
            for key in sorted(before.keys() | after.keys()) if not equal(before.get(key), after.get(key))}


def setting_issues(actual, requested, tolerance, location):
    """Check experimental Starter inputs, never presumed inherited outputs."""
    if requested == []:  # Only called with a previously verified empty native mapping.
        requested = {}
    if not isinstance(actual, dict) or not isinstance(requested, dict):
        return [location + ": Starter input map unavailable"]
    issues = []
    for name, value in requested.items():
        observed = actual.get(name)
        matches = equal(observed, value)
        if numeric(value) and numeric(observed):
            matches = abs(value - observed) <= tolerance
        if not matches:
            issues.append(f"{location}.{name}: declared Starter input not observed")
    return issues


def analyze_rows(rows, observed, registration, raw_sha256, raw_bytes):
    issues, warnings = [], []
    manifest = one(rows, "run_manifest", "client", issues)
    result = one(rows, "run_result", "client", issues)
    run_id = manifest.get("run_id")
    try:
        uuid.UUID(run_id)
    except (ValueError, TypeError, AttributeError):
        issues.append("client: run_id is not a native GUID")
    issues.extend(sequence_issues(rows, run_id, "client"))
    if rows and (rows[0].get("kind") != "run_manifest" or rows[-1].get("kind") != "run_result"):
        issues.append("client: manifest/result do not bracket raw stream")
    if observed.get("raw_sha256") != raw_sha256 or observed.get("raw_records") != len(rows):
        issues.append("transport report raw SHA256/record count differs")
    if observed.get("run_id") != run_id:
        issues.append("transport report run_id differs")
    if observed.get("parser_issues"):
        issues.append("transport report contains parser issues")
    if observed.get("status") != "OBSERVED":
        issues.append("prior transport/native observed report is BLOCKED/incomplete")
    compressed = observed.get("compressed_transport")
    if not isinstance(compressed, dict) or compressed.get("status") != "VERIFIED" or compressed.get("integrity_issues") != []:
        issues.append("compressed transport is not verified")
    transport = compressed.get("manifest") if isinstance(compressed, dict) else None
    if not isinstance(transport, dict) or not all(equal(transport.get(key), value) for key, value in
            (("raw_sha256", raw_sha256), ("raw_records", len(rows)), ("raw_bytes", raw_bytes), ("run_id", run_id))):
        issues.append("compressed transport manifest missing or does not match actual raw identity/bytes/count")
    if registration.get("fixture_version", "").endswith("-v1"):
        issues.append("INVALID_SOURCE_FIXTURE v1: boolean-false serializer loss; v1 was not a valid native capture fixture")
    config = manifest.get("config", {})
    prereg_cases = registration.get("cases", [])
    matching = [c for c in prereg_cases if c.get("id") == config.get("id")]
    if len(matching) != 1 or not config_equal(config, matching[0]):
        issues.append("client: config/session ID does not exactly match one preregistered Play case")
    session_index = config.get("session_index")
    expected_split = "train" if type(session_index) is int and 1 <= session_index <= 3 else "holdout"
    if type(session_index) is not int or session_index not in range(1, 6) or config.get("split") != expected_split:
        issues.append("client: session_index/split not preregistered 1..3 train, 4..5 holdout")
    if manifest.get("mode") != "ordinary_spawn_a2" or not registration_equal(manifest.get("registration"), registration):
        issues.append("client: mode/frozen registration/source hashes differ")
    source_hashes = registration.get("fixture_source_sha256", {})
    if not source_hashes or any(not isinstance(v, str) or not re.fullmatch("[0-9a-f]{64}", v) for v in source_hashes.values()):
        issues.append("registration: missing/invalid fixture source SHA256")
    if tuple(registration.get("required_snapshot_points", [])) != EXPECTED_POINTS:
        issues.append("registration: required five observation points changed")
    server = [r["server"] for r in rows if r.get("kind") == "server_record" and isinstance(r.get("server"), dict)]
    issues.extend(sequence_issues(server, run_id, "server"))
    server_manifest = one(server, "run_manifest", "server", issues)
    server_result = one(server, "run_result", "server", issues)
    if not registration_equal(server_manifest.get("registration"), registration) or not config_equal(server_manifest.get("config"), config):
        issues.append("server: registration/source hashes/config differ from paired client")
    if server_manifest.get("studio_version") != manifest.get("studio_version"):
        issues.append("server/client Studio versions differ")
    if server_manifest.get("character_auto_loads") is not False:
        issues.append("server: CharacterAutoLoads was not false before controlled first load")
    joins = [r for r in server if r.get("kind") == "a2_player_join"]
    if len(joins) != 1 or joins[0].get("initial_join_event_observed") is not True or joins[0].get("attachment") != "PlayerAdded":
        issues.append("server: one actual initial PlayerAdded observation not available")
    attachment = one(rows, "a2_client_probe_attached", "client", issues)
    if attachment.get("character_already_present") is not False:
        issues.append("client: probe did not attach before first native Character")
    for realm, row in (("client", attachment), ("server", joins[0] if len(joins) == 1 else {})):
        for key in ("starter_player", "player_properties"):
            issues.extend(property_issues(row.get(key), CORE_FIELDS[key], f"{realm}/initial_join/{key}"))
    tolerance = registration.get("tolerances", {}).get("scalar_numeric_abs", 1e-6)
    if not numeric(tolerance) or tolerance < 0:
        issues.append("registration: invalid scalar_numeric_abs tolerance")
        tolerance = 1e-6
    if len(joins) == 1:
        issues.extend(setting_issues(joins[0].get("starter_player"), config.get("prejoin_values"), tolerance, "server/initial_join/StarterPlayer"))
    for realm, stream, outcome in (("client", rows, result), ("server", server, server_result)):
        if outcome.get("status") != "OBSERVED" or outcome.get("errors"):
            issues.append(f"{realm}: native run_result is BLOCKED/incomplete")
        if any(r.get("kind") == "blocked" for r in stream):
            issues.append(f"{realm}: source recorded blocked conditions")
        # Cover each own measured Starter/Player dictionary, including manifest,
        # join, load requests and the live mutation records, not just +3s rows.
        for row in stream:
            for key in ("starter_player", "player_properties"):
                if key in row:
                    issues.extend(property_issues(row[key], CORE_FIELDS[key], f"{realm}/seq{row.get('seq')}/{key}"))
    snapshots = {}
    for realm, stream in (("client", rows), ("server", server)):
        for row in stream:
            if row.get("kind") != "a2_ordinary_snapshot":
                continue
            key = (realm, row.get("token"), row.get("point"))
            if key in snapshots:
                issues.append(f"{realm}: duplicate snapshot {key[1:]}")
            snapshots[key] = row
    case_rows = [r for r in rows if r.get("kind") == "case_result"]
    case_by_id = {r.get("case"): r for r in case_rows}
    begins = [r for r in rows if r.get("kind") == "case_begin"]
    begin_by_id = {r.get("case"): r for r in begins}
    if len(case_rows) != 10 or len(case_by_id) != 10:
        issues.append("client: exactly ten distinct completed native generation cases required")
    if len(begins) != 10 or len(begin_by_id) != 10:
        issues.append("client: exactly ten distinct case_begin windows required")
    if result.get("count") != 10 or server_result.get("loaded_characters") != 10:
        issues.append("client/server completion counts do not confirm ten native loads")
    cases = []
    for index in range(1, 11):
        token = f"spawn_{index}"
        raw_case = case_by_id.get(token, {})
        local_issues = []
        actual_rigs = {}
        timing = {realm: {} for realm in ("client", "server")}
        for realm in ("client", "server"):
            for point in EXPECTED_POINTS:
                row = snapshots.get((realm, token, point))
                label = f"{realm}/{token}/{point}"
                if not row:
                    local_issues.append(label + ": missing snapshot")
                    continue
                if row.get("contamination", {}).get("status") != "OBSERVED_ABSENT":
                    local_issues.append(label + ": custom-character contamination not ruled out")
                local_issues.extend(property_issues(row.get("starter_player"), CORE_FIELDS["starter_player"], label + "/StarterPlayer"))
                local_issues.extend(property_issues(row.get("player_properties"), CORE_FIELDS["player_properties"], label + "/Player"))
                if type(row.get("character_generation")) is not int or row.get("character_generation") != index or row.get("current_character_same") is not True:
                    local_issues.append(label + ": generation/current Character mismatch")
                if "server_generation" in row and (type(row["server_generation"]) is not int or row["server_generation"] != index):
                    local_issues.append(label + ": observed replicated server generation mismatch")
                character = row.get("character", {})
                if not isinstance(character, dict):
                    local_issues.append(label + ": Character dictionary absent")
                    character = {}
                for flag in ("has_humanoid", "has_hrp", "has_animator", "has_animate"):
                    if type(character.get(flag)) is not bool:
                        local_issues.append(label + f": {flag} must be an observed boolean")
                # A missing early Humanoid is valid. Any enum that was present
                # must nevertheless retain its canonical native representation.
                early_humanoid = character.get("humanoid")
                if isinstance(early_humanoid, dict) and "RigType" in early_humanoid:
                    local_issues.extend(property_issues(early_humanoid, ("RigType",), label + "/Humanoid"))
                    rig_tag = early_humanoid["RigType"]
                    if not isinstance(rig_tag, dict) or character.get("actual_rig") != rig_tag.get("Name"):
                        local_issues.append(label + ": observed actual rig disagrees with its Humanoid RigType")
                requested_age = {"CharacterAdded_immediate": 0, "after_0.25s": .25, "after_1s": 1, "after_3s": 3}.get(point)
                if not equal(row.get("requested_age_s"), requested_age) or not numeric(row.get("actual_age_wall_s")) or row["actual_age_wall_s"] < 0:
                    local_issues.append(label + ": requested/actual observation timing metadata absent or inconsistent")
                elif requested_age is not None and row["actual_age_wall_s"] + AGE_NUMERIC_EPSILON_S < requested_age:
                    local_issues.append(label + ": actual age precedes the registered requested observation age")
                timing[realm][point] = {key: row.get(key) for key in ("requested_age_s", "actual_age_wall_s", "callback_dt_sim_s", "wall_s", "seq")}
                if point == "first_PostSimulation" and not (numeric(row.get("callback_dt_sim_s")) and row["callback_dt_sim_s"] >= 0):
                    local_issues.append(label + ": actual PostSimulation dt absent")
                if realm == "client" and not (begin_by_id.get(token, {}).get("seq", math.inf) < row.get("seq", -1) < raw_case.get("seq", -1)):
                    local_issues.append(label + ": snapshot outside measured case sequence window")
                if point != "after_3s":
                    continue  # Truthful early absence is allowed; do not require a ready Humanoid.
                if realm == "server":
                    requested_settings = config.get("prejoin_values") if index <= 5 else registration.get("post_join_values")
                    local_issues.extend(setting_issues(row.get("starter_player"), requested_settings, tolerance, label + "/StarterPlayer"))
                local_issues.extend(property_issues(character.get("humanoid"), CORE_FIELDS["humanoid"], label + "/Humanoid"))
                if character.get("has_humanoid") is not True or character.get("has_hrp") is not True:
                    local_issues.append(label + ": Humanoid/HRP not ready")
                health = character.get("humanoid", {}).get("Health")
                if not numeric(health) or health <= 0:
                    local_issues.append(label + ": Character not alive")
                actual_rigs[realm] = character.get("actual_rig")
                rig = character.get("humanoid", {}).get("RigType", {})
                expected_value = {"R6": 0, "R15": 1}.get(character.get("actual_rig"))
                if not isinstance(rig, dict) or rig.get("EnumType") != "HumanoidRigType" or rig.get("Name") != character.get("actual_rig") or rig.get("Value") != expected_value:
                    local_issues.append(label + ": actual RigType tag/name/value inconsistent")
                if realm == "client" and row.get("server_generation") != index:
                    local_issues.append(label + ": replicated server generation mismatch")
        if any(value != config.get("requested_rig") for value in actual_rigs.values()) or len(actual_rigs) != 2:
            local_issues.append("requested rig unavailable/mismatched; no custom fallback allowed")
        if type(raw_case.get("server_generation")) is not int or raw_case.get("server_generation") != index or type(raw_case.get("local_generation")) is not int or raw_case.get("local_generation") != index:
            local_issues.append("case_result: native generation IDs not 1..10")
        expected_params = {"rig": config.get("requested_rig"), "path": "NATIVE_DEFAULT", "split": config.get("split"),
                           "spawn_index": index, "phase": "prejoin_profile" if index <= 5 else "post_join_mutation"}
        for kind, row in (("case_begin", begin_by_id.get(token, {})), ("case_result", raw_case)):
            if not equal(row.get("parameters"), expected_params):
                local_issues.append(kind + ": rig/path/index/independent-join split/phase mismatch")
        if raw_case.get("actual_rig") != config.get("requested_rig"):
            local_issues.append("case_result: reported actual rig differs from registered requested rig")
        if raw_case.get("status") != "OBSERVED":
            local_issues.append("case_result: raw source status not OBSERVED")
        validations = [r for r in server if r.get("kind") == "a2_server_window_validation" and r.get("token") == token]
        if len(validations) != 1 or validations[0].get("status") != "OBSERVED" or type(validations[0].get("expected_generation")) is not int or validations[0].get("expected_generation") != index or validations[0].get("reasons"):
            local_issues.append("server: validated all-point/generation barrier missing or blocked")
        cases.append({"id": token, "analysis_status": "BLOCKED" if local_issues else "OBSERVED", "raw_result_status": raw_case.get("status"),
                      "phase": "prejoin_profile" if index <= 5 else "post_join_mutation", "actual_rigs": actual_rigs, "issues": local_issues,
                      "snapshot_timing_per_realm": timing,
                      "final_observed_properties": {realm: snapshots.get((realm, token, "after_3s"), {}) for realm in ("client", "server")}})
    mutation_rows = [r for r in server if r.get("kind") == "a2_starter_mutation"]
    expected_mutations = registration.get("post_join_values", {})
    if len(mutation_rows) != len(expected_mutations) or {r.get("property") for r in mutation_rows} != expected_mutations.keys():
        issues.append("server: StarterPlayer-only mutation fields incomplete/duplicated")
    for row in mutation_rows:
        if row.get("ok") is not True or not equal(row.get("requested"), expected_mutations.get(row.get("property"))):
            issues.append("server: declared StarterPlayer mutation not applied/does not match registration")
    before = snapshots.get(("server", "mutation", "live_before_StarterPlayer_mutation"), {})
    after = snapshots.get(("server", "mutation", "live_after_StarterPlayer_mutation"), {})
    live_mutation_issues = []
    for point, row in (("before", before), ("after", after)):
        label = f"server/live_{point}_StarterPlayer_mutation"
        if type(row.get("character_generation")) is not int or row.get("character_generation") != 5 or row.get("current_character_same") is not True:
            live_mutation_issues.append(label + ": live generation 5/current Character not confirmed")
        live_mutation_issues.extend(property_issues(row.get("player_properties"), CORE_FIELDS["player_properties"], label + "/Player"))
        character = row.get("character", {})
        if not isinstance(character, dict):
            character = {}
        humanoid = character.get("humanoid", {})
        live_mutation_issues.extend(property_issues(humanoid, CORE_FIELDS["humanoid"], label + "/Humanoid"))
        for flag in ("has_humanoid", "has_hrp", "has_animator", "has_animate"):
            if type(character.get(flag)) is not bool:
                live_mutation_issues.append(label + f": {flag} must be an observed boolean")
        health = humanoid.get("Health") if isinstance(humanoid, dict) else None
        if character.get("has_humanoid") is not True or character.get("has_hrp") is not True or not numeric(health) or health <= 0:
            live_mutation_issues.append(label + ": live Humanoid/HRP/alive readiness not confirmed")
        rig = humanoid.get("RigType", {}) if isinstance(humanoid, dict) else {}
        if not isinstance(rig, dict) or character.get("actual_rig") != config.get("requested_rig") or rig.get("Name") != character.get("actual_rig"):
            live_mutation_issues.append(label + ": live actual rig/RigType mismatch")
        if not isinstance(row.get("contamination"), dict) or row["contamination"].get("status") != "OBSERVED_ABSENT":
            live_mutation_issues.append(label + ": custom-character contamination not ruled out")
    bracket = [snapshots.get(("server", "spawn_5", "after_3s"), {}).get("seq"), before.get("seq"), after.get("seq"),
               snapshots.get(("server", "spawn_6", "CharacterAdded_immediate"), {}).get("seq")]
    if any(type(value) is not int for value in bracket) or any(a >= b for a, b in zip(bracket, bracket[1:])):
        live_mutation_issues.append("server: live mutation snapshots do not occur after generation 5 and before generation 6, in before/after order")
    issues.extend(live_mutation_issues)
    issues.extend(setting_issues(before.get("starter_player"), config.get("prejoin_values"), tolerance, "server/live_before_StarterPlayer_mutation/StarterPlayer"))
    issues.extend(setting_issues(after.get("starter_player"), expected_mutations, tolerance, "server/live_after_StarterPlayer_mutation/StarterPlayer"))
    lifecycle = {realm: [{k: row.get(k) for k in ("seq", "event", "character_generation", "token", "wall_s")} for row in stream if row.get("kind") == "a2_lifecycle"] for realm, stream in (("client", rows), ("server", server))}
    lifecycle_counts = {realm: dict(Counter(r.get("event") for r in events)) for realm, events in lifecycle.items()}
    for realm, counts in lifecycle_counts.items():
        if counts.get("CharacterAdded", 0) != 10:
            issues.append(f"{realm}: ten native CharacterAdded events not observed")
        added = [row for row in lifecycle[realm] if row.get("event") == "CharacterAdded"]
        if any(type(row.get("character_generation")) is not int or row["character_generation"] != index or row.get("token") != f"spawn_{index}"
               for index, row in enumerate(added, 1)):
            issues.append(f"{realm}: CharacterAdded generation/token stream is not spawn_1..spawn_10")
        removing = [row for row in lifecycle[realm] if row.get("event") == "CharacterRemoving"]
        if removing:
            expected_lifecycle = []
            for index in range(1, 11):
                if index > 1:
                    expected_lifecycle.append(["CharacterRemoving", index - 1])
                expected_lifecycle.append(["CharacterAdded", index])
            actual_lifecycle = [[row.get("event"), row.get("character_generation")] for row in lifecycle[realm] if row.get("event") in ("CharacterAdded", "CharacterRemoving")]
            if not equal(actual_lifecycle, expected_lifecycle):
                issues.append(f"{realm}: observed CharacterRemoving/Added generation order differs from native loads 1..10")
        else:
            warnings.append(f"{realm}: no CharacterRemoving event observed; retained as observation")
        if counts.get("CharacterAppearanceLoaded", 0) == 0:
            warnings.append(f"{realm}: CharacterAppearanceLoaded absent under LoadCharacterAppearance=false; retained as observation, not failure")
    blocked_cases = sum(c["analysis_status"] == "BLOCKED" for c in cases)
    return {"schema": 1, "scope": "One preregistered ordinary-spawn Play session; no Bobux implementation comparison", "analysis_utc": datetime.now(timezone.utc).isoformat(),
            "run_id": run_id, "session_id": config.get("id"), "session_index": session_index, "split_per_initial_join": config.get("split"),
            "studio_version": manifest.get("studio_version"), "native_date_utc": manifest.get("date_utc"), "fixture_version": registration.get("fixture_version"),
            "status": "BLOCKED" if issues or blocked_cases else "OBSERVED", "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED", "no_fit": True,
            "raw_sha256": raw_sha256, "raw_bytes": raw_bytes, "raw_records": len(rows), "source_hash_validation": "RAW_REGISTRATION_MATCH; use frozen place manifest for independent input-file provenance",
            "registered_source_sha256": source_hashes, "issues": issues, "warnings": warnings, "cases": cases,
            "manifest_normalization": "Only empty config.prejoin_values {} may round-trip as [] via native HttpService; other registration fields compared exactly",
            "timing_validation": {"minimum_age_numeric_epsilon_s": AGE_NUMERIC_EPSILON_S, "upper_callback_lateness_limit": None,
                                  "policy": "Fixed representation epsilon, not fitted native timing; requested delayed ages are lower bounds; actual callback dt must be finite and nonnegative"},
            "initial_join_observations": {"server_PlayerAdded": joins[0] if len(joins) == 1 else None, "client_probe_attachment": attachment},
            "counts": {"initial_join_sessions": 1, "native_generation_cases": len(case_rows), "observed_cases": 10 - blocked_cases, "blocked_cases": blocked_cases,
                       "required_points_per_realm_per_generation": 5, "native_respawns_do_not_increase_join_count": True},
            "lifecycle": lifecycle, "lifecycle_counts": lifecycle_counts,
            "live_generation5_after_StarterPlayer_mutation": ({"player_observed_changes": observed_delta(before.get("player_properties"), after.get("player_properties")),
                                                             "humanoid_observed_changes": observed_delta(before.get("character", {}).get("humanoid"), after.get("character", {}).get("humanoid"))}
                                                            if not live_mutation_issues else {"status": "NOT_OBSERVABLE", "issues": live_mutation_issues}),
            "limitations": ["Only one Play session; >=5 independent joins per requested rig/profile remain an aggregate requirement.",
                            "Server and client os.clock origins differ; event order is per realm, not frame-synchronized across realms.",
                            "Inheritance differences are native observations, not failures against a presumed expected value.",
                            "Rollout flags remain NOT_OBSERVABLE; no original script Source/assets/keyframes retained."]}


def write_report(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("--observed", type=Path, required=True)
    parser.add_argument("--registration", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Refusing to overwrite analysis/evidence; use a fresh output path")
    rows, digest, size = load_raw(args.raw)
    observed = json.loads(args.observed.read_text(encoding="utf-8"))
    registration = json.loads(args.registration.read_text(encoding="utf-8"))
    report = analyze_rows(rows, observed, registration, digest, size)
    report["input_paths"] = {"raw": str(args.raw.resolve()), "observed": str(args.observed.resolve()), "registration": str(args.registration.resolve())}
    report["registration_sha256"] = hashlib.sha256(args.registration.read_bytes()).hexdigest()
    report["analyzer_source_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    write_report(args.output, report)
    print(json.dumps({"output": str(args.output), "status": report["status"], "counts": report["counts"], "parity_status": report["parity_status"]}, ensure_ascii=True))
    raise SystemExit(0 if report["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
