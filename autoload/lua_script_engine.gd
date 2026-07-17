extends Node

# LuaScriptEngine.gd - Autoload for in-game Lua scripting

const RobloxDataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")

var _lua: Variant = null
var is_active: bool = false
var _last_property_setter_calls: int = 0
var _last_property_setter_target_type: String = ""
var _last_property_setter_target_class: String = ""
var _last_property_setter_has_set_property: bool = false
var _script_runtimes: Dictionary = {}
var _retained_lua_states: Dictionary = {}
var _module_cache: Dictionary = {}
var _pending_script_starts: Array[Dictionary] = []
var _stopped_lua_state_quarantine: Array = []
var _next_script_runtime_id: int = 1
var _scripts_paused: bool = false
var _run_service_heartbeat: Variant = null
var _run_service_stepped: Variant = null
var _run_service_render_stepped: Variant = null
var _scheduler_cursor: int = 0
var _runtime_started_total: int = 0
var _runtime_completed_total: int = 0
var _runtime_failed_total: int = 0
var _runtime_last_errors: Array[String] = []
var _runtime_resume_started_usec: Dictionary = {}
var _runtime_budget_exceeded: Dictionary = {}
var _service_nodes_cache: Dictionary = {}

const SCRIPT_MEMORY_LIMIT_BYTES := 32 * 1024 * 1024
const MAX_CONCURRENT_SCRIPTS := 2048
const MAX_SCRIPT_SOURCE_BYTES := 2 * 1024 * 1024
const SCRIPT_RESUME_BUDGET_PER_FRAME := 48
const SCRIPT_RESUME_TIME_BUDGET_USEC := 4000
# Creating a Lua state and binding the Roblox compatibility library is one
# indivisible operation. On large imported places two starts in one frame can
# exceed 120 ms even though the time budget is checked between starts.
const SCRIPT_COMPILE_BUDGET_PER_FRAME := 2
const SCRIPT_COMPILE_TIME_BUDGET_USEC := 4000
const SCRIPT_INSTRUCTION_HOOK_INTERVAL := 10000
const SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC := 12000
const LUA_HOOK_MASK_COUNT := 8

