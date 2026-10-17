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
	var data_model: Node = studio.get("data_model")

	studio._populate_script_ribbon()
	var script_action := _find_ribbon_button(studio, "Script")
	var local_action := _find_ribbon_button(studio, "Local")
	var module_action := _find_ribbon_button(studio, "Module")
	var templates_action := _find_ribbon_button(studio, "Templates")
	var ribbon_ok := script_action != null and local_action != null and module_action != null and templates_action != null
	studio._set_selection([])
	studio.explorer_selected_node = null
	studio._insert_script_class_from_ribbon("LocalScript")
	var starter_player: Node = data_model.ensure_service("StarterPlayer")
	var local_parent: Node = starter_player.get_node_or_null("StarterPlayerScripts")
	var local_script: Node = _last_script_child(local_parent, "LocalScript")
	var local_insert_ok := local_script != null and str(local_script.get_meta("code", "")).contains("LocalPlayer")
	studio._set_selection([])
	studio.explorer_selected_node = null
	studio._insert_script_class_from_ribbon("ModuleScript")
	var module_parent: Node = data_model.ensure_service("ReplicatedStorage")
	var module_script: Node = _last_script_child(module_parent, "ModuleScript")
	var module_insert_ok := module_script != null and str(module_script.get_meta("code", "")).contains("return module")
	studio._set_selection([])
	studio.explorer_selected_node = null
	studio._insert_script_from_ribbon()
	await process_frame
	var scripts: Array = data_model.find_all_of_class("Script") if data_model != null else []
	var script_node: Node = scripts.back() as Node if not scripts.is_empty() else null
	var active_tab: Control = studio._get_active_script_tab()
	var editor: CodeEdit = studio._find_code_edit(active_tab) if active_tab != null else null
	var document_button: Button = editor.get_meta("_document_button", null) as Button if editor != null else null
	var save_button := _find_button(active_tab, "Save")
	var output: RichTextLabel = studio._find_output_log(active_tab) if active_tab != null else null
	var opened_ok := script_node != null and editor != null and save_button != null and output != null
	var shortcut_router_ok := false
	if editor != null:
		for connection in editor.get_signal_connection_list("gui_input"):
			var callback: Callable = connection.get("callable", Callable())
			shortcut_router_ok = shortcut_router_ok or callback.get_method() == "_on_script_editor_gui_input"
	var rename_sync_ok := false
	if script_node != null:
		studio._rename_item_dialog(script_node)
		await process_frame
		var rename_dialog := studio.find_child("ExplorerRenameDialog", true, false) as ConfirmationDialog
		var rename_edit: LineEdit = null
		if rename_dialog != null:
			for child in rename_dialog.get_children():
				if child is LineEdit:
					rename_edit = child as LineEdit
					break
		if rename_edit != null and rename_dialog != null:
			rename_edit.text = "EditorWorkflowScript"
			rename_dialog.emit_signal("confirmed")
			await process_frame
		var renamed_tab := studio.open_scripts.get(script_node.get_instance_id(), null) as Control if script_node != null else null
		rename_sync_ok = script_node != null and script_node.name == "EditorWorkflowScript" and document_button != null and document_button.text == "EditorWorkflowScript" and is_instance_valid(renamed_tab) and renamed_tab.name == "EditorWorkflowScript"

	var valid_source := "script:SetAttribute('EditorRun', true)\nprint('studio editor test')\n"
	if editor != null:
		editor.text = valid_source
	var keyboard_save := InputEventKey.new()
	keyboard_save.keycode = KEY_S
	keyboard_save.ctrl_pressed = true
	keyboard_save.pressed = true
	if editor != null:
		editor.emit_signal("gui_input", keyboard_save)
	await process_frame
	var saved_ok := script_node != null and str(script_node.get_meta("code", "")) == valid_source
	var clean_after_save := editor != null and not bool(editor.get_meta("_script_dirty", true))
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	var valid_validation: Dictionary = lua_engine.validate_script_source(valid_source) if lua_engine != null else {}
	var valid_source_ok := bool(valid_validation.get("ok", false))

	if editor != null:
		editor.text = "local x = )\n"
	await process_frame
	var invalid_validation: Dictionary = lua_engine.validate_script_source(editor.text) if lua_engine != null and editor != null else {}
	var dirty_after_edit: bool = editor != null and studio._script_editor_has_unsaved_changes(editor)
	var dirty_marker_visible := document_button != null and document_button.text.ends_with(" *")
	if editor != null:
		studio._save_and_close_tab(editor)
	await process_frame
	var source_preserved := script_node != null and str(script_node.get_meta("code", "")) == valid_source
	var invalid_save_kept_open: bool = script_node != null and studio.open_scripts.has(script_node.get_instance_id())
	var invalid_save_kept_dirty: bool = editor != null and studio._script_editor_has_unsaved_changes(editor)
	var invalid_save_marker_visible := document_button != null and document_button.text.ends_with(" *")
	var compile_log_visible := output != null and output.get_parsed_text().contains("Compile Error")
	var invalid_rejected := not bool(invalid_validation.get("ok", true)) and source_preserved and compile_log_visible

	if editor != null:
		editor.text = valid_source
	if save_button != null:
		save_button.emit_signal("pressed")
	await process_frame
	var clean_after_repair := editor != null and not bool(editor.get_meta("_script_dirty", true))
	var repair_marker_cleared := document_button != null and not document_button.text.ends_with(" *")
	var manifest: Dictionary = data_model.build_manifest({}) if data_model != null else {}
	var manifest_saved := _manifest_contains_source(manifest, valid_source)
	var closed_after_save: bool = false
	if editor != null:
		studio._save_and_close_tab(editor)
		closed_after_save = script_node != null and not studio.open_scripts.has(script_node.get_instance_id())
	var ok: bool = ribbon_ok and local_insert_ok and module_insert_ok and opened_ok and shortcut_router_ok and rename_sync_ok and saved_ok and clean_after_save and valid_source_ok and invalid_rejected and dirty_after_edit and dirty_marker_visible and invalid_save_kept_open and invalid_save_kept_dirty and invalid_save_marker_visible and clean_after_repair and repair_marker_cleared and manifest_saved and closed_after_save
	print("[validate_studio_script_editor] ok=%s ribbon=%s local=%s module=%s opened=%s shortcuts=%s rename=%s saved=%s clean=%s valid=%s invalid_rejected=%s dirty=%s dirty_marker=%s invalid_kept_open=%s invalid_kept_dirty=%s invalid_marker=%s repair_clean=%s marker_cleared=%s manifest=%s closed=%s" % [
		str(ok), str(ribbon_ok), str(local_insert_ok), str(module_insert_ok), str(opened_ok), str(shortcut_router_ok), str(rename_sync_ok), str(saved_ok), str(clean_after_save), str(valid_source_ok), str(invalid_rejected), str(dirty_after_edit), str(dirty_marker_visible), str(invalid_save_kept_open), str(invalid_save_kept_dirty), str(invalid_save_marker_visible), str(clean_after_repair), str(repair_marker_cleared), str(manifest_saved), str(closed_after_save),
	])
	print("[validate_studio_script_editor] invalid_validation=%s source_preserved=%s compile_log=%s output=%s" % [
		str(invalid_validation), str(source_preserved), str(compile_log_visible), output.get_parsed_text() if output != null else "<none>",
	])
	if lua_engine != null and lua_engine.has_method("stop_all_scripts"):
		lua_engine.stop_all_scripts()
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _find_button(root: Node, target_text: String) -> Button:
	if root == null:
		return null
	if root is Button and (root as Button).text == target_text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, target_text)
		if found != null:
			return found
	return null


func _find_ribbon_button(root: Node, ribbon_label: String) -> Button:
	if root == null:
		return null
	if root is Button and str(root.get_meta("ribbon_label", "")) == ribbon_label:
		return root as Button
	for child in root.get_children():
		var found := _find_ribbon_button(child, ribbon_label)
		if found != null:
			return found
	return null


func _last_script_child(parent: Node, script_class: String) -> Node:
	if parent == null:
		return null
	var result: Node = null
	for child in parent.get_children():
		if child.is_in_group("bobux_scripts") and str(child.get_meta("script_type", "")) == script_class:
			result = child
	return result


func _manifest_contains_source(value: Variant, source: String) -> bool:
	if value is Dictionary:
		for nested in (value as Dictionary).values():
			if _manifest_contains_source(nested, source):
				return true
	elif value is Array:
		for nested in value as Array:
			if _manifest_contains_source(nested, source):
				return true
	elif value is String:
		return str(value) == source
	return false
