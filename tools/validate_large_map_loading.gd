extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host_root := Node.new()
	host_root.name = "LoadingHost"
	root.add_child(host_root)
	var client_root := Node.new()
	client_root.name = "LoadingClient"
	root.add_child(client_root)
	var host_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	set_multiplayer(host_api, host_root.get_path())
	set_multiplayer(client_api, client_root.get_path())
	var server_peer := WebSocketMultiplayerPeer.new()
	var port := 27860
	var listen_error := ERR_CANT_CREATE
	for candidate in range(port, port + 20):
		listen_error = server_peer.create_server(candidate, "127.0.0.1")
		if listen_error == OK:
			port = candidate
			break
	if listen_error != OK:
		push_error("No local test WebSocket port available")
		quit(1)
		return
	host_api.multiplayer_peer = server_peer
	var client_peer := WebSocketMultiplayerPeer.new()
	client_peer.create_client("ws://127.0.0.1:%d" % port)
	client_api.multiplayer_peer = client_peer
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	var probe_script := GDScript.new()
	probe_script.source_code = "extends \"res://scripts/main/main.gd\"\nfunc _ready():\n\t_ensure_host_keepalive_timer()\n\t_network_loading_overlay = ColorRect.new()\n\tadd_child(_network_loading_overlay)\n\t_network_loading_overlay.show()\nfunc _process(_delta):\n\tpass\n"
	_check(probe_script.reload() == OK, "loading harness compiles after autoload initialization")
	var host_main := main_scene.instantiate()
	host_main.set_script(probe_script)
	host_root.add_child(host_main)
	var client_main := main_scene.instantiate()
	client_main.set_script(probe_script)
	client_root.add_child(client_main)
	var deadline := Time.get_ticks_msec() + 5000
	while client_api.get_peers().is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(client_api.get_peers().has(1), "local socket connects")
	if client_api.get_peers().has(1):
		client_main.call("_on_transport_progress_updated", "auth", 0.82)
		var timer := client_main.get("_host_keepalive_timer") as Timer
		_check(not timer.is_stopped(), "heartbeat starts before map download")
		var reload: Dictionary = await client_main.call("reload_runtime_map_from_game_state")
		_check(bool(reload.get("deferred", false)), "initial download does not build world twice")
		# Exceed the production server's eight-second stale-peer deadline while
		# the real Main RPCs send and receive keepalives with loading UI visible.
		await create_timer(9.2).timeout
		var pong_age := Time.get_ticks_msec() - int(client_main.get("_host_last_pong_msec"))
		_check(int(client_main.get("_last_ping_rtt_msec")) >= 0, "loading client receives real RPC pong")
		_check(pong_age < 1800, "heartbeats continue throughout slow loading")
		_check(not bool(client_main.get("_runtime_world_ready")), "world stays unready during download")
		client_main.call("_stop_host_keepalive")
	var surface := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 10, 2)
	surface.mesh = mesh
	surface.position = Vector3(25, -200, 10)
	host_root.add_child(surface)
	var spawn: Vector3 = host_main.call("_spawn_position_above_surface", surface, Vector3(50, 0, 50))
	_check(is_equal_approx(spawn.y, -192.8), "spawn uses actual mesh height")
	_check(absf(spawn.x - 25) <= 0.41 and absf(spawn.z - 10) <= 0.41, "spawn offsets stay inside narrow pad")
	for index in range(200):
		host_main.call("_register_fallback_spawn_surface", surface)
	_check((host_main.get("_fallback_spawn_positions") as Array).size() == 64, "large maps bound replicated spawn list")
	client_peer.close()
	server_peer.close()
	client_root.queue_free()
	host_root.queue_free()
	await process_frame
	print("[validate_large_map_loading] ok=%s failures=%s" % [failures.is_empty(), failures])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
