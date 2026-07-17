extends CharacterBody3D

const MAX_FORWARD_SPEED: float = 98.0
const MAX_REVERSE_SPEED: float = 36.0
const ACCELERATION: float = 150.0
const BRAKE_ACCELERATION: float = 210.0
const SIDE_GRIP: float = 44.0
const TURN_RATE: float = 2.35
const BOOST_MULTIPLIER: float = 1.35
const GRAVITY: float = 98.0
const FLOOR_STICK: float = -9.5
const IMPACT_BREAK_SPEED: float = 50.0
const DAMAGE_IMPACT_SPEED: float = 46.0
const DESTROY_IMPACT_SPEED: float = 86.0
const STATE_SEND_HZ: float = 30.0
const REMOTE_LERP_SPEED: float = 18.0
const ENTER_DISTANCE: float = 15.0
const CAR_CAMERA_SENSITIVITY: float = 0.006
const CAR_CAMERA_MIN_PITCH: float = deg_to_rad(-32.0)
const CAR_CAMERA_MAX_PITCH: float = deg_to_rad(18.0)
const DRIVER_SEAT_OFFSET: Vector3 = Vector3(0.0, 1.32, -0.38)
const DRIVER_SEATED_SCALE: Vector3 = Vector3(0.58, 0.58, 0.58)

@export var car_id: String = ""
@export var owner_peer_id: int = 0
@export var room_id: String = ""
@export var body_color: Color = Color(0.9, 0.15, 0.08, 1.0)

var _main: Node = null
var _camera: Camera3D = null
var _camera_pivot: Node3D = null
var _spring_arm: SpringArm3D = null
var _seat_position: Node3D = null
var _enter_prompt: Label3D = null
var _driver_player: CharacterBody3D = null
var _send_accumulator: float = 0.0
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_rotation_y: float = 0.0
var _remote_target_velocity: Vector3 = Vector3.ZERO
var _remote_initialized: bool = false
var _damage_level: int = 0
var _detached_parts: Dictionary = {}
var _is_driving: bool = false
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-10.0)
var _destroyed: bool = false
var _original_driver_scale: Vector3 = Vector3.ONE
var _steer_smoothed: float = 0.0

func _ready() -> void:
	_main = get_tree().current_scene
	_build_runtime_nodes()
	floor_snap_length = 5.0
	floor_max_angle = deg_to_rad(82.0)
	floor_block_on_wall = false
	floor_stop_on_slope = false
	floor_constant_speed = true
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	safe_margin = 0.08
	max_slides = 8
	collision_layer = 4
	collision_mask = 1 | 4
	set_multiplayer_authority(owner_peer_id, true)
	_remote_target_position = global_position
	_remote_target_rotation_y = rotation.y
	_update_enter_prompt(false)

func _exit_tree() -> void:
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	if _is_local_owner() and _is_driving:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_owner() or not _is_driving:
		return
	if event is InputEventMouseButton and _camera != null and _camera.current:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed and _spring_arm != null:
			_spring_arm.spring_length = clampf(_spring_arm.spring_length - 1.0, 7.0, 22.0)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed and _spring_arm != null:
			_spring_arm.spring_length = clampf(_spring_arm.spring_length + 1.0, 7.0, 22.0)
	if event is InputEventMouseMotion and _camera != null and _camera.current:
		var mouse_event := event as InputEventMouseMotion
		_camera_yaw -= mouse_event.relative.x * CAR_CAMERA_SENSITIVITY
		_camera_pitch = clampf(_camera_pitch - mouse_event.relative.y * CAR_CAMERA_SENSITIVITY, CAR_CAMERA_MIN_PITCH, CAR_CAMERA_MAX_PITCH)
		_update_camera_pivot()

func configure(payload: Dictionary) -> void:
	car_id = str(payload.get("car_id", car_id)).strip_edges()
	owner_peer_id = int(payload.get("owner_peer_id", owner_peer_id))
	room_id = str(payload.get("room_id", room_id)).strip_edges()
	if payload.has("color") and payload["color"] is Dictionary:
		var c: Dictionary = payload["color"]
		body_color = Color(float(c.get("r", body_color.r)), float(c.get("g", body_color.g)), float(c.get("b", body_color.b)), 1.0)
	if not car_id.is_empty():
		name = car_id
	set_multiplayer_authority(owner_peer_id, true)

