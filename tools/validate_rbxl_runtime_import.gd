extends SceneTree

const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

class FakeStudio:
	extends Node3D

	var placement_parent: Node3D
	var sun_light: DirectionalLight3D
	var time_slider: HSlider
	var imported_sounds: Array[Dictionary] = []
	var history_labels: Array[String] = []

	func _init() -> void:
		placement_parent = Node3D.new()
		placement_parent.name = "Blocks"
		add_child(placement_parent)

		var env := WorldEnvironment.new()
		env.name = "WorldEnvironment"
		env.environment = Environment.new()
		add_child(env)

		sun_light = DirectionalLight3D.new()
		sun_light.name = "DirectionalLight3D"
		add_child(sun_light)

		time_slider = HSlider.new()
		time_slider.name = "TimeSlider"
		add_child(time_slider)

	func _build_imported_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		return _build_block_instance(shape_name, color, material_type, transparency, can_collide, block_name)

	func _build_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = block_name
		match shape_name:
			"Sphere":
				mesh_inst.mesh = SphereMesh.new()
			"Cylinder":
				mesh_inst.mesh = CylinderMesh.new()
			_:
				mesh_inst.mesh = BoxMesh.new()
		mesh_inst.add_to_group("studio_parts")
		mesh_inst.set_meta("shape_type", shape_name)
		mesh_inst.set_meta("material_type", material_type)
		mesh_inst.set_meta("transparency", transparency)
		mesh_inst.set_meta("can_collide", can_collide)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mesh_inst.set_surface_override_material(0, mat)
		return mesh_inst

	func _update_block_collision(_block: Node) -> void:
		pass

	func _refresh_explorer() -> void:
		pass

	func _clear_selection() -> void:
		pass

	func _commit_editor_history(label: String) -> void:
		history_labels.append(label)

	func _refresh_music_source_ui() -> void:
		pass

	func _register_imported_sound_asset(sound_data: Dictionary) -> void:
		imported_sounds.append(sound_data.duplicate(true))

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "res://addons/rbxl_importer/tests/sample_runtime_features.out.json"
	if not args.is_empty():
		source_path = str(args[0])
	var started_ms := Time.get_ticks_msec()
	print("[validate_rbxl_runtime_import] source=", source_path)

	var studio := FakeStudio.new()
	root.add_child(studio)

	var importer := RuntimeImporter.new()
	importer.replace_existing = true
	if args.size() > 1:
		importer.max_runtime_preview_nodes = max(0, int(str(args[1])))
	if args.size() > 2:
		importer.max_texture_preview_nodes = max(0, int(str(args[2])))
	if args.size() > 3:
		importer.apply_standard_mesh_children = bool(int(str(args[3])))
	var report: Dictionary = {}
	if source_path.get_extension().to_lower() == "json":
		var json_path := ProjectSettings.globalize_path(source_path) if source_path.begins_with("res://") or source_path.begins_with("user://") else source_path
		if not FileAccess.file_exists(json_path):
			push_error("[validate_rbxl_runtime_import] JSON not found: %s" % json_path)
			quit(1)
			return
		print("[validate_rbxl_runtime_import] reading_json_ms=", Time.get_ticks_msec() - started_ms)
		var file := FileAccess.open(json_path, FileAccess.READ)
		var json_text := file.get_as_text() if file != null else ""
		if file != null:
			file.close()
		print("[validate_rbxl_runtime_import] parsing_json_ms=", Time.get_ticks_msec() - started_ms, " bytes=", json_text.length())
		var parsed: Variant = JSON.parse_string(json_text)
		if not (parsed is Dictionary):
			push_error("[validate_rbxl_runtime_import] JSON is malformed: %s" % json_path)
			quit(1)
			return
		print("[validate_rbxl_runtime_import] importing_json_ms=", Time.get_ticks_msec() - started_ms)
		report = importer.import_json(parsed as Dictionary, studio.placement_parent, studio)
	else:
		if not FileAccess.file_exists(source_path):
			push_error("[validate_rbxl_runtime_import] Source file not found: %s" % source_path)
			quit(1)
			return
		print("[validate_rbxl_runtime_import] importing_source_ms=", Time.get_ticks_msec() - started_ms)
		report = importer.import_file(source_path, studio)
	print("[validate_rbxl_runtime_import] imported_ms=", Time.get_ticks_msec() - started_ms)
	print("[validate_rbxl_runtime_import] report=", JSON.stringify(report))

	var block_count := 0
	var textured_material_count := 0
	var shape_counts: Dictionary = {}
	var roblox_class_counts: Dictionary = {}
	var deferred_mesh_count := 0
	var special_mesh_count := 0
	for child in studio.placement_parent.get_children():
		if child is MeshInstance3D and child.is_in_group("studio_parts"):
			block_count += 1
			var mesh_child := child as MeshInstance3D
			var shape_name := str(mesh_child.get_meta("shape_type", "Box"))
			shape_counts[shape_name] = int(shape_counts.get(shape_name, 0)) + 1
			var roblox_class := str(mesh_child.get_meta("roblox_class", ""))
			if not roblox_class.is_empty():
				roblox_class_counts[roblox_class] = int(roblox_class_counts.get(roblox_class, 0)) + 1
			if bool(mesh_child.get_meta("roblox_mesh_deferred", false)):
				deferred_mesh_count += 1
			if mesh_child.has_meta("roblox_special_mesh"):
				special_mesh_count += 1
			var mat := mesh_child.get_active_material(0) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null:
				textured_material_count += 1
	print("[validate_rbxl_runtime_import] studio_parts=", block_count)
	print("[validate_rbxl_runtime_import] shapes=", JSON.stringify(shape_counts))
	print("[validate_rbxl_runtime_import] roblox_classes=", JSON.stringify(roblox_class_counts))
	print("[validate_rbxl_runtime_import] deferred_meshes=", deferred_mesh_count, " special_mesh_blocks=", special_mesh_count)
	print("[validate_rbxl_runtime_import] surface_materials=", textured_material_count)

	var env_node := studio.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		print("[validate_rbxl_runtime_import] background=", env_node.environment.background_color)
		print("[validate_rbxl_runtime_import] ambient=", env_node.environment.ambient_light_color)

	root.remove_child(studio)
	studio.free()
	quit(0 if bool(report.get("ok", false)) and block_count > 0 else 1)
