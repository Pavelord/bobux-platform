extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

var _connected: bool = false
var _spawn_confirmed: bool = false
var _failed: bool = false
var _disconnect_expected: bool = false
var _move_started: bool = false
var _move_finished: bool = false
var _move_elapsed: float = 0.0
var _remote_positions: Dictionary = {}
var _remote_movement_detected: bool = false
var _last_remote_log_msec: int = 0
var _last_local_log_msec: int = 0
var _respawn_triggered: bool = false
var _respawn_verified: bool = false
var _respawn_elapsed: float = 0.0
var _respawn_wait_elapsed: float = 0.0
var _respawn_reference_position: Vector3 = Vector3.ZERO

func _get_autoload(name: String) -> Node:
	return root.get_node_or_null(NodePath(name))

func _build_probe_server_url(host: String, port: int) -> String:
	var clean_host: String = host.strip_edges()
	if clean_host.begins_with("ws://") or clean_host.begins_with("wss://"):
		return clean_host
	var use_secure: bool = port == 443 or clean_host.contains("hf.space")
	var scheme: String = "wss" if use_secure else "ws"
	if port > 0 and port != 443 and port != 80:
		return "%s://%s:%d/ws" % [scheme, clean_host, port]
	return "%s://%s/ws" % [scheme, clean_host]

func _initialize() -> void:
	await process_frame
	var network_manager: Node = _get_autoload("NetworkManager")
	var game_state: Node = _get_autoload("GameState")
	var cloud_api: Node = _get_autoload("CloudAPI")
	var user_session: Node = _get_autoload("UserSession")
	var auth_compat_client: Node = _get_autoload("SupabaseClient")
	if network_manager == null or game_state == null:
		push_error("[MainJoinProbe] Required autoloads are unavailable.")
		quit(1)
		return
	if cloud_api != null and cloud_api.has_method("ensure_authenticated_session"):
		var auth_result: Dictionary = await cloud_api.ensure_authenticated_session()
		print("[MainJoinProbe] Auth ok=%s user=%s" % [str(auth_result.get("ok", false)), str(cloud_api.call("get_current_user_id"))])
	var forced_user_id: String = OS.get_environment("CODEX_TEST_USER_ID").strip_edges()
	if cloud_api != null and not forced_user_id.is_empty():
		cloud_api.set("_auth_user_id", forced_user_id)
		print("[MainJoinProbe] Forced cloud user id=%s" % forced_user_id)
	if user_session != null:
		var override_username: String = OS.get_environment("CODEX_TEST_USERNAME").strip_edges()
		if not override_username.is_empty():
			user_session.set("username", override_username)
			user_session.set("is_logged_in", true)
	if auth_compat_client != null and auth_compat_client.has_method("get_user_id"):
		print("[MainJoinProbe] Session user id=%s" % str(auth_compat_client.call("get_user_id")))
	if not network_manager.connected_to_server.is_connected(_on_connected):
		network_manager.connected_to_server.connect(_on_connected)
	if not network_manager.connection_failed.is_connected(_on_failed):
		network_manager.connection_failed.connect(_on_failed)
	if not network_manager.server_disconnected.is_connected(_on_disconnected):
		network_manager.server_disconnected.connect(_on_disconnected)
	var host: String = OS.get_environment("DEDICATED_PROBE_HOST").strip_edges()
	var port_raw: String = OS.get_environment("DEDICATED_PROBE_PORT").strip_edges()
	var room_id: String = OS.get_environment("DEDICATED_PROBE_ROOM_ID").strip_edges()
	var create_if_missing: bool = OS.get_environment("DEDICATED_PROBE_CREATE_IF_MISSING").strip_edges().to_lower() != "false"
	if host.is_empty():
		host = "127.0.0.1"
	var port: int = int(port_raw) if not port_raw.is_empty() else 7860
	game_state.call("configure_target_join", {
		"room_id": room_id if not room_id.is_empty() else "codex-reconnect-room",
		"server_url": _build_probe_server_url(host, port),
		"ip": host,
		"port": port,
		"create_if_missing": create_if_missing,
		"map_name": "classic",
		"map_id": "classic"
	}, {})
	change_scene_to_file(MAIN_SCENE_PATH)
	var hold_seconds_raw: String = OS.get_environment("DEDICATED_PROBE_HOLD_SECONDS").strip_edges()
	var hold_seconds: float = float(hold_seconds_raw) if not hold_seconds_raw.is_empty() else 4.0
	await create_timer(hold_seconds).timeout
	if OS.get_environment("CODEX_TEST_EXPECT_REMOTE_MOVEMENT").strip_edges().to_lower() == "true" and not _remote_movement_detected:
		push_error("[MainJoinProbe] Remote movement was expected but never observed.")
		_failed = true
	var graceful_leave_enabled: bool = OS.get_environment("CODEX_TEST_GRACEFUL_LEAVE").strip_edges().to_lower() != "false"
	if graceful_leave_enabled:
		_disconnect_expected = true
		var scene: Node = current_scene
		if scene != null and scene.has_method("leave_game"):
			await scene.call("leave_game")
			await create_timer(1.0).timeout
	quit(0 if _connected and not _failed else 1)

func _process(_delta: float) -> bool:
	if _spawn_confirmed:
		_run_optional_local_move(_delta)
		_run_optional_respawn_test(_delta)
		_poll_remote_players()
		return false
	var scene: Node = current_scene
	if scene == null or not scene.has_method("_get_local_player"):
		return false
	var local_player: Variant = scene.call("_get_local_player")
	if local_player == null:
		return false
	_spawn_confirmed = true
	print("[MainJoinProbe] Local player spawned successfully. authority=%d is_auth=%s pos=%s" % [local_player.get_multiplayer_authority(), str(local_player.is_multiplayer_authority()), str(local_player.global_position)])
	return false

