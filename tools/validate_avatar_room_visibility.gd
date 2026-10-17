extends SceneTree
## Real server spawns and client-owned movement, including a room switch.
var players: Node3D
var spawner: MultiplayerSpawner
var server := false
var room := "a"
var auth: Node
var joined := {}
var reports := {}
var wrong_room_spawned := false
var timed_out := false
var expected_disconnect := false

func _initialize() -> void: run.call_deferred()

func run() -> void:
	server = OS.get_cmdline_user_args().has("--server")
	room = "b" if OS.get_cmdline_user_args().has("--other") else "a"
	for event in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in root.multiplayer.get_signal_connection_list(event): root.multiplayer.disconnect(event, connection.callable)
	# Preserve the game's WebSocket poll while avoiding production login state.
	root.get_node("NetworkManager").set_process(true)
	auth = load("res://tools/fixtures/avatar_visibility_auth.gd").new()
	auth.name = "TestAuth"
	root.add_child(auth)
	var host := Node3D.new()
	host.name = "VisibilityTest"
	root.add_child(host)
	players = Node3D.new()
	players.name = "Players"
	host.add_child(players)
	players.child_entered_tree.connect(func(player):
		if not server and player.network_room_id != room: wrong_room_spawned = true
	)
	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = spawn_player
	host.add_child(spawner)
	var peer := WebSocketMultiplayerPeer.new()
	var result := peer.create_server(18742) if server else peer.create_client("ws://127.0.0.1:18742")
	if result != OK: quit(2); return
	root.multiplayer.multiplayer_peer = peer
	create_timer(25).timeout.connect(func(): timed_out = true)
	if server:
		auth.peer_joined.connect(func(id, target_room):
			joined[id] = target_room
			spawner.spawn({"id": id, "room": target_room})
			root.get_node("NetworkManager").room_summaries_updated.emit([])
		)
		auth.observed.connect(func(id, phase, passed): reports[str(phase) + ":" + str(id)] = passed)
		FileAccess.open("res://.codex-tmp/avatar-visibility-ready", FileAccess.WRITE).store_string("ready")
		while joined.size() < 3 and not timed_out: await process_frame
		if timed_out: quit(1); return
		while not timed_out:
			var ready := true
			for id in joined: ready = ready and reports.has("0:" + str(id))
			if ready: break
			await process_frame
		var passed := check_replication_encoding()
		passed = await check_phase(1) and passed
		var moving := 0
		for id in joined:
			if joined[id] == "b": moving = id
		players.get_node(str(moving)).queue_free()
		await process_frame
		joined[moving] = "a"
		root.get_node("NetworkManager")._peer_room_ids[moving] = "a"
		# Membership precedes the spawn, matching the production room hub.
		auth.check.rpc(0, joined)
		await create_timer(.1).timeout
		spawner.spawn({"id": moving, "room": "a"})
		root.get_node("NetworkManager").room_summaries_updated.emit([])
		passed = await check_phase(2) and passed
		auth.finish.rpc(passed)
		await create_timer(.1).timeout
		print("[visibility] SERVER PASS=", passed, " players=", players.get_child_count(), " reports=", reports)
		quit(0 if passed else 1)
		return
	auth.check_requested.connect(check_client)
	root.multiplayer.server_disconnected.connect(func():
		if not expected_disconnect:
			print("[visibility] Unexpected server disconnect")
			timed_out = true
		root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	)
	auth.finished.connect(func(passed):
		expected_disconnect = true
		await create_timer(.4).timeout
		quit(0 if passed else 1)
	)
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and not timed_out: await process_frame
	if timed_out or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("[visibility] Client could not connect to isolated server")
		quit(1)
		return
	auth.join.rpc_id(1, room)
	await auth.accepted
	auth.report.rpc_id(1, 0, true)
	while not timed_out: await process_frame
	quit(1)

func check_phase(phase: int) -> bool:
	auth.check.rpc(phase, joined)
	while not timed_out:
		var complete := true
		for id in joined: complete = complete and reports.has(str(phase) + ":" + str(id))
		if complete: break
		await process_frame
	var passed := not timed_out and players.get_child_count() == 3
	for id in joined:
		passed = passed and reports.get(str(phase) + ":" + str(id), false)
		var player := players.get_node_or_null(str(id))
		passed = passed and player != null and player.network_position.is_equal_approx(Vector3(phase * 10, 3, 0))
	return passed

func check_replication_encoding() -> bool:
	var probe: Node = load("res://tools/fixtures/replication_encoding_probe.gd").new()
	root.add_child(probe)
	probe.set_process(false)
	var subscriptions := {}
	var observers: Array = []
	for id in joined:
		if joined[id] == "a":
			subscriptions[id] = {"room": "a", "token": id}
			observers.append(id)
	probe._subscriptions = subscriptions
	var ops := [["pose", "moving-disaster", Transform3D.IDENTITY, 0]]
	probe._broadcast_room_changes("a", ops)
	var passed: bool = probe.encoded_count == 1 and probe.received.size() == 2
	for id in observers: passed = passed and probe.received[id].ops == ops
	# Mixed updates preserve private PlayerGui data while the public observer
	# still shares the same encoded view as every other non-owner.
	probe.encoded_count = 0
	probe.received.clear()
	ops.append(["put", {"ref": "private-hud", "owner": observers[0], "properties": {"Text": "secret"}}])
	probe._broadcast_room_changes("a", ops)
	passed = passed and probe.encoded_count == 2 and probe.received[observers[0]].ops.size() == 2 and probe.received[observers[1]].ops.size() == 1
	probe.queue_free()
	print("[replication-encoding] shared_public_once=true privacy=", passed)
	return passed

func check_client(phase: int, assignments: Dictionary) -> void:
	var own := root.multiplayer.get_unique_id()
	room = assignments[own]
	if phase == 0: return
	wrong_room_spawned = false
	await create_timer(.8).timeout
	var mine := players.get_node_or_null(str(own))
	if mine != null: mine.network_position = Vector3(phase * 10, 3, 0)
	await create_timer(1).timeout
	var expected := 0
	for id in assignments:
		if assignments[id] == room: expected += 1
	var passed := not wrong_room_spawned and players.get_child_count() == expected
	for player in players.get_children():
		passed = passed and player.network_room_id == room and player.network_position.is_equal_approx(Vector3(phase * 10, 3, 0))
	print("[visibility] CLIENT room=", room, " phase=", phase, " count=", players.get_child_count(), " no_cross_room_spawn=", not wrong_room_spawned, " PASS=", passed)
	auth.report.rpc_id(1, phase, passed)

func spawn_player(data: Dictionary) -> Node:
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = str(data.id)
	player.network_room_id = data.room
	player.set_multiplayer_authority(int(data.id))
	player.set_process(false)
	player.set_physics_process(false)
	player.ready.connect(func():
		player.set_process(false)
		player.set_physics_process(false)
	)
	return player
