extends SceneTree

const MaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")


func _initialize() -> void:
	var map_folder := _argument_value("--map-folder=")
	if map_folder.is_empty():
		map_folder = _find_newest_nonempty_map_folder()
	if map_folder.is_empty():
		push_error("[validate_real_saved_map_materials] no saved map found")
		quit(1)
		return
	var path := map_folder.path_join("map_data.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[validate_real_saved_map_materials] cannot open %s" % path)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("[validate_real_saved_map_materials] invalid JSON")
		quit(1)
		return
	var blocks: Array = (parsed as Dictionary).get("blocks", [])
	var mesh_blocks := 0
	var colored_mesh_blocks := 0
	var resource_color_mismatches := 0
	var textured_resources := 0
	var runtime_color_mismatches := 0
	var runtime_builder: Node = load("res://scripts/main/main.gd").new()
	var samples: Array[String] = []
	for block_variant in blocks:
		if not (block_variant is Dictionary):
			continue
		var block := block_variant as Dictionary
		var expected := _block_color(block)
		var runtime_color: Color = runtime_builder.call("_color_from_block_data", block, Color.WHITE)
		var runtime_material: StandardMaterial3D = runtime_builder.call(
			"_create_material",
			runtime_color,
			str(block.get("material", "Plastic")),
			float(block.get("transparency", 0.0))
		) as StandardMaterial3D
		if bool(runtime_builder.call("_should_apply_saved_roblox_block_material", block)):
			var runtime_cache: Variant = runtime_builder.get("_runtime_rbxl_material_cache")
			if runtime_cache != null:
				runtime_material = runtime_cache.call(
					"get_part_material_with_color",
					block.get("roblox_properties", {}),
					runtime_color
				) as StandardMaterial3D
		if runtime_material == null or Vector3(runtime_material.albedo_color.r, runtime_material.albedo_color.g, runtime_material.albedo_color.b).distance_to(Vector3(expected.r, expected.g, expected.b)) > 0.12:
			runtime_color_mismatches += 1
			if samples.size() < 8:
				samples.append("runtime %s expected=%s resolved=%s material=%s" % [str(block.get("name", "Part")), expected, runtime_color, runtime_material.albedo_color if runtime_material != null else Color.TRANSPARENT])
		var asset := str(block.get("bobux_mesh_resource_asset", "")).strip_edges()
		if asset.is_empty():
			continue
		mesh_blocks += 1
		if not _is_gray(expected):
			colored_mesh_blocks += 1
		var resource_path := asset
		if not (asset.begins_with("res://") or asset.begins_with("user://") or asset.is_absolute_path()):
			resource_path = map_folder.path_join(asset)
		var mesh: Mesh = ResourceLoader.load(_loader_path(resource_path)) as Mesh
		if mesh == null:
			continue
		var found_color := Color.WHITE
		var has_color := false
		var has_texture := false
		for surface_index in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface_index)
			if material is BaseMaterial3D:
				var base := material as BaseMaterial3D
				if not has_color:
					found_color = base.albedo_color
					has_color = true
				if base.albedo_texture != null:
					has_texture = true
		if has_texture:
			textured_resources += 1
		var expected_rgb := Vector3(expected.r, expected.g, expected.b)
		var found_rgb := Vector3(found_color.r, found_color.g, found_color.b)
		if has_color and not has_texture and expected_rgb.distance_to(found_rgb) > 0.12:
			resource_color_mismatches += 1
			if samples.size() < 8:
				samples.append("%s expected=%s resource=%s asset=%s" % [str(block.get("name", "MeshPart")), expected, found_color, asset])
	runtime_builder.free()
	print("[validate_real_saved_map_materials] folder=%s blocks=%d mesh_blocks=%d colored_mesh_blocks=%d textured_resources=%d resource_mismatches=%d runtime_mismatches=%d" % [map_folder, blocks.size(), mesh_blocks, colored_mesh_blocks, textured_resources, resource_color_mismatches, runtime_color_mismatches])
	for sample in samples:
		print("[validate_real_saved_map_materials] ", sample)
	quit(0 if resource_color_mismatches == 0 and runtime_color_mismatches == 0 else 1)


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length()).strip_edges()
	return ""


func _find_newest_nonempty_map_folder() -> String:
	var roots := [
		ProjectSettings.globalize_path("user://cache/users"),
		ProjectSettings.globalize_path("user://cache/maps")
	]
	var newest_path := ""
	var newest_time := 0
	for root in roots:
		for path in _find_map_files(str(root)):
			var modified := int(FileAccess.get_modified_time(path))
			if modified > newest_time and FileAccess.get_size(path) > 64:
				newest_time = modified
				newest_path = path.get_base_dir()
	return newest_path


func _find_map_files(root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := root.path_join(entry)
			if directory.current_is_dir():
				result.append_array(_find_map_files(path))
			elif entry == "map_data.json":
				result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _loader_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var normalized := path.replace("\\", "/")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if normalized.begins_with(user_root + "/"):
		return "user://" + normalized.substr(user_root.length() + 1)
	return ProjectSettings.localize_path(path)


func _block_color(block: Dictionary) -> Color:
	for key in ["color", "Color", "colour", "albedo", "albedo_color", "Color3", "Color3uint8"]:
		if block.has(key):
			return _variant_color(block.get(key), Color.WHITE)
	if block.has("cr") or block.has("cg") or block.has("cb"):
		return _variant_color([block.get("cr", 1.0), block.get("cg", 1.0), block.get("cb", 1.0), block.get("ca", 1.0)], Color.WHITE)
	if block.get("roblox_properties", {}) is Dictionary:
		return MaterialCache.part_color_from_properties(block.get("roblox_properties", {}))
	return Color.WHITE


func _variant_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Array:
		var values := value as Array
		var color := Color(
			float(values[0]) if values.size() > 0 else fallback.r,
			float(values[1]) if values.size() > 1 else fallback.g,
			float(values[2]) if values.size() > 2 else fallback.b,
			float(values[3]) if values.size() > 3 else fallback.a
		)
		if maxf(color.r, maxf(color.g, color.b)) > 1.0:
			color.r /= 255.0
			color.g /= 255.0
			color.b /= 255.0
		return color
	return fallback


func _is_gray(color: Color) -> bool:
	return maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) < 0.05
