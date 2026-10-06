extends Node

const QUERIES = preload("res://addons/roblox_runtime/roblox_spatial_query.gd")

# Legacy MakeJoints joins touching surfaces, not every part in a Model. Keep a
# reverse index so disasters can detach one brick without scanning the place.
const PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
const CELL := 8.0
const EPSILON := 0.04
const FACES := ["RightSurface", "TopSurface", "FrontSurface", "LeftSurface", "BottomSurface", "BackSurface"]

static func register_joint(part: Node, joint: Node) -> void:
	var ids: Array = part.get_meta("_bobux_joint_ids", [])
	if not ids.has(joint.get_instance_id()): ids.append(joint.get_instance_id())
	part.set_meta("_bobux_joint_ids", ids)

static func break_part(part: Node) -> void:
	for supported_id in part.get_meta("_bobux_supported_assemblies", []):
		var supported: Variant = instance_from_id(supported_id)
		if is_instance_valid(supported): supported.break_external_support(part)
	part.remove_meta("_bobux_supported_assemblies")
	var assembly_id := int(part.get_meta("_bobux_surface_assembly", 0))
	var assembly: Variant = instance_from_id(assembly_id) if assembly_id else null
	if is_instance_valid(assembly): assembly.break_connections(part)
	var ids: Array = part.get_meta("_bobux_joint_ids", [])
	part.set_meta("_bobux_joint_ids", [])
	for id in ids:
		var joint: Variant = instance_from_id(int(id))
		if is_instance_valid(joint) and not joint.is_queued_for_deletion():
			if joint is Joint3D:
				joint.node_a = NodePath()
				joint.node_b = NodePath()
			joint.queue_free()
	var body := PHYSICS.body_for(part)
	if body != null: body.sleeping = false

