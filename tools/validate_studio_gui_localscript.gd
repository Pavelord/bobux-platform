extends SceneTree

const RobloxDataModel := preload("res://addons/roblox_studio/roblox_data_model.gd")


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var data_model: Node = studio.get("data_model")
	var starter_gui: Node = data_model.call("ensure_service", "StarterGui")
	var screen := RobloxDataModel.create_instance("ScreenGui", "TestGui")
	screen.set_meta("roblox_ref", "test_screen")
	starter_gui.add_child(screen, true)
	var button := RobloxDataModel.create_instance("TextButton", "ActionButton") as Button
	button.set_meta("roblox_ref", "test_button")
	button.text = "Action"
	button.position = Vector2(80, 80)
	button.size = Vector2(240, 64)
	button.set_meta("roblox_properties", {
		"Text": "Action", "Visible": true, "Enabled": true,
		"Position": [0.0, 80.0, 0.0, 80.0],
		"Size": [0.0, 240.0, 0.0, 64.0],
	})
	screen.add_child(button, true)
	var local_script := RobloxDataModel.create_instance("LocalScript", "ButtonClient")
	local_script.set_meta("roblox_ref", "test_script")
	local_script.set_meta("code", "local button = script.Parent\nbutton.Activated:Connect(function()\n    button.Text = 'Clicked'\nend)\n")
	local_script.set_meta("lua_source", local_script.get_meta("code"))
	local_script.set_meta("disabled", false)
	button.add_child(local_script, true)
	studio._on_data_model_gui_changed()
	var manifest_before: Dictionary = studio.get("current_roblox_place_manifest")
	await studio._start_studio_playtest()
	await process_frame
	var runtime_roots: Array[String] = []
	_collect_runtime_roots(studio.get("viewport_container_node"), runtime_roots)
	var gui_preview := _find_runtime_gui(studio.get("viewport_container_node"))
	var runtime_button := _find_by_ref(gui_preview, "test_button") as Button
	var runtime_found := runtime_button != null
	var bound_target_path := str(runtime_button.get_meta("bobux_bound_target_path", "")) if runtime_button != null else ""
	var bind_report: Dictionary = gui_preview.get_meta("bobux_gui_bind_report", {}) if gui_preview != null and gui_preview.get_meta("bobux_gui_bind_report", {}) is Dictionary else {}
	var local_player := data_model.get_node_or_null("Players/LocalPlayer")
	var live_tree: Array[String] = []
	_collect_node_tree(local_player.get_node_or_null("PlayerGui") if local_player != null else null, live_tree)
	var live_button_before := _find_by_ref(local_player.get_node_or_null("PlayerGui") if local_player != null else null, "test_button") as Button
	var live_script := _find_by_ref(local_player.get_node_or_null("PlayerGui") if local_player != null else null, "test_script")
	var registry: Dictionary = live_button_before.get_meta("_bobux_event_registry", {}) if live_button_before != null and live_button_before.get_meta("_bobux_event_registry", {}) is Dictionary else {}
	var activated_event: Variant = registry.get("Activated", null)
	var activated_connections := int(((activated_event as Object).get("connections") as Array).size()) if activated_event is Object else -1
	var diagnostics: Dictionary = get_root().get_node("LuaScriptEngine").call("get_runtime_diagnostics")
	var source_screen_after := starter_gui.get_node_or_null("TestGui")
	var source_button_after := source_screen_after.get_node_or_null("ActionButton") if source_screen_after != null else null
	var source_refs := "%s/%s path=%s" % [
		str(source_screen_after.get_meta("roblox_ref", "")) if source_screen_after != null else "-",
		str(source_button_after.get_meta("roblox_ref", "")) if source_button_after != null else "-",
		str(starter_gui.get_path()),
	]
	if runtime_button != null:
		runtime_button.pressed.emit()
	await process_frame
	await process_frame
	var live_button := _find_by_ref(local_player.get_node_or_null("PlayerGui") if local_player != null else null, "test_button") as Button
	var live_changed := live_button != null and live_button.text == "Clicked"
	var visual_changed := runtime_button != null and runtime_button.text == "Clicked"
	await studio._stop_studio_playtest()
	await process_frame
	var ok := runtime_found and live_changed and visual_changed
	print("[validate_studio_gui_localscript] ok=%s runtime=%s live=%s visual=%s target=%s bind=%s player=%s script=%s connections=%d gui_entries=%d source=%s live_tree=%s roots=%s diagnostics=%s" % [str(ok), str(runtime_found), str(live_changed), str(visual_changed), bound_target_path, str(bind_report), str(local_player != null), str(live_script != null), activated_connections, int((manifest_before.get("gui", []) as Array).size()), source_refs, str(live_tree), str(runtime_roots), str(diagnostics)])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _find_by_ref(root: Node, expected_ref: String) -> Node:
	if root == null:
		return null
	if str(root.get_meta("roblox_ref", "")) == expected_ref:
		return root
	for child in root.get_children():
		var found := _find_by_ref(child, expected_ref)
		if found != null:
			return found
	return null


func _find_runtime_gui(root: Node) -> Node:
	if root == null:
		return null
	if root.is_in_group("roblox_gui_runtime") and root.has_meta("built_gui_controls"):
		return root
	for child in root.get_children():
		var found := _find_runtime_gui(child)
		if found != null:
			return found
	return null


func _collect_runtime_roots(root: Node, output: Array[String]) -> void:
	if root == null:
		return
	if str(root.name).find("Roblox") >= 0 or root.is_in_group("roblox_gui_runtime"):
		output.append("%s type=%s ref=%s class=%s group=%s controls=%s" % [str(root.get_path()), root.get_class(), str(root.get_meta("roblox_ref", "")), str(root.get_meta("roblox_class", "")), str(root.is_in_group("roblox_gui_runtime")), str(root.get_meta("built_gui_controls", "-"))])
	for child in root.get_children():
		_collect_runtime_roots(child, output)


func _collect_node_tree(root: Node, output: Array[String]) -> void:
	if root == null:
		return
	output.append("%s ref=%s class=%s generated=%s" % [
		str(root.name),
		str(root.get_meta("roblox_ref", "")),
		str(root.get_meta("roblox_class", "")),
		str(root.get_meta("bobux_runtime_generated", false)),
	])
	for child in root.get_children():
		_collect_node_tree(child, output)
