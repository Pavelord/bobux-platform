# Roblox Humanoid trace captures

This directory is the destination for user-captured Roblox Studio Output and generated traces. `tools/roblox/collect_roblox_traces.py` creates the `roblox/` CSVs plus `part_dump.csv`, metadata, and sensor logs here. Copy the Godot stand's CSVs into `godot/` before running `tools/compare_traces.py`.

No reference captures are checked in yet. Their absence is why physics parameters tagged `TODO_MEASURE` have not been calibrated.
