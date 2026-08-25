extends SceneTree


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if scene == null:
		push_error("Could not load new Studio scene")
		quit(1)
		return
	var studio := scene.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var required_paths := [
		"StudioRoot",
		"StudioRoot/MenuBar",
		"StudioRoot/ToolbarContainer",
		"StudioRoot/MainSplit",
		"StudioRoot/MainSplit/ViewportColumn",
		"StudioRoot/MainSplit/ViewportColumn/DocumentTabs",
		"StudioRoot/MainSplit/ViewportColumn/ViewportContainer",
		"StudioRoot/MainSplit/RightDockSplit",
		"StudioRoot/MainSplit/RightDockSplit/ExplorerPanel",
		"StudioRoot/MainSplit/RightDockSplit/PropertiesPanel",
		"StudioRoot/StatusBar",
	]
	var missing: Array[String] = []
	for path in required_paths:
		if studio.get_node_or_null(path) == null:
			missing.append(path)

	var explorer_tree := studio.get_node_or_null("StudioRoot/MainSplit/RightDockSplit/ExplorerPanel/ExplorerTree")
	if explorer_tree == null:
		explorer_tree = _find_named_child(studio, "ExplorerTree")
	if explorer_tree == null:
		missing.append("ExplorerTree")

	var command_line := _find_named_child(studio, "CommandLine")
	if command_line == null:
		missing.append("CommandLine")
	if _find_named_child(studio, "StudioAutosaveTimer") == null:
		missing.append("StudioAutosaveTimer")
	if _find_named_child(studio, "RibbonScroll") != null:
		missing.append("RibbonScroll should not exist")
	if _find_button_with_text(studio, "Viewport") != null:
		missing.append("Extra Viewport button should not exist")

	var toolbar := studio.get_node_or_null("StudioRoot/ToolbarContainer")
	if _find_horizontal_scroll_container(toolbar) != null:
		missing.append("Toolbar horizontal ScrollContainer should not exist")
	var ribbon_tools := _find_named_child(toolbar, "RibbonTools")
	if ribbon_tools == null:
		missing.append("RibbonTools")
	else:
		var ribbon_width: float = ribbon_tools.get_combined_minimum_size().x
		var available_width: float = maxf(studio.size.x, float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)))
		if ribbon_width > available_width:
			missing.append("Ribbon exceeds viewport: %.1f > %.1f" % [ribbon_width, available_width])
	var button_text := _collect_button_text(ribbon_tools)
	for label in ["Select", "Move", "Scale", "Rotate", "Transform", "Geometric", "Part", "Terrain", "Character", "GUI", "Script", "Import", "Explorer", "Properties", "Toolbox", "Assets"]:
		if not button_text.has(label):
			missing.append("Ribbon button: " + label)
		else:
			var button := _find_button_with_text(ribbon_tools, label)
			if button == null:
				button = _find_ribbon_button_by_label(ribbon_tools, label)
			if button == null or button.get_node_or_null("RibbonButtonContent/RibbonIcon") == null:
				missing.append("Ribbon icon: " + label)

	if not missing.is_empty():
		push_error("New Studio layout missing: " + ", ".join(missing))
		quit(1)
		return

	print("New Studio layout validation OK buttons=%d" % button_text.size())
	studio.free()
	quit(0)


func _find_named_child(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_named_child(child, target_name)
		if found != null:
			return found
	return null


func _collect_button_text(root: Node) -> Dictionary:
	var result := {}
	if root == null:
		return result
	if root is Button:
		var button := root as Button
		var label := str(button.get_meta("ribbon_label", button.text))
		if not label.is_empty():
			result[label] = true
	for child in root.get_children():
		var child_result := _collect_button_text(child)
		for key in child_result.keys():
			result[key] = true
	return result


func _find_button_with_text(root: Node, text: String) -> Button:
	if root is Button and str((root as Button).text) == text:
		return root
	for child in root.get_children():
		var found := _find_button_with_text(child, text)
		if found != null:
			return found
	return null


func _find_ribbon_button_by_label(root: Node, text: String) -> Button:
	if root is Button and str((root as Button).get_meta("ribbon_label", "")) == text:
		return root
	for child in root.get_children():
		var found := _find_ribbon_button_by_label(child, text)
		if found != null:
			return found
	return null


func _find_horizontal_scroll_container(root: Node) -> ScrollContainer:
	if root == null:
		return null
	if root is ScrollContainer and (root as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return root as ScrollContainer
	for child in root.get_children():
		var found := _find_horizontal_scroll_container(child)
		if found != null:
			return found
	return null
