extends VehicleBody3D

var model: Node3D
var seat: Node3D
var _model_scale := Vector3.ONE
var _wheels: Array[VehicleWheel3D] = []
var _driver: CollisionObject3D

static func ensure(seat_: Node3D) -> VehicleBody3D:
	if not is_instance_valid(seat_) or not seat_.get_parent() is Node3D: return null
	var id := int(seat_.get_meta("bobux_vehicle_motor_id", 0))
	var existing: Variant = instance_from_id(id) if id > 0 else null
	if is_instance_valid(existing): return existing
	var motor: VehicleBody3D = load("res://addons/roblox_runtime/roblox_vehicle_motor.gd").new()
	motor.model = seat_.get_parent()
	motor.seat = seat_
	motor.name = "VehiclePhysics"
	motor.set_as_top_level(true)
	motor.set_meta("bobux_runtime_generated", true)
	motor.model.add_child(motor)
	return motor

func _ready() -> void:
	_model_scale = model.global_basis.get_scale()
	global_transform = Transform3D(model.global_basis.orthonormalized(), model.global_position)
	mass = 400
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.5, 0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 1.1, 8) * _model_scale
	collision.shape = box
	collision.position.y = 1.4 * _model_scale.y
	add_child(collision)
	for side in [-1, 1]:
		for axle in [-1, 1]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(side * 2.2, 1.3, axle * 2.65) * _model_scale
			wheel.wheel_radius = 0.8 * _model_scale.y
			wheel.wheel_rest_length = 0.45 * _model_scale.y
			wheel.suspension_travel = 0.5 * _model_scale.y
			wheel.suspension_stiffness = 35
			wheel.suspension_max_force = 8000
			wheel.damping_compression = 0.9
			wheel.damping_relaxation = 0.9
			wheel.wheel_friction_slip = 2.8
			wheel.wheel_roll_influence = 0.05
			wheel.use_as_traction = true
			wheel.use_as_steering = axle == 1
			add_child(wheel)
			_wheels.append(wheel)
	seat.set_meta("bobux_vehicle_motor_id", get_instance_id())
	for body in model.find_children("*", "CollisionObject3D", true, false):
		if body != self:
			body.collision_layer = 0
			body.collision_mask = 0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(seat): queue_free(); return
	var occupant: Variant = seat.get_meta("Occupant") if seat.has_meta("Occupant") else null
	var character: Node = occupant.get_parent() if is_instance_valid(occupant) else null
	if is_instance_valid(_driver) and _driver != character:
		remove_collision_exception_with(_driver)
		_driver = null
	var driving := is_instance_valid(character) and character.has_method("_is_local_authority_safe") and bool(character._is_local_authority_safe())
	var throttle := Input.get_axis("move_back", "move_forward") if driving else 0.0
	var turn := Input.get_axis("move_right", "move_left") if driving else 0.0
	# Properties remain available to Lua controllers, including autonomous cars.
	if not driving:
		throttle = float(seat.get_meta("ThrottleFloat", 0.0)) if occupant != null else 0.0
		turn = float(seat.get_meta("SteerFloat", 0.0)) if occupant != null else 0.0
	else:
		seat.set_meta("ThrottleFloat", throttle)
		seat.set_meta("SteerFloat", turn)
	var speed := linear_velocity.dot(global_basis.z)
	var limit := float(seat.get_meta("MaxSpeed", 65.0))
	engine_force = throttle * 1400.0 if absf(speed) < limit or signf(speed) != signf(throttle) else 0.0
	brake = 35.0 if not driving or is_zero_approx(throttle) else 0.0
	steering = move_toward(steering, turn * 0.4, delta * 2)
	model.global_transform = Transform3D(global_basis.scaled(_model_scale), global_position)
	if driving and character is CollisionObject3D:
		add_collision_exception_with(character)
		_driver = character
