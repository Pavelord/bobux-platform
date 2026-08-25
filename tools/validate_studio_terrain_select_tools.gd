extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	studio._open_terrain_panel_popup()
	var terrain_editor: Variant = studio.get("roblox_terrain_editor")
	var mode_button := Button.new()
	terrain_editor.call("_select_brush_mode", "add", mode_button)
	var terrain_mode := str(studio.get("current_editor_tool")) == "terrain"
	var selected_before := studio._get_editor_parts()[0] as Node3D
	var original_position := selected_before.position
	var stroke_started := bool(terrain_editor.call("begin_stroke", Vector3(0.0, 2.0, 0.0)))
	terrain_editor.call("continue_stroke", Vector3(4.0, 2.0, 0.0))
	terrain_editor.call("end_stroke")
	var terrain: Node = null
	var workspace: Node = studio.get("placement_parent")
	for child in workspace.get_children():
		if str(child.get_meta("roblox_class", "")) == "Terrain":
			terrain = child
			break
	var terrain_props: Dictionary = terrain.get_meta("roblox_properties", {}) if terrain != null else {}
	var painted_cells: Array = terrain_props.get("Cells", []) if terrain_props.get("Cells", []) is Array else []

	studio._set_shape("Select")
	studio._set_selection([selected_before])
	studio._update_transform_gizmo()
	var gizmo_root: Node3D = studio.get("transform_gizmo_root") as Node3D
	var pure_select := (
		str(studio.get("current_editor_tool")) == "select"
		and not bool(terrain_editor.call("is_brush_active"))
		and selected_before.position.is_equal_approx(original_position)
		and (gizmo_root == null or not gizmo_root.visible)
	)
	var ok := terrain_mode and stroke_started and not painted_cells.is_empty() and pure_select
	print("[validate_studio_terrain_select_tools] ok=%s terrain_mode=%s stroke=%s cells=%d pure_select=%s" % [
		str(ok), str(terrain_mode), str(stroke_started), painted_cells.size(), str(pure_select),
	])
	studio.free()
	quit(0 if ok else 1)
