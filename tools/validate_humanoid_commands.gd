extends SceneTree

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
var bridge: Node
var engine: Node
var auth: Node
var worlds := {}
var actors := {}
var probes := {}
var reports := {}
var checks := 0
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[humanoid-commands] ", "PASS " if ok else "FAIL ", label)
	failed = failed or not ok

func run() -> void:
	bridge = root.get_node("ImportedPlaceNetwork")
	engine = root.get_node("LuaScriptEngine")
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in root.multiplayer.get_signal_connection_list(signal_name):
			root.multiplayer.disconnect(signal_name, connection.callable)
	auth = load("res://tools/fixtures/seat_test_auth.gd").new()
	auth.name = "HumanoidCommandAuth"
	root.add_child(auth)
	var transport := ENetMultiplayerPeer.new()
	if OS.get_cmdline_user_args().has("--server"):
		if transport.create_server(18846) != OK:
			quit(2)
			return
		root.multiplayer.multiplayer_peer = transport
		make_world("a", Vector3(600000, 0, 630000), true)
		make_world("b", Vector3(640000, 0, 610000), true)
		auth.peer_joined.connect(joined)
		auth.check_actor = server_stage
		auth.finished.connect(func(peer: int, ok: bool): reports[peer] = ok)
		FileAccess.open("res://.codex-tmp/humanoid_commands/server-ready", FileAccess.WRITE).store_string("ready")
		var until := Time.get_ticks_msec() + 35000
		while reports.size() < 2 and Time.get_ticks_msec() < until:
			await create_timer(0.05).timeout
		check(reports.size() == 2 and not reports.values().has(false), "both clients completed independent room scenarios")
		check(engine.get_runtime_diagnostics().failed == 0, "server Luau scripts have no failures")
		for world in worlds.values():
			engine.stop_all_scripts(world)
			bridge.unregister_workspace(world)
		print("[humanoid-commands] server checks=", checks, " reports=", reports)
		quit(1 if failed else 0)
		return
	var room := "b" if OS.get_cmdline_user_args().has("--room-b") else "a"
	transport.create_client("127.0.0.1", 18846)
	root.multiplayer.multiplayer_peer = transport
	await root.multiplayer.connected_to_server
	auth.join.rpc_id(1, room)
	await auth.accepted
	var world := make_world(room, Vector3.ZERO, false)
	bridge.register_workspace(world, room)
	# Imported places can use a real Workspace rather than an alias. Exercise
	# its manifest-property path too, not only the separate pose operation.
	world.set_meta("bobux_workspace_alias", false)
	var until := Time.get_ticks_msec() + 10000
	while not bool(world.get_meta("bobux_replica_ready", false)) and Time.get_ticks_msec() < until:
		await process_frame
	check(bool(world.get_meta("bobux_replica_ready", false)), "room replica ready")
	check(world.global_position.is_equal_approx(Vector3.ZERO), "server Workspace manifest and pose preserve the client's local origin")
	# A local-authority avatar in a different workspace must never consume this
	# room's commands, even when it appears earlier in the global group.
	var foreign := make_world("foreign", Vector3(1500, 0, 0), false)
	var decoy := make_character(foreign, root.multiplayer.get_unique_id())
	decoy.set_physics_process(false)
	var sentinel: Vector3 = decoy.global_position
	var player := make_character(world, root.multiplayer.get_unique_id())
	engine.bind_local_player_character(player)
	var h = engine.BobuxInstance.wrap(player.get_node("Humanoid"))
	auth.check.rpc_id(1, "start")
	var start: Dictionary = await auth.checked
	await create_timer(0.2).timeout
	check(player.get_runtime_humanoid_state() == 16 and player._lua_move_deadline > 0, "server MoveTo and Physics reach the owning client")
	check(is_equal_approx(player.get_humanoid_walk_speed(), 24.0) and not player._humanoid_auto_rotate_enabled() and is_equal_approx(float(h.HipHeight), 1.75) and not bool(h.UseJumpPower) and is_equal_approx(float(h.JumpHeight), 10.0), "server typed Humanoid properties reach that client")
	check(not h.GetStateEnabled(3), "server SetStateEnabled reaches the client")
	check(decoy.global_position == sentinel and decoy._lua_move_deadline == 0 and decoy.get_humanoid_walk_speed() == 16, "another workspace's avatar remains untouched")
	bridge._humanoid_move_finished.rpc_id(1, "wrong-room", int(start.token), true, int(bridge._client.token))
	bridge._humanoid_move_finished.rpc_id(1, room, int(start.token) + 12345, true, int(bridge._client.token))
	bridge._humanoid_move_finished.rpc_id(1, room, int(start.token), "true", int(bridge._client.token))
	await create_timer(0.1).timeout
	auth.check.rpc_id(1, "status")
	var bad_ack: Dictionary = await auth.checked
	check(int(bad_ack.count) == 0 and bool(bad_ack.active), "wrong-room and stale completion acknowledgements are rejected")
	auth.check.rpc_id(1, "malformed")
	await auth.checked
	await create_timer(0.1).timeout
	check(player.get_humanoid_walk_speed() == 24 and not player._humanoid_auto_rotate_enabled() and player.get_runtime_humanoid_state() == 16, "malformed vectors, state IDs, booleans and properties are rejected")
	auth.check.rpc_id(1, "go")
	await auth.checked
	await await_move(player)
	await create_timer(0.1).timeout
	auth.check.rpc_id(1, "status")
	var completed: Dictionary = await auth.checked
	check(int(completed.count) == 1 and bool(completed.reached) and not bool(completed.active) and absf(player.position.x - 12.0) <= 1.0, "MoveTo completion reaches the server Luau listener once")
	auth.check.rpc_id(1, "part")
	await auth.checked
	await create_timer(0.35).timeout
	print("[humanoid-commands] moving-part target=", player._get_lua_move_target(), " valid=", is_instance_valid(player._lua_move_part), " offset=", player._lua_move_part_offset)
	check(is_instance_valid(player._lua_move_part) and absf(player._get_lua_move_target().x - 24.0) < 0.01, "moving target uses the room's replicated part reference")
	auth.check.rpc_id(1, "go")
	await auth.checked
	await await_move(player)
	await create_timer(0.1).timeout
	auth.check.rpc_id(1, "status")
	var part_done: Dictionary = await auth.checked
	check(int(part_done.count) == 2 and bool(part_done.reached) and absf(player.position.x - 24.0) <= 1.0, "moving-part MoveTo completes on server")
	auth.check.rpc_id(1, "move")
	await auth.checked
	await create_timer(0.3).timeout
	check(absf(player.velocity.x - 12.0) < 0.01 and player._lua_move_deadline == 0, "server Move applies analog direction with the server WalkSpeed")
	auth.check.rpc_id(1, "stop")
	await auth.checked
	await create_timer(0.3).timeout
	check(absf(player.velocity.x) < 0.01, "server Move zero stops movement")
	auth.check.rpc_id(1, "jump")
	await auth.checked
	await create_timer(0.1).timeout
	check(player.get_runtime_humanoid_state() == 5 and player.velocity.y > 0.0, "server Jumping then Freefall preserve ascending motion")
	auth.check.rpc_id(1, "infinite-health")
	await auth.checked
	await create_timer(0.1).timeout
	check(is_inf(float(h._get(&"Health"))) and is_inf(float(h._get(&"MaxHealth"))) and is_finite(player.get_health()), "infinite logical health reaches its client without poisoning the HUD")
	auth.check.rpc_id(1, "timeout")
	var timeout_case: Dictionary = await auth.checked
	await create_timer(0.35).timeout
	bridge._humanoid_move_finished.rpc_id(1, room, int(timeout_case.token), true, int(bridge._client.token))
	await create_timer(0.1).timeout
	auth.check.rpc_id(1, "status")
	var expired: Dictionary = await auth.checked
	check(int(expired.count) == 3 and not bool(expired.reached) and not bool(expired.active), "server watchdog finishes timed-out moves once and rejects late ACK")
	var previous_actor := player
	world.remove_child(previous_actor)
	previous_actor.queue_free()
	player = make_character(world, root.multiplayer.get_unique_id())
	engine.bind_local_player_character(player)
	check(bool(bridge._client.get("actor_waiting", false)), "replacement avatar waits for its own server actor generation")
	auth.check.rpc_id(1, "replace-actor")
	await auth.checked
	await create_timer(0.15).timeout
	check(player.get_humanoid_walk_speed() == 18.0 and not bool(bridge._client.get("actor_waiting", true)), "new actor receives commands and rejects a valid old-life payload")
	check(engine.get_runtime_diagnostics().failed == 0, "client Luau runtime has no failures")
	print("[humanoid-commands] client room=", room, " checks=", checks, " failed=", failed)
	# Retire local fixture actors while the transport is still live. Closing the
	# server with their Luau bindings/authority checks alive creates test-only
	# disconnected ENet queries instead of a normal game leave sequence.
	for branch in worlds.values():
		engine.stop_all_scripts(branch)
		bridge.unregister_workspace(branch)
		branch.queue_free()
	for frame in range(4): await process_frame
	auth.complete.rpc_id(1, not failed)
	await process_frame
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	quit(1 if failed else 0)

