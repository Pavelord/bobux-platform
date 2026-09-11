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
	var buttons: Array[Button] = []
	_collect_ribbon_buttons(studio, buttons)
	var safe_actions := [
		"Select", "Move", "Scale", "Rotate", "Transform", "Geometric",
		"Part", "Character", "GUI", "Script", "Group", "Lock", "Anchor",
		"Explorer", "Properties", "Toolbox", "Record"
	]
	var pressed := 0
	for button in buttons:
		var label := str(button.get_meta("ribbon_label", ""))
		if not safe_actions.has(label):
			continue
		button.emit_signal("pressed")
		pressed += 1
		await process_frame
	for tab_name in ["Home", "Avatar", "UI", "Script", "Model", "Plugins", "Misc"]:
		studio._on_ribbon_tab_pressed(tab_name)
	var required_menu_ids := [
		101, 102, 103, 104, 105, 107, 108, 109,
		201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214,
		301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313,
		401, 402, 403, 404, 501, 502, 503, 504, 506, 507, 508, 601, 602, 701, 702,
	]
	var discovered_menu_ids: Array[int] = []
	_collect_menu_ids(studio, discovered_menu_ids)
	var menus_complete := true
	for required_id in required_menu_ids:
		if not discovered_menu_ids.has(required_id):
			menus_complete = false
			break
	var parts_for_properties: Array = studio._get_editor_parts()
	if not parts_for_properties.is_empty():
		studio._set_selection([parts_for_properties[0]])
		studio._on_studio_menu_action(211, "Edit")
		studio._on_studio_menu_action(213, "Edit")
	var property_actions_ok := (
		not parts_for_properties.is_empty()
		and bool(parts_for_properties[0].get_meta("locked", false))
		and bool(parts_for_properties[0].get_meta("anchored", false))
	)
	studio._on_studio_menu_action(212, "Edit")
	studio._on_studio_menu_action(214, "Edit")
	var wireframe_initial := bool(studio.get("studio_wireframe_enabled"))
	studio._on_studio_menu_action(308, "View")
	var wireframe_toggled := bool(studio.get("studio_wireframe_enabled")) != wireframe_initial
	studio._on_studio_menu_action(308, "View")
	var wireframe_restored := bool(studio.get("studio_wireframe_enabled")) == wireframe_initial
	var gui_initial := bool(studio.get("studio_gui_preview_enabled"))
	studio._on_studio_menu_action(309, "View")
	await process_frame
	var gui_toggled := bool(studio.get("studio_gui_preview_enabled")) != gui_initial
	studio._on_studio_menu_action(309, "View")
	await process_frame
	var gui_restored := bool(studio.get("studio_gui_preview_enabled")) == gui_initial
	var audio_initial := bool(studio.get("studio_audio_muted"))
	studio._on_studio_menu_action(311, "View")
	var audio_toggled := bool(studio.get("studio_audio_muted")) != audio_initial
	studio._on_studio_menu_action(311, "View")
	var audio_restored := bool(studio.get("studio_audio_muted")) == audio_initial
	studio._on_studio_menu_action(508, "Window")
	var has_insert_dialog := false
	for child in studio.get_children():
		if child is ConfirmationDialog and (child as ConfirmationDialog).title == "Insert Object":
			has_insert_dialog = true
			break
	studio._on_studio_test_control_pressed("Record")
	var data_model: Node = studio.get("data_model")
	var has_gui: bool = data_model != null and not data_model.find_all_of_class("ScreenGui").is_empty()
	var has_script: bool = data_model != null and not data_model.find_all_of_class("Script").is_empty()
	var parts: Array = studio._get_editor_parts()
	var capture_status_ok: bool = (
		studio.toolbar_status_label != null
		and "headless" in studio.toolbar_status_label.text.to_lower()
	)
	var ok: bool = (
		pressed >= 16 and has_gui and has_script and parts.size() >= 2 and capture_status_ok
		and menus_complete and property_actions_ok
		and wireframe_toggled and wireframe_restored
		and gui_toggled and gui_restored
		and audio_toggled and audio_restored and has_insert_dialog
	)
	print("[validate_new_studio_button_smoke] ok=%s pressed=%d parts=%d gui=%s script=%s menus=%s properties=%s toggles=%s" % [
		str(ok), pressed, parts.size(), str(has_gui), str(has_script), str(menus_complete),
		str(property_actions_ok), str(
			wireframe_toggled and wireframe_restored
			and gui_toggled and gui_restored
			and audio_toggled and audio_restored
		)
	])
	studio.free()
	quit(0 if ok else 1)

func _collect_ribbon_buttons(root: Node, out: Array[Button]) -> void:
	if root is Button and root.has_meta("ribbon_label"):
		out.append(root as Button)
	for child in root.get_children():
		_collect_ribbon_buttons(child, out)

func _collect_menu_ids(root: Node, out: Array[int]) -> void:
	if root is MenuButton:
		var popup := (root as MenuButton).get_popup()
		for index in range(popup.item_count):
			var item_id := popup.get_item_id(index)
			if item_id >= 0 and not out.has(item_id):
				out.append(item_id)
	for child in root.get_children():
		_collect_menu_ids(child, out)
