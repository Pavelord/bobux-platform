"""Snapshot the existing character implementation without changing Git/index.

This preserves unrelated work and records protected files before parity edits.
Only source files are copied; large assets and credentials are not collected.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PROTECTED = ["scripts/place_editor/studio.gd", "scripts/main/main.gd",
             "addons/rbxl_importer/rbxl_runtime_importer.gd"]
SOURCE_PATHS = ["scripts/player", "addons/roblox_runtime/roblox_humanoid_motor.gd",
                "autoload/lua_script_engine.gd", "autoload/imported_place_network.gd",
                "autoload/mobile_runtime.gd", "native/luau_bridge", "project.godot"]
SUFFIXES = {".gd", ".tres", ".tscn", ".cpp", ".h", ".hpp", ".lua", ".luau", ".godot"}

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True,
                                   encoding="utf-8", errors="replace")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        raise SystemExit("Baseline already exists; choose a fresh output directory")
    out.mkdir(parents=True)
    (out / "git-status.txt").write_text(git("status", "--porcelain=v1", "--untracked-files=all"), encoding="utf-8")
    (out / "git-index.txt").write_text(git("diff", "--cached", "--name-status"), encoding="utf-8")
    source_files = []
    for relative in SOURCE_PATHS:
        path = ROOT / relative
        source_files.extend([path] if path.is_file() else
                            [p for p in path.rglob("*") if p.is_file() and p.suffix in SUFFIXES] if path.is_dir() else [])
    records = {}
    for path in sorted(set(source_files)):
        relative = path.relative_to(ROOT).as_posix()
        records[relative] = {"sha256": sha(path), "bytes": path.stat().st_size}
        target = out / "sources" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    protected = {p: {"exists": (ROOT / p).is_file(),
                      "sha256": sha(ROOT / p) if (ROOT / p).is_file() else None} for p in PROTECTED}
    # Prior instruction names map_format.gd, but it is absent in this checkout.
    protected["**/map_format.gd"] = {"exists": False, "policy": "protect every matching filename; absent in initial workspace search"}
    empirical = ROOT / "tests/roblox_humanoid/2026-10-13.empirical.json"
    calibration = ROOT / ".codex-tmp/performance/humanoid-empirical-calibration.json"
    for source, name in [(empirical, "empirical-2026-10-13.json"), (calibration, "calibration-baseline.json")]:
        if source.is_file():
            shutil.copy2(source, out / name)
    report = {"schema": 1, "captured_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "head": git("rev-parse", "HEAD").strip(), "branch": git("branch", "--show-current").strip(),
              "source_files": records, "protected_files": protected,
              "empirical_sha256": sha(empirical),
              "starting_calibration": {"pass": 48, "fail": 5, "skip": 18, "blocked": 0},
              "git_policy": "No reset, staging, commit, or checkout performed by this snapshot"}
    (out / "baseline.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Captured {len(records)} source files; preserved Studio run02 hash {report['empirical_sha256']}")

if __name__ == "__main__":
    main()
