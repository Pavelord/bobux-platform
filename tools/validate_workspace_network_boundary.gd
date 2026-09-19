extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	host.name = "Main"
	root.add_child(host)
	current_scene = host
	var world := Node3D.new()
	world.name = "World"
	host.add_child(world)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	world.add_child(spawner)
	spawner.spawn_path = NodePath("../Players")
	var engine := root.get_node("LuaScriptEngine")
	var maps: Array[Node3D] = []
	for index in range(2):
		var room := Node3D.new()
		room.name = "Room%d" % index
		room.position = Vector3(1000 * (index + 1), 0, 0)
		world.add_child(room)
		var map := Node3D.new()
		map.name = "MapRoot"
		map.set_meta("roblox_class", "Workspace")
		room.add_child(map)
		maps.append(map)
		var manifest := {"services": [{"ref": "0", "class": "Workspace", "properties": {}}, {"ref": "1", "class": "ServerStorage"}],
			"instances": [{"ref": "2", "parent_ref": "0", "class": "Folder", "name": "Island"}],
			"hierarchy": [{"child": "0", "parent": "-1"}, {"child": "1", "parent": "-1"}, {"child": "2", "parent": "0"}]}
		if index == 0:
			engine.install_roblox_manifest(manifest, map)
		else:
			await engine.install_roblox_manifest_async(manifest, map, 32)
		if map.get_parent() != room or map.global_position != room.global_position:
			push_error("Workspace import moved the native room container")
			quit(1)
			return
		assert(engine._resolve_workspace_node(host, map) == map)
	assert(maps[0].get_node("Island") != maps[1].get_node("Island"))
	assert(host.get_node("World/Players") == players)
	assert(spawner.get_node(spawner.spawn_path) == players)
	print("WORKSPACE_NETWORK_BOUNDARY_OK: sync/async import, isolated rooms, stable replication paths")
	host.queue_free()
	await process_frame
	quit(0)
