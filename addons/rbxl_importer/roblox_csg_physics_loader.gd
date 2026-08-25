@tool
class_name RobloxCsgPhysicsLoader
extends RefCounted

## Rebuilds the collision hull embedded in UnionOperation.PhysicalConfigData.
## Roblox stores this data inside the place, so it remains available when the
## visual CSG asset is private and Asset Delivery cannot return it.

const CSG_MAGIC := "CSGPHS"
const MESH_HEADER_SIZE := 40
const MAX_VERTICES := 250000
const MAX_INDICES := 1500000


static func load_from_property(value: Variant) -> ArrayMesh:
	var bytes := _property_bytes(value)
	if bytes.size() < 54 or bytes.slice(0, 6).get_string_from_ascii() != CSG_MAGIC:
		return null
	var version := int(bytes.decode_u32(6))
	var offset := 10
	match version:
		3, 5:
			pass
		6:
			offset += 40
		7:
			offset += 41
		_:
			return null
	var surfaces: Array[Dictionary] = []
	while offset < bytes.size():
		var parsed := _read_mesh(bytes, offset)
		if parsed.is_empty():
			break
		surfaces.append(parsed)
		offset = int(parsed.get("next_offset", bytes.size()))
		if version == 6:
			break
	if surfaces.is_empty():
		return null
	return _build_mesh(surfaces)


static func _property_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if value is Dictionary:
		var encoded := str((value as Dictionary).get("__bobux_binary_base64", "")).strip_edges()
		return Marshalls.base64_to_raw(encoded) if not encoded.is_empty() else PackedByteArray()
	var text := str(value).strip_edges()
	if text.is_empty() or text.begins_with("__bobux_blob__"):
		return PackedByteArray()
	return Marshalls.base64_to_raw(text)


static func _read_mesh(bytes: PackedByteArray, offset: int) -> Dictionary:
	if offset < 0 or offset + MESH_HEADER_SIZE + 12 > bytes.size():
		return {}
	if not _has_mesh_header(bytes, offset):
		return {}
	offset += MESH_HEADER_SIZE
	var component_count := int(bytes.decode_u32(offset))
	offset += 4
	var vertex_width := int(bytes.decode_u32(offset))
	offset += 4
	if vertex_width != 4 or component_count < 9 or component_count % 3 != 0:
		return {}
	var vertex_count := component_count / 3
	if vertex_count > MAX_VERTICES or offset + component_count * 4 + 4 > bytes.size():
		return {}
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for index in range(vertex_count):
		var x := bytes.decode_float(offset)
		var y := bytes.decode_float(offset + 4)
		var z := bytes.decode_float(offset + 8)
		offset += 12
		if not is_finite(x) or not is_finite(y) or not is_finite(z):
			return {}
		vertices[index] = Vector3(x, y, -z)
	var index_count := int(bytes.decode_u32(offset))
	offset += 4
	if index_count < 3 or index_count % 3 != 0 or index_count > MAX_INDICES or offset + index_count * 4 > bytes.size():
		return {}
	var indices := PackedInt32Array()
	indices.resize(index_count)
	for triangle_offset in range(0, index_count, 3):
		var a := int(bytes.decode_u32(offset))
		var b := int(bytes.decode_u32(offset + 4))
		var c := int(bytes.decode_u32(offset + 8))
		offset += 12
		if a < 0 or b < 0 or c < 0 or a >= vertex_count or b >= vertex_count or c >= vertex_count:
			return {}
		# Mirroring Roblox Z changes triangle handedness.
		indices[triangle_offset] = a
		indices[triangle_offset + 1] = c
		indices[triangle_offset + 2] = b
	return {"vertices": vertices, "indices": indices, "next_offset": offset}


static func _has_mesh_header(bytes: PackedByteArray, offset: int) -> bool:
	if bytes.decode_u32(offset) != 16 or bytes.decode_u32(offset + 20) != 16:
		return false
	for byte_offset in range(offset + 4, offset + 20):
		if bytes[byte_offset] != 0:
			return false
	for byte_offset in range(offset + 24, offset + 36):
		if bytes[byte_offset] != 0:
			return false
	return is_equal_approx(bytes.decode_float(offset + 36), 1.0)


static func _build_mesh(surfaces: Array[Dictionary]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		var vertices: PackedVector3Array = surface.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = surface.get("indices", PackedInt32Array())
		if vertices.is_empty() or indices.is_empty():
			continue
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		for triangle_offset in range(0, indices.size(), 3):
			var a := indices[triangle_offset]
			var b := indices[triangle_offset + 1]
			var c := indices[triangle_offset + 2]
			var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			if normal.length_squared() <= 0.00000001:
				continue
			normal = normal.normalized()
			normals[a] += normal
			normals[b] += normal
			normals[c] += normal
		for index in range(normals.size()):
			normals[index] = normals[index].normalized() if normals[index].length_squared() > 0.00000001 else Vector3.UP
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() == 0:
		return null
	mesh.resource_name = "Embedded Roblox CSG hull"
	return mesh
