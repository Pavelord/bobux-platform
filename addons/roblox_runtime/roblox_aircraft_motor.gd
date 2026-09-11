extends RigidBody3D

# An arcade flight adapter for the editable Bobux aircraft prefab (+Z forward).
var model: Node3D
var seat: Node3D
var _model_scale := Vector3.ONE
var _driver: CollisionObject3D

static func ensure(seat_: Node3D) -> RigidBody3D:
	if not is_instance_valid(seat_) or not seat_.get_parent() is Node3D: return null
	var id := int(seat_.get_meta("bobux_aircraft_motor_id", 0))
	var existing: Variant = instance_from_id(id) if id > 0 else null
	if is_instance_valid(existing): return existing
	var motor: RigidBody3D = load("res://addons/roblox_runtime/roblox_aircraft_motor.gd").new()
	motor.model = seat_.get_parent()
	motor.seat = seat_
	motor.name = "AircraftPhysics"
	motor.set_as_top_level(true)
	motor.set_meta("bobux_runtime_generated", true)
	motor.model.add_child(motor)
	return motor

func _ready() -> void:
	_model_scale = model.global_basis.get_scale()
	global_transform = Transform3D(model.global_basis.orthonormalized(), model.global_position)
	mass = 150
	linear_damp = 0.08
	angular_damp = 3
	collision_layer = 4
	collision_mask = 7
	for dimensions in [Vector3(2.5, 2, 12), Vector3(20, 0.3, 4)]:
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = dimensions * _model_scale
		collision.shape = box
		collision.position.y = 2 * _model_scale.y
		add_child(collision)
	seat.set_meta("bobux_aircraft_motor_id", get_instance_id())
	for body in model.find_children("*", "CollisionObject3D", true, false):
		if body != self: body.collision_layer = 0; body.collision_mask = 0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(seat): queue_free(); return
	var occupant: Variant = seat.get_meta("Occupant") if seat.has_meta("Occupant") else null
	var character: Node = occupant.get_parent() if is_instance_valid(occupant) else null
	if is_instance_valid(_driver) and _driver != character:
		remove_collision_exception_with(_driver)
		_driver = null
	var driving := is_instance_valid(character) and character.has_method("_is_local_authority_safe") and bool(character._is_local_authority_safe())
	var throttle := Input.get_axis("move_back", "move_forward") if driving else 0.0
	var yaw := Input.get_axis("move_right", "move_left") if driving else 0.0
	var pitch := (float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))) if driving else 0.0
	seat.set_meta("ThrottleFloat", throttle)
	seat.set_meta("SteerFloat", yaw)
	var speed := maxf(0, linear_velocity.dot(global_basis.z))
	var limit := maxf(10, float(seat.get_meta("MaxSpeed", 90)))
	if driving and speed < limit: apply_central_force(global_basis.z * throttle * mass * 14)
	# Lift is velocity dependent: a stopped plane cannot hover; bank tilts lift.
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	apply_central_force(global_basis.y * mass * gravity * clampf(speed * speed / 625.0, 0, 1.65))
	apply_central_force(-global_basis.x * linear_velocity.dot(global_basis.x) * mass * 1.5)
	if driving:
		var target := global_basis * Vector3(pitch * 0.65, yaw * 0.55, -yaw * 0.3)
		# Release steering to level the wings, while preserving chosen pitch.
		if is_zero_approx(yaw): target.z -= global_basis.x.y * 1.2
		angular_velocity = angular_velocity.lerp(target, minf(delta * 3, 1))
	model.global_transform = Transform3D(global_basis.scaled(_model_scale), global_position)
	if driving and character is CollisionObject3D:
		add_collision_exception_with(character)
		_driver = character
