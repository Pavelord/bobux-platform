extends Node3D

# A connected welded model is one rigid assembly. Thousands of individual
# constrained bodies both jitter and overwhelm the solver on legacy maps.
var parts: Dictionary = {}
var edges: Dictionary = {}
var groups: Dictionary = {}
var rebuilding := false
var dirty_groups: Dictionary = {}
var hinges: Array = []
var hinge_nodes: Array[HingeJoint3D] = []
const PART_PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")

func configure(nodes: Array, connections: Array) -> void:
	for part in nodes:
		var id: int = part.get_instance_id()
		parts[id] = part
		edges[id] = {}
	for pair in connections:
		var a: int = nodes[pair[0]].get_instance_id()
		var b: int = nodes[pair[1]].get_instance_id()
		if pair.size() > 2 and pair[2] is Vector3:
			hinges.append([a, b, pair[2]])
			continue
		edges[a][b] = true
		edges[b][a] = true
	for id in parts:
		var part: MeshInstance3D = parts[id]
		# Remove temporary standalone adapters after capturing authored transforms.
		for helper in part.get_children():
			if helper.name == "RobloxPartPhysics" or helper is RigidBody3D:
				part.remove_child(helper)
				helper.queue_free()
			elif helper is CollisionObject3D:
				helper.collision_layer = 0
				helper.collision_mask = 0
		part.set_meta("_bobux_surface_assembly", get_instance_id())
		part.tree_exiting.connect(_part_exiting.bind(id))
	_build_components(parts.keys())
	_refresh_hinges()

func shutdown() -> void:
	set_physics_process(false)
	for id in parts:
		var part: Variant = parts[id]
		if is_instance_valid(part) and part.tree_exiting.is_connected(_part_exiting.bind(id)):
			part.tree_exiting.disconnect(_part_exiting.bind(id))
	parts.clear()
	edges.clear()
	hinges.clear()
	dirty_groups.clear()

func _refresh_hinges() -> void:
	for joint in hinge_nodes:
		if is_instance_valid(joint):
			joint.node_a = NodePath()
			joint.node_b = NodePath()
			joint.queue_free()
	hinge_nodes.clear()
	for pair in hinges:
		if not is_instance_valid(parts.get(pair[0])) or not is_instance_valid(parts.get(pair[1])): continue
		var a := PART_PHYSICS.body_for(parts[pair[0]])
		var b := PART_PHYSICS.body_for(parts[pair[1]])
		if a == null or b == null or a == b: continue
		var joint := HingeJoint3D.new()
		joint.set_meta("bobux_runtime_generated", true)
		add_child(joint)
		var normal: Vector3 = pair[2]
		var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		joint.global_transform = Transform3D(Basis(tangent, normal.cross(tangent), normal), (parts[pair[0]].global_position + parts[pair[1]].global_position) * 0.5)
		joint.node_a = joint.get_path_to(a)
		joint.node_b = joint.get_path_to(b)
		hinge_nodes.append(joint)

func _build_components(ids: Array, velocity := Vector3.ZERO, angular := Vector3.ZERO, old_center := Vector3.ZERO) -> void:
	var unseen := {}
	for id in ids:
		if parts.has(id) and is_instance_valid(parts[id]) and not parts[id].is_queued_for_deletion(): unseen[id] = true
	while not unseen.is_empty():
		var pending: Array = [unseen.keys()[0]]
		var component: Array = []
		while not pending.is_empty():
			var id: int = pending.pop_back()
			if not unseen.has(id): continue
			unseen.erase(id)
			component.append(id)
			for neighbor in edges.get(id, {}):
				if unseen.has(neighbor): pending.append(neighbor)
		_build_body(component, velocity, angular, old_center)

