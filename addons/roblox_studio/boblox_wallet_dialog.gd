extends AcceptDialog

var balance_label: Label
var details: Label

func _ready() -> void:
	title = "Boblox"
	ok_button_text = "Закрыть"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var icon := TextureRect.new()
	# The user's original artwork, without modifying the source image.
	var picture := Image.load_from_file("res://assets/currency/boblox.png")
	if picture != null: icon.texture = ImageTexture.create_from_image(picture)
	icon.custom_minimum_size = Vector2(80, 80)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(icon)
	balance_label = Label.new()
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_label.add_theme_font_size_override("font_size", 26)
	balance_label.text = "Проверка кошелька…"
	column.add_child(balance_label)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.x = 420
	details.text = "Boblox — валюта аккаунта. Баланс и история приходят с сервера."
	column.add_child(details)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)

func refresh() -> void:
	var api := get_tree().root.get_node_or_null("CloudAPI")
	if api == null: show_response({"ok": false}); return
	show_response(await api.fetch_boblox_wallet())

func show_response(response: Dictionary) -> void:
	var data: Variant = response.get("data", response)
	if not response.get("ok", false) or not data is Dictionary or not data.has("balance"):
		balance_label.text = "Кошелёк пока недоступен"
		details.text = "Нужны вход в аккаунт и включённый сервис Boblox. Покупки и переводы пока не подключены."
		return
	balance_label.text = "%d Boblox" % int(data.balance)
	var rows: Array[String] = ["Последние операции:"]
	for operation in data.get("operations", []):
		rows.append("%+d · %s" % [int(operation.get("amount", 0)), str(operation.get("reason", ""))])
	if rows.size() == 1: rows.append("Операций пока нет.")
	details.text = "\n".join(rows)