static func make_joints(root: Node) -> int:
	if not root.is_inside_tree(): return 0
	var parts: Array[MeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh != null and QUERIES.is_part(node):
			parts.append(node)
		for child in node.get_children():
			if not bool(child.get_meta("bobux_runtime_generated", false)): pending.append(child)
	var owned_count := parts.size()
	var repair_seams := bool(root.get_meta("attribute_BobuxRepairLegacySeams", false))
	var tolerance := 0.25 if repair_seams else EPSILON
	# MakeJoints also joins touching Parts outside the requested Model. Keep
	# anchored supports external so deleting a round never deletes lobby physics.
	var engine := root.get_tree().root.get_node("LuaScriptEngine")
	var workspace: Node = engine._resolve_workspace_node(root.get_tree().current_scene, root)
	if workspace != root:
		for part in workspace.find_children("*", "MeshInstance3D", true, false):
			if root.is_ancestor_of(part) or part.mesh == null or not bool(part.get_meta("anchored", part.get_meta("roblox_properties", {}).get("Anchored", true))): continue
			if not QUERIES.is_part(part) or not part.is_visible_in_tree(): continue
			parts.append(part)
	var external_supports := {}
	var container := root.get_node_or_null("RobloxSurfaceJoints")
	if container == null:
		container = Node3D.new()
		container.name = "RobloxSurfaceJoints"
		container.set_meta("bobux_runtime_generated", true)
		root.add_child(container)
	var grid := {}
	var bounds: Array[AABB] = []
	var large: Array[int] = []
	var count := 0
	var connections: Array = []
	for index in parts.size():
		var part := parts[index]
		var box: AABB = (part.global_transform * QUERIES.bounds(part)).grow(tolerance)
		bounds.append(box)
		var low := Vector3i((box.position / CELL).floor())
		var high := Vector3i((box.end / CELL).floor())
		var span := high - low + Vector3i.ONE
		var candidates := {}
		if span.x * span.y * span.z > 4096:
			for previous in index: candidates[previous] = true
			large.append(index)
		else:
			for previous in large: candidates[previous] = true
			for x in range(low.x, high.x + 1):
				for y in range(low.y, high.y + 1):
					for z in range(low.z, high.z + 1):
						var cell := Vector3i(x, y, z)
						var bucket: Array = grid.get(cell, [])
						for previous in bucket: candidates[previous] = true
						bucket.append(index)
						grid[cell] = bucket
		for previous in candidates:
			if previous >= owned_count: continue
			if not box.intersects(bounds[previous]): continue
			var other := parts[previous]
			var contact := _contact(part, other, tolerance)
			if contact.is_empty() and repair_seams and part.get_parent() == other.get_parent() and not _has_rotating_surface(part) and not _has_rotating_surface(other) and _boxes_touch(part, other, tolerance):
				contact = {"normal": Vector3.UP, "hinge": false}
			if contact.is_empty(): continue
			if index >= owned_count:
				var supports: Array = external_supports.get(parts[previous].get_instance_id(), [])
				supports.append(part.get_instance_id())
				external_supports[parts[previous].get_instance_id()] = supports
			else:
				connections.append([index, previous, contact.normal if contact.hinge else null, contact])
			count += 1
	if not connections.is_empty() or not external_supports.is_empty():
		for old in container.get_children():
			if old.has_method("shutdown"): old.shutdown()
			container.remove_child(old)
			old.queue_free()
		var assembly: Node = load("res://addons/roblox_runtime/roblox_surface_assembly.gd").new()
		assembly.name = "WeldedAssemblies"
		assembly.set_meta("bobux_runtime_generated", true)
		container.add_child(assembly)
		assembly.configure(parts.slice(0, owned_count), connections, external_supports)

	root.set_meta("bobux_surface_joint_count", count)
	return count

static func _surface(part: Node, face: int) -> int:
	var key: String = FACES[face]
	var value: Variant = part.get_meta(key, part.get_meta("roblox_properties", {}).get(key, 0))
	if value is String:
		return {"Glue": 1, "Weld": 2, "Studs": 3, "Inlet": 4, "Universal": 5, "Hinge": 6, "Motor": 7, "SteppingMotor": 8}.get(str(value).get_slice(".", str(value).get_slice_count(".") - 1), 0)
	return int(value)

static func _has_rotating_surface(part: Node) -> bool:
	for face in 6:
		if _surface(part, face) in [6, 7, 8]: return true
	return false

static func _contact(a: MeshInstance3D, b: MeshInstance3D, tolerance: float = EPSILON) -> Dictionary:
	var basis_a := a.global_basis.orthonormalized()
	var basis_b := b.global_basis.orthonormalized()
	var half_a := QUERIES.bounds(a).size * a.global_basis.get_scale().abs() * 0.5
	var half_b := QUERIES.bounds(b).size * b.global_basis.get_scale().abs() * 0.5
	var offset := b.global_transform * QUERIES.bounds(b).get_center() - a.global_transform * QUERIES.bounds(a).get_center()
	for axis_a in 3:
		var normal: Vector3 = basis_a[axis_a]
		var radius_b := absf(normal.dot(basis_b.x)) * half_b.x + absf(normal.dot(basis_b.y)) * half_b.y + absf(normal.dot(basis_b.z)) * half_b.z
		if absf(absf(offset.dot(normal)) - half_a[axis_a] - radius_b) > tolerance: continue
		if offset.dot(normal) < 0: normal = -normal
		for axis_b in 3:
			if absf(normal.dot(basis_b[axis_b])) < 0.999: continue
			var overlaps := true
			for tangent_axis in 3:
				if tangent_axis == axis_a: continue
				var tangent: Vector3 = basis_a[tangent_axis]
				var extent := absf(tangent.dot(basis_b.x)) * half_b.x + absf(tangent.dot(basis_b.y)) * half_b.y + absf(tangent.dot(basis_b.z)) * half_b.z
				if absf(offset.dot(tangent)) >= half_a[tangent_axis] + extent - EPSILON: overlaps = false
			if not overlaps: continue
			var face_a := axis_a + (3 if normal.dot(basis_a[axis_a]) < 0 else 0)
			var face_b := axis_b + (3 if normal.dot(basis_b[axis_b]) > 0 else 0)
			var sa := _surface(a, face_a)
			var sb := _surface(b, face_b)
			if sa in [1, 2, 5, 6, 7, 8] or sb in [1, 2, 5, 6, 7, 8] or (sa == 3 and sb == 4) or (sa == 4 and sb == 3):
				return {"normal": normal, "hinge": sa in [6, 7, 8] or sb in [6, 7, 8], "face_a": face_a, "face_b": face_b, "point": a.global_position + normal * half_a[axis_a]}
	return {}


# Opt-in repair for archived models whose old auto-generated joints were not
# stored in the file. Join only intersecting/adjacent volumes, never the entire
# model by its bounding box. The resulting edges remain individually breakable.
static func _boxes_touch(a: MeshInstance3D, b: MeshInstance3D, tolerance: float) -> bool:
	var ba := a.global_basis.orthonormalized()
	var bb := b.global_basis.orthonormalized()
	var ha := QUERIES.bounds(a).size * a.global_basis.get_scale().abs() * 0.5
	var hb := QUERIES.bounds(b).size * b.global_basis.get_scale().abs() * 0.5
	var offset := b.global_position - a.global_position
	var axes: Array[Vector3] = [ba.x, ba.y, ba.z, bb.x, bb.y, bb.z]
	for aa in [ba.x, ba.y, ba.z]:
		for ab in [bb.x, bb.y, bb.z]: axes.append(aa.cross(ab))
	for raw in axes:
		if raw.length_squared() < 0.000001: continue
		var axis := raw.normalized()
		var ra := absf(axis.dot(ba.x))*ha.x + absf(axis.dot(ba.y))*ha.y + absf(axis.dot(ba.z))*ha.z
		var rb := absf(axis.dot(bb.x))*hb.x + absf(axis.dot(bb.y))*hb.y + absf(axis.dot(bb.z))*hb.z
		if absf(axis.dot(offset)) > ra + rb + tolerance: return false
	return true