func _build_body(ids: Array, velocity: Vector3, angular: Vector3, old_center: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "SurfaceAssembly"
	body.set_meta("bobux_runtime_generated", true)
	body.set_meta("_bobux_surface_assembly", get_instance_id())
	body.continuous_cd = true
	body.linear_damp = 0.0
	body.angular_damp = 0.05
	body.contact_monitor = true
	body.max_contacts_reported = 8
	add_child(body)
	var center := Vector3.ZERO
	for id in ids: center += parts[id].global_position
	center /= ids.size()
	body.global_position = center
	var shapes := {}
	var relative := {}
	var anchored := false
	var mass := 0.0
	var assembly_bounds := AABB()
	var first_bounds := true
	for id in ids:
		var part: MeshInstance3D = parts[id]
		var transform_: Transform3D = body.global_transform.affine_inverse() * part.global_transform
		relative[id] = transform_
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (part.get_aabb().size * part.global_basis.get_scale().abs()).max(Vector3.ONE * 0.01)
		shape.shape = box
		body.add_child(shape)
		shape.transform = Transform3D(transform_.basis.orthonormalized(), transform_ * part.get_aabb().get_center())
		shape.disabled = not bool(part.get_meta("can_collide", true))
		shapes[shape.get_index()] = id
		anchored = anchored or bool(part.get_meta("anchored", false))
		mass += box.size.x * box.size.y * box.size.z * 0.7
		var bounds: AABB = transform_ * part.get_aabb()
		assembly_bounds = bounds if first_bounds else assembly_bounds.merge(bounds)
		first_bounds = false
		part.set_meta("_bobux_physics_body_instance_id", body.get_instance_id())
		part.set_meta("_bobux_surface_group", body.get_instance_id())
	body.set_meta("_bobux_shape_parts", shapes)
	body.set_meta("bobux_visual_instance_id", ids[0])
	body.mass = maxf(mass, 0.01)
	# Old places contain extremely thin, rotated bricks. A diagonal box inertia
	# avoids unstable principal-axis diagonalization for these compound shapes.
	var squared := assembly_bounds.size * assembly_bounds.size
	body.inertia = (Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * body.mass / 12.0).max(Vector3.ONE * 0.0001)
	var material := PhysicsMaterial.new()
	material.friction = 0.3
	body.physics_material_override = material
	body.collision_layer = 1
	body.collision_mask = 1 | 2 | 4 | 64
	body.freeze = anchored
	var engine := get_tree().root.get_node("LuaScriptEngine")
	body.gravity_scale = 196.2 * engine.BobuxInstance.new(parts[ids[0]])._stud_scale() / maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0.01)
	body.linear_velocity = velocity + angular.cross(center - old_center)
	body.angular_velocity = angular
	for id in ids:
		var part: Node = parts[id]
		if part.has_meta("_bobux_pending_velocity"):
			body.linear_velocity = part.get_meta("_bobux_pending_velocity")
			part.remove_meta("_bobux_pending_velocity")
		if part.has_meta("_bobux_pending_angular"):
			body.angular_velocity = part.get_meta("_bobux_pending_angular")
			part.remove_meta("_bobux_pending_angular")
		if part.has_meta("_bobux_pending_impulse"):
			body.apply_central_impulse(part.get_meta("_bobux_pending_impulse"))
			part.remove_meta("_bobux_pending_impulse")
	preload("res://addons/roblox_runtime/roblox_heavy_body.gd").configure(body, engine.BobuxInstance.wrap(parts[ids[0]])._stud_scale())
	groups[body.get_instance_id()] = {"body": body, "ids": ids, "relative": relative}
	body.body_shape_entered.connect(_on_shape_contact.bind(body.get_instance_id()))

func _physics_process(_delta: float) -> void:
	_flush_rebuilds()
	for group in groups.values():
		var body: RigidBody3D = group.body
		if not is_instance_valid(body) or body.freeze or body.sleeping: continue
		for id in group.ids:
			var part: Variant = parts.get(id)
			if is_instance_valid(part): part.global_transform = body.global_transform * group.relative[id]

