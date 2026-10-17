extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.canvas_cull_mask = 1
	var probe = load("res://tools/fixtures/performance_start_probe.gd").new()
	root.add_child(probe)
	var model := Node.new()
	root.add_child(model)
	var hidden := Button.new()
	hidden.name = "StartButton"
	hidden.visibility_layer = 2
	hidden.position = Vector2(30, 30)
	hidden.size = Vector2(180, 60)
	root.add_child(hidden)
	assert(hidden.is_visible_in_tree(), "DataModel visibility alone is insufficient")
	assert(not probe._is_drawn_button(hidden), "Hidden canvas cannot pass the start diagnostic")
	assert(not await probe._touch_start_button(hidden))
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var button := Button.new()
	button.name = "StartButton"
	button.position = Vector2(300, 500)
	button.size = Vector2(180, 60)
	host.add_child(button)
	var sync = load("res://addons/roblox_runtime/roblox_live_gui.gd").new()
	sync.host = host
	sync.player_gui = model
	sync.engine = root.get_node("LuaScriptEngine")
	host.add_child(sync)
	sync.set_process(false)
	button.pressed.connect(func(): button.hide())
	await process_frame
	assert(probe._is_drawn_button(button))
	assert(await probe._touch_start_button(button), "Touch closes actual drawable intro control")
	button.show()
	for callback in button.pressed.get_connections(): button.pressed.disconnect(callback.callable)
	assert(not await probe._touch_start_button(button), "An unhandled touch must never report success")
	host.free()
	hidden.free()
	model.free()
	probe.free()
	print("PERFORMANCE_START_CONTROL_OK: hidden DataModel rejected; visible routed callback closed; unhandled touch fails")
	quit(0)