func await_move(player: Node) -> void:
	var until := Time.get_ticks_msec() + 3000
	while player._lua_move_deadline > 0 and Time.get_ticks_msec() < until:
		await process_frame

func make_world(room: String, origin: Vector3, server: bool) -> Node3D:
	var world := Node3D.new()
	world.name = "World_" + room
	world.position = origin
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 1.0)
	world.set_meta("Gravity", 196.2)
	root.add_child(world)
	worlds[room] = world
	bridge.prepare(world, room)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(150, 1, 150)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	if server:
		var part := DataModel.create_instance("Part", "Target") as Node3D
		part.set_meta("roblox_ref", room + ":target")
		part.set_meta("anchored", true)
		part.set_meta("can_collide", false)
		part.set_meta("roblox_properties", {"Anchored": true, "CanCollide": false})
		part.position = Vector3(12, 0, 0)
		world.add_child(part)
		bridge.register_workspace(world, room)
	return world

func make_character(world: Node3D, peer: int) -> CharacterBody3D:
	var player := load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	player.set_script(load("res://tools/fixtures/humanoid_command_character.gd"))
	player.name = "Actor_%d" % peer
	player.set_multiplayer_authority(peer)
	player.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	var sync := player.get_node("StateSynchronizer")
	# This stand tests ImportedPlaceNetwork directly; native scene-sync paths
	# for its intentionally unreplicated decoy avatars must not be registered.
	player.remove_child(sync)
	sync.free()
	world.add_child(player)
	bridge.track_character(player, world)
	return player

