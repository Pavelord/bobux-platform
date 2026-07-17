extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_resource := load("res://scenes/model_editor/model_editor.tscn") as PackedScene
	if scene_resource == null:
		_fail("Model Editor scene could not be loaded.")
		_finish()
		return
	var editor := scene_resource.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	editor.call("_clear_parts")
	await process_frame

	var parts_root := editor.get("_parts_root") as Node3D
	if parts_root == null:
		_fail("Model Editor did not create PartsRoot.")
		_finish()
		return
	var imported_root := Node3D.new()
	imported_root.name = "ImportedValidationModel"
	imported_root.set_meta("kind", "ImportedScene")
	parts_root.add_child(imported_root)
	imported_root.add_child(_colored_mesh("RedSurface", Color(0.85, 0.12, 0.08)))
	var blue_mesh := _colored_mesh("BlueSurface", Color(0.08, 0.24, 0.88))
	blue_mesh.position.x = 1.25
	imported_root.add_child(blue_mesh)
	await process_frame

	var model_data: Dictionary = editor.call("_collect_model_data")
	var source_path := str(model_data.get("canonical_source_model_path", ""))
	var parts: Array = model_data.get("parts", []) if model_data.get("parts", []) is Array else []
	var has_surface_materials := false
	for part_variant in parts:
		if part_variant is Dictionary and not ((part_variant as Dictionary).get("surface_materials", []) as Array).is_empty():
			has_surface_materials = true
			break
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		_fail("Canonical GLB was not exported.")
	if parts.size() != 2 or not has_surface_materials:
		_fail("Serialized model did not preserve both colored mesh parts.")
	if not source_path.is_empty() and FileAccess.file_exists(source_path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(source_path, state) != OK:
			_fail("Canonical GLB could not be read back.")
		else:
			var generated := document.generate_scene(state)
			var colors: Array[Color] = []
			_collect_material_colors(generated, colors)
			if not _contains_similar_color(colors, Color(0.85, 0.12, 0.08)) or not _contains_similar_color(colors, Color(0.08, 0.24, 0.88)):
				_fail("Canonical GLB lost source material colors.")
			generated.queue_free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))

	print("[validate_model_asset_pipeline] ok=%s parts=%d canonical=%s materials=%s" % [
		str(not _failed),
		parts.size(),
		str(not source_path.is_empty()),
		str(has_surface_materials)
	])
	editor.queue_free()
	await process_frame
	_finish()


func _colored_mesh(mesh_name: String, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.63
	mesh.material = material
	mesh_instance.mesh = mesh
	return mesh_instance


func _collect_material_colors(node: Node, colors: Array[Color]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.get_active_material(surface_index)
				if material is BaseMaterial3D:
					colors.append((material as BaseMaterial3D).albedo_color)
	for child in node.get_children():
		_collect_material_colors(child, colors)


func _contains_similar_color(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if absf(color.r - expected.r) < 0.08 and absf(color.g - expected.g) < 0.08 and absf(color.b - expected.b) < 0.08:
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error("[validate_model_asset_pipeline] %s" % message)


func _finish() -> void:
	quit(1 if _failed else 0)
