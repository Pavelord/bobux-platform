extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1000, 800)
	root.content_scale_size = root.size
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("17151b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -20, 0)
	light.light_energy = 0.8
	world.add_child(light)
	var actors: Array[Node3D] = []
	for key in ["gift", "pumpkin"]:
		# Raw mode verifies rebuilt GLBs independently of editor import caches.
		var source_path := "res://assets/events/halloween2026/%s.glb" % key
		if OS.get_cmdline_user_args().has("--raw-models"):
			var raw_path := "user://%s-textured.glb" % key
			var file := FileAccess.open(raw_path, FileAccess.WRITE)
			file.store_buffer(FileAccess.get_file_as_bytes(source_path))
			file.close()
			source_path = raw_path
		var actor := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
		actor.set("is_ui_preview", true)
		actor.set("use_local_avatar_fallback", false)
		actor.set("face_texture_path", "res://assets/avatar/default_face.png")
		actor.set("chest_badge_texture_path", "")
		actor.set("equipped_avatar_items", [{"id": "event_halloween_2026_" + key, "name": key, "attachment_slot": "Head" if key == "gift" else "HeadCenter", "source_url": source_path,
			"data": {"covers_head": key == "pumpkin"},
			"attachment_transform": {"position": [0,0.34 if key == "gift" else 0,0], "rotation_degrees":[0,0 if key == "gift" else -90,0], "scale":[0.65,0.65,0.65] if key == "gift" else [0.9,0.9,0.9]}}])
		world.add_child(actor)
		actor.position.x = -1.6 if key == "gift" else 1.6
		actors.append(actor)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,4.8,8.0)
	camera.look_at(Vector3(0,3.0,0))
	camera.current = true
	await create_timer(1.5).timeout
	for actor in actors:
		var attachments: Node3D = actor.get("_avatar_attachment_root")
		if attachments == null or attachments.get_child_count() != 1:
			failures.append("attachment missing")
			continue
		var item := attachments.get_child(0) as Node3D
		var meshes := item.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty(): failures.append("loaded mesh missing")
		var first := true
		var bounds: AABB
		var glowing := false
		for mesh in meshes:
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface in mesh.mesh.get_surface_count():
				var material: BaseMaterial3D = mesh.get_active_material(surface)
				if material == null or material.albedo_texture == null: failures.append("original UV texture missing")
				if material != null and material.emission_enabled: glowing = true
		if maxf(bounds.size.x, maxf(bounds.size.y,bounds.size.z)) > 1.5: failures.append("head accessory too large")
		var head: MeshInstance3D = actor.get("head_mesh")
		var head_bounds: AABB = head.global_transform * head.get_aabb()
		if item.name == "gift" and bounds.position.y < head_bounds.end.y - 0.01: failures.append("gift intersects rounded head")
		if item.name == "pumpkin" and (head.visible or bounds.get_center().distance_to(head_bounds.get_center()) > 0.1): failures.append("pumpkin is not worn over the head")
		if item.name == "pumpkin" and (not glowing or item.find_children("*", "OmniLight3D", true, false).is_empty()): failures.append("pumpkin glow missing")
		print("[halloween-accessory] ",item.name," bounds=",bounds," head=",head_bounds," glowing=",glowing)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/halloween")
		root.get_texture().get_image().save_png("user://validation/halloween/accessories.png")
		root.get_texture().get_image().save_png("res://.codex-tmp/final_event_accessories.png")
	var pumpkin_actor := actors[1]
	pumpkin_actor.set("equipped_avatar_items", [])
	pumpkin_actor.call("force_avatar_visual_refresh")
	await process_frame
	if not (pumpkin_actor.get("head_mesh") as MeshInstance3D).visible: failures.append("head not restored after unequip")
	print("HALLOWEEN_ACCESSORIES_RESULT=", JSON.stringify({"ok":failures.is_empty(),"failures":failures}))
	world.free()
	quit(0 if failures.is_empty() else 1)
