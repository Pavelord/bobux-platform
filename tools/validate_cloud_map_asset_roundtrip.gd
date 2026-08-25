extends SceneTree

var _cloud: Node = null
var _session: Node = null
var _map_id := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cloud = root.get_node_or_null("CloudAPI")
	_session = root.get_node_or_null("UserSession")
	if _cloud == null or _session == null:
		_finish(false, "required autoloads are missing")
		return
	var username := str(_session.get("username")).strip_edges()
	if username.is_empty():
		username = str(_cloud.call("get_current_username")).strip_edges()
	var auth_result: Dictionary = await _cloud.call("authenticate_or_create_profile", username)
	if not bool(auth_result.get("ok", false)):
		_finish(false, "authentication failed: %s" % str(auth_result.get("error", "unknown")))
		return

	var suffix := str(Time.get_ticks_msec())
	var map_name := "__asset_roundtrip_contract_%s" % suffix
	var initial_result: Dictionary = await _cloud.call("upload_map_to_cloud", {"blocks": [], "probe": suffix}, map_name, {
		"owner_name": username,
		"description": "Automated Studio asset package roundtrip probe",
		"is_published": false,
	})
	_map_id = _extract_id(initial_result.get("data", {}))
	if not bool(initial_result.get("ok", false)) or _map_id.is_empty():
		_finish(false, "initial map upload failed: %s" % str(initial_result.get("error", "unknown")))
		return

	var folder := "user://validation/cloud_map_asset_roundtrip_%s" % suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("textures")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("meshes")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("scripts")))
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.72, 0.34, 1.0))
	if image.save_png(folder.path_join("textures/probe.png")) != OK:
		await _cleanup()
		_finish(false, "could not create PNG probe")
		return
	_write_text(folder.path_join("meshes/probe.mesh.json"), "{\"surfaces\":[],\"probe\":true}")
	_write_text(folder.path_join("scripts/probe.lua"), "return { probe = true }")

	var studio_scene := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if studio_scene == null:
		await _cleanup()
		_finish(false, "Studio scene could not be loaded")
		return
	var studio := studio_scene.instantiate() as Control
	root.add_child(studio)
	var payload := {
		"blocks": [{"name": "AssetProbe", "roblox_mesh_json_asset": "meshes/probe.mesh.json", "roblox_texture_asset_file": "textures/probe.png"}],
		"runtime_objects": [],
		"mode_settings": {},
		"roblox_manifest": {"instances": [{"class": "ModuleScript", "source_file": "scripts/probe.lua"}]},
	}
	var packaged: Dictionary = await studio.call("_embed_mode_assets_for_cloud", payload, folder, _map_id)
	var failures: Array = packaged.get("__bobux_publish_asset_failures", []) if packaged.get("__bobux_publish_asset_failures", []) is Array else []
	packaged.erase("__bobux_publish_asset_failures")
	var urls: Dictionary = packaged.get("mode_asset_urls", {}) if packaged.get("mode_asset_urls", {}) is Dictionary else {}
	if not failures.is_empty() or not urls.has("textures/probe.png") or not urls.has("meshes/probe.mesh.json") or not urls.has("scripts/probe.lua"):
		studio.queue_free()
		await process_frame
		await _cleanup()
		_finish(false, "Studio package is incomplete: failures=%s urls=%s" % [str(failures), str(urls.keys())])
		return

	var publish_result: Dictionary = await _cloud.call("upload_map_to_cloud", packaged, map_name, {
		"owner_name": username,
		"cloud_map_id": _map_id,
		"description": "Automated Studio asset package roundtrip probe",
		"is_published": false,
	})
	if not bool(publish_result.get("ok", false)):
		studio.queue_free()
		await process_frame
		await _cleanup()
		_finish(false, "final map upload failed: %s" % str(publish_result.get("error", "unknown")))
		return
	var record := _extract_record(publish_result.get("data", {}))
	var version := str(record.get("cloud_version_id", record.get("version_id", record.get("updated_at", "")))).strip_edges()
	var cache_result: Dictionary = await _cloud.call("download_map_with_cache", _map_id, version, map_name)
	var cached_folder := str(cache_result.get("folder", ""))
	var prefetch: Dictionary = cache_result.get("asset_prefetch", {}) if cache_result.get("asset_prefetch", {}) is Dictionary else {}
	var texture_ok := FileAccess.file_exists(cached_folder.path_join("probe.png"))
	var mesh_ok := FileAccess.file_exists(cached_folder.path_join("probe.mesh.json"))
	var ok := bool(cache_result.get("ok", false)) and texture_ok and mesh_ok and int(prefetch.get("failed", 0)) == 0
	print("[validate_cloud_map_asset_roundtrip] ok=%s urls=%d texture=%s mesh=%s prefetch=%s" % [
		str(ok), urls.size(), str(texture_ok), str(mesh_ok), str(prefetch)
	])
	studio.queue_free()
	await process_frame
	await _cleanup()
	quit(0 if ok else 1)


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


func _extract_id(value: Variant) -> String:
	var record := _extract_record(value)
	return str(record.get("id", record.get("map_id", ""))).strip_edges()


func _extract_record(value: Variant) -> Dictionary:
	if value is Dictionary:
		var dictionary := value as Dictionary
		if dictionary.has("id") or dictionary.has("map_id"):
			return dictionary
		return _extract_record(dictionary.get("data", null))
	if value is Array and not (value as Array).is_empty():
		return _extract_record((value as Array)[0])
	return {}


func _cleanup() -> void:
	if not _map_id.is_empty():
		await _cloud.call("delete_map_and_cleanup", _map_id)
	await process_frame


func _finish(ok: bool, message: String) -> void:
	print("[validate_cloud_map_asset_roundtrip] ok=%s %s" % [str(ok), message])
	quit(0 if ok else 1)
