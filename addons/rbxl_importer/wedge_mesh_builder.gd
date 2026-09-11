@tool
class_name RbxlWedgeMeshBuilder
extends RefCounted

## Builds ArrayMesh resources that reproduce Roblox WedgePart and CornerWedgePart
## geometry, sized in Godot units.
##
## Roblox wedge convention (Y up, +X right, -Z forward):
##   bottom face spans the full box; the +Z top edge is lowered to y=0,
##   forming a right-triangular prism. We mirror this into Godot's coordinate
##   system during the build.


static func build_wedge(size: Vector3) -> ArrayMesh:
	# WedgePart: a triangular prism. Local space is centered on the origin so the
	# resulting mesh matches BoxMesh's centering convention.
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	# 6 vertices for a wedge: 4 on the bottom, 2 on the top-front edge.
	# +Z is the "back" face; the slope goes from the +Z bottom up to nothing on
	# the -Z side, so the top edge sits at -Z.
	var v0 := Vector3(-hx, -hy,  hz) # bottom back-left
	var v1 := Vector3( hx, -hy,  hz) # bottom back-right
	var v2 := Vector3( hx, -hy, -hz) # bottom front-right
	var v3 := Vector3(-hx, -hy, -hz) # bottom front-left
	var v4 := Vector3(-hx,  hy, -hz) # top front-left
	var v5 := Vector3( hx,  hy, -hz) # top front-right

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var _add_triangle := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		var base: int = verts.size()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0)])
		indices.append_array([base, base + 1, base + 2])

	# Bottom
	_add_triangle.call(v0, v3, v2)
	_add_triangle.call(v0, v2, v1)
	# Front: the full-height rectangular face at -Z.
	_add_triangle.call(v3, v4, v5)
	_add_triangle.call(v3, v5, v2)
	# Slope: the rectangular face joining the +Z bottom edge to the -Z top edge.
	_add_triangle.call(v0, v1, v5)
	_add_triangle.call(v0, v5, v4)
	# Left side triangle
	_add_triangle.call(v0, v4, v3)
	# Right side triangle
	_add_triangle.call(v1, v2, v5)

	return _build_mesh(verts, normals, uvs, indices)


static func build_corner_wedge(size: Vector3) -> ArrayMesh:
	# CornerWedgePart: a wedge that slopes along two axes (a corner cut).
	# Modelled as a tetra-cut box: bottom rectangle + one top vertex.
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var v0 := Vector3(-hx, -hy,  hz) # bottom back-left
	var v1 := Vector3( hx, -hy,  hz) # bottom back-right
	var v2 := Vector3( hx, -hy, -hz) # bottom front-right
	var v3 := Vector3(-hx, -hy, -hz) # bottom front-left
	var v4 := Vector3(-hx,  hy,  hz) # top back-left (apex of the corner)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var _add_triangle := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		var base: int = verts.size()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0)])
		indices.append_array([base, base + 1, base + 2])

	# Bottom
	_add_triangle.call(v0, v3, v2)
	_add_triangle.call(v0, v2, v1)
	# Back (+Z)
	_add_triangle.call(v0, v1, v4)
	# Left (-X)
	_add_triangle.call(v0, v4, v3)
	# Slope (top face from apex down to the two front-bottom corners)
	_add_triangle.call(v1, v2, v4)
	_add_triangle.call(v2, v3, v4)

	return _build_mesh(verts, normals, uvs, indices)


static func build_pyramid(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var v0 := Vector3(-hx, -hy,  hz)
	var v1 := Vector3( hx, -hy,  hz)
	var v2 := Vector3( hx, -hy, -hz)
	var v3 := Vector3(-hx, -hy, -hz)
	var apex := Vector3(0.0, hy, 0.0)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var _add_triangle := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		var base: int = verts.size()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
		indices.append_array([base, base + 1, base + 2])

	_add_triangle.call(v0, v3, v2)
	_add_triangle.call(v0, v2, v1)
	_add_triangle.call(v0, v1, apex)
	_add_triangle.call(v1, v2, apex)
	_add_triangle.call(v2, v3, apex)
	_add_triangle.call(v3, v0, apex)

	return _build_mesh(verts, normals, uvs, indices)


static func build_truss(size: Vector3) -> ArrayMesh:
	# TrussPart is approximated as a thin rung ladder of cross-bars merged into
	# a single ArrayMesh. Real trusses have side rails + rungs; this emits a
	# decorative lattice adequate for visual parity.
	var mesh := ArrayMesh.new()
	var count_x := maxi(1, int(round(size.x / 1.0)))
	var count_y := maxi(1, int(round(size.y / 2.0)))
	var count_z := maxi(1, int(round(size.z / 1.0)))

	var combined_verts := PackedVector3Array()
	var combined_normals := PackedVector3Array()
	var combined_uvs := PackedVector2Array()
	var combined_indices := PackedInt32Array()

	var add_box := func(center: Vector3, half: Vector3) -> void:
		var base := combined_verts.size()
		var hv := [
			Vector3(-1, -1,  1), Vector3( 1, -1,  1),
			Vector3( 1,  1,  1), Vector3(-1,  1,  1),
			Vector3(-1, -1, -1), Vector3( 1, -1, -1),
			Vector3( 1,  1, -1), Vector3(-1,  1, -1),
		]
		for v in hv:
			combined_verts.append(center + Vector3(v.x * half.x, v.y * half.y, v.z * half.z))
			combined_normals.append(Vector3(v.x, v.y, v.z).normalized())
			combined_uvs.append(Vector2(float(v.x > 0), float(v.y > 0)))
		var tris := [
			0, 1, 2, 0, 2, 3,   # +Z
			5, 4, 7, 5, 7, 6,   # -Z
			4, 0, 3, 4, 3, 7,   # -X
			1, 5, 6, 1, 6, 2,   # +X
			3, 2, 6, 3, 6, 7,   # +Y
			4, 5, 1, 4, 1, 0,   # -Y
		]
		for t in tris:
			combined_indices.append(base + t)

	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	# Side rails
	for side in [-1, 1]:
		for j in range(count_y):
			var y := -hy + (j + 0.5) * (size.y / float(count_y))
			add_box.call(Vector3(side * (hx - 0.15), y, 0.0), Vector3(0.1, 0.4, hz))
	# Rungs
	for j in range(count_y):
		var y := -hy + (j + 0.5) * (size.y / float(count_y))
		add_box.call(Vector3(0.0, y, 0.0), Vector3(hx - 0.2, 0.1, hz))
	# Vertical bars (for Z thickness)
	for k in range(count_z):
		var z := -hz + (k + 0.5) * (size.z / float(count_z))
		add_box.call(Vector3(0.0, 0.0, z), Vector3(hx - 0.2, hy, 0.1))

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = combined_verts
	arr[Mesh.ARRAY_NORMAL] = combined_normals
	arr[Mesh.ARRAY_TEX_UV] = combined_uvs
	arr[Mesh.ARRAY_INDEX] = combined_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _build_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