func apply_remote_state(pos: Vector3, rot_y: float, new_velocity: Vector3) -> void:
	if _is_local_owner():
		return
	_remote_target_position = pos
	_remote_target_rotation_y = rot_y
	_remote_target_velocity = new_velocity
	if not _remote_initialized:
		_remote_initialized = true
		global_position = pos
		rotation.y = rot_y
		velocity = new_velocity

func exit_vehicle_local() -> void:
	if not _is_local_owner():
		return
	var exit_pos := global_position + global_transform.basis.x.normalized() * 4.6 + Vector3.UP * 1.2
	release_local_driver(exit_pos)
	if _main != null and _main.has_method("request_exit_chaos_car"):
		_main.call("request_exit_chaos_car", car_id, exit_pos)

func _physics_process(delta: float) -> void:
	if _is_local_owner():
		if _is_driving:
			_drive_local(delta)
		else:
			_idle_local(delta)
	else:
		_drive_remote(delta)
	if _is_driving:
		_place_driver_on_seat()

func _idle_local(delta: float) -> void:
	if delta <= 0.0:
		return
	var can_enter := _can_enter_local_vehicle()
	_update_enter_prompt(can_enter)
	if Input.is_action_just_pressed("interact") and can_enter:
		_enter_local_vehicle()
		return
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, BRAKE_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, BRAKE_ACCELERATION * delta)
		velocity.y = FLOOR_STICK
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -170.0)
	move_and_slide()

func _can_enter_local_vehicle() -> bool:
	var player := _find_local_player()
	if player == null:
		return false
	return player.global_position.distance_to(global_position) <= ENTER_DISTANCE

func _drive_local(delta: float) -> void:
	if delta <= 0.0:
		return
	_update_enter_prompt(false)
	if Input.is_action_just_pressed("interact"):
		exit_vehicle_local()
		return

	var forward_input := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steer_input := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var boosting := Input.is_action_pressed("sprint")
	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	if is_on_floor():
		var floor_normal := get_floor_normal()
		forward = forward.slide(floor_normal).normalized()
		right = right.slide(floor_normal).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var forward_speed := horizontal.dot(forward)
	var side_speed := horizontal.dot(right)
	var speed_limit := MAX_FORWARD_SPEED * (BOOST_MULTIPLIER if boosting else 1.0)
	var target_speed := forward_input * (speed_limit if forward_input >= 0.0 else MAX_REVERSE_SPEED)
	var accel := ACCELERATION if absf(target_speed) > absf(forward_speed) else BRAKE_ACCELERATION
	forward_speed = move_toward(forward_speed, target_speed, accel * delta)
	side_speed = move_toward(side_speed, 0.0, SIDE_GRIP * maxf(1.0, absf(forward_speed) * 0.18) * delta)
	_steer_smoothed = move_toward(_steer_smoothed, steer_input, 3.4 * delta)
	if absf(forward_speed) > 1.8 and absf(_steer_smoothed) > 0.01:
		var speed_factor := clampf(absf(forward_speed) / 48.0, 0.25, 1.0)
		rotate_y(-_steer_smoothed * TURN_RATE * speed_factor * delta * signf(forward_speed))
	var drive_velocity := forward * forward_speed + right * side_speed
	velocity.x = drive_velocity.x
	velocity.z = drive_velocity.z
	if is_on_floor():
		velocity.y = clampf(drive_velocity.y, FLOOR_STICK, 38.0)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -170.0)

	var pre_slide_velocity := velocity
	move_and_slide()
	_check_impacts(pre_slide_velocity)
	_place_driver_on_seat()
	_send_state_if_needed(delta)

func _drive_remote(delta: float) -> void:
	_update_enter_prompt(false)
	if not _remote_initialized:
		return
	global_position = global_position.lerp(_remote_target_position, clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_target_rotation_y, clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	velocity = velocity.lerp(_remote_target_velocity, clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0))

func _send_state_if_needed(delta: float) -> void:
	_send_accumulator += delta
	if _send_accumulator < 1.0 / STATE_SEND_HZ:
		return
	_send_accumulator = 0.0
	if _main != null and _main.has_method("submit_chaos_car_state"):
		_main.call("submit_chaos_car_state", car_id, global_position, rotation.y, velocity)

