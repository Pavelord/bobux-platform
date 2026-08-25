extends SceneTree

# Active Godot dedicated WebSocket entry point.
#
# The REST/profile/storage backend lives in services/bobux_api/server.js, but
# the live multiplayer process on the VPS still starts this script through PM2.
# This file talks to Bobux REST compatibility endpoints under /api/rest/v1 for
# active room registry updates.

# PRACTICE SCREENSHOT: Dedicated server bootstrap - starts the authoritative Godot WebSocket process for live game rooms.
const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"
const HEARTBEAT_INTERVAL_SECONDS: float = 5.0
const ACTIVE_SERVERS_ENDPOINT: String = "/rest/v1/active_servers"
const HEARTBEAT_STATUS_PATH: String = "res://heartbeat_status.json"
const CLOSE_REQUEST_NOTIFICATION: int = 1006
const PREDELETE_NOTIFICATION: int = 1
const NETWORK_PROTOCOL_VERSION: String = "vps-ws-2026-05-28-1"

var _heartbeat_timer: Timer = null
var _heartbeat_in_flight: bool = false
var _known_server_keys: Dictionary = {}
var _reusable_http_request: HTTPRequest = null
var _server_port: int = 7860
var _server_map_name: String = ""
var _api_url: String = ""
var _service_key: String = ""
var _server_heartbeat_token: String = ""
var _public_server_ws_url: String = ""
var _position_probe_timer: Timer = null
var _heartbeat_status_file_path: String = ""
var _shutdown_cleanup_started: bool = false
var _build_commit: String = ""
var _build_branch: String = ""
var _service_name: String = ""

func _get_autoload(name: String) -> Node:
	return root.get_node_or_null(NodePath(name))

func _initialize() -> void:
	_server_port = _get_server_port()
	_server_map_name = _get_server_map_name()
	_heartbeat_status_file_path = ProjectSettings.globalize_path(HEARTBEAT_STATUS_PATH)
	_build_commit = OS.get_environment("BOBUX_GIT_COMMIT").strip_edges()
	_build_branch = OS.get_environment("BOBUX_GIT_BRANCH").strip_edges()
	_service_name = OS.get_environment("BOBUX_SERVICE_NAME").strip_edges()
	_api_url = OS.get_environment("BOBUX_API_URL").strip_edges().trim_suffix("/")
	if _api_url.is_empty():
		var bobux_rest_url: String = OS.get_environment("BOBUX_REST_BASE_URL").strip_edges().trim_suffix("/")
		if bobux_rest_url.ends_with("/rest/v1"):
			_api_url = bobux_rest_url.trim_suffix("/rest/v1")
	_service_key = OS.get_environment("BOBUX_SERVICE_KEY").strip_edges()
	_server_heartbeat_token = OS.get_environment("BOBUX_SERVER_HEARTBEAT_TOKEN").strip_edges()
	_public_server_ws_url = _resolve_public_server_ws_url()
	var game_state: Node = _get_autoload("GameState")
	if game_state != null and game_state.has_method("configure_dedicated_server"):
		game_state.call("configure_dedicated_server", _server_port, _server_map_name)
	var network_manager: Node = _get_autoload("NetworkManager")
	if network_manager != null:
		if network_manager.has_signal("hosting_started") and not network_manager.hosting_started.is_connected(_on_hosting_started):
			network_manager.hosting_started.connect(_on_hosting_started)
		if network_manager.has_signal("connection_failed") and not network_manager.connection_failed.is_connected(_on_connection_failed):
			network_manager.connection_failed.connect(_on_connection_failed)
		if network_manager.has_signal("room_emptied") and not network_manager.room_emptied.is_connected(_on_room_emptied):
			network_manager.room_emptied.connect(_on_room_emptied)
	change_scene_to_file(MAIN_SCENE_PATH)
	_write_heartbeat_status({
		"configured": not _api_url.is_empty() and not _service_key.is_empty(),
		"api_url_configured": not _api_url.is_empty(),
		"service_key_configured": not _service_key.is_empty(),
		"public_server_ws_url": _public_server_ws_url,
		"server_port": _server_port,
		"server_map_name": _server_map_name,
		"stage": "bootstrapping",
		"last_result": "pending"
	})
	print("[DedicatedServer] Bootstrapping authoritative WebSocket server on port %d for map '%s'." % [_server_port, _server_map_name])
	print("[DedicatedServer] Build metadata: protocol=%s commit=%s branch=%s service=%s" % [
		NETWORK_PROTOCOL_VERSION,
		_build_commit if not _build_commit.is_empty() else "unknown",
		_build_branch if not _build_branch.is_empty() else "unknown",
		_service_name if not _service_name.is_empty() else "unknown"
	])

