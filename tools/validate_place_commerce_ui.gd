extends SceneTree

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.selected_map = "stale-local-map"
	game_state.selected_map_folder = ""
	game_state.active_room_map_id = "authoritative-published-map"
	var room_map_id_ok: bool = game_state.get_selected_map_identifier() == "authoritative-published-map"
	game_state.clear_launch_mode()
	var room_map_id_cleared: bool = game_state.get_selected_map_identifier() == "stale-local-map"
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	current_scene = studio
	await process_frame
	var planner = preload("res://addons/roblox_studio/studio_ai_planner.gd")
	var coin: Dictionary = planner.plan_for_request("создай геймпасс за 150 боблоксов с монеткой для скорости и прыжка",{})
	var daily: Dictionary = planner.plan_for_request("создай ежедневную награду 10 боблоксов справа сверху",{})
	var count: int = studio._apply_studio_ai_actions(coin.actions)
	count += studio._apply_studio_ai_actions(daily.actions)
	var buttons: Array = studio.data_model.find_all_of_class("TextButton")
	var ok: bool = count > 4 and buttons.size() >= 2 and room_map_id_ok and room_map_id_cleared
	studio.studio_music_toggle_enabled = true
	studio._on_music_browse_pressed()
	ok = ok and studio.studio_music_toggle_check.button_pressed
	studio.studio_music_dialog.hide()
	studio._start_studio_playtest()
	await create_timer(2).timeout
	var controls := studio.find_children("*", "Button", true, false)
	var commerce: Node
	for control in controls:
		for child in control.get_children():
			if child.get_script() == load("res://addons/roblox_runtime/place_commerce_button.gd") and child.kind == "gamepass_coin": commerce = child
	ok = ok and commerce != null
	if commerce != null:
		commerce._open()
		commerce._claim()
		await create_timer(0.5).timeout
		var engine := root.get_node("LuaScriptEngine")
		var workspace: Node = root.get_node("ImportedPlaceNetwork").workspace_for(commerce.target)
		var services: Dictionary = engine._ensure_roblox_service_nodes(root,workspace)
		var player: Node = services.Players.get_node_or_null("LocalPlayer")
		var tool: Node = player.get_node_or_null("Backpack/GamepassBoostCoin") if player else null
		ok = ok and tool != null
		print("[commerce-ui] preview coin in backpack=",tool != null)
		if tool:
			var character: Node = engine._bound_character_for_player(player)
			var humanoid = engine.BobuxInstance.wrap(character.get_node("Humanoid"))
			humanoid.EquipTool(engine.BobuxInstance.wrap(tool))
			await create_timer(0.2).timeout
			print("[commerce-ui] speed=",character.get_humanoid_walk_speed()," jump=",character.get_humanoid_jump_power())
			ok = ok and character.get_humanoid_walk_speed()==30 and character.get_humanoid_jump_power()==70
	print("[commerce-ui] PASS=",ok," room_map_id_ok=",room_map_id_ok," room_map_id_cleared=",room_map_id_cleared," inserted=",count)
	studio._stop_studio_playtest()
	await create_timer(1.0).timeout
	quit(0 if ok else 1)
