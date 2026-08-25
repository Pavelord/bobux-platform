extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cache_folder := "user://validation/model_material_roundtrip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_folder))
	var resource_path := cache_folder.path_join("two_surface_model.res")
	var source_mesh := _build_two_surface_mesh()
	if ResourceSaver.save(source_mesh, resource_path, ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
		_fail("Could not save the source mesh resource.")
		_finish(resource_path)
		return

	var main_script := load("res://scripts/main/main.gd") as Script
	if main_script == null:
		_fail("Main runtime script could not be loaded.")
		_finish(resource_path)
		return
	var runtime: Node = main_script.new() as Node
	if runtime == null:
		_fail("Main runtime script could not be instantiated.")
		_finish(resource_path)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	runtime.call("_apply_saved_bobux_mesh_resource", mesh_instance, {
		"bobux_mesh_resource_asset": resource_path.get_file()
	}, ProjectSettings.globalize_path(cache_folder))

	var colors: Array[Color] = []
	if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() != 2:
		_fail("Runtime loader did not restore both mesh surfaces.")
	else:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			if material is BaseMaterial3D:
				colors.append((material as BaseMaterial3D).albedo_color)
	if not _contains_color(colors, Color(0.86, 0.12, 0.07)):
		_fail("Runtime mesh lost the red surface material.")
	if not _contains_color(colors, Color(0.05, 0.24, 0.9)):
		_fail("Runtime mesh lost the blue surface material.")

	print("[validate_saved_model_material_roundtrip] ok=%s surfaces=%d colors=%s" % [
		str(not _failed),
		mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0,
		str(colors)
	])
	runtime.free()
	mesh_instance.free()
	_finish(resource_path)


func _build_two_surface_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(-0.6))
	mesh.surface_set_material(0, _material(Color(0.86, 0.12, 0.07)))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(0.6))
	mesh.surface_set_material(1, _material(Color(0.05, 0.24, 0.9)))
	return mesh


func _triangle_arrays(x_offset: float) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(x_offset - 0.4, -0.4, 0.0),
		Vector3(x_offset + 0.4, -0.4, 0.0),
		Vector3(x_offset, 0.4, 0.0)
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	return arrays


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.58
	return material


func _contains_color(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if absf(color.r - expected.r) < 0.03 and absf(color.g - expected.g) < 0.03 and absf(color.b - expected.b) < 0.03:
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error("[validate_saved_model_material_roundtrip] %s" % message)


func _finish(resource_path: String) -> void:
	if FileAccess.file_exists(resource_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(resource_path))
	quit(1 if _failed else 0)
