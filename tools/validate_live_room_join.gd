extends SceneTree

# Uses the real main scene and production transport, without account credentials.
# Run with a separate APPDATA directory and an isolated validation room.
func _initialize() -> void: run.call_deferred()

func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains(".codex-tmp/"):
		push_error("Live probe requires isolated APPDATA under .codex-tmp")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var late := args.has("--late")
	var state := root.get_node("GameState")
	root.get_node("UserSession").username = "NetworkCheckLate" if late else "NetworkCheckFirst"
	var map_id := "z9ovqynlv860sgw_baseplate 108"
	state.configure_target_join({
		"server_url": "ws://109.71.245.162/ws",
		"room_id": "z9ovqynlv860sgw_baseplate_108:validation:20261004",
		"map_id": map_id, "map_name": "Baseplate 108", "create_if_missing": true,
		"max_players": 4
	}, {})
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var start := Time.get_ticks_msec()
	var deadline := start + 150000
	var ready_at := 0
	var last_progress := 0
	var samples: Array[float] = []
	var phases := {}
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not is_instance_valid(main) or current_scene != main:
			print("[live_join] FAIL returned to lobby: ", state.last_network_error)
			quit(1)
			return
		var now := Time.get_ticks_msec()
		if ready_at == 0 and main._runtime_world_ready and not state.network_gameplay_frozen and main._get_local_player() != null:
			ready_at = now
			var player: Node3D = main._get_local_player()
			print("[live_join] READY late=", late, " milliseconds=", ready_at-start, " position=", player.global_position, " replica=", main.world.get_meta("bobux_replica_ready",false))
			var nodes: Dictionary = root.get_node("ImportedPlaceNetwork")._client.get("nodes", {})
			var window: Node = nodes.get("1014")
			var decal: Node = nodes.get("25")
			var texture_path := str(decal.get_meta("roblox_properties", {}).get("Texture", "")) if decal else ""
			print("[live_join] visuals window_transparency=", window.get_meta("roblox_properties", {}).get("Transparency") if window else "missing", " decal=", texture_path, " file=", FileAccess.file_exists(texture_path), " face_quads=", decal.get_parent().get_children().filter(func(n): return n.get_meta("roblox_face_decal", false)).size() if decal else 0)
		if now-last_progress > 15000:
			last_progress = now
			var status: Node = main.world.get_node_or_null("Script/Status")
			var phase: String = str(status.get_meta("Value", "")) if status != null else "missing"
			phases[phase] = true
			var structure: Node = main.world.get_node_or_null("Structure")
			print("[live_join] elapsed_ms=", now-start, " loaded=",main._map_loaded," ready=",main._runtime_world_ready," frozen=",state.network_gameplay_frozen, " phase=",phase, " structure_parts=",structure.find_children("*","MeshInstance3D",true,false).size() if structure else -1)
		if ready_at > 0:
			samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			if now-ready_at > (45000 if late else 90000): break
	var ok: bool = ready_at > 0 and is_instance_valid(main) and main._runtime_world_ready
	if ok:
		samples.sort()
		print("[live_join] PASS late=",late," join_ms=",ready_at-start," frame_p95_ms=",samples[int(samples.size()*0.95)]," nodes=",root.get_node("ImportedPlaceNetwork")._client.get("nodes",{}).size()," phases=",phases.keys())
	else: print("[live_join] FAIL timeout: ", state.last_network_error)
	if ok:
		var leave_start := Time.get_ticks_msec()
		await main.leave_game()
		await process_frame
		await create_timer(1.0).timeout
		print("[live_join] leave_ms=", Time.get_ticks_msec()-leave_start, " retired_remaining=", root.get_node("ImportedPlaceNetwork")._retired.size())
	else: root.get_node("NetworkManager").disconnect_from_session()
	quit(0 if ok else 1)
