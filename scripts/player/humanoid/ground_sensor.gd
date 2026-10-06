extends RefCounted
class_name GroundSensor

var hit_part: Object
var hit_position := Vector3.ZERO
var hit_normal := Vector3.UP
var search_distance := 0.0
var hit_distance := INF
var _last_frame := -1
var _last_transform := Transform3D.IDENTITY
var _foot := BoxShape3D.new()
var _lower_body := BoxShape3D.new()

func recover_spawn_overlap(body: CharacterBody3D, config: HumanoidConfig) -> bool:
	# Teleports can place the non-colliding R6 legs inside a newly built floor.
	# Only recover upward during spawn, never while jumping beside a tall wall.
	var scale_: float = body.get("world_stud_scale")
	var space := body.get_world_3d().direct_space_state
	var origin := body.global_position
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.95 * scale_, origin - Vector3.UP * 0.05 * scale_, body.collision_mask, [body.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.65: return false
	var rise := float(hit.position.y) - origin.y + config.float_value("GroundController.GroundOffset") * scale_
	if rise <= config.float_value("Motion.SafeMargin") * scale_ or rise > 1.95 * scale_: return false
	var upward := Vector3.UP * rise
	if body.test_move(body.global_transform, upward): return false
	body.global_position += upward
	body.velocity.y = maxf(body.velocity.y, 0.0)
	return true

func sweep_lower_body(body: CharacterBody3D, motion: Vector3, config: HumanoidConfig, grounded: bool) -> Dictionary:
	if Vector2(motion.x, motion.z).length_squared() < 0.00000001 or body.get_world_3d() == null: return {}
	var bounds := AABB()
	var first := true
	for name in ["CollisionLeftLeg", "CollisionRightLeg"]:
		var leg := body.get_node_or_null(name) as CollisionShape3D
		if leg == null or not leg.shape is BoxShape3D: continue
		var box: AABB = leg.transform * AABB(-leg.shape.size * 0.5, leg.shape.size)
		bounds = box if first else bounds.merge(box)
		first = false
	if first: return {}
	var stud_scale: float = body.get("world_stud_scale")
	# Animated R6 legs need not be rigid bodies, but their resting volume must
	# not enter a tall ledge sideways. Leave low grounded steps to try_step().
	var clearance := config.float_value("GroundController.StepHeight") if grounded else config.float_value("Motion.SafeMargin")
	clearance *= stud_scale
	_lower_body.size = Vector3(bounds.size.x, maxf(0.01, bounds.size.y - clearance), bounds.size.z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _lower_body
	query.transform = body.global_transform * Transform3D(Basis.IDENTITY, bounds.get_center() + Vector3.UP * clearance * 0.5)
	query.motion = motion
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	var space := body.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0: return {}
	query.transform.origin += motion * fractions[1]
	query.motion = Vector3.ZERO
	query.margin = config.float_value("Motion.SafeMargin") * stud_scale
	var hit := space.get_rest_info(query)
	if hit.is_empty() or absf(Vector3(hit.normal).dot(Vector3.UP)) > 0.5: return {}
	var normal := Vector3(hit.normal)
	var travelled := motion * fractions[0]
	# Keep the next sweep outside the wall. cast_motion ignores a shape that
	# starts overlapping; stopping at the unsafe contact point loses the wall
	# on the following tick and allows the legs to enter it incrementally.
	var separation := minf(config.float_value("Motion.SafeMargin") * stud_scale, maxf(0.0, -travelled.dot(normal)))
	return {"motion": travelled + normal * separation + (motion * (1.0 - fractions[0])).slide(normal), "normal": normal}

func sense(body: CharacterBody3D, config: HumanoidConfig) -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _last_frame and body.global_transform == _last_transform:
		return is_instance_valid(hit_part)
	_last_frame = frame
	_last_transform = body.global_transform
	hit_part = null
	hit_distance = INF
	var scale_: float = body.get("world_stud_scale")
	search_distance = config.float_value("GroundSensor.SearchDistance")
	var offset := config.float_value("GroundController.GroundOffset")
	if offset >= search_distance or body.get_world_3d() == null: return false
	# Query the complete sole, including a beam between its corners. This is
	# a floor sensor, not an extra capsule or animated limb collider.
	var bounds := AABB()
	var first := true
	for name in ["CollisionLeftLeg", "CollisionRightLeg"]:
		var foot := body.get_node_or_null(name) as CollisionShape3D
		if foot == null or not foot.shape is BoxShape3D: continue
		var size_: Vector3 = foot.shape.size
		var box: AABB = foot.transform * AABB(-size_ * 0.5, size_)
		bounds = box if first else bounds.merge(box)
		first = false
	if first: return false
	var thickness := config.float_value("GroundSensor.ProbeThickness") * scale_
	_foot.size = Vector3(bounds.size.x, thickness, bounds.size.z)
	# Start above a walkable step. A sweep beginning inside a raised floor
	# ignores that floor, allowing non-colliding R6 legs to sink to the torso.
	var lift := config.float_value("GroundController.StepHeight")
	var travel := search_distance + lift
	var center := Vector3(bounds.get_center().x, bounds.position.y + (offset + lift) * scale_ + thickness * 0.5, bounds.get_center().z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _foot
	query.transform = body.global_transform * Transform3D(Basis.IDENTITY, center)
	query.motion = Vector3.DOWN * travel * scale_
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	var space := body.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0: return false
	query.transform.origin += query.motion * fractions[1]
	query.motion = Vector3.ZERO
	query.margin = config.float_value("Motion.SafeMargin") * scale_
	var hit := space.get_rest_info(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < cos(deg_to_rad(config.float_value("MaxSlopeAngle"))): return false
	hit_part = instance_from_id(int(hit.collider_id))
	hit_position = hit.point
	hit_normal = hit.normal
	hit_distance = fractions[0] * travel - lift
	return hit_part != null

func is_grounded(config: HumanoidConfig) -> bool:
	return is_instance_valid(hit_part) and hit_distance <= config.float_value("GroundController.GroundOffset") + config.float_value("GroundController.GroundTolerance")

func sweep_landing(body: CharacterBody3D, motion: Vector3, config: HumanoidConfig) -> Dictionary:
	if motion.y >= 0.0 or body.get_world_3d() == null: return {}
	# R6's animated legs are not rigid obstacles. Their full sole nevertheless
	# needs continuous floor contact: at terminal speed one tick spans four
	# studs, longer than the resting ground sensor, and the torso can otherwise
	# stop two studs below the floor.
	var scale_: float = body.get("world_stud_scale")
	var bounds := AABB()
	var first := true
	for name in ["CollisionLeftLeg", "CollisionRightLeg"]:
		var foot := body.get_node_or_null(name) as CollisionShape3D
		if foot == null or not foot.shape is BoxShape3D: continue
		var box: AABB = foot.transform * AABB(-foot.shape.size * 0.5, foot.shape.size)
		bounds = box if first else bounds.merge(box)
		first = false
	if first: return {}
	var thickness := config.float_value("GroundSensor.ProbeThickness") * scale_
	_foot.size = Vector3(bounds.size.x, thickness, bounds.size.z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _foot
	query.transform = body.global_transform * Transform3D(Basis.IDENTITY, Vector3(bounds.get_center().x, bounds.position.y + thickness * 0.5, bounds.get_center().z))
	query.motion = motion
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	var space := body.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0: return {}
	query.transform.origin += motion * fractions[1]
	query.motion = Vector3.ZERO
	query.margin = config.float_value("Motion.SafeMargin") * scale_
	var hit := space.get_rest_info(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < cos(deg_to_rad(config.float_value("MaxSlopeAngle"))): return {}
	return {"fraction": fractions[0], "normal": hit.normal}
