extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	if not args.is_empty():
		source_path = str(args[0])
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var scene: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if scene == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := scene.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	await studio._on_rbxl_file_selected(source_path)
	await process_frame
	var counts := {}
	var examples := {}
	var refs := {}
	var data_model: Node = studio.get("data_model")
	var placement_parent: Node = studio.get("placement_parent")
	_collect(data_model, counts, examples, refs, "data_model")
	_collect(placement_parent, counts, examples, refs, "workspace")
	for key in counts.keys():
		var ref_set: Dictionary = refs.get(key, {})
		print("%s=%d unique_refs=%d example=%s" % [key, counts[key], ref_set.size(), examples.get(key, "")])
	studio.free()
	quit(0)

func _collect(node: Node, counts: Dictionary, examples: Dictionary, refs: Dictionary, path: String) -> void:
	if node == null:
		return
	var next_path := path + "/" + str(node.name)
	if node.is_in_group("imported_roblox_scripts"):
		var cls := str(node.get_meta("roblox_class", node.get_meta("script_type", "Script")))
		counts[cls] = int(counts.get(cls, 0)) + 1
		if not examples.has(cls):
			examples[cls] = next_path
		if not refs.has(cls):
			refs[cls] = {}
		var ref_set: Dictionary = refs[cls]
		ref_set[str(node.get_meta("roblox_ref", ""))] = true
	for child in node.get_children():
		_collect(child, counts, examples, refs, next_path)
