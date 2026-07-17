extends SceneTree

var _session_file_backup: Dictionary = {}
var _cloud_api: Node = null
var _model_id := ""
var _user_id := ""
var _source_path := ""
var _thumbnail_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_backup_session_files()
	_cloud_api = root.get_node_or_null("CloudAPI")
	if _cloud_api == null:
		await _finish(false, "CloudAPI autoload was not found")
		return
	await process_frame
	await process_frame
	var stamp := "%d%s" % [
		int(Time.get_unix_time_from_system()),
		Crypto.new().generate_random_bytes(4).hex_encode()
	]
	var username := "codexmodel%s" % stamp
	var password := "CodexModel%s!" % stamp
	var sign_up_result: Dictionary = await _cloud_api.call("sign_up_with_credentials", username, password)
	if not bool(sign_up_result.get("ok", false)):
		await _finish(false, "sign-up failed: %s" % _error_text(sign_up_result))
		return
	var session: Dictionary = _cloud_api.call("get_current_auth_session")
	_user_id = str(session.get("user_id", "")).strip_edges()
	_model_id = "model_contract_%s" % stamp

	var scene_resource := load("res://scenes/model_editor/model_editor.tscn") as PackedScene
	var editor := scene_resource.instantiate() if scene_resource != null else null
	if editor == null:
		await _finish(false, "Model Editor scene could not be instantiated")
		return
	root.add_child(editor)
	await process_frame
	await process_frame
	editor.call("_clear_parts")
	var parts_root := editor.get("_parts_root") as Node3D
	var imported_root := Node3D.new()
	imported_root.name = "PublishContractModel"
	imported_root.set_meta("kind", "ImportedScene")
	parts_root.add_child(imported_root)
	imported_root.add_child(_colored_mesh("RedSurface", Color(0.86, 0.12, 0.08)))
	var blue_surface := _colored_mesh("BlueSurface", Color(0.08, 0.25, 0.88))
	blue_surface.position.x = 1.25
	imported_root.add_child(blue_surface)
	await process_frame
	var model_data: Dictionary = editor.call("_collect_model_data")
	_source_path = str(model_data.get("canonical_source_model_path", "")).strip_edges()
	editor.queue_free()
	await process_frame
	if _source_path.is_empty() or not FileAccess.file_exists(_source_path):
		await _finish(false, "canonical GLB was not exported")
		return

	_thumbnail_path = "user://model_publish_contract_%s.png" % stamp
	var thumbnail := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	thumbnail.fill(Color(0.07, 0.09, 0.12, 1.0))
	thumbnail.fill_rect(Rect2i(24, 48, 68, 96), Color(0.86, 0.12, 0.08, 1.0))
	thumbnail.fill_rect(Rect2i(100, 48, 68, 96), Color(0.08, 0.25, 0.88, 1.0))
	if thumbnail.save_png(_thumbnail_path) != OK:
		await _finish(false, "thumbnail fixture could not be written")
		return

	var model_upload: Dictionary = await _cloud_api.call(
		"upload_model_asset_file",
		_model_id,
		"model.glb",
		_source_path,
		"model/gltf-binary"
	)
	var thumbnail_upload: Dictionary = await _cloud_api.call(
		"upload_model_asset_file",
		_model_id,
		"thumbnail.png",
		_thumbnail_path,
		"image/png"
	)
	if not bool(model_upload.get("ok", false)) or not bool(thumbnail_upload.get("ok", false)):
		await _finish(false, "asset upload failed: %s / %s" % [_error_text(model_upload), _error_text(thumbnail_upload)])
		return
	var source_url := _public_url(model_upload)
	var thumbnail_url := _public_url(thumbnail_upload)
	if source_url.is_empty() or thumbnail_url.is_empty():
		await _finish(false, "storage upload did not return public URLs")
		return
	model_data["source_url"] = source_url
	model_data["source_file_url"] = source_url
	var metadata := {
		"id": _model_id,
		"description": "Automated model publication contract",
		"visibility": "private",
		"asset_type": "model",
		"source_url": source_url,
		"source_file_name": "model.glb",
		"thumbnail": thumbnail_url
	}
	var publish_result: Dictionary = await _cloud_api.call(
		"publish_model_asset",
		model_data,
		"Model Publish Contract",
		metadata
	)
	if not bool(publish_result.get("ok", false)):
		await _finish(false, "publish failed: %s" % _error_text(publish_result))
		return
	var fetch_result: Dictionary = await _cloud_api.call("fetch_marketplace_models", 32, true, true)
	var published_entry := _find_model_entry(fetch_result, _model_id)
	var transport_ok := not published_entry.is_empty() \
		and str(published_entry.get("source_url", "")).strip_edges() == source_url \
		and str(published_entry.get("thumbnail", "")).strip_edges() == thumbnail_url
	var downloaded_glb := await _http_get(source_url)
	var source_ok := downloaded_glb.size() > 32 and _validate_downloaded_glb(downloaded_glb)
	var thumbnail_ok := (await _http_get(thumbnail_url)).size() > 32
	var parts: Array = model_data.get("parts", []) if model_data.get("parts", []) is Array else []
	var ok := transport_ok and source_ok and thumbnail_ok and parts.size() == 2
	await _finish(ok, "catalog=%s source=%s thumbnail=%s parts=%d" % [
		str(transport_ok),
		str(source_ok),
		str(thumbnail_ok),
		parts.size()
	])

