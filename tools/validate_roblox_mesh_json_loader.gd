extends SceneTree

const RobloxMeshJsonLoader := preload("res://addons/rbxl_importer/roblox_mesh_json_loader.gd")

func _init() -> void:
	var mesh_path := ProjectSettings.globalize_path("user://rbxl_assets/151778863.mesh.json")
	if not FileAccess.file_exists(mesh_path):
		push_error("[validate_roblox_mesh_json_loader] Missing test mesh JSON: %s" % mesh_path)
		quit(1)
		return
	var mesh := RobloxMeshJsonLoader.load_mesh(mesh_path)
	if mesh == null:
		push_error("[validate_roblox_mesh_json_loader] Loader returned null")
		quit(1)
		return
	if mesh.get_surface_count() <= 0:
		push_error("[validate_roblox_mesh_json_loader] Mesh has no surfaces")
		quit(1)
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() < 3 or indices.size() < 3:
		push_error("[validate_roblox_mesh_json_loader] Mesh arrays are empty")
		quit(1)
		return
	var expected_size := Vector3(1.757005, 1.64372, 1.94692)
	var actual_size := mesh.get_aabb().size
	if not actual_size.is_equal_approx(expected_size):
		push_error("[validate_roblox_mesh_json_loader] Source bounds were not restored: expected=%s actual=%s" % [expected_size, actual_size])
		quit(1)
		return
	print("[validate_roblox_mesh_json_loader] OK vertices=%d triangles=%d bounds=%s" % [vertices.size(), int(indices.size() / 3), actual_size])
	quit(0)
