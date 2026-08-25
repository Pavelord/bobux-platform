class_name GamesBuilder
extends RefCounted


static func build(lobby) -> void:
	var tabs = lobby.get_node_or_null("%MainTabs")
	if not tabs:
		return

	var games_view = tabs.get_node_or_null("GamesView")
	if not games_view:
		return
	var build_token: int = Time.get_ticks_msec()
	games_view.set_meta("games_build_token", build_token)

	for child in games_view.get_children():
		child.queue_free()

	var scroll_host: ScrollContainer = games_view as ScrollContainer
	if scroll_host == null:
		scroll_host = ScrollContainer.new()
		scroll_host.set_anchors_preset(Control.PRESET_FULL_RECT)
		games_view.add_child(scroll_host)
	scroll_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_host.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var hero := Panel.new()
	hero.custom_minimum_size = Vector2(0, 118)
	hero.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(hero)

	var hero_margin := MarginContainer.new()
	hero_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero_margin.add_theme_constant_override("margin_left", 18)
	hero_margin.add_theme_constant_override("margin_top", 18)
	hero_margin.add_theme_constant_override("margin_right", 18)
	hero_margin.add_theme_constant_override("margin_bottom", 18)
	hero.add_child(hero_margin)

	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 18)
	hero_margin.add_child(hero_row)

	var hero_info := VBoxContainer.new()
	hero_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_info.add_theme_constant_override("separation", 8)
	hero_row.add_child(hero_info)

	var title := Label.new()
	title.text = "Games"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	hero_info.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Live experiences, published maps, and fast re-entry into the most active rooms."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_info.add_child(subtitle)

	var summary_label := Label.new()
	summary_label.text = "Loading games..."
	summary_label.add_theme_font_size_override("font_size", 12)
	summary_label.add_theme_color_override("font_color", Color(0.12, 0.6, 0.88, 1))
	hero_info.add_child(summary_label)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(150, 0)
	actions.add_theme_constant_override("separation", 10)
	hero_row.add_child(actions)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(0, 40)
	refresh_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
	refresh_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	refresh_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	refresh_btn.add_theme_color_override("font_color", Color.WHITE)
	refresh_btn.pressed.connect(func(): build(lobby))
	actions.add_child(refresh_btn)

	var live_parts := _create_section(root, "Live Right Now", "Rooms with active players you can jump into immediately.", 320)
	var creator_parts := _create_section(root, "From Bobux Creators", "Experiences from pavelord and the Bobux team.", 320)
	var all_parts := _create_section(root, "All Experiences", "Published server experiences from Bobux.", 520)

	_populate_async(lobby, games_view, build_token, summary_label, live_parts, all_parts, creator_parts)


static func _populate_async(lobby, games_view: Control, build_token: int, summary_label: Label, live_parts: Dictionary, all_parts: Dictionary, creator_parts: Dictionary) -> void:
	var live_status: Label = live_parts.get("status_label", null)
	var live_grid: GridContainer = live_parts.get("grid", null)
	var all_status: Label = all_parts.get("status_label", null)
	var all_grid: GridContainer = all_parts.get("grid", null)
	var creator_status: Label = creator_parts.get("status_label", null)
	var creator_grid: GridContainer = creator_parts.get("grid", null)
	if live_status:
		live_status.text = "Loading live rooms..."
	if all_status:
		all_status.text = "Loading experiences..."
	if creator_status:
		creator_status.text = "Loading creator picks..."

	var entries: Array = await lobby._build_discover_entries()
	if not is_instance_valid(lobby) or not is_instance_valid(games_view):
		return
	if int(games_view.get_meta("games_build_token", -1)) != build_token:
		return
	if live_grid == null or all_grid == null or creator_grid == null:
		return

	_clear_children(live_grid)
	_clear_children(all_grid)
	_clear_children(creator_grid)

	var live_entries: Array = []
	var creator_entries: Array = []
	var all_entries: Array = lobby._get_all_home_entries(entries) if lobby.has_method("_get_all_home_entries") else entries.duplicate(true)
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		if int(entry.get("active_players", 0)) > 0:
			live_entries.append(entry)
		if lobby._is_bobux_creator_entry(entry):
			creator_entries.append(entry)

	if summary_label:
		summary_label.text = "%d total experience(s), %d live right now" % [entries.size(), live_entries.size()]

	if live_entries.is_empty():
		_add_placeholder(live_grid, "No live rooms right now. Create or publish a map to populate this list.")
		if live_status:
			live_status.text = "No live rooms right now."
	else:
		live_grid.columns = _resolve_grid_columns(lobby)
		if live_status:
			live_status.text = "%d live experience(s)" % live_entries.size()
		await _add_cards_progressively(lobby, live_grid, live_entries, true)

	if creator_entries.is_empty():
		_add_placeholder(creator_grid, "Creator picks from pavelord will appear here.")
		if creator_status:
			creator_status.text = "No creator experiences published yet."
	else:
		creator_grid.columns = _resolve_grid_columns(lobby)
		if creator_status:
			creator_status.text = "%d creator experience(s)" % creator_entries.size()
		await _add_cards_progressively(lobby, creator_grid, creator_entries, false, true)

	if all_entries.is_empty():
		_add_placeholder(all_grid, "No discoverable games yet.")
		if all_status:
			all_status.text = "No experiences available."
	else:
		all_grid.columns = _resolve_grid_columns(lobby)
		if all_status:
			all_status.text = "%d experience(s) available" % all_entries.size()
		await _add_cards_progressively(lobby, all_grid, all_entries, false)


static func _add_cards_progressively(lobby, grid: GridContainer, entries: Array, force_active_players: bool, compact_width: bool = false) -> void:
	var added_count: int = 0
	for entry_variant in entries:
		if not is_instance_valid(lobby) or not is_instance_valid(grid):
			return
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			var show_active_players := force_active_players or int(entry.get("active_players", 0)) > 0
			grid.add_child(lobby._create_smart_play_card(entry, show_active_players, compact_width))
			added_count += 1
			if added_count % 2 == 0:
				await lobby.get_tree().process_frame


static func _resolve_grid_columns(lobby) -> int:
	var width: float = lobby.get_viewport_rect().size.x if lobby is Control else 1280.0
	var mobile_runtime: Node = lobby.get_node_or_null("/root/MobileRuntime") if lobby != null else null
	var is_mobile: bool = mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))
	if is_mobile:
		return 2 if width < 760.0 else 3
	return 4 if width >= 1280.0 else 3


static func _create_section(parent: VBoxContainer, title_text: String, subtitle_text: String, min_height: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, min_height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(root)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var status_label := Label.new()
	status_label.text = "Loading..."
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.48, 0.49, 0.53, 1))
	root.add_child(status_label)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	return {
		"panel": panel,
		"status_label": status_label,
		"grid": grid
	}


static func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.89, 0.9, 0.93, 1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	return style


static func _make_primary_button_style(color_value: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style


static func _add_placeholder(container: GridContainer, text: String) -> void:
	container.columns = 1
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 56)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	container.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(label)


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
