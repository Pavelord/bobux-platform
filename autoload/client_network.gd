extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connected_to_server(peer_id: int)
signal connection_failed(message: String)
signal hosting_started(port: int, external_ip: String, upnp_mapped: bool)
signal chat_message_received(text: String, sender_id: int)
signal transport_status_changed(message: String)
signal transport_progress_updated(phase: String, progress: float)
signal room_summaries_updated(summaries: Array)
signal room_peer_profiles_updated(profiles_by_peer: Dictionary)
signal room_emptied(server_key: String, room_id: String)

# PRACTICE SCREENSHOT: Multiplayer network module - tracks WebSocket state, room membership, reconnects and peer events.
const MAX_CLIENTS: int = 10
const DEFAULT_EXTERNAL_WS_PORT: int = 80
const CONNECTION_TIMEOUT_SECONDS: float = 12.0
const RETRY_DELAY_SECONDS: float = 1.35
const RETRY_BACKOFF_MULTIPLIER: float = 1.8
const MAX_CONNECT_ATTEMPTS: int = 4
const SERVER_WAKEUP_TIMEOUT_SECONDS: float = 70.0
const SERVER_WAKEUP_POLL_SECONDS: float = 3.0
const SERVER_WAKEUP_HTTP_TIMEOUT_SECONDS: float = 8.0
const ROOM_AUTH_TIMEOUT_SECONDS: float = 8.0
const LEAVE_ACK_TIMEOUT_SECONDS: float = 1.5
const JOIN_RATE_LIMIT_MSEC: int = 2000
const JOIN_RATE_LIMIT_MAX_VIOLATIONS: int = 3
const MAX_RPC_PAYLOAD_SIZE: int = 16384
const DEFAULT_WS_PATH: String = "/ws"
const DEFAULT_DEDICATED_WS_URL: String = "ws://109.71.245.162/ws"
const DEFAULT_DEDICATED_HOST: String = "109.71.245.162"
const NETWORK_PROTOCOL_VERSION: String = "vps-ws-2026-05-28-1"
const DEFAULT_ROOM_MAP_NAME: String = "Untitled Experience"
const DEFAULT_ROOM_MAP_ID: String = "untitled"
const MANUAL_NETWORK_POLL_RATE_HZ: float = 90.0
const SERVER_PEER_KEEPALIVE_GRACE_SECONDS: float = 8.0
const GLOBAL_SESSION_LOCK_FRESHNESS_SECONDS: int = 15
const DUPLICATE_SESSION_REJECTION_MESSAGE: String = "Этот аккаунт уже находится в игре."
# Best-effort transport-level WebSocket heartbeat.
# HF Spaces currently regresses when protocol-level ping/pong is enabled:
# the socket disconnects sooner than with pure application-level traffic.
# Keep transport heartbeat disabled here and rely on RPC keepalive instead.
const WS_TRANSPORT_HEARTBEAT_INTERVAL_SECONDS: float = 0.0

var current_port: int = 0
var current_host_ip: String = ""
var last_connection_error: String = ""

var _hosting: bool = false
var _active_room_id: String = ""
var _active_map_name: String = ""
var _active_map_id: String = ""
var _active_cloud_version_id: String = ""
var _current_server_info: Dictionary = {}
var _pending_ws_url: String = ""
var _pending_public_host: String = ""
var _pending_public_port: int = 0
var _pending_attempt: int = 0
var _connected_once_for_attempt: bool = false
var _connect_timeout_timer: Timer = null
var _pending_auth_payload: Dictionary = {}
var _peer_room_ids: Dictionary = {}
var _server_rooms: Dictionary = {}
var _room_join_confirmed: bool = false
var _cached_room_summaries: Array = []
var _cached_room_peer_profiles: Dictionary = {}
var _peer_last_join_msec: Dictionary = {}
var _peer_join_violations: Dictionary = {}
var _pending_server_room_joins: Dictionary = {}
var _explicit_join_rejection_message: String = ""
var _reconcile_timer: Timer = null
var _peer_last_keepalive_msec: Dictionary = {}
var _leave_ack_received: bool = false
var _leave_ack_room_id: String = ""
var _client_attempt_serial: int = 0
var _client_wakeup_serial: int = 0
var _manual_network_poll_accumulator: float = 0.0
var _debug_last_server_poll_log_msec: int = 0

func _multiplayer_api() -> MultiplayerAPI:
	if not is_inside_tree():
		return null
	return get_tree().get_multiplayer()

func _force_disconnect_scene_peer(peer_id: int) -> bool:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or peer_id <= 0:
		return false
	if api.has_method("get_peers") and not api.get_peers().has(peer_id):
		return false
	if api.has_method("disconnect_peer"):
		api.call("disconnect_peer", peer_id)
		return true
	var peer: MultiplayerPeer = api.multiplayer_peer
	if peer != null and peer.has_method("disconnect_peer"):
		peer.call("disconnect_peer", peer_id, true)
		return true
	return false

func get_current_room_id() -> String:
	return _active_room_id

func _refresh_client_peer_room_assignments_from_summaries(summaries: Array) -> void:
	if is_host():
		return
	var updated_assignments: Dictionary = {}
	if not _active_room_id.is_empty():
		updated_assignments[1] = _active_room_id
	var local_peer_id: int = get_unique_id()
	if local_peer_id > 0 and not _active_room_id.is_empty():
		updated_assignments[local_peer_id] = _active_room_id
	for summary_variant in summaries:
		if not (summary_variant is Dictionary):
			continue
		var summary: Dictionary = summary_variant
		var room_id: String = str(summary.get("room_id", "")).strip_edges()
		if room_id.is_empty():
			continue
		for peer_variant in summary.get("peer_ids", []):
			var peer_id: int = int(peer_variant)
			if peer_id > 0:
				updated_assignments[peer_id] = room_id
	_peer_room_ids = updated_assignments

func _find_live_or_pending_peer_by_user_id(user_id: String, exclude_peer_id: int = 0) -> int:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return 0
	for peer_id_variant in _pending_server_room_joins.keys():
		var pending_peer_id: int = int(peer_id_variant)
		if pending_peer_id <= 0 or pending_peer_id == exclude_peer_id:
			continue
		var pending_join: Dictionary = _pending_server_room_joins.get(pending_peer_id, {}) if _pending_server_room_joins.get(pending_peer_id, {}) is Dictionary else {}
		if str(pending_join.get("user_id", "")).strip_edges() == clean_user_id:
			return pending_peer_id
	for room_state_variant in _server_rooms.values():
		if not (room_state_variant is Dictionary):
			continue
		var room_state: Dictionary = room_state_variant
		var owner_peer_id: int = int(room_state.get("owner_peer_id", 0))
		if owner_peer_id > 0 and owner_peer_id != exclude_peer_id and str(room_state.get("owner_user_id", "")).strip_edges() == clean_user_id:
			return owner_peer_id
		var peer_meta: Dictionary = room_state.get("peer_meta", {}) if room_state.get("peer_meta", {}) is Dictionary else {}
		for peer_key_variant in peer_meta.keys():
			var peer_id: int = int(peer_key_variant)
			if peer_id <= 0 or peer_id == exclude_peer_id:
				continue
			var metadata: Dictionary = peer_meta.get(str(peer_id), {}) if peer_meta.get(str(peer_id), {}) is Dictionary else {}
			if str(metadata.get("user_id", "")).strip_edges() == clean_user_id:
				return peer_id
	return 0

func get_peer_room_id(peer_id: int) -> String:
	return str(_peer_room_ids.get(peer_id, "")).strip_edges()

func get_server_room_state(room_id: String) -> Dictionary:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return {}
	var room_state: Dictionary = _server_rooms.get(clean_room_id, {}) if _server_rooms.get(clean_room_id, {}) is Dictionary else {}
	return room_state.duplicate(true)

func are_peers_in_same_room(peer_a: int, peer_b: int) -> bool:
	if peer_a <= 0 or peer_b <= 0:
		return false
	var room_a: String = get_peer_room_id(peer_a)
	var room_b: String = get_peer_room_id(peer_b)
	return not room_a.is_empty() and room_a == room_b

func is_peer_in_same_room(peer_id: int) -> bool:
	var local_peer_id: int = get_unique_id()
	if local_peer_id <= 0:
		return false
	return are_peers_in_same_room(local_peer_id, peer_id)

func get_room_member_peer_ids(room_id: String) -> Array[int]:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty() or not _server_rooms.has(clean_room_id):
		return []
	var room_state: Dictionary = _server_rooms[clean_room_id] if _server_rooms[clean_room_id] is Dictionary else {}
	var peer_ids_variant: Array = room_state.get("peer_ids", []) if room_state.has("peer_ids") else []
	var peer_ids: Array[int] = []
	for peer_variant in peer_ids_variant:
		var peer_id: int = int(peer_variant)
		if peer_id > 0:
			peer_ids.append(peer_id)
	return peer_ids

func get_room_member_user_ids(room_id: String) -> Array[String]:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty() or not _server_rooms.has(clean_room_id):
		return []
	var room_state: Dictionary = _server_rooms[clean_room_id] if _server_rooms[clean_room_id] is Dictionary else {}
	var peer_meta: Dictionary = room_state.get("peer_meta", {}) if room_state.get("peer_meta", {}) is Dictionary else {}
	var user_ids: Array[String] = []
	for peer_id in get_room_member_peer_ids(clean_room_id):
		var metadata: Dictionary = peer_meta.get(str(peer_id), {}) if peer_meta.get(str(peer_id), {}) is Dictionary else {}
		var user_id: String = str(metadata.get("user_id", "")).strip_edges()
		if not user_id.is_empty() and not user_ids.has(user_id):
			user_ids.append(user_id)
	var owner_user_id: String = str(room_state.get("owner_user_id", "")).strip_edges()
	if not owner_user_id.is_empty() and not user_ids.has(owner_user_id):
		user_ids.append(owner_user_id)
	return user_ids

func _is_server_peer_currently_connected(peer_id: int) -> bool:
	if peer_id <= 0:
		return false
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return false
	if peer_id == 1:
		return true
	for live_peer_id_variant in api.get_peers():
		if int(live_peer_id_variant) == peer_id:
			return true
	return false

func record_server_peer_keepalive(peer_id: int) -> void:
	if not is_host() or peer_id <= 0:
		return
	_peer_last_keepalive_msec[peer_id] = Time.get_ticks_msec()

func _server_peer_keepalive_age_msec(peer_id: int, now_msec: int = 0) -> int:
	if peer_id <= 0:
		return 0
	var effective_now_msec: int = now_msec if now_msec > 0 else Time.get_ticks_msec()
	var last_keepalive_msec: int = int(_peer_last_keepalive_msec.get(peer_id, 0))
	if last_keepalive_msec <= 0:
		return 0
	return maxi(effective_now_msec - last_keepalive_msec, 0)

func _find_external_active_session_conflict(user_id: String, requested_room_id: String) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty() or CloudAPI == null:
		return {}
	if not CloudAPI.has_method("find_active_server_for_member_user") or not CloudAPI.has_method("has_server_service_role"):
		return {}
	if not bool(CloudAPI.call("has_server_service_role")):
		return {}
	var current_server_key: String = _build_room_server_key(requested_room_id)
	var result: Dictionary = await CloudAPI.call("find_active_server_for_member_user", clean_user_id, GLOBAL_SESSION_LOCK_FRESHNESS_SECONDS, true)
	if not bool(result.get("ok", false)):
		push_warning("[RoomHub] Global duplicate-session lookup failed for user %s: %s" % [clean_user_id, str(result.get("error", "unknown error"))])
		return {}
	var server_row: Dictionary = result.get("data", {}) if result.get("data", {}) is Dictionary else {}
	var server_key: String = str(server_row.get("server_key", "")).strip_edges()
	if server_key.is_empty() or server_key == current_server_key:
		return {}
	return server_row.duplicate(true)

