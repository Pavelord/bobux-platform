extends SceneTree

func _initialize() -> void:
	var started_msec := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\PKil(Alpha).rbxl"
	if not args.is_empty():
		source_path = str(args[0])
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var scene: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if scene == null:
		push_error("Could not load new Studio scene")
		quit(1)
		return
	var studio := scene.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	if not studio.has_method("_on_rbxl_file_selected"):
		push_error("New Studio has no RBXL import entrypoint")
		quit(1)
		return
	await studio._on_rbxl_file_selected(source_path)
	await process_frame
	var stats := _collect_import_stats(studio)
	print("[validate_new_studio_rbxl_import] parts=%d exact_meshes=%d proxy=%d unavailable=%d unmarked_missing=%d imported_scripts=%d manifest_scripts=%d grid_visible=%s elapsed_ms=%d" % [
		int(stats.get("parts", 0)),
		int(stats.get("exact_meshes", 0)),
		int(stats.get("proxy", 0)),
		int(stats.get("unavailable", 0)),
		int(stats.get("unmarked_missing", 0)),
		int(stats.get("imported_scripts", 0)),
		int(stats.get("manifest_scripts", 0)),
		str(bool(stats.get("grid_visible", false))),
		Time.get_ticks_msec() - started_msec,
	])
	# Deleted/private Roblox assets have no geometry in the RBXL itself. A tagged
	# fallback is an honest, serializable result; only an untagged missing mesh is
	# an importer regression.
	var ok := int(stats.get("parts", 0)) > 0 and int(stats.get("unmarked_missing", 0)) == 0 and not bool(stats.get("grid_visible", false))
	if int(stats.get("manifest_scripts", 0)) > 0:
		ok = ok and int(stats.get("imported_scripts", 0)) > 0
	studio.free()
	quit(0 if ok else 1)

func _collect_import_stats(studio: Node) -> Dictionary:
	var stats := {
		"parts": 0,
		"exact_meshes": 0,
		"proxy": 0,
		"unavailable": 0,
		"unmarked_missing": 0,
		"imported_scripts": 0,
		"manifest_scripts": 0,
		"grid_visible": false,
	}
	var placement_parent: Node = studio.get("placement_parent")
	if placement_parent != null:
		_collect_node_stats(placement_parent, stats)
	var data_model: Node = studio.get("data_model")
	if data_model != null:
		_collect_node_stats(data_model, stats)
	var grid_root: Node = studio.get("studio_grid_root")
	if grid_root is Node3D:
		stats["grid_visible"] = (grid_root as Node3D).visible
	if studio.get("current_roblox_place_manifest") is Dictionary:
		var manifest: Dictionary = studio.get("current_roblox_place_manifest")
		var scripts: Array = manifest.get("scripts", []) if manifest.get("scripts", []) is Array else []
		stats["manifest_scripts"] = scripts.size()
	return stats

func _collect_node_stats(root: Node, stats: Dictionary) -> void:
	if root.is_in_group("studio_parts"):
		stats["parts"] = int(stats.get("parts", 0)) + 1
	if root is MeshInstance3D:
		if bool(root.get_meta("roblox_mesh_applied", false)):
			stats["exact_meshes"] = int(stats.get("exact_meshes", 0)) + 1
		if bool(root.get_meta("roblox_proxy_geometry", false)):
			stats["proxy"] = int(stats.get("proxy", 0)) + 1
		if bool(root.get_meta("roblox_missing_exact_mesh", false)):
			if bool(root.get_meta("roblox_asset_unavailable", false)):
				stats["unavailable"] = int(stats.get("unavailable", 0)) + 1
			else:
				stats["unmarked_missing"] = int(stats.get("unmarked_missing", 0)) + 1
	if root.is_in_group("imported_roblox_scripts"):
		stats["imported_scripts"] = int(stats.get("imported_scripts", 0)) + 1
	for child in root.get_children():
		_collect_node_stats(child, stats)
