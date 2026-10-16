"""Build isolated ordinary native-spawn places, with prejoin settings frozen.

Only new output directories are accepted. No source/core/global fixture is edited.
The requested rig is a coverage label, never a hidden setting or custom model.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCHEMA = ROOT / "tests/roblox_humanoid/phase_a/creator_docs_api.json"
PINNED_COMMIT = "031b2f91d3d47274c255f3ed5691c29f792c181d"
VERSION = "2026-10-15-a2-ordinary-native-v2"
MODIFIED = {"CharacterWalkSpeed": 23, "CharacterJumpPower": 61,
            "CharacterJumpHeight": 9, "CharacterUseJumpPower": False,
            "CharacterMaxSlopeAngle": 37, "AutoJumpEnabled": False,
            "CameraMinZoomDistance": 2, "CameraMaxZoomDistance": 60,
            "CharacterBreakJointsOnDeath": False}
# A second explicit probe setting, not a claim about engine default values.
POST_JOIN = {"CharacterWalkSpeed": 31, "CharacterJumpPower": 44,
             "CharacterJumpHeight": 5.5, "CharacterUseJumpPower": True,
             "CharacterMaxSlopeAngle": 55, "AutoJumpEnabled": True,
             "CameraMinZoomDistance": 1, "CameraMaxZoomDistance": 90,
             "CharacterBreakJointsOnDeath": True}

spec = importlib.util.spec_from_file_location(
    "own_xml_helpers", HERE.parents[1] / "roblox_humanoid_experiments/build_place.py")
helpers = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(helpers)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def registration() -> dict:
    official = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert official["commit"] == PINNED_COMMIT
    available = {row["name"].split(".")[-1] for row in official["classes"]["StarterPlayer"]["members"]}
    assert set(MODIFIED) <= available
    cases = []
    for rig in ("R6", "R15"):
        for profile in ("default", "altered"):
            for session in range(1, 6):
                cases.append({"id": f"native_default_{rig.lower()}_{profile}_play{session}",
                              "requested_rig": rig, "profile": profile,
                              "session_index": session,
                              "split": "train" if session <= 3 else "holdout",
                              "path": "NATIVE_DEFAULT",
                              "prejoin_values": MODIFIED.copy() if profile == "altered" else {}})
    return {
        "schema": 1, "fixture_version": VERSION,
        "status": "PREREGISTERED_SOURCE_READY_NOT_NATIVE_OBSERVED",
        "creator_docs_commit": PINNED_COMMIT, "creator_docs_snapshot_sha256": digest(SCHEMA),
        "fixture_source_sha256": {p.name: digest(p) for p in sorted(HERE.glob("*.luau"))},
        "builder_sha256": digest(Path(__file__)),
        "reused_transport": {
            "export": "tools/roblox_character_experiments/export_zstd.commandbar.luau",
            "export_sha256": digest(HERE.parent / "export_zstd.commandbar.luau"),
            "parser": "tools/roblox_character_experiments/parse_compressed_output.py",
            "parser_sha256": digest(HERE.parent / "parse_compressed_output.py"),
            "policy": "Use existing Zstd/Base64/SHA256 transport on own telemetry only; no existing parser edited"},
        "cases": cases, "initial_join_cases": 20,
        "fixed_before_join": {"LoadCharacterAppearance": False,
                              "LuaCharacterController": "Legacy (native observed enum Value=1)",
                              "Players.CharacterAutoLoads": False},
        "default_policy": "Nine inheritance fields omitted in XML; native defaults observed, never populated from assumed numbers",
        "requested_rig_policy": "Coverage label only. No rig setting/custom Character installed. Actual RigType mismatch BLOCKED.",
        "native_description_path": "NOT_IMPLEMENTED_IN_THIS_FIRST_SLICE; separate preregistered continuation required",
        "per_session": {"initial_native_loads": 5, "post_join_native_loads": 5,
                        "initial_join_repeats": 1, "respawns_are_not_independent_joins": True},
        "post_join_values": POST_JOIN.copy(),
        "post_join_policy": "Mutate only StarterPlayer after five completed generations; record live Player/Character before/after, then five native reloads. Never copy fields to Player/Humanoid.",
        "snapshot_delays_wall_s": [0.25, 1, 3],
        "required_snapshot_points": ["CharacterAdded_immediate", "first_PostSimulation", "after_0.25s", "after_1s", "after_3s"],
        "time_basis": "Record actual os.clock arrival for every point; requested wall delay is not a simulated frame or exact timing guarantee",
        "timeouts": {"native_load_wall_s": 20, "snapshot_window_wall_s": 7,
                     "session_wall_s": 300},
        "tolerances": {"enum_name_value_domain": "exact", "boolean": "exact",
                       "scalar_numeric_abs": 1e-6, "timing": "observed distributions, no exact callback arrival assertion",
                       "lifecycle": "Compare per-realm ordered event streams; missing appearance event under appearance-disabled is recorded, not automatically FAIL"},
        "rollout_policy": "AvatarJointUpgrade/ClassicDeath NOT_OBSERVABLE without registered public readable API; no hidden settings queried",
        "noise_policy": "Five independent Play sessions per rig/profile; ambiguous lifecycle requires a separately preregistered >=10-session extension before comparison/calibration",
        "no_native_parity_pass_claim": True,
        "source_policy": "No stock Source, asset IDs, textures, models or original animation keyframes accessed/exported",
        "revision_reason": "v1 was never captured: source review found false-value serializer loss and incomplete server barrier. v2 uses explicit success branch, executable serializer regression and all-point/+3s generation validation.",
    }


def scalar(props: ET.Element, name: str, value: object) -> None:
    if isinstance(value, bool):
        ET.SubElement(props, "bool", {"name": name}).text = str(value).lower()
    elif isinstance(value, (float, int)):
        ET.SubElement(props, "float", {"name": name}).text = str(value)
    else:
        raise ValueError(f"unsupported own fixture property type: {name}")


def build_scene(config: dict, plan: dict) -> bytes:
    doc = ET.Element("roblox", {"version": "4"})
    ET.SubElement(doc, "External").text = "null"
    ET.SubElement(doc, "External").text = "nil"
    workspace, props = helpers.item(doc, "Workspace", "WORKSPACE", "Workspace")
    scalar(props, "Gravity", 196.2)
    scalar(props, "StreamingEnabled", False)
    for cls, referent, name, size, position in (
        ("Part", "BASE", "Baseplate", (512, 1, 512), (0, -0.5, 0)),
        ("SpawnLocation", "SPAWN", "OwnNativeSpawn", (12, 1, 12), (0, 0.5, 0)),
    ):
        _, props = helpers.item(workspace, cls, referent, name)
        scalar(props, "Anchored", True)
        scalar(props, "CanCollide", True)
        helpers.vector(props, "size", size)
        helpers.cf(props, "CFrame", position)
        if cls == "SpawnLocation":
            scalar(props, "Neutral", True)
    _, props = helpers.item(doc, "Players", "PLAYERS", "Players")
    scalar(props, "CharacterAutoLoads", False)
    rep, _ = helpers.item(doc, "ReplicatedStorage", "REP", "ReplicatedStorage")
    for name, data in (("OrdinarySpawnConfig", config), ("OrdinarySpawnRegistration", plan)):
        _, props = helpers.item(rep, "StringValue", name, name)
        ET.SubElement(props, "string", {"name": "Value"}).text = json.dumps(data, separators=(",", ":"))
    _, props = helpers.item(rep, "ModuleScript", "COMMON", "OrdinarySpawnCommon")
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = (HERE / "common.luau").read_text(encoding="utf-8")
    server, _ = helpers.item(doc, "ServerScriptService", "SERVER", "ServerScriptService")
    _, props = helpers.item(server, "Script", "SETUP", "OrdinarySpawnSetup")
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = (HERE / "setup.server.luau").read_text(encoding="utf-8")
    starter, props = helpers.item(doc, "StarterPlayer", "STARTER", "StarterPlayer")
    scalar(props, "LoadCharacterAppearance", False)
    ET.SubElement(props, "token", {"name": "LuaCharacterController"}).text = "1"
    for key, value in config["prejoin_values"].items():
        scalar(props, key, value)
    scripts, _ = helpers.item(starter, "StarterPlayerScripts", "CLIENTS", "StarterPlayerScripts")
    _, props = helpers.item(scripts, "LocalScript", "MEASURE", "OrdinarySpawnMeasurement")
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = (HERE / "measure.client.luau").read_text(encoding="utf-8")
    # No custom StarterCharacter, StarterHumanoid or StarterCharacterScripts.
    ET.indent(doc, space="  ")
    return ET.tostring(doc, encoding="utf-8", xml_declaration=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "generated_v2")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Refusing to overwrite preregistration/fixtures; choose a new output directory")
    compiler = HERE.parent / ".compiler/luau-compile.exe"
    if not compiler.is_file():
        raise SystemExit("Official local Luau compiler unavailable; native fixtures not written")
    subprocess.run([str(compiler), "--null", *map(str, sorted(HERE.glob("*.luau")))], check=True)
    plan = registration()
    args.output.mkdir(parents=True)
    with (args.output / "registration.json").open("x", encoding="utf-8") as stream:
        json.dump(plan, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    places = {}
    for config in plan["cases"]:
        path = args.output / (config["id"] + ".rbxlx")
        with path.open("xb") as stream:
            stream.write(build_scene(config, plan))
        places[path.name] = digest(path)
    with (args.output / "places_manifest.json").open("x", encoding="utf-8") as stream:
        json.dump({"scope": "preregistered source-ready native places; no Play capture performed",
                   "registration_sha256": digest(args.output / "registration.json"),
                   "place_sha256": places}, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"status": "SOURCE_READY_NOT_NATIVE_OBSERVED", "sessions": len(places),
                      "registration": str(args.output / "registration.json")}, ensure_ascii=True))


if __name__ == "__main__":
    main()
