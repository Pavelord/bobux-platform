extends Node

signal update_check_finished(has_update: bool, message: String)

const DEFAULT_MOBILE_MANIFEST_URL: String = "http://109.71.245.162/mobile/latest.json"
const UPDATE_CHECK_TIMEOUT_SECONDS: float = 10.0
const LOOK_SENSITIVITY: float = 0.006
const JOYSTICK_RADIUS: float = 74.0
const JOYSTICK_MODE_FIXED: String = "Fixed"
const JOYSTICK_MODE_DYNAMIC: String = "Dynamic"
const JOYSTICK_MODE_FOLLOWING: String = "Following"
const GAMEPLAY_SCENE_PATH: String = "res://scenes/main/main.tscn"
const CONTROL_SETTINGS_PATH: String = "user://settings/mobile_controls.json"
const JUMP_TEXTURE_PATH: String = "res://assets/mobile/jump_button.png"
const JUMP_TEXTURE_PRESSED_PATH: String = "res://assets/mobile/jump_button_pressed.png"
const SPRINT_TEXTURE_PATH: String = "res://assets/mobile/sprint_button.png"
const SHIFT_LOCK_OFF_TEXTURE_PATH: String = "res://assets/mobile/shift_lock_off.png"
const SHIFT_LOCK_ON_TEXTURE_PATH: String = "res://assets/mobile/shift_lock_on.png"
const PINCH_ZOOM_SENSITIVITY: float = 0.018
const PINCH_ZOOM_DEADZONE: float = 5.0
const UI_SCROLL_TAP_CANCEL_DISTANCE: float = 10.0
const TOP_RUNTIME_HUD_TOUCH_HEIGHT: float = 74.0

var _is_mobile_beta: bool = false
var _controls_enabled: bool = false
var _ui_layer: CanvasLayer = null
var _joystick_base: Panel = null
var _joystick_knob: Panel = null
var _jump_button: Button = null
var _jump_texture: Texture2D = null
var _jump_pressed_texture: Texture2D = null
var _shift_lock_button: Button = null
var _run_button: Button = null
var _shift_lock_enabled: bool = false
var _sprint_enabled: bool = false
var _move_vector: Vector2 = Vector2.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var _zoom_delta: float = 0.0
var _jump_pressed_once: bool = false
var _jump_held: bool = false
var _move_touch_index: int = -1
var _look_touch_index: int = -1
var _pinch_touch_index: int = -1
var _jump_touch_index: int = -1
var _run_touch_index: int = -1
var _shift_lock_touch_index: int = -1
var _ui_scroll_touch_index: int = -1
var _ui_scroll_target: ScrollContainer = null
var _ui_scroll_start_position: Vector2 = Vector2.ZERO
var _ui_scroll_dragged: bool = false
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_default_offsets: Vector4 = Vector4.ZERO
var _touch_positions: Dictionary = {}
var _last_pinch_distance: float = 0.0
var _control_settings: Dictionary = {}
var _latest_update_payload: Dictionary = {}
var _update_dialog: ConfirmationDialog = null
var _checking_updates: bool = false
var _last_auto_opened_update_url: String = ""


func _ready() -> void:
	_is_mobile_beta = OS.has_feature("android") or OS.has_feature("ios") or bool(ProjectSettings.get_setting("bobux/mobile/force_mobile_beta", false))
	_load_control_settings()
	if _is_mobile_beta:
		call_deferred("check_for_updates", false)


func _process(_delta: float) -> void:
	if _controls_enabled and not _is_current_scene_gameplay():
		set_gameplay_touch_controls_enabled(false)


func is_mobile_beta() -> bool:
	return _is_mobile_beta


func get_move_vector() -> Vector2:
	return _move_vector


func consume_look_delta() -> Vector2:
	var delta: Vector2 = _look_delta
	_look_delta = Vector2.ZERO
	return delta


func consume_zoom_delta() -> float:
	var delta: float = _zoom_delta
	_zoom_delta = 0.0
	return delta


func get_control_settings() -> Dictionary:
	return _control_settings.duplicate(true)


func update_control_settings(settings: Dictionary) -> void:
	for key in settings.keys():
		_control_settings[key] = settings[key]
	_save_control_settings()
	if _controls_enabled:
		_rebuild_touch_controls()


