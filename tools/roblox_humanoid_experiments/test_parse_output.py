"""Synthetic parser checks only; these are not Roblox measurements."""
from pathlib import Path
import json
import unittest
import xml.etree.ElementTree as ET
import tempfile

from parse_output import PREFIX, parse_records, evidence
from build_place import build


def line(record):
    return "12:34:56 [FLog::Output] " + PREFIX + json.dumps(record) + " - Client - test:1\n"


class ParserTests(unittest.TestCase):
    def begin(self, run="synthetic", seq=1):
        return {"kind": "run_begin", "run_id": run, "seq": seq, "engine_version": "SYNTHETIC_NOT_EMPIRICAL"}

    def test_noise_trailing_metadata_and_dedup(self):
        begin = self.begin()
        records, issues = parse_records("noise\n" + line(begin) + line(begin))
        self.assertEqual(records, [begin])
        self.assertEqual(issues, [])

    def test_malformed_recovers_next_prefix(self):
        records, issues = parse_records(PREFIX + "{broken}\n" + line(self.begin()))
        self.assertEqual(len(records), 1)
        self.assertEqual(len(issues), 1)

    def test_compact_result_collects_independent_cases(self):
        records = [self.begin(), {"kind": "case_result", "run_id": "synthetic", "seq": 2,
                                 "name": "synthetic", "status": "measured", "parameters": {"type": "drop", "height": 5}},
                   {"kind": "run_result", "run_id": "synthetic", "seq": 3, "status": "complete", "case_count": 1}]
        result, _ = evidence(records, Path("synthetic"), [])
        self.assertEqual(len(result["cases"]), 1)

    def test_full_raw_record_replaces_compact_duplicate(self):
        compact = {"kind": "case_result", "run_id": "synthetic", "seq": 2, "name": "test"}
        full = dict(compact, state_events=[{"new": "Landed"}])
        records, _ = parse_records(line(compact) + line(full))
        self.assertEqual(records, [full])

    def test_no_measurement_without_real_record_structure(self):
        with self.assertRaises(ValueError):
            evidence([], Path("synthetic"), [])

    def test_partial_explicitly_incomplete(self):
        result, _ = evidence([self.begin()], Path("synthetic"), [])
        self.assertEqual(result["status"], "incomplete")
        self.assertEqual(result["measurements"]["jumps"], [])

    def test_latest_run_selected(self):
        result, selected = evidence([self.begin("old"), self.begin("new")], Path("synthetic"), [])
        self.assertEqual(result["run_id"], "new")
        self.assertEqual(len(selected), 1)

    def test_unknown_speed_does_not_turn_into_zero(self):
        case = {"name": "test", "status": "unmeasured", "parameters": {"type": "climb", "WalkSpeed": 16}}
        result, _ = evidence([self.begin(), {"kind": "run_result", "run_id": "synthetic", "status": "completed_with_failures", "cases": [case]}], Path("synthetic"), [])
        self.assertEqual(result["measurements"]["locomotion"], [])

    def test_jump_impulse_never_claimed_exact(self):
        case = {"name": "test", "status": "measured", "parameters": {"type": "jump", "gravity": 196.2, "UseJumpPower": False, "JumpHeight": 10},
                "observed_apex_height": 9.8, "max_observed_vy": 61, "first_post_vy": 60.7, "first_post_simulation": {"dt_sim_s": 1/60}}
        result, _ = evidence([self.begin(), {"kind": "run_result", "run_id": "synthetic", "status": "complete", "cases": [case]}], Path("synthetic"), [])
        jump = result["measurements"]["jumps"][0]
        self.assertEqual(jump["observed_apex_height_studs"]["median"], 9.8)
        self.assertIsNone(jump["exact_initial_impulse_velocity"]["value"])
        self.assertEqual(jump["first_post_dt_sim_seconds"]["median"], 1/60)

    def test_generated_xml_contains_exact_script_sources(self):
        here = Path(__file__).resolve().parent
        # Do not rewrite a place currently open in a real Studio experiment.
        with tempfile.TemporaryDirectory(dir=here) as temporary:
            doc = ET.parse(build(Path(temporary) / "fixture.rbxlx"))
        sources = [element.text for element in doc.findall(".//ProtectedString[@name='Source']")]
        self.assertIn((here / "setup.server.luau").read_text(encoding="utf-8"), sources)
        self.assertIn((here / "measure.client.luau").read_text(encoding="utf-8"), sources)
        self.assertEqual(len(doc.findall(".//Item[@class='LocalScript']")), 1)
        self.assertEqual(len(doc.findall(".//Item[@class='Part']")), 1)


if __name__ == "__main__":
    unittest.main()
