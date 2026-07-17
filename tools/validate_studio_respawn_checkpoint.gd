extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var parent := studio.get("placement_parent") as Node3D
	var spawn: MeshInstance3D = studio._build_block_instance("Spawn", Color.GREEN, "Plastic", 0.0, true, "SpawnLocation")
	spawn.position = Vector3(-10.0, 2.0, 0.0)
	parent.add_child(spawn)
	var checkpoint: MeshInstance3D = studio._build_block_instance("Checkpoint", Color.YELLOW, "Plastic", 0.0, true, "Checkpoint")
	checkpoint.position = Vector3(12.0, 2.0, 3.0)
	parent.add_child(checkpoint)
	await studio._start_studio_playtest()
	await process_frame
	var player := studio.get("studio_playtest_player") as CharacterBody3D
	var checkpoint_target: Vector3 = studio._get_part_respawn_global_position(checkpoint)
	studio._on_studio_respawn_trigger_entered(player, checkpoint_target, checkpoint.name)
	var checkpoint_saved := player != null and (player.call("get_respawn_position") as Vector3).distance_to(checkpoint_target) < 0.05
	if player != null:
		player.global_position = Vector3(-30.0, 18.0, -20.0)
		player.call("kill_now")
	await create_timer(2.8).timeout
	await physics_frame
	var respawned := player != null and int(player.call("get_health")) == int(player.call("get_max_health"))
	var at_checkpoint := player != null and Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(checkpoint_target.x, checkpoint_target.z)) < 0.3
	var not_center := player != null and Vector2(player.global_position.x, player.global_position.z).length() > 2.0
	await studio._stop_studio_playtest()
	await process_frame
	var ok := checkpoint_saved and respawned and at_checkpoint and not_center
	print("[validate_studio_respawn_checkpoint] ok=%s saved=%s respawned=%s checkpoint=%s not_center=%s target=%s" % [str(ok), str(checkpoint_saved), str(respawned), str(at_checkpoint), str(not_center), str(checkpoint_target)])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