func consume_jump_pressed() -> bool:
	var pressed: bool = _jump_pressed_once
	_jump_pressed_once = false
	return pressed


func is_jump_pressed() -> bool:
	return _jump_held


func set_gameplay_touch_controls_enabled(enabled: bool) -> void:
	if not _is_mobile_beta:
		enabled = false
	if enabled and not _is_current_scene_gameplay():
		return
	if _controls_enabled == enabled:
		return
	_controls_enabled = enabled
	if enabled:
		_build_touch_controls()
	else:
		_clear_touch_state()
		if _ui_layer != null:
			_ui_layer.queue_free()
		_ui_layer = null
		_joystick_base = null
		_joystick_knob = null
		_jump_button = null
		_shift_lock_button = null
		_run_button = null


func disable_gameplay_touch_controls() -> void:
	set_gameplay_touch_controls_enabled(false)


func check_for_updates(show_prompt: bool = true) -> void:
	if not _is_mobile_beta or _checking_updates:
		return
	var manifest_url: String = str(ProjectSettings.get_setting("bobux/mobile/manifest_url", DEFAULT_MOBILE_MANIFEST_URL)).strip_edges()
	if manifest_url.is_empty():
		update_check_finished.emit(false, "Mobile manifest URL is empty.")
		return
	_checking_updates = true
	var request := HTTPRequest.new()
	request.timeout = UPDATE_CHECK_TIMEOUT_SECONDS
	add_child(request)
	var error: Error = request.request(manifest_url)
	if error != OK:
		request.queue_free()
		_checking_updates = false
		update_check_finished.emit(false, "Manifest request failed: %s" % error_string(error))
		return
	var response: Array = await request.request_completed
	request.queue_free()
	_checking_updates = false
	if response.size() < 4:
		update_check_finished.emit(false, "Manifest response was incomplete.")
		return
	var result_code: int = int(response[0])
	var status_code: int = int(response[1])
	var body: PackedByteArray = response[3] as PackedByteArray
	if result_code != HTTPRequest.RESULT_SUCCESS or status_code < 200 or status_code >= 300:
		update_check_finished.emit(false, "Manifest request failed: result=%d status=%d" % [result_code, status_code])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		update_check_finished.emit(false, "Manifest JSON is invalid.")
		return
	var manifest: Dictionary = parsed as Dictionary
	var platform_payload: Dictionary = _get_platform_payload(manifest)
	var remote_build: int = int(platform_payload.get("build", manifest.get("build", 0)))
	var current_build: int = int(ProjectSettings.get_setting("bobux/mobile/build", 1))
	var download_url: String = _get_update_download_url(platform_payload, manifest)
	var has_update: bool = remote_build > current_build and not download_url.is_empty()
	_latest_update_payload = platform_payload if has_update else {}
	update_check_finished.emit(has_update, "Update available." if has_update else "Mobile build is up to date.")
	if has_update and (show_prompt or bool(platform_payload.get("required", false))):
		_show_update_dialog(platform_payload)


func show_update_prompt_if_available() -> void:
	if not _is_mobile_beta:
		return
	if _latest_update_payload.is_empty():
		check_for_updates(true)
	else:
		_show_update_dialog(_latest_update_payload)


func _input(event: InputEvent) -> void:
	if _is_mobile_beta and not _controls_enabled:
		_handle_mobile_ui_scroll_input(event)
		return
	if not _controls_enabled or not _is_current_scene_gameplay():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _controls_enabled:
		_clear_touch_state()


