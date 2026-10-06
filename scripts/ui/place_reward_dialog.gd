extends CanvasLayer
signal confirmed
var action: Button
var headline: Label
var description: Label
var balance: Label
var price := 0
var _done := false

func _ready() -> void:
	layer = 100
	var dim := ColorRect.new()
	dim.color = Color(0.04,0.07,0.11,0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(420, get_viewport().get_visible_rect().size.x - 32)
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color.WHITE
	surface.set_corner_radius_all(8)
	surface.set_content_margin_all(24)
	surface.shadow_color = Color(0,0,0,0.3)
	surface.shadow_size = 18
	panel.add_theme_stylebox_override("panel",surface)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(450, get_viewport().get_visible_rect().size.y - 80)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",14)
	scroll.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var heading := Label.new()
	heading.text = "BOBUX  /  НАГРАДЫ"
	heading.add_theme_color_override("font_color",Color("#0074bd"))
	heading.add_theme_font_size_override("font_size",14)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_color_override("font_color",Color("#66717c"))
	close.pressed.connect(queue_free)
	top.add_child(close)
	var coin_row := CenterContainer.new()
	column.add_child(coin_row)
	var coin := Label.new()
	coin.text = "B$"
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin.custom_minimum_size = Vector2(80,80)
	coin.add_theme_font_size_override("font_size",32)
	coin.add_theme_color_override("font_color",Color("#a66600"))
	var gold := StyleBoxFlat.new()
	gold.bg_color = Color("#fff2b8")
	gold.border_color = Color("#f6ca45")
	gold.set_border_width_all(3)
	gold.set_corner_radius_all(40)
	coin.add_theme_stylebox_override("normal",gold)
	coin_row.add_child(coin)
	headline = Label.new()
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size",23)
	headline.add_theme_color_override("font_color",Color("#222c37"))
	column.add_child(headline)
	description = Label.new()
	description.custom_minimum_size.x = panel.custom_minimum_size.x - 48
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size",15)
	description.add_theme_color_override("font_color",Color("#606b76"))
	column.add_child(description)
	balance = Label.new()
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance.add_theme_color_override("font_color",Color("#606b76"))
	column.add_child(balance)
	action = Button.new()
	action.custom_minimum_size.y = 48
	action.focus_mode = Control.FOCUS_NONE
	action.add_theme_font_size_override("font_size",17)
	for state in ["normal","hover","pressed","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#00b65a") if state=="normal" else Color("#07974f") if state=="hover" else Color("#078947") if state=="pressed" else Color("#b9c7bf")
		style.set_corner_radius_all(5)
		action.add_theme_stylebox_override(state,style)
		action.add_theme_color_override("font_color" if state=="normal" else "font_"+state+"_color",Color.WHITE)
	column.add_child(action)
	action.pressed.connect(func():
		if _done: queue_free()
		else: confirmed.emit()
	)
	var cancel := Button.new()
	cancel.text = "Не сейчас"
	cancel.flat = true
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.add_theme_color_override("font_color",Color("#66717c"))
	cancel.pressed.connect(queue_free)
	column.add_child(cancel)

func configure(kind: String, status: Dictionary, preview: bool = false) -> void:
	action.disabled = false
	var daily := kind == "daily_boblox"
	price = int(status.get("price",150))
	headline.text = "Ежедневная награда" if daily else "Монета усиления"
	description.text = "10 Boblox каждый день. Награда общая для всех режимов, обновляется в 00:00 UTC." if daily else "Бегайте быстрее и прыгайте выше, пока монета в руке. Геймпасс остаётся вашим в этом режиме навсегда."
	balance.text = "Предпросмотр Studio · без изменения баланса" if preview else "Ваш баланс: %d Boblox" % int(status.get("balance",0))
	action.text = "Получить 10 Boblox" if daily else "Купить за %d Boblox" % price
	if daily and bool(status.get("daily_claimed",false)):
		action.text = "Сегодня уже получено"
		action.disabled = true
	elif not daily and (preview or bool(status.get("owned",false))): action.text = "Получить монету"

func busy() -> void:
	action.disabled = true
	action.text = "Подождите…"

func failure(message: String) -> void:
	description.text = message
	action.text = "Повторить"
	action.disabled = false

func complete(message: String) -> void:
	_done = true
	headline.text = "Готово!"
	description.text = message
	action.text = "Отлично"
	action.disabled = false