func _on_hosting_started(port: int, _external_ip: String, _upnp_mapped: bool) -> void:
	print("[DedicatedServer] WebSocket authoritative server is live on port %d." % port)
	_write_heartbeat_status({
		"configured": not _api_url.is_empty() and not _service_key.is_empty(),
		"api_url_configured": not _api_url.is_empty(),
		"service_key_configured": not _service_key.is_empty(),
		"public_server_ws_url": _public_server_ws_url,
		"server_port": _server_port,
		"server_map_name": _server_map_name,
		"stage": "live",
		"last_result": "pending"
	})
	_ensure_heartbeat_timer()
	_ensure_position_probe_timer()
	if _heartbeat_timer != null and _heartbeat_timer.is_stopped():
		_heartbeat_timer.start()
	if _position_probe_timer != null and _position_probe_timer.is_stopped():
		_position_probe_timer.start()
	call_deferred("_run_server_heartbeat_async")

func _on_connection_failed(message: String) -> void:
	_cleanup_http_resources()
	push_error("[DedicatedServer] Failed to boot: %s" % message)
	quit(1)

func _on_room_emptied(server_key: String, room_id: String) -> void:
	var clean_server_key: String = server_key.strip_edges()
	if clean_server_key.is_empty():
		clean_server_key = "hub:%s" % room_id.strip_edges()
	if clean_server_key.is_empty() or _api_url.is_empty() or _service_key.is_empty():
		return
	_known_server_keys.erase(clean_server_key)
	# FIX D (Death Loop): Immediately purge the ghost room from the room registry.
	# Try async first; if it fails, fall back to a synchronous blocking DELETE
	# to guarantee the row is removed and prevent "already in game" rejoin errors.
	_delete_room_heartbeat_with_sync_fallback(clean_server_key)

func _delete_room_heartbeat_with_sync_fallback(server_key: String) -> void:
	var clean_server_key: String = server_key.strip_edges()
	if clean_server_key.is_empty():
		return
	var delete_result: Dictionary = await _delete_active_server_async(clean_server_key, false)
	var ok: bool = bool(delete_result.get("ok", false))
	if not ok:
		# Synchronous fallback — blocks the thread but guarantees delivery
		push_warning("[DedicatedServer] Async DELETE failed for '%s', attempting sync fallback..." % clean_server_key)
		_delete_active_server_sync(clean_server_key)
	_write_heartbeat_status({
		"configured": not _api_url.is_empty() and not _service_key.is_empty(),
		"api_url_configured": not _api_url.is_empty(),
		"service_key_configured": not _service_key.is_empty(),
		"public_server_ws_url": _public_server_ws_url,
		"server_port": _server_port,
		"server_map_name": _server_map_name,
		"stage": "live",
		"last_attempt_at": Time.get_datetime_string_from_system(true, true),
		"last_result": "delete_ok" if ok else "delete_sync_fallback",
		"last_status": int(delete_result.get("status", 0)),
		"last_error": str(delete_result.get("error", "")).strip_edges(),
		"tracked_rooms": _known_server_keys.keys().size()
	})
	if not ok:
		push_warning("[DedicatedServer] Immediate room cleanup used sync fallback for '%s'" % clean_server_key)

