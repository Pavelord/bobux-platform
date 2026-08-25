extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	var output_path := "C:\\robloxclone\\tmp_ronaldinho_playtest.png"
	var frame_count := 240
	if args.size() >= 1:
		source_path = str(args[0])
	if args.size() >= 2:
		output_path = str(args[1])
	if args.size() >= 3:
		frame_count = maxi(int(args[2]), 1)
	get_root().size = Vector2i(960, 540)
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	await studio._on_rbxl_file_selected(source_path)
	await process_frame
	await studio._start_studio_playtest()
	for _frame in range(frame_count):
		await process_frame
	var container := studio.get("viewport_container_node") as SubViewportContainer
	var subviewport := _find_subviewport(container)
	if subviewport == null:
		push_error("Studio SubViewport was not found")
		await studio._stop_studio_playtest()
		studio.queue_free()
		quit(1)
		return
	var gui_counts := {"loaded": 0, "missing": 0}
	_count_gui_images(container, gui_counts)
	# The dummy headless renderer does not emit frame_post_draw. Two process
	# frames are enough to flush SubViewport rendering in both CI and desktop.
	await process_frame
	await process_frame
	var image := subviewport.get_texture().get_image()
	var error := image.save_png(output_path)
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	var diagnostics: Dictionary = lua_engine.get_runtime_diagnostics() if lua_engine != null else {}
	print("[render_rbxl_playtest] path=%s size=%s gui_loaded=%d gui_missing=%d scripts_started=%d failed=%d error=%d" % [
		output_path,
		str(image.get_size()),
		int(gui_counts.loaded),
		int(gui_counts.missing),
		int(diagnostics.get("started", 0)),
		int(diagnostics.get("failed", 0)),
		error,
	])
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	if lua_engine != null and lua_engine.has_method("release_stopped_script_states"):
		lua_engine.release_stopped_script_states()
	await process_frame
	quit(0 if error == OK else 1)


func _find_subviewport(root: Node) -> SubViewport:
	if root == null:
		return null
	if root is SubViewport:
		return root as SubViewport
	for child in root.get_children():
		var found := _find_subviewport(child)
		if found != null:
			return found
	return null


func _count_gui_images(root: Node, counts: Dictionary) -> void:
	if root == null:
		return
	if bool(root.get_meta("bobux_image_loaded", false)):
		counts.loaded = int(counts.loaded) + 1
	if bool(root.get_meta("bobux_image_missing", false)):
		counts.missing = int(counts.missing) + 1
	for child in root.get_children():
		_count_gui_images(child, counts)
