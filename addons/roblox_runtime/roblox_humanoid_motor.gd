extends CharacterBody3D

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
	destination = destination_
	has_destination = true
	deadline_msec = Time.get_ticks_msec() + 8000

func move(direction: Vector3) -> void:
	has_destination = false
	move_direction = direction.limit_length(1.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(humanoid) or not is_instance_valid(root_part):
		queue_free()
		return
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
		var offset := destination - global_position
		offset.y = 0
		if offset.length() < stud_scale or Time.get_ticks_msec() >= deadline_msec:
			has_destination = false
			_event("MoveToFinished", [offset.length() < stud_scale])
		else:
			direction = offset.normalized()
	var speed := get_humanoid_walk_speed() * stud_scale
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 98.1 * stud_scale * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
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
	if direction.length_squared() > 0.01 and bool(humanoid.get_meta("AutoRotate", true)):
		model.rotation.y = atan2(direction.x, direction.z)
	var next_state := 15 if get_health() <= 0 else (8 if is_on_floor() else (3 if velocity.y > 0 else 5))
	if state != next_state:
		var old := state
		state = next_state
		_event("StateChanged", [old, state])

func _event(name_: String, args: Array) -> void:
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine != null:
		engine.fire_roblox_instance_event(humanoid, name_, args)

func get_health() -> float:
	return float(humanoid.get_meta("Health", 100.0))
func get_max_health() -> float:
	return float(humanoid.get_meta("MaxHealth", 100.0))
func set_health(value: float) -> void:
	var previous := get_health()
	humanoid.set_meta("Health", clampf(value, 0, get_max_health()))
	if get_health() != previous: _event("HealthChanged", [get_health()])
	if previous > 0 and get_health() <= 0: _event("Died", [])
func take_damage(amount: float) -> void:
	if amount <= 0 or model.get_node_or_null("ForceField") != null:
		return
	set_health(get_health() - amount)
func get_humanoid_walk_speed() -> float:
	return float(humanoid.get_meta("WalkSpeed", 16.0))
func set_humanoid_walk_speed(value: float) -> void:
	humanoid.set_meta("WalkSpeed", maxf(0, value))
func get_humanoid_jump_power() -> float:
	return float(humanoid.get_meta("JumpPower", 50.0))
func set_humanoid_jump_power(value: float) -> void:
	humanoid.set_meta("JumpPower", maxf(0, value))
func request_humanoid_state(value: int) -> void:
	if value == 3 and get_health() > 0 and bool(humanoid.get_meta("bobux_state_enabled_3", true)):
		velocity.y = get_humanoid_jump_power() * stud_scale
		floor_snap_length = 0
func get_runtime_humanoid_state() -> int:
	return state
func set_lua_linear_velocity(value: Vector3) -> void:
	velocity = value
