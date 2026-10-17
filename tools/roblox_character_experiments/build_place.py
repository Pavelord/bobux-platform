"""Separate lawful black-box Roblox places; embeds only Bobux-authored probes."""
from pathlib import Path
import argparse
import importlib.util
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
spec = importlib.util.spec_from_file_location("old_builder", HERE.parent / "roblox_humanoid_experiments/build_place.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)


def matrix(fixture_version="2026-10-14-a1", baseplate_size=(220, 1, 100)):
    cases = []
    geometries = ["smooth_tall_block", "thin_part", "regular_parts_ladder", "single_ledge", "truss"]
    for geometry in geometries:
        for repeat in range(1, 6):
            cases.append(dict(id=f"r6_{geometry}_ws16_r{repeat}", geometry=geometry,
                              rig="R6", WalkSpeed=16, repeat=repeat,
                              split="train" if repeat <= 3 else "holdout"))
    for geometry in ["regular_parts_ladder", "truss"]:
        for speed in [8, 32]:
            for repeat in range(1, 6):
                cases.append(dict(id=f"r6_{geometry}_ws{speed}_r{repeat}", geometry=geometry,
                                  rig="R6", WalkSpeed=speed, repeat=repeat,
                                  split="train" if repeat <= 3 else "holdout"))
    return dict(schema=1, fixture_version=fixture_version, profile="classic_humanoid",
                fixture_source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in HERE.glob("*.luau")},
                cases=cases, durations=dict(active_sim_s=6.0, settle_wall_s=6.0, native_load_wall_s=20.0, global_wall_s=540),
                support_geometry=dict(baseplate=dict(size=list(baseplate_size), pos=[0, -0.5, 0],
                                      class_name="Part", anchored=True, can_collide=True),
                                      provenance="Own fixture landing support, not an obstacle/ladders detection parameter"),
                reset_policy=dict(stop_move_before_teleport=True, zero_linear_and_angular_velocity=True,
                                  native_reload_if_life_invalid=True, max_preprocessing_reloads_per_case=2,
                                  no_measured_case_retries=True, forced_state="Freefall only during preprocessing; never Climbing"),
                tolerances=dict(speeds_relative=0.10, distances_studs=0.10,
                                states="exact observed sequence; durations compared as distributions/physical callback steps",
                                sensor="exact observed part/nil; no assertion of hidden internal sensor identity"),
                noise_policy="Five completed trials per condition. If trajectory/state spread indicates noise, BLOCKED for calibration until separately preregistered ten-repeat extension.",
                fixture_geometry={
                    "smooth_tall_block": dict(x=-60, parts=[dict(name="SmoothBlock", size=[12, 32, 8], pos=[-60, 16, 0], class_name="Part")]),
                    "thin_part": dict(x=-30, parts=[dict(name="ThinPart", size=[10, 32, 0.4], pos=[-30, 16, 0], class_name="Part")]),
                    "regular_parts_ladder": dict(x=0, parts=[dict(name=f"Rung{i:02d}", size=[8, 0.5, 1], pos=[0, 0.5 + i * 1.5, 0], class_name="Part") for i in range(22)]),
                    "single_ledge": dict(x=30, parts=[dict(name="SingleLedge", size=[12, 4, 8], pos=[30, 2, 0], class_name="Part")]),
                    "truss": dict(x=60, parts=[dict(name="Truss", size=[2, 32, 2], pos=[60, 16, 0], class_name="TrussPart")])},
                sensor_settings=dict(SearchDistance=3.0, LadderSearchHeight=6.0, LadderSearchOffset=0.0,
                                     provenance="ENGINE_APPROXIMATION fixture settings, not inferred Humanoid thresholds", UpdateType="OnRead"))


