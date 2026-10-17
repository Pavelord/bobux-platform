extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	await process_frame
	root.get_node("ClientPreferences").values.app_theme = "halloween"
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(load("res://tools/fixtures/seasonal_lobby.gd"))
	root.add_child(lobby)
	current_scene = lobby
	check(lobby.get_node_or_null("SeasonalTheme") != null, "lobby theme was deferred beyond ready")
	for path in ["TopBar/HBox/Nav1", "TopBar/HBox/Nav2"]:
		check((lobby.get_node(path) as Button).icon == null, "header icon still present: " + path)
	for tab in [2, 4, 11]:
		lobby._switch_tab(tab)
		var page: Control = lobby.main_tabs.get_tab_control(tab)
		check(lobby.main_tabs.current_tab == tab, "tab did not open")
		for node: Node in page.find_children("*", "Control", true, false):
			if not (node as Control).is_visible_in_tree() or node.name == "_focus": continue
			if node.has_meta("seasonal_preserve_color") or node.has_meta("seasonal_ignore"): continue
			if node is Panel or node is PanelContainer:
				var box := (node as Control).get_theme_stylebox("panel") as StyleBoxFlat
				if box != null and not node.has_meta("bobux_author_ui"):
					check(box.bg_color.v < 0.6 or box.bg_color.a == 0, "white panel before first frame: " + str(node.get_path()))
	var item := {"id": "event_halloween_2026_gift", "name": "Halloween gift", "data": {"limited": true}}
	var inventory: Control = lobby._create_inventory_item_card(item, "Accessories")
	lobby.add_child(inventory)
	var badge := inventory.find_child("LimitedBadge", true, false) as PanelContainer
	check(badge != null, "inventory event badge missing")
	check(badge != null and (badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Color("399341"), "inventory badge is not green")
	var wardrobe: Control = lobby.avatar_ui._create_item_card(item)
	lobby.add_child(wardrobe)
	check(wardrobe.find_child("LimitedBadge", true, false) != null, "avatar event badge missing")
	inventory.queue_free()
	wardrobe.queue_free()
	lobby._switch_tab(0)
	var banner := lobby.find_child("HalloweenWelcome", true, false)
	var action := banner.find_children("*", "Button", true, false)[0] as Button
	action.pressed.emit()
	check(lobby.main_tabs.current_tab == 11, "banner did not open catalog")
	var halloween := lobby.main_tabs.get_node("CatalogView").find_child("HalloweenCatalog", true, false) as Control
	check(halloween != null and halloween.visible, "banner did not open Halloween subtab directly")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var folder := "user://validation/halloween"
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join("halloween_catalog_first_frame.png"))
	root.get_node("CloudAPI")._cleanup_active_http_requests()
	lobby.queue_free()
	await process_frame
	print("SEASONAL_TAB_ENTRY_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
