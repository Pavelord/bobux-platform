class_name RbxlServerImporter
extends Node

signal import_progress(stage: String, progress: float, message: String, parts_done: int, parts_total: int)
signal import_finished(job_id: String, scene_path: String)
signal import_failed(message: String)

const DEFAULT_SERVER_URL := "http://109.71.245.162:7821"
const SERVER_SETTING := "bobux/import_server_url"

var server_url: String = ""
var poll_interval_seconds: float = 1.0
var request_timeout_seconds: float = 120.0
var last_status: Dictionary = {}


static func ensure_project_settings() -> void:
	if not ProjectSettings.has_setting(SERVER_SETTING):
		ProjectSettings.set_setting(SERVER_SETTING, DEFAULT_SERVER_URL)
		ProjectSettings.set_initial_value(SERVER_SETTING, DEFAULT_SERVER_URL)
		ProjectSettings.set_as_basic(SERVER_SETTING, true)


func _ready() -> void:
	ensure_project_settings()
	server_url = str(ProjectSettings.get_setting(SERVER_SETTING, DEFAULT_SERVER_URL)).strip_edges().trim_suffix("/")


func import_rbxl(path: String) -> Dictionary:
	if not is_inside_tree():
		var tree_error := "RbxlServerImporter must be inside the scene tree before import_rbxl()"
		import_failed.emit(tree_error)
		return {"ok": false, "error": tree_error}
	if server_url.strip_edges().is_empty():
		ensure_project_settings()
		server_url = str(ProjectSettings.get_setting(SERVER_SETTING, DEFAULT_SERVER_URL)).strip_edges().trim_suffix("/")

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error := "Could not open RBXL file: %s" % path
		import_failed.emit(open_error)
		return {"ok": false, "error": open_error}
	var bytes := file.get_buffer(file.get_length())
	file.close()

	import_progress.emit("uploading", 0.0, "Отправка файла на сервер", 0, 1)
	var upload := await _upload_file_to_server(path.get_file(), bytes)
	if not bool(upload.get("ok", false)):
		import_failed.emit(str(upload.get("error", "Upload failed")))
		return upload

	var job_id := str(upload.get("job_id", ""))
	if job_id.is_empty():
		var no_job_error := "Import server did not return job_id"
		import_failed.emit(no_job_error)
		return {"ok": false, "error": no_job_error}

	while true:
		await get_tree().create_timer(poll_interval_seconds).timeout
		var status := await _poll_status(job_id)
		if not bool(status.get("ok", false)):
			import_failed.emit(str(status.get("error", "Status polling failed")))
			return status
		last_status = status
		var stage := str(status.get("stage", "processing"))
		var progress := float(status.get("progress", 0.0))
		var done := int(status.get("parts_done", 0))
		var total := int(status.get("parts_total", 0))
		import_progress.emit(stage, progress, _format_status_message(status), done, total)
		var state := str(status.get("status", "processing"))
		if state == "done":
			break
		if state == "error":
			var server_error := str(status.get("error", "Import server returned an error"))
			import_failed.emit(server_error)
			return {"ok": false, "error": server_error, "status": status}

	import_progress.emit("downloading", 0.0, "Загрузка готовой сцены", 0, 1)
	var output_dir := "user://imported/%s" % job_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rbxl_assets"))

	var scene_result := await _download_to_file("%s/result/%s/scene.tscn" % [server_url, job_id], output_dir.path_join("scene.tscn"))
	if not bool(scene_result.get("ok", false)):
		import_failed.emit(str(scene_result.get("error", "Scene download failed")))
		return scene_result

	var assets_result := await _request_json("%s/result/%s/assets" % [server_url, job_id])
	if bool(assets_result.get("ok", false)):
		var meshes := assets_result.get("meshes", [])
		if meshes is Array:
			var index := 0
			for asset_id in meshes:
				index += 1
				import_progress.emit("downloading", float(index) / maxf(float(meshes.size()), 1.0), "Загрузка мешей", index, meshes.size())
				var glb_url := "%s/result/%s/assets/%s.glb" % [server_url, job_id, str(asset_id)]
				var glb_path := output_dir.path_join("%s.glb" % str(asset_id))
				await _download_to_file(glb_url, glb_path)
				var mesh_json_url := "%s/result/%s/assets/%s.mesh.json" % [server_url, job_id, str(asset_id)]
				var mesh_json_path := "user://rbxl_assets/%s.mesh.json" % str(asset_id)
				await _download_to_file(mesh_json_url, mesh_json_path)
		var textures := assets_result.get("textures", [])
		if textures is Array:
			var texture_index := 0
			for record in textures:
				if not (record is Dictionary):
					continue
				texture_index += 1
				var texture_id := str(record.get("id", ""))
				var ext := str(record.get("ext", "png")).strip_edges().to_lower()
				if texture_id.is_empty() or ext.is_empty():
					continue
				import_progress.emit("downloading", float(texture_index) / maxf(float(textures.size()), 1.0), "Загрузка текстур", texture_index, textures.size())
				var texture_url := "%s/result/%s/assets/%s.%s" % [server_url, job_id, texture_id, ext]
				var texture_path := "user://rbxl_assets/%s.asset.%s" % [texture_id, ext]
				await _download_to_file(texture_url, texture_path)

	var scene_path := output_dir.path_join("scene.tscn")
	import_progress.emit("done", 1.0, "Импорт готов", 1, 1)
	import_finished.emit(job_id, scene_path)
	return {"ok": true, "job_id": job_id, "scene_path": scene_path}


