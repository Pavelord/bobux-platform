extends VBoxContainer
## Compact archive collection beside the ordinary home collections.
var _character: SubViewportContainer
var _badge: PanelContainer
var _age := 0.0
var _games: HFlowContainer
var _status: Label
var _manage: Button

func _ready() -> void:
	name = "RobloxLegends"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 9)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	add_child(heading)
	heading.add_child(_label("Легенды Roblox", 23, Color("303840")))
	_badge = PanelContainer.new()
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("e63d48")
	badge_style.set_corner_radius_all(4)
	badge_style.content_margin_left = 7
	badge_style.content_margin_right = 7
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	_badge.add_theme_stylebox_override("panel", badge_style)
	_badge.add_child(_label("NEW", 11, Color.WHITE))
	heading.add_child(_badge)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	_manage = Button.new()
	_manage.text = "Управлять коллекцией"
	_manage.focus_mode = Control.FOCUS_NONE
	_manage.visible = CloudAPI.get_current_user_id() == "z9ovqynlv860sgw"
	_manage.pressed.connect(_edit_collection)
	heading.add_child(_manage)
	var card := PanelContainer.new()
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fbfdff")
	style.border_color = Color("d6e2ec")
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	_character = preload("res://scripts/lobby/legends_character.gd").new()
	_character.custom_minimum_size = Vector2(96, 104)
	_character.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_character)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 7)
	row.add_child(copy)
	var title := _label("Классика. Снова вместе.", 19, Color("175580"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title)
	var subtitle := _label("Игры Roblox разных лет — в Bobux", 14, Color("627586"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(subtitle)
	_status = _label("Загрузка коллекции…", 12, Color("84929d"))
	copy.add_child(_status)
	_games = HFlowContainer.new()
	_games.add_theme_constant_override("h_separation", 12)
	_games.add_theme_constant_override("v_separation", 12)
	add_child(_games)
	_reload()

func _reload() -> void:
	var result := await CloudAPI.fetch_legends()
	if not is_inside_tree(): return
	for child in _games.get_children(): child.queue_free()
	if not result.get("ok", false):
		_status.text = "Коллекция временно недоступна"
		return
	var games: Array = result.get("games", [])
	_status.text = "В коллекции пока нет игр" if games.is_empty() else "%d игр в коллекции" % games.size()
	var lobby := get_tree().current_scene
	for item in games:
		if not lobby.has_method("_create_smart_play_card"): continue
		var entry: Dictionary = item.duplicate()
		entry["map_id"] = str(item.id)
		var column := VBoxContainer.new()
		column.add_child(_label(str(item.year), 13, Color("175580")))
		column.add_child(lobby._create_smart_play_card(entry, true, true))
		_games.add_child(column)

func _edit_collection() -> void:
	_manage.disabled = true
	var result := await CloudAPI.fetch_published_maps(200)
	_manage.disabled = false
	if not result.get("ok", false):
		_status.text = "Не удалось загрузить список игр. Попробуйте ещё раз."
		return
	var maps: Array = CloudAPI._extract_array_payload(result.get("data", []))
	var dialog := AcceptDialog.new()
	dialog.title = "Легенды Roblox — коллекция"
	dialog.ok_button_text = "Закрыть"
	add_child(dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	dialog.add_child(column)
	var select := OptionButton.new()
	select.custom_minimum_size.x = 340
	for item in maps: select.add_item("%s · %s" % [item.get("name","Игра"),item.get("owner_name","")])
	column.add_child(select)
	column.add_child(_label("Год оригинальной игры Roblox", 14, Color("555555")))
	var year := SpinBox.new()
	year.min_value = 2006
	year.max_value = Time.get_date_dict_from_system().year
	year.value = 2011
	column.add_child(year)
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var save := Button.new()
	save.text = "Добавить / сохранить год"
	column.add_child(save)
	var remove := Button.new()
	remove.text = "Убрать из коллекции"
	column.add_child(remove)
	for button in [save, remove]:
		button.disabled = maps.is_empty()
		button.pressed.connect(func():
			save.disabled = true
			remove.disabled = true
			var response := await CloudAPI.update_legend(str(maps[select.selected].id), int(year.value), button == remove)
			if not is_instance_valid(message): return
			message.text = "Сохранено" if response.get("ok",false) else str(response.get("error","Ошибка сохранения"))
			save.disabled = false
			remove.disabled = false
			if response.get("ok",false): _reload()
		)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(380,320))

func _process(delta: float) -> void:
	if _manage != null: _manage.visible = CloudAPI.get_current_user_id() == "z9ovqynlv860sgw"
	if not is_visible_in_tree() or _badge == null: return
	_age += delta
	_badge.pivot_offset = _badge.size * 0.5
	var pulse := maxf(0.0, sin(fmod(_age, 5.0) * TAU)) * 0.025 if fmod(_age, 5.0) < 1.0 else 0.0
	_badge.scale = Vector2.ONE * (1.0 + pulse)

func _label(copy: String, pixels: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = copy
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
