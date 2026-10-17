extends CharacterBody3D

const StateMachine = preload("res://scripts/player/humanoid/state_machine.gd")
const HumanoidConfiguration = preload("res://scripts/player/humanoid/humanoid_config.tres")

# A physics motor for imported/authored Models with Humanoid + HumanoidRootPart.
# It preserves their Instance hierarchy; scripts retain the original model/parts.
var humanoid: Node
var model: Node3D
var root_part: Node3D
var destination := Vector3.ZERO
var has_destination := false
var move_direction := Vector3.ZERO
var deadline_msec := 0
var stud_scale := 0.5
var state := 8
var _model_offset := Vector3.ZERO
var _health_label: Label3D
var _last_display := ""
var _limbs: Array[Dictionary] = []
var _walk_phase := 0.0
var _state_machine := StateMachine.new()
var _workspace_ref: WeakRef
var _destination_part: WeakRef
var _destination_offset := Vector3.ZERO
var _explicit_state := -1
var _jump_requested := false
var _last_motion_state := -1
var _last_motion_speed := -1.0

static func ensure(h: Node) -> CharacterBody3D:
	if not is_instance_valid(h) or not h.is_inside_tree():
		return null
	var id := int(h.get_meta("bobux_character_body_instance_id", 0))
	var existing: Variant = instance_from_id(id) if id > 0 else null
	if is_instance_valid(existing) and existing is CharacterBody3D:
		return existing
	var parent := h.get_parent()
	if parent is CharacterBody3D:
		return parent
	if not parent is Node3D:
		return null
	var part := parent.get_node_or_null("HumanoidRootPart") as Node3D
	if part == null:
		part = parent.get_node_or_null("Torso") as Node3D
	if part == null:
		return null
	var motor: CharacterBody3D = load("res://addons/roblox_runtime/roblox_humanoid_motor.gd").new()
	motor.name = "RobloxHumanoidMotor"
	motor.humanoid = h
	motor.model = parent
	motor.root_part = part
	motor.set_as_top_level(true)
	motor.set_meta("bobux_runtime_generated", true)
	parent.add_child(motor)
	return motor

func _ready() -> void:
	_state_machine.configure(HumanoidConfiguration)
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null:
		var workspace: Node = engine._resolve_workspace_node(get_tree().root, humanoid)
		if workspace != null: _workspace_ref = weakref(workspace)
	var cursor: Node = model
	while cursor != null:
		if cursor.has_meta("roblox_stud_scale"):
			stud_scale = float(cursor.get_meta("roblox_stud_scale"))
			break
		cursor = cursor.get_parent()
	var body_scale := model.global_basis.get_scale()
	global_position = root_part.global_position
	_model_offset = model.global_position - global_position
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.25 * stud_scale
	safe_margin = 0.02 * stud_scale
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.8 * maxf(body_scale.x, body_scale.z)
	capsule.height = 5 * body_scale.y
	var shape := CollisionShape3D.new()
	shape.name = "HumanoidCollision"
	shape.shape = capsule
	add_child(shape)
	humanoid.set_meta("bobux_character_body_instance_id", get_instance_id())
	root_part.set_meta("bobux_character_body_instance_id", get_instance_id())
	root_part.set_meta("bobux_character_part_proxy", true)
	_health_label = Label3D.new()
	_health_label.name = "HumanoidHealthDisplay"
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 42
	_health_label.outline_size = 9
	_health_label.pixel_size = 0.013 * stud_scale
	_health_label.position.y = 3.5 * body_scale.y
	_health_label.set_meta("bobux_runtime_generated", true)
	add_child(_health_label)
	# Authored part helpers would otherwise collide with their own motor.
	for child in model.find_children("*", "CollisionObject3D", true, false):
		if child != self:
			child.collision_layer = 0
			child.collision_mask = 0
	if model.has_meta("attribute_PrefabId"):
		for name_ in ["RightArm", "LeftArm", "RightLeg", "LeftLeg"]:
			var limb := model.get_node_or_null(name_) as Node3D
			if limb != null: _limbs.append({"node": limb, "rest": limb.transform, "sign": -1 if name_ in ["RightArm", "LeftLeg"] else 1})

func move_to(destination_: Vector3) -> void:
	if not destination_.is_finite(): return
	destination = destination_
	has_destination = true
	deadline_msec = Time.get_ticks_msec() + 8000
	_destination_part = null
	move_direction = Vector3.ZERO

