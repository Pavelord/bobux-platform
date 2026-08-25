extends SceneTree

func _initialize() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_player_climbing] Player scene is missing")
		quit(1)
		return
	var world := Node3D.new()
	world.name = "ClimbingValidation"
	get_root().add_child(world)
	_add_box_body(world, "Floor", Vector3(0.0, -0.5, 0.0), Vector3(12.0, 1.0, 12.0), "Part")
	var truss := _add_box_body(world, "Truss", Vector3(0.0, 2.8, -1.2), Vector3(3.0, 6.0, 0.25), "TrussPart")
	truss.add_to_group("roblox_climbable")

	var player := player_scene.instantiate() as CharacterBody3D
	player.name = "Character"
	world.add_child(player)
	player.position = Vector3.ZERO
	player.call("_set_collision_enabled", true)
	player.collision_mask = 1

	for _frame in range(4):
		await physics_frame
	var probe: Dictionary = player.call("_probe_climbable_surface", Vector3.FORWARD)
	var detected := not probe.is_empty()
	var start_y := player.global_position.y
	for frame_index in range(24):
		# Climbing is deliberate: pressing jump while moving into a climbable
		# surface grabs it; holding forward then moves upward.
		player.call("_update_climbing_movement", 1.0 / 60.0, Vector2(0.0, -1.0), Vector3.FORWARD, Basis.IDENTITY, frame_index == 0)
		await physics_frame
	var humanoid := player.get_node_or_null("Humanoid")
	var climbing := humanoid != null and str(humanoid.get_meta("HumanoidState", "")) == "Climbing"
	var climbed := player.global_position.y > start_y + 0.25

	player.call("_update_climbing_movement", 1.0 / 60.0, Vector2.ZERO, Vector3.ZERO, Basis.IDENTITY, true)
	await physics_frame
	var detached := not bool(player.get("_climbing_active")) and player.velocity.y > 0.0
	var ok := detected and climbing and climbed and detached
	print("[validate_player_climbing] ok=%s detected=%s climbing=%s climbed=%s detached=%s delta_y=%.3f" % [
		str(ok), str(detected), str(climbing), str(climbed), str(detached), player.global_position.y - start_y,
	])
	world.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _add_box_body(parent: Node3D, node_name: String, position: Vector3, size: Vector3, roblox_class: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("roblox_class", roblox_class)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
