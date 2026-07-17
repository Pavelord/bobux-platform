extends Control

const DEFAULT_MANIFEST_URL: String = "http://109.71.245.162/launcher/latest.json"
const LOCAL_VERSION_FILE: String = "version.json"
const TEMP_DIR_NAME: String = "_download"
const STAGING_DIR_NAME: String = "_staging_game"
const GAME_BACKUP_DIR_NAME: String = "_backup_game"
const LAUNCHER_STAGING_DIR_NAME: String = "_staging_launcher"
const HTTP_TIMEOUT_SECONDS: float = 60.0
const DOWNLOAD_TIMEOUT_SECONDS: float = 120.0
const HTTP_ATTEMPTS_PER_URL: int = 3
const DOWNLOAD_ATTEMPTS_PER_URL: int = 8
const DOWNLOAD_CHUNK_BYTES: int = 512 * 1024
const LAUNCHER_VERSION: String = "0.1.11"
const LAUNCHER_BUILD: int = 13
const MIN_GAME_EXECUTABLE_BYTES: int = 10 * 1024 * 1024

var _title_label: Label = null
var _status_label: Label = null
var _detail_label: Label = null
var _progress_bar: ProgressBar = null
var _action_button: Button = null
var _active_download_request: HTTPRequest = null
var _current_manifest: Dictionary = {}
var _install_root: String = ""
var _game_dir: String = ""
var _temp_dir: String = ""
var _staging_dir: String = ""
var _game_backup_dir: String = ""
var _launcher_staging_dir: String = ""

func _ready() -> void:
	_install_root = _get_install_root()
	_game_dir = _install_root.path_join(_get_project_setting_string("launcher/game_folder_name", "Game"))
	_temp_dir = _install_root.path_join(TEMP_DIR_NAME)
	_staging_dir = _install_root.path_join(STAGING_DIR_NAME)
	_game_backup_dir = _install_root.path_join(GAME_BACKUP_DIR_NAME)
	_launcher_staging_dir = _install_root.path_join(LAUNCHER_STAGING_DIR_NAME)
	_build_ui()
	call_deferred("_run_update_flow")

func _process(_delta: float) -> void:
	if _active_download_request == null:
		return
	var downloaded: int = _active_download_request.get_downloaded_bytes()
	var total: int = _active_download_request.get_body_size()
	if total > 0:
		_set_progress(float(downloaded) / float(total), "Downloading %.1f / %.1f MB" % [
			float(downloaded) / 1048576.0,
			float(total) / 1048576.0
		])
	else:
		_set_progress(-1.0, "Downloading %.1f MB" % (float(downloaded) / 1048576.0))

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.045, 0.08, 0.105, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var accent := ColorRect.new()
	accent.color = Color(0.0, 0.48, 0.74, 1.0)
	accent.anchor_right = 1.0
	accent.offset_bottom = 8.0
	background.add_child(accent)

	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -310.0
	card.offset_top = -190.0
	card.offset_right = 310.0
	card.offset_bottom = 190.0
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.96, 0.97, 0.98, 1.0)
	card_style.corner_radius_top_left = 18
	card_style.corner_radius_top_right = 18
	card_style.corner_radius_bottom_right = 18
	card_style.corner_radius_bottom_left = 18
	card_style.shadow_color = Color(0, 0, 0, 0.26)
	card_style.shadow_size = 18
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var logo_texture := _load_image_texture("res://assets/branding/bobux_logo_ui.png")
	if logo_texture != null:
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(0.0, 118.0)
		root.add_child(logo)

	_title_label = Label.new()
	_title_label.text = "Bobux"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.08, 0.13, 0.17, 1.0))
	root.add_child(_title_label)

	_status_label = Label.new()
	_status_label.text = "Checking for updates..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", Color(0.16, 0.18, 0.21, 1.0))
	root.add_child(_status_label)

	_detail_label = Label.new()
	_detail_label.text = "Preparing launcher."
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52, 1.0))
	root.add_child(_detail_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 20.0)
	root.add_child(_progress_bar)

	_action_button = Button.new()
	_action_button.text = "Launch"
	_action_button.disabled = true
	_action_button.custom_minimum_size = Vector2(0.0, 44.0)
	_action_button.focus_mode = Control.FOCUS_NONE
	_action_button.pressed.connect(_launch_game)
	root.add_child(_action_button)

