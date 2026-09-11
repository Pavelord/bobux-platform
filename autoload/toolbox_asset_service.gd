extends Node

signal catalog_changed
signal download_finished(asset_id: String, ok: bool)
const INDEX_URL := "http://109.71.245.162/toolbox/index.json"
const CACHE := "user://toolbox_cache"
const INDEX_PATH := CACHE + "/index.json"
var _refreshing := false
var _refreshed := false
var _retry_after := 0
var _in_flight: Dictionary = {}
var last_error := ""

func refresh_catalog() -> bool:
	if _refreshed: return FileAccess.file_exists(INDEX_PATH)
	if Time.get_ticks_msec() < _retry_after: return FileAccess.file_exists(INDEX_PATH)
	if _refreshing:
		await catalog_changed
		return FileAccess.file_exists(INDEX_PATH)
	_refreshing = true
	DirAccess.make_dir_recursive_absolute(CACHE)
	var payload := await _request(INDEX_URL, 12 * 1024 * 1024)
	var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8()) if not payload.is_empty() else null
	var ok: bool = parsed is Dictionary and parsed.get("version") == 2 and parsed.get("assets") is Array
	if ok:
		for entry in parsed.assets:
			if not entry is Dictionary or entry.get("license") != "CC0" or not _valid_hash(str(entry.get("package_sha256", ""))) or not _safe_relative(str(entry.get("entrypoint", ""))):
				ok = false
				break
	if ok:
		var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
		file.store_buffer(payload)
		file.close()
		preload("res://addons/roblox_studio/toolbox_asset_library.gd").reload()
	_refreshing = false
	_refreshed = ok
	_retry_after = Time.get_ticks_msec() + 10000 if not ok else 0
	catalog_changed.emit()
	return ok

func ensure_asset(asset_id: String) -> bool:
	var library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
	var entry: Dictionary = library.get_asset(asset_id)
	if entry.is_empty(): return false
	if not entry.has("asset_url"): return FileAccess.file_exists(entry.file)
	var destination := asset_folder(entry)
	if FileAccess.file_exists(destination + "/.verified") and FileAccess.file_exists(destination + "/" + entry.entrypoint): return true
	if _in_flight.has(asset_id):
		while _in_flight.has(asset_id): await download_finished
		return FileAccess.file_exists(destination + "/.verified")
	_in_flight[asset_id] = true
	var bytes := await _request(entry.asset_url, 32 * 1024 * 1024)
	var ok: bool = not bytes.is_empty() and _sha256(bytes) == entry.package_sha256
	if ok:
		DirAccess.make_dir_recursive_absolute(destination)
		var archive_path := destination + "/download.zip"
		var output := FileAccess.open(archive_path, FileAccess.WRITE)
		output.store_buffer(bytes)
		output.close()
		var zip := ZIPReader.new()
		ok = zip.open(archive_path) == OK
		if ok:
			for info in entry.get("package_files", []):
				if not _safe_relative(str(info.path)) or not zip.file_exists(info.path): ok = false; break
				var data := zip.read_file(info.path)
				if data.size() != int(info.size) or _sha256(data) != info.sha256: ok = false; break
				var file_path: String = destination + "/" + info.path
				DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
				var file := FileAccess.open(file_path, FileAccess.WRITE)
				if file == null: ok = false; break
				file.store_buffer(data)
				file.close()
			zip.close()
		DirAccess.remove_absolute(archive_path)
		if ok:
			FileAccess.open(destination + "/.verified", FileAccess.WRITE).store_string(entry.package_sha256)
	if not ok: last_error = "Не удалось загрузить или проверить ассет: " + asset_id
	_in_flight.erase(asset_id)
	download_finished.emit(asset_id, ok)
	return ok

func ensure_thumbnail(entry: Dictionary) -> String:
	var checksum := str(entry.get("thumbnail_sha256", ""))
	if not _valid_hash(checksum): return str(entry.get("thumbnail", ""))
	var path := CACHE + "/thumbnails/" + checksum + ".png"
	if FileAccess.file_exists(path): return path
	var bytes := await _request(str(entry.get("thumbnail_url", "")), 2 * 1024 * 1024)
	if bytes.is_empty() or _sha256(bytes) != checksum: return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
	return path

func _request(url: String, limit: int) -> PackedByteArray:
	if not url.begins_with("http://109.71.245.162/toolbox/"): return PackedByteArray()
	var request := HTTPRequest.new()
	request.timeout = 20
	request.body_size_limit = limit
	add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return PackedByteArray()
	var reply: Array = await request.request_completed
	request.queue_free()
	if int(reply[0]) != HTTPRequest.RESULT_SUCCESS or int(reply[1]) != 200:
		last_error = "Сервер библиотеки недоступен (HTTP %d)." % int(reply[1])
		return PackedByteArray()
	return reply[3]

static func asset_folder(entry: Dictionary) -> String:
	return CACHE + "/assets/" + str(entry.get("package_sha256", ""))

static func _sha256(bytes: PackedByteArray) -> String:
	var hash_ := HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256)
	hash_.update(bytes)
	return hash_.finish().hex_encode()

static func _valid_hash(value: String) -> bool:
	if value.length() != 64: return false
	for c in value:
		if c not in "0123456789abcdef": return false
	return true

static func _safe_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and ":" not in value and "\\" not in value and ".." not in value.split("/")
