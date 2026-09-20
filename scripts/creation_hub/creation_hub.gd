extends Control

signal create_game_requested
signal create_model_requested(source_path: String)
signal create_avatar_item_requested
signal catalog_requested
signal home_requested
signal legacy_editor_requested

const PAGE_MIN_SIZE := Vector2(760, 520)
const ICON_ROOT := "res://assets/studio/icons/lucide"
const STUDIO_GUIDE_DATA = preload("res://scripts/creation_hub/studio_guide_data.gd")
const COLOR_BACKGROUND := Color(0.055, 0.061, 0.075, 1)
const COLOR_TOP_BAR := Color(0.075, 0.083, 0.102, 1)
const COLOR_SURFACE := Color(0.105, 0.116, 0.14, 1)
const COLOR_SURFACE_HOVER := Color(0.135, 0.149, 0.178, 1)
const COLOR_BORDER := Color(0.22, 0.235, 0.27, 1)
const COLOR_TEXT := Color(0.96, 0.965, 0.98, 1)
const COLOR_MUTED := Color(0.66, 0.69, 0.74, 1)
const COLOR_BLUE := Color(0.12, 0.54, 0.92, 1)
const COLOR_GREEN := Color(0.20, 0.72, 0.43, 1)

var _content_host: Control = null
var _nav_buttons: Dictionary = {}
var _current_page: String = "dashboard"
var _compact_layout: bool = false
var _guide_title_label: Label = null
var _guide_text: RichTextLabel = null
var _guide_select: OptionButton = null
var _guide_topic_buttons: Array[Button] = []
var _guide_topic_index: int = 0
var _model_source_dialog: ConfirmationDialog = null
var _model_file_dialog: FileDialog = null


func _ready() -> void:
	custom_minimum_size = PAGE_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_compact_layout = get_viewport_rect().size.x < 920.0
	_build_shell()
	_show_dashboard()
	resized.connect(_on_hub_resized)
	_play_intro()


func _build_shell() -> void:
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", _flat_style(COLOR_BACKGROUND))
	add_child(background)

	var shell := VBoxContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)
	shell.add_child(_create_top_bar())

	_content_host = Control.new()
	_content_host.name = "CreatorPageHost"
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_content_host)


