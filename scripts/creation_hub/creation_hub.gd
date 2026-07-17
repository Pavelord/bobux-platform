extends Control

signal create_game_requested
signal create_model_requested(source_path: String)
signal create_avatar_item_requested
signal catalog_requested
signal home_requested

const PAGE_MIN_SIZE := Vector2(980, 680)
const CARD_MIN_SIZE := Vector2(220, 210)

var _page_root: VBoxContainer = null
var _model_source_dialog: ConfirmationDialog = null
var _model_file_dialog: FileDialog = null

func _ready() -> void:
	custom_minimum_size = PAGE_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_page()
	_play_intro()

func _build_page() -> void:
	# Add dark background panel
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.09, 0.10)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 28)
	page_margin.add_theme_constant_override("margin_top", 24)
	page_margin.add_theme_constant_override("margin_right", 28)
	page_margin.add_theme_constant_override("margin_bottom", 28)
	add_child(page_margin)

	_page_root = VBoxContainer.new()
	_page_root.add_theme_constant_override("separation", 18)
	page_margin.add_child(_page_root)

	_page_root.add_child(_create_header())
	_page_root.add_child(_create_primary_cards())
	_page_root.add_child(_create_status_panel())

func _create_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 3)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	var title := Label.new()
	title.text = "Develop"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Bobux Studio hub. Build games, create models, and manage your creations."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	title_box.add_child(subtitle)

	var home_button := Button.new()
	home_button.text = "Back to Home"
	home_button.custom_minimum_size = Vector2(130, 36)
	home_button.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.18, 0.20), Color(0.28, 0.30, 0.32)))
	home_button.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.26, 0.28), Color(0.0, 0.52, 0.82)))
	home_button.add_theme_color_override("font_color", Color.WHITE)
	home_button.pressed.connect(func(): home_requested.emit())
	header.add_child(home_button)

	return header

func _create_primary_cards() -> GridContainer:
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 18)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	row.add_child(_create_hub_card(
		"Create Game",
		"Open the experience builder and choose a starting template. Published games must go through Bobux Cloud, not local-only maps.",
		"Games",
		Color(0.0, 0.52, 0.82),
		Callable(self, "_emit_create_game")
	))
	row.add_child(_create_hub_card(
		"Create Model",
		"Design reusable map/avatar assets. This module will get Explorer, Properties, Toolbox and safe asset publishing.",
		"Models",
		Color(0.95, 0.38, 0.08),
		Callable(self, "_emit_create_model")
	))
	row.add_child(_create_hub_card(
		"Create Avatar Items",
		"Turn your models and clothing templates into wearable items for player avatars.",
		"Avatar",
		Color(0.75, 0.34, 0.86),
		Callable(self, "_emit_create_avatar_item")
	))
	row.add_child(_create_hub_card(
		"My Catalog",
		"Browse your drafts and cloud-ready creations from one place. Local drafts are treated as drafts only.",
		"Catalog",
		Color(0.26, 0.64, 0.30),
		Callable(self, "_emit_catalog")
	))

	return row

func _create_hub_card(title: String, description: String, label_text: String, accent: Color, callback: Callable) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(accent))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)

	var badge := Label.new()
	badge.text = label_text
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", accent.lightened(0.2))
	box.add_child(badge)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(heading)

	var desc := Label.new()
	desc.text = description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var action := Button.new()
	action.text = "Open"
	action.custom_minimum_size = Vector2(0, 38)
	action.add_theme_stylebox_override("normal", _button_style(accent, accent.darkened(0.08)))
	action.add_theme_stylebox_override("hover", _button_style(accent.lightened(0.08), accent.darkened(0.02)))
	action.add_theme_color_override("font_color", Color.WHITE)
	action.pressed.connect(callback)
	box.add_child(action)

	return card

func _create_status_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 96)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.13, 0.15)))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var text := Label.new()
	text.text = "Development rule: drafts can be cached locally, but anything playable by users must be published through the server/cloud pipeline."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	margin.add_child(text)

	return panel

func _emit_create_game() -> void:
	create_game_requested.emit()

func _emit_create_model() -> void:
	_show_model_source_dialog()

func _emit_create_avatar_item() -> void:
	create_avatar_item_requested.emit()

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
		"*.glb, *.gltf ; glTF models",
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
	if OS.has_feature("android"):
		if OS.has_method("request_permissions"):
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
		if not status or selected_paths.is_empty():
			return
		create_model_requested.emit(str(selected_paths[0]))
	var error: Error = DisplayServer.file_dialog_show(
		"Load Model File",
		start_dir,
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray([
			"*.glb, *.gltf ; glTF models",
			"*.obj ; Wavefront OBJ",
			"*.fbx ; FBX model",
			"*.dae ; Collada model",
			"*.tscn, *.scn ; Godot scenes",
			"*.* ; All files"
		]),
		callback
	)
	return error == OK

func _emit_catalog() -> void:
	catalog_requested.emit()

func _play_intro() -> void:
	if _page_root == null:
		return
	_page_root.modulate.a = 0.0
	_page_root.scale = Vector2(0.8, 0.8)
	_page_root.pivot_offset = PAGE_MIN_SIZE / 2.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_page_root, "modulate:a", 1.0, 0.22)
	tween.tween_property(_page_root, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.25, 0.27, 0.30)
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	return style

func _card_style(accent: Color) -> StyleBoxFlat:
	var style := _panel_style(Color(0.12, 0.13, 0.15))
	style.border_width_top = 4
	style.border_color = accent
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style

func _button_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
