class_name LobbyStyler
extends RefCounted

static func apply_2016_theme(lobby: Control) -> void:
	_style_topbar(lobby)
	_style_sidebar(lobby)
	_style_avatar_tab(lobby)

static func _style_topbar(lobby: Control) -> void:
	var topbar := lobby.get_node_or_null("TopBar") as Panel
	if topbar:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0074BD")
		style.border_width_bottom = 0
		topbar.add_theme_stylebox_override("panel", style)
		topbar.custom_minimum_size.y = 44 

	var text_elements := [
		"TopBar/HBox/Logo", "TopBar/HBox/Nav1", "TopBar/HBox/Nav2", 
		"TopBar/HBox/Nav3", "TopBar/HBox/Nav4", "TopBar/HBox/NavRobux"
	]
	
	for path in text_elements:
		var node = lobby.get_node_or_null(path)
		if node is Control:
			node.add_theme_color_override("font_color", Color.WHITE)
			if node is Label:
				node.add_theme_font_size_override("font_size", 22)
				node.add_theme_color_override("font_shadow_color", Color(0,0,0,0))
			elif node is Button:
				node.add_theme_font_size_override("font_size", 14)
				var flat_style := StyleBoxEmpty.new()
				node.add_theme_stylebox_override("normal", flat_style)
				node.add_theme_stylebox_override("hover", flat_style)
				node.add_theme_stylebox_override("pressed", flat_style)
				node.add_theme_stylebox_override("focus", flat_style)

	var search := lobby.get_node_or_null("TopBar/HBox/Search") as LineEdit
	if search:
		search.add_theme_color_override("font_color", Color("#888888"))
		var s_style := StyleBoxFlat.new()
		s_style.bg_color = Color.WHITE
		s_style.corner_radius_top_left = 3
		s_style.corner_radius_top_right = 3
		s_style.corner_radius_bottom_right = 3
		s_style.corner_radius_bottom_left = 3
		search.add_theme_stylebox_override("normal", s_style)

static func _style_sidebar(lobby: Control) -> void:
	var labels_map := {
		"NavHomeBtn": "Home", "NavProfileBtn": "Profile",
		"NavMessagesBtn": "Messages", "NavFriendsBtn": "Friends",
		"NavCharacterBtn": "Avatar", "NavInventoryBtn": "Inventory",
		"NavTradeBtn": "Trade", "NavGroupsBtn": "Groups",
		"NavForumBtn": "Forum", "NavBlogBtn": "Blog",
		"NavPromocodesBtn": "Promocodes"
	}
	
	var s_box := StyleBoxFlat.new()
	s_box.bg_color = Color.TRANSPARENT
	s_box.content_margin_left = 12
	s_box.content_margin_top = 6
	s_box.content_margin_bottom = 6
	
	var h_box := s_box.duplicate() as StyleBoxFlat
	h_box.bg_color = Color("#F0F2F4") 
	h_box.border_width_left = 3
	h_box.border_color = Color("#0074BD")

	var sidebar = lobby.get_node_or_null("Body/HBox/Sidebar") as Control
	if sidebar:
		if not sidebar.has_meta("has_bg_draw"):
			sidebar.set_meta("has_bg_draw", true)
			sidebar.draw.connect(func():
				sidebar.draw_rect(Rect2(Vector2.ZERO, sidebar.size), Color.WHITE)
				sidebar.draw_line(Vector2(sidebar.size.x - 1, 0), Vector2(sidebar.size.x - 1, sidebar.size.y), Color("#E3E3E3"), 1.0)
			)
			sidebar.queue_redraw()
	
	var btn_names = [
		"NavHomeBtn", "NavProfileBtn", "NavMessagesBtn", "NavFriendsBtn",
		"NavCharacterBtn", "NavInventoryBtn", 
		"NavTradeBtn", "NavGroupsBtn",
		"NavForumBtn", "NavBlogBtn", "NavPromocodesBtn"
	]
	var icons_map = {
		"NavHomeBtn": "home", "NavProfileBtn": "profile",
		"NavMessagesBtn": "messages", "NavFriendsBtn": "friends",
		"NavCharacterBtn": "avatar", "NavInventoryBtn": "inventory",
		"NavTradeBtn": "trade", "NavGroupsBtn": "groups",
		"NavForumBtn": "forum", "NavBlogBtn": "blog",
		"NavPromocodesBtn": "promocodes"
	}
	
	for btn_name in btn_names:
		var btn = lobby.get_node_or_null("%" + btn_name) as Button
		if not btn: btn = lobby.get_node_or_null("Body/HBox/Sidebar/" + btn_name) as Button
		if not btn: continue
		
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_stylebox_override("normal", s_box)
		btn.add_theme_stylebox_override("hover", h_box)
		btn.add_theme_stylebox_override("pressed", h_box)
		btn.add_theme_stylebox_override("focus", s_box)
		btn.add_theme_color_override("font_color", Color("#4A4A4A"))
		btn.add_theme_color_override("font_hover_color", Color("#191919"))
		btn.add_theme_font_size_override("font_size", 14)
		btn.text = str(labels_map.get(btn.name, btn.text.strip_edges()))
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon = false
		btn.add_theme_constant_override("h_separation", 10)
		
		var icon_id := str(icons_map.get(btn.name, ""))
		if not icon_id.is_empty():
			var icon_texture := _load_sidebar_icon(icon_id)
			if icon_texture != null:
				btn.icon = icon_texture

	var upgrade = lobby.get_node_or_null("Body/HBox/Sidebar/UpgradeBtn") as Button
	if upgrade:
		var u_style := StyleBoxFlat.new()
		u_style.bg_color = Color("#0074BD")
		u_style.corner_radius_top_left = 2; u_style.corner_radius_top_right = 2
		u_style.corner_radius_bottom_right = 2; u_style.corner_radius_bottom_left = 2
		upgrade.add_theme_stylebox_override("normal", u_style)
		upgrade.add_theme_stylebox_override("hover", u_style)
		upgrade.add_theme_color_override("font_color", Color.WHITE)
		upgrade.text = "Upgrade Now"

