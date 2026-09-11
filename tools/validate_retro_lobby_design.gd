extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = root.size
	var lobby := (load("res://scenes/lobby/lobby.tscn") as PackedScene).instantiate() as Control
	lobby.set_meta("boblox_preview", true)
	var sample: Array = []
	for source in ["avatar_items", "model_assets"]:
		var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.codex-tmp/%s_preview_audit.json" % source))
		if rows is Array:
			var by_category := {}
			for row in rows:
				var category := str(row.get("category", "model"))
				if int(by_category.get(category, 0)) < 8:
					sample.append(row)
					by_category[category] = int(by_category.get(category, 0)) + 1
	lobby.set_meta("catalog_preview_items", sample)
	root.add_child(lobby)
	await create_timer(1.0).timeout
	var overlay := lobby.get("_loading_overlay") as Control
	if overlay: overlay.hide()
	lobby.call("_switch_tab", 11)
	await create_timer(1.0).timeout
	var renderer := lobby.get_node_or_null("CatalogThumbnailRenderer")
	if renderer:
		for frame in range(1200):
			if not renderer.get("_running"): break
			await process_frame
	await _capture("catalog")
	assert(lobby.get_node("TopBar/HBox/HeaderBobloxBalance") != null)
	assert(lobby.find_child("CatalogSearch", true, false) != null)
	assert(lobby.find_child("NavBricksClubBtn", true, false) == null)
	lobby.call("_show_game_details_page", {
		"name": "Bobux Adventure", "owner_name": "Bobux", "map_id": "preview_map",
		"description": "Build, explore and play together. A place for your next adventure.",
		"visits": 1234, "likes_count": 128, "favorites": 23, "active_players": 7,
		"created_at": "2026-06-12", "updated_at": "2026-09-10", "max_players": 20,
		"icon_path": "res://assets/branding/login_background.png"
	})
	await _capture("details")
	var details := lobby.get_node("%MainTabs/GameDetailsView") as Control
	assert(details.find_child("GamePlayButton", true, false) != null)
	assert(details.find_child("ServersTab", true, false) is Button)
	for cell in details.find_child("GameStatistics", true, false).get_children():
		assert(cell.size.x >= 140)
	lobby.call("_open_boblox_shop", 1)
	await create_timer(0.4).timeout
	await _capture("currency")
	lobby.call("_open_boblox_shop", 0)
	await _capture("club_clean")
	var cards_page := PanelContainer.new()
	cards_page.name = "CardsValidation"
	lobby.get_node("%MainTabs").add_child(cards_page)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 14)
	cards_page.add_child(grid)
	for i in range(5):
		var card: Control = lobby.call("_create_smart_play_card", {
			"name": ["Bobux Adventure", "Build Together", "Obby World", "Island Survival", "Studio Sandbox"][i],
			"active_players": [3200, 128, 26, 0, 84][i], "rating_positive": 80 + i * 5, "rating_negative": 20 - i * 5,
			"thumbnail": "res://assets/branding/login_background.png"
		}, true, true)
		grid.add_child(card)
		assert(card.find_child("GameRating", true, false) != null)
		assert(card.find_child("OnlineCount", true, false) != null)
	lobby.call("_switch_tab", cards_page.get_index())
	await _capture("cards")
	root.size = Vector2i(480, 900)
	root.content_scale_size = root.size
	lobby.call("_open_boblox_shop", 1)
	await create_timer(0.5).timeout
	await _capture("mobile_currency")
	var header := lobby.get_node("TopBar/HBox") as Control
	assert(header.size.x <= 480)
	lobby.queue_free()
	await process_frame
	print("[validate_retro_lobby_design] PASS")
	quit(0)

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "res://.codex-tmp/retro_%s.png" % name
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("capture=" + ProjectSettings.globalize_path(path))
