extends SceneTree
## Actual room RPC over isolated WebSocket: reject old protocol before map sync.
const PORT := 18148
const OLD_PROTOCOL := "vps-ws-2026-10-10-1"
const OLD_ROOM := "protocol-gate-old"
const NEW_ROOM := "protocol-gate-current"
const OUTPUT := "res://.codex-tmp/performance/protocol-gate/"

var network: Node
var timed_out := false
var failure_message := ""
var joined := false
var map_loads := 0
var saw_fresh_member := false
var old_runtime_created := false

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains(".codex-tmp/"):
		push_error("Protocol gate requires isolated APPDATA under .codex-tmp")
		quit(2)
		return
	network = root.get_node("NetworkManager")
	var args := OS.get_cmdline_user_args()
	var server := args.has("--server")
	create_timer(25).timeout.connect(func(): timed_out = true)
	if server:
		root.get_node("GameState").configure_dedicated_server(PORT, "classic")
		if network.host_game(PORT) != OK: quit(2); return
		FileAccess.open(OUTPUT + "ready", FileAccess.WRITE).store_string("ready")
		while not timed_out and not FileAccess.file_exists(OUTPUT + "clients-done"):
			old_runtime_created = old_runtime_created or network._server_rooms.has(OLD_ROOM)
			saw_fresh_member = saw_fresh_member or not network.get_room_member_peer_ids(NEW_ROOM).is_empty()
			await process_frame
		var passed := not timed_out and not old_runtime_created and saw_fresh_member
		print("PROTOCOL_GATE_SERVER_PASS=", passed, " old_room_created=", old_runtime_created, " fresh_member_seen=", saw_fresh_member)
		network.disconnect_from_session()
		quit(0 if passed else 1)
		return
	var old := args.has("--old")
	var api := get_multiplayer()
	# The wire payload is supplied explicitly; retain the real RPC receivers and
	# failure handling, but bypass the automatic current-version join request.
	for connection in api.get_signal_connection_list("connected_to_server"):
		api.disconnect("connected_to_server", connection.callable)
	network.connection_failed.connect(func(message): failure_message = message)
	network.connected_to_server.connect(func(_id): joined = true)
	root.get_node("MapManager").map_loaded.connect(func(_id, _result): map_loads += 1)
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_client("ws://127.0.0.1:%d" % PORT) != OK: quit(2); return
	api.multiplayer_peer = peer
	while not timed_out and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await process_frame
	if timed_out or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: quit(1); return
	var current: String = network.get_script().get_script_constant_map()["NETWORK_PROTOCOL_VERSION"]
	network._request_room_join.rpc_id(1, {
		"room_id": OLD_ROOM if old else NEW_ROOM,
		"protocol_version": OLD_PROTOCOL if old else current,
		"map_id": "classic", "map_name": "Classic", "user_id": "",
		"username": "ProtocolFixture", "create_if_missing": true, "max_players": 4
	})
	while not timed_out and failure_message.is_empty() and not joined:
		await process_frame
	if old:
		var passed := not timed_out and not joined and map_loads == 0 and failure_message.contains("обновление Bobux")
		print("PROTOCOL_GATE_OLD_PASS=", passed, " message_received=", not failure_message.is_empty(), " map_loads=", map_loads, " message=", failure_message)
		quit(0 if passed else 1)
	else:
		var passed := not timed_out and joined and failure_message.is_empty() and map_loads == 1
		await create_timer(0.5).timeout
		print("PROTOCOL_GATE_CURRENT_PASS=", passed, " joined=", joined, " map_loads=", map_loads)
		FileAccess.open(OUTPUT + "clients-done", FileAccess.WRITE).store_string("done")
		network.disconnect_from_session()
		quit(0 if passed else 1)
