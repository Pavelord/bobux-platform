extends RefCounted
const UI := preload("res://scripts/lobby/boblox_shop.gd")

static func build(lobby: Control, info: Dictionary, return_tab: int) -> void:
	var view := lobby.get_node("%MainTabs/GameDetailsView") as ScrollContainer
	for child in view.get_children():
		view.remove_child(child)
		child.queue_free()
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_bottom", 24)
	view.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var back := UI._button("‹ Games", false)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): lobby.call("_switch_tab", return_tab))
	content.add_child(back)
	var hero := _panel()
	content.add_child(hero)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hero.add_child(row)
	var artwork: Control = lobby.call("_create_game_icon_widget", info, 340.0)
	artwork.name = "GameHeroArtwork"
	artwork.custom_minimum_size = Vector2(580, 340)
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(artwork)
	for child in artwork.get_children():
		if child is TextureRect: child.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 270
	side.add_theme_constant_override("separation", 14)
	row.add_child(side)
	side.add_child(UI._label(str(info.get("name", "Untitled Experience")), 28))
	var creator := LinkButton.new()
	var owner := str(info.get("owner_name", info.get("creator", "Bobux")))
	creator.text = "By " + owner
	creator.add_theme_color_override("font_color", Color("#009fff"))
	creator.pressed.connect(func():
		lobby.set("selected_profile_user_id", str(info.get("owner_id", "")))
		lobby.set("selected_profile_username", owner)
		lobby.call("_switch_tab", 1)
	)
	side.add_child(creator)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(space)
	side.add_child(HSeparator.new())
	var play := UI._button("Play")
	play.name = "GamePlayButton"
	play.custom_minimum_size.y = 56
	play.add_theme_font_size_override("font_size", 21)
	play.add_theme_stylebox_override("normal", UI._style(Color("#00b653"), 12))
	play.pressed.connect(func(): lobby.call("_start_smart_play_for_game", info))
	side.add_child(play)
	side.add_child(HSeparator.new())
	var reactions := HFlowContainer.new()
	reactions.add_theme_constant_override("h_separation", 24)
	side.add_child(reactions)
	reactions.add_child(UI._label("☆ %d" % int(info.get("favorites", 0)), 20, Color("#e6a600")))
	var rating := preload("res://scripts/lobby/game_rating_bar.gd").new()
	rating.custom_minimum_size.x = 125
	rating.configure(info)
	reactions.add_child(rating)
	var vote_buttons: Array[Button] = []
	for value in [1, -1]:
		var vote := UI._button("Нравится" if value == 1 else "Не нравится", false)
		vote_buttons.append(vote)
		reactions.add_child(vote)
		vote.pressed.connect(func():
			var map_id := str(info.get("map_id", info.get("id", "")))
			if map_id.is_empty(): return
			for button in vote_buttons: button.disabled = true
			var response: Dictionary = await CloudAPI.vote_for_map(map_id, value)
			if not is_instance_valid(rating): return
			for button in vote_buttons: button.disabled = false
			if response.get("ok", false):
				var data := UI._payload(response)
				info.merge(data, true)
				rating.configure(data)
				vote.text = "Голос учтён"
			else:
				vote.text = "Повторить"
				vote.tooltip_text = "Не удалось сохранить голос. Войди в аккаунт и проверь соединение."
		)

	side.add_child(UI._label("%d playing now" % int(info.get("active_players", 0)), 14, UI.MUTED))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	content.add_child(tabs)
	var pages: Array[Control] = []
	var buttons: Array[Button] = []
	for tab_name in ["About", "Store", "Leaderboards", "Servers"]:
		var tab := UI._button(tab_name, false)
		tab.name = tab_name + "Tab"
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 42
		tabs.add_child(tab)
		buttons.append(tab)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		page.visible = pages.is_empty()
		pages.append(page)
		content.add_child(page)
	var show_page := func(index: int):
		for idx in range(pages.size()):
			pages[idx].visible = idx == index
			var style := UI._style(Color.WHITE, 10)
			style.border_color = Color("#00aaff") if idx == index else Color("#dddddd")
			style.set_border_width_all(0)
			style.border_width_bottom = 3 if idx == index else 1
			buttons[idx].add_theme_stylebox_override("normal", style)
	for idx in range(buttons.size()): buttons[idx].pressed.connect(show_page.bind(idx))
	show_page.call(0)
	pages[0].add_child(UI._label("Description", 23))
	var about := _panel()
	pages[0].add_child(about)
	var about_column := VBoxContainer.new()
	about_column.add_theme_constant_override("separation", 14)
	about.add_child(about_column)
	about_column.add_child(UI._label(str(info.get("description", "The creator has not added a description yet.")), 16))
	about_column.add_child(HSeparator.new())
	var stats := HFlowContainer.new()
	stats.name = "GameStatistics"
	stats.add_theme_constant_override("h_separation", 20)
	about_column.add_child(stats)
	for field in [["Visits", str(info.get("visits", info.get("visits_count", 0)))],
		["Created", lobby.call("_format_game_date", str(info.get("created_at", "")))],
		["Updated", lobby.call("_format_game_date", str(info.get("updated_at", "")))],
		["Max Players", str(info.get("max_players", 10))], ["Genre", str(info.get("genre", "All"))]]:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = 140
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UI._label(field[0], 14, Color("#999999"), true))
		cell.add_child(UI._label(field[1], 16, UI.INK, true))
		stats.add_child(cell)
	pages[1].add_child(UI._label("Store", 23))
	var store := _panel()
	pages[1].add_child(store)
	store.add_child(UI._label("This experience has no game passes for sale.", 16, UI.MUTED))
	pages[2].add_child(UI._label("Leaderboards", 23))
	var leaderboard := _panel()
	pages[2].add_child(leaderboard)
	leaderboard.add_child(UI._label("The creator has not connected a leaderboard.", 16, UI.MUTED))
	pages[3].add_child(UI._label("Servers", 23))
	var servers := VBoxContainer.new()
	servers.add_theme_constant_override("separation", 10)
	pages[3].add_child(servers)
	var load_servers := func(): _load_servers(lobby, info, servers)
	buttons[3].pressed.connect(load_servers)
	var refresh := UI._button("Refresh servers", false)
	refresh.pressed.connect(load_servers)
	pages[3].add_child(refresh)
	var resize := func():
		if not is_instance_valid(margin): return
		var compact := view.size.x < 960
		var inset := maxi(0, int((view.size.x - 1080) / 2))
		margin.add_theme_constant_override("margin_left", inset)
		margin.add_theme_constant_override("margin_right", inset)
		row.vertical = compact
		artwork.custom_minimum_size = Vector2(0, 260) if compact else Vector2(580, 340)
		side.custom_minimum_size.x = 0 if compact else 270
	view.resized.connect(resize)
	margin.tree_exiting.connect(func():
		if view.resized.is_connected(resize): view.resized.disconnect(resize)
	)
	resize.call()

static func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UI._style(Color.WHITE, 12)
	style.set_corner_radius_all(0)
	style.shadow_size = 2
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_offset = Vector2(0, 1)
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func _load_servers(lobby: Control, info: Dictionary, target: VBoxContainer) -> void:
	if target.get_meta("loading", false): return
	target.set_meta("loading", true)
	for child in target.get_children(): target.remove_child(child); child.queue_free()
	var status := UI._label("Loading servers…", 16, UI.MUTED)
	target.add_child(status)
	var filter := str(info.get("map_id", info.get("id", info.get("name", ""))))
	var response: Dictionary = await CloudAPI.fetch_active_servers(filter)
	if not is_instance_valid(target): return
	target.set_meta("loading", false)
	status.text = "No active servers. Press Play to start." if response.get("ok", false) else "Could not load servers. Try again."
	for server in response.get("data", []):
		if not server is Dictionary: continue
		status.hide()
		var panel := _panel()
		target.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		row.add_child(UI._label("%s · %d / %d players" % [str(server.get("host_username", "Bobux")), int(server.get("players_count", 0)), int(server.get("max_players", 10))], 16))
		var join := UI._button("Join")
		join.pressed.connect(func(): lobby.call("_join_live_server", server))
		row.add_child(join)
