extends SceneTree

func _initialize() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_player_humanoid_states] Player scene is missing")
		quit(1)
		return
	var world := Node3D.new()
	world.name = "HumanoidStateValidation"
	get_root().add_child(world)
	_add_box_body(world, "Floor", Vector3(0.0, -0.5, 0.0), Vector3(18.0, 1.0, 18.0), "Part")

	var player := player_scene.instantiate() as CharacterBody3D
	player.name = "Character"
	player.set_meta("bobux_studio_playtest", true)
	world.add_child(player)
	player.position = Vector3.ZERO
	player.call("_configure_collision_profile")
	for _frame in range(4):
		await physics_frame

	var primary_collision := player.get_node_or_null("CollisionBody") as CollisionShape3D
	var fitted_collisions_ok := true
	for collision_name in ["CollisionLeftLeg", "CollisionRightLeg", "CollisionTorso", "CollisionHead", "CollisionLeftArm", "CollisionRightArm"]:
		var fitted_collision := player.get_node_or_null(collision_name) as CollisionShape3D
		fitted_collisions_ok = fitted_collisions_ok and fitted_collision != null and not fitted_collision.disabled and fitted_collision.shape is ConvexPolygonShape3D
	var collision_ok: bool = (
		player.collision_layer == 2
		and (player.collision_mask & 2) != 0
		and player.safe_margin <= 0.04
		and primary_collision != null
		and primary_collision.disabled
		and fitted_collisions_ok
	)
	var humanoid := player.get_node_or_null("Humanoid")

	var seat := _add_box_body(world, "Seat", Vector3(3.0, 0.25, 0.0), Vector3(2.0, 0.5, 2.0), "Seat")
	seat.add_to_group("roblox_seat")
	player.call("_enter_seat", seat)
	var seat_attached: bool = player.call("_update_seated_movement", false)
	var seated_ok: bool = seat_attached and humanoid != null and str(humanoid.get_meta("HumanoidState", "")) == "Seated" and seat.get_meta("Occupant", null) == humanoid
	player.call("_update_seated_movement", true)
	var seat_exit_ok: bool = player.get("_seated_part") == null and player.velocity.y > 0.0 and not bool(humanoid.get_meta("Sit", true))

	player.global_position = Vector3(0.0, 1.4, 4.0)
	player.velocity = Vector3.ZERO
	var water := Area3D.new()
	water.name = "TerrainWater"
	water.collision_layer = 4
	water.collision_mask = 0
	water.set_meta("roblox_class", "TerrainWater")
	water.add_to_group("roblox_water")
	var water_collision := CollisionShape3D.new()
	var water_shape := BoxShape3D.new()
	water_shape.size = Vector3(5.0, 5.0, 5.0)
	water_collision.shape = water_shape
	water.add_child(water_collision)
	world.add_child(water)
	water.global_position = player.global_position
	for _frame in range(3):
		await physics_frame
	player.call("_update_swimming_contact")
	player.call("_run_swimming_movement", 1.0 / 60.0, Vector2(0.0, -1.0), true)
	var swimming_ok: bool = bool(player.get("_swimming_active")) and player.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING and str(humanoid.get_meta("HumanoidState", "")) == "Swimming"
	water.queue_free()
	await physics_frame
	player.call("_update_swimming_contact")

	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	_add_box_body(world, "Ledge", Vector3(0.0, 1.15, -1.25), Vector3(3.5, 2.3, 1.0), "Part")
	for _frame in range(3):
		await physics_frame
	var ledge_started: bool = player.call("_try_begin_ledge_hang", Vector3.FORWARD, true)
	var ledge_start_y := player.global_position.y
	for _frame in range(8):
		player.call("_update_ledge_hang", 1.0 / 60.0, Vector2.ZERO, false)
		await physics_frame
	var held_without_auto_climb := bool(player.get("_ledge_hang_active")) and not bool(player.get("_ledge_mantle_active"))
	player.call("_update_ledge_hang", 1.0 / 60.0, Vector2(0.0, -1.0), false)
	for _frame in range(90):
		player.call("_update_ledge_mantle", 1.0 / 60.0)
		await physics_frame
		if not bool(player.get("_ledge_mantle_active")):
			break
	var ledge_ok: bool = ledge_started and held_without_auto_climb and not bool(player.get("_ledge_mantle_active")) and player.global_position.y > ledge_start_y + 1.0

	player.call("_spawn_death_fragments")
	await physics_frame
	var fragment_root := player.get("_death_fragment_root") as Node3D
	var death_ok: bool = fragment_root != null and fragment_root.get_child_count() >= 6 and not player.get_node("Visuals").visible
	player.call("_restore_after_respawn")
	var respawn_visual_ok: bool = player.get_node("Visuals").visible and player.get("_death_fragment_root") == null

	var ok: bool = collision_ok and seated_ok and seat_exit_ok and swimming_ok and ledge_ok and death_ok and respawn_visual_ok
	print("[validate_player_humanoid_states] ok=%s collision=%s seated=%s seat_exit=%s swimming=%s ledge=%s death=%s restored=%s" % [
		str(ok), str(collision_ok), str(seated_ok), str(seat_exit_ok), str(swimming_ok), str(ledge_ok), str(death_ok), str(respawn_visual_ok),
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
