class_name ProfileBuilder
extends RefCounted

const ORBIT := preload("res://scripts/ui/profile_preview_orbit.gd")
const CACHE_ROOT := "user://cache/public_profiles/"

static func cached_profile(user_id: String) -> Dictionary:
	if user_id.is_empty(): return {}
	var path := CACHE_ROOT.path_join(user_id.sha256_text() + ".json")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and str(data.get("id", "")) == user_id else {}

static func remember(profile: Dictionary) -> void:
	var user_id := str(profile.get("id", "")).strip_edges()
	if user_id.is_empty(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_ROOT))
	var file := FileAccess.open(CACHE_ROOT.path_join(user_id.sha256_text() + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(profile))

static func _panel() -> PanelContainer:
	var result := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color("#d2d2d2")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	result.add_theme_stylebox_override("panel", style)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

static func _label(text: String, font_size := 14) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color("#333333"))
	return result

static func build(lobby: Control) -> void:
	var tabs := lobby.get_node_or_null("%MainTabs")
	var view := tabs.get_node_or_null("ProfileView") as ScrollContainer if tabs != null else null
	if view == null: return
	for child in view.get_children():
		view.remove_child(child)
		child.queue_free()
	# DISABLED forwards the two-column content minimum into the tab container,
	# preventing the narrow layout from ever receiving the actual phone width.
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var margin := MarginContainer.new()
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(key, 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(margin)
	var root := VBoxContainer.new()
	root.name = "ProfileContent"
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := _panel()
	root.add_child(header)
	var head_box := VBoxContainer.new()
	header.add_child(head_box)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 16)
	head_box.add_child(identity)
	var avatar := Panel.new()
	avatar.name = "ProfileHeaderAvatar"
	avatar.custom_minimum_size = Vector2(100, 100)
	identity.add_child(avatar)
	lobby.profile_header_avatar_holder = avatar
	var identity_text := VBoxContainer.new()
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_child(identity_text)
	lobby.profile_username_label = _label("Player", 24)
	lobby.profile_username_label.clip_text = true
	lobby.profile_username_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_text.add_child(lobby.profile_username_label)
	lobby.profile_status_label = _label("Offline")
	lobby.profile_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(lobby.profile_status_label)
	lobby.join_date_label = _label("Join Date: —", 12)
	lobby.join_date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(lobby.join_date_label)
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 22)
	head_box.add_child(stats)
	for key in ["Friends", "Followers", "Following", "Modes visited"]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.add_child(_label(key, 12))
		var count := _label("—", 18)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(count)
		stats.add_child(column)
		match key:
			"Friends": lobby.profile_friends_count_label = count
			"Followers": lobby.profile_followers_count_label = count
			"Following": lobby.profile_following_count_label = count
			"Modes visited":
				lobby.profile_visited_count_label = count
				count.tooltip_text = "Distinct experiences successfully joined since this update. Older versions did not save this account statistic."
	var tab_row := HBoxContainer.new()
	root.add_child(tab_row)
	var about_button := Button.new()
	about_button.name = "ProfileAboutButton"
	about_button.text = "About"
	about_button.custom_minimum_size.y = 44
	about_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(about_button)
	var creations_button := Button.new()
	creations_button.name = "ProfileCreationsButton"
	creations_button.text = "Creations"
	creations_button.custom_minimum_size.y = 44
	creations_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(creations_button)
	var about := VBoxContainer.new()
	about.name = "ProfileAbout"
	about.add_theme_constant_override("separation", 14)
	root.add_child(about)
	var creations := VBoxContainer.new()
	creations.name = "ProfileCreations"
	creations.visible = false
	root.add_child(creations)
	var creations_note := _label("Open Creations to see experiences made by this player.")
	creations_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creations.add_child(creations_note)
	lobby.profile_creations_container = creations
	about_button.pressed.connect(func():
		about.show()
		creations.hide()
	)
	creations_button.pressed.connect(func():
		about.hide()
		creations.show()
		lobby._refresh_profile_games_section()
	)
	var bio_panel := _panel()
	about.add_child(bio_panel)
	var bio_box := VBoxContainer.new()
	bio_box.add_theme_constant_override("separation", 8)
	bio_panel.add_child(bio_box)
	var bio_header := HBoxContainer.new()
	bio_box.add_child(bio_header)
	var title := _label("About", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bio_header.add_child(title)
	var edit := Button.new()
	edit.name = "EditDescription"
	edit.text = "Edit description"
	edit.custom_minimum_size.y = 44
	bio_header.add_child(edit)
	lobby.profile_about_edit_button = edit
	lobby.profile_about_label = _label("This player has not written a description yet.")
	lobby.profile_about_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio_box.add_child(lobby.profile_about_label)
	var editor := VBoxContainer.new()
	editor.name = "DescriptionEditor"
	editor.visible = false
	bio_box.add_child(editor)
	var text := TextEdit.new()
	text.custom_minimum_size = Vector2(0, 132)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.placeholder_text = "Tell players about yourself (up to 1000 characters)."
	editor.add_child(text)
	var status := _label("0 / 1000", 12)
	editor.add_child(status)
	var actions := HBoxContainer.new()
	editor.add_child(actions)
	var save := Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(100, 44)
	actions.add_child(save)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(100, 44)
	actions.add_child(cancel)
	lobby.profile_about_editor = editor
	lobby.profile_about_input = text
	lobby.profile_about_status = status
	lobby.profile_about_save_button = save
	edit.pressed.connect(func():
		text.text = str(lobby.selected_profile_snapshot.get("bio", ""))
		status.text = "%d / 1000" % text.text.length()
		editor.show()
		lobby.profile_about_label.hide()
		edit.hide()
		text.grab_focus()
	)
	cancel.pressed.connect(func(): lobby._close_profile_about_editor())
	text.text_changed.connect(func():
		status.text = "%d / 1000" % text.text.length()
		save.disabled = text.text.length() > 1000 or bool(lobby.get("_profile_about_save_in_flight"))
	)
	save.pressed.connect(func(): lobby._save_profile_about_async())
	about.add_child(_label("Currently Wearing", 18))
	var wearing := _panel()
	about.add_child(wearing)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	wearing.add_child(row)
	var preview_column := VBoxContainer.new()
	preview_column.custom_minimum_size = Vector2(260, 0)
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(preview_column)
	var preview := SubViewportContainer.new()
	preview.name = "ProfileAvatarViewport"
	preview.stretch = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = Vector2(0, 300)
	preview_column.add_child(preview)
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 300)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	preview.add_child(vp)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.2
	camera.position = Vector3(0, 3.2, 10)
	camera.current = true
	vp.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -35, 0)
	vp.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 145, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
	player.name = "ProfilePreviewPlayer"
	player.set("is_ui_preview", true)
	player.set("use_local_avatar_fallback", false)
	player.set("render_avatar_clothing_decals", true)
	player.set("render_avatar_visual_decals", true)
	vp.add_child(player)
	var name_label := player.get_node_or_null("Visuals/NameLabel") as Node3D
	if name_label != null: name_label.hide()
	lobby.profile_preview_player = player
	var orbit := ORBIT.new()
	orbit.name = "ProfileAvatarOrbit"
	preview.add_child(orbit)
	orbit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orbit.set_player(player)
	lobby.profile_preview_orbit = orbit
	var orbit_buttons := HBoxContainer.new()
	orbit_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_column.add_child(orbit_buttons)
	for direction in [-1, 1]:
		var button := Button.new()
		button.text = "‹" if direction < 0 else "›"
		button.tooltip_text = "Rotate character"
		button.custom_minimum_size = Vector2(64, 44)
		button.pressed.connect(func(): orbit.turn(float(direction) * PI / 4.0))
		orbit_buttons.add_child(button)
	var items_column := VBoxContainer.new()
	items_column.custom_minimum_size = Vector2(260, 0)
	items_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(items_column)
	var empty := _label("No items to display")
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items_column.add_child(empty)
	lobby.profile_wearing_empty_label = empty
	var items := GridContainer.new()
	items.name = "ProfileWearingItems"
	items.columns = 2
	items.add_theme_constant_override("h_separation", 8)
	items.add_theme_constant_override("v_separation", 8)
	items_column.add_child(items)
	lobby.profile_wearing_items_container = items
	view.resized.connect(func(): _layout(view, row, preview_column, items_column, items))
	items_column.resized.connect(func(): _layout(view, row, preview_column, items_column, items))
	_layout(view, row, preview_column, items_column, items)

static func _layout(view: Control, row: BoxContainer, preview: Control, items_column: Control, items: GridContainer) -> void:
	var available := view.size.x - 56
	row.vertical = available < 650
	preview.custom_minimum_size.x = minf(260, maxf(available, 0))
	items_column.custom_minimum_size.x = minf(260, maxf(available, 0))
	# Derive columns from the available viewport width, never from the grid's
	# previous minimum: otherwise a wide desktop grid holds the phone layout open.
	var item_width := available if row.vertical else maxf((available - 16) * 0.5, 0)
	items.columns = maxi(1, int((item_width + 8) / 142.0))
