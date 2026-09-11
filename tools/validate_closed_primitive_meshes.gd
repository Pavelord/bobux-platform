extends SceneTree

const WedgeBuilder = preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")
const MeshProxy = preload("res://addons/rbxl_importer/roblox_mesh_proxy.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var imported_wedge := WedgeBuilder.build_wedge(Vector3(4.0, 3.0, 6.0))
	var imported_corner_wedge := WedgeBuilder.build_corner_wedge(Vector3(4.0, 3.0, 6.0))
	var proxy_wedge := MeshProxy._make_wedge_mesh()
	var proxy_cone := MeshProxy._make_cone_mesh() as CylinderMesh
	var imported_closed := _is_closed_triangle_shell(imported_wedge)
	var imported_corner_closed := _is_closed_triangle_shell(imported_corner_wedge)
	var proxy_closed := _is_closed_triangle_shell(proxy_wedge)
	var cone_closed := proxy_cone != null and proxy_cone.cap_top and proxy_cone.cap_bottom
	var ok := imported_closed and imported_corner_closed and proxy_closed and cone_closed
	print("[validate_closed_primitive_meshes] ok=%s imported_wedge=%s corner_wedge=%s proxy_wedge=%s cone_caps=%s" % [ok, imported_closed, imported_corner_closed, proxy_closed, cone_closed])
	quit(0 if ok else 1)


func _is_closed_triangle_shell(mesh: ArrayMesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size() % 3 != 0:
		return false
	var edge_counts := {}
	for triangle_start in range(0, indices.size(), 3):
		for edge_index in range(3):
			var first := _vertex_key(vertices[indices[triangle_start + edge_index]])
			var second := _vertex_key(vertices[indices[triangle_start + ((edge_index + 1) % 3)]])
			var edge_key := "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]
			edge_counts[edge_key] = int(edge_counts.get(edge_key, 0)) + 1
	for count_value in edge_counts.values():
		if int(count_value) != 2:
			return false
	return not edge_counts.is_empty()


func _vertex_key(vertex: Vector3) -> String:
	return "%d,%d,%d" % [roundi(vertex.x * 10000.0), roundi(vertex.y * 10000.0), roundi(vertex.z * 10000.0)]
