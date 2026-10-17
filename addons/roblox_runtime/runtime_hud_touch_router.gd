extends Node
## Real touches for the Bobux core buttons while the game mouse is captured.
## Kept above the game scene in the root so authored GUI input stays below it.

var buttons: Array[WeakRef] = []
var _touches: Dictionary = {}
var enabled: bool = true
var _emulated_mouse_press: bool = false

func _input(event: InputEvent) -> void:
	# Android can emit both the real touch and its synthetic mouse events. The
	# touch owns these buttons; accepting the mouse copy would toggle them twice.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_emulated_mouse_press = enabled and _button_at(event.position) != null
		if _emulated_mouse_press:
			get_viewport().set_input_as_handled()
		if not event.pressed:
			_emulated_mouse_press = false
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not enabled:
				return
			var button: BaseButton = _button_at(event.position)
			if button == null:
				return
			_touches[event.index] = {"button": weakref(button), "start": event.position, "cancelled": false}
			button.button_down.emit()
			get_viewport().set_input_as_handled()
		elif _touches.has(event.index):
			var press: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			get_viewport().set_input_as_handled()
			var button: BaseButton = (press.button as WeakRef).get_ref() as BaseButton
			if not is_instance_valid(button):
				return
			button.button_up.emit()
			if enabled and not bool(press.cancelled) and not event.canceled and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
				button.pressed.emit()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if event.position.distance_to(_touches[event.index].start) > 16.0:
			_touches[event.index].cancelled = true
		get_viewport().set_input_as_handled()

func _button_at(position: Vector2) -> BaseButton:
	for reference in buttons:
		var button: BaseButton = reference.get_ref() as BaseButton
		if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(position):
			return button
	return null