func _create_top_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 58)
	bar.add_theme_stylebox_override("panel", _bordered_style(COLOR_TOP_BAR, COLOR_BORDER, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var brand := Button.new()
	brand.text = "BOBUX  CREATOR"
	brand.flat = true
	brand.focus_mode = Control.FOCUS_NONE
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", COLOR_TEXT)
	brand.pressed.connect(_show_dashboard)
	row.add_child(brand)

	var divider := VSeparator.new()
	divider.custom_minimum_size = Vector2(10, 0)
	row.add_child(divider)

	_add_top_navigation_button(row, "Dashboard", "dashboard", Callable(self, "_show_dashboard"))
	_add_top_navigation_button(row, "Learn", "guide", Callable(self, "_show_guide"))

	var studio_button := Button.new()
	studio_button.text = "Open Studio"
	studio_button.custom_minimum_size = Vector2(112, 34)
	studio_button.add_theme_stylebox_override("normal", _button_style(COLOR_BLUE, COLOR_BLUE.darkened(0.12)))
	studio_button.add_theme_stylebox_override("hover", _button_style(COLOR_BLUE.lightened(0.08), COLOR_BLUE))
	studio_button.add_theme_color_override("font_color", Color.WHITE)
	studio_button.pressed.connect(_emit_create_game)
	row.add_child(studio_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var creations_button := Button.new()
	creations_button.text = "My Creations"
	creations_button.flat = true
	creations_button.add_theme_color_override("font_color", COLOR_MUTED)
	creations_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	creations_button.pressed.connect(_emit_catalog)
	row.add_child(creations_button)

	var close_button := Button.new()
	close_button.text = "Back to Bobux"
	close_button.custom_minimum_size = Vector2(116, 34)
	close_button.add_theme_stylebox_override("normal", _button_style(COLOR_SURFACE, COLOR_BORDER))
	close_button.add_theme_stylebox_override("hover", _button_style(COLOR_SURFACE_HOVER, COLOR_BLUE))
	close_button.add_theme_color_override("font_color", COLOR_TEXT)
	close_button.pressed.connect(func(): home_requested.emit())
	row.add_child(close_button)

	return bar


func _add_top_navigation_button(parent: Container, title: String, page_key: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.pressed.connect(callback)
	parent.add_child(button)
	_nav_buttons[page_key] = button


func _show_dashboard() -> void:
	_current_page = "dashboard"
	_clear_content_host()
	_update_top_navigation()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	_content_host.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18 if _compact_layout else 38)
	margin.add_theme_constant_override("margin_top", 22 if _compact_layout else 30)
	margin.add_theme_constant_override("margin_right", 18 if _compact_layout else 38)
	margin.add_theme_constant_override("margin_bottom", 34)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var heading := Label.new()
	heading.text = "Creator Dashboard"
	heading.add_theme_font_size_override("font_size", 30 if _compact_layout else 36)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Create experiences, reusable models and avatar items from one workspace."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	root.add_child(_section_heading("Start creating"))

	var action_grid := GridContainer.new()
	action_grid.columns = 1 if _compact_layout else 2
	action_grid.add_theme_constant_override("h_separation", 14)
	action_grid.add_theme_constant_override("v_separation", 14)
	action_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(action_grid)
	action_grid.add_child(_create_action_card(
		"Open Bobux Studio",
		"Build worlds, scripts, GUI, models, avatar items, terrain and audio in one workspace.",
		"play.svg",
		COLOR_BLUE,
		Callable(self, "_emit_create_game")
	))
	action_grid.add_child(_create_action_card(
		"Create Model",
		"Start an empty reusable model or load a 3D file, preserve its colors and publish it to Toolbox.",
		"boxes.svg",
		Color(0.72, 0.43, 0.96, 1),
		Callable(self, "_emit_create_model")
	))
	action_grid.add_child(_create_action_card(
		"Create Avatar Item",
		"Attach a published model to a character slot, position it precisely and generate its preview.",
		"person-standing.svg",
		Color(0.95, 0.56, 0.18, 1),
		Callable(self, "_emit_create_avatar_item")
	))
	action_grid.add_child(_create_action_card(
		"My Creations",
		"Manage Studio projects, models, avatar items, visibility and generated previews.",
		"briefcase-business.svg",
		COLOR_GREEN,
		Callable(self, "_emit_catalog")
	))

	root.add_child(_section_heading("Creation workflow"))
	var workflow := GridContainer.new()
	workflow.columns = 1 if _compact_layout else 3
	workflow.add_theme_constant_override("h_separation", 14)
	workflow.add_theme_constant_override("v_separation", 12)
	workflow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(workflow)
	workflow.add_child(_create_workflow_step("1", "Build", "Create the world, scripts, UI and assets in Studio."))
	workflow.add_child(_create_workflow_step("2", "Test", "Use Play and Stop, read Output and verify mobile controls."))
	workflow.add_child(_create_workflow_step("3", "Publish", "Upload through Bobux Cloud so the server remains authoritative."))

	var learn_panel := PanelContainer.new()
	learn_panel.custom_minimum_size = Vector2(0, 112)
	learn_panel.add_theme_stylebox_override("panel", _bordered_style(Color(0.085, 0.12, 0.17, 1), Color(0.16, 0.38, 0.62, 1), 8))
	root.add_child(learn_panel)
	var learn_margin := MarginContainer.new()
	learn_margin.add_theme_constant_override("margin_left", 18)
	learn_margin.add_theme_constant_override("margin_top", 15)
	learn_margin.add_theme_constant_override("margin_right", 18)
	learn_margin.add_theme_constant_override("margin_bottom", 15)
	learn_panel.add_child(learn_margin)
	var learn_row := HBoxContainer.new()
	learn_row.add_theme_constant_override("separation", 18)
	learn_margin.add_child(learn_row)
	var learn_copy := VBoxContainer.new()
	learn_copy.add_theme_constant_override("separation", 4)
	learn_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	learn_row.add_child(learn_copy)
	var learn_title := Label.new()
	learn_title.text = "New to Bobux Studio?"
	learn_title.add_theme_font_size_override("font_size", 20)
	learn_title.add_theme_color_override("font_color", COLOR_TEXT)
	learn_copy.add_child(learn_title)
	var learn_desc := Label.new()
	learn_desc.text = "The built-in guide explains every important editor workflow step by step."
	learn_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	learn_desc.add_theme_color_override("font_color", COLOR_MUTED)
	learn_copy.add_child(learn_desc)
	var learn_button := Button.new()
	learn_button.text = "Open Studio Guide"
	learn_button.custom_minimum_size = Vector2(158, 38)
	learn_button.add_theme_stylebox_override("normal", _button_style(COLOR_BLUE, COLOR_BLUE.darkened(0.1)))
	learn_button.add_theme_stylebox_override("hover", _button_style(COLOR_BLUE.lightened(0.08), COLOR_BLUE))
	learn_button.add_theme_color_override("font_color", Color.WHITE)
	learn_button.pressed.connect(_show_guide)
	learn_row.add_child(learn_button)

	var authority_note := Label.new()
	authority_note.text = "Publishing rule: local files are drafts. Public experiences and catalog items are saved through the server and Bobux Cloud."
	authority_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	authority_note.add_theme_font_size_override("font_size", 12)
	authority_note.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64, 1))
	root.add_child(authority_note)

	var legacy_row := HBoxContainer.new()
	legacy_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(legacy_row)
	var legacy_button := Button.new()
	legacy_button.text = "Legacy editor"
	legacy_button.tooltip_text = "Open the retired editor for old projects"
	legacy_button.flat = true
	legacy_button.focus_mode = Control.FOCUS_NONE
	legacy_button.add_theme_font_size_override("font_size", 11)
	legacy_button.add_theme_color_override("font_color", Color(0.43, 0.45, 0.50, 1))
	legacy_button.add_theme_color_override("font_hover_color", COLOR_MUTED)
	legacy_button.pressed.connect(_emit_legacy_editor)
	legacy_row.add_child(legacy_button)


func _create_action_card(title: String, description: String, icon_name: String, accent: Color, callback: Callable) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(188, 156)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.text = ""
	card.add_theme_stylebox_override("normal", _bordered_style(COLOR_SURFACE, COLOR_BORDER, 8))
	card.add_theme_stylebox_override("hover", _bordered_style(COLOR_SURFACE_HOVER, accent, 8))
	card.add_theme_stylebox_override("pressed", _bordered_style(COLOR_SURFACE_HOVER.darkened(0.06), accent, 8))
	card.pressed.connect(callback)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.texture = load(ICON_ROOT.path_join(icon_name)) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = accent
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(heading)
	var desc := Label.new()
	desc.text = description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = 3
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", COLOR_MUTED)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	var open_label := Label.new()
	open_label.text = "Open  >"
	open_label.add_theme_font_size_override("font_size", 12)
	open_label.add_theme_color_override("font_color", accent)
	open_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(open_label)
	return card


func _create_workflow_step(number: String, title: String, description: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 88)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _bordered_style(Color(0.08, 0.087, 0.105, 1), COLOR_BORDER, 6))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var badge := Label.new()
	badge.text = number
	badge.custom_minimum_size = Vector2(34, 34)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 17)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_stylebox_override("normal", _bordered_style(COLOR_BLUE, COLOR_BLUE, 6))
	row.add_child(badge)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	copy.add_child(heading)
	var desc := Label.new()
	desc.text = description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", COLOR_MUTED)
	copy.add_child(desc)
	return panel


