extends SceneTree

const MANIFEST_URL := "http://109.71.245.162/launcher/latest.json"
const API_HEALTH_URL := "http://109.71.245.162/api/health"
const RANGE_BYTES := 512 * 1024
const EXPECTED_GAME_BUILD := 39
const EXPECTED_LAUNCHER_BUILD := 13

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest_result := await _request_bytes(MANIFEST_URL, PackedStringArray(["Accept: application/json"]))
	if not bool(manifest_result.get("ok", false)):
		push_error("[validate_remote_launcher_manifest] Manifest request failed: %s" % str(manifest_result.get("error", "")))
		quit(1)
		return
	var manifest_json: Variant = JSON.parse_string((manifest_result.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not (manifest_json is Dictionary):
		push_error("[validate_remote_launcher_manifest] Manifest response is not a dictionary")
		quit(1)
		return
	var manifest: Dictionary = manifest_json
	var launcher: Dictionary = manifest.get("launcher", {}) if manifest.get("launcher", {}) is Dictionary else {}
	if int(manifest.get("build", 0)) != EXPECTED_GAME_BUILD:
		push_error("[validate_remote_launcher_manifest] Game build should be %d" % EXPECTED_GAME_BUILD)
		quit(1)
		return
	if int(launcher.get("build", 0)) != EXPECTED_LAUNCHER_BUILD:
		push_error("[validate_remote_launcher_manifest] Launcher build should be %d" % EXPECTED_LAUNCHER_BUILD)
		quit(1)
		return
	var zip_url: String = str(manifest.get("zip_url", "")).strip_edges()
	if zip_url.is_empty():
		push_error("[validate_remote_launcher_manifest] Game zip_url is empty")
		quit(1)
		return
	var range_result := await _request_bytes(zip_url, PackedStringArray([
		"Accept: application/octet-stream",
		"Range: bytes=0-%d" % (RANGE_BYTES - 1)
	]))
	if not bool(range_result.get("ok", false)):
		push_error("[validate_remote_launcher_manifest] Range request failed: %s" % str(range_result.get("error", "")))
		quit(1)
		return
	if int(range_result.get("status", 0)) != 206:
		push_error("[validate_remote_launcher_manifest] Expected HTTP 206, got %d" % int(range_result.get("status", 0)))
		quit(1)
		return
	var body: PackedByteArray = range_result.get("body", PackedByteArray())
	if body.size() != RANGE_BYTES:
		push_error("[validate_remote_launcher_manifest] Expected %d bytes, got %d" % [RANGE_BYTES, body.size()])
		quit(1)
		return
	var health_result := await _request_bytes(API_HEALTH_URL, PackedStringArray(["Accept: application/json"]))
	if not bool(health_result.get("ok", false)):
		push_error("[validate_remote_launcher_manifest] API health request failed: %s" % str(health_result.get("error", "")))
		quit(1)
		return
	var health_json: Variant = JSON.parse_string((health_result.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not (health_json is Dictionary) or not bool((health_json as Dictionary).get("ok", false)):
		push_error("[validate_remote_launcher_manifest] /api/health is not the Bobux API")
		quit(1)
		return
	print("[validate_remote_launcher_manifest] Manifest, download path, and Bobux API OK")
	quit(0)

func _request_bytes(url: String, headers: PackedStringArray) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 60.0
	root.add_child(request)
	var start_error: Error = request.request(url, headers, HTTPClient.METHOD_GET)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "error": error_string(start_error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport: int = int(completed[0])
	var status: int = int(completed[1])
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {"ok": false, "error": "transport=%d status=%d" % [transport, status], "status": status}
	return {
		"ok": true,
		"status": status,
		"headers": completed[2] as PackedStringArray,
		"body": completed[3] as PackedByteArray,
	}
