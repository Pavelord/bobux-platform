extends SceneTree


func _initialize() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	var studio := packed.instantiate() if packed != null else null
	if studio == null:
		print("[validate_studio_ai_physics] ok=false reason=studio_missing")
		quit(1)
		return
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var actions := [
		{
			"type": "create_part",
			"name": "Physics Ball",
			"shape": "Sphere",
			"size": [3, 3, 3],
			"position": [0, 5, 0],
			"color": "#E34B45",
			"material": "Plastic",
			"anchored": false,
			"can_collide": true,
			"physics_mode": "Dynamic",
			"mass": 1.1,
			"friction": 0.45,
			"bounce": 0.72,
			"gravity_scale": 1.0,
			"linear_damp": 0.08,
			"angular_damp": 0.05,
		},
		{
			"type": "create_model",
			"name": "Working Door",
			"parts": [{
				"name": "Door",
				"shape": "Box",
				"size": [5, 8, 0.55],
				"position": [8, 4.5, 0],
				"color": "#2584D8",
				"material": "Wood",
				"anchored": true,
				"can_collide": true,
				"interaction": {"mode": "click", "action": "toggle_door", "prompt": "Open / Close", "max_distance": 16},
			}],
		},
		{
			"type": "set_environment",
			"sky_color": "#17254A",
			"ambient_color": "#26314F",
			"sun_color": "#FFF1D2",
			"brightness": 0.65,
			"clock_time": 0.0,
		},
	]
	var applied := int(studio.call("_apply_studio_ai_actions", actions))
	var placement_parent := studio.get("placement_parent") as Node
	var ball := placement_parent.find_child("Physics Ball", true, false) as MeshInstance3D if placement_parent != null else null
	var door := placement_parent.find_child("Door", true, false) as MeshInstance3D if placement_parent != null else null
	var door_detector := door.get_node_or_null("ClickDetector") if door != null else null
	var door_script := door.get_node_or_null("InteractionScript") if door != null else null
	var door_source := str(door_script.get_meta("lua_source", "")) if door_script != null else ""
	var serialized: Dictionary = studio.call("_serialize_block_for_clipboard", ball) if ball != null else {}

	studio.call("_activate_studio_playtest_dynamic_parts")
	await physics_frame
	var body: RigidBody3D = null
	if ball != null and ball.has_meta("_bobux_physics_body_instance_id"):
		body = instance_from_id(int(ball.get_meta("_bobux_physics_body_instance_id", 0))) as RigidBody3D
	var body_shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D if body != null else null
	var body_material := body.physics_material_override if body != null else null
	var environment_settings: Dictionary = studio.get("current_roblox_environment_settings")
	var background: Array = environment_settings.get("background_color", []) if environment_settings.get("background_color", []) is Array else []

	var ball_ok := (
		ball != null
		and str(ball.get_meta("bobux_physics_mode", "")) == "Dynamic"
		and not bool(ball.get_meta("anchored", true))
		and body != null
		and is_equal_approx(body.mass, 1.1)
		and body_shape != null
		and body_shape.shape is SphereShape3D
		and body_material != null
		and is_equal_approx(body_material.bounce, 0.72)
		and is_equal_approx(float(serialized.get("bobux_physics_bounce", -1.0)), 0.72)
		and str(serialized.get("bobux_physics_mode", "")) == "Dynamic"
	)
	var door_ok := (
		door != null
		and bool(door.get_meta("can_collide", false))
		and door_detector != null
		and door_detector.is_in_group("roblox_click_detectors")
		and door_source.contains("door.Position")
		and door_source.contains("door.CanCollide")
	)
	var environment_ok := background.size() >= 3 and float(background[2]) > float(background[0]) and is_equal_approx(float(environment_settings.get("ambient_energy", -1.0)), 0.208)
	var ok := applied >= 3 and ball_ok and door_ok and environment_ok
	print("[validate_studio_ai_physics] ok=%s applied=%d ball=%s door=%s environment=%s" % [
		str(ok), applied, str(ball_ok), str(door_ok), str(environment_ok),
	])
	studio.free()
	quit(0 if ok else 1)