func _show_guide() -> void:
	_current_page = "guide"
	_clear_content_host()
	_update_top_navigation()
	_guide_topic_buttons.clear()
	_guide_select = null

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14 if _compact_layout else 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 14 if _compact_layout else 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_content_host.add_child(margin)

	var layout: Container
	if _compact_layout:
		layout = VBoxContainer.new()
	else:
		layout = HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)

	var topics: Array = _get_guide_topics()
	if _compact_layout:
		_guide_select = OptionButton.new()
		_guide_select.custom_minimum_size = Vector2(0, 48)
		_guide_select.add_theme_font_size_override("font_size", 16)
		for topic_variant in topics:
			var topic: Dictionary = topic_variant
			_guide_select.add_item(str(topic.get("title", "Topic")))
		_guide_select.item_selected.connect(func(index: int): _set_guide_topic(index))
		layout.add_child(_guide_select)
	else:
		var topic_panel := PanelContainer.new()
		topic_panel.custom_minimum_size = Vector2(236, 0)
		topic_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		topic_panel.add_theme_stylebox_override("panel", _bordered_style(COLOR_SURFACE, COLOR_BORDER, 7))
		layout.add_child(topic_panel)
		var topic_scroll := ScrollContainer.new()
		topic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		topic_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		topic_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		topic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		topic_panel.add_child(topic_scroll)
		var topic_margin := MarginContainer.new()
		topic_margin.add_theme_constant_override("margin_left", 10)
		topic_margin.add_theme_constant_override("margin_top", 12)
		topic_margin.add_theme_constant_override("margin_right", 10)
		topic_margin.add_theme_constant_override("margin_bottom", 12)
		topic_scroll.add_child(topic_margin)
		var topic_list := VBoxContainer.new()
		topic_list.add_theme_constant_override("separation", 3)
		topic_margin.add_child(topic_list)
		var guide_label := Label.new()
		guide_label.text = "BOBUX STUDIO GUIDE"
		guide_label.add_theme_font_size_override("font_size", 13)
		guide_label.add_theme_color_override("font_color", COLOR_MUTED)
		topic_list.add_child(guide_label)
		for topic_index in range(topics.size()):
			var topic: Dictionary = topics[topic_index]
			var topic_button := Button.new()
			topic_button.text = str(topic.get("title", "Topic"))
			topic_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			topic_button.toggle_mode = true
			topic_button.focus_mode = Control.FOCUS_NONE
			topic_button.custom_minimum_size = Vector2(0, 32)
			topic_button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
			topic_button.add_theme_stylebox_override("hover", _button_style(COLOR_SURFACE_HOVER, COLOR_BORDER))
			topic_button.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.24, 0.39, 1), COLOR_BLUE))
			topic_button.add_theme_color_override("font_color", COLOR_MUTED)
			topic_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
			var selected_topic_index := topic_index
			topic_button.pressed.connect(func(): _set_guide_topic(selected_topic_index))
			topic_list.add_child(topic_button)
			_guide_topic_buttons.append(topic_button)

	var article_scroll := ScrollContainer.new()
	article_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	article_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	article_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(article_scroll)
	var article_margin := MarginContainer.new()
	article_margin.add_theme_constant_override("margin_left", 4 if _compact_layout else 18)
	article_margin.add_theme_constant_override("margin_top", 10 if _compact_layout else 4)
	article_margin.add_theme_constant_override("margin_right", 12)
	article_margin.add_theme_constant_override("margin_bottom", 30)
	article_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article_scroll.add_child(article_margin)
	var article := VBoxContainer.new()
	article.add_theme_constant_override("separation", 14)
	article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article_margin.add_child(article)
	_guide_title_label = Label.new()
	_guide_title_label.add_theme_font_size_override("font_size", 30 if _compact_layout else 34)
	_guide_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	_guide_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	article.add_child(_guide_title_label)
	_guide_text = RichTextLabel.new()
	_guide_text.bbcode_enabled = true
	_guide_text.fit_content = true
	_guide_text.scroll_active = false
	_guide_text.selection_enabled = true
	_guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_text.add_theme_font_size_override("normal_font_size", 18 if _compact_layout else 17)
	_guide_text.add_theme_font_size_override("bold_font_size", 18 if _compact_layout else 17)
	_guide_text.add_theme_font_size_override("mono_font_size", 17 if _compact_layout else 16)
	_guide_text.add_theme_color_override("default_color", Color(0.82, 0.84, 0.88, 1))
	_guide_text.add_theme_constant_override("line_separation", 9 if _compact_layout else 7)
	article.add_child(_guide_text)

	var quick_actions := HBoxContainer.new()
	quick_actions.add_theme_constant_override("separation", 10)
	article.add_child(quick_actions)
	var open_studio := Button.new()
	open_studio.text = "Open Studio"
	open_studio.custom_minimum_size = Vector2(130, 38)
	open_studio.add_theme_stylebox_override("normal", _button_style(COLOR_BLUE, COLOR_BLUE.darkened(0.1)))
	open_studio.add_theme_stylebox_override("hover", _button_style(COLOR_BLUE.lightened(0.08), COLOR_BLUE))
	open_studio.add_theme_color_override("font_color", Color.WHITE)
	open_studio.pressed.connect(_emit_create_game)
	quick_actions.add_child(open_studio)
	var dashboard_button := Button.new()
	dashboard_button.text = "Back to Dashboard"
	dashboard_button.custom_minimum_size = Vector2(154, 38)
	dashboard_button.add_theme_stylebox_override("normal", _button_style(COLOR_SURFACE, COLOR_BORDER))
	dashboard_button.add_theme_stylebox_override("hover", _button_style(COLOR_SURFACE_HOVER, COLOR_BLUE))
	dashboard_button.add_theme_color_override("font_color", COLOR_TEXT)
	dashboard_button.pressed.connect(_show_dashboard)
	quick_actions.add_child(dashboard_button)
	_set_guide_topic(_guide_topic_index)


