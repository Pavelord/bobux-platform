@tool
class_name RobloxMeshJsonLoader
extends RefCounted

## Loads normalized Roblox .mesh geometry exported by rbxl_converter.py.
## The Python side writes flat arrays to keep GDScript parsing predictable.

static func load_mesh(path: String) -> ArrayMesh:
	var resolved := path
	if resolved.begins_with("user://") or resolved.begins_with("res://"):
		resolved = ProjectSettings.globalize_path(resolved)
	if not FileAccess.file_exists(resolved):
		return null
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed
	var vertex_values: Array = data.get("vertices", []) if data.get("vertices", []) is Array else []
	var normal_values: Array = data.get("normals", []) if data.get("normals", []) is Array else []
	var uv_values: Array = data.get("uvs", []) if data.get("uvs", []) is Array else []
	var color_values: Array = data.get("colors", []) if data.get("colors", []) is Array else []
	var index_values: Array = data.get("indices", []) if data.get("indices", []) is Array else []
	if vertex_values.size() < 9 or index_values.size() < 3:
		return null
	var restore_source_bounds := bool(data.get("normalized_to_unit_bounds", false))
	var source_bounds_min_values: Array = data.get("source_bounds_min", []) if data.get("source_bounds_min", []) is Array else []
	var source_bounds_max_values: Array = data.get("source_bounds_max", []) if data.get("source_bounds_max", []) is Array else []
	var source_bounds_size_values: Array = data.get("source_bounds_size", []) if data.get("source_bounds_size", []) is Array else []
	if source_bounds_min_values.size() < 3 or source_bounds_max_values.size() < 3 or source_bounds_size_values.size() < 3:
		restore_source_bounds = false
	var source_bounds_min := Vector3.ZERO
	var source_bounds_size := Vector3.ONE
	var source_bounds_center := Vector3.ZERO
	if restore_source_bounds:
		source_bounds_min = Vector3(
			float(source_bounds_min_values[0]),
			float(source_bounds_min_values[1]),
			float(source_bounds_min_values[2])
		)
		var source_bounds_max := Vector3(
			float(source_bounds_max_values[0]),
			float(source_bounds_max_values[1]),
			float(source_bounds_max_values[2])
		)
		source_bounds_size = Vector3(
			maxf(absf(float(source_bounds_size_values[0])), 0.000001),
			maxf(absf(float(source_bounds_size_values[1])), 0.000001),
			maxf(absf(float(source_bounds_size_values[2])), 0.000001)
		)
		source_bounds_center = (source_bounds_min + source_bounds_max) * 0.5
	var vertex_count := int(vertex_values.size() / 3)
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for i in range(vertex_count):
		var vertex := Vector3(
			float(vertex_values[i * 3]),
			float(vertex_values[i * 3 + 1]),
			float(vertex_values[i * 3 + 2])
		)
		if restore_source_bounds:
			vertex = vertex * source_bounds_size + source_bounds_center
		vertices[i] = vertex
	var normals := PackedVector3Array()
	if normal_values.size() >= vertex_count * 3:
		normals.resize(vertex_count)
		for i in range(vertex_count):
			normals[i] = Vector3(
				float(normal_values[i * 3]),
				float(normal_values[i * 3 + 1]),
				float(normal_values[i * 3 + 2])
			).normalized()
	var uvs := PackedVector2Array()
	if uv_values.size() >= vertex_count * 2:
		uvs.resize(vertex_count)
		for i in range(vertex_count):
			uvs[i] = Vector2(float(uv_values[i * 2]), float(uv_values[i * 2 + 1]))
	var colors := PackedColorArray()
	if color_values.size() >= vertex_count * 4:
		colors.resize(vertex_count)
		for i in range(vertex_count):
			colors[i] = Color8(
				int(color_values[i * 4]),
				int(color_values[i * 4 + 1]),
				int(color_values[i * 4 + 2]),
				int(color_values[i * 4 + 3])
			)
	var indices := PackedInt32Array()
	indices.resize(index_values.size())
	for i in range(index_values.size()):
		indices[i] = int(index_values[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if normals.size() == vertex_count:
		arrays[Mesh.ARRAY_NORMAL] = normals
	if uvs.size() == vertex_count:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if colors.size() == vertex_count:
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = str(data.get("asset_id", path.get_file()))
	return mesh
