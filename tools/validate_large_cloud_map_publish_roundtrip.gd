extends SceneTree

const LARGE_BLOCK_COUNT := 7200

var _cloud: Node = null
var _session: Node = null
var _map_id := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cloud = root.get_node_or_null("CloudAPI")
	_session = root.get_node_or_null("UserSession")
	if _cloud == null or _session == null:
		push_error("[validate_large_cloud_map_publish_roundtrip] Required autoloads are missing")
		quit(1)
		return

	var username := str(_session.get("username")).strip_edges()
	if username.is_empty():
		username = str(_cloud.call("get_current_username")).strip_edges()
	var auth_result: Dictionary = await _cloud.call("authenticate_or_create_profile", username)
	if not bool(auth_result.get("ok", false)):
		push_error("[validate_large_cloud_map_publish_roundtrip] Auth failed: %s" % str(auth_result.get("error", "unknown")))
		quit(1)
		return

	var suffix := str(Time.get_ticks_msec())
	var map_name := "__large_publish_contract_%s" % suffix
	var blocks: Array = []
	blocks.resize(LARGE_BLOCK_COUNT)
	for index in range(LARGE_BLOCK_COUNT):
		blocks[index] = {
			"id": index,
			"name": "LargePublishBlock_%06d_payload_padding_for_external_storage_contract" % index,
			"position": [float(index % 120) * 4.0, float(index / 120), float(index % 17) * 2.0],
			"rotation": [0.0, float(index % 360), 0.0],
			"size": [4.0, 1.0, 4.0],
			"color": [0.125, 0.5, 0.875, 1.0] if index == LARGE_BLOCK_COUNT - 1 else [0.8, 0.2, 0.35, 1.0],
			"shape": "Box",
			"material": "Plastic",
			"can_collide": true
		}
	var map_data := {
		"format": "bobux_map_v2",
		"blocks": blocks,
		"settings": {"probe": "large-cloud-map-roundtrip", "sentinel": 8675309}
	}
	var encoded_size := JSON.stringify(map_data).to_utf8_buffer().size()
	if encoded_size <= 1024 * 1024:
		push_error("[validate_large_cloud_map_publish_roundtrip] Probe payload is unexpectedly small: %d" % encoded_size)
		quit(1)
		return

	var upload_result: Dictionary = await _cloud.call("upload_map_to_cloud", map_data, map_name, {
		"owner_name": username,
		"description": "Automated external map-data roundtrip probe",
		"is_published": false
	})
	_map_id = _extract_id(upload_result.get("data", {}))
	if not bool(upload_result.get("ok", false)) or _map_id.is_empty():
		push_error("[validate_large_cloud_map_publish_roundtrip] Upload failed: %s" % str(upload_result.get("error", "unknown")))
		await _cleanup()
		quit(1)
		return

	var download_result: Dictionary = await _cloud.call("download_map_from_cloud", _map_id)
	var record := _extract_record(download_result.get("data", null))
	var hydrated: Dictionary = record.get("data", {}) if record.get("data", {}) is Dictionary else {}
	var downloaded_blocks: Array = hydrated.get("blocks", []) if hydrated.get("blocks", []) is Array else []
	var settings: Dictionary = hydrated.get("settings", {}) if hydrated.get("settings", {}) is Dictionary else {}
	var sentinel_block: Dictionary = downloaded_blocks.back() if not downloaded_blocks.is_empty() and downloaded_blocks.back() is Dictionary else {}
	var sentinel_color: Array = sentinel_block.get("color", []) if sentinel_block.get("color", []) is Array else []
	var color_ok := sentinel_color.size() == 4 and is_equal_approx(float(sentinel_color[0]), 0.125) and is_equal_approx(float(sentinel_color[2]), 0.875)
	var ok := (
		bool(download_result.get("ok", false))
		and downloaded_blocks.size() == LARGE_BLOCK_COUNT
		and int(settings.get("sentinel", 0)) == 8675309
		and color_ok
	)
	print(
		"[validate_large_cloud_map_publish_roundtrip] ok=%s bytes=%d blocks=%d id=%s"
		% [str(ok), encoded_size, downloaded_blocks.size(), _map_id]
	)
	await _cleanup()
	quit(0 if ok else 1)


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
