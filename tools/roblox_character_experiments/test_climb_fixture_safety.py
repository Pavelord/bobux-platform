"""Static registration/lifecycle checks; real native motion remains OBSERVED/BLOCKED."""
import hashlib
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

import build_place

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


class ClimbFixtureSafetyTests(unittest.TestCase):
    def setUp(self):
        self.original = json.loads((ROOT / "tests/roblox_humanoid/phase_a/splits.json").read_text(encoding="utf-8"))
        self.registered = json.loads((ROOT / "tests/roblox_humanoid/phase_a/climb_run02.splits.json").read_text(encoding="utf-8"))
        self.scene = ET.parse(HERE / "CharacterClimbBaseline_run02.rbxlx")

    def item(self, name):
        return next(item for item in self.scene.iter("Item")
                    if item.find("Properties/string[@name='Name']") is not None
                    and item.find("Properties/string[@name='Name']").text == name)

    def test_obstacles_cases_and_splits_unchanged(self):
        self.assertEqual(self.registered["cases"], self.original["cases"])
        self.assertEqual(self.registered["fixture_geometry"], self.original["fixture_geometry"])
        self.assertEqual(self.registered["durations"]["active_sim_s"], self.original["durations"]["active_sim_s"])
        self.assertEqual(len(self.registered["cases"]), 45)

    def test_scene_registration_matches_frozen_manifest(self):
        value = self.item("CharacterExperimentMatrix").find("Properties/string[@name='Value']").text
        self.assertEqual(json.loads(value), self.registered)

    def test_plane_covers_fastest_command_displacement_with_margin(self):
        size = self.registered["support_geometry"]["baseplate"]["size"]
        speed = max(case["WalkSpeed"] for case in self.registered["cases"])
        distance = speed * self.registered["durations"]["active_sim_s"]
        # Conservative forward travel bound, not an assertion of actual trajectory.
        self.assertGreaterEqual(size[2] / 2, distance + 8 + 32)
        part_size = self.item("Baseplate").find("Properties/Vector3[@name='size']")
        self.assertEqual([float(part_size.find(axis).text) for axis in ("X", "Y", "Z")], size)

    def test_loaded_measurement_matches_registered_source_sha(self):
        source = self.item("CharacterBlackBoxMeasurement").find("Properties/ProtectedString[@name='Source']").text
        self.assertEqual(hashlib.sha256(source.encode("utf-8")).hexdigest(),
                         self.registered["fixture_source_sha256"]["measure.client.luau"])

    def test_no_forced_climbing_or_measured_case_retries(self):
        source = self.item("CharacterBlackBoxMeasurement").find("Properties/ProtectedString[@name='Source']").text
        states = re.findall(r"h:ChangeState\(Enum\.HumanoidStateType\.(\w+)\)", source)
        self.assertEqual(states, ["Freefall"])
        self.assertIn("if not characterAlive() then", source)
        self.assertIn("bounded native spawn RPC", source)
        self.assertIn("characterGeneration", source)
        self.assertFalse(self.registered["reset_policy"]["no_measured_case_retries"] is False)


if __name__ == "__main__":
    unittest.main()