func _is_server_peer_keepalive_stale(peer_id: int, now_msec: int) -> bool:
	if peer_id <= 0 or peer_id == 1:
		return false
	var last_keepalive_msec: int = int(_peer_last_keepalive_msec.get(peer_id, 0))
	if last_keepalive_msec <= 0:
		return false
	return (now_msec - last_keepalive_msec) >= int(SERVER_PEER_KEEPALIVE_GRACE_SECONDS * 1000.0)

func _reconcile_server_room_members() -> void:
	if not is_host():
		return
	var stale_peer_ids: Array[int] = []
	var affected_rooms: Dictionary = {}
	var now_msec: int = Time.get_ticks_msec()
	for room_key_variant in _server_rooms.keys():
		var room_id: String = str(room_key_variant).strip_edges()
		for peer_id in get_room_member_peer_ids(room_id):
			var transport_live: bool = _is_server_peer_currently_connected(peer_id)
			var keepalive_stale: bool = _is_server_peer_keepalive_stale(peer_id, now_msec)
			if transport_live and not keepalive_stale:
				continue
			if stale_peer_ids.has(peer_id):
				continue
			stale_peer_ids.append(peer_id)
			affected_rooms[room_id] = true
	if not stale_peer_ids.is_empty():
		for stale_peer_id in stale_peer_ids:
			var stale_room_id: String = get_peer_room_id(stale_peer_id)
			if not stale_room_id.is_empty():
				affected_rooms[stale_room_id] = true
			var stale_reason: String = "transport_disconnected"
			var keepalive_age_msec: int = _server_peer_keepalive_age_msec(stale_peer_id, now_msec)
			if keepalive_age_msec >= int(SERVER_PEER_KEEPALIVE_GRACE_SECONDS * 1000.0):
				stale_reason = "keepalive_stalled_%dms" % keepalive_age_msec
			print("[RoomHub] Reaping stale peer %d from room registry (%s)." % [stale_peer_id, stale_reason])
			var pending_data: Dictionary = _pending_server_room_joins.get(stale_peer_id, {}) if _pending_server_room_joins.get(stale_peer_id, {}) is Dictionary else {}
			var pending_room_id: String = str(pending_data.get("room_id", "")).strip_edges()
			_pending_server_room_joins.erase(stale_peer_id)
			_remove_peer_from_room(stale_peer_id)
			_peer_last_join_msec.erase(stale_peer_id)
			_peer_join_violations.erase(stale_peer_id)
			_peer_last_keepalive_msec.erase(stale_peer_id)
			_force_disconnect_scene_peer(stale_peer_id)
			player_disconnected.emit(stale_peer_id)
			if not pending_room_id.is_empty():
				affected_rooms[pending_room_id] = true
				_prune_empty_room_if_orphaned(pending_room_id)
	# Also clean up stale entries in _pending_server_room_joins for peers
	# that disconnected without completing their join handshake.
	var stale_pending_peers: Array[int] = []
	for pending_peer_variant in _pending_server_room_joins.keys():
		var pending_peer_id: int = int(pending_peer_variant)
		if pending_peer_id <= 0:
			continue
		if not _is_server_peer_currently_connected(pending_peer_id) or _is_server_peer_keepalive_stale(pending_peer_id, now_msec):
			stale_pending_peers.append(pending_peer_id)
	for stale_pending_id in stale_pending_peers:
		var pending_reason: String = "transport_disconnected"
		var pending_keepalive_age_msec: int = _server_peer_keepalive_age_msec(stale_pending_id, now_msec)
		if pending_keepalive_age_msec >= int(SERVER_PEER_KEEPALIVE_GRACE_SECONDS * 1000.0):
			pending_reason = "keepalive_stalled_%dms" % pending_keepalive_age_msec
		print("[RoomHub] Reaping stale pending join for peer %d (%s)." % [stale_pending_id, pending_reason])
		var pending_data: Dictionary = _pending_server_room_joins.get(stale_pending_id, {}) if _pending_server_room_joins.get(stale_pending_id, {}) is Dictionary else {}
		var pending_room_id: String = str(pending_data.get("room_id", "")).strip_edges()
		_pending_server_room_joins.erase(stale_pending_id)
		_peer_last_keepalive_msec.erase(stale_pending_id)
		_force_disconnect_scene_peer(stale_pending_id)
		if not pending_room_id.is_empty():
			affected_rooms[pending_room_id] = true
		_prune_empty_room_if_orphaned(pending_room_id)
	if affected_rooms.is_empty():
		return
	for room_id_variant in affected_rooms.keys():
		var affected_room_id: String = str(room_id_variant).strip_edges()
		if affected_room_id.is_empty():
			continue
		_broadcast_room_summaries(affected_room_id)
		_broadcast_room_peer_profiles(affected_room_id)

func _get_reserved_room_ids() -> Array[String]:
	var room_ids: Array[String] = []
	var seen: Dictionary = {}
	for room_key_variant in _server_rooms.keys():
		var room_id: String = str(room_key_variant).strip_edges()
		if room_id.is_empty() or seen.has(room_id):
			continue
		seen[room_id] = true
		room_ids.append(room_id)
	for pending_join_variant in _pending_server_room_joins.values():
		if not (pending_join_variant is Dictionary):
			continue
		var pending_join: Dictionary = pending_join_variant
		var pending_room_id: String = str(pending_join.get("room_id", "")).strip_edges()
		if pending_room_id.is_empty() or seen.has(pending_room_id):
			continue
		seen[pending_room_id] = true
		room_ids.append(pending_room_id)
	return room_ids

func _find_conflicting_process_room_id(_requested_room_id: String) -> String:
	return ""

func _get_primary_reserved_room_id() -> String:
	var configured_room_id: String = str(_current_server_info.get("room_id", "")).strip_edges()
	if not configured_room_id.is_empty():
		for reserved_room_id in _get_reserved_room_ids():
			if reserved_room_id == configured_room_id:
				return reserved_room_id
	var reserved_room_ids: Array[String] = _get_reserved_room_ids()
	return reserved_room_ids[0] if not reserved_room_ids.is_empty() else ""

func get_active_room_snapshots() -> Array[Dictionary]:
	_reconcile_server_room_members()
	var snapshots: Array[Dictionary] = []
	for room_id_variant in _server_rooms.keys():
		var room_id: String = str(room_id_variant).strip_edges()
		if room_id.is_empty():
			continue
		var room_state: Dictionary = _server_rooms.get(room_id, {}) if _server_rooms.get(room_id, {}) is Dictionary else {}
		if room_state.is_empty():
			continue
		var peer_ids: Array[int] = get_room_member_peer_ids(room_id)
		if peer_ids.is_empty():
			continue
		snapshots.append({
			"room_id": room_id,
			"peer_ids": peer_ids,
			"players_count": peer_ids.size(),
			"max_players": int(room_state.get("max_players", MAX_CLIENTS)),
			"owner_peer_id": int(room_state.get("owner_peer_id", peer_ids[0])),
			"owner_user_id": str(room_state.get("owner_user_id", "")).strip_edges(),
			"owner_username": str(room_state.get("owner_username", "Dedicated Server")).strip_edges(),
			"member_user_ids": get_room_member_user_ids(room_id),
			"map_id": str(room_state.get("map_id", _guess_runtime_map_id())).strip_edges(),
			"map_name": _sanitize_room_map_name(str(room_state.get("map_name", _guess_runtime_map_name())).strip_edges(), str(room_state.get("map_id", _guess_runtime_map_id())).strip_edges(), _guess_runtime_map_name()),
			"cloud_version_id": str(room_state.get("cloud_version_id", "")).strip_edges()
		})
	return snapshots

func _build_room_server_key(room_id: String) -> String:
	var clean_room_id: String = room_id.strip_edges()
	return "" if clean_room_id.is_empty() else "hub:%s" % clean_room_id

func _emit_room_emptied_priority(room_id: String) -> void:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return
	room_emptied.emit(_build_room_server_key(clean_room_id), clean_room_id)

func get_cached_room_summaries() -> Array:
	return _cached_room_summaries.duplicate(true)

func get_cached_room_peer_profiles() -> Dictionary:
	return _cached_room_peer_profiles.duplicate(true)

func update_peer_room_profile(peer_id: int, user_id: String, username: String, profile: Dictionary = {}) -> void:
	var clean_room_id: String = get_peer_room_id(peer_id)
	if clean_room_id.is_empty():
		return
	var room_state: Dictionary = _server_rooms.get(clean_room_id, {}) if _server_rooms.get(clean_room_id, {}) is Dictionary else {}
	var peer_meta: Dictionary = room_state.get("peer_meta", {}) if room_state.get("peer_meta", {}) is Dictionary else {}
	var peer_key: String = str(peer_id)
	var current_meta: Dictionary = peer_meta.get(peer_key, {}) if peer_meta.get(peer_key, {}) is Dictionary else {}
	if not user_id.strip_edges().is_empty():
		current_meta["user_id"] = user_id.strip_edges()
	if not username.strip_edges().is_empty():
		current_meta["username"] = username.strip_edges()
	if not profile.is_empty():
		current_meta["profile"] = profile.duplicate(true)
	peer_meta[peer_key] = current_meta
	room_state["peer_meta"] = peer_meta
	if int(room_state.get("owner_peer_id", 0)) == peer_id:
		if not user_id.strip_edges().is_empty():
			room_state["owner_user_id"] = user_id.strip_edges()
		if not username.strip_edges().is_empty():
			room_state["owner_username"] = username.strip_edges()
	_server_rooms[clean_room_id] = room_state
	if is_host():
		_broadcast_room_peer_profiles(clean_room_id)

func _build_room_peer_profile_snapshot(room_id: String) -> Dictionary:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return {}
	var room_state: Dictionary = _server_rooms.get(clean_room_id, {}) if _server_rooms.get(clean_room_id, {}) is Dictionary else {}
	var peer_meta: Dictionary = room_state.get("peer_meta", {}) if room_state.get("peer_meta", {}) is Dictionary else {}
	var snapshot: Dictionary = {}
	for peer_id in get_room_member_peer_ids(clean_room_id):
		var metadata: Dictionary = peer_meta.get(str(peer_id), {}) if peer_meta.get(str(peer_id), {}) is Dictionary else {}
		snapshot[str(peer_id)] = {
			"room_id": clean_room_id,
			"user_id": str(metadata.get("user_id", "")).strip_edges(),
			"username": str(metadata.get("username", "")).strip_edges(),
			"profile": metadata.get("profile", {}).duplicate(true) if metadata.get("profile", {}) is Dictionary else {}
		}
	return snapshot

func _encode_auth_payload(payload: Dictionary) -> PackedByteArray:
	return JSON.stringify(payload).to_utf8_buffer()

func _decode_auth_payload(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

func _ready() -> void:
	set_process(true)
	var api: MultiplayerAPI = _multiplayer_api()
	if api != null:
		api.peer_connected.connect(_on_peer_connected)
		api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected_to_server)
	api.connection_failed.connect(_on_connection_failed_native)
	api.server_disconnected.connect(_on_server_disconnected_native)
	_ensure_timers()