# Synchronous blocking DELETE using raw HTTPClient — guarantees the row
# is removed from the room registry even during process exit or network instability.
func _delete_active_server_sync(server_key: String) -> void:
	var clean_server_key: String = server_key.strip_edges()
	if clean_server_key.is_empty():
		return
	var endpoint: String = "%s%s?server_key=eq.%s" % [_api_url, ACTIVE_SERVERS_ENDPOINT, clean_server_key.uri_encode()]
	var parsed_url := endpoint.split("://")
	if parsed_url.size() < 2:
		return
	var scheme := parsed_url[0]
	var host_path := parsed_url[1]
	var slash_idx := host_path.find("/")
	var host := host_path.substr(0, slash_idx) if slash_idx > 0 else host_path
	var path := host_path.substr(slash_idx) if slash_idx > 0 else "/"
	var port := 443 if scheme == "https" else 80
	var client := HTTPClient.new()
	var tls_options: TLSOptions = TLSOptions.client() if scheme == "https" else null
	var err := client.connect_to_host(host, port, tls_options)
	if err == OK:
		while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
			client.poll()
			OS.delay_msec(10)
		if client.get_status() == HTTPClient.STATUS_CONNECTED:
			var headers := PackedStringArray([
				"Accept: application/json",
				"Content-Type: application/json",
				"apikey: %s" % _service_key
			])
			if _should_send_service_role_authorization_header():
				headers.append("Authorization: Bearer %s" % _service_key)
			client.request(HTTPClient.METHOD_DELETE, path, headers, "")
			while client.get_status() == HTTPClient.STATUS_REQUESTING:
				client.poll()
				OS.delay_msec(10)
		client.close()
	print("[DedicatedServer] Sync DELETE completed for server_key='%s'" % clean_server_key)

func _ensure_heartbeat_timer() -> void:
	if _heartbeat_timer != null or root == null:
		return
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.name = "ServerHeartbeatTimer"
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SECONDS
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	root.add_child(_heartbeat_timer)

func _ensure_position_probe_timer() -> void:
	if OS.get_environment("CODEX_TEST_LOG_PLAYER_POSITIONS").strip_edges().to_lower() != "true":
		return
	if _position_probe_timer != null or root == null:
		return
	_position_probe_timer = Timer.new()
	_position_probe_timer.name = "ServerPositionProbeTimer"
	_position_probe_timer.wait_time = 0.5
	_position_probe_timer.one_shot = false
	_position_probe_timer.timeout.connect(_on_position_probe_timeout)
	root.add_child(_position_probe_timer)

func _on_heartbeat_timeout() -> void:
	call_deferred("_run_server_heartbeat_async")

func _on_position_probe_timeout() -> void:
	var scene: Node = current_scene
	if scene == null:
		return
	var players_root: Node = scene.get_node_or_null("World/Players")
	if players_root == null:
		return
	var samples: Array[String] = []
	for child in players_root.get_children():
		if not (child is Node3D):
			continue
		var node_3d: Node3D = child as Node3D
		samples.append("%s=%s(auth=%d)" % [node_3d.name, str(node_3d.global_position), int(node_3d.get_multiplayer_authority())])
	if not samples.is_empty():
		print("[DedicatedServer][Probe] %s" % ", ".join(samples))

