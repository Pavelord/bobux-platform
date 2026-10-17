extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	root.get_node("GameState").selected_map_folder = "C:/robloxclone/.codex-tmp/performance-server/Godot/app_userdata/Bobux/cache/maps/akx0oto939gi501_bobux_park_krut"
	var main := load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/nds_network_runtime.gd"))
	root.add_child(main)
	current_scene = main
	await main._load_selected_map()
	var character: CharacterBody3D = main.add_probe_player(1)
	main._apply_character_map_scale(character,main._map_roblox_manifest)
	engine.bind_local_player_character(character)
	engine.script_message.connect(func(context,message,error):
		if error or "LOBBY ERROR" in message or "join watcher:" in message: failures.append(str(context.name)+": "+message))
	var source := FileAccess.get_file_as_string("res://.codex-tmp/performance/map-audit/park-original.luau")
	var context := Node.new()
	context.name = "OriginalParkClient"
	context.set_meta("bobux_map_asset_folder",root.get_node("GameState").selected_map_folder)
	main.world.add_child(context)
	engine.reset_runtime_diagnostics()
	engine.start_script(source,context,{"realm":"client","retain":true})
	var button: BaseButton
	var deadline := Time.get_ticks_msec()+70000
	while button == null and Time.get_ticks_msec()<deadline and engine.get_runtime_diagnostics().failed==0:
		await process_frame
		for node in main.find_children("*","BaseButton",true,false):
			if str(node.get_meta("Text",node.text)).begins_with("ПОЕХАТЬ • 1 "): button=node; break
	if button == null: failures.append("original one-seat car join button did not become ready")
	else: button.pressed.emit()
	var scriptable_frames := 0
	var moved_frames := 0
	var first_camera := Vector3.ZERO
	var last_camera := Vector3.ZERO
	var was_scriptable := false
	deadline = Time.get_ticks_msec()+35000
	while Time.get_ticks_msec()<deadline and failures.is_empty():
		await process_frame
		character._update_local_camera_rig_render_phase(.016)
		if character._is_scriptable_camera():
			scriptable_frames += 1
			if not was_scriptable: first_camera=character.player_camera.global_position
			if character.player_camera.global_position.distance_to(last_camera)>.01: moved_frames += 1
			last_camera=character.player_camera.global_position
			was_scriptable=true
		elif was_scriptable and scriptable_frames>100: break
	var passed := failures.is_empty() and scriptable_frames>100 and moved_frames>30 and first_camera.distance_to(last_camera)>1 and engine.get_runtime_diagnostics().failed==0
	print("[halloween-park-cutscene] PASS=",passed," original_ui_join=",button!=null," scriptable_frames=",scriptable_frames," moved_frames=",moved_frames," camera_travel=",first_camera.distance_to(last_camera)," diagnostics=",engine.get_runtime_diagnostics()," failures=",failures)
	engine.stop_all_scripts(main)
	main.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if passed else 1)
