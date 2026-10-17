extends SceneTree

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
var bridge: Node
var engine: Node
var workspace: Node3D
var room := "a"
var client_number := 1
var is_server := false
var observed := {}
var worlds := {}
var remote_probe: Node
var replicated_texture_ready := false

func _initialize() -> void: run.call_deferred()

func run() -> void:
	bridge = root.get_node("ImportedPlaceNetwork")
	engine = root.get_node("LuaScriptEngine")
	is_server = OS.get_cmdline_user_args().has("--server")
	if OS.get_cmdline_user_args().has("--other-room"): room = "b"
	if OS.get_cmdline_user_args().has("--late"): client_number = 2
	if room == "b": client_number = 3
	var api := root.multiplayer
	var auth: Node = load("res://tools/fixtures/replication_test_auth.gd").new()
	auth.name = "TestAuth"
	root.add_child(auth)
	# These processes exercise the actual transport without production login.
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in api.get_signal_connection_list(signal_name): api.disconnect(signal_name, connection.callable)
	var peer := ENetMultiplayerPeer.new()
	if is_server:
		if peer.create_server(18739) != OK: quit(2); return
		api.multiplayer_peer = peer
		_make_world("a", 0)
		_make_world("b", 100)
		auth.peer_joined.connect(_joined_peer)
		# The third client explicitly chooses a different room through the test
		# auth handshake below; the production bridge never trusts client room IDs.
		var marker := FileAccess.open("res://.codex-tmp/replication-server-ready", FileAccess.WRITE)
		marker.store_string("ready")
		marker.close()
		await create_timer(32).timeout
		print("[replication-server] diagnostics=", engine.get_runtime_diagnostics())
		quit(0)
		return
	peer.create_client("127.0.0.1", 18739)
	api.multiplayer_peer = peer
	await api.connected_to_server
	var media_service := root.get_node("MapMediaStream")
	auth.join.rpc_id(1, room)
	await auth.accepted
	workspace = _make_world(room, 0, false)
	bridge.replica_ready.connect(_ready_replica)
	bridge.register_workspace(workspace, room)
	var blocked: Dictionary = engine.start_script("workspace:SetAttribute('ClientRanServer', true)", workspace, {"realm": "server"})
	var deadline := Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.15).timeout
		var counter := workspace.get_node_or_null("Round")
		if counter != null and bool(workspace.get_meta("bobux_replica_ready", false)):
			var value := int(counter.get_meta("Value", 0))
			observed[value] = true
			var map := workspace.get_node_or_null("Map")
			if map != null:
				var textured_part := workspace.get_node_or_null("NetworkTexturePart") as MeshInstance3D
				if textured_part != null:
					var expected_path := str(workspace.get_meta("bobux_map_asset_folder", "")).path_join("net_texture.png")
					var face: MeshInstance3D = null
					for child in textured_part.get_children():
						if bool(child.get_meta("roblox_face_decal", false)):
							face = child as MeshInstance3D
							break
					var face_material := face.get_active_material(0) if face != null else null
					var texture := face_material.get("albedo_texture") as ImageTexture if face_material is StandardMaterial3D else null
					if FileAccess.file_exists(expected_path) and texture != null and texture.get_width() == 2 and texture.get_height() == 2:
						var downloaded_image := Image.new()
						if downloaded_image.load(expected_path) == OK:
							var pixel := downloaded_image.get_pixel(0, 0)
							replicated_texture_ready = pixel.r > 0.9 and pixel.g < 0.2 and pixel.b > 0.7
				var piece := map.get_node_or_null("Moving") as MeshInstance3D
				if piece != null:
					var body := preload("res://addons/roblox_runtime/roblox_part_physics.gd").body_for(piece)
					if body == null or not body.freeze:
						push_error("Replica is simulating its own physics")
						quit(1); return
	var first := int(workspace.get_meta("FirstRound", -1))
	var isolated: bool = first >= 100 if room == "b" else first < 100
	var private_ok := true
	var players: Node = engine._ensure_roblox_service_nodes(root, workspace).Players
	for player in players.get_children():
		if int(player.get_meta("bobux_peer_id", 0)) != api.get_unique_id() and player.has_node("PlayerGui"): private_ok = false
	var remotes_ok := is_instance_valid(remote_probe) and bool(remote_probe.get_meta("attribute_RemotesPassed", false))
	var ok: bool = blocked.get("skipped_realm", false) and not workspace.get_meta("attribute_ClientRanServer", false) and observed.size() >= 3 and first >= (3 if client_number == 2 else 0) and isolated and private_ok and remotes_ok and replicated_texture_ready
	print("[replication-client] privacy=", private_ok, " isolated=", isolated, " remotes=", remotes_ok, " texture=", replicated_texture_ready)
	print("[replication-client] diagnostics=", engine.get_runtime_diagnostics())
	print("[replication-client] client=", client_number, " first=", first, " rounds=", observed.keys(), " PASS=", ok)
	quit(0 if ok else 1)

