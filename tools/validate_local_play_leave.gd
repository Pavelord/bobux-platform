extends SceneTree
var failures: Array[String]=[]
func _initialize(): run.call_deferred()
func check(ok:bool,label_:String):
	print("[play_leave] ",label_,"=",ok)
	if not ok: failures.append(label_)
func run():
	# Local Godot's WebSocket listener has no nginx /health endpoint.
	var transport := GDScript.new()
	transport.source_code = "extends 'res://autoload/client_network.gd'\nfunc _warm_server_if_needed(_url: String): pass\n"
	if transport.reload()!=OK: quit(1); return
	root.get_node("NetworkManager").set_script(transport)
	var api=root.get_node("CloudAPI")
	api.base_url="http://127.0.0.1:1/rest/v1"
	api.project_url="http://127.0.0.1:1"
	api._auth_user_id="local-menu-validation"
	var session=root.get_node("UserSession")
	session.user_id="local-menu-validation"
	session.username="Local validation"
	session.is_logged_in=true
	var state=root.get_node("GameState")
	state.configure_target_join({"room_id":"local-menu-validation","server_url":"ws://127.0.0.1:18768/ws","ip":"127.0.0.1","port":18768,"create_if_missing":true,"map_id":"classic","map_name":"Classic"},{})
	change_scene_to_file("res://scenes/main/main.tscn")
	await process_frame
	await process_frame
	var main=current_scene
	var player:CharacterBody3D
	for i in range(400):
		if is_instance_valid(main): player=main._get_local_player()
		if is_instance_valid(player) and main._runtime_world_ready and not state.network_gameplay_frozen: break
		await create_timer(0.05).timeout
	check(is_instance_valid(player) and main._runtime_world_ready and not state.network_gameplay_frozen,"join reaches controllable character")
	if not is_instance_valid(player):
		quit(1)
		return
	player.set_lua_position(player.position+Vector3(12,0,0))
	var before=player.position
	main._on_game_menu_button_pressed()
	await create_timer(0.3).timeout
	main._on_respawn_pressed()
	for i in range(100):
		await create_timer(0.05).timeout
		if player.position.distance_to(before)>4 and not player._is_respawning: break
	check(player.position.distance_to(before)>4 and not player._is_respawning,"Reset receives authoritative respawn")
	var context=Node.new()
	main.get_node("World").add_child(context)
	root.get_node("LuaScriptEngine").start_script("task.spawn(function() while true do task.wait(0.03) end end)",context,{"retain":true})
	await main.leave_game()
	await create_timer(0.6).timeout
	check(is_instance_valid(current_scene) and current_scene.scene_file_path=="res://scenes/lobby/lobby.tscn","Leave reaches lobby with active Lua tasks")
	var diagnostics:Dictionary=root.get_node("LuaScriptEngine").get_runtime_diagnostics()
	check(int(diagnostics.active)==0 and int(diagnostics.retained)==0 and int(diagnostics.pending)==0,"no script runtimes survive leaving the mode")
	print("[play_leave] failures=",failures)
	quit(0 if failures.is_empty() else 1)
