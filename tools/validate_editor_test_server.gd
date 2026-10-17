extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print("[editor-test] ", message, "=", value)
	if not value: failures.append(message)
func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains(".codex-tmp/"):
		push_error("Run the probe with isolated APPDATA under .codex-tmp.")
		quit(2)
		return
	var helper := root.get_node("EditorTestServer")
	check(helper.should_route("ws://109.71.245.162/ws"), "explicit headless editor flag routes to current checkout")
	check(not helper.should_route("ws://127.0.0.1:12345/ws"), "explicit existing local fixtures keep their endpoint")
	var state := root.get_node("GameState")
	var map_id := "classic"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="): map_id = argument.trim_prefix("--map=")
	state.configure_smart_play({}, {"map_id": map_id, "map_name": map_id})
	var network := root.get_node("NetworkManager")
	var error := ""
	network.connection_failed.connect(func(message): error = message)
	change_scene_to_file("res://scenes/main/main.tscn")
	while current_scene == null: await process_frame
	var main := current_scene
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline and error.is_empty():
		if is_instance_valid(main) and main._runtime_world_ready and main._get_local_player() != null and not state.network_gameplay_frozen: break
		await create_timer(0.05).timeout
	check(is_instance_valid(main) and main._runtime_world_ready and main._get_local_player() != null and not state.network_gameplay_frozen, "real main scene reaches a controllable avatar")
	if is_instance_valid(main): print("[editor-test] load=", main._map_loaded, " loading=", main._map_load_in_progress, " ready=", main._runtime_world_ready, " players=", main.players.get_child_count(), " manifest=", main._map_roblox_manifest.size(), " replica=", main.world.get_meta("bobux_replica_ready", false))
	check(network.current_host_ip == "127.0.0.1" and helper._child_pid > 0 and OS.is_process_running(helper._child_pid), "owned hidden authoritative child uses loopback")
	check(network.get_current_room_id().begins_with("editor:"), "production room identity is not reused")
	var ready_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(helper._ready_path))
	check(not ready_info.get("service_credentials", true) and not ready_info.get("account_credentials", true), "child retains no production service or player credentials")
	check(ready_info.get("bind_address", "") == "127.0.0.1" and ready_info.get("protocol_version", "") == network.NETWORK_PROTOCOL_VERSION and ready_info.get("runtime_name", "") == "Luau 0.719", "loopback child runs current protocol and actual Luau")
	if map_id != "classic":
		check(is_instance_valid(main) and not main._map_roblox_manifest.is_empty() and main.world.get_meta("bobux_replica_ready", false), "original imported map synchronizes from authoritative server")
		check(int(root.get_node("LuaScriptEngine").get_runtime_diagnostics().failed) == 0, "client Luau scripts have no failures after join")
	var child := int(helper._child_pid)
	await network.disconnect_from_session_async()
	await create_timer(0.3).timeout
	check(not helper.session_active, "leaving clears development session status")
	helper._shutdown_child()
	await create_timer(0.1).timeout
	check(not OS.is_process_running(child), "only the owned child is terminated")
	print("[editor-test] failures=", failures, " network_error=", error)
	quit(0 if failures.is_empty() else 1)
