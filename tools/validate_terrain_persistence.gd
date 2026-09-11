extends SceneTree


func _initialize() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[validate_terrain_persistence] Studio scene is missing")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	studio._open_terrain_panel_popup()
	var terrain_editor: Variant = studio.get("roblox_terrain_editor")
	terrain_editor.call("_apply_brush", "fill")
	var workspace := studio.get("placement_parent") as Node3D
	var before := _terrain_cell_count(workspace)
	var folder := "user://validation/terrain_persistence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await studio._save_map(folder)

	var serialized_cells := _serialized_terrain_cell_count(folder + "/map_data.json")
	studio._clear_authored_terrain_for_load()
	await process_frame
	await studio._load_map_from_folder(folder)
	await process_frame
	await process_frame
	var after := _terrain_cell_count(workspace)
	var grid := _find_terrain_grid(workspace)
	var collision_ok := grid != null and grid.collision_layer == 1
	var ok := before > 0 and serialized_cells == before and after == before and collision_ok
	print("[validate_terrain_persistence] ok=%s before=%d serialized=%d restored=%d collision=%s" % [
		str(ok), before, serialized_cells, after, str(collision_ok),
	])
	studio.queue_free()
	await process_frame
	_cleanup(folder)
	quit(0 if ok else 1)


func _find_terrain_grid(workspace: Node) -> GridMap:
	if workspace == null:
		return null
	for child in workspace.get_children():
		if str(child.get_meta("roblox_class", "")) == "Terrain":
			return child.get_node_or_null("EditableTerrainGrid") as GridMap
	return null


func _terrain_cell_count(workspace: Node) -> int:
	var grid := _find_terrain_grid(workspace)
	return grid.get_used_cells().size() if grid != null else 0


func _serialized_terrain_cell_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return -1
	var manifest: Variant = (parsed as Dictionary).get("roblox_manifest", {})
	if not (manifest is Dictionary):
		return -1
	var entries: Variant = (manifest as Dictionary).get("instances", [])
	if not (entries is Array):
		return -1
	var serialized_classes: Array[String] = []
	for entry in entries:
		if entry is Dictionary:
			serialized_classes.append(str((entry as Dictionary).get("class", "")))
		if entry is Dictionary and str((entry as Dictionary).get("class", "")) == "Terrain":
			var properties: Variant = (entry as Dictionary).get("properties", {})
			if properties is Dictionary and (properties as Dictionary).get("Cells", []) is Array:
				return ((properties as Dictionary).get("Cells", []) as Array).size()
	print("[validate_terrain_persistence] terrain missing from manifest; classes=%s" % [str(serialized_classes)])
	return -1


func _cleanup(folder: String) -> void:
	var absolute := ProjectSettings.globalize_path(folder)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	dir = null
	DirAccess.remove_absolute(absolute)
