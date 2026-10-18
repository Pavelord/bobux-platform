"""Own source/registration/serializer checks, never a native coercion simulation."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rig_type_edges_builder", HERE / "build_place.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class SourceReadyChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = builder.registration()

    def test_five_independent_sessions_keep_train_holdout_assignment(self):
        sessions = self.plan["sessions"]
        self.assertEqual([row["session_index"] for row in sessions], [1, 2, 3, 4, 5])
        self.assertEqual([row["split"] for row in sessions], ["train"] * 3 + ["holdout"] * 2)
        self.assertEqual(len({row["id"] for row in sessions}), 5)
        self.assertEqual({row["seed"] for row in sessions}, {20261016})

    def test_exact_matrix_includes_both_booleans_and_negative_fraction(self):
        cases = self.plan["cases"]
        expected = {(context, baseline, target, variant)
                    for context in ("fresh_unparented", "fresh_workspace")
                    for baseline in ("R6", "R15") for target in ("R6", "R15")
                    for variant, _ in builder.VARIANTS}
        self.assertEqual(len(builder.VARIANTS), 18)
        self.assertEqual(len(cases), 144)
        self.assertEqual(len({row["id"] for row in cases}), 144)
        self.assertEqual({(row["context"], row["baseline"], row["target"], row["variant"]) for row in cases}, expected)
        self.assertTrue({"boolean_false", "boolean_true", "negative_fraction"} <= {row["variant"] for row in cases})

    def test_permutation_is_fixed_without_native_outcome_input(self):
        self.assertEqual(self.plan["cases"], builder.registration()["cases"])
        self.assertEqual([row["ordinal"] for row in self.plan["cases"]], list(range(1, 145)))
        # Tiny fixed LCG/Fisher-Yates example; no native outcomes enter order.
        self.assertEqual(builder.deterministic_permutation(list(range(8)), 20261016), [2, 4, 0, 6, 1, 3, 5, 7])

    def test_embedded_own_sources_config_registration_are_exact(self):
        for config in self.plan["sessions"]:
            doc = ET.fromstring(builder.build_scene(config, self.plan))
            entries = {node.find("Properties/string[@name='Name']").text: node for node in doc.findall(".//Item")}
            for name, data in (("RigTypeEdgesConfig", config), ("RigTypeEdgesRegistration", self.plan)):
                self.assertEqual(json.loads(entries[name].find("Properties/string[@name='Value']").text), data)
            for name, filename in (("RigTypeEdgesCommon", "common.luau"), ("RigTypeEdgesProbe", "probe.server.luau")):
                self.assertEqual(entries[name].find("Properties/ProtectedString[@name='Source']").text,
                                 (HERE / filename).read_text(encoding="utf-8"))

    def test_xml_installs_no_rig_avatar_or_preexisting_humanoid(self):
        doc = ET.fromstring(builder.build_scene(self.plan["sessions"][0], self.plan))
        entries = doc.findall(".//Item")
        self.assertFalse(any(node.attrib["class"] in ("Humanoid", "Model", "HumanoidDescription", "LocalScript", "StarterPlayer") for node in entries))
        for node in entries:
            properties = {value.attrib["name"]: value.text for value in node.find("Properties")}
            self.assertFalse({"CharacterRigType", "AvatarType", "RigType", "GameSettings"} & properties.keys())
            self.assertNotIn(properties["Name"], ("StarterCharacter", "StarterHumanoid"))
            if node.attrib["class"] == "Players":
                self.assertEqual(properties["CharacterAutoLoads"], "false")

    def test_probe_uses_only_own_scalar_targets_without_original_source_assets(self):
        sources = "\n".join(path.read_text(encoding="utf-8") for path in HERE.glob("*.luau"))
        for pattern in (r"\.Source\b", r"GetService\([\"']Players[\"']\)", r"\.Character\s*[=\.]",
                        r"CreateHumanoidModel", r"LoadCharacter", r"HumanoidDescription", r"AnimationId|TextureId|SoundId",
                        r"Instance\.new\([\"'](?:Model|Part|HumanoidDescription)[\"']\)"):
            self.assertIsNone(re.search(pattern, sources), pattern)
        probe = (HERE / "probe.server.luau").read_text(encoding="utf-8")
        self.assertIn('Instance.new("Humanoid")', probe)
        self.assertIn('humanoid.Parent=workspace', probe)
        self.assertIn('humanoid:GetPropertyChangedSignal("RigType")', probe)
        self.assertIn('humanoid.Changed:Connect', probe)
        self.assertIn('fresh RigType is observed; R6 is not an asserted fixture input', probe)
        self.assertIn('observation_Heartbeats_after_setter', probe)
        self.assertLess(probe.index('fresh_default_policy="The following new Humanoid'),
                        probe.index('Instance.new("Humanoid")'))
        self.assertIn('setter_call_before=callBefore,setter_call_after=callAfter', probe)
        self.assertIn('if finished or activeHumanoid~=humanoid then return end', probe)

    def test_registered_sources_and_immutable_transport_hashes_match(self):
        for filename, digest in self.plan["fixture_source_sha256"].items():
            self.assertEqual(builder.digest(HERE / filename), digest)
        for field in ("export", "parser"):
            transport = self.plan["reused_transport"]
            self.assertEqual(builder.digest(builder.ROOT / transport[field]), transport[field + "_sha256"])
        self.assertEqual(self.plan["reused_transport"]["folder"], "CharacterExperimentTelemetry")

    def test_registration_contains_only_finite_json_and_no_presumed_outcomes(self):
        json.dumps(self.plan, allow_nan=False)
        self.assertTrue(self.plan["no_fit"])
        self.assertTrue(self.plan["no_physical_rig_claim"])
        self.assertEqual(self.plan["baseline_settle_Heartbeats"], 1)
        self.assertEqual(self.plan["observation_Heartbeats_after_setter"], 2)

    def test_serializer_semantics_in_official_local_luau_cli(self):
        result = subprocess.run([str(HERE.parent / ".compiler/luau.exe"), str(HERE / "serializer_test.luau")],
                                cwd=HERE, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("PASS 20 own-data assertions; native coercion NOT_RUN", result.stdout)

    def test_sources_compile_in_official_local_luau_compiler(self):
        result = subprocess.run([str(HERE.parent / ".compiler/luau-compile.exe"), "--null",
                                 *map(str, sorted(HERE.glob("*.luau")))], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
