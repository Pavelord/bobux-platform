extends Node

# VehicleSeat drives hinges attached to its rigid component. Constant surface
# motors (old helicopter rotors) also work without an occupant or Lua script.
var joint: HingeJoint3D
var seat: MeshInstance3D
var wheel: MeshInstance3D
var wheel_is_b := true
var constant_speed := 0.0
var axis_in_seat := Vector3.ZERO

static func configure(hinge: HingeJoint3D, a: MeshInstance3D, b: MeshInstance3D, contact: Dictionary, groups: Dictionary) -> void:
	var control: MeshInstance3D
	var other: MeshInstance3D
	var second := true
	for endpoint in [a, b]:
		var group: Dictionary = groups.get(int(endpoint.get_meta("_bobux_surface_group", 0)), {})
		for id in group.get("ids", []):
			var part: Variant = instance_from_id(id)
			if is_instance_valid(part) and str(part.get_meta("roblox_class", "")) == "VehicleSeat":
				control = part
				other = b if endpoint == a else a
				second = endpoint == a
				break
		if control != null: break
	var speed := 0.0
	for pair in [[a, contact.get("face_a", -1)], [b, contact.get("face_b", -1)]]:
		var face: int = pair[1]
		if face < 0: continue
		var part: Node = pair[0]
		var prefix: String = ["Right", "Top", "Front", "Left", "Bottom", "Back"][face]
		var props: Dictionary = part.get_meta("roblox_properties", {})
		if int(props.get(prefix + "Surface", 0)) in [7, 8] and int(props.get(prefix + "SurfaceInput", 0)) == 12:
			speed = float(props.get(prefix + "ParamB", 0.0)) * (1.0 if part == a else -1.0)
	if control == null and is_zero_approx(speed): return
	var motor: Node = load("res://addons/roblox_runtime/roblox_legacy_motor.gd").new()
	motor.joint = hinge
	motor.seat = control
	motor.wheel = other
	motor.wheel_is_b = second
	motor.constant_speed = speed
	if control != null:
		motor.axis_in_seat = control.global_basis.orthonormalized().inverse() * hinge.global_basis.z
		control.set_meta("AreHingesDetected", int(control.get_meta("AreHingesDetected", 0)) + 1)
	motor.set_meta("bobux_runtime_generated", true)
	hinge.add_child(motor)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(joint): return
	var speed := constant_speed
	var impulse := 10.0
	if is_instance_valid(seat) and is_instance_valid(wheel):
		var props: Dictionary = seat.get_meta("roblox_properties", {})
		var occupied := seat.has_meta("Occupant") and is_instance_valid(seat.get_meta("Occupant")) and not bool(seat.get_meta("Disabled", props.get("Disabled", false)))
		var throttle := float(seat.get_meta("ThrottleFloat", seat.get_meta("Throttle", 0))) if occupied else 0.0
		var steer := float(seat.get_meta("SteerFloat", seat.get_meta("Steer", 0))) if occupied else 0.0
		var scale_ := float(seat.get_meta("roblox_stud_scale", 0.5))
		var axis := seat.global_basis.orthonormalized() * axis_in_seat
		var forward := seat.global_basis.z.normalized() # Roblox -Z is mirrored into Godot +Z.
		var side := signf(seat.global_basis.x.dot(wheel.global_position - seat.global_position))
		var dimensions := wheel.global_basis.get_scale().abs()
		var radius := maxf(maxf(dimensions.x, maxf(dimensions.y, dimensions.z)) * 0.5, 0.05)
		var max_speed := float(seat.get_meta("MaxSpeed", props.get("MaxSpeed", 25.0))) * scale_
		var turning := float(seat.get_meta("TurnSpeed", props.get("TurnSpeed", 1.0))) * scale_
		var roll_sign := signf(axis.cross(Vector3.DOWN).dot(forward)) * (1.0 if wheel_is_b else -1.0)
		speed = -(throttle * max_speed + steer * side * turning) / radius * roll_sign
		var body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(wheel)
		impulse = maxf(float(seat.get_meta("Torque", props.get("Torque", 10.0))), 0.0) * maxf(body.mass if body else 1.0, 1.0) * delta
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, speed)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, impulse)
