"""Static experiment safety/registration checks; no native behavior is mocked."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ordinary_builder", HERE / "build_place.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class FixtureSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = builder.registration()

    def test_independent_preregistered_sessions_and_splits(self):
        cases = self.plan["cases"]
        self.assertEqual(len({x["id"] for x in cases}), 20)
        for rig in ("R6", "R15"):
            for profile in ("default", "altered"):
                selected = [x for x in cases if x["requested_rig"] == rig and x["profile"] == profile]
                self.assertEqual([x["session_index"] for x in selected], list(range(1, 6)))
                self.assertEqual([x["split"] for x in selected], ["train"] * 3 + ["holdout"] * 2)

    def test_xml_sets_values_before_join_and_does_not_install_custom_rig(self):
        for case in self.plan["cases"]:
            doc = ET.fromstring(builder.build_scene(case, self.plan))
            items = doc.findall(".//Item")
            self.assertFalse(any(x.attrib["class"] in ("Humanoid", "Model", "HumanoidDescription") for x in items))
            names = [x.find("Properties/string[@name='Name']").text for x in items]
            self.assertNotIn("StarterCharacter", names)
            self.assertNotIn("StarterHumanoid", names)
            starter = next(x for x in items if x.attrib["class"] == "StarterPlayer")
            props = {x.attrib["name"]: x.text for x in starter.find("Properties")}
            self.assertEqual(props["LoadCharacterAppearance"], "false")
            self.assertEqual(props["LuaCharacterController"], "1")
            for name in builder.MODIFIED:
                if case["profile"] == "default":
                    self.assertNotIn(name, props)
                else:
                    expected = builder.MODIFIED[name]
                    self.assertEqual(props[name], str(expected).lower() if isinstance(expected, bool) else str(expected))
            players = next(x for x in items if x.attrib["class"] == "Players")
            self.assertEqual(players.find("Properties/bool[@name='CharacterAutoLoads']").text, "false")

    def test_rig_labels_do_not_set_hidden_avatar_fields(self):
        for case in self.plan["cases"]:
            text = builder.build_scene(case, self.plan).decode()
            for forbidden in ('name="CharacterRigType"', 'name="AvatarType"', 'name="RigType"', 'name="GameSettings"'):
                self.assertNotIn(forbidden, text)

    def test_sources_use_only_native_load_without_manual_inheritance(self):
        scripts = "\n".join(p.read_text(encoding="utf-8") for p in HERE.glob("*.luau"))
        self.assertIn("player:LoadCharacterAsync()", scripts)
        for pattern in (r"\.Character\s*=(?!=)", r"\.RigType\s*=(?!=)", r"\.Source\b",
                        r"LoadCharacterWithHumanoidDescription", r"CreateHumanoidModel", r"Instance\.new\([\"'](?:Humanoid|Model|HumanoidDescription)[\"']"):
            self.assertIsNone(re.search(pattern, scripts), pattern)

    def test_each_realm_has_registered_points_and_watchdogs(self):
        for name in ("setup.server.luau", "measure.client.luau"):
            source = (HERE / name).read_text(encoding="utf-8")
            self.assertIn('"CharacterAdded_immediate"', source)
            self.assertIn('"first_PostSimulation"', source)
            self.assertIn("registration.snapshot_delays_wall_s", source)
            self.assertIn("registration.timeouts.session_wall_s", source)
            self.assertIn("actual_age_wall_s", source)
            self.assertIn("callback_dt_sim_s", source)
            self.assertIn("CharacterAppearanceLoaded", source)

    def test_embedded_registration_exact_and_source_hashes_current(self):
        doc = ET.fromstring(builder.build_scene(self.plan["cases"][0], self.plan))
        value = next(x.find("Properties/string[@name='Value']").text for x in doc.findall(".//Item")
                     if x.find("Properties/string[@name='Name']").text == "OrdinarySpawnRegistration")
        self.assertEqual(json.loads(value), self.plan)
        for name, digest in self.plan["fixture_source_sha256"].items():
            self.assertEqual(builder.digest(HERE / name), digest)

    def test_false_nil_error_serializer_in_official_luau_runtime(self):
        result = subprocess.run([str(HERE.parent / ".compiler/luau.exe"), str(HERE / "serializer_test.luau")],
                                cwd=HERE, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("PASS 7 own-data assertions", result.stdout)


if __name__ == "__main__":
    unittest.main()
