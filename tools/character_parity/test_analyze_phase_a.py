"""Meaningful integrity/type guards for the independent Phase A analysis."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("phase_a_analysis", Path(__file__).with_name("analyze_phase_a.py"))
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class PhaseAAnalysisTests(unittest.TestCase):
    def raw_fixture(self, tmp, rows):
        path = Path(tmp) / "raw.log"
        path.write_text("".join(analysis.PREFIX + json.dumps(row) + "\n" for row in rows), encoding="utf-8")
        observed = {"raw_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "raw_records": len(rows),
                    "status": "OBSERVED", "parser_issues": [], "run_id": "own-fixture"}
        return path, observed

    def test_numeric_bool_and_enum_do_not_collapse(self):
        enum = {"type": "EnumItem", "Name": "Idle", "Value": 0, "EnumType": "AnimationPriority"}
        result = analysis.distribution([0, False, enum])
        self.assertEqual(len(result["unique"]), 3)
        self.assertNotIn("median", result)

    def test_sequence_gap_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, observed = self.raw_fixture(tmp, [
                {"seq": 1, "run_id": "own-fixture", "kind": "run_manifest"},
                {"seq": 3, "run_id": "own-fixture", "kind": "run_result"}])
            with self.assertRaisesRegex(ValueError, "sequence"):
                analysis.parse_raw(path, observed)

    def test_tampered_raw_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, observed = self.raw_fixture(tmp, [{"seq": 1, "run_id": "own-fixture", "kind": "run_result"}])
            path.write_text(path.read_text() + "\n")
            with self.assertRaisesRegex(ValueError, "SHA"):
                analysis.parse_raw(path, observed)

    def test_incomplete_report_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, observed = self.raw_fixture(tmp, [{"seq": 1, "run_id": "own-fixture", "kind": "run_result"}])
            observed["status"] = "BLOCKED"
            with self.assertRaisesRegex(ValueError, "incomplete"):
                analysis.parse_raw(path, observed)

    def test_old_metadata_prefixes_are_not_semantic_constants(self):
        result = analysis.analyze_a4({"schema": 1, "scripts": [{"path": "Workspace.Own.Health",
            "class": "Script", "status": "OBSERVED", "source_length": 20, "literal_constants": {"RATE": 1}}]}, [])
        self.assertEqual(result["semantic_constants"]["status"], "BLOCKED")
        self.assertEqual(result["inventory"][0]["literal_extraction_status"], "PROVISIONAL_LEXICAL_PREFIX_ONLY")

    def test_strict_metadata_is_initializer_not_behavior(self):
        result = analysis.analyze_a4({"schema": 2, "extractor_version": "standalone_single_line_literals_v2",
            "scripts": [{"path": "Workspace.Own.Animate", "class": "LocalScript", "status": "OBSERVED",
                         "source_length": 20, "literal_constants": {"ownTime": 0.31},
                         "literal_extraction": {"status": "EXACT_LITERAL_DECLARATIONS_ONLY"}}]}, [])
        self.assertEqual(result["semantic_constants"]["status"], "OBSERVED_EXACT_LOCAL_INITIALIZERS")
        self.assertEqual(result["runtime_configuration_behavior"], "NOT_MEASURED")


if __name__ == "__main__":
    unittest.main()