# PRACTICE SCREENSHOT: Server heartbeat - batches all active room snapshots into one API update every few seconds.
# Batch all room upserts into a single HTTP POST instead of sequential per-room
# awaits. Reuse one HTTPRequest node per heartbeat cycle to reduce GC pressure.
func _run_server_heartbeat_async() -> void:
	if _heartbeat_in_flight:
		return
	if _api_url.is_empty() or _service_key.is_empty():
		_write_heartbeat_status({
			"configured": false,
			"api_url_configured": not _api_url.is_empty(),
			"service_key_configured": not _service_key.is_empty(),
			"public_server_ws_url": _public_server_ws_url,
			"server_port": _server_port,
			"server_map_name": _server_map_name,
			"stage": "live",
			"last_attempt_at": Time.get_datetime_string_from_system(true, true),
			"last_result": "skipped_missing_config",
			"tracked_rooms": _known_server_keys.keys().size()
		})
		return
	var network_manager: Node = _get_autoload("NetworkManager")
	if network_manager == null or not network_manager.has_method("get_active_room_snapshots"):
		_write_heartbeat_status({
			"configured": true,
			"api_url_configured": true,
			"service_key_configured": true,
			"public_server_ws_url": _public_server_ws_url,
			"server_port": _server_port,
			"server_map_name": _server_map_name,
			"stage": "live",
			"last_attempt_at": Time.get_datetime_string_from_system(true, true),
			"last_result": "skipped_missing_network_manager",
			"tracked_rooms": _known_server_keys.keys().size()
		})
		return
	_heartbeat_in_flight = true
	var active_keys: Dictionary = {}
	var room_snapshots: Array = network_manager.call("get_active_room_snapshots")
	var batch_payloads: Array = []
	for snapshot_variant in room_snapshots:
		if not (snapshot_variant is Dictionary):
			continue
		var snapshot: Dictionary = snapshot_variant
		var room_id: String = str(snapshot.get("room_id", "")).strip_edges()
		var owner_user_id: String = str(snapshot.get("owner_user_id", "")).strip_edges()
		if room_id.is_empty() or owner_user_id.is_empty():
			continue
		var payload: Dictionary = _build_active_server_payload(snapshot)
		var server_key: String = str(payload.get("server_key", "")).strip_edges()
		if server_key.is_empty():
			continue
		batch_payloads.append(payload)
		active_keys[server_key] = true
	# Single batch upsert for all rooms
	if not batch_payloads.is_empty():
		var batch_result: Dictionary = await _batch_upsert_active_servers_async(batch_payloads, true)
		_write_heartbeat_status({
			"configured": true,
			"api_url_configured": true,
			"service_key_configured": true,
			"public_server_ws_url": _public_server_ws_url,
			"server_port": _server_port,
			"server_map_name": _server_map_name,
			"stage": "live",
			"last_attempt_at": Time.get_datetime_string_from_system(true, true),
			"last_result": "upsert_ok" if bool(batch_result.get("ok", false)) else "upsert_failed",
			"last_status": int(batch_result.get("status", 0)),
			"last_error": str(batch_result.get("error", "")).strip_edges(),
			"tracked_rooms": batch_payloads.size(),
			"tracked_server_keys": active_keys.keys(),
			"sample_room_ids": batch_payloads.map(func(item): return str((item as Dictionary).get("room_id", "")).strip_edges())
		})
		if not bool(batch_result.get("ok", false)):
			push_warning("[DedicatedServer] Batch heartbeat upsert failed: %s" % str(batch_result.get("error", batch_result.get("raw", "unknown error"))))
	else:
		_write_heartbeat_status({
			"configured": true,
			"api_url_configured": true,
			"service_key_configured": true,
			"public_server_ws_url": _public_server_ws_url,
			"server_port": _server_port,
			"server_map_name": _server_map_name,
			"stage": "live",
			"last_attempt_at": Time.get_datetime_string_from_system(true, true),
			"last_result": "no_rooms_to_sync",
			"tracked_rooms": 0,
			"tracked_server_keys": []
		})
	# Clean up stale keys that are no longer actively tracked
	var stale_keys: Array = []
	for known_key_variant in _known_server_keys.keys():
		var known_key: String = str(known_key_variant).strip_edges()
		if known_key.is_empty() or active_keys.has(known_key):
			continue
		stale_keys.append(known_key)
	if not stale_keys.is_empty():
		for stale_key in stale_keys:
			var delete_result: Dictionary = await _delete_active_server_async(stale_key, true)
			if not bool(delete_result.get("ok", false)):
				push_warning("[DedicatedServer] Failed to clear stale room heartbeat '%s': %s" % [stale_key, str(delete_result.get("error", delete_result.get("raw", "unknown error")))])
	_known_server_keys = active_keys
	_heartbeat_in_flight = false

