extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[studio_script_editor] Could not load the Studio scene")
		quit(2)
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame

	var placement: Node = studio.get("placement_parent")
	var probe := Node.new()
	probe.name = "EditorLayoutProbe"
	probe.set_meta("roblox_class", "Script")
	probe.set_meta("script_type", "Script")
	probe.set_meta("code", "local part = script.Parent\nprint(part.Name)")
	placement.add_child(probe)
	studio.call("_open_script_in_editor", probe)
	await process_frame
	await process_frame

	var main_split := studio.find_child("MainSplit", true, false) as HSplitContainer
	var work_split := studio.find_child("WorkspaceAndDocksSplit", true, false) as HSplitContainer
	var dock_split := studio.find_child("RightDockSplit", true, false) as VSplitContainer
	var editor_output := studio.find_child("EditorOutputSplit", true, false) as VSplitContainer
	var code_edit := editor_output.get_child(0) as CodeEdit if editor_output != null and editor_output.get_child_count() > 0 else null
	var output_panel := editor_output.get_child(1) as Control if editor_output != null and editor_output.get_child_count() > 1 else null
	var viewport_panel := studio.get("viewport_frame_panel") as Control
	var script_tabs := studio.get("script_editor_tabs") as Control
	var font_path := code_edit.get_theme_font("font").resource_path if code_edit != null else ""
	var pop_out_button := script_tabs.get_child(0).find_child("FloatScriptEditorButton", true, false) as Button if script_tabs != null and script_tabs.get_child_count() > 0 else null
	var material_completion_count := 0
	if code_edit != null:
		code_edit.text = "Enum.Material."
		code_edit.set_caret_column(code_edit.get_line(0).length())
		studio.call("_on_lua_code_completion_requested", code_edit)
		material_completion_count = code_edit.get_code_completion_options().size()
		studio.call("_on_lua_code_completion_requested", code_edit)
		material_completion_count = mini(material_completion_count, code_edit.get_code_completion_options().size())
	var library_entries: Array[Dictionary] = preload("res://addons/roblox_studio/studio_script_library.gd").entries()
	var has_terrain_example := false
	var has_sound_example := false
	for entry in library_entries:
		has_terrain_example = has_terrain_example or str(entry.title).begins_with("Terrain ·")
		has_sound_example = has_sound_example or str(entry.title).begins_with("Звук ·")
	var ok := main_split != null and work_split != null and dock_split != null and editor_output != null
	ok = ok and code_edit != null and viewport_panel != null and not viewport_panel.visible
	ok = ok and script_tabs != null and script_tabs.visible
	ok = ok and editor_output.get_child_count() == 2 and code_edit.get_theme_color("background_color") == Color("#FFFFFF")
	ok = ok and output_panel != null and output_panel.custom_minimum_size.y >= 120
	ok = ok and code_edit.custom_minimum_size.y >= 220 and code_edit.minimap_draw
	ok = ok and material_completion_count >= 30 and has_terrain_example and has_sound_example
	ok = ok and studio.find_child("PropertiesPanel", true, false) != null
	ok = ok and font_path.ends_with("CascadiaMono.ttf") and pop_out_button != null
	var main_splitter := main_split.dragger_visibility == SplitContainer.DRAGGER_VISIBLE if main_split != null else false
	var output_splitter := editor_output.dragger_visibility == SplitContainer.DRAGGER_VISIBLE if editor_output != null else false
	ok = ok and main_splitter and output_splitter
	studio.call("_float_script_editor_window")
	var float_window := studio.get("script_editor_window") as Window
	var float_content := studio.get("script_editor_window_content") as Control
	var detached := float_window != null and float_content != null and script_tabs.get_parent() == float_content
	var resizable_window := detached and not float_window.unresizable and float_window.min_size.x >= 700 and float_window.min_size.y >= 480
	ok = ok and detached and resizable_window and viewport_panel.visible
	studio.call("_dock_script_editor_window")
	var docked: bool = script_tabs.get_parent() == studio.get("script_editor_home") and not viewport_panel.visible
	ok = ok and docked
	print("[studio_script_editor] diagnostics font=", font_path, " pop_out=", pop_out_button != null,
		" main_splitter=", main_splitter, " output_splitter=", output_splitter,
		" detached=", detached, " resizable=", resizable_window, " docked=", docked)
	print("[studio_script_editor] ok=", ok,
		" main_split=", main_split != null,
		" workspace_split=", work_split != null,
		" dock_split=", dock_split != null,
		" editor_output_split=", editor_output != null,
		" material_completions=", material_completion_count,
		" terrain_example=", has_terrain_example,
		" sound_example=", has_sound_example,
		" viewport_hidden=", viewport_panel != null and not viewport_panel.visible,
		" code_size=", code_edit.size if code_edit != null else Vector2.ZERO)
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