func _build_touch_controls() -> void:
	if _ui_layer != null:
		return
	_load_control_settings()
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MobileTouchControls"
	# BUGFIX: keep gameplay touch controls below menu and popup layers.
	_ui_layer.layer = 80
	get_tree().root.add_child(_ui_layer)

	_joystick_base = Panel.new()
	_joystick_base.name = "MoveJoystick"
	var joystick_scale: float = clampf(float(_control_settings.get("joystick_scale", 1.08)), 0.72, 1.65)
	var joystick_size: float = 156.0 * joystick_scale
	var joystick_margin_x: float = float(_control_settings.get("joystick_margin_x", 64.0))
	var joystick_margin_bottom: float = float(_control_settings.get("joystick_margin_bottom", 72.0))
	_joystick_base.custom_minimum_size = Vector2(joystick_size, joystick_size)
	_joystick_base.anchor_left = 0.0
	_joystick_base.anchor_top = 1.0
	_joystick_base.anchor_right = 0.0
	_joystick_base.anchor_bottom = 1.0
	_joystick_base.offset_left = joystick_margin_x
	_joystick_base.offset_top = -(joystick_margin_bottom + joystick_size)
	_joystick_base.offset_right = joystick_margin_x + joystick_size
	_joystick_base.offset_bottom = -joystick_margin_bottom
	_joystick_default_offsets = Vector4(
		_joystick_base.offset_left,
		_joystick_base.offset_top,
		_joystick_base.offset_right,
		_joystick_base.offset_bottom
	)
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.add_theme_stylebox_override("panel", _make_round_style(Color(0.08, 0.10, 0.12, 0.34), Color(1.0, 1.0, 1.0, 0.22), int(joystick_size * 0.5)))
	_ui_layer.add_child(_joystick_base)

	_joystick_knob = Panel.new()
	_joystick_knob.name = "MoveKnob"
	var knob_size: float = 66.0 * joystick_scale
	_joystick_knob.custom_minimum_size = Vector2(knob_size, knob_size)
	_joystick_knob.anchor_left = 0.5
	_joystick_knob.anchor_top = 0.5
	_joystick_knob.anchor_right = 0.5
	_joystick_knob.anchor_bottom = 0.5
	_joystick_knob.offset_left = -knob_size * 0.5
	_joystick_knob.offset_top = -knob_size * 0.5
	_joystick_knob.offset_right = knob_size * 0.5
	_joystick_knob.offset_bottom = knob_size * 0.5
	_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_knob.add_theme_stylebox_override("panel", _make_round_style(Color(0.93, 0.95, 0.98, 0.72), Color(0.0, 0.0, 0.0, 0.14), int(knob_size * 0.5)))
	_joystick_base.add_child(_joystick_knob)

	_jump_button = Button.new()
	_jump_button.name = "JumpButton"
	_jump_button.text = ""
	var jump_scale: float = clampf(float(_control_settings.get("jump_scale", 1.0)), 0.72, 1.55)
	var jump_size: Vector2 = Vector2(128, 128) * jump_scale
	var jump_margin_x: float = float(_control_settings.get("jump_margin_x", 74.0))
	var jump_margin_bottom: float = float(_control_settings.get("jump_margin_bottom", 78.0))
	_jump_button.custom_minimum_size = jump_size
	_jump_button.anchor_left = 1.0
	_jump_button.anchor_top = 1.0
	_jump_button.anchor_right = 1.0
	_jump_button.anchor_bottom = 1.0
	_jump_button.offset_left = -(jump_margin_x + jump_size.x)
	_jump_button.offset_top = -(jump_margin_bottom + jump_size.y)
	_jump_button.offset_right = -jump_margin_x
	_jump_button.offset_bottom = -jump_margin_bottom
	_jump_button.focus_mode = Control.FOCUS_NONE
	_jump_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jump_button.expand_icon = true
	_jump_texture = load(JUMP_TEXTURE_PATH) as Texture2D
	_jump_pressed_texture = load(JUMP_TEXTURE_PRESSED_PATH) as Texture2D
	if _jump_texture != null:
		_jump_button.icon = _jump_texture
	_jump_button.add_theme_stylebox_override("normal", _make_round_style(Color(0.08, 0.08, 0.08, 0.18), Color(1.0, 1.0, 1.0, 0.0), int(jump_size.x * 0.5)))
	_jump_button.add_theme_stylebox_override("pressed", _make_round_style(Color(0.08, 0.08, 0.08, 0.30), Color(1.0, 1.0, 1.0, 0.10), int(jump_size.x * 0.5)))
	_jump_button.add_theme_color_override("font_color", Color.WHITE)
	_ui_layer.add_child(_jump_button)

	# Shift Lock Button
	_shift_lock_button = Button.new()
	_shift_lock_button.name = "ShiftLockButton"
	_shift_lock_button.text = ""
	_shift_lock_button.focus_mode = Control.FOCUS_NONE
	_shift_lock_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shift_lock_button.expand_icon = true
	var sl_scale: float = clampf(float(_control_settings.get("shift_lock_scale", 1.0)), 0.72, 1.7)
	var sl_size: Vector2 = Vector2(96, 96) * sl_scale
	var sl_margin_x: float = float(_control_settings.get("shift_lock_margin_x", 34.0))
	var sl_margin_bottom: float = float(_control_settings.get("shift_lock_margin_bottom", 78.0))
	_shift_lock_button.custom_minimum_size = sl_size
	_shift_lock_button.anchor_left = 1.0
	_shift_lock_button.anchor_top = 1.0
	_shift_lock_button.anchor_right = 1.0
	_shift_lock_button.anchor_bottom = 1.0
	_shift_lock_button.offset_left = -(sl_margin_x + sl_size.x)
	_shift_lock_button.offset_top = -(sl_margin_bottom + sl_size.y)
	_shift_lock_button.offset_right = -sl_margin_x
	_shift_lock_button.offset_bottom = -sl_margin_bottom
	_ui_layer.add_child(_shift_lock_button)
	_update_shift_lock_button_ui()

	# Run Button
	_run_button = Button.new()
	_run_button.name = "RunButton"
	_run_button.text = ""
	_run_button.focus_mode = Control.FOCUS_NONE
	_run_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var run_scale: float = clampf(float(_control_settings.get("run_scale", 1.08)), 0.72, 1.7)
	var run_size: Vector2 = Vector2(96, 96) * run_scale
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var min_run_margin_x: float = joystick_margin_x + joystick_size + 28.0
	var max_run_margin_x: float = maxf(min_run_margin_x, viewport_width - run_size.x - 24.0)
	var run_margin_x: float = clampf(float(_control_settings.get("run_margin_x", min_run_margin_x)), min_run_margin_x, max_run_margin_x)
	var run_margin_bottom: float = float(_control_settings.get("run_margin_bottom", joystick_margin_bottom + 16.0))
	_run_button.custom_minimum_size = run_size
	_run_button.anchor_left = 0.0
	_run_button.anchor_top = 1.0
	_run_button.anchor_right = 0.0
	_run_button.anchor_bottom = 1.0
	_run_button.offset_left = run_margin_x
	_run_button.offset_top = -(run_margin_bottom + run_size.y)
	_run_button.offset_right = run_margin_x + run_size.x
	_run_button.offset_bottom = -run_margin_bottom
	_run_button.expand_icon = true
	var sprint_texture := load(SPRINT_TEXTURE_PATH) as Texture2D
	if sprint_texture != null:
		_run_button.icon = sprint_texture
	else:
		_run_button.text = "RUN"
		_run_button.add_theme_font_size_override("font_size", 13)
	_run_button.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98, 0.92))
	_ui_layer.add_child(_run_button)
	_update_run_button_ui()

	call_deferred("_refresh_joystick_center")


