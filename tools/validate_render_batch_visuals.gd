extends SceneTree
const Batches = preload("res://addons/roblox_runtime/roblox_render_batches.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This visual regression requires a graphical renderer")
		quit(2)
		return
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(18, 21, 25)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, -28, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.2, 0.3)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	world.add_child(environment)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x in 8:
		for y in 8: image.set_pixel(x, y, Color.WHITE if (x + y) % 2 else Color(0.2, 0.7, 0.4))
	var texture := ImageTexture.create_from_image(image)
	var excluded: Array[MeshInstance3D] = []
	for index in 128:
		var part := MeshInstance3D.new()
		part.mesh = BoxMesh.new() if index % 2 else CylinderMesh.new()
		part.position = Vector3((index % 16) - 7.5, (index / 16) % 2, (index / 32) - 1.5) * 1.1
		part.scale = Vector3(0.4, 0.3 + (index % 3) * 0.2, 0.45)
		part.rotation_degrees.y = (index % 5) * 12.0
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color(0.9, 0.8, 0.65)
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(1.5, 0.75, 0.9)
		part.material_override = material
		world.add_child(part)
		if index % 43 == 0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.7
			excluded.append(part)
	for index in 8: await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	var calls_before := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var result := Batches.build(world)
	for index in 8: await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	var calls_after := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	DirAccess.make_dir_recursive_absolute("user://validation/render_batches")
	before.save_png("user://validation/render_batches/before.png")
	after.save_png("user://validation/render_batches/after.png")
	before.convert(Image.FORMAT_RGBA8)
	after.convert(Image.FORMAT_RGBA8)
	var left := before.get_data()
	var right := after.get_data()
	var difference := 0.0
	var changed := 0
	for pixel in range(0, left.size(), 4):
		var delta_ := absi(int(left[pixel]) - int(right[pixel])) + absi(int(left[pixel + 1]) - int(right[pixel + 1])) + absi(int(left[pixel + 2]) - int(right[pixel + 2]))
		difference += delta_ / 765.0
		if delta_ > 6: changed += 1
	difference /= left.size() / 4.0
	var fraction := changed / (left.size() / 4.0)
	var ok: bool = result.instances > 100 and excluded.all(func(part): return not part.has_meta(Batches.ENTRY)) and difference < 0.005 and fraction < 0.025
	print("[render-batch-visual] PASS=", ok, " result=", result, " mean_rgb_difference=", difference, " changed_fraction=", fraction, " draws=", calls_before, "->", calls_after)
	world.free()
	quit(0 if ok else 1)
