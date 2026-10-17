extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	multiplayer_poll = false
	var network := root.get_node("NetworkManager")
	var api: MultiplayerAPI = network._multiplayer_api()
	var closed := ENetMultiplayerPeer.new()
	var ok := closed.create_client("127.0.0.1", 18991) == OK
	api.multiplayer_peer = closed
	closed.close()
	for index in 100: network._process(0.1)
	ok = ok and network._manual_network_poll_accumulator == 0.0 and network._get_connected_player_count() == 0
	api.multiplayer_peer = null
	var listener := TCPServer.new()
	ok = ok and listener.listen(0, "127.0.0.1") == OK
	var connecting := WebSocketMultiplayerPeer.new()
	ok = ok and connecting.create_client("ws://127.0.0.1:%d" % listener.get_local_port()) == OK
	api.multiplayer_peer = connecting
	for index in 10:
		network._process(0.1)
		await process_frame
	ok = ok and listener.is_connection_available()
	api.multiplayer_peer = null
	connecting.close()
	listener.stop()
	print("[network-poll] PASS=", ok, " closed ENet stays idle, connecting WebSocket still polls")
	quit(0 if ok else 1)