func _load_image_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture != null:
		return texture
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _run_update_flow() -> void:
	_action_button.disabled = true
	_set_status("Checking for updates...", "Contacting release manifest.", 0.08)
	var manifest_urls: Array[String] = _get_manifest_urls()
	if manifest_urls.is_empty():
		_fail("Launcher manifest URL is not configured. Set launcher/manifest_url before export.")
		return
	var manifest_result: Dictionary = {}
	var last_manifest_error: String = ""
	for manifest_url in manifest_urls:
		for attempt in range(HTTP_ATTEMPTS_PER_URL):
			_set_status("Checking for updates...", "Contacting %s (attempt %d/%d)" % [_short_url_for_status(manifest_url), attempt + 1, HTTP_ATTEMPTS_PER_URL], 0.08)
			manifest_result = await _http_get_json(manifest_url, "manifest")
			if bool(manifest_result.get("ok", false)):
				break
			last_manifest_error = str(manifest_result.get("error", "Could not fetch update manifest."))
			if not bool(manifest_result.get("retryable", true)):
				break
			await get_tree().create_timer(0.45 + float(attempt) * 0.65).timeout
		if bool(manifest_result.get("ok", false)):
			break
	if not bool(manifest_result.get("ok", false)):
		_fail(last_manifest_error if not last_manifest_error.is_empty() else "Could not fetch update manifest.")
		return
	var manifest: Dictionary = manifest_result.get("data", {}) if manifest_result.get("data", {}) is Dictionary else {}
	_current_manifest = manifest
	var launcher_update_result: Dictionary = await _maybe_self_update_launcher(manifest)
	if bool(launcher_update_result.get("restarting", false)):
		return
	if not bool(launcher_update_result.get("ok", true)):
		_fail(str(launcher_update_result.get("error", "Launcher self-update failed.")))
		return
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	var zip_url: String = str(manifest.get("zip_url", "")).strip_edges()
	if remote_version.is_empty() or zip_url.is_empty():
		_fail("Manifest is missing version or zip_url.")
		return
	var local_version: String = _get_local_version()
	var local_build: int = _get_local_game_build()
	if not _is_remote_manifest_newer(manifest, local_version, local_build) and _is_game_install_usable(manifest):
		_set_status("Game is up to date.", "Version %s build %d is ready." % [local_version, local_build], 1.0)
		_action_button.disabled = false
		_launch_game()
		return
	_set_status("Updating game...", "Installing version %s." % remote_version, 0.14)
	var update_result: Dictionary = await _download_and_install(manifest)
	if not bool(update_result.get("ok", false)):
		_fail(str(update_result.get("error", "Update failed.")))
		return
	_write_local_version(manifest)
	_set_status("Update complete.", "Launching version %s." % remote_version, 1.0)
	_action_button.disabled = false
	_launch_game()

func _download_and_install(manifest: Dictionary) -> Dictionary:
	var expected_hash: String = str(manifest.get("sha256", "")).strip_edges().to_lower()
	var urls: Array[String] = _get_download_urls(manifest, "zip_url", PackedStringArray(["mirrors", "zip_mirrors", "download_mirrors"]))
	if urls.is_empty():
		return {"ok": false, "error": "zip_url is empty."}
	_delete_recursive_absolute(_staging_dir)
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	DirAccess.make_dir_recursive_absolute(_staging_dir)
	var zip_name: String = "game_%s.zip" % _hash_suffix(expected_hash)
	var zip_path: String = _temp_dir.path_join(zip_name)
	var download_result: Dictionary = await _download_file_from_urls(urls, zip_path, "game build", expected_hash)
	if not bool(download_result.get("ok", false)):
		return download_result
	_set_status("Extracting update...", "Unpacking game files.", 0.82)
	var extract_result: Dictionary = _extract_zip_to_directory(zip_path, _staging_dir)
	if not bool(extract_result.get("ok", false)):
		return extract_result
	var validate_result: Dictionary = _validate_game_install_directory(_staging_dir, manifest)
	if not bool(validate_result.get("ok", false)):
		return validate_result
	_set_status("Installing update...", "Replacing local game build.", 0.92)
	_delete_recursive_absolute(_game_backup_dir)
	var had_previous_install: bool = DirAccess.dir_exists_absolute(_game_dir)
	if had_previous_install:
		var backup_error: Error = DirAccess.rename_absolute(_game_dir, _game_backup_dir)
		if backup_error != OK:
			return {"ok": false, "error": "Could not preserve the previous game build: %s" % error_string(backup_error)}
	var rename_error: Error = DirAccess.rename_absolute(_staging_dir, _game_dir)
	if rename_error != OK:
		if had_previous_install:
			DirAccess.rename_absolute(_game_backup_dir, _game_dir)
		return {"ok": false, "error": "Could not install update: %s" % error_string(rename_error)}
	var installed_validate_result: Dictionary = _validate_game_install_directory(_game_dir, manifest)
	if not bool(installed_validate_result.get("ok", false)):
		_delete_recursive_absolute(_game_dir)
		if had_previous_install:
			DirAccess.rename_absolute(_game_backup_dir, _game_dir)
		return installed_validate_result
	_delete_recursive_absolute(_game_backup_dir)
	_delete_recursive_absolute(_temp_dir)
	return {"ok": true}

