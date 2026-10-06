extends RefCounted
class_name GroundController


static func update_horizontal(current: Vector3, move_direction: Vector3, input_strength: float, walk_speed: float, delta: float, config: HumanoidConfig) -> Vector3:
	var acceleration_time := maxf(config.float_value("GroundController.AccelerationTime"), 0.000001)
	var deceleration_time := maxf(config.float_value("GroundController.DecelerationTime"), 0.000001)
	var friction := maxf(config.float_value("GroundController.Friction"), 0.0)
	var friction_weight := clampf(config.float_value("GroundController.FrictionWeight"), 0.0, 1.0)
	var surface_factor := lerpf(1.0, friction, friction_weight)
	var current_planar := Vector3(current.x, 0.0, current.z)
	var desired := move_direction * walk_speed * clampf(input_strength, 0.0, 1.0)
	var duration := acceleration_time if desired.length_squared() > 0.0 else deceleration_time
	var rate := walk_speed * surface_factor / duration
	return current_planar.move_toward(desired, rate * delta)


static func update_vertical(velocity_y: float, sensed_distance: float, has_ground_hit: bool, delta: float, config: HumanoidConfig) -> float:
	if not has_ground_hit:
		return velocity_y - config.float_value("Gravity") * delta
	# Support force balances gravity; implicit damping stays stable at the
	# configured fixed step. All arguments and coefficients are in studs.
	var target := config.float_value("GroundController.GroundOffset")
	var stiffness := config.float_value("GroundController.SpringStiffness")
	var damping := config.float_value("GroundController.SpringDamping")
	return (velocity_y + stiffness * (target - sensed_distance) * delta) / (1.0 + damping * delta)



static func try_step(body: CharacterBody3D, direction: Vector3, _delta: float, was_grounded: bool, _collisions: Array, config: HumanoidConfig) -> bool:
	if not was_grounded or direction.length_squared() == 0.0 or body.get_world_3d() == null:
		return false
	var scale_: float = body.get("world_stud_scale")
	# The floor sensor covers the actual sole, including narrow ledges. Use
	# its signed clearance, not a downward torso cast (two studs too high).
	var sensor: RefCounted = body.get("_ground_sensor")
	sensor.sense(body, config)
	var rise: float = config.float_value("GroundController.GroundOffset") - float(sensor.hit_distance)
	if not is_finite(rise) or rise <= config.float_value("Motion.SafeMargin") or rise > config.float_value("GroundController.StepHeight"):
		return false
	var up_motion := Vector3.UP * rise * scale_
	if body.test_move(body.global_transform, up_motion): return false
	body.move_and_collide(up_motion)
	body.velocity.y = 0.0
	return true
