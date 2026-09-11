extends RefCounted

class InputObject extends RefCounted:
	var values: Dictionary
	func _init(data: Dictionary) -> void:
		values = data
	func _get(property: StringName) -> Variant:
		return values.get(str(property))

static func key_codes() -> Dictionary:
	var keys := {"Unknown": 0, "Backspace": 8, "Tab": 9, "Return": 13, "Escape": 27, "Space": 32,
		"LeftShift": 304, "RightShift": 303, "LeftControl": 306, "RightControl": 305,
		"LeftAlt": 308, "RightAlt": 307, "Up": 273, "Down": 274, "Right": 275, "Left": 276,
		"Insert": 277, "Home": 278, "End": 279, "PageUp": 280, "PageDown": 281, "Delete": 127}
	for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		keys[letter] = letter.to_lower().unicode_at(0)
	var digits := ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
	for index in range(digits.size()): keys[digits[index]] = 48 + index
	for index in range(1, 13): keys["F%d" % index] = 281 + index
	return keys

static func key_code(event: InputEventKey) -> int:
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code >= KEY_A and code <= KEY_Z: return code + 32
	if code >= KEY_F1 and code <= KEY_F12: return 282 + code - KEY_F1
	if code >= 32 and code <= 126: return code
	var right := event.location == KEY_LOCATION_RIGHT
	return int({KEY_SHIFT: 303 if right else 304, KEY_CTRL: 305 if right else 306, KEY_ALT: 307 if right else 308,
		KEY_BACKSPACE: 8, KEY_TAB: 9, KEY_ENTER: 13, KEY_ESCAPE: 27, KEY_DELETE: 127,
		KEY_UP: 273, KEY_DOWN: 274, KEY_RIGHT: 275, KEY_LEFT: 276,
		KEY_INSERT: 277, KEY_HOME: 278, KEY_END: 279, KEY_PAGEUP: 280, KEY_PAGEDOWN: 281}.get(code, 0))

static func event_data(event: InputEvent) -> Dictionary:
	var data := {"KeyCode": 0, "Position": Vector3.ZERO, "Delta": Vector3.ZERO, "UserInputState": 1}
	if event is InputEventKey:
		if event.echo: return {}
		data.KeyCode = key_code(event)
		data.UserInputType = 8
		data.UserInputState = 0 if event.pressed else 2
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if not event.pressed: return {}
			data.UserInputType = 3
			data.Position.z = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		else:
			var buttons := {MOUSE_BUTTON_LEFT: 0, MOUSE_BUTTON_RIGHT: 1, MOUSE_BUTTON_MIDDLE: 2}
			if not buttons.has(event.button_index): return {}
			data.UserInputType = buttons[event.button_index]
			data.UserInputState = 0 if event.pressed else 2
		data.Position.x = event.position.x
		data.Position.y = event.position.y
	elif event is InputEventMouseMotion:
		data.UserInputType = 4
		data.Position = Vector3(event.position.x, event.position.y, 0)
		data.Delta = Vector3(event.relative.x, event.relative.y, 0)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		data.UserInputType = 7
		data.Position = Vector3(event.position.x, event.position.y, 0)
		if event is InputEventScreenTouch:
			data.UserInputState = 0 if event.pressed else 2
		else:
			data.Delta = Vector3(event.relative.x, event.relative.y, 0)
	else:
		return {}
	return data
