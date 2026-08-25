extends SceneTree

const AVATAR_TEMPLATE_PROCESSOR: Script = preload("res://scripts/avatar/avatar_template_processor.gd")

var _session_file_backup: Dictionary = {}

func _initialize() -> void:
	_backup_session_files()
	var stamp := "%d" % Time.get_ticks_msec()
	var username := "codexpub%s" % stamp
	var password := "CodexPub%s!" % stamp
	var item_id := "codex_avatar_publish_%s" % stamp
	var user_id := ""
	var cloud_api := _get_cloud_api()
	if cloud_api == null:
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] CloudAPI autoload was not found")
		quit(1)
		return
	await process_frame
	await process_frame
	var sign_up_result: Dictionary = await cloud_api.call("sign_up_with_credentials", username, password)
	if not bool(sign_up_result.get("ok", false)):
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Sign-up failed: %s" % _error_text(sign_up_result))
		quit(1)
		return
	var session: Dictionary = cloud_api.call("get_current_auth_session")
	user_id = str(session.get("user_id", "")).strip_edges()
	var import_result: Dictionary = AVATAR_TEMPLATE_PROCESSOR.import_template_to_user_storage(
		"res://assets/avatar/shirt_template_reference.jpg",
		"shirt",
		username
	)
	if not bool(import_result.get("ok", false)):
		await _cleanup_probe(item_id, user_id)
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Template import failed: %s" % _error_text(import_result))
		quit(1)
		return
	var template_path := str(import_result.get("path", "")).strip_edges()
	var preview_path := str(import_result.get("preview_path", "")).strip_edges()
	var template_upload: Dictionary = await cloud_api.call("upload_avatar_item_file", item_id, "shirt_template.png", template_path, "image/png")
	if not bool(template_upload.get("ok", false)):
		await _cleanup_probe(item_id, user_id)
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Template upload failed: %s" % _error_text(template_upload))
		quit(1)
		return
	var template_asset: Dictionary = template_upload.get("asset", {}) if template_upload.get("asset", {}) is Dictionary else {}
	var template_url := str(template_asset.get("public_url", "")).strip_edges()
	if template_url.is_empty():
		await _cleanup_probe(item_id, user_id)
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Template upload returned no public_url")
		quit(1)
		return
	var thumbnail_url := template_url
	if not preview_path.is_empty() and FileAccess.file_exists(preview_path):
		var thumbnail_upload: Dictionary = await cloud_api.call("upload_avatar_item_file", item_id, "thumbnail.png", preview_path, "image/png")
		if bool(thumbnail_upload.get("ok", false)):
			var thumbnail_asset: Dictionary = thumbnail_upload.get("asset", {}) if thumbnail_upload.get("asset", {}) is Dictionary else {}
			var uploaded_thumbnail_url := str(thumbnail_asset.get("public_url", "")).strip_edges()
			if not uploaded_thumbnail_url.is_empty():
				thumbnail_url = uploaded_thumbnail_url
	var clothing_data := {
		"item_kind": "shirt",
		"category": "shirt",
		"texture_path": template_url,
		"template_url": template_url,
		"atlas_path": template_url,
		"thumbnail": thumbnail_url,
		"template_version": str(import_result.get("template_version", "bobux_r6_square_v1"))
	}
	var metadata := {
		"id": item_id,
		"category": "shirt",
		"asset_type": "avatar_item",
		"item_kind": "shirt",
		"visibility": "private",
		"thumbnail": thumbnail_url,
		"template_url": template_url,
		"source_url": template_url,
		"attachment_slot": "Torso",
		"attachment_transform": {},
		"data": clothing_data
	}
	var publish_result: Dictionary = await cloud_api.call("publish_avatar_item", clothing_data, "Codex Publish Probe", metadata)
	if not bool(publish_result.get("ok", false)):
		await _cleanup_probe(item_id, user_id)
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Publish failed: %s" % _error_text(publish_result))
		quit(1)
		return
	var fetch_result: Dictionary = await cloud_api.call("fetch_avatar_marketplace_items", 32, true, true)
	if not bool(fetch_result.get("ok", false)):
		await _cleanup_probe(item_id, user_id)
		_restore_session_files()
		push_error("[validate_avatar_item_publish_client] Fetch after publish failed: %s" % _error_text(fetch_result))
		quit(1)
		return
	var found := false
	for item_variant in _extract_array_payload(fetch_result.get("data", [])):
		if item_variant is Dictionary and str((item_variant as Dictionary).get("id", "")) == item_id:
			found = true
			break
	await _cleanup_probe(item_id, user_id)
	_restore_session_files()
	if not found:
		push_error("[validate_avatar_item_publish_client] Published avatar item was not returned by owner marketplace fetch")
		quit(1)
		return
	print("[validate_avatar_item_publish_client] Avatar item client publish OK")
	quit(0)

func _cleanup_probe(item_id: String, user_id: String) -> void:
	if not item_id.strip_edges().is_empty():
		await _delete_rest_rows("/user_inventory?item_id=eq.%s" % item_id.uri_encode())
		await _delete_rest_rows("/avatar_items?id=eq.%s" % item_id.uri_encode())
	if not user_id.strip_edges().is_empty():
		await _delete_rest_rows("/profiles?id=eq.%s" % user_id.uri_encode())

func _delete_rest_rows(endpoint: String) -> int:
	var cloud_api := _get_cloud_api()
	if cloud_api == null:
		return 0
	var request := HTTPRequest.new()
	root.add_child(request)
	var session: Dictionary = cloud_api.call("get_current_auth_session")
	var token := str(session.get("access_token", "")).strip_edges()
	var headers := PackedStringArray([
		"Accept: application/json",
		"apikey: %s" % str(cloud_api.get("api_key"))
	])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var base_url := str(cloud_api.get("base_url")).trim_suffix("/")
	var err := request.request("%s%s" % [base_url, endpoint], headers, HTTPClient.METHOD_DELETE)
	if err != OK:
		request.queue_free()
		return 0
	var result: Array = await request.request_completed
	request.queue_free()
	return int(result[1]) if result.size() >= 2 else 0

func _backup_session_files() -> void:
	for path in ["user://session/current_profile.json", "user://session/bobux_auth_session.json"]:
		var absolute_path := ProjectSettings.globalize_path(path)
		var entry := {"exists": FileAccess.file_exists(path), "text": ""}
		if bool(entry["exists"]):
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				entry["text"] = file.get_as_text()
				file.close()
		_session_file_backup[path] = entry

func _restore_session_files() -> void:
	for path in _session_file_backup.keys():
		var entry: Dictionary = _session_file_backup[path]
		var absolute_path := ProjectSettings.globalize_path(str(path))
		if bool(entry.get("exists", false)):
			DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
			var file := FileAccess.open(str(path), FileAccess.WRITE)
			if file != null:
				file.store_string(str(entry.get("text", "")))
				file.close()
		elif FileAccess.file_exists(str(path)):
			DirAccess.remove_absolute(absolute_path)

func _get_cloud_api() -> Node:
	return root.get_node_or_null("CloudAPI")

func _extract_array_payload(value: Variant) -> Array:
	if value is Array:
		return value as Array
	if value is Dictionary:
		for key in ["items", "avatar_items", "data"]:
			var nested: Variant = (value as Dictionary).get(key, [])
			if nested is Array:
				return nested as Array
	return []

func _error_text(result: Dictionary) -> String:
	for key in ["error", "message"]:
		var value := str(result.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	var data: Variant = result.get("data", null)
	if data is Dictionary:
		for key in ["message", "error"]:
			var value := str((data as Dictionary).get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	return JSON.stringify(result)
