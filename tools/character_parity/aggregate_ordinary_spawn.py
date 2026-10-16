"""Read-only coverage aggregate for the frozen ordinary-spawn v2 experiment.

Supply explicit reviewed analysis paths, never a glob of superseded reports.
Each input is revalidated against its raw/observed files with the frozen analyzer.
Independent joins are unique run/session/raw identities, never respawn counts.
This utility does not fit parameters or establish Bobux parity.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

HERE = Path(__file__).resolve().parent
ANALYZER = HERE / "analyze_ordinary_spawn.py"
EXPECTED_ANALYZER_SHA256 = "7d495e79f439fd70bdd471af49e2c82017536d41130206fde480c337a7e2dfc1"
EXPECTED_REGISTRATION_SHA256 = "b2f02492b81644565aed45b7d4fb6798318457b7d995a12197807e132a7dd273"
spec = importlib.util.spec_from_file_location("ordinary_spawn_frozen_validator", ANALYZER)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    if path.stat().st_size > validator.RAW_LIMIT:
        raise ValueError("JSON exceeds 32 MiB analysis cap")
    return json.loads(path.read_text(encoding="utf-8"))


def read_analysis(path, registration, registration_sha):
    """Recompute input findings; an edited report is not sufficient evidence."""
    record = {"analysis_path": str(path.resolve()), "analysis_sha256": None, "analysis": {}, "issues": []}
    try:
        analysis = read_json(path)
        if not isinstance(analysis, dict):
            raise ValueError("selected analysis JSON must be an object")
        record.update(analysis=analysis, analysis_sha256=sha256(path))
        if sha256(ANALYZER) != EXPECTED_ANALYZER_SHA256:
            raise ValueError("frozen analyzer source SHA256 changed")
        if analysis.get("analyzer_source_sha256") != EXPECTED_ANALYZER_SHA256:
            raise ValueError("report was not produced by the reviewed frozen analyzer")
        if registration_sha != EXPECTED_REGISTRATION_SHA256 or analysis.get("registration_sha256") != registration_sha:
            raise ValueError("frozen preregistration SHA256 differs")
        paths = analysis.get("input_paths", {})
        if sha256(Path(paths["registration"])) != registration_sha:
            raise ValueError("report's referenced registration bytes differ")
        rows, digest, size = validator.load_raw(Path(paths["raw"]))
        observed = read_json(Path(paths["observed"]))
        rerun = validator.analyze_rows(rows, observed, registration, digest, size)
        for key, value in rerun.items():
            if key != "analysis_utc" and not validator.equal(analysis.get(key), value):
                record["issues"].append("report differs from frozen raw reanalysis at " + key)
        if rerun["status"] != "OBSERVED":
            record["issues"].append("raw reanalysis is BLOCKED; not a valid independent observed join")
        uuid.UUID(analysis.get("run_id"))
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        record["issues"].append(str(error))
    return record


def validate_matrix(registration):
    cases = registration.get("cases", [])
    expected = {(rig, profile, index) for rig in ("R6", "R15") for profile in ("default", "altered") for index in range(1, 6)}
    actual = {(case.get("requested_rig"), case.get("profile"), case.get("session_index")) for case in cases}
    if len(cases) != 20 or actual != expected or len({case.get("id") for case in cases}) != 20:
        raise ValueError("frozen v2 matrix must contain 20 distinct rig/profile/Play configurations")
    for case in cases:
        index = case["session_index"]
        if type(index) is not int or case.get("split") != ("train" if index <= 3 else "holdout") or case.get("path") != "NATIVE_DEFAULT":
            raise ValueError("frozen v2 case index/path/train-holdout assignment is invalid")
    return {case["id"]: case for case in cases}


def assemble(registration, registration_sha, records):
    configs = validate_matrix(registration)
    # A rejected explicit file has no trusted analysis schema or identity. Keep
    # its path/diagnostic, but do not dereference its hash/group/count payload.
    verified_records = [record for record in records if not record["issues"]]
    input_issues = [{"analysis_path": record["analysis_path"], "issues": list(record["issues"])}
                    for record in records if record["issues"]]
    # Reject every member of a duplicate identity set. Never choose a favourable
    # rerun/report or silently deduplicate superseded reports into a success.
    duplicates = {key: Counter(record["analysis"].get(key) for record in verified_records if record["analysis"].get(key))
                  for key in ("run_id", "session_id", "raw_sha256")}
    grouped = defaultdict(list)
    for record in verified_records:
        report = record["analysis"]
        issues = list(record["issues"])
        config = configs.get(report.get("session_id"))
        if config is None:
            issues.append("session ID is not a preregistered Play configuration")
        else:
            if report.get("session_index") != config["session_index"] or report.get("split_per_initial_join") != config["split"]:
                issues.append("initial-join session index/split differs from preregistration")
            for case in report.get("cases", []):
                if case.get("actual_rigs") != {"client": config["requested_rig"], "server": config["requested_rig"]}:
                    issues.append("one native generation has an unavailable/mismatched actual rig")
        for key, counts in duplicates.items():
            if counts.get(report.get(key), 0) > 1:
                issues.append("duplicate independent-capture identity: " + key)
        if report.get("status") != "OBSERVED" or report.get("parity_status") != "NOT_IMPLEMENTED_NOT_CALIBRATED" or report.get("no_fit") is not True:
            issues.append("input is not an observed, unfitted native session")
        if report.get("counts", {}).get("initial_join_sessions") != 1 or report.get("counts", {}).get("observed_cases") != 10:
            issues.append("input does not represent exactly one join and ten valid native generation cases")
        item = {"analysis_path": record["analysis_path"], "analysis_sha256": record["analysis_sha256"],
                "session_id": report.get("session_id"), "run_id": report.get("run_id"), "raw_sha256": report.get("raw_sha256"),
                "studio_version": report.get("studio_version"), "native_date_utc": report.get("native_date_utc"),
                "session_index": report.get("session_index"), "split": report.get("split_per_initial_join"),
                "input_status": "BLOCKED" if issues else "VERIFIED_OBSERVED", "issues": issues}
        if issues:
            input_issues.append({"analysis_path": record["analysis_path"], "issues": issues})
        if config:
            grouped[(config["requested_rig"], config["profile"])].append(item)
    groups = []
    valid_total = complete_groups = 0
    for rig in ("R6", "R15"):
        for profile in ("default", "altered"):
            planned = sorted((c for c in configs.values() if c["requested_rig"] == rig and c["profile"] == profile), key=lambda c: c["session_index"])
            submitted = grouped[(rig, profile)]
            valid = [item for item in submitted if item["input_status"] == "VERIFIED_OBSERVED"]
            versions = sorted({item["studio_version"] for item in valid})
            complete = len(valid) == 5 and len(versions) == 1
            status = "OBSERVED" if complete else ("BLOCKED_INCOMPLETE" if submitted else "NOT_RUN")
            if len(versions) > 1:
                status = "BLOCKED_MIXED_STUDIO_VERSIONS"
            complete_groups += int(complete)
            valid_total += len(valid)
            submitted_ids = {item["session_id"] for item in submitted}
            groups.append({"requested_rig": rig, "profile": profile, "path": "NATIVE_DEFAULT", "status": status,
                           "required_independent_joins": 5, "observed_independent_joins": len(valid),
                           "observed_train_joins": sum(item["split"] == "train" for item in valid),
                           "observed_holdout_joins": sum(item["split"] == "holdout" for item in valid),
                           "observed_studio_versions": versions, "studio_versions_are_not_pooled": True,
                           "blocked_session_ids": sorted({item["session_id"] for item in submitted if item["input_status"] == "BLOCKED"}),
                           "not_run_session_ids": [c["id"] for c in planned if c["id"] not in submitted_ids],
                           "sessions": sorted(submitted, key=lambda item: item["session_index"])})
    complete = complete_groups == 4 and not input_issues
    return {"schema": 1, "aggregate_utc": datetime.now(timezone.utc).isoformat(),
            "scope": "Frozen ordinary-spawn v2 NATIVE_DEFAULT coverage only; no Bobux comparison or parameter fitting",
            "status": "BLOCKED_INPUT" if input_issues else ("OBSERVED" if complete else "BLOCKED_INCOMPLETE"),
            "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED", "no_fit": True,
            "fixture_version": registration.get("fixture_version"), "registration_sha256": registration_sha,
            "analyzer_source_sha256": EXPECTED_ANALYZER_SHA256, "registered_source_sha256": registration.get("fixture_source_sha256"),
            "native_default_matrix_complete": complete, "full_A2_complete": False,
            "counts": {"submitted_analysis_files": len(records), "observed_independent_joins": valid_total,
                       "required_independent_joins": 20, "observed_native_generations": valid_total * 10,
                       "complete_groups": complete_groups, "required_groups": 4, "respawns_are_not_independent_joins": True},
            "input_issues": input_issues, "groups": groups,
            "limitations": ["Only explicitly supplied, raw-revalidated reports count; no filename, assumed rig or missing session is substituted.",
                            "Five valid independent Play sessions are required separately for each registered rig/profile; train 1..3 and holdout 4..5 stay identified.",
                            "Holdout data are observations only; no model, threshold, inheritance output or callback tolerance is fitted.",
                            "Different Studio versions are shown separately and cannot complete a group by pooling.",
                            "NATIVE_DESCRIPTION remains NOT_RUN/NOT_IMPLEMENTED in this v2 first slice; even all 20 v2 sessions do not complete full A2 or character parity."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registration", type=Path, required=True)
    parser.add_argument("--analyses", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Refusing to overwrite an existing aggregate/evidence file")
    digest = sha256(args.registration)
    if digest != EXPECTED_REGISTRATION_SHA256 or sha256(ANALYZER) != EXPECTED_ANALYZER_SHA256:
        raise SystemExit("Frozen registration/analyzer bytes differ; do not mix experiment versions")
    registration = read_json(args.registration)
    records = [read_analysis(path, registration, digest) for path in args.analyses]
    report = assemble(registration, digest, records)
    report["aggregate_source_sha256"] = sha256(Path(__file__))
    report["registration_path"] = str(args.registration.resolve())
    validator.write_report(args.output, report)
    print(json.dumps({"output": str(args.output), "status": report["status"], "counts": report["counts"]}))
    raise SystemExit(2 if report["input_issues"] else 0)


if __name__ == "__main__":
    main()
