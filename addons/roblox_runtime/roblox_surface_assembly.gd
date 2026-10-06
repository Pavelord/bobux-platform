extends Node3D

const QUERIES = preload("res://addons/roblox_runtime/roblox_spatial_query.gd")

# A connected welded model is one rigid assembly. Thousands of individual
# constrained bodies both jitter and overwhelm the solver on legacy maps.
var parts: Dictionary = {}
var edges: Dictionary = {}
var external_supports: Dictionary = {}
var groups: Dictionary = {}
var rebuilding := false
var dirty_groups: Dictionary = {}
var hinges: Array = []
var hinge_nodes: Array[HingeJoint3D] = []
var _support_check := 0.0
var _hinges_dirty := false
var _flush_queued := false
const PART_PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")

func configure(nodes: Array, connections: Array, supports: Dictionary = {}) -> void:
	external_supports = supports
	for supported_id in supports:
		for support_id in supports[supported_id]:
			var support: Variant = instance_from_id(support_id)
			if not is_instance_valid(support): continue
			var assemblies: Array = support.get_meta("_bobux_supported_assemblies", [])
			if not assemblies.has(get_instance_id()): assemblies.append(get_instance_id())
			support.set_meta("_bobux_supported_assemblies", assemblies)
	for part in nodes:
		var id: int = part.get_instance_id()
		parts[id] = part
		edges[id] = {}
	for pair in connections:
		var a: int = nodes[pair[0]].get_instance_id()
		var b: int = nodes[pair[1]].get_instance_id()
		if pair.size() > 2 and pair[2] is Vector3:
			var contact: Dictionary = pair[3].duplicate() if pair.size() > 3 else {}
			contact["local_point"] = nodes[pair[0]].to_local(contact.get("point", (nodes[pair[0]].global_position + nodes[pair[1]].global_position) * 0.5))
			contact["local_axis"] = nodes[pair[0]].global_basis.orthonormalized().inverse() * pair[2]
			hinges.append([a, b, pair[2], contact])
			continue
		edges[a][b] = true
		edges[b][a] = true
	for id in parts:
		var part: MeshInstance3D = parts[id]
		# Older published maps may have a sibling body with a RemoteTransform.
		# It must stop driving the visual before the compound body takes over.
		var previous_body := PART_PHYSICS.body_for(part)
		if previous_body != null and not previous_body.is_queued_for_deletion() and previous_body.get_parent() != null and previous_body.get_parent() != part:
			previous_body.collision_layer = 0
			previous_body.collision_mask = 0
			previous_body.freeze = true
			previous_body.get_parent().remove_child(previous_body)
			previous_body.queue_free()
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
	var previous := {}
	for joint in hinge_nodes:
		if is_instance_valid(joint):
			previous[joint.get_meta("body_pair", "")] = joint
	hinge_nodes.clear()
	var connected := {}
	for pair in hinges:
		if not is_instance_valid(parts.get(pair[0])) or not is_instance_valid(parts.get(pair[1])): continue
		var a := PART_PHYSICS.body_for(parts[pair[0]])
		var b := PART_PHYSICS.body_for(parts[pair[1]])
		if a == null or b == null or a == b: continue
		# A wheel often touches several welded axle bricks. Those contacts are
		# one joint between rigid bodies, not dozens of competing constraints.
		var key := "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
		if connected.has(key): continue
		connected[key] = true
		if previous.has(key):
			hinge_nodes.append(previous[key])
			previous.erase(key)
			continue
		var joint := HingeJoint3D.new()
		joint.set_meta("body_pair", key)
		joint.set_meta("bobux_runtime_generated", true)
		add_child(joint)
		var normal: Vector3 = parts[pair[0]].global_basis.orthonormalized() * pair[3].local_axis
		var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		joint.global_transform = Transform3D(Basis(tangent, normal.cross(tangent), normal), parts[pair[0]].to_global(pair[3].local_point))
		joint.node_a = joint.get_path_to(a)
		joint.node_b = joint.get_path_to(b)
		preload("res://addons/roblox_runtime/roblox_legacy_motor.gd").configure(joint, parts[pair[0]], parts[pair[1]], pair[3], groups)
		hinge_nodes.append(joint)
	for joint in previous.values():
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		remove_child(joint)
		joint.queue_free()
	for part in parts.values():
		if is_instance_valid(part) and str(part.get_meta("roblox_class", "")) == "VehicleSeat": part.set_meta("AreHingesDetected", 0)
	for joint in hinge_nodes:
		for motor in joint.get_children():
			if is_instance_valid(motor.seat):
				motor.seat.set_meta("AreHingesDetected", int(motor.seat.get_meta("AreHingesDetected", 0)) + 1)