func _check_impacts(pre_slide_velocity: Vector3) -> void:
	if _destroyed or pre_slide_velocity.length() < 12.0:
		return
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var collider := collision.get_collider() as Node
		if collider == null:
			continue
		var normal := collision.get_normal()
		var normal_impact_speed := maxf(0.0, -pre_slide_velocity.dot(normal))
		if normal_impact_speed < 8.0 and collider.is_in_group("chaos_cars"):
			normal_impact_speed = maxf(normal_impact_speed, pre_slide_velocity.length() * 0.45)
		var impact_speed := normal_impact_speed
		if impact_speed > DAMAGE_IMPACT_SPEED:
			_damage_car_visuals(impact_speed, collision.get_normal())
		if impact_speed >= DESTROY_IMPACT_SPEED:
			_destroy_vehicle(collision.get_normal(), impact_speed)
			return
		var target := _find_destructible_target(collider)
		if target != null and impact_speed >= IMPACT_BREAK_SPEED and _main != null and _main.has_method("request_break_destructible"):
			_main.call("request_break_destructible", car_id, target.name, room_id, collision.get_position(), impact_speed)

func _find_destructible_target(node: Node) -> Node3D:
	var cursor: Node = node
	while cursor != null:
		if cursor is Node3D and (cursor.is_in_group("destructible_blocks") or str(cursor.get_meta("shape_type", "")) == "Destructible"):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null

func _damage_car_visuals(impact_speed: float, normal: Vector3) -> void:
	if _damage_level >= 8:
		return
	var next_level := clampi(int(floor((impact_speed - 28.0) / 12.0)), 1, 8)
	while _damage_level < next_level:
		_damage_level += 1
		match _damage_level:
			1:
				_detach_part("FrontBumper", normal)
			2:
				_detach_part("RearBumper", normal)
			3:
				_detach_part("LeftDoor", normal)
			4:
				_detach_part("RightDoor", normal)
			5:
				_detach_part("Hood", normal)
			6:
				_detach_part("Trunk", normal)
			7:
				_detach_part("CabinRoof", normal)
			8:
				_detach_part("WheelFL", normal)
				_detach_part("WheelFR", normal)
				_detach_part("WheelRL", normal)
				_detach_part("WheelRR", normal)

func _detach_part(part_name: String, normal: Vector3) -> void:
	if _detached_parts.has(part_name):
		return
	var part := get_node_or_null("Visuals/%s" % part_name) as MeshInstance3D
	if part == null:
		return
	_detached_parts[part_name] = true
	var debris := RigidBody3D.new()
	debris.name = "%s_Debris" % part_name
	debris.global_transform = part.global_transform
	var mesh_copy := MeshInstance3D.new()
	mesh_copy.mesh = part.mesh
	if part.get_surface_override_material_count() > 0:
		mesh_copy.set_surface_override_material(0, part.get_surface_override_material(0))
	debris.add_child(mesh_copy)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var mesh_size := Vector3(1.0, 0.35, 0.28)
	if part.mesh is BoxMesh:
		mesh_size = (part.mesh as BoxMesh).size
	elif part.mesh is CylinderMesh:
		var cylinder := part.mesh as CylinderMesh
		mesh_size = Vector3(cylinder.top_radius * 2.0, cylinder.top_radius * 2.0, cylinder.height)
	box.size = mesh_size
	shape.shape = box
	debris.add_child(shape)
	get_parent().add_child(debris)
	var impulse_strength := randf_range(24.0, 42.0)
	debris.apply_impulse((normal + Vector3.UP * randf_range(0.55, 1.1)).normalized() * impulse_strength)
	part.visible = false
	var debris_ref: WeakRef = weakref(debris)
	var timer: SceneTreeTimer = get_tree().create_timer(7.0)
	timer.timeout.connect(func():
		var debris_node := debris_ref.get_ref() as Node
		if debris_node != null and is_instance_valid(debris_node):
			debris_node.queue_free()
	)

func _destroy_vehicle(normal: Vector3, impact_speed: float) -> void:
	if _destroyed:
		return
	_destroyed = true
	_update_enter_prompt(false)
	for part_name in ["FrontBumper", "RearBumper", "LeftDoor", "RightDoor", "Hood", "Trunk", "CabinRoof", "WheelFL", "WheelFR", "WheelRL", "WheelRR", "Cabin", "Body"]:
		_detach_part(part_name, normal)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if _is_local_owner():
		var exit_pos := _get_safe_eject_position(normal, impact_speed)
		release_local_driver(exit_pos)
		if _main != null and _main.has_method("request_exit_chaos_car"):
			_main.call("request_exit_chaos_car", car_id, exit_pos)

