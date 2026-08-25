extends SceneTree

const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

class FakeStudio:
	extends Node3D

	var placement_parent: Node3D
	var sun_light: DirectionalLight3D
	var time_slider: HSlider
	var imported_sounds: Array[Dictionary] = []

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

	func _commit_editor_history(_label: String) -> void:
		pass

	func _refresh_music_source_ui() -> void:
		pass

	func _register_imported_sound_asset(sound_data: Dictionary) -> void:
		imported_sounds.append(sound_data.duplicate(true))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: --script res://tools/inspect_rbxl_import_missing_meshes.gd -- <file.rbxl|file.json>")
		quit(2)
		return
	var source_path := str(args[0])
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var studio := FakeStudio.new()
	root.add_child(studio)
	var importer := RuntimeImporter.new()
	importer.replace_existing = true
	var report: Dictionary = await importer.import_file_async(source_path, studio)
	print("[inspect_rbxl_import_missing_meshes] report=", JSON.stringify(report))
	var stats := {
		"parts": 0,
		"exact": 0,
		"proxy": 0,
		"missing": 0,
		"deferred": 0,
	}
	var missing_ids: Dictionary = {}
	var proxy_ids: Dictionary = {}
	var deferred_ids: Dictionary = {}
	_collect(studio.placement_parent, stats, missing_ids, proxy_ids, deferred_ids)
	print("[inspect_rbxl_import_missing_meshes] stats=", JSON.stringify(stats))
	print("[inspect_rbxl_import_missing_meshes] missing_ids=", JSON.stringify(_sorted_keys(missing_ids)))
	print("[inspect_rbxl_import_missing_meshes] proxy_ids=", JSON.stringify(_sorted_keys(proxy_ids)))
	print("[inspect_rbxl_import_missing_meshes] deferred_ids=", JSON.stringify(_sorted_keys(deferred_ids)))
	studio.free()
	quit(0)


func _collect(node: Node, stats: Dictionary, missing_ids: Dictionary, proxy_ids: Dictionary, deferred_ids: Dictionary) -> void:
	if node.is_in_group("studio_parts"):
		stats["parts"] = int(stats.get("parts", 0)) + 1
	if node is MeshInstance3D:
		if bool(node.get_meta("roblox_mesh_applied", false)):
			stats["exact"] = int(stats.get("exact", 0)) + 1
		if bool(node.get_meta("roblox_proxy_geometry", false)):
			stats["proxy"] = int(stats.get("proxy", 0)) + 1
			var proxy_id := str(node.get_meta("roblox_mesh_id", "")).strip_edges()
			if not proxy_id.is_empty():
				proxy_ids[proxy_id] = int(proxy_ids.get(proxy_id, 0)) + 1
		if bool(node.get_meta("roblox_missing_exact_mesh", false)):
			stats["missing"] = int(stats.get("missing", 0)) + 1
			var missing_id := str(node.get_meta("roblox_mesh_id", "")).strip_edges()
			if not missing_id.is_empty():
				missing_ids[missing_id] = int(missing_ids.get(missing_id, 0)) + 1
		if bool(node.get_meta("roblox_mesh_deferred", false)):
			stats["deferred"] = int(stats.get("deferred", 0)) + 1
			var deferred_id := str(node.get_meta("roblox_mesh_id", "")).strip_edges()
			if not deferred_id.is_empty():
				deferred_ids[deferred_id] = int(deferred_ids.get(deferred_id, 0)) + 1
	for child in node.get_children():
		_collect(child, stats, missing_ids, proxy_ids, deferred_ids)


func _sorted_keys(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append({"id": str(key), "count": int(dict.get(key, 0))})
	return result