func _components(ids: Array) -> Array:
	var result: Array = []
	var unseen := {}
	for id in ids:
		if parts.has(id) and is_instance_valid(parts[id]) and not parts[id].is_queued_for_deletion(): unseen[id] = true
	for first in ids:
		if not unseen.has(first): continue
		var pending: Array = [first]
		var component: Array = []
		while not pending.is_empty():
			var id: int = pending.pop_back()
			if not unseen.has(id): continue
			unseen.erase(id)
			component.append(id)
			for neighbor in edges.get(id, {}):
				if unseen.has(neighbor): pending.append(neighbor)
		result.append(component)
	return result

func _build_components(ids: Array, velocity := Vector3.ZERO, angular := Vector3.ZERO, old_center := Vector3.ZERO) -> void:
	for component in _components(ids): _build_body(component, velocity, angular, old_center)

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
	var part_shapes := {}
	var relative := {}
	var mass_parts := {}
	var local_bounds := {}
	var fixed_parts := {}
	var mass := 0.0
	var assembly_bounds := AABB()
	var first_bounds := true
	for id in ids:
		var part: MeshInstance3D = parts[id]
		var transform_: Transform3D = body.global_transform.affine_inverse() * part.global_transform
		relative[id] = transform_
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (QUERIES.bounds(part).size * part.global_basis.get_scale().abs()).max(Vector3.ONE * 0.01)
		shape.shape = QUERIES.collision_shape(part)
		body.add_child(shape)
		shape.transform = Transform3D(transform_.basis.orthonormalized(), transform_ * QUERIES.bounds(part).get_center())
		shape.disabled = not bool(part.get_meta("can_collide", true))
		shapes[shape.get_index()] = id
		part_shapes[id] = shape
		if bool(part.get_meta("anchored", part.get_meta("roblox_properties", {}).get("Anchored", true))) or _has_external_support(id): fixed_parts[id] = true
		mass_parts[id] = box.size.x * box.size.y * box.size.z * 0.7
		mass += mass_parts[id]
		var bounds: AABB = transform_ * QUERIES.bounds(part)
		local_bounds[id] = bounds
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
	body.freeze = not fixed_parts.is_empty()
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
	groups[body.get_instance_id()] = {"body": body, "ids": ids, "relative": relative, "shapes": part_shapes, "fixed": fixed_parts, "masses": mass_parts, "bounds": local_bounds}
	body.body_shape_entered.connect(_on_shape_contact.bind(body.get_instance_id()))

func _physics_process(delta: float) -> void:
	var profile_start := Time.get_ticks_usec()
	_support_check += delta
	if _support_check >= 0.2:
		_support_check = 0.0
		for id in external_supports.keys():
			if not _has_external_support(id):
				external_supports.erase(id)
				if is_instance_valid(parts.get(id)): _queue_rebuild(int(parts[id].get_meta("_bobux_surface_group", 0)))
	_flush_rebuilds()
	for group in groups.values():
		var body: RigidBody3D = group.body
		if not is_instance_valid(body) or body.freeze or body.sleeping: continue
		for id in group.ids:
			var part: Variant = parts.get(id)
			if is_instance_valid(part):
				part.global_transform = body.global_transform * group.relative[id]
				QUERIES.invalidate(part)
	if OS.get_cmdline_user_args().has("--profile-runtime-spans") and Time.get_ticks_usec() - profile_start > 3000:
		print("[assembly-span] physics=",Time.get_ticks_usec()-profile_start," groups=",groups.size())