func _refresh_joystick_center() -> void:
	if _joystick_base != null:
		_joystick_center = _joystick_base.get_global_rect().get_center()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_positions[event.index] = event.position
		if event.position.y <= TOP_RUNTIME_HUD_TOUCH_HEIGHT:
			return
		if _is_jump_touch(event.position) and _jump_touch_index == -1:
			_jump_touch_index = event.index
			_jump_pressed_once = true
			_jump_held = true
			_set_jump_visual_pressed(true)
			return
		if _is_shift_lock_touch(event.position) and _shift_lock_touch_index == -1:
			_shift_lock_touch_index = event.index
			_shift_lock_enabled = not _shift_lock_enabled
			_update_shift_lock_button_ui()
			return
		if _is_run_touch(event.position) and _run_touch_index == -1:
			_run_touch_index = event.index
			_sprint_enabled = not _sprint_enabled
			_update_run_button_ui()
			return
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		if event.position.x <= viewport_size.x * 0.48 and _move_touch_index == -1:
			_move_touch_index = event.index
			if _get_joystick_mode() != JOYSTICK_MODE_FIXED:
				_place_joystick_center(event.position)
			else:
				_refresh_joystick_center()
			_update_move_touch(event.position)
		elif _look_touch_index == -1:
			_look_touch_index = event.index
		elif _pinch_touch_index == -1:
			_pinch_touch_index = event.index
			_last_pinch_distance = _get_current_pinch_distance()
	else:
		_touch_positions.erase(event.index)
		if event.index == _move_touch_index:
			_move_touch_index = -1
			_move_vector = Vector2.ZERO
			_reset_joystick_knob()
			_restore_joystick_position()
		if event.index == _look_touch_index:
			_look_touch_index = -1
			_last_pinch_distance = 0.0
			if _pinch_touch_index != -1 and _touch_positions.has(_pinch_touch_index):
				_look_touch_index = _pinch_touch_index
				_pinch_touch_index = -1
		if event.index == _jump_touch_index:
			_jump_touch_index = -1
			_jump_held = false
			_set_jump_visual_pressed(false)
		if event.index == _shift_lock_touch_index:
			_shift_lock_touch_index = -1
		if event.index == _run_touch_index:
			_run_touch_index = -1
		if event.index == _pinch_touch_index:
			_pinch_touch_index = -1
			_last_pinch_distance = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_positions[event.index] = event.position
	if event.index == _move_touch_index:
		_update_move_touch(event.position)
	elif event.index == _look_touch_index or event.index == _pinch_touch_index:
		if _look_touch_index != -1 and _pinch_touch_index != -1:
			_update_pinch_zoom()
			return
		_look_delta += event.relative * LOOK_SENSITIVITY