func _ready_replica(value: Node) -> void:
	var counter := value.get_node_or_null("Round")
	value.set_meta("FirstRound", int(counter.get_meta("Value", -1)) if counter != null else -1)
	remote_probe = DataModel.create_instance("LocalScript", "LocalProbe")
	value.add_child(remote_probe)
	var result: Dictionary = engine.start_script("""
local rs=game:GetService('ReplicatedStorage')
local got=false
rs.Echo.OnClientEvent:Connect(function(n) got=(n==21) end)
rs.Echo:FireServer(21)
assert(rs.Sum:InvokeServer(7,9)==16, 'RemoteFunction result')
for i=1,100 do if got then break end; task.wait(.05) end
assert(got, 'RemoteEvent response')
script:SetAttribute('RemotesPassed',true)
""", remote_probe, {"realm": "client", "retain": true})
	print("[replication-client] remote start=", result)

func _joined_peer(peer: int, id: String) -> void:
	var services: Dictionary = engine._ensure_roblox_service_nodes(root, worlds[id])
	var player := DataModel.create_instance("Player", "Peer_%d" % peer)
	player.set_meta("roblox_ref", "player:%d" % peer)
	player.set_meta("bobux_peer_id", peer)
	services.Players.add_child(player)
	var gui := DataModel.create_instance("PlayerGui", "PlayerGui")
	player.add_child(gui)
	var value := DataModel.create_instance("StringValue", "PrivateValue")
	value.set_meta("Value", str(peer))
	gui.add_child(value)

func _make_world(id: String, initial: int, simulate := true) -> Node3D:
	var world := Node3D.new()
	world.name = "World_" + id
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	var asset_folder := "user://replication_server_map_assets" if simulate else "user://replication_client_map_assets_%d" % client_number
	world.set_meta("bobux_map_asset_folder", asset_folder)
	world.set_meta("bobux_map_asset_urls", {"net_texture.png": OS.get_environment("BOBUX_REPLICATION_ASSET_URL")})
	var texture_path := asset_folder.path_join("net_texture.png")
	if simulate:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 0.1, 0.8, 1.0))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_folder))
		image.save_png(ProjectSettings.globalize_path(texture_path))
	else:
		var cached_texture_path := ProjectSettings.globalize_path(texture_path)
		if FileAccess.file_exists(texture_path): DirAccess.remove_absolute(cached_texture_path)
	root.add_child(world)
	bridge.prepare(world, id)
	var services: Dictionary = engine._ensure_roblox_service_nodes(root, world)
	worlds[id] = world
	var round_value := DataModel.create_instance("IntValue", "Round")
	round_value.set_meta("roblox_ref", "round")
	round_value.set_meta("Value", initial)
	world.add_child(round_value)
	var scene: Node = DataModel.create_instance("Model", "Map")
	scene.set_meta("roblox_ref", "initial-map")
	world.add_child(scene)
	var stale := DataModel.create_instance("Part", "OldPart")
	stale.set_meta("roblox_ref", "initial-part")
	scene.add_child(stale)
	if simulate:
		var textured_part := DataModel.create_instance("Part", "NetworkTexturePart") as MeshInstance3D
		textured_part.mesh = BoxMesh.new()
		textured_part.set_meta("roblox_ref", "network-textured-part")
		textured_part.set_meta("anchored", true)
		textured_part.set_meta("can_collide", false)
		textured_part.set_meta("roblox_properties", {"Size": [4.0, 4.0, 1.0], "Color": [1.0, 1.0, 1.0], "Anchored": true, "CanCollide": false})
		world.add_child(textured_part)
		var decal := DataModel.create_instance("Decal", "NetworkTexture")
		decal.set_meta("roblox_ref", "network-texture-decal")
		decal.set_meta("roblox_properties", {"Texture": texture_path, "Face": 5, "Transparency": 0.0})
		textured_part.add_child(decal)
		print("[replication-server] texture fixture part=", world.get_node_or_null("NetworkTexturePart"), " decal=", textured_part.get_node_or_null("NetworkTexture"))
		var remotes: Node = services.ReplicatedStorage
		for kind in ["RemoteEvent", "RemoteFunction"]:
			var remote := DataModel.create_instance(kind, "Echo" if kind == "RemoteEvent" else "Sum")
			remote.set_meta("roblox_ref", str(remote.name))
			remotes.add_child(remote)
		bridge.register_workspace(world, id)
		engine.start_script("""
local rs=game:GetService('ReplicatedStorage')
rs.Echo.OnServerEvent:Connect(function(player,n) rs.Echo:FireClient(player,n) end)
rs.Sum.OnServerInvoke=function(player,a,b) return a+b end
local round = workspace.Round.Value
while true do
    task.wait(2)
    round += 1
    workspace.Map:Destroy()
    local map = Instance.new('Model')
    map.Name = 'Map'
    map.Parent = workspace
    local block = Instance.new('Part')
    block.Name = 'Moving'
    block.Anchored = true
    block.Size = Vector3.new(6, 2, 3)
    block.Parent = map
    workspace.Round.Value = round
    for i = 1, 10 do
        block.CFrame = CFrame.new(round * 4, 12 + i, 0)
        task.wait(.1)
    end
end
""", world, {"realm": "server", "retain": true})
	return world