func _get_safe_eject_position(normal: Vector3, impact_speed: float) -> Vector3:
	var eject_direction := normal + Vector3.UP * 0.75
	if eject_direction.length_squared() < 0.01:
		eject_direction = Vector3.UP
	var candidate := global_position + eject_direction.normalized() * clampf(impact_speed * 0.08, 4.0, 9.0) + Vector3.UP * 2.2
	var world := get_world_3d()
	if world == null:
		return candidate
	var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 12.0, candidate + Vector3.DOWN * 120.0)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.has("position"):
		candidate = (hit["position"] as Vector3) + Vector3.UP * 2.35
	return candidate

func _enter_local_vehicle() -> void:
	if _is_driving:
		return
	_driver_player = _find_local_player()
	if _driver_player == null:
		return
	if _driver_player.global_position.distance_to(global_position) > ENTER_DISTANCE:
		return
	_is_driving = true
	_original_driver_scale = _driver_player.scale
	if _main != null and _main.has_method("request_enter_chaos_car"):
		_main.call("request_enter_chaos_car", car_id, global_position)
	_driver_player.visible = true
	_driver_player.set_physics_process(false)
	_driver_player.collision_layer = 0
	_driver_player.collision_mask = 0
	_driver_player.scale = DRIVER_SEATED_SCALE
	_place_driver_on_seat()
	var player_camera := _driver_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = true
	if _camera != null:
		_camera.current = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_local_driver(exit_position: Vector3) -> void:
	if _driver_player == null:
		_driver_player = _find_local_player()
	if _driver_player == null:
		return
	_is_driving = false
	_driver_player.global_position = exit_position
	_driver_player.visible = true
	_driver_player.scale = _original_driver_scale
	_driver_player.velocity = Vector3.ZERO
	_driver_player.collision_layer = 2
	_driver_player.collision_mask = 1
	_driver_player.set_physics_process(true)
	if _driver_player.has_method("reset_physics_interpolation"):
		_driver_player.call("reset_physics_interpolation")
	var player_camera := _driver_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = true
	if _camera != null:
		_camera.current = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _place_driver_on_seat() -> void:
	if _driver_player == null or not is_instance_valid(_driver_player):
		_driver_player = _find_local_player()
	if _driver_player == null:
		return
	_driver_player.global_position = _get_seat_global_position()
	_driver_player.rotation = Vector3.ZERO
	if _driver_player.has_node("Visuals"):
		var driver_visuals := _driver_player.get_node("Visuals") as Node3D
		driver_visuals.global_rotation = Vector3(0.0, rotation.y, 0.0)

func _get_seat_global_position() -> Vector3:
	if _seat_position != null and is_instance_valid(_seat_position):
		return _seat_position.global_position
	return global_transform * DRIVER_SEAT_OFFSET

func _find_local_player() -> CharacterBody3D:
	if _main != null and _main.has_method("_get_local_player"):
		var player = _main.call("_get_local_player")
		if player is CharacterBody3D:
			return player as CharacterBody3D
	var players_root := get_node_or_null("/root/Main/World/Players")
	if players_root != null:
		for child in players_root.get_children():
			if child is CharacterBody3D and child.get_multiplayer_authority() == owner_peer_id:
				return child as CharacterBody3D
	return null

func _is_local_owner() -> bool:
	if owner_peer_id <= 0:
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return owner_peer_id == 1
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return owner_peer_id == 1
	return multiplayer.get_unique_id() == owner_peer_id

