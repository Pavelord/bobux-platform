extends "res://scripts/player/player.gd"

func _ready() -> void:
	_configure_humanoid_physics()
	_configure_physics_motion()
	apply_world_stud_scale(world_stud_scale)
	ensure_roblox_character_contract()
	_configure_collision_profile()
	set_process_input(false)
	set_process_unhandled_input(false)
	player_camera.current = is_multiplayer_authority()
	set_process(false)

func _physics_process(delta: float) -> void:
	if get_node("/root/ImportedPlaceNetwork").networked() and not multiplayer.is_server() and is_multiplayer_authority():
		_run_local_movement(delta)
		_sync_humanoid_runtime_properties(_sample_ground_sensor())

func _exit_tree() -> void:
	pass
