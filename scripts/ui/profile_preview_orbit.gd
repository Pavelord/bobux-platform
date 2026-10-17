extends Control

var player_ref: WeakRef
var _mouse_drag := false
var _touch_index := -1
var _last_touch_msec := -1000

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	visibility_changed.connect(_reset_capture)

func set_player(player: Node3D) -> void:
	player_ref = weakref(player)

func turn(amount: float) -> void:
	if player_ref == null: return
	var player := player_ref.get_ref() as Node3D
	if is_instance_valid(player):
		player.rotation.y = wrapf(player.rotation.y + amount, -PI, PI)

func _reset_capture() -> void:
	_mouse_drag = false
	_touch_index = -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed and _touch_index < 0: _touch_index = event.index
		elif not event.pressed and _touch_index == event.index: _touch_index = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_last_touch_msec = Time.get_ticks_msec()
		turn(event.relative.x * 0.012)
		accept_event()
	elif event is InputEventMouseButton and Time.get_ticks_msec() - _last_touch_msec > 500:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_mouse_drag = event.pressed
			accept_event()
	elif event is InputEventMouseMotion and _mouse_drag and Time.get_ticks_msec() - _last_touch_msec > 500:
		turn(event.relative.x * 0.012)
		accept_event()
