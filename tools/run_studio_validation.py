"""Run offline Godot Studio regressions; script errors fail even with exit code 0."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TESTS = [
    "validate_studio_double_jump", "validate_lua_input", "validate_lua_async_tween",
    "validate_lua_runtime_regressions", "validate_lua_scheduler",
    "validate_luau_compatibility", "validate_lua_service_compatibility",
    "validate_lua_cframe_runtime", "validate_lua_instruction_budget",
    "validate_lua_click_detector_runtime", "validate_lua_fire_runtime",
    "validate_studio_ai_builder", "validate_studio_ai_response_contract",
    "validate_studio_ai_runtime", "validate_studio_ai_physics",
    "validate_roblox_inventory_runtime", "validate_studio_playtest_character",
    "validate_player_humanoid_states", "validate_player_climbing",
    "validate_large_map_loading",
    "validate_lua_gameplay_primitives", "validate_main_script_lifecycle",
    "validate_player_wall_steps", "validate_studio_movement_scripts",
    "validate_studio_gui_inventory", "validate_studio_weapons_npc",
    "validate_studio_explorer_library", "validate_toolbox_asset_library",
]

def main():
    # Godot may log Cyrillic and tree glyphs on a legacy Windows console.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", default=DEFAULT_TESTS)
    parser.add_argument("--godot", default=str(ROOT / ".codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"))
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    output_dir = ROOT / ".codex-tmp/studio_validation"
    output_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name in args.tests:
        if not name.startswith("validate_") or not name.replace("_", "").isalnum():
            parser.error("Supply validation script names without path or extension")
        start = time.monotonic()
        try:
            result = subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--script", f"tools/{name}.gd"],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=args.timeout, encoding="utf-8", errors="replace",
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            output = result.stdout
            ok = result.returncode == 0 and "SCRIPT ERROR:" not in output and "ERROR:" not in output
            code = result.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            output += "\nVALIDATION TIMEOUT\n"
            ok, code = False, None
        (output_dir / f"{name}.log").write_text(output, encoding="utf-8")
        row = {"test": name, "ok": ok, "exit_code": code, "seconds": round(time.monotonic() - start, 2)}
        results.append(row)
        print(json.dumps(row), flush=True)
        if not ok:
            print(output[-5000:], flush=True)
    (output_dir / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 0 if all(row["ok"] for row in results) else 1

if __name__ == "__main__":
    raise SystemExit(main())
