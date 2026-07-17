extends SceneTree

const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

class FakeStudio:
	extends Node3D
	var placement_parent: Node3D
	var sun_light: DirectionalLight3D
	var time_slider: HSlider

	func _init() -> void:
		placement_parent = Node3D.new()
		placement_parent.name = "Blocks"
		add_child(placement_parent)
		var env := WorldEnvironment.new()
		env.name = "WorldEnvironment"
		env.environment = Environment.new()
		add_child(env)
		sun_light = DirectionalLight3D.new()
		add_child(sun_light)
		time_slider = HSlider.new()
		add_child(time_slider)

	func _build_imported_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = block_name
		mesh_inst.mesh = BoxMesh.new()
		mesh_inst.set_meta("shape_type", shape_name)
		mesh_inst.set_meta("block_name", block_name)
		mesh_inst.set_meta("material_type", material_type)
		mesh_inst.set_meta("transparency", transparency)
		mesh_inst.set_meta("can_collide", can_collide)
		mesh_inst.add_to_group("studio_parts")
		return mesh_inst

	func _build_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		return _build_imported_block_instance(shape_name, color, material_type, transparency, can_collide, block_name)

	func _update_block_collision(_block: Node3D) -> void:
		pass

	func _register_imported_sound_asset(_sound_data: Dictionary) -> void:
		pass


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Build a Boat FULLY WORKING (Subscribe to FrenchBread).rbxl"
	if not args.is_empty():
		source_path = str(args[0])
	var studio := FakeStudio.new()
	get_root().add_child(studio)
	var importer := RuntimeImporter.new()
	importer.max_runtime_preview_nodes = 0
	importer.max_texture_preview_nodes = 0
	var report: Dictionary = importer.import_file(source_path, studio)
	var stats := _collect_mesh_stats(studio.placement_parent)
	print("[validate_rbxl_mesh_materialization] ok=%s parts=%d exact=%d proxy=%d missing=%d mesh_textured=%d mesh_untextured=%d face_decals=%d decal_failures=%d cull_violations=%d warnings=%d" % [
		str(bool(report.get("ok", false))),
		int(report.get("parts", 0)),
		int(stats.get("exact", 0)),
		int(stats.get("proxy", 0)),
		int(stats.get("missing", 0)),
		int(stats.get("mesh_textured", 0)),
		int(stats.get("mesh_untextured", 0)),
		int(stats.get("face_decals", 0)),
		int(stats.get("decal_failures", 0)),
		int(stats.get("cull_violations", 0)),
		int(report.get("warnings", []).size() if report.get("warnings", []) is Array else 0)
	])
	var missing_ids: Array = stats.get("missing_ids", []) if stats.get("missing_ids", []) is Array else []
	var untextured_ids: Array = stats.get("untextured_texture_ids", []) if stats.get("untextured_texture_ids", []) is Array else []
	print("[validate_rbxl_mesh_materialization] missing_ids=%s" % JSON.stringify(missing_ids.slice(0, mini(missing_ids.size(), 24))))
	print("[validate_rbxl_mesh_materialization] untextured_texture_ids=%s" % JSON.stringify(untextured_ids.slice(0, mini(untextured_ids.size(), 24))))
	var expects_decals := source_path.to_lower().contains("ronaldinho")
	var decals_ok := not expects_decals or (int(stats.get("face_decals", 0)) >= 70 and int(stats.get("decal_failures", 0)) == 0)
	var ok := bool(report.get("ok", false)) and int(stats.get("missing", 0)) == 0 and int(stats.get("proxy", 0)) == 0 and int(stats.get("cull_violations", 0)) == 0 and decals_ok
	quit(0 if ok else 1)


func _collect_mesh_stats(root: Node) -> Dictionary:
	var stats := {
		"exact": 0,
		"proxy": 0,
		"missing": 0,
		"mesh_textured": 0,
		"mesh_untextured": 0,
		"face_decals": 0,
		"decal_failures": 0,
		"cull_violations": 0,
		"missing_ids": [],
		"untextured_texture_ids": [],
	}
	_collect_mesh_stats_recursive(root, stats)
	return stats


func _collect_mesh_stats_recursive(node: Node, stats: Dictionary) -> void:
	if bool(node.get_meta("roblox_face_decal", false)):
		stats["face_decals"] = int(stats.get("face_decals", 0)) + 1
		if not (node is MeshInstance3D) or (node as MeshInstance3D).material_override == null:
			stats["decal_failures"] = int(stats.get("decal_failures", 0)) + 1
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var roblox_class := str(mesh_inst.get_meta("roblox_class", ""))
		if roblox_class in ["MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"] or mesh_inst.has_meta("roblox_special_mesh"):
			if bool(mesh_inst.get_meta("roblox_mesh_applied", false)):
				stats["exact"] = int(stats.get("exact", 0)) + 1
				var surface_count := maxi(1, mesh_inst.mesh.get_surface_count() if mesh_inst.mesh != null else 1)
				for surface_index in range(surface_count):
					var surface_material := mesh_inst.get_active_material(surface_index) as StandardMaterial3D
					if surface_material == null or surface_material.cull_mode != BaseMaterial3D.CULL_DISABLED:
						stats["cull_violations"] = int(stats.get("cull_violations", 0)) + 1
			if bool(mesh_inst.get_meta("roblox_proxy_geometry", false)):
				stats["proxy"] = int(stats.get("proxy", 0)) + 1
			if bool(mesh_inst.get_meta("roblox_missing_exact_mesh", false)):
				stats["missing"] = int(stats.get("missing", 0)) + 1
				var missing_ids: Array = stats.get("missing_ids", []) if stats.get("missing_ids", []) is Array else []
				var mesh_id := str(mesh_inst.get_meta("roblox_mesh_id", "")).strip_edges()
				if not mesh_id.is_empty() and not missing_ids.has(mesh_id):
					missing_ids.append(mesh_id)
				stats["missing_ids"] = missing_ids
			var mat := mesh_inst.get_active_material(0) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null:
				stats["mesh_textured"] = int(stats.get("mesh_textured", 0)) + 1
			else:
				stats["mesh_untextured"] = int(stats.get("mesh_untextured", 0)) + 1
				var texture_ids: Array = stats.get("untextured_texture_ids", []) if stats.get("untextured_texture_ids", []) is Array else []
				var texture_id := str(mesh_inst.get_meta("roblox_texture_id", "")).strip_edges()
				if not texture_id.is_empty() and not texture_ids.has(texture_id):
					texture_ids.append(texture_id)
				stats["untextured_texture_ids"] = texture_ids
	for child in node.get_children():
		_collect_mesh_stats_recursive(child, stats)
