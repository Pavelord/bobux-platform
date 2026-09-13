extends CanvasLayer

signal claimed(account: Dictionary)
var preview_only := false
var _button: Button
var _status: Label
var _card: PanelContainer
var _confetti: Control

class Confetti extends Control:
	var age := 0.0
	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age > 5.0: set_process(false)
	func _draw() -> void:
		var colors := [Color("35b8ff"), Color("ffcc43"), Color("ffffff"), Color("ff637b")]
		for i in range(48):
			var speed := 60.0 + float(i % 7) * 13.0
			var x := fmod(float(i) * 127.3, maxf(size.x, 1.0)) + sin(age * 2.0 + i) * 20.0
			var y := -80.0 - float(i % 9) * 35.0 + age * speed
			draw_set_transform(Vector2(x, y), age + i)
			draw_rect(Rect2(-3, -6, 6, 12), colors[i % 4] * Color(1, 1, 1, clampf(5.0 - age, 0, 1)))
		draw_set_transform(Vector2.ZERO)

func _ready() -> void:
	layer = 120
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.03, 0.08, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(620, get_viewport().get_visible_rect().size.x - 32), minf(660, get_viewport().get_visible_rect().size.y - 32))
	center.add_child(scroll)
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_card)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffffff")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(28)
	style.border_color = Color("42b9ff")
	style.set_border_width_all(2)
	style.shadow_color = Color(0.03, 0.4, 0.8, 0.32)
	style.shadow_size = 28
	_card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_card.add_child(column)
	column.add_child(_label("ВЫ ДЕЛАЕТЕ BOBUX ЛУЧШЕ", 14, Color("0074bd")))
	column.add_child(_label("Спасибо, %s!" % (UserSession.username if not preview_only else "pavelord"), 30, Color("223047")))
	var badges := HBoxContainer.new()
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	badges.add_theme_constant_override("separation", 22)
	column.add_child(badges)
	badges.add_child(preload("res://scripts/lobby/account_badges.gd").icon("tbc", 112))
	badges.add_child(preload("res://scripts/lobby/account_badges.gd").icon("verified", 76))
	column.add_child(_label("Turbo Bricks Club · навсегда", 23, Color("c62935")))
	var message := _label("Спасибо за активное участие в развитии игры!\n\nВаши идеи, тестирование и поддержка помогают Bobux расти. Вы были рядом, когда многое только начиналось, и ваш вклад останется частью нашей истории.\n\nВ знак благодарности — пожизненный максимальный Bricks Club и галочка рядом с именем.", 17, Color("495367"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = minf(540, get_viewport().get_visible_rect().size.x - 92)
	column.add_child(message)
	_status = _label("Награда закреплена за вашим аккаунтом.", 13, Color("748094"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_button = Button.new()
	_button.text = "Получить"
	_button.custom_minimum_size.y = 50
	_button.add_theme_font_size_override("font_size", 21)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color("00ad54")
	button_style.set_corner_radius_all(5)
	_button.add_theme_stylebox_override("normal", button_style)
	var hover := button_style.duplicate()
	hover.bg_color = Color("00c060")
	_button.add_theme_stylebox_override("hover", hover)
	_button.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_button)
	_button.pressed.connect(_claim)
	_confetti = Confetti.new()
	_confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(_confetti)
	_card.modulate.a = 0
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.35)
	# Keep the heading visible on a short mobile screen; keyboard focus scrolls to the claim button.

func _label(text_: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	return label

func _claim() -> void:
	_button.disabled = true
	_status.text = "Получаем награду…"
	var result: Dictionary = {"ok": true, "data": {}} if preview_only else await CloudAPI.claim_founder_reward()
	if not is_inside_tree(): return
	if not result.get("ok", false):
		_status.text = "Не удалось связаться с сервером. Нажмите «Получить» ещё раз."
		_button.disabled = false
		return
	var account: Dictionary = result.get("data", result)
	claimed.emit(account)
	_status.text = "Галочка и пожизненный TBC получены. Спасибо, что вы с нами!"
	await get_tree().create_timer(0.8).timeout
	queue_free()