func refresh(part: Node, property: String) -> void:
	var key := int(part.get_meta("_bobux_surface_group", 0))
	if not groups.has(key): return
	var group: Dictionary = groups[key]
	var body: RigidBody3D = group.body
	if property == "Anchored":
		var id := part.get_instance_id()
		if bool(part.get_meta("anchored", part.get_meta("roblox_properties", {}).get("Anchored", true))) or _has_external_support(id): group.fixed[id] = true
		else: group.fixed.erase(id)
		body.freeze = not group.fixed.is_empty()
	elif property in ["CFrame", "Position", "Rotation"]:
		# Anchored parts have independent authored transforms, even if their
		# touching surfaces share a frozen collision body. Preserve each new
		# relative frame so BulkMoveTo cannot tear a multi-part wave apart.
		if body.freeze:
			group.relative[part.get_instance_id()] = body.global_transform.affine_inverse() * part.global_transform
			group.bounds[part.get_instance_id()] = group.relative[part.get_instance_id()] * QUERIES.bounds(part)
			var shape: CollisionShape3D = group.shapes.get(part.get_instance_id())
			var frame: Transform3D = group.relative[part.get_instance_id()]
			shape.transform = Transform3D(frame.basis.orthonormalized(), frame * QUERIES.bounds(part).get_center())
			var player_shape: Variant = instance_from_id(int(shape.get_meta("bobux_player_shape_id", 0)))
			if is_instance_valid(player_shape): player_shape.transform = shape.transform
		else:
			body.global_transform = part.global_transform * group.relative[part.get_instance_id()].affine_inverse()
	elif property in ["Size", "CanCollide"]:
		group["rebuild_shapes"] = true
		_queue_rebuild(key)
	if property in ["Anchored", "CFrame", "Position", "Rotation", "Size", "CanCollide"] and is_instance_valid(body): body.sleeping = false

func break_connections(part: Node) -> void:
	var id := part.get_instance_id()
	var supported := external_supports.erase(id)
	var had_hinges := hinges.size()
	hinges = hinges.filter(func(pair): return pair[0] != id and pair[1] != id)
	if hinges.size() != had_hinges:
		_hinges_dirty = true
		_schedule_flush()
	if not edges.has(id) or edges[id].is_empty():
		if supported: _queue_rebuild(int(part.get_meta("_bobux_surface_group", 0)))
		return
	for neighbor in edges[id]: edges[neighbor].erase(id)
	edges[id].clear()
	_queue_rebuild(int(part.get_meta("_bobux_surface_group", 0)))

func break_external_support(support: Node) -> void:
	for id in external_supports.keys():
		if external_supports[id].has(support.get_instance_id()):
			external_supports[id].erase(support.get_instance_id())
			if is_instance_valid(parts.get(id)): _queue_rebuild(int(parts[id].get_meta("_bobux_surface_group", 0)))

func _queue_rebuild(key: int) -> void:
	if not groups.has(key) or dirty_groups.has(key): return
	dirty_groups[key] = true
	_schedule_flush()

func _schedule_flush() -> void:
	if _flush_queued: return
	_flush_queued = true
	_flush_rebuilds.call_deferred()

