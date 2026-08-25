class_name AvatarPreviewInputOverlay
extends Control

var input_handler: Callable = Callable()

var _pointer_inside := false
var _drag_capture := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void:
		_pointer_inside = true
	)
	mouse_exited.connect(func() -> void:
		_pointer_inside = false
	)


func set_input_handler(handler: Callable) -> void:
	input_handler = handler

func _exit_tree() -> void:
	input_handler = Callable()
	_drag_capture = false
	_pointer_inside = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func force_capture_for_validation(enabled: bool) -> void:
	_drag_capture = enabled
	_pointer_inside = enabled


func _gui_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if not input_handler.is_valid():
		return
	_update_drag_capture(event)
	input_handler.call(event, self)
	accept_event()


func _should_capture_event(event: InputEvent) -> bool:
	if not visible or not is_inside_tree():
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return _drag_capture or _pointer_inside or get_global_rect().has_point(button.position)
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		return _drag_capture or _pointer_inside or get_global_rect().has_point(motion.position)
	return false


func _copy_mouse_event_with_local_position(event: InputEvent) -> InputEvent:
	if event is InputEventMouseButton:
		var button_copy := (event as InputEventMouseButton).duplicate() as InputEventMouseButton
		button_copy.position = get_local_mouse_position()
		return button_copy
	if event is InputEventMouseMotion:
		var motion_copy := (event as InputEventMouseMotion).duplicate() as InputEventMouseMotion
		motion_copy.position = get_local_mouse_position()
		return motion_copy
	return event


func _update_drag_capture(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT:
		_drag_capture = button.pressed