static func _load_sidebar_icon(icon_id: String) -> Texture2D:
	var icon_path := "res://assets/textures/icons/%s.svg" % icon_id
	if ResourceLoader.exists(icon_path):
		var imported_texture := load(icon_path) as Texture2D
		if imported_texture != null:
			return imported_texture

	var file := FileAccess.open(icon_path, FileAccess.READ)
	if file == null:
		push_warning("[LobbyStyler] Sidebar icon is missing: %s" % icon_path)
		return null

	var svg_str := file.get_as_text()
	file.close()

	var image := Image.new()
	if image.load_svg_from_string(svg_str, 2.0) != OK:
		push_warning("[LobbyStyler] Failed to parse sidebar SVG icon: %s" % icon_path)
		return null

	image.resize(22, 22, Image.INTERPOLATE_TRILINEAR)
	return ImageTexture.create_from_image(image)

static func _style_avatar_tab(lobby: Control) -> void:
	var view = lobby.get_node_or_null("%MainTabs/AvatarView")
	if not view: return
	
	var cat_flow = view.get_node_or_null("Content/MainRow/RightColumn/WardrobePanel/WardrobeMargin/WardrobeVBox/CategoriesFlow")
	if cat_flow:
		var link_style := StyleBoxEmpty.new()
		for child in cat_flow.get_children():
			if child is Button:
				child.add_theme_stylebox_override("normal", link_style)
				child.add_theme_stylebox_override("hover", link_style)
				child.add_theme_color_override("font_color", Color("#0074BD"))
				child.add_theme_color_override("font_hover_color", Color("#0057B8"))
				child.add_theme_font_size_override("font_size", 12)
				
	var tabs_row = view.get_node_or_null("Content/MainRow/RightColumn/WardrobePanel/WardrobeMargin/WardrobeVBox/TabsRow")
	if tabs_row:
		for child in tabs_row.get_children():
			if child is Button:
				var tab_style := StyleBoxFlat.new()
				tab_style.bg_color = Color("#F8F8F8")
				tab_style.border_width_left = 1; tab_style.border_width_top = 1; tab_style.border_width_right = 1
				tab_style.border_color = Color("#DDDDDD")
				tab_style.content_margin_left = 16; tab_style.content_margin_right = 16
				tab_style.content_margin_top = 6; tab_style.content_margin_bottom = 6
				child.add_theme_stylebox_override("normal", tab_style)
				if child.name == "WardrobeTab":
					var active := tab_style.duplicate() as StyleBoxFlat
					active.bg_color = Color.WHITE
					active.border_width_top = 2
					active.border_color = Color("#DDDDDD")
					child.add_theme_stylebox_override("normal", active)
	
	var left_col = view.get_node_or_null("Content/MainRow/LeftColumn")
	if left_col:
		for child in left_col.get_children():
			if child is Panel:
				var p_style := StyleBoxFlat.new()
				p_style.bg_color = Color.WHITE
				p_style.border_width_left = 1; p_style.border_width_top = 1
				p_style.border_width_right = 1; p_style.border_width_bottom = 1
				p_style.border_color = Color("#EEEEEE")
				child.add_theme_stylebox_override("panel", p_style)

	var pnl = view.get_node_or_null("Content/MainRow/RightColumn/WardrobePanel")
	if pnl is Panel:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color.WHITE
		bg.set_border_width_all(0)
		pnl.add_theme_stylebox_override("panel", bg)
	
	var r6 = view.get_node_or_null("Content/MainRow/LeftColumn/TypeRow/BtnR6")
	var r15 = view.get_node_or_null("Content/MainRow/LeftColumn/TypeRow/BtnR15")
	var t_style = StyleBoxFlat.new()
	t_style.bg_color = Color("#EEEEEE")
	t_style.border_width_left = 1; t_style.border_width_top = 1
	t_style.border_width_right = 1; t_style.border_width_bottom = 1
	t_style.border_color = Color("#CCCCCC")
	if r6 is Button:
		r6.add_theme_stylebox_override("normal", t_style)
		r6.add_theme_color_override("font_color", Color("#333333"))
		r6.text = "R6"
	if r15 is Button:
		var t2 = t_style.duplicate() as StyleBoxFlat
		t2.bg_color = Color.WHITE
		r15.add_theme_stylebox_override("normal", t2)
		r15.add_theme_color_override("font_color", Color("#A0A0A0"))
		r15.text = "R15"
