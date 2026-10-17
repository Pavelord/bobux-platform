extends SceneTree
## Real ENet server + two clients, production Player scene/methods and exact
## published City Sit source. No live map/account writes.
const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
var Seats: GDScript
var bridge: Node
var engine: Node
var auth: Node
var worlds := {}
var actors := {}
var reports := {}
var peer_list: Array[int] = []
var observed := {}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	bridge = root.get_node("ImportedPlaceNetwork")
	engine = root.get_node("LuaScriptEngine")
	Seats = load("res://addons/roblox_runtime/roblox_seat_authority.gd")
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in root.multiplayer.get_signal_connection_list(signal_name): root.multiplayer.disconnect(signal_name, connection.callable)
	auth = load("res://tools/fixtures/seat_test_auth.gd").new()
	auth.name = "SeatTestAuth"
	root.add_child(auth)
	var peer := ENetMultiplayerPeer.new()
	if OS.get_cmdline_user_args().has("--server"):
		if peer.create_server(18746) != OK: quit(2); return
		root.multiplayer.multiplayer_peer = peer
		await make_world("a", Vector3(600000, 0, 630000), true)
		await make_world("b", Vector3(640000, 0, 600000), true)
		auth.peer_joined.connect(joined)
		auth.check_actor = check_actor
		auth.finished.connect(func(id: int, ok: bool): reports[id] = ok)
		FileAccess.open("res://.codex-tmp/halloween/city-rp/seat-server-ready", FileAccess.WRITE).store_string("ready")
		var until := Time.get_ticks_msec() + 35000
		while reports.size() < 2 and Time.get_ticks_msec() < until: await create_timer(0.05).timeout
		var diagnostics: Dictionary = engine.get_runtime_diagnostics()
		var ok := reports.size() == 2 and not reports.values().has(false) and int(diagnostics.get("failed", 0)) == 0
		print("[seat-server] reports=", reports, " diagnostics=", diagnostics, " PASS=", ok)
		for world in worlds.values():
			engine.stop_all_scripts(world)
			bridge.unregister_workspace(world)
		for actor in actors.values():
			var synchronizer: Node = actor.get_node_or_null("StateSynchronizer")
			if synchronizer != null: actor.remove_child(synchronizer); synchronizer.queue_free()
		quit(0 if ok else 1); return
	peer.create_client("127.0.0.1", 18746)
	root.multiplayer.multiplayer_peer = peer
	await root.multiplayer.connected_to_server
	auth.join.rpc_id(1, "a")
	await auth.accepted
	var world := await make_world("a", Vector3.ZERO, false)
	bridge.register_workspace(world, "a")
	var until := Time.get_ticks_msec() + 10000
	while not bool(world.get_meta("bobux_replica_ready", false)) and Time.get_ticks_msec() < until: await process_frame
	# Wait for both test players and index both production avatars. Observer
	# occupancy must resolve when the second avatar arrives after the snapshot.
	var player_peers: Array[int] = []
	while player_peers.size() < 2 and Time.get_ticks_msec() < until:
		player_peers.clear()
		for ref in bridge._client.nodes:
			if str(ref).begins_with("player:") and str(ref).trim_prefix("player:").is_valid_int(): player_peers.append(int(str(ref).trim_prefix("player:")))
		await process_frame
	for id in player_peers: make_character(world, id)
	var self_id := root.multiplayer.get_unique_id()
	var character: Node = actors.get(self_id)
	var ok := character != null and player_peers.size() == 2
	print("[seat-client] ready=", world.get_meta("bobux_replica_ready", false), " avatars=", player_peers, " own=", self_id)
	if not ok:
		auth.complete.rpc_id(1, false)
		await create_timer(0.4).timeout
		quit(1); return
	auth.check.rpc_id(1, "identity")
	var identity: Dictionary = await auth.checked
	print("[seat-client] identity=", identity)
	var own_ref: String = identity.ref
	var other_ref: String = identity.other
	var seat: Node = bridge._client.nodes.get(own_ref)
	var player: Node = bridge._client.nodes.get("player:%d" % self_id)
	var prompt: Node = bridge._client.nodes.get(own_ref + ":prompt")
	# Server invokes exact published Sit callback at the booth, authoritatively
	# assigning this Humanoid. On its device that must enter production seating.
	bridge._interaction_input.rpc_id(1, str(prompt.get_meta("roblox_ref")), "Triggered")
	await create_timer(0.45).timeout
	ok = ok and Seats.assigned_seat(character) == seat and character._seated_part == seat and Seats.occupant(seat).get_parent() == character
	ok = ok and engine.BobuxInstance.wrap(seat).Occupant.ClassName == "Humanoid"
	var weld_count := 0
	for child in seat.get_children():
		if str(child.get_meta("roblox_class", "")) == "Weld": weld_count += 1
	ok = ok and weld_count == 1
	print("[seat-client] seat entered PASS=", ok)
	var other: Node = bridge._client.nodes.get(other_ref)
	var observe_until := Time.get_ticks_msec() + 2500
	while Seats.occupant(other) == null and Time.get_ticks_msec() < observe_until: await create_timer(0.05).timeout
	ok = ok and Seats.occupant(other) != null and Seats.occupant(other).get_parent().get_multiplayer_authority() != self_id
	# Both clients must inspect each other's attachment before either leaves.
	var both_observed := false
	while not both_observed and Time.get_ticks_msec() < observe_until:
		auth.check.rpc_id(1, "observed")
		var observation: Dictionary = await auth.checked
		both_observed = observation.get("ok", false)
		await create_timer(0.05).timeout
	ok = ok and both_observed
	character.fixture_input = Vector2(0.5, -0.75)
	await create_timer(0.3).timeout
	auth.check.rpc_id(1, "drive")
	var drive: Dictionary = await auth.checked
	ok = ok and drive.get("ok", false)
	print("[seat-client] drive=", drive, " PASS=", ok)
	# Cross-room, wrong owner, malformed values and forged leave all fail.
	bridge._seat_input.rpc_id(1, other_ref, Vector2(-1, 1))
	bridge._seat_action.rpc_id(1, "leave", other_ref)
	bridge._seat_action.rpc_id(1, "enter", "b:seat:0")
	bridge._seat_input.rpc_id(1, "b:seat:0", Vector2.ONE)
	bridge._seat_input.rpc_id(1, own_ref, Vector2(3, 4))
	bridge._seat_input.rpc_id(1, own_ref, Vector2(NAN, 0))
	await create_timer(0.3).timeout
	auth.check.rpc_id(1, "drive")
	var rejection: Dictionary = await auth.checked
	ok = ok and rejection.get("ok", false)
	print("[seat-client] rejected inputs=", rejection, " PASS=", ok)
	ok = ok and load("res://addons/roblox_runtime/roblox_vehicle_motor.gd").ensure(seat) == null
	character.set_physics_process(false)
	await create_timer(0.8).timeout
	auth.check.rpc_id(1, "timeout")
	var timeout: Dictionary = await auth.checked
	ok = ok and timeout.get("ok", false)
	character.fixture_input = Vector2.ZERO
	character.set_physics_process(true)
	# Local jump/leave must clear the authoritative Seat, Humanoid and weld.
	character._leave_seat(true)
	await create_timer(0.3).timeout
	auth.check.rpc_id(1, "left")
	var left: Dictionary = await auth.checked
	ok = ok and left.get("ok", false) and Seats.assigned_seat(character) == null and Seats.occupant(seat) == null
	print("[seat-client] local leave=", left, " PASS=", ok)
	bridge._seat_action.rpc_id(1, "enter", own_ref) # The server moved us out of range.
	await create_timer(0.25).timeout
	auth.check.rpc_id(1, "left")
	var out_of_range: Dictionary = await auth.checked
	ok = ok and out_of_range.get("ok", false)
	print("[seat-client] range rejection=", out_of_range, " PASS=", ok)
	# Authoritative Sit is allowed to seat a distant Humanoid; setting Sit=false
	# on the server must release that owner's device as well.
	auth.check.rpc_id(1, "server_sit")
	var server_sit: Dictionary = await auth.checked
	await create_timer(0.3).timeout
	ok = ok and server_sit.get("ok", false) and character._seated_part == seat
	print("[seat-client] server Sit=", server_sit, " PASS=", ok)
	auth.check.rpc_id(1, "server_unseat")
	var server_unseat: Dictionary = await auth.checked
	await create_timer(0.3).timeout
	ok = ok and server_unseat.get("ok", false) and character._seated_part == null and Seats.occupant(seat) == null
	auth.check.rpc_id(1, "plain_seat")
	var plain_result: Dictionary = await auth.checked
	await create_timer(0.3).timeout
	var plain: Node = bridge._client.nodes.get(plain_result.get("ref", ""))
	ok = ok and plain_result.get("ok", false) and character._seated_part == plain and Seats.occupant(plain) == character.get_node("Humanoid")
	auth.check.rpc_id(1, "plain_unseat")
	var plain_unseat: Dictionary = await auth.checked
	await create_timer(0.3).timeout
	ok = ok and plain_unseat.get("ok", false) and character._seated_part == null and Seats.occupant(plain) == null
	for actor in actors.values():
		var synchronizer: Node = actor.get_node_or_null("StateSynchronizer")
		if synchronizer != null: actor.remove_child(synchronizer); synchronizer.queue_free()
	print("[seat-client] peer=", self_id, " production avatar/Sit/Occupant/owner controls/rejections/unseat PASS=", ok)
	auth.complete.rpc_id(1, ok)
	await create_timer(0.4).timeout
	quit(0 if ok else 1)

