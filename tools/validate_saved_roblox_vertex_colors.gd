extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var folder := ProjectSettings.globalize_path("user://validation/roblox_vertex_colors")
	DirAccess.make_dir_recursive_absolute(folder)
	var mesh_file := "vertex_color.mesh.json"
	var mesh_path := folder.path_join(mesh_file)
	var payload := {
		"asset_id": "vertex-color-test",
		"vertices": [-0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0],
		"normals": [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
		"uvs": [0.0, 1.0, 1.0, 1.0, 0.5, 0.0],
		"colors": [255, 24, 16, 255, 16, 220, 48, 255, 24, 64, 255, 255],
		"indices": [0, 1, 2]
	}
	var file := FileAccess.open(mesh_path, FileAccess.WRITE)
	if file == null:
		_finish(false, mesh_path, "could not create fixture")
		return
	file.store_string(JSON.stringify(payload))
	file.close()

	var block_data := {
		"roblox_mesh_json_asset": mesh_file,
		"color": [0.42, 0.42, 0.42, 1.0]
	}
	var main_script := load("res://scripts/main/main.gd") as Script
	var studio_script := load("res://scripts/place_editor/studio.gd") as Script
	var main_node: Node = main_script.new()
	var studio_node: Node = studio_script.new()
	var main_mesh := _fixture_mesh_instance()
	var studio_mesh := _fixture_mesh_instance()
	main_node.call("_apply_saved_roblox_mesh_asset", main_mesh, block_data, folder)
	studio_node.call("_apply_saved_roblox_mesh_asset", studio_mesh, block_data, folder)

	var main_ok := _uses_vertex_colors(main_mesh)
	var studio_ok := _uses_vertex_colors(studio_mesh)
	print("[validate_saved_roblox_vertex_colors] ok=%s main=%s studio=%s" % [
		str(main_ok and studio_ok), str(main_ok), str(studio_ok)
	])
	main_mesh.free()
	studio_mesh.free()
	main_node.free()
	studio_node.free()
	_finish(main_ok and studio_ok, mesh_path, "vertex colors were disabled")


func _fixture_mesh_instance() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.42, 0.42)
	instance.set_surface_override_material(0, material)
	return instance


func _uses_vertex_colors(instance: MeshInstance3D) -> bool:
	if instance.mesh == null or instance.mesh.get_surface_count() != 1:
		return false
	var format := int((instance.mesh as ArrayMesh).surface_get_format(0)) if instance.mesh is ArrayMesh else 0
	var material := instance.get_active_material(0) as StandardMaterial3D
	return (format & int(Mesh.ARRAY_FORMAT_COLOR)) != 0 \
		and material != null \
		and material.vertex_color_use_as_albedo


func _finish(ok: bool, mesh_path: String, error_message: String) -> void:
	if FileAccess.file_exists(mesh_path):
		DirAccess.remove_absolute(mesh_path)
	if not ok:
		push_error("[validate_saved_roblox_vertex_colors] %s" % error_message)
	quit(0 if ok else 1)
