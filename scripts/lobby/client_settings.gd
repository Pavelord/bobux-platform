extends ColorRect
const UI := preload("res://scripts/lobby/boblox_shop.gd")
var _tabs: TabContainer
var _panel: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI._style(Color.WHITE, 24))
	center.add_child(_panel)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	_panel.add_child(page)
	var heading := HBoxContainer.new()
	page.add_child(heading)
	var title := UI._label("Settings", 28)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	var brand := UI._label("BOBUX", 16, Color("#0076b4"))
	brand.size_flags_horizontal = SIZE_SHRINK_END
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_child(brand)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.y = 280
	_tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("panel", UI._style(Color.WHITE, 12))
	_tabs.add_theme_stylebox_override("tab_selected", UI._style(Color("#e9f6fd"), 10))
	_tabs.add_theme_stylebox_override("tab_unselected", UI._style(Color("#f3f3f3"), 10))
	for key in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		_tabs.add_theme_color_override(key, Color("#333333"))
	page.add_child(_tabs)
	var sound := _page("Sound")
	_slider(sound, "Общая громкость", "volume", 0, 100, 100, "%")
	sound.add_child(UI._label("Музыка и звуки во всех режимах.", 14, UI.MUTED))
	var display := _page("Display")
	if not OS.has_feature("mobile"): _toggle(display, "Полный экран", "fullscreen")
	_toggle(display, "Вертикальная синхронизация", "vsync")
	display.add_child(UI._label("Синхронизирует кадры с экраном, чтобы убрать разрывы изображения.", 14, UI.MUTED))
	var controls := _page("Controls")
	_slider(controls, "Чувствительность камеры", "mouse_sensitivity", 25, 300, 100, "%")
	_toggle(controls, "Инвертировать камеру по вертикали", "invert_y")
	controls.add_child(UI._label("W A S D — движение   ·   Space — прыжок\nПравая кнопка мыши — камера\nShift — фиксация камеры   ·   Ctrl — бег" if not OS.has_feature("mobile") else "Джойстик — движение. Проведи пальцем справа для поворота камеры. Кнопки управления доступны в режиме.", 14, UI.MUTED))
	var footer := HBoxContainer.new()
	page.add_child(footer)
	var saved := UI._label("Сохраняется на этом устройстве", 13, UI.MUTED)
	saved.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(saved)
	var done := UI._button("Готово")
	done.pressed.connect(queue_free)
	footer.add_child(done)
	var resize := func(): _panel.custom_minimum_size = Vector2(minf(560, size.x - 24), 0)
	resized.connect(resize)
	resize.call()
	done.grab_focus()

func _page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 18)
	_tabs.add_child(page)
	return page

func _slider(page: VBoxContainer, title: String, key: String, low: float, high: float, factor: float, suffix: String) -> void:
	var row := HBoxContainer.new()
	page.add_child(row)
	var label := UI._label(title, 16)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var amount := UI._label("", 16, Color("#0076b4"))
	amount.size_flags_horizontal = SIZE_SHRINK_END
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(amount)
	var slider := HSlider.new()
	slider.name = key
	slider.min_value = low
	slider.max_value = high
	slider.step = 1
	slider.value = float(ClientPreferences.values[key]) * factor
	amount.text = str(roundi(slider.value)) + suffix
	slider.custom_minimum_size.y = 28
	slider.value_changed.connect(func(value: float):
		amount.text = str(roundi(value)) + suffix
		ClientPreferences.update(key, value / factor)
	)
	page.add_child(slider)

func _toggle(page: VBoxContainer, title: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.name = key
	toggle.add_theme_color_override("font_color", Color("#333333"))
	toggle.add_theme_color_override("font_hover_color", Color("#0076b4"))
	toggle.button_pressed = ClientPreferences.values[key]
	toggle.toggled.connect(func(value: bool): ClientPreferences.update(key, value))
	page.add_child(toggle)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
