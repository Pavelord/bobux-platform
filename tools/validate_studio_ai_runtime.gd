extends SceneTree


func _initialize() -> void:
	var runtime: Node = load("res://scripts/main/main.gd").new()
	var world := Node3D.new()
	world.name = "RuntimeAIValidationWorld"
	get_root().add_child(world)
	await process_frame
	var part := MeshInstance3D.new()
	part.name = "InteractiveLamp"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	part.mesh = mesh
	runtime.add_child(part)
	var block_data := {
		"bobux_ai_effects": [
			{"type": "Fire", "color": "#FF7814", "enabled": true, "rate": 24},
			{"type": "PointLight", "color": "#3366FF", "enabled": true, "brightness": 3.0, "range": 18.0}
		],
		"bobux_ai_interaction": {"mode": "click", "action": "toggle_effect", "prompt": "Toggle lamp", "max_distance": 16.0}
	}
	runtime.call("_configure_runtime_ai_components", part, block_data)
	var fire := part.get_node_or_null("Fire") as GPUParticles3D
	var light := part.get_node_or_null("PointLight") as OmniLight3D
	var detector := part.get_node_or_null("ClickDetector")
	var before_ok := fire != null and fire.emitting and light != null and light.visible \
		and detector != null and detector.is_in_group("roblox_click_detectors")
	var handled := bool(runtime.call("_perform_bobux_ai_interaction", detector, null))
	var after_ok := handled and not fire.emitting and not light.visible

	var ball := MeshInstance3D.new()
	ball.name = "PhysicsBall"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 1.0
	ball.mesh = sphere_mesh
	ball.scale = Vector3(3.0, 3.0, 3.0)
	ball.position = Vector3(0.0, 8.0, 0.0)
	world.add_child(ball)
	var ball_data := {
		"anchored": false,
		"bobux_physics_mode": "Dynamic",
		"bobux_physics_mass": 1.1,
		"bobux_physics_friction": 0.45,
		"bobux_physics_bounce": 0.72,
		"bobux_physics_gravity_scale": 1.0,
		"bobux_physics_linear_damp": 0.08,
		"bobux_physics_angular_damp": 0.05,
	}
	runtime.call("_attach_runtime_block_physics", ball, ball_data, "Sphere", "Plastic", true, world)
	var ball_body: RigidBody3D = null
	if ball.has_meta("_bobux_physics_body_instance_id"):
		ball_body = instance_from_id(int(ball.get_meta("_bobux_physics_body_instance_id", 0))) as RigidBody3D
	var ball_start_y := ball_body.global_position.y if ball_body != null else 0.0
	for _frame in range(12):
		await physics_frame
	var ball_material := ball_body.physics_material_override if ball_body != null else null
	var ball_ok := ball_body != null \
		and ball_body.global_position.y < ball_start_y \
		and is_equal_approx(ball_body.mass, 1.1) \
		and ball_material != null \
		and is_equal_approx(ball_material.bounce, 0.72)

	var door := MeshInstance3D.new()
	door.name = "Door"
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3.ONE
	door.mesh = door_mesh
	door.scale = Vector3(5.0, 8.0, 0.55)
	door.position = Vector3(8.0, 4.5, 0.0)
	world.add_child(door)
	var door_data := {
		"anchored": true,
		"bobux_ai_interaction": {"mode": "click", "action": "toggle_door", "prompt": "Open / Close", "max_distance": 16.0},
	}
	runtime.call("_attach_runtime_block_physics", door, door_data, "Box", "Wood", true, world)
	runtime.call("_configure_runtime_ai_components", door, door_data)
	var door_detector := door.get_node_or_null("ClickDetector")
	var door_start := door.position
	var door_handled := bool(runtime.call("_perform_bobux_ai_interaction", door_detector, null))
	await create_timer(0.5).timeout
	await physics_frame
	var door_collisions := door.find_children("*", "CollisionShape3D", true, false)
	var door_collision := door_collisions[0] as CollisionShape3D if not door_collisions.is_empty() else null
	var door_ok := door_handled \
		and bool(door.get_meta("bobux_door_open", false)) \
		and door.position.y > door_start.y + 7.0 \
		and door_collision != null \
		and door_collision.disabled
	if not door_ok:
		print("[validate_studio_ai_runtime] door_debug handled=%s open=%s start=%s current=%s collision=%s disabled=%s" % [
			str(door_handled),
			str(door.get_meta("bobux_door_open", false)),
			str(door_start),
			str(door.position),
			str(door_collision != null),
			str(door_collision.disabled if door_collision != null else false),
		])

	var ok := before_ok and after_ok and ball_ok and door_ok
	print("[validate_studio_ai_runtime] ok=%s before=%s after=%s ball=%s door=%s" % [
		str(ok), str(before_ok), str(after_ok), str(ball_ok), str(door_ok),
	])
	world.free()
	runtime.free()
	quit(0 if ok else 1)