func _flush_rebuilds() -> void:
	var profile_start := Time.get_ticks_usec()
	_flush_queued = false
	if not is_inside_tree() or rebuilding: return
	var keys := dirty_groups.keys()
	dirty_groups.clear()
	for key in keys: _rebuild_group(key)
	if not keys.is_empty() or _hinges_dirty:
		_hinges_dirty = false
		_refresh_hinges()
	if OS.get_cmdline_user_args().has("--profile-runtime-spans") and Time.get_ticks_usec() - profile_start > 3000:
		print("[assembly-span] rebuild=",Time.get_ticks_usec()-profile_start," dirty=",keys.size()," groups=",groups.size())

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
	var components := _components(group.ids.filter(func(id): return id != removed_id))
	if components.is_empty() or bool(group.get("rebuild_shapes", false)):
		groups.erase(key)
		remove_child(body)
		body.queue_free()
		for component in components: _build_body(component, velocity, angular, center)
	else:
		# Preserve the largest remaining component's body and collision resources.
		# Recreating the whole building per brick causes quadratic destruction cost.
		components.sort_custom(func(a: Array, b: Array): return a.size() > b.size())
		var kept: Array = components.pop_front()
		var retained := {}
		for id in kept: retained[id] = true
		for id in group.ids:
			if retained.has(id): continue
			if is_instance_valid(parts.get(id)):
				parts[id].global_transform = body.global_transform * group.relative[id]
			var shape: CollisionShape3D = group.shapes[id]
			var player_shape: Variant = instance_from_id(int(shape.get_meta("bobux_player_shape_id", 0)))
			if is_instance_valid(player_shape):
				player_shape.get_parent().remove_child(player_shape)
				player_shape.queue_free()
			body.remove_child(shape)
			shape.queue_free()
			group.shapes.erase(id)
			group.relative.erase(id)
			group.fixed.erase(id)
			group.masses.erase(id)
			group.bounds.erase(id)
		group.ids = kept
		var mass := 0.0
		var box := AABB()
		group.fixed.clear()
		for id in kept:
			var part: MeshInstance3D = parts[id]
			if bool(part.get_meta("anchored", part.get_meta("roblox_properties", {}).get("Anchored", true))) or _has_external_support(id): group.fixed[id] = true
			mass += group.masses[id]
			var bounds_: AABB = group.bounds[id]
			box = bounds_ if id == kept[0] else box.merge(bounds_)
			for motion in ["velocity", "angular", "impulse"]:
				var meta: String = "_bobux_pending_" + motion
				if not part.has_meta(meta): continue
				if motion == "velocity": body.linear_velocity = part.get_meta(meta)
				elif motion == "angular": body.angular_velocity = part.get_meta(meta)
				else: body.apply_central_impulse(part.get_meta(meta))
				part.remove_meta(meta)
		body.mass = maxf(mass, 0.01)
		var squared := box.size * box.size
		body.inertia = (Vector3(squared.y+squared.z, squared.x+squared.z, squared.x+squared.y)*body.mass/12.0).max(Vector3.ONE*0.0001)
		body.freeze = not group.fixed.is_empty()
		body.set_meta("bobux_visual_instance_id", kept[0])
		_reindex_shapes(body, group.shapes)
		var surface := body.get_node_or_null("PlayerSurface")
		if surface != null:
			surface.set_meta("bobux_visual_instance_id", kept[0])
			var player_shapes := {}
			for id in kept:
				player_shapes[id] = instance_from_id(int(group.shapes[id].get_meta("bobux_player_shape_id", 0)))
			_reindex_shapes(surface, player_shapes)
		for component in components: _build_body(component, velocity, angular, center)
	rebuilding = false

func _reindex_shapes(body: CollisionObject3D, shapes: Dictionary) -> void:
	var owners := {}
	for id in shapes:
		if is_instance_valid(shapes[id]): owners[shapes[id].get_instance_id()] = id
	var indices := {}
	for owner_id in body.get_shape_owners():
		var owner: Object = body.shape_owner_get_owner(owner_id)
		if is_instance_valid(owner) and owners.has(owner.get_instance_id()):
			for i in body.shape_owner_get_shape_count(owner_id):
				indices[body.shape_owner_get_shape_index(owner_id, i)] = owners[owner.get_instance_id()]
	body.set_meta("_bobux_shape_parts", indices)

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
	var part: Node = parts.get(part_id)
	if part != null and bool(part.get_meta("CanTouch", true)) and get_tree().root.get_node("LuaScriptEngine").has_roblox_instance_event_listeners(part, "Touched"):
		_deliver_contact.call_deferred(part_id, target.get_instance_id(), target_shape)

func _deliver_contact(part_id: int, target_id: int, target_shape: int) -> void:
	var part: Variant = instance_from_id(part_id)
	var target: Variant = instance_from_id(target_id)
	if not is_instance_valid(part) or not is_instance_valid(target): return
	var engine := get_tree().root.get_node("LuaScriptEngine")
	var wrapper = engine.BobuxInstance.wrap(part)
	var hit: Node = wrapper._part_from_raycast_collider(target, target_shape)
	if hit != null and bool(part.get_meta("CanTouch", true)): engine.fire_roblox_instance_event(part, "Touched", [hit])


func _has_external_support(id: int) -> bool:
	for support_id in external_supports.get(id, []):
		var support: Variant = instance_from_id(support_id)
		if is_instance_valid(support) and not support.is_queued_for_deletion() and support.is_inside_tree() and bool(support.get_meta("anchored", support.get_meta("roblox_properties", {}).get("Anchored", true))): return true
	return false
