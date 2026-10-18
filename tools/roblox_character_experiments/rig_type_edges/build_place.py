"""Prepare isolated public Humanoid.RigType probes; no fixtures freeze by default.

Root review must precede explicit --freeze-reviewed. Only a new output directory
is accepted. This builder is self-contained and does not edit shared helpers.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCHEMA = ROOT / "tests/roblox_humanoid/phase_a/creator_docs_api.json"
PINNED_COMMIT = "031b2f91d3d47274c255f3ed5691c29f792c181d"
VERSION = "2026-10-17-a3-rig-type-edges-v1"
SEED = 20261016
VARIANTS = (
    ("matching_enum", "Enum.HumanoidRigType[target]"),
    ("number", "target.Value"),
    ("bare_name", "target.Name"),
    ("numeric_string", "tostring(target.Value)"),
    ("positive_fraction", "target.Value + 0.5"),
    ("negative_fraction", "-0.5; independent of target label"),
    ("wrong_domain", "Enum.CameraType.Fixed; same numeric value as R6, different domain"),
    ("full_name_string", "tostring(target EnumItem)"),
    ("nil", "nil; explicit tagged nil in telemetry"),
    ("boolean_false", "false; preserved as boolean"),
    ("boolean_true", "true; preserved as boolean"),
    ("empty_table", "new empty table"),
    ("negative_number", "-1"),
    ("invalid_number", "999999"),
    ("invalid_name", '"BOBUX_NONEXISTENT_ITEM"'),
    ("nan", "0/0; tagged special=nan, never a raw JSON number"),
    ("positive_inf", "math.huge; tagged special=positive_inf"),
    ("negative_inf", "-math.huge; tagged special=negative_inf"),
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def deterministic_permutation(values: list, seed: int) -> list:
    """Frozen 32-bit LCG Fisher-Yates, independent of Python random versions."""
    result = values.copy()
    state = seed
    for index in range(len(result) - 1, 0, -1):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        swap = state % (index + 1)
        result[index], result[swap] = result[swap], result[index]
    return result


def registration() -> dict:
    official = json.loads(SCHEMA.read_text(encoding="utf-8"))
    if official["commit"] != PINNED_COMMIT:
        raise ValueError("pinned official creator-docs snapshot changed")
    member = next(value for value in official["classes"]["Humanoid"]["members"]
                  if value["name"] == "Humanoid.RigType")
    if member["type"] != "HumanoidRigType" or member["security"] != {"read": "None", "write": "None"} or "ReadOnly" in member["tags"]:
        raise ValueError("public readable/writable Humanoid.RigType schema differs")
    cases = []
    for context in ("fresh_unparented", "fresh_workspace"):
        for baseline in ("R6", "R15"):
            for target in ("R6", "R15"):
                for variant, _ in VARIANTS:
                    cases.append({"id": f"{context}_baseline_{baseline.lower()}_target_{target.lower()}_{variant}",
                                  "context": context, "baseline": baseline,
                                  "target": target, "variant": variant})
    cases = deterministic_permutation(cases, SEED)
    for ordinal, case in enumerate(cases, 1):
        case["ordinal"] = ordinal
    return {
        "schema": 1, "fixture_version": VERSION,
        "status": "PREREGISTERED_SOURCE_READY_NOT_NATIVE_OBSERVED",
        "creator_docs_commit": PINNED_COMMIT, "creator_docs_snapshot_sha256": digest(SCHEMA),
        "fixture_source_sha256": {path.name: digest(path) for path in sorted(HERE.glob("*.luau"))},
        "builder_sha256": digest(Path(__file__)),
        "source_test_sha256": digest(HERE / "test_fixture.py"),
        "reused_transport": {
            "export": "tools/roblox_character_experiments/export_zstd.commandbar.luau",
            "export_sha256": digest(HERE.parent / "export_zstd.commandbar.luau"),
            "parser": "tools/roblox_character_experiments/parse_compressed_output.py",
            "parser_sha256": digest(HERE.parent / "parse_compressed_output.py"),
            "folder": "CharacterExperimentTelemetry",
            "policy": "Existing immutable exporter/parser; generic climbing baseline_summary is not RigType analysis"},
        "sessions": [{"id": f"rig_type_edges_play{index}", "session_index": index,
                      "split": "train" if index <= 3 else "holdout", "seed": SEED}
                     for index in range(1, 6)],
        "cases": cases, "cases_per_Play": 144, "required_independent_Play_sessions": 5,
        "variant_descriptions": [{"id": name, "construction": text} for name, text in VARIANTS],
        "order": {"seed": SEED,
                  "algorithm": "LCG32 state=(1664525*state+1013904223)&0xffffffff; descending Fisher-Yates swap=state%(i+1)",
                  "policy": "Same frozen 144-case permutation in each independent Play; no adaptive reordering"},
        "target_policy": "Target name selects input construction only; resulting getter/error/events are native observations, never expected outcomes",
        "contexts": {
            "fresh_unparented": "New Instance.new Humanoid; Parent nil",
            "fresh_workspace": "New Instance.new Humanoid; Parent Workspace directly, without Model/skeleton/body parts"},
        "fresh_default_policy": "Read before parenting and in measured context; never assert R6 as an experimental input",
        "baseline_policy": "Own matching EnumItem setter, immediate getter, one settle Heartbeat and exact getter validation; baseline failure BLOCKED without target call or retry",
        "baseline_settle_Heartbeats": 1, "observation_Heartbeats_after_setter": 2,
        "required_points": ["before_setter", "immediate_after_setter", "after_Heartbeat_1", "after_Heartbeat_2"],
        "signals": ["GetPropertyChangedSignal(RigType)", "Changed"],
        "signal_policy": "Attach after baseline settle. Preserve actual callback order, arguments, getter, counts and wall/simulation callback clocks; no asserted count or exclusion of later callbacks",
        "timing_policy": "Actual os.clock wall time, Heartbeat ordinal/dt and accumulated callback dt; no assumed fixed frame length, physical/render timing or cross-realm synchronization",
        "rollout_policy": "No hidden Avatar settings, Player.Character, description/model factories, assets or stock Source accessed",
        "fixed_XML_input": {"Players.CharacterAutoLoads": False},
        "timeouts": {"session_wall_s": 300}, "limits": {"recorded_events_per_case": 64},
        "coverage_policy": "144 independent fresh scalar targets in a Play are one Play session, never 144 independent Play repeats",
        "noise_policy": "If setter/getter/event outcomes vary across five independent Plays, preserve them and preregister a separate >=10-Play extension before comparison or fitting",
        "no_fit": True, "no_parity_pass_claim": True, "no_physical_rig_claim": True,
    }


def item(parent: ET.Element, class_name: str, referent: str, name: str):
    node = ET.SubElement(parent, "Item", {"class": class_name, "referent": referent})
    props = ET.SubElement(node, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    return node, props


def build_scene(config: dict, plan: dict) -> bytes:
    doc = ET.Element("roblox", {"version": "4"})
    ET.SubElement(doc, "External").text = "null"
    ET.SubElement(doc, "External").text = "nil"
    item(doc, "Workspace", "WORKSPACE", "Workspace")
    _, props = item(doc, "Players", "PLAYERS", "Players")
    ET.SubElement(props, "bool", {"name": "CharacterAutoLoads"}).text = "false"
    rep, _ = item(doc, "ReplicatedStorage", "REP", "ReplicatedStorage")
    for name, value in (("RigTypeEdgesConfig", config), ("RigTypeEdgesRegistration", plan)):
        _, props = item(rep, "StringValue", name, name)
        ET.SubElement(props, "string", {"name": "Value"}).text = json.dumps(value, separators=(",", ":"), allow_nan=False)
    _, props = item(rep, "ModuleScript", "COMMON", "RigTypeEdgesCommon")
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = (HERE / "common.luau").read_text(encoding="utf-8")
    server, _ = item(doc, "ServerScriptService", "SERVER", "ServerScriptService")
    _, props = item(server, "Script", "PROBE", "RigTypeEdgesProbe")
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = (HERE / "probe.server.luau").read_text(encoding="utf-8")
    ET.indent(doc, space="  ")
    return ET.tostring(doc, encoding="utf-8", xml_declaration=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--freeze-reviewed", action="store_true", help="Root has reviewed these source files; freeze new fixtures explicitly")
    args = parser.parse_args()
    if not args.freeze_reviewed:
        raise SystemExit("Source-only until root review; no files created. After review pass --freeze-reviewed explicitly.")
    if args.output.exists():
        raise SystemExit("Refusing to overwrite registration/fixtures; choose a new output directory")
    compiler = HERE.parent / ".compiler/luau-compile.exe"
    if not compiler.is_file():
        raise SystemExit("Official local Luau compiler unavailable; no fixtures written")
    subprocess.run([str(compiler), "--null", *map(str, sorted(HERE.glob("*.luau")))], check=True)
    plan = registration()
    args.output.mkdir(parents=True)
    with (args.output / "registration.json").open("x", encoding="utf-8") as handle:
        json.dump(plan, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
    places = {}
    for config in plan["sessions"]:
        path = args.output / (config["id"] + ".rbxlx")
        with path.open("xb") as handle:
            handle.write(build_scene(config, plan))
        places[path.name] = digest(path)
    with (args.output / "places_manifest.json").open("x", encoding="utf-8") as handle:
        json.dump({"scope": "Frozen own native scalar places; native Play NOT_RUN",
                   "registration_sha256": digest(args.output / "registration.json"),
                   "place_sha256": places}, handle, indent=2)
        handle.write("\n")
    print(json.dumps({"status": "SOURCE_READY_NOT_NATIVE_OBSERVED", "sessions": len(places),
                      "cases_per_Play": len(plan["cases"]), "registration": str(args.output / "registration.json")}))


if __name__ == "__main__":
    main()
