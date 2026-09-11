extends RefCounted

static func apply(lobby: Control) -> void:
	var bar := lobby.get_node("TopBar") as Control
	bar.offset_bottom = 42
	bar.custom_minimum_size.y = 42
	var body := lobby.get_node("Body") as MarginContainer
	body.offset_top = 42
	for edge in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + edge, 0)
	var row := lobby.get_node("Body/HBox") as HBoxContainer
	row.add_theme_constant_override("separation", 0)
	var sidebar := lobby.get_node("Body/HBox/Sidebar") as Control
	sidebar.custom_minimum_size.x = 176
	var username := lobby.get_node("%SidebarUsername") as Label
	username.custom_minimum_size.y = 36
	username.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	username.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var name_padding := StyleBoxEmpty.new()
	name_padding.content_margin_left = 12
	name_padding.content_margin_right = 10
	username.add_theme_stylebox_override("normal", name_padding)
	username.add_theme_font_size_override("font_size", 15)
	var tabs := lobby.get_node("%MainTabs") as TabContainer
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#e3e3e3")
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	tabs.add_theme_stylebox_override("panel", panel)
	var header := lobby.get_node("TopBar/HBox") as HBoxContainer
	var menu := MenuButton.new()
	menu.name = "HeaderNavigation"
	menu.text = "☰"
	menu.tooltip_text = "Навигация"
	menu.add_theme_color_override("font_color", Color.WHITE)
	menu.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	menu.set_meta("classic_flat", true)
	header.add_child(menu)
	header.move_child(menu, 1)
	var destinations := [0, 1, 5, 3, 2, 4, 12, 11, 6]
	for name in ["Home", "Profile", "Messages", "Friends", "Avatar", "Inventory", "Games", "Catalog", "Develop"]:
		menu.get_popup().add_item(name)
	menu.get_popup().id_pressed.connect(func(index: int): lobby.call("_switch_tab", destinations[index]))
	header.add_theme_constant_override("separation", 16)
	(lobby.get_node("TopBar/HBox/Logo") as Control).custom_minimum_size = Vector2(160, 36)
	(lobby.get_node("TopBar/HBox/PaddingL") as Control).custom_minimum_size.x = 6
	(lobby.get_node("TopBar/HBox/PaddingR") as Control).custom_minimum_size.x = 10
	for id in ["Nav1", "Nav2", "Nav3", "Nav4"]:
		var nav := header.get_node(id) as Button
		nav.custom_minimum_size.x = 90
		nav.add_theme_font_size_override("font_size", 15)
	var search := header.get_node("Search") as LineEdit
	header.move_child(search, header.get_node("Spacer").get_index())
	search.custom_minimum_size = Vector2(200, 28)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_stretch_ratio = 3
	search.add_theme_font_size_override("font_size", 14)
	search.placeholder_text = "Search catalog"
	search.add_theme_color_override("font_placeholder_color", Color("#aaaaaa"))
	search.add_theme_color_override("font_color", Color("#333333"))
	if search.get_signal_connection_list("text_submitted").is_empty():
		search.text_submitted.connect(func(query: String):
			lobby.call("_switch_tab", 11)
			var field := tabs.find_child("CatalogSearch", true, false) as LineEdit
			if field:
				field.text = query
				field.text_submitted.emit(query)
		)
	var wallet := Button.new()
	wallet.name = "HeaderBobloxBalance"
	wallet.text = "B$ —"
	wallet.tooltip_text = "Баланс Boblox"
	wallet.pressed.connect(func(): lobby.call("_open_boblox_shop", 1))
	var history := Button.new()
	history.name = "HeaderPurchases"
	history.text = "▤"
	history.tooltip_text = "Мои покупки"
	history.pressed.connect(func(): lobby.call("_open_boblox_shop", 2))
	var settings := Button.new()
	settings.name = "HeaderSettings"
	settings.icon = load("res://assets/textures/icons/settings_white.svg")
	settings.tooltip_text = "Настройки"
	settings.pressed.connect(func(): _settings(lobby))
	for button in [history, wallet, settings]:
		button.set_meta("classic_flat", true)
		header.add_child(button)
		header.move_child(button, header.get_node("PaddingR").get_index())
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_font_size_override("font_size", 15 if button == wallet else 24)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	var resize := func():
		var narrow := lobby.size.x < 850
		sidebar.visible = not narrow
		search.visible = lobby.size.x >= 1150
		header.add_theme_constant_override("separation", 8 if narrow else 12)
		(lobby.get_node("TopBar/HBox/Logo") as Control).custom_minimum_size.x = 106 if narrow else 150
		for id in ["Nav1", "Nav2", "Nav3", "Nav4"]: header.get_node(id).visible = not narrow
		panel.content_margin_left = 10 if narrow else 24
		panel.content_margin_right = 10 if narrow else 24
	lobby.resized.connect(resize)
	resize.call()

static func _settings(lobby: Control) -> void:
	if lobby.has_node("ClientSettings"): return
	var dialog := load("res://scripts/lobby/client_settings.gd").new() as Control
	dialog.name = "ClientSettings"
	lobby.add_child(dialog)
