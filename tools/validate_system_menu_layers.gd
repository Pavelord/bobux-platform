extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[system_menu] ",label_,"=",ok)
	if not ok: failures.append(label_)
func click_button(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	root.push_input(motion)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = pos
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click)
		await process_frame
func _run() -> void:
	var probe := GDScript.new()
	probe.source_code = "extends 'res://scripts/main/main.gd'\nvar reset_clicks=0\nvar leave_clicks=0\nfunc _ready():\n\t_build_runtime_hud()\n\t_ensure_runtime_inventory_controller()\nfunc _process(_delta): pass\nfunc _on_respawn_pressed(): reset_clicks+=1\nfunc _on_leave_pressed(): leave_clicks+=1\nfunc _is_dedicated_server_runtime(): return false\n"
	check(probe.reload()==OK,"main HUD harness compiles")
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(probe)
	root.add_child(main)
	current_scene = main
	main._network_loading_overlay.hide()
	# A full-screen imported GUI that used to sit above HUD layer 1.
	var imported_gui := CanvasLayer.new()
	imported_gui.layer=50
	var cover := ColorRect.new()
	cover.color=Color("#ccddeb")
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	imported_gui.add_child(cover)
	main.add_child(imported_gui)
	var inventory: Node = main._runtime_inventory_controller
	for width in [1280,480]:
		root.size=Vector2i(width,720)
		root.content_scale_size=root.size
		inventory.set_inventory_visible(true)
		main._on_game_menu_button_pressed()
		await create_timer(0.35).timeout
		var key := InputEventKey.new()
		key.keycode=KEY_QUOTELEFT
		key.pressed=true
		inventory._unhandled_input(key)
		check(not inventory.is_inventory_visible() and not inventory._root.visible,"inventory cannot cover open system menu at %d"%width)
		var rect := Rect2(Vector2.ZERO,Vector2(root.size))
		check(rect.encloses(main._respawn_button.get_global_rect()) and rect.encloses(main._menu_leave_button.get_global_rect()),"Reset and Leave stay inside screen at %d"%width)
		await click_button(main._respawn_button)
		await click_button(main._menu_leave_button)
		check(main.reset_clicks>0 and main.leave_clicks>0,"real GUI clicks reach Reset and Leave at %d"%width)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.codex-tmp/system_menu_%d.png"%width)
		main.close_game_menu()
		await create_timer(0.25).timeout
		check(inventory._root.visible,"inventory returns after menu closes")
		main.reset_clicks=0
		main.leave_clicks=0
	main.queue_free()
	await process_frame
	await process_frame
	root.get_node("LuaScriptEngine").release_stopped_script_states()
	print("[system_menu] failures=",failures)
	quit(0 if failures.is_empty() else 1)
