extends SceneTree

const MaterialCache := preload("res://addons/rbxl_importer/material_cache.gd")
const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

func _initialize() -> void:
	var cache := MaterialCache.new()
	var textured_names := ["Wood", "WoodPlanks", "Concrete", "Brick", "Grass", "Sand", "Metal", "Slate"]
	var textured_ok := true
	for material_name in textured_names:
		var material := cache.get_named_material(Color(0.42, 0.67, 0.31), material_name, 0.0)
		textured_ok = textured_ok and material != null and material.albedo_texture != null

	var array_mesh := ArrayMesh.new()
	_add_triangle_surface(array_mesh, 0.0)
	_add_triangle_surface(array_mesh, 0.2)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	var importer := RuntimeImporter.new()
	importer._ensure_imported_mesh_double_sided(mesh_instance)
	var surfaces_ok := array_mesh.get_surface_count() == 2
	for surface_index in range(array_mesh.get_surface_count()):
		var material := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
		surfaces_ok = surfaces_ok and material != null and material.cull_mode == BaseMaterial3D.CULL_DISABLED

	var ok := textured_ok and surfaces_ok
	print("[validate_studio_material_mesh_rendering] ok=%s textures=%s surfaces=%d double_sided=%s" % [
		str(ok), str(textured_ok), array_mesh.get_surface_count(), str(surfaces_ok)
	])
	for surface_index in range(array_mesh.get_surface_count()):
		mesh_instance.set_surface_override_material(surface_index, null)
	mesh_instance.mesh = null
	mesh_instance.free()
	array_mesh.clear_surfaces()
	quit(0 if ok else 1)

func _add_triangle_surface(mesh: ArrayMesh, z_offset: float) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, z_offset),
		Vector3(0.5, -0.5, z_offset),
		Vector3(0.0, 0.5, z_offset),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1.0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, StandardMaterial3D.new())