func move_to_part(destination_: Vector3, part: Node3D) -> void:
	move_to(destination_)
	if is_instance_valid(part) and part.is_inside_tree():
		_destination_part = weakref(part)
		_destination_offset = part.to_local(destination_)

func move(direction: Vector3) -> void:
	set_humanoid_move(direction)

func set_humanoid_move(direction: Vector3) -> void:
	if not direction.is_finite(): return
	has_destination = false
	_destination_part = null
	# Walking uses the horizontal projection. Analog input magnitude survives.
	move_direction = Vector3(direction.x, 0.0, direction.z).limit_length(1.0)

func get_humanoid_move_direction() -> Vector3:
	return move_direction.normalized() if move_direction.length_squared() > 0.000001 else Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not is_instance_valid(humanoid) or not is_instance_valid(root_part):
		queue_free()
		return
	_state_machine.tick(delta)
	var display := "%s\n%d / %d HP" % [str(humanoid.get_meta("DisplayName", model.name)), roundi(get_health()), roundi(get_max_health())]
	if display != _last_display:
		_last_display = display
		_health_label.text = display
		_health_label.modulate = Color(0.45, 1.0, 0.5) if get_health() > get_max_health() * 0.3 else Color(1.0, 0.35, 0.3)
	var direction := move_direction
	if get_health() <= 0:
		direction = Vector3.ZERO
		has_destination = false
	elif has_destination:
		var moving_part := _destination_part.get_ref() as Node3D if _destination_part != null else null
		if is_instance_valid(moving_part) and moving_part.is_inside_tree():
			destination = moving_part.to_global(_destination_offset)
		var offset := destination - global_position
		offset.y = 0
		if offset.length() < stud_scale or Time.get_ticks_msec() >= deadline_msec:
			has_destination = false
			_destination_part = null
			move_direction = Vector3.ZERO
			direction = Vector3.ZERO
			_event("MoveToFinished", [offset.length() < stud_scale])
		else:
			direction = offset.normalized()
			move_direction = direction
	if bool(humanoid.get_meta("Jump", false)):
		humanoid.set_meta("Jump", false)
		request_humanoid_state(3)
	if bool(humanoid.get_meta("PlatformStand", false)) and _explicit_state != 14:
		request_humanoid_state(14)
	elif not bool(humanoid.get_meta("PlatformStand", false)) and _explicit_state == 14:
		request_humanoid_state(8)
	if bool(humanoid.get_meta("Sit", false)) and _explicit_state != 13:
		request_humanoid_state(13)
	elif not bool(humanoid.get_meta("Sit", false)) and _explicit_state == 13:
		request_humanoid_state(8)
	var passive := _explicit_state in [0, 1, 2, 6, 13, 14, 16] or get_health() <= 0.0
	var speed := get_humanoid_walk_speed() * stud_scale
	if _explicit_state == 4: speed *= 0.875 # Documented Humanoid.Swimming contract.
	if _explicit_state == 12: speed *= 0.7 # Documented Humanoid.Climbing contract.
	if not passive:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	elif _explicit_state != 16:
		velocity.x = 0.0
		velocity.z = 0.0
	var was_on_floor := is_on_floor()
	if not is_on_floor() and _explicit_state != 4:
		velocity.y -= get_workspace_gravity() * stud_scale * delta
	elif is_on_floor() and not _jump_requested:
		velocity.y = minf(velocity.y, 0.0)
	move_and_slide()
	_walk_phase += Vector2(velocity.x, velocity.z).length() * delta * 0.7
	for limb in _limbs:
		if not is_instance_valid(limb.node): continue
		var rest: Transform3D = limb.rest
		var angle := sin(_walk_phase) * 0.55 * float(limb.sign) if direction.length_squared() > 0.01 and get_health() > 0 else 0.0
		var rotation_ := Basis(Vector3.RIGHT, angle)
		var pivot := Vector3(0, 0.5, 0) if "Arm" in str(limb.node.name) else Vector3(0, 1, 0)
		limb.node.transform = Transform3D(rotation_ * rest.basis, rest.origin + pivot - rotation_ * pivot)
	model.global_position = global_position + _model_offset
	if not passive and direction.length_squared() > 0.01 and bool(humanoid.get_meta("AutoRotate", true)):
		model.rotation.y = atan2(direction.x, direction.z)
	var next_state := 15 if get_health() <= 0 else (_explicit_state if _explicit_state >= 0 else (8 if is_on_floor() else 5))
	var landed := not was_on_floor and is_on_floor() and state in [3, 5]
	_publish_transition(_state_machine.transition(humanoid, next_state, landed))
	_jump_requested = false
	# Jumping is a short entry state; this one physics-step retention is an
	# engineering approximation, not a measured Roblox transition threshold.
	if _explicit_state == 3: _explicit_state = -1
	_publish_motion_events()