# PRACTICE SCREENSHOT: Active server payload - the data stored in the active_servers collection for lobby discovery.
func _build_active_server_payload(snapshot: Dictionary) -> Dictionary:
	var now_unix: int = int(Time.get_unix_time_from_system())
	var server_key: String = "hub:%s" % str(snapshot.get("room_id", "")).strip_edges()
	var public_host: String = _extract_host_from_ws_url(_public_server_ws_url)
	var public_port: int = _extract_port_from_ws_url(_public_server_ws_url)
	return {
		"server_key": server_key,
		"room_id": str(snapshot.get("room_id", "")).strip_edges(),
		"player_id": str(snapshot.get("owner_peer_id", 1)).strip_edges(),
		"is_host": true,
		"transport": "websocket",
		"server_url": _public_server_ws_url,
		"ip": public_host,
		"port": public_port,
		"map_id": str(snapshot.get("map_id", _server_map_name)).strip_edges(),
		"map_name": str(snapshot.get("map_name", _server_map_name)).strip_edges(),
		"cloud_version_id": str(snapshot.get("cloud_version_id", "")).strip_edges(),
		"host_user_id": str(snapshot.get("owner_user_id", "")).strip_edges(),
		"host_username": str(snapshot.get("owner_username", "Dedicated Server")).strip_edges(),
		"member_user_ids": snapshot.get("member_user_ids", []),
		"players_count": int(snapshot.get("players_count", 0)),
		"max_players": int(snapshot.get("max_players", 10)),
		"status": "active",
		"last_seen": now_unix,
		"last_seen_at": Time.get_datetime_string_from_system(true, true),
		"last_heartbeat": Time.get_datetime_string_from_system(true, true)
	}

func _upsert_active_server_async(payload: Dictionary) -> Dictionary:
	var endpoint: String = "%s%s?on_conflict=server_key" % [_api_url, ACTIVE_SERVERS_ENDPOINT]
	return await _request_registry_json(endpoint, HTTPClient.METHOD_POST, [payload], PackedStringArray([
		"Prefer: resolution=merge-duplicates,return=minimal"
	]))

# Batch upsert sends all room payloads in a single HTTP POST.
func _batch_upsert_active_servers_async(payloads: Array, reuse_request: bool = false) -> Dictionary:
	if payloads.is_empty():
		return {"ok": true}
	var endpoint: String = "%s%s?on_conflict=server_key" % [_api_url, ACTIVE_SERVERS_ENDPOINT]
	var batch_result: Dictionary = await _request_registry_json(endpoint, HTTPClient.METHOD_POST, payloads, PackedStringArray([
		"Prefer: resolution=merge-duplicates,return=minimal"
	]), reuse_request)
	if bool(batch_result.get("ok", false)) or not _should_retry_active_server_upsert_without_member_user_ids(batch_result):
		return batch_result
	var stripped_payloads: Array = []
	for payload_variant in payloads:
		if not (payload_variant is Dictionary):
			continue
		var stripped_payload: Dictionary = (payload_variant as Dictionary).duplicate(true)
		stripped_payload.erase("member_user_ids")
		stripped_payloads.append(stripped_payload)
	if stripped_payloads.is_empty():
		return batch_result
	push_warning("[DedicatedServer] active_servers registry is missing member_user_ids; retrying heartbeat upsert without that field.")
	return await _request_registry_json(endpoint, HTTPClient.METHOD_POST, stripped_payloads, PackedStringArray([
		"Prefer: resolution=merge-duplicates,return=minimal"
	]), reuse_request)

func _delete_active_server_async(server_key: String, reuse_request: bool = false) -> Dictionary:
	var endpoint: String = "%s%s?server_key=eq.%s" % [_api_url, ACTIVE_SERVERS_ENDPOINT, server_key.uri_encode()]
	return await _request_registry_json(endpoint, HTTPClient.METHOD_DELETE, null, PackedStringArray([
		"Prefer: return=minimal"
	]), reuse_request)

func _should_retry_active_server_upsert_without_member_user_ids(result: Dictionary) -> bool:
	var error_text: String = "%s %s" % [str(result.get("error", "")), str(result.get("raw", ""))]
	var lowered_error: String = error_text.to_lower()
	return lowered_error.contains("member_user_ids") and (lowered_error.contains("column") or lowered_error.contains("schema cache"))

# Reuse a single HTTPRequest node for heartbeat requests instead of creating and
# freeing one per cycle.
func _ensure_reusable_http_request() -> HTTPRequest:
	if _reusable_http_request != null and is_instance_valid(_reusable_http_request):
		return _reusable_http_request
	if root == null:
		return null
	_reusable_http_request = HTTPRequest.new()
	_reusable_http_request.name = "ReusableHeartbeatHTTP"
	root.add_child(_reusable_http_request)
	return _reusable_http_request