func _set_guide_topic(index: int) -> void:
	var topics: Array = _get_guide_topics()
	if topics.is_empty():
		return
	_guide_topic_index = clampi(index, 0, topics.size() - 1)
	var topic: Dictionary = topics[_guide_topic_index]
	if _guide_title_label != null:
		_guide_title_label.text = str(topic.get("title", "Studio Guide"))
	if _guide_text != null:
		_guide_text.text = str(topic.get("body", ""))
	if _guide_select != null:
		_guide_select.select(_guide_topic_index)
	for button_index in range(_guide_topic_buttons.size()):
		_guide_topic_buttons[button_index].button_pressed = button_index == _guide_topic_index


func _get_guide_topics() -> Array:
	return STUDIO_GUIDE_DATA.get_topics()


func _get_legacy_guide_topics() -> Array:
	return [
		{
			"title": "1. Quick start",
			"body": "[b]Create your first playable experience[/b]\n\n1. Open [b]Develop > Experience[/b].\n2. Choose a template. Baseplate is best for learning; Obby already contains a route and checkpoints.\n3. Save immediately with [b]File > Save[/b]. Give the project a clear name.\n4. Add a Part, move it above the floor and press [b]Play[/b].\n5. Walk, jump and check collisions. Press [b]Stop[/b] to return to editing.\n6. Use [b]Publish[/b] only after the local test succeeds.\n\n[b]Important:[/b] Play runs a temporary test copy. Stop must restore the edit world. Published worlds are stored by the Bobux server, while local files remain drafts."
		},
		{
			"title": "2. Camera and navigation",
			"body": "[b]Viewport controls[/b]\n\n- Hold the right mouse button and move the mouse to look around.\n- Use W, A, S and D to fly through the editor viewport. Q and E move down and up.\n- Use the mouse wheel to change movement speed and zoom.\n- F focuses the camera on the selected object.\n- On a phone, drag an empty viewport area to rotate; use the editor joystick to move. UI panels consume touch input, so touching Explorer or Properties must not move the camera.\n\nIf the camera does not respond, stop Play mode and click an empty part of the viewport once."
		},
		{
			"title": "3. Parts and transforms",
			"body": "[b]Building blocks[/b]\n\nUse [b]Part[/b] to insert a Block, Sphere, Cylinder, Wedge, Corner Wedge, Spawn, Checkpoint, Ladder or Water block. Choose the shape from the arrow next to Part.\n\n[b]Select[/b] only selects. [b]Move[/b], [b]Scale[/b] and [b]Rotate[/b] activate their own gizmos. Drag the red, green and blue handles for X, Y and Z. Enable snapping for precise construction.\n\nSet [b]Anchored[/b] for static architecture. Disable it only for physics objects. [b]CanCollide[/b] controls physical collision. Use Ctrl+D to duplicate and Delete to remove. Group related parts into a Model so Explorer remains readable."
		},
		{
			"title": "4. Explorer and Properties",
			"body": "[b]Explorer is the structure of the experience[/b]\n\nWorkspace contains visible world objects. Lighting controls the environment. ReplicatedStorage is shared data. ServerScriptService contains server logic. StarterGui contains player interface. StarterPack contains tools. StarterPlayer contains character and client scripts. SoundService contains global audio.\n\nClick the arrow beside a service or model to expand it. Drag an object onto another compatible object to reparent it. Search filters by name.\n\n[b]Properties[/b] edits the selected object. Common fields are Name, Position, Rotation, Size, Color, Material, Transparency, Anchored and CanCollide. Press Enter after typing a numeric value. Multi-selection shows only shared properties."
		},
		{
			"title": "5. Terrain",
			"body": "[b]Painting terrain[/b]\n\nOpen the Terrain tab, choose Add, Subtract, Paint, Smooth or Flatten, then choose brush size, strength and material. Drag directly over the viewport. Select mode must release control while a terrain tool is active.\n\nAdd creates volume; Subtract carves it; Paint changes material without changing shape; Smooth removes sharp voxel edges; Flatten creates a level surface. Water is a terrain material and can also be inserted as a Water part for simple maps.\n\nWork from large forms to small details. Large brushes are faster and produce fewer cells, which improves performance on mobile devices."
		},
		{
			"title": "6. User interface",
			"body": "[b]Creating GUI[/b]\n\nOpen the UI tab and insert a ScreenGui into StarterGui. Add Frame, Label, Button, Image, Input or layout objects beneath it. The hierarchy matters: a Button inside a Frame moves with that Frame.\n\nUse anchors for responsive placement. Scale values follow screen size; Offset values are fixed pixels. Test at desktop and phone aspect ratios. Avoid full-screen opaque Frames unless the design intentionally covers gameplay.\n\nSelect a button and add a LocalScript to handle activation. Use the Activated event so mouse and touch work through the same code path. Imported Roblox GUI is shown only when Enabled and Visible are true."
		},
		{
			"title": "7. Scripts and events",
			"body": "[b]Where code runs[/b]\n\nServer scripts own gameplay state, rewards, checkpoints and validation. Client scripts own local input, camera and player-only UI. Shared ModuleScripts contain reusable functions. Remote events request actions across the client/server boundary; the server must validate every request.\n\nDouble-click a script in Explorer to open it as a tab next to the Baseplate. Use Output for print messages and errors, Find to search, and Go To Line to jump to an error.\n\nBobux supports its Lua/Luau compatibility layer, but not every Roblox API exists yet. Prefer documented Bobux services and test imported scripts one system at a time. Never trust prices, inventory changes or teleport destinations sent by a client."
		},
		{
			"title": "8. Models and assets",
			"body": "[b]Reusable content[/b]\n\nUse Creator Dashboard > Model to start empty or load GLB, glTF, OBJ, FBX, DAE or a Godot scene. Check scale, rotation, colors and materials before saving. Set a sensible pivot because placement and avatar attachments are measured from it.\n\nSave creates a local draft. Publish uploads the model payload and generated preview to your account. The model then appears in My Creations and Studio Toolbox under 3D Assets.\n\nFor reliable materials, embed textures in GLB or keep texture files beside the model. Transparent meshes need correct face normals; otherwise the front can look invisible. Keep mesh complexity reasonable for phones."
		},
		{
			"title": "9. Avatar items and clothing",
			"body": "[b]Wearable workflow[/b]\n\nOpen Avatar & Clothing. For shirts and pants, download the templates and paint only inside their regions. Upload the completed image, inspect every body side and publish. Shirts cover torso and arms; pants cover torso and legs, but an equipped shirt visually replaces the pants torso layer.\n\nFor a 3D accessory, first publish a model. Select it, choose an attachment slot, then position, rotate and scale it with the gizmo or numeric fields. Save the transform before publishing. The generated catalog preview must show the item on the default avatar.\n\nPrivate items remain visible only to the owner. Public items may appear in Catalog after the server confirms publication."
		},
		{
			"title": "10. Play test and debugging",
			"body": "[b]Test before publishing[/b]\n\nPlay starts a local server/client simulation at SpawnLocation. Stop removes the test player and restores the original edit snapshot. During Play, editing tools are locked; only Stop, Pause and gameplay controls remain active.\n\nCheck spawning, checkpoints, death and respawn, ladders, seats, swimming, tools, GUI buttons, audio and mobile controls. Watch Output for the first error rather than the hundreds of follow-up errors it may cause.\n\nFor a performance problem, temporarily hide large models, particle systems and imported GUI to find the expensive group. Use fewer collision shapes than visual triangles."
		},
		{
			"title": "11. Publishing and servers",
			"body": "[b]Server-authoritative publication[/b]\n\nSave locally first, then open File > Publish. Enter a name, description, player limit and preview. Bobux uploads the map and assets, creates a cloud version and registers the experience. Do not close Studio while the progress dialog is active.\n\nThe server is authoritative: clients request joins and actions, but the server decides the map version, player state and persistent data. A successful publish must return a map ID and version ID. Open the lobby and verify that the preview, creator, visits and Play button appear.\n\nPublishing an update creates a new version without changing the public experience identity."
		},
		{
			"title": "12. Mobile Studio",
			"body": "[b]Editing on a phone[/b]\n\nUse landscape orientation. Drag the viewport to rotate and use the editor joystick to move. Tap an object once to select it, then choose Move, Scale or Rotate. Drag only the visible gizmo handles. Pinch gestures are reserved for viewport zoom when no panel is being scrolled.\n\nExplorer, Properties, Toolbox and the guide use vertical scrolling. File pickers open Android storage or the photo gallery for model and clothing uploads. Grant media permission when Android asks.\n\nFor precision, type transform values in Properties instead of relying only on touch gizmos. Always run a phone Play test before publishing."
		},
		{
			"title": "13. Shortcuts",
			"body": "[b]Useful keyboard shortcuts[/b]\n\nCtrl+S Save | Ctrl+Shift+S Save As | Ctrl+Z Undo | Ctrl+Y Redo | Ctrl+C Copy | Ctrl+V Paste | Ctrl+D Duplicate | Delete Remove | Ctrl+A Select All | F Focus Selection | W/A/S/D Camera | Q/E Camera Down/Up | F11 Full Screen | Esc Stop a drag or release the mouse.\n\nShortcuts act on the focused editor. If typing inside a script or property field, movement shortcuts do not move the viewport."
		},
		{
			"title": "14. Troubleshooting",
			"body": "[b]Common fixes[/b]\n\n[b]Nothing is selected:[/b] activate Select and click the visible mesh, then find the highlighted object in Explorer.\n[b]Gizmo moves the wrong object:[/b] check Model pivot and selection hierarchy.\n[b]Object falls:[/b] enable Anchored.\n[b]Player falls forever:[/b] add a collidable floor and a SpawnLocation above it.\n[b]Checkpoint is ignored:[/b] ensure it is enabled, reachable and belongs to Workspace.\n[b]GUI covers everything:[/b] inspect full-screen Frames in StarterGui and their Visible property.\n[b]Texture is missing:[/b] verify the file exists, is a supported image and was included during publication.\n[b]Imported map is slow:[/b] disable unneeded scripts/GUI, reduce mesh collision and test smaller groups.\n[b]Publish fails:[/b] confirm login, server connection and that the project has a valid name."
		}
	]