func _configure_websocket_transport_heartbeat(peer_id: int = 0) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not (api.multiplayer_peer is WebSocketMultiplayerPeer):
		return
	var ws_multiplayer: WebSocketMultiplayerPeer = api.multiplayer_peer as WebSocketMultiplayerPeer
	var target_peer_id: int = peer_id
	if target_peer_id <= 0:
		target_peer_id = 1 if not api.is_server() else 0
	if api.is_server():
		if target_peer_id <= 0:
			return
		var server_socket: WebSocketPeer = ws_multiplayer.get_peer(target_peer_id)
		if server_socket == null:
			print("[ClientNetwork] WARNING: get_peer(%d) returned null on server; transport heartbeat skipped." % target_peer_id)
			return
		_try_set_ws_heartbeat(server_socket, target_peer_id)
		return
	var client_socket: WebSocketPeer = ws_multiplayer.get_peer(1)
	if client_socket == null:
		print("[ClientNetwork] WARNING: get_peer(1) returned null on client; transport heartbeat skipped.")
		return
	_try_set_ws_heartbeat(client_socket, 1)

# Attempts to enable transport-level WebSocket ping/pong heartbeat on the given
# WebSocketPeer. Tries property assignment first, then setter method, and logs
# the outcome. This is a best-effort supplement — the primary keep-alive is the
# application-level RPC ping/pong sent by _on_host_keepalive_timeout / server push.
func _try_set_ws_heartbeat(ws_peer: WebSocketPeer, peer_id: int) -> void:
	if ws_peer == null:
		return
	var interval_seconds: float = WS_TRANSPORT_HEARTBEAT_INTERVAL_SECONDS
	# When interval is 0.0, transport-level heartbeat is intentionally disabled
	# (required for reverse-proxy deployments like HF/Cloudflare).
	if interval_seconds <= 0.0:
		print("[ClientNetwork] WebSocket transport heartbeat disabled (interval=0); using application-level keepalive for peer %d." % peer_id)
		return
	# Try 1: Direct property assignment (works in Godot builds that expose heartbeat_interval)
	if "heartbeat_interval" in ws_peer:
		ws_peer.set("heartbeat_interval", interval_seconds)
		print("[ClientNetwork] Set WebSocket transport heartbeat_interval=%.1fs for peer %d (property)." % [interval_seconds, peer_id])
		return
	# Try 2: Setter method (some builds expose the setter but not the property in reflection)
	if ws_peer.has_method("set_heartbeat_interval"):
		ws_peer.call("set_heartbeat_interval", interval_seconds)
		print("[ClientNetwork] Set WebSocket transport heartbeat_interval=%.1fs for peer %d (method)." % [interval_seconds, peer_id])
		return
	# Neither available — not fatal. Application-level RPC keepalive pings will
	# keep the HF/Cloudflare proxy connection alive.
	print("[ClientNetwork] WebSocketPeer has no heartbeat_interval support; relying on application-level keepalive RPCs for peer %d." % peer_id)

func _process(delta: float) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		_manual_network_poll_accumulator = 0.0
		return
	_manual_network_poll_accumulator += delta
	if _manual_network_poll_accumulator < (1.0 / MANUAL_NETWORK_POLL_RATE_HZ):
		return
	_manual_network_poll_accumulator = 0.0
	api.multiplayer_peer.poll()
	if api.is_server():
		var now_msec: int = Time.get_ticks_msec()
		if api.get_peers().size() > 0 and now_msec - _debug_last_server_poll_log_msec >= 2000:
			_debug_last_server_poll_log_msec = now_msec
			print("[ClientNetwork] Server manual poll alive. peers=%s rooms=%d auto_poll=%s" % [str(api.get_peers()), _server_rooms.size(), str(get_tree().multiplayer_poll)])

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		disconnect_from_session()

func _build_room_auth_payload() -> Dictionary:
	var desired_room_id: String = _active_room_id.strip_edges()
	if desired_room_id.is_empty():
		desired_room_id = str(_current_server_info.get("room_id", "")).strip_edges()
	if desired_room_id.is_empty():
		desired_room_id = _build_room_id()
		_active_room_id = desired_room_id
	return {
		"room_id": desired_room_id,
		"protocol_version": NETWORK_PROTOCOL_VERSION,
		"map_id": _active_map_id,
		"map_name": _sanitize_room_map_name(_active_map_name, _active_map_id, _guess_runtime_map_name()),
		"cloud_version_id": _active_cloud_version_id,
		"user_id": SupabaseClient.get_user_id(),
		"username": CloudAPI.get_current_username(),
		"max_players": int(_current_server_info.get("max_players", MAX_CLIENTS)),
		"create_if_missing": bool(_current_server_info.get("create_if_missing", false))
	}

func _remove_peer_from_room(peer_id: int) -> void:
	var room_id: String = get_peer_room_id(peer_id)
	if room_id.is_empty():
		return
	var room_state: Dictionary = _server_rooms.get(room_id, {}) if _server_rooms.get(room_id, {}) is Dictionary else {}
	var peer_ids: Array[int] = get_room_member_peer_ids(room_id)
	peer_ids.erase(peer_id)
	var peer_meta: Dictionary = room_state.get("peer_meta", {}) if room_state.get("peer_meta", {}) is Dictionary else {}
	peer_meta.erase(str(peer_id))
	if peer_ids.is_empty():
		_server_rooms.erase(room_id)
		_emit_room_emptied_priority(room_id)
	else:
		room_state["peer_ids"] = peer_ids
		room_state["peer_meta"] = peer_meta
		if int(room_state.get("owner_peer_id", 0)) == peer_id:
			var next_owner_peer_id: int = peer_ids[0]
			var next_owner_meta: Dictionary = peer_meta.get(str(next_owner_peer_id), {}) if peer_meta.get(str(next_owner_peer_id), {}) is Dictionary else {}
			room_state["owner_peer_id"] = next_owner_peer_id
			room_state["owner_user_id"] = str(next_owner_meta.get("user_id", "")).strip_edges()
			room_state["owner_username"] = str(next_owner_meta.get("username", "Dedicated Server")).strip_edges()
		_server_rooms[room_id] = room_state
	_peer_room_ids.erase(peer_id)

func _prune_empty_room_if_orphaned(room_id: String) -> void:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty() or not _server_rooms.has(clean_room_id):
		return
	if not get_room_member_peer_ids(clean_room_id).is_empty():
		return
	_server_rooms.erase(clean_room_id)
	_emit_room_emptied_priority(clean_room_id)

func _ensure_timers() -> void:
	if _connect_timeout_timer == null:
		_connect_timeout_timer = Timer.new()
		_connect_timeout_timer.one_shot = true
		_connect_timeout_timer.timeout.connect(_on_connection_timeout)
		add_child(_connect_timeout_timer)

func _ensure_reconcile_timer() -> void:
	if _reconcile_timer != null:
		return
	_reconcile_timer = Timer.new()
	_reconcile_timer.name = "RoomReconcileTimer"
	_reconcile_timer.one_shot = false
	_reconcile_timer.wait_time = 2.0
	_reconcile_timer.timeout.connect(_on_reconcile_timeout)
	add_child(_reconcile_timer)
	_reconcile_timer.start()

func _stop_reconcile_timer() -> void:
	if _reconcile_timer != null:
		_reconcile_timer.stop()

func _on_reconcile_timeout() -> void:
	_reconcile_server_room_members()

func prepare_for_lobby() -> void:
	disconnect_from_session()

func connect_or_host() -> void:
	transport_status_changed.emit("Looking for a live dedicated room...")
	transport_progress_updated.emit("discover", 0.2)
	var preferred_map_filter: String = _guess_runtime_map_id()
	if preferred_map_filter.is_empty():
		preferred_map_filter = _guess_runtime_map_name()
	var active_result: Dictionary = await CloudAPI.fetch_active_servers(preferred_map_filter, 24)
	var rows: Array = CloudAPI._extract_array_payload(active_result.get("data", [])) if bool(active_result.get("ok", false)) else []
	var candidate: Dictionary = _select_joinable_room_candidate(rows)
	if not candidate.is_empty():
		join_targeted_room(candidate)
		return
	transport_status_changed.emit("No compatible live room found. Creating a new dedicated room...")
	transport_progress_updated.emit("create", 0.35)
	host_game(GameState.DEFAULT_PORT, rows)

func host_game(_port: int, existing_mode_rows: Array = []) -> Error:
	disconnect_from_session()
	last_connection_error = ""
	if _is_dedicated_server_runtime():
		return _host_dedicated_server(_get_dedicated_bind_port(_port))
	_active_room_id = _build_room_id()
	_active_map_name = _guess_runtime_map_name()
	_active_map_id = _guess_runtime_map_id()
	_active_cloud_version_id = _guess_runtime_cloud_version_id()
	var runtime_server_url: String = _select_bootstrap_server_ws_url_for(existing_mode_rows, _active_map_id, _active_map_name)
	_current_server_info = {
		"room_id": _active_room_id,
		"map_name": _sanitize_room_map_name(_active_map_name, _active_map_id, _guess_runtime_map_name()),
		"map_id": _active_map_id,
		"cloud_version_id": _active_cloud_version_id,
		"host_user_id": SupabaseClient.get_user_id(),
		"host_username": CloudAPI.get_current_username(),
		"server_url": runtime_server_url,
		"ip": _extract_public_host(runtime_server_url),
		"port": _extract_public_port(runtime_server_url),
		"player_id": "",
		"is_host": true,
		"create_if_missing": true,
		"players_count": 1,
		"max_players": MAX_CLIENTS,
		"transport": "websocket"
	}
	transport_status_changed.emit("Connecting to dedicated server...")
	transport_progress_updated.emit("connect", 0.42)
	return _start_client_attempt(runtime_server_url if not runtime_server_url.is_empty() else _get_default_ws_url())

func join_game(ip: String, port: int) -> Error:
	disconnect_from_session()
	last_connection_error = ""
	_active_room_id = str(_current_server_info.get("room_id", "")).strip_edges()
	_active_map_name = _guess_runtime_map_name()
	_active_map_id = _guess_runtime_map_id()
	_active_cloud_version_id = _guess_runtime_cloud_version_id()
	_current_server_info = {
		"room_id": _active_room_id,
		"server_url": ip.strip_edges() if ip.strip_edges().begins_with("ws://") or ip.strip_edges().begins_with("wss://") else "",
		"ip": ip.strip_edges(),
		"port": port,
		"map_name": _sanitize_room_map_name(_active_map_name, _active_map_id, _guess_runtime_map_name()),
		"map_id": _active_map_id,
		"cloud_version_id": _active_cloud_version_id,
		"host_username": "Dedicated Server",
		"create_if_missing": _active_room_id.is_empty()
	}
	transport_status_changed.emit("Connecting to dedicated server...")
	transport_progress_updated.emit("connect", 0.42)
	return _start_client_attempt(_build_ws_url(ip, port))

