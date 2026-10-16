"""Coverage/integrity regressions for the isolated A2 aggregate utility.

Pure assemble tests deliberately mutate copies of verified report metadata to
exercise grouping gates. File-boundary tests rerun the frozen analyzer against
real own telemetry. Neither kind is a native behavior or Bobux parity test.
"""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ordinary_spawn_aggregate", HERE / "aggregate_ordinary_spawn.py")
aggregate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aggregate)


class IndependentJoinAggregate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = HERE.parents[1] / "tests" / "roblox_humanoid" / "phase_a" / "ordinary_spawn_v2"
        cls.paths = [cls.base / f"2026-10-15-r15-default-play{index}.analysis-{'reviewed2' if index <= 2 else 'reviewed-final'}.json"
                     for index in range(1, 6)]
        if not all(path.is_file() for path in cls.paths):
            raise unittest.SkipTest("five preserved R15/default own native report inputs unavailable")
        cls.registration_path = Path(json.loads(cls.paths[0].read_text(encoding="utf-8"))["input_paths"]["registration"])
        cls.registration = aggregate.read_json(cls.registration_path)
        cls.registration_sha = aggregate.sha256(cls.registration_path)
        if cls.registration_sha != aggregate.EXPECTED_REGISTRATION_SHA256:
            raise AssertionError("frozen registration changed")
        if aggregate.sha256(aggregate.ANALYZER) != aggregate.EXPECTED_ANALYZER_SHA256:
            raise AssertionError("frozen analyzer changed")
        cls.records = [aggregate.read_analysis(path, cls.registration, cls.registration_sha) for path in cls.paths]
        if any(record["issues"] for record in cls.records):
            raise AssertionError("unmodified real input failed validation: " + repr([r["issues"] for r in cls.records]))

    def assemble(self, records):
        return aggregate.assemble(self.registration, self.registration_sha, records)

    @staticmethod
    def group(report, rig="R15", profile="default"):
        return next(group for group in report["groups"] if group["requested_rig"] == rig and group["profile"] == profile)

    def test_four_joins_never_complete_the_five_join_group(self):
        report = self.assemble(self.records[:4])
        group = self.group(report)
        self.assertEqual(group["status"], "BLOCKED_INCOMPLETE")
        self.assertEqual(group["observed_independent_joins"], 4)
        self.assertEqual(group["observed_train_joins"], 3)
        self.assertEqual(group["observed_holdout_joins"], 1)
        self.assertEqual(group["not_run_session_ids"], ["native_default_r15_default_play5"])
        self.assertEqual(report["counts"]["observed_native_generations"], 40)
        self.assertFalse(report["native_default_matrix_complete"])

    def test_five_real_default_joins_only_complete_their_own_group(self):
        report = self.assemble(self.records)
        group = self.group(report)
        self.assertEqual(group["status"], "OBSERVED")
        self.assertEqual((group["observed_train_joins"], group["observed_holdout_joins"]), (3, 2))
        self.assertEqual(report["counts"]["observed_independent_joins"], 5)
        self.assertEqual(report["counts"]["complete_groups"], 1)
        self.assertEqual(report["status"], "BLOCKED_INCOMPLETE")
        for rig, profile in (("R6", "default"), ("R6", "altered"), ("R15", "altered")):
            absent = self.group(report, rig, profile)
            self.assertEqual(absent["status"], "NOT_RUN")
            self.assertEqual(absent["observed_independent_joins"], 0)
            self.assertEqual(len(absent["not_run_session_ids"]), 5)
        self.assertFalse(report["full_A2_complete"])
        self.assertEqual(report["parity_status"], "NOT_IMPLEMENTED_NOT_CALIBRATED")
        self.assertTrue(report["no_fit"])

    def test_empty_submission_leaves_every_group_not_run(self):
        report = self.assemble([])
        self.assertEqual(report["counts"]["observed_independent_joins"], 0)
        self.assertTrue(all(group["status"] == "NOT_RUN" for group in report["groups"]))
        self.assertEqual(sum(len(group["not_run_session_ids"]) for group in report["groups"]), 20)

    def test_duplicate_run_session_and_raw_identities_reject_every_member(self):
        for key in ("run_id", "session_id", "raw_sha256"):
            with self.subTest(identity=key):
                records = copy.deepcopy(self.records)
                records[1]["analysis"][key] = records[0]["analysis"][key]
                report = self.assemble(records)
                self.assertEqual(report["status"], "BLOCKED_INPUT")
                self.assertEqual(self.group(report)["observed_independent_joins"], 3)
                self.assertEqual(sum(any("duplicate independent-capture identity: " + key in issue for issue in entry["issues"])
                                     for entry in report["input_issues"]), 2)

    def test_same_explicit_report_twice_is_not_silently_best_of_deduplicated(self):
        report = self.assemble(self.records + [self.records[0]])
        self.assertEqual(report["status"], "BLOCKED_INPUT")
        self.assertEqual(self.group(report)["observed_independent_joins"], 4)
        self.assertEqual(len(report["input_issues"]), 2)

    def test_mixed_studio_versions_cannot_complete_a_group(self):
        records = copy.deepcopy(self.records)
        records[-1]["analysis"]["studio_version"] = "SYNTHETIC_OTHER_VERSION_ONLY_FOR_GROUPING_TEST"
        report = self.assemble(records)
        group = self.group(report)
        self.assertEqual(group["status"], "BLOCKED_MIXED_STUDIO_VERSIONS")
        self.assertEqual(group["observed_independent_joins"], 5)
        self.assertEqual(len(group["observed_studio_versions"]), 2)
        self.assertEqual(report["counts"]["complete_groups"], 0)
        self.assertFalse(report["native_default_matrix_complete"])

    def test_report_edit_cannot_change_identity_version_or_holdout_assignment(self):
        for key, value in (("studio_version", "SYNTHETIC_EDIT"), ("session_id", "native_default_r15_default_play5"),
                           ("split_per_initial_join", "holdout"), ("analyzer_source_sha256", "0" * 64)):
            with self.subTest(edited_field=key), tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-test-") as directory:
                edited = copy.deepcopy(self.records[0]["analysis"])
                edited[key] = value
                path = Path(directory) / "edited-analysis.json"
                path.write_text(json.dumps(edited), encoding="utf-8")
                record = aggregate.read_analysis(path, self.registration, self.registration_sha)
                self.assertTrue(record["issues"], key)
                self.assertEqual(self.assemble([record])["counts"]["observed_independent_joins"], 0)

    def test_rig_mismatch_is_blocked_and_never_filled_from_another_group(self):
        records = copy.deepcopy(self.records)
        records[0]["analysis"]["cases"][0]["actual_rigs"]["client"] = "R6"
        report = self.assemble(records)
        self.assertEqual(report["status"], "BLOCKED_INPUT")
        self.assertEqual(self.group(report)["observed_independent_joins"], 4)
        self.assertEqual(self.group(report, "R6")["status"], "NOT_RUN")

    def test_cli_uses_only_explicit_inputs_and_preserves_existing_output(self):
        with tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-cli-") as directory:
            folder = Path(directory)
            # A sibling stale/invalid report must never be globbed implicitly.
            (folder / "unselected.analysis.json").write_text("invalid unselected file", encoding="utf-8")
            output = folder / "aggregate.json"
            args = [sys.executable, str(HERE / "aggregate_ordinary_spawn.py"), "--registration", str(self.registration_path),
                    "--analyses", str(self.paths[0]), "--output", str(output)]
            result = subprocess.run(args, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(data["counts"]["submitted_analysis_files"], 1)
            self.assertEqual(data["counts"]["observed_independent_joins"], 1)
            preserved = output.read_bytes()
            repeat = subprocess.run(args, capture_output=True, text=True, timeout=20)
            self.assertNotEqual(repeat.returncode, 0)
            self.assertEqual(output.read_bytes(), preserved)

    def test_missing_explicit_input_is_blocked_not_substituted(self):
        with tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-missing-") as directory:
            record = aggregate.read_analysis(Path(directory) / "not-present.json", self.registration, self.registration_sha)
            report = self.assemble([record])
            self.assertEqual(report["status"], "BLOCKED_INPUT")
            self.assertEqual(report["counts"]["observed_independent_joins"], 0)

    def test_selected_nonobject_json_is_a_blocked_input_not_an_aggregate_crash(self):
        for value in ([], None):
            with self.subTest(json_value=value), tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-nonobject-") as directory:
                path = Path(directory) / "selected-invalid-analysis.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                record = aggregate.read_analysis(path, self.registration, self.registration_sha)
                self.assertTrue(record["issues"])
                report = self.assemble([record])
                self.assertEqual(report["status"], "BLOCKED_INPUT")
                self.assertEqual(report["counts"]["observed_independent_joins"], 0)

    def test_rejected_count_shape_never_reaches_aggregate_count_dereference(self):
        with tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-count-shape-") as directory:
            edited = copy.deepcopy(self.records[0]["analysis"])
            edited["counts"] = None
            path = Path(directory) / "selected-counts-null.json"
            path.write_text(json.dumps(edited), encoding="utf-8")
            record = aggregate.read_analysis(path, self.registration, self.registration_sha)
            self.assertTrue(record["issues"])
            report = self.assemble([record])
            self.assertEqual(report["status"], "BLOCKED_INPUT")
            self.assertEqual(report["counts"]["observed_independent_joins"], 0)
            self.assertEqual(report["input_issues"][0]["analysis_path"], str(path.resolve()))
            self.assertEqual(report["input_issues"][0]["issues"], record["issues"])

    def test_rejected_unhashable_identities_never_reach_duplicate_or_group_keys(self):
        for key in ("run_id", "session_id", "raw_sha256"):
            with self.subTest(identity=key), tempfile.TemporaryDirectory(prefix="bobux-a2-aggregate-identity-shape-") as directory:
                edited = copy.deepcopy(self.records[0]["analysis"])
                edited[key] = []
                path = Path(directory) / "selected-unhashable-identity.json"
                path.write_text(json.dumps(edited), encoding="utf-8")
                record = aggregate.read_analysis(path, self.registration, self.registration_sha)
                self.assertTrue(record["issues"])
                report = self.assemble([record])
                self.assertEqual(report["status"], "BLOCKED_INPUT")
                self.assertEqual(report["counts"]["observed_independent_joins"], 0)
                self.assertEqual(report["input_issues"][0]["analysis_path"], str(path.resolve()))
                self.assertEqual(report["input_issues"][0]["issues"], record["issues"])


if __name__ == "__main__":
    unittest.main()
