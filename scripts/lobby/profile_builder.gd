class_name ProfileBuilder
extends RefCounted

static func build(lobby: Control) -> void:
	var tabs = lobby.get_node_or_null("%MainTabs")
	if not tabs: return
	
	var profile_view = tabs.get_node_or_null("ProfileView") as ScrollContainer
	if not profile_view: return
	
	# Clear existing
	for child in profile_view.get_children():
		profile_view.remove_child(child)
		child.queue_free()
		
	profile_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_view.add_child(margin)
	
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	
	# --- Top Header User Box ---
	var header_panel := PanelContainer.new()
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color.WHITE
	h_style.border_width_left = 1; h_style.border_width_top = 1
	h_style.border_width_right = 1; h_style.border_width_bottom = 3
	h_style.border_color = Color("#DDDDDD")
	header_panel.add_theme_stylebox_override("panel", h_style)
	root.add_child(header_panel)
	
	var v_head := VBoxContainer.new()
	header_panel.add_child(v_head)
	
	# Avatar + Username + Stats
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 20)
	var m2 := MarginContainer.new()
	m2.add_theme_constant_override("margin_left", 16)
	m2.add_theme_constant_override("margin_top", 16)
	m2.add_theme_constant_override("margin_bottom", 16)
	m2.add_child(top_row)
	v_head.add_child(m2)
	
	# Avatar circle bg
	var av_bg := Panel.new()
	av_bg.custom_minimum_size = Vector2(100, 100)
	var ab_style := StyleBoxFlat.new()
	ab_style.bg_color = Color.WHITE
	ab_style.corner_radius_top_left = 50; ab_style.corner_radius_top_right = 50
	ab_style.corner_radius_bottom_left = 50; ab_style.corner_radius_bottom_right = 50
	ab_style.border_color = Color("#CCCCCC")
	ab_style.border_width_left = 1; ab_style.border_width_top = 1
	ab_style.border_width_right = 1; ab_style.border_width_bottom = 1
	av_bg.add_theme_stylebox_override("panel", ab_style)
	av_bg.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	top_row.add_child(av_bg)
	lobby.profile_header_avatar_holder = av_bg
	var player_res := load("res://scenes/player/player.tscn")
	var initial_profile := {
		"id": UserSession.user_id,
		"username": UserSession.username,
		"avatar_data": UserSession.avatar_data.duplicate(true),
		"avatar_outfit": UserSession.avatar_data.duplicate(true)
	}
	av_bg.add_child(lobby._create_profile_avatar_snapshot(initial_profile, 100))
	lobby.profile_header_preview_player = null
	
	var name_box := VBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(name_box)
	
	var lbl_name := Label.new()
	lbl_name.text = "Player" # Will be updated
	lobby.profile_username_label = lbl_name
	lbl_name.add_theme_color_override("font_color", Color("#111111"))
	lbl_name.add_theme_font_size_override("font_size", 24)
	name_box.add_child(lbl_name)
	
	var lbl_sub := Label.new()
	lbl_sub.text = "Offline"
	lobby.profile_status_label = lbl_sub
	lbl_sub.add_theme_color_override("font_color", Color("#555555"))
	name_box.add_child(lbl_sub)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	
	var stats_hbox := HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 30)
	stats_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(stats_hbox)
	
	for s in [["Friends", "0"], ["Followers", "0"], ["Following", "0"]]:
		var sb := VBoxContainer.new()
		sb.alignment = BoxContainer.ALIGNMENT_CENTER
		var l1 = Label.new()
		l1.text = s[0]
		l1.add_theme_color_override("font_color", Color("#888888"))
		l1.add_theme_font_size_override("font_size", 12)
		var l2 = Label.new()
		l2.text = s[1]
		l2.add_theme_color_override("font_color", Color("#00A2FF"))
		l2.add_theme_font_size_override("font_size", 16)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		match str(s[0]):
			"Friends":
				lobby.profile_friends_count_label = l2
			"Followers":
				lobby.profile_followers_count_label = l2
			"Following":
				lobby.profile_following_count_label = l2
		sb.add_child(l1)
		sb.add_child(l2)
		stats_hbox.add_child(sb)
	
	# About / Creations Tabs
	var tab_row := HBoxContainer.new()
	tab_row.custom_minimum_size.y = 40
	v_head.add_child(tab_row)
	
	var btn_about := Button.new()
	btn_about.text = "About"
	btn_about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color.WHITE
	b_style.border_width_bottom = 2
	b_style.border_color = Color("#00A2FF")
	btn_about.add_theme_stylebox_override("normal", b_style)
	btn_about.add_theme_color_override("font_color", Color("#333333"))
	tab_row.add_child(btn_about)
	
	var btn_creations := Button.new()
	btn_creations.text = "Creations"
	btn_creations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b_style2 := StyleBoxFlat.new()
	b_style2.bg_color = Color.WHITE
	b_style2.border_width_bottom = 2
	b_style2.border_width_left = 1
	b_style2.border_color = Color("#DDDDDD")
	btn_creations.add_theme_stylebox_override("normal", b_style2)
	btn_creations.add_theme_color_override("font_color", Color("#333333"))
	tab_row.add_child(btn_creations)
	
	# Content Containers
	var about_content := VBoxContainer.new()
	about_content.add_theme_constant_override("separation", 20)
	about_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(about_content)
	
	var creations_content := VBoxContainer.new()
	creations_content.add_theme_constant_override("separation", 20)
	creations_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creations_content.visible = false
	root.add_child(creations_content)
	
	var creations_lbl := Label.new()
	creations_lbl.text = "This user does not have any creations."
	creations_lbl.add_theme_color_override("font_color", Color("#888888"))
	creations_content.add_child(creations_lbl)
	
	btn_about.pressed.connect(func():
		about_content.visible = true
		creations_content.visible = false
		b_style.border_color = Color("#00A2FF")
		b_style2.border_color = Color("#DDDDDD")
	)
	
	btn_creations.pressed.connect(func():
		about_content.visible = false
		creations_content.visible = true
		b_style2.border_color = Color("#00A2FF")
		b_style.border_color = Color("#DDDDDD")
	)
	
	# --- About Section ---
	var about_lbl := Label.new()
	about_lbl.text = "About"
	about_lbl.add_theme_color_override("font_color", Color("#333333"))
	about_lbl.add_theme_font_size_override("font_size", 18)
	about_content.add_child(about_lbl)
	
	var ab_panel := PanelContainer.new()
	var a_style := StyleBoxFlat.new()
	a_style.bg_color = Color.WHITE
	a_style.border_width_top = 1; a_style.border_color = Color("#CCCCCC")
	a_style.content_margin_top = 10; a_style.content_margin_bottom = 10
	ab_panel.add_theme_stylebox_override("panel", a_style)
	about_content.add_child(ab_panel)
	
	var ab_box := VBoxContainer.new()
	ab_panel.add_child(ab_box)
	
	var ab_line := ColorRect.new()
	ab_line.custom_minimum_size.y = 1
	ab_line.color = Color("#EEEEEE")
	ab_box.add_child(ab_line)
	
	var ab_report := Label.new()
	ab_report.text = "Report Abuse"
	ab_report.add_theme_color_override("font_color", Color("#CC4444"))
	ab_report.add_theme_font_size_override("font_size", 10)
	ab_report.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ab_box.add_child(ab_report)
	
	# --- Currently Wearing Section ---
	var cw_lbl := Label.new()
	cw_lbl.text = "Currently Wearing"
	cw_lbl.add_theme_color_override("font_color", Color("#333333"))
	cw_lbl.add_theme_font_size_override("font_size", 18)
	about_content.add_child(cw_lbl)
	
	var cw_panel := PanelContainer.new()
	var cw_style := StyleBoxFlat.new()
	cw_style.bg_color = Color.WHITE
	cw_style.border_width_top = 1; cw_style.border_width_left = 1
	cw_style.border_width_right = 1; cw_style.border_width_bottom = 1
	cw_style.border_color = Color("#DDDDDD")
	cw_panel.add_theme_stylebox_override("panel", cw_style)
	about_content.add_child(cw_panel)
	
	var cw_hbox := HBoxContainer.new()
	cw_hbox.add_theme_constant_override("separation", 0)
	cw_panel.add_child(cw_hbox)
	
	var cw_left := SubViewportContainer.new()
	cw_left.stretch = true
	cw_left.custom_minimum_size = Vector2(300, 250)
	cw_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cw_hbox.add_child(cw_left)
	
	var sub_vp2 := SubViewport.new()
	sub_vp2.transparent_bg = true
	sub_vp2.own_world_3d = true
	cw_left.add_child(sub_vp2)
	
	var cam2 := Camera3D.new()
	cam2.fov = 28.0
	var cam2_pos := Vector3(0.0, 3.3, 6.9)
	var cam2_target := Vector3(0.0, 3.3, 0.0)
	cam2.transform = Transform3D(Basis.looking_at(cam2_target - cam2_pos, Vector3.UP), cam2_pos)
	sub_vp2.add_child(cam2)
	
	var dr_light2 := DirectionalLight3D.new()
	dr_light2.transform = Transform3D(Basis.looking_at(Vector3(0, 3.0, 0) - Vector3(2.0, 7.0, 3.0), Vector3.UP), Vector3(2.0, 7.0, 3.0))
	sub_vp2.add_child(dr_light2)
	
	if player_res:
		var p_avatar2 = player_res.instantiate()
		p_avatar2.name = "ProfilePreviewPlayer"
		p_avatar2.set("is_ui_preview", true)
		p_avatar2.set("use_local_avatar_fallback", false)
		p_avatar2.set("render_avatar_clothing_decals", true)
		p_avatar2.position.y = -0.12
		if p_avatar2.get_node_or_null("Visuals/NameLabel"):
			p_avatar2.get_node("Visuals/NameLabel").visible = false
		sub_vp2.add_child(p_avatar2)
		lobby.profile_preview_player = p_avatar2
		
		p_avatar2.head_color = GameState.head_color; p_avatar2.torso_color = GameState.torso_color
		p_avatar2.left_arm_color = GameState.left_arm_color; p_avatar2.right_arm_color = GameState.right_arm_color
		p_avatar2.left_leg_color = GameState.left_leg_color; p_avatar2.right_leg_color = GameState.right_leg_color
		_apply_current_session_avatar_to_preview(p_avatar2)
	
	var cw_right := Panel.new()
	var er_style := StyleBoxFlat.new()
	er_style.bg_color = Color("#FAFAFA")
	er_style.border_color = Color("#DDDDDD")
	er_style.border_width_left = 1
	cw_right.add_theme_stylebox_override("panel", er_style)
	cw_right.custom_minimum_size = Vector2(300, 250)
	cw_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cw_hbox.add_child(cw_right)
	
	var cw_items_scroll := ScrollContainer.new()
	cw_items_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	cw_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cw_items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cw_right.add_child(cw_items_scroll)

	var cw_items_grid := GridContainer.new()
	cw_items_grid.columns = 2
	cw_items_grid.add_theme_constant_override("h_separation", 8)
	cw_items_grid.add_theme_constant_override("v_separation", 8)
	cw_items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cw_items_scroll.add_child(cw_items_grid)
	lobby.profile_wearing_items_container = cw_items_grid

	var cw_no_items := Label.new()
	cw_no_items.text = "No items to display"
	cw_no_items.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cw_no_items.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cw_no_items.add_theme_color_override("font_color", Color("#888888"))
	cw_no_items.add_theme_font_size_override("font_size", 14)
	cw_no_items.set_anchors_preset(Control.PRESET_FULL_RECT)
	cw_right.add_child(cw_no_items)
	lobby.profile_wearing_empty_label = cw_no_items
	
	# --- Statistics Section ---
	var st_lbl := Label.new()
	st_lbl.text = "Statistics"
	st_lbl.add_theme_color_override("font_color", Color("#333333"))
	st_lbl.add_theme_font_size_override("font_size", 18)
	about_content.add_child(st_lbl)
	
	var st_panel := PanelContainer.new()
	var st_style := StyleBoxFlat.new()
	st_style.bg_color = Color.WHITE
	st_style.border_width_top = 1; st_style.border_width_left = 1
	st_style.border_width_right = 1; st_style.border_width_bottom = 1
	st_style.border_color = Color("#DDDDDD")
	st_panel.add_theme_stylebox_override("panel", st_style)
	about_content.add_child(st_panel)
	
	var st_m := MarginContainer.new()
	st_m.add_theme_constant_override("margin_top", 16)
	st_m.add_theme_constant_override("margin_bottom", 16)
	st_panel.add_child(st_m)
	
	var st_hbox := HBoxContainer.new()
	st_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	st_hbox.add_theme_constant_override("separation", 100)
	st_m.add_child(st_hbox)
	
	var join_lbl = Label.new()
	lobby.join_date_label = join_lbl
	for s in [["Join Date", "04/17/2026", join_lbl], ["Place Visits", "0", null], ["Forum Posts", "0", null]]:
		var sb := VBoxContainer.new()
		sb.alignment = BoxContainer.ALIGNMENT_CENTER
		var l1 = Label.new()
		l1.text = s[0]
		l1.add_theme_color_override("font_color", Color("#888888"))
		l1.add_theme_font_size_override("font_size", 12)
		var l2 = s[2] if s[2] != null else Label.new()
		if s[2] == null: l2.text = s[1]
		l2.add_theme_color_override("font_color", Color("#111111"))
		l2.add_theme_font_size_override("font_size", 14)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sb.add_child(l1)
		sb.add_child(l2)
		st_hbox.add_child(sb)

static func _apply_current_session_avatar_to_preview(preview: Node) -> void:
	if preview == null:
		return
	var avatar_data: Dictionary = UserSession.avatar_data if UserSession.avatar_data is Dictionary else {}
	preview.set("face_texture_path", str(avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)))
	preview.set("chest_badge_texture_path", str(avatar_data.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)))
	preview.set("shirt_texture_path", str(avatar_data.get("shirt_texture_path", "")))
	preview.set("pants_texture_path", str(avatar_data.get("pants_texture_path", "")))
	var equipped_payloads: Array = avatar_data.get("equipped_avatar_item_payloads", []) if avatar_data.get("equipped_avatar_item_payloads", []) is Array else []
	preview.set("equipped_avatar_items", equipped_payloads.duplicate(true))
	if preview.has_method("force_avatar_visual_refresh"):
		preview.call_deferred("force_avatar_visual_refresh")
	elif preview.has_method("_apply_avatar_visuals_if_needed"):
		preview.call_deferred("_apply_avatar_visuals_if_needed")