func _emit_create_game() -> void:
	create_game_requested.emit()


func _emit_create_model() -> void:
	_show_model_source_dialog()


func _emit_create_avatar_item() -> void:
	create_avatar_item_requested.emit()


func _emit_catalog() -> void:
	catalog_requested.emit()


func _emit_legacy_editor() -> void:
	legacy_editor_requested.emit()


func _show_model_source_dialog() -> void:
	if _model_source_dialog != null and is_instance_valid(_model_source_dialog):
		_model_source_dialog.queue_free()
	_model_source_dialog = ConfirmationDialog.new()
	_model_source_dialog.title = "Create Model"
	_model_source_dialog.dialog_text = "Start from an empty Bobux model or import a model file into the editor."
	_model_source_dialog.ok_button_text = "Create Empty"
	_model_source_dialog.cancel_button_text = "Load File..."
	_model_source_dialog.confirmed.connect(func() -> void:
		create_model_requested.emit("")
	)
	add_child(_model_source_dialog)
	var load_button := _model_source_dialog.get_cancel_button()
	if load_button != null:
		load_button.pressed.connect(func() -> void:
			call_deferred("_open_model_file_dialog")
		)
	_model_source_dialog.popup_centered(Vector2i(430, 190))


func _open_model_file_dialog() -> void:
	if _show_system_model_file_dialog():
		return
	if _model_file_dialog != null and is_instance_valid(_model_file_dialog):
		_model_file_dialog.queue_free()
	_model_file_dialog = FileDialog.new()
	_model_file_dialog.title = "Load Model File"
	_model_file_dialog.use_native_dialog = true
	_model_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_model_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_model_file_dialog.filters = PackedStringArray([
		"*.glb, *.gltf, *.fbx ; glTF / FBX models",
		"*.obj ; Wavefront OBJ",
		"*.fbx ; FBX model",
		"*.dae ; Collada model",
		"*.tscn, *.scn ; Godot scenes",
		"*.* ; All files"
	])
	_model_file_dialog.file_selected.connect(func(path: String) -> void:
		create_model_requested.emit(path)
	)
	if OS.has_feature("android"):
		if OS.has_method("request_permissions"):
			OS.request_permissions()
		if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
			_model_file_dialog.current_dir = "/storage/emulated/0/Download"
	add_child(_model_file_dialog)
	_model_file_dialog.popup_centered(Vector2i(780, 520))