func ping_server() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "error": "RbxlServerImporter is not inside the scene tree"}
	if server_url.strip_edges().is_empty():
		ensure_project_settings()
		server_url = str(ProjectSettings.get_setting(SERVER_SETTING, DEFAULT_SERVER_URL)).strip_edges().trim_suffix("/")
	return await _request_json("%s/cache/stats" % server_url)


func _upload_file_to_server(filename: String, bytes: PackedByteArray) -> Dictionary:
	var boundary := "BobuxBoundary%s" % str(Time.get_ticks_usec())
	var body := PackedByteArray()
	_append_utf8(body, "--%s\r\n" % boundary)
	_append_utf8(body, "Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" % filename.replace("\"", "_"))
	_append_utf8(body, "Content-Type: application/octet-stream\r\n\r\n")
	body.append_array(bytes)
	_append_utf8(body, "\r\n--%s--\r\n" % boundary)
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=%s" % boundary])
	var response := await _request_raw("%s/import" % server_url, headers, HTTPClient.METHOD_POST, body)
	if not bool(response.get("ok", false)):
		return response
	var data := _parse_json_response(response)
	if not bool(data.get("ok", false)):
		return data
	data["job_id"] = str(data.get("job_id", ""))
	return data


func _poll_status(job_id: String) -> Dictionary:
	return await _request_json("%s/status/%s" % [server_url, job_id])


func _request_json(url: String) -> Dictionary:
	var response := await _request_raw(url, PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray())
	if not bool(response.get("ok", false)):
		return response
	return _parse_json_response(response)


func _download_to_file(url: String, path: String) -> Dictionary:
	var response := await _request_raw(url, PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray())
	if not bool(response.get("ok", false)):
		return response
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Could not write %s" % path}
	out.store_buffer(response.get("body", PackedByteArray()))
	out.close()
	return {"ok": true, "path": path}


func _request_raw(url: String, headers: PackedStringArray, method: int, body: PackedByteArray) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = request_timeout_seconds
	add_child(request)
	var err := request.request_raw(url, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "HTTP request failed to start: %d" % err}
	var completed: Array = await request.request_completed
	request.queue_free()
	var result := int(completed[0])
	var code := int(completed[1])
	var response_body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "HTTP request failed: %d" % result, "code": code, "body": response_body}
	if code < 200 or code >= 300:
		return {"ok": false, "error": "HTTP %d" % code, "code": code, "body": response_body}
	return {"ok": true, "code": code, "body": response_body}


func _parse_json_response(response: Dictionary) -> Dictionary:
	var text := ""
	if response.get("body") is PackedByteArray:
		text = (response["body"] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid JSON response", "raw": text}
	var data: Dictionary = parsed
	data["ok"] = true
	return data


func _append_utf8(body: PackedByteArray, text: String) -> void:
	body.append_array(text.to_utf8_buffer())


func _format_status_message(status: Dictionary) -> String:
	var stage := str(status.get("stage", "processing"))
	var done := int(status.get("parts_done", 0))
	var total := int(status.get("parts_total", 0))
	var missing := status.get("missing_meshes", [])
	var missing_count: int = (missing as Array).size() if missing is Array else 0
	match stage:
		"parsing":
			return "Парсинг RBXL"
		"downloading":
			return "Скачивание ассетов (%d/%d), пропущено %d" % [done, total, missing_count]
		"converting":
			return "Конвертация мешей"
		"building":
			return "Сборка сцены"
		"done":
			return "Импорт готов"
		_:
			return stage
