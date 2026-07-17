extends SceneTree

var _studio: Control = null
var _folder: String = ""
var _map_id: String = ""
var _cloud: Node = null
var _session: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cloud = root.get_node_or_null("CloudAPI")
	_session = root.get_node_or_null("UserSession")
	if _cloud == null or _session == null:
		push_error("[validate_cloud_map_publish_roundtrip] Required autoloads are missing")
		quit(1)
		return
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[validate_cloud_map_publish_roundtrip] Studio failed to load")
		quit(1)
		return
	_studio = packed.instantiate() as Control
	root.add_child(_studio)
	await process_frame
	await process_frame
	await process_frame

	var username := str(_session.get("username")).strip_edges()
	if username.is_empty():
		username = str(_cloud.call("get_current_username"))
	var auth_result: Dictionary = await _cloud.call("authenticate_or_create_profile", username)
	if not bool(auth_result.get("ok", false)):
		push_error("[validate_cloud_map_publish_roundtrip] Auth failed: %s" % str(auth_result.get("error", "unknown")))
		await _cleanup()
		quit(1)
		return

	var suffix := str(Time.get_ticks_msec())
	var map_name := "__publish_contract_%s" % suffix
	_folder = "user://publish_contract_%s" % suffix
	_studio.set("current_map_name", map_name)
	_studio.set("current_map_folder", _folder)
	var publish_result: Dictionary = await _studio.call("_publish_map", _folder, map_name, "Automated publish contract probe")
	_map_id = _extract_id(publish_result.get("data", {}))
	var published := bool(publish_result.get("ok", false)) and not _map_id.is_empty()

	var public_record: Dictionary = {}
	if published:
		public_record = await _fetch_public_map(_map_id)
	var publicly_visible := (
		not public_record.is_empty()
		and bool(public_record.get("is_published", false))
		and str(public_record.get("name", "")) == map_name
	)
	var payload: Dictionary = public_record.get("data", {}) if public_record.get("data", {}) is Dictionary else {}
	var downloadable := payload is Dictionary and (payload as Dictionary).has("blocks")
	var thumbnail_url := str(public_record.get("thumbnail", "")).strip_edges()
	var thumbnail_available := not thumbnail_url.is_empty() and await _url_exists(thumbnail_url)

	print(
		"[validate_cloud_map_publish_roundtrip] published=%s public=%s data=%s thumbnail=%s id=%s"
		% [published, publicly_visible, downloadable, thumbnail_available, _map_id]
	)
	var ok := published and publicly_visible and downloadable and thumbnail_available
	await _cleanup()
	quit(0 if ok else 1)


func _fetch_public_map(map_id: String) -> Dictionary:
	var url := "%s/maps?select=id,name,owner_id,owner_name,is_published,thumbnail,cloud_version_id,data&id=eq.%s&is_published=eq.true&limit=1" % [
		str(_cloud.get("base_url")).trim_suffix("/"),
		map_id.uri_encode()
	]
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 20.0
	var start_error := request.request(url, PackedStringArray(["apikey: %s" % str(_cloud.get("api_key"))]))
	if start_error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response.size() < 4 or int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Array and not (parsed as Array).is_empty() and (parsed as Array)[0] is Dictionary:
		return ((parsed as Array)[0] as Dictionary).duplicate(true)
	return {}


func _url_exists(url: String) -> bool:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 15.0
	var start_error := request.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if start_error != OK:
		request.queue_free()
		return false
	var response: Array = await request.request_completed
	request.queue_free()
	return response.size() >= 2 and int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) >= 200 and int(response[1]) < 300


func _extract_id(value: Variant) -> String:
	if value is Dictionary:
		for key in ["id", "map_id"]:
			var candidate := str((value as Dictionary).get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
		return _extract_id((value as Dictionary).get("data", null))
	if value is Array and not (value as Array).is_empty():
		return _extract_id((value as Array)[0])
	return ""


func _cleanup() -> void:
	if not _map_id.is_empty():
		await _cloud.call("delete_map_and_cleanup", _map_id)
	if _studio != null and is_instance_valid(_studio):
		_studio.queue_free()
	await process_frame
	if _folder.begins_with("user://publish_contract_"):
		for file_name in ["icon.png", "meta.json", "map_data.json"]:
			var file_path := _folder.path_join(file_name)
			if FileAccess.file_exists(file_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
		var absolute_folder := ProjectSettings.globalize_path(_folder)
		if DirAccess.dir_exists_absolute(absolute_folder):
			DirAccess.remove_absolute(absolute_folder)
