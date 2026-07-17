extends Node

signal map_loaded(map_id: String, result: Dictionary)

func load_map(map_id: String, map_name: String = "", cloud_version_id: String = "") -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	var clean_map_name: String = map_name.strip_edges()
	var clean_cloud_version_id: String = cloud_version_id.strip_edges()
	var selected_folder: String = ""
	var selected_meta: Dictionary = {}

	if GameState != null and not GameState.selected_map_folder.is_empty():
		selected_meta = _read_local_map_metadata(GameState.selected_map_folder)
		var selected_folder_name: String = GameState.selected_map_folder.get_file().strip_edges()
		var selected_cloud_map_id: String = str(selected_meta.get("cloud_map_id", selected_meta.get("map_id", ""))).strip_edges()
		var selected_display_name: String = str(selected_meta.get("name", GameState.selected_map)).strip_edges()
		var selected_cloud_version_id: String = str(selected_meta.get("cloud_version_id", "")).strip_edges()
		var matches_selected_folder: bool = false
		if FileAccess.file_exists(GameState.selected_map_folder + "/map_data.json"):
			matches_selected_folder = (
				(not clean_map_id.is_empty() and (clean_map_id == GameState.selected_map or clean_map_id == selected_folder_name or clean_map_id == selected_cloud_map_id))
				or (clean_map_id.is_empty() and not clean_map_name.is_empty() and clean_map_name == selected_display_name)
				or (not clean_cloud_version_id.is_empty() and clean_cloud_version_id == selected_cloud_version_id)
			)
		if matches_selected_folder:
			return {
				"ok": true,
				"folder": GameState.selected_map_folder,
				"cloud_version_id": clean_cloud_version_id if not clean_cloud_version_id.is_empty() else selected_cloud_version_id
			}

	var is_builtin_map: bool = clean_map_id.is_empty() or clean_map_id == "classic" or clean_map_id == "untitled"
	if not clean_map_id.is_empty() and not is_builtin_map:
		selected_folder = CloudAPI.get_cached_map_folder(clean_map_id, clean_cloud_version_id)
		if selected_folder.is_empty():
			if CloudAPI == null or not CloudAPI.is_configured():
				# Fall back to built-in map instead of failing entirely
				push_warning("[MapManager] Cloud API not configured. Falling back to built-in map.")
				is_builtin_map = true
			else:
				var download_result: Dictionary = await CloudAPI.download_map_with_cache(
					clean_map_id,
					clean_cloud_version_id,
					clean_map_name if not clean_map_name.is_empty() else "Cloud Map"
				)
				if not bool(download_result.get("ok", false)):
					# Fall back to built-in map instead of disconnecting
					push_warning("[MapManager] Cloud map download failed for '%s': %s. Falling back to built-in map." % [clean_map_id, str(download_result.get("error", "unknown"))])
					is_builtin_map = true
				else:
					selected_folder = str(download_result.get("folder", "")).strip_edges()
					if clean_cloud_version_id.is_empty():
						clean_cloud_version_id = str(download_result.get("cloud_version_id", clean_cloud_version_id)).strip_edges()

	if clean_map_name.is_empty() and not selected_folder.is_empty():
		var cached_meta: Dictionary = _read_local_map_metadata(selected_folder)
		clean_map_name = str(cached_meta.get("name", "")).strip_edges()
	if clean_map_name.is_empty() and clean_map_id.to_lower() == "classic":
		clean_map_name = "Classic"
	if clean_map_name.is_empty():
		clean_map_name = "Untitled Experience"

	GameState.selected_map = clean_map_id
	GameState.selected_map_folder = selected_folder

	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var current_scene: Node = scene_tree.current_scene if scene_tree != null else null
	if current_scene != null and current_scene.has_method("reload_runtime_map_from_game_state"):
		var reload_result: Dictionary = await current_scene.call("reload_runtime_map_from_game_state")
		if not bool(reload_result.get("ok", false)):
			map_loaded.emit(clean_map_id, reload_result)
			return reload_result

	var resolved_map_name: String = clean_map_name
	if GameState != null and GameState.has_method("get_selected_map_display_name"):
		resolved_map_name = str(GameState.get_selected_map_display_name()).strip_edges()
	if resolved_map_name.is_empty():
		resolved_map_name = clean_map_name
	var result := {
		"ok": true,
		"map_id": clean_map_id,
		"map_name": resolved_map_name,
		"cloud_version_id": clean_cloud_version_id,
		"folder": selected_folder
	}
	map_loaded.emit(clean_map_id, result)
	return result

func _read_local_map_metadata(folder_path: String) -> Dictionary:
	var meta_path: String = folder_path.path_join("meta.json")
	if not FileAccess.file_exists(meta_path):
		return {}
	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