func _maybe_self_update_launcher(manifest: Dictionary) -> Dictionary:
	var launcher_manifest: Dictionary = manifest.get("launcher", {}) if manifest.get("launcher", {}) is Dictionary else {}
	if launcher_manifest.is_empty():
		return {"ok": true}
	var remote_build: int = int(launcher_manifest.get("build", 0))
	var local_build: int = _get_local_launcher_build()
	if remote_build <= local_build:
		return {"ok": true}
	var urls: Array[String] = _get_download_urls(launcher_manifest, "zip_url", PackedStringArray(["mirrors", "zip_mirrors", "download_mirrors"]))
	if urls.is_empty():
		return {"ok": false, "error": "Launcher update is missing zip_url."}
	var expected_hash: String = str(launcher_manifest.get("sha256", "")).strip_edges().to_lower()
	_set_status("Updating launcher...", "A newer launcher build is available.", 0.2)
	_delete_recursive_absolute(_launcher_staging_dir)
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	DirAccess.make_dir_recursive_absolute(_launcher_staging_dir)
	var zip_name: String = "launcher_%s.zip" % _hash_suffix(expected_hash)
	var zip_path: String = _temp_dir.path_join(zip_name)
	var download_result: Dictionary = await _download_file_from_urls(urls, zip_path, "launcher", expected_hash)
	if not bool(download_result.get("ok", false)):
		return download_result
	var extract_result: Dictionary = _extract_zip_to_directory(zip_path, _launcher_staging_dir)
	if not bool(extract_result.get("ok", false)):
		return extract_result
	var validate_result: Dictionary = _validate_launcher_install_directory(_launcher_staging_dir)
	if not bool(validate_result.get("ok", false)):
		return validate_result
	var bat_result: Dictionary = _write_and_run_self_update_script()
	if not bool(bat_result.get("ok", false)):
		return bat_result
	_set_status("Restarting launcher...", "Applying launcher update.", 1.0)
	get_tree().quit()
	return {"ok": true, "restarting": true}

func _write_and_run_self_update_script() -> Dictionary:
	var launcher_exe: String = OS.get_executable_path()
	if launcher_exe.strip_edges().is_empty() or not FileAccess.file_exists(launcher_exe):
		return {"ok": false, "error": "Cannot locate running launcher executable."}
	var launcher_dir: String = launcher_exe.get_base_dir()
	var bat_path: String = _temp_dir.path_join("apply_launcher_update.bat")
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	var bat := FileAccess.open(bat_path, FileAccess.WRITE)
	if bat == null:
		return {"ok": false, "error": "Could not write launcher self-update script."}
	bat.store_string("@echo off\r\n")
	bat.store_string("setlocal\r\n")
	bat.store_string("timeout /t 2 /nobreak >nul\r\n")
	bat.store_string("xcopy /E /Y /I \"%s\\*\" \"%s\\\" >nul\r\n" % [_windows_path(_launcher_staging_dir), _windows_path(launcher_dir)])
	bat.store_string("start \"\" \"%s\"\r\n" % _windows_path(launcher_exe))
	bat.store_string("exit /b 0\r\n")
	bat.close()
	var pid: int = OS.create_process("cmd.exe", PackedStringArray(["/C", _windows_path(bat_path)]), false)
	if pid <= 0:
		return {"ok": false, "error": "Could not start launcher self-update helper."}
	return {"ok": true}

