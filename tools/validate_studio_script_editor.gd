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

	studio._insert_script_from_ribbon()
	await process_frame
	var data_model: Node = studio.get("data_model")
	var scripts: Array = data_model.find_all_of_class("Script") if data_model != null else []
	var script_node: Node = scripts.back() as Node if not scripts.is_empty() else null
	var active_tab: Control = studio._get_active_script_tab()
	var editor: CodeEdit = studio._find_code_edit(active_tab) if active_tab != null else null
	var save_button := _find_button(active_tab, "Save")
	var run_button := _find_button(active_tab, "Run")
	var output: RichTextLabel = studio._find_output_log(active_tab) if active_tab != null else null
	var opened_ok := script_node != null and editor != null and save_button != null and run_button != null and output != null

	var valid_source := "script:SetAttribute('EditorRun', true)\nprint('studio editor test')\n"
	if editor != null:
		editor.text = valid_source
	if save_button != null:
		save_button.emit_signal("pressed")
	await process_frame
	var saved_ok := script_node != null and str(script_node.get_meta("code", "")) == valid_source
	if run_button != null:
		run_button.emit_signal("pressed")
	for _frame in range(5):
		await process_frame
	var run_ok := script_node != null and bool(script_node.get_meta("attribute_EditorRun", false))

	if editor != null:
		editor.text = "if then end\n"
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	var invalid_validation: Dictionary = lua_engine.validate_script_source(editor.text) if lua_engine != null and editor != null else {}
	if save_button != null:
		save_button.emit_signal("pressed")
	await process_frame
	var source_preserved := script_node != null and str(script_node.get_meta("code", "")) == valid_source
	var compile_log_visible := output != null and output.get_parsed_text().contains("Compile Error")
	var invalid_rejected := not bool(invalid_validation.get("ok", true)) and source_preserved and compile_log_visible

	var manifest: Dictionary = data_model.build_manifest({}) if data_model != null else {}
	var manifest_saved := _manifest_contains_source(manifest, valid_source)
	var ok := opened_ok and saved_ok and run_ok and invalid_rejected and manifest_saved
	print("[validate_studio_script_editor] ok=%s opened=%s saved=%s run=%s invalid_rejected=%s manifest=%s" % [
		str(ok), str(opened_ok), str(saved_ok), str(run_ok), str(invalid_rejected), str(manifest_saved),
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
