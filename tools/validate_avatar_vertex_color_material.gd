extends SceneTree

const MaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const REAL_AVATAR_MODEL := "user://cache/avatar_attachments/happyConus.glb"


func _initialize() -> void:
	var synthetic_root := Node3D.new()
	var synthetic_mesh := MeshInstance3D.new()
	synthetic_mesh.mesh = _build_colored_mesh()
	synthetic_root.add_child(synthetic_mesh)

	var changed := MaterialCache.enable_embedded_vertex_colors(synthetic_root)
	var synthetic_material := synthetic_mesh.get_surface_override_material(0) as StandardMaterial3D
	var synthetic_ok := (
		changed == 1
		and synthetic_material != null
		and synthetic_material.vertex_color_use_as_albedo
		and synthetic_material.vertex_color_is_srgb
	)
	synthetic_root.free()

	var real_checked := false
	var real_ok := true
	var real_changed := 0
	if FileAccess.file_exists(REAL_AVATAR_MODEL):
		real_checked = true
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var append_error := document.append_from_file(REAL_AVATAR_MODEL, state)
		if append_error != OK:
			real_ok = false
		else:
			var real_root := document.generate_scene(state)
			if real_root == null:
				real_ok = false
			else:
				root.add_child(real_root)
				var colored_surfaces := _count_colored_surfaces(real_root)
				real_changed = MaterialCache.enable_embedded_vertex_colors(real_root)
				real_ok = colored_surfaces > 0 and _all_colored_surfaces_enabled(real_root)

	var ok := synthetic_ok and real_ok
	print(
		"[validate_avatar_vertex_color_material] ok=%s synthetic=%s real_checked=%s real_changed=%d"
		% [str(ok), str(synthetic_ok), str(real_checked), real_changed]
	)
	quit(0 if ok else 1)


func _build_colored_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.BACK,
		Vector3.BACK,
		Vector3.BACK,
	])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.RED,
		Color.GREEN,
		Color.BLUE,
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _count_colored_surfaces(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh is ArrayMesh:
		var mesh := (root as MeshInstance3D).mesh as ArrayMesh
		for surface_index in range(mesh.get_surface_count()):
			if (int(mesh.surface_get_format(surface_index)) & int(Mesh.ARRAY_FORMAT_COLOR)) != 0:
				count += 1
	for child in root.get_children():
		count += _count_colored_surfaces(child)
	return count


func _all_colored_surfaces_enabled(root: Node) -> bool:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh is ArrayMesh:
		var mesh_instance := root as MeshInstance3D
		var mesh := mesh_instance.mesh as ArrayMesh
		for surface_index in range(mesh.get_surface_count()):
			if (int(mesh.surface_get_format(surface_index)) & int(Mesh.ARRAY_FORMAT_COLOR)) == 0:
				continue
			var material := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
			if material == null:
				material = mesh.surface_get_material(surface_index) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo:
				return false
	for child in root.get_children():
		if not _all_colored_surfaces_enabled(child):
			return false
	return true