func _download_file_from_urls(urls: Array[String], destination_path: String, label: String, expected_hash: String = "") -> Dictionary:
	var last_error: String = ""
	for url in urls:
		for attempt in range(DOWNLOAD_ATTEMPTS_PER_URL):
			if FileAccess.file_exists(destination_path):
				DirAccess.remove_absolute(destination_path)
			_set_status("Downloading update...", "Downloading %s from %s (attempt %d/%d, resumable)" % [label, _short_url_for_status(url), attempt + 1, DOWNLOAD_ATTEMPTS_PER_URL], -1.0)
			var result: Dictionary = await _download_file_resumable(url, destination_path, label)
			if bool(result.get("ok", false)) and not expected_hash.is_empty():
				var actual_hash: String = _sha256_file(destination_path)
				if actual_hash != expected_hash:
					var part_path: String = "%s.part" % destination_path
					if FileAccess.file_exists(part_path):
						DirAccess.remove_absolute(part_path)
					if FileAccess.file_exists(destination_path):
						DirAccess.remove_absolute(destination_path)
					result = {
						"ok": false,
						"error": "%s hash mismatch.\nExpected: %s\nActual: %s\nURL: %s" % [
							label.capitalize(),
							expected_hash,
							actual_hash,
							url
						]
					}
			if bool(result.get("ok", false)):
				return result
			last_error = str(result.get("error", "Download failed."))
			if not bool(result.get("retryable", true)):
				break
			await get_tree().create_timer(0.7 + float(attempt) * 0.8).timeout
	return {"ok": false, "error": last_error if not last_error.is_empty() else "All download mirrors failed."}

func _download_file_resumable(url: String, destination_path: String, label: String) -> Dictionary:
	var part_path: String = "%s.part" % destination_path
	DirAccess.make_dir_recursive_absolute(destination_path.get_base_dir())
	var downloaded: int = _file_size(part_path)
	var total_size: int = -1
	var range_supported: bool = true
	while true:
		var chunk_end: int = downloaded + DOWNLOAD_CHUNK_BYTES - 1
		var headers := PackedStringArray([
			"Accept: application/octet-stream",
			"Range: bytes=%d-%d" % [downloaded, chunk_end]
		])
		_set_download_progress(downloaded, total_size, label)
		var result: Dictionary = await _http_get_bytes(url, headers, "download chunk")
		if not bool(result.get("ok", false)):
			return result
		var status: int = int(result.get("status", 0))
		var body: PackedByteArray = result.get("body", PackedByteArray())
		var response_headers: PackedStringArray = result.get("headers", PackedStringArray())
		if status == 206:
			total_size = _extract_total_size_from_content_range(response_headers, total_size)
		elif status == 200 and downloaded == 0:
			range_supported = false
			total_size = _extract_content_length(response_headers, body.size())
		else:
			return {"ok": false, "error": "Server did not continue resumable download: status=%d" % status}
		if body.is_empty():
			return {"ok": false, "error": "Download returned an empty chunk."}
		var write_result: Dictionary = _append_bytes_to_file(part_path, body)
		if not bool(write_result.get("ok", false)):
			return write_result
		downloaded += body.size()
		_set_download_progress(downloaded, total_size, label)
		if not range_supported:
			break
		if total_size > 0 and downloaded >= total_size:
			break
		if body.size() < DOWNLOAD_CHUNK_BYTES and total_size <= 0:
			break
	var rename_error: Error = DirAccess.rename_absolute(part_path, destination_path)
	if rename_error != OK:
		return {"ok": false, "error": "Could not finalize download: %s" % error_string(rename_error)}
	return {"ok": true}

