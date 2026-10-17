extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var source := Node.new()
	root.add_child(source)
	var label := Label.new()
	label.text = "Clock 1"
	label.set_meta("roblox_class", "TextLabel")
	label.set_meta("roblox_ref", "clock")
	label.set_meta("roblox_properties", {"Text": "Clock 1", "TextSize": 18, "Size": {"x": {"offset": 200}, "y": {"offset": 40}}, "BackgroundColor3": [0.3,0.4,0.5]})
	source.add_child(label)
	var corner := Node.new()
	corner.set_meta("roblox_class", "UICorner")
	corner.set_meta("roblox_properties", {"CornerRadius": {"scale": 0, "offset": 6}})
	label.add_child(corner)
	var host := Control.new()
	host.size = Vector2(1280,720)
	root.add_child(host)
	var sync: Node = load("res://addons/roblox_runtime/roblox_live_gui.gd").new()
	sync.engine = root.get_node("LuaScriptEngine")
	sync.host = host
	sync.player_gui = source
	host.add_child(sync)
	await process_frame
	sync.sync_now()
	var view: Label = sync._views.clock
	var style := view.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style.corner_radius_top_left == 6)
	sync.sync_now()
	assert(style == view.get_theme_stylebox("normal"), "Unchanged decorator must retain its StyleBox")
	var props: Dictionary = label.get_meta("roblox_properties").duplicate()
	props.Text = "Clock 2"
	label.text = props.Text
	label.set_meta("roblox_properties", props)
	sync.sync_now()
	assert(view.text == "Clock 2" and style == view.get_theme_stylebox("normal"), "Text must update without rebuilding style")
	corner.set_meta("roblox_properties", {"CornerRadius": {"scale": 0, "offset": 12}})
	sync.sync_now()
	style = view.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style.corner_radius_top_left == 12)
	props.BackgroundColor3 = [0.8,0.2,0.1]
	label.set_meta("roblox_properties", props)
	sync.sync_now()
	style = view.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style.corner_radius_top_left == 12 and style.bg_color.is_equal_approx(Color(0.8,0.2,0.1)), "Base style changes must reapply decorators")
	corner.queue_free()
	await process_frame
	sync.sync_now()
	assert(sync._decorator_styles.is_empty(), "Removed decorators must leave the cache")
	print("[gui-style-cache] PASS stable style, text update, decorator edit, base colour, removal")
	quit()