func _request_registry_json(url: String, method: HTTPClient.Method, body: Variant, extra_headers: PackedStringArray = PackedStringArray(), reuse_request: bool = false) -> Dictionary:
	if root == null:
		return {"ok": false, "error": "SceneTree root is unavailable."}
	var request: HTTPRequest = _ensure_reusable_http_request() if reuse_request else HTTPRequest.new()
	if request == null:
		return {"ok": false, "error": "HTTPRequest is unavailable."}
	if not reuse_request:
		root.add_child(request)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"apikey: %s" % _service_key
	])
	if _should_send_service_role_authorization_header():
		headers.append("Authorization: Bearer %s" % _service_key)
	for header in extra_headers:
		headers.append(str(header))
	if not _server_heartbeat_token.is_empty():
		headers.append("X-Bobux-Server-Token: %s" % _server_heartbeat_token)
	var body_string: String = "" if body == null else JSON.stringify(body)
	var request_error: Error = request.request(url, headers, method, body_string)
	if request_error != OK:
		if not reuse_request:
			request.queue_free()
		return {"ok": false, "error": error_string(request_error)}
	var response: Array = await request.request_completed
	if not reuse_request:
		request.queue_free()
	var status_code: int = int(response[1]) if response.size() > 1 else 0
	var raw_body: String = ""
	if response.size() > 3 and response[3] is PackedByteArray:
		raw_body = (response[3] as PackedByteArray).get_string_from_utf8()
	var parsed_body: Variant = {}
	if not raw_body.is_empty():
		var parsed_variant: Variant = JSON.parse_string(raw_body)
		parsed_body = parsed_variant if parsed_variant != null else raw_body
	return {
		"ok": status_code >= 200 and status_code < 300,
		"status": status_code,
		"data": parsed_body,
		"raw": raw_body,
		"error": "" if status_code >= 200 and status_code < 300 else raw_body
	}

func _should_send_service_role_authorization_header() -> bool:
	var clean_key: String = _service_key.strip_edges()
	if clean_key.is_empty():
		return false
	return not clean_key.begins_with("sb_")

func _cleanup_http_resources() -> void:
	if _heartbeat_timer != null and is_instance_valid(_heartbeat_timer):
		_heartbeat_timer.stop()
	if _position_probe_timer != null and is_instance_valid(_position_probe_timer):
		_position_probe_timer.stop()
	if _reusable_http_request != null and is_instance_valid(_reusable_http_request):
		_reusable_http_request.free()
	_reusable_http_request = null

func _write_heartbeat_status(payload: Dictionary) -> void:
	if _heartbeat_status_file_path.is_empty():
		return
	var enriched_payload: Dictionary = payload.duplicate(true)
	enriched_payload["network_protocol_version"] = NETWORK_PROTOCOL_VERSION
	enriched_payload["build_commit"] = _build_commit
	enriched_payload["build_branch"] = _build_branch
	enriched_payload["service_name"] = _service_name
	var file := FileAccess.open(_heartbeat_status_file_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(enriched_payload, "\t"))
	file.close()

func _notification(what: int) -> void:
	if what == CLOSE_REQUEST_NOTIFICATION:
		if not _shutdown_cleanup_started:
			_cleanup_all_active_servers_and_quit()
	elif what == PREDELETE_NOTIFICATION:
		if not _shutdown_cleanup_started:
			_cleanup_all_active_servers_sync()
		_cleanup_http_resources()

func _cleanup_all_active_servers_and_quit() -> void:
	_cleanup_all_active_servers_sync()
	quit()

func _collect_active_server_keys_for_cleanup() -> Array[String]:
	var server_keys: Array[String] = []
	var seen: Dictionary = {}
	for known_key_variant in _known_server_keys.keys():
		var known_key: String = str(known_key_variant).strip_edges()
		if known_key.is_empty() or seen.has(known_key):
			continue
		seen[known_key] = true
		server_keys.append(known_key)
	var network_manager: Node = _get_autoload("NetworkManager")
	if network_manager != null and network_manager.has_method("get_active_room_snapshots"):
		var room_snapshots: Array = network_manager.call("get_active_room_snapshots")
		for snapshot_variant in room_snapshots:
			if not (snapshot_variant is Dictionary):
				continue
			var room_id: String = str((snapshot_variant as Dictionary).get("room_id", "")).strip_edges()
			if room_id.is_empty():
				continue
			var server_key: String = "hub:%s" % room_id
			if seen.has(server_key):
				continue
			seen[server_key] = true
			server_keys.append(server_key)
	return server_keys