func _http_get_bytes(url: String, headers: PackedStringArray, label: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = DOWNLOAD_TIMEOUT_SECONDS
	add_child(request)
	_active_download_request = request
	var error: Error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_active_download_request = null
		request.queue_free()
		return {"ok": false, "error": "Could not start %s: %s" % [label, error_string(error)]}
	var result: Array = await request.request_completed
	_active_download_request = null
	request.queue_free()
	var transport: int = int(result[0])
	var status: int = int(result[1])
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {
			"ok": false,
			"error": "%s failed: result=%d status=%d" % [label, transport, status],
			"status": status,
			"retryable": _is_retryable_http_failure(transport, status)
		}
	return {
		"ok": true,
		"status": status,
		"headers": result[2] as PackedStringArray,
		"body": result[3] as PackedByteArray
	}

func _set_download_progress(downloaded: int, total_size: int, label: String) -> void:
	if total_size > 0:
		_set_progress(float(downloaded) / float(total_size), "Downloading %s %.1f / %.1f MB" % [
			label,
			float(downloaded) / 1048576.0,
			float(total_size) / 1048576.0
		])
	else:
		_set_progress(-1.0, "Downloading %s %.1f MB" % [label, float(downloaded) / 1048576.0])

func _append_bytes_to_file(path: String, bytes: PackedByteArray) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = null
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open partial download for writing."}
	file.seek_end()
	file.store_buffer(bytes)
	file.close()
	return {"ok": true}

func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = int(file.get_length())
	file.close()
	return size

func _extract_total_size_from_content_range(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-range:"):
			continue
		var slash_index: int = clean_header.find("/")
		if slash_index < 0:
			return fallback
		var total_text: String = clean_header.substr(slash_index + 1).strip_edges()
		if total_text.is_valid_int():
			return int(total_text)
	return fallback

func _extract_content_length(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-length:"):
			continue
		var length_text: String = clean_header.substr(clean_header.find(":") + 1).strip_edges()
		if length_text.is_valid_int():
			return int(length_text)
	return fallback

func _hash_suffix(expected_hash: String) -> String:
	var clean_hash: String = expected_hash.strip_edges().to_lower()
	if clean_hash.length() >= 12:
		return clean_hash.substr(0, 12)
	return "current"

func _http_get_json(url: String, label: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(request)
	var error: Error = request.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "Could not start %s request: %s" % [label, error_string(error)]}
	var result: Array = await request.request_completed
	request.queue_free()
	var transport: int = int(result[0])
	var status: int = int(result[1])
	var body: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {
			"ok": false,
			"error": "%s request failed: result=%d status=%d" % [label, transport, status],
			"status": status,
			"retryable": _is_retryable_http_failure(transport, status)
		}
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "%s response was not a JSON object." % label}
	return {"ok": true, "data": parsed}

func _is_retryable_http_failure(transport: int, status: int) -> bool:
	if transport != HTTPRequest.RESULT_SUCCESS:
		return true
	return status == 408 or status == 409 or status == 425 or status == 429 or status >= 500

func _download_file(url: String, destination_path: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = DOWNLOAD_TIMEOUT_SECONDS
	request.download_file = destination_path
	add_child(request)
	_active_download_request = request
	var error: Error = request.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if error != OK:
		_active_download_request = null
		request.queue_free()
		return {"ok": false, "error": "Could not start download: %s" % error_string(error)}
	var result: Array = await request.request_completed
	_active_download_request = null
	request.queue_free()
	var transport: int = int(result[0])
	var status: int = int(result[1])
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {"ok": false, "error": "Download failed: result=%d status=%d" % [transport, status]}
	if not FileAccess.file_exists(destination_path):
		return {"ok": false, "error": "Download finished but file is missing."}
	return {"ok": true}

func _extract_zip_to_directory(zip_path: String, target_dir: String) -> Dictionary:
	if OS.get_name() == "Windows":
		var windows_result: Dictionary = _extract_zip_to_directory_windows(zip_path, target_dir)
		if bool(windows_result.get("ok", false)):
			return windows_result
	var reader := ZIPReader.new()
	var open_error: Error = reader.open(zip_path)
	if open_error != OK:
		return {"ok": false, "error": "Could not open update zip: %s" % error_string(open_error)}
	for packed_path in reader.get_files():
		var clean_path: String = str(packed_path).replace("\\", "/").strip_edges()
		if clean_path.is_empty() or clean_path.ends_with("/"):
			continue
		if clean_path.begins_with("/") or clean_path.contains("../"):
			reader.close()
			return {"ok": false, "error": "Unsafe path in update zip: %s" % clean_path}
		var output_path: String = target_dir.path_join(clean_path)
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var bytes: PackedByteArray = reader.read_file(clean_path)
		if bytes.is_empty():
			reader.close()
			return {"ok": false, "error": "Could not extract %s: empty data from zip." % clean_path}
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			reader.close()
			return {"ok": false, "error": "Could not write extracted file: %s" % clean_path}
		file.store_buffer(bytes)
		file.close()
	reader.close()
	return {"ok": true}

func _extract_zip_to_directory_windows(zip_path: String, target_dir: String) -> Dictionary:
	_delete_recursive_absolute(target_dir)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var global_zip: String = _windows_path(zip_path)
	var global_target: String = _windows_path(target_dir)
	var ps_script: String = "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force" % [
		global_zip.replace("'", "''"),
		global_target.replace("'", "''")
	]
	var output: Array = []
	var exit_code: int = OS.execute("powershell.exe", PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-Command",
		ps_script
	]), output, true, false)
	if exit_code == 0:
		return {"ok": true}
	var tar_output: Array = []
	var tar_code: int = OS.execute("tar.exe", PackedStringArray([
		"-xf",
		global_zip,
		"-C",
		global_target
	]), tar_output, true, false)
	if tar_code == 0:
		return {"ok": true}
	return {
		"ok": false,
		"error": "Could not extract update zip with Windows tools.\nPowerShell exit=%d: %s\nTar exit=%d: %s" % [
			exit_code,
			"\n".join(output),
			tar_code,
			"\n".join(tar_output)
		]
	}

func _launch_game() -> void:
	var candidates := _get_game_executable_candidates(_current_manifest)
	var missing: Array[String] = []
	for executable_path in candidates:
		if not FileAccess.file_exists(executable_path):
			missing.append(executable_path)
			continue
		var file_size: int = _get_file_size(executable_path)
		if file_size < MIN_GAME_EXECUTABLE_BYTES:
			missing.append("%s (%d bytes)" % [executable_path, file_size])
			continue
		var pid: int = OS.create_process(executable_path, PackedStringArray(), false)
		if pid > 0:
			get_tree().quit()
			return
		var cmd_pid: int = _launch_game_via_cmd(executable_path)
		if cmd_pid > 0:
			get_tree().quit()
			return
	_fail("Could not launch game executable.\nTried: %s\nInstall folder: %s" % [
		", ".join(candidates) if not candidates.is_empty() else ", ".join(missing),
		_game_dir
	])

func _get_manifest_url() -> String:
	return _get_project_setting_string("launcher/manifest_url", DEFAULT_MANIFEST_URL).strip_edges()

func _get_manifest_urls() -> Array[String]:
	var urls: Array[String] = []
	var primary_url: String = _get_manifest_url()
	if not primary_url.is_empty():
		urls.append(primary_url)
	if ProjectSettings.has_setting("launcher/manifest_fallback_urls"):
		var fallback_urls: Variant = ProjectSettings.get_setting("launcher/manifest_fallback_urls", PackedStringArray())
		if fallback_urls is PackedStringArray or fallback_urls is Array:
			for url_variant in fallback_urls:
				var fallback_url: String = str(url_variant).strip_edges()
				if fallback_url.is_empty() or urls.has(fallback_url):
					continue
				urls.append(fallback_url)
	return urls

func _get_download_urls(manifest: Dictionary, primary_key: String, mirror_keys: PackedStringArray) -> Array[String]:
	var urls: Array[String] = []
	var primary_url: String = str(manifest.get(primary_key, "")).strip_edges()
	if not primary_url.is_empty():
		urls.append(primary_url)
	for mirror_key in mirror_keys:
		var mirrors: Variant = manifest.get(str(mirror_key), [])
		if not (mirrors is Array):
			continue
		for mirror_variant in mirrors:
			var mirror_url: String = str(mirror_variant).strip_edges()
			if mirror_url.is_empty() or urls.has(mirror_url):
				continue
			urls.append(mirror_url)
	return urls

func _get_local_launcher_build() -> int:
	if ProjectSettings.has_setting("launcher/build"):
		return int(ProjectSettings.get_setting("launcher/build", LAUNCHER_BUILD))
	return LAUNCHER_BUILD

func _short_url_for_status(url: String) -> String:
	var clean_url: String = url.strip_edges()
	var scheme_end: int = clean_url.find("://")
	var host_start: int = scheme_end + 3 if scheme_end >= 0 else 0
	var slash_index: int = clean_url.find("/", host_start)
	return clean_url if slash_index < 0 else clean_url.substr(0, slash_index)

func _get_install_root() -> String:
	var local_app_data: String = OS.get_environment("LOCALAPPDATA").strip_edges()
	if local_app_data.is_empty():
		local_app_data = OS.get_user_data_dir().get_base_dir()
	var folder_name: String = _get_project_setting_string("launcher/install_folder_name", "Bobux")
	return local_app_data.path_join(folder_name)

func _get_game_executable_path(manifest: Dictionary) -> String:
	var exe_name: String = str(manifest.get("executable", "")).strip_edges()
	if exe_name.is_empty():
		exe_name = _get_project_setting_string("launcher/game_executable", "Bobux.exe")
	return _game_dir.path_join(exe_name)

func _get_game_executable_candidates(manifest: Dictionary) -> Array[String]:
	return _get_game_executable_candidates_for_directory(_game_dir, manifest)

func _get_game_executable_candidate_names(manifest: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var primary_name: String = str(manifest.get("executable", "")).strip_edges()
	if not primary_name.is_empty():
		names.append(primary_name)
	var compat: Variant = manifest.get("compat_executables", [])
	if compat is Array:
		for raw_name in compat:
			var compat_name: String = str(raw_name).strip_edges()
			if not compat_name.is_empty() and not names.has(compat_name):
				names.append(compat_name)
	var configured_name: String = _get_project_setting_string("launcher/game_executable", "Bobux.exe").strip_edges()
	if not configured_name.is_empty() and not names.has(configured_name):
		names.append(configured_name)
	for fallback_name in ["Bobux.exe", "Game.exe"]:
		if not names.has(fallback_name):
			names.append(fallback_name)
	return names

func _launch_game_via_cmd(executable_path: String) -> int:
	if OS.get_name() != "Windows":
		return 0
	var helper_path := _temp_dir.path_join("launch_game.cmd")
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	var helper := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null:
		return 0
	helper.store_string("@echo off\r\n")
	helper.store_string("cd /d \"%s\"\r\n" % _windows_path(executable_path.get_base_dir()))
	helper.store_string("start \"\" \"%s\"\r\n" % _windows_path(executable_path))
	helper.store_string("exit /b 0\r\n")
	helper.close()
	return OS.create_process("cmd.exe", PackedStringArray(["/C", _windows_path(helper_path)]), false)

func _is_game_install_usable(manifest: Dictionary) -> bool:
	var executable_path: String = _find_usable_game_executable(_game_dir, manifest)
	if executable_path.is_empty():
		_delete_broken_game_install_if_needed()
		return false
	if bool(manifest.get("embedded_pck", false)):
		return true
	var pck_path: String = "%s.pck" % executable_path.get_basename()
	if FileAccess.file_exists(pck_path):
		return true
	for fallback_name in ["Bobux.pck", "Game.pck"]:
		if FileAccess.file_exists(_game_dir.path_join(fallback_name)):
			return true
	return false

func _validate_game_install_directory(directory: String, manifest: Dictionary) -> Dictionary:
	var executable_path: String = _find_usable_game_executable(directory, manifest)
	if executable_path.is_empty():
		return {
			"ok": false,
			"error": "Downloaded build is invalid: game executable is missing or empty after extraction."
		}
	if bool(manifest.get("embedded_pck", false)):
		return {"ok": true}
	var pck_path: String = "%s.pck" % executable_path.get_basename()
	if FileAccess.file_exists(pck_path) and _get_file_size(pck_path) > MIN_GAME_EXECUTABLE_BYTES:
		return {"ok": true}
	for fallback_name in ["Bobux.pck", "Game.pck"]:
		var fallback_pck: String = directory.path_join(fallback_name)
		if FileAccess.file_exists(fallback_pck) and _get_file_size(fallback_pck) > MIN_GAME_EXECUTABLE_BYTES:
			return {"ok": true}
	return {"ok": false, "error": "Downloaded build is missing its .pck data file."}

func _validate_launcher_install_directory(directory: String) -> Dictionary:
	for executable_name in ["BobuxLauncher.exe", OS.get_executable_path().get_file()]:
		var clean_name: String = executable_name.strip_edges()
		if clean_name.is_empty():
			continue
		var executable_path: String = directory.path_join(clean_name)
		if FileAccess.file_exists(executable_path) and _get_file_size(executable_path) >= MIN_GAME_EXECUTABLE_BYTES:
			return {"ok": true}
	return {
		"ok": false,
		"error": "Downloaded launcher update is invalid: BobuxLauncher.exe is missing or empty."
	}

func _find_usable_game_executable(directory: String, manifest: Dictionary) -> String:
	for executable_path in _get_game_executable_candidates_for_directory(directory, manifest):
		if not FileAccess.file_exists(executable_path):
			continue
		if _get_file_size(executable_path) >= MIN_GAME_EXECUTABLE_BYTES:
			return executable_path
	return ""

func _get_game_executable_candidates_for_directory(directory: String, manifest: Dictionary) -> Array[String]:
	var names: Array[String] = _get_game_executable_candidate_names(manifest)
	var paths: Array[String] = []
	for exe_name in names:
		var clean_name: String = exe_name.replace("\\", "/").get_file()
		if clean_name.is_empty():
			continue
		var path: String = directory.path_join(clean_name)
		if not paths.has(path):
			paths.append(path)
	return paths

func _delete_broken_game_install_if_needed() -> void:
	if _game_dir.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(_game_dir):
		return
	var has_broken_executable := false
	for executable_path in _get_game_executable_candidates(_current_manifest):
		if FileAccess.file_exists(executable_path) and _get_file_size(executable_path) < MIN_GAME_EXECUTABLE_BYTES:
			has_broken_executable = true
			break
	if has_broken_executable:
		_delete_recursive_absolute(_game_dir)

func _get_local_version() -> String:
	var parsed := _read_local_version_record()
	if parsed.is_empty():
		return "0.0.0"
	return str(parsed.get("version", "0.0.0")).strip_edges()

func _get_local_game_build() -> int:
	var parsed := _read_local_version_record()
	if parsed.is_empty():
		return 0
	return int(parsed.get("build", 0))

func _read_local_version_record() -> Dictionary:
	for version_path in [_game_dir.path_join(LOCAL_VERSION_FILE), _install_root.path_join(LOCAL_VERSION_FILE)]:
		if not FileAccess.file_exists(version_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(version_path))
		if parsed is Dictionary:
			return parsed as Dictionary
	return {}

func _write_local_version(manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_game_dir)
	var payload := JSON.stringify({
		"version": str(manifest.get("version", "")).strip_edges(),
		"build": int(manifest.get("build", 0)),
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}, "\t")
	for version_path in [_game_dir.path_join(LOCAL_VERSION_FILE), _install_root.path_join(LOCAL_VERSION_FILE)]:
		DirAccess.make_dir_recursive_absolute(version_path.get_base_dir())
		var file := FileAccess.open(version_path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(payload)
		file.close()
	var written := _read_local_version_record()
	if int(written.get("build", 0)) != int(manifest.get("build", 0)):
		push_warning("[BobuxLauncher] Failed to persist local game build marker.")

func _is_remote_newer(remote_version: String, local_version: String) -> bool:
	var remote_parts: PackedStringArray = remote_version.split(".")
	var local_parts: PackedStringArray = local_version.split(".")
	var count: int = maxi(remote_parts.size(), local_parts.size())
	for i in range(count):
		var remote_num: int = int(remote_parts[i]) if i < remote_parts.size() else 0
		var local_num: int = int(local_parts[i]) if i < local_parts.size() else 0
		if remote_num != local_num:
			return remote_num > local_num
	return false

func _is_remote_manifest_newer(manifest: Dictionary, local_version: String, local_build: int) -> bool:
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	if _is_remote_newer(remote_version, local_version):
		return true
	if _is_remote_newer(local_version, remote_version):
		return false
	return int(manifest.get("build", 0)) > local_build

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(65536))
	file.close()
	return context.finish().hex_encode()

func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = int(file.get_length())
	file.close()
	return length

func _delete_recursive_absolute(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	var dir := DirAccess.open(path)
	if dir == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_delete_recursive_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _get_project_setting_string(setting_name: String, fallback: String) -> String:
	if ProjectSettings.has_setting(setting_name):
		return str(ProjectSettings.get_setting(setting_name, fallback))
	return fallback

func _windows_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("/", "\\")

func _set_status(title: String, detail: String, progress: float) -> void:
	_status_label.text = title
	_detail_label.text = detail
	_set_progress(progress, detail)

func _set_progress(progress: float, detail: String = "") -> void:
	if not detail.is_empty():
		_detail_label.text = detail
	if progress < 0.0:
		_progress_bar.value = fmod(Time.get_ticks_msec() / 18.0, 100.0)
	else:
		_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0

func _fail(message: String) -> void:
	_set_status("Launcher error", message, 0.0)
	_action_button.disabled = true