func join_targeted_room(server_info: Dictionary) -> Error:
	disconnect_from_session()
	last_connection_error = ""
	_current_server_info = server_info.duplicate(true)
	_active_room_id = str(_current_server_info.get("room_id", "")).strip_edges()
	_active_map_name = _sanitize_room_map_name(str(_current_server_info.get("map_name", _guess_runtime_map_name())).strip_edges(), str(_current_server_info.get("map_id", _guess_runtime_map_id())).strip_edges(), _guess_runtime_map_name())
	_active_map_id = str(_current_server_info.get("map_id", _guess_runtime_map_id())).strip_edges()
	_active_cloud_version_id = str(_current_server_info.get("cloud_version_id", _guess_runtime_cloud_version_id())).strip_edges()
	_current_server_info["map_name"] = _active_map_name
	_current_server_info["create_if_missing"] = bool(_current_server_info.get("create_if_missing", false))
	var host_value: String = str(_current_server_info.get("server_url", _current_server_info.get("ip", _get_public_dedicated_host()))).strip_edges()
	var port_value: int = int(_current_server_info.get("port", _get_public_dedicated_port()))
	if host_value.is_empty():
		host_value = _get_public_dedicated_host()
	if port_value <= 0:
		port_value = _get_public_dedicated_port()
	transport_status_changed.emit("Joining dedicated room...")
	transport_progress_updated.emit("connect", 0.42)
	return _start_client_attempt(_build_ws_url(host_value, port_value))

func connect_to_dedicated_server(server_url: String, room_id: String, server_info: Dictionary = {}) -> Error:
	var targeted_info: Dictionary = server_info.duplicate(true)
	targeted_info["server_url"] = server_url.strip_edges()
	targeted_info["room_id"] = room_id.strip_edges()
	if not targeted_info.has("create_if_missing"):
		targeted_info["create_if_missing"] = false
	return join_targeted_room(targeted_info)

func measure_server_latency(ip: String, port: int, timeout_seconds: float = 1.5) -> float:
	var ws_url: String = _build_ws_url(ip, port)
	if ws_url.is_empty():
		return INF
	var socket := WebSocketPeer.new()
	var start_error: Error = socket.connect_to_url(ws_url)
	if start_error != OK:
		return INF
	var start_msec: int = Time.get_ticks_msec()
	var deadline_msec: int = start_msec + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		socket.poll()
		var state: int = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			socket.close()
			return float(Time.get_ticks_msec() - start_msec)
		if state == WebSocketPeer.STATE_CLOSED:
			return INF
		await get_tree().create_timer(0.05).timeout
	socket.close()
	return INF

func disconnect_from_session_async() -> void:
	_stop_connection_timeout()
	_stop_reconcile_timer()
	await _send_leave_notice_if_needed_async()
	_teardown_session_peer()

func disconnect_from_session() -> void:
	_stop_connection_timeout()
	_stop_reconcile_timer()
	_send_leave_notice_if_needed()
	_teardown_session_peer()

func _teardown_session_peer() -> void:
	# Emit room_emptied for all active rooms before clearing state so that
	# server_main can immediately DELETE the Bobux active_servers rows.
	if is_host():
		for room_id_variant in _server_rooms.keys():
			var room_id: String = str(room_id_variant).strip_edges()
			if not room_id.is_empty() and not get_room_member_peer_ids(room_id).is_empty():
				_emit_room_emptied_priority(room_id)
	_active_room_id = ""
	_active_map_name = ""
	_active_map_id = ""
	_active_cloud_version_id = ""
	_pending_ws_url = ""
	_pending_public_host = ""
	_pending_public_port = 0
	_pending_attempt = 0
	_connected_once_for_attempt = false
	_room_join_confirmed = false
	_explicit_join_rejection_message = ""
	_pending_auth_payload = {}
	current_port = 0
	current_host_ip = ""
	_hosting = false
	_current_server_info = {}
	_peer_room_ids.clear()
	_server_rooms.clear()
	_cached_room_summaries.clear()
	_cached_room_peer_profiles.clear()
	_peer_last_join_msec.clear()
	_peer_join_violations.clear()
	_peer_last_keepalive_msec.clear()
	_pending_server_room_joins.clear()
	_leave_ack_received = false
	_leave_ack_room_id = ""
	var api: MultiplayerAPI = _multiplayer_api()
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	if peer != null:
		peer.close()
		# Immediately poll to flush the WebSocket close frame before the peer
		# is replaced or nullified. Without this, fast reconnect or scene-change
		# paths could orphan the server-side session.
		peer.poll()
		call_deferred("_finalize_peer_shutdown_async", peer)
	elif api != null:
		api.multiplayer_peer = null

func _send_leave_notice_if_needed() -> void:
	if is_host():
		return
	if not _room_join_confirmed or _active_room_id.is_empty():
		return
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		return
	var local_peer_id: int = api.get_unique_id()
	if local_peer_id <= 0:
		return
	_request_room_leave.rpc_id(1, {
		"room_id": _active_room_id,
		"peer_id": local_peer_id
	})
	api.multiplayer_peer.poll()

