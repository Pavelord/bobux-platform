"""Own synthetic telemetry only; never read the new native RigType captures."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rig_type_validator", HERE / "analyze_rig_type_edges.py")
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
PLAN_PATH = HERE.parents[1] / "tools/roblox_character_experiments/rig_type_edges/frozen_v1/registration.json"
PLAN = analyzer.read_json(PLAN_PATH)
RAW_SIZE = 123456


def getter(name):
    return {"ok": True, "value": analyzer.enum_tag("HumanoidRigType", name, {"R6": 0, "R15": 1}[name])}


def synthetic(session=1, version="SYNTHETIC_NOT_NATIVE_STUDIO", changed_case=False, timer_scale=1):
    """Input construction follows own source; outcomes deliberately do not.

    Some synthetic failed setters change the getter; some successful setters
    do not reach the nominal target; fresh defaults are R15. Signals deliberately
    have nonstandard arity/order. A validator must not encode a coercion model.
    """
    config = copy.deepcopy(PLAN["sessions"][session - 1])
    run = f"00000000-0000-4000-8000-{session:012d}"
    rows, results = [], []
    wall, hb, simulated, lastdt = 0., 0, 0., 0.
    active = "startup"

    def clock():
        nonlocal wall
        wall += .001 * timer_scale
        return {"wall_s": wall, "heartbeat_index": hb, "heartbeat_sim_elapsed_s": simulated, "last_heartbeat_dt_sim_s": lastdt}

    def wait():
        nonlocal hb, simulated, lastdt
        before = clock()
        hb += 1
        lastdt = (.017 if hb % 2 else .023) * timer_scale
        simulated += lastdt
        return {"before": before, "after": clock(), "wait_callback_dt_sim_s": lastdt}

    def emit(kind, **values):
        row = dict(values, kind=kind, schema=1, run_id=run, seq=len(rows) + 1, realm="server", case=active, clock=clock())
        rows.append(row)
        return row

    emit("run_manifest", mode="rig_type_edges_a3", studio_version=version, date_utc="2026-10-17T01:00:00Z", config=config, registration=copy.deepcopy(PLAN))
    for case in PLAN["cases"]:
        active = case["id"]
        params = analyzer.parameters(case, config)
        emit("case_begin", parameters=copy.deepcopy(params))
        emit("rig_type_fresh_observation", parameters=copy.deepcopy(params), unparented_getter=getter("R15"), context_getter=getter("R15"))
        call_before, call_after = clock(), clock()
        baseline = emit("rig_type_baseline_result", parameters=copy.deepcopy(params), setter={"ok": True, "returns": {"count": 0, "values": []}},
                        setter_call_before=call_before, setter_call_after=call_after, getter_immediate=getter(case["baseline"]),
                        getter_after_settle=getter(case["baseline"]), settle_Heartbeat=wait(), exact_tag_name_value_verified=True)
        counts = dict.fromkeys(analyzer.COUNT_KEYS, 0)
        observations, events = [], []

        def observe(point, name, phase, payload=None):
            data = {"parameters": copy.deepcopy(params), "point": point, "phase": phase, "getter": getter(name), "counts": counts.copy()}
            if payload is not None: data["Heartbeat_wait"] = payload
            row = emit("rig_type_observation", **data)
            observations.append({"point": point, "seq": row["seq"]})

        observe("before_setter", case["baseline"], "before_setter")
        argument = analyzer.expected_input(case)
        attempt = emit("rig_type_setter_attempt", parameters=copy.deepcopy(params), input=copy.deepcopy(argument))
        call_before = clock()
        outcome = "R15" if case["ordinal"] % 2 else "R6"
        if changed_case and case["ordinal"] == 1:
            outcome = "R6" if outcome == "R15" else "R15"
        if case["ordinal"] % 4:
            for signal, values in (("Changed", [{"type": "string", "value": "RigType"}, {"type": "boolean", "value": False}, {"type": "nil", "is_nil": True}]),
                                   ("GetPropertyChangedSignal", [{"type": "nil", "is_nil": True}, {"type": "boolean", "value": False}]),
                                   ("Changed", [{"type": "string", "value": "Health"}])):
                if signal == "GetPropertyChangedSignal":
                    counts["property_changed"] += 1
                else:
                    counts["changed_total"] += 1
                    if values[0] == {"type": "string", "value": "RigType"}: counts["changed_rig_type"] += 1
                row = emit("rig_type_event", parameters=copy.deepcopy(params), signal=signal, phase="setter_call",
                           arguments={"count": len(values), "values": copy.deepcopy(values)}, getter=getter(outcome), counts=counts.copy())
                events.append(row["seq"])
        call_after = clock()
        setter = ({"ok": False, "error": "synthetic outcome, no native behavior encoded"} if case["ordinal"] % 3 == 0
                  else {"ok": True, "returns": {"count": 0, "values": []}})
        returned = emit("rig_type_setter_return", parameters=copy.deepcopy(params), input=copy.deepcopy(argument), setter=setter,
                        setter_call_before=call_before, setter_call_after=call_after, counts=counts.copy(), getter=getter(outcome))
        observe("immediate_after_setter", outcome, "after_setter_return")
        for index in (1, 2):
            observe(f"after_Heartbeat_{index}", outcome, f"after_Heartbeat_{index}", wait())
        result = emit("case_result", status="OBSERVED", parameters=copy.deepcopy(params), baseline_seq=baseline["seq"], setter_attempt_seq=attempt["seq"],
                      setter_return_seq=returned["seq"], observation_seqs=observations, event_seqs=events, final_counts=counts.copy(),
                      setter_ok=setter["ok"], setter_error_is_an_observation=True, event_stream_truncated=False, no_physical_rig_claim=True, no_parity_pass_claim=True)
        results.append(copy.deepcopy(result))
    emit("run_result", status="OBSERVED", reason="synthetic source-schema example only", count=144, planned_cases=144,
         errors=[], cases=results, independent_play_sessions=1, disposable_instances_are_not_independent_Play_sessions=True,
         no_parity_pass_claim=True, no_physical_rig_claim=True)
    return rows, observed_for(rows)


def observed_for(rows):
    sha = hashlib.sha256(json.dumps(rows, sort_keys=True, allow_nan=False).encode()).hexdigest()
    run = rows[0]["run_id"]
    return {"status": "OBSERVED", "parser_issues": [], "run_id": run, "raw_sha256": sha, "raw_records": len(rows), "run_result": copy.deepcopy(rows[-1]),
            "compressed_transport": {"status": "VERIFIED", "integrity_issues": [],
                                     "manifest": {"run_id": run, "raw_sha256": sha, "raw_records": len(rows), "raw_bytes": RAW_SIZE}}}


def check(rows, observed=None):
    if observed is None:
        # Keep mirrored result copies valid so mutations exercise their actual
        # field validator, not merely a stale run_result copy.
        rows[-1]["cases"] = copy.deepcopy([row for row in rows if row.get("kind") == "case_result"])
        observed = observed_for(rows)
    return analyzer.analyze_rows(rows, observed, PLAN, observed["raw_sha256"], RAW_SIZE)


def selected(rows, kind, ordinal=1):
    name = PLAN["cases"][ordinal - 1]["id"]
    return next(row for row in rows if row.get("case") == name and row.get("kind") == kind)


class RigTypeValidator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if analyzer.digest(PLAN_PATH) != analyzer.REGISTRATION_SHA256: raise AssertionError("frozen registration changed")
        cls.rows, cls.observed = synthetic()

    def test_schema_allows_unexpected_native_outcomes_without_a_coercion_model(self):
        report = check(copy.deepcopy(self.rows))
        self.assertEqual(report["status"], "OBSERVED", report["issues"][:3] + report["cases"][0]["issues"])
        self.assertEqual(report["counts"]["independent_Play_sessions"], 1)
        self.assertEqual(report["counts"]["observed_scalar_cases"], 144)
        self.assertEqual(report["cases"][0]["fresh_observation"]["unparented_getter"], getter("R15"))
        self.assertTrue(any(case["setter_return"]["setter"]["ok"] is False for case in report["cases"]))
        self.assertEqual(report["parity_status"], "NOT_IMPLEMENTED_NOT_CALIBRATED")
        self.assertTrue(report["no_fit"] and report["no_physical_rig_claim"])

    def test_required_transport_guid_schema_and_source_hashes(self):
        for mutation in ("transport", "manifest", "guid", "seq_bool", "source", "split"):
            with self.subTest(mutation=mutation):
                rows = copy.deepcopy(self.rows)
                observed = copy.deepcopy(self.observed)
                if mutation == "transport": observed["compressed_transport"] = {}
                elif mutation == "manifest": del observed["compressed_transport"]["manifest"]["raw_bytes"]
                elif mutation == "guid": rows[5]["run_id"] = "not-the-run"
                elif mutation == "seq_bool": rows[0]["seq"] = True
                elif mutation == "source": rows[0]["registration"]["fixture_source_sha256"]["common.luau"] = "0" * 64
                elif mutation == "split": rows[0]["config"]["split"] = "holdout"
                self.assertEqual(check(rows, observed)["status"], "BLOCKED")

    def test_counts_null_and_unhashable_metadata_are_blocked_without_crash(self):
        for field, value in (("counts", None), ("getter", []), ("parameters", [])):
            with self.subTest(field=field):
                rows = copy.deepcopy(self.rows)
                selected(rows, "rig_type_setter_return")[field] = value
                report = check(rows)
                self.assertEqual(report["cases"][0]["status"], "BLOCKED")
        rows = copy.deepcopy(self.rows)
        rows[0]["kind"] = []
        self.assertEqual(check(rows)["status"], "BLOCKED")

    def test_each_controlled_baseline_getter_is_exact(self):
        for field in ("getter_immediate", "getter_after_settle"):
            rows = copy.deepcopy(self.rows)
            baseline = selected(rows, "rig_type_baseline_result")
            baseline[field] = getter("R15" if PLAN["cases"][0]["baseline"] == "R6" else "R6")
            self.assertEqual(check(rows)["cases"][0]["status"], "BLOCKED")

    def test_all_four_points_and_result_seq_references_are_required(self):
        for variant in ("point", "event_ref", "observation_ref", "baseline_ref"):
            rows = copy.deepcopy(self.rows)
            result = selected(rows, "case_result")
            if variant == "point": selected(rows, "rig_type_observation")["point"] = "after_Heartbeat_2"
            elif variant == "event_ref": result["event_seqs"] = []
            elif variant == "observation_ref": result["observation_seqs"][0]["seq"] = 99999
            else: result["baseline_seq"] = True
            self.assertEqual(check(rows)["cases"][0]["status"], "BLOCKED")

    def test_false_nil_and_nonfinite_inputs_keep_exact_tags(self):
        variants = {"boolean_false": {"type": "number", "value": 0},
                    "nil": {"type": "nil", "is_nil": 1}, "nan": {"type": "number", "value": 0},
                    "positive_inf": {"type": "number", "special": "negative_inf"}}
        for variant, bad in variants.items():
            rows = copy.deepcopy(self.rows)
            case = next(case for case in PLAN["cases"] if case["variant"] == variant)
            selected(rows, "rig_type_setter_attempt", case["ordinal"])["input"] = bad
            self.assertEqual(check(rows)["cases"][case["ordinal"] - 1]["status"], "BLOCKED")

    def test_event_counts_arity_phase_and_getter_are_not_accepted_on_trust(self):
        for mutation in ("counts", "arity", "phase", "getter"):
            rows = copy.deepcopy(self.rows)
            event = selected(rows, "rig_type_event")
            if mutation == "counts": event["counts"]["changed_total"] += 1
            elif mutation == "arity": event["arguments"]["count"] += 1
            elif mutation == "phase": event["phase"] = "after_Heartbeat_2"
            else: event["getter"] = {"ok": False, "status": "NOT_OBSERVABLE", "reason": "missing"}
            self.assertEqual(check(rows)["cases"][0]["status"], "BLOCKED")

    def test_failed_setter_is_an_observation_but_its_ok_and_error_shapes_are_strict(self):
        for bad in ({"ok": 0, "error": "synthetic"}, {"ok": False}, {"ok": True, "returns": {"count": 1, "values": [{"type": "nil", "is_nil": True}]}}):
            rows = copy.deepcopy(self.rows)
            selected(rows, "rig_type_setter_return")["setter"] = bad
            self.assertEqual(check(rows)["cases"][0]["status"], "BLOCKED")

    def test_required_wait_clocks_and_finite_dt_are_checked(self):
        for value in (-1, float("inf"), False, None):
            rows = copy.deepcopy(self.rows)
            baseline = selected(rows, "rig_type_baseline_result")
            baseline["settle_Heartbeat"]["wait_callback_dt_sim_s"] = value
            # No serialization is performed for this malformed in-memory case.
            report = analyzer.analyze_rows(rows, self.observed, PLAN, self.observed["raw_sha256"], RAW_SIZE)
            self.assertEqual(report["cases"][0]["status"], "BLOCKED")
        rows = copy.deepcopy(self.rows)
        selected(rows, "rig_type_setter_return")["setter_call_before"]["wall_s"] = 999999
        self.assertEqual(check(rows)["cases"][0]["status"], "BLOCKED")

    def test_strict_json_and_writer_preserve_existing_evidence(self):
        for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}'):
            with self.assertRaises(ValueError): analyzer.strict_json(raw)
        with tempfile.TemporaryDirectory(prefix="rig-edges-analysis-test-") as directory:
            path = Path(directory) / "report.json"
            analyzer.write_new(path, {"original": True})
            with self.assertRaises(FileExistsError): analyzer.write_new(path, {"replacement": True})
            self.assertEqual(json.loads(path.read_text()), {"original": True})

    def test_frozen_own_source_provenance_without_running_any_native_process(self):
        self.assertEqual(analyzer.source_issues(PLAN), [])
        bad = copy.deepcopy(PLAN)
        bad["fixture_source_sha256"]["common.luau"] = "0" * 64
        self.assertTrue(any("common.luau" in issue for issue in analyzer.source_issues(bad)))

    def test_public_report_loader_rejects_malformed_payload_before_grouping(self):
        # Create only our synthetic files in a temporary directory. No native
        # capture file or directory is opened by this test.
        rows = copy.deepcopy(self.rows)
        with tempfile.TemporaryDirectory(prefix="rig-edges-loader-test-") as directory:
            folder = Path(directory)
            raw_path, observed_path = folder / "synthetic.raw.log", folder / "synthetic.observed.json"
            data = "".join(analyzer.PREFIX + json.dumps(row, allow_nan=False) + "\n" for row in rows).encode()
            raw_path.write_bytes(data)
            sha, size = hashlib.sha256(data).hexdigest(), len(data)
            observed = observed_for(rows)
            observed["raw_sha256"] = sha
            observed["compressed_transport"]["manifest"].update(raw_sha256=sha, raw_bytes=size)
            observed_path.write_text(json.dumps(observed), encoding="utf-8")
            report = analyzer.analyze_rows(rows, observed, PLAN, sha, size)
            self.assertEqual(report["status"], "OBSERVED")
            report.update(registration_sha256=analyzer.REGISTRATION_SHA256, analyzer_source_sha256=analyzer.digest(HERE / "analyze_rig_type_edges.py"),
                          input_paths={"raw": str(raw_path), "observed": str(observed_path), "registration": str(PLAN_PATH)})
            valid_path = folder / "synthetic.analysis.json"
            analyzer.write_new(valid_path, report)
            valid = analyzer.load_report(valid_path, PLAN)
            self.assertEqual(valid["issues"], [])
            for index, (key, value) in enumerate((("counts", None), ("cases", None), ("run_id", []), ("session_id", []), ("raw_sha256", []))):
                with self.subTest(key=key):
                    bad = copy.deepcopy(report)
                    bad[key] = value
                    path = folder / f"invalid-{index}.json"
                    analyzer.write_new(path, bad)
                    record = analyzer.load_report(path, PLAN)
                    self.assertTrue(record["issues"])
                    grouped = analyzer.aggregate_reports([record], PLAN)
                    self.assertEqual(grouped["status"], "BLOCKED_INPUT")
                    self.assertEqual(grouped["counts"]["observed_independent_Play_sessions"], 0)
                    self.assertEqual(grouped["input_issues"][0]["analysis_path"], str(path.resolve()))
            for index, value in enumerate(([], None)):
                path = folder / f"nonobject-{index}.json"
                analyzer.write_new(path, value)
                record = analyzer.load_report(path, PLAN)
                self.assertTrue(record["issues"])
                self.assertEqual(analyzer.aggregate_reports([record], PLAN)["status"], "BLOCKED_INPUT")


class PlayGrouping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reports = [check(*synthetic(index)) for index in range(1, 6)]

    @staticmethod
    def records(reports):
        return [{"analysis_path": f"SYNTHETIC_{index}.json", "report": report, "issues": []} for index, report in enumerate(reports)]

    def test_five_unique_sessions_complete_coverage_not_parity(self):
        report = analyzer.aggregate_reports(self.records(self.reports), PLAN)
        self.assertEqual(report["status"], "OBSERVED")
        self.assertEqual(report["counts"]["observed_independent_Play_sessions"], 5)
        self.assertEqual(report["counts"]["observed_scalar_cases"], 720)
        self.assertEqual(len(report["versions"][0]["train_sessions"]), 3)
        self.assertEqual(len(report["versions"][0]["holdout_sessions"]), 2)
        self.assertFalse(report["separate_preregistered_10_Play_extension_required"])

    def test_four_is_not_five_and_versions_never_pool(self):
        report = analyzer.aggregate_reports(self.records(self.reports[:4]), PLAN)
        self.assertEqual(report["status"], "BLOCKED_INCOMPLETE")
        mixed = copy.deepcopy(self.reports)
        for row in mixed[3:]: row["studio_version"] = "SYNTHETIC_SECOND_VERSION"
        report = analyzer.aggregate_reports(self.records(mixed), PLAN)
        self.assertEqual(report["status"], "BLOCKED_INCOMPLETE")
        self.assertEqual(sorted(version["observed_independent_Play_sessions"] for version in report["versions"]), [2, 3])

    def test_duplicate_run_session_or_raw_identities_reject_both_members(self):
        for key in ("run_id", "session_id", "raw_sha256"):
            reports = copy.deepcopy(self.reports)
            reports[1][key] = reports[0][key]
            report = analyzer.aggregate_reports(self.records(reports), PLAN)
            self.assertEqual(report["status"], "BLOCKED_INPUT")
            self.assertEqual(report["counts"]["observed_independent_Play_sessions"], 3)

    def test_variable_native_outcome_requires_new_preregistered_extension(self):
        reports = copy.deepcopy(self.reports)
        reports[-1] = check(*synthetic(5, changed_case=True))
        report = analyzer.aggregate_reports(self.records(reports), PLAN)
        self.assertEqual(report["status"], "BLOCKED_EXTENSION_REQUIRED")
        self.assertTrue(report["five_Play_matrix_complete"])
        self.assertTrue(report["separate_preregistered_10_Play_extension_required"])
        self.assertEqual(len(report["versions"][0]["variable_case_outcomes"]), 1)

    def test_timing_alone_is_not_fitted_or_a_coercion_outcome(self):
        reports = copy.deepcopy(self.reports)
        reports[-1] = check(*synthetic(5, timer_scale=3))
        report = analyzer.aggregate_reports(self.records(reports), PLAN)
        self.assertEqual(report["status"], "OBSERVED")
        self.assertEqual(report["versions"][0]["variable_case_outcomes"], [])

    def test_rejected_report_shape_does_not_reach_identity_hashing(self):
        records = self.records(self.reports[:1])
        records.append({"analysis_path": "invalid.json", "report": {"run_id": [], "counts": None}, "issues": ["rejected source input"]})
        report = analyzer.aggregate_reports(records, PLAN)
        self.assertEqual(report["status"], "BLOCKED_INPUT")
        self.assertEqual(report["counts"]["observed_independent_Play_sessions"], 1)
        self.assertEqual(report["input_issues"][0]["analysis_path"], "invalid.json")


if __name__ == "__main__": unittest.main()
