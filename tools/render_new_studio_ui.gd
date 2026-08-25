extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output_path := "C:\\robloxclone\\tmp_new_studio_ui.png"
	var render_size := Vector2i(1600, 900)
	if not args.is_empty():
		output_path = str(args[0])
	if args.size() >= 3:
		render_size = Vector2i(maxi(int(args[1]), 800), maxi(int(args[2]), 600))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(render_size)
	get_root().size = render_size
	await process_frame
	var game_state := get_root().get_node_or_null("GameState")
	if game_state != null:
		game_state.set("selected_map_folder", "")
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	print("[render_new_studio_ui] studio_added")
	await process_frame
	await process_frame
	var parts: Array = studio._get_editor_parts()
	print("[render_new_studio_ui] before_selection parts=%d" % parts.size())
	if not parts.is_empty():
		studio._set_selection([parts[0]])
	print("[render_new_studio_ui] after_selection")
	await process_frame
	print("[render_new_studio_ui] after_selection_frame")
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var error := image.save_png(output_path)
	print("[render_new_studio_ui] path=%s size=%s error=%d" % [output_path, str(image.get_size()), error])
	studio.free()
	quit(0 if error == OK else 1)
