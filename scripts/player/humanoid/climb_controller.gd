extends RefCounted
class_name ClimbController


static func velocity_for(current: Vector3, truss: Node, normal: Vector3, vertical_input: float, walk_speed: float, delta: float, config: HumanoidConfig) -> Vector3:
	var axis := Vector3.UP
	if is_instance_valid(truss) and truss is Node3D:
		axis = (truss as Node3D).global_basis.y.normalized()
	if axis.length_squared() <= 0.000001:
		axis = Vector3.UP
	# A truss has no designated top: rotating it 180 degrees must not turn
	# forward/up input into descent. Preserve the slope, choose its upward end.
	if axis.dot(Vector3.UP) < 0.0:
		axis = -axis
	var speed_factor := config.float_value("ClimbController.MoveSpeedFactor")
	var approach := -normal.normalized() * config.float_value("ClimbController.SurfaceApproachSpeed")
	var desired := axis * clampf(vertical_input, -1.0, 1.0) * walk_speed * speed_factor + approach
	var acceleration_time := maxf(config.float_value("ClimbController.AccelerationTime"), 0.000001)
	return current.move_toward(desired, walk_speed * delta / acceleration_time)
