@tool
class_name RobloxMeshProxy
extends RefCounted

## Best-effort visual mesh proxies for Roblox MeshPart/SpecialMesh assets when
## Roblox does not expose the original mesh binary without authentication.
## Meshes are normalized to roughly 1x1x1; the importer keeps the part scale.

static func proxy_mesh_for_part(roblox_class: String, props: Dictionary, shape_name: String) -> Mesh:
	var name := str(_prop(props, "Name", "")).to_lower()
	var material_id := int(_prop(props, "Material", 256))
	var mesh_id := str(_prop(props, "MeshId", _prop(props, "MeshID", ""))).strip_edges()
	if roblox_class == "MeshPart" or not mesh_id.is_empty():
		if _looks_like_curved_part(name, mesh_id):
			return _make_curved_part_mesh()
		if _looks_like_leaf(name, material_id):
			return _make_foliage_mesh()
		if _looks_like_cone(name):
			return _make_cone_mesh()
		if _looks_like_rock(name, material_id):
			return _make_rock_mesh()
		if _looks_like_gem(name):
			return _make_gem_mesh()
		if _looks_like_rope_or_blade(name):
			return _make_cylinder_mesh(12)
		if _looks_like_wing_or_plate(name):
			return _make_wedge_mesh()
		if _looks_like_character_or_statue(name):
			return _make_capsule_mesh()
	match shape_name:
		"Sphere":
			return _make_rock_mesh()
		"Cylinder":
			return _make_cylinder_mesh(16)
		"Wedge":
			return _make_wedge_mesh()
		"Pyramid":
			return _make_cone_mesh()
		_:
			return null


static func _looks_like_leaf(name: String, material_id: int) -> bool:
	return name.find("leaf") >= 0 or name.find("leaves") >= 0 or name.find("tree") >= 0 or name.find("grass") >= 0 or material_id == 1280


static func _looks_like_cone(name: String) -> bool:
	return name.find("cone") >= 0 or name.find("pine") >= 0 or name.find("tip") >= 0 or name.find("top") >= 0


static func _looks_like_curved_part(name: String, mesh_id: String) -> bool:
	var lowered_id := mesh_id.to_lower()
	return (
		name.find("curved") >= 0
		or name.find("curve") >= 0
		or lowered_id.find("9756259") >= 0
	)


static func _looks_like_rock(name: String, material_id: int) -> bool:
	return name.find("rock") >= 0 or name.find("stone") >= 0 or name.find("boulder") >= 0 or material_id in [800, 816, 832, 880, 896, 912, 1392, 1440]


static func _looks_like_gem(name: String) -> bool:
	return name.find("gem") >= 0 or name.find("diamond") >= 0 or name.find("crystal") >= 0


static func _looks_like_rope_or_blade(name: String) -> bool:
	return name.find("rope") >= 0 or name.find("cable") >= 0 or name.find("stick") >= 0 or name.find("blade") >= 0 or name.find("bolt") >= 0


static func _looks_like_wing_or_plate(name: String) -> bool:
	return name.find("wing") >= 0 or name.find("fin") >= 0 or name.find("nose") >= 0 or name.find("wedge") >= 0


static func _looks_like_character_or_statue(name: String) -> bool:
	return name.find("body") >= 0 or name.find("head") >= 0 or name.find("statue") >= 0


static func _make_foliage_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 0.82
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh


static func _make_rock_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 0.92
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


static func _make_capsule_mesh() -> Mesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.34
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


static func _make_cone_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 1
	# CylinderMesh caps are configurable. Set them explicitly so proxy cones do
	# not depend on engine-version defaults and remain opaque from every angle.
	mesh.cap_top = true
	mesh.cap_bottom = true
	return mesh


static func _make_cylinder_mesh(segments: int) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = maxi(6, segments)
	mesh.rings = 1
	return mesh


static func _make_curved_part_mesh() -> Mesh:
	var segments := 18
	var outer_radius := 0.5
	var inner_radius := 0.22
	var half_height := 0.5
	var center_offset := Vector3(0.25, 0.0, 0.25)
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()

	var _point := func(radius: float, angle: float, y: float) -> Vector3:
		return Vector3(cos(angle) * radius, y, sin(angle) * radius) - center_offset

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := t * PI * 0.5
		verts.append(_point.call(outer_radius, angle, half_height))
		verts.append(_point.call(inner_radius, angle, half_height))
		verts.append(_point.call(outer_radius, angle, -half_height))
		verts.append(_point.call(inner_radius, angle, -half_height))

	var add_quad := func(a: int, b: int, c: int, d: int) -> void:
		indices.append_array([a, c, b, b, c, d])

	for i in range(segments):
		var base := i * 4
		var next := (i + 1) * 4
		add_quad.call(base + 0, next + 0, base + 2, next + 2) # outer wall
		add_quad.call(next + 1, base + 1, next + 3, base + 3) # inner wall
		add_quad.call(base + 0, base + 1, next + 0, next + 1) # top
		add_quad.call(base + 2, next + 2, base + 3, next + 3) # bottom

	add_quad.call(0, 2, 1, 3)
	var last := segments * 4
	add_quad.call(last + 0, last + 1, last + 2, last + 3)
	return _mesh_from_arrays(verts, indices)


static func _make_gem_mesh() -> Mesh:
	var verts := PackedVector3Array([
		Vector3(0.0, 0.5, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.5),
		Vector3(-0.5, 0.0, 0.0),
		Vector3(0.0, 0.0, -0.5),
		Vector3(0.0, -0.5, 0.0),
	])
	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1,
		5, 2, 1, 5, 3, 2, 5, 4, 3, 5, 1, 4,
	])
	return _mesh_from_arrays(verts, indices)


static func _make_wedge_mesh() -> Mesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, 0.5),
		Vector3(0.5, 0.5, 0.5),
	])
	var indices := PackedInt32Array([
		# Bottom (-Y)
		0, 1, 2, 1, 3, 2,
		# Full-height face (+Z)
		2, 3, 4, 3, 5, 4,
		# Slope (+Y/-Z)
		0, 4, 1, 1, 4, 5,
		# Triangular end caps (-X, +X)
		0, 2, 4,
		1, 5, 3,
	])
	return _mesh_from_arrays(verts, indices)


static func _mesh_from_arrays(verts: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, indices.size(), 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		var normal := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia]).normalized()
		normals[ia] += normal
		normals[ib] += normal
		normals[ic] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(Vector2(v.x + 0.5, 1.0 - (v.z + 0.5)))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _prop(props: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if props.has(key):
		return props[key]
	var lower := key.to_lower()
	if props.has(lower):
		return props[lower]
	for candidate in props.keys():
		if str(candidate).to_lower() == lower:
			return props[candidate]
	return fallback
