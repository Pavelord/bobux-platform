extends SceneTree

var _session_file_backup: Dictionary = {}


func _initialize() -> void:
	_backup_session_files()
	var cloud_api := _get_cloud_api()
	if cloud_api == null:
		_restore_session_files()
		push_error("[validate_friends_client] CloudAPI autoload was not found")
		quit(1)
		return
	await process_frame
	await process_frame

	var random_suffix := Crypto.new().generate_random_bytes(4).hex_encode()
	var stamp := "%d%s" % [int(Time.get_unix_time_from_system()), random_suffix]
	var username := "codexfriends%s" % stamp
	var password := "CodexFriends%s!" % stamp
	var sign_up_result: Dictionary = await cloud_api.call("sign_up_with_credentials", username, password)
	if not bool(sign_up_result.get("ok", false)):
		_restore_session_files()
		push_error("[validate_friends_client] Sign-up failed: %s" % _error_text(sign_up_result))
		quit(1)
		return

	var session: Dictionary = cloud_api.call("get_current_auth_session")
	var user_id := str(session.get("user_id", "")).strip_edges()
	var friends_result: Dictionary = await cloud_api.call("get_friends_list")
	if not bool(friends_result.get("ok", false)):
		await _cleanup_probe(user_id)
		_restore_session_files()
		push_error("[validate_friends_client] Friends list failed: %s" % _error_text(friends_result))
		quit(1)
		return
	if not (friends_result.get("data", []) is Array):
		await _cleanup_probe(user_id)
		_restore_session_files()
		push_error("[validate_friends_client] Friends list did not return an array")
		quit(1)
		return

	var incoming_result: Dictionary = await cloud_api.call("get_incoming_friend_requests")
	var outgoing_result: Dictionary = await cloud_api.call("get_outgoing_friend_requests")
	if not bool(incoming_result.get("ok", false)) or not bool(outgoing_result.get("ok", false)):
		await _cleanup_probe(user_id)
		_restore_session_files()
		push_error("[validate_friends_client] Friend request RPC failed: incoming=%s outgoing=%s" % [_error_text(incoming_result), _error_text(outgoing_result)])
		quit(1)
		return

	await _cleanup_probe(user_id)
	_restore_session_files()
	print("[validate_friends_client] Friends client RPC OK")
	quit(0)


func _cleanup_probe(user_id: String) -> void:
	if user_id.strip_edges().is_empty():
		return
	await _delete_rest_rows("/friendships?or=(user_a.eq.%s,user_b.eq.%s)" % [user_id.uri_encode(), user_id.uri_encode()])
	await _delete_rest_rows("/friend_requests?or=(sender_id.eq.%s,receiver_id.eq.%s)" % [user_id.uri_encode(), user_id.uri_encode()])
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
