extends RefCounted
class_name AirController


static func update_horizontal(current: Vector3, move_direction: Vector3, input_strength: float, walk_speed: float, delta: float, config: HumanoidConfig) -> Vector3:
	var move_max_force := maxf(config.float_value("AirController.MoveMaxForce"), 0.0)
	var desired := move_direction * walk_speed * clampf(input_strength, 0.0, 1.0)
	var planar := Vector3(current.x, 0.0, current.z).move_toward(desired, move_max_force * delta)
	return planar


static func update_vertical(velocity_y: float, delta: float, config: HumanoidConfig) -> float:
	var gravity := config.float_value("Gravity")
	var max_fall_speed := config.float_value("Motion.MaxFallSpeed")
	return maxf(velocity_y - gravity * delta, -max_fall_speed)