func _run_optional_local_move(delta: float) -> void:
	if _move_finished:
		return
	var move_speed_raw: String = OS.get_environment("CODEX_TEST_MOVE_SPEED").strip_edges()
	var move_duration_raw: String = OS.get_environment("CODEX_TEST_MOVE_DURATION").strip_edges()
	var move_axis: String = OS.get_environment("CODEX_TEST_MOVE_AXIS").strip_edges().to_lower()
	var move_speed: float = float(move_speed_raw) if not move_speed_raw.is_empty() else 0.0
	var move_duration: float = float(move_duration_raw) if not move_duration_raw.is_empty() else 0.0
	if move_speed <= 0.0 or move_duration <= 0.0:
		_move_finished = true
		return
	var scene: Node = current_scene
	if scene == null or not scene.has_method("_get_local_player"):
		return
	var local_player: CharacterBody3D = scene.call("_get_local_player") as CharacterBody3D
	if local_player == null:
		return
	if not _move_started:
		_move_started = true
		print("[MainJoinProbe] Starting scripted local movement.")
	_move_elapsed += delta
	var axis_vector: Vector3 = Vector3.FORWARD
	match move_axis:
		"x":
			axis_vector = Vector3.RIGHT
		"z":
			axis_vector = Vector3.FORWARD
		"-x":
			axis_vector = Vector3.LEFT
		"-z":
			axis_vector = Vector3.BACK
	local_player.global_position += axis_vector * move_speed * delta
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_local_log_msec > 250:
		_last_local_log_msec = now_msec
		print("[MainJoinProbe] Local peer authority=%d is_auth=%s pos=%s." % [local_player.get_multiplayer_authority(), str(local_player.is_multiplayer_authority()), str(local_player.global_position)])
	if _move_elapsed >= move_duration:
		_move_finished = true
		print("[MainJoinProbe] Scripted local movement finished at %s." % local_player.global_position)

func _run_optional_respawn_test(delta: float) -> void:
	if _respawn_verified:
		return
	var trigger_after_raw: String = OS.get_environment("CODEX_TEST_TRIGGER_RESPAWN_AFTER").strip_edges()
	var trigger_after: float = float(trigger_after_raw) if not trigger_after_raw.is_empty() else 0.0
	if trigger_after <= 0.0:
		_respawn_verified = true
		return
	var scene: Node = current_scene
	if scene == null or not scene.has_method("_get_local_player"):
		return
	var local_player: CharacterBody3D = scene.call("_get_local_player") as CharacterBody3D
	if local_player == null:
		return
	if not _respawn_triggered:
		_respawn_elapsed += delta
		if _respawn_elapsed < trigger_after:
			return
		_respawn_triggered = true
		_respawn_wait_elapsed = 0.0
		_respawn_reference_position = local_player.global_position
		print("[MainJoinProbe] Triggering scripted death at %s." % _respawn_reference_position)
		if local_player.has_method("kill_now"):
			local_player.call("kill_now")
		return
	_respawn_wait_elapsed += delta
	var current_health: int = int(local_player.get("current_health"))
	var moved_after_respawn: bool = local_player.global_position.distance_to(_respawn_reference_position) > 0.5
	if current_health > 0 and moved_after_respawn:
		_respawn_verified = true
		print("[MainJoinProbe] Authoritative respawn observed at %s." % local_player.global_position)
		return
	var respawn_timeout_raw: String = OS.get_environment("CODEX_TEST_RESPAWN_TIMEOUT").strip_edges()
	var respawn_timeout: float = float(respawn_timeout_raw) if not respawn_timeout_raw.is_empty() else 5.0
	if _respawn_wait_elapsed >= respawn_timeout:
		_failed = true
		push_error("[MainJoinProbe] Respawn did not complete within %.2f seconds." % respawn_timeout)
		quit(1)

func _poll_remote_players() -> void:
	var scene: Node = current_scene
	if scene == null:
		return
	var players_root: Node = scene.get_node_or_null("World/Players")
	if players_root == null:
		return
	var local_peer_id: int = 0
	var network_manager: Node = _get_autoload("NetworkManager")
	if network_manager != null and network_manager.has_method("get_unique_id"):
		local_peer_id = int(network_manager.call("get_unique_id"))
	for child in players_root.get_children():
		if not (child is CharacterBody3D):
			continue
		var player: CharacterBody3D = child as CharacterBody3D
		var peer_id: int = int(player.name)
		if peer_id <= 0 or peer_id == local_peer_id:
			continue
		var current_pos: Vector3 = player.global_position
		if not _remote_positions.has(peer_id):
			_remote_positions[peer_id] = current_pos
			print("[MainJoinProbe] Tracking remote peer %d at %s." % [peer_id, current_pos])
			continue
		var previous_pos: Vector3 = _remote_positions[peer_id]
		if current_pos.distance_to(previous_pos) > 0.05:
			_remote_positions[peer_id] = current_pos
			_remote_movement_detected = true
			var now_msec: int = Time.get_ticks_msec()
			if now_msec - _last_remote_log_msec > 150:
				_last_remote_log_msec = now_msec
				print("[MainJoinProbe] Remote peer %d moved to %s." % [peer_id, current_pos])

func _on_connected(peer_id: int) -> void:
	_connected = true
	print("[MainJoinProbe] Connected as peer %d." % peer_id)

func _on_failed(message: String) -> void:
	_failed = true
	push_error("[MainJoinProbe] Connection failed: %s" % message)
	quit(1)

func _on_disconnected() -> void:
	if _disconnect_expected:
		print("[MainJoinProbe] Session closed after graceful leave.")
		return
	_failed = true
	push_error("[MainJoinProbe] Server disconnected unexpectedly.")
	quit(1)
