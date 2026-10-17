extends "res://scripts/player/player.gd"

## Diagnostic wrapper for the NDS stand; production character behavior is
## inherited unchanged. Trace only test-owned respawn inputs when requested.
func apply_authoritative_respawn_position(target_position: Vector3, treat_as_checkpoint: bool = false) -> void:
	if OS.get_cmdline_user_args().has("--trace-imported-network"):
		print("[nds-character] respawn input=", target_position, " peer=", multiplayer.get_unique_id(), " stack=", get_stack())
	super.apply_authoritative_respawn_position(target_position, treat_as_checkpoint)
	if OS.get_cmdline_user_args().has("--trace-imported-network"):
		print("[nds-character] respawn output=", global_position)

func _force_local_respawn_recovery() -> void:
	if OS.get_cmdline_user_args().has("--trace-imported-network"):
		print("[nds-character] recovery input=", global_position, " spawn_points=", spawn_points, " respawn_position=", respawn_position, " stack=", get_stack())
	super._force_local_respawn_recovery()
	if OS.get_cmdline_user_args().has("--trace-imported-network"):
		print("[nds-character] recovery output=", global_position)
