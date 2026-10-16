"""Synthetic telemetry-integrity regressions; these never claim native parity."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ordinary_analysis", HERE / "analyze_ordinary_spawn.py")
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
RUN = "12345678-1234-4234-8234-123456789abc"
RAW_SHA = "a" * 64


def enum(domain, name, value):
    return {"type": "EnumItem", "EnumType": domain, "Name": name, "Value": value}


def example():
    """Own synthetic capture with deliberately observed false and early absence."""
    config = {"id": "native_default_r6_altered_play1", "requested_rig": "R6", "profile": "altered", "session_index": 1, "split": "train", "path": "NATIVE_DEFAULT", "prejoin_values": {"CharacterUseJumpPower": False}}
    plan = {"fixture_version": "synthetic-ordinary-native-v2", "fixture_source_sha256": {"common.luau": "b" * 64}, "cases": [config],
            "required_snapshot_points": list(analyzer.EXPECTED_POINTS), "post_join_values": {"CharacterWalkSpeed": 31}}
    starter = {"LoadCharacterAppearance": False, "LuaCharacterController": enum("CharacterControlMode", "Legacy", 1), "AutoJumpEnabled": False,
               "CharacterWalkSpeed": 23, "CharacterJumpPower": 61, "CharacterJumpHeight": 9, "CharacterUseJumpPower": False,
               "CharacterMaxSlopeAngle": 37, "CharacterBreakJointsOnDeath": False, "CameraMinZoomDistance": 2, "CameraMaxZoomDistance": 60,
               "CameraMode": enum("CameraMode", "Classic", 0)}
    player = {"AutoJumpEnabled": False, "CameraMinZoomDistance": 2, "CameraMaxZoomDistance": 60, "CameraMode": enum("CameraMode", "Classic", 0)}
    humanoid = {"Health": 100, "MaxHealth": 100, "WalkSpeed": 23, "JumpPower": 61, "JumpHeight": 9, "UseJumpPower": False,
                "HipHeight": 0, "MaxSlopeAngle": 37, "AutoJumpEnabled": False, "AutoRotate": True, "BreakJointsOnDeath": False,
                "RequiresNeck": True, "RigType": enum("HumanoidRigType", "R6", 0)}

    def manifest(realm):
        row = {"kind": "run_manifest", "mode": "ordinary_spawn_a2", "studio_version": "SYNTHETIC_NO_STUDIO", "config": copy.deepcopy(config), "registration": copy.deepcopy(plan)}
        if realm == "server":
            row["character_auto_loads"] = False
        return row

    def snapshot(index, point):
        character = {"has_humanoid": True, "has_hrp": True, "has_animator": True, "has_animate": True, "actual_rig": "R6", "humanoid": copy.deepcopy(humanoid)}
        if point == "CharacterAdded_immediate":
            character = {"has_humanoid": False, "has_hrp": False, "has_animator": False, "has_animate": False, "actual_rig": "NOT_OBSERVABLE", "humanoid": {"status": "NOT_OBSERVABLE", "reason": "not present yet"}}
        starter_values = copy.deepcopy(starter)
        if index >= 6 or point == "live_after_StarterPlayer_mutation":
            starter_values.update(plan["post_join_values"])
        return {"kind": "a2_ordinary_snapshot", "token": f"spawn_{index}", "point": point, "character_generation": index, "server_generation": index,
                "current_character_same": True, "starter_player": starter_values, "player_properties": copy.deepcopy(player), "character": character,
                "requested_age_s": {"CharacterAdded_immediate": 0, "after_0.25s": .25, "after_1s": 1, "after_3s": 3}.get(point),
                "actual_age_wall_s": {"CharacterAdded_immediate": .0001, "first_PostSimulation": .0167, "after_0.25s": .26, "after_1s": 1.01, "after_3s": 3.02}.get(point, 3.1),
                "contamination": {"status": "OBSERVED_ABSENT"}, "callback_dt_sim_s": 1 / 60 if point == "first_PostSimulation" else None}

    client = [manifest("client"), {"kind": "a2_client_probe_attached", "character_already_present": False, "starter_player": copy.deepcopy(starter), "player_properties": copy.deepcopy(player)}]
    server = [manifest("server"), {"kind": "a2_player_join", "attachment": "PlayerAdded", "initial_join_event_observed": True, "starter_player": copy.deepcopy(starter), "player_properties": copy.deepcopy(player)}]
    for index in range(1, 11):
        token = f"spawn_{index}"
        params = {"spawn_index": index, "rig": "R6", "split": "train", "path": "NATIVE_DEFAULT", "phase": "prejoin_profile" if index <= 5 else "post_join_mutation"}
        client.append({"kind": "case_begin", "case": token, "parameters": params})
        for stream in (client, server):
            stream.append({"kind": "a2_lifecycle", "event": "CharacterAdded", "character_generation": index, "token": token})
            stream.extend(snapshot(index, point) for point in analyzer.EXPECTED_POINTS)
        server.append({"kind": "a2_server_window_validation", "token": token, "expected_generation": index, "status": "OBSERVED", "reasons": []})
        client.append({"kind": "case_result", "case": token, "status": "OBSERVED", "server_generation": index, "local_generation": index, "actual_rig": "R6", "parameters": params})
        if index == 5:
            for point in ("live_before_StarterPlayer_mutation", "live_after_StarterPlayer_mutation"):
                row = snapshot(5, point)
                row["token"] = "mutation"
                server.append(row)
            server.append({"kind": "a2_starter_mutation", "property": "CharacterWalkSpeed", "ok": True, "requested": 31})
    server.append({"kind": "run_result", "status": "OBSERVED", "errors": [], "loaded_characters": 10})
    for index, row in enumerate(server, 1):
        row.update(seq=index, run_id=RUN, realm="server")
        client.append({"kind": "server_record", "server": row})
    client.append({"kind": "run_result", "status": "OBSERVED", "errors": [], "count": 10})
    for index, row in enumerate(client, 1):
        row.update(seq=index, run_id=RUN, realm="client")
    observed = {"run_id": RUN, "raw_sha256": RAW_SHA, "raw_records": len(client), "parser_issues": [], "status": "OBSERVED",
                "compressed_transport": {"status": "VERIFIED", "integrity_issues": [],
                                         "manifest": {"run_id": RUN, "raw_sha256": RAW_SHA, "raw_records": len(client), "raw_bytes": 1000}}}
    return client, observed, plan


def analyze(rows=None, observed=None, plan=None):
    if rows is None:
        rows, observed, plan = example()
    return analyzer.analyze_rows(rows, observed, plan, RAW_SHA, 1000)


class CaptureValidation(unittest.TestCase):
    def test_truthful_immediate_absence_and_false_are_observed(self):
        report = analyze()
        self.assertEqual(report["status"], "OBSERVED", report["issues"])
        self.assertEqual(report["counts"]["initial_join_sessions"], 1)
        self.assertEqual(report["counts"]["observed_cases"], 10)
        self.assertEqual(report["parity_status"], "NOT_IMPLEMENTED_NOT_CALIBRATED")
        self.assertTrue(any("AppearanceLoaded absent" in x for x in report["warnings"]))

    def test_late_readiness_required_even_when_immediate_absence_allowed(self):
        rows, observed, plan = example()
        row = next(r for r in rows if r.get("token") == "spawn_1" and r.get("point") == "after_3s")
        row["character"]["has_hrp"] = False
        self.assertEqual(analyze(rows, observed, plan)["cases"][0]["analysis_status"], "BLOCKED")

    def test_missing_server_point_does_not_accept_source_barrier(self):
        rows, observed, plan = example()
        nested = next(r["server"] for r in rows if r.get("kind") == "server_record" and r["server"].get("token") == "spawn_2" and r["server"].get("point") == "after_1s")
        nested["point"] = "NOT_THE_REGISTERED_POINT"
        report = analyze(rows, observed, plan)
        self.assertEqual(report["cases"][1]["analysis_status"], "BLOCKED")
        self.assertTrue(any("missing snapshot" in x for x in report["cases"][1]["issues"]))

    def test_wrong_rig_is_blocked_without_accepting_filename_label(self):
        rows, observed, plan = example()
        for row in rows:
            candidate = row.get("server", row)
            if candidate.get("point") == "after_3s":
                candidate["character"]["actual_rig"] = "R15"
                candidate["character"]["humanoid"]["RigType"] = enum("HumanoidRigType", "R15", 1)
        report = analyze(rows, observed, plan)
        self.assertEqual(report["counts"]["blocked_cases"], 10)

    def test_reused_character_generation_is_not_a_respawn(self):
        rows, observed, plan = example()
        row = next(r for r in rows if r.get("token") == "spawn_3" and r.get("point") == "after_3s")
        row["character_generation"] = 2
        self.assertEqual(analyze(rows, observed, plan)["cases"][2]["analysis_status"], "BLOCKED")

    def test_source_hash_or_join_split_mismatch_blocks(self):
        rows, observed, plan = example()
        rows[0]["registration"]["fixture_source_sha256"]["common.luau"] = "c" * 64
        rows[0]["config"]["split"] = "holdout"
        report = analyze(rows, observed, plan)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertTrue(any("registration/source hashes differ" in x for x in report["issues"]))

    def test_native_empty_prejoin_mapping_round_trip_is_narrowly_allowed(self):
        rows, observed, plan = example()
        plan["cases"][0]["prejoin_values"] = {}
        for manifest in (rows[0], next(r["server"] for r in rows if r.get("kind") == "server_record")):
            manifest["config"]["prejoin_values"] = []
            manifest["registration"]["cases"][0]["prejoin_values"] = []
        report = analyze(rows, observed, plan)
        self.assertEqual(report["status"], "OBSERVED", report["issues"])
        self.assertFalse(analyzer.equal({}, []))
        self.assertFalse(analyzer.config_equal({"prejoin_values": []}, {"prejoin_values": {"CharacterUseJumpPower": False}}))
        self.assertFalse(analyzer.config_equal({"prejoin_values": [], "other": []}, {"prejoin_values": {}, "other": {}}))
        rows[0]["registration"]["fixture_source_sha256"] = []
        self.assertEqual(analyze(rows, observed, plan)["status"], "BLOCKED")

    def test_missing_timing_or_late_probe_attachment_blocks(self):
        rows, observed, plan = example()
        rows[1]["character_already_present"] = True
        row = next(r for r in rows if r.get("token") == "spawn_2" and r.get("point") == "after_3s")
        row["actual_age_wall_s"] = float("nan")
        report = analyze(rows, observed, plan)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertEqual(report["cases"][1]["analysis_status"], "BLOCKED")

    def test_declared_starter_inputs_are_verified_without_presuming_inheritance(self):
        rows, observed, plan = example()
        report = analyze(rows, observed, plan)
        self.assertEqual(report["status"], "OBSERVED")
        # Synthetic Humanoid intentionally stays at 23 after Starter becomes 31:
        # the analyzer must retain that observation, not force an expected result.
        self.assertEqual(report["cases"][5]["final_observed_properties"]["server"]["character"]["humanoid"]["WalkSpeed"], 23)
        nested = next(r["server"] for r in rows if r.get("kind") == "server_record" and r["server"].get("token") == "spawn_6" and r["server"].get("point") == "after_3s")
        nested["starter_player"]["CharacterWalkSpeed"] = 23
        self.assertEqual(analyze(rows, observed, plan)["cases"][5]["analysis_status"], "BLOCKED")

    def test_false_loss_source_and_numeric_boolean_are_blocked(self):
        rows, observed, plan = example()
        row = next(r for r in rows if r.get("token") == "spawn_1" and r.get("point") == "after_3s")
        row["starter_player"]["LoadCharacterAppearance"] = {"status": "NOT_OBSERVABLE", "reason": "false"}
        row["character"]["humanoid"]["UseJumpPower"] = 0
        self.assertEqual(analyze(rows, observed, plan)["cases"][0]["analysis_status"], "BLOCKED")
        self.assertFalse(analyzer.equal(False, 0))

    def test_transport_hash_and_mixed_run_do_not_become_observed(self):
        rows, observed, plan = example()
        rows[1]["run_id"] = "unrelated"
        observed["raw_sha256"] = "d" * 64
        report = analyze(rows, observed, plan)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertTrue(any("SHA256" in x for x in report["issues"]))

    def test_writer_preserves_existing_evidence(self):
        with tempfile.TemporaryDirectory(prefix="bobux-a2-analysis-") as temp:
            path = Path(temp) / "analysis.json"
            analyzer.write_report(path, {"original": True})
            with self.assertRaises(FileExistsError):
                analyzer.write_report(path, {"replacement": True})
            self.assertEqual(json.loads(path.read_text()), {"original": True})


class NativeMalformedTelemetryRegression(unittest.TestCase):
    """Mutate the preserved real Play 2 telemetry, never the native capture.

    The positive source provenance comparison is also exercised by the CLI
    against root's frozen registration. Here the already-verified manifest is
    copied only to isolate whether each telemetry corruption gets rejected.
    """
    @classmethod
    def setUpClass(cls):
        base = HERE.parents[1] / "tests" / "roblox_humanoid" / "phase_a" / "ordinary_spawn_v2"
        raw = base / "2026-10-15-r15-default-play2.raw.log"
        if not raw.exists():
            raise unittest.SkipTest("immutable real native Play 2 evidence unavailable in this checkout")
        cls.rows, cls.digest, cls.size = analyzer.load_raw(raw)
        if cls.digest != "b653f05229577be95d34e3c7fe33dd0b6535a7c1e2ef0b441f25066eb481cbe3":
            raise AssertionError("preserved native Play 2 raw evidence changed")
        cls.observed = json.loads(raw.with_name(raw.name.replace(".raw.log", ".observed.json")).read_text(encoding="utf-8"))
        cls.registration = copy.deepcopy(cls.rows[0]["registration"])
        baseline = cls.check(cls.rows, cls.observed)
        if baseline["status"] != "OBSERVED":
            raise AssertionError("real unmodified baseline no longer validates: " + repr(baseline["issues"]))

    @classmethod
    def check(cls, rows, observed=None):
        return analyzer.analyze_rows(rows, cls.observed if observed is None else observed, cls.registration, cls.digest, cls.size)

    @staticmethod
    def snapshot(rows, realm, point):
        stream = rows if realm == "client" else [r["server"] for r in rows if r.get("kind") == "server_record"]
        return next(r for r in stream if r.get("kind") == "a2_ordinary_snapshot" and r.get("token") == "spawn_2" and r.get("point") == point)

    def test_required_verified_transport_and_full_identity_manifest(self):
        for replacement in (None, {}, {"status": "VERIFIED"}, {"status": "VERIFIED", "integrity_issues": [], "manifest": {}}):
            with self.subTest(transport=replacement):
                observed = copy.deepcopy(self.observed)
                observed["compressed_transport"] = replacement
                self.assertEqual(self.check(self.rows, observed)["status"], "BLOCKED")
        observed = copy.deepcopy(self.observed)
        del observed["compressed_transport"]
        self.assertEqual(self.check(self.rows, observed)["status"], "BLOCKED")
        for key in ("raw_sha256", "raw_bytes", "raw_records", "run_id"):
            with self.subTest(missing_identity=key):
                observed = copy.deepcopy(self.observed)
                del observed["compressed_transport"]["manifest"][key]
                self.assertEqual(self.check(self.rows, observed)["status"], "BLOCKED")

    def test_delayed_snapshots_cannot_be_relabeled_immediate_measurements(self):
        for realm in ("client", "server"):
            for point in ("after_0.25s", "after_1s", "after_3s"):
                with self.subTest(realm=realm, point=point):
                    rows = copy.deepcopy(self.rows)
                    self.snapshot(rows, realm, point)["actual_age_wall_s"] = .001
                    report = self.check(rows)
                    self.assertEqual(report["cases"][1]["analysis_status"], "BLOCKED")
                    self.assertTrue(any("precedes" in issue for issue in report["cases"][1]["issues"]))

    def test_readiness_requires_boolean_true_in_both_realms(self):
        for realm in ("client", "server"):
            for key in ("has_humanoid", "has_hrp"):
                for value in ("false", {"is_nil": True}, 1, [], None):
                    with self.subTest(realm=realm, key=key, value=value):
                        rows = copy.deepcopy(self.rows)
                        self.snapshot(rows, realm, "after_3s")["character"][key] = value
                        self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_postsimulation_dt_must_be_finite_numeric_and_nonnegative(self):
        for realm in ("client", "server"):
            for value in (-.001, float("nan"), float("inf"), "0.016", False, None):
                with self.subTest(realm=realm, dt=value):
                    rows = copy.deepcopy(self.rows)
                    self.snapshot(rows, realm, "first_PostSimulation")["callback_dt_sim_s"] = value
                    self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_generation_and_current_character_are_checked_before_readiness(self):
        for realm in ("client", "server"):
            for point in analyzer.EXPECTED_POINTS[:-1]:
                for key, value in (("character_generation", 999), ("current_character_same", False)):
                    with self.subTest(realm=realm, point=point, key=key):
                        rows = copy.deepcopy(self.rows)
                        self.snapshot(rows, realm, point)[key] = value
                        self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_early_replication_may_be_missing_but_present_wrong_value_is_blocked(self):
        rows = copy.deepcopy(self.rows)
        for point in analyzer.EXPECTED_POINTS[:-1]:
            self.snapshot(rows, "client", point).pop("server_generation", None)
        self.assertEqual(self.check(rows)["status"], "OBSERVED")
        self.snapshot(rows, "client", "CharacterAdded_immediate")["server_generation"] = 999
        self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_early_component_absence_is_allowed_but_flag_types_remain_boolean(self):
        rows = copy.deepcopy(self.rows)
        for realm in ("client", "server"):
            character = self.snapshot(rows, realm, "CharacterAdded_immediate")["character"]
            character.update(has_humanoid=False, has_hrp=False)
        self.assertEqual(self.check(rows)["status"], "OBSERVED")
        self.snapshot(rows, "server", "CharacterAdded_immediate")["character"]["has_hrp"] = "false"
        self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_fixed_inputs_and_enum_tags_are_checked_outside_final_snapshot(self):
        for realm in ("client", "server"):
            for field, value in (("LoadCharacterAppearance", True),
                                 ("LuaCharacterController", enum("CharacterControlMode", "NewController", 2)),
                                 ("LuaCharacterController", enum("WrongDomain", "Legacy", 1))):
                with self.subTest(realm=realm, field=field, value=value):
                    rows = copy.deepcopy(self.rows)
                    stream = rows if realm == "client" else [r["server"] for r in rows if r.get("kind") == "server_record"]
                    observation = next(r for r in stream if "starter_player" in r)
                    observation["starter_player"][field] = value
                    self.assertEqual(self.check(rows)["status"], "BLOCKED")
        for key, value in (("EnumType", None), ("Name", "InventedMode"), ("Value", .5), ("Value", False)):
            with self.subTest(camera_tag=key, value=value):
                rows = copy.deepcopy(self.rows)
                self.snapshot(rows, "client", "after_0.25s")["player_properties"]["CameraMode"][key] = value
                self.assertEqual(self.check(rows)["status"], "BLOCKED")

    def test_lifecycle_generations_and_added_tokens_are_not_only_counted(self):
        for realm in ("client", "server"):
            for event in ("CharacterAdded", "CharacterRemoving"):
                with self.subTest(realm=realm, event=event):
                    rows = copy.deepcopy(self.rows)
                    stream = rows if realm == "client" else [r["server"] for r in rows if r.get("kind") == "server_record"]
                    for row in stream:
                        if row.get("kind") == "a2_lifecycle" and row.get("event") == event:
                            row["character_generation"] = 1
                    self.assertEqual(self.check(rows)["status"], "BLOCKED")
            rows = copy.deepcopy(self.rows)
            stream = rows if realm == "client" else [r["server"] for r in rows if r.get("kind") == "server_record"]
            row = next(r for r in stream if r.get("kind") == "a2_lifecycle" and r.get("event") == "CharacterAdded")
            row["token"] = "invented_case"
            self.assertEqual(self.check(rows)["status"], "BLOCKED")

    def test_age_precision_allowance_is_fixed_and_has_no_fitted_upper_lateness(self):
        rows = copy.deepcopy(self.rows)
        row = self.snapshot(rows, "server", "after_3s")
        row["actual_age_wall_s"] = 3 - analyzer.AGE_NUMERIC_EPSILON_S / 2
        self.assertEqual(self.check(rows)["status"], "OBSERVED")
        row["actual_age_wall_s"] = 3 - analyzer.AGE_NUMERIC_EPSILON_S * 2
        self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")
        row["actual_age_wall_s"] = 30
        self.assertEqual(self.check(rows)["status"], "OBSERVED")

    def test_both_case_parameters_match_registered_rig_and_phase(self):
        for kind in ("case_begin", "case_result"):
            for key, value in (("rig", "R6"), ("phase", "not_registered_phase")):
                with self.subTest(kind=kind, key=key):
                    rows = copy.deepcopy(self.rows)
                    case = next(r for r in rows if r.get("kind") == kind and r.get("case") == "spawn_2")
                    case["parameters"][key] = value
                    self.assertEqual(self.check(rows)["cases"][1]["analysis_status"], "BLOCKED")

    def test_live_mutation_requires_current_ready_generation_five(self):
        for point in ("live_before_StarterPlayer_mutation", "live_after_StarterPlayer_mutation"):
            rows = copy.deepcopy(self.rows)
            row = next(r["server"] for r in rows if r.get("kind") == "server_record" and r["server"].get("point") == point)
            row["current_character_same"] = False
            report = self.check(rows)
            self.assertEqual(report["status"], "BLOCKED")
            self.assertEqual(report["live_generation5_after_StarterPlayer_mutation"]["status"], "NOT_OBSERVABLE")

    def test_unavailable_live_humanoid_cannot_be_used_as_observed_delta(self):
        rows = copy.deepcopy(self.rows)
        row = next(r["server"] for r in rows if r.get("kind") == "server_record" and r["server"].get("point") == "live_after_StarterPlayer_mutation")
        row["character"]["humanoid"] = {"status": "NOT_OBSERVABLE", "reason": "missing"}
        report = self.check(rows)
        self.assertEqual(report["status"], "BLOCKED")
        delta = report["live_generation5_after_StarterPlayer_mutation"]
        self.assertEqual(delta["status"], "NOT_OBSERVABLE")
        self.assertNotIn("humanoid_observed_changes", delta)


if __name__ == "__main__":
    unittest.main()
