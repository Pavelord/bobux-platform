extends SceneTree
var _failures: Array[String] = []
var _clicks := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, detail: String) -> void:
	if not ok: _failures.append(detail)

func _touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event, true)

func _drag(position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = relative
	root.push_input(event, true)

func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(640, 480)
	var mobile: Node = root.get_node("MobileRuntime")
	mobile.set("_is_mobile_beta", true)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(surface)
	current_scene = surface
	var outer := ScrollContainer.new()
	outer.position = Vector2(20, 20)
	outer.size = Vector2(300, 230)
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	surface.add_child(outer)
	var content := Panel.new()
	content.custom_minimum_size = Vector2(280, 850)
	outer.add_child(content)
	var shelf := ScrollContainer.new()
	shelf.position = Vector2(0, 40)
	shelf.size = Vector2(270, 70)
	shelf.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(shelf)
	var shelf_content := Panel.new()
	shelf_content.custom_minimum_size = Vector2(900, 50)
	shelf.add_child(shelf_content)
	var button := Button.new()
	button.text = "Play"
	button.position = Vector2(40, 130)
	button.size = Vector2(120, 46)
	button.pressed.connect(func(): _clicks += 1)
	content.add_child(button)
	var hidden := ScrollContainer.new()
	hidden.position = Vector2(20, 20)
	hidden.size = Vector2(300, 230)
	surface.add_child(hidden)
	var hidden_content := Panel.new()
	hidden_content.custom_minimum_size = Vector2(600, 900)
	hidden.add_child(hidden_content)
	hidden.hide()
	await process_frame
	await process_frame
	_check(mobile.call("_find_scroll_container_at", surface, Vector2(50, 75)) == shelf, "horizontal shelf not detected")
	_check(mobile.call("_find_scroll_container_at", surface, Vector2(100, 190)) == outer, "visible page lost to hidden scroll")
	_check(mobile.call("_find_scroll_container_at", surface, Vector2(50, 5)) == null, "clipped child stole an outside gesture")
	mobile.set("_ui_scroll_axis", Vector2(0, 1))
	mobile.call("_apply_mobile_ui_scroll", shelf, Vector2(15, -20))
	_check(outer.scroll_vertical == 20 and shelf.scroll_horizontal == 0, "vertical shelf swipe did not reach outer page")
	for index in range(10): mobile.call("_apply_mobile_ui_scroll", outer, Vector2(0.1, -0.35))
	_check(outer.scroll_vertical >= 23 and outer.scroll_vertical <= 24, "fractional motion was rounded away")
	var before := outer.scroll_vertical
	mobile.call("_apply_mobile_ui_scroll", shelf, Vector2(-30, -2))
	_check(outer.scroll_vertical >= before + 2 and shelf.scroll_horizontal == 0, "axis changed mid-gesture")
	var modal := ColorRect.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.z_index = 100
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(modal)
	_check(mobile.call("_find_scroll_container_at", surface, Vector2(100, 190)) == null, "page scroll leaked behind a modal")
	modal.hide()
	outer.scroll_vertical = 0
	mobile.call("_finish_ui_scroll")
	await process_frame
	var point := button.get_global_rect().get_center()
	_touch(point, true)
	_mouse(point, true)
	_touch(point, false)
	_mouse(point, false)
	await process_frame
	_check(_clicks == 1 and not button.disabled, "normal touch tap was swallowed")
	point = button.get_global_rect().get_center()
	_touch(point, true)
	_mouse(point, true)
	_drag(point - Vector2(0, 25), Vector2(0, -25))
	_check(button.disabled, "swipe failed to cancel the pressed Play button")
	_touch(point - Vector2(0, 25), false)
	_mouse(point - Vector2(0, 25), false)
	await process_frame
	_check(_clicks == 1 and not button.disabled, "swipe activated Play or left it disabled")
	mobile.set("_is_mobile_beta", false)
	print("MOBILE_UI_SCROLL_RESULT=" + JSON.stringify({"ok": _failures.is_empty(), "failures": _failures, "clicks": _clicks}))
	surface.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
