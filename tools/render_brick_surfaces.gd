extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1100, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b9c9d9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.2
	scene.add_child(light)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(8, 14, 12)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	camera.current = true
	var cache := preload("res://addons/rbxl_importer/material_cache.gd").new()
	for row in range(2):
		for col in range(2):
			var part := MeshInstance3D.new()
			part.mesh = BoxMesh.new()
			part.scale = Vector3(2 if col == 0 else 6, 0.5, 3)
			part.position = Vector3(-4 if col == 0 else 1, 0, -2.4 if row == 0 else 2.4)
			if row == 1: part.rotation.z = PI
			part.material_override = cache.get_part_material({"Color": [0.7, 0.28, 0.13], "TopSurface": 3, "BottomSurface": 4, "BobuxStudScale": 0.5})
			scene.add_child(part)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.codex-tmp/natural_disasters/brick_surfaces_preview.png")
	quit()
