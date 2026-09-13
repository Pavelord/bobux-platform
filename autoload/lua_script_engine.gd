extends Node

# LuaScriptEngine.gd - Autoload for in-game Lua scripting

const RobloxDataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")
const RobloxInputBridge = preload("res://addons/roblox_studio/roblox_input_bridge.gd")
signal script_message(context: Node, message: String, is_error: bool)

var _lua: Variant = null
var is_active: bool = false
var _last_property_setter_calls: int = 0
var _last_property_setter_target_type: String = ""
var _last_property_setter_target_class: String = ""
var _last_property_setter_has_set_property: bool = false
var _script_runtimes: Dictionary = {}
var _retained_lua_states: Dictionary = {}
var _module_cache: Dictionary = {}
var _module_loading: Dictionary = {}
var _module_cycle_warnings: Dictionary = {}
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
var _runtime_native_spans: Dictionary = {}
var _runtime_budget_exceeded: Dictionary = {}
var _service_nodes_cache: Dictionary = {}
var _task_runtime_ids: Dictionary = {}
var _task_scheduler_cursor: int = 0
var _runtime_tweens: Array = []

const SCRIPT_MEMORY_LIMIT_BYTES := 32 * 1024 * 1024
const MAX_CONCURRENT_SCRIPTS := 2048
const MAX_SCRIPT_SOURCE_BYTES := 2 * 1024 * 1024
const SCRIPT_RESUME_BUDGET_PER_FRAME := 8
const SCRIPT_RESUME_TIME_BUDGET_USEC := 3000
# Creating a Lua state and binding the Roblox compatibility library is one
# indivisible operation. On large imported places two starts in one frame can
# exceed 120 ms even though the time budget is checked between starts.
const SCRIPT_COMPILE_BUDGET_PER_FRAME := 1
const SCRIPT_COMPILE_TIME_BUDGET_USEC := 4000
const SCRIPT_INSTRUCTION_HOOK_INTERVAL := 2500
# A hard runaway watchdog is separate from the small shared frame budget.
# Native Instance traversal/resource creation can legitimately exceed 4.5 ms.
const SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC := 50000
const SCRIPT_EVENT_CALLBACK_BUDGET_PER_FRAME := 8
const SCRIPT_EVENT_TIME_BUDGET_USEC := 1500
# LuaAPI values are state-bound. Deeply nesting separate Lua states through
# require() can overflow/crash the native extension before its instruction hook
# gets control back. Until modules execute inside their caller's Lua state, only
# one state-bound module may be active; nested graphs fail closed instead of
# taking down Studio or the game client.
const MAX_MODULE_REQUIRE_DEPTH := 1
const LUA_HOOK_MASK_COUNT := 8

class BobuxEvent extends RefCounted:
	var connections: Array = []
	var _budget_cursor: int = 0
	func Connect(callback_or_self: Variant, callback: Variant = null) -> Variant:
		if callback == null and not (callback_or_self is BobuxEvent):
			callback = callback_or_self
		var connection := BobuxConnection.new()
		connection.event_ref = weakref(self)
		connection.callback = callback
		connection.Connected = callback != null
		if connection.Connected:
			connections.append(connection)
		return connection
	func Once(callback_or_self: Variant, callback: Variant = null) -> Variant:
		if callback == null and not (callback_or_self is BobuxEvent):
			callback = callback_or_self
		var connection: BobuxConnection = Connect(callback)
		connection.once = true
		return connection
	func Disconnect(_self_arg: Variant = null) -> void:
		for connection in connections:
			if connection is BobuxConnection:
				connection.Connected = false
				connection.callback = null
				connection.event_ref = null
		connections.clear()
	func Wait(_self_arg: Variant = null) -> Variant:
		return null
	func Fire(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		var args := []
		if arg1 != null: args.append(arg1)
		if arg2 != null: args.append(arg2)
		if arg3 != null: args.append(arg3)
		FireArgs(args)

	func FireArgs(args: Array) -> void:
		for connection in connections.duplicate():
			_invoke_connection(connection, args)

	func FireBudgeted(max_callbacks: int, deadline_usec: int, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> int:
		var snapshot := connections.duplicate()
		if snapshot.is_empty() or max_callbacks <= 0:
			_budget_cursor = 0
			return 0
		var args := []
		if arg1 != null: args.append(arg1)
		if arg2 != null: args.append(arg2)
		if arg3 != null: args.append(arg3)
		var start_index := _budget_cursor % snapshot.size()
		var inspected := 0
		var invoked := 0
		while inspected < snapshot.size() and invoked < max_callbacks:
			var connection: Variant = snapshot[(start_index + inspected) % snapshot.size()]
			inspected += 1
			_invoke_connection(connection, args)
			invoked += 1
			if Time.get_ticks_usec() >= deadline_usec:
				break
		_budget_cursor = (start_index + inspected) % maxi(snapshot.size(), 1)
		return invoked

	func _invoke_connection(connection: Variant, args: Array) -> void:
		if connection is BobuxConnection:
			if not connection.Connected:
				return
			var callback: Variant = connection.callback
			if connection.once:
				connection.Disconnect()
			_invoke_connection(callback, args)
			return
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


class BobuxConnection extends RefCounted:
	var Connected: bool = false
	var callback: Variant = null
	var event_ref: WeakRef = null
	var once: bool = false
	func Disconnect(_self_arg: Variant = null) -> void:
		Connected = false
		var event: Variant = event_ref.get_ref() if event_ref != null else null
		if event != null:
			event.connections.erase(self)
		event_ref = null
		callback = null

class BobuxTween extends RefCounted:
	var Completed := BobuxEvent.new()
	var PlaybackState: int = 0
	var engine: Node
	var target: BobuxInstance
	var info: Dictionary
	var goals: Dictionary
	var animation: Tween

	func Play(_self_arg: Variant = null) -> void:
		if animation != null and animation.is_valid() and PlaybackState == 3:
			animation.play()
			PlaybackState = 2
			return
		if PlaybackState == 2 or not is_instance_valid(target.node) or not is_instance_valid(engine):
			return
		animation = engine.create_tween().bind_node(target.node)
		var duration := maxf(float(info.get("Time", 1.0)), 0.0)
		var delay_time := maxf(float(info.get("DelayTime", 0.0)), 0.0)
		if delay_time > 0.0:
			animation.tween_interval(delay_time)
		var styles := [Tween.TRANS_LINEAR, Tween.TRANS_SINE, Tween.TRANS_BACK, Tween.TRANS_QUAD, Tween.TRANS_QUART, Tween.TRANS_QUINT, Tween.TRANS_BOUNCE, Tween.TRANS_ELASTIC, Tween.TRANS_EXPO, Tween.TRANS_CIRC, Tween.TRANS_CUBIC]
		animation.set_trans(styles[clampi(int(info.get("EasingStyle", 0)), 0, styles.size() - 1)])
		animation.set_ease([Tween.EASE_IN, Tween.EASE_OUT, Tween.EASE_IN_OUT][clampi(int(info.get("EasingDirection", 1)), 0, 2)])
		var starts := {}
		for key in goals:
			starts[key] = target._get(str(key))
		animation.tween_method(_apply_fraction.bind(starts, goals), 0.0, 1.0, duration)
		if bool(info.get("Reverses", false)):
			animation.tween_method(_apply_fraction.bind(goals, starts), 0.0, 1.0, duration)
		var repeats := int(info.get("RepeatCount", 0))
		animation.set_loops(0 if repeats < 0 else repeats + 1)
		animation.finished.connect(_on_finished)
		PlaybackState = 2

	func _apply_fraction(fraction: float, starts: Dictionary, ends: Dictionary) -> void:
		if not is_instance_valid(target.node):
			return
		for key in ends:
			var first: Variant = starts.get(key)
			var last: Variant = ends[key]
			if first is BobuxCFrame and last is BobuxCFrame:
				target._set(str(key), first.Lerp(last, fraction))
			elif (first is float or first is int) and (last is float or last is int):
				target._set(str(key), lerpf(float(first), float(last), fraction))
			elif (first is Vector3 and last is Vector3) or (first is Color and last is Color) or (first is Vector2 and last is Vector2):
				target._set(str(key), first.lerp(last, fraction))
			elif fraction >= 1.0:
				target._set(str(key), last)

	func Pause(_self_arg: Variant = null) -> void:
		if animation != null and animation.is_valid() and PlaybackState == 2:
			animation.pause()
			PlaybackState = 3

	func Cancel(_self_arg: Variant = null) -> void:
		if animation != null and animation.is_valid():
			animation.kill()
		PlaybackState = 5
		Completed.Fire(PlaybackState)

	func _on_finished() -> void:
		PlaybackState = 4
		Completed.Fire(PlaybackState)

	func dispose() -> void:
		Completed.Disconnect()
		if animation != null and animation.is_valid():
			animation.kill()
		animation = null


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
		var other: Variant = maybe_other if (self_or_other is Object and self_or_other == self) else self_or_other
		return __mul(null, other)

	func ToObjectSpace(self_or_other: Variant, maybe_other: Variant = null) -> Variant:
		var other: Variant = maybe_other if (self_or_other is Object and self_or_other == self) else self_or_other
		return Inverse().__mul(null, other)

	func toWorldSpace(self_or_other: Variant, maybe_other: Variant = null) -> Variant:
		return ToWorldSpace(self_or_other, maybe_other)

	func toObjectSpace(self_or_other: Variant, maybe_other: Variant = null) -> Variant:
		return ToObjectSpace(self_or_other, maybe_other)

	func PointToWorldSpace(self_or_point: Variant, maybe_point: Variant = null) -> Variant:
		var point: Variant = maybe_point if (self_or_point is Object and self_or_point == self) else self_or_point
		return transform * point if point is Vector3 else null

	func PointToObjectSpace(self_or_point: Variant, maybe_point: Variant = null) -> Variant:
		var point: Variant = maybe_point if (self_or_point is Object and self_or_point == self) else self_or_point
		return transform.affine_inverse() * point if point is Vector3 else null

	func VectorToWorldSpace(self_or_vector: Variant, maybe_vector: Variant = null) -> Variant:
		var vector: Variant = maybe_vector if (self_or_vector is Object and self_or_vector == self) else self_or_vector
		return transform.basis * vector if vector is Vector3 else null

	func VectorToObjectSpace(self_or_vector: Variant, maybe_vector: Variant = null) -> Variant:
		var vector: Variant = maybe_vector if (self_or_vector is Object and self_or_vector == self) else self_or_vector
		return transform.basis.inverse() * vector if vector is Vector3 else null

	func Lerp(self_or_goal: Variant, goal_or_alpha: Variant = null, maybe_alpha: Variant = null) -> BobuxCFrame:
		var goal: Variant = goal_or_alpha if (self_or_goal is Object and self_or_goal == self) else self_or_goal
		var alpha: float = float(maybe_alpha if (self_or_goal is Object and self_or_goal == self) else goal_or_alpha)
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
		Speed = float(maybe_speed if (self_or_speed is Object and self_or_speed == self) else self_or_speed)

	func AdjustWeight(self_or_weight: Variant = 1.0, maybe_weight: Variant = null, _fade_time: Variant = 0.1) -> void:
		WeightCurrent = float(maybe_weight if (self_or_weight is Object and self_or_weight == self) else self_or_weight)


class BobuxRay extends RefCounted:
	var Origin: Vector3 = Vector3.ZERO
	var Direction: Vector3 = Vector3.ZERO

	func _init(origin: Variant = Vector3.ZERO, direction: Variant = Vector3.ZERO) -> void:
		Origin = origin as Vector3 if origin is Vector3 else Vector3.ZERO
		Direction = direction as Vector3 if direction is Vector3 else Vector3.ZERO


class BobuxRaycastParams extends RefCounted:
	var FilterDescendantsInstances: Array = []
	var FilterType: int = 0
	var IgnoreWater: bool = false
	var CollisionGroup: String = "Default"
	var RespectCanCollide: bool = false
	var BruteForceAllSlow: bool = false

class BobuxOverlapParams extends BobuxRaycastParams:
	var MaxParts: int = 0
	var Tolerance: float = 0


class BobuxMouse extends RefCounted:
	var _player: Node
	var Hit: BobuxCFrame:
		get: return BobuxCFrame.new(Transform3D(Basis.IDENTITY, _sample()[1]))
	var Target: Variant:
		get: return _sample()[0]
	var X: float:
		get: return _position().x
	var Y: float:
		get: return _position().y
	var Button1Down: BobuxEvent
	var Button1Up: BobuxEvent
	var KeyDown: BobuxEvent
	var KeyUp: BobuxEvent
	func _init(player: Node = null) -> void:
		_player = player
		var instance := BobuxInstance.wrap(player)
		Button1Down = instance._shared_event("Mouse_Button1Down")
		Button1Up = instance._shared_event("Mouse_Button1Up")
		KeyDown = instance._shared_event("Mouse_KeyDown")
		KeyUp = instance._shared_event("Mouse_KeyUp")
	func _viewport() -> Viewport:
		if not is_instance_valid(_player): return null
		var character := BobuxInstance.wrap(_player)._bound_character()
		return character.get_viewport() if is_instance_valid(character) else _player.get_viewport()
	func _position() -> Vector2:
		var viewport := _viewport()
		if viewport != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return viewport.get_visible_rect().size * 0.5
		if viewport != null and viewport.has_meta("bobux_pointer_position"):
			return viewport.get_meta("bobux_pointer_position")
		return viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	func _sample() -> Array:
		var viewport := _viewport()
		var camera := viewport.get_camera_3d() if viewport != null else null
		if camera == null: return [null, Vector3.ZERO]
		var owner := BobuxInstance.wrap(_player)
		var character := owner._bound_character()
		var instance := BobuxInstance.wrap(character if character != null else _player)
		var origin := camera.project_ray_origin(_position())
		var direction := camera.project_ray_normal(_position()) * 1000
		return instance._perform_roblox_raycast(BobuxRay.new(instance._godot_point_to_roblox(origin), instance._godot_point_to_roblox(direction)), owner.Character)


class BobuxRandom extends RefCounted:
	var _generator := RandomNumberGenerator.new()

	func _init(seed_value: Variant = null) -> void:
		if seed_value != null and (seed_value is int or seed_value is float):
			_generator.seed = int(seed_value)
		else:
			_generator.randomize()

	func NextNumber(self_or_minimum: Variant = 0.0, minimum_or_maximum: Variant = 1.0, maybe_maximum: Variant = null) -> float:
		var minimum := 0.0
		var maximum := 1.0
		if (self_or_minimum is Object and self_or_minimum == self):
			minimum = float(minimum_or_maximum) if minimum_or_maximum != null else 0.0
			maximum = float(maybe_maximum) if maybe_maximum != null else 1.0
		else:
			minimum = float(self_or_minimum)
			maximum = float(minimum_or_maximum) if minimum_or_maximum != null else 1.0
		if maximum < minimum:
			var swap := minimum
			minimum = maximum
			maximum = swap
		return _generator.randf_range(minimum, maximum)

	func NextInteger(self_or_minimum: Variant = 0, minimum_or_maximum: Variant = 1, maybe_maximum: Variant = null) -> int:
		var minimum := 0
		var maximum := 1
		if (self_or_minimum is Object and self_or_minimum == self):
			minimum = int(minimum_or_maximum) if minimum_or_maximum != null else 0
			maximum = int(maybe_maximum) if maybe_maximum != null else 1
		else:
			minimum = int(self_or_minimum)
			maximum = int(minimum_or_maximum) if minimum_or_maximum != null else 1
		if maximum < minimum:
			var swap := minimum
			minimum = maximum
			maximum = swap
		return _generator.randi_range(minimum, maximum)

	func Clone(_self_arg: Variant = null) -> BobuxRandom:
		return BobuxRandom.new(_generator.seed)


class BobuxDataStorePages extends RefCounted:
	var IsFinished: bool = true
	var _items: Array = []
	var _page_size: int = 50
	var _cursor: int = 0

	func _init(items: Array, page_size: int = 50) -> void:
		_items = items.duplicate(true)
		_page_size = maxi(page_size, 1)
		_update_finished()

	func GetCurrentPage(_self_arg: Variant = null) -> Array:
		var end := mini(_cursor + _page_size, _items.size())
		return _items.slice(_cursor, end)

	func AdvanceToNextPageAsync(_self_arg: Variant = null) -> void:
		_cursor = mini(_cursor + _page_size, _items.size())
		_update_finished()

	func _update_finished() -> void:
		IsFinished = _cursor + _page_size >= _items.size()


class BobuxDataStore extends RefCounted:
	var service_node: Node
	var store_name: String
	var ordered: bool = false

	func _init(owner: Node, name_value: String, is_ordered: bool = false) -> void:
		service_node = owner
		store_name = name_value.strip_edges() if not name_value.strip_edges().is_empty() else "Default"
		ordered = is_ordered

	func _bucket_key() -> String:
		return ("ordered:" if ordered else "standard:") + store_name

	func _read_bucket() -> Dictionary:
		if not is_instance_valid(service_node):
			return {}
		var stores: Dictionary = service_node.get_meta("_bobux_data_store_values", {}) if service_node.get_meta("_bobux_data_store_values", {}) is Dictionary else {}
		var bucket: Variant = stores.get(_bucket_key(), {})
		return (bucket as Dictionary).duplicate(true) if bucket is Dictionary else {}

	func _write_bucket(bucket: Dictionary) -> void:
		if not is_instance_valid(service_node):
			return
		var stores: Dictionary = service_node.get_meta("_bobux_data_store_values", {}) if service_node.get_meta("_bobux_data_store_values", {}) is Dictionary else {}
		stores = stores.duplicate(true)
		stores[_bucket_key()] = bucket.duplicate(true)
		service_node.set_meta("_bobux_data_store_values", stores)

	func GetAsync(key_or_self: Variant, maybe_key: Variant = null) -> Variant:
		var key := str(maybe_key if (key_or_self is Object and key_or_self == self) else key_or_self)
		return _read_bucket().get(key, null)

	func SetAsync(key_or_self: Variant, key_or_value: Variant = null, maybe_value: Variant = null) -> void:
		var key := str(key_or_value if (key_or_self is Object and key_or_self == self) else key_or_self)
		var value: Variant = maybe_value if (key_or_self is Object and key_or_self == self) else key_or_value
		var bucket := _read_bucket()
		bucket[key] = value
		_write_bucket(bucket)

	func RemoveAsync(key_or_self: Variant, maybe_key: Variant = null) -> Variant:
		var key := str(maybe_key if (key_or_self is Object and key_or_self == self) else key_or_self)
		var bucket := _read_bucket()
		var previous: Variant = bucket.get(key, null)
		bucket.erase(key)
		_write_bucket(bucket)
		return previous

	func IncrementAsync(key_or_self: Variant, key_or_amount: Variant = 1, maybe_amount: Variant = null) -> Variant:
		var key := str(key_or_amount if (key_or_self is Object and key_or_self == self) else key_or_self)
		var amount: Variant = maybe_amount if (key_or_self is Object and key_or_self == self) else key_or_amount
		var bucket := _read_bucket()
		var value := float(bucket.get(key, 0.0)) + float(amount if amount != null else 1.0)
		bucket[key] = value
		_write_bucket(bucket)
		return value

	func UpdateAsync(key_or_self: Variant, key_or_callback: Variant = null, maybe_callback: Variant = null) -> Variant:
		var key := str(key_or_callback if (key_or_self is Object and key_or_self == self) else key_or_self)
		var callback: Variant = maybe_callback if (key_or_self is Object and key_or_self == self) else key_or_callback
		var bucket := _read_bucket()
		var previous: Variant = bucket.get(key, null)
		var updated: Variant = previous
		if callback is Callable:
			updated = (callback as Callable).call(previous)
		elif callback is Object and (callback as Object).has_method("call"):
			updated = (callback as Object).call("call", previous)
		if updated != null and updated is Object and (updated as Object).has_method("has_error") and bool((updated as Object).call("has_error")):
			return previous
		if updated == null:
			bucket.erase(key)
		else:
			bucket[key] = updated
		_write_bucket(bucket)
		return updated

	func GetSortedAsync(self_or_ascending: Variant = true, ascending_or_page_size: Variant = 50, page_size_or_minimum: Variant = null, minimum_or_maximum: Variant = null, maybe_maximum: Variant = null) -> BobuxDataStorePages:
		var ascending := true
		var page_size := 50
		var minimum: Variant = null
		var maximum: Variant = null
		if (self_or_ascending is Object and self_or_ascending == self):
			ascending = bool(ascending_or_page_size)
			page_size = int(page_size_or_minimum) if page_size_or_minimum != null else 50
			minimum = minimum_or_maximum
			maximum = maybe_maximum
		else:
			ascending = bool(self_or_ascending)
			page_size = int(ascending_or_page_size) if ascending_or_page_size != null else 50
			minimum = page_size_or_minimum
			maximum = minimum_or_maximum
		var bucket := _read_bucket()
		var items: Array = []
		for key_variant in bucket.keys():
			var value: Variant = bucket[key_variant]
			if minimum != null and float(value) < float(minimum):
				continue
			if maximum != null and float(value) > float(maximum):
				continue
			items.append({"key": str(key_variant), "value": value})
		items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.get("value", 0.0)) < float(right.get("value", 0.0)) if ascending else float(left.get("value", 0.0)) > float(right.get("value", 0.0))
		)
		return BobuxDataStorePages.new(items, page_size)