func _update_move_touch(position: Vector2) -> void:
	if _joystick_center == Vector2.ZERO:
		_refresh_joystick_center()
	var offset: Vector2 = position - _joystick_center
	var joystick_scale: float = clampf(float(_control_settings.get("joystick_scale", 1.08)), 0.72, 1.65)
	var radius: float = JOYSTICK_RADIUS * joystick_scale
	if _get_joystick_mode() == JOYSTICK_MODE_FOLLOWING and offset.length() > radius:
		var overflow: float = offset.length() - radius
		_place_joystick_center(_joystick_center + offset.normalized() * overflow)
		offset = position - _joystick_center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	var raw_vector := Vector2(offset.x / radius, offset.y / radius)
	_move_vector = _apply_joystick_deadzone(raw_vector, float(_control_settings.get("joystick_deadzone", 0.12)))
	if _joystick_knob != null:
		var knob_half: float = _joystick_knob.custom_minimum_size.x * 0.5
		_joystick_knob.offset_left = -knob_half + offset.x
		_joystick_knob.offset_top = -knob_half + offset.y
		_joystick_knob.offset_right = knob_half + offset.x
		_joystick_knob.offset_bottom = knob_half + offset.y


func _reset_joystick_knob() -> void:
	if _joystick_knob != null:
		var knob_half: float = _joystick_knob.custom_minimum_size.x * 0.5
		_joystick_knob.offset_left = -knob_half
		_joystick_knob.offset_top = -knob_half
		_joystick_knob.offset_right = knob_half
		_joystick_knob.offset_bottom = knob_half


static func _apply_joystick_deadzone(value: Vector2, deadzone: float) -> Vector2:
	var magnitude := minf(value.length(), 1.0)
	var safe_deadzone := clampf(deadzone, 0.0, 0.95)
	if magnitude <= safe_deadzone or magnitude <= 0.0001:
		return Vector2.ZERO
	var remapped_magnitude := (magnitude - safe_deadzone) / (1.0 - safe_deadzone)
	return value.normalized() * remapped_magnitude


func _get_joystick_mode() -> String:
	var mode := str(_control_settings.get("joystick_mode", JOYSTICK_MODE_FIXED)).strip_edges().capitalize()
	if mode not in [JOYSTICK_MODE_FIXED, JOYSTICK_MODE_DYNAMIC, JOYSTICK_MODE_FOLLOWING]:
		return JOYSTICK_MODE_FIXED
	return mode


func _place_joystick_center(center: Vector2) -> void:
	if _joystick_base == null:
		return
	var half_size := _joystick_base.size * 0.5
	_joystick_base.global_position = center - half_size
	_joystick_center = center


