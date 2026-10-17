extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var data_model := Node.new()
	root.add_child(data_model)
	var data := Label.new()
	data.name = "Counter"
	data.set_meta("roblox_class", "TextLabel")
	data.set_meta("roblox_ref", "counter")
	data.set_meta("roblox_properties", {"TextSize": 18, "TextWrapped": true, "BorderSizePixel": 0,
		"Size": {"x": {"offset": 236}, "y": {"offset": 24}}})
	data.text = "Feathers: 30 / 30"
	data_model.add_child(data)
	var host := Control.new()
	host.size = Vector2(683,384)
	host.set_meta("bobux_gui_runtime_options", {"fit_to_viewport": true, "design_size": [1366,768]})
	root.add_child(host)
	var sync: Node = load("res://addons/roblox_runtime/roblox_live_gui.gd").new()
	sync.engine = root.get_node("LuaScriptEngine")
	sync.host = host
	sync.player_gui = data_model
	host.add_child(sync)
	await process_frame
	var view: Label = sync._views.counter
	assert(view.get_theme_font_size("font_size") == 9)
	assert(is_equal_approx(view.size.x, 118))
	var wrapper = root.get_node("LuaScriptEngine").BobuxInstance.new(data)
	assert(wrapper._get(&"AbsoluteSize") == view.get_global_rect().size, "AbsoluteSize must use fitted live GUI")
	assert(wrapper._get(&"AbsolutePosition") == view.get_global_rect().position)
	assert(view.get_theme_stylebox("normal").get_content_margin(SIDE_TOP) == 0)
	sync.sync_now()
	assert(view.get_theme_font_size("font_size") == 9, "Live updates must retain viewport scaling")
	host.size = Vector2(1366,768)
	sync.sync_now()
	await process_frame
	assert(view.get_theme_font_size("font_size") == 18)
	assert(is_equal_approx(view.size.x,236))
	assert(wrapper._get(&"AbsoluteSize") == view.get_global_rect().size)
	print("[live-gui-scaling] PASS viewport resize, font scale, HUD padding")
	quit(0)