class BobuxInstance extends RefCounted:
	const DEFAULT_ROBLOX_STUD_SCALE: float = 0.5
	const STUDIO_WORLD_COLLISION_MASK: int = 1 | 2 | 4 | 16 | 64
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

	static func wrap(n: Node) -> BobuxInstance:
		if not is_instance_valid(n): return null
		var cached: Variant = n.get_meta("_bobux_instance_wrapper") if n.has_meta("_bobux_instance_wrapper") else null
		# Node owns the wrapper; wrapper's Node field is non-refcounted. Keep one
		# stable identity instead of rebuilding all event adapters on every read.
		if cached is BobuxInstance: return cached
		var wrapper := BobuxInstance.new(n)
		n.set_meta("_bobux_instance_wrapper", wrapper)
		return wrapper

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
		PlayerAdded = _shared_event("PlayerAdded")
		PlayerRemoving = _shared_event("PlayerRemoving")
		_ensure_node_signal_bridge()

	func __eq(_lua: Variant, other: Variant) -> bool:
		return other is BobuxInstance and is_instance_valid(node) and node == other.node

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
		var bridges: Array = []
		if node.has_signal("body_entered"):
			bridges.append({"signal": "body_entered", "callback": _on_body_entered})
		if node.has_signal("child_entered_tree"):
			bridges.append({"signal": "child_entered_tree", "callback": _on_child_entered_tree})
		if node.has_signal("child_exiting_tree"):
			bridges.append({"signal": "child_exiting_tree", "callback": _on_child_exiting_tree})
		if node is BaseButton:
			bridges.append({"signal": "pressed", "callback": _on_button_pressed})
		for bridge in bridges:
			node.connect(bridge.signal, bridge.callback)
		node.set_meta("_bobux_signal_callbacks", bridges)

	func _on_child_entered_tree(child: Node) -> void:
		if _is_native_helper(child): return
		if not ChildAdded.connections.is_empty():
			ChildAdded.Fire(BobuxInstance.wrap(child))

	func _on_child_exiting_tree(child: Node) -> void:
		if _is_native_helper(child): return
		if not ChildRemoved.connections.is_empty():
			ChildRemoved.Fire(BobuxInstance.wrap(child))

	func _on_button_pressed() -> void:
		Activated.Fire()
		MouseButton1Click.Fire()

	func _on_body_entered(body: Node) -> void:
		var hit_part = body
		if body.name == "CollisionBody" or body.name == "SelectionBody":
			hit_part = body.get_parent()
		Touched.Fire(BobuxInstance.wrap(hit_part))

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
		var native_start := Time.get_ticks_usec()
		var result: Variant = _get_impl(property)
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return result

	func _get_impl(property: StringName) -> Variant:
		if not is_instance_valid(node):
			return null
		var prop_str := str(property)
		if prop_str in [
			"Button1Down", "Button1Up", "KeyDown", "KeyUp", "MouseButton1Down",
			"MouseButton1Up", "MouseEnter", "MouseLeave", "MouseClick", "Died",
			"Selected", "Deselected", "Deactivated", "InputBegan", "InputChanged",
			"InputEnded", "DeviceRotationChanged", "CharacterAdded", "Move", "Seated",
			"JumpRequest", "StateChanged", "Jumping", "FreeFalling", "DescendantAdded", "DescendantRemoving", "TouchMoved",
			"MoveToFinished", "HealthChanged", "StateEnabledChanged",
			"TouchStarted", "TouchEnded", "Hit", "Running", "Triggered",
			"TriggerEnded", "PromptShown", "PromptHidden", "PromptTriggered",
			"PromptButtonHoldBegan", "PromptButtonHoldEnded",
			"PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished",
			"PromptPurchaseFinished", "PromptBundlePurchaseFinished"
		]:
			return _shared_event(prop_str)
		match prop_str:
			"CurrentCamera":
				var camera := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
				return BobuxInstance.wrap(camera) if camera != null else null
			"C0", "C1", "Transform", "WorldPivot":
				var raw: Variant = _stored_reference(prop_str)
				if raw is BobuxCFrame: return raw
				if raw is Dictionary:
					var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
					return BobuxCFrame.new(_godot_transform_to_roblox(importer._cframe_to_transform(raw, _stud_scale())))
				return BobuxCFrame.new()
			"PrimaryPart", "Part0", "Part1", "Attachment0", "Attachment1", "Adornee", "RespawnLocation", "Team":
				var stored: Variant = _stored_reference(prop_str)
				return _resolve_instance_reference(stored)
			"KeyboardEnabled", "MouseEnabled":
				return not OS.has_feature("mobile")
			"TouchEnabled":
				return DisplayServer.is_touchscreen_available()
			"Name":
				return str(node.get_meta("Name", node.get_meta("block_name", node.name)))
			"ClassName", "className":
				return str(node.get_meta("roblox_class", node.get_meta("shape_type", node.get_class())))
			"userId":
				return _get(&"UserId")
			"Disabled":
				return bool(node.get_meta("disabled", node.get_meta("roblox_properties", {}).get("Disabled", false)))
			"Source":
				return str(node.get_meta("code", node.get_meta("lua_source", "")))
			"DataReady":
				return str(node.get_meta("roblox_class", "")) == "Player"
			"AbsoluteSize":
				return node.size if node is Control else Vector2.ZERO
			"AbsolutePosition":
				return node.global_position if node is Control else Vector2.ZERO
			"Parent":
				var p := node.get_parent()
				return BobuxInstance.wrap(p) if p else null
			"Value":
				if str(node.get_meta("roblox_class", "")) == "ObjectValue":
					return _resolve_instance_reference(_stored_reference("Value"))
				if node.has_meta("Value"):
					return node.get_meta("Value")
				return node.get_meta("value") if node.has_meta("value") else null
			"Position":
				if node is Node3D:
					var godot_position := (node as Node3D).global_position if node.is_inside_tree() else (node as Node3D).position
					return _godot_point_to_roblox(godot_position)
				if node is Control:
					return (node as Control).position
			"Rotation":
				if node is Node3D:
					var roblox_basis := _godot_transform_to_roblox(Transform3D((node as Node3D).basis, Vector3.ZERO)).basis
					return roblox_basis.get_euler(EULER_ORDER_XYZ) * (180.0 / PI)
			"CFrame":
				if node is Node3D:
					var frame: Transform3D = (node as Node3D).global_transform if node.is_inside_tree() else (node as Node3D).transform
					frame.basis = frame.basis.orthonormalized()
					return BobuxCFrame.new(_godot_transform_to_roblox(frame))
			"Velocity", "AssemblyLinearVelocity":
				if bool(node.get_meta("bobux_character_part_proxy", false)):
					var assembly := _character_body()
					if assembly != null:
						return _godot_velocity_to_roblox(assembly.velocity)
				if node is CharacterBody3D:
					return _godot_velocity_to_roblox((node as CharacterBody3D).velocity)
				if node is RigidBody3D:
					return _godot_velocity_to_roblox((node as RigidBody3D).linear_velocity)
				var physics_body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(node)
				if physics_body != null:
					return _godot_velocity_to_roblox(physics_body.linear_velocity)
				var stored_velocity: Variant = node.get_meta("velocity", Vector3.ZERO)
				return _godot_velocity_to_roblox(stored_velocity as Vector3) if stored_velocity is Vector3 else Vector3.ZERO
			"Size":
				if node is GPUParticles3D: return node.get_meta("Size", 5.0)
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
				if node is GPUParticles3D:
					return (node as GPUParticles3D).emitting
				if node is Light3D:
					return (node as Light3D).visible
				if node is AudioStreamPlayer3D:
					return (node as AudioStreamPlayer3D).playing
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
				if node is GPUParticles3D:
					var particle_material := (node as GPUParticles3D).process_material as ParticleProcessMaterial
					if particle_material != null:
						return particle_material.color
				if node is MeshInstance3D:
					var mat := node.get_active_material(0) as StandardMaterial3D
					if mat:
						return mat.albedo_color
				return Color.WHITE
			"LocalPlayer":
				var local_player := node.get_node_or_null("LocalPlayer")
				return BobuxInstance.wrap(local_player) if local_player else null
			"Backpack", "PlayerGui":
				var named_child := node.get_node_or_null(prop_str)
				return BobuxInstance.wrap(named_child) if named_child else null
			"Character":
				var character := _bound_character()
				return BobuxInstance.wrap(character) if character else null
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
			"JumpHeight":
				return node.get_meta("JumpHeight", 7.2)
			"UseJumpPower":
				return node.get_meta("UseJumpPower", true)
			"Jump":
				return node.get_meta("Jump", false)
			"PlatformStand", "Sit", "AutoRotate":
				if prop_str == "Sit" and str(node.get_meta("roblox_class", "")) in ["Seat", "VehicleSeat"]:
					return Callable(self, "_seat_sit")
				return node.get_meta(prop_str, false if prop_str != "AutoRotate" else true)
			"TimeOfDay":
				return node.get_meta("TimeOfDay", "14:00:00")
			"ClockTime":
				return node.get_meta("ClockTime", 14.0)
			_:
				var direct_child := node.get_node_or_null(prop_str)
				if direct_child != null:
					return BobuxInstance.wrap(direct_child)
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

	func _resolve_instance_reference(value: Variant) -> BobuxInstance:
		if value is BobuxInstance: return value if is_instance_valid(value.node) else null
		if value is Node: return BobuxInstance.wrap(value) if is_instance_valid(value) else null
		if value == null or str(value) in ["", "-1", "<null>"]: return null
		var ref := str(int(value)) if value is float else str(value)
		var cursor := node
		while cursor != null:
			var refs: Dictionary = cursor.get_meta("_bobux_clone_refs", {})
			if refs.has(ref):
				var target: Variant = instance_from_id(int(refs[ref]))
				return BobuxInstance.wrap(target) if is_instance_valid(target) else null
			cursor = cursor.get_parent()
		if node.is_inside_tree():
			var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
			var target: Node = engine.find_instance_by_ref(node, ref) if engine != null else null
			if target != null: return BobuxInstance.wrap(target)
		return null

	func _stored_reference(key: String) -> Variant:
		return node.get_meta(key) if node.has_meta(key) else node.get_meta("roblox_properties", {}).get(key)

	func _set(property: StringName, value: Variant) -> bool:
		var native_start := Time.get_ticks_usec()
		var result: bool = _set_impl(property, value)
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return result

	func _set_impl(property: StringName, value: Variant) -> bool:
		if not is_instance_valid(node):
			return false
		var prop_str := str(property)
		var previous: Variant = _get(property)
		if typeof(previous) == typeof(value) and typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]:
			if previous == value:
				return true
		match prop_str:
			"Source":
				node.set_meta("code", str(value))
				node.set_meta("lua_source", str(value))
				return true
			"Disabled":
				node.set_meta("disabled", bool(value))
				var script_properties: Dictionary = node.get_meta("roblox_properties", {})
				script_properties["Disabled"] = bool(value)
				node.set_meta("roblox_properties", script_properties)
				_notify_property_changed("Disabled")
				return true
			"Name":
				node.set_meta("Name", str(value))
				node.set_meta("block_name", str(value))
				node.name = str(value)
				_notify_property_changed("Name")
				return true
			"Team":
				var team := _node_from_instance_variant(value)
				if team != null and str(team.get_meta("roblox_class", "")) != "Team": return false
				var old_team: Variant = _resolve_instance_reference(_stored_reference("Team"))
				node.set_meta("Team", value)
				node.set_meta("Neutral", team == null)
				if team != null: node.set_meta("TeamColor", team.get_meta("TeamColor", team.get_meta("roblox_properties", {}).get("TeamColor", 194)))
				if old_team is BobuxInstance: old_team.PlayerRemoving.Fire(BobuxInstance.wrap(node))
				if team != null: BobuxInstance.wrap(team).PlayerAdded.Fire(BobuxInstance.wrap(node))
				_notify_property_changed(prop_str)
				return true
			"Parent":
				var native_start := Time.get_ticks_usec()
				var engine: Node = Engine.get_main_loop().root.get_node_or_null("LuaScriptEngine")
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
					AncestryChanged.Fire(BobuxInstance.wrap(node), value)
					_notify_property_changed("Parent")
					if engine != null: engine._exclude_native_work(native_start)
					return true
			"Value":
				node.set_meta("value", value)
				node.set_meta("Value", value)
				_notify_property_changed("Value")
				return true
			"Position":
				if node is Node3D and value is Vector3:
					var target_position := _roblox_point_to_godot(value as Vector3)
					if bool(node.get_meta("bobux_character_part_proxy", false)):
						var proxy_body := _character_body()
						if proxy_body != null:
							var destination := proxy_body.global_position + target_position - (node as Node3D).global_position
							if proxy_body.has_method("set_lua_position"): proxy_body.set_lua_position(destination)
							else: proxy_body.global_position = destination
					else:
						if node.is_inside_tree():
							(node as Node3D).global_position = target_position
						else:
							(node as Node3D).position = target_position
					_notify_property_changed("Position")
					return true
				if node is Control:
					var position_properties: Dictionary = node.get_meta("roblox_properties", {})
					position_properties["Position"] = value
					node.set_meta("roblox_properties", position_properties)
					preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")._apply_udim2_layout(node, position_properties)
					_notify_property_changed("Position")
					return true
			"Rotation":
				if node is Node3D and value is Vector3:
					var roblox_rotation := Basis.from_euler((value as Vector3) * (PI / 180.0), EULER_ORDER_XYZ)
					(node as Node3D).basis = _roblox_transform_to_godot(Transform3D(roblox_rotation, Vector3.ZERO)).basis
					_notify_property_changed("Rotation")
					return true
			"CFrame":
				if node is Node3D:
					if value is BobuxCFrame:
						var target_frame := _roblox_transform_to_godot((value as BobuxCFrame).transform)
						if bool(node.get_meta("bobux_character_part_proxy", false)):
							var cframe_body := _character_body()
							if cframe_body != null:
								var destination := cframe_body.global_position + target_frame.origin - (node as Node3D).global_position
								if cframe_body.has_method("set_lua_position"): cframe_body.set_lua_position(destination)
								else: cframe_body.global_position = destination
								cframe_body.global_basis = target_frame.basis.orthonormalized().scaled(cframe_body.global_basis.get_scale())
						else:
							if node.is_inside_tree():
								target_frame.basis = target_frame.basis.scaled((node as Node3D).global_basis.get_scale())
								(node as Node3D).global_transform = target_frame
							else:
								target_frame.basis = target_frame.basis.scaled((node as Node3D).scale)
								(node as Node3D).transform = target_frame
						_notify_property_changed("CFrame")
						return true
					if value is Transform3D:
						node.transform = value
						_notify_property_changed("CFrame")
						return true
					if value is Vector3:
						(node as Node3D).position = _roblox_point_to_godot(value as Vector3)
						_notify_property_changed("CFrame")
						return true
			"RotVelocity", "AssemblyAngularVelocity":
				if value is Vector3:
					node.set_meta("RotVelocity", value)
					if _queue_assembly_motion(Vector3(-value.x, -value.y, value.z), "angular"): return true
					var body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(node, true)
					if body != null: body.angular_velocity = Vector3(-value.x, -value.y, value.z)
					_notify_property_changed(prop_str)
					return true
			"Velocity", "AssemblyLinearVelocity":
				if value is Vector3:
					var godot_velocity := _roblox_velocity_to_godot(value as Vector3)
					node.set_meta("velocity", godot_velocity)
					if _queue_assembly_motion(godot_velocity, "velocity"): return true
					var assembly := _character_body() if bool(node.get_meta("bobux_character_part_proxy", false)) or node is CharacterBody3D else null
					if assembly != null and assembly.has_method("set_lua_linear_velocity"):
						assembly.call("set_lua_linear_velocity", godot_velocity)
					elif node is CharacterBody3D:
						(node as CharacterBody3D).velocity = godot_velocity
					elif node is RigidBody3D:
						(node as RigidBody3D).linear_velocity = godot_velocity
					elif node is MeshInstance3D:
						var physics_body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(node, true)
						if physics_body != null:
							physics_body.linear_velocity = godot_velocity
					_notify_property_changed(prop_str)
					return true
			"Size":
				if node is GPUParticles3D and (value is float or value is int):
					node.set_meta("Size", float(value))
					var mesh: Mesh = node.draw_pass_1
					if mesh is QuadMesh:
						mesh = mesh.duplicate()
						mesh.size = Vector2.ONE * maxf(float(value) * _stud_scale() * 0.35, 0.01)
						node.draw_pass_1 = mesh
					return true
				if node is Control:
					var properties: Dictionary = node.get_meta("roblox_properties", {})
					properties["Size"] = value
					node.set_meta("roblox_properties", properties)
					preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")._apply_udim2_layout(node, properties)
					_notify_property_changed("Size")
					return true
				if node is Node3D and value is Vector3:
					(node as Node3D).scale = (value as Vector3).abs() * _stud_scale()
					_notify_property_changed("Size")
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
				_notify_property_changed("Text")
				return true
			"Visible":
				if node is Control:
					(node as Control).visible = bool(value)
					node.set_meta("Visible", bool(value))
					_notify_property_changed("Visible")
					return true
			"Enabled":
				if node is BaseButton:
					(node as BaseButton).disabled = not bool(value)
				elif node is Control:
					(node as Control).visible = bool(value)
				elif node is GPUParticles3D:
					(node as GPUParticles3D).emitting = bool(value)
				elif node is Light3D:
					(node as Light3D).visible = bool(value)
				elif node is AudioStreamPlayer3D:
					if bool(value):
						(node as AudioStreamPlayer3D).play()
					else:
						(node as AudioStreamPlayer3D).stop()
				else:
					return false
				node.set_meta("Enabled", bool(value))
				_notify_property_changed("Enabled")
				return true
			"Health":
				var health_body := _character_body()
				var target_health := maxf(0.0, float(value))
				if health_body != null:
					if health_body.has_method("set_health"):
						health_body.call("set_health", target_health)
				node.set_meta("Health", target_health)
				_notify_property_changed("Health")
				return true
			"MaxHealth":
				node.set_meta("MaxHealth", maxf(1.0, float(value)))
				_notify_property_changed("MaxHealth")
				return true
			"WalkSpeed":
				var walk_body := _character_body()
				if walk_body != null:
					if walk_body.has_method("set_humanoid_walk_speed"):
						walk_body.call("set_humanoid_walk_speed", maxf(0.0, float(value)))
					else:
						walk_body.set("move_speed", maxf(0.0, float(value)))
				node.set_meta("WalkSpeed", float(value))
				_notify_property_changed("WalkSpeed")
				return true
			"JumpPower":
				var jump_body := _character_body()
				if jump_body != null:
					if jump_body.has_method("set_humanoid_jump_power"):
						jump_body.call("set_humanoid_jump_power", maxf(0.0, float(value)))
					else:
						jump_body.set("jump_velocity_setting", maxf(0.0, float(value)))
				node.set_meta("JumpPower", float(value))
				_notify_property_changed("JumpPower")
				return true
			"JumpHeight", "UseJumpPower":
				node.set_meta(prop_str, bool(value) if prop_str == "UseJumpPower" else maxf(0, float(value)))
				_notify_property_changed(prop_str)
				return true
			"Jump":
				node.set_meta("Jump", bool(value))
				if bool(value):
					ChangeState(3)
				_notify_property_changed(prop_str)
				return true
			"PlatformStand", "Sit", "AutoRotate":
				node.set_meta(prop_str, bool(value))
				_notify_property_changed(prop_str)
				return true
			"Anchored":
				node.set_meta("anchored", bool(value))
				_notify_property_changed("Anchored")
				return true
			"Shape":
				if node is MeshInstance3D:
					var material: Material = node.get_active_material(0) if node.mesh != null else null
					var spherical := str(value) in ["Ball", "Sphere", "0", "0.0"]
					node.mesh = SphereMesh.new() if spherical else BoxMesh.new()
					node.material_override = material
					node.set_meta("shape_type", "Sphere" if spherical else "Box")
					node.set_meta("Shape", value)
					_notify_property_changed("Size")
					return true
			"CanCollide":
				node.set_meta("can_collide", bool(value))
				if node.has_method("_update_block_collision"):
					node.call("_update_block_collision", node)
				_notify_property_changed("CanCollide")
				return true
			"Transparency":
				var trans := float(value)
				node.set_meta("transparency", trans)
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if trans > 0.01 else BaseMaterial3D.TRANSPARENCY_DISABLED
					material.albedo_color.a = 1.0 - trans
					if material.next_pass is ShaderMaterial:
						material.next_pass = material.next_pass.duplicate()
						material.next_pass.set_shader_parameter("opacity", 1.0 - trans)
				)
				_notify_property_changed("Transparency")
				return true
			"BrickColor":
				var col: Color = Color.WHITE
				if value is Color:
					col = value
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					var alpha := material.albedo_color.a
					material.albedo_color = Color(col.r, col.g, col.b, alpha)
				)
				_notify_property_changed("BrickColor")
				return true
			"Color":
				var color_value: Color = Color.WHITE
				if value is Color:
					color_value = value
				if node is GPUParticles3D:
					var particles := node as GPUParticles3D
					var particle_material := particles.process_material as ParticleProcessMaterial
					if particle_material == null:
						particle_material = ParticleProcessMaterial.new()
						particles.process_material = particle_material
					else:
						particle_material = particle_material.duplicate(true) as ParticleProcessMaterial
						particles.process_material = particle_material
					particle_material.color = color_value
				_mutate_mesh_materials(func(material: StandardMaterial3D):
					var alpha := material.albedo_color.a
					material.albedo_color = Color(color_value.r, color_value.g, color_value.b, alpha)
				)
				_notify_property_changed("Color")
				return true
			"TimeOfDay", "ClockTime":
				node.set_meta(prop_str, value)
				_notify_property_changed(prop_str)
				return true
		var properties: Dictionary = node.get_meta("roblox_properties", {}) if node.get_meta("roblox_properties", {}) is Dictionary else {}
		properties[prop_str] = value
		node.set_meta("roblox_properties", properties)
		node.set_meta(prop_str, value)
		_notify_property_changed(prop_str)
		return true

	func SetProperty(property_or_self: Variant, property_or_value: Variant, maybe_value: Variant = null) -> bool:
		var property_name := str(property_or_value if (property_or_self is Object and property_or_self == self) else property_or_self)
		var value: Variant = maybe_value if (property_or_self is Object and property_or_self == self) else property_or_value
		return _set(StringName(property_name), value)

	func GetProperty(property_or_self: Variant, maybe_property: Variant = null) -> Variant:
		var property_name := str(maybe_property if (property_or_self is Object and property_or_self == self) else property_or_self)
		return _get(StringName(property_name))

	func GetNode() -> Node:
		return node

	func FindFirstChild(name_or_self: Variant, name_or_recursive: Variant = null, maybe_recursive: Variant = false) -> BobuxInstance:
		var child_name := str(name_or_recursive if (name_or_self is Object and name_or_self == self) else name_or_self)
		var recursive := bool(maybe_recursive if (name_or_self is Object and name_or_self == self) else (name_or_recursive if name_or_recursive != null else false))
		if not is_instance_valid(node):
			return null
		var child := node.find_child(child_name, recursive, false)
		return BobuxInstance.wrap(child) if child else null

	func findFirstChild(name_or_self: Variant, name_or_recursive: Variant = null, maybe_recursive: Variant = false) -> BobuxInstance:
		return FindFirstChild(name_or_self, name_or_recursive, maybe_recursive)

	func FindFirstChildOfClass(class_or_self: Variant, maybe_class: Variant = null) -> BobuxInstance:
		var requested_class := str(maybe_class if (class_or_self is Object and class_or_self == self) else class_or_self)
		if not is_instance_valid(node):
			return null
		for child in node.get_children():
			if _node_matches_roblox_class(child, requested_class, false):
				return BobuxInstance.wrap(child)
		return null

	func FindFirstChildWhichIsA(class_or_self: Variant, maybe_class: Variant = null) -> BobuxInstance:
		var requested_class := str(maybe_class if (class_or_self is Object and class_or_self == self) else class_or_self)
		if not is_instance_valid(node):
			return null
		for child in node.get_children():
			if _node_matches_roblox_class(child, requested_class, true):
				return BobuxInstance.wrap(child)
		return null

	func FindFirstAncestor(name_or_self: Variant, maybe_name: Variant = null) -> BobuxInstance:
		var ancestor_name := str(maybe_name if (name_or_self is Object and name_or_self == self) else name_or_self)
		var cursor := node.get_parent() if is_instance_valid(node) else null
		while cursor != null:
			if str(cursor.get_meta("Name", cursor.get_meta("block_name", cursor.name))) == ancestor_name:
				return BobuxInstance.wrap(cursor)
			cursor = cursor.get_parent()
		return null

	func FindFirstAncestorOfClass(class_or_self: Variant, maybe_class: Variant = null) -> BobuxInstance:
		var requested_class := str(maybe_class if (class_or_self is Object and class_or_self == self) else class_or_self)
		var cursor := node.get_parent() if is_instance_valid(node) else null
		while cursor != null:
			if _node_matches_roblox_class(cursor, requested_class, false):
				return BobuxInstance.wrap(cursor)
			cursor = cursor.get_parent()
		return null

	func FindFirstAncestorWhichIsA(class_or_self: Variant, maybe_class: Variant = null) -> BobuxInstance:
		var requested_class := str(maybe_class if (class_or_self is Object and class_or_self == self) else class_or_self)
		var cursor := node.get_parent() if is_instance_valid(node) else null
		while cursor != null:
			if _node_matches_roblox_class(cursor, requested_class, true):
				return BobuxInstance.wrap(cursor)
			cursor = cursor.get_parent()
		return null

	func GetChildren(_self_arg: Variant = null) -> Array[BobuxInstance]:
		var native_start := Time.get_ticks_usec()
		var arr: Array[BobuxInstance] = []
		if not is_instance_valid(node):
			return arr
		for c in node.get_children():
			if _is_native_helper(c) or c.is_queued_for_deletion(): continue
			arr.append(BobuxInstance.wrap(c))
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return arr

	func getChildren(_self_arg: Variant = null) -> Array[BobuxInstance]:
		return GetChildren()

	func children(_self_arg: Variant = null) -> Array[BobuxInstance]:
		return GetChildren()

	func GetDescendants(_self_arg: Variant = null) -> Array[BobuxInstance]:
		var native_start := Time.get_ticks_usec()
		var arr: Array[BobuxInstance] = []
		if not is_instance_valid(node):
			return arr
		_collect_descendants(node, arr)
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return arr

	func _collect_descendants(root_node: Node, out: Array[BobuxInstance]) -> void:
		for child in root_node.get_children():
			if _is_native_helper(child) or child.is_queued_for_deletion(): continue
			out.append(BobuxInstance.wrap(child))
			_collect_descendants(child, out)

	static func _is_native_helper(child: Node) -> bool:
		return str(child.get_meta("roblox_class", "")).is_empty() and (child is CollisionObject3D or child is CollisionShape3D or bool(child.get_meta("bobux_runtime_generated", false)))

	func Destroy(_self_arg: Variant = null) -> void:
		if is_instance_valid(node):
			Destroying.Fire()
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()

	func Clone(_self_arg: Variant = null) -> BobuxInstance:
		if is_instance_valid(node):
			var native_start := Time.get_ticks_usec()
			var dupe := node.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
			_reset_clone_metadata(dupe)
			_rekey_clone_tree(dupe)
			dupe.set_meta("bobux_runtime_generated", true)
			var engine: Node = Engine.get_main_loop().root.get_node_or_null("LuaScriptEngine")
			if engine != null: engine._exclude_native_work(native_start)
			return BobuxInstance.wrap(dupe)
		return null

	func clone(_self_arg: Variant = null) -> BobuxInstance:
		return Clone()

	static func _reset_clone_metadata(clone_node: Node) -> void:
		for key in clone_node.get_meta_list():
			var name_ := str(key)
			if name_.begins_with("_bobux_") or name_ in ["bobux_script_runtime_id", "bobux_character_body_instance_id", "bobux_character_instance_id", "bobux_vehicle_motor_id", "bobux_tool_equipped", "bobux_equipped_character_id", "bobux_bound_target_path", "bobux_lua_event_bound"]:
				clone_node.remove_meta(key)
		for child in clone_node.get_children():
			if _is_native_helper(child) and not child is StaticBody3D:
				clone_node.remove_child(child)
				child.free()
			else: _reset_clone_metadata(child)

	static func _rekey_clone_tree(root_node: Node) -> void:
		var pending: Array[Node] = [root_node]
		var all: Array[Node] = []
		var replacements := {}
		var refs := {}
		while not pending.is_empty():
			var child: Node = pending.pop_back()
			all.append(child)
			pending.append_array(child.get_children())
			var old_ref := str(child.get_meta("roblox_ref", ""))
			var new_ref := "clone:%d" % child.get_instance_id()
			if not old_ref.is_empty(): replacements[old_ref] = new_ref
			refs[new_ref] = child.get_instance_id()
			child.set_meta("roblox_ref", new_ref)
		for child in all:
			var props: Dictionary = child.get_meta("roblox_properties", {}).duplicate(true)
			var keys := ["PrimaryPart", "Part0", "Part1", "Attachment0", "Attachment1", "Adornee"]
			if str(child.get_meta("roblox_class", "")) == "ObjectValue": keys.append("Value")
			for key in keys:
				var raw: Variant = child.get_meta(key) if child.has_meta(key) else props.get(key)
				var old := str(int(raw)) if raw is float else str(raw)
				if replacements.has(old):
					props[key] = replacements[old]
					child.set_meta(key, replacements[old])
			child.set_meta("roblox_properties", props)
		root_node.set_meta("_bobux_clone_refs", refs)

	func _is_node_under_workspace(candidate: Node) -> bool:
		var cursor := candidate
		while cursor != null:
			var roblox_class := str(cursor.get_meta("roblox_class", ""))
			if roblox_class == "Workspace" or cursor.name in ["Workspace", "Blocks"]:
				return true
			cursor = cursor.get_parent()
		return false

	func _set_template_tree_visible(root_node: Node, visible_in_world: bool) -> void:
		if visible_in_world and root_node is MeshInstance3D and bool(root_node.get_meta("bobux_deferred_geometry", false)):
			var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
			importer.scale_factor = _stud_scale()
			importer.materialize_template_part(root_node)
		if visible_in_world and root_node is MeshInstance3D and bool(root_node.get_meta("roblox_properties", {}).get("BobuxTemplateOnly", false)):
			preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(root_node, true)
		if root_node is Node3D:
			(root_node as Node3D).visible = visible_in_world
		if visible_in_world:
			root_node.set_meta("BobuxTemplateOnly", false)
		for child in root_node.get_children():
			_set_template_tree_visible(child, visible_in_world)

	func remove(_self_arg: Variant = null) -> void:
		Destroy()

	func WaitForChild(name_or_self: Variant, name_or_timeout: Variant = null, maybe_timeout: Variant = 5.0) -> BobuxInstance:
		var child_name := str(name_or_timeout if (name_or_self is Object and name_or_self == self) else name_or_self)
		if not is_instance_valid(node):
			return null
		var child = node.find_child(child_name, true, false)
		if child:
			return BobuxInstance.wrap(child)
		# The complete DataModel is installed before scripts start, so an absent
		# child is returned immediately instead of blocking the render thread.
		return null

	func IsA(class_or_self: Variant, maybe_class: Variant = null) -> bool:
		var p_class_name := str(maybe_class if (class_or_self is Object and class_or_self == self) else class_or_self)
		if not is_instance_valid(node):
			return false
		return _node_matches_roblox_class(node, p_class_name, true)

	func _node_matches_roblox_class(candidate: Node, requested_class: String, include_inheritance: bool) -> bool:
		if candidate == null or not is_instance_valid(candidate):
			return false
		var roblox_class := str(candidate.get_meta("roblox_class", candidate.get_meta("shape_type", "")))
		if roblox_class == requested_class:
			return true
		if candidate.has_meta("shape_type") and str(candidate.get_meta("shape_type")) == requested_class:
			return true
		if include_inheritance and requested_class == "BasePart":
			return roblox_class in ["Part", "MeshPart", "WedgePart", "CornerWedgePart", "TrussPart", "SpawnLocation", "Seat", "VehicleSeat", "UnionOperation", "NegateOperation", "IntersectOperation"] or bool(candidate.get_meta("bobux_character_part_proxy", false))
		return candidate.is_class(requested_class)

	func IsDescendantOf(parent_or_self: Variant, maybe_parent: Variant = null) -> bool:
		var parent: BobuxInstance = maybe_parent as BobuxInstance if (parent_or_self is Object and parent_or_self == self) else parent_or_self as BobuxInstance
		if not is_instance_valid(node) or parent == null or not is_instance_valid(parent.node):
			return false
		return parent.node.is_ancestor_of(node)

	func IsAncestorOf(child_or_self: Variant, maybe_child: Variant = null) -> bool:
		var child_variant: Variant = maybe_child if (child_or_self is Object and child_or_self == self) else child_or_self
		var child_node := _node_from_instance_variant(child_variant)
		return is_instance_valid(node) and is_instance_valid(child_node) and node.is_ancestor_of(child_node)

	func GetConnectedParts(self_or_recursive: Variant = null, maybe_recursive: Variant = null) -> Array[BobuxInstance]:
		if not is_instance_valid(node) or not node.is_inside_tree():
			return []
		var recursive := bool(maybe_recursive) if (self_or_recursive is Object and self_or_recursive == self) and maybe_recursive != null else bool(self_or_recursive) if self_or_recursive != null and not (self_or_recursive is Object and self_or_recursive == self) else false
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
				result.append(BobuxInstance.wrap(connected_node))
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
			result.append(BobuxInstance.wrap(sibling))
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
		var ray: Variant = ray_or_ignore if (ray_or_self is Object and ray_or_self == self) else ray_or_self
		var ignore: Variant = ignore_or_terrain if (ray_or_self is Object and ray_or_self == self) else ray_or_ignore
		return _perform_roblox_raycast(ray, ignore)

	func FindPartOnRayWithIgnoreListResult(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, _terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayResult(ray_or_self, ray_or_ignore, ignore_or_terrain, _terrain_cells_are_cubes)

	func FindPartOnRay(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayResult(ray_or_self, ray_or_ignore, ignore_or_terrain, terrain_cells_are_cubes)

	func FindPartOnRayWithIgnoreList(ray_or_self: Variant, ray_or_ignore: Variant = null, ignore_or_terrain: Variant = null, terrain_cells_are_cubes: Variant = false) -> Array:
		return FindPartOnRayWithIgnoreListResult(ray_or_self, ray_or_ignore, ignore_or_terrain, terrain_cells_are_cubes)

	func Raycast(origin_or_self: Variant, origin_or_direction: Variant = null, direction_or_params: Variant = null, maybe_params: Variant = null) -> Variant:
		var origin: Variant = origin_or_direction if (origin_or_self is Object and origin_or_self == self) else origin_or_self
		var direction: Variant = direction_or_params if (origin_or_self is Object and origin_or_self == self) else origin_or_direction
		var params: Variant = maybe_params if (origin_or_self is Object and origin_or_self == self) else direction_or_params
		if not (origin is Vector3) or not (direction is Vector3):
			return null
		var result := _perform_roblox_raycast(BobuxRay.new(origin, direction), params)
		if result.is_empty() or result[0] == null:
			return null
		return {"Instance": result[0], "Position": result[1], "Normal": result[2], "Material": result[3]}

	func GetPartBoundsInRadius(position_or_self: Variant, position_or_radius: Variant = null, radius_or_params: Variant = null, maybe_params: Variant = null) -> Array[BobuxInstance]:
		var native_start := Time.get_ticks_usec()
		var colon: bool = position_or_self is Object and position_or_self == self
		var position_: Variant = position_or_radius if colon else position_or_self
		var radius_: Variant = radius_or_params if colon else position_or_radius
		var params: Variant = maybe_params if colon else radius_or_params
		var result: Array[BobuxInstance] = []
		if not position_ is Vector3 or not (radius_ is float or radius_ is int): return result
		var filters: Array = []
		var include := false
		var max_parts := 0
		var respect := false
		if params is BobuxOverlapParams:
			for value in params.FilterDescendantsInstances:
				var filter := _node_from_instance_variant(value)
				if filter != null: filters.append(filter)
			include = params.FilterType == 1
			max_parts = params.MaxParts
			respect = params.RespectCanCollide
		for part in preload("res://addons/roblox_runtime/roblox_spatial_query.gd").in_radius(node, _roblox_point_to_godot(position_), float(radius_) * _stud_scale(), filters, include, max_parts, respect):
			result.append(BobuxInstance.wrap(part))
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return result

	func FindPartsInRegion3(region_or_self: Variant, region_or_ignore: Variant = null, ignore_or_max: Variant = null, maybe_max: Variant = 20) -> Array[BobuxInstance]:
		var colon := region_or_self is BobuxInstance
		var region: Variant = region_or_ignore if colon else region_or_self
		var ignored: Variant = ignore_or_max if colon else region_or_ignore
		var limit: Variant = maybe_max if colon else ignore_or_max
		if not region is Dictionary or not region.get("CFrame") is BobuxCFrame: return []
		var params := BobuxOverlapParams.new()
		if ignored != null: params.FilterDescendantsInstances = [ignored]
		params.MaxParts = int(limit) if limit != null else 20
		return GetPartBoundsInBox(region.CFrame, region.Size, params)

	func GetPartBoundsInBox(frame_or_self: Variant, frame_or_size: Variant = null, size_or_params: Variant = null, maybe_params: Variant = null) -> Array[BobuxInstance]:
		var native_start := Time.get_ticks_usec()
		var colon := frame_or_self is BobuxInstance
		var frame: Variant = frame_or_size if colon else frame_or_self
		var size_: Variant = size_or_params if colon else frame_or_size
		var params: Variant = maybe_params if colon else size_or_params
		var result: Array[BobuxInstance] = []
		if not frame is BobuxCFrame or not size_ is Vector3: return result
		var filters: Array = []
		if params is BobuxOverlapParams:
			for value in params.FilterDescendantsInstances:
				var filter := _node_from_instance_variant(value)
				if filter != null: filters.append(filter)
		var include: bool = params.FilterType == 1 if params is BobuxOverlapParams else false
		var count: int = params.MaxParts if params is BobuxOverlapParams else 0
		var respect: bool = params.RespectCanCollide if params is BobuxOverlapParams else false
		for part in preload("res://addons/roblox_runtime/roblox_spatial_query.gd").in_box(node, _roblox_transform_to_godot(frame.transform), size_ * _stud_scale(), filters, include, count, respect):
			result.append(BobuxInstance.wrap(part))
		var engine: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)
		return result

	func _perform_roblox_raycast(ray_variant: Variant, ignore: Variant) -> Array:
		if not (ray_variant is BobuxRay) or not is_instance_valid(node) or not node.is_inside_tree():
			return [null, Vector3.ZERO, Vector3.ZERO, "Air"]
		var ray := ray_variant as BobuxRay
		var start := _roblox_point_to_godot(ray.Origin)
		var finish := start + _roblox_point_to_godot(ray.Direction)
		if start.is_equal_approx(finish):
			return [null, ray.Origin, Vector3.ZERO, "Air"]
		var viewport := node.get_viewport()
		var world := viewport.find_world_3d() if viewport != null else null
		if world == null:
			return [null, ray.Origin + ray.Direction, Vector3.ZERO, "Air"]
		var query := PhysicsRayQueryParameters3D.create(start, finish)
		query.collision_mask = STUDIO_WORLD_COLLISION_MASK
		query.collide_with_bodies = true
		query.collide_with_areas = true
		var exclusions: Array[RID] = []
		if ignore is BobuxRaycastParams:
			var raycast_params := ignore as BobuxRaycastParams
			if raycast_params.FilterType == 1:
				var included: Array[RID] = []
				_collect_raycast_exclusions(raycast_params.FilterDescendantsInstances, included)
				var all_colliders: Array[RID] = []
				_collect_collision_rids(node, all_colliders)
				for collider_rid in all_colliders:
					if not included.has(collider_rid):
						exclusions.append(collider_rid)
			else:
				_collect_raycast_exclusions(raycast_params.FilterDescendantsInstances, exclusions)
		else:
			_collect_raycast_exclusions(ignore, exclusions)
		query.exclude = exclusions
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return [null, ray.Origin + ray.Direction, Vector3.ZERO, "Air"]
		var hit_part := _part_from_raycast_collider(hit.get("collider", null), int(hit.get("shape", -1)))
		var hit_position := _godot_point_to_roblox(hit.get("position", finish) as Vector3)
		var hit_normal := _godot_direction_to_roblox(hit.get("normal", Vector3.ZERO) as Vector3)
		var hit_material: Variant = hit_part.get_meta("material_type", hit_part.get_meta("Material", "Plastic")) if hit_part != null else "Plastic"
		return [BobuxInstance.wrap(hit_part) if hit_part != null else null, hit_position, hit_normal, hit_material]

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

	func _part_from_raycast_collider(collider: Variant, shape_index: int = -1) -> Node:
		if is_instance_valid(collider) and collider is Node and shape_index >= 0:
			var shape_id := int(collider.get_meta("_bobux_shape_parts", {}).get(shape_index, 0))
			var shape_part: Variant = instance_from_id(shape_id) if shape_id else null
			if is_instance_valid(shape_part): return shape_part
		if is_instance_valid(collider) and collider is CharacterBody3D:
			var root_part := (collider as Node).get_node_or_null("HumanoidRootPart")
			return root_part if root_part != null else collider
		if is_instance_valid(collider) and collider is Node:
			var visual_id := int(collider.get_meta("bobux_visual_instance_id", 0))
			var visual: Variant = instance_from_id(visual_id) if visual_id != 0 else null
			if is_instance_valid(visual):
				return visual
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
		if (arg1 is Object and arg1 == self):
			OnServerEvent.Fire(arg2, arg3)
		else:
			OnServerEvent.Fire(arg1, arg2, arg3)

	# Lua packs the complete vararg list (including interior/trailing nils).
	# RemoteEvent's server sender is supplied by the runtime, never by the payload.
	func DispatchPacked(method_or_self: Variant, packed_or_method: Variant = null, count_or_packed: Variant = null, maybe_count: int = 0) -> Variant:
		var colon := method_or_self is BobuxInstance
		var method := str(packed_or_method if colon else method_or_self)
		var packed: Variant = count_or_packed if colon else packed_or_method
		var count := maybe_count if colon else int(count_or_packed)
		var args: Array = []
		if packed is Array:
			args = packed.duplicate()
		elif packed is Dictionary:
			for index in range(1, count + 1):
				args.append(packed.get(index, packed.get(float(index), null)))
		args.resize(count)
		if not is_instance_valid(node) or not node.is_inside_tree(): return null
		var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
		var state: Dictionary = engine.get_local_inventory_state(node) if engine != null else {}
		var player: Node = state.get("local_player")
		match method:
			"FireServer", "InvokeServer":
				args.push_front(BobuxInstance.wrap(player) if is_instance_valid(player) else null)
			"FireClient", "InvokeClient":
				if args.is_empty(): return null
				var recipient := _node_from_instance_variant(args.pop_front())
				if recipient != player: return null
		match method:
			"FireServer": OnServerEvent.FireArgs(args)
			"FireClient", "FireAllClients": OnClientEvent.FireArgs(args)
			"Fire": Event.FireArgs(args)
			"InvokeServer", "InvokeClient", "Invoke":
				var callback_name := "OnServerInvoke" if method == "InvokeServer" else ("OnClientInvoke" if method == "InvokeClient" else "OnInvoke")
				var callback: Variant = node.get_meta(callback_name, null)
				if callback is Callable: return callback.callv(args)
		return null

	func FireClient(_player: Variant = null, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		if (_player is Object and _player == self):
			OnClientEvent.Fire(arg1, arg2, arg3)
		else:
			OnClientEvent.Fire(arg1, arg2, arg3)

	func FireAllClients(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
		if (arg1 is Object and arg1 == self):
			OnClientEvent.Fire(arg2, arg3)
		else:
			OnClientEvent.Fire(arg1, arg2, arg3)

	func Fire(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null) -> void:
		if (arg1 is Object and arg1 == self):
			Event.Fire(arg2, arg3, arg4)
		else:
			Event.Fire(arg1, arg2, arg3)

	func InvokeServer(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> Variant:
		var callback: Variant = node.get_meta("OnServerInvoke", null) if is_instance_valid(node) else null
		return callback.call(arg1, arg2, arg3) if callback is Callable else null

	func InvokeClient(_player: Variant = null, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> Variant:
		var callback: Variant = node.get_meta("OnClientInvoke", null) if is_instance_valid(node) else null
		return callback.call(arg1, arg2, arg3) if callback is Callable else null

	func GetAttribute(attribute_or_self: Variant, maybe_attribute_name: Variant = null) -> Variant:
		var attribute_name := str(maybe_attribute_name if (attribute_or_self is Object and attribute_or_self == self) else attribute_or_self)
		if not is_instance_valid(node) or attribute_name.is_empty():
			return null
		var meta_name := "attribute_" + attribute_name
		return node.get_meta(meta_name) if node.has_meta(meta_name) else null

	func SetAttribute(attribute_or_self: Variant, value_or_name: Variant = null, maybe_value: Variant = null) -> void:
		var attribute_name := str(value_or_name if (attribute_or_self is Object and attribute_or_self == self) else attribute_or_self)
		var value: Variant = maybe_value if (attribute_or_self is Object and attribute_or_self == self) else value_or_name
		if is_instance_valid(node) and not attribute_name.is_empty():
			var meta_name := "attribute_" + attribute_name
			var previous: Variant = node.get_meta(meta_name) if node.has_meta(meta_name) else null
			if typeof(previous) == typeof(value) and previous == value:
				return
			if value == null:
				node.remove_meta(meta_name)
			else:
				node.set_meta(meta_name, value)
			var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
			var attributes: Dictionary = properties.get("Attributes", {}).duplicate(true)
			if value == null: attributes.erase(attribute_name)
			else: attributes[attribute_name] = value
			properties["Attributes"] = attributes
			node.set_meta("roblox_properties", properties)
			_shared_event("AttributeChanged").Fire(attribute_name)
			_shared_event("AttributeChanged_" + attribute_name).Fire()

	func GetAttributes(_self_arg: Variant = null) -> Dictionary:
		var attributes := {}
		if is_instance_valid(node):
			for key in node.get_meta_list():
				if str(key).begins_with("attribute_"):
					attributes[str(key).trim_prefix("attribute_")] = node.get_meta(key)
		return attributes

	func GetAttributeChangedSignal(attribute_or_self: Variant, maybe_attribute_name: Variant = null) -> BobuxEvent:
		var attribute_name := str(maybe_attribute_name if (attribute_or_self is Object and attribute_or_self == self) else attribute_or_self)
		return _shared_event("AttributeChanged_" + attribute_name)

	func GetPropertyChangedSignal(property_or_self: Variant, maybe_property_name: Variant = null) -> BobuxEvent:
		var property_name := str(maybe_property_name if property_or_self is BobuxInstance else property_or_self)
		return _shared_event("PropertyChanged_" + property_name)

	func _notify_property_changed(property_name: String) -> void:
		if str(node.get_meta("roblox_class", "")) == "Sound" and node.is_inside_tree():
			if property_name in ["SoundId", "Volume", "Pitch", "PlaybackSpeed", "Looped", "Parent"]:
				preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").configure(node)
			if property_name == "Playing":
				if bool(node.get_meta("Playing", false)): Play()
				else: Stop()
		if node is MeshInstance3D and property_name.ends_with("Surface"):
			var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(false)
			properties["BobuxStudScale"] = _stud_scale()
			var material := preload("res://addons/rbxl_importer/material_cache.gd").new().get_part_material(properties)
			_mutate_mesh_materials(func(existing: StandardMaterial3D): existing.next_pass = material.next_pass)
		if property_name in ["Parent", "CFrame", "Position", "Size"]:
			preload("res://addons/roblox_runtime/roblox_spatial_query.gd").invalidate()
		if node.is_inside_tree() and str(node.get_meta("roblox_class", "")) in ["Weld", "ManualWeld", "WeldConstraint", "Motor6D", "Motor", "Snap"]:
			var adapter := node.get_node_or_null("RobloxJointRuntime")
			if adapter == null:
				adapter = preload("res://addons/roblox_runtime/roblox_joint_runtime.gd").new()
				adapter.name = "RobloxJointRuntime"
				adapter.set_meta("bobux_runtime_generated", true)
				node.add_child(adapter)
			adapter.request_refresh()
		if property_name in ["Parent", "Disabled"] and node.is_inside_tree():
			var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
			if engine != null: engine.call_deferred("_refresh_authored_scripts_by_id", node.get_instance_id())
		if property_name == "Parent" and node.is_inside_tree() and str(node.get_meta("roblox_class", "")) == "Explosion" and not node.has_meta("bobux_exploded"):
			node.set_meta("bobux_exploded", true)
			var explosion := preload("res://addons/roblox_runtime/roblox_explosion.gd").new()
			node.add_child(explosion)
		if node is MeshInstance3D and node.is_inside_tree():
			var assembly_id := int(node.get_meta("_bobux_surface_assembly", 0))
			var assembly: Variant = instance_from_id(assembly_id) if assembly_id else null
			if is_instance_valid(assembly):
				assembly.refresh(node, property_name)
				_shared_event("PropertyChanged_" + property_name).Fire()
				Changed.Fire(property_name)
				return
			var physics_api := preload("res://addons/roblox_runtime/roblox_part_physics.gd")
			var create_body := property_name == "Anchored" or (property_name == "Parent" and bool(node.get_meta("bobux_lua_created_part", false)))
			var body := physics_api.body_for(node, create_body)
			if body != null:
				if property_name in ["Position", "CFrame", "Rotation", "Size", "Parent"]:
					body.global_transform = Transform3D(node.global_basis.orthonormalized(), node.global_position)
					var adapter := node.get_node_or_null("RobloxPartPhysics")
					if adapter != null: adapter.sync_from_part()
				if property_name in ["Anchored", "CanCollide", "CanQuery"]:
					body.freeze = bool(node.get_meta("anchored", false))
					body.collision_layer = 1 if bool(node.get_meta("can_collide", true)) else (16 if bool(node.get_meta("CanQuery", true)) else 0)
					body.collision_mask = (1 | 2 | 4 | 64) if bool(node.get_meta("can_collide", true)) else 0
					body.sleeping = false
		_shared_event("PropertyChanged_" + property_name).Fire()
		if property_name == "Value" and str(node.get_meta("roblox_class", "")).ends_with("Value"):
			Changed.Fire(_get(&"Value"))
		else:
			Changed.Fire(property_name)

	func GetPlayers(_self_arg: Variant = null) -> Array[BobuxInstance]:
		if str(node.get_meta("roblox_class", "")) == "Players":
			var joined: Array[BobuxInstance] = []
			for child in node.get_children():
				if str(child.get_meta("roblox_class", "")) == "Player" and bool(child.get_meta("bobux_player_joined", false)):
					joined.append(BobuxInstance.wrap(child))
			return joined
		if str(node.get_meta("roblox_class", "")) == "Team":
			var result: Array[BobuxInstance] = []
			if not node.is_inside_tree(): return result
			var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
			var state: Dictionary = engine.get_local_inventory_state(node)
			var local: Node = state.get("local_player")
			if local == null: return result
			var players := BobuxInstance.wrap(local.get_parent())
			for player in players.GetChildren():
				var team: Variant = player._get(&"Team")
				if team is BobuxInstance and team.node == node and not bool(player.node.get_meta("Neutral", false)): result.append(player)
			return result
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
				return BobuxInstance.wrap(player_node)
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
		_shared_event("CharacterAdded").Fire(BobuxInstance.wrap(character))
		return BobuxInstance.wrap(character)

	func GetMouse(_self_arg: Variant = null) -> BobuxMouse:
		return BobuxMouse.new(node)

	func EquipTool(tool_or_self: Variant, maybe_tool: Variant = null) -> void:
		var tool := _node_from_instance_variant(maybe_tool if tool_or_self is BobuxInstance and tool_or_self.node == node else tool_or_self)
		var character := _character_body()
		if tool == null or character == null: return
		var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null:
			engine.equip_local_tool(tool, character, character)

	func _seat_sit(humanoid_or_self: Variant, maybe_humanoid: Variant = null) -> void:
		var target: Variant = maybe_humanoid if humanoid_or_self is BobuxInstance and humanoid_or_self.node == node else humanoid_or_self
		if not target is BobuxInstance or not is_instance_valid(node): return
		var body: Node = target._character_body()
		if body != null and body.has_method("_enter_seat"):
			body._enter_seat(node)

	func UnequipTools(_self_arg: Variant = null) -> void:
		var character := _character_body()
		if character == null: return
		var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null:
			engine.unequip_all_local_tools(character)

	func Play(_self_arg: Variant = null) -> void:
		preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").play(node)

	func Stop(_self_arg: Variant = null) -> void:
		preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").stop(node)

	func _queue_assembly_motion(value: Vector3, kind: String) -> bool:
		var id := int(node.get_meta("_bobux_surface_assembly", 0))
		var assembly: Variant = instance_from_id(id) if id else null
		return is_instance_valid(assembly) and assembly.queue_motion(node, value, kind)

	func GetMass(_self_arg: Variant = null) -> float:
		if node is RigidBody3D:
			return (node as RigidBody3D).mass
		if node is Node3D:
			var dimensions := (node as Node3D).scale.abs() / _stud_scale()
			return maxf(dimensions.x * dimensions.y * dimensions.z, 0.001)
		return 1.0

	func ApplyImpulse(impulse_or_self: Variant, maybe_impulse: Variant = null) -> void:
		var impulse: Variant = maybe_impulse if impulse_or_self is BobuxInstance else impulse_or_self
		if not impulse is Vector3 or not is_instance_valid(node): return
		var value := _roblox_velocity_to_godot(impulse)
		if _queue_assembly_motion(value, "impulse"): return
		var character := _character_body()
		if character != null and character.has_method("apply_external_impulse"):
			character.call("apply_external_impulse", value / maxf(GetMass(), 1.0))
			return
		if character != null and character.has_method("set_lua_linear_velocity"):
			character.call("set_lua_linear_velocity", character.velocity + value / maxf(GetMass(), 1.0))
			return
		var body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(node, true)
		if body != null and not body.freeze:
			body.apply_central_impulse(value)

	func MoveTo(position_or_self: Variant, maybe_position: Variant = null) -> void:
		var destination: Variant = maybe_position if (position_or_self is Object and position_or_self == self) else position_or_self
		if not (destination is Vector3):
			return
		var godot_destination := _roblox_point_to_godot(destination as Vector3)
		var body := _character_body()
		if str(node.get_meta("roblox_class", "")) == "Humanoid":
			if body == null:
				body = preload("res://addons/roblox_runtime/roblox_humanoid_motor.gd").ensure(node)
			if body != null and body.has_method("move_to"):
				body.call("move_to", godot_destination)
			return
		if body != null:
			body.global_position = godot_destination
			body.velocity = Vector3.ZERO
			return
		if node is Node3D:
			(node as Node3D).global_position = godot_destination

	func TakeDamage(amount_or_self: Variant, maybe_amount: Variant = null) -> void:
		var amount := float(maybe_amount if (amount_or_self is Object and amount_or_self == self) else amount_or_self)
		var body := _character_body()
		if body == null and str(node.get_meta("roblox_class", "")) == "Humanoid":
			body = preload("res://addons/roblox_runtime/roblox_humanoid_motor.gd").ensure(node)
		if body != null and body.has_method("take_damage"):
			body.call("take_damage", amount)

	func ChangeState(state_or_self: Variant, maybe_state: Variant = null) -> void:
		var state_value: Variant = maybe_state if (state_or_self is Object and state_or_self == self) else state_or_self
		if not GetStateEnabled(state_value):
			return
		var body := _character_body()
		if body != null and body.has_method("request_humanoid_state"):
			body.call("request_humanoid_state", int(state_value))

	func SetStateEnabled(state_or_self: Variant, state_or_enabled: Variant, maybe_enabled: Variant = null) -> void:
		var state := int(state_or_enabled if (state_or_self is Object and state_or_self == self) else state_or_self)
		var enabled := bool(maybe_enabled if (state_or_self is Object and state_or_self == self) else state_or_enabled)
		if is_instance_valid(node):
			node.set_meta("bobux_state_enabled_%d" % state, enabled)
			_shared_event("StateEnabledChanged").Fire(state, enabled)

	func GetStateEnabled(state_or_self: Variant, maybe_state: Variant = null) -> bool:
		var state := int(maybe_state if state_or_self is BobuxInstance else state_or_self)
		return bool(node.get_meta("bobux_state_enabled_%d" % state, true)) if is_instance_valid(node) else false

	func GetState(_self_arg: Variant = null) -> Variant:
		var body := _character_body()
		if body != null and body.has_method("get_runtime_humanoid_state"):
			return body.call("get_runtime_humanoid_state")
		var state: Variant = node.get_meta("HumanoidState", 8) if is_instance_valid(node) else 8
		return {"Running": 8, "RunningNoPhysics": 8, "Jumping": 3, "Freefall": 5, "Landed": 7, "Dead": 15, "Climbing": 12, "Swimming": 4, "Seated": 13}.get(state, 8) if state is String else state

	func IsKeyDown(key_or_self: Variant, maybe_key: Variant = null) -> bool:
		var key := int(maybe_key if (key_or_self is Object and key_or_self == self) else key_or_self)
		return bool((node.get_meta("_bobux_pressed_keys", {}) as Dictionary).get(key, false)) if is_instance_valid(node) else false

	func GetMouseLocation(_self_arg: Variant = null) -> Vector2:
		return node.get_viewport().get_mouse_position() if is_instance_valid(node) and node.is_inside_tree() else Vector2.ZERO

	func ScreenPointToRay(x_or_self: Variant, x_or_y: Variant = 0.0, y_or_depth: Variant = 0.0, maybe_depth: float = 0.0) -> BobuxRay:
		var colon := x_or_self is BobuxInstance
		var point := Vector2(float(x_or_y if colon else x_or_self), float(y_or_depth if colon else x_or_y))
		var depth := maybe_depth if colon else float(y_or_depth)
		if not node is Camera3D or not node.is_inside_tree(): return BobuxRay.new(Vector3.ZERO, Vector3.FORWARD)
		var direction: Vector3 = node.project_ray_normal(point)
		var origin: Vector3 = node.project_ray_origin(point) + direction * depth * _stud_scale()
		return BobuxRay.new(_godot_point_to_roblox(origin), _godot_point_to_roblox(direction).normalized())

	func ViewportPointToRay(x_or_self: Variant, x_or_y: Variant = 0.0, y_or_depth: Variant = 0.0, maybe_depth: float = 0.0) -> BobuxRay:
		return ScreenPointToRay(x_or_self, x_or_y, y_or_depth, maybe_depth)

	func LoadAnimation(_animation_or_self: Variant = null, _maybe_animation: Variant = null) -> BobuxAnimationTrack:
		return BobuxAnimationTrack.new()

	func GetModelCFrame(_self_arg: Variant = null) -> BobuxCFrame:
		if node is Node3D:
			return BobuxCFrame.new(_godot_transform_to_roblox((node as Node3D).global_transform))
		var first_part := _first_descendant_node3d(node)
		return BobuxCFrame.new(_godot_transform_to_roblox(first_part.global_transform)) if first_part != null else BobuxCFrame.new()

	func GetPivot(_self_arg: Variant = null) -> BobuxCFrame:
		return GetModelCFrame()

	func GetModelSize(_self_arg: Variant = null) -> Vector3:
		var bounds := _combined_descendant_bounds(node)
		return bounds.size / _stud_scale()

	func SetPrimaryPartCFrame(frame_or_self: Variant, maybe_frame: Variant = null) -> void:
		var frame_value: Variant = maybe_frame if (frame_or_self is Object and frame_or_self == self) else frame_or_self
		if not (frame_value is BobuxCFrame):
			return
		var desired := _roblox_transform_to_godot((frame_value as BobuxCFrame).transform)
		var primary := _resolve_instance_reference(_stored_reference("PrimaryPart"))
		if primary != null and primary.node is Node3D and node is Node3D:
			var primary_frame: Transform3D = primary.node.global_transform if node.is_inside_tree() else _relative_frame(primary.node, node) * Transform3D.IDENTITY
			primary_frame.basis = primary_frame.basis.orthonormalized()
			if node.is_inside_tree(): node.global_transform = desired * primary_frame.affine_inverse() * node.global_transform
			else: node.transform = desired * primary_frame.affine_inverse()
			_sync_descendant_physics()
			return
		if node is Node3D:
			(node as Node3D).global_transform = desired
			_sync_descendant_physics()
			return
		var first_part := _first_descendant_node3d(node)
		if first_part != null:
			first_part.global_transform = desired

	func PivotTo(frame_or_self: Variant, maybe_frame: Variant = null) -> void:
		var frame: Variant = maybe_frame if frame_or_self is BobuxInstance else frame_or_self
		if node is Node3D and frame is BobuxCFrame:
			var desired := _roblox_transform_to_godot(frame.transform)
			if node.is_inside_tree(): node.global_transform = desired
			else: node.transform = desired
			_sync_descendant_physics()

	func _sync_descendant_physics() -> void:
		if not node.is_inside_tree(): return
		var pending: Array[Node] = [node]
		while not pending.is_empty():
			var child: Node = pending.pop_back()
			pending.append_array(child.get_children())
			if not child is MeshInstance3D: continue
			var body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(child)
			if body != null: body.global_transform = Transform3D(child.global_basis.orthonormalized(), child.global_position)

	static func _relative_frame(part: Node3D, ancestor: Node) -> Transform3D:
		var frame := part.transform
		var cursor := part.get_parent()
		while cursor != null and cursor != ancestor:
			if cursor is Node3D: frame = cursor.transform * frame
			cursor = cursor.get_parent()
		return frame

	func BulkMoveTo(parts_or_self: Variant, frames_or_parts: Variant = null, mode_or_frames: Variant = null, _maybe_mode: Variant = null) -> void:
		var parts: Variant = frames_or_parts if (parts_or_self is Object and parts_or_self == self) else parts_or_self
		var frames: Variant = mode_or_frames if (parts_or_self is Object and parts_or_self == self) else frames_or_parts
		if not (parts is Array) or not (frames is Array):
			return
		var part_array := parts as Array
		var frame_array := frames as Array
		for index in range(mini(part_array.size(), frame_array.size())):
			var target: Variant = part_array[index]
			var frame: Variant = frame_array[index]
			if not (frame is BobuxCFrame):
				continue
			if target is BobuxInstance:
				(target as BobuxInstance)._set(&"CFrame", frame)
			elif target is Node3D:
				(target as Node3D).global_transform = _roblox_transform_to_godot((frame as BobuxCFrame).transform)

	func TweenPosition(goal_or_self: Variant, maybe_goal: Variant = null, _direction: Variant = null, _style: Variant = null, _time: Variant = 1.0, _override: Variant = false, callback: Variant = null) -> bool:
		var goal: Variant = maybe_goal if (goal_or_self is Object and goal_or_self == self) else goal_or_self
		_set(&"Position", goal)
		if callback is Callable:
			(callback as Callable).call()
		return true

	func TweenSize(goal_or_self: Variant, maybe_goal: Variant = null, _direction: Variant = null, _style: Variant = null, _time: Variant = 1.0, _override: Variant = false, callback: Variant = null) -> bool:
		var goal: Variant = maybe_goal if (goal_or_self is Object and goal_or_self == self) else goal_or_self
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
		var native_start := Time.get_ticks_usec()
		var pending: Array[Node] = [node]
		while not pending.is_empty():
			var part: Node = pending.pop_back()
			preload("res://addons/roblox_runtime/roblox_surface_joints.gd").break_part(part)
			for child in part.get_children():
				if not _is_native_helper(child): pending.append(child)
		var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)

	func MakeJoints(_self_arg: Variant = null) -> void:
		if not is_instance_valid(node) or not node.is_inside_tree(): return
		var native_start := Time.get_ticks_usec()
		preload("res://addons/roblox_runtime/roblox_surface_joints.gd").make_joints(node)
		var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine._exclude_native_work(native_start)

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
		var asset_id: Variant = maybe_asset_id if (asset_or_self is Object and asset_or_self == self) else asset_or_self
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
		return BobuxInstance.wrap(model)

	func GetDataStore(name_or_self: Variant, maybe_name: Variant = null, _scope: Variant = null) -> BobuxDataStore:
		var requested_name := str(maybe_name if (name_or_self is Object and name_or_self == self) else name_or_self)
		return BobuxDataStore.new(node, requested_name, false)

	func GetOrderedDataStore(name_or_self: Variant, maybe_name: Variant = null, _scope: Variant = null) -> BobuxDataStore:
		var requested_name := str(maybe_name if (name_or_self is Object and name_or_self == self) else name_or_self)
		return BobuxDataStore.new(node, requested_name, true)

	func GetTagged(tag_or_self: Variant, maybe_tag: Variant = null) -> Array[BobuxInstance]:
		var tag := str(maybe_tag if (tag_or_self is Object and tag_or_self == self) else tag_or_self).strip_edges()
		var result: Array[BobuxInstance] = []
		if tag.is_empty() or not is_instance_valid(node) or not node.is_inside_tree():
			return result
		var search_root := node.get_tree().current_scene
		if search_root == null:
			search_root = node.get_tree().root
		_collect_tagged_nodes(search_root, tag, result)
		return result

	func _collect_tagged_nodes(root_node: Node, tag: String, result: Array[BobuxInstance]) -> void:
		if root_node == null:
			return
		if _node_has_roblox_tag(root_node, tag):
			result.append(BobuxInstance.wrap(root_node))
		for child in root_node.get_children():
			_collect_tagged_nodes(child, tag, result)

	func GetTags(instance_or_self: Variant = null, maybe_instance: Variant = null) -> Array:
		var target_variant: Variant = maybe_instance if (instance_or_self is Object and instance_or_self == self) else instance_or_self
		var target := _node_from_instance_variant(target_variant)
		if target == null:
			target = node
		return _read_roblox_tags(target)

	func HasTag(instance_or_self: Variant, instance_or_tag: Variant = null, maybe_tag: Variant = null) -> bool:
		var target_variant: Variant = instance_or_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_self
		var tag := str(maybe_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_tag)
		var target := _node_from_instance_variant(target_variant)
		return target != null and _node_has_roblox_tag(target, tag)

	func AddTag(instance_or_self: Variant, instance_or_tag: Variant = null, maybe_tag: Variant = null) -> void:
		var target_variant: Variant = instance_or_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_self
		var tag := str(maybe_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_tag).strip_edges()
		var target := _node_from_instance_variant(target_variant)
		if target == null or tag.is_empty():
			return
		var tags := _read_roblox_tags(target)
		if not tag in tags:
			tags.append(tag)
			_write_roblox_tags(target, tags)
			_shared_event("CollectionTagAdded_" + tag).Fire(BobuxInstance.wrap(target))

	func RemoveTag(instance_or_self: Variant, instance_or_tag: Variant = null, maybe_tag: Variant = null) -> void:
		var target_variant: Variant = instance_or_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_self
		var tag := str(maybe_tag if (instance_or_self is Object and instance_or_self == self) else instance_or_tag).strip_edges()
		var target := _node_from_instance_variant(target_variant)
		if target == null or tag.is_empty():
			return
		var tags := _read_roblox_tags(target)
		if tag in tags:
			tags.erase(tag)
			_write_roblox_tags(target, tags)
			_shared_event("CollectionTagRemoved_" + tag).Fire(BobuxInstance.wrap(target))

	func GetInstanceAddedSignal(tag_or_self: Variant, maybe_tag: Variant = null) -> BobuxEvent:
		var tag := str(maybe_tag if (tag_or_self is Object and tag_or_self == self) else tag_or_self)
		return _shared_event("CollectionTagAdded_" + tag)

	func GetInstanceRemovedSignal(tag_or_self: Variant, maybe_tag: Variant = null) -> BobuxEvent:
		var tag := str(maybe_tag if (tag_or_self is Object and tag_or_self == self) else tag_or_self)
		return _shared_event("CollectionTagRemoved_" + tag)

	func _read_roblox_tags(target: Node) -> Array:
		if target == null:
			return []
		var raw: Variant = target.get_meta("roblox_tags") if target.has_meta("roblox_tags") else null
		if raw == null:
			var properties: Dictionary = target.get_meta("roblox_properties", {}) if target.get_meta("roblox_properties", {}) is Dictionary else {}
			raw = properties.get("Tags", [])
		if raw is Array:
			return (raw as Array).duplicate()
		if raw is PackedStringArray:
			return Array(raw as PackedStringArray)
		if raw is String:
			var parsed: Array = []
			for piece in str(raw).split(",", false):
				var clean := piece.strip_edges()
				if not clean.is_empty():
					parsed.append(clean)
			return parsed
		return []

	func _write_roblox_tags(target: Node, tags: Array) -> void:
		target.set_meta("roblox_tags", tags.duplicate())
		var properties: Dictionary = target.get_meta("roblox_properties", {}) if target.get_meta("roblox_properties", {}) is Dictionary else {}
		properties = properties.duplicate(true)
		properties["Tags"] = tags.duplicate()
		target.set_meta("roblox_properties", properties)

	func _node_has_roblox_tag(target: Node, tag: String) -> bool:
		return tag in _read_roblox_tags(target)

	func SetCoreGuiEnabled(core_type_or_self: Variant, core_type_or_enabled: Variant = true, maybe_enabled: Variant = null) -> void:
		var core_type: Variant = core_type_or_enabled if (core_type_or_self is Object and core_type_or_self == self) else core_type_or_self
		var enabled := bool(maybe_enabled if (core_type_or_self is Object and core_type_or_self == self) else core_type_or_enabled)
		if not is_instance_valid(node):
			return
		var states: Dictionary = node.get_meta("_bobux_core_gui_enabled", {}) if node.get_meta("_bobux_core_gui_enabled", {}) is Dictionary else {}
		states[str(core_type)] = enabled
		node.set_meta("_bobux_core_gui_enabled", states)

	func GetCoreGuiEnabled(core_type_or_self: Variant, maybe_core_type: Variant = null) -> bool:
		var core_type: Variant = maybe_core_type if (core_type_or_self is Object and core_type_or_self == self) else core_type_or_self
		var states: Dictionary = node.get_meta("_bobux_core_gui_enabled", {}) if is_instance_valid(node) and node.get_meta("_bobux_core_gui_enabled", {}) is Dictionary else {}
		return bool(states.get(str(core_type), true))

	func PromptPurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func PromptProductPurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func PromptGamePassPurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func PromptBundlePurchase(_player_or_self: Variant = null, _player_or_asset: Variant = null, _asset_id: Variant = null) -> bool:
		return true

	func PromptPremiumPurchase(_player_or_self: Variant = null, _maybe_player: Variant = null) -> bool:
		return true

	func UserOwnsGamePassAsync(_player_or_self: Variant = null, _player_or_pass: Variant = null, _pass_id: Variant = null) -> bool:
		return false

	func GetProductInfo(asset_or_self: Variant, maybe_asset_id: Variant = null, _info_type: Variant = null) -> Dictionary:
		var asset_id: Variant = maybe_asset_id if (asset_or_self is Object and asset_or_self == self) else asset_or_self
		return {"AssetId": asset_id, "Name": "Asset %s" % str(asset_id), "PriceInRobux": 0, "IsForSale": false}

	func UserHasBadge(_user_or_self: Variant = null, _user_or_badge: Variant = null, _badge_id: Variant = null) -> bool:
		var user: Variant = _user_or_badge if _user_or_self is BobuxInstance else _user_or_self
		var badge: Variant = _badge_id if _user_or_self is BobuxInstance else _user_or_badge
		return bool(node.get_meta("_bobux_earned_badges", {}).get(str(user) + ":" + str(badge), false))

	func AwardBadge(_user_or_self: Variant = null, _user_or_badge: Variant = null, _badge_id: Variant = null) -> bool:
		var user: Variant = _user_or_badge if _user_or_self is BobuxInstance else _user_or_self
		var badge: Variant = _badge_id if _user_or_self is BobuxInstance else _user_or_badge
		var earned: Dictionary = node.get_meta("_bobux_earned_badges", {})
		earned[str(user) + ":" + str(badge)] = true
		node.set_meta("_bobux_earned_badges", earned)
		return true

	func LoadNumber(key_or_self: Variant, maybe_key: Variant = null) -> float:
		var key := str(maybe_key if key_or_self is BobuxInstance else key_or_self)
		return float(node.get_meta("_bobux_legacy_numbers", {}).get(key, 0.0))

	func SaveNumber(key_or_self: Variant, key_or_value: Variant, maybe_value: Variant = null) -> void:
		var key := str(key_or_value if key_or_self is BobuxInstance else key_or_self)
		var value := float(maybe_value if key_or_self is BobuxInstance else key_or_value)
		if not is_finite(value): return
		var numbers: Dictionary = node.get_meta("_bobux_legacy_numbers", {})
		numbers[key] = value
		node.set_meta("_bobux_legacy_numbers", numbers)

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
			mesh_inst.set_meta("roblox_class", "Part")
			mesh_inst.set_meta("bobux_lua_created_part", true)
			var stud_scale := BobuxInstance.wrap(workspace_node)._stud_scale()
			mesh_inst.set_meta("roblox_stud_scale", stud_scale)
			mesh_inst.add_to_group("studio_parts")
			mesh_inst.set_meta("shape_type", "Box")
			mesh_inst.set_meta("block_name", "Part_" + str(randi() % 10000))
			# Default geometry
			var box := BoxMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.WHITE
			box.surface_set_material(0, mat)
			mesh_inst.mesh = box
			mesh_inst.scale = Vector3(4.0, 1.0, 4.0) * stud_scale
			# Rebuild helpers / collision
			var studio = Engine.get_main_loop().current_scene
			if studio != null and studio.has_method("_rebuild_block_helpers"):
				studio.call("_rebuild_block_helpers", mesh_inst)
				studio.call("_update_block_collision", mesh_inst)
			var part_instance := BobuxInstance.wrap(mesh_inst)
			if parent_variant != null:
				part_instance._set(&"Parent", parent_variant)
			return part_instance
		var node := RobloxDataModelClass.create_instance(p_class_name, p_class_name)
		if node == null:
			node = Node.new()
		if node is Node3D:
			node.set_meta("roblox_stud_scale", BobuxInstance.wrap(workspace_node)._stud_scale())
		node.name = p_class_name
		node.set_meta("roblox_class", p_class_name)
		match p_class_name:
			"Folder", "Model", "Configuration":
				pass
			"RemoteEvent":
				node.set_meta("roblox_class", "RemoteEvent")
			"BindableEvent":
				node.set_meta("roblox_class", "BindableEvent")
			"ClickDetector":
				node.add_to_group("roblox_click_detectors")
				node.set_meta("max_activation_distance", 32.0)
			"ProximityPrompt":
				node.add_to_group("roblox_proximity_prompts")
				node.set_meta("max_activation_distance", 16.0)
				node.set_meta("action_text", "Interact")
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
		var instance := BobuxInstance.wrap(node)
		if parent_variant != null:
			instance._set(&"Parent", parent_variant)
		return instance

func _ready() -> void:
	_init_lua_engine()
	set_process(true)
	if OS.get_cmdline_user_args().has("--verify-lua-runtime"):
		_verify_exported_runtime.call_deferred()

func _verify_exported_runtime() -> void:
	if not is_active:
		push_error("BOBUX_LUA_SMOKE_FAILED: native LuaAPI is unavailable")
		get_tree().quit(1)
		return
	var context := Node.new()
	context.name = "PackagedLuaProbe"
	get_tree().root.add_child(context)
	var result := start_script("""
local value = Instance.new('IntValue')
value.Value = 40
value.Parent = script
local seen = false
value.Changed:Connect(function(newValue) seen = newValue == 42 end)
task.wait(0.02)
value.Value = value.Value + 2
task.wait(0.05)
assert(seen and value.Value == 42, 'native callback/scheduler failed')
script:SetAttribute('Passed', true)
""", context, {"realm": "server"})
	await get_tree().create_timer(0.8).timeout
	var passed := bool(result.get("ok", false)) and bool(context.get_meta("attribute_Passed", false)) and _runtime_failed_total == 0
	stop_all_scripts(context)
	context.queue_free()
	print("BOBUX_LUA_SMOKE_OK" if passed else "BOBUX_LUA_SMOKE_FAILED")
	get_tree().quit(0 if passed else 1)

func _exit_tree() -> void:
	stop_all_scripts()
	release_stopped_script_states()
	_service_nodes_cache.clear()
	_lua = null

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
	var ws_instance := BobuxInstance.wrap(workspace_node)
	var service_instances: Dictionary = {}
	for service_name in service_nodes.keys():
		service_instances[service_name] = BobuxInstance.wrap(service_nodes[service_name])
	
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
		"IsClient": func(): return false,
		"IsStudio": func(): return true,
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
		"Players": service_instances.get("Players", BobuxInstance.wrap(null)),
		"Lighting": service_instances.get("Lighting", BobuxInstance.wrap(null)),
		"ReplicatedStorage": service_instances.get("ReplicatedStorage", BobuxInstance.wrap(null)),
		"ServerStorage": service_instances.get("ServerStorage", BobuxInstance.wrap(null)),
		"StarterGui": service_instances.get("StarterGui", BobuxInstance.wrap(null)),
		"StarterPack": service_instances.get("StarterPack", BobuxInstance.wrap(null)),
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
					return BobuxInstance.wrap(_ensure_single_roblox_service(main_scene, service_name, workspace_node))
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
		_lua.push_variant("Color3", _build_color3_library())
		_lua.push_variant("RaycastParams", _build_raycast_params_library())
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
		_lua.push_variant("script", BobuxInstance.wrap(context_node))
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
	if _script_runtimes.size() + _pending_script_starts.size() >= MAX_CONCURRENT_SCRIPTS:
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
	var bind_error = lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine", "utf8", "debug"]))
	var bind_message := _lua_error_message(bind_error)
	if not bind_message.is_empty():
		return {"ok": false, "error": "Lua library binding failed: %s" % bind_message}
	var runtime_id := int(options.get("_reserved_runtime_id", 0))
	if runtime_id <= 0:
		runtime_id = _next_script_runtime_id
		_next_script_runtime_id += 1
	var runtime_options := options.duplicate()
	runtime_options["_runtime_id"] = runtime_id
	_push_runtime_bindings(lua, context_node, runtime_options)
	_push_lua_binding(lua, "__bobux_budget_expired", func() -> bool:
		if not _runtime_resume_started_usec.has(runtime_id):
			return false
		if Time.get_ticks_usec() - int(_runtime_resume_started_usec[runtime_id]) <= SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC:
			return false
		_runtime_budget_exceeded[runtime_id] = true
		return true
	)
	# Use native debug only to adapt value metatables, then remove it before
	# authored code runs. Scripts receive the restricted compatibility debug API.
	var type_setup: Variant = lua.do_string(_native_lua_type_setup())
	var type_setup_error := _lua_error_message(type_setup)
	if not type_setup_error.is_empty():
		return {"ok": false, "error": type_setup_error}
	# New coroutines inherit the private Lua hook. Throwing from Lua after the
	# budget callback returns avoids longjmp across native Godot Ref destructors.
	var coroutine = lua.new_coroutine()
	if coroutine == null:
		return {"ok": false, "error": "Could not create Lua coroutine."}
	var prepared_source := _prepare_scheduled_lua_source(lua_code)
	var load_error = coroutine.load_string(prepared_source)
	var load_message := _lua_error_message(load_error)
	if not load_message.is_empty():
		return {"ok": false, "error": "[LUA LOAD ERROR] %s" % load_message}

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
	elif is_instance_valid(context_or_runtime) and context_or_runtime is Node:
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
	for tween in _runtime_tweens.duplicate():
		if root_context == null or not is_instance_valid(tween.target.node) or tween.target.node == root_context or root_context.is_ancestor_of(tween.target.node):
			tween.dispose()
			_runtime_tweens.erase(tween)
	if root_context == null:
		_clear_all_runtime_event_connections(get_tree().root if is_inside_tree() else null)
		_pending_script_starts.clear()
		# Module return values and event callbacks may contain LuaCallable values.
		# The extension stores a raw lua_State pointer in those callables, so every
		# external callable must die before its owning LuaAPI closes the state.
		_module_cache.clear()
		_module_loading.clear()
		_module_cycle_warnings.clear()
		for runtime_id_variant in _script_runtimes.keys().duplicate():
			_dispose_script_runtime(int(runtime_id_variant))
		for runtime_id_variant in _retained_lua_states.keys().duplicate():
			_dispose_retained_lua_state(runtime_id_variant)
		_runtime_resume_started_usec.clear()
		_runtime_native_spans.clear()
		_runtime_budget_exceeded.clear()
		return
	_clear_all_runtime_event_connections(root_context)
	var remaining_pending: Array[Dictionary] = []
	for pending in _pending_script_starts:
		var pending_context: Variant = pending.get("context")
		if not is_instance_valid(pending_context) or pending_context == root_context or root_context.is_ancestor_of(pending_context):
			continue
		remaining_pending.append(pending)
	_pending_script_starts = remaining_pending
	# Module return values can be Lua callables owned by any runtime below this
	# root. Release them before disposing the corresponding Lua states.
	_module_cache.clear()
	_module_loading.clear()
	_module_cycle_warnings.clear()
	for runtime_id_variant in _script_runtimes.keys().duplicate():
		var runtime: Dictionary = _script_runtimes[runtime_id_variant]
		var context: Variant = runtime.get("context")
		if not is_instance_valid(context) or context == root_context or root_context.is_ancestor_of(context):
			_dispose_script_runtime(int(runtime_id_variant))
	for runtime_id_variant in _retained_lua_states.keys().duplicate():
		var retained: Dictionary = _retained_lua_states[runtime_id_variant]
		var context: Variant = retained.get("context")
		if not is_instance_valid(context) or context == root_context or root_context.is_ancestor_of(context):
			_dispose_retained_lua_state(runtime_id_variant)


func _dispose_script_runtime(runtime_id: int) -> void:
	_task_runtime_ids.erase(runtime_id)
	_runtime_native_spans.erase(runtime_id)
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	if not _script_runtimes.has(runtime_id):
		return
	var runtime: Dictionary = _script_runtimes[runtime_id]
	_script_runtimes.erase(runtime_id)
	_clear_script_runtime_marker(runtime.get("context"), runtime_id)
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
	_task_runtime_ids.erase(runtime_id)
	_runtime_native_spans.erase(runtime_id)
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	if not _retained_lua_states.has(runtime_id):
		return
	var retained: Dictionary = _retained_lua_states[runtime_id]
	_retained_lua_states.erase(runtime_id)
	_clear_script_runtime_marker(retained.get("context"), runtime_id)
	var lua: Variant = retained.get("lua")
	if lua != null:
		_stopped_lua_state_quarantine.append(lua)
	retained["lua"] = null
	retained.clear()


func _clear_script_runtime_marker(context: Variant, runtime_id: Variant) -> void:
	if is_instance_valid(context) and context.has_meta("bobux_script_runtime_id") and context.get_meta("bobux_script_runtime_id") == runtime_id:
		context.remove_meta("bobux_script_runtime_id")


func release_stopped_script_states() -> void:
	# Call only after the stopped playtest tree has survived at least one
	# process frame. LuaCallable destructors require their lua_State to exist.
	for lua in _stopped_lua_state_quarantine:
		if lua != null:
			# Run userdata finalizers while their LuaAPI/metatable owner is alive.
			# Closing the native state first leaves Godot proxy references behind.
			lua.do_string("local gc, globals = collectgarbage, _G; for key in pairs(globals) do globals[key] = nil end; gc('collect'); gc('collect')")
	_stopped_lua_state_quarantine.clear()


func set_scripts_paused(paused: bool) -> void:
	_scripts_paused = paused


func _process(delta: float) -> void:
	if _scripts_paused:
		return
	_process_pending_script_starts()
	_process_lua_tasks()
	_ensure_run_service_events()
	# Do not run an ever-growing set of frame callbacks while a large imported
	# place is still compiling. Once ready, dispatch them round-robin under one
	# shared deadline so a script-heavy place cannot freeze Studio or the client.
	if _pending_script_starts.is_empty():
		var event_deadline_usec := Time.get_ticks_usec() + SCRIPT_EVENT_TIME_BUDGET_USEC
		_run_service_stepped.FireBudgeted(
			SCRIPT_EVENT_CALLBACK_BUDGET_PER_FRAME,
			event_deadline_usec,
			Time.get_ticks_msec() / 1000.0,
			delta
		)
		if Time.get_ticks_usec() < event_deadline_usec:
			_run_service_heartbeat.FireBudgeted(
				SCRIPT_EVENT_CALLBACK_BUDGET_PER_FRAME,
				event_deadline_usec,
				delta
			)
		if Time.get_ticks_usec() < event_deadline_usec:
			_run_service_render_stepped.FireBudgeted(
				SCRIPT_EVENT_CALLBACK_BUDGET_PER_FRAME,
				event_deadline_usec,
				delta
			)
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
		var context := _live_node(runtime.get("context"))
		if context == null or context.is_queued_for_deletion() or not context.is_inside_tree():
			_dispose_script_runtime(runtime_id)
			continue
		if now + 0.0001 >= float(runtime.get("wake_at", 0.0)):
			_resume_script_runtime(runtime_id)
			resumed += 1
			if resumed >= SCRIPT_RESUME_BUDGET_PER_FRAME or Time.get_ticks_usec() - frame_started_usec >= SCRIPT_RESUME_TIME_BUDGET_USEC:
				break
	_scheduler_cursor = (start_index + inspected) % maxi(runtime_ids.size(), 1)


func _process_lua_tasks() -> void:
	var runtime_ids := _task_runtime_ids.keys()
	if runtime_ids.is_empty():
		return
	var started_usec := Time.get_ticks_usec()
	var processed := 0
	var start_index := _task_scheduler_cursor % runtime_ids.size()
	while processed < runtime_ids.size() and processed < SCRIPT_RESUME_BUDGET_PER_FRAME:
		var runtime_id := int(runtime_ids[(start_index + processed) % runtime_ids.size()])
		processed += 1
		var runtime: Dictionary = _script_runtimes.get(runtime_id, _retained_lua_states.get(runtime_id, {}))
		var context := _live_node(runtime.get("context"))
		var lua: Variant = runtime.get("lua")
		if lua == null or context == null or context.is_queued_for_deletion() or not context.is_inside_tree():
			_dispose_script_runtime(runtime_id)
			_dispose_retained_lua_state(runtime_id)
			continue
		_runtime_resume_started_usec[runtime_id] = Time.get_ticks_usec()
		_runtime_native_spans.erase(runtime_id)
		_runtime_budget_exceeded.erase(runtime_id)
		var result: Variant = lua.call_function("__bobux_step_tasks", [])
		_runtime_native_spans.erase(runtime_id)
		_runtime_resume_started_usec.erase(runtime_id)
		var error_message := _lua_error_message(result)
		if not error_message.is_empty():
			_report_task_error(runtime_id, error_message)
			_task_runtime_ids.erase(runtime_id)
		_runtime_budget_exceeded.erase(runtime_id)
		if Time.get_ticks_usec() - started_usec >= SCRIPT_RESUME_TIME_BUDGET_USEC:
			break
	_task_scheduler_cursor = (start_index + processed) % runtime_ids.size()


func _report_task_error(runtime_id: int, message: String) -> void:
	var runtime: Dictionary = _script_runtimes.get(runtime_id, _retained_lua_states.get(runtime_id, {}))
	_runtime_failed_total += 1
	_runtime_last_errors.append("%s task: %s" % [runtime.get("source_name", "Script"), message])
	_emit_script_message(_live_node(runtime.get("context")), message, true)
	if _runtime_last_errors.size() > 64:
		_runtime_last_errors.pop_front()
	push_warning("[LuaScriptEngine] Task failed: %s" % message)


func _exclude_native_work(start_usec: int) -> void:
	var end_usec := Time.get_ticks_usec()
	for id in _runtime_resume_started_usec:
		var spans: Array = _runtime_native_spans.get(id, [])
		var added := end_usec - start_usec
		var union_start := start_usec
		while not spans.is_empty() and int(spans.back()[1]) >= start_usec:
			var previous: Array = spans.pop_back()
			added -= int(previous[1]) - maxi(int(previous[0]), start_usec)
			union_start = mini(union_start, int(previous[0]))
		spans.append([union_start, end_usec])
		_runtime_native_spans[id] = spans
		_runtime_resume_started_usec[id] = int(_runtime_resume_started_usec[id]) + maxi(0, added)


func _resume_script_runtime(runtime_id: int) -> Dictionary:
	if not _script_runtimes.has(runtime_id):
		return {"ok": false, "error": "Script runtime no longer exists."}
	var runtime: Dictionary = _script_runtimes[runtime_id]
	var coroutine = runtime.get("coroutine")
	if coroutine == null:
		_dispose_script_runtime(runtime_id)
		return {"ok": false, "error": "Script coroutine is missing."}
	_runtime_resume_started_usec[runtime_id] = Time.get_ticks_usec()
	_runtime_native_spans.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	var result: Variant = coroutine.resume([])
	_runtime_native_spans.erase(runtime_id)
	_runtime_resume_started_usec.erase(runtime_id)
	var error_message := _lua_error_message(result)
	if _runtime_budget_exceeded.has(runtime_id):
		error_message = "Script exceeded the %.1f ms execution budget without yielding." % [float(SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC) / 1000.0]
		_runtime_budget_exceeded.erase(runtime_id)
	if not error_message.is_empty():
		# A script can connect callbacks before its first later error. Keep the
		# owning Lua state alive until Stop so those callbacks never point at a
		# closed lua_State.
		var failed_context := _live_node(runtime.get("context"))
		var failed_name := str(runtime.get("source_name", "Script"))
		_retain_stopped_runtime(runtime_id, runtime)
		_runtime_failed_total += 1
		_runtime_last_errors.append("%s: %s" % [failed_name, error_message])
		_emit_script_message(failed_context, error_message, true)
		if _runtime_last_errors.size() > 64:
			_runtime_last_errors.pop_front()
		push_warning("[LuaScriptEngine] %s: %s" % [failed_name, error_message])
		return {"ok": false, "error": "[LUA ERROR] %s" % error_message, "runtime_id": runtime_id}
	if bool(coroutine.is_done()):
		_script_runtimes.erase(runtime_id)
		_runtime_completed_total += 1
		if bool(runtime.get("retain", true)):
			_retained_lua_states[runtime_id] = {
				"lua": runtime.get("lua"),
				"coroutine": runtime.get("coroutine"),
				"context": runtime.get("context"),
				"source_name": runtime.get("source_name", "Script"),
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
	_runtime_native_spans.erase(runtime_id)
	_runtime_resume_started_usec.erase(runtime_id)
	_runtime_budget_exceeded.erase(runtime_id)
	_script_runtimes.erase(runtime_id)
	var lua: Variant = runtime.get("lua")
	if lua != null:
		_retained_lua_states[runtime_id] = {
			"lua": lua,
			"coroutine": runtime.get("coroutine"),
			"context": runtime.get("context"),
			"source_name": runtime.get("source_name", "Script"),
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
		var context := _live_node(pending.get("context"))
		if context == null or context.is_queued_for_deletion() or not context.is_inside_tree():
			continue
		var result := start_script(
			str(pending.get("source", "")),
			context,
			pending.get("options", {}) as Dictionary
		)
		if not bool(result.get("ok", false)):
			_runtime_failed_total += 1
			_emit_script_message(context, str(result.get("error", "Script compilation failed")), true)
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
			(event_variant as BobuxEvent).Disconnect()


func _clear_runtime_event_connections_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_meta("bobux_script_runtime_id"):
		node.remove_meta("bobux_script_runtime_id")
	if node.has_meta("_bobux_pressed_keys"):
		node.remove_meta("_bobux_pressed_keys")
	for bridge in node.get_meta("_bobux_signal_callbacks", []):
		if node.is_connected(bridge.signal, bridge.callback):
			node.disconnect(bridge.signal, bridge.callback)
	if node.has_meta("_bobux_signal_callbacks"):
		node.remove_meta("_bobux_signal_callbacks")
	if node.has_meta("_bobux_event_registry"):
		var registry: Variant = node.get_meta("_bobux_event_registry")
		if registry is Dictionary:
			for event_variant in (registry as Dictionary).values():
				if event_variant is BobuxEvent:
					(event_variant as BobuxEvent).Disconnect()
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


func _owned_lua_bindings(value: Variant) -> Variant:
	# LuaAPI's mt_Callable lacks a userdata finalizer in the shipped extension.
	# LuaCallableExtra has one and releases captured proxies when a VM closes.
	if value is Callable and ClassDB.class_exists("LuaCallableExtra"):
		var wrapper: Variant = ClassDB.instantiate("LuaCallableExtra")
		wrapper.set_info(value, 0, false, false)
		return wrapper
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _owned_lua_bindings(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_owned_lua_bindings(item))
		return result
	return value

func _push_lua_binding(target: Object, name: String, value: Variant) -> void:
	target.call("push_variant", name, _owned_lua_bindings(value))

func _create_roblox_tween(arg1: Variant, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null) -> BobuxTween:
	var item: Variant = arg2 if arg4 != null else arg1
	var info: Variant = arg3 if arg4 != null else arg2
	var goals: Variant = arg4 if arg4 != null else arg3
	if not item is BobuxInstance or not goals is Dictionary:
		return null
	var tween := BobuxTween.new()
	tween.engine = self
	tween.target = item
	tween.info = info if info is Dictionary else {}
	tween.goals = goals.duplicate()
	_runtime_tweens.append(tween)
	return tween

func _push_runtime_bindings(target: Object, context_node: Node, options: Dictionary) -> void:
	_push_lua_binding(target, "Region3", {"new": func(minimum: Vector3, maximum: Vector3): return {"CFrame": BobuxCFrame.new(Transform3D(Basis.IDENTITY, (minimum + maximum) * 0.5)), "Size": (maximum - minimum).abs()}})
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
	var workspace_instance := BobuxInstance.wrap(workspace_node)
	var service_instances: Dictionary = {}
	for service_name_variant in service_nodes.keys():
		var service_name := str(service_name_variant)
		service_instances[service_name] = BobuxInstance.wrap(service_nodes[service_name])
	_ensure_run_service_events()
	var is_server := bool(options.get("is_server", str(options.get("realm", "")).to_lower() in ["server", "studio"]))
	var run_service: Dictionary = _owned_lua_bindings({
		"Heartbeat": _run_service_heartbeat,
		"Stepped": _run_service_stepped,
		"RenderStepped": _run_service_render_stepped,
		"IsServer": func(): return is_server,
		"IsClient": func(): return not is_server,
		"IsStudio": func(): return str(options.get("realm", "")).to_lower() == "studio",
	})
	var tween_service: Dictionary = _owned_lua_bindings({"Create": _create_roblox_tween})
	var debris_service: Dictionary = _owned_lua_bindings({
		"AddItem": func(arg1: Variant, arg2: Variant = null, arg3: Variant = null):
			var item: Variant = arg2 if arg2 is BobuxInstance else arg1
			var lifetime := float(arg3 if arg2 is BobuxInstance and arg3 != null else (arg2 if arg2 != null and not (arg2 is BobuxInstance) else 0.0))
			_schedule_debris_item(item, lifetime)
	})
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
					return BobuxInstance.wrap(_ensure_single_roblox_service(main_scene, service_name, workspace_node))
	}
	for service_name_variant in service_instances.keys():
		game_proxy[str(service_name_variant)] = service_instances[service_name_variant]
	game_proxy["RunService"] = run_service
	game_proxy["TweenService"] = tween_service
	game_proxy["Debris"] = debris_service

	_push_lua_binding(target, "game", game_proxy)
	_push_lua_binding(target, "workspace", workspace_instance)
	_push_lua_binding(target, "Instance", BobuxInstanceCreator.new(workspace_node))
	_push_lua_binding(target, "Vector3", {"new": func(x: Variant = 0.0, y: Variant = 0.0, z: Variant = 0.0): return Vector3(float(x), float(y), float(z))})
	_push_lua_binding(target, "Vector2", {"new": func(x: Variant = 0.0, y: Variant = 0.0): return Vector2(float(x), float(y))})
	_push_lua_binding(target, "Ray", {"new": func(origin: Variant = Vector3.ZERO, direction: Variant = Vector3.ZERO): return BobuxRay.new(origin, direction)})
	_push_lua_binding(target, "CFrame", _build_cframe_library())
	_push_lua_binding(target, "Color3", _build_color3_library())
	_push_lua_binding(target, "RaycastParams", _build_raycast_params_library())
	_push_lua_binding(target, "OverlapParams", {"new": func(_self_arg: Variant = null): return BobuxOverlapParams.new()})
	_push_lua_binding(target, "BrickColor", _build_brick_color_library())
	_push_lua_binding(target, "UDim", {"new": func(scale: Variant = 0.0, offset: Variant = 0.0): return {"scale": float(scale), "offset": float(offset)}})
	_push_lua_binding(target, "UDim2", {
		"new": func(xs: Variant = 0.0, xo: Variant = 0.0, ys: Variant = 0.0, yo: Variant = 0.0): return {"x": {"scale": float(xs), "offset": float(xo)}, "y": {"scale": float(ys), "offset": float(yo)}},
		"fromScale": func(x: Variant = 0.0, y: Variant = 0.0): return {"x": {"scale": float(x), "offset": 0.0}, "y": {"scale": float(y), "offset": 0.0}},
		"fromOffset": func(x: Variant = 0.0, y: Variant = 0.0): return {"x": {"scale": 0.0, "offset": float(x)}, "y": {"scale": 0.0, "offset": float(y)}},
	})
	_push_lua_binding(target, "TweenInfo", {"new": func(duration: Variant = 1.0, style: Variant = 0, direction: Variant = 1, repeats: Variant = 0, reverses: Variant = false, delay_time: Variant = 0.0): return {"Time": float(duration), "EasingStyle": style, "EasingDirection": direction, "RepeatCount": repeats, "Reverses": reverses, "DelayTime": delay_time}})
	_push_lua_binding(target, "Random", {
		"new": func(seed_or_self: Variant = null, maybe_seed: Variant = null):
			var seed_value: Variant = maybe_seed if seed_or_self is Dictionary else seed_or_self
			return BobuxRandom.new(seed_value)
	})
	_push_lua_binding(target, "os", {
		"time": func(_value: Variant = null): return int(Time.get_unix_time_from_system()),
		"clock": func(): return Time.get_ticks_usec() / 1000000.0,
		"difftime": func(first: Variant = 0.0, second: Variant = 0.0): return float(first) - float(second),
		"date": func(_format: Variant = "%c", timestamp: Variant = null):
			var unix_time := int(timestamp) if timestamp != null else int(Time.get_unix_time_from_system())
			return Time.get_datetime_string_from_unix_time(unix_time, true),
	})
	_push_lua_binding(target, "Enum", _build_enum_proxy())
	_push_lua_binding(target, "script", BobuxInstance.wrap(context_node))
	_push_lua_binding(target, "__bobux_log", func(message: String, is_error: bool): _emit_script_message(context_node, message, is_error))
	_push_lua_binding(target, "tick", func(): return Time.get_ticks_msec() / 1000.0)
	_push_lua_binding(target, "__bobux_module_source", _module_source_for_runtime)
	var runtime_id := int(options.get("_runtime_id", 0))
	_push_lua_binding(target, "__bobux_begin_task_slice", func() -> bool:
		if _runtime_resume_started_usec.has(runtime_id):
			return false
		_runtime_resume_started_usec[runtime_id] = Time.get_ticks_usec()
		_runtime_native_spans.erase(runtime_id)
		return true
	)
	_push_lua_binding(target, "__bobux_end_task_slice", func(owned: bool):
		if owned:
			_runtime_native_spans.erase(runtime_id)
			_runtime_resume_started_usec.erase(runtime_id)
			_runtime_budget_exceeded.erase(runtime_id)
	)
	_push_lua_binding(target, "__bobux_tasks_active", func(active: bool):
		if active:
			_task_runtime_ids[runtime_id] = true
		else:
			_task_runtime_ids.erase(runtime_id)
	)
	_push_lua_binding(target, "__bobux_task_error", func(message: Variant): _report_task_error(runtime_id, str(message)))
	_push_lua_binding(target, "__bobux_set", func(item: Variant, property_name: Variant, value: Variant):
		_last_property_setter_calls += 1
		_last_property_setter_target_type = type_string(typeof(item))
		if item is Object:
			_last_property_setter_target_class = (item as Object).get_class()
			_last_property_setter_has_set_property = (item as Object).has_method("SetProperty")
		if item is BobuxInstance:
			(item as BobuxInstance)._set(str(property_name), value)
		return value
	)


func _emit_script_message(context: Node, message: String, is_error: bool) -> void:
	print("[LUA] ", message)
	if is_instance_valid(context):
		script_message.emit(context, message, is_error)

func normalize_script_source(source: String) -> String:
	# Pasted Windows scripts and multiline GDScript constants may carry CRLF.
	# Lua itself normalizes physical line endings; compatibility parsing must too.
	source = source.replace("\r\n", "\n").replace("\r", "\n")
	# Decode whitespace artifacts only in code, preserving literals and comments.
	var tokens := _lua_tokens(source)
	var entities := {"&#x20;": " ", "&#32;": " ", "&#160;": " ", "&nbsp;": " ", "&#x9;": "\t", "&#9;": "\t"}
	for index in range(tokens.size() - 1, -1, -1):
		var token: Dictionary = tokens[index]
		if str(token.text) != "&":
			continue
		for entity in entities:
			if source.substr(int(token.start), str(entity).length()).to_lower() == entity:
				source = source.left(int(token.start)) + str(entities[entity]) + source.substr(int(token.start) + str(entity).length())
				break
	return source

func _prepare_lua_body(lua_code: String) -> String:
	var lexer = preload("res://addons/roblox_studio/roblox_lua_lexer.gd")
	var protected: Dictionary = lexer.protect_strings(_replace_luau_backtick_strings(normalize_script_source(lua_code)))
	var rewritten := _rewrite_luau_compatibility(protected.source)
	rewritten = _rewrite_lua_property_assignments(rewritten)
	rewritten = _rewrite_lua_multi_return_calls(rewritten)
	# Classic Roblox scripts used lowercase RBXScriptSignal:connect(). On a
	# RefCounted proxy that spelling otherwise resolves to Godot Object.connect
	# and attempts to connect a signal with an empty name.
	return lexer.restore_strings(_rewrite_lua_async_calls(rewritten), protected.literals)

func _native_lua_type_setup() -> String:
	return """
do
    local getmeta = debug.getmetatable
    local types = {}
    local function vector_type(sample, name)
        local meta = getmeta(sample)
        types[meta] = name
        local index, multiply = meta.__index, meta.__mul
		local names = {X='x', Y='y', Z='z', Dot='dot', Cross='cross', Lerp='lerp', Angle='angle_to', FuzzyEq='is_equal_approx', Abs='abs', Sign='sign', Floor='floor', Ceil='ceil', Max='max', Min='min'}
        meta.__index = function(value, key)
			if key == 'Magnitude' or key == 'magnitude' then return index(value, 'length')() end
			if key == 'Unit' or key == 'unit' then return index(value, 'normalized')() end
            local member = index(value, names[key] or key)
			if type(member) == 'function' then
				-- Godot's vector methods are already bound. Strip Lua's colon
                -- self argument and retain value while the bound method lives.
                return function(first, ...)
                    if first == value then return member(...) end
                    return member(first, ...)
                end
            end
            return member
        end
        meta.__unm = function(value) return value * -1 end
		meta.__mul = function(a, b) if type(a) == 'number' then return multiply(b, a) end return multiply(a, b) end
    end
	vector_type(Vector3.new(), 'Vector3')
	vector_type(Vector2.new(), 'Vector2')
    Vector3.zero, Vector3.one = Vector3.new(), Vector3.new(1, 1, 1)
    Vector3.xAxis, Vector3.yAxis, Vector3.zAxis = Vector3.new(1,0,0), Vector3.new(0,1,0), Vector3.new(0,0,1)
    Vector2.zero, Vector2.one = Vector2.new(), Vector2.new(1,1)
    local color_meta = getmeta(Color3.new())
	types[color_meta] = 'Color3'
    local color_index = color_meta.__index
    color_meta.__index = function(value, key)
		local member = color_index(value, ({R='r', G='g', B='b', Lerp='lerp'})[key] or key)
		if type(member) == 'function' then
            return function(first, ...)
                if first == value then return member(...) end
                return member(first, ...)
            end
        end
        return member
    end
    typeof = function(value)
        local kind = type(value)
		if kind ~= 'userdata' then return kind end
        local known = types[getmeta(value)]
        if known then return known end
        local ok, class = pcall(function() return value.ClassName end)
		if ok and class ~= nil then return 'Instance' end
        local frame, position = pcall(function() return value.LookVector end)
		if frame and position ~= nil then return 'CFrame' end
        return kind
    end
    local budget_expired, raise = __bobux_budget_expired, error
    if budget_expired then
        local sethook = debug.sethook
        local hook = function()
			if budget_expired() then raise('Script execution budget exceeded', 0) end
        end
		sethook(hook, '', 1000)
		__bobux_install_hook = function() sethook(hook, '', 1000) end
        local create = coroutine.create
        coroutine.create = function(callback)
            local thread = create(callback)
			sethook(thread, hook, '', 1000)
            return thread
        end
    end
    __bobux_budget_expired = nil
    debug = nil
end
"""


func _prepare_scheduled_lua_source(lua_code: String) -> String:
	var rewritten := _prepare_lua_body(lua_code)
	var prelude := """
if __bobux_install_hook then __bobux_install_hook(); __bobux_install_hook = nil end
local __bobux_native_set = __bobux_set
function __bobux_set(target, key, value)
    if type(target) == 'table' then target[key] = value
    else __bobux_native_set(target, key, value) end
    return value
end
local function __bobux_print(is_error, ...)
    local values = {}
	for index = 1, select('#', ...) do
        values[index] = tostring(select(index, ...))
    end
	__bobux_log(table.concat(values, '\\t'), is_error)
end
function print(...) __bobux_print(false, ...) end
function warn(...) __bobux_print(true, ...) end
-- Android and older LuaAPI builds may omit the coroutine library. Roblox
-- scripts must still start, even when that optional native library is absent.
coroutine = coroutine or {}
local __bobux_raw_coroutine_yield = type(coroutine.yield) == 'function' and coroutine.yield or nil
local __bobux_unpack = table.unpack or unpack
coroutine.create = coroutine.create or function(callback)
	return {__bobux_callback = callback, __bobux_status = 'suspended'}
end
coroutine.resume = coroutine.resume or function(thread, ...)
	if type(thread) ~= 'table' or type(thread.__bobux_callback) ~= 'function' then
		return false, 'invalid coroutine'
    end
	if thread.__bobux_status == 'dead' then return false, 'cannot resume dead coroutine' end
	thread.__bobux_status = 'running'
    local result = {pcall(thread.__bobux_callback, ...)}
	thread.__bobux_status = 'dead'
    return __bobux_unpack(result)
end
coroutine.status = coroutine.status or function(thread)
	return type(thread) == 'table' and (thread.__bobux_status or 'dead') or 'dead'
end
coroutine.wrap = function(callback)
    local thread = coroutine.create(callback)
    return function(...)
        local result = {coroutine.resume(thread, ...)}
        if not result[1] then error(result[2]) end
        table.remove(result, 1)
        return __bobux_unpack(result)
    end
end
function wait(seconds)
    local duration = math.max(tonumber(seconds) or 0.03, 0)
    local started = os.clock()
    if __bobux_raw_coroutine_yield ~= nil then
        __bobux_raw_coroutine_yield(duration)
        return os.clock() - started
    end
    return duration
end
task = task or {}
task.wait = wait
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.pow = math.pow or function(x, y) return x ^ y end
math.log10 = math.log10 or function(x) return math.log(x, 10) end
local __bobux_tasks = {}
local function __bobux_pack(...) return {n = select('#', ...), ...} end
local function __bobux_dispatch(receiver, method, ...)
	if type(receiver) == 'table' then return receiver[method](receiver, ...) end
	return receiver:DispatchPacked(method, {...}, select('#', ...))
end
function __bobux_fire_server(receiver, ...) return __bobux_dispatch(receiver, 'FireServer', ...) end
function __bobux_fire_client(receiver, ...) return __bobux_dispatch(receiver, 'FireClient', ...) end
function __bobux_fire_all_clients(receiver, ...) return __bobux_dispatch(receiver, 'FireAllClients', ...) end
function __bobux_fire(receiver, ...) return __bobux_dispatch(receiver, 'Fire', ...) end
function __bobux_invoke_server(receiver, ...) return __bobux_dispatch(receiver, 'InvokeServer', ...) end
function __bobux_invoke_client(receiver, ...) return __bobux_dispatch(receiver, 'InvokeClient', ...) end
function __bobux_invoke(receiver, ...) return __bobux_dispatch(receiver, 'Invoke', ...) end
local __bobux_begin_slice, __bobux_end_slice = __bobux_begin_task_slice, __bobux_end_task_slice
__bobux_begin_task_slice, __bobux_end_task_slice = nil, nil
local function __bobux_resume_task(entry)
    if entry.cancelled then return end
    local args = entry.args
    entry.args = {n = 0}
    local owned_slice = __bobux_begin_slice()
    local ok, duration = coroutine.resume(entry.thread, __bobux_unpack(args, 1, args.n))
    __bobux_end_slice(owned_slice)
    if not ok then
        __bobux_task_error(tostring(duration))
        entry.cancelled = true
	elseif coroutine.status(entry.thread) == 'dead' then
        entry.cancelled = true
    else
        entry.wake_at = os.clock() + math.max(tonumber(duration) or 0, 0)
    end
end
local function __bobux_schedule_task(callback, duration, immediately, ...)
	assert(type(callback) == 'function' or type(callback) == 'thread', 'task expects a function or thread')
    local entry = {args = __bobux_pack(...), wake_at = os.clock() + duration}
    local thread
	if type(callback) == 'thread' then
        thread = callback
    else
        thread = coroutine.create(function(...)
            local results = __bobux_pack(callback(...))
            -- Native exported callbacks may leave values on their origin
			-- thread's stack. Record completion rather than infer it from that
			-- stack via coroutine.status when deciding whether to resume.
			entry.cancelled = true
			return __bobux_unpack(results, 1, results.n)
		end)
	end
	entry.thread = thread
	table.insert(__bobux_tasks, entry)
	__bobux_tasks_active(true)
	if immediately then __bobux_resume_task(entry) end
	return thread
end
function task.spawn(callback, ...) return __bobux_schedule_task(callback, 0, true, ...) end
function task.defer(callback, ...) return __bobux_schedule_task(callback, 0, false, ...) end
function task.delay(seconds, callback, ...)
	return __bobux_schedule_task(callback, math.max(tonumber(seconds) or 0, 0), false, ...)
end
function task.cancel(thread)
	for _, entry in ipairs(__bobux_tasks) do
		if entry.thread == thread then entry.cancelled = true end
	end
end
function __bobux_step_tasks()
	local now, count = os.clock(), #__bobux_tasks
	for index = 1, count do
		local entry = __bobux_tasks[index]
		if not entry.cancelled and entry.wake_at <= now then __bobux_resume_task(entry) end
		if os.clock() - now > 0.002 then break end
	end
	for index = #__bobux_tasks, 1, -1 do
		if __bobux_tasks[index].cancelled then table.remove(__bobux_tasks, index) end
	end
	__bobux_tasks_active(#__bobux_tasks > 0)
end
spawn = task.spawn
delay = task.delay
local __bobux_checkpoint_at = os.clock()
function __bobux_checkpoint()
    local now = os.clock()
    if now - __bobux_checkpoint_at >= 0.008 and coroutine.isyieldable() then
        wait(0)
        __bobux_checkpoint_at = os.clock()
    end
end
local __bobux_modules, __bobux_loading = {}, {}
function require(module)
	local descriptor = __bobux_module_source(module)
	assert(descriptor.error == nil, descriptor.error)
	local key = descriptor.key
	if __bobux_modules[key] ~= nil then return __bobux_modules[key] end
	assert(not __bobux_loading[key], 'Circular ModuleScript require: ' .. descriptor.name)
	__bobux_loading[key] = true
	local factory, load_error = load('return function(script) ' .. descriptor.source .. '\\nend', '@' .. descriptor.name, 't')
	if factory == nil then __bobux_loading[key] = nil; error(load_error, 2) end
	local module_function = factory()
	local results = __bobux_pack(pcall(module_function, module))
	__bobux_loading[key] = nil
	if not results[1] then error(results[2], 2) end
	assert(results.n == 2 and results[2] ~= nil, 'ModuleScript must return exactly one non-nil value: ' .. descriptor.name)
	__bobux_modules[key] = results[2]
	return results[2]
end
function __bobux_connect(signal, callback)
	if type(signal) == 'table' then return signal:Connect(callback) end
	-- LuaAPI stores the exporting coroutine's lua_State pointer in a Callable.
	-- Retain that thread through the registered function's upvalue until the
	-- connection is released; a completed task may otherwise be collected.
	local origin = coroutine.running()
	return signal:Connect(function(...)
		if origin then task.spawn(callback, ...) end
	end)
end
function __bobux_once(signal, callback)
	if type(signal) == 'table' then return signal:Once(callback) end
	local origin = coroutine.running()
	return signal:Once(function(...)
		if origin then task.spawn(callback, ...) end
	end)
end
function __bobux_disconnect(connection, ...)
	if type(connection) == 'table' then
		return (connection.disconnect or connection.Disconnect)(connection, ...)
	end
	return connection:Disconnect(...)
end
function __bobux_wait_for_child(parent, name, timeout)
	if type(parent) == 'table' then return parent:WaitForChild(name, timeout) end
	local started = os.clock()
	while true do
		local child = parent:FindFirstChild(name)
		if child ~= nil then return child end
		if timeout ~= nil and os.clock() - started >= timeout then return nil end
		task.wait(0)
	end
end
function __bobux_signal_wait(signal, ...)
	if type(signal) == 'table' then return signal:Wait(...) end
	local received
	local origin = coroutine.running()
	local connection = signal:Once(function(...)
		if origin then received = __bobux_pack(...) end
	end)
	while received == nil do task.wait(0) end
	return __bobux_unpack(received, 1, received.n)
end
typeof = typeof or type
function newproxy(with_metatable)
	local proxy = {}
	if with_metatable then setmetatable(proxy, {}) end
	return proxy
end
debug = debug or {}
debug.info = debug.info or function() return '' end
debug.traceback = debug.traceback or function(message) return tostring(message or '') end
debug.setmemorycategory = debug.setmemorycategory or function(_category) end
table.clone = table.clone or function(source)
	local result = {}
	if source ~= nil then for key, value in pairs(source) do result[key] = value end end
	return result
end
table.clear = table.clear or function(source)
	if source ~= nil then for key in pairs(source) do source[key] = nil end end
end
table.find = table.find or function(source, needle)
	if source ~= nil then for key, value in pairs(source) do if value == needle then return key end end end
	return nil
end
table.create = table.create or function(count, value)
	local result = {}
	for index = 1, tonumber(count) or 0 do result[index] = value end
	return result
end
table.freeze = table.freeze or function(source) return source end
math.clamp = math.clamp or function(value, minimum, maximum)
	return math.max(tonumber(minimum) or 0, math.min(tonumber(maximum) or 0, tonumber(value) or 0))
end
math.round = math.round or function(value) return math.floor((tonumber(value) or 0) + 0.5) end
string.split = string.split or function(value, separator)
	value = tostring(value or '')
	separator = tostring(separator or ',')
	if separator == '' then return {value} end
	local result, start = {}, 1
	while true do
		local first, last = string.find(value, separator, start, true)
		if first == nil then table.insert(result, string.sub(value, start)); break end
		table.insert(result, string.sub(value, start, first - 1))
		start = last + 1
	end
	return result
end
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


func _rewrite_luau_compatibility(lua_code: String) -> String:
	var rewritten := lua_code.replace("%*", "%s")
	rewritten = _replace_luau_backtick_strings(rewritten)
	rewritten = _comment_multiline_luau_type_declarations(rewritten)
	var numeric_separator_regex := RegEx.new()
	if numeric_separator_regex.compile("([0-9])_([0-9])") == OK:
		# Repeat because global non-overlapping replacement of `1_000_000` may
		# leave the second separator adjacent to the first replacement.
		while numeric_separator_regex.search(rewritten) != null:
			rewritten = numeric_separator_regex.sub(rewritten, "$1$2", true)
	# Keep this grammar deliberately narrow. A broad "anything until =" pattern
	# can mistake Roblox method calls (`object:Method`) for Luau annotations and
	# silently remove whitespace from otherwise valid classic Lua sources.
	var type_atom := "(?:[A-Za-z_][A-Za-z0-9_.?]*(?:<[^>,)=\\n]+>)?(?:\\[\\])?|\\{[^}\\n]+\\})"
	var type_expression := type_atom + "(?:[\\t ]*\\|[\\t ]*" + type_atom + ")*"
	var local_type_regex := RegEx.new()
	local_type_regex.compile("^([\\t ]*local[\\t ]+[A-Za-z_][A-Za-z0-9_]*)[\\t ]*:[\\t ]*(?:" + type_expression + ")([\\t ]*=)")
	var parameter_type_regex := RegEx.new()
	parameter_type_regex.compile("([,(][\\t ]*[A-Za-z_][A-Za-z0-9_]*)[\\t ]*:[\\t ]*(?:" + type_expression + ")([,)=])")
	var vararg_type_regex := RegEx.new()
	vararg_type_regex.compile("([,(][\\t ]*\\.\\.\\.)[\\t ]*:[\\t ]*(?:" + type_expression + ")([,)=])")
	var return_type_regex := RegEx.new()
	return_type_regex.compile("(\\))[\\t ]*:[\\t ]*(?:" + type_expression + ")([\\t ]*(?:$|do|[;{]))")
	var cast_regex := RegEx.new()
	cast_regex.compile("[\\t ]*::[\\t ]*(?:" + type_expression + ")")
	var generic_function_regex := RegEx.new()
	generic_function_regex.compile("(function[\\t ]+[A-Za-z_][A-Za-z0-9_%.:]*)<[^>]+>([\\t ]*\\()")
	var compound_regex := RegEx.new()
	compound_regex.compile("^([\\t ]*)([A-Za-z_][A-Za-z0-9_.\\[\\]\\\"']*)[\\t ]*([+*/-])=[\\t ]*(.+?)(;?)[\\t ]*$")
	var generalized_for_regex := RegEx.new()
	generalized_for_regex.compile("^([\\t ]*)for[\\t ]+(.+)[\\t ]+in[\\t ]+(.+)[\\t ]+do([\\t ]*(?:--.*)?)$")
	var if_expression_regex := RegEx.new()
	if_expression_regex.compile("^(.*?return[\\t ]+)if[\\t ]+(.+)[\\t ]+then[\\t ]+(.+)[\\t ]+else[\\t ]+(.+?)([,;]?)[\\t ]*$")
	var parenthesized_if_regex := RegEx.new()
	parenthesized_if_regex.compile("\\(if[\\t ]+(.+?)[\\t ]+then[\\t ]+(.+?)[\\t ]+else[\\t ]+([A-Za-z_][A-Za-z0-9_.\\[\\]]*)\\)")
	var embedded_if_regex := RegEx.new()
	embedded_if_regex.compile("([,(=][\\t ]*)if[\\t ]+(.+?)[\\t ]+then[\\t ]+(.+?)[\\t ]+else[\\t ]+(\\\"(?:\\\\.|[^\\\"])*\\\"|'(?:\\\\.|[^'])*'|[A-Za-z_][A-Za-z0-9_.\\[\\]]*|[-+]?[0-9]+(?:\\.[0-9]+)?|true|false|nil)")
	var output: Array[String] = []
	for raw_line in rewritten.split("\n"):
		var line := str(raw_line)
		var stripped := line.strip_edges()
		if stripped.begins_with("--!strict") or stripped.begins_with("--!native") or stripped.begins_with("--!optimize"):
			output.append("-- " + stripped.trim_prefix("--!"))
			continue
		if stripped.begins_with("export type ") or stripped.begins_with("type "):
			output.append("-- Bobux ignored Luau type declaration: " + stripped)
			continue
		line = _strip_luau_function_annotations(line)
		line = _strip_luau_local_annotation(line)
		line = local_type_regex.sub(line, "$1$2", true)
		while parameter_type_regex.search(line) != null:
			line = parameter_type_regex.sub(line, "$1$2", false)
		while vararg_type_regex.search(line) != null:
			line = vararg_type_regex.sub(line, "$1$2", false)
		line = return_type_regex.sub(line, "$1$2", true)
		line = cast_regex.sub(line, "", true)
		line = generic_function_regex.sub(line, "$1$2", true)
		var compound_match := compound_regex.search(line)
		if compound_match != null:
			var lhs := compound_match.get_string(2)
			line = "%s%s = %s %s %s%s" % [
				compound_match.get_string(1), lhs, lhs, compound_match.get_string(3),
				compound_match.get_string(4), compound_match.get_string(5),
			]
		while parenthesized_if_regex.search(line) != null:
			line = parenthesized_if_regex.sub(line, "((function() if $1 then return $2 else return $3 end end)())", false)
		while embedded_if_regex.search(line) != null:
			line = embedded_if_regex.sub(line, "$1(function() if $2 then return $3 else return $4 end end)()", false)
		var if_match := if_expression_regex.search(line)
		if if_match != null:
			line = "%s(function() if %s then return %s else return %s end end)()%s" % [
				if_match.get_string(1), if_match.get_string(2), if_match.get_string(3),
				if_match.get_string(4), if_match.get_string(5),
			]
		var for_match := generalized_for_regex.search(line)
		if for_match != null:
			var iterator_expression := for_match.get_string(3).strip_edges()
			if not (
				iterator_expression.begins_with("pairs(")
				or iterator_expression.begins_with("ipairs(")
				or iterator_expression.begins_with("next,")
				or iterator_expression.begins_with("string.gmatch(")
			):
				line = "%sfor %s in pairs(%s) do%s" % [
					for_match.get_string(1), for_match.get_string(2), iterator_expression,
					for_match.get_string(4),
				]
		output.append(line)
	return preload("res://addons/roblox_studio/roblox_luau_syntax.gd").rewrite_continue("\n".join(output))


func _comment_multiline_luau_type_declarations(source: String) -> String:
	var lines := source.split("\n")
	var output: Array[String] = []
	var in_type_declaration := false
	var delimiter_depth := 0
	for line_index in range(lines.size()):
		var line := str(lines[line_index])
		var stripped := line.strip_edges()
		var starts_type := stripped.begins_with("type ") or stripped.begins_with("export type ")
		if not in_type_declaration and not starts_type:
			output.append(line)
			continue
		if not in_type_declaration:
			in_type_declaration = true
			delimiter_depth = 0
		delimiter_depth += _luau_type_delimiter_delta(line)
		var label := "-- Bobux ignored Luau type declaration: " if starts_type else "-- Bobux ignored Luau type body: "
		output.append(label + stripped)
		var next_starts_continuation := false
		if line_index + 1 < lines.size():
			var next_stripped := str(lines[line_index + 1]).strip_edges()
			next_starts_continuation = next_stripped.begins_with("|") or next_stripped.begins_with("&")
		var keeps_alias_open := stripped.ends_with("=") or stripped.ends_with("|") or stripped.ends_with("&")
		if delimiter_depth <= 0 and not keeps_alias_open and not next_starts_continuation:
			in_type_declaration = false
			delimiter_depth = 0
	return "\n".join(output)


func _luau_type_delimiter_delta(line: String) -> int:
	var depth := 0
	var quote := ""
	var escaped := false
	var index := 0
	while index < line.length():
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "-" and index + 1 < line.length() and line.substr(index + 1, 1) == "-":
			break
		elif character == "{" or character == "(" or character == "[":
			depth += 1
		elif character == "}" or character == ")" or character == "]":
			depth -= 1
		index += 1
	return depth


func _strip_luau_function_annotations(line: String) -> String:
	var function_position := line.find("function")
	if function_position < 0:
		return line
	var open_parenthesis := line.find("(", function_position + 8)
	if open_parenthesis < 0:
		return line
	var depth := 0
	var close_parenthesis := -1
	var quote := ""
	var escaped := false
	for index in range(open_parenthesis, line.length()):
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == "\"" or character == "'":
			quote = character
		elif character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0:
				close_parenthesis = index
				break
	if close_parenthesis < 0:
		return line
	var parameters := line.substr(open_parenthesis + 1, close_parenthesis - open_parenthesis - 1)
	var rebuilt := line.left(open_parenthesis + 1) + _strip_luau_parameter_annotations(parameters) + ")"
	var suffix := line.substr(close_parenthesis + 1)
	if not suffix.strip_edges().begins_with(":"):
		return rebuilt + suffix
	var comment_position := suffix.find("--")
	var comment := ""
	if comment_position >= 0:
		comment = " " + suffix.substr(comment_position).strip_edges()
	var inline_body_position := suffix.find(" return ")
	if inline_body_position >= 0 and (comment_position < 0 or inline_body_position < comment_position):
		return rebuilt + suffix.substr(inline_body_position)
	return rebuilt + comment


func _strip_luau_parameter_annotations(parameters: String) -> String:
	var output: Array[String] = []
	var segment_start := 0
	var depth := 0
	var quote := ""
	var escaped := false
	for index in range(parameters.length()):
		var character := parameters.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == "\"" or character == "'":
			quote = character
		elif character == "(" or character == "{" or character == "[" or character == "<":
			depth += 1
		elif character == ")" or character == "}" or character == "]" or character == ">":
			depth = maxi(depth - 1, 0)
		elif character == "," and depth == 0:
			output.append(_strip_luau_parameter_segment(parameters.substr(segment_start, index - segment_start)))
			segment_start = index + 1
	output.append(_strip_luau_parameter_segment(parameters.substr(segment_start)))
	return ",".join(output)


func _strip_luau_parameter_segment(segment: String) -> String:
	var colon := segment.find(":")
	if colon < 0:
		return segment
	return segment.left(colon).rstrip(" \t")


func _strip_luau_local_annotation(line: String) -> String:
	var stripped := line.strip_edges()
	if not stripped.begins_with("local ") or stripped.begins_with("local function "):
		return line
	var local_position := line.find("local")
	var identifier_start := local_position + 5
	while identifier_start < line.length() and line.substr(identifier_start, 1) in [" ", "\t"]:
		identifier_start += 1
	var identifier_end := identifier_start
	while identifier_end < line.length():
		var character := line.substr(identifier_end, 1)
		if not (character == "_" or character.to_lower() != character.to_upper() or character.is_valid_int()):
			break
		identifier_end += 1
	var colon_position := identifier_end
	while colon_position < line.length() and line.substr(colon_position, 1) in [" ", "\t"]:
		colon_position += 1
	if colon_position >= line.length() or line.substr(colon_position, 1) != ":":
		return line
	var depth := 0
	var quote := ""
	var escaped := false
	var assignment_position := -1
	for index in range(colon_position + 1, line.length()):
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == "\"" or character == "'":
			quote = character
		elif character == "(" or character == "{" or character == "[" or character == "<":
			depth += 1
		elif character == ")" or character == "}" or character == "]" or character == ">":
			depth = maxi(depth - 1, 0)
		elif character == "=" and depth == 0:
			assignment_position = index
			break
	var prefix := line.left(identifier_end)
	if assignment_position < 0:
		return prefix
	return prefix + " " + line.substr(assignment_position)


func _replace_luau_backtick_strings(source: String) -> String:
	return preload("res://addons/roblox_studio/roblox_luau_syntax.gd").interpolate(source)


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


func _module_source_for_runtime(module_variant: Variant) -> Dictionary:
	# Keep functions, metatables, cyclic class tables and dependencies inside the
	# caller's Lua state. Converting module return tables to Godot Variants loses
	# identity and recursively walks class tables until the native bridge crashes.
	if not (module_variant is BobuxInstance) or not is_instance_valid(module_variant.node):
		return {"error": "require expects a ModuleScript instance; asset-ID require is unavailable."}
	var module_node: Node = module_variant.node
	if str(module_node.get_meta("roblox_class", "")) != "ModuleScript":
		return {"error": "require expects a ModuleScript instance."}
	var source := str(module_node.get_meta("code", module_node.get_meta("lua_source", "")))
	if source.to_utf8_buffer().size() > MAX_SCRIPT_SOURCE_BYTES:
		return {"error": "ModuleScript exceeds the source size limit."}
	return {
		"key": str(module_node.get_instance_id()),
		"name": str(module_node.get_path()) if module_node.is_inside_tree() else str(module_node.name),
		"source": _prepare_lua_body(source),
	}


func _require_module(module_variant: Variant, context_node: Node, options: Dictionary) -> Variant:
	if not (module_variant is BobuxInstance):
		return module_variant
	var module := module_variant as BobuxInstance
	if not is_instance_valid(module.node):
		return null
	var cache_key := str(module.node.get_meta("roblox_ref", module.node.get_instance_id()))
	if _module_cache.has(cache_key):
		return _module_cache[cache_key]
	if _module_loading.has(cache_key):
		if not _module_cycle_warnings.has(cache_key):
			_module_cycle_warnings[cache_key] = true
			push_warning("[LuaScriptEngine] Circular ModuleScript require stopped at '%s'." % module.node.name)
		return null
	if _module_loading.size() >= MAX_MODULE_REQUIRE_DEPTH:
		push_warning("[LuaScriptEngine] ModuleScript require depth exceeded %d at '%s'." % [MAX_MODULE_REQUIRE_DEPTH, module.node.name])
		_module_cache[cache_key] = null
		return null
	var source := str(module.node.get_meta("code", module.node.get_meta("lua_source", ""))).strip_edges()
	if source.is_empty():
		_module_cache[cache_key] = null
		return null
	if _module_source_requires_another_module(source):
		var dependency_warning_key := "dependency:" + cache_key
		if not _module_cycle_warnings.has(dependency_warning_key):
			_module_cycle_warnings[dependency_warning_key] = true
			push_warning("[LuaScriptEngine] ModuleScript '%s' uses nested require and was isolated for runtime stability." % module.node.name)
		_module_cache[cache_key] = null
		return null
	if _module_source_returns_recursive_table(source):
		var recursive_warning_key := "recursive-table:" + cache_key
		if not _module_cycle_warnings.has(recursive_warning_key):
			_module_cycle_warnings[recursive_warning_key] = true
			push_warning("[LuaScriptEngine] ModuleScript '%s' returns a self-referencing table and was isolated for runtime stability." % module.node.name)
		_module_cache[cache_key] = null
		return null
	_module_loading[cache_key] = true
	var lua = ClassDB.instantiate("LuaAPI")
	if lua == null:
		_module_loading.erase(cache_key)
		_module_cache[cache_key] = null
		return null
	if lua.has_method("set_use_callables"):
		lua.set_use_callables(true)
	lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine", "utf8"]))
	var coroutine = lua.new_coroutine()
	_push_runtime_bindings(coroutine, module.node, options)
	var load_error = coroutine.load_string(_prepare_scheduled_lua_source(source))
	var load_message := _lua_error_message(load_error)
	if not load_message.is_empty():
		_module_loading.erase(cache_key)
		_module_cache[cache_key] = null
		push_warning("[LuaScriptEngine] ModuleScript '%s' failed to load: %s" % [module.node.name, load_message])
		return null
	var module_runtime_id := _next_script_runtime_id
	_next_script_runtime_id += 1
	_configure_instruction_hook(coroutine, module_runtime_id)
	_runtime_resume_started_usec[module_runtime_id] = Time.get_ticks_usec()
	_runtime_budget_exceeded.erase(module_runtime_id)
	if OS.has_environment("BOBUX_TRACE_LUA_MODULES"):
		print("[LuaScriptEngine][module-start] name=", module.node.name, " ref=", cache_key, " bytes=", source.to_utf8_buffer().size())
	var result: Variant = coroutine.resume([])
	if OS.has_environment("BOBUX_TRACE_LUA_MODULES"):
		print("[LuaScriptEngine][module-end] name=", module.node.name, " ref=", cache_key)
	_runtime_resume_started_usec.erase(module_runtime_id)
	var error_message := _lua_error_message(result)
	if _runtime_budget_exceeded.has(module_runtime_id):
		error_message = "ModuleScript exceeded the %.1f ms execution budget without yielding." % [float(SCRIPT_SINGLE_RESUME_TIME_LIMIT_USEC) / 1000.0]
		_runtime_budget_exceeded.erase(module_runtime_id)
	if not error_message.is_empty():
		_module_loading.erase(cache_key)
		_module_cache[cache_key] = null
		# A failed module may already have connected Lua callbacks. Retain its state
		# until Stop so those callbacks never reference a closed lua_State.
		_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
		push_warning("[LuaScriptEngine] ModuleScript '%s': %s" % [module.node.name, error_message])
		return null
	if not bool(coroutine.is_done()):
		_module_loading.erase(cache_key)
		_module_cache[cache_key] = null
		_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
		push_warning("[LuaScriptEngine] ModuleScript '%s' yielded during require; asynchronous modules are not supported." % module.node.name)
		return null
	var value: Variant = (result as Array)[0] if result is Array and not (result as Array).is_empty() else null
	_module_loading.erase(cache_key)
	_module_cache[cache_key] = value
	_retained_lua_states["module:" + cache_key] = {"lua": lua, "context": module.node}
	return value


func _module_source_requires_another_module(source: String) -> bool:
	var require_regex := RegEx.new()
	if require_regex.compile("(^|[^A-Za-z0-9_])require[\\t ]*\\(") != OK:
		return source.contains("require(")
	return require_regex.search(source) != null


func _module_source_returns_recursive_table(source: String) -> bool:
	# LuaAPI recursively converts returned tables to Variant. Classic class
	# modules commonly assign `Class.__index = Class`, creating a cycle that the
	# extension cannot currently represent and would otherwise follow forever.
	var recursive_table_regex := RegEx.new()
	if recursive_table_regex.compile("([A-Za-z_][A-Za-z0-9_]*)\\.__index[\\t ]*=[\\t ]*\\1") != OK:
		return false
	return recursive_table_regex.search(source) != null

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
	var node_by_ref: Dictionary = {"-1": _find_roblox_data_model_for_workspace(main_scene, workspace_node)}
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
		var service_name := str(service.get("class", service.get("name", ""))).strip_edges()
		if ref.is_empty() or service_name.is_empty():
			continue
		var service_node: Node = service_nodes.get(service_name, null) as Node
		if service_node == null:
			service_node = _ensure_single_roblox_service(main_scene, service_name, workspace_node)
		if service_node != null:
			service_node.set_meta("roblox_ref", ref)
			service_node.set_meta("roblox_class", str(service.get("class", service_name)))
			if service.has("properties"):
				service_node.set_meta("roblox_properties", service.properties)
				_apply_manifest_properties_to_node(service_node, service.properties)
			node_by_ref[ref] = service_node
	var entries: Array[Dictionary] = []
	_append_manifest_entries(entries, manifest.get("gui", []))
	_append_manifest_entries(entries, manifest.get("tools", []))
	_append_manifest_entries(entries, manifest.get("scripts", []))
	_append_manifest_entries(entries, manifest.get("instances", []))
	_append_manifest_entries(entries, manifest.get("storage_libraries", []))
	var unique_entries: Array[Dictionary] = []
	var seen_entry_refs: Dictionary = {}
	for entry in entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if not entry_ref.is_empty() and seen_entry_refs.has(entry_ref):
			continue
		if not entry_ref.is_empty():
			seen_entry_refs[entry_ref] = true
		unique_entries.append(entry)
	var pending: Array[Dictionary] = unique_entries.duplicate()
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
	var node_by_ref: Dictionary = {"-1": _find_roblox_data_model_for_workspace(main_scene, workspace_node)}
	await _index_nodes_by_roblox_ref_async(workspace_node, node_by_ref, tree, maxi(batch_size, 32))
	for service_node_variant in service_nodes.values():
		if service_node_variant is Node:
			await _index_nodes_by_roblox_ref_async(service_node_variant as Node, node_by_ref, tree, maxi(batch_size, 32))
	var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	for service_variant in services:
		if not (service_variant is Dictionary):
			continue
		var service: Dictionary = service_variant
		var ref := str(service.get("ref", "")).strip_edges()
		var service_name := str(service.get("class", service.get("name", ""))).strip_edges()
		if ref.is_empty() or service_name.is_empty():
			continue
		var service_node: Node = service_nodes.get(service_name, null) as Node
		if service_node == null:
			service_node = _ensure_single_roblox_service(main_scene, service_name, workspace_node)
		if service_node != null:
			service_node.set_meta("roblox_ref", ref)
			service_node.set_meta("roblox_class", str(service.get("class", service_name)))
			if service.has("properties"):
				service_node.set_meta("roblox_properties", service.properties)
				_apply_manifest_properties_to_node(service_node, service.properties)
			node_by_ref[ref] = service_node

	var entries: Array[Dictionary] = []
	_append_manifest_entries(entries, manifest.get("gui", []))
	_append_manifest_entries(entries, manifest.get("tools", []))
	_append_manifest_entries(entries, manifest.get("scripts", []))
	_append_manifest_entries(entries, manifest.get("instances", []))
	_append_manifest_entries(entries, manifest.get("storage_libraries", []))
	var unique_entries: Array[Dictionary] = []
	var seen_entry_refs: Dictionary = {}
	for entry in entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if not entry_ref.is_empty() and seen_entry_refs.has(entry_ref):
			continue
		if not entry_ref.is_empty():
			seen_entry_refs[entry_ref] = true
		unique_entries.append(entry)

	# Build the dependency queue once. The old multi-pass installer scanned every
	# unresolved entry again after each hierarchy level and each creation also
	# scanned every sibling under its parent. Real places with thousands of
	# objects therefore degraded toward O(n^2) and appeared to freeze Studio.
	var entry_by_ref: Dictionary = {}
	var waiting_by_parent_ref: Dictionary = {}
	var ready: Array[Dictionary] = []
	var anonymous_entries: Array[Dictionary] = []
	for entry in unique_entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if entry_ref.is_empty():
			anonymous_entries.append(entry)
			continue
		entry_by_ref[entry_ref] = entry
	for entry in unique_entries:
		var entry_ref := str(entry.get("ref", "")).strip_edges()
		if entry_ref.is_empty() or node_by_ref.has(entry_ref):
			continue
		var parent_ref := str(entry.get("parent_ref", "")).strip_edges()
		if parent_ref.is_empty() or node_by_ref.has(parent_ref):
			ready.append(entry)
		elif entry_by_ref.has(parent_ref):
			var waiting: Array = waiting_by_parent_ref.get(parent_ref, [])
			waiting.append(entry)
			waiting_by_parent_ref[parent_ref] = waiting
	var created := 0
	var processed_since_yield := 0
	var safe_batch_size := maxi(batch_size, 32)
	var ready_index := 0
	while ready_index < ready.size():
		var entry: Dictionary = ready[ready_index]
		ready_index += 1
		var ref := str(entry.get("ref", "")).strip_edges()
		if not node_by_ref.has(ref):
			var parent_node := _resolve_manifest_parent_node(entry, node_by_ref, service_nodes, main_scene)
			if parent_node != null:
				var node := _ensure_manifest_entry_node(parent_node, entry)
				if node != null:
					node_by_ref[ref] = node
					created += 1
					var children: Array = waiting_by_parent_ref.get(ref, [])
					for child_entry in children:
						if child_entry is Dictionary:
							ready.append(child_entry as Dictionary)
					waiting_by_parent_ref.erase(ref)
		processed_since_yield += 1
		if tree != null and processed_since_yield >= safe_batch_size:
			processed_since_yield = 0
			await tree.process_frame
	for entry in anonymous_entries:
		var parent_node := _resolve_manifest_parent_node(entry, node_by_ref, service_nodes, main_scene)
		if parent_node != null and _ensure_manifest_entry_node(parent_node, entry) != null:
			created += 1
		processed_since_yield += 1
		if tree != null and processed_since_yield >= safe_batch_size:
			processed_since_yield = 0
			await tree.process_frame
	var pending_count := 0
	for ref in entry_by_ref:
		if not node_by_ref.has(ref): pending_count += 1
	var hierarchy_result := await _restore_manifest_hierarchy_async(
		manifest.get("hierarchy", []), node_by_ref, tree, safe_batch_size
	)
	_ensure_local_player_nodes(service_nodes.get("Players", null), service_nodes.get("StarterGui", null), service_nodes.get("StarterPack", null), service_nodes.get("StarterPlayer", null))
	return {
		"ok": true,
		"created": created,
		"pending": pending_count,
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
			# Manifest entries are immutable during installation. Keeping references
			# avoids cloning thousands of nested property dictionaries twice.
			out.append(entry_variant as Dictionary)

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
	# Ref-bearing entries are already globally indexed by the caller. Anonymous
	# authored nodes are reconciled by their safe name below.
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
	if bool(entry.get("properties", {}).get("BobuxDeferredGeometry", false)):
		var part := MeshInstance3D.new()
		part.add_to_group("studio_parts")
		return part
	return RobloxDataModelClass.create_instance(roblox_class, str(entry.get("name", roblox_class)))

func _apply_manifest_entry_metadata(node: Node, entry: Dictionary) -> void:
	var roblox_class := str(entry.get("class", "Instance")).strip_edges()
	node.set_meta("roblox_ref", str(entry.get("ref", "")).strip_edges())
	node.set_meta("roblox_class", roblox_class)
	node.set_meta("Name", str(entry.get("name", node.name)).strip_edges())
	if entry.has("properties") and entry["properties"] is Dictionary:
		var properties := (entry["properties"] as Dictionary).duplicate(false)
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
	if roblox_class == "ClickDetector":
		node.add_to_group("roblox_click_detectors")
	if roblox_class == "ProximityPrompt":
		node.add_to_group("roblox_proximity_prompts")
	if roblox_class.ends_with("Value"):
		node.add_to_group("roblox_value_objects")


func _apply_manifest_properties_to_node(node: Node, properties: Dictionary) -> void:
	for attribute in properties.get("Attributes", {}):
		node.set_meta("attribute_" + str(attribute), properties.Attributes[attribute])
	if node is Node3D:
		var node_3d := node as Node3D
		node_3d.position = _vector3_from_manifest_value(properties.get("BobuxPosition", properties.get("Position", [0.0, 0.0, 0.0])), node_3d.position)
		node_3d.rotation_degrees = _vector3_from_manifest_value(properties.get("BobuxRotation", properties.get("Rotation", [0.0, 0.0, 0.0])), node_3d.rotation_degrees)
		node_3d.scale = _vector3_from_manifest_value(properties.get("BobuxSize", properties.get("Size", [1.0, 1.0, 1.0])), node_3d.scale)
		if bool(properties.get("BobuxTemplateOnly", false)):
			node_3d.visible = false
	if node is MeshInstance3D:
		node.set_meta("anchored", bool(properties.get("Anchored", true)))
		node.set_meta("can_collide", bool(properties.get("CanCollide", true)))
		node.set_meta("transparency", float(properties.get("Transparency", 0.0)))
		node.set_meta("bobux_deferred_geometry", bool(properties.get("BobuxDeferredGeometry", false)) or bool(properties.get("BobuxTemplateOnly", false)))
		if not bool(properties.get("BobuxDeferredGeometry", false)):
			_apply_manifest_part_appearance(node as MeshInstance3D, properties)
		var mesh_path := str(properties.get("BobuxMeshResource", ""))
		if not mesh_path.is_empty() and FileAccess.file_exists(mesh_path):
			var mesh: Variant = ResourceLoader.load(mesh_path)
			if mesh is Mesh:
				node.mesh = mesh.duplicate(true)
				node.material_override = null
				node.set_meta("bobux_mesh_resource_asset", mesh_path)
				node.set_meta("roblox_mesh_applied", true)
	if node is AudioStreamPlayer3D:
		preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").configure(node)

	if node is Control:
		var control := node as Control
		var roblox_class := str(node.get_meta("roblox_class", ""))
		if roblox_class not in ["ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup"]:
			control.position = _udim2_offset_from_manifest(properties.get("Position", {}), control.position)
			control.size = _udim2_offset_from_manifest(properties.get("Size", {}), control.size)
		control.visible = bool(properties.get("Visible", properties.get("Enabled", true)))
		control.z_index = clampi(int(properties.get("ZIndex", 0)), -4096, 4096)
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
	var raw_color: Variant = properties.get(
		"Color",
		properties.get("Color3", properties.get("Color3uint8", null))
	)
	if raw_color == null and properties.has("BrickColor"):
		raw_color = _brick_color_from_variant(properties.get("BrickColor"))
	material.albedo_color = _color_from_manifest_value(raw_color, material.albedo_color)
	material.albedo_color.a = clampf(1.0 - float(properties.get("Transparency", 0.0)), 0.0, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if material.albedo_color.a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
	var surface_props := properties.duplicate(false)
	surface_props["BobuxStudScale"] = BobuxInstance.wrap(mesh_instance)._stud_scale()
	material.next_pass = preload("res://addons/rbxl_importer/material_cache.gd").new().get_part_material(surface_props).next_pass
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


func _index_nodes_by_roblox_ref_async(root_node: Node, out: Dictionary, tree: SceneTree, batch_size: int) -> void:
	if root_node == null:
		return
	var pending: Array[Node] = [root_node]
	var processed := 0
	var safe_batch_size := maxi(batch_size, 32)
	while not pending.is_empty():
		var current: Node = pending.pop_back() as Node
		if current == null or not is_instance_valid(current):
			continue
		var ref := str(current.get_meta("roblox_ref", "")).strip_edges()
		if not ref.is_empty():
			out[ref] = current
		for child in current.get_children():
			if child is Node:
				pending.append(child as Node)
		processed += 1
		if tree != null and processed >= safe_batch_size:
			processed = 0
			await tree.process_frame


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
	_register_live_gui(gui_root, context_node)
	return {"ok": true, "bound": bound, "indexed": indexed.size(), "refs": indexed.keys()}


func bind_gui_controls_async(gui_root: Node, context_node: Node, batch_size: int = 96) -> Dictionary:
	if gui_root == null:
		return {"ok": false, "bound": 0}
	var tree := gui_root.get_tree() if gui_root.is_inside_tree() else null
	_register_live_gui(gui_root, context_node)
	var indexed: Dictionary = {}
	if context_node != null:
		await _index_nodes_by_roblox_ref_async(context_node, indexed, tree, batch_size)
	if tree != null:
		var workspace_node := _resolve_workspace_node(tree.root, context_node)
		var data_model_root := _find_roblox_data_model_for_workspace(tree.root, workspace_node)
		if data_model_root == null:
			data_model_root = _find_roblox_data_model_root(tree.root)
		if data_model_root != null:
			await _index_nodes_by_roblox_ref_async(data_model_root, indexed, tree, batch_size)
			var players_service := data_model_root.get_node_or_null("Players")
			if players_service != null:
				var local_player := players_service.get_node_or_null("LocalPlayer")
				if local_player != null:
					var player_gui := local_player.get_node_or_null("PlayerGui")
					if player_gui != null:
						await _index_nodes_by_roblox_ref_async(player_gui, indexed, tree, batch_size)
	var bound := 0
	var processed := 0
	var pending: Array[Node] = [gui_root]
	var safe_batch_size := maxi(batch_size, 24)
	while not pending.is_empty():
		var node: Node = pending.pop_back() as Node
		if node == null or not is_instance_valid(node):
			continue
		if node is BaseButton and not bool(node.get_meta("bobux_lua_event_bound", false)):
			var ref := str(node.get_meta("roblox_ref", "")).strip_edges()
			var target: Node = indexed.get(ref, null) as Node
			if target != null:
				var target_instance := BobuxInstance.wrap(target)
				var roblox_class := str(node.get_meta("roblox_class", target.get_meta("roblox_class", "")))
				node.set_meta("bobux_bound_target_path", str(target.get_path()))
				var control_instance_id: int = node.get_instance_id()
				var target_instance_id: int = target.get_instance_id()
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
			if child is Node:
				pending.append(child as Node)
		processed += 1
		if tree != null and processed >= safe_batch_size:
			processed = 0
			await tree.process_frame
	return {"ok": true, "bound": bound, "indexed": indexed.size(), "refs": indexed.keys(), "batched": true}


func fire_roblox_instance_event(target: Node, event_name: String, args: Array = []) -> bool:
	if target == null or not is_instance_valid(target) or event_name.strip_edges().is_empty():
		return false
	var event := BobuxInstance.wrap(target)._shared_event(event_name.strip_edges())
	var normalized: Array = []
	for arg in args.slice(0, 3):
		normalized.append(BobuxInstance.wrap(arg as Node) if arg is Node and is_instance_valid(arg) else arg)
	while normalized.size() < 3:
		normalized.append(null)
	event.Fire(normalized[0], normalized[1], normalized[2])
	return true


func _register_live_gui(gui_root: Node, context: Node) -> void:
	if not gui_root is Control or gui_root.has_node("LivePlayerGui"):
		return
	var state := get_local_inventory_state(context)
	var player := _live_node(state.get("local_player"))
	if player == null: return
	var sync: Node = preload("res://addons/roblox_runtime/roblox_live_gui.gd").new()
	sync.name = "LivePlayerGui"
	sync.engine = self
	sync.host = gui_root
	sync.player_gui = player.get_node_or_null("PlayerGui")
	gui_root.add_child(sync)

func _bind_gui_controls_recursive(node: Node, indexed: Dictionary) -> int:
	var bound := 0
	if node is BaseButton and not bool(node.get_meta("bobux_lua_event_bound", false)):
		var ref := str(node.get_meta("roblox_ref", "")).strip_edges()
		var target: Node = indexed.get(ref, null) as Node
		if target != null:
			var target_instance := BobuxInstance.wrap(target)
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
	# A semicolon ends a statement, not the property's value expression.
	# Token offsets exclude quoted text/comments; keep table field separators.
	var separators := _lua_tokens(lua_code)
	separators.reverse()
	for token in separators:
		if token.text == ";": lua_code = lua_code.left(token.end) + "\n" + lua_code.substr(token.end)
	var regex := RegEx.new()
	var compile_error := regex.compile("^([\\t ]*)([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)\\.(Name|Parent|Value|Position|Rotation|CFrame|Velocity|AssemblyLinearVelocity|Size|Anchored|CanCollide|Transparency|BrickColor|Color|Reflectance|Enabled|Visible|TimeOfDay|ClockTime)\\s*=\\s*(?!=)(.+)$")
	if compile_error != OK:
		return lua_code
	var rewritten: Array[String] = []
	var pending_assignment_balance := 0
	var pending_assignment_suffix := ""
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
				var continuation_body := continuation.rstrip(" \t")
				if continuation_body.ends_with(";"):
					continuation_body = continuation_body.left(-1)
					pending_assignment_suffix = ";"
				rewritten.append("%s)%s%s%s" % [
					continuation_body, pending_assignment_suffix,
					" " if not continuation_comment.is_empty() else "", continuation_comment
				])
				pending_assignment_balance = 0
				pending_assignment_suffix = ""
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
		var statement_suffix := ""
		value_expr = value_expr.rstrip(" \t")
		if value_expr.ends_with(";"):
			value_expr = value_expr.left(-1).rstrip(" \t")
			statement_suffix = ";"
		var balance := _lua_delimiter_balance(value_expr)
		if balance > 0:
			rewritten.append('%s__bobux_set(%s, "%s", %s%s%s' % [
				indent, target, property_name, value_expr,
				" " if not comment.is_empty() else "", comment
			])
			pending_assignment_balance = balance
			pending_assignment_suffix = statement_suffix
		else:
			rewritten.append('%s__bobux_set(%s, "%s", %s)%s%s%s' % [
				indent, target, property_name, value_expr, statement_suffix,
				" " if not comment.is_empty() else "", comment
			])
	if pending_assignment_balance > 0 and not rewritten.is_empty():
		rewritten[rewritten.size() - 1] += ")"
	return "\n".join(rewritten)

func _lua_tokens(source: String) -> Array[Dictionary]:
	return preload("res://addons/roblox_studio/roblox_lua_lexer.gd").tokens(source)


func _lua_receiver_start(tokens: Array[Dictionary], end_index: int) -> int:
	var cursor := end_index
	while cursor >= 0:
		var token := str(tokens[cursor].text)
		if token in [")", "]"]:
			var opening := "(" if token == ")" else "["
			var depth := 1
			cursor -= 1
			while cursor >= 0 and depth > 0:
				if tokens[cursor].text == token:
					depth += 1
				elif tokens[cursor].text == opening:
					depth -= 1
				cursor -= 1
			if depth != 0:
				return -1
			if cursor >= 0 and (bool(tokens[cursor].identifier) or tokens[cursor].text in [")", "]"]):
				continue
			return cursor + 1
		if not bool(tokens[cursor].identifier):
			return -1
		if cursor >= 2 and tokens[cursor - 1].text in [".", ":"]:
			cursor -= 2
			continue
		return cursor
	return -1


func _rewrite_lua_async_calls(source: String) -> String:
	var helpers := {"Connect": "__bobux_connect", "connect": "__bobux_connect", "Once": "__bobux_once", "disconnect": "__bobux_disconnect", "WaitForChild": "__bobux_wait_for_child", "Wait": "__bobux_signal_wait", "wait": "__bobux_signal_wait"}
	helpers.merge({"FireServer": "__bobux_fire_server", "FireClient": "__bobux_fire_client", "FireAllClients": "__bobux_fire_all_clients", "Fire": "__bobux_fire", "InvokeServer": "__bobux_invoke_server", "InvokeClient": "__bobux_invoke_client", "Invoke": "__bobux_invoke"})
	var tokens := _lua_tokens(source)
	var replacements: Array[Dictionary] = []
	for index in range(1, tokens.size() - 2):
		if tokens[index].text != ":" or not helpers.has(tokens[index + 1].text) or tokens[index + 2].text != "(":
			continue
		var receiver_start := _lua_receiver_start(tokens, index - 1)
		if receiver_start < 0:
			continue
		# Insert helper before the receiver, then replace :Method( separately.
		# Nested/chained calls therefore never overlap another replacement span.
		replacements.append({"start": int(tokens[receiver_start].start), "end": int(tokens[receiver_start].start), "text": str(helpers[tokens[index + 1].text]) + "("})
		var has_arguments: bool = index + 3 < tokens.size() and tokens[index + 3].text != ")"
		replacements.append({"start": int(tokens[index].start), "end": int(tokens[index + 2].end), "text": ", " if has_arguments else ""})
	replacements.sort_custom(func(first: Dictionary, second: Dictionary): return int(first.start) > int(second.start))
	for replacement in replacements:
		source = source.left(int(replacement.start)) + str(replacement.text) + source.substr(int(replacement.end))
	return source


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
	var cached_workspace := _live_node(cached.get("workspace"))
	var cached_root := _live_node(cached.get("root"))
	if cached_workspace != workspace_node or cached_root == null or not is_instance_valid(cached_root):
		return false
	for service_variant in services.values():
		if not is_instance_valid(service_variant) or not (service_variant is Node):
			return false
	return true

func _live_node(value: Variant) -> Node:
	# `as Node` itself throws for a freed Object; check the Variant first.
	return value as Node if is_instance_valid(value) and value is Node else null

func _live_service_caches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _service_nodes_cache.keys():
		var cached: Dictionary = _service_nodes_cache[key]
		var workspace_node := _live_node(cached.get("workspace"))
		if workspace_node == null or not _service_cache_is_valid(cached, workspace_node, cached.get("services", {})):
			_service_nodes_cache.erase(key)
			continue
		result.append(cached)
	return result


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
	if not bool(local_player.get_meta("bobux_player_joined", false)):
		local_player.set_meta("bobux_player_joined", true)
		_assign_initial_team(local_player, services.get("Teams"))
		BobuxInstance.wrap(players_service).PlayerAdded.Fire(BobuxInstance.wrap(local_player))
	local_player.set_meta("bobux_character_instance_id", character_node.get_instance_id())
	character_node.set_meta("bobux_player_instance_id", local_player.get_instance_id())
	character_node.set_meta("roblox_class", "Model")
	character_node.set_meta("Name", "Character")
	var starter_player: Node = services.get("StarterPlayer", null)
	if starter_player != null:
		var starter_character_scripts := starter_player.get_node_or_null("StarterCharacterScripts")
		if starter_character_scripts != null:
			_clone_missing_children(starter_character_scripts, character_node)
	refresh_local_team_spawns(character_node, true)
	BobuxInstance.wrap(local_player)._shared_event("CharacterAdded").Fire(BobuxInstance.wrap(character_node))


func _assign_initial_team(player: Node, teams: Node) -> void:
	if teams == null or player.has_meta("Team"): return
	var best: Node = null
	var count := 2147483647
	for team in teams.get_children():
		if str(team.get_meta("roblox_class", "")) != "Team": continue
		if not bool(team.get_meta("AutoAssignable", team.get_meta("roblox_properties", {}).get("AutoAssignable", true))): continue
		var members := BobuxInstance.wrap(team).GetPlayers().size()
		if members < count:
			best = team
			count = members
	if best != null: BobuxInstance.wrap(player)._set(&"Team", BobuxInstance.wrap(best))


func refresh_local_team_spawns(character: Node, place_initial: bool = false) -> void:
	if not is_instance_valid(character) or not character.is_inside_tree(): return
	var player := _live_node(instance_from_id(int(character.get_meta("bobux_player_instance_id", 0))))
	if player == null: return
	var workspace := _resolve_workspace_node(character.get_tree().root, character)
	if workspace == null: return
	var wrapper := BobuxInstance.wrap(player)
	var team: Variant = wrapper._get(&"Team")
	var color: Variant = player.get_meta("TeamColor", 194)
	if team is BobuxInstance: color = team._get(&"TeamColor")
	var neutral := bool(player.get_meta("Neutral", team == null))
	var preferred: Variant = wrapper._get(&"RespawnLocation")
	var points: Array[Vector3] = []
	var pending: Array[Node] = [workspace]
	while not pending.is_empty():
		var candidate: Node = pending.pop_back()
		pending.append_array(candidate.get_children())
		if str(candidate.get_meta("roblox_class", "")) != "SpawnLocation" or not candidate is Node3D: continue
		var props: Dictionary = candidate.get_meta("roblox_properties", {})
		if not bool(candidate.get_meta("Enabled", props.get("Enabled", true))): continue
		var spawn_neutral := bool(candidate.get_meta("Neutral", props.get("Neutral", true)))
		var spawn_color: Variant = candidate.get_meta("TeamColor", props.get("TeamColor", 194))
		if not spawn_neutral and (neutral or _brick_color_from_variant(spawn_color) != _brick_color_from_variant(color)): continue
		var center: Vector3 = candidate.global_position
		if candidate is MeshInstance3D:
			var bounds: AABB = candidate.global_transform * candidate.get_aabb()
			center = Vector3(bounds.get_center().x, bounds.end.y + 0.12, bounds.get_center().z)
		if preferred is BobuxInstance and preferred.node == candidate:
			points.assign([center])
			break
		points.append(center)
	if points.is_empty(): return
	if character.has_method("configure_spawn_points"): character.configure_spawn_points(points)
	if place_initial and character.has_method("set_lua_position"):
		character.set_lua_position(points[0])
		character.set_initial_spawn_position(points[0])


func collect_live_player_scripts(context_node: Node, character: Node = null) -> Array[Node]:
	var state := get_local_inventory_state(context_node, character)
	var pending: Array[Node] = []
	for key in ["local_player", "character"]:
		var node := _live_node(state.get(key))
		if node != null:
			pending.append(node)
	var result: Array[Node] = []
	var seen := {}
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if seen.has(node.get_instance_id()):
			continue
		seen[node.get_instance_id()] = true
		if str(node.get_meta("roblox_class", "")) in ["Script", "LocalScript"] and not bool(node.get_meta("disabled", false)):
			result.append(node)
		pending.append_array(node.get_children())
	return result

func start_new_player_scripts(context_node: Node, character: Node = null) -> void:
	if not is_instance_valid(context_node) or not context_node.is_inside_tree(): return
	for script_node in collect_live_player_scripts(context_node, character):
		if script_node.has_meta("bobux_script_runtime_id"): continue
		var source := str(script_node.get_meta("code", script_node.get_meta("lua_source", "")))
		if source.is_empty(): continue
		start_script(source, script_node, {"realm": "client" if str(script_node.get_meta("roblox_class", "Script")) == "LocalScript" else "server", "retain": true})

func _start_new_player_scripts_by_id(id: int) -> void:
	var context: Variant = instance_from_id(id)
	if is_instance_valid(context): start_new_player_scripts(context)


func _refresh_authored_scripts_by_id(id: int) -> void:
	var context := _live_node(instance_from_id(id))
	if context == null or context.is_queued_for_deletion() or not context.is_inside_tree(): return
	var pending: Array[Node] = [context]
	while not pending.is_empty():
		var item: Node = pending.pop_back()
		if item.is_queued_for_deletion(): continue
		var class_name_ := str(item.get_meta("roblox_class", ""))
		if class_name_ in ["Script", "LocalScript"]:
			var enabled := not bool(item.get_meta("disabled", false))
			var cursor := item.get_parent()
			var live_world := false
			var live_player := false
			while cursor != null:
				var parent_class := str(cursor.get_meta("roblox_class", ""))
				if parent_class in ["Lighting", "ServerStorage", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer"]:
					enabled = false
					break
				if parent_class in ["Workspace", "ServerScriptService"]: live_world = true
				if parent_class == "Player" or bool(cursor.get_meta("bobux_character_instance_id", false)): live_player = true
				cursor = cursor.get_parent()
			enabled = enabled and (live_player or (live_world and class_name_ == "Script"))
			if not enabled and item.has_meta("bobux_script_runtime_id"):
				stop_script(int(item.get_meta("bobux_script_runtime_id")))
				item.remove_meta("bobux_script_runtime_id")
			elif enabled and not item.has_meta("bobux_script_runtime_id"):
				var source := str(item.get_meta("code", item.get_meta("lua_source", "")))
				if not source.is_empty(): start_script(source, item, {"realm": "client" if class_name_ == "LocalScript" else "server", "retain": true, "defer_compilation": true})
		for child in item.get_children():
			if not BobuxInstance._is_native_helper(child): pending.append(child)


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
	start_new_player_scripts(character, character)
	BobuxInstance.wrap(tool_node).Equipped.Fire(BobuxMouse.new(state.get("local_player")))
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
	BobuxInstance.wrap(tool_node).Unequipped.Fire()
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
	var now_msec := Time.get_ticks_msec()
	var cooldown_seconds := clampf(float(tool_node.get_meta("bobux_tool_cooldown", 0.0)), 0.0, 10.0)
	var last_activation_msec := int(tool_node.get_meta("bobux_tool_last_activation_msec", 0))
	if cooldown_seconds > 0.0 and now_msec - last_activation_msec < roundi(cooldown_seconds * 1000.0):
		return false
	tool_node.set_meta("bobux_tool_last_activation_msec", now_msec)
	BobuxInstance.wrap(tool_node).Activated.Fire()
	var damage := clampf(float(tool_node.get_meta("bobux_tool_damage", 0.0)), 0.0, 200.0)
	if damage > 0.0 and character is Node3D:
		_apply_local_tool_damage(tool_node, character as Node3D, damage)
	return true


func _apply_local_tool_damage(tool_node: Node, character: Node3D, damage: float) -> bool:
	if tool_node == null or character == null or not character.is_inside_tree():
		return false
	var stud_scale := maxf(float(character.get_meta("roblox_stud_scale", 1.0)), 0.25)
	var attack_range := clampf(float(tool_node.get_meta("bobux_tool_range", 5.0)), 1.0, 24.0) * stud_scale
	var attack_origin := character.global_position + Vector3.UP * 2.2 * stud_scale
	var attack_forward := -character.global_transform.basis.z
	var visuals := character.get_node_or_null("Visuals") as Node3D
	if visuals != null:
		# The block avatar mesh faces its local +Z direction.
		attack_forward = visuals.global_transform.basis.z
	attack_forward.y = 0.0
	if attack_forward.length_squared() <= 0.001:
		attack_forward = Vector3.FORWARD
	else:
		attack_forward = attack_forward.normalized()

	var scene := get_tree().current_scene
	if scene == null:
		return false
	var target: CharacterBody3D = null
	var target_distance := INF
	for candidate_variant in scene.find_children("*", "CharacterBody3D", true, false):
		if not candidate_variant is CharacterBody3D:
			continue
		var candidate := candidate_variant as CharacterBody3D
		if candidate == character or not candidate.has_method("take_damage"):
			continue
		var offset := candidate.global_position + Vector3.UP * stud_scale * 1.8 - attack_origin
		var distance := offset.length()
		if distance > attack_range or distance >= target_distance:
			continue
		var direction := offset.normalized() if distance > 0.001 else attack_forward
		# Very close contacts count even when the camera is turning. Longer hits
		# must remain in the forward hemisphere like a Roblox melee Tool.
		if distance > 1.45 * stud_scale and direction.dot(attack_forward) < 0.05:
			continue
		target = candidate
		target_distance = distance
	if target == null:
		return false

	var handle := _find_tool_handle(tool_node)
	var hit_part: Node = target.get_node_or_null("HumanoidRootPart")
	if hit_part == null:
		hit_part = target
	if handle != null:
		notify_part_touched(handle, hit_part)
	var root_scene := get_tree().current_scene
	if root_scene != null and root_scene.has_method("request_lua_tool_damage"):
		return bool(root_scene.call("request_lua_tool_damage", target, damage, character))
	target.call("take_damage", damage)
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
		if bool(local_player.get_meta("bobux_player_joined", false)):
			BobuxInstance.wrap(players_service).PlayerRemoving.Fire(BobuxInstance.wrap(local_player))
		local_player.remove_meta("bobux_player_joined")
		local_player.remove_meta("bobux_character_instance_id")

func notify_part_touched(touched_part: Node, hit_part: Node) -> void:
	if touched_part == null or hit_part == null or not is_instance_valid(touched_part) or not is_instance_valid(hit_part):
		return
	BobuxInstance.wrap(touched_part).Touched.Fire(BobuxInstance.wrap(hit_part))

func notify_jump_request(character: Node) -> void:
	# Dispatch only to the DataModel bound to this local character, including
	# Studio's isolated play viewport. Do not create services on every input.
	for cached in _live_service_caches():
		var services: Dictionary = cached.get("services", {})
		var players: Node = services.get("Players") as Node
		if not is_instance_valid(players):
			continue
		var local_player := players.get_node_or_null("LocalPlayer")
		if local_player == null or int(local_player.get_meta("bobux_character_instance_id", 0)) != character.get_instance_id():
			continue
		_fire_existing_runtime_event(services.get("UserInputService") as Node, "JumpRequest", [])

func _input(event: InputEvent) -> void:
	if _scripts_paused or _service_nodes_cache.is_empty():
		return
	var data := RobloxInputBridge.event_data(event)
	if data.is_empty():
		return
	for cached in _live_service_caches():
		var services: Dictionary = cached.get("services", {})
		var players := _live_node(services.get("Players"))
		var input_service := _live_node(services.get("UserInputService"))
		if not is_instance_valid(players) or not is_instance_valid(input_service):
			continue
		var local_player := players.get_node_or_null("LocalPlayer")
		var character_id := int(local_player.get_meta("bobux_character_instance_id", 0)) if local_player != null else 0
		var character := instance_from_id(character_id) as Node if character_id != 0 else null
		if not is_instance_valid(character) or not character.is_inside_tree() or character.is_queued_for_deletion():
			continue
		if event is InputEventMouse and character.get_viewport() == get_viewport():
			character.get_viewport().set_meta("bobux_pointer_position", event.position)
		var focus := get_viewport().gui_get_focus_owner()
		var character_focus := character.get_viewport().gui_get_focus_owner()
		var processed := bool(character.get_meta("bobux_system_menu_open", false)) or (is_instance_valid(focus) and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)) or (is_instance_valid(character_focus) and character_focus.is_visible_in_tree() and (character_focus is LineEdit or character_focus is TextEdit))
		if data.UserInputType == 8:
			var keys: Dictionary = input_service.get_meta("_bobux_pressed_keys", {})
			if data.UserInputState == 0: keys[int(data.KeyCode)] = true
			else: keys.erase(int(data.KeyCode))
			input_service.set_meta("_bobux_pressed_keys", keys)
		var event_name: String = {0: "InputBegan", 1: "InputChanged", 2: "InputEnded"}[int(data.UserInputState)]
		_fire_existing_runtime_event(input_service, event_name, [RobloxInputBridge.InputObject.new(data), processed])
		if data.UserInputType == 0 and data.UserInputState in [0, 2]:
			_fire_existing_runtime_event(local_player, "Mouse_Button1Down" if data.UserInputState == 0 else "Mouse_Button1Up", [])
		elif data.UserInputType == 8 and data.UserInputState in [0, 2] and not processed:
			_fire_existing_runtime_event(local_player, "Mouse_KeyDown" if data.UserInputState == 0 else "Mouse_KeyUp", [String.chr(int(data.KeyCode)).to_lower()])

func notify_humanoid_state_changed(humanoid: Node, previous: int, next_state: int) -> void:
	_fire_existing_runtime_event(humanoid, "StateChanged", [previous, next_state])
	for signal_state in {"Jumping": 3, "FreeFalling": 5}:
		var state_id: int = {"Jumping": 3, "FreeFalling": 5}[signal_state]
		if previous == state_id or next_state == state_id:
			_fire_existing_runtime_event(humanoid, signal_state, [next_state == state_id])

func _fire_existing_runtime_event(target: Node, event_name: String, args: Array) -> void:
	if not is_instance_valid(target):
		return
	var registry: Dictionary = target.get_meta("_bobux_event_registry", {})
	var event: Variant = registry.get(event_name)
	if event != null:
		event.callv("Fire", args)

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
	if visible_in_world and root_node is MeshInstance3D and bool(root_node.get_meta("bobux_deferred_geometry", false)):
		var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
		importer.scale_factor = BobuxInstance.wrap(root_node)._stud_scale()
		importer.materialize_template_part(root_node)
	if root_node is Node3D:
		(root_node as Node3D).visible = visible_in_world
	root_node.set_meta("BobuxTemplateOnly", not visible_in_world)
	for child in root_node.get_children():
		_set_inventory_tool_tree_visible(child, visible_in_world)


func _position_equipped_tool(tool_node: Node) -> void:
	if not (tool_node is Node3D):
		return
	var tool_root := tool_node as Node3D
	var character := tool_node.get_parent()
	var hand_frame := Transform3D(Basis.IDENTITY, Vector3(1.55, 2.72, -0.62))
	if is_instance_valid(character) and character.has_method("get_tool_hand_transform"):
		hand_frame = character.call("get_tool_hand_transform")
	var properties: Dictionary = tool_node.get_meta("roblox_properties", {}) if tool_node.get_meta("roblox_properties", {}) is Dictionary else {}
	var grip_position := _vector3_from_manifest_value(properties.get("GripPos", properties.get("GripPosition", Vector3.ZERO)), Vector3.ZERO)
	var grip := Transform3D(Basis.IDENTITY, grip_position)
	var grip_value: Variant = properties.get("Grip")
	if grip_value is BobuxCFrame:
		grip = grip_value.transform
	else:
		var forward := _vector3_from_manifest_value(properties.get("GripForward", Vector3.FORWARD), Vector3.FORWARD)
		var up := _vector3_from_manifest_value(properties.get("GripUp", Vector3.UP), Vector3.UP)
		if forward.length_squared() > 0.001 and forward.cross(up).length_squared() > 0.001:
			grip.basis = Basis.looking_at(forward, up)
	var desired := hand_frame * grip.affine_inverse()
	var handle := _find_tool_handle(tool_node)
	if handle != null and handle != tool_root:
		desired.origin -= desired.basis * handle.position
	tool_root.transform = desired


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
	if x is Vector3:
		if y is Vector3: return _create_cframe_look_at(x, y)
		return BobuxCFrame.new(Transform3D(Basis.IDENTITY, x))
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

func _build_color3_library() -> Dictionary:
	return {
		"new": func(r: Variant = 1.0, g: Variant = 1.0, b: Variant = 1.0): return Color(float(r), float(g), float(b)),
		"fromRGB": func(r: Variant = 255.0, g: Variant = 255.0, b: Variant = 255.0): return Color(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0),
		"fromHSV": func(h: Variant = 0.0, s: Variant = 0.0, v: Variant = 0.0): return Color.from_hsv(float(h), float(s), float(v)),
		"fromHex": func(value: Variant = "ffffff"): return Color.html(str(value).trim_prefix("#")),
	}

func _build_raycast_params_library() -> Dictionary:
	return {
		"new": func(): return BobuxRaycastParams.new(),
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
		},
		"EasingStyle": {
			"Linear": 0, "Sine": 1, "Back": 2, "Quad": 3, "Quart": 4,
			"Quint": 5, "Bounce": 6, "Elastic": 7, "Exponential": 8,
			"Circular": 9, "Cubic": 10
		},
		"EasingDirection": {"In": 0, "Out": 1, "InOut": 2},
		"BulkMoveMode": {
			"FireAllEvents": 0,
			"FireCFrameChanged": 1,
		},
		"RaycastFilterType": {
			"Exclude": 0,
			"Blacklist": 0,
			"Include": 1,
			"Whitelist": 1,
		},
		"CoreGuiType": {
			"PlayerList": 0, "Health": 1, "Backpack": 2, "Chat": 3,
			"EmotesMenu": 4, "SelfView": 5, "Captures": 6, "All": 7
		},
		"UserInputType": {
			"MouseButton1": 0, "MouseButton2": 1, "MouseButton3": 2, "MouseWheel": 3, "MouseMovement": 4,
			"Touch": 7, "Keyboard": 8, "Gamepad1": 12
		},
		"UserInputState": {"Begin": 0, "Change": 1, "End": 2, "Cancel": 3, "None": 4},
		"KeyCode": RobloxInputBridge.key_codes(),
		"HumanoidStateType": {
			"Running": 8, "Jumping": 3, "Freefall": 5, "Landed": 7,
			"Climbing": 12, "Swimming": 4, "Seated": 13, "Dead": 15
		}
	}