func _restore_joystick_position() -> void:
	if _joystick_base == null or _get_joystick_mode() == JOYSTICK_MODE_FIXED:
		return
	_joystick_base.offset_left = _joystick_default_offsets.x
	_joystick_base.offset_top = _joystick_default_offsets.y
	_joystick_base.offset_right = _joystick_default_offsets.z
	_joystick_base.offset_bottom = _joystick_default_offsets.w
	_refresh_joystick_center()


func _rebuild_touch_controls() -> void:
	if _ui_layer != null:
		_ui_layer.queue_free()
	_ui_layer = null
	_joystick_base = null
	_joystick_knob = null
	_jump_button = null
	_shift_lock_button = null
	_run_button = null
	_jump_texture = null
	_jump_pressed_texture = null
	_clear_touch_state()
	_build_touch_controls()


func _get_current_pinch_distance() -> float:
	if _look_touch_index == -1 or _pinch_touch_index == -1:
		return 0.0
	if not _touch_positions.has(_look_touch_index) or not _touch_positions.has(_pinch_touch_index):
		return 0.0
	var first: Vector2 = _touch_positions[_look_touch_index] as Vector2
	var second: Vector2 = _touch_positions[_pinch_touch_index] as Vector2
	return first.distance_to(second)


func _update_pinch_zoom() -> void:
	var current_distance: float = _get_current_pinch_distance()
	if current_distance <= 0.0:
		return
	if _last_pinch_distance <= 0.0:
		_last_pinch_distance = current_distance
		return
	var distance_delta: float = current_distance - _last_pinch_distance
	_last_pinch_distance = current_distance
	if absf(distance_delta) < PINCH_ZOOM_DEADZONE:
		return
	_zoom_delta += -distance_delta * PINCH_ZOOM_SENSITIVITY


func _load_control_settings() -> void:
	_control_settings = {
		"joystick_mode": JOYSTICK_MODE_FIXED,
		"joystick_deadzone": 0.12,
		"joystick_scale": 1.08,
		"joystick_margin_x": 64.0,
		"joystick_margin_bottom": 72.0,
		"jump_scale": 1.0,
		"jump_margin_x": 74.0,
		"jump_margin_bottom": 78.0,
		"shift_lock_scale": 1.0,
		"shift_lock_margin_x": 74.0,
		"shift_lock_margin_bottom": 220.0,
		"run_scale": 1.08,
		"run_margin_x": 260.0,
		"run_margin_bottom": 78.0
	}
	if not FileAccess.file_exists(CONTROL_SETTINGS_PATH):
		return
	var file := FileAccess.open(CONTROL_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var stored := parsed as Dictionary
		for key in stored.keys():
			_control_settings[key] = stored[key]


func _save_control_settings() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTROL_SETTINGS_PATH.get_base_dir()))
	var file := FileAccess.open(CONTROL_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_control_settings, "\t"))
	file.close()


func _is_jump_touch(position: Vector2) -> bool:
	return _jump_button != null and _jump_button.get_global_rect().has_point(position)

func _is_run_touch(position: Vector2) -> bool:
	return _run_button != null and _run_button.get_global_rect().has_point(position)

func _is_shift_lock_touch(position: Vector2) -> bool:
	return _shift_lock_button != null and _shift_lock_button.get_global_rect().has_point(position)


func _clear_touch_state() -> void:
	_move_touch_index = -1
	_look_touch_index = -1
	_pinch_touch_index = -1
	_jump_touch_index = -1
	_run_touch_index = -1
	_shift_lock_touch_index = -1
	_ui_scroll_touch_index = -1
	_ui_scroll_target = null
	_ui_scroll_start_position = Vector2.ZERO
	_ui_scroll_dragged = false
	_touch_positions.clear()
	_move_vector = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_zoom_delta = 0.0
	_jump_pressed_once = false
	_jump_held = false
	_shift_lock_enabled = false
	_sprint_enabled = false
	_set_jump_visual_pressed(false)
	_reset_joystick_knob()
	_restore_joystick_position()


func is_shift_lock_enabled() -> bool:
	return _shift_lock_enabled


func is_sprint_enabled() -> bool:
	return _sprint_enabled


