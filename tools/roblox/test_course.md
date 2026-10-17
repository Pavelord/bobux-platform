# R6 Humanoid trace course

The authoritative layout and deterministic inputs are in [`tools/scenarios.json`](../scenarios.json). The Godot trace stand builds every fixture from that file. In Roblox Studio, `scenario_runner.lua` builds the same anchored `Part` and `TrussPart` fixtures from the JSON copied into its `ScenarioData` StringValue.

All positions and dimensions in the scenario file are studs. The course uses separate start pads so a run starts at the listed HRP position without another fixture affecting it.

`humanoid_config.tres` defaults to `CollisionType = "OuterBox"`, which uses part sizes from `part_dump.csv` when available. Setting it to `"InnerBox"` uses the fixed-size candidate boxes listed in the resource; those dimensions remain `TODO_MEASURE` until they are checked against Roblox.

## Fixture coverage

| Fixture | Scenario names | Course cases |
| --- | --- | --- |
| Ledges | `jump_ledge_0_5`, `jump_ledge_1`, `jump_ledge_1_5`, `jump_ledge_2`, `jump_ledge_3`, `jump_ledge_4`, `jump_ledge_5`, `jump_ledge_6_5` | Vertical faces at 0.5, 1, 1.5, 2, 3, 4, 5, and 6.5 studs, each with a landing top |
| Stairs | `walk_stairs` | Four consecutive rises of 0.5, 1, 1.5, and 2 studs |
| Slope | `walk_slope` | A thin block rotated 20 degrees about X |
| Narrow beams | `walk_beam_width_1`, `walk_beam_width_2`, `land_narrow_beam` | Walk across 1 and 2 stud widths; fall from above onto a 1 stud beam |
| Edges and corner | `walk_edge_slow`, `walk_corner_slow` | Low speed overhang at a straight edge and diagonally over a platform corner |
| Wall | `jump_wall_close` | Jump pressed while moving into a close wall |
| Truss | `truss_approach_*`, `truss_approach_angled`, `truss_climb_up`, `truss_climb_down`, `truss_exit_top`, `truss_release`, `truss_jump_off`, `truss_next_to_ledge` | Approach from four horizontal directions, use a tilted TrussPart, climb both ways, reach the top, stop, jump away, and approach beside a ledge |
| General movement and landing | `walk_start_stop`, `jump_stationary`, `jump_run`, `fall_from_height_landed` | Start/stop, stationary and running jumps, and a fall ending in Landed |

The straight-edge run adds `edge_overhang_studs` to each trace row. On the first Freefall sample, the logger estimates how far the leading edge of either foot extends beyond the last supporting part. The Godot trace computes the same geometric quantity from its last floor contact. Empty values mean the support part or movement direction was unavailable.

## Studio setup

1. Create a new Baseplate place and set **Avatar Type** to **R6** in Game Settings. Keep the normal player `Humanoid`; do not add a ControllerManager.
2. Add `trace_logger.lua`, `part_dump.lua`, `sensor_logger.lua`, and `scenario_runner.lua` as separate **LocalScripts** under `StarterPlayer > StarterPlayerScripts`.
3. Under `scenario_runner.lua`, add a `StringValue` named `ScenarioData`. Paste the complete contents of `tools/scenarios.json` into its `Value`.
4. Run **Play** (F5) in a single-player Studio session. The runner creates the course, sets `Workspace.R6Scenario` before each sequence, and calls `Humanoid:Move()` with the JSON's world-space directions. Jump is a one-tick input. `climb_axis` is -1 for down and +1 for up. The trace logger writes the active scenario name and actual `dt` for every sample.
5. Open **View > Output**. Confirm that `R6TRACE_COLUMNS` and `R6PART_COLUMNS` appear and that `R6SCENARIO_RUN_COMPLETE` is printed. Check `R6PART_META` for CollisionType, HipHeight, and RigType.
6. To test sensors on the ordinary live Humanoid, keep `sensor_logger.lua` enabled. Look for `R6SENSOR_STATUS` and `R6SENSOR` rows. `CREATED`/`OK` confirms instance creation and readable properties; `sensed_part` (Roblox's current API property is `SensedPart`) should become non-empty on the floor or ladder fixture. The same rows contain an explicit raycast fallback. A create/read error, or an always-empty sensed part while the fallback hits, means the sensor did not provide useful data in this live-Humanoid setup.
7. In Output, use **Copy All** and save the text as `tests/roblox_traces/studio_output.txt` in the project checkout. From the repository root run:

   ```powershell
   python tools\roblox\collect_roblox_traces.py tests\roblox_traces\studio_output.txt
   ```

   This writes one `tests/roblox_traces/roblox/<scenario>.csv`, `part_dump.csv`, `part_dump_meta.txt`, and `sensor_logger.csv` when those rows are present. `part_dump.csv` is read automatically by `CharacterCollider` on the next Godot run.

## Godot capture and comparison

1. Open `tools/godot/humanoid_trace_stand.tscn` and run the current scene (F6). It builds from the same JSON, plays every scenario, writes one CSV per scenario, then exits. The Output panel prints the resolved `user://roblox_humanoid_traces/godot` directory.
2. Copy those Godot CSV files into `tests/roblox_traces/godot/`.
3. Run:

   ```powershell
   python tools\compare_traces.py --studio tests\roblox_traces\roblox --godot tests\roblox_traces\godot
   ```

   The table reports maximum aligned position error and state-transition sequence equality. SVG position-error plots and a CSV summary are written to `tests/roblox_traces/reports/`.

Studio's physics cadence can differ from the configured Godot cadence. The comparator interpolates positions at matching timestamps and uses the recorded `dt`; it does not claim that differing sample rates are equivalent. If sensor behavior is unavailable, the documented fallback is the built-in Humanoid FloorMaterial/state observations plus downward and forward raycasts, not an invented controller result.
