# Character parity checks

Run commands from `C:\robloxclone`. Results are local regressions, not proof that a character phase or Roblox parity is complete. Historical empirical calibration is not regenerated.

During a native Studio capture, use only the Python checks:

```powershell
python tools/character_parity/run_checks.py --offline
```

After closing Roblox Studio, run Python checks and the sequential Godot suite:

```powershell
python tools/character_parity/run_checks.py
```

Godot defaults to `.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe`; override it with `--godot <path>`. The full runner refuses to proceed while Studio is running and does not stop processes itself.

The Godot suite covers the EnumItem kernel, both VM creation orders, player/NPC contracts, Luau scheduling, native callback guard, and property cache. `validate_enum_vm_boundary.gd` uses `--parity-first` for parity first; **no order flag** means legacy first. Both enum validators accept `--report=<fresh path>` after Godot's `--` separator.

Each invocation creates a fresh `.codex-tmp/character_parity/suites/<UTC timestamp>-<id>/` with per-check logs and the aggregate `report.json`. The full suite also writes three enum JSON reports. To choose a destination, pass `--output <new-directory>`; existing directories are refused. `--baseline <snapshot-directory>` also checks protected sources and frozen evidence against the saved dirty baseline, allowing the reviewed `autoload/lua_script_engine.gd` phase change.

Additional reviewed differences require an explicit `--allow-baseline-source <exact-path>`. This never bypasses protected-file hash checks. On 15 October the editor only moved the unchanged clear-color setting inside `project.godot`; that reviewed order-only change can be declared with `--allow-baseline-source project.godot`. Do not add paths without inspecting their actual diff.

For a focused rerun, repeat `--only <check-name>` (for example `--only enum-kernel --only enum-vm-parity-first --only enum-vm-legacy-first`). Omitted checks are listed as `not_selected`; a selected PASS does not imply the full suite passed. Unknown check names are rejected.

The runner does not perform Android or visual comparison, old/new peer negotiation, the 20-player/100-NPC load case, or historical calibration.