func joined(peer: int, room: String) -> void:
	var player := make_character(worlds[room], peer)
	actors[peer] = player
	engine.bind_network_player_character(player, worlds[room], peer, "Peer_%d" % peer, "fixture_%d" % peer)
	bridge.track_character(player, worlds[room])
	var probe := DataModel.create_instance("Script", "MoveToProbe")
	worlds[room].add_child(probe)
	probes[peer] = probe
	engine.start_script("""
local h=game.Players:GetPlayers()[1].Character.Humanoid
local count=0
h.MoveToFinished:Connect(function(reached)
    count+=1
    script:SetAttribute('Count',count)
    script:SetAttribute('Reached',reached)
end)
""", probe, {"realm": "server", "retain": true})

func server_stage(peer: int, stage: String) -> Dictionary:
	var player: Node = actors[peer]
	var room: String = root.get_node("NetworkManager").get_peer_room_id(peer)
	var h = engine.BobuxInstance.wrap(player.get_node("Humanoid"))
	if stage == "start":
		h._set(&"WalkSpeed", 24.0)
		h._set(&"AutoRotate", false)
		h._set(&"HipHeight", 1.75)
		h._set(&"UseJumpPower", false)
		h._set(&"JumpHeight", 10.0)
		h.SetStateEnabled(3, false)
		h.ChangeState(16)
		h.MoveTo(Vector3(12, 0, 0))
		return {"token": bridge._humanoid_moves.get(peer, {}).get("token", 0)}
	if stage == "go":
		h.ChangeState(8)
		return {"ok": true}
	if stage == "part":
		h.ChangeState(16)
		bridge.send_character_command(player, "set_lua_linear_velocity", Vector3.ZERO)
		var part: Node3D = bridge._rooms[room].nodes[room + ":target"]
		h.MoveTo(Vector3(12, 0, 0), engine.BobuxInstance.wrap(part))
		part.position.x = 24
		return {"ok": true}
	if stage == "move":
		h._get(&"Move").call(Vector3(0.5, 0, 0), false)
		return {"ok": true}
	if stage == "stop":
		h._get(&"Move").call(Vector3.ZERO, false)
		return {"ok": true}
	if stage == "jump":
		h.SetStateEnabled(3, true)
		h.ChangeState(3)
		h.ChangeState(5)
		return {"ok": true}
	if stage == "timeout":
		h.ChangeState(16)
		h.MoveTo(Vector3(60, 0, 0))
		var token: int = bridge._humanoid_moves.get(peer, {}).get("token", 0)
		if bridge._humanoid_moves.has(peer): bridge._humanoid_moves[peer].deadline = Time.get_ticks_msec() + 100
		return {"token": token}
	if stage == "infinite-health":
		h._set(&"MaxHealth", INF)
		h._set(&"Health", INF)
		return {"ok": true}
	if stage == "malformed":
		for packet in [["set_humanoid_move", Vector3(NAN, 0, 0)], ["request_humanoid_state", 999], ["request_humanoid_state", "Physics"], ["set_humanoid_property", {"key": "AutoRotate", "value": "true"}], ["set_humanoid_property", {"key": "WalkSpeed", "value": -100}], ["set_humanoid_property", {"key": "QueueFree", "value": true}], ["set_humanoid_state_enabled", {"state": 3, "enabled": 1}], ["move_to", {"point": Vector3.INF, "token": 4}]]:
			bridge._character_command.rpc_id(peer, room, packet[0], {"value": packet[1], "replica_token": int(bridge._subscriptions[peer].token), "actor_token": bridge._humanoid_actor_token(player)})
		return {"ok": true}
	if stage == "replace-actor":
		var old_token: int = bridge._humanoid_actor_token(player)
		player.get_parent().remove_child(player)
		player.queue_free()
		var replacement := make_character(worlds[room], peer)
		actors[peer] = replacement
		engine.bind_network_player_character(replacement, worlds[room], peer, "Peer_%d" % peer, "fixture_%d" % peer)
		engine.BobuxInstance.wrap(replacement.get_node("Humanoid"))._set(&"WalkSpeed", 18.0)
		bridge._character_command.rpc_id(peer, room, "set_humanoid_property", {"value": {"key": "WalkSpeed", "value": 99.0}, "replica_token": int(bridge._subscriptions[peer].token), "actor_token": old_token})
		return {"ok": true}
	return {"count": int(probes[peer].get_meta("attribute_Count", 0)), "reached": bool(probes[peer].get_meta("attribute_Reached", false)), "active": bridge._humanoid_moves.has(peer)}