func _show_system_model_file_dialog() -> bool:
	if OS.has_feature("android") and OS.has_method("request_permissions"):
		OS.request_permissions()
	if not DisplayServer.has_method("file_dialog_show"):
		return false
	var start_dir := ""
	if OS.has_feature("android"):
		if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
			start_dir = "/storage/emulated/0/Download"
		elif DirAccess.dir_exists_absolute("/storage/emulated/0"):
			start_dir = "/storage/emulated/0"
	var callback := func(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
		if status and not selected_paths.is_empty():
			create_model_requested.emit(str(selected_paths[0]))
	var error: Error = DisplayServer.file_dialog_show(
		"Load Model File",
		start_dir,
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray([
			"*.glb, *.gltf, *.fbx ; glTF / FBX models",
			"*.obj ; Wavefront OBJ",
			"*.fbx ; FBX model",
			"*.dae ; Collada model",
			"*.tscn, *.scn ; Godot scenes",
			"*.* ; All files"
		]),
		callback
	)
	return error == OK


func _clear_content_host() -> void:
	if _content_host == null:
		return
	for child in _content_host.get_children():
		_content_host.remove_child(child)
		child.queue_free()


func _update_top_navigation() -> void:
	for page_key in _nav_buttons.keys():
		var button: Button = _nav_buttons.get(page_key) as Button
		if button == null:
			continue
		var selected: bool = str(page_key) == _current_page
		button.add_theme_color_override("font_color", COLOR_TEXT if selected else COLOR_MUTED)
		button.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.15, 0.2, 1) if selected else Color(0, 0, 0, 0), Color(0, 0, 0, 0)))


func _on_hub_resized() -> void:
	var next_compact: bool = get_viewport_rect().size.x < 920.0
	if next_compact == _compact_layout:
		return
	_compact_layout = next_compact
	if _current_page == "guide":
		_show_guide()
	else:
		_show_dashboard()


func _section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _play_intro() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _flat_style(color: Color, radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _bordered_style(color: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style := _flat_style(color, radius)
	style.border_color = border
	style.set_border_width_all(1)
	return style


func _button_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := _bordered_style(color, border, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