func _colored_mesh(mesh_name: String, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	return mesh_instance

func _validate_downloaded_glb(bytes: PackedByteArray) -> bool:
	var path := "user://model_publish_download.glb"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := document.append_from_file(path, state) == OK
	_remove_if_present(path)
	return ok

func _find_model_entry(result: Dictionary, model_id: String) -> Dictionary:
	if not bool(result.get("ok", false)):
		return {}
	for entry_variant in _extract_array_payload(result.get("data", [])):
		if entry_variant is Dictionary and str((entry_variant as Dictionary).get("id", "")).strip_edges() == model_id:
			return (entry_variant as Dictionary).duplicate(true)
	return {}

func _extract_array_payload(value: Variant) -> Array:
	if value is Array:
		return value as Array
	if value is Dictionary:
		for key in ["items", "models", "data"]:
			var nested: Variant = (value as Dictionary).get(key, [])
			if nested is Array:
				return nested as Array
	return []

func _public_url(result: Dictionary) -> String:
	var asset: Dictionary = result.get("asset", {}) if result.get("asset", {}) is Dictionary else {}
	return str(asset.get("public_url", "")).strip_edges()

func _http_get(url: String) -> PackedByteArray:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 20.0
	if request.request(url) != OK:
		request.queue_free()
		return PackedByteArray()
	var response: Array = await request.request_completed
	request.queue_free()
	if response.size() < 4 or int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) < 200 or int(response[1]) >= 300:
		return PackedByteArray()
	return response[3] as PackedByteArray

func _cleanup_probe() -> void:
	if not _model_id.is_empty():
		await _delete_rest_rows("/model_assets?id=eq.%s" % _model_id.uri_encode())
	if not _user_id.is_empty():
		await _delete_rest_rows("/profiles?id=eq.%s" % _user_id.uri_encode())
	_remove_if_present(_source_path)
	_remove_if_present(_thumbnail_path)

func _delete_rest_rows(endpoint: String) -> void:
	var request := HTTPRequest.new()
	root.add_child(request)
	var session: Dictionary = _cloud_api.call("get_current_auth_session")
	var token := str(session.get("access_token", "")).strip_edges()
	var headers := PackedStringArray([
		"Accept: application/json",
		"apikey: %s" % str(_cloud_api.get("api_key"))
	])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var base_url := str(_cloud_api.get("base_url")).trim_suffix("/")
	if request.request("%s%s" % [base_url, endpoint], headers, HTTPClient.METHOD_DELETE) == OK:
		await request.request_completed
	request.queue_free()

func _remove_if_present(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _error_text(result: Dictionary) -> String:
	for key in ["error", "message"]:
		var value := str(result.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return "unknown error"

func _backup_session_files() -> void:
	for path in ["user://session/current_profile.json", "user://session/bobux_auth_session.json"]:
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
		if bool(entry.get("exists", false)):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(path)).get_base_dir())
			var file := FileAccess.open(str(path), FileAccess.WRITE)
			if file != null:
				file.store_string(str(entry.get("text", "")))
				file.close()
		elif FileAccess.file_exists(str(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(path)))

func _finish(ok: bool, details: String) -> void:
	await _cleanup_probe()
	_restore_session_files()
	print("[validate_model_publish_roundtrip] ok=%s %s" % [str(ok), details])
	quit(0 if ok else 1)
