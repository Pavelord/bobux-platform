extends Node

# Keeps Roblox Instance identity on the authored mesh while Godot owns the body.
var part: MeshInstance3D
var body: RigidBody3D
var shape: CollisionShape3D
var last_position := Vector3.ZERO
var touch_ids := {}

static func body_for(node: Node, create: bool = false) -> RigidBody3D:
	if not is_instance_valid(node):
		return null
	if node is RigidBody3D:
		return node
	var id := int(node.get_meta("_bobux_physics_body_instance_id", 0))
	var candidate: Variant = instance_from_id(id) if id > 0 else null
	if is_instance_valid(candidate) and candidate is RigidBody3D:
		return candidate
	if not create or not node is MeshInstance3D or not node.is_inside_tree():
		return null
	var adapter: Node = load("res://addons/roblox_runtime/roblox_part_physics.gd").new()
	adapter.name = "RobloxPartPhysics"
	adapter.part = node
	adapter.set_meta("bobux_runtime_generated", true)
	node.add_child(adapter)
	return adapter.body

func _ready() -> void:
	body = RigidBody3D.new()
	body.name = "RobloxAssembly"
	body.set_as_top_level(true)
	body.set_meta("bobux_visual_instance_id", part.get_instance_id())
	body.set_meta("bobux_runtime_generated", true)
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	part.add_child(body)
	shape = CollisionShape3D.new()
	body.add_child(shape)
	part.set_meta("_bobux_physics_body_instance_id", body.get_instance_id())
	# Existing selection/static helpers must not remain a second solid body.
	for child in part.get_children():
		if child != body and child is CollisionObject3D:
			child.collision_layer = 0
			child.collision_mask = 0
	sync_from_part()
	body.linear_velocity = part.get_meta("velocity", Vector3.ZERO)
	var rotation_velocity: Vector3 = part.get_meta("RotVelocity", Vector3.ZERO)
	body.angular_velocity = Vector3(-rotation_velocity.x, -rotation_velocity.y, rotation_velocity.z)
	last_position = body.global_position
	body.body_entered.connect(_on_body_entered)

func sync_from_part() -> void:
	if not is_instance_valid(body):
		return
	body.global_transform = Transform3D(part.global_basis.orthonormalized(), part.global_position)
	var box := BoxShape3D.new()
	box.size = (part.get_aabb().size * part.global_basis.get_scale().abs()).max(Vector3.ONE * 0.01)
	shape.shape = box
	if str(part.get_meta("shape_type", "")) in ["Sphere", "Ball"]:
		var sphere := SphereShape3D.new()
		sphere.radius = box.size.x * 0.5
		shape.shape = sphere
	shape.position = part.get_aabb().get_center() * part.global_basis.get_scale()
	refresh_properties()

func refresh_properties() -> void:
	body.freeze = bool(part.get_meta("anchored", false))
	var collide := bool(part.get_meta("can_collide", true))
	body.collision_layer = 1 if collide else (16 if bool(part.get_meta("CanQuery", true)) else 0)
	body.collision_mask = (1 | 2 | 4 | 64) if collide else 0
	body.sleeping = false
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null:
		var wrapper = engine.BobuxInstance.new(part)
		var stud_scale: float = wrapper._stud_scale()
		var gravity := 196.2
		var cursor: Node = part
		while cursor != null:
			if str(cursor.get_meta("roblox_class", "")) == "Workspace":
				gravity = float(cursor.get_meta("Gravity", cursor.get_meta("roblox_properties", {}).get("Gravity", 196.2)))
				break
			cursor = cursor.get_parent()
		body.gravity_scale = gravity * stud_scale / maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0.01)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(part) or not is_instance_valid(body):
		return
	if not body.freeze:
		var old_scale := part.global_basis.get_scale()
		part.global_transform = Transform3D(body.global_basis.scaled(old_scale), body.global_position)
		# CanCollide=false does not disable Roblox Touched. Sweep the travelled
		# segment so fast projectiles cannot tunnel through the island.
		if not bool(part.get_meta("can_collide", true)) and bool(part.get_meta("CanTouch", true)) and last_position.distance_squared_to(body.global_position) > 0.00001:
			var query := PhysicsRayQueryParameters3D.create(last_position, body.global_position, 1 | 2 | 4 | 16 | 64, [body.get_rid()])
			query.hit_from_inside = true
			var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty(): _deliver_touch.call_deferred(hit.collider.get_instance_id(), int(hit.get("shape", -1)))
	last_position = body.global_position

func _on_body_entered(hit: Node) -> void:
	if not is_instance_valid(hit) or touch_ids.has(hit.get_instance_id()): return
	touch_ids[hit.get_instance_id()] = true
	_deliver_touch.call_deferred(hit.get_instance_id())

func _deliver_touch(id: int, shape_index: int = -1) -> void:
	touch_ids.erase(id)
	var hit: Variant = instance_from_id(id)
	if not is_instance_valid(hit): return
	if is_instance_valid(part) and bool(part.get_meta("CanTouch", true)):
		var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null:
			var instance = engine.BobuxInstance.new(part)
			var target: Node = instance._part_from_raycast_collider(hit, shape_index)
			if target != null:
				engine.fire_roblox_instance_event(part, "Touched", [target])