func _build_runtime_nodes() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.6, 2.65, 12.4)
		shape.shape = box
		shape.position = Vector3(0.0, 1.58, 0.0)
		add_child(shape)

	if get_node_or_null("SeatPosition") == null:
		_seat_position = Node3D.new()
		_seat_position.name = "SeatPosition"
		_seat_position.position = DRIVER_SEAT_OFFSET
		add_child(_seat_position)
	else:
		_seat_position = get_node_or_null("SeatPosition") as Node3D

	if get_node_or_null("Visuals") == null:
		var visuals := Node3D.new()
		visuals.name = "Visuals"
		add_child(visuals)
		_add_box_part(visuals, "Body", Vector3(8.2, 1.55, 11.4), Vector3(0.0, 1.48, 0.0), body_color)
		_add_box_part(visuals, "Cabin", Vector3(5.25, 1.8, 4.35), Vector3(0.0, 2.92, -0.65), body_color.lightened(0.16))
		_add_box_part(visuals, "CabinRoof", Vector3(5.45, 0.34, 4.55), Vector3(0.0, 4.02, -0.65), body_color.darkened(0.08))
		_add_box_part(visuals, "Hood", Vector3(8.0, 0.55, 3.05), Vector3(0.0, 2.36, -4.3), body_color.lightened(0.08))
		_add_box_part(visuals, "Trunk", Vector3(7.9, 0.52, 2.55), Vector3(0.0, 2.2, 4.45), body_color.darkened(0.08))
		_add_box_part(visuals, "FrontBumper", Vector3(8.85, 0.72, 0.62), Vector3(0.0, 1.08, -6.22), Color(0.08, 0.08, 0.08))
		_add_box_part(visuals, "RearBumper", Vector3(8.85, 0.72, 0.62), Vector3(0.0, 1.08, 6.22), Color(0.08, 0.08, 0.08))
		_add_box_part(visuals, "LeftDoor", Vector3(0.48, 1.55, 3.55), Vector3(-4.36, 1.9, -0.45), body_color.darkened(0.12))
		_add_box_part(visuals, "RightDoor", Vector3(0.48, 1.55, 3.55), Vector3(4.36, 1.9, -0.45), body_color.darkened(0.12))
		for wheel_data in [
			["WheelFL", Vector3(-4.55, 0.82, -4.25)],
			["WheelFR", Vector3(4.55, 0.82, -4.25)],
			["WheelRL", Vector3(-4.55, 0.82, 4.25)],
			["WheelRR", Vector3(4.55, 0.82, 4.25)]
		]:
			_add_wheel(visuals, str(wheel_data[0]), wheel_data[1])

	if get_node_or_null("CameraPivot") == null:
		var pivot := Node3D.new()
		pivot.name = "CameraPivot"
		pivot.position = Vector3(0.0, 4.25, 0.65)
		add_child(pivot)
		_camera_pivot = pivot
		var spring := SpringArm3D.new()
		spring.name = "SpringArm3D"
		spring.spring_length = 20.0
		spring.collision_mask = 0
		spring.rotation_degrees.x = rad_to_deg(_camera_pitch)
		pivot.add_child(spring)
		_spring_arm = spring
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = 78.0
		_camera.near = 0.08
		_camera.far = 520.0
		_camera.current = false
		spring.add_child(_camera)
	else:
		_camera_pivot = get_node_or_null("CameraPivot") as Node3D
		_spring_arm = get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
		_camera = get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if _spring_arm != null:
		_spring_arm.collision_mask = 0
	_update_camera_pivot()

	if get_node_or_null("EnterPrompt") == null:
		_enter_prompt = Label3D.new()
		_enter_prompt.name = "EnterPrompt"
		_enter_prompt.text = "E  Drive"
		_enter_prompt.position = Vector3(0.0, 6.8, -1.2)
		_enter_prompt.modulate = Color(1, 1, 1, 1)
		_enter_prompt.outline_modulate = Color(0, 0, 0, 1)
		_enter_prompt.outline_size = 18
		_enter_prompt.font_size = 86
		_enter_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_enter_prompt.visible = false
		add_child(_enter_prompt)
	else:
		_enter_prompt = get_node_or_null("EnterPrompt") as Label3D

func _update_camera_pivot() -> void:
	if _camera_pivot == null:
		return
	_camera_pivot.rotation.y = _camera_yaw
	if _spring_arm != null:
		_spring_arm.rotation.x = _camera_pitch

func _update_enter_prompt(visible_now: bool) -> void:
	if _enter_prompt != null:
		_enter_prompt.visible = visible_now and not _is_driving and not _destroyed

func _add_box_part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.58
	mesh_instance.set_surface_override_material(0, mat)
	parent.add_child(mesh_instance)

func _add_wheel(parent: Node3D, part_name: String, pos: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	wheel.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.15
	mesh.bottom_radius = 1.15
	mesh.height = 0.98
	mesh.radial_segments = 18
	wheel.mesh = mesh
	wheel.position = pos
	wheel.rotation_degrees.z = 90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.035, 0.035)
	mat.roughness = 0.85
	wheel.set_surface_override_material(0, mat)
	parent.add_child(wheel)
