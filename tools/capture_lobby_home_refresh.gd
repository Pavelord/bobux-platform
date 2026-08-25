extends SceneTree

const CAPTURE_PATH := "user://lobby_home_refresh.png"


func _initialize() -> void:
	root.size = Vector2i(1440, 900)
	var packed := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lobby := packed.instantiate() as Control
	root.add_child(lobby)
	await create_timer(1.0).timeout
	var loading_overlay: Control = lobby.get("_loading_overlay") as Control
	if loading_overlay != null:
		loading_overlay.hide()
	# Invalidate the live network refresh started by Lobby._ready so this probe
	# can verify a same-content refresh without unrelated server data racing it.
	lobby.set("_discover_refresh_token", int(lobby.get("_discover_refresh_token")) + 1000)

	var friends_container: Container = lobby.get("home_friends_container") as Container
	if friends_container != null:
		_clear_children(friends_container)
		var sample_profiles: Array[Dictionary] = [
			{"id": "preview-1", "username": "BuilderMax", "avatar_data": {"head": "#f4c542", "torso": "#246fbd", "left_arm": "#f4c542", "right_arm": "#f4c542", "left_leg": "#263238", "right_leg": "#263238"}},
			{"id": "preview-2", "username": "Denchiz", "avatar_data": {"head": "#f4c542", "torso": "#1b8c49", "left_arm": "#f4c542", "right_arm": "#f4c542", "left_leg": "#252525", "right_leg": "#252525"}},
			{"id": "preview-3", "username": "Fox228", "avatar_data": {"head": "#e6b98a", "torso": "#f7f7f7", "left_arm": "#e6b98a", "right_arm": "#e6b98a", "left_leg": "#303238", "right_leg": "#303238"}},
			{"id": "preview-4", "username": "VoidPlayer", "avatar_data": {"head": "#323238", "torso": "#14151a", "left_arm": "#e58d1b", "right_arm": "#2b6fc0", "left_leg": "#202126", "right_leg": "#202126"}}
		]
		for profile in sample_profiles:
			friends_container.add_child(lobby.call("_create_home_friend_avatar", profile, {}))

	var sample_games: Array[Dictionary] = [
		{"name": "Classic Crossroads", "icon_path": "res://assets/branding/login_background.png", "active_players": 12, "visits": 8421, "likes": 416},
		{"name": "Avatar Workshop", "icon_path": "res://assets/avatar/avatar_room_bg.jpg", "active_players": 7, "visits": 3702, "likes": 291},
		{"name": "Bobux Obby", "icon_path": "res://assets/branding/bobux_android_icon_source.png", "active_players": 4, "visits": 2115, "likes": 184},
		{"name": "Build Together", "icon_path": "res://assets/branding/bobux_logo.png", "active_players": 2, "visits": 1198, "likes": 96},
		{"name": "Retro Hangout", "icon_path": "res://assets/branding/bobux_app_icon.png", "active_players": 1, "visits": 954, "likes": 78},
		{"name": "Color Parkour", "icon_path": "res://assets/avatar/shirt_template_reference.jpg", "active_players": 0, "visits": 722, "likes": 61}
	]
	for property_name in ["recommended_cards_grid", "new_cards_grid"]:
		var grid: GridContainer = lobby.get(property_name) as GridContainer
		if grid == null:
			continue
		_clear_children(grid)
		grid.remove_meta("bobux_content_signature")
		await lobby.call(
			"_populate_home_game_grid",
			grid,
			sample_games,
			sample_games.size(),
			int(lobby.get("_discover_refresh_token")),
			lobby.get("recommended_status_label") if property_name == "recommended_cards_grid" else lobby.get("new_status_label"),
			"No experiences",
			true
		)
	var recommended_status: Label = lobby.get("recommended_status_label") as Label
	if recommended_status != null:
		recommended_status.text = "6 experiences"

	await create_timer(3.0).timeout
	var recommended_grid: GridContainer = lobby.get("recommended_cards_grid") as GridContainer
	if recommended_grid != null and recommended_grid.get_child_count() > 0:
		var hover_card := recommended_grid.get_child(0) as Control
		if hover_card != null:
			var hover_overlay := hover_card.find_child("PlayHoverOverlay", true, false) as Control
			var play_button := hover_card.find_child("PlayButton", true, false) as Button
			hover_card.mouse_entered.emit()
			await process_frame
			await lobby.call(
				"_populate_home_game_grid",
				recommended_grid,
				sample_games,
				sample_games.size(),
				int(lobby.get("_discover_refresh_token")),
				recommended_status,
				"No experiences",
				true
			)
			if recommended_grid.get_child(0) != hover_card:
				push_error("[capture_lobby_home_refresh] Stable refresh replaced the hovered card")
				quit(1)
				return
			if hover_overlay == null or hover_overlay.modulate.a < 0.99:
				push_error("[capture_lobby_home_refresh] Play overlay did not remain visible after hover")
				quit(1)
				return
			if play_button == null or play_button.mouse_filter != Control.MOUSE_FILTER_STOP or not play_button.pressed.has_connections():
				push_error("[capture_lobby_home_refresh] Play button is not interactive")
				quit(1)
				return
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(CAPTURE_PATH) != OK:
		push_error("[capture_lobby_home_refresh] Failed to save capture")
		quit(1)
		return
	print("[capture_lobby_home_refresh] Capture saved")
	quit(0)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
