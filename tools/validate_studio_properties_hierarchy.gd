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

	var workspace: Node = studio.get("placement_parent")
	var data_model: Node = studio.get("data_model")
	studio._insert_roblox_instance(workspace, "Model")
	var model := _last_direct_child_of_class(workspace, "Model") as Node3D
	studio._insert_roblox_instance(model, "Part")
	var root_part := _last_direct_child_of_class(model, "Part")
	root_part.name = "Root"
	root_part.set_meta("block_name", "Root")

	var properties: Variant = studio.get("roblox_properties")
	properties.call("_on_model_primary_part_changed", "Root", model)
	properties.call("_on_model_scale_changed", 1.5, model)
	properties.call("_on_model_world_pivot_changed", Vector3(4.0, 3.0, -2.0), model)
	properties.call("_on_tags_changed", "Gameplay, Spawnable, Gameplay", model)
	properties.call("_set_node_attribute", model, "Level", 7)
	properties.call("_set_node_attribute", model, "Enabled", true)

	var model_properties: Dictionary = model.get_meta("roblox_properties", {})
	var tags: Array = model.get_meta("roblox_tags", [])
	var attributes: Dictionary = model.get_meta("roblox_attributes", {})
	var property_values_ok := (
		str(model.get_meta("PrimaryPart", "")) == "Root"
		and model.scale.is_equal_approx(Vector3.ONE * 1.5)
		and model.global_position.is_equal_approx(Vector3(4.0, 3.0, -2.0))
		and tags == ["Gameplay", "Spawnable"]
		and int(attributes.get("Level", 0)) == 7
		and bool(attributes.get("Enabled", false))
		and str(model_properties.get("PrimaryPart", "")) == "Root"
	)

	var inspector := VBoxContainer.new()
	get_root().add_child(inspector)
	properties.call("build_into", inspector, model, studio)
	await process_frame
	var property_ui_ok := (
		_find_line_edit_for_label(inspector, "PrimaryPart", "Root")
		and _find_line_edit_for_label(inspector, "Tags", "Gameplay, Spawnable")
		and _find_line_edit_for_label(inspector, "Level", "7")
	)

	studio._refresh_explorer()
	var explorer: Tree = studio.get("explorer_tree")
	var hierarchy_ok := root_part.get_parent() == model and _tree_parent_matches(explorer.get_root(), root_part.get_instance_id(), model.get_instance_id())
	properties.call("_on_node_name_changed", "GameplayModel", model)
	studio._refresh_explorer()
	hierarchy_ok = hierarchy_ok and model.name == "GameplayModel" and _tree_contains_node(explorer.get_root(), model.get_instance_id())

	var manifest: Dictionary = data_model.build_manifest()
	var manifest_entry := _find_manifest_entry(manifest, "GameplayModel")
	var manifest_properties: Dictionary = manifest_entry.get("properties", {}) if not manifest_entry.is_empty() else {}
	var manifest_ok := (
		not manifest_entry.is_empty()
		and str(manifest_properties.get("PrimaryPart", "")) == "Root"
		and (manifest_properties.get("Tags", []) as Array).size() == 2
		and int((manifest_properties.get("Attributes", {}) as Dictionary).get("Level", 0)) == 7
	)

	studio._insert_character_placeholder()
	var characters: Array[Node] = []
	for candidate in get_nodes_in_group("studio_character_models"):
		if candidate is Node:
			characters.append(candidate as Node)
	var character: Node = characters.back() if not characters.is_empty() else null
	var body_colors := character.find_child("Body Colors", true, false) if character != null else null
	var head := character.find_child("Head", true, false) as MeshInstance3D if character != null else null
	var target_color := Color("#E67E45")
	if body_colors != null:
		properties.call("_on_body_color_changed", target_color, body_colors, "HeadColor3", "Head")
	var body_color_ok := head != null and (head.get_meta("bobux_color", Color.BLACK) as Color).is_equal_approx(target_color)

	var replicated_storage: Node = data_model.ensure_service("ReplicatedStorage")
	studio._insert_roblox_instance(replicated_storage, "NumberValue")
	var number_value := _last_direct_child_of_class(replicated_storage, "NumberValue")
	properties.call("_on_meta_number_changed", 42.5, number_value, "Value")
	var value_object_ok := is_equal_approx(float((number_value.get_meta("roblox_properties", {}) as Dictionary).get("Value", 0.0)), 42.5)

	var ok := property_values_ok and property_ui_ok and hierarchy_ok and manifest_ok and body_color_ok and value_object_ok
	print("[validate_studio_properties_hierarchy] ok=%s values=%s ui=%s hierarchy=%s manifest=%s body_color=%s value_object=%s" % [
		str(ok), str(property_values_ok), str(property_ui_ok), str(hierarchy_ok), str(manifest_ok), str(body_color_ok), str(value_object_ok),
	])
	inspector.free()
	studio.free()
	quit(0 if ok else 1)


func _last_direct_child_of_class(parent: Node, roblox_class: String) -> Node:
	var result: Node = null
	for child in parent.get_children():
		if str(child.get_meta("roblox_class", "")) == roblox_class:
			result = child
	return result


func _find_line_edit_for_label(root: Node, label_text: String, expected_value: String) -> bool:
	for child in root.get_children():
		if child is HBoxContainer:
			var label: Label = null
			var edit: LineEdit = null
			for row_child in child.get_children():
				if row_child is Label:
					label = row_child as Label
				elif row_child is LineEdit:
					edit = row_child as LineEdit
				elif row_child is HBoxContainer:
					for nested in row_child.get_children():
						if nested is LineEdit:
							edit = nested as LineEdit
			if label != null and edit != null and label.text == label_text and edit.text == expected_value:
				return true
		if _find_line_edit_for_label(child, label_text, expected_value):
			return true
	return false


func _tree_parent_matches(item: TreeItem, child_id: int, expected_parent_id: int) -> bool:
	if item == null:
		return false
	var child := item.get_first_child()
	while child != null:
		if child.get_metadata(0) is int and int(child.get_metadata(0)) == child_id:
			return item.get_metadata(0) is int and int(item.get_metadata(0)) == expected_parent_id
		if _tree_parent_matches(child, child_id, expected_parent_id):
			return true
		child = child.get_next()
	return false


func _tree_contains_node(item: TreeItem, node_id: int) -> bool:
	if item == null:
		return false
	if item.get_metadata(0) is int and int(item.get_metadata(0)) == node_id:
		return true
	var child := item.get_first_child()
	while child != null:
		if _tree_contains_node(child, node_id):
			return true
		child = child.get_next()
	return false


func _find_manifest_entry(manifest: Dictionary, target_name: String) -> Dictionary:
	for section in ["instances", "tools", "gui", "scripts"]:
		var entries: Array = manifest.get(section, []) if manifest.get(section, []) is Array else []
		for entry_variant in entries:
			if entry_variant is Dictionary and str((entry_variant as Dictionary).get("name", "")) == target_name:
				return (entry_variant as Dictionary).duplicate(true)
	return {}