func _send_leave_notice_if_needed_async() -> void:
	if is_host():
		return
	if not _room_join_confirmed or _active_room_id.is_empty():
		return
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		return
	var local_peer_id: int = api.get_unique_id()
	if local_peer_id <= 0:
		return
	_leave_ack_received = false
	_leave_ack_room_id = _active_room_id
	_request_room_leave.rpc_id(1, {
		"room_id": _active_room_id,
		"peer_id": local_peer_id
	})
	var deadline_msec: int = Time.get_ticks_msec() + int(LEAVE_ACK_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		if api.multiplayer_peer == null:
			break
		api.multiplayer_peer.poll()
		if _leave_ack_received:
			break
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
	if api.multiplayer_peer != null:
		api.multiplayer_peer.poll()

func _finalize_peer_shutdown_async(expected_peer: MultiplayerPeer) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	var api: MultiplayerAPI = _multiplayer_api()
	if api != null and api.multiplayer_peer == expected_peer:
		api.multiplayer_peer = null

func is_host() -> bool:
	var api: MultiplayerAPI = _multiplayer_api()
	return _hosting and api != null and api.is_server()

func is_session_active() -> bool:
	var api: MultiplayerAPI = _multiplayer_api()
	return api != null and api.multiplayer_peer != null

func get_unique_id() -> int:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		return 0
	return api.get_unique_id()

func get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		return MultiplayerPeer.CONNECTION_DISCONNECTED
	return api.multiplayer_peer.get_connection_status()

func get_external_ip() -> String:
	return current_host_ip

func get_active_transport_label() -> String:
	return "Dedicated WebSocket"

func is_host_migration_in_progress() -> bool:
	return false

func get_cached_migration_local_peer_id() -> int:
	return get_unique_id()

func set_manual_handover_target_peer_id(_peer_id: int) -> void:
	return

func start_host_migration_detection(_message: String = "") -> void:
	return

func broadcast_message(text: String) -> void:
	var clean_text: String = text.strip_edges()
	if clean_text.is_empty():
		return
	if not is_session_active():
		_receive_room_chat_message(clean_text, get_unique_id())
		return
	var current_room_id: String = get_current_room_id()
	if current_room_id.is_empty():
		current_room_id = get_peer_room_id(get_unique_id())
	if current_room_id.is_empty():
		_receive_room_chat_message(clean_text, get_unique_id())
		return
	_relay_room_chat_message.rpc_id(1, clean_text, current_room_id)

@rpc("any_peer", "reliable")
func _relay_room_chat_message(text: String, _requested_room_id: String = "") -> void:
	var clean_text: String = text.strip_edges()
	if clean_text.is_empty():
		return
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return
	var sender_id: int = api.get_remote_sender_id() if api != null else 0
	if sender_id <= 0:
		return
	# AUDIT FIX MEDIUM-3: Never trust client-provided room_id. Only use the
	# server-authoritative room assignment to prevent cross-room chat spoofing.
	var room_id: String = get_peer_room_id(sender_id)
	if room_id.is_empty():
		return
	for target_peer_id in get_room_member_peer_ids(room_id):
		_receive_room_chat_message.rpc_id(target_peer_id, clean_text, sender_id)

@rpc("authority", "call_local", "reliable")
func _receive_room_chat_message(text: String, sender_id: int) -> void:
	var clean_text: String = text.strip_edges()
	if clean_text.is_empty():
		return
	chat_message_received.emit(clean_text, sender_id)

func _host_dedicated_server(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error_code: Error = peer.create_server(port, "*")
	if error_code != OK:
		last_connection_error = "Dedicated server creation failed: %s" % error_string(error_code)
		push_error("[ClientNetwork] %s" % last_connection_error)
		return error_code
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null:
		last_connection_error = "Dedicated server creation failed: MultiplayerAPI is unavailable."
		push_error("[ClientNetwork] %s" % last_connection_error)
		peer.close()
		return ERR_UNAVAILABLE
	api.multiplayer_peer = peer
	current_port = port
	current_host_ip = "0.0.0.0"
	_hosting = true
	_peer_room_ids[1] = "__server__"
	transport_status_changed.emit("Dedicated WebSocket server is listening on port %d." % port)
	transport_progress_updated.emit("hosted", 1.0)
	hosting_started.emit(port, current_host_ip, false)
	print("[NetworkManager] Dedicated WebSocket server listening on port %d." % port)
	_ensure_reconcile_timer()
	return OK

func _start_client_attempt(ws_url: String) -> Error:
	_pending_ws_url = ws_url.strip_edges()
	if _pending_ws_url.is_empty():
		last_connection_error = "Dedicated server URL is empty."
		return ERR_INVALID_PARAMETER
	_pending_public_host = _extract_public_host(_pending_ws_url)
	_pending_public_port = _extract_public_port(_pending_ws_url)
	if _pending_public_port <= 0:
		_pending_public_port = _get_public_dedicated_port()
	_pending_attempt = 1
	_connected_once_for_attempt = false
	_explicit_join_rejection_message = ""
	_client_wakeup_serial += 1
	_wakeup_and_begin_client_attempt(_client_wakeup_serial)
	return OK

func _wakeup_and_begin_client_attempt(wakeup_serial: int) -> void:
	var ws_url_snapshot: String = _pending_ws_url
	await _warm_server_if_needed(ws_url_snapshot)
	if wakeup_serial != _client_wakeup_serial or ws_url_snapshot != _pending_ws_url or _pending_ws_url.is_empty():
		return
	_begin_client_attempt()

func _warm_server_if_needed(ws_url: String) -> void:
	var health_url: String = _build_health_url_from_ws_url(ws_url)
	if health_url.is_empty():
		return
	var deadline_msec: int = Time.get_ticks_msec() + int(SERVER_WAKEUP_TIMEOUT_SECONDS * 1000.0)
	var attempt_index: int = 1
	while Time.get_ticks_msec() < deadline_msec:
		transport_status_changed.emit("Waking dedicated server... (%d)" % attempt_index)
		transport_progress_updated.emit("wakeup", 0.44)
		var response_code: int = await _request_wakeup_http_status(health_url)
		if response_code >= 200 and response_code < 500:
			await get_tree().create_timer(0.35).timeout
			return
		attempt_index += 1
		await get_tree().create_timer(SERVER_WAKEUP_POLL_SECONDS).timeout

func _build_health_url_from_ws_url(ws_url: String) -> String:
	var clean_url: String = ws_url.strip_edges()
	if clean_url.is_empty():
		return ""
	if clean_url.begins_with("wss://"):
		clean_url = "https://" + clean_url.substr(6)
	elif clean_url.begins_with("ws://"):
		clean_url = "http://" + clean_url.substr(5)
	else:
		return ""
	var scheme_end: int = clean_url.find("://")
	var host_start: int = scheme_end + 3
	var path_start: int = clean_url.find("/", host_start)
	var base_url: String = clean_url if path_start < 0 else clean_url.substr(0, path_start)
	return base_url + "/health"

func _request_wakeup_http_status(url: String) -> int:
	var http := HTTPRequest.new()
	http.timeout = SERVER_WAKEUP_HTTP_TIMEOUT_SECONDS
	add_child(http)
	var err: Error = http.request(url, ["Cache-Control: no-cache"], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return 0
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 2:
		return 0
	return int(result[1])

# PRACTICE SCREENSHOT: WebSocket client connection - opens a dedicated server socket and prepares room auth payload.
func _begin_client_attempt() -> Error:
	_client_attempt_serial += 1
	var peer := WebSocketMultiplayerPeer.new()
	var error_code: Error = peer.create_client(_pending_ws_url)
	if error_code != OK:
		last_connection_error = "Dedicated join failed: %s" % error_string(error_code)
		push_error("[ClientNetwork] %s" % last_connection_error)
		return error_code
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null:
		last_connection_error = "Dedicated join failed: MultiplayerAPI is unavailable."
		push_error("[ClientNetwork] %s" % last_connection_error)
		peer.close()
		return ERR_UNAVAILABLE
	api.multiplayer_peer = peer
	current_host_ip = _pending_public_host
	current_port = _pending_public_port
	_hosting = false
	_pending_auth_payload = _build_room_auth_payload()
	print("[ClientNetwork] Begin client attempt #%d url=%s room=%s protocol=%s" % [_client_attempt_serial, _pending_ws_url, str(_pending_auth_payload.get("room_id", "")).strip_edges(), NETWORK_PROTOCOL_VERSION])
	transport_status_changed.emit("Connecting to %s" % _pending_ws_url)
	transport_progress_updated.emit("connecting", clampf(0.38 + (0.15 * float(_pending_attempt - 1)), 0.0, 0.9))
	_start_connection_timeout()
	return OK

func _start_connection_timeout() -> void:
	_ensure_timers()
	_connect_timeout_timer.start(CONNECTION_TIMEOUT_SECONDS)

func _stop_connection_timeout() -> void:
	if _connect_timeout_timer != null:
		_connect_timeout_timer.stop()

func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		record_server_peer_keepalive(peer_id)
		_configure_websocket_transport_heartbeat(peer_id)
	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var disconnected_room_id: String = get_peer_room_id(peer_id)
	var pending_join: Dictionary = _pending_server_room_joins.get(peer_id, {}) if _pending_server_room_joins.get(peer_id, {}) is Dictionary else {}
	_pending_server_room_joins.erase(peer_id)
	_prune_empty_room_if_orphaned(str(pending_join.get("room_id", "")).strip_edges())
	if is_host():
		_remove_peer_from_room(peer_id)
		# AUDIT FIX CRITICAL-5: Scope broadcast to the affected room only.
		_broadcast_room_summaries(disconnected_room_id)
		_broadcast_room_peer_profiles(disconnected_room_id)
	# AUDIT FIX CRITICAL-3: Clean up rate limit tracking for disconnected peers.
	_peer_last_join_msec.erase(peer_id)
	_peer_join_violations.erase(peer_id)
	_peer_last_keepalive_msec.erase(peer_id)
	player_disconnected.emit(peer_id)
	# Safety net: reconcile all rooms on the next frame to catch any other
	# stale peers whose disconnect callback was lost by the transport layer.
	if is_host():
		call_deferred("_reconcile_server_room_members")

func server_evict_peer(peer_id: int) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server() or peer_id <= 0:
		return
	var disconnected_room_id: String = get_peer_room_id(peer_id)
	var pending_join: Dictionary = _pending_server_room_joins.get(peer_id, {}) if _pending_server_room_joins.get(peer_id, {}) is Dictionary else {}
	_pending_server_room_joins.erase(peer_id)
	_prune_empty_room_if_orphaned(str(pending_join.get("room_id", "")).strip_edges())
	_remove_peer_from_room(peer_id)
	_peer_last_join_msec.erase(peer_id)
	_peer_join_violations.erase(peer_id)
	_peer_last_keepalive_msec.erase(peer_id)
	if not disconnected_room_id.is_empty():
		_broadcast_room_summaries(disconnected_room_id)
		_broadcast_room_peer_profiles(disconnected_room_id)
	if api.get_peers().has(peer_id):
		_force_disconnect_scene_peer(peer_id)

func _on_connected_to_server() -> void:
	_connected_once_for_attempt = true
	_room_join_confirmed = false
	_stop_connection_timeout()
	_configure_websocket_transport_heartbeat(1)
	_pending_auth_payload = _build_room_auth_payload()
	print("[ClientNetwork] Socket connected on attempt #%d. Waiting for room join ack..." % _client_attempt_serial)
	transport_status_changed.emit("Socket connected. Joining room...")
	transport_progress_updated.emit("auth", 0.82)
	_connect_timeout_timer.start(ROOM_AUTH_TIMEOUT_SECONDS)
	_request_room_join.rpc_id(1, _pending_auth_payload)

func _after_client_connected_async() -> void:
	var local_peer_id: int = get_unique_id()
	if local_peer_id > 0 and not _active_room_id.is_empty():
		_peer_room_ids[local_peer_id] = _active_room_id

func _on_connection_failed_native() -> void:
	_stop_connection_timeout()
	var failed_api: MultiplayerAPI = _multiplayer_api()
	var failed_status: MultiplayerPeer.ConnectionStatus = failed_api.multiplayer_peer.get_connection_status() if failed_api != null and failed_api.multiplayer_peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
	print("[ClientNetwork] connection_failed on attempt #%d connected_once=%s room_join_confirmed=%s status=%d pending_url=%s" % [_client_attempt_serial, str(_connected_once_for_attempt), str(_room_join_confirmed), int(failed_status), _pending_ws_url])
	# Guard: if session was already torn down by disconnect_from_session(),
	# this callback is stale — there is no server URL to retry against.
	if _pending_ws_url.is_empty():
		return
	if _connected_once_for_attempt:
		return
	if _pending_attempt < MAX_CONNECT_ATTEMPTS:
		_pending_attempt += 1
		# AUDIT FIX MEDIUM-6: Exponential backoff to prevent retry storms.
		var backoff_delay: float = RETRY_DELAY_SECONDS * pow(RETRY_BACKOFF_MULTIPLIER, float(_pending_attempt - 1))
		transport_status_changed.emit("Connection failed. Retrying dedicated server handshake (%d/%d)..." % [_pending_attempt, MAX_CONNECT_ATTEMPTS])
		transport_progress_updated.emit("retry", 0.55)
		await get_tree().create_timer(backoff_delay).timeout
		_begin_client_attempt()
		return
	_finish_connection_failure("Could not connect to the dedicated server.")

func _on_server_disconnected_native() -> void:
	_stop_connection_timeout()
	var disconnected_api: MultiplayerAPI = _multiplayer_api()
	var disconnected_status: MultiplayerPeer.ConnectionStatus = disconnected_api.multiplayer_peer.get_connection_status() if disconnected_api != null and disconnected_api.multiplayer_peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
	print("[ClientNetwork] server_disconnected on attempt #%d connected_once=%s room_join_confirmed=%s status=%d pending_url=%s" % [_client_attempt_serial, str(_connected_once_for_attempt), str(_room_join_confirmed), int(disconnected_status), _pending_ws_url])
	# Guard: if session was already torn down by disconnect_from_session(),
	# this callback is stale — there is no server URL to retry against.
	if _pending_ws_url.is_empty():
		return
	if not _explicit_join_rejection_message.is_empty():
		_explicit_join_rejection_message = ""
		return
	if (not _connected_once_for_attempt or not _room_join_confirmed) and _pending_attempt < MAX_CONNECT_ATTEMPTS:
		_pending_attempt += 1
		# AUDIT FIX MEDIUM-6: Exponential backoff.
		var backoff_delay: float = RETRY_DELAY_SECONDS * pow(RETRY_BACKOFF_MULTIPLIER, float(_pending_attempt - 1))
		var retry_message: String = "Dedicated server closed the socket during handshake. Retrying (%d/%d)..." if not _room_join_confirmed else "Dedicated room handshake was interrupted. Retrying (%d/%d)..."
		transport_status_changed.emit(retry_message % [_pending_attempt, MAX_CONNECT_ATTEMPTS])
		transport_progress_updated.emit("retry", 0.55)
		await get_tree().create_timer(backoff_delay).timeout
		_connected_once_for_attempt = false
		_room_join_confirmed = false
		_begin_client_attempt()
		return
	server_disconnected.emit()

func _on_connection_timeout() -> void:
	var timeout_api_snapshot: MultiplayerAPI = _multiplayer_api()
	var timeout_status: MultiplayerPeer.ConnectionStatus = timeout_api_snapshot.multiplayer_peer.get_connection_status() if timeout_api_snapshot != null and timeout_api_snapshot.multiplayer_peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
	print("[ClientNetwork] timeout on attempt #%d connected_once=%s room_join_confirmed=%s status=%d pending_url=%s" % [_client_attempt_serial, str(_connected_once_for_attempt), str(_room_join_confirmed), int(timeout_status), _pending_ws_url])
	# Guard: if session was already torn down, skip.
	if _pending_ws_url.is_empty():
		return
	if _connected_once_for_attempt and not _room_join_confirmed:
		if _pending_attempt < MAX_CONNECT_ATTEMPTS:
			_pending_attempt += 1
			transport_status_changed.emit("Dedicated room handshake timed out. Retrying (%d/%d)..." % [_pending_attempt, MAX_CONNECT_ATTEMPTS])
			transport_progress_updated.emit("retry", 0.58)
			var timeout_api: MultiplayerAPI = _multiplayer_api()
			var timeout_peer: MultiplayerPeer = timeout_api.multiplayer_peer if timeout_api != null else null
			if timeout_peer != null:
				timeout_peer.close()
				timeout_peer.poll()
			if timeout_api != null:
				timeout_api.multiplayer_peer = null
			_connected_once_for_attempt = false
			_room_join_confirmed = false
			_begin_client_attempt()
			return
		_finish_connection_failure("Connection to the dedicated room timed out.")
		return
	if _connected_once_for_attempt:
		return
	if _pending_attempt < MAX_CONNECT_ATTEMPTS:
		_pending_attempt += 1
		transport_status_changed.emit("Dedicated server handshake timed out. Retrying (%d/%d)..." % [_pending_attempt, MAX_CONNECT_ATTEMPTS])
		transport_progress_updated.emit("retry", 0.58)
		var api: MultiplayerAPI = _multiplayer_api()
		var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
		if peer != null:
			peer.close()
			peer.poll()
		if api != null:
			api.multiplayer_peer = null
		_begin_client_attempt()
		return
	_finish_connection_failure("Connection to the dedicated server timed out.")

func _finish_connection_failure(message: String) -> void:
	last_connection_error = message.strip_edges()
	var api: MultiplayerAPI = _multiplayer_api()
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	if peer != null:
		peer.close()
		peer.poll()
	if api != null:
		api.multiplayer_peer = null
	_room_join_confirmed = false
	_connected_once_for_attempt = false
	connection_failed.emit(last_connection_error)

func request_room_summaries() -> Error:
	if is_host():
		_cached_room_summaries = _build_room_summary_list()
		room_summaries_updated.emit(_cached_room_summaries.duplicate(true))
		return OK
	if not is_session_active():
		return ERR_UNCONFIGURED
	_request_room_summaries_rpc.rpc_id(1)
	return OK

func _build_room_summary_list() -> Array:
	var summaries: Array = []
	var default_server_url: String = _get_advertised_server_ws_url()
	var summary_host: String = _extract_public_host(default_server_url)
	var summary_port: int = _extract_public_port(default_server_url)
	for snapshot_variant in get_active_room_snapshots():
		if not (snapshot_variant is Dictionary):
			continue
		var snapshot: Dictionary = snapshot_variant
		var peer_ids: Array[int] = []
		for peer_variant in snapshot.get("peer_ids", []):
			var peer_id: int = int(peer_variant)
			if peer_id > 0:
				peer_ids.append(peer_id)
		summaries.append({
			"room_id": str(snapshot.get("room_id", "")).strip_edges(),
			"map_id": str(snapshot.get("map_id", _guess_runtime_map_id())).strip_edges(),
			"map_name": str(snapshot.get("map_name", _guess_runtime_map_name())).strip_edges(),
			"cloud_version_id": str(snapshot.get("cloud_version_id", "")).strip_edges(),
			"players_count": int(snapshot.get("players_count", peer_ids.size())),
			"max_players": int(snapshot.get("max_players", MAX_CLIENTS)),
			"owner_peer_id": int(snapshot.get("owner_peer_id", 0)),
			"owner_user_id": str(snapshot.get("owner_user_id", "")).strip_edges(),
			"owner_username": str(snapshot.get("owner_username", "Dedicated Server")).strip_edges(),
			"peer_ids": peer_ids,
			"transport": "websocket",
			"server_url": default_server_url,
			"server_host": summary_host,
			"server_port": summary_port
		})
	return summaries

func _push_room_summaries_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	_receive_room_summaries.rpc_id(peer_id, _build_room_summary_list())

func _push_room_peer_profiles_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	var room_id: String = get_peer_room_id(peer_id)
	if room_id.is_empty():
		return
	_receive_room_peer_profiles.rpc_id(peer_id, _build_room_peer_profile_snapshot(room_id))

# AUDIT FIX CRITICAL-5: Room summary broadcasts are now scoped to only the
# peers in the affected room instead of sending ALL summaries to ALL 1,000
# peers. This reduces broadcast traffic from O(rooms×peers) to O(room_size).
func _broadcast_room_summaries(affected_room_id: String = "") -> void:
	if not is_host():
		return
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null:
		return
	var summaries: Array = _build_room_summary_list()
	_cached_room_summaries = summaries.duplicate(true)
	room_summaries_updated.emit(_cached_room_summaries.duplicate(true))
	var clean_affected_room: String = affected_room_id.strip_edges()
	if clean_affected_room.is_empty():
		# Fallback: send to all peers (only for initial connect or summary requests)
		for peer_id in api.get_peers():
			_receive_room_summaries.rpc_id(peer_id, summaries)
	else:
		# Scoped: only notify peers in the affected room
		for peer_id in get_room_member_peer_ids(clean_affected_room):
			_receive_room_summaries.rpc_id(peer_id, summaries)

func _broadcast_room_peer_profiles(affected_room_id: String = "") -> void:
	if not is_host():
		return
	var clean_affected_room: String = affected_room_id.strip_edges()
	if clean_affected_room.is_empty():
		return
	var profiles_by_peer: Dictionary = _build_room_peer_profile_snapshot(clean_affected_room)
	for peer_id in get_room_member_peer_ids(clean_affected_room):
		_receive_room_peer_profiles.rpc_id(peer_id, profiles_by_peer)

@rpc("any_peer", "reliable")
func _request_room_summaries_rpc() -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return
	var sender_id: int = api.get_remote_sender_id()
	_push_room_summaries_to_peer(sender_id)
	_push_room_peer_profiles_to_peer(sender_id)

@rpc("authority", "reliable")
func _receive_room_summaries(summaries: Array) -> void:
	_cached_room_summaries = summaries.duplicate(true)
	_refresh_client_peer_room_assignments_from_summaries(_cached_room_summaries)
	room_summaries_updated.emit(_cached_room_summaries.duplicate(true))

@rpc("authority", "reliable")
func _receive_room_peer_profiles(profiles_by_peer: Dictionary) -> void:
	_cached_room_peer_profiles = profiles_by_peer.duplicate(true)
	room_peer_profiles_updated.emit(_cached_room_peer_profiles.duplicate(true))

# PRACTICE SCREENSHOT: Server-side room join RPC - validates protocol, duplicate sessions, room capacity and map identity.
@rpc("any_peer", "reliable")
func _request_room_join(payload: Dictionary) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return
	var sender_id: int = api.get_remote_sender_id()
	record_server_peer_keepalive(sender_id)
	# AUDIT FIX CRITICAL-3: Rate-limit join requests to prevent amplification DoS.
	# Each _request_room_join triggers _broadcast_room_summaries which is O(rooms×peers).
	var now_msec: int = Time.get_ticks_msec()
	var last_join_msec: int = int(_peer_last_join_msec.get(sender_id, 0))
	if last_join_msec > 0 and (now_msec - last_join_msec) < JOIN_RATE_LIMIT_MSEC:
		var violations: int = int(_peer_join_violations.get(sender_id, 0)) + 1
		_peer_join_violations[sender_id] = violations
		if violations >= JOIN_RATE_LIMIT_MAX_VIOLATIONS:
			push_warning("[RoomHub] Disconnecting peer %d for join request flooding (%d violations)." % [sender_id, violations])
			_reject_room_join.rpc_id(sender_id, "Too many join requests.")
			call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	_peer_last_join_msec[sender_id] = now_msec
	# AUDIT FIX MEDIUM-4: Reject oversized payloads to prevent memory bombs.
	var payload_json: String = JSON.stringify(payload)
	if payload_json.length() > MAX_RPC_PAYLOAD_SIZE:
		_reject_room_join.rpc_id(sender_id, "Payload too large.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var room_id: String = str(payload.get("room_id", "")).strip_edges()
	var incoming_protocol_version: String = str(payload.get("protocol_version", "")).strip_edges()
	var incoming_user_id: String = str(payload.get("user_id", "")).strip_edges()
	if room_id.is_empty():
		_reject_room_join.rpc_id(sender_id, "Room id is missing.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	if incoming_protocol_version != NETWORK_PROTOCOL_VERSION:
		_reject_room_join.rpc_id(sender_id, "Client/server version mismatch. Update the game and redeploy the dedicated server.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var duplicate_peer_id: int = _find_live_or_pending_peer_by_user_id(incoming_user_id, sender_id)
	if duplicate_peer_id > 0:
		_reject_room_join.rpc_id(sender_id, DUPLICATE_SESSION_REJECTION_MESSAGE)
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var external_conflict: Dictionary = await _find_external_active_session_conflict(incoming_user_id, room_id)
	if not _is_server_peer_currently_connected(sender_id):
		return
	if not external_conflict.is_empty():
		_reject_room_join.rpc_id(sender_id, DUPLICATE_SESSION_REJECTION_MESSAGE)
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var conflicting_room_id: String = _find_conflicting_process_room_id(room_id)
	if not conflicting_room_id.is_empty():
		_reject_room_join.rpc_id(sender_id, "This dedicated server is already hosting another room.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var create_if_missing: bool = bool(payload.get("create_if_missing", false))
	var max_players: int = clampi(int(payload.get("max_players", MAX_CLIENTS)), 1, MAX_CLIENTS)
	var room_state: Dictionary = _server_rooms.get(room_id, {}) if _server_rooms.get(room_id, {}) is Dictionary else {}
	var peer_ids: Array[int] = get_room_member_peer_ids(room_id)
	if room_state.is_empty():
		if not create_if_missing:
			_reject_room_join.rpc_id(sender_id, "This room is no longer available.")
			call_deferred("_disconnect_peer_after_reject", sender_id)
			return
		room_state = {
			"room_id": room_id,
			"map_id": str(payload.get("map_id", "classic")).strip_edges(),
			"map_name": str(payload.get("map_name", "Classic")).strip_edges(),
			"cloud_version_id": str(payload.get("cloud_version_id", "")).strip_edges(),
			"max_players": max_players,
			"owner_peer_id": 0,
			"owner_user_id": str(payload.get("user_id", "")).strip_edges(),
			"owner_username": str(payload.get("username", "Dedicated Server")).strip_edges(),
			"peer_ids": [],
			"peer_meta": {}
		}
	if peer_ids.size() >= max_players and not peer_ids.has(sender_id):
		_reject_room_join.rpc_id(sender_id, "This room is full.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	room_state["max_players"] = max_players
	_server_rooms[room_id] = room_state
	_pending_server_room_joins[sender_id] = {
		"room_id": room_id,
		"user_id": str(payload.get("user_id", "")).strip_edges(),
		"username": str(payload.get("username", "Dedicated Server")).strip_edges(),
		"max_players": max_players
	}
	var joined_room_state: Dictionary = _server_rooms.get(room_id, room_state) if _server_rooms.get(room_id, room_state) is Dictionary else room_state
	_confirm_room_join.rpc_id(sender_id, {
		"room_id": room_id,
		"map_id": str(joined_room_state.get("map_id", _guess_runtime_map_id())).strip_edges(),
		"map_name": _sanitize_room_map_name(str(joined_room_state.get("map_name", _guess_runtime_map_name())).strip_edges(), str(joined_room_state.get("map_id", _guess_runtime_map_id())).strip_edges(), _guess_runtime_map_name()),
		"cloud_version_id": str(joined_room_state.get("cloud_version_id", "")).strip_edges(),
		"max_players": int(joined_room_state.get("max_players", max_players))
	})
	print("[RoomHub] Peer %d reserved room '%s' and is waiting for map sync." % [sender_id, room_id])

# PRACTICE SCREENSHOT: Client room confirmation RPC - loads the agreed map before the player is accepted into the room.
@rpc("authority", "reliable")
func _confirm_room_join(payload: Dictionary) -> void:
	_stop_connection_timeout()
	print("[ClientNetwork] Room confirm received on attempt #%d room=%s map=%s" % [_client_attempt_serial, str(payload.get("room_id", "")).strip_edges(), str(payload.get("map_id", "")).strip_edges()])
	_active_room_id = str(payload.get("room_id", _active_room_id)).strip_edges()
	_active_map_id = str(payload.get("map_id", _active_map_id)).strip_edges()
	_active_map_name = _sanitize_room_map_name(str(payload.get("map_name", _active_map_name)).strip_edges(), _active_map_id, _guess_runtime_map_name())
	_active_cloud_version_id = str(payload.get("cloud_version_id", _active_cloud_version_id)).strip_edges()
	if not _active_room_id.is_empty():
		_peer_room_ids[1] = _active_room_id
	_current_server_info["room_id"] = _active_room_id
	_current_server_info["map_id"] = _active_map_id
	_current_server_info["map_name"] = _active_map_name
	_current_server_info["cloud_version_id"] = _active_cloud_version_id
	_current_server_info["create_if_missing"] = false
	transport_status_changed.emit("Room confirmed. Syncing map...")
	transport_progress_updated.emit("map", 0.9)
	if MapManager != null and MapManager.has_method("load_map"):
		var map_result: Dictionary = await MapManager.load_map(_active_map_id, _active_map_name, _active_cloud_version_id)
		if not bool(map_result.get("ok", false)):
			var api: MultiplayerAPI = _multiplayer_api()
			if api != null and api.multiplayer_peer != null:
				api.multiplayer_peer.close()
				api.multiplayer_peer.poll()
				api.multiplayer_peer = null
			_finish_connection_failure(str(map_result.get("error", "Could not load the server map.")))
			return
	_connect_timeout_timer.start(ROOM_AUTH_TIMEOUT_SECONDS)
	_complete_room_join.rpc_id(1, {
		"room_id": _active_room_id
	})

# PRACTICE SCREENSHOT: Final room join RPC - commits the player to the room registry and broadcasts room summaries.
@rpc("any_peer", "reliable")
func _complete_room_join(payload: Dictionary) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return
	var sender_id: int = api.get_remote_sender_id()
	record_server_peer_keepalive(sender_id)
	var room_id: String = str(payload.get("room_id", "")).strip_edges()
	var pending_join: Dictionary = _pending_server_room_joins.get(sender_id, {}) if _pending_server_room_joins.get(sender_id, {}) is Dictionary else {}
	if room_id.is_empty() or pending_join.is_empty():
		_reject_room_join.rpc_id(sender_id, "This room join is no longer valid.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var pending_room_id: String = str(pending_join.get("room_id", "")).strip_edges()
	var pending_user_id: String = str(pending_join.get("user_id", "")).strip_edges()
	if pending_room_id != room_id:
		_reject_room_join.rpc_id(sender_id, "Room confirmation mismatch.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var duplicate_peer_id: int = _find_live_or_pending_peer_by_user_id(pending_user_id, sender_id)
	if duplicate_peer_id > 0:
		_pending_server_room_joins.erase(sender_id)
		_reject_room_join.rpc_id(sender_id, DUPLICATE_SESSION_REJECTION_MESSAGE)
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var external_conflict: Dictionary = await _find_external_active_session_conflict(pending_user_id, room_id)
	if not _is_server_peer_currently_connected(sender_id):
		_pending_server_room_joins.erase(sender_id)
		return
	if not external_conflict.is_empty():
		_pending_server_room_joins.erase(sender_id)
		_reject_room_join.rpc_id(sender_id, DUPLICATE_SESSION_REJECTION_MESSAGE)
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var conflicting_room_id: String = _find_conflicting_process_room_id(room_id)
	if not conflicting_room_id.is_empty():
		_pending_server_room_joins.erase(sender_id)
		_reject_room_join.rpc_id(sender_id, "This dedicated server is already hosting another room.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var room_state: Dictionary = _server_rooms.get(room_id, {}) if _server_rooms.get(room_id, {}) is Dictionary else {}
	if room_state.is_empty():
		_reject_room_join.rpc_id(sender_id, "This room is no longer available.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	var peer_ids: Array[int] = get_room_member_peer_ids(room_id)
	if peer_ids.size() >= int(room_state.get("max_players", MAX_CLIENTS)) and not peer_ids.has(sender_id):
		_pending_server_room_joins.erase(sender_id)
		_reject_room_join.rpc_id(sender_id, "This room is full.")
		call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	if not peer_ids.has(sender_id):
		peer_ids.append(sender_id)
	room_state["peer_ids"] = peer_ids
	if int(room_state.get("owner_peer_id", 0)) <= 0:
		room_state["owner_peer_id"] = sender_id
		room_state["owner_user_id"] = str(pending_join.get("user_id", room_state.get("owner_user_id", ""))).strip_edges()
		room_state["owner_username"] = str(pending_join.get("username", room_state.get("owner_username", "Dedicated Server"))).strip_edges()
	_server_rooms[room_id] = room_state
	_peer_room_ids[sender_id] = room_id
	update_peer_room_profile(sender_id, str(pending_join.get("user_id", "")).strip_edges(), str(pending_join.get("username", "")).strip_edges())
	_pending_server_room_joins.erase(sender_id)
	_room_join_ready.rpc_id(sender_id, {
		"room_id": room_id,
		"max_players": int(room_state.get("max_players", MAX_CLIENTS))
	})
	_broadcast_room_summaries(room_id)
	_broadcast_room_peer_profiles(room_id)
	print("[RoomHub] Peer %d joined room '%s' (%d/%d)." % [sender_id, room_id, peer_ids.size(), int(room_state.get("max_players", MAX_CLIENTS))])

@rpc("any_peer", "reliable")
func _request_room_leave(payload: Dictionary) -> void:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or not api.is_server():
		return
	var sender_id: int = api.get_remote_sender_id()
	if sender_id <= 0:
		return
	var room_id: String = str(payload.get("room_id", "")).strip_edges()
	var authoritative_room_id: String = get_peer_room_id(sender_id)
	if authoritative_room_id.is_empty():
		authoritative_room_id = room_id
	if authoritative_room_id.is_empty():
		return
	print("[RoomHub] Peer %d is leaving room '%s' by explicit client notice." % [sender_id, authoritative_room_id])
	_pending_server_room_joins.erase(sender_id)
	_prune_empty_room_if_orphaned(room_id)
	_remove_peer_from_room(sender_id)
	_peer_last_join_msec.erase(sender_id)
	_peer_join_violations.erase(sender_id)
	_peer_last_keepalive_msec.erase(sender_id)
	_broadcast_room_summaries(authoritative_room_id)
	_broadcast_room_peer_profiles(authoritative_room_id)
	_confirm_room_leave.rpc_id(sender_id, {
		"room_id": authoritative_room_id
	})

@rpc("authority", "reliable")
func _confirm_room_leave(payload: Dictionary) -> void:
	var room_id: String = str(payload.get("room_id", "")).strip_edges()
	if _leave_ack_room_id.is_empty() or room_id == _leave_ack_room_id or room_id == _active_room_id:
		_leave_ack_received = true

@rpc("authority", "reliable")
func _room_join_ready(_payload: Dictionary) -> void:
	_room_join_confirmed = true
	_stop_connection_timeout()
	var api: MultiplayerAPI = _multiplayer_api()
	var local_peer_id: int = api.get_unique_id() if api != null else 0
	print("[ClientNetwork] Room join ready received on attempt #%d room=%s local_peer=%d" % [_client_attempt_serial, _active_room_id, local_peer_id])
	if local_peer_id > 0:
		_peer_room_ids[local_peer_id] = _active_room_id
	if not _active_room_id.is_empty():
		_peer_room_ids[1] = _active_room_id
	request_room_summaries()
	transport_status_changed.emit("Connected to dedicated server.")
	transport_progress_updated.emit("connected", 1.0)
	connected_to_server.emit(local_peer_id)
	call_deferred("_after_client_connected_async")

@rpc("authority", "reliable")
func _reject_room_join(message: String) -> void:
	var resolved_message: String = message.strip_edges() if not message.strip_edges().is_empty() else "The dedicated server rejected this room join."
	_explicit_join_rejection_message = resolved_message
	_pending_attempt = MAX_CONNECT_ATTEMPTS
	_finish_connection_failure(resolved_message)

func _disconnect_peer_after_reject(peer_id: int) -> void:
	if peer_id <= 0:
		return
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_force_disconnect_scene_peer(peer_id)

func _select_joinable_room_candidate(rows: Array) -> Dictionary:
	var preferred_map_id: String = _guess_runtime_map_id()
	var preferred_map_name: String = _guess_runtime_map_name()
	var best_row: Dictionary = {}
	var best_players_count: int = -1
	var best_last_seen: int = -1
	for row_variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant
		if row.has("is_host") and not bool(row.get("is_host", false)):
			continue
		var status: String = str(row.get("status", "")).strip_edges().to_lower()
		if status != "active":
			continue
		var players_count: int = int(row.get("players_count", 0))
		var max_players: int = int(row.get("max_players", MAX_CLIENTS))
		if max_players > 0 and players_count >= max_players:
			continue
		var matches_preferred_room: bool = false
		var row_map_id: String = str(row.get("map_id", "")).strip_edges()
		var row_map_name: String = str(row.get("map_name", "")).strip_edges()
		if not preferred_map_id.is_empty():
			matches_preferred_room = row_map_id == preferred_map_id
			if not matches_preferred_room and row_map_id.is_empty() and not preferred_map_name.is_empty():
				matches_preferred_room = row_map_name == preferred_map_name
		elif not preferred_map_name.is_empty():
			matches_preferred_room = row_map_name == preferred_map_name
		if not matches_preferred_room:
			continue
		var row_last_seen: int = int(row.get("last_seen", 0))
		if players_count > best_players_count or (players_count == best_players_count and row_last_seen > best_last_seen):
			best_players_count = players_count
			best_last_seen = row_last_seen
			best_row = row.duplicate(true)
	# No fallback to a mismatched room — return empty so that connect_or_host
	# creates a new room with the correct map instead of joining an unrelated one.
	return best_row

func _get_connected_player_count() -> int:
	var api: MultiplayerAPI = _multiplayer_api()
	if api == null or api.multiplayer_peer == null:
		return 0
	return api.get_peers().size() + 1

func update_all_rooms_map_state(map_id: String, map_name: String, cloud_version_id: String = "") -> void:
	if not is_host():
		return
	var clean_map_id: String = map_id.strip_edges()
	var clean_cloud_version_id: String = cloud_version_id.strip_edges()
	var resolved_map_name: String = _sanitize_room_map_name(map_name, clean_map_id, _guess_runtime_map_name())
	for room_id_variant in _server_rooms.keys():
		var room_id: String = str(room_id_variant).strip_edges()
		var room_state: Dictionary = _server_rooms.get(room_id, {}) if _server_rooms.get(room_id, {}) is Dictionary else {}
		if room_state.is_empty():
			continue
		room_state["map_id"] = clean_map_id
		room_state["map_name"] = resolved_map_name
		room_state["cloud_version_id"] = clean_cloud_version_id
		_server_rooms[room_id] = room_state
	_current_server_info["map_id"] = clean_map_id
	_current_server_info["map_name"] = resolved_map_name
	_current_server_info["cloud_version_id"] = clean_cloud_version_id
	_broadcast_room_summaries()

func _build_room_id() -> String:
	var stable_room_id: String = _build_stable_public_room_id()
	if not stable_room_id.is_empty():
		return stable_room_id
	var owner_id: String = SupabaseClient.get_user_id()
	if owner_id.is_empty():
		owner_id = CloudAPI.get_current_username().strip_edges().to_lower().replace(" ", "_")
	return "%s:%s:%d" % [_guess_runtime_map_id(), owner_id.substr(0, min(owner_id.length(), 8)), int(Time.get_unix_time_from_system())]

func _build_stable_public_room_id(slot_index: int = 0) -> String:
	var clean_map_id: String = _guess_runtime_map_id().strip_edges().to_lower()
	if clean_map_id.is_empty():
		clean_map_id = DEFAULT_ROOM_MAP_ID
	clean_map_id = clean_map_id.replace(" ", "_")
	clean_map_id = clean_map_id.replace(":", "_")
	return "%s:public:%d" % [clean_map_id, maxi(slot_index, 0)]

func _guess_runtime_map_name() -> String:
	if GameState == null:
		return DEFAULT_ROOM_MAP_NAME
	if GameState.has_method("get_selected_map_display_name"):
		var resolved_name: String = str(GameState.call("get_selected_map_display_name")).strip_edges()
		if not resolved_name.is_empty():
			return resolved_name
	if not str(GameState.selected_map_folder).strip_edges().is_empty():
		return str(GameState.selected_map_folder).get_file().strip_edges()
	var selected_map: String = str(GameState.selected_map).strip_edges()
	return selected_map if not selected_map.is_empty() else DEFAULT_ROOM_MAP_NAME

func _guess_runtime_map_id() -> String:
	if GameState == null:
		return DEFAULT_ROOM_MAP_ID
	# Prefer cloud UUID from target_server_info (set by lobby's Smart Play flow).
	var target_map_id: String = str(GameState.target_server_info.get("map_id", "")).strip_edges()
	if not target_map_id.is_empty():
		return target_map_id
	if GameState.has_method("get_selected_map_identifier"):
		var resolved_id: String = str(GameState.call("get_selected_map_identifier")).strip_edges()
		if not resolved_id.is_empty():
			return resolved_id.to_lower()
	if not str(GameState.selected_map_folder).strip_edges().is_empty():
		return str(GameState.selected_map_folder).get_file().strip_edges().to_lower()
	var selected_map: String = str(GameState.selected_map).strip_edges().to_lower()
	return selected_map if not selected_map.is_empty() else DEFAULT_ROOM_MAP_ID

func _sanitize_room_map_name(map_name: String, map_id: String = "", fallback_name: String = "Untitled Experience") -> String:
	var clean_map_name: String = map_name.strip_edges()
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_name.to_lower() == "classic" or clean_map_id.to_lower() == "classic":
		return "Classic"
	if not clean_map_name.is_empty() and not _looks_like_generated_room_or_map_name(clean_map_name):
		return clean_map_name
	if GameState != null and GameState.has_method("get_selected_map_display_name"):
		var selected_display_name: String = str(GameState.call("get_selected_map_display_name")).strip_edges()
		if not selected_display_name.is_empty() and not _looks_like_generated_room_or_map_name(selected_display_name):
			return selected_display_name
	var clean_fallback_name: String = fallback_name.strip_edges()
	if not clean_fallback_name.is_empty() and not _looks_like_generated_room_or_map_name(clean_fallback_name):
		return clean_fallback_name
	return "Untitled Experience"

func _looks_like_generated_room_or_map_name(value: String) -> bool:
	var clean_value: String = value.strip_edges().to_lower()
	if clean_value.is_empty() or clean_value == "classic":
		return false
	var matcher := RegEx.new()
	if matcher.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}([:_].+)?$") != OK:
		return false
	return matcher.search(clean_value) != null

func _guess_runtime_cloud_version_id() -> String:
	var target_version: String = str(GameState.target_server_info.get("cloud_version_id", "")).strip_edges() if GameState != null else ""
	if not target_version.is_empty():
		return target_version
	return str(_current_server_info.get("cloud_version_id", "")).strip_edges()

func _get_default_ws_url() -> String:
	if ProjectSettings.has_setting("application/config/dedicated_server_ws_url"):
		var configured_url: String = str(ProjectSettings.get_setting("application/config/dedicated_server_ws_url", DEFAULT_DEDICATED_WS_URL)).strip_edges()
		if not configured_url.is_empty():
			return configured_url
	return DEFAULT_DEDICATED_WS_URL

func _get_runtime_target_ws_url() -> String:
	var routed_url: String = _get_routed_server_ws_url_for(_guess_runtime_map_id(), _guess_runtime_map_name())
	if not routed_url.is_empty():
		return routed_url
	return _get_default_ws_url()

func _select_bootstrap_server_ws_url_for(rows: Array, map_id: String, map_name: String) -> String:
	var routed_urls: Array[String] = _get_routed_server_ws_urls_for(map_id, map_name)
	if routed_urls.is_empty():
		return _get_default_ws_url()
	var load_by_url: Dictionary = {}
	for row_variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant
		var clean_server_url: String = str(row.get("server_url", "")).strip_edges().trim_suffix("/")
		if clean_server_url.is_empty():
			continue
		load_by_url[clean_server_url] = int(load_by_url.get(clean_server_url, 0)) + maxi(int(row.get("players_count", 0)), 0)
	for routed_url in routed_urls:
		if not load_by_url.has(routed_url):
			return routed_url
	var best_url: String = routed_urls[0]
	var best_load: int = int(load_by_url.get(best_url, 2147483647))
	for routed_url in routed_urls:
		var current_load: int = int(load_by_url.get(routed_url, 2147483647))
		if current_load < best_load:
			best_load = current_load
			best_url = routed_url
	return best_url

func _get_routed_server_ws_url_for(map_id: String, map_name: String) -> String:
	var routed_urls: Array[String] = _get_routed_server_ws_urls_for(map_id, map_name)
	return routed_urls[0] if not routed_urls.is_empty() else ""

func _get_routed_server_ws_urls_for(map_id: String, map_name: String) -> Array[String]:
	var routes: Dictionary = _get_dedicated_server_route_map()
	if routes.is_empty():
		return []
	var lookup_keys: Array[String] = []
	var clean_map_id: String = map_id.strip_edges()
	var clean_map_name: String = map_name.strip_edges()
	if not clean_map_id.is_empty():
		lookup_keys.append(clean_map_id)
		lookup_keys.append(clean_map_id.to_lower())
	if not clean_map_name.is_empty():
		lookup_keys.append(clean_map_name)
		lookup_keys.append(clean_map_name.to_lower())
	for key in lookup_keys:
		var routed_urls_variant: Variant = routes.get(key, [])
		if routed_urls_variant is Array and not (routed_urls_variant as Array).is_empty():
			var routed_urls: Array[String] = []
			for url_variant in routed_urls_variant:
				var clean_url: String = str(url_variant).strip_edges()
				if not clean_url.is_empty():
					routed_urls.append(clean_url)
			if not routed_urls.is_empty():
				return routed_urls
	return []

func _get_dedicated_server_route_map() -> Dictionary:
	var raw_routes: String = OS.get_environment("DEDICATED_SERVER_ROUTES_JSON").strip_edges()
	if raw_routes.is_empty() and ProjectSettings.has_setting("application/config/dedicated_server_routes_json"):
		raw_routes = str(ProjectSettings.get_setting("application/config/dedicated_server_routes_json", "")).strip_edges()
	if raw_routes.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(raw_routes) != OK or not (json.data is Dictionary):
		return {}
	var route_map: Dictionary = {}
	for key_variant in json.data.keys():
		var clean_key: String = str(key_variant).strip_edges()
		if clean_key.is_empty():
			continue
		var value_variant: Variant = json.data[key_variant]
		var routed_urls: Array[String] = _extract_dedicated_route_urls(value_variant)
		if routed_urls.is_empty():
			continue
		route_map[clean_key] = routed_urls.duplicate()
		route_map[clean_key.to_lower()] = routed_urls.duplicate()
	return route_map

func _extract_dedicated_route_urls(value_variant: Variant) -> Array[String]:
	var routed_urls: Array[String] = []
	if value_variant is Dictionary:
		var value_dict: Dictionary = value_variant
		if value_dict.get("server_urls", []) is Array:
			for url_variant in value_dict.get("server_urls", []):
				var clean_url: String = str(url_variant).strip_edges().trim_suffix("/")
				if not clean_url.is_empty():
					routed_urls.append(clean_url)
		else:
			var single_url: String = str(value_dict.get("server_url", "")).strip_edges().trim_suffix("/")
			if not single_url.is_empty():
				routed_urls.append(single_url)
	elif value_variant is Array:
		for url_variant in value_variant:
			var clean_url: String = str(url_variant).strip_edges().trim_suffix("/")
			if not clean_url.is_empty():
				routed_urls.append(clean_url)
	else:
		var clean_url: String = str(value_variant).strip_edges().trim_suffix("/")
		if not clean_url.is_empty():
			routed_urls.append(clean_url)
	return routed_urls

func _get_platform_public_ws_url() -> String:
	var explicit_ws_url: String = OS.get_environment("PUBLIC_SERVER_WS_URL").strip_edges().trim_suffix("/")
	if not explicit_ws_url.is_empty():
		return explicit_ws_url
	return ""

func _get_advertised_server_ws_url() -> String:
	var platform_url: String = _get_platform_public_ws_url()
	if not platform_url.is_empty():
		return platform_url
	var configured_url: String = _get_default_ws_url()
	if not configured_url.is_empty():
		return configured_url
	return _build_ws_url(_get_public_dedicated_host(), _get_public_dedicated_port())

func _get_public_dedicated_host() -> String:
	var platform_url: String = _get_platform_public_ws_url()
	if not platform_url.is_empty():
		var platform_host: String = _extract_public_host(platform_url)
		if not platform_host.is_empty():
			return platform_host
	if ProjectSettings.has_setting("application/config/dedicated_server_public_host"):
		var configured_host: String = str(ProjectSettings.get_setting("application/config/dedicated_server_public_host", DEFAULT_DEDICATED_HOST)).strip_edges()
		if not configured_host.is_empty():
			return configured_host
	return DEFAULT_DEDICATED_HOST

func _get_public_dedicated_port() -> int:
	var platform_url: String = _get_platform_public_ws_url()
	if not platform_url.is_empty():
		var platform_port: int = _extract_public_port(platform_url)
		if platform_port > 0:
			return platform_port
	if ProjectSettings.has_setting("application/config/dedicated_server_public_port"):
		var configured_port: int = int(ProjectSettings.get_setting("application/config/dedicated_server_public_port", DEFAULT_EXTERNAL_WS_PORT))
		if configured_port > 0:
			return configured_port
	return DEFAULT_EXTERNAL_WS_PORT

func _get_default_ws_path() -> String:
	if ProjectSettings.has_setting("application/config/dedicated_server_ws_path"):
		var configured_path: String = str(ProjectSettings.get_setting("application/config/dedicated_server_ws_path", DEFAULT_WS_PATH)).strip_edges()
		if not configured_path.is_empty():
			return configured_path if configured_path.begins_with("/") else "/%s" % configured_path
	return DEFAULT_WS_PATH

func _build_ws_url(address: String, port: int) -> String:
	var clean_address: String = address.strip_edges()
	if clean_address.is_empty():
		return _get_default_ws_url()
	if clean_address.begins_with("ws://") or clean_address.begins_with("wss://"):
		return clean_address
	var use_secure: bool = port <= 0 or port == 443 or clean_address.contains("hf.space")
	var scheme: String = "wss://" if use_secure else "ws://"
	var clean_path: String = _get_default_ws_path()
	if clean_address.contains("/"):
		return "%s%s" % [scheme, clean_address.trim_prefix("/")]
	if port > 0 and port != 443 and port != 80:
		return "%s%s:%d%s" % [scheme, clean_address, port, clean_path]
	return "%s%s%s" % [scheme, clean_address, clean_path]

func _extract_public_host(ws_url: String) -> String:
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

func _extract_public_port(ws_url: String) -> int:
	var clean_url: String = ws_url.strip_edges()
	var is_secure: bool = clean_url.begins_with("wss://")
	clean_url = clean_url.trim_prefix("ws://")
	clean_url = clean_url.trim_prefix("wss://")
	var slash_index: int = clean_url.find("/")
	if slash_index >= 0:
		clean_url = clean_url.substr(0, slash_index)
	var colon_index: int = clean_url.find(":")
	if colon_index >= 0:
		return int(clean_url.substr(colon_index + 1))
	return 443 if is_secure else 80

func _get_dedicated_bind_port(fallback_port: int) -> int:
	var env_port: String = OS.get_environment("GODOT_SERVER_PORT").strip_edges()
	if not env_port.is_empty():
		return int(env_port)
	if fallback_port > 0:
		return fallback_port
	return 7860

func _is_dedicated_server_runtime() -> bool:
	if GameState != null and GameState.has_method("is_dedicated_server_runtime"):
		return bool(GameState.is_dedicated_server_runtime())
	return DisplayServer.get_name() == "headless"
