extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(960,720)
	root.content_scale_size = root.size
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#cdddea")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.shadow_enabled = true
	world.add_child(light)
	var ground := StaticBody3D.new()
	ground.position.y = -0.5
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(80,1,80)
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(80,1,80)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#98b99f")
	mesh.material_override = material
	ground.add_child(mesh)
	world.add_child(ground)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest",true)
	world.add_child(player)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	var label := Label.new()
	label.position = Vector2(24,22)
	label.add_theme_color_override("font_color",Color("#233746"))
	label.add_theme_font_size_override("font_size",24)
	root.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://.codex-tmp/player_motion")
	for frame in range(270):
		await physics_frame
		if frame == 45: Input.action_press("move_forward")
		if frame == 72: Input.action_press("jump")
		if frame == 74: Input.action_release("jump")
		if frame == 110: Input.action_release("move_forward")
		if frame == 145: player.apply_external_impulse(Vector3(20,4,0))
		camera.position = player.position + Vector3(9,7,13)
		camera.look_at(player.position + Vector3(0,2.3,0))
		label.text = "BOBUX  ·  " + str(player.get_node("Humanoid").get_meta("HumanoidState", ""))
		await RenderingServer.frame_post_draw
		if frame in [30,58,80,117,170,260]: root.get_texture().get_image().save_png("res://.codex-tmp/player_motion/%03d.png" % frame)
	Input.action_release("move_forward")
	Input.action_release("jump")
	print("[capture_player_motion] PASS")
	quit()
