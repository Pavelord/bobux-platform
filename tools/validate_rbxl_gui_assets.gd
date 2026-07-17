extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	if not args.is_empty():
		source_path = str(args[0])
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
	var viewport_root := studio.get("viewport_container_node") as Node
	var gui_root := _find_named(viewport_root, "RobloxStudioGuiPreview")
	var counts := {"loaded": 0, "missing": 0, "controls": 0, "classes": {}}
	_count_gui(gui_root, counts)
	print("[validate_rbxl_gui_assets] loaded=%d missing=%d controls=%d classes=%s" % [
		int(counts.loaded), int(counts.missing), int(counts.controls), str(counts.classes),
	])
	studio.queue_free()
	await process_frame
	await process_frame
	# Some places intentionally build their active HUD from text and solid
	# buttons only. Missing assets are a failure; having no ImageLabel is not.
	quit(0 if int(counts.controls) >= 10 and int(counts.missing) == 0 else 1)


func _find_named(root: Node, expected_name: String) -> Node:
	if root == null:
		return null
	if root.name == expected_name:
		return root
	for child in root.get_children():
		var found := _find_named(child, expected_name)
		if found != null:
			return found
	return null


func _count_gui(root: Node, counts: Dictionary) -> void:
	if root == null:
		return
	var roblox_class := str(root.get_meta("roblox_class", ""))
	if root is Control and roblox_class in [
		"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton",
	]:
		counts.controls = int(counts.controls) + 1
		var classes := counts.classes as Dictionary
		classes[roblox_class] = int(classes.get(roblox_class, 0)) + 1
	if bool(root.get_meta("bobux_image_loaded", false)):
		counts.loaded = int(counts.loaded) + 1
	if bool(root.get_meta("bobux_image_missing", false)):
		counts.missing = int(counts.missing) + 1
	for child in root.get_children():
		_count_gui(child, counts)
