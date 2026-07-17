extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[validate_studio_exact_model_source] Studio scene is missing")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var source_path := ProjectSettings.globalize_path("res://files/RolandStudioNoHatsRBLX.obj")
	var entry := {
		"id": "exact_model_validation",
		"name": "Exact Character Mesh",
		"source_model_path": source_path,
		"source_model_loaded": true,
		"parts": [{
			"name": "FallbackThatMustNotBeUsed",
			"kind": "ImportedMeshPart",
			"scale": [9.0, 9.0, 9.0],
			"color": "ffffff",
		}],
	}
	studio._insert_model_draft_into_place(entry)
	for _frame in range(5):
		await process_frame
	var exact_parts: Array[Node3D] = []
	for part in studio._get_editor_parts():
		if str(part.get_meta("source_asset_path", "")) == source_path:
			exact_parts.append(part)
	var geometry_ok := not exact_parts.is_empty()
	var cache_ok := geometry_ok
	var no_proxy_boxes := geometry_ok
	for part in exact_parts:
		var mesh_part := part as MeshInstance3D
		geometry_ok = geometry_ok and mesh_part != null and mesh_part.mesh != null and mesh_part.mesh.get_surface_count() >= 1
		no_proxy_boxes = no_proxy_boxes and not (mesh_part.mesh is BoxMesh)
		var cache_path := str(part.get_meta("bobux_mesh_resource_asset", ""))
		cache_ok = cache_ok and not cache_path.is_empty() and FileAccess.file_exists(cache_path)
	var color_block: Dictionary = studio._model_part_to_studio_block({
		"name": "ColoredPart",
		"kind": "Block",
		"color": {"r": 0.2, "g": 0.6, "b": 0.9, "a": 1.0},
	})
	var parsed_color := color_block.get("color", Color.WHITE) as Color
	var color_ok := parsed_color.is_equal_approx(Color(0.2, 0.6, 0.9, 1.0))
	var ok := geometry_ok and cache_ok and no_proxy_boxes and color_ok
	print("[validate_studio_exact_model_source] ok=%s parts=%d geometry=%s cached=%s no_boxes=%s color=%s" % [
		str(ok), exact_parts.size(), str(geometry_ok), str(cache_ok), str(no_proxy_boxes), str(color_ok),
	])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
