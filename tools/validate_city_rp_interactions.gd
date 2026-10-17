extends SceneTree
## Reads the exact published sources from an audit snapshot. No authored map
## edits and no production account login are involved in this transport test.

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
const Interaction = preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd")
const JOBS = ["Полицейский", "Преступник", "Маньяк", "Врач", "Продавец", "Таксист", "Водитель", "Пассажир", "Горожанин"]
const TOOLS = ["Дубинка", "Лом", "Нож", "Аптечка", "", "", "", "", ""]
var bridge: Node
var engine: Node
var auth: Node
var worlds := {}
var actors := {}
var reports := {}
var map_path := "res://.codex-tmp/halloween/city-rp/city-map.json"
var original_scripts: Array

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): map_path = arg.trim_prefix("--map=")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	if not data is Dictionary: push_error("City audit map is missing: " + map_path); quit(2); return
	original_scripts = data.roblox_manifest.scripts
	bridge = root.get_node("ImportedPlaceNetwork")
	engine = root.get_node("LuaScriptEngine")
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in root.multiplayer.get_signal_connection_list(signal_name): root.multiplayer.disconnect(signal_name, connection.callable)
	auth = load("res://tools/fixtures/city_rp_test_auth.gd").new()
	auth.name = "TestAuth"
	root.add_child(auth)
	var peer := ENetMultiplayerPeer.new()
	if OS.get_cmdline_user_args().has("--server"):
		if peer.create_server(18745) != OK: quit(2); return
		root.multiplayer.multiplayer_peer = peer
		await make_world("a", Vector3(600000, 0, 630000), true)
		await make_world("b", Vector3(640000, 0, 600000), true)
		auth.peer_joined.connect(joined)
		auth.move_actor = move_actor
		auth.finished.connect(func(id: int, ok: bool): reports[id] = ok)
		FileAccess.open("res://.codex-tmp/halloween/city-rp/server-ready", FileAccess.WRITE).store_string("ready")
		var deadline := Time.get_ticks_msec() + 40000
		while reports.size() < 2 and Time.get_ticks_msec() < deadline: await create_timer(0.1).timeout
		var ok := reports.size() == 2 and not reports.values().has(false)
		for actor in actors.values():
			var player = engine.BobuxInstance.wrap(instance_from_id(actor.get_meta("bobux_player_instance_id")))
			ok = ok and player.GetAttribute("Job") == "Горожанин" and player.FindFirstChild("Backpack").GetChildren().is_empty()
		var diagnostics: Dictionary = engine.get_runtime_diagnostics()
		ok = ok and int(diagnostics.get("failed", 0)) == 0
		print("[city-rp-server] origin=(600000,0,630000) reports=", reports, " diagnostics=", diagnostics, " PASS=", ok)
		for world in worlds.values(): engine.stop_all_scripts(world)
		quit(0 if ok else 1)
		return
	peer.create_client("127.0.0.1", 18745)
	root.multiplayer.multiplayer_peer = peer
	await root.multiplayer.connected_to_server
	auth.join.rpc_id(1, "a")
	await auth.accepted
	var world := await make_world("a", Vector3.ZERO, false)
	var ready := false
	bridge.replica_ready.connect(func(value: Node): if value == world: ready = true)
	bridge.register_workspace(world, "a")
	var deadline := Time.get_ticks_msec() + 12000
	while not bool(world.get_meta("bobux_replica_ready", false)) and Time.get_ticks_msec() < deadline: await process_frame
	var character: Node3D = load("res://tools/fixtures/city_rp_test_character.gd").new()
	character.name = "Character"
	character.set_multiplayer_authority(root.multiplayer.get_unique_id())
	world.add_child(character)
	bridge.track_character(character, world)
	var ok := bool(world.get_meta("bobux_replica_ready", false))
	for index in JOBS.size():
		auth.position_actor.rpc_id(1, index, true)
		await auth.positioned
		var prompt: Node = bridge._client.nodes.get("a:prompt:%d" % index)
		if not is_instance_valid(prompt): ok = false; break
		character.global_position = Interaction.prompt_position(prompt)
		ok = Interaction.activate_nearest_prompt(world, character, engine) and ok
		var player: Node = bridge._client.nodes.get("player:%d" % root.multiplayer.get_unique_id())
		var changed_until := Time.get_ticks_msec() + 2000
		while player.get_meta("attribute_Job", "") != JOBS[index] and Time.get_ticks_msec() < changed_until: await create_timer(0.03).timeout
		var wrapper = engine.BobuxInstance.wrap(player)
		var team: Variant = wrapper.GetProperty("Team")
		var profession: Variant = wrapper.FindFirstChild("leaderstats").FindFirstChild("Профессия")
		var backpack: Variant = wrapper.FindFirstChild("Backpack")
		ok = ok and wrapper.GetAttribute("Job") == JOBS[index] and team != null and team.Name == JOBS[index] and profession.Value == JOBS[index]
		for tool in ["Дубинка", "Лом", "Нож", "Аптечка"]: ok = ok and (backpack.FindFirstChild(tool) != null) == (tool == TOOLS[index])
		ok = ok and int(wrapper.GetAttribute("ServiceInputCount")) == index + 1
		print("[city-rp-client] peer=", root.multiplayer.get_unique_id(), " job=", JOBS[index], " PASS=", ok)
	var detector: Node = bridge._client.nodes.get("a:click")
	ok = Interaction.activate_detector(detector, character, engine) and ok
	await create_timer(0.3).timeout
	var click_player: Node = bridge._client.nodes.get("player:%d" % root.multiplayer.get_unique_id())
	ok = ok and int(click_player.get_meta("attribute_Clicks", 0)) == 1
	# A forged input must not bypass range, room, Enabled, or event identity.
	auth.position_actor.rpc_id(1, 0, false)
	await auth.positioned
	for request in [["a:prompt:0", "Triggered"], ["b:prompt:0", "Triggered"], ["a:disabled", "Triggered"], ["a:prompt:0", "MouseClick"]]: bridge._interaction_input.rpc_id(1, request[0], request[1])
	await create_timer(0.8).timeout
	var player: Node = bridge._client.nodes.get("player:%d" % root.multiplayer.get_unique_id())
	ok = ok and player.get_meta("attribute_Job", "") == "Горожанин"
	print("[city-rp-client] rejection range/room/disabled/wrong-event PASS=", ok)
	auth.complete.rpc_id(1, ok)
	await create_timer(0.5).timeout
	quit(0 if ok else 1)

