extends SceneTree

var _hold_timer: SceneTreeTimer = null

func _get_autoload(name: String) -> Node:
	return root.get_node_or_null(NodePath(name))

func _initialize() -> void:
	var network_manager: Node = _get_autoload("NetworkManager")
	if network_manager == null:
		push_error("[DedicatedProbe] NetworkManager autoload is unavailable.")
		quit(1)
		return
	await process_frame
	if network_manager.connected_to_server.is_connected(_on_connected) == false:
		network_manager.connected_to_server.connect(_on_connected)
	if network_manager.connection_failed.is_connected(_on_failed) == false:
		network_manager.connection_failed.connect(_on_failed)
	if network_manager.server_disconnected.is_connected(_on_disconnected) == false:
		network_manager.server_disconnected.connect(_on_disconnected)
	if network_manager.has_signal("room_summaries_updated") and network_manager.room_summaries_updated.is_connected(_on_room_summaries_updated) == false:
		network_manager.room_summaries_updated.connect(_on_room_summaries_updated)
	var host: String = OS.get_environment("DEDICATED_PROBE_HOST").strip_edges()
	var port_raw: String = OS.get_environment("DEDICATED_PROBE_PORT").strip_edges()
	var room_id: String = OS.get_environment("DEDICATED_PROBE_ROOM_ID").strip_edges()
	var create_if_missing: bool = OS.get_environment("DEDICATED_PROBE_CREATE_IF_MISSING").strip_edges().to_lower() != "false"
	if host.is_empty():
		host = "127.0.0.1"
	var port: int = int(port_raw) if not port_raw.is_empty() else 7860
	var err: Error = OK
	if not room_id.is_empty():
		err = await network_manager.join_targeted_room({
			"room_id": room_id,
			"ip": host,
			"port": port,
			"create_if_missing": create_if_missing
		})
	else:
		err = await network_manager.join_game(host, port)
	if err != OK:
		push_error("[DedicatedProbe] join_game failed immediately: %s" % error_string(err))
		quit(1)

func _on_connected(peer_id: int) -> void:
	print("[DedicatedProbe] Connected to dedicated server as peer %d." % peer_id)
	var hold_seconds_raw: String = OS.get_environment("DEDICATED_PROBE_HOLD_SECONDS").strip_edges()
	var hold_seconds: float = float(hold_seconds_raw) if not hold_seconds_raw.is_empty() else 0.0
	if hold_seconds <= 0.0:
		quit(0)
		return
	_hold_timer = create_timer(hold_seconds)
	await _hold_timer.timeout
	quit(0)

func _on_failed(message: String) -> void:
	push_error("[DedicatedProbe] Connection failed: %s" % message)
	quit(1)

func _on_disconnected() -> void:
	push_error("[DedicatedProbe] Server disconnected before probe completed.")
	quit(1)

func _on_room_summaries_updated(summaries: Array) -> void:
	print("[DedicatedProbe] Room summaries: %s" % JSON.stringify(summaries))