func get_workspace_gravity() -> float:
	var workspace := _workspace_ref.get_ref() as Node if _workspace_ref != null else null
	if workspace == null: return 196.2
	var props: Dictionary = workspace.get_meta("roblox_properties", {})
	var value: Variant = workspace.get_meta("Gravity", props.get("Gravity", 196.2))
	return maxf(float(value), 0.0) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else 196.2

func _publish_transition(pair: Array[int]) -> void:
	if pair.is_empty(): return
	state = pair[1]
	humanoid.set_meta("HumanoidState", state)
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null: engine.notify_humanoid_state_changed(humanoid, pair[0], pair[1])

func _publish_motion_events() -> void:
	var event_names := {8: "Running", 10: "Running", 12: "Climbing", 4: "Swimming"}
	var speed := (velocity.length() if state in [4, 12] else Vector2(velocity.x, velocity.z).length()) / maxf(stud_scale, 0.0001)
	if _last_motion_state != state and event_names.has(_last_motion_state):
		_event(event_names[_last_motion_state], [0.0])
	if event_names.has(state) and (_last_motion_state != state or not is_equal_approx(_last_motion_speed, speed)):
		_event(event_names[state], [speed])
	_last_motion_state = state
	_last_motion_speed = speed

func _event(name_: String, args: Array) -> void:
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null:
		engine.fire_roblox_instance_event(humanoid, name_, args)

func get_health() -> float:
	return float(humanoid.get_meta("Health", 100.0))
func get_max_health() -> float:
	return float(humanoid.get_meta("MaxHealth", 100.0))
func set_health(value: float) -> void:
	if is_nan(value) or value == -INF: return
	var previous := get_health()
	# The documented Dead state locks Health at zero; revival needs a new rig.
	humanoid.set_meta("Health", 0.0 if state == 15 else clampf(value, 0, get_max_health()))
	if get_health() != previous: _event("HealthChanged", [get_health()])
	if previous > 0 and get_health() <= 0:
		_publish_transition(_state_machine.force_transition(humanoid, 15))
		if StateMachine.is_enabled(humanoid, 15): _event("Died", [])
func take_damage(amount: float) -> void:
	if not is_finite(amount) or amount == 0.0:
		return
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null and engine.humanoid_is_forcefield_protected(humanoid): return
	set_health(get_health() - amount)
func get_humanoid_walk_speed() -> float:
	return float(humanoid.get_meta("WalkSpeed", 16.0))
func set_humanoid_walk_speed(value: float) -> void:
	if not is_finite(value): return
	humanoid.set_meta("WalkSpeed", maxf(0, value))
func get_humanoid_jump_power() -> float:
	return float(humanoid.get_meta("JumpPower", 50.0))
func set_humanoid_jump_power(value: float) -> void:
	if not is_finite(value): return
	humanoid.set_meta("JumpPower", maxf(0, value))
func request_humanoid_state(value: int) -> void:
	if not StateMachine.is_enabled(humanoid, value) or (get_health() <= 0 and value != 15): return
	if value == 15:
		set_health(0.0)
		return
	if value == 3:
		# Ballistic approximation awaiting Studio JumpHeight calibration.
		var height := maxf(float(humanoid.get_meta("JumpHeight", 7.2)), 0.0)
		velocity.y = get_humanoid_jump_power() * HumanoidConfiguration.float_value("Humanoid.JumpPowerVelocityScale") * stud_scale if bool(humanoid.get_meta("UseJumpPower", true)) else sqrt(2.0 * get_workspace_gravity() * height) * stud_scale
		floor_snap_length = 0
		_jump_requested = true
	_explicit_state = -1 if value in [5, 7, 8, 10] else value
	humanoid.set_meta("PlatformStand", value == 14)
	humanoid.set_meta("Sit", value == 13)
	_publish_transition(_state_machine.force_transition(humanoid, value))
func get_runtime_humanoid_state() -> int:
	return state
func set_lua_linear_velocity(value: Vector3) -> void:
	if value.is_finite(): velocity = value

func set_lua_position(value: Vector3) -> void:
	if not value.is_finite(): return
	has_destination = false
	_destination_part = null
	move_direction = Vector3.ZERO
	global_position = value
	model.global_position = global_position + _model_offset
