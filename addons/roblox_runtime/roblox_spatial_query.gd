extends RefCounted

# Mesh bounding boxes, including non-collidable queryable Parts. Evaluate in
# part-local space so a rotated building doesn't become a huge world AABB.
static func in_radius(root: Node, position_: Vector3, radius: float, filters: Array, include: bool, max_parts: int, respect_collision: bool) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(root) or not root.is_inside_tree() or not is_finite(radius) or radius < 0: return result
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var part := candidate as MeshInstance3D
		if part.mesh == null or not part.is_visible_in_tree(): continue
		var props: Dictionary = part.get_meta("roblox_properties", {})
		var property := "CanCollide" if respect_collision else "CanQuery"
		if not bool(part.get_meta(property, props.get(property, true))): continue
		var filtered := false
		for filter in filters:
			if is_instance_valid(filter) and (filter == part or filter.is_ancestor_of(part)): filtered = true; break
		if filtered != include: continue
		if is_zero_approx(part.global_basis.determinant()): continue
		var box := part.get_aabb()
		var local_point := part.to_local(position_)
		var closest := local_point.clamp(box.position, box.end)
		if part.to_global(closest).distance_squared_to(position_) > radius * radius: continue
		result.append(part)
		if max_parts > 0 and result.size() >= max_parts: break
	return result

static func in_box(root: Node, frame: Transform3D, size_: Vector3, filters: Array, include: bool, max_parts: int, respect_collision: bool) -> Array[Node]:
	var result: Array[Node] = []
	var half := size_.abs() * 0.5
	var basis := frame.basis.orthonormalized()
	for part in in_radius(root, frame.origin, half.length(), filters, include, 0, respect_collision):
		var box: AABB = part.get_aabb()
		var part_basis: Basis = part.global_basis.orthonormalized()
		var extent: Vector3 = box.size * part.global_basis.get_scale().abs() * 0.5
		var offset: Vector3 = part.to_global(box.get_center()) - frame.origin
		var axes: Array[Vector3] = [basis.x, basis.y, basis.z, part_basis.x, part_basis.y, part_basis.z]
		for first in [basis.x, basis.y, basis.z]:
			for second in [part_basis.x, part_basis.y, part_basis.z]:
				axes.append(first.cross(second))
		var overlap := true
		for axis in axes:
			if axis.length_squared() < 0.00000001: continue
			var a := absf(axis.dot(basis.x)) * half.x + absf(axis.dot(basis.y)) * half.y + absf(axis.dot(basis.z)) * half.z
			var b := absf(axis.dot(part_basis.x)) * extent.x + absf(axis.dot(part_basis.y)) * extent.y + absf(axis.dot(part_basis.z)) * extent.z
			if absf(axis.dot(offset)) > a + b + 0.00001:
				overlap = false
				break
		if overlap:
			result.append(part)
			if max_parts > 0 and result.size() >= max_parts: break
	return result
