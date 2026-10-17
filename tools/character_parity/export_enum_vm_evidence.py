"""Freeze the verified production boundary evidence without changing old runs."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
TMP = ROOT / ".codex-tmp/character_parity"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_once(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        assert source.read_bytes() == destination.read_bytes(), f"Refusing overwrite: {destination}"
    else:
        shutil.copyfile(source, destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", default="tests/roblox_humanoid/phase_a/enum_vm_boundary_20261015")
    parser.add_argument("--parity-run", type=int, default=11)
    parser.add_argument("--legacy-run", type=int, default=12)
    parser.add_argument("--expected-checks", type=int, default=34)
    parser.add_argument("--failures", default="1,2,3,4,6,7,8,10")
    parser.add_argument("--extra-failure-log", type=Path, action="append", default=[],
                        help="An additional own development log to preserve in this fresh snapshot")
    parser.add_argument("--archive-sources", action="store_true")
    parser.add_argument("--include-camera-contract", action="store_true",
                        help="Freeze the real Camera3D consumer contract with this fresh evidence set")
    parser.add_argument("--regression-dir", type=Path, help="Fresh runner directory containing player/NPC contract logs")
    parser.add_argument("--vm-results-dir", type=Path, help="Fresh runner directory containing enum-vm-<order> reports/logs")
    options = parser.parse_args()
    dest = ROOT / options.destination
    results = {}
    for run, order in [(options.parity_run, "parity-first"), (options.legacy_run, "legacy-first")]:
        for extension in ["json", "log"]:
            source = (options.vm_results_dir / f"enum-vm-{order}.{extension}" if options.vm_results_dir
                      else TMP / f"enum-vm-boundary-r{run:02}.{extension}")
            copy_once(source, dest / f"{order}.{extension}")
        data = json.loads((dest / f"{order}.json").read_text(encoding="utf-8"))
        assert data["pass"] == options.expected_checks and data["fail"] == 0
        results[order] = {"pass": data["pass"], "fail": data["fail"], "sha256": sha(dest / f"{order}.json")}
    for kind, expected in [("player", 40), ("npc", 16)]:
        source = options.regression_dir / f"{kind}-contract.log" if options.regression_dir else TMP / f"enum-vm-{kind}-r01.log"
        text = source.read_text(encoding="utf-8")
        assert text.count(f"[humanoid-{kind}] PASS ") == expected
        assert "SCRIPT ERROR" not in text and f"[humanoid-{kind}] FAIL " not in text
        copy_once(source, dest / f"{kind}.log")
        results[kind] = {"pass": expected, "fail": 0, "sha256": sha(source)}
    # Preserve failed development runs, including the now-fixed cyclic-input
    # native conversion crash. They are failures, never native observations.
    failures = []
    for run in [int(value) for value in options.failures.split(",") if value]:
        for extension in ["log", "json"]:
            source = TMP / f"enum-vm-boundary-r{run:02}.{extension}"
            if source.exists():
                destination = dest / "development_failures" / source.name
                copy_once(source, destination)
                failures.append({"path": str(destination.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(source)})
    for extra in options.extra_failure_log:
        source = extra.resolve()
        source.relative_to(ROOT)
        assert source.suffix == ".log", "Only an explicitly selected own development log is accepted"
        destination = dest / "development_failures" / source.name
        copy_once(source, destination)
        failures.append({"path": str(destination.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(source)})
    source_paths = [
        "autoload/lua_script_engine.gd",
        "addons/roblox_runtime/enums/roblox_enum_vm_boundary.gd",
        "tools/character_parity/enum_vm_contract.luau",
        "tools/character_parity/validate_enum_vm_boundary.gd",
        "tools/character_parity/check_enum_vm_sources.py",
    ]
    if options.expected_checks > 34:
        source_paths.append("tools/character_parity/enum_vm_cyclic_contract.luau")
    if options.expected_checks > 36:
        source_paths.append("tools/character_parity/enum_vm_humanoid_edges_contract.luau")
    if options.include_camera_contract:
        source_paths.append("tools/character_parity/enum_vm_camera_contract.luau")
    source_paths += ["addons/roblox_runtime/enums/" + name for name in
                     ("roblox_enum_registry.gd", "roblox_enum_item.gd", "roblox_enum_type.gd", "roblox_enums.gd")]
    if options.archive_sources:
        for source in source_paths:
            copy_once(ROOT / source, dest / "source_snapshot" / source)
    manifest = {
        "date_local": "2026-10-15", "timezone": "Europe/Kaliningrad",
        "status": "PASS_MINIMAL_OPT_IN_SLICE", "godot": "4.7.stable.official.5b4e0cb0f", "luau_runtime": "0.719",
        "results": results,
        "consumer_scope": ["Humanoid state methods/signals"] +
                          (["Camera.CameraType: typed getter, strict setter, scalar storage; camera algorithms and event ordering remain partial"]
                           if options.include_camera_contract else []),
        "source_sha256": {path: sha(ROOT / path) for path in source_paths},
        "native_reference_sha256": {path: sha(ROOT / path) for path in [
            "tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-coercion-run01.raw.json",
            "tests/roblox_humanoid/phase_a/2026-10-15-studio-humanoid-edges-run01.raw.json"]
            if (ROOT / path).is_file()},
        "dirty_snapshot_sha256": sha(TMP / "pre_vm_integration/lua_script_engine.gd"),
        "development_failures": failures,
        "open": ["complete enum namespace", "typed boundaries for all other enum properties", "remaining bool casts and noncanonical ChangeState coercion", "generic BindableEvent EnumItem interop between registries", "tagged wire codec and explicit capability negotiation", "generic BobuxEvent equality (rawequal identity verified; default Object equality remains unchanged)", "Humanoid physical/default-state calibration"],
        "unchanged": ["ExistingNumericEnums default", "protected production files", "native C++", "map sources", "historical 48 PASS / 5 FAIL / 18 SKIP calibration"],
    }
    path = dest / "manifest.json"
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if path.exists():
        assert path.read_text(encoding="utf-8") == encoded, "Refusing manifest overwrite"
    else:
        path.write_text(encoded, encoding="utf-8")
    print(json.dumps({"destination": str(dest), "results": results}, indent=2))


if __name__ == "__main__":
    main()
