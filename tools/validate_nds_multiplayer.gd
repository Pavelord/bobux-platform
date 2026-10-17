extends SceneTree
var main: Node
var controller: Node
var engine: Node
var bridge: Node
var auth: Node
var server := false
var server_frame_ms: Array[float] = []
var max_outgoing_chunks := 0
var disaster := "tsunami"
var peak_fire := 0
var minimum_health := 100.0
var client_finished := false
var completed_disaster_seconds := -1.0

func _initialize() -> void: run.call_deferred()
func run() -> void:
	server = OS.get_cmdline_user_args().has("--server")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--disaster="): disaster = arg.trim_prefix("--disaster=")
	if disaster not in ["tsunami", "fire", "flooding"]: quit(2); return
	bridge = root.get_node("ImportedPlaceNetwork")
	engine = root.get_node("LuaScriptEngine")
	for event in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in root.multiplayer.get_signal_connection_list(event): root.multiplayer.disconnect(event, connection.callable)
	auth = load("res://tools/fixtures/replication_test_auth.gd").new()
	auth.name = "TestAuth"
	root.add_child(auth)
	var peer := WebSocketMultiplayerPeer.new()
	if server: peer.create_server(18740)
	else: peer.create_client("ws://127.0.0.1:18740")
	root.multiplayer.multiplayer_peer = peer
	if not server: root.multiplayer.server_disconnected.connect(func(): quit(0 if client_finished else 1))
	if not server: await root.multiplayer.connected_to_server
	root.get_node("GameState").selected_map_folder = "user://validation/nds_performance"
	main = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/nds_network_runtime.gd"))
	root.add_child(main)
	current_scene = main
	if server and OS.get_cmdline_user_args().has("--nonzero-origin"):
		main.world.position = Vector3(600000, 0, 630000)
	if not server:
		auth.join.rpc_id(1, "a")
		await auth.accepted
		# The isolated auth bypasses the production room snapshot. Mirror its
		# local membership so the real native respawn RPC can resolve room "a"
		# and apply the same coordinate translation as an ordinary game join.
		root.get_node("NetworkManager")._peer_room_ids[root.multiplayer.get_unique_id()] = "a"
	var started := Time.get_ticks_msec()
	await main._load_selected_map()
	print("[nds-net] build_ms=", Time.get_ticks_msec()-started)
	controller = main.world.get_node("Script")
	if server:
		auth.peer_joined.connect(_joined)
		FileAccess.open("res://.codex-tmp/nds-net-ready", FileAccess.WRITE).store_string("ready")
		while main.players.get_child_count() == 0: await process_frame
		await create_timer(5).timeout
		engine.stop_all_scripts(main)
		engine.reset_runtime_diagnostics()
		var source: String = controller.get_meta("lua_source", "")
		if disaster == "fire":
			# Fixture diagnostics only; the authored map remains byte-for-byte intact.
			source = source.replace("function updatefireparts(mdl)", "function updatefireparts(mdl)\n__fire_nodes=(__fire_nodes or 0)+1")
			source = source.replace("updatefireparts(game.Workspace.Structure)", "__fire_pass=(__fire_pass or 0)+1; __fire_nodes=0; __fire_stage='pass'; updatefireparts(game.Workspace.Structure); __fire_stage='wait'")
			source = source.replace("disaster.Start()", "disaster.Start(); __fire_stage='cleanup'")
		# Only shorten intermissions in this test. The actual tsunami controller
		# runs all of its original 60 seconds; production source stays untouched.
		var cut := source.find("while true do\n\twait(20)")
		if cut < 0: quit(2); return
		var rounds := source.substr(cut)
		rounds = rounds.replace("wait(20)", "wait(1)").replace("wait(40)", "wait(1)").replace("wait(3)", "wait(.2)").replace("wait(2)", "wait(.2)")
		rounds = rounds.replace("local disaster=disasters[rd]", "local disaster=" + disaster)
		if disaster == "fire": rounds = rounds.replace("local ns=structures[rs]:clone()", "local ns=game.Lighting.Structures['Sunny Ranch']:clone()")
		rounds = rounds.replace("disaster.Start()", "script:SetAttribute('TestRound', (script:GetAttribute('TestRound') or 0)+1)\ndisaster.Start()")
		rounds = rounds.replace("disaster.Start()", "script:SetAttribute('DisasterStartTime',tick()); disaster.Start(); script:SetAttribute('DisasterEndTime',tick())")
		engine.start_script("math.randomseed(20261010)\n"+source.substr(0, cut) + rounds, controller, {"realm":"server", "retain":true})
		var deadline := Time.get_ticks_msec()+200000
		var previous_frame := Time.get_ticks_usec()
		var fire_probe_at := 0
		var progress_at := 0
		while int(controller.get_meta("attribute_TestRound", 0)) < 2 and Time.get_ticks_msec()<deadline and engine.get_runtime_diagnostics().failed==0:
			await process_frame
			var now_frame := Time.get_ticks_usec()
			if int(controller.get_meta("attribute_TestRound", 0)) == 1 and str(controller.get_node("Status").get_meta("Value", "")) == "Disaster":
				server_frame_ms.append(float(now_frame - previous_frame) / 1000.0)
			if int(controller.get_meta("attribute_TestRound", 0)) == 1 and controller.has_meta("attribute_DisasterEndTime"):
				completed_disaster_seconds = float(controller.get_meta("attribute_DisasterEndTime")) - float(controller.get_meta("attribute_DisasterStartTime"))
			previous_frame = now_frame
			max_outgoing_chunks = maxi(max_outgoing_chunks, bridge._outgoing.size())
			if Time.get_ticks_msec() - progress_at >= 10000:
				progress_at = Time.get_ticks_msec()
				for runtime in engine._script_runtimes.values():
					if engine._live_node(runtime.get("context")) == controller:
						print("[nds-net-progress] status=", controller.get_node("Status").get_meta("Value", ""), " round=", controller.get_meta("attribute_TestRound",0), " timer=", runtime.lua.pull_variant("timer"), " a=", runtime.lua.pull_variant("a"), " wake=", runtime.get("wake_at"), " now=",Time.get_ticks_msec()/1000.0)
						print("[nds-net-fire-stage] stage=", runtime.lua.pull_variant("__fire_stage"), " pass=", runtime.lua.pull_variant("__fire_pass"), " nodes=", runtime.lua.pull_variant("__fire_nodes"))
				if engine._profile_native_enabled:
					for stats in [engine._native_profile, engine._native_access_profile]:
						var keys: Array = stats.keys()
						keys.sort_custom(func(a,b): return stats[a].usec > stats[b].usec)
						for key in keys.slice(0, 5): print("[nds-net-profile] ", key, " ", stats[key])
			if disaster == "fire" and Time.get_ticks_msec() - fire_probe_at >= 250:
				fire_probe_at = Time.get_ticks_msec()
				var fires: Array[Node] = []
				for node in main.world.get_node("Structure").find_children("*", "GPUParticles3D", true, false):
					if node.get_meta("roblox_class", "") == "Fire": fires.append(node)
				peak_fire = maxi(peak_fire, fires.size())
				if not fires.is_empty():
					for character in main.players.get_children():
						if character.get_health() > 0: character.set_lua_position(fires[0].global_position)
				for character in main.players.get_children(): minimum_health = minf(minimum_health, character.get_health())
		var count: int = engine._ensure_roblox_service_nodes(root, main.world).Players.get_child_count()
		var network: Node = root.get_node("NetworkManager")
		var connected_peers: Array = root.multiplayer.get_peers()
		var stale_heartbeat_kept_peer := false
		if not connected_peers.is_empty():
			var connected_peer_id: int = int(connected_peers[0])
			network._hosting = true
			network._server_rooms["a"] = {"room_id":"a", "peer_ids":[connected_peer_id], "max_players":10}
			network._peer_room_ids[connected_peer_id] = "a"
			network._peer_last_keepalive_msec[connected_peer_id] = Time.get_ticks_msec() - 9000
			network._reconcile_server_room_members()
			stale_heartbeat_kept_peer = root.multiplayer.get_peers().has(connected_peer_id) and network.get_room_member_peer_ids("a").has(connected_peer_id)
		var ok: bool = count == 2 and controller.get_meta("attribute_TestRound", 0)==2 and engine.get_runtime_diagnostics().failed==0 and stale_heartbeat_kept_peer
		if disaster == "fire": ok = ok and peak_fire > 0 and minimum_health < 100
		await create_timer(3).timeout
		server_frame_ms.sort()
		var p95: float = server_frame_ms[int((server_frame_ms.size() - 1) * .95)] if not server_frame_ms.is_empty() else 0.0
		var max_frame: float = server_frame_ms.back() if not server_frame_ms.is_empty() else 0.0
		print("[nds-net] SERVER PASS=", ok, " disaster=", disaster, " authored_disaster_seconds=",completed_disaster_seconds," peak_fire=", peak_fire, " minimum_health=", minimum_health, " players=", count, " stale_heartbeat_kept_peer=", stale_heartbeat_kept_peer, " disaster_frames=", server_frame_ms.size(), " frame_p95_ms=", p95, " frame_max_ms=", max_frame, " max_outgoing_chunks=", max_outgoing_chunks, " diagnostics=", engine.get_runtime_diagnostics())
		engine.stop_all_scripts(main)
		quit(0 if ok else 1)
		return
	var character: CharacterBody3D = main.add_probe_player(root.multiplayer.get_unique_id())
	var until := Time.get_ticks_msec()+195000
	while not main.world.get_meta("bobux_replica_ready",false) and Time.get_ticks_msec()<until: await process_frame
	engine.bind_local_player_character(character)
	var initial: Vector3 = character.position
	var late := OS.get_cmdline_user_args().has("--late")
	var first_round := int(controller.get_meta("attribute_TestRound",0))
	var seen_wave := false
	var held_lobby := true
	var local_coordinates: bool = main.world.global_position.is_equal_approx(Vector3.ZERO) and character.position.length() < 5000.0
	var parts := 0
	while int(controller.get_meta("attribute_TestRound",0))<2 and Time.get_ticks_msec()<until:
		await create_timer(.1).timeout
		if main.world.get_node("Structure").get_node_or_null("TsunamiWave") != null: seen_wave=true
		if disaster == "fire":
			for node in main.world.get_node("Structure").find_children("*", "GPUParticles3D", true, false):
				if node.get_meta("roblox_class", "") == "Fire" and node.emitting and node.draw_pass_1 != null: seen_wave = true
			minimum_health = minf(minimum_health, character.get_health())
		if disaster != "fire" and late and int(controller.get_meta("attribute_TestRound",0))==1 and str(controller.get_node("Status").get_meta("Value", ""))=="Disaster" and initial.distance_to(character.position)>0.1: held_lobby=false
		# A server room is deliberately offset by hundreds of thousands of
		# units. Neither a root pose nor manifest metadata may leak that origin
		# into this client, including a delta that arrives during round changes.
		local_coordinates = local_coordinates and main.world.global_position.is_equal_approx(Vector3.ZERO) and character.position.length() < 5000.0
		parts = maxi(parts, main.world.get_node("Structure").find_children("*","MeshInstance3D",true,false).size())
	var ok: bool = seen_wave and local_coordinates and parts>50 and controller.get_meta("attribute_TestRound",0)==2 and (not late or (first_round==1 and held_lobby)) and initial.distance_to(character.position)>1.0 and engine.get_runtime_diagnostics().failed==0
	if disaster == "fire" and not late: ok = ok and minimum_health < 100
	print("[nds-net] CLIENT PASS=",ok," disaster=",disaster," minimum_health=",minimum_health," late=",late," first_round=",first_round," wave=",seen_wave," parts=",parts," held_lobby=",held_lobby," local_coordinates=",local_coordinates," workspace_origin=",main.world.global_position," initial=",initial," next_round=",character.position," diagnostics=",engine.get_runtime_diagnostics())
	client_finished = ok
	# Keep transport alive while the server flushes the final round snapshot.
	if ok: await create_timer(5).timeout
	quit(0 if ok else 1)

func _joined(peer: int, _room: String) -> void:
	main.add_probe_player(peer)
