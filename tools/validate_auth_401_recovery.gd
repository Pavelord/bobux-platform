extends SceneTree

var _session_file_backup: Dictionary = {}


func _initialize() -> void:
	_backup_session_files()
	var cloud_api := _get_cloud_api()
	if cloud_api == null:
		_restore_session_files()
		push_error("[validate_auth_401_recovery] CloudAPI autoload was not found")
		quit(1)
		return
	await process_frame
	await process_frame

	var previous_session: Dictionary = cloud_api.call("get_current_auth_session")
	cloud_api.set("_auth_access_token", "codex_invalid_access_token")
	cloud_api.set("_auth_refresh_token", "codex_invalid_refresh_token")
	cloud_api.set("_auth_user_id", "codex_invalid_user")
	cloud_api.set("_auth_expires_at", int(Time.get_unix_time_from_system()) + 3600)
	cloud_api.set("_current_profile_username", "codex_invalid_user")

	var result: Dictionary = await cloud_api.call(
		"_request_json_with_retries",
		"/rpc/get_friends_list",
		HTTPClient.METHOD_POST,
		{},
		"validate_auth_401_recovery",
		PackedStringArray(),
		true,
		4.0,
		1
	)
	var cleared_session: Dictionary = cloud_api.call("get_current_auth_session")
	var error_text := str(result.get("error", ""))
	var access_after := str(cleared_session.get("access_token", "")).strip_edges()
	_restore_cloud_session(cloud_api, previous_session)
	_restore_session_files()

	if bool(result.get("ok", false)):
		push_error("[validate_auth_401_recovery] Invalid token request unexpectedly succeeded")
		quit(1)
		return
	if access_after != "":
		push_error("[validate_auth_401_recovery] Invalid token did not clear the saved auth session")
		quit(1)
		return
	if error_text.find("sign in again") == -1:
		push_error("[validate_auth_401_recovery] Invalid token error was not user-facing: %s" % error_text)
		quit(1)
		return

	print("[validate_auth_401_recovery] Auth 401 recovery OK")
	quit(0)


func _restore_cloud_session(cloud_api: Node, session: Dictionary) -> void:
	cloud_api.set("_auth_access_token", str(session.get("access_token", "")))
	cloud_api.set("_auth_refresh_token", str(session.get("refresh_token", "")))
	cloud_api.set("_auth_user_id", str(session.get("user_id", "")))
	cloud_api.set("_auth_expires_at", int(session.get("expires_at", 0)))
	cloud_api.set("_auth_is_anonymous", bool(session.get("is_anonymous", false)))
	cloud_api.set("_auth_email", str(session.get("email", "")))
	cloud_api.set("_current_profile_username", str(session.get("username", "")))


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
