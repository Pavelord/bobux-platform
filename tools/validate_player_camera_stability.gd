extends SceneTree


func _initialize() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	if scene == null:
		push_error("[validate_player_camera_stability] Player scene is missing")
		quit(1)
		return
	var player := scene.instantiate()
	player.set("is_ui_preview", false)
	root.add_child(player)
	await process_frame
	var camera_pivot := player.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot == null:
		push_error("[validate_player_camera_stability] CameraPivot is missing")
		quit(1)
		return
	var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	if spring_arm == null:
		push_error("[validate_player_camera_stability] SpringArm3D is missing")
		quit(1)
		return
	if int(spring_arm.collision_mask) != 0:
		push_error("[validate_player_camera_stability] SpringArm3D collision probe must stay disabled to prevent camera distance jitter")
		quit(1)
		return
	camera_pivot.top_level = true
	player.global_position = Vector3(12.0, 3.0, -4.0)
	player.call("_reset_local_camera_anchor", player.global_position)
	player.call("_update_local_camera_rig_render_phase", 0.016)
	var expected: Vector3 = player.global_position + Vector3(0.0, 4.0, 0.0)
	if camera_pivot.global_position.distance_to(expected) > 0.05:
		push_error("[validate_player_camera_stability] Top-level camera pivot did not follow interpolated player position: expected=%s actual=%s" % [str(expected), str(camera_pivot.global_position)])
		quit(1)
		return
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	blocker.position = expected + Vector3(0.0, 0.0, 3.0)
	var blocker_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.8)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	root.add_child(blocker)
	await physics_frame
	camera_pivot.global_rotation = Vector3.ZERO
	player.call("_set_camera_desired_spring_length", 8.5)
	player.call("_update_local_camera_rig_render_phase", 0.016)
	if spring_arm.spring_length >= 8.0:
		push_error("[validate_player_camera_stability] Camera collision ray did not shorten spring length near a wall: spring_length=%s" % str(spring_arm.spring_length))
		quit(1)
		return
	print("[validate_player_camera_stability] Player camera stability OK")
	quit(0)