func _update_shift_lock_button_ui() -> void:
	if _shift_lock_button != null:
		var next_icon := load(SHIFT_LOCK_ON_TEXTURE_PATH if _shift_lock_enabled else SHIFT_LOCK_OFF_TEXTURE_PATH) as Texture2D
		if next_icon != null:
			_shift_lock_button.icon = next_icon
		_shift_lock_button.text = "" if next_icon != null else ("LOCK\nON" if _shift_lock_enabled else "LOCK\nOFF")
		if _shift_lock_enabled:
			_shift_lock_button.add_theme_stylebox_override("normal", _make_round_style(Color(0.02, 0.47, 0.78, 0.10), Color(1.0, 1.0, 1.0, 0.0), 48))
			_shift_lock_button.add_theme_stylebox_override("hover", _make_round_style(Color(0.04, 0.56, 0.92, 0.16), Color(1.0, 1.0, 1.0, 0.0), 48))
			_shift_lock_button.add_theme_stylebox_override("pressed", _make_round_style(Color(0.02, 0.38, 0.68, 0.22), Color(1.0, 1.0, 1.0, 0.0), 48))
		else:
			_shift_lock_button.add_theme_stylebox_override("normal", _make_round_style(Color(0.18, 0.20, 0.23, 0.08), Color(1.0, 1.0, 1.0, 0.0), 48))
			_shift_lock_button.add_theme_stylebox_override("hover", _make_round_style(Color(0.24, 0.26, 0.30, 0.14), Color(1.0, 1.0, 1.0, 0.0), 48))
			_shift_lock_button.add_theme_stylebox_override("pressed", _make_round_style(Color(0.14, 0.16, 0.20, 0.20), Color(1.0, 1.0, 1.0, 0.0), 48))


func _update_run_button_ui() -> void:
	if _run_button != null:
		if _sprint_enabled:
			if _run_button.icon == null:
				_run_button.text = "RUN"
			_run_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_run_button.add_theme_stylebox_override("normal", _make_round_style(Color(0.16, 0.16, 0.16, 0.44), Color(1.0, 1.0, 1.0, 0.46), 39))
			_run_button.add_theme_stylebox_override("hover", _make_round_style(Color(0.18, 0.18, 0.18, 0.52), Color(1.0, 1.0, 1.0, 0.55), 39))
			_run_button.add_theme_stylebox_override("pressed", _make_round_style(Color(0.08, 0.08, 0.08, 0.60), Color(1.0, 1.0, 1.0, 0.58), 39))
		else:
			if _run_button.icon == null:
				_run_button.text = "RUN"
			_run_button.modulate = Color(1.0, 1.0, 1.0, 0.72)
			_run_button.add_theme_stylebox_override("normal", _make_round_style(Color(0.20, 0.20, 0.20, 0.26), Color(1.0, 1.0, 1.0, 0.20), 39))
			_run_button.add_theme_stylebox_override("hover", _make_round_style(Color(0.24, 0.24, 0.24, 0.34), Color(1.0, 1.0, 1.0, 0.26), 39))
			_run_button.add_theme_stylebox_override("pressed", _make_round_style(Color(0.14, 0.14, 0.14, 0.44), Color(1.0, 1.0, 1.0, 0.30), 39))


func _set_jump_visual_pressed(pressed: bool) -> void:
	if _jump_button == null:
		return
	if pressed and _jump_pressed_texture != null:
		_jump_button.icon = _jump_pressed_texture
	elif _jump_texture != null:
		_jump_button.icon = _jump_texture


func _get_platform_payload(manifest: Dictionary) -> Dictionary:
	var key: String = "android" if OS.has_feature("android") else "ios"
	if manifest.has(key) and manifest[key] is Dictionary:
		return manifest[key] as Dictionary
	return manifest


