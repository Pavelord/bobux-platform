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

	var manifest: Dictionary = studio.get("current_roblox_place_manifest")
	var indexed: Dictionary = {}
	_index_refs(studio.get("data_model"), indexed)
	_index_refs(studio.get("placement_parent"), indexed)
	var scripts: Array = manifest.get("scripts", []) if manifest.get("scripts", []) is Array else []
	var instances: Array = manifest.get("instances", []) if manifest.get("instances", []) is Array else []
	var resolved_scripts := 0
	var exact_script_parents := 0
	var missing_script_examples: Array[String] = []
	for script_variant in scripts:
		if not (script_variant is Dictionary):
			continue
		var script := script_variant as Dictionary
		var ref := str(script.get("ref", ""))
		var parent_ref := str(script.get("parent_ref", ""))
		if not indexed.has(ref):
			if missing_script_examples.size() < 5:
				missing_script_examples.append("missing:%s/%s" % [script.get("name", "Script"), ref])
			continue
		resolved_scripts += 1
		var script_node := indexed[ref] as Node
		var actual_parent_ref := str(script_node.get_parent().get_meta("roblox_ref", "")) if script_node.get_parent() != null else ""
		if parent_ref == actual_parent_ref:
			exact_script_parents += 1
		elif missing_script_examples.size() < 8:
			missing_script_examples.append("parent:%s expected=%s(%s) actual=%s service=%s" % [
				script.get("name", "Script"), parent_ref, script.get("parent_class", ""),
				actual_parent_ref, script.get("service_name", "")
			])

	var hierarchy: Array = manifest.get("hierarchy", []) if manifest.get("hierarchy", []) is Array else []
	var comparable_edges := 0
	var exact_edges := 0
	var edge_examples: Array[String] = []
	for edge_variant in hierarchy:
		if not (edge_variant is Dictionary):
			continue
		var edge := edge_variant as Dictionary
		var child_ref := str(edge.get("child", ""))
		var parent_ref := str(edge.get("parent", ""))
		if not indexed.has(child_ref) or not indexed.has(parent_ref):
			if edge_examples.size() < 5:
				edge_examples.append("%s(%s)>%s(%s)" % [child_ref, indexed.has(child_ref), parent_ref, indexed.has(parent_ref)])
			continue
		comparable_edges += 1
		var child := indexed[child_ref] as Node
		if child.get_parent() != null and str(child.get_parent().get_meta("roblox_ref", "")) == parent_ref:
			exact_edges += 1

	var visible_templates := 0
	for entry_variant in instances:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var properties: Dictionary = entry.get("properties", {}) if entry.get("properties", {}) is Dictionary else {}
		if not bool(properties.get("BobuxTemplateOnly", false)):
			continue
		var ref := str(entry.get("ref", ""))
		if indexed.has(ref) and indexed[ref] is Node3D and (indexed[ref] as Node3D).visible:
			visible_templates += 1

	print("[validate_rbxl_data_model_hierarchy] scripts=%d resolved=%d exact_parents=%d instances=%d edges=%d/%d(raw=%d) visible_templates=%d examples=%s edge_examples=%s" % [
		scripts.size(), resolved_scripts, exact_script_parents, instances.size(), exact_edges,
		comparable_edges, hierarchy.size(), visible_templates, str(missing_script_examples), str(edge_examples)
	])
	var ok := scripts.size() == resolved_scripts and scripts.size() == exact_script_parents
	ok = ok and visible_templates == 0
	studio.free()
	quit(0 if ok else 1)

func _index_refs(root: Node, out: Dictionary) -> void:
	if root == null:
		return
	var ref := str(root.get_meta("roblox_ref", "")).strip_edges()
	if not ref.is_empty():
		out[ref] = root
	for child in root.get_children():
		_index_refs(child, out)