class BobuxEvent extends RefCounted:
	var connections: Array = []
	func Connect(callback_or_self: Variant, callback: Variant = null) -> Variant:
		if callback == null and callback_or_self != self:
			callback = callback_or_self
		if callback != null:
			connections.append(callback)
		return self
	func Once(callback_or_self: Variant, callback: Variant = null) -> Variant:
		if callback == null and callback_or_self != self:
			callback = callback_or_self
		if callback != null:
			connections.append(callback)
		return self
	func Disconnect(_self_arg: Variant = null) -> void:
		connections.clear()
	func Wait(_self_arg: Variant = null) -> Variant:
		return null
	func Fire(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		var args := []
		if arg1 != null: args.append(arg1)
		if arg2 != null: args.append(arg2)
		if arg3 != null: args.append(arg3)
		for connection in connections.duplicate():
			if connection is Callable:
				var callable := connection as Callable
				# LuaAPI's callable mode follows Godot's Callable contract. callv
				# expands this array into Lua parameters; call(args) would pass the
				# whole Array as arg1 and make Roblox values such as hit.Parent nil.
				var callback_result: Variant = callable.callv(args)
				if callback_result != null and callback_result is Object and (callback_result as Object).has_method("has_error") and bool((callback_result as Object).call("has_error")):
					push_warning("[LuaScriptEngine] Event callback failed: %s" % str((callback_result as Object).call("get_error")))
			elif connection is Object and (connection as Object).has_method("call"):
				(connection as Object).call("call", args)


class BobuxCFrame extends RefCounted:
	var transform: Transform3D = Transform3D.IDENTITY
	var Position: Vector3:
		get: return transform.origin
	var p: Vector3:
		get: return transform.origin
	var X: float:
		get: return transform.origin.x
	var Y: float:
		get: return transform.origin.y
	var Z: float:
		get: return transform.origin.z
	var LookVector: Vector3:
		get: return -transform.basis.z.normalized()
	var lookVector: Vector3:
		get: return LookVector
	var RightVector: Vector3:
		get: return transform.basis.x.normalized()
	var rightVector: Vector3:
		get: return RightVector
	var UpVector: Vector3:
		get: return transform.basis.y.normalized()
	var upVector: Vector3:
		get: return UpVector

	func _init(value: Transform3D = Transform3D.IDENTITY) -> void:
		transform = value

	func __mul(_lua_api: Variant, other: Variant) -> Variant:
		if other is BobuxCFrame:
			return BobuxCFrame.new(transform * (other as BobuxCFrame).transform)
		if other is Vector3:
			return transform * (other as Vector3)
		return null

	func __add(_lua_api: Variant, other: Variant) -> Variant:
		if other is Vector3:
			var moved := transform
			moved.origin += other as Vector3
			return BobuxCFrame.new(moved)
		return null

	func __sub(_lua_api: Variant, other: Variant) -> Variant:
		if other is Vector3:
			var moved := transform
			moved.origin -= other as Vector3
			return BobuxCFrame.new(moved)
		return null

	func Inverse(_self_arg: Variant = null) -> BobuxCFrame:
		return BobuxCFrame.new(transform.affine_inverse())

	func inverse(_self_arg: Variant = null) -> BobuxCFrame:
		return Inverse()

	func ToWorldSpace(self_or_other: Variant, maybe_other: Variant = null) -> Variant:
		var other: Variant = maybe_other if self_or_other == self else self_or_other
		return __mul(null, other)

	func ToObjectSpace(self_or_other: Variant, maybe_other: Variant = null) -> Variant:
		var other: Variant = maybe_other if self_or_other == self else self_or_other
		return Inverse().__mul(null, other)

	func PointToWorldSpace(self_or_point: Variant, maybe_point: Variant = null) -> Variant:
		var point: Variant = maybe_point if self_or_point == self else self_or_point
		return transform * point if point is Vector3 else null

	func PointToObjectSpace(self_or_point: Variant, maybe_point: Variant = null) -> Variant:
		var point: Variant = maybe_point if self_or_point == self else self_or_point
		return transform.affine_inverse() * point if point is Vector3 else null

	func VectorToWorldSpace(self_or_vector: Variant, maybe_vector: Variant = null) -> Variant:
		var vector: Variant = maybe_vector if self_or_vector == self else self_or_vector
		return transform.basis * vector if vector is Vector3 else null

	func VectorToObjectSpace(self_or_vector: Variant, maybe_vector: Variant = null) -> Variant:
		var vector: Variant = maybe_vector if self_or_vector == self else self_or_vector
		return transform.basis.inverse() * vector if vector is Vector3 else null

	func Lerp(self_or_goal: Variant, goal_or_alpha: Variant = null, maybe_alpha: Variant = null) -> BobuxCFrame:
		var goal: Variant = goal_or_alpha if self_or_goal == self else self_or_goal
		var alpha: float = float(maybe_alpha if self_or_goal == self else goal_or_alpha)
		if not (goal is BobuxCFrame):
			return BobuxCFrame.new(transform)
		var goal_transform := (goal as BobuxCFrame).transform
		var weight := clampf(alpha, 0.0, 1.0)
		return BobuxCFrame.new(Transform3D(
			transform.basis.slerp(goal_transform.basis, weight),
			transform.origin.lerp(goal_transform.origin, weight)
		))

	func GetComponents(_self_arg: Variant = null) -> Array:
		var b := transform.basis
		return [
			transform.origin.x, transform.origin.y, transform.origin.z,
			b.x.x, b.y.x, b.z.x,
			b.x.y, b.y.y, b.z.y,
			b.x.z, b.y.z, b.z.z,
		]

	func components(_self_arg: Variant = null) -> Array:
		return GetComponents()

	func __tostring(_lua_api: Variant = null) -> String:
		return "%.6f, %.6f, %.6f" % [transform.origin.x, transform.origin.y, transform.origin.z]


class BobuxAnimationTrack extends RefCounted:
	var IsPlaying: bool = false
	var Looped: bool = false
	var Speed: float = 1.0
	var WeightCurrent: float = 1.0
	var KeyframeReached: BobuxEvent = BobuxEvent.new()
	var Stopped: BobuxEvent = BobuxEvent.new()

	func Play(_self_arg: Variant = null, _fade_time: Variant = 0.1, weight: Variant = 1.0, speed: Variant = 1.0) -> void:
		IsPlaying = true
		WeightCurrent = float(weight)
		Speed = float(speed)

	func Stop(_self_arg: Variant = null, _fade_time: Variant = 0.1) -> void:
		if IsPlaying:
			IsPlaying = false
			Stopped.Fire()

	func AdjustSpeed(self_or_speed: Variant = 1.0, maybe_speed: Variant = null) -> void:
		Speed = float(maybe_speed if self_or_speed == self else self_or_speed)

	func AdjustWeight(self_or_weight: Variant = 1.0, maybe_weight: Variant = null, _fade_time: Variant = 0.1) -> void:
		WeightCurrent = float(maybe_weight if self_or_weight == self else self_or_weight)


class BobuxRay extends RefCounted:
	var Origin: Vector3 = Vector3.ZERO
	var Direction: Vector3 = Vector3.ZERO

	func _init(origin: Variant = Vector3.ZERO, direction: Variant = Vector3.ZERO) -> void:
		Origin = origin as Vector3 if origin is Vector3 else Vector3.ZERO
		Direction = direction as Vector3 if direction is Vector3 else Vector3.ZERO


class BobuxMouse extends RefCounted:
	var Hit: BobuxCFrame = BobuxCFrame.new()
	var Target: Variant = null
	var X: float = 0.0
	var Y: float = 0.0
	var Button1Down: BobuxEvent = BobuxEvent.new()
	var Button1Up: BobuxEvent = BobuxEvent.new()
	var KeyDown: BobuxEvent = BobuxEvent.new()
	var KeyUp: BobuxEvent = BobuxEvent.new()


class BobuxInstance extends RefCounted:
	const DEFAULT_ROBLOX_STUD_SCALE: float = 0.5
	const STUDIO_WORLD_COLLISION_MASK: int = 1 << 2
	const JOINT_CLASSES: Array[String] = [
		"Weld", "ManualWeld", "WeldConstraint", "Motor6D", "Snap", "Motor",
		"HingeConstraint", "BallSocketConstraint", "SpringConstraint",
		"PrismaticConstraint", "CylindricalConstraint", "RodConstraint",
		"RopeConstraint", "NoCollisionConstraint"
	]
	var node: Node
	var Touched: BobuxEvent
	var Changed: BobuxEvent
	var ChildAdded: BobuxEvent
	var ChildRemoved: BobuxEvent
	var AncestryChanged: BobuxEvent
	var Destroying: BobuxEvent
	var OnServerEvent: BobuxEvent
	var OnClientEvent: BobuxEvent
	var Event: BobuxEvent
	var Activated: BobuxEvent
	var Equipped: BobuxEvent
	var Unequipped: BobuxEvent
	var MouseButton1Click: BobuxEvent
	var PlayerAdded: BobuxEvent
	var PlayerRemoving: BobuxEvent
	var Name: Variant:
		get:
			return _get(&"Name")
		set(value):
			_set(&"Name", value)
	var ClassName: Variant:
		get:
			return _get(&"ClassName")
	var Parent: Variant:
		get:
			return _get(&"Parent")
		set(value):
			_set(&"Parent", value)
	var Value: Variant:
		get:
			return _get(&"Value")
		set(value):
			_set(&"Value", value)
	var Position: Variant:
		get:
			return _get(&"Position")
		set(value):
			_set(&"Position", value)
	var Rotation: Variant:
		get:
			return _get(&"Rotation")
		set(value):
			_set(&"Rotation", value)
	var CFrame: Variant:
		get:
			return _get(&"CFrame")
		set(value):
			_set(&"CFrame", value)
	var Velocity: Variant:
		get:
			return _get(&"Velocity")
		set(value):
			_set(&"Velocity", value)
	var AssemblyLinearVelocity: Variant:
		get:
			return _get(&"AssemblyLinearVelocity")
		set(value):
			_set(&"AssemblyLinearVelocity", value)
	var Size: Variant:
		get:
			return _get(&"Size")
		set(value):
			_set(&"Size", value)
	var Anchored: Variant:
		get:
			return _get(&"Anchored")
		set(value):
			_set(&"Anchored", value)
	var CanCollide: Variant:
		get:
			return _get(&"CanCollide")
		set(value):
			_set(&"CanCollide", value)
	var Transparency: Variant:
		get:
			return _get(&"Transparency")
		set(value):
			_set(&"Transparency", value)
	var BrickColor: Variant:
		get:
			return _get(&"BrickColor")
		set(value):
			_set(&"BrickColor", value)
	var LocalPlayer: Variant:
		get:
			return _get(&"LocalPlayer")
	var Backpack: Variant:
		get:
			return _get(&"Backpack")
	var PlayerGui: Variant:
		get:
			return _get(&"PlayerGui")
	var Character: Variant:
		get:
			return _get(&"Character")
	var TimeOfDay: Variant:
		get:
			return _get(&"TimeOfDay")
		set(value):
			_set(&"TimeOfDay", value)
	var ClockTime: Variant:
		get:
			return _get(&"ClockTime")
		set(value):
			_set(&"ClockTime", value)

	func _init(n: Node) -> void:
		node = n
		Touched = _shared_event("Touched")
		Changed = _shared_event("Changed")
		ChildAdded = _shared_event("ChildAdded")
		ChildRemoved = _shared_event("ChildRemoved")
		AncestryChanged = _shared_event("AncestryChanged")
		Destroying = _shared_event("Destroying")
		OnServerEvent = _shared_event("OnServerEvent")
		OnClientEvent = _shared_event("OnClientEvent")
		Event = _shared_event("Event")
		Activated = _shared_event("Activated")
		Equipped = _shared_event("Equipped")
		Unequipped = _shared_event("Unequipped")
		MouseButton1Click = _shared_event("MouseButton1Click")
		PlayerAdded = ChildAdded
		PlayerRemoving = ChildRemoved
		_ensure_node_signal_bridge()

	func _shared_event(event_name: String) -> BobuxEvent:
		if not is_instance_valid(node):
			return BobuxEvent.new()
		var registry: Dictionary = {}
		if node.get_meta("_bobux_event_registry", {}) is Dictionary:
			registry = node.get_meta("_bobux_event_registry", {})
		if registry.has(event_name) and registry[event_name] is BobuxEvent:
			return registry[event_name] as BobuxEvent
		var event := BobuxEvent.new()
		registry[event_name] = event
		node.set_meta("_bobux_event_registry", registry)
		return event

	func _ensure_node_signal_bridge() -> void:
		if not is_instance_valid(node) or bool(node.get_meta("_bobux_signal_bridge", false)):
			return
		node.set_meta("_bobux_signal_bridge", true)
		if node.has_signal("body_entered"):
			node.connect("body_entered", _on_body_entered)
		if node.has_signal("child_entered_tree"):
			node.connect("child_entered_tree", func(child: Node): ChildAdded.Fire(BobuxInstance.new(child)))
		if node.has_signal("child_exiting_tree"):
			node.connect("child_exiting_tree", func(child: Node): ChildRemoved.Fire(BobuxInstance.new(child)))
		if node is BaseButton:
			(node as BaseButton).pressed.connect(func():
				Activated.Fire()
				MouseButton1Click.Fire()
			)

	func _on_body_entered(body: Node) -> void:
		var hit_part = body
		if body.name == "CollisionBody" or body.name == "SelectionBody":
			hit_part = body.get_parent()
		Touched.Fire(BobuxInstance.new(hit_part))

	func _character_body() -> CharacterBody3D:
		if not is_instance_valid(node):
			return null
		if node is CharacterBody3D:
			return node as CharacterBody3D
		var body_id := int(node.get_meta("bobux_character_body_instance_id", 0))
		if body_id > 0:
			var body_variant := instance_from_id(body_id)
			if body_variant is CharacterBody3D and is_instance_valid(body_variant):
				return body_variant as CharacterBody3D
		var cursor := node.get_parent()
		while cursor != null:
			if cursor is CharacterBody3D:
				return cursor as CharacterBody3D
			cursor = cursor.get_parent()
		return null

	func _bound_character() -> Node:
		if not is_instance_valid(node):
			return null
		var character_id := int(node.get_meta("bobux_character_instance_id", 0))
		if character_id <= 0:
			return node.get_node_or_null("Character")
		var character_variant := instance_from_id(character_id)
		return character_variant as Node if character_variant is Node and is_instance_valid(character_variant) else null

	func _node_from_instance_variant(value: Variant) -> Node:
		if value is BobuxInstance:
			var wrapped_node := (value as BobuxInstance).node
			return wrapped_node if is_instance_valid(wrapped_node) else null
		if value is Node:
			return value as Node if is_instance_valid(value) else null
		if value is Object and (value as Object).has_method("GetNode"):
			var raw_node: Variant = (value as Object).call("GetNode")
			return raw_node as Node if raw_node is Node and is_instance_valid(raw_node) else null
		return null

	func _stud_scale() -> float:
		var cursor := node
		while cursor != null:
			if cursor.has_meta("roblox_stud_scale"):
				return maxf(float(cursor.get_meta("roblox_stud_scale")), 0.0001)
			cursor = cursor.get_parent()
		return DEFAULT_ROBLOX_STUD_SCALE

	func _coordinate_mirror_basis() -> Basis:
		return Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0))

	func _roblox_point_to_godot(value: Vector3) -> Vector3:
		var scale := _stud_scale()
		return Vector3(value.x * scale, value.y * scale, -value.z * scale)

	func _godot_point_to_roblox(value: Vector3) -> Vector3:
		var inverse_scale := 1.0 / _stud_scale()
		return Vector3(value.x * inverse_scale, value.y * inverse_scale, -value.z * inverse_scale)

	func _roblox_direction_to_godot(value: Vector3) -> Vector3:
		return Vector3(value.x, value.y, -value.z)

	func _godot_direction_to_roblox(value: Vector3) -> Vector3:
		return Vector3(value.x, value.y, -value.z)

	func _roblox_velocity_to_godot(value: Vector3) -> Vector3:
		return _roblox_point_to_godot(value)

	func _godot_velocity_to_roblox(value: Vector3) -> Vector3:
		return _godot_point_to_roblox(value)

	func _roblox_transform_to_godot(value: Transform3D) -> Transform3D:
		var mirror := _coordinate_mirror_basis()
		return Transform3D(
			mirror * value.basis.orthonormalized() * mirror,
			_roblox_point_to_godot(value.origin)
		)

	func _godot_transform_to_roblox(value: Transform3D) -> Transform3D:
		var mirror := _coordinate_mirror_basis()
		return Transform3D(
			mirror * value.basis.orthonormalized() * mirror,
			_godot_point_to_roblox(value.origin)
		)

	func _mutate_mesh_materials(mutator: Callable) -> void:
		if not (node is MeshInstance3D) or not mutator.is_valid():
			return
		var mesh_node := node as MeshInstance3D
		var surface_count := mesh_node.get_surface_override_material_count()
		if mesh_node.mesh != null:
			surface_count = maxi(surface_count, mesh_node.mesh.get_surface_count())
		for surface_index in range(maxi(surface_count, 1)):
			var source := mesh_node.get_active_material(surface_index) as StandardMaterial3D
			if source == null:
				continue
			var local_material := source.duplicate(true) as StandardMaterial3D
			if local_material == null:
				continue
			mutator.call(local_material)
			mesh_node.set_surface_override_material(surface_index, local_material)

	func _ui_value_to_vector2(value: Variant, parent_control: Control = null) -> Vector2:
		if value is Vector2:
			return value as Vector2
		if value is Vector3:
			return Vector2((value as Vector3).x, (value as Vector3).y)
		if not (value is Dictionary):
			return Vector2.ZERO
		var data := value as Dictionary
		var x_data: Variant = data.get("x", data.get("X", {}))
		var y_data: Variant = data.get("y", data.get("Y", {}))
		var parent_size := parent_control.size if parent_control != null else Vector2.ZERO
		var x_scale := float((x_data as Dictionary).get("scale", (x_data as Dictionary).get("Scale", 0.0))) if x_data is Dictionary else 0.0
		var x_offset := float((x_data as Dictionary).get("offset", (x_data as Dictionary).get("Offset", 0.0))) if x_data is Dictionary else 0.0
		var y_scale := float((y_data as Dictionary).get("scale", (y_data as Dictionary).get("Scale", 0.0))) if y_data is Dictionary else 0.0
		var y_offset := float((y_data as Dictionary).get("offset", (y_data as Dictionary).get("Offset", 0.0))) if y_data is Dictionary else 0.0
		return Vector2(parent_size.x * x_scale + x_offset, parent_size.y * y_scale + y_offset)

	func _get(property: StringName) -> Variant:
		if not is_instance_valid(node):
			return null
		var prop_str := str(property)
		if prop_str in [
			"Button1Down", "Button1Up", "KeyDown", "KeyUp", "MouseButton1Down",
			"MouseButton1Up", "MouseEnter", "MouseLeave", "MouseClick", "Died",
			"Selected", "Deselected", "Deactivated", "InputBegan", "InputChanged",
			"InputEnded", "DeviceRotationChanged", "CharacterAdded", "Move", "Seated",
			"JumpRequest", "DescendantAdded", "DescendantRemoving", "TouchMoved",
			"TouchStarted", "TouchEnded", "Hit", "Running"
		]:
			return _shared_event(prop_str)
		match prop_str:
			"Name":
				return node.get_meta("Name", node.get_meta("block_name", node.name))
			"ClassName":
				return node.get_meta("roblox_class", node.get_meta("shape_type", node.get_class()))
			"Parent":
				var p := node.get_parent()
				return BobuxInstance.new(p) if p else null
			"Value":
				if node.has_meta("Value"):
					return node.get_meta("Value")
				return node.get_meta("value") if node.has_meta("value") else null
			"Position":
				if node is Node3D:
					var godot_position := (node as Node3D).global_position if bool(node.get_meta("bobux_character_part_proxy", false)) else (node as Node3D).position
					return _godot_point_to_roblox(godot_position)
				if node is Control:
					return (node as Control).position
			"Rotation":
				if node is Node3D:
					var roblox_basis := _godot_transform_to_roblox(Transform3D((node as Node3D).basis, Vector3.ZERO)).basis
					return roblox_basis.get_euler(EULER_ORDER_XYZ) * (180.0 / PI)
			"CFrame":
				if node is Node3D:
					var frame: Transform3D = (node as Node3D).global_transform if bool(node.get_meta("bobux_character_part_proxy", false)) else (node as Node3D).transform
					return BobuxCFrame.new(_godot_transform_to_roblox(frame))
			"Velocity", "AssemblyLinearVelocity":
				if node is CharacterBody3D:
					return _godot_velocity_to_roblox((node as CharacterBody3D).velocity)
				if node is RigidBody3D:
					return _godot_velocity_to_roblox((node as RigidBody3D).linear_velocity)
				var stored_velocity: Variant = node.get_meta("velocity", Vector3.ZERO)
				return _godot_velocity_to_roblox(stored_velocity as Vector3) if stored_velocity is Vector3 else Vector3.ZERO
			"Size":
				if node is Node3D:
					return (node as Node3D).scale.abs() / _stud_scale()
				if node is Control:
					return (node as Control).size
			"Text":
				if node is Button:
					return (node as Button).text
				if node is Label:
					return (node as Label).text
				if node is LineEdit:
					return (node as LineEdit).text
			"Visible":
				return (node as Control).visible if node is Control else true
			"Enabled":
				if node is BaseButton:
					return not (node as BaseButton).disabled
				return (node as Control).visible if node is Control else true
			"Anchored":
				return node.get_meta("anchored", true)
			"CanCollide":
				return node.get_meta("can_collide", true)
			"Transparency":
				return node.get_meta("transparency", 0.0)
			"BrickColor":
				if node is MeshInstance3D:
					var mat := node.get_active_material(0) as StandardMaterial3D
					if mat:
						return mat.albedo_color
				return Color.WHITE
			"Color":
				if node is MeshInstance3D:
					var mat := node.get_active_material(0) as StandardMaterial3D
					if mat:
						return mat.albedo_color
				return Color.WHITE
			"LocalPlayer":
				var local_player := node.get_node_or_null("LocalPlayer")
				return BobuxInstance.new(local_player) if local_player else null
			"Backpack", "PlayerGui":
				var named_child := node.get_node_or_null(prop_str)
				return BobuxInstance.new(named_child) if named_child else null
			"Character":
				var character := _bound_character()
				return BobuxInstance.new(character) if character else null
			"Health":
				var health_body := _character_body()
				if health_body != null and health_body.has_method("get_health"):
					return health_body.call("get_health")
				return node.get_meta("Health", 100.0)
			"MaxHealth":
				var max_health_body := _character_body()
				if max_health_body != null and max_health_body.has_method("get_max_health"):
					return max_health_body.call("get_max_health")
				return node.get_meta("MaxHealth", 100.0)
			"WalkSpeed":
				var walk_body := _character_body()
				if walk_body != null and walk_body.has_method("get_humanoid_walk_speed"):
					return walk_body.call("get_humanoid_walk_speed")
				return walk_body.get("move_speed") if walk_body != null else node.get_meta("WalkSpeed", 16.0)
			"JumpPower":
				var jump_body := _character_body()
				if jump_body != null and jump_body.has_method("get_humanoid_jump_power"):
					return jump_body.call("get_humanoid_jump_power")
				return jump_body.get("jump_velocity_setting") if jump_body != null else node.get_meta("JumpPower", 50.0)
			"PlatformStand", "Sit", "AutoRotate":
				return node.get_meta(prop_str, false if prop_str != "AutoRotate" else true)
			"TimeOfDay":
				return node.get_meta("TimeOfDay", "14:00:00")
			"ClockTime":
				return node.get_meta("ClockTime", 14.0)
			_:
				var direct_child := node.get_node_or_null(prop_str)
				if direct_child != null:
					return BobuxInstance.new(direct_child)
				if node.has_meta(prop_str):
					return node.get_meta(prop_str)
				var properties: Dictionary = node.get_meta("roblox_properties", {}) if node.get_meta("roblox_properties", {}) is Dictionary else {}
				for key_variant in properties.keys():
					if str(key_variant).nocasecmp_to(prop_str) == 0:
						return properties[key_variant]
				for property_info_variant in node.get_property_list():
					if not (property_info_variant is Dictionary):
						continue
					var native_name := str((property_info_variant as Dictionary).get("name", ""))
					if native_name.nocasecmp_to(prop_str) == 0:
						return node.get(native_name)
		return null

	func _set(property: StringName, value: Variant) -> bool:
		if not is_instance_valid(node):
			return false
		var prop_str := str(property)
		match prop_str:
			"Name":
				node.set_meta("block_name", str(value))
				node.name = str(value)
				Changed.Fire("Name")
				return true
			"Parent":
				var parent_node: Node = null
				if value is BobuxInstance and is_instance_valid(value.node):
					parent_node = value.node
				elif value != null and value is Object and (value as Object).has_method("GetNode"):
					var raw_parent: Variant = (value as Object).call("GetNode")
					if raw_parent is Node:
						parent_node = raw_parent
				if parent_node != null and is_instance_valid(parent_node):
					if node.get_parent():
						node.get_parent().remove_child(node)
					parent_node.add_child(node)
					_set_template_tree_visible(node, _is_node_under_workspace(parent_node))
					AncestryChanged.Fire(BobuxInstance.new(node), value)
					Changed.Fire("Parent")
					return true
			"Value":
				node.set_meta("value", value)
				node.set_meta("Value", value)
				Changed.Fire("Value")
				return true
			"Position":
				if node is Node3D and value is Vector3:
					var target_position := _roblox_point_to_godot(value as Vector3)
					if bool(node.get_meta("bobux_character_part_proxy", false)):
						var proxy_body := _character_body()
						if proxy_body != null:
							proxy_body.global_position += target_position - (node as Node3D).global_position
					else:
						(node as Node3D).position = target_position
					Changed.Fire("Position")
					return true
				if node is Control:
					var control_position := _ui_value_to_vector2(value, (node as Control).get_parent() as Control)
					(node as Control).position = control_position
					Changed.Fire("Position")
					return true
			"Rotation":
				if node is Node3D and value is Vector3:
					var roblox_rotation := Basis.from_euler((value as Vector3) * (PI / 180.0), EULER_ORDER_XYZ)
					(node as Node3D).basis = _roblox_transform_to_godot(Transform3D(roblox_rotation, Vector3.ZERO)).basis
					Changed.Fire("Rotation")
					return true
			"CFrame":
				if node is Node3D:
					if value is BobuxCFrame:
						var target_frame := _roblox_transform_to_godot((value as BobuxCFrame).transform)
						if bool(node.get_meta("bobux_character_part_proxy", false)):
							var cframe_body := _character_body()
							if cframe_body != null:
								cframe_body.global_position += target_frame.origin - (node as Node3D).global_position
						else:
							(node as Node3D).transform = target_frame
						Changed.Fire("CFrame")
						return true
					if value is Transform3D:
						node.transform = value
						Changed.Fire("CFrame")
						return true
					if value is Vector3:
						(node as Node3D).position = _roblox_point_to_godot(value as Vector3)
						Changed.Fire("CFrame")
						return true
			"Velocity", "AssemblyLinearVelocity":
				if value is Vector3:
					var godot_velocity := _roblox_velocity_to_godot(value as Vector3)
					node.set_meta("velocity", godot_velocity)
					if node is CharacterBody3D:
						(node as CharacterBody3D).velocity = godot_velocity
					elif node is RigidBody3D:
						(node as RigidBody3D).linear_velocity = godot_velocity
					Changed.Fire(prop_str)
					return true
			"Size":
				if node is Node3D and value is Vector3:
					(node as Node3D).scale = (value as Vector3).abs() * _stud_scale()
					Changed.Fire("Size")
					return true
			"Text":
				var text_value := str(value)
				if node is Button:
					(node as Button).text = text_value
				elif node is Label:
					(node as Label).text = text_value
				elif node is LineEdit:
					(node as LineEdit).text = text_value
				else:
					return false
				var text_properties: Dictionary = node.get_meta("roblox_properties", {}) if node.get_meta("roblox_properties", {}) is Dictionary else {}
				text_properties["Text"] = text_value
				node.set_meta("roblox_properties", text_properties)
				Changed.Fire("Text")
				return true
			"Visible":
				if node is Control:
					(node as Control).visible = bool(value)
					node.set_meta("Visible", bool(value))
					Changed.Fire("Visible")
					return true
			"Enabled":
				if node is BaseButton:
					(node as BaseButton).disabled = not bool(value)
				elif node is Control:
					(node as Control).visible = bool(value)
				else:
					return false
				node.set_meta("Enabled", bool(value))
				Changed.Fire("Enabled")
				return true
				if node is Control:
					(node as Control).size = _ui_value_to_vector2(value, (node as Control).get_parent() as Control)
					Changed.Fire("Size")
					return true
			"Health":
				var health_body := _character_body()
				var target_health := maxf(0.0, float(value))
				if health_body != null:
					var current_health := float(health_body.call("get_health")) if health_body.has_method("get_health") else float(health_body.get("current_health"))
					if target_health < current_health and health_body.has_method("take_damage"):
						health_body.call("take_damage", current_health - target_health)
					else:
						health_body.set("current_health", int(target_health))
				node.set_meta("Health", target_health)
				Changed.Fire("Health")
				return true
			"MaxHealth":
				node.set_meta("MaxHealth", maxf(1.0, float(value)))
				Changed.Fire("MaxHealth")
				return true
			"WalkSpeed":
				var walk_body := _character_body()
				if walk_body != null:
					if walk_body.has_method("set_humanoid_walk_speed"):
						walk_body.call("set_humanoid_walk_speed", maxf(0.0, float(value)))
					else:
						walk_body.set("move_speed", maxf(0.0, float(value)))
				node.set_meta("WalkSpeed", float(value))
				Changed.Fire("WalkSpeed")
				return true
			"JumpPower":
				var jump_body := _character_body()
				if jump_body != null:
					if jump_body.has_method("set_humanoid_jump_power"):
						jump_body.call("set_humanoid_jump_power", maxf(0.0, float(value)))
					else:
						jump_body.set("jump_velocity_setting", maxf(0.0, float(value)))
				node.set_meta("JumpPower", float(value))
				Changed.Fire("JumpPower")
				return true
			"PlatformStand", "Sit", "AutoRotate":
				node.set_meta(prop_str, bool(value))
				Changed.Fire(prop_str)
				return true
			"Anchored":
				node.set_meta("anchored", bool(value))
				Changed.Fire("Anchored")
				return true
			"CanCollide":
				node.set_meta("can_collide", bool(value))
				if node.has_method("_update_block_collision"):
					node.call("_update_block_collision", node)
				Changed.Fire("CanCollide")
				return true
			"Transparency":
				var trans := float(value)
				node.set_meta("transparency", trans)
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if trans > 0.01 else BaseMaterial3D.TRANSPARENCY_DISABLED
					material.albedo_color.a = 1.0 - trans
				)
				Changed.Fire("Transparency")
				return true
			"BrickColor":
				var col: Color = Color.WHITE
				if value is Color:
					col = value
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					var alpha := material.albedo_color.a
					material.albedo_color = Color(col.r, col.g, col.b, alpha)
				)
				Changed.Fire("BrickColor")
				return true
			"Color":
				var color_value: Color = Color.WHITE
				if value is Color:
					color_value = value
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					var alpha := material.albedo_color.a
					material.albedo_color = Color(color_value.r, color_value.g, color_value.b, alpha)
				)
				Changed.Fire("Color")
				return true
			"TimeOfDay", "ClockTime":
				node.set_meta(prop_str, value)
				Changed.Fire(prop_str)
				return true
		var properties: Dictionary = node.get_meta("roblox_properties", {}) if node.get_meta("roblox_properties", {}) is Dictionary else {}
		properties[prop_str] = value
		node.set_meta("roblox_properties", properties)
		node.set_meta(prop_str, value)
		Changed.Fire(prop_str)
		return true

	func SetProperty(property_or_self: Variant, property_or_value: Variant, maybe_value: Variant = null) -> bool:
		var property_name := str(property_or_value if property_or_self == self else property_or_self)
		var value: Variant = maybe_value if property_or_self == self else property_or_value
		return _set(StringName(property_name), value)

	func GetProperty(property_or_self: Variant, maybe_property: Variant = null) -> Variant:
		var property_name := str(maybe_property if property_or_self == self else property_or_self)
		return _get(StringName(property_name))

	func GetNode() -> Node:
		return node

	func FindFirstChild(name_or_self: Variant, name_or_recursive: Variant = null, maybe_recursive: Variant = false) -> BobuxInstance:
		var child_name := str(name_or_recursive if name_or_self == self else name_or_self)
		var recursive := bool(maybe_recursive if name_or_self == self else (name_or_recursive if name_or_recursive != null else false))
		if not is_instance_valid(node):
			return null
		var child := node.find_child(child_name, recursive, false)
		return BobuxInstance.new(child) if child else null

	func findFirstChild(name_or_self: Variant, name_or_recursive: Variant = null, maybe_recursive: Variant = false) -> BobuxInstance:
		return FindFirstChild(name_or_self, name_or_recursive, maybe_recursive)

	func GetChildren(_self_arg: Variant = null) -> Array[BobuxInstance]:
		var arr: Array[BobuxInstance] = []
		if not is_instance_valid(node):
			return arr
		for c in node.get_children():
			arr.append(BobuxInstance.new(c))
		return arr

	func getChildren(_self_arg: Variant = null) -> Array[BobuxInstance]:
		return GetChildren()

	func GetDescendants(_self_arg: Variant = null) -> Array[BobuxInstance]:
		var arr: Array[BobuxInstance] = []
		if not is_instance_valid(node):
			return arr
		_collect_descendants(node, arr)
		return arr

	func _collect_descendants(root_node: Node, out: Array[BobuxInstance]) -> void:
		for child in root_node.get_children():
			out.append(BobuxInstance.new(child))
			_collect_descendants(child, out)

	func Destroy(_self_arg: Variant = null) -> void:
		if is_instance_valid(node):
			Destroying.Fire()
			node.queue_free()

	func Clone(_self_arg: Variant = null) -> BobuxInstance:
		if is_instance_valid(node):
			var dupe := node.duplicate()
			dupe.set_meta("bobux_runtime_generated", true)
			return BobuxInstance.new(dupe)
		return null

	func clone(_self_arg: Variant = null) -> BobuxInstance:
		return Clone()

	func _is_node_under_workspace(candidate: Node) -> bool:
		var cursor := candidate
		while cursor != null:
			var roblox_class := str(cursor.get_meta("roblox_class", ""))
			if roblox_class == "Workspace" or cursor.name in ["Workspace", "Blocks"]:
				return true
			cursor = cursor.get_parent()
		return false

	func _set_template_tree_visible(root_node: Node, visible_in_world: bool) -> void:
		if root_node is Node3D:
			(root_node as Node3D).visible = visible_in_world
		if visible_in_world:
			root_node.set_meta("BobuxTemplateOnly", false)
		for child in root_node.get_children():
			_set_template_tree_visible(child, visible_in_world)

	func remove(_self_arg: Variant = null) -> void:
		Destroy()

	func WaitForChild(name_or_self: Variant, name_or_timeout: Variant = null, maybe_timeout: Variant = 5.0) -> BobuxInstance:
		var child_name := str(name_or_timeout if name_or_self == self else name_or_self)
		if not is_instance_valid(node):
			return null
		var child = node.find_child(child_name, true, false)
		if child:
			return BobuxInstance.new(child)
		# The complete DataModel is installed before scripts start, so an absent
		# child is returned immediately instead of blocking the render thread.
		return null

	func IsA(class_or_self: Variant, maybe_class: Variant = null) -> bool:
		var p_class_name := str(maybe_class if class_or_self == self else class_or_self)
		if not is_instance_valid(node):
			return false
		var roblox_class := str(node.get_meta("roblox_class", node.get_meta("shape_type", "")))
		if roblox_class == p_class_name:
			return true
		if node.has_meta("shape_type") and str(node.get_meta("shape_type")) == p_class_name:
			return true
		if p_class_name == "BasePart" and node is Node3D:
			return true
		return node.is_class(p_class_name)

	func IsDescendantOf(parent_or_self: Variant, maybe_parent: Variant = null) -> bool:
		var parent: BobuxInstance = maybe_parent as BobuxInstance if parent_or_self == self else parent_or_self as BobuxInstance
		if not is_instance_valid(node) or parent == null or not is_instance_valid(parent.node):
			return false
		return parent.node.is_ancestor_of(node)

	func IsAncestorOf(child_or_self: Variant, maybe_child: Variant = null) -> bool:
		var child_variant: Variant = maybe_child if child_or_self == self else child_or_self
		var child_node := _node_from_instance_variant(child_variant)
		return is_instance_valid(node) and is_instance_valid(child_node) and node.is_ancestor_of(child_node)

	func GetConnectedParts(self_or_recursive: Variant = null, maybe_recursive: Variant = null) -> Array[BobuxInstance]:
		if not is_instance_valid(node) or not node.is_inside_tree():
			return []
		var recursive := bool(maybe_recursive) if self_or_recursive == self and maybe_recursive != null else bool(self_or_recursive) if self_or_recursive != null and self_or_recursive != self else false
		var this_ref := str(node.get_meta("roblox_ref", "")).strip_edges()
		if this_ref.is_empty():
			return _connected_siblings_fallback(recursive)
		var scene_root := node.get_tree().current_scene
		if scene_root == null:
			scene_root = node.get_tree().root
		var by_ref: Dictionary = {}
		var constraints: Array[Node] = []
		_index_runtime_graph(scene_root, by_ref, constraints)
		var adjacency: Dictionary = {}
		for constraint in constraints:
			var props: Dictionary = constraint.get_meta("roblox_properties", {}) if constraint.get_meta("roblox_properties", {}) is Dictionary else {}
			var part0 := _normalized_ref(props.get("Part0", constraint.get_meta("Part0", "")))
			var part1 := _normalized_ref(props.get("Part1", constraint.get_meta("Part1", "")))
			if part0.is_empty() or part1.is_empty() or part0 == "-1" or part1 == "-1":
				continue
			if not adjacency.has(part0):
				adjacency[part0] = []
			if not adjacency.has(part1):
				adjacency[part1] = []
			(adjacency[part0] as Array).append(part1)
			(adjacency[part1] as Array).append(part0)
		var result: Array[BobuxInstance] = []
		var visited := {this_ref: true}
		var pending: Array[String] = []
		for direct_ref_variant in adjacency.get(this_ref, []):
			pending.append(str(direct_ref_variant))
		while not pending.is_empty():
			var connected_ref: String = pending.pop_front()
			if visited.has(connected_ref):
				continue
			visited[connected_ref] = true
			var connected_node: Node = by_ref.get(connected_ref, null) as Node
			if connected_node != null and is_instance_valid(connected_node):
				result.append(BobuxInstance.new(connected_node))
			if recursive:
				for next_ref_variant in adjacency.get(connected_ref, []):
					var next_ref := str(next_ref_variant)
					if not visited.has(next_ref):
						pending.append(next_ref)
		return result

	func _connected_siblings_fallback(recursive: bool) -> Array[BobuxInstance]:
		var result: Array[BobuxInstance] = []
		var parent := node.get_parent()
		if parent == null:
			return result
		for sibling in parent.get_children():
			if sibling == node or not (sibling is Node3D):
				continue
			result.append(BobuxInstance.new(sibling))
			if not recursive:
				break
		return result

	func _index_runtime_graph(root: Node, by_ref: Dictionary, constraints: Array[Node]) -> void:
		if root == null:
			return
		var ref := str(root.get_meta("roblox_ref", "")).strip_edges()
		if not ref.is_empty():
			by_ref[ref] = root
		if str(root.get_meta("roblox_class", "")) in JOINT_CLASSES:
			constraints.append(root)
		for child in root.get_children():
			_index_runtime_graph(child, by_ref, constraints)

	func _normalized_ref(value: Variant) -> String:
		if value == null:
			return ""
		if value is BobuxInstance:
			return str((value as BobuxInstance).node.get_meta("roblox_ref", "")).strip_edges()
		if value is Dictionary:
			var data := value as Dictionary
			for key in ["ref", "value", "id"]:
				if data.has(key):
					return str(data[key]).strip_edges()
		return str(value).strip_edges()

	func FindPartOnRayResult(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, _terrain_cells_are_cubes: Variant = false) -> Array:
		var ray: Variant = ray_or_ignore if ray_or_self == self else ray_or_self
		var ignore: Variant = ignore_or_terrain if ray_or_self == self else ray_or_ignore
		return _perform_roblox_raycast(ray, ignore)

	func FindPartOnRayWithIgnoreListResult(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, _terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayResult(ray_or_self, ray_or_ignore, ignore_or_terrain, _terrain_cells_are_cubes)

	func FindPartOnRay(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayResult(ray_or_self, ray_or_ignore, ignore_or_terrain, terrain_cells_are_cubes)

	func FindPartOnRayWithIgnoreList(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayWithIgnoreListResult(ray_or_self, ray_or_ignore, ignore_or_terrain, terrain_cells_are_cubes)

	func Raycast(origin_or_self: Variant, origin_or_direction: Variant = null, direction_or_params: Variant = null, maybe_params: Variant = null) -> Variant:
		var origin: Variant = origin_or_direction if origin_or_self == self else origin_or_self
		var direction: Variant = direction_or_params if origin_or_self == self else origin_or_direction
		var params: Variant = maybe_params if origin_or_self == self else direction_or_params
		if not (origin is Vector3) or not (direction is Vector3):
			return null
		var result := _perform_roblox_raycast(BobuxRay.new(origin, direction), params)
		if result.is_empty() or result[0] == null:
			return null
		return {"Instance": result[0], "Position": result[1], "Normal": result[2], "Material": result[3]}

	func _perform_roblox_raycast(ray_variant: Variant, ignore: Variant) -> Array:
		if not (ray_variant is BobuxRay) or not is_instance_valid(node) or not node.is_inside_tree():
			return [null, Vector3.ZERO, Vector3.ZERO, "Air"]
		var ray := ray_variant as BobuxRay
		var start := _roblox_point_to_godot(ray.Origin)
		var finish := start + _roblox_point_to_godot(ray.Direction)
		if start.is_equal_approx(finish):
			return [null, ray.Origin, Vector3.ZERO, "Air"]
		var viewport := node.get_viewport()
		var world := viewport.world_3d if viewport != null else null
		if world == null:
			return [null, ray.Origin + ray.Direction, Vector3.ZERO, "Air"]
		var query := PhysicsRayQueryParameters3D.create(start, finish)
		query.collision_mask = STUDIO_WORLD_COLLISION_MASK
		query.collide_with_bodies = true
		query.collide_with_areas = true
		var exclusions: Array[RID] = []
		_collect_raycast_exclusions(ignore, exclusions)
		query.exclude = exclusions
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return [null, ray.Origin + ray.Direction, Vector3.ZERO, "Air"]
		var hit_part := _part_from_raycast_collider(hit.get("collider", null))
		var hit_position := _godot_point_to_roblox(hit.get("position", finish) as Vector3)
		var hit_normal := _godot_direction_to_roblox(hit.get("normal", Vector3.ZERO) as Vector3)
		var hit_material: Variant = hit_part.get_meta("material_type", hit_part.get_meta("Material", "Plastic")) if hit_part != null else "Plastic"
		return [BobuxInstance.new(hit_part) if hit_part != null else null, hit_position, hit_normal, hit_material]

	func _collect_raycast_exclusions(value: Variant, out: Array[RID]) -> void:
		if value is Array:
			for item in value as Array:
				_collect_raycast_exclusions(item, out)
			return
		if value is Dictionary:
			for item in (value as Dictionary).values():
				_collect_raycast_exclusions(item, out)
			return
		var ignored_node := _node_from_instance_variant(value)
		if ignored_node != null:
			_collect_collision_rids(ignored_node, out)

	func _collect_collision_rids(root: Node, out: Array[RID]) -> void:
		if root is CollisionObject3D:
			out.append((root as CollisionObject3D).get_rid())
		for child in root.get_children():
			_collect_collision_rids(child, out)

	func _part_from_raycast_collider(collider: Variant) -> Node:
		var cursor := collider as Node if collider is Node else null
		while cursor != null:
			if cursor.is_in_group("studio_parts"):
				return cursor
			var roblox_class := str(cursor.get_meta("roblox_class", ""))
			if roblox_class in ["Part", "MeshPart", "WedgePart", "CornerWedgePart", "TrussPart", "SpawnLocation", "Seat", "VehicleSeat"]:
				return cursor
			cursor = cursor.get_parent()
		return null

	func GetFullName(_self_arg: Variant = null) -> String:
		if not is_instance_valid(node):
			return ""
		var names: Array[String] = []
		var cursor: Node = node
		while cursor != null:
			names.push_front(cursor.name)
			cursor = cursor.get_parent()
		return ".".join(names)

	func ClearAllChildren(_self_arg: Variant = null) -> void:
		if not is_instance_valid(node):
			return
		for child in node.get_children():
			child.queue_free()

	func FireServer(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		if arg1 == self:
			OnServerEvent.Fire(arg2, arg3)
		else:
			OnServerEvent.Fire(arg1, arg2, arg3)

	func FireClient(_player: Variant = null, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		if _player == self:
			OnClientEvent.Fire(arg1, arg2, arg3)
		else:
			OnClientEvent.Fire(arg1, arg2, arg3)

	func FireAllClients(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		if arg1 == self:
			OnClientEvent.Fire(arg2, arg3)
		else:
			OnClientEvent.Fire(arg1, arg2, arg3)

	func InvokeServer(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> Variant:
		var callback: Variant = node.get_meta("OnServerInvoke", null) if is_instance_valid(node) else null
		return callback.call(arg1, arg2, arg3) if callback is Callable else null

	func InvokeClient(_player: Variant = null, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> Variant:
		var callback: Variant = node.get_meta("OnClientInvoke", null) if is_instance_valid(node) else null
		return callback.call(arg1, arg2, arg3) if callback is Callable else null

	func GetAttribute(attribute_or_self: Variant, maybe_attribute_name: Variant = null) -> Variant:
		var attribute_name := str(maybe_attribute_name if attribute_or_self == self else attribute_or_self)
		return node.get_meta("attribute_" + attribute_name, null) if is_instance_valid(node) else null

	func SetAttribute(attribute_or_self: Variant, value_or_name: Variant = null, maybe_value: Variant = null) -> void:
		var attribute_name := str(value_or_name if attribute_or_self == self else attribute_or_self)
		var value: Variant = maybe_value if attribute_or_self == self else value_or_name
		if is_instance_valid(node) and not attribute_name.is_empty():
			node.set_meta("attribute_" + attribute_name, value)
			Changed.Fire(attribute_name)

	func GetPropertyChangedSignal(_property_name: String) -> BobuxEvent:
		return Changed

	func GetPlayers(_self_arg: Variant = null) -> Array[BobuxInstance]:
		return GetChildren()

	func GetPlayerFromCharacter(character_or_self: Variant, maybe_character: Variant = null) -> BobuxInstance:
		if not is_instance_valid(node):
			return null
		var first_node := _node_from_instance_variant(character_or_self)
		var character_variant: Variant = maybe_character if first_node == node and maybe_character != null else character_or_self
		var character_node := _node_from_instance_variant(character_variant)
		if not is_instance_valid(character_node):
			return null
		var character_body: Node = character_node
		while character_body != null and not (character_body is CharacterBody3D):
			character_body = character_body.get_parent()
		if character_body == null:
			return null
		for player_node in node.get_children():
			var bound_id := int(player_node.get_meta("bobux_character_instance_id", 0))
			if bound_id == character_body.get_instance_id():
				return BobuxInstance.new(player_node)
		return null

	func playerFromCharacter(character_or_self: Variant, maybe_character: Variant = null) -> BobuxInstance:
		return GetPlayerFromCharacter(character_or_self, maybe_character)

	func LoadCharacter(_self_arg: Variant = null) -> BobuxInstance:
		var character := _bound_character()
		if character == null:
			return null
		if character.has_method("force_respawn"):
			character.call("force_respawn")
		elif character is CharacterBody3D:
			(character as CharacterBody3D).velocity = Vector3.ZERO
		_shared_event("CharacterAdded").Fire(BobuxInstance.new(character))
		return BobuxInstance.new(character)

	func GetMouse(_self_arg: Variant = null) -> BobuxMouse:
		return BobuxMouse.new()

	func Play(_self_arg: Variant = null) -> void:
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).play()
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).play()
		else:
			node.set_meta("Playing", true)

	func Stop(_self_arg: Variant = null) -> void:
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stop()
		else:
			node.set_meta("Playing", false)

	func GetMass(_self_arg: Variant = null) -> float:
		if node is RigidBody3D:
			return (node as RigidBody3D).mass
		if node is Node3D:
			var dimensions := (node as Node3D).scale.abs() / _stud_scale()
			return maxf(dimensions.x * dimensions.y * dimensions.z, 0.001)
		return 1.0

	func MoveTo(position_or_self: Variant, maybe_position: Variant = null) -> void:
		var destination: Variant = maybe_position if position_or_self == self else position_or_self
		if not (destination is Vector3):
			return
		var godot_destination := _roblox_point_to_godot(destination as Vector3)
		var body := _character_body()
		if body != null:
			body.global_position = godot_destination
			body.velocity = Vector3.ZERO
			return
		if node is Node3D:
			(node as Node3D).global_position = godot_destination

	func TakeDamage(amount_or_self: Variant, maybe_amount: Variant = null) -> void:
		var amount := float(maybe_amount if amount_or_self == self else amount_or_self)
		var body := _character_body()
		if body != null and body.has_method("take_damage"):
			body.call("take_damage", amount)

	func ChangeState(state_or_self: Variant, maybe_state: Variant = null) -> void:
		var state_value: Variant = maybe_state if state_or_self == self else state_or_self
		node.set_meta("HumanoidState", state_value)

	func GetState(_self_arg: Variant = null) -> Variant:
		return node.get_meta("HumanoidState", "Running") if is_instance_valid(node) else "Running"

	func LoadAnimation(_animation_or_self: Variant = null, _maybe_animation: Variant = null) -> BobuxAnimationTrack:
		return BobuxAnimationTrack.new()

	func GetModelCFrame(_self_arg: Variant = null) -> BobuxCFrame:
		if node is Node3D:
			return BobuxCFrame.new(_godot_transform_to_roblox((node as Node3D).global_transform))
		var first_part := _first_descendant_node3d(node)
		return BobuxCFrame.new(_godot_transform_to_roblox(first_part.global_transform)) if first_part != null else BobuxCFrame.new()

	func GetModelSize(_self_arg: Variant = null) -> Vector3:
		var bounds := _combined_descendant_bounds(node)
		return bounds.size / _stud_scale()

	func SetPrimaryPartCFrame(frame_or_self: Variant, maybe_frame: Variant = null) -> void:
		var frame_value: Variant = maybe_frame if frame_or_self == self else frame_or_self
		if not (frame_value is BobuxCFrame):
			return
		var desired := _roblox_transform_to_godot((frame_value as BobuxCFrame).transform)
		if node is Node3D:
			(node as Node3D).global_transform = desired
			return
		var first_part := _first_descendant_node3d(node)
		if first_part != null:
			first_part.global_transform = desired

	func TweenPosition(goal_or_self: Variant, maybe_goal: Variant = null, _direction: Variant = null, _style: Variant = null, _time: Variant = 1.0, _override: Variant = false, callback: Variant = null) -> bool:
		var goal: Variant = maybe_goal if goal_or_self == self else goal_or_self
		_set(&"Position", goal)
		if callback is Callable:
			(callback as Callable).call()
		return true

	func TweenSize(goal_or_self: Variant, maybe_goal: Variant = null, _direction: Variant = null, _style: Variant = null, _time: Variant = 1.0, _override: Variant = false, callback: Variant = null) -> bool:
		var goal: Variant = maybe_goal if goal_or_self == self else goal_or_self
		_set(&"Size", goal)
		if callback is Callable:
			(callback as Callable).call()
		return true

	func BreakJoints(_self_arg: Variant = null) -> void:
		if not is_instance_valid(node):
			return
		var character_body := _character_body()
		if character_body != null:
			if character_body.has_method("take_damage"):
				character_body.call("take_damage", 1000000.0)
			elif character_body.has_method("force_respawn"):
				character_body.call_deferred("force_respawn")
			return
		if not node.is_inside_tree():
			return
		var target_refs: Dictionary = {}
		_collect_descendant_roblox_refs(node, target_refs)
		var scene_root := node.get_tree().current_scene
		if scene_root == null:
			scene_root = node.get_tree().root
		var by_ref: Dictionary = {}
		var constraints: Array[Node] = []
		_index_runtime_graph(scene_root, by_ref, constraints)
		for constraint in constraints:
			var properties: Dictionary = constraint.get_meta("roblox_properties", {}) if constraint.get_meta("roblox_properties", {}) is Dictionary else {}
			var part0 := _normalized_ref(properties.get("Part0", constraint.get_meta("Part0", "")))
			var part1 := _normalized_ref(properties.get("Part1", constraint.get_meta("Part1", "")))
			if target_refs.has(part0) or target_refs.has(part1):
				constraint.queue_free()

	func MakeJoints(_self_arg: Variant = null) -> void:
		if is_instance_valid(node):
			node.set_meta("bobux_make_joints_requested", true)

	func _collect_descendant_roblox_refs(root: Node, result: Dictionary) -> void:
		if root == null:
			return
		var ref := str(root.get_meta("roblox_ref", "")).strip_edges()
		if not ref.is_empty():
			result[ref] = true
		for child in root.get_children():
			_collect_descendant_roblox_refs(child, result)

	func _first_descendant_node3d(root_node: Node) -> Node3D:
		if root_node == null:
			return null
		for child in root_node.get_children():
			if child is Node3D:
				return child as Node3D
			var nested := _first_descendant_node3d(child)
			if nested != null:
				return nested
		return null

	func _combined_descendant_bounds(root_node: Node) -> AABB:
		var result := AABB()
		var initialized := false
		if root_node == null:
			return result
		var root_inverse := Transform3D.IDENTITY
		if root_node is Node3D:
			root_inverse = (root_node as Node3D).global_transform.affine_inverse()
		for descendant in root_node.find_children("*", "MeshInstance3D", true, false):
			if not (descendant is MeshInstance3D):
				continue
			var mesh_node := descendant as MeshInstance3D
			var local_bounds := mesh_node.get_aabb()
			var relative_transform := root_inverse * mesh_node.global_transform
			var transformed_bounds := relative_transform * local_bounds
			if not initialized:
				result = transformed_bounds
				initialized = true
			else:
				result = result.merge(transformed_bounds)
		return result

	func LoadAsset(asset_or_self: Variant, maybe_asset_id: Variant = null) -> BobuxInstance:
		var asset_id: Variant = maybe_asset_id if asset_or_self == self else asset_or_self
		var model := Node3D.new()
		model.name = "Asset_%s" % str(asset_id)
		model.set_meta("roblox_class", "Model")
		model.set_meta("roblox_asset_id", str(asset_id))
		# InsertService is an online service in Roblox. The compatibility runtime
		# returns a stable model shell when the asset is not bundled with the place,
		# allowing old scripts to parent/configure it without crashing Play.
		var asset_root := Node3D.new()
		asset_root.name = "AssetRoot"
		asset_root.set_meta("roblox_class", "Model")
		model.add_child(asset_root)
		return BobuxInstance.new(model)

	func PromptPurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func PromptProductPurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func UserHasBadge(_user_or_self: Variant = null, _user_or_badge: Variant = null, _badge_id: Variant = null) -> bool:
		return false

	func AwardBadge(_user_or_self: Variant = null, _user_or_badge: Variant = null, _badge_id: Variant = null) -> bool:
		return true

	func PlayerOwnsAsset(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return false

	func PlayerHasPass(_player_or_self: Variant = null, _player_or_pass: Variant = null, _pass_id: Variant = null) -> bool:
		return false

class BobuxInstanceCreator extends RefCounted:
	var workspace_node: Node
	func _init(ws: Node) -> void:
		workspace_node = ws
	func new(p_class_name: String, parent_variant: Variant = null) -> BobuxInstance:
		if p_class_name == "Part":
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.name = "Part"
			mesh_inst.add_to_group("studio_parts")
			mesh_inst.set_meta("shape_type", "Box")
			mesh_inst.set_meta("block_name", "Part_" + str(randi() % 10000))
			# Default geometry
			var box := BoxMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.WHITE
			box.surface_set_material(0, mat)
			mesh_inst.mesh = box
			mesh_inst.scale = Vector3(4.0, 1.0, 4.0)
			# Rebuild helpers / collision
			var studio = Engine.get_main_loop().current_scene
			if studio != null and studio.has_method("_rebuild_block_helpers"):
				studio.call("_rebuild_block_helpers", mesh_inst)
				studio.call("_update_block_collision", mesh_inst)
			var part_instance := BobuxInstance.new(mesh_inst)
			if parent_variant != null:
				part_instance._set(&"Parent", parent_variant)
			return part_instance
		var node := Node.new()
		node.name = p_class_name
		node.set_meta("roblox_class", p_class_name)
		match p_class_name:
			"Folder", "Model", "Configuration":
				pass
			"RemoteEvent":
				node.set_meta("roblox_class", "RemoteEvent")
			"BindableEvent":
				node.set_meta("roblox_class", "BindableEvent")
			"BoolValue":
				node.set_meta("value", false)
			"IntValue":
				node.set_meta("value", 0)
			"NumberValue":
				node.set_meta("value", 0.0)
			"StringValue":
				node.set_meta("value", "")
			"Vector3Value":
				node.set_meta("value", Vector3.ZERO)
			"ObjectValue":
				node.set_meta("value", null)
			"ScreenGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton":
				node.set_meta("roblox_class", p_class_name)
			_:
				node.set_meta("roblox_class", p_class_name)
		var instance := BobuxInstance.new(node)
		if parent_variant != null:
			instance._set(&"Parent", parent_variant)
		return instance

func _ready() -> void:
	_init_lua_engine()
	set_process(true)

func _init_lua_engine() -> void:
	if ClassDB.class_exists("LuaAPI"):
		print("[LuaScriptEngine] Initializing WeaselGames LuaAPI GDExtension...")
		_lua = ClassDB.instantiate("LuaAPI")
		is_active = true
	else:
		push_warning("[LuaScriptEngine] WeaselGames LuaAPI class not found in current runtime. Using Sandbox Mock fallback.")
		_lua = null
		is_active = false

func run_script(lua_code: String, context_node: Node) -> Dictionary:
	return start_script(lua_code, context_node, {"realm": "studio", "retain": true})
	# Legacy synchronous implementation remains below as a compatibility
	# reference; the coroutine scheduler above is now the active path.
	print("[LuaScriptEngine] Executing Lua script on node: ", context_node.name)
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	if tree == null and context_node != null and context_node.is_inside_tree():
		tree = context_node.get_tree()
	var main_scene: Node = tree.current_scene if tree != null else null
	var workspace_node: Node = _resolve_workspace_node(main_scene, context_node)
	var service_nodes := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var ws_instance := BobuxInstance.new(workspace_node)
	var service_instances: Dictionary = {}
	for service_name in service_nodes.keys():
		service_instances[service_name] = BobuxInstance.new(service_nodes[service_name])
	
	var tween_service := {
		"Create": func(arg1: Variant, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null):
			var part = arg2 if arg4 != null else arg1
			var target_props = arg4 if arg4 != null else arg3
			return {
				"Play": func():
					if part is BobuxInstance and target_props is Dictionary:
						for key in target_props:
							part._set(str(key), target_props[key])
			}
	}
	var run_service := {
		"Heartbeat": BobuxEvent.new(),
		"Stepped": BobuxEvent.new(),
		"RenderStepped": BobuxEvent.new(),
		"IsServer": func(): return true,
		"IsClient": func(): return false
	}
	var debris_service := {
		"AddItem": func(arg1: Variant, arg2: Variant = null, _arg3: Variant = null):
			var item = arg2 if arg2 is BobuxInstance else arg1
			if item is BobuxInstance:
				(item as BobuxInstance).Destroy()
	}
	var game_proxy := {
		"Workspace": ws_instance,
		"workspace": ws_instance,
		"Players": service_instances.get("Players", BobuxInstance.new(null)),
		"Lighting": service_instances.get("Lighting", BobuxInstance.new(null)),
		"ReplicatedStorage": service_instances.get("ReplicatedStorage", BobuxInstance.new(null)),
		"ServerStorage": service_instances.get("ServerStorage", BobuxInstance.new(null)),
		"StarterGui": service_instances.get("StarterGui", BobuxInstance.new(null)),
		"StarterPack": service_instances.get("StarterPack", BobuxInstance.new(null)),
		"GetService": func(arg1: Variant, arg2: Variant = null):
			var service_name := str(arg2 if arg2 != null else arg1)
			match service_name:
				"Workspace":
					return ws_instance
				"TweenService":
					return tween_service
				"RunService":
					return run_service
				"Debris":
					return debris_service
				_:
					if service_instances.has(service_name):
						return service_instances[service_name]
					return BobuxInstance.new(_ensure_single_roblox_service(main_scene, service_name, workspace_node))
	}

	var instance_creator := BobuxInstanceCreator.new(workspace_node)
	
	if is_active and _lua != null:
		var prepared_lua_code := _rewrite_lua_property_assignments(lua_code)
		_last_property_setter_calls = 0
		_last_property_setter_target_type = ""
		_last_property_setter_target_class = ""
		_last_property_setter_has_set_property = false
		# Bind proxy variables
		_lua.push_variant("game", game_proxy)
		_lua.push_variant("workspace", ws_instance)
		_lua.push_variant("Instance", instance_creator)
		_lua.push_variant("Vector3", {
			"new": func(x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0): return Vector3(float(x), float(y), float(z))
		})
		_lua.push_variant("Ray", {
			"new": func(origin: Variant = Vector3.ZERO, direction: Variant = Vector3.ZERO): return BobuxRay.new(origin, direction)
		})
		_lua.push_variant("CFrame", _build_cframe_library())
		_lua.push_variant("Color3", {
			"new": func(r: Variant = 1.0, g: Variant = 1.0, b: Variant = 1.0): return Color(float(r), float(g), float(b))
		})
		_lua.push_variant("BrickColor", _build_brick_color_library())
		_lua.push_variant("UDim2", {
			"new": func(xs: Variant = 0.0, xo: Variant = 0.0, ys: Variant = 0.0, yo: Variant = 0.0):
				return {
					"x": {"scale": float(xs), "offset": int(xo)},
					"y": {"scale": float(ys), "offset": int(yo)}
				}
		})
		_lua.push_variant("print", func(msg): print("[LUA PRINT] ", msg))
		_lua.push_variant("wait", func(_t: Variant = 0.03): return Engine.get_process_frames())
		_lua.push_variant("task", {
			"wait": func(_t: Variant = 0.03): return Engine.get_process_frames(),
			"spawn": func(callable: Variant): if callable is Callable: callable.call(),
			"defer": func(callable: Variant): if callable is Callable: callable.call()
		})
		_lua.push_variant("tick", func(): return Time.get_ticks_msec() / 1000.0)
		_lua.push_variant("Enum", _build_enum_proxy())
		_lua.push_variant("script", BobuxInstance.new(context_node))
		_lua.push_variant("__bobux_set", func(target: Variant, property_name: Variant, value: Variant):
			_last_property_setter_calls += 1
			_last_property_setter_target_type = type_string(typeof(target))
			if target is Object:
				_last_property_setter_target_class = (target as Object).get_class()
				_last_property_setter_has_set_property = (target as Object).has_method("SetProperty")
			if target is BobuxInstance:
				(target as BobuxInstance)._set(str(property_name), value)
			elif target != null and target is Object and (target as Object).has_method("SetProperty"):
				(target as Object).call("SetProperty", str(property_name), value)
			return value
		)
		
		var result = _lua.do_string(prepared_lua_code)
		if result == null:
			return {"ok": true}
		if result.has_error():
			var err = "[LUA ERROR] " + result.get_error()
			push_error(err)
			return {"ok": false, "error": err}
		return {"ok": true}
	else:
		# Fallback interpreter: Execute simple mockup code or parse basic operations for sandbox compatibility
		# If the script has standard print statements or basic changes, we can mock it
		print("[LuaScriptEngine Mock] Mock running code: \n", lua_code)
		if "print" in lua_code:
			print("[LUA PRINT (MOCK)] Hello, World!")
		return {"ok": true, "mock": true}


func start_script(lua_code: String, context_node: Node, options: Dictionary = {}) -> Dictionary:
	if context_node == null or not is_instance_valid(context_node):
		return {"ok": false, "error": "Script context is invalid."}
	if lua_code.to_utf8_buffer().size() > MAX_SCRIPT_SOURCE_BYTES:
		return {"ok": false, "error": "Script exceeds the %d byte safety limit." % MAX_SCRIPT_SOURCE_BYTES}
	var static_safety_error := _static_script_safety_error(lua_code)
	if not static_safety_error.is_empty():
		return {"ok": false, "error": static_safety_error}
	if _script_runtimes.size() >= MAX_CONCURRENT_SCRIPTS:
		return {"ok": false, "error": "Script runtime limit reached (%d)." % MAX_CONCURRENT_SCRIPTS}
	if not ClassDB.class_exists("LuaAPI"):
		return {"ok": false, "error": "LuaAPI GDExtension is unavailable."}
	if bool(options.get("defer_compilation", false)):
		var queued_runtime_id := _next_script_runtime_id
		_next_script_runtime_id += 1
		var queued_options := options.duplicate(true)
		queued_options["defer_compilation"] = false
		queued_options["_reserved_runtime_id"] = queued_runtime_id
		queued_options["_runtime_was_counted"] = true
		_pending_script_starts.append({
			"id": queued_runtime_id,
			"source": lua_code,
			"context": context_node,
			"options": queued_options,
		})
		_runtime_started_total += 1
		context_node.set_meta("bobux_script_runtime_id", queued_runtime_id)
		return {
			"ok": true,
			"runtime_id": queued_runtime_id,
			"queued": true,
			"scheduled": true,
			"completed": false,
		}

	var lua = ClassDB.instantiate("LuaAPI")
	if lua == null:
		return {"ok": false, "error": "Could not create LuaAPI state."}
	if lua.has_method("set_memory_limit"):
		lua.set_memory_limit(SCRIPT_MEMORY_LIMIT_BYTES)
	if lua.has_method("set_use_callables"):
		lua.set_use_callables(true)
	var bind_error = lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine", "utf8"]))
	var bind_message := _lua_error_message(bind_error)
	if not bind_message.is_empty():
		return {"ok": false, "error": "Lua library binding failed: %s" % bind_message}
	var coroutine = lua.new_coroutine()
	if coroutine == null:
		return {"ok": false, "error": "Could not create Lua coroutine."}
	_push_runtime_bindings(coroutine, context_node, options)
	var prepared_source := _prepare_scheduled_lua_source(lua_code)
	var load_error = coroutine.load_string(prepared_source)
	var load_message := _lua_error_message(load_error)
	if not load_message.is_empty():
		return {"ok": false, "error": "[LUA LOAD ERROR] %s" % load_message}

	var runtime_id := int(options.get("_reserved_runtime_id", 0))
	if runtime_id <= 0:
		runtime_id = _next_script_runtime_id
		_next_script_runtime_id += 1
	var runtime := {
		"id": runtime_id,
		"lua": lua,
		"coroutine": coroutine,
		"context": context_node,
		"wake_at": 0.0,
		"realm": str(options.get("realm", "runtime")),
		"source_name": str(options.get("source_name", context_node.name)),
		"retain": bool(options.get("retain", true)),
		"last_error": "",
	}
	_script_runtimes[runtime_id] = runtime
	_configure_instruction_hook(coroutine, runtime_id)
	if not bool(options.get("_runtime_was_counted", false)):
		_runtime_started_total += 1
	context_node.set_meta("bobux_script_runtime_id", runtime_id)
	if bool(options.get("defer_initial_resume", false)):
		return {
			"ok": true,
			"runtime_id": runtime_id,
			"scheduled": true,
			"completed": false,
			"deferred": true,
		}
	var resume_result := _resume_script_runtime(runtime_id)
	if not bool(resume_result.get("ok", false)):
		return resume_result
	return {
		"ok": true,
		"runtime_id": runtime_id,
		"scheduled": _script_runtimes.has(runtime_id),
		"completed": not _script_runtimes.has(runtime_id),
	}

func validate_script_source(lua_code: String) -> Dictionary:
	if not ClassDB.class_exists("LuaAPI"):
		return {"ok": false, "error": "LuaAPI GDExtension is unavailable."}
	var lua = ClassDB.instantiate("LuaAPI")
	if lua == null:
		return {"ok": false, "error": "Could not create LuaAPI state."}
	if lua.has_method("set_use_callables"):
		lua.set_use_callables(true)
	var bind_error = lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine", "utf8"]))
	var bind_message := _lua_error_message(bind_error)
	if not bind_message.is_empty():
		return {"ok": false, "error": bind_message}
	var coroutine = lua.new_coroutine()
	if coroutine == null:
		return {"ok": false, "error": "Could not create Lua coroutine."}
	var prepared_source := _prepare_scheduled_lua_source(lua_code)
	var load_error = coroutine.load_string(prepared_source)
	var load_message := _lua_error_message(load_error)
	return {
		"ok": load_message.is_empty(),
		"error": load_message,
		"source_bytes": lua_code.to_utf8_buffer().size(),
	}


func stop_script(context_or_runtime: Variant) -> void:
	var runtime_ids: Array[int] = []
	if context_or_runtime is int:
		runtime_ids.append(int(context_or_runtime))
	elif context_or_runtime is Node:
		var context_node := context_or_runtime as Node
		_clear_runtime_event_connections_recursive(context_node)
		for runtime_id_variant in _script_runtimes.keys():
			var runtime: Dictionary = _script_runtimes[runtime_id_variant]
			if runtime.get("context") == context_node:
				runtime_ids.append(int(runtime_id_variant))
		for runtime_id_variant in _retained_lua_states.keys():
			var retained: Dictionary = _retained_lua_states[runtime_id_variant]
			if retained.get("context") == context_node:
				runtime_ids.append(int(runtime_id_variant))
	for runtime_id in runtime_ids:
		_dispose_script_runtime(runtime_id)
		_dispose_retained_lua_state(runtime_id)


func stop_all_scripts(root_context: Node = null) -> void:
	if root_context == null:
		_clear_all_runtime_event_connections(get_tree().root if is_inside_tree() else null)
		_pending_script_starts.clear()
		# Module return values and event callbacks may contain LuaCallable values.
		# The extension stores a raw lua_State pointer in those callables, so every
		# external callable must die before its owning LuaAPI closes the state.
		_module_cache.clear()
		for runtime_id_variant in _script_runtimes.keys().duplicate():
			_dispose_script_runtime(int(runtime_id_variant))
		for runtime_id_variant in _retained_lua_states.keys().duplicate():
			_dispose_retained_lua_state(runtime_id_variant)
		_runtime_resume_started_usec.clear()
		_runtime_budget_exceeded.clear()
		return
	_clear_all_runtime_event_connections(root_context)
	var remaining_pending: Array[Dictionary] = []
	for pending in _pending_script_starts:
		var pending_context: Node = pending.get("context") as Node
		if pending_context == null or not is_instance_valid(pending_context) or pending_context == root_context or root_context.is_ancestor_of(pending_context):
			continue
		remaining_pending.append(pending)
	_pending_script_starts = remaining_pending
	# Module return values can be Lua callables owned by any runtime below this
	# root. Release them before disposing the corresponding Lua states.
	_module_cache.clear()
	for runtime_id_variant in _script_runtimes.keys().duplicate():
		var runtime: Dictionary = _script_runtimes[runtime_id_variant]
		var context: Node = runtime.get("context") as Node
		if context != null and (context == root_context or root_context.is_ancestor_of(context)):
			_dispose_script_runtime(int(runtime_id_variant))
	for runtime_id_variant in _retained_lua_states.keys().duplicate():
		var retained: Dictionary = _retained_lua_states[runtime_id_variant]
		var context: Node = retained.get("context") as Node
		if context != null and (context == root_context or root_context.is_ancestor_of(context)):
			_dispose_retained_lua_state(runtime_id_variant)


func _dispose_script_runtime(runtime_id: int) -> void:
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	if not _script_runtimes.has(runtime_id):
		return
	var runtime: Dictionary = _script_runtimes[runtime_id]
	_script_runtimes.erase(runtime_id)
	# LuaCoroutine owns a Ref<LuaAPI>. Drop our duplicate LuaAPI reference first,
	# then the coroutine. Keep the state quarantined until removed scene nodes
	# have completed their deferred destruction and released every LuaCallable.
	var lua: Variant = runtime.get("lua")
	if lua != null:
		_stopped_lua_state_quarantine.append(lua)
	runtime["lua"] = null
	runtime["coroutine"] = null
	runtime.clear()


func _dispose_retained_lua_state(runtime_id: Variant) -> void:
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	if not _retained_lua_states.has(runtime_id):
		return
	var retained: Dictionary = _retained_lua_states[runtime_id]
	_retained_lua_states.erase(runtime_id)
	var lua: Variant = retained.get("lua")
	if lua != null:
		_stopped_lua_state_quarantine.append(lua)
	retained["lua"] = null
	retained.clear()


func release_stopped_script_states() -> void:
	# Call only after the stopped playtest tree has survived at least one
	# process frame. LuaCallable destructors require their lua_State to exist.
	_stopped_lua_state_quarantine.clear()


func set_scripts_paused(paused: bool) -> void:
	_scripts_paused = paused


func _process(delta: float) -> void:
	if _scripts_paused:
		return
	_process_pending_script_starts()
	_ensure_run_service_events()
	_run_service_stepped.Fire(Time.get_ticks_msec() / 1000.0, delta)
	_run_service_heartbeat.Fire(delta)
	_run_service_render_stepped.Fire(delta)
	var now := Time.get_ticks_msec() / 1000.0
	var runtime_ids: Array = _script_runtimes.keys().duplicate()
	if runtime_ids.is_empty():
		_scheduler_cursor = 0
		return
	var frame_started_usec := Time.get_ticks_usec()
	var resumed := 0
	var inspected := 0
	var start_index := _scheduler_cursor % runtime_ids.size()
	while inspected < runtime_ids.size():
		var runtime_id_variant: Variant = runtime_ids[(start_index + inspected) % runtime_ids.size()]
		inspected += 1
		var runtime_id := int(runtime_id_variant)
		if not _script_runtimes.has(runtime_id):
			continue
		var runtime: Dictionary = _script_runtimes[runtime_id]
		var context: Node = runtime.get("context") as Node
		if context == null or not is_instance_valid(context):
			_retain_stopped_runtime(runtime_id, runtime)
			continue
		if now + 0.0001 >= float(runtime.get("wake_at", 0.0)):
			_resume_script_runtime(runtime_id)
			resumed += 1
			if resumed >= SCRIPT_RESUME_BUDGET_PER_FRAME or Time.get_ticks_usec() - frame_started_usec >= SCRIPT_RESUME_TIME_BUDGET_USEC:
				break
	_scheduler_cursor = (start_index + inspected) % maxi(runtime_ids.size(), 1)


func _resume_script_runtime(runtime_id: int) -> Dictionary:
	if not _script_runtimes.has(runtime_id):
		return {"ok": false, "error": "Script runtime no longer exists."}
	var runtime: Dictionary = _script_runtimes[runtime_id]
	var coroutine = runtime.get("coroutine")
	if coroutine == null:
		_dispose_script_runtime(runtime_id)
		return {"ok": false, "error": "Script coroutine is missing."}
	_runtime_resume_started_usec[runtime_id] = Time.get_ticks_usec()
	_runtime_budget_exceeded.erase(runtime_id)
	var result: Variant = coroutine.resume([])
	_runtime_resume_started_usec.erase(runtime_id)
	var error_message := _lua_error_message(result)
	if _runtime_budget_exceeded.has(runtime_id):
		error_message = "Script exceeded the %.1f ms execution budget without yielding." % [float(SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC) / 1000.0]
		_runtime_budget_exceeded.erase(runtime_id)
	if not error_message.is_empty():
		# A script can connect callbacks before its first later error. Keep the
		# owning Lua state alive until Stop so those callbacks never point at a
		# closed lua_State.
		_retain_stopped_runtime(runtime_id, runtime)
		_runtime_failed_total += 1
		_runtime_last_errors.append("%s: %s" % [runtime.get("source_name", "Script"), error_message])
		if _runtime_last_errors.size() > 64:
			_runtime_last_errors.pop_front()
		push_warning("[LuaScriptEngine] %s: %s" % [runtime.get("source_name", "Script"), error_message])
		return {"ok": false, "error": "[LUA ERROR] %s" % error_message, "runtime_id": runtime_id}
	if bool(coroutine.is_done()):
		_script_runtimes.erase(runtime_id)
		_runtime_completed_total += 1
		if bool(runtime.get("retain", true)):
			_retained_lua_states[runtime_id] = {
				"lua": runtime.get("lua"),
				"coroutine": runtime.get("coroutine"),
				"context": runtime.get("context"),
				"realm": runtime.get("realm", "runtime"),
			}
		return {"ok": true, "completed": true, "runtime_id": runtime_id, "result": result}
	var delay_seconds := 0.03
	if result is Array and not (result as Array).is_empty():
		var yielded: Variant = (result as Array)[0]
		if yielded is float or yielded is int:
			delay_seconds = maxf(float(yielded), 0.0)
	runtime["wake_at"] = Time.get_ticks_msec() / 1000.0 + delay_seconds
	_script_runtimes[runtime_id] = runtime
	return {"ok": true, "completed": false, "runtime_id": runtime_id, "delay": delay_seconds}


func _retain_stopped_runtime(runtime_id: int, runtime: Dictionary) -> void:
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	_script_runtimes.erase(runtime_id)
	var lua: Variant = runtime.get("lua")
	if lua != null:
		_retained_lua_states[runtime_id] = {
			"lua": lua,
			"coroutine": runtime.get("coroutine"),
			"context": runtime.get("context"),
			"realm": runtime.get("realm", "runtime"),
		}
	runtime["lua"] = null
	runtime["coroutine"] = null
	runtime.clear()


func _configure_instruction_hook(coroutine: Variant, runtime_id: int) -> void:
	if coroutine != null and coroutine.has_method("set_hook"):
		coroutine.set_hook(
			Callable(self, "_on_script_instruction_hook").bind(runtime_id),
			LUA_HOOK_MASK_COUNT,
			SCRIPT_INSTRUCTION_HOOK_INTERVAL
		)


func _on_script_instruction_hook(_lua_api: Variant, _event: Variant, _line: Variant, runtime_id: int) -> Variant:
	if not _runtime_resume_started_usec.has(runtime_id):
		return null
	var elapsed_usec := Time.get_ticks_usec() - int(_runtime_resume_started_usec[runtime_id])
	if elapsed_usec <= SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC:
		return null
	_runtime_budget_exceeded[runtime_id] = true
	# AABB is intentionally unsupported by this Lua extension. Returning it
	# makes the hook raise a protected Lua error and unwinds the runaway resume.
	return AABB(Vector3.ZERO, Vector3.ONE)


func reset_runtime_diagnostics() -> void:
	_runtime_started_total = 0
	_runtime_completed_total = 0
	_runtime_failed_total = 0
	_runtime_last_errors.clear()


func get_runtime_diagnostics() -> Dictionary:
	return {
		"started": _runtime_started_total,
		"completed": _runtime_completed_total,
		"failed": _runtime_failed_total,
		"active": _script_runtimes.size(),
		"pending": _pending_script_starts.size(),
		"retained": _retained_lua_states.size(),
		"quarantined": _stopped_lua_state_quarantine.size(),
		"last_errors": _runtime_last_errors.duplicate(),
	}


func _process_pending_script_starts() -> void:
	var compiled := 0
	var compile_started_usec := Time.get_ticks_usec()
	while not _pending_script_starts.is_empty():
		var pending: Dictionary = _pending_script_starts.pop_front()
		var context: Node = pending.get("context") as Node
		if context == null or not is_instance_valid(context):
			continue
		var result := start_script(
			str(pending.get("source", "")),
			context,
			pending.get("options", {}) as Dictionary
		)
		if not bool(result.get("ok", false)):
			_runtime_failed_total += 1
			_runtime_last_errors.append("%s: %s" % [
				str((pending.get("options", {}) as Dictionary).get("source_name", context.name)),
				str(result.get("error", "Script compilation failed")),
			])
		compiled += 1
		if compiled >= SCRIPT_COMPILE_BUDGET_PER_FRAME or Time.get_ticks_usec() - compile_started_usec >= SCRIPT_COMPILE_TIME_BUDGET_USEC:
			break


func _clear_all_runtime_event_connections(root: Node) -> void:
	if root != null and is_instance_valid(root):
		_clear_runtime_event_connections_recursive(root)
	for event_variant in [_run_service_heartbeat, _run_service_stepped, _run_service_render_stepped]:
		if event_variant is BobuxEvent:
			(event_variant as BobuxEvent).connections.clear()


func _clear_runtime_event_connections_recursive(node: Node) -> void:
	if node.has_meta("_bobux_event_registry"):
		var registry: Variant = node.get_meta("_bobux_event_registry")
		if registry is Dictionary:
			for event_variant in (registry as Dictionary).values():
				if event_variant is BobuxEvent:
					(event_variant as BobuxEvent).connections.clear()
		node.remove_meta("_bobux_event_registry")
		node.remove_meta("_bobux_signal_bridge")
	_clear_runtime_callable_metadata(node)
	for child in node.get_children():
		_clear_runtime_event_connections_recursive(child)


func _clear_runtime_callable_metadata(node: Node) -> void:
	# Roblox permits assigning Lua functions to Instance properties such as
	# RemoteFunction.OnServerInvoke. The bridge stores unknown properties in
	# metadata, so those LuaCallable values must be released while their
	# lua_State is still alive.
	for meta_name_variant in node.get_meta_list():
		var meta_name := StringName(meta_name_variant)
		if meta_name in [&"_bobux_event_registry", &"_bobux_signal_bridge"]:
			continue
		var value: Variant = node.get_meta(meta_name)
		if not _variant_contains_runtime_callable(value):
			continue
		if value is Callable:
			node.remove_meta(meta_name)
		else:
			node.set_meta(meta_name, _without_runtime_callables(value))


func _variant_contains_runtime_callable(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	if value is Callable:
		return true
	if value is Array:
		for child_value in value as Array:
			if _variant_contains_runtime_callable(child_value, depth + 1):
				return true
	elif value is Dictionary:
		for child_value in (value as Dictionary).values():
			if _variant_contains_runtime_callable(child_value, depth + 1):
				return true
	return false


func _without_runtime_callables(value: Variant, depth: int = 0) -> Variant:
	if depth > 8 or value is Callable:
		return null
	if value is Array:
		var clean_array: Array = []
		for child_value in value as Array:
			if not _variant_contains_runtime_callable(child_value, depth + 1):
				clean_array.append(child_value)
			elif not (child_value is Callable):
				clean_array.append(_without_runtime_callables(child_value, depth + 1))
		return clean_array
	if value is Dictionary:
		var clean_dictionary: Dictionary = {}
		for key_variant in (value as Dictionary).keys():
			var child_value: Variant = (value as Dictionary)[key_variant]
			if child_value is Callable:
				continue
			clean_dictionary[key_variant] = _without_runtime_callables(child_value, depth + 1) if _variant_contains_runtime_callable(child_value, depth + 1) else child_value
		return clean_dictionary
	return value


func _push_runtime_bindings(target: Object, context_node: Node, options: Dictionary) -> void:
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	elif context_node != null and context_node.is_inside_tree():
		tree = context_node.get_tree()
	var main_scene: Node = tree.current_scene if tree != null else null
	if main_scene == null and tree != null:
		main_scene = tree.root
	var workspace_node := _resolve_workspace_node(main_scene, context_node)
	var service_nodes := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var workspace_instance := BobuxInstance.new(workspace_node)
	var service_instances: Dictionary = {}
	for service_name_variant in service_nodes.keys():
		var service_name := str(service_name_variant)
		service_instances[service_name] = BobuxInstance.new(service_nodes[service_name])
	_ensure_run_service_events()
	var is_server := bool(options.get("is_server", str(options.get("realm", "")).to_lower() in ["server", "studio"]))
	var run_service := {
		"Heartbeat": _run_service_heartbeat,
		"Stepped": _run_service_stepped,
		"RenderStepped": _run_service_render_stepped,
		"IsServer": func(): return is_server,
		"IsClient": func(): return not is_server,
	}
	var tween_service := {
		"Create": func(arg1: Variant, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null):
			var item: Variant = arg2 if arg4 != null else arg1
			var target_properties: Variant = arg4 if arg4 != null else arg3
			return {
				"Play": func():
					if item is BobuxInstance and target_properties is Dictionary:
						for property_name in (target_properties as Dictionary).keys():
							(item as BobuxInstance)._set(str(property_name), target_properties[property_name])
			}
	}
	var debris_service := {
		"AddItem": func(arg1: Variant, arg2: Variant = null, arg3: Variant = null):
			var item: Variant = arg2 if arg2 is BobuxInstance else arg1
			var lifetime := float(arg3 if arg2 is BobuxInstance and arg3 != null else (arg2 if arg2 != null and not (arg2 is BobuxInstance) else 0.0))
			_schedule_debris_item(item, lifetime)
	}
	var game_proxy := {
		"Workspace": workspace_instance,
		"workspace": workspace_instance,
		"GetService": func(arg1: Variant, arg2: Variant = null):
			var service_name := str(arg2 if arg2 != null else arg1)
			match service_name:
				"Workspace": return workspace_instance
				"RunService": return run_service
				"TweenService": return tween_service
				"Debris": return debris_service
				_:
					if service_instances.has(service_name):
						return service_instances[service_name]
					return BobuxInstance.new(_ensure_single_roblox_service(main_scene, service_name, workspace_node))
	}
	for service_name_variant in service_instances.keys():
		game_proxy[str(service_name_variant)] = service_instances[service_name_variant]

	target.call("push_variant", "game", game_proxy)
	target.call("push_variant", "workspace", workspace_instance)
	target.call("push_variant", "Instance", BobuxInstanceCreator.new(workspace_node))
	target.call("push_variant", "Vector3", {"new": func(x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0): return Vector3(float(x), float(y), float(z))})
	target.call("push_variant", "Vector2", {"new": func(x: Variant = 0.0, y: Variant = 0.0): return Vector2(float(x), float(y))})
	target.call("push_variant", "Ray", {"new": func(origin: Variant = Vector3.ZERO, direction: Variant = Vector3.ZERO): return BobuxRay.new(origin, direction)})
	target.call("push_variant", "CFrame", _build_cframe_library())
	target.call("push_variant", "Color3", {
		"new": func(r: Variant = 1.0, g: Variant = 1.0, b: Variant = 1.0): return Color(float(r), float(g), float(b)),
		"fromRGB": func(r: Variant = 255.0, g: Variant = 255.0, b: Variant = 255.0): return Color(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0),
	})
	target.call("push_variant", "BrickColor", _build_brick_color_library())
	target.call("push_variant", "UDim", {"new": func(scale: Variant = 0.0, offset: Variant = 0.0): return {"scale": float(scale), "offset": float(offset)}})
	target.call("push_variant", "UDim2", {
		"new": func(xs: Variant = 0.0, xo: Variant = 0.0, ys: Variant = 0.0, yo: Variant = 0.0): return {"x": {"scale": float(xs), "offset": float(xo)}, "y": {"scale": float(ys), "offset": float(yo)}},
		"fromScale": func(x: Variant = 0.0, y: Variant = 0.0): return {"x": {"scale": float(x), "offset": 0.0}, "y": {"scale": float(y), "offset": 0.0}},
		"fromOffset": func(x: Variant = 0.0, y: Variant = 0.0): return {"x": {"scale": 0.0, "offset": float(x)}, "y": {"scale": 0.0, "offset": float(y)}},
	})
	target.call("push_variant", "TweenInfo", {"new": func(duration: Variant = 1.0, _style: Variant = null, _direction: Variant = null): return {"Time": float(duration)}})
	target.call("push_variant", "Enum", _build_enum_proxy())
	target.call("push_variant", "script", BobuxInstance.new(context_node))
	target.call("push_variant", "print", func(value: Variant = null): print("[LUA] ", value))
	target.call("push_variant", "warn", func(value: Variant = null): push_warning("[LUA] %s" % str(value)))
	target.call("push_variant", "tick", func(): return Time.get_ticks_msec() / 1000.0)
	target.call("push_variant", "require", func(module_variant: Variant): return _require_module(module_variant, context_node, options))
	target.call("push_variant", "__bobux_set", func(item: Variant, property_name: Variant, value: Variant):
		_last_property_setter_calls += 1
		_last_property_setter_target_type = type_string(typeof(item))
		if item is Object:
			_last_property_setter_target_class = (item as Object).get_class()
			_last_property_setter_has_set_property = (item as Object).has_method("SetProperty")
		if item is BobuxInstance:
			(item as BobuxInstance)._set(str(property_name), value)
		return value
	)


func _prepare_scheduled_lua_source(lua_code: String) -> String:
	var rewritten := _rewrite_lua_property_assignments(lua_code)
	rewritten = _rewrite_lua_multi_return_calls(rewritten)
	# Classic Roblox scripts used lowercase RBXScriptSignal:connect(). On a
	# RefCounted proxy that spelling otherwise resolves to Godot Object.connect
	# and attempts to connect a signal with an empty name.
	rewritten = rewritten.replace(":connect(", ":Connect(")
	rewritten = rewritten.replace(":disconnect(", ":Disconnect(")
	var prelude := """
local __bobux_raw_coroutine_yield = coroutine.yield
function wait(seconds)
    return __bobux_raw_coroutine_yield(tonumber(seconds) or 0.03)
end
task = task or {}
task.wait = wait
function spawn(callback, ...)
    if type(callback) == 'function' then return callback(...) end
end
task.spawn = spawn
task.defer = spawn
function delay(_seconds, callback, ...)
    if type(callback) == 'function' then return callback(...) end
end
task.delay = delay
local function __bobux_unpack_raycast(result)
    if result == nil then return nil, nil, nil, nil end
    return result[1], result[2], result[3], result[4]
end
function __bobux_find_part_on_ray(workspace_proxy, ray, ignore, terrain_cells_are_cubes)
    return __bobux_unpack_raycast(workspace_proxy:FindPartOnRayResult(ray, ignore, terrain_cells_are_cubes))
end
function __bobux_find_part_on_ray_with_ignore_list(workspace_proxy, ray, ignore, terrain_cells_are_cubes)
    return __bobux_unpack_raycast(workspace_proxy:FindPartOnRayWithIgnoreListResult(ray, ignore, terrain_cells_are_cubes))
end
"""
	return prelude + "\n" + rewritten


func _static_script_safety_error(lua_code: String) -> String:
	var compact := lua_code.to_lower()
	if compact.contains("while true do"):
		var has_yield := compact.contains("wait(") or compact.contains("task.wait(") or compact.contains(":wait(") or compact.contains("coroutine.yield(")
		if not has_yield:
			return "Script contains an unbounded loop without a cooperative wait/yield."
	return ""


func _lua_error_message(value: Variant) -> String:
	if value == null:
		return ""
	if value is Object and (value as Object).has_method("get_message"):
		return str((value as Object).call("get_message")).strip_edges()
	return ""


func _ensure_run_service_events() -> void:
	if not (_run_service_heartbeat is BobuxEvent):
		_run_service_heartbeat = BobuxEvent.new()
	if not (_run_service_stepped is BobuxEvent):
		_run_service_stepped = BobuxEvent.new()
	if not (_run_service_render_stepped is BobuxEvent):
		_run_service_render_stepped = BobuxEvent.new()


func _schedule_debris_item(item: Variant, lifetime: float) -> void:
	if not (item is BobuxInstance):
		return
	var wrapped := item as BobuxInstance
	if lifetime <= 0.0 or not is_inside_tree():
		wrapped.Destroy()
		return
	get_tree().create_timer(lifetime).timeout.connect(func():
		if wrapped != null:
			wrapped.Destroy()
	)


func _require_module(module_variant: Variant, context_node: Node, options: Dictionary) -> Variant:
	if not (module_variant is BobuxInstance):
		return module_variant
	var module := module_variant as BobuxInstance
	if not is_instance_valid(module.node):
		return null
	var cache_key := str(module.node.get_meta("roblox_ref", module.node.get_instance_id()))
	if _module_cache.has(cache_key):
		return _module_cache[cache_key]
	var source := str(module.node.get_meta("code", module.node.get_meta("lua_source", ""))).strip_edges()
	if source.is_empty():
		return null
	var lua = ClassDB.instantiate("LuaAPI")
	if lua.has_method("set_use_callables"):
		lua.set_use_callables(true)
	lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine", "utf8"]))
	var coroutine = lua.new_coroutine()
	_push_runtime_bindings(coroutine, module.node, options)
	var load_error = coroutine.load_string(_prepare_scheduled_lua_source(source))
	var load_message := _lua_error_message(load_error)
	if not load_message.is_empty():
		push_warning("[LuaScriptEngine] ModuleScript '%s' failed to load: %s" % [module.node.name, load_message])
		return null
	var module_runtime_id := _next_script_runtime_id
	_next_script_runtime_id += 1
	_configure_instruction_hook(coroutine, module_runtime_id)
	_runtime_resume_started_usec[module_runtime_id] = Time.get_ticks_usec()
	_runtime_budget_exceeded.erase(module_runtime_id)
	var result: Variant = coroutine.resume([])
	_runtime_resume_started_usec.erase(module_runtime_id)
	var error_message := _lua_error_message(result)
	if _runtime_budget_exceeded.has(module_runtime_id):
		error_message = "ModuleScript exceeded the %.1f ms execution budget without yielding." % [float(SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC) / 1000.0]
		_runtime_budget_exceeded.erase(module_runtime_id)
	if not error_message.is_empty():
		# A failed module may already have connected Lua callbacks. Retain its state
		# until Stop so those callbacks never reference a closed lua_State.
		_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
		push_warning("[LuaScriptEngine] ModuleScript '%s': %s" % [module.node.name, error_message])
		return null
	if not bool(coroutine.is_done()):
		_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
		push_warning("[LuaScriptEngine] ModuleScript '%s' yielded during require; asynchronous modules are not supported." % module.node.name)
		return null
	var value: Variant = (result as Array)[0] if result is Array and not (result as Array).is_empty() else null
	_module_cache[cache_key] = value
	_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
	return value

func install_roblox_manifest(manifest_variant: Variant, context_node: Node) -> Dictionary:
	if not (manifest_variant is Dictionary):
		return {"ok": false, "error": "Manifest is not a dictionary."}
	var manifest: Dictionary = manifest_variant
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	if tree == null and context_node != null and context_node.is_inside_tree():
		tree = context_node.get_tree()
	var main_scene: Node = tree.current_scene if tree != null else null
	if main_scene == null and context_node != null and context_node.is_inside_tree():
		main_scene = context_node.get_tree().root
	var workspace_node := _resolve_workspace_node(main_scene, context_node)
	var service_nodes := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var node_by_ref: Dictionary = {}
	_index_nodes_by_roblox_ref(workspace_node, node_by_ref)
	for service_node_variant in service_nodes.values():
		if service_node_variant is Node:
			_index_nodes_by_roblox_ref(service_node_variant as Node, node_by_ref)
	var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	for service_variant in services:
		if not (service_variant is Dictionary):
			continue
		var service: Dictionary = service_variant
		var ref := str(service.get("ref", "")).strip_edges()
		var service_name := str(service.get("name", service.get("class", ""))).strip_edges()
		if ref.is_empty() or service_name.is_empty():
			continue
		var service_node: Node = service_nodes.get(service_name, null) as Node
		if service_node == null:
			service_node = _ensure_single_roblox_service(main_scene, service_name, workspace_node)
		if service_node != null:
			service_node.set_meta("roblox_ref", ref)
			service_node.set_meta("roblox_class", str(service.get("class", service_name)))
			node_by_ref[ref] = service_node
	var entries: Array[Dictionary] = []
	_append_manifest_entries(entries, manifest.get("gui", []))
	_append_manifest_entries(entries, manifest.get("tools", []))
	_append_manifest_entries(entries, manifest.get("scripts", []))
	_append_manifest_entries(entries, manifest.get("storage_libraries", []))
	_append_manifest_entries(entries, manifest.get("instances", []))
	var unique_entries: Array[Dictionary] = []
	var seen_entry_refs: Dictionary = {}
	for entry in entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if not entry_ref.is_empty() and seen_entry_refs.has(entry_ref):
			continue
		if not entry_ref.is_empty():
			seen_entry_refs[entry_ref] = true
		unique_entries.append(entry)
	var pending := unique_entries.duplicate(true)
	var created := 0
	var pass_count := 0
	while not pending.is_empty() and pass_count < 32:
		var next_pending: Array[Dictionary] = []
		var progressed := false
		for entry in pending:
			var parent_node := _resolve_manifest_parent_node(entry, node_by_ref, service_nodes, main_scene)
			if parent_node == null:
				next_pending.append(entry)
				continue
			var ref := str(entry.get("ref", "")).strip_edges()
			if not ref.is_empty() and node_by_ref.has(ref):
				continue
			var node := _ensure_manifest_entry_node(parent_node, entry)
			if node != null:
				if not ref.is_empty():
					node_by_ref[ref] = node
				created += 1
				progressed = true
		if not progressed:
			break
		pending = next_pending
		pass_count += 1
	var reparented := _restore_manifest_hierarchy(manifest.get("hierarchy", []), node_by_ref)
	_ensure_local_player_nodes(
		service_nodes.get("Players", null),
		service_nodes.get("StarterGui", null),
		service_nodes.get("StarterPack", null),
		service_nodes.get("StarterPlayer", null)
	)
	return {
		"ok": true,
		"created": created,
		"pending": pending.size(),
		"reparented": reparented,
		"services": service_nodes.size()
	}

func install_roblox_manifest_async(manifest_variant: Variant, context_node: Node, batch_size: int = 384) -> Dictionary:
	if not (manifest_variant is Dictionary):
		return {"ok": false, "error": "Manifest is not a dictionary."}
	var manifest: Dictionary = manifest_variant
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	if tree == null and context_node != null and context_node.is_inside_tree():
		tree = context_node.get_tree()
	var main_scene: Node = tree.current_scene if tree != null else null
	if main_scene == null and context_node != null and context_node.is_inside_tree():
		main_scene = context_node.get_tree().root
	var workspace_node := _resolve_workspace_node(main_scene, context_node)
	var service_nodes := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var node_by_ref: Dictionary = {}
	_index_nodes_by_roblox_ref(workspace_node, node_by_ref)
	for service_node_variant in service_nodes.values():
		if service_node_variant is Node:
			_index_nodes_by_roblox_ref(service_node_variant as Node, node_by_ref)
	var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	for service_variant in services:
		if not (service_variant is Dictionary):
			continue
		var service: Dictionary = service_variant
		var ref := str(service.get("ref", "")).strip_edges()
		var service_name := str(service.get("name", service.get("class", ""))).strip_edges()
		if ref.is_empty() or service_name.is_empty():
			continue
		var service_node: Node = service_nodes.get(service_name, null) as Node
		if service_node == null:
			service_node = _ensure_single_roblox_service(main_scene, service_name, workspace_node)
		if service_node != null:
			service_node.set_meta("roblox_ref", ref)
			service_node.set_meta("roblox_class", str(service.get("class", service_name)))
			node_by_ref[ref] = service_node

	var entries: Array[Dictionary] = []
	_append_manifest_entries(entries, manifest.get("gui", []))
	_append_manifest_entries(entries, manifest.get("tools", []))
	_append_manifest_entries(entries, manifest.get("scripts", []))
	_append_manifest_entries(entries, manifest.get("storage_libraries", []))
	_append_manifest_entries(entries, manifest.get("instances", []))
	var unique_entries: Array[Dictionary] = []
	var seen_entry_refs: Dictionary = {}
	for entry in entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if not entry_ref.is_empty() and seen_entry_refs.has(entry_ref):
			continue
		if not entry_ref.is_empty():
			seen_entry_refs[entry_ref] = true
		unique_entries.append(entry)

	var pending := unique_entries.duplicate(true)
	var created := 0
	var pass_count := 0
	var processed_since_yield := 0
	var safe_batch_size := maxi(batch_size, 32)
	while not pending.is_empty() and pass_count < 32:
		var next_pending: Array[Dictionary] = []
		var progressed := false
		for entry in pending:
			var parent_node := _resolve_manifest_parent_node(entry, node_by_ref, service_nodes, main_scene)
			if parent_node == null:
				next_pending.append(entry)
			else:
				var ref := str(entry.get("ref", "")).strip_edges()
				if ref.is_empty() or not node_by_ref.has(ref):
					var node := _ensure_manifest_entry_node(parent_node, entry)
					if node != null:
						if not ref.is_empty():
							node_by_ref[ref] = node
						created += 1
						progressed = true
			processed_since_yield += 1
			if tree != null and processed_since_yield >= safe_batch_size:
				processed_since_yield = 0
				await tree.process_frame
		if not progressed:
			pending = next_pending
			break
		pending = next_pending
		pass_count += 1
	var hierarchy_result := await _restore_manifest_hierarchy_async(
		manifest.get("hierarchy", []), node_by_ref, tree, safe_batch_size
	)
	_ensure_local_player_nodes(service_nodes.get("Players", null), service_nodes.get("StarterGui", null), service_nodes.get("StarterPack", null), service_nodes.get("StarterPlayer", null))
	return {
		"ok": true,
		"created": created,
		"pending": pending.size(),
		"reparented": int(hierarchy_result.get("reparented", 0)),
		"services": service_nodes.size(),
		"batched": true,
	}

func _restore_manifest_hierarchy_async(raw_hierarchy: Variant, node_by_ref: Dictionary, tree: SceneTree,
		batch_size: int) -> Dictionary:
	if not (raw_hierarchy is Array):
		return {"reparented": 0}
	var reparented := 0
	var processed := 0
	for edge_variant in raw_hierarchy:
		if edge_variant is Dictionary:
			var edge := edge_variant as Dictionary
			var child_ref := str(edge.get("child", "")).strip_edges()
			var parent_ref := str(edge.get("parent", "")).strip_edges()
			if node_by_ref.has(child_ref) and node_by_ref.has(parent_ref):
				var child := node_by_ref[child_ref] as Node
				var parent := node_by_ref[parent_ref] as Node
				if child != null and parent != null and child != parent and child.get_parent() != parent and not child.is_ancestor_of(parent):
					child.reparent(parent, true)
					reparented += 1
		processed += 1
		if tree != null and processed >= batch_size:
			processed = 0
			await tree.process_frame
	return {"reparented": reparented}

func _restore_manifest_hierarchy(raw_hierarchy: Variant, node_by_ref: Dictionary) -> int:
	if not (raw_hierarchy is Array):
		return 0
	var reparented := 0
	for edge_variant in raw_hierarchy:
		if not (edge_variant is Dictionary):
			continue
		var edge := edge_variant as Dictionary
		var child_ref := str(edge.get("child", "")).strip_edges()
		var parent_ref := str(edge.get("parent", "")).strip_edges()
		if child_ref.is_empty() or parent_ref.is_empty():
			continue
		if not node_by_ref.has(child_ref) or not node_by_ref.has(parent_ref):
			continue
		var child := node_by_ref[child_ref] as Node
		var parent := node_by_ref[parent_ref] as Node
		if child == null or parent == null or child == parent or child.get_parent() == parent:
			continue
		if child.is_ancestor_of(parent):
			continue
		child.reparent(parent, true)
		reparented += 1
	return reparented

func _append_manifest_entries(out: Array[Dictionary], raw_entries: Variant) -> void:
	if not (raw_entries is Array):
		return
	for entry_variant in raw_entries:
		if entry_variant is Dictionary:
			out.append((entry_variant as Dictionary).duplicate(true))

func _resolve_manifest_parent_node(entry: Dictionary, node_by_ref: Dictionary, service_nodes: Dictionary, main_scene: Node) -> Node:
	var parent_ref := str(entry.get("parent_ref", "")).strip_edges()
	if not parent_ref.is_empty():
		if node_by_ref.has(parent_ref):
			return node_by_ref[parent_ref] as Node
		# Do not flatten children into a fallback service while their exact parent
		# is still waiting later in the manifest. The multi-pass installer will
		# retry after Model/Folder/Script/Tool dependencies are created.
		return null
	var service_name := str(entry.get("service_name", "")).strip_edges()
	if service_name.is_empty():
		service_name = str(entry.get("root_name", "")).strip_edges()
	if service_name.is_empty():
		service_name = str(entry.get("root_class", "")).strip_edges()
	if service_name.is_empty():
		service_name = _default_service_for_manifest_class(str(entry.get("class", "")))
	if service_nodes.has(service_name):
		return service_nodes[service_name] as Node
	if not service_name.is_empty():
		return _ensure_single_roblox_service(main_scene, service_name, service_nodes.get("Workspace", null))
	return null

func _default_service_for_manifest_class(roblox_class: String) -> String:
	if roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"]:
		return "StarterGui"
	if roblox_class == "Tool":
		return "StarterPack"
	if roblox_class in ["Script", "ModuleScript"]:
		return "ServerScriptService"
	if roblox_class == "LocalScript":
		return "StarterGui"
	return "ReplicatedStorage"

func _ensure_manifest_entry_node(parent_node: Node, entry: Dictionary) -> Node:
	if parent_node == null:
		return null
	var ref := str(entry.get("ref", "")).strip_edges()
	for child in parent_node.get_children():
		if not ref.is_empty() and str(child.get_meta("roblox_ref", "")).strip_edges() == ref:
			return child
	var clean_name := _safe_manifest_node_name(str(entry.get("name", entry.get("class", "Instance"))))
	var existing := parent_node.get_node_or_null(clean_name)
	if existing != null and (ref.is_empty() or str(existing.get_meta("roblox_ref", "")).is_empty()):
		_apply_manifest_entry_metadata(existing, entry)
		return existing
	var node := _create_manifest_entry_node(entry)
	node.name = clean_name
	_apply_manifest_entry_metadata(node, entry)
	parent_node.add_child(node)
	return node

func _create_manifest_entry_node(entry: Dictionary) -> Node:
	var roblox_class := str(entry.get("class", "Instance")).strip_edges()
	return RobloxDataModelClass.create_instance(roblox_class, str(entry.get("name", roblox_class)))

func _apply_manifest_entry_metadata(node: Node, entry: Dictionary) -> void:
	var roblox_class := str(entry.get("class", "Instance")).strip_edges()
	node.set_meta("roblox_ref", str(entry.get("ref", "")).strip_edges())
	node.set_meta("roblox_class", roblox_class)
	node.set_meta("Name", str(entry.get("name", node.name)).strip_edges())
	if entry.has("properties") and entry["properties"] is Dictionary:
		var properties := (entry["properties"] as Dictionary).duplicate(true)
		node.set_meta("roblox_properties", properties)
		if properties.has("Value"):
			node.set_meta("Value", properties.get("Value"))
		_apply_manifest_properties_to_node(node, properties)
	if entry.has("source"):
		node.add_to_group("bobux_scripts")
		node.add_to_group("imported_roblox_scripts")
		node.set_meta("script_type", roblox_class)
		node.set_meta("lua_source", str(entry.get("source", "")))
		node.set_meta("code", str(entry.get("source", "")))
		node.set_meta("disabled", bool(entry.get("disabled", false)))
	if entry.has("source_length"):
		node.set_meta("source_length", int(entry.get("source_length", 0)))
	if roblox_class in ["Tool", "HopperBin"]:
		node.add_to_group("roblox_tools")
		node.set_meta("inventory_source", true)
	if roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"]:
		node.add_to_group("roblox_gui_objects")
	if roblox_class in ["RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction"]:
		node.add_to_group("roblox_remotes")
	if roblox_class.ends_with("Value"):
		node.add_to_group("roblox_value_objects")


func _apply_manifest_properties_to_node(node: Node, properties: Dictionary) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		node_3d.position = _vector3_from_manifest_value(properties.get("BobuxPosition", properties.get("Position", [0.0, 0.0, 0.0])), node_3d.position)
		node_3d.rotation_degrees = _vector3_from_manifest_value(properties.get("BobuxRotation", properties.get("Rotation", [0.0, 0.0, 0.0])), node_3d.rotation_degrees)
		node_3d.scale = _vector3_from_manifest_value(properties.get("BobuxSize", properties.get("Size", [1.0, 1.0, 1.0])), node_3d.scale)
		if bool(properties.get("BobuxTemplateOnly", false)):
			node_3d.visible = false
	if node is MeshInstance3D:
		_apply_manifest_part_appearance(node as MeshInstance3D, properties)
	if node is Control:
		var control := node as Control
		var roblox_class := str(node.get_meta("roblox_class", ""))
		if roblox_class not in ["ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup"]:
			control.position = _udim2_offset_from_manifest(properties.get("Position", {}), control.position)
			control.size = _udim2_offset_from_manifest(properties.get("Size", {}), control.size)
		control.visible = bool(properties.get("Visible", properties.get("Enabled", true)))
		control.z_index = int(properties.get("ZIndex", 0))
		control.rotation_degrees = float(properties.get("Rotation", 0.0))
	if node is Label:
		(node as Label).text = str(properties.get("Text", ""))
	elif node is Button:
		(node as Button).text = str(properties.get("Text", node.name))
	elif node is LineEdit:
		(node as LineEdit).text = str(properties.get("Text", ""))


func _apply_manifest_part_appearance(mesh_instance: MeshInstance3D, properties: Dictionary) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
	else:
		material = material.duplicate() as StandardMaterial3D
	material.albedo_color = _color_from_manifest_value(
		properties.get("Color", properties.get("Color3", Color(0.64, 0.64, 0.64))),
		material.albedo_color
	)
	material.albedo_color.a = clampf(1.0 - float(properties.get("Transparency", 0.0)), 0.0, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if material.albedo_color.a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mesh_instance.material_override = material
	mesh_instance.set_meta("anchored", bool(properties.get("Anchored", true)))
	mesh_instance.set_meta("can_collide", bool(properties.get("CanCollide", true)))
	mesh_instance.set_meta("transparency", float(properties.get("Transparency", 0.0)))


func _color_from_manifest_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		var divisor := 255.0 if maxf(float(array[0]), maxf(float(array[1]), float(array[2]))) > 1.0 else 1.0
		return Color(float(array[0]) / divisor, float(array[1]) / divisor, float(array[2]) / divisor, fallback.a)
	if value is Dictionary:
		var data := value as Dictionary
		var red := float(data.get("r", data.get("R", fallback.r)))
		var green := float(data.get("g", data.get("G", fallback.g)))
		var blue := float(data.get("b", data.get("B", fallback.b)))
		var divisor := 255.0 if maxf(red, maxf(green, blue)) > 1.0 else 1.0
		return Color(red / divisor, green / divisor, blue / divisor, fallback.a)
	return fallback


func _vector3_from_manifest_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		if _is_manifest_number(array[0]) and _is_manifest_number(array[1]) and _is_manifest_number(array[2]):
			return Vector3(_manifest_float(array[0], fallback.x), _manifest_float(array[1], fallback.y), _manifest_float(array[2], fallback.z))
		return fallback
	if value is Dictionary:
		var data := value as Dictionary
		var x_value: Variant = data.get("x", data.get("X", fallback.x))
		var y_value: Variant = data.get("y", data.get("Y", fallback.y))
		var z_value: Variant = data.get("z", data.get("Z", fallback.z))
		if _is_manifest_number(x_value) and _is_manifest_number(y_value) and _is_manifest_number(z_value):
			return Vector3(_manifest_float(x_value, fallback.x), _manifest_float(y_value, fallback.y), _manifest_float(z_value, fallback.z))
	return fallback


func _is_manifest_number(value: Variant) -> bool:
	if value is int or value is float:
		return true
	return value is String and str(value).strip_edges().is_valid_float()


func _manifest_float(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	if value is String and str(value).strip_edges().is_valid_float():
		return str(value).to_float()
	return fallback


func _udim2_offset_from_manifest(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if not (value is Dictionary):
		return fallback
	var data := value as Dictionary
	var x_value: Variant = data.get("x", data.get("X", {}))
	var y_value: Variant = data.get("y", data.get("Y", {}))
	return Vector2(_udim_offset_component(x_value, fallback.x), _udim_offset_component(y_value, fallback.y))


func _udim_offset_component(value: Variant, fallback: float) -> float:
	if value is Dictionary:
		return float((value as Dictionary).get("offset", (value as Dictionary).get("Offset", fallback)))
	if value is Array and (value as Array).size() >= 2:
		return float(value[1])
	if value is float or value is int:
		return float(value)
	return fallback


func _index_nodes_by_roblox_ref(root_node: Node, out: Dictionary) -> void:
	if root_node == null:
		return
	var ref := str(root_node.get_meta("roblox_ref", "")).strip_edges()
	if not ref.is_empty():
		out[ref] = root_node
	for child in root_node.get_children():
		_index_nodes_by_roblox_ref(child, out)


func find_instance_by_ref(context_node: Node, roblox_ref: String) -> Node:
	var clean_ref := roblox_ref.strip_edges()
	if clean_ref.is_empty():
		return null
	var indexed: Dictionary = {}
	if context_node != null:
		_index_nodes_by_roblox_ref(context_node, indexed)
		var tree := context_node.get_tree() if context_node.is_inside_tree() else null
		if tree != null:
			var workspace_node := _resolve_workspace_node(tree.root, context_node)
			var data_model_root := _find_roblox_data_model_for_workspace(tree.root, workspace_node)
			if data_model_root == null:
				data_model_root = _find_roblox_data_model_root(tree.root)
			if data_model_root != null:
				_index_nodes_by_roblox_ref(data_model_root, indexed)
	return indexed.get(clean_ref, null) as Node


func bind_gui_controls(gui_root: Node, context_node: Node) -> Dictionary:
	if gui_root == null:
		return {"ok": false, "bound": 0}
	var indexed: Dictionary = {}
	if context_node != null:
		_index_nodes_by_roblox_ref(context_node, indexed)
	var tree := gui_root.get_tree() if gui_root.is_inside_tree() else null
	if tree != null:
		var workspace_node := _resolve_workspace_node(tree.root, context_node)
		var data_model_root := _find_roblox_data_model_for_workspace(tree.root, workspace_node)
		if data_model_root == null:
			data_model_root = _find_roblox_data_model_root(tree.root)
		if data_model_root != null:
			_index_nodes_by_roblox_ref(data_model_root, indexed)
			# Runtime LocalScripts execute against the PlayerGui clones, not the
			# StarterGui templates. Index the live tree last so duplicate Roblox refs
			# resolve to the same object that `script.Parent` sees.
			var players_service := data_model_root.get_node_or_null("Players")
			if players_service != null:
				var local_player := players_service.get_node_or_null("LocalPlayer")
				if local_player != null:
					var player_gui := local_player.get_node_or_null("PlayerGui")
					if player_gui != null:
						_index_nodes_by_roblox_ref(player_gui, indexed)
	var bound := _bind_gui_controls_recursive(gui_root, indexed)
	return {"ok": true, "bound": bound, "indexed": indexed.size(), "refs": indexed.keys()}


func _bind_gui_controls_recursive(node: Node, indexed: Dictionary) -> int:
	var bound := 0
	if node is BaseButton and not bool(node.get_meta("bobux_lua_event_bound", false)):
		var ref := str(node.get_meta("roblox_ref", "")).strip_edges()
		var target: Node = indexed.get(ref, null) as Node
		if target != null:
			var target_instance := BobuxInstance.new(target)
			var roblox_class := str(node.get_meta("roblox_class", target.get_meta("roblox_class", "")))
			node.set_meta("bobux_bound_target_path", str(target.get_path()))
			var control_instance_id := node.get_instance_id()
			var target_instance_id := target.get_instance_id()
			target_instance.Changed.Connect(target_instance.Changed, func(_property_name: Variant = null) -> void:
				call_deferred("_sync_bound_gui_control_by_id", control_instance_id, target_instance_id)
			)
			(node as BaseButton).pressed.connect(func():
				target_instance.Activated.Fire()
				if roblox_class in ["TextButton", "ImageButton"]:
					target_instance.MouseButton1Click.Fire()
				if roblox_class in ["Tool", "HopperBin"]:
					target_instance.Equipped.Fire()
			)
			node.set_meta("bobux_lua_event_bound", true)
			bound += 1
	for child in node.get_children():
		bound += _bind_gui_controls_recursive(child, indexed)
	return bound


func _sync_bound_gui_control_by_id(control_instance_id: int, target_instance_id: int) -> void:
	var control_object := instance_from_id(control_instance_id)
	var target_object := instance_from_id(target_instance_id)
	if control_object is Control and target_object is Node:
		_sync_bound_gui_control(control_object as Control, target_object as Node)


func _sync_bound_gui_control(control: Control, target: Node) -> void:
	if control == null or target == null or not is_instance_valid(control) or not is_instance_valid(target):
		return
	if control is Button:
		if target is Button:
			(control as Button).text = (target as Button).text
		elif target.has_meta("Text"):
			(control as Button).text = str(target.get_meta("Text"))
	elif control is Label:
		if target is Label:
			(control as Label).text = (target as Label).text
		elif target.has_meta("Text"):
			(control as Label).text = str(target.get_meta("Text"))
	elif control is LineEdit and target is LineEdit:
		(control as LineEdit).text = (target as LineEdit).text
	if target is Control:
		control.visible = (target as Control).visible
	if control is BaseButton and target is BaseButton:
		(control as BaseButton).disabled = (target as BaseButton).disabled

func _safe_manifest_node_name(raw_name: String) -> String:
	var clean := raw_name.strip_edges()
	if clean.is_empty():
		clean = "Instance"
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		clean = clean.replace(ch, "_")
	return clean

func _rewrite_lua_property_assignments(lua_code: String) -> String:
	var regex := RegEx.new()
	var compile_error := regex.compile("^([\\t ]*)([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)\\.(Name|Parent|Value|Position|Rotation|CFrame|Velocity|AssemblyLinearVelocity|Size|Anchored|CanCollide|Transparency|BrickColor|Color|Reflectance|TimeOfDay|ClockTime)\\s*=\\s*(?!=)(.+)$")
	if compile_error != OK:
		return lua_code
	var rewritten: Array[String] = []
	var pending_assignment_balance := 0
	for line in lua_code.split("\n"):
		if pending_assignment_balance > 0:
			var continuation := str(line)
			var continuation_comment := ""
			var continuation_comment_index := _find_lua_inline_comment(continuation)
			if continuation_comment_index >= 0:
				continuation_comment = continuation.substr(continuation_comment_index)
				continuation = continuation.substr(0, continuation_comment_index)
			pending_assignment_balance += _lua_delimiter_balance(continuation)
			if pending_assignment_balance <= 0:
				rewritten.append("%s)%s%s" % [
					continuation, " " if not continuation_comment.is_empty() else "", continuation_comment
				])
				pending_assignment_balance = 0
			else:
				rewritten.append(str(line))
			continue
		var stripped := line.strip_edges()
		if stripped.begins_with("--") or stripped.begins_with("local ") or stripped.begins_with("function "):
			rewritten.append(line)
			continue
		var match_result := regex.search(line)
		if match_result == null:
			rewritten.append(line)
			continue
		var indent := match_result.get_string(1)
		var target := match_result.get_string(2)
		var property_name := match_result.get_string(3)
		var value_expr := match_result.get_string(4)
		var comment := ""
		var comment_index := _find_lua_inline_comment(value_expr)
		if comment_index >= 0:
			comment = value_expr.substr(comment_index)
			value_expr = value_expr.substr(0, comment_index).strip_edges()
		var balance := _lua_delimiter_balance(value_expr)
		if balance > 0:
			rewritten.append('%s__bobux_set(%s, "%s", %s%s%s' % [
				indent, target, property_name, value_expr,
				" " if not comment.is_empty() else "", comment
			])
			pending_assignment_balance = balance
		else:
			rewritten.append('%s__bobux_set(%s, "%s", %s)%s%s' % [
				indent, target, property_name, value_expr,
				" " if not comment.is_empty() else "", comment
			])
	if pending_assignment_balance > 0 and not rewritten.is_empty():
		rewritten[rewritten.size() - 1] += ")"
	return "\n".join(rewritten)

func _rewrite_lua_multi_return_calls(lua_code: String) -> String:
	var rewritten := lua_code
	for workspace_expression in [
		'game:GetService("Workspace")',
		"game:GetService('Workspace')",
		"game.Workspace",
		"game.workspace",
		"workspace",
	]:
		rewritten = rewritten.replace(
			workspace_expression + ":FindPartOnRayWithIgnoreList(",
			"__bobux_find_part_on_ray_with_ignore_list(" + workspace_expression + ", "
		)
		rewritten = rewritten.replace(
			workspace_expression + ":FindPartOnRay(",
			"__bobux_find_part_on_ray(" + workspace_expression + ", "
		)
	var receiver_regex := RegEx.new()
	if receiver_regex.compile("([A-Za-z_][A-Za-z0-9_\\.]*)\\:FindPartOnRayWithIgnoreList\\s*\\(") == OK:
		rewritten = receiver_regex.sub(rewritten, "__bobux_find_part_on_ray_with_ignore_list($1, ", true)
	if receiver_regex.compile("([A-Za-z_][A-Za-z0-9_\\.]*)\\:FindPartOnRay\\s*\\(") == OK:
		rewritten = receiver_regex.sub(rewritten, "__bobux_find_part_on_ray($1, ", true)
	return rewritten

func _find_lua_inline_comment(text: String) -> int:
	var quote := ""
	var escaped := false
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if escaped:
			escaped = false
		elif character == "\\" and not quote.is_empty():
			escaped = true
		elif not quote.is_empty():
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "-" and index + 1 < text.length() and text.substr(index + 1, 1) == "-":
			return index
		index += 1
	return -1

func _lua_delimiter_balance(text: String) -> int:
	var balance := 0
	var quote := ""
	var escaped := false
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if escaped:
			escaped = false
		elif character == "\\" and not quote.is_empty():
			escaped = true
		elif not quote.is_empty():
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character in ["(", "[", "{"]:
			balance += 1
		elif character in [")", "]", "}"]:
			balance -= 1
		elif character == "-" and index + 1 < text.length() and text.substr(index + 1, 1) == "-":
			break
		index += 1
	return balance

func _resolve_workspace_node(main_scene: Node, context_node: Node) -> Node:
	var context_cursor := context_node
	while context_cursor != null:
		var cursor_class := str(context_cursor.get_meta("roblox_class", ""))
		if cursor_class == "Workspace" or str(context_cursor.name) in ["Blocks", "Workspace"]:
			return context_cursor
		if context_cursor.has_method("get_workspace"):
			var ancestor_workspace: Variant = context_cursor.call("get_workspace")
			if ancestor_workspace is Node and is_instance_valid(ancestor_workspace):
				return ancestor_workspace as Node
		context_cursor = context_cursor.get_parent()
	# Runtime scripts under ServerScriptService/StarterGui are siblings of the
	# Workspace alias. Resolve that alias from the DataModel before trying scene
	# paths or the script's immediate parent.
	var data_model := _find_roblox_data_model_root(main_scene)
	if data_model != null and data_model.has_method("get_workspace"):
		var model_workspace: Variant = data_model.call("get_workspace")
		if model_workspace is Node and is_instance_valid(model_workspace):
			return model_workspace as Node
	var candidates: Array[String] = [
		"SubViewportContainer/SubViewport/World3D/Blocks",
		"SubViewportContainer/SubViewport/World3D",
		"World",
		"Blocks"
	]
	if main_scene != null:
		for path in candidates:
			var node := main_scene.get_node_or_null(path)
			if node != null:
				return node
	if context_node != null and context_node.get_parent() != null:
		return context_node.get_parent()
	return main_scene

func _ensure_roblox_service_nodes(main_scene: Node, workspace_node: Node) -> Dictionary:
	var cache_key := workspace_node.get_instance_id() if workspace_node != null and is_instance_valid(workspace_node) else 0
	if cache_key != 0 and _service_nodes_cache.has(cache_key):
		var cached: Dictionary = _service_nodes_cache[cache_key]
		var cached_services: Dictionary = cached.get("services", {}) if cached.get("services", {}) is Dictionary else {}
		if _service_cache_is_valid(cached, workspace_node, cached_services):
			_ensure_local_player_nodes(cached_services.get("Players", null), cached_services.get("StarterGui", null), cached_services.get("StarterPack", null), cached_services.get("StarterPlayer", null))
			return cached_services
		_service_nodes_cache.erase(cache_key)

	var service_nodes: Dictionary = {}
	if workspace_node != null:
		service_nodes["Workspace"] = workspace_node
	var parent := main_scene if main_scene != null else self
	var root := _find_roblox_data_model_for_workspace(parent, workspace_node)
	if root == null and workspace_node == null:
		root = _find_roblox_data_model_root(parent)
	if root == null:
		root = RobloxDataModelClass.new()
		root.name = "RobloxDataModel"
		parent.add_child(root)
		if workspace_node is Node3D and root.has_method("register_workspace_alias"):
			root.call("register_workspace_alias", workspace_node)
	for service_name in RobloxDataModelClass.DEFAULT_SERVICES:
		if service_name == "Workspace":
			continue
		service_nodes[service_name] = _ensure_service_on_data_model(root, service_name)
	_ensure_local_player_nodes(service_nodes.get("Players", null), service_nodes.get("StarterGui", null), service_nodes.get("StarterPack", null), service_nodes.get("StarterPlayer", null))
	if cache_key != 0:
		_service_nodes_cache[cache_key] = {
			"workspace": workspace_node,
			"root": root,
			"services": service_nodes,
		}
	return service_nodes


func _service_cache_is_valid(cached: Dictionary, workspace_node: Node, services: Dictionary) -> bool:
	var cached_workspace: Node = cached.get("workspace", null) as Node
	var cached_root: Node = cached.get("root", null) as Node
	if cached_workspace != workspace_node or cached_root == null or not is_instance_valid(cached_root):
		return false
	for service_variant in services.values():
		if not (service_variant is Node) or not is_instance_valid(service_variant):
			return false
	return true


func _ensure_service_on_data_model(root: Node, service_name: String) -> Node:
	if root == null:
		return null
	if root.has_method("ensure_service"):
		var ensured: Variant = root.call("ensure_service", service_name)
		if ensured is Node:
			return ensured as Node
	var service := root.get_node_or_null(service_name)
	if service == null:
		service = Node.new()
		service.name = service_name
		service.set_meta("roblox_class", service_name)
		root.add_child(service)
	return service

func _ensure_single_roblox_service(main_scene: Node, service_name: String, workspace_node: Node = null) -> Node:
	if workspace_node != null and is_instance_valid(workspace_node):
		var cache_key := workspace_node.get_instance_id()
		if _service_nodes_cache.has(cache_key):
			var cached: Dictionary = _service_nodes_cache[cache_key]
			var cached_services: Dictionary = cached.get("services", {}) if cached.get("services", {}) is Dictionary else {}
			if _service_cache_is_valid(cached, workspace_node, cached_services) and cached_services.has(service_name):
				return cached_services[service_name] as Node
	var parent := main_scene
	if parent == null:
		parent = self
	var root := _find_roblox_data_model_for_workspace(parent, workspace_node)
	if root == null and workspace_node == null:
		root = _find_roblox_data_model_root(parent)
	if root == null:
		root = RobloxDataModelClass.new()
		root.name = "RobloxDataModel"
		parent.add_child(root)
		if workspace_node is Node3D and root.has_method("register_workspace_alias"):
			root.call("register_workspace_alias", workspace_node)
	return _ensure_service_on_data_model(root, service_name)

func _find_roblox_data_model_for_workspace(search_root: Node, workspace_node: Node) -> Node:
	if search_root == null or workspace_node == null:
		return null
	if search_root.has_method("get_workspace") and search_root.call("get_workspace") == workspace_node:
		return search_root
	for child in search_root.get_children():
		var matching := _find_roblox_data_model_for_workspace(child, workspace_node)
		if matching != null:
			return matching
	return null

func _find_roblox_data_model_root(parent: Node) -> Node:
	if parent == null:
		return null
	var direct := parent.get_node_or_null("RobloxDataModel")
	if direct != null:
		return direct
	return _find_descendant_named(parent, "RobloxDataModel")

func _find_descendant_named(node: Node, target_name: String) -> Node:
	for child in node.get_children():
		if str(child.name) == target_name:
			return child
		var nested := _find_descendant_named(child, target_name)
		if nested != null:
			return nested
	return null

func _ensure_local_player_nodes(players_service: Node, starter_gui: Node, starter_pack: Node, starter_player: Node = null) -> void:
	if players_service == null:
		return
	var local_player := players_service.get_node_or_null("LocalPlayer")
	if local_player == null:
		local_player = Node.new()
		local_player.name = "LocalPlayer"
		local_player.set_meta("roblox_class", "Player")
		local_player.set_meta("UserId", UserSession.user_id)
		local_player.set_meta("Name", UserSession.username if not UserSession.username.strip_edges().is_empty() else "Player")
		players_service.add_child(local_player)
		local_player.set_meta("bobux_runtime_generated", true)
	for child_name in ["Backpack", "PlayerGui", "PlayerScripts"]:
		if local_player.get_node_or_null(child_name) == null:
			var child := Node.new()
			child.name = child_name
			child.set_meta("roblox_class", child_name)
			child.set_meta("bobux_runtime_generated", true)
			local_player.add_child(child)
	if starter_gui != null:
		_clone_missing_children(starter_gui, local_player.get_node_or_null("PlayerGui"))
	if starter_pack != null:
		_clone_missing_inventory_children(
			starter_pack,
			local_player.get_node_or_null("Backpack"),
			_bound_character_for_player(local_player)
		)
	if starter_player != null:
		var starter_player_scripts := starter_player.get_node_or_null("StarterPlayerScripts")
		if starter_player_scripts != null:
			_clone_missing_children(starter_player_scripts, local_player.get_node_or_null("PlayerScripts"))

func bind_local_player_character(character_node: Node) -> void:
	if character_node == null or not is_instance_valid(character_node):
		return
	var main_scene: Node = get_tree().current_scene if is_inside_tree() else null
	if main_scene == null and character_node.is_inside_tree():
		main_scene = character_node.get_tree().root
	var workspace_node := _resolve_workspace_node(main_scene, character_node)
	var services := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var players_service: Node = services.get("Players", null)
	if players_service == null:
		return
	_ensure_local_player_nodes(players_service, services.get("StarterGui", null), services.get("StarterPack", null), services.get("StarterPlayer", null))
	var local_player := players_service.get_node_or_null("LocalPlayer")
	if local_player == null:
		return
	local_player.set_meta("bobux_character_instance_id", character_node.get_instance_id())
	character_node.set_meta("bobux_player_instance_id", local_player.get_instance_id())
	character_node.set_meta("roblox_class", "Model")
	character_node.set_meta("Name", "Character")
	var starter_player: Node = services.get("StarterPlayer", null)
	if starter_player != null:
		var starter_character_scripts := starter_player.get_node_or_null("StarterCharacterScripts")
		if starter_character_scripts != null:
			_clone_missing_children(starter_character_scripts, character_node)
	BobuxInstance.new(local_player)._shared_event("CharacterAdded").Fire(BobuxInstance.new(character_node))


func get_local_inventory_state(context_node: Node = null, character_override: Node = null) -> Dictionary:
	var main_scene: Node = get_tree().current_scene if is_inside_tree() else null
	if main_scene == null and context_node != null and is_instance_valid(context_node) and context_node.is_inside_tree():
		# Embedded Studio viewports and headless playtests may not own
		# SceneTree.current_scene. Search from the real tree root so we reuse the
		# Studio DataModel instead of silently creating a second empty one.
		main_scene = context_node.get_tree().root
	var workspace_node := _resolve_workspace_node(main_scene, context_node)
	var services := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var players_service: Node = services.get("Players", null)
	if players_service == null:
		return {}
	_ensure_local_player_nodes(players_service, services.get("StarterGui", null), services.get("StarterPack", null), services.get("StarterPlayer", null))
	var local_player := players_service.get_node_or_null("LocalPlayer")
	if local_player == null:
		return {}
	if character_override != null and is_instance_valid(character_override):
		local_player.set_meta("bobux_character_instance_id", character_override.get_instance_id())
		character_override.set_meta("bobux_player_instance_id", local_player.get_instance_id())
	var backpack := local_player.get_node_or_null("Backpack")
	var character := _bound_character_for_player(local_player)
	var backpack_tools: Array[Node] = _direct_tool_children(backpack)
	var equipped_tools: Array[Node] = _direct_tool_children(character)
	var tools: Array[Node] = []
	tools.append_array(equipped_tools)
	tools.append_array(backpack_tools)
	tools.sort_custom(func(a: Node, b: Node) -> bool:
		var a_order := int(a.get_meta("bobux_inventory_order", 1000000))
		var b_order := int(b.get_meta("bobux_inventory_order", 1000000))
		if a_order == b_order:
			return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
		return a_order < b_order
	)
	return {
		"local_player": local_player,
		"backpack": backpack,
		"character": character,
		"tools": tools,
		"backpack_tools": backpack_tools,
		"equipped_tools": equipped_tools,
		"equipped_tool": equipped_tools[0] if not equipped_tools.is_empty() else null,
	}


func equip_local_tool(tool_node: Node, context_node: Node = null, character_override: Node = null) -> bool:
	if not _is_tool_node(tool_node):
		return false
	var state := get_local_inventory_state(context_node, character_override)
	var backpack: Node = state.get("backpack", null)
	var character: Node = state.get("character", null)
	if backpack == null or character == null or not is_instance_valid(backpack) or not is_instance_valid(character):
		return false
	if tool_node.get_parent() == character:
		return true
	var equipped_tools: Array = state.get("equipped_tools", []) if state.get("equipped_tools", []) is Array else []
	for equipped_variant in equipped_tools:
		if equipped_variant is Node and equipped_variant != tool_node:
			unequip_local_tool(equipped_variant as Node, context_node)
	_reparent_inventory_node(tool_node, character)
	tool_node.set_meta("bobux_tool_equipped", true)
	tool_node.set_meta("bobux_equipped_character_id", character.get_instance_id())
	_set_inventory_tool_tree_visible(tool_node, true)
	_position_equipped_tool(tool_node)
	BobuxInstance.new(tool_node).Equipped.Fire(BobuxMouse.new())
	return true


func unequip_local_tool(tool_node: Node, context_node: Node = null) -> bool:
	if not _is_tool_node(tool_node):
		return false
	var state := get_local_inventory_state(context_node)
	var backpack: Node = state.get("backpack", null)
	if backpack == null or not is_instance_valid(backpack):
		return false
	if tool_node.get_parent() == backpack:
		_set_inventory_tool_tree_visible(tool_node, false)
		return true
	BobuxInstance.new(tool_node).Unequipped.Fire()
	_reparent_inventory_node(tool_node, backpack)
	tool_node.set_meta("bobux_tool_equipped", false)
	tool_node.remove_meta("bobux_equipped_character_id")
	_set_inventory_tool_tree_visible(tool_node, false)
	return true


func unequip_all_local_tools(context_node: Node = null) -> int:
	var state := get_local_inventory_state(context_node)
	var equipped_tools: Array = state.get("equipped_tools", []) if state.get("equipped_tools", []) is Array else []
	var changed := 0
	for tool_variant in equipped_tools.duplicate():
		if tool_variant is Node and unequip_local_tool(tool_variant as Node, context_node):
			changed += 1
	return changed


func activate_local_tool(tool_node: Node, context_node: Node = null) -> bool:
	if not _is_tool_node(tool_node):
		return false
	var state := get_local_inventory_state(context_node)
	var character: Node = state.get("character", null)
	if character == null or tool_node.get_parent() != character:
		return false
	BobuxInstance.new(tool_node).Activated.Fire()
	return true

func unbind_local_player_character(character_node: Node = null) -> void:
	var main_scene: Node = get_tree().current_scene if is_inside_tree() else null
	if main_scene == null and character_node != null and is_instance_valid(character_node) and character_node.is_inside_tree():
		main_scene = character_node.get_tree().root
	var workspace_node := _resolve_workspace_node(main_scene, character_node)
	var services := _ensure_roblox_service_nodes(main_scene, workspace_node)
	var players_service: Node = services.get("Players", null)
	if players_service == null:
		return
	var local_player := players_service.get_node_or_null("LocalPlayer")
	if local_player == null:
		return
	var bound_id := int(local_player.get_meta("bobux_character_instance_id", 0))
	if character_node == null or not is_instance_valid(character_node) or bound_id == character_node.get_instance_id():
		local_player.remove_meta("bobux_character_instance_id")

func notify_part_touched(touched_part: Node, hit_part: Node) -> void:
	if touched_part == null or hit_part == null or not is_instance_valid(touched_part) or not is_instance_valid(hit_part):
		return
	BobuxInstance.new(touched_part).Touched.Fire(BobuxInstance.new(hit_part))

func _clone_missing_children(source: Node, target: Node) -> void:
	if source == null or target == null:
		return
	var next_order := target.get_child_count()
	for child in source.get_children():
		if _is_tool_node(child):
			_set_inventory_tool_tree_visible(child, false)
		var existing := target.get_node_or_null(str(child.name))
		if existing != null:
			if _runtime_clone_matches_source(existing, child):
				continue
			# Starter containers are editable templates. A runtime clone with the
			# same name but another stable ref belongs to an older template
			# revision and must not shadow the current GUI/script tree.
			target.remove_child(existing)
			existing.free()
		var clone := child.duplicate()
		_copy_runtime_template_metadata_tree(child, clone)
		clone.set_meta("bobux_runtime_generated", true)
		clone.set_meta("bobux_inventory_order", next_order)
		target.add_child(clone)
		if _is_tool_node(clone):
			_set_inventory_tool_tree_visible(clone, false)
		next_order += 1


func _runtime_clone_matches_source(runtime_clone: Node, source: Node) -> bool:
	if runtime_clone == null or source == null:
		return false
	var source_ref := str(source.get_meta("roblox_ref", "")).strip_edges()
	var runtime_ref := str(runtime_clone.get_meta("roblox_ref", "")).strip_edges()
	if not source_ref.is_empty() or not runtime_ref.is_empty():
		return source_ref == runtime_ref
	var source_class := str(source.get_meta("roblox_class", source.get_class())).strip_edges()
	var runtime_class := str(runtime_clone.get_meta("roblox_class", runtime_clone.get_class())).strip_edges()
	return str(runtime_clone.name) == str(source.name) and runtime_class == source_class


func _copy_runtime_template_metadata_tree(source: Node, runtime_clone: Node) -> void:
	if source == null or runtime_clone == null:
		return
	for key_variant in source.get_meta_list():
		var key := str(key_variant)
		var value: Variant = source.get_meta(key_variant)
		if value is Dictionary:
			value = (value as Dictionary).duplicate(true)
		elif value is Array:
			value = (value as Array).duplicate(true)
		runtime_clone.set_meta(key, value)
	var child_count := mini(source.get_child_count(), runtime_clone.get_child_count())
	for child_index in range(child_count):
		_copy_runtime_template_metadata_tree(source.get_child(child_index), runtime_clone.get_child(child_index))


func _clone_missing_inventory_children(source: Node, backpack: Node, character: Node) -> void:
	if source == null or backpack == null:
		return
	var next_order := backpack.get_child_count()
	for child in source.get_children():
		if not _is_tool_node(child):
			continue
		_set_inventory_tool_tree_visible(child, false)
		if _find_matching_inventory_child(backpack, child) != null or _find_matching_inventory_child(character, child) != null:
			continue
		var clone := child.duplicate()
		_copy_runtime_template_metadata_tree(child, clone)
		clone.set_meta("bobux_runtime_generated", true)
		clone.set_meta("bobux_inventory_order", next_order)
		backpack.add_child(clone)
		_set_inventory_tool_tree_visible(clone, false)
		next_order += 1


func _find_matching_inventory_child(parent_node: Node, source_tool: Node) -> Node:
	if parent_node == null or source_tool == null:
		return null
	var source_ref := str(source_tool.get_meta("roblox_ref", "")).strip_edges()
	for child in parent_node.get_children():
		if not _is_tool_node(child):
			continue
		var child_ref := str(child.get_meta("roblox_ref", "")).strip_edges()
		if not source_ref.is_empty() and child_ref == source_ref:
			return child
		if source_ref.is_empty() and str(child.name) == str(source_tool.name):
			return child
	return null


func _bound_character_for_player(local_player: Node) -> Node:
	if local_player == null or not is_instance_valid(local_player):
		return null
	var character_id := int(local_player.get_meta("bobux_character_instance_id", 0))
	if character_id > 0:
		var character_variant := instance_from_id(character_id)
		if character_variant is Node and is_instance_valid(character_variant):
			return character_variant as Node
	return local_player.get_node_or_null("Character")


func _direct_tool_children(parent_node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if parent_node == null or not is_instance_valid(parent_node):
		return result
	for child in parent_node.get_children():
		if _is_tool_node(child):
			result.append(child)
	return result


func _is_tool_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return str(node.get_meta("roblox_class", "")) in ["Tool", "HopperBin"] or node.is_in_group("roblox_tools")


func _reparent_inventory_node(node: Node, new_parent: Node) -> void:
	if node == null or new_parent == null or node.get_parent() == new_parent:
		return
	if node.is_inside_tree() and new_parent.is_inside_tree():
		node.reparent(new_parent, false)
	else:
		var previous_parent := node.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(node)
		new_parent.add_child(node)


func _set_inventory_tool_tree_visible(root_node: Node, visible_in_world: bool) -> void:
	if root_node == null or not is_instance_valid(root_node):
		return
	if root_node is Node3D:
		(root_node as Node3D).visible = visible_in_world
	root_node.set_meta("BobuxTemplateOnly", not visible_in_world)
	for child in root_node.get_children():
		_set_inventory_tool_tree_visible(child, visible_in_world)


func _position_equipped_tool(tool_node: Node) -> void:
	if not (tool_node is Node3D):
		return
	var tool_root := tool_node as Node3D
	tool_root.transform = Transform3D.IDENTITY
	var properties: Dictionary = tool_node.get_meta("roblox_properties", {}) if tool_node.get_meta("roblox_properties", {}) is Dictionary else {}
	var grip_position := _vector3_from_manifest_value(properties.get("GripPos", properties.get("GripPosition", Vector3.ZERO)), Vector3.ZERO)
	var target_position := Vector3(1.55, 2.72, -0.62) + grip_position * 0.5
	var handle := _find_tool_handle(tool_node)
	if handle != null and handle != tool_root:
		tool_root.position = target_position - handle.position
	else:
		tool_root.position = target_position
	var grip_forward := _vector3_from_manifest_value(properties.get("GripForward", Vector3(0.0, 0.0, -1.0)), Vector3(0.0, 0.0, -1.0))
	if grip_forward.length_squared() > 0.001:
		tool_root.rotation.y = atan2(grip_forward.x, -grip_forward.z)


func _find_tool_handle(root_node: Node) -> Node3D:
	if root_node == null:
		return null
	for child in root_node.get_children():
		if child is Node3D and (str(child.name).nocasecmp_to("Handle") == 0 or str(child.get_meta("Name", "")).nocasecmp_to("Handle") == 0):
			return child as Node3D
		var nested := _find_tool_handle(child)
		if nested != null:
			return nested
	return null


func _build_cframe_library() -> Dictionary:
	return {
		"new": Callable(self, "_create_cframe"),
		"Angles": Callable(self, "_create_cframe_angles"),
		"fromEulerAnglesXYZ": Callable(self, "_create_cframe_angles"),
		"fromEulerAnglesYXZ": Callable(self, "_create_cframe_angles_yxz"),
		"fromMatrix": Callable(self, "_create_cframe_from_matrix"),
		"lookAt": Callable(self, "_create_cframe_look_at"),
	}


func _create_cframe(
	x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0,
	r00: Variant = null, r01: Variant = null, r02: Variant = null,
	r10: Variant = null, r11: Variant = null, r12: Variant = null,
	r20: Variant = null, r21: Variant = null, r22: Variant = null
) -> BobuxCFrame:
	var basis := Basis.IDENTITY
	if r00 != null and r01 != null and r02 != null and r10 != null and r11 != null and r12 != null and r20 != null and r21 != null and r22 != null:
		# Roblox provides a row-major rotation matrix; Godot Basis stores columns.
		basis = Basis(
			Vector3(float(r00), float(r10), float(r20)),
			Vector3(float(r01), float(r11), float(r21)),
			Vector3(float(r02), float(r12), float(r22))
		)
	return BobuxCFrame.new(Transform3D(basis, Vector3(float(x), float(y), float(z))))


func _create_cframe_angles(x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0) -> BobuxCFrame:
	return BobuxCFrame.new(Transform3D(Basis.from_euler(Vector3(float(x), float(y), float(z)), EULER_ORDER_XYZ), Vector3.ZERO))


func _create_cframe_angles_yxz(x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0) -> BobuxCFrame:
	return BobuxCFrame.new(Transform3D(Basis.from_euler(Vector3(float(x), float(y), float(z)), EULER_ORDER_YXZ), Vector3.ZERO))


func _create_cframe_from_matrix(
	position: Variant = Vector3.ZERO,
	right: Variant = Vector3.RIGHT,
	up: Variant = Vector3.UP,
	back: Variant = Vector3.BACK
) -> BobuxCFrame:
	var origin := position as Vector3 if position is Vector3 else Vector3.ZERO
	var basis := Basis(
		right as Vector3 if right is Vector3 else Vector3.RIGHT,
		up as Vector3 if up is Vector3 else Vector3.UP,
		back as Vector3 if back is Vector3 else Vector3.BACK
	)
	return BobuxCFrame.new(Transform3D(basis, origin))


func _create_cframe_look_at(
	position: Variant = Vector3.ZERO,
	target: Variant = Vector3.FORWARD,
	up: Variant = Vector3.UP
) -> BobuxCFrame:
	var origin := position as Vector3 if position is Vector3 else Vector3.ZERO
	var target_position := target as Vector3 if target is Vector3 else Vector3.FORWARD
	var up_vector := up as Vector3 if up is Vector3 else Vector3.UP
	if origin.is_equal_approx(target_position):
		return BobuxCFrame.new(Transform3D(Basis.IDENTITY, origin))
	return BobuxCFrame.new(Transform3D(Basis.IDENTITY, origin).looking_at(target_position, up_vector))


func _brick_color_from_variant(value: Variant) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges().to_lower()
	match text:
		"really red", "bright red", "red":
			return Color(1.0, 0.0, 0.0)
		"bright blue", "blue":
			return Color(0.0, 0.25, 1.0)
		"bright green", "green":
			return Color(0.0, 0.8, 0.15)
		"black":
			return Color.BLACK
		"white":
			return Color.WHITE
		"medium stone grey", "grey", "gray":
			return Color(0.55, 0.56, 0.58)
		_:
			return Color.WHITE


func _build_brick_color_library() -> Dictionary:
	return {
		"new": func(value: Variant = "White"): return _brick_color_from_variant(value),
		"Red": func(): return _brick_color_from_variant("Bright red"),
		"Blue": func(): return _brick_color_from_variant("Bright blue"),
	}

func _build_enum_proxy() -> Dictionary:
	return {
		"Material": {
			"Plastic": 256,
			"Wood": 512,
			"Slate": 800,
			"Concrete": 816,
			"Metal": 1088,
			"Neon": 288,
			"Glass": 1568
		},
		"PartType": {
			"Ball": 0,
			"Block": 1,
			"Cylinder": 2
		},
		"NormalId": {
			"Right": 0,
			"Top": 1,
			"Back": 2,
			"Left": 3,
			"Bottom": 4,
			"Front": 5
		}
	}