func make_world(id: String, origin: Vector3, simulate: bool) -> Node3D:
	var world := Node3D.new()
	world.name = "SeatWorld_" + id
	world.position = origin
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 1.0)
	world.set_meta("attribute_RPAttrsReady", true)
	root.add_child(world)
	bridge.prepare(world, id)
	engine._ensure_roblox_service_nodes(root, world)
	worlds[id] = world
	if simulate:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex-tmp/halloween/city-rp/city-map.json"))
		for index in 2:
			var model := DataModel.create_instance("Model", "Car%d" % index) as Node3D
			model.position = Vector3(index * 50, 5, 0)
			world.add_child(model)
			var seat := DataModel.create_instance("VehicleSeat", "Seat") as Node3D
			seat.set_meta("roblox_ref", "%s:seat:%d" % [id, index])
			seat.set_meta("attribute_BobuxVehicle", true)
			model.add_child(seat)
			var prompt := DataModel.create_instance("ProximityPrompt", "ProximityPrompt")
			prompt.set_meta("roblox_ref", "%s:seat:%d:prompt" % [id, index])
			seat.add_child(prompt)
			var script_node := DataModel.create_instance("Script", "Sit")
			seat.add_child(script_node)
			engine.start_script(data.roblox_manifest.scripts[16].source, script_node, {"realm": "server", "retain": true})
			var plain := DataModel.create_instance("Seat", "PlainSeat%d" % index) as Node3D
			plain.set_meta("roblox_ref", "%s:plain:%d" % [id, index])
			plain.position = Vector3(index * 50, 5, 10)
			world.add_child(plain)
		for _frame in 3: await process_frame
		bridge.register_workspace(world, id)
	return world