func make_world(id: String, origin: Vector3, simulate: bool) -> Node3D:
	var world := Node3D.new()
	world.name = "World_" + id
	world.position = origin
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 1.0)
	world.set_meta("attribute_RPAttrsReady", true)
	root.add_child(world)
	bridge.prepare(world, id)
	var services: Dictionary = engine._ensure_roblox_service_nodes(root, world)
	worlds[id] = world
	if simulate:
		var templates := DataModel.create_instance("Folder", "RPTools")
		services.ServerStorage.add_child(templates)
		for tool_name in ["Дубинка", "Лом", "Нож", "Аптечка"]: templates.add_child(DataModel.create_instance("Tool", tool_name))
		for index in JOBS.size():
			var board := DataModel.create_instance("Part", "Board") as Node3D
			board.position = Vector3(index * 30.0, 4, 0)
			board.set_meta("roblox_ref", "%s:board:%d" % [id, index])
			board.set_meta("attribute_Job", JOBS[index])
			board.set_meta("attribute_Tool", TOOLS[index])
			world.add_child(board)
			var prompt := DataModel.create_instance("ProximityPrompt", "ProximityPrompt")
			prompt.set_meta("roblox_ref", "%s:prompt:%d" % [id, index])
			prompt.set_meta("MaxActivationDistance", 10.0)
			board.add_child(prompt)
			var script_node := DataModel.create_instance("Script", "Job")
			board.add_child(script_node)
			engine.start_script(original_scripts[7].source, script_node, {"realm": "server", "retain": true})
		var disabled := DataModel.create_instance("ProximityPrompt", "Disabled")
		disabled.set_meta("roblox_ref", id + ":disabled")
		disabled.set_meta("Enabled", false)
		world.get_node("Board").add_child(disabled)
		var detector := DataModel.create_instance("ClickDetector", "ClickDetector")
		detector.set_meta("roblox_ref", id + ":click")
		(world.get_children()[JOBS.size() - 1] as Node).add_child(detector)
		var script_node := DataModel.create_instance("Script", "Teams")
		world.add_child(script_node)
		engine.start_script(original_scripts[48].source, script_node, {"realm": "server", "retain": true})
		for _frame in 4: await process_frame
		var probe := DataModel.create_instance("Script", "InteractionApiProbe")
		world.add_child(probe)
		engine.start_script("""
local teams=game:GetService('Teams')
assert(#teams:GetTeams()==9, 'Teams:GetTeams')
local folder=Instance.new('Folder'); folder.Parent=teams
assert(#teams:GetTeams()==9, 'GetTeams must filter non-Team children')
game:GetService('ProximityPromptService').PromptTriggered:Connect(function(prompt, player)
    assert(prompt:IsA('ProximityPrompt'), 'service receives prompt')
    player:SetAttribute('ServiceInputCount', (player:GetAttribute('ServiceInputCount') or 0)+1)
end)
""", probe, {"realm": "server", "retain": true})
		var click_probe := DataModel.create_instance("Script", "ClickProbe")
		detector.add_child(click_probe)
		engine.start_script("""
script.Parent.MouseClick:Connect(function(player)
    player:SetAttribute('Clicks', (player:GetAttribute('Clicks') or 0)+1)
end)
""", click_probe, {"realm": "server", "retain": true})
		for _frame in 2: await process_frame
		bridge.register_workspace(world, id)
	return world

func joined(peer: int, id: String) -> void:
	var character := load("res://tools/fixtures/city_rp_test_character.gd").new() as CharacterBody3D
	character.name = "Actor_%d" % peer
	character.set_multiplayer_authority(peer)
	worlds[id].add_child(character)
	engine.bind_network_player_character(character, worlds[id], peer, "Peer_%d" % peer, "fixture_%d" % peer)
	bridge.track_character(character, worlds[id])
	actors[peer] = character

func move_actor(peer: int, index: int, in_range: bool) -> void:
	if not actors.has(peer) or index < 0 or index >= JOBS.size(): return
	var room: String = root.get_node("NetworkManager").get_peer_room_id(peer)
	actors[peer].global_position = worlds[room].global_position + Vector3(index * 30.0, 4, 0) + (Vector3.ZERO if in_range else Vector3(0, 0, 100))