func _cleanup_all_active_servers_sync() -> void:
	if _shutdown_cleanup_started:
		return
	_shutdown_cleanup_started = true
	var server_keys: Array[String] = _collect_active_server_keys_for_cleanup()
	if server_keys.is_empty() or _api_url.is_empty() or _service_key.is_empty():
		return
	
	print("[DedicatedServer] Shutting down. Cleaning up %d active rooms..." % server_keys.size())
	for server_key in server_keys:
		var endpoint: String = "%s%s?server_key=eq.%s" % [_api_url, ACTIVE_SERVERS_ENDPOINT, str(server_key).uri_encode()]
		# Synchronous blocking HTTPClient to ensure delivery before process exits
		var client := HTTPClient.new()
		var parsed_url := endpoint.split("://")
		if parsed_url.size() < 2:
			continue
		var scheme := parsed_url[0]
		var host_path := parsed_url[1]
		var slash_idx := host_path.find("/")
		var host := host_path.substr(0, slash_idx) if slash_idx > 0 else host_path
		var path := host_path.substr(slash_idx) if slash_idx > 0 else "/"
		
		var port := 443 if scheme == "https" else 80
		var tls_options: TLSOptions = TLSOptions.client() if scheme == "https" else null
		var err := client.connect_to_host(host, port, tls_options)
		if err == OK:
			while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
				client.poll()
				OS.delay_msec(10)
			
			if client.get_status() == HTTPClient.STATUS_CONNECTED:
				var headers := PackedStringArray([
					"Accept: application/json",
					"Content-Type: application/json",
					"apikey: %s" % _service_key
				])
				if _should_send_service_role_authorization_header():
					headers.append("Authorization: Bearer %s" % _service_key)
				client.request(HTTPClient.METHOD_DELETE, path, headers, "")
				while client.get_status() == HTTPClient.STATUS_REQUESTING:
					client.poll()
					OS.delay_msec(10)
			client.close()
	
	OS.delay_msec(50)

func _resolve_public_server_ws_url() -> String:
	var env_url: String = OS.get_environment("PUBLIC_SERVER_WS_URL").strip_edges()
	if not env_url.is_empty():
		return env_url
	var project_url: String = str(ProjectSettings.get_setting("application/config/dedicated_server_ws_url", "")).strip_edges()
	if not project_url.is_empty():
		return project_url
	return "ws://109.71.245.162/ws"

func _extract_host_from_ws_url(ws_url: String) -> String:
	var clean_url: String = ws_url.strip_edges()
	clean_url = clean_url.trim_prefix("ws://")
	clean_url = clean_url.trim_prefix("wss://")
	var slash_index: int = clean_url.find("/")
	if slash_index >= 0:
		clean_url = clean_url.substr(0, slash_index)
	var colon_index: int = clean_url.find(":")
	if colon_index >= 0:
		clean_url = clean_url.substr(0, colon_index)
	return clean_url

func _extract_port_from_ws_url(ws_url: String) -> int:
	var clean_url: String = ws_url.strip_edges()
	var secure: bool = clean_url.begins_with("wss://")
	clean_url = clean_url.trim_prefix("ws://")
	clean_url = clean_url.trim_prefix("wss://")
	var slash_index: int = clean_url.find("/")
	if slash_index >= 0:
		clean_url = clean_url.substr(0, slash_index)
	var colon_index: int = clean_url.find(":")
	if colon_index >= 0:
		return int(clean_url.substr(colon_index + 1))
	return 443 if secure else 80

func _get_server_port() -> int:
	var raw: String = OS.get_environment("GODOT_SERVER_PORT").strip_edges()
	if not raw.is_empty():
		return int(raw)
	return 7860

func _get_server_map_name() -> String:
	var raw: String = OS.get_environment("GODOT_SERVER_MAP").strip_edges()
	return raw