func _get_update_download_url(platform_payload: Dictionary, manifest: Dictionary) -> String:
	for key in ["apk_url", "download_url", "url", "zip_url"]:
		if platform_payload.has(key):
			var value: String = str(platform_payload.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	for key in ["apk_url", "download_url", "url", "zip_url"]:
		if manifest.has(key):
			var value: String = str(manifest.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	return ""


func _handle_mobile_ui_scroll_input(event: InputEvent) -> void:
	if _is_current_scene_gameplay():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var target: ScrollContainer = _find_scroll_container_at(get_tree().current_scene, touch.position)
			if target != null:
				_ui_scroll_touch_index = touch.index
				_ui_scroll_target = target
				_ui_scroll_start_position = touch.position
				_ui_scroll_dragged = false
		elif touch.index == _ui_scroll_touch_index:
			# BUGFIX: a scroll release must not be reinterpreted as tapping a game card.
			if _ui_scroll_dragged:
				get_viewport().set_input_as_handled()
			_ui_scroll_touch_index = -1
			_ui_scroll_target = null
			_ui_scroll_start_position = Vector2.ZERO
			_ui_scroll_dragged = false
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _ui_scroll_touch_index and _ui_scroll_target != null and is_instance_valid(_ui_scroll_target):
			if drag.position.distance_to(_ui_scroll_start_position) >= UI_SCROLL_TAP_CANCEL_DISTANCE:
				_ui_scroll_dragged = true
			_apply_mobile_ui_scroll(_ui_scroll_target, drag.relative)
			get_viewport().set_input_as_handled()


func _apply_mobile_ui_scroll(scroll: ScrollContainer, relative: Vector2) -> void:
	if absf(relative.y) >= absf(relative.x):
		if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int(round(relative.y)))
		else:
			var parent_vertical := _find_parent_scroll_container_with_axis(scroll, true)
			if parent_vertical != null:
				parent_vertical.scroll_vertical = maxi(0, parent_vertical.scroll_vertical - int(round(relative.y)))
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		scroll.scroll_horizontal = maxi(0, scroll.scroll_horizontal - int(round(relative.x)))
	else:
		var parent_horizontal := _find_parent_scroll_container_with_axis(scroll, false)
		if parent_horizontal != null:
			parent_horizontal.scroll_horizontal = maxi(0, parent_horizontal.scroll_horizontal - int(round(relative.x)))


func _find_parent_scroll_container_with_axis(node: Node, vertical: bool) -> ScrollContainer:
	var current := node.get_parent()
	while current != null:
		if current is ScrollContainer:
			var scroll := current as ScrollContainer
			if vertical and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return scroll
			if not vertical and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return scroll
		current = current.get_parent()
	return null


func _find_scroll_container_at(root: Node, position: Vector2) -> ScrollContainer:
	if root == null:
		return null
	for index in range(root.get_child_count() - 1, -1, -1):
		var child: Node = root.get_child(index)
		var nested: ScrollContainer = _find_scroll_container_at(child, position)
		if nested != null:
			return nested
	if root is ScrollContainer:
		var scroll := root as ScrollContainer
		if scroll.is_visible_in_tree() and scroll.get_global_rect().has_point(position):
			var can_scroll_vertical: bool = scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			var can_scroll_horizontal: bool = scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			if can_scroll_vertical or can_scroll_horizontal:
				return scroll
	return null


func _show_update_dialog(payload: Dictionary) -> void:
	if _update_dialog != null and is_instance_valid(_update_dialog):
		_update_dialog.queue_free()
	var url: String = _get_update_download_url(payload, payload)
	if url.is_empty():
		return
	_update_dialog = ConfirmationDialog.new()
	_update_dialog.title = "Bobux update"
	_update_dialog.dialog_text = "%s\n\nTap Download to install the newest mobile beta." % str(payload.get("notes", "A new Bobux mobile beta is available."))
	_update_dialog.ok_button_text = "Download"
	_update_dialog.cancel_button_text = "Later"
	_update_dialog.exclusive = bool(payload.get("required", false))
	get_tree().root.add_child(_update_dialog)
	_update_dialog.confirmed.connect(func() -> void:
		OS.shell_open(url)
	)
	_update_dialog.popup_centered(Vector2i(520, 310))
	if bool(payload.get("required", false)) and bool(ProjectSettings.get_setting("bobux/mobile/auto_open_required_update", true)):
		if _last_auto_opened_update_url != url:
			_last_auto_opened_update_url = url
			call_deferred("_open_update_url_once", url)


func _open_update_url_once(url: String) -> void:
	await get_tree().create_timer(0.35).timeout
	OS.shell_open(url)


func _is_current_scene_gameplay() -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	var scene_path: String = str(scene.scene_file_path)
	return scene_path == GAMEPLAY_SCENE_PATH or scene.name == "Main"


func _make_round_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style