func refresh(part: Node, property: String) -> void:
	var key := int(part.get_meta("_bobux_surface_group", 0))
	if not groups.has(key): return
	var group: Dictionary = groups[key]
	var body: RigidBody3D = group.body
	if property == "Anchored":
		body.freeze = false
		for id in group.ids:
			if is_instance_valid(parts.get(id)) and bool(parts[id].get_meta("anchored", false)):
				body.freeze = true
				break
	elif property in ["CFrame", "Position", "Rotation"]:
		body.global_transform = part.global_transform * group.relative[part.get_instance_id()].affine_inverse()
	elif property in ["Size", "CanCollide"]:
		_rebuild_group(key)
	if is_instance_valid(body): body.sleeping = false

func break_connections(part: Node) -> void:
	var id := part.get_instance_id()
	var had_hinges := hinges.size()
	hinges = hinges.filter(func(pair): return pair[0] != id and pair[1] != id)
	if not edges.has(id) or edges[id].is_empty():
		if hinges.size() != had_hinges: _refresh_hinges()
		return
	for neighbor in edges[id]: edges[neighbor].erase(id)
	edges[id].clear()
	_queue_rebuild(int(part.get_meta("_bobux_surface_group", 0)))

func _queue_rebuild(key: int) -> void:
	if not groups.has(key) or dirty_groups.has(key): return
	dirty_groups[key] = true
	_flush_rebuilds.call_deferred()

func _flush_rebuilds() -> void:
	if not is_inside_tree() or rebuilding: return
	var keys := dirty_groups.keys()
	dirty_groups.clear()
	for key in keys: _rebuild_group(key)

func queue_motion(part: Node, value: Vector3, kind: String) -> bool:
	if not dirty_groups.has(int(part.get_meta("_bobux_surface_group", 0))): return false
	var key := "_bobux_pending_" + kind
	if kind == "impulse": value += part.get_meta(key, Vector3.ZERO)
	part.set_meta(key, value)
	return true

func _rebuild_group(key: int, removed_id: int = 0) -> void:
	if rebuilding or not groups.has(key): return
	rebuilding = true
	var group: Dictionary = groups[key]
	var body: RigidBody3D = group.body
	var velocity := body.linear_velocity
	var angular := body.angular_velocity
	var center := body.global_position
	for id in group.ids:
		if id != removed_id and is_instance_valid(parts.get(id)):
			parts[id].global_transform = body.global_transform * group.relative[id]
	groups.erase(key)
	remove_child(body)
	body.queue_free()
	_build_components(group.ids.filter(func(id): return id != removed_id), velocity, angular, center)
	_refresh_hinges()
	rebuilding = false

func _part_exiting(id: int) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not get_parent().is_inside_tree(): return
	if not parts.has(id): return
	var key := int(parts[id].get_meta("_bobux_surface_group", 0))
	for neighbor in edges.get(id, {}):
		if edges.has(neighbor): edges[neighbor].erase(id)
	edges.erase(id)
	parts.erase(id)
	_queue_rebuild(key)

func _on_shape_contact(_rid: RID, target: Node, target_shape: int, own_shape: int, group_id: int) -> void:
	if not groups.has(group_id) or not is_instance_valid(target): return
	var body: RigidBody3D = groups[group_id].body
	var part_id := int(body.get_meta("_bobux_shape_parts", {}).get(own_shape, 0))
	if part_id > 0: _deliver_contact.call_deferred(part_id, target.get_instance_id(), target_shape)

func _deliver_contact(part_id: int, target_id: int, target_shape: int) -> void:
	var part: Variant = instance_from_id(part_id)
	var target: Variant = instance_from_id(target_id)
	if not is_instance_valid(part) or not is_instance_valid(target): return
	var engine := get_tree().root.get_node("LuaScriptEngine")
	var wrapper = engine.BobuxInstance.new(part)
	var hit: Node = wrapper._part_from_raycast_collider(target, target_shape)
	if hit != null and bool(part.get_meta("CanTouch", true)): engine.fire_roblox_instance_event(part, "Touched", [hit])