def build(mode, output=None, fixture_version="2026-10-14-a1", baseplate_size=(220, 1, 100), registration=None):
    doc = ET.Element("roblox", {"version": "4"})
    ET.SubElement(doc, "External").text = "null"
    ET.SubElement(doc, "External").text = "nil"
    workspace, props = old.item(doc, "Workspace", "WORKSPACE", "Workspace")
    ET.SubElement(props, "float", {"name": "Gravity"}).text = "196.2"
    ET.SubElement(props, "bool", {"name": "StreamingEnabled"}).text = "false"
    _, p = old.item(workspace, "Part", "BASE", "Baseplate")
    ET.SubElement(p, "bool", {"name": "Anchored"}).text = "true"
    ET.SubElement(p, "bool", {"name": "CanCollide"}).text = "true"
    old.vector(p, "size", baseplate_size)
    old.cf(p, "CFrame", (0, -0.5, 0))
    ET.SubElement(p, "token", {"name": "TopSurface"}).text = "0"
    ET.SubElement(p, "token", {"name": "BottomSurface"}).text = "0"
    old.item(doc, "Players", "PLAYERS", "Players")
    rep, _ = old.item(doc, "ReplicatedStorage", "REP", "ReplicatedStorage")
    _, p = old.item(rep, "StringValue", "MODE", "CharacterExperimentMode")
    ET.SubElement(p, "string", {"name": "Value"}).text = mode
    _, p = old.item(rep, "StringValue", "MATRIX", "CharacterExperimentMatrix")
    data = registration if registration is not None else matrix(fixture_version, baseplate_size)
    ET.SubElement(p, "string", {"name": "Value"}).text = json.dumps(data, separators=(",", ":"))
    for name, source in [("CharacterExperimentCommon", "common.luau"), ("StandardScriptMetadataProbe", "metadata_probe.luau")]:
        _, p = old.item(rep, "ModuleScript", name.upper(), name)
        ET.SubElement(p, "ProtectedString", {"name": "Source"}).text = (HERE / source).read_text(encoding="utf-8")
    server, _ = old.item(doc, "ServerScriptService", "SERVER", "ServerScriptService")
    _, p = old.item(server, "Script", "SETUP", "CharacterExperimentSetup")
    ET.SubElement(p, "ProtectedString", {"name": "Source"}).text = (HERE / "setup.server.luau").read_text(encoding="utf-8")
    starter, p = old.item(doc, "StarterPlayer", "STARTER", "StarterPlayer")
    ET.SubElement(p, "bool", {"name": "LoadCharacterAppearance"}).text = "false"
    ET.SubElement(p, "token", {"name": "LuaCharacterController"}).text = "1"  # Legacy, independent from CCL.
    scripts, _ = old.item(starter, "StarterPlayerScripts", "CLIENTS", "StarterPlayerScripts")
    _, p = old.item(scripts, "LocalScript", "MEASURE", "CharacterBlackBoxMeasurement")
    ET.SubElement(p, "ProtectedString", {"name": "Source"}).text = (HERE / "measure.client.luau").read_text(encoding="utf-8")
    old.item(starter, "StarterCharacterScripts", "CHAR_SCRIPTS", "StarterCharacterScripts")
    ET.indent(doc, space="  ")
    path = Path(output) if output else HERE / ("CharacterPhaseA.rbxlx" if mode == "phase_a" else "CharacterClimbBaseline.rbxlx")
    ET.ElementTree(doc).write(path, encoding="utf-8", xml_declaration=True)
    print(f"{path}: {path.stat().st_size} bytes")
    return path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--climb-run02", action="store_true", help="Create separate life-safe fixture; leave old places/splits intact")
    args = parser.parse_args()
    compiler = HERE / ".compiler/luau-compile.exe"
    if compiler.exists():
        subprocess.run([str(compiler), "--null", *[str(p) for p in HERE.glob("*.luau")]], check=True)
    target = ROOT / "tests/roblox_humanoid/phase_a"
    target.mkdir(parents=True, exist_ok=True)
    if args.climb_run02:
        version = "2026-10-14-climb-a2-life-safe"
        size = (512, 1, 512)
        scene = HERE / "CharacterClimbBaseline_run02.rbxlx"
        splits = target / "climb_run02.splits.json"
        if scene.exists() or splits.exists():
            raise SystemExit("Refusing to overwrite run02 fixture/evidence registration")
        data = matrix(version, size)
        original = json.loads((target / "splits.json").read_text(encoding="utf-8"))
        assert data["cases"] == original["cases"], "registered cases/splits changed"
        assert data["fixture_geometry"] == original["fixture_geometry"], "registered obstacle geometry changed"
        data["revision_reason"] = "run01 lost Character after leaving 100-stud-deep support plane; enlarge support only and make reset life-safe"
        data["previous_support_geometry"] = dict(size=[220, 1, 100], pos=[0, -0.5, 0])
        splits.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        build("climb_baseline", scene, version, size, registration=data)
    else:
        (target / "splits.json").write_text(json.dumps(matrix(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        for mode in ["phase_a", "climb_baseline"]:
            build(mode)