func make_character(world: Node3D, id: int) -> Node:
	var character := load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	character.set_script(load("res://tools/fixtures/seat_test_character.gd"))
	character.name = "Actor_%d" % id
	character.set_multiplayer_authority(id)
	character.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	character.get_node("StateSynchronizer").replication_config = null
	character.get_node("StateSynchronizer").public_visibility = false
	world.add_child(character)
	bridge.track_character(character, world)
	actors[id] = character
	return character

func joined(peer: int, id: String) -> void:
	peer_list.append(peer)
	var character := make_character(worlds[id], peer)
	character.global_position = worlds[id].global_position + Vector3((peer_list.size() - 1) * 50, 5, 0)
	engine.bind_network_player_character(character, worlds[id], peer, "Peer_%d" % peer, "fixture_%d" % peer)
	bridge.track_character(character, worlds[id])

func check_actor(peer: int, stage: String) -> Dictionary:
	var character: Node = actors[peer]
	var index := peer_list.find(peer)
	var ref := "a:seat:%d" % index
	var seat: Node = bridge._rooms.a.nodes.get(ref)
	if stage == "identity": return {"ref": ref, "other": "a:seat:%d" % (1 - index)}
	if stage == "observed":
		observed[peer] = true
		return {"ok": observed.size() == 2}
	if stage == "timeout": return {"ok": is_zero_approx(float(seat.get_meta("ThrottleFloat", 0))) and is_zero_approx(float(seat.get_meta("SteerFloat", 0)))}
	if stage == "drive":
		var ok: bool = Seats.assigned_seat(character) == seat and Seats.occupant(seat) == character.get_node("Humanoid")
		ok = ok and is_equal_approx(float(seat.get_meta("ThrottleFloat", 0)), 0.75) and is_equal_approx(float(seat.get_meta("SteerFloat", 0)), 0.5)
		var motor: Variant = instance_from_id(int(seat.get_meta("bobux_vehicle_motor_id", 0)))
		if is_instance_valid(motor):
			motor.freeze = true
			motor._physics_process(0.016)
			ok = ok and motor.engine_force > 0 and is_zero_approx(motor.brake)
		else: ok = false
		return {"ok": ok, "throttle": seat.get_meta("ThrottleFloat", 0), "steer": seat.get_meta("SteerFloat", 0)}
	if stage == "left":
		character.global_position = worlds.a.global_position + Vector3(index * 50, 5, 100)
		return {"ok": Seats.assigned_seat(character) == null and Seats.occupant(seat) == null and seat.get_node_or_null("SeatWeld") == null and is_zero_approx(float(seat.get_meta("ThrottleFloat", 0)))}
	if stage == "server_sit":
		engine.BobuxInstance.wrap(seat)._seat_sit(engine.BobuxInstance.wrap(character.get_node("Humanoid")))
		return {"ok": Seats.assigned_seat(character) == seat}
	if stage == "server_unseat":
		engine.BobuxInstance.wrap(character.get_node("Humanoid"))._set(&"Sit", false)
		return {"ok": Seats.assigned_seat(character) == null}
	if stage == "plain_seat":
		var plain: Node = bridge._rooms.a.nodes.get("a:plain:%d" % index)
		engine.BobuxInstance.wrap(plain)._seat_sit(engine.BobuxInstance.wrap(character.get_node("Humanoid")))
		return {"ok": Seats.assigned_seat(character) == plain, "ref": "a:plain:%d" % index}
	if stage == "plain_unseat":
		engine.BobuxInstance.wrap(character.get_node("Humanoid"))._set(&"Sit", false)
		return {"ok": Seats.assigned_seat(character) == null}
	return {"ok": false}
