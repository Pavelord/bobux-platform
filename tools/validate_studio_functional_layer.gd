extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	studio._on_ribbon_tab_pressed("Avatar")
	studio._insert_character_placeholder()
	await process_frame
	var workspace: Node = studio.get("placement_parent")
	var characters := workspace.get_tree().get_nodes_in_group("studio_character_models")
	var character: Node = characters.back() if not characters.is_empty() else null
	var character_ok := character != null and character.find_child("Humanoid", true, false) != null
	character_ok = character_ok and character.find_child("Head", true, false) != null

	studio._open_terrain_panel_popup()
	var terrain_editor: Variant = studio.get("roblox_terrain_editor")
	if terrain_editor != null:
		terrain_editor.call("_apply_brush", "fill")
	var terrain: Node = null
	for child in workspace.get_children():
		if str(child.get_meta("roblox_class", "")) == "Terrain":
			terrain = child
			break
	var terrain_properties: Dictionary = terrain.get_meta("roblox_properties", {}) if terrain != null else {}
	var terrain_ok := terrain != null and (terrain_properties.get("Cells", []) as Array).size() > 0

	studio._on_ribbon_tab_pressed("UI")
	studio._insert_gui_instance("Frame")
	studio._insert_gui_instance("TextButton")
	var data_model: Node = studio.get("data_model")
	var gui_ok: bool = data_model.find_all_of_class("ScreenGui").size() == 1
	gui_ok = gui_ok and data_model.find_all_of_class("Frame").size() >= 1
	gui_ok = gui_ok and data_model.find_all_of_class("TextButton").size() >= 1

	studio._on_ribbon_tab_pressed("Script")
	studio._insert_script_from_ribbon()
	await process_frame
	var scripts: Array = data_model.find_all_of_class("Script")
	var script_ok := not scripts.is_empty() and str(scripts[0].get_meta("code", "")).contains("print")
	studio._execute_command_bar("print('functional studio command')")

	studio._on_ribbon_tab_pressed("Model")
	studio._add_shape_to_node(workspace, "WedgePart")
	studio._add_shape_to_node(workspace, "Part")
	var parts: Array = studio._get_editor_parts()
	var part_a: MeshInstance3D = parts[parts.size() - 2]
	var part_b: MeshInstance3D = parts[parts.size() - 1]
	studio._set_selection([part_a, part_b])
	studio._group_selected_blocks()
	var grouped_ok := part_a.get_parent() == part_b.get_parent()
	grouped_ok = grouped_ok and str(part_a.get_parent().get_meta("roblox_class", "")) == "Model"

	var properties: Variant = studio.get("roblox_properties")
	properties.call("_on_part_color_changed", Color("#E33A38"), part_a)
	properties.call("_on_part_shape_changed", "Sphere", part_a)
	var color: Color = part_a.get_meta("bobux_color", Color.BLACK)
	var properties_ok := color.is_equal_approx(Color("#E33A38")) and part_a.mesh is SphereMesh

	var explorer: Tree = studio.get("explorer_tree")
	studio._refresh_explorer()
	var explorer_ok := _tree_has_node_without_class_suffix(explorer.get_root(), part_a.get_instance_id())
	var tool_ok := str(studio.get("current_editor_tool")) == "select"
	studio._set_transform_mode("move")
	tool_ok = tool_ok and str(studio.get("current_editor_tool")) == "move" and str(studio.get("current_shape")) == "Select"

	var ok: bool = character_ok and terrain_ok and gui_ok and script_ok and grouped_ok and properties_ok and explorer_ok and tool_ok
	print("[validate_studio_functional_layer] ok=%s character=%s terrain=%s gui=%s script=%s group=%s properties=%s explorer=%s tools=%s" % [
		str(ok), str(character_ok), str(terrain_ok), str(gui_ok), str(script_ok),
		str(grouped_ok), str(properties_ok), str(explorer_ok), str(tool_ok),
	])
	studio.free()
	quit(0 if ok else 1)


func _tree_has_node_without_class_suffix(item: TreeItem, node_id: int) -> bool:
	if item == null:
		return false
	var cursor := item.get_first_child()
	while cursor != null:
		if int(cursor.get_metadata(0)) == node_id:
			return not cursor.get_text(0).contains("[")
		if _tree_has_node_without_class_suffix(cursor, node_id):
			return true
		cursor = cursor.get_next()
	return false
