extends Node

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
		if node is MeshInstance3D and node.mesh != null and node.has_meta("roblox_class"):
			parts.append(node)
		for child in node.get_children():
			if not bool(child.get_meta("bobux_runtime_generated", false)): pending.append(child)
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
		var box: AABB = (part.global_transform * part.get_aabb()).grow(EPSILON)
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
			if not box.intersects(bounds[previous]): continue
			var other := parts[previous]
			var contact := _contact(part, other)
			if contact.is_empty(): continue
			connections.append([index, previous, contact.normal if contact.hinge else null])
			count += 1
	if not connections.is_empty():
		for old in container.get_children():
			if old.has_method("shutdown"): old.shutdown()
			container.remove_child(old)
			old.queue_free()
		var assembly: Node = load("res://addons/roblox_runtime/roblox_surface_assembly.gd").new()
		assembly.name = "WeldedAssemblies"
		assembly.set_meta("bobux_runtime_generated", true)
		container.add_child(assembly)
		assembly.configure(parts, connections)

	root.set_meta("bobux_surface_joint_count", count)
	return count

static func _surface(part: Node, face: int) -> int:
	var key: String = FACES[face]
	var value: Variant = part.get_meta(key, part.get_meta("roblox_properties", {}).get(key, 0))
	if value is String:
		return {"Glue": 1, "Weld": 2, "Studs": 3, "Inlet": 4, "Universal": 5, "Hinge": 6, "Motor": 7, "SteppingMotor": 8}.get(str(value).get_slice(".", str(value).get_slice_count(".") - 1), 0)
	return int(value)

static func _contact(a: MeshInstance3D, b: MeshInstance3D) -> Dictionary:
	var basis_a := a.global_basis.orthonormalized()
	var basis_b := b.global_basis.orthonormalized()
	var half_a := a.get_aabb().size * a.global_basis.get_scale().abs() * 0.5
	var half_b := b.get_aabb().size * b.global_basis.get_scale().abs() * 0.5
	var offset := b.global_transform * b.get_aabb().get_center() - a.global_transform * a.get_aabb().get_center()
	for axis_a in 3:
		var normal: Vector3 = basis_a[axis_a]
		var radius_b := absf(normal.dot(basis_b.x)) * half_b.x + absf(normal.dot(basis_b.y)) * half_b.y + absf(normal.dot(basis_b.z)) * half_b.z
		if absf(absf(offset.dot(normal)) - half_a[axis_a] - radius_b) > EPSILON: continue
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
				return {"normal": normal, "hinge": sa in [6, 7, 8] or sb in [6, 7, 8]}
	return {}
