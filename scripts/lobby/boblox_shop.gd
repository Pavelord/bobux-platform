extends PanelContainer
## Server-owned wallet and membership shop. Preview prices never authorize a purchase.
signal account_updated(account: Dictionary)

const CATALOG_PATH := "res://assets/currency/commerce_catalog.json"
const GREEN := Color("#008a27")
const INK := Color("#343434")
const MUTED := Color("#757575")
var catalog: Dictionary = {}
var account: Dictionary = {}
var preview_only := false
var _body: VBoxContainer
var _balance: Label
var _club: Label
var _notice: Label
var _refresh_button: Button
var _section := 0
var _compact := false
var _busy := false
var _refreshing := false
var _dialog: ConfirmationDialog
var _email: LineEdit
var _consent: CheckBox
var _dialog_status: Label
var _check_button: Button
var _chosen: Dictionary = {}
var _request_key := ""
var _order_id := ""
var _buttons: Array[Button] = []
var _session_id := ""

func _ready() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	_session_id = UserSession.user_id
	_compact = size.x < 850
	add_theme_stylebox_override("panel", _style(Color.WHITE, 24))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Noto Sans", "sans-serif"])
	add_theme_font_override("font", font)
	add_theme_color_override("font_color", INK)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 18)
	scroll.add_child(page)
	var account_row := HFlowContainer.new()
	account_row.add_theme_constant_override("h_separation", 14)
	page.add_child(account_row)
	account_row.add_child(_icon("res://assets/currency/boblox.png", 32))
	_balance = _label("— Boblox", 22, GREEN)
	_balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	account_row.add_child(_balance)
	_club = _label("BC · Бесплатный клуб", 15, MUTED)
	_club.autowrap_mode = TextServer.AUTOWRAP_OFF
	account_row.add_child(_club)
	_refresh_button = _button("Обновить", false)
	_refresh_button.pressed.connect(refresh)
	account_row.add_child(_refresh_button)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	page.add_child(tabs)
	for idx in range(3):
		var tab := _button(["Bricks Club", "Купить Boblox", "Мои покупки"][idx], false)
		tab.toggle_mode = true
		tab.pressed.connect(func(): select_section(idx))
		_buttons.append(tab)
		tabs.add_child(tab)
	page.add_child(HSeparator.new())
	_notice = _label("Знакомьтесь с Boblox и Bricks Club. Продажи ещё не открыты.", 14, MUTED)
	page.add_child(_notice)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 20)
	page.add_child(_body)
	resized.connect(_on_resize)
	select_section(0)
	if not preview_only:
		call_deferred("refresh")

func select_section(index: int) -> void:
	_section = clampi(index, 0, 2)
	for idx in range(_buttons.size()):
		_buttons[idx].set_pressed_no_signal(idx == _section)
	_render()

func _on_resize() -> void:
	var compact := size.x < 850
	if compact != _compact:
		_compact = compact
		_render()

func _render() -> void:
	if not is_instance_valid(_body): return
	add_theme_stylebox_override("panel", _style(Color("#e3e3e3") if _section == 1 else Color.WHITE, 24))
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _section == 0: _render_club()
	elif _section == 1: _render_packs()
	else: _render_history()

func _render_club() -> void:
	_body.add_child(_label("Bricks Club", 34))
	_body.add_child(_label("Твой клуб. Твои возможности.", 19, MUTED))
	_body.add_child(_label("Получай Boblox каждый день и выбирай свой цвет клуба.", 15, MUTED))
	if _compact:
		for tier in catalog.get("tiers", []):
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _style(Color("#fafafa"), 18))
			_body.add_child(card)
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 12)
			card.add_child(column)
			column.add_child(_tier_heading(tier))
			column.add_child(_label("%d Boblox в день · %d за 30 дней" % [int(tier.daily), int(tier.daily) * 30], 16, GREEN, true))
			var rules: Dictionary = tier.get("creator", {})
			column.add_child(_label("Одежда: %d бесплатно / месяц · затем %d Boblox\n3D-предметы: %d бесплатно / месяц · затем %d Boblox" % [int(rules.get("clothing_limit", 0)), int(rules.get("clothing_fee", 0)), int(rules.get("items_limit", 0)), int(rules.get("items_fee", 0))], 14, MUTED))
			column.add_child(_tier_button(tier))
	else:
		var grid := GridContainer.new()
		grid.name = "ClubComparison"
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 0)
		_body.add_child(grid)
		var first := _label("Выбери свой\nBricks Club", 22)
		first.custom_minimum_size.x = 175
		grid.add_child(first)
		for tier in catalog.tiers: grid.add_child(_tier_heading(tier))
		_compare_row(grid, "Boblox каждый день", ["—", str(int(catalog.tiers[1].daily)), str(int(catalog.tiers[2].daily)), str(int(catalog.tiers[3].daily))], true)
		_compare_row(grid, "Всего за 30 дней", ["—", str(int(catalog.tiers[1].daily) * 30), str(int(catalog.tiers[2].daily) * 30), str(int(catalog.tiers[3].daily) * 30)], true)
		_compare_row(grid, "Значок клуба", ["BC", "BBC", "PBC", "TBC"])
		_compare_row(grid, "Игры и Bobux Studio", ["Доступны", "Доступны", "Доступны", "Доступны"])
		_compare_row(grid, "Автосписания", ["Нет", "Нет", "Нет", "Нет"])
		for benefit in [["clothing_limit", "Одежда без сбора / месяц"], ["items_limit", "3D без сбора / месяц"], ["clothing_fee", "Сверх лимита: одежда, Boblox"], ["items_fee", "Сверх лимита: 3D, Boblox"], ["clothing_max", "Всего одежды / месяц"], ["items_max", "Всего 3D / месяц"], ["free_items_limit", "Товары с ценой 0 / месяц"]]:
			var values: Array = []
			for tier in catalog.tiers: values.append(str(int(tier.get("creator", {}).get(benefit[0], 0))))
			_compare_row(grid, benefit[1], values)

		var price_label := _label("Стоимость", 16)
		price_label.custom_minimum_size.y = 70
		grid.add_child(price_label)
		for tier in catalog.tiers:
			var holder := MarginContainer.new()
			holder.add_theme_constant_override("margin_top", 18)
			holder.add_theme_constant_override("margin_left", 10)
			holder.add_theme_constant_override("margin_right", 10)
			grid.add_child(holder)
			holder.add_child(_tier_button(tier))
	_body.add_child(_label("Лимиты обновляются 1-го числа по UTC. Черновики, карты и правки опубликованных вещей бесплатны. Платная одежда — от 5 Boblox, 3D-предметы — от 20. Товары с ценой 0 имеют отдельный лимит; удаление его не возвращает. Модели для Toolbox остаются бесплатными.", 14, MUTED))
	_body.add_child(_label("30 дней клуба · Без автоматического продления", 16, GREEN))
	_body.add_child(_label("Первая награда — после активации, следующие — каждые 24 часа. Награды за пропущенные дни сохраняются. Продление того же уровня добавляет ещё 30 дней; другой уровень можно выбрать после окончания текущего.", 14, MUTED))
	_body.add_child(HSeparator.new())
	var more := HFlowContainer.new()
	more.add_theme_constant_override("h_separation", 30)
	_body.add_child(more)
	var buy := _button("Нужны Boblox сразу?", false)
	buy.pressed.connect(func(): select_section(1))
	more.add_child(buy)
	more.add_child(_label("100 Boblox = 50 ₽", 18, GREEN))

func _tier_heading(tier: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label(str(tier.id), 26, INK, true))
	column.add_child(_icon("res://assets/currency/bricks_club/%s.png" % str(tier.id).to_lower(), 104))
	var title := _label(str(tier.name), 15, MUTED, true)
	title.custom_minimum_size = Vector2(125 if not _compact else 0, 42)
	column.add_child(title)
	return column

func _tier_button(tier: Dictionary) -> Button:
	var free := str(tier.id) == "BC"
	var button := _button("Бесплатно" if free else "%s ₽ / 30 дней" % _rubles(tier.price_kopecks), not free)
	button.name = "Buy" + str(tier.id)
	button.disabled = free
	if bool(account.get("membership", {}).get("lifetime", false)):
		button.disabled = true
		button.text = "Ваш клуб · навсегда" if str(tier.id) == "TBC" else "У вас уже есть TBC"
	if not free: button.pressed.connect(func(): _show_checkout(tier))
	return button

func _compare_row(grid: GridContainer, title: String, values: Array, currency := false) -> void:
	var cells: Array = [title]
	cells.append_array(values)
	for idx in range(cells.size()):
		var panel := PanelContainer.new()
		var style := _style(Color.WHITE, 10)
		style.set_border_width_all(0)
		style.border_width_bottom = 1
		panel.add_theme_stylebox_override("panel", style)
		grid.add_child(panel)
		panel.add_child(_label(str(cells[idx]), 15, GREEN if currency and idx > 0 else INK, idx > 0))

func _render_packs() -> void:
	_body.add_child(_label("Купить Boblox", 34))
	var layout := BoxContainer.new()
	layout.vertical = _compact
	layout.add_theme_constant_override("separation", 32)
	_body.add_child(layout)
	var promo := PanelContainer.new()
	promo.visible = not _compact
	promo.custom_minimum_size.x = 0 if _compact else 260
	promo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	promo.add_theme_stylebox_override("panel", _style(Color("#172b24"), 22))
	layout.add_child(promo)
	var promo_content := VBoxContainer.new()
	promo_content.add_theme_constant_override("separation", 18)
	promo.add_child(promo_content)
	promo_content.add_child(_label("BOBLOX", 27, Color.WHITE))
	var promo_preview := TextureRect.new()
	promo_preview.custom_minimum_size = Vector2(210, 240)
	promo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	promo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	promo_content.add_child(promo_preview)
	var renderer := get_node_or_null("PromoRenderer")
	if renderer == null:
		renderer = load("res://scripts/lobby/catalog_thumbnail_renderer.gd").new()
		renderer.name = "PromoRenderer"
		add_child(renderer)
	renderer.call("request_preview", {"id": "boblox_promo_v1", "category": "boblox_promo"}, promo_preview)
	promo_content.add_child(_label("Твоя валюта\nв мире Bobux.", 23, Color.WHITE))
	promo_content.add_child(_label("100 Boblox = 50 ₽\nКлуб для покупки не требуется.", 15, Color("#d5e7dd")))
	var products := VBoxContainer.new()
	products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	products.add_theme_constant_override("separation", 18)
	layout.add_child(products)
	products.add_child(_label("Пакеты Boblox", 22, MUTED))
	for pack in catalog.get("packs", []):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := _style(Color.WHITE, 16)
		style.shadow_color = Color(0, 0, 0, 0.13)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 1)
		panel.add_theme_stylebox_override("panel", style)
		products.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		panel.add_child(column)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		column.add_child(line)
		line.add_child(_icon("res://assets/currency/boblox.png", 28))
		line.add_child(_label(str(int(pack.amount)), 27, GREEN))
		var buy := _button("Купить за %s ₽" % _rubles(pack.price_kopecks))
		buy.custom_minimum_size.x = 150 if _compact else 195
		buy.name = "Buy" + str(pack.id)
		buy.pressed.connect(func(): _show_checkout(pack))
		line.add_child(buy)
		var club_link := LinkButton.new()
		club_link.text = "Boblox каждый день — вступить в Bricks Club"
		club_link.add_theme_font_size_override("font_size", 13)
		club_link.add_theme_color_override("font_color", Color("#0074bd"))
		club_link.pressed.connect(func(): select_section(0))
		if _compact: club_link.text = "Вступить в Bricks Club"
		column.add_child(club_link)
	_body.add_child(_label("Boblox зачисляются на аккаунт после подтверждения оплаты. Баланс сохраняется на сервере и доступен на других устройствах.", 15, MUTED))
	_body.add_child(HSeparator.new())
	_body.add_child(_label("Boblox — внутренняя валюта Bobux. Обмен на реальные деньги не предусмотрен.", 14, MUTED))

func _render_history() -> void:
	_body.add_child(_label("Мои покупки", 32))
	var membership: Dictionary = account.get("membership", {})
	var ends := int(membership.get("paid_until_ms", 0))
	if membership.get("lifetime", false):
		_body.add_child(_label("Turbo Bricks Club — пожизненно", 20, GREEN))
	elif ends > 0:
		_body.add_child(_label("Клуб оплачен до %s" % _date(ends), 16, GREEN))
	if account.is_empty():
		_body.add_child(_label("Подключитесь к серверу, чтобы увидеть баланс и историю.", 16, MUTED))
	for order in account.get("orders", []):
		var row := VBoxContainer.new()
		_body.add_child(row)
		row.add_child(_label("%s · %s" % [order.product, _status_text(str(order.status))], 16))
		row.add_child(_label(_date(int(order.created_ms)), 13, MUTED))
		if order.get("review", false): row.add_child(_label("Возврат на проверке поддержки.", 14, Color("#ad5711")))
		if str(order.status) not in ["succeeded", "canceled"]:
			var check := _button("Проверить оплату", false)
			check.disabled = _busy
			check.pressed.connect(func(): _check_order(str(order.id)))
			row.add_child(check)
		row.add_child(HSeparator.new())
	if account.get("orders", []).is_empty() and not account.is_empty():
		_body.add_child(_label("У тебя пока нет покупок.", 16, MUTED))
	_body.add_child(_label("Движение Boblox", 22))
	for operation in account.get("operations", []):
		var reason: String = str(operation.reason)
		var caption := "Покупка Boblox" if reason == "boblox_purchase" else "Награда Bricks Club" if reason.ends_with(":daily") else reason
		_body.add_child(_label("%+d Boblox · %s · %s" % [int(operation.amount), caption, str(operation.created_at).substr(0, 10)], 15, GREEN if int(operation.amount) > 0 else INK))
	if account.get("operations", []).is_empty():
		_body.add_child(_label("Здесь появятся начисления и списания.", 14, MUTED))
	var support := str(catalog.get("support_url", ""))
	if support.begins_with("https://"):
		var help := _button("Помощь с оплатой", false)
		help.pressed.connect(func(): OS.shell_open(support))
		_body.add_child(help)

func refresh() -> void:
	if _refreshing or preview_only: return
	_refreshing = true
	_refresh_button.disabled = true
	var response: Dictionary = await CloudAPI.fetch_boblox_catalog()
	if not is_inside_tree() or UserSession.user_id != _session_id: return
	if response.get("ok", false):
		var data := _payload(response)
		if data.has("tiers") and data.has("packs"): catalog = data
	if UserSession.is_logged_in:
		response = await CloudAPI.fetch_boblox_wallet()
		if not is_inside_tree() or UserSession.user_id != _session_id: return
		if response.get("ok", false): _set_account(_payload(response))
		else: _balance.text = "Баланс недоступен"
	_notice.text = "ТЕСТОВЫЙ МАГАЗИН · Тестовые покупки не попадают в настоящий баланс." if catalog.get("test", false) else "Оплата откроется на защищённой странице ЮKassa." if catalog.get("sales_enabled", false) else "Предварительные тарифы · Продажи ещё не открыты."
	_refreshing = false
	_refresh_button.disabled = false
	_render()

func _set_account(data: Dictionary) -> void:
	account = data
	_balance.text = "%d Boblox%s" % [int(account.get("balance", 0)), " (тест)" if account.get("test", false) else ""]
	var member: Dictionary = account.get("membership", {})
	_club.text = "%s · %s" % [str(member.get("tier", "BC")), "Бесплатный клуб" if member.get("tier", "BC") == "BC" else "%d Boblox в день" % int(member.get("daily", 0))]
	if member.get("lifetime", false): _club.text += " · навсегда"
	account_updated.emit(account)

func _show_checkout(product: Dictionary) -> void:
	if _busy: return
	_chosen = product
	var pending := ConfigFile.new()
	var pending_key := "%s:%s" % [_session_id, str(product.id)]
	pending.load("user://boblox_pending.cfg")
	_request_key = str(pending.get_value("requests", pending_key, ""))
	if _request_key.is_empty():
		_request_key = Crypto.new().generate_random_bytes(16).hex_encode()
		pending.set_value("requests", pending_key, _request_key)
		pending.save("user://boblox_pending.cfg")
	_order_id = ""
	if is_instance_valid(_dialog): _dialog.queue_free()
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Покупка в Bobux"
	_dialog.ok_button_text = "Перейти к оплате"
	_dialog.cancel_button_text = "Закрыть"
	_dialog.dialog_hide_on_ok = false
	add_child(_dialog)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = minf(410, get_viewport_rect().size.x - 64)
	content.add_theme_constant_override("separation", 14)
	_dialog.add_child(content)
	var title: String = str(product.get("name", "%d Boblox" % int(product.get("amount", 0))))
	content.add_child(_label(title, 23))
	content.add_child(_label("К оплате: %s ₽" % _rubles(product.price_kopecks), 20, GREEN))
	if product.has("daily"):
		content.add_child(_label("%d Boblox каждый день в течение 30 дней. Без автосписаний." % int(product.daily), 15))
	_email = LineEdit.new()
	_email.placeholder_text = "Email для чека"
	_email.custom_minimum_size.y = 38
	content.add_child(_email)
	var terms := str(catalog.get("terms_url", ""))
	if terms.begins_with("https://"):
		var link := _button("Условия покупки и возврата", false)
		link.pressed.connect(func(): OS.shell_open(terms))
		content.add_child(link)
	_consent = CheckBox.new()
	_consent.text = "Согласен с условиями покупки"
	content.add_child(_consent)
	_dialog_status = _label("", 14, MUTED)
	content.add_child(_dialog_status)
	_check_button = _button("Проверить оплату")
	_check_button.hide()
	_check_button.pressed.connect(func(): _check_order(_order_id))
	content.add_child(_check_button)
	_consent.toggled.connect(func(_value: bool): _update_checkout_button())
	_email.text_changed.connect(func(_value: String): _update_checkout_button())
	_dialog.confirmed.connect(_checkout)
	var can_buy := bool(catalog.get("sales_enabled", false)) and UserSession.is_logged_in and not preview_only
	_dialog_status.text = "Продажи ещё не открыты. Деньги не списываются." if not can_buy else "Тестовый платёж: настоящие деньги не списываются." if catalog.get("test", false) else "Данные карты вводятся только на странице платёжного сервиса."
	_update_checkout_button()
	_dialog.popup_centered()

func _update_checkout_button() -> void:
	var email := _email.text.strip_edges()
	_dialog.get_ok_button().disabled = _busy or preview_only or not UserSession.is_logged_in or not catalog.get("sales_enabled", false) or not _consent.button_pressed or not ("@" in email and "." in email)

func _checkout() -> void:
	if _busy: return
	_busy = true
	_update_checkout_button()
	_dialog_status.text = "Создаём заказ…"
	var response: Dictionary = await CloudAPI.create_boblox_checkout(str(_chosen.id), _request_key, _email.text.strip_edges())
	if not is_inside_tree() or UserSession.user_id != _session_id: return
	_busy = false
	if not response.get("ok", false):
		_dialog_status.text = _error(response)
		_update_checkout_button()
		return
	var order: Dictionary = _payload(response).get("order", {})
	_order_id = str(order.get("id", ""))
	var url := str(order.get("confirmation_url", ""))
	if str(order.get("status", "")) == "succeeded" or str(order.get("status", "")) == "canceled":
		_clear_request_key(str(_chosen.id))
		_dialog_status.text = _status_text(str(order.status))
	elif _safe_payment_url(url):
		var open_error := OS.shell_open(url)
		_dialog_status.text = "Страница оплаты открыта. После оплаты нажмите «Проверить оплату»." if open_error == OK else "Не удалось открыть браузер. Повторите попытку."
	else:
		_dialog_status.text = "Страница оплаты пока не получена. Повторите проверку."
	_check_button.visible = not _order_id.is_empty()
	_update_checkout_button()
	await refresh()

func _check_order(id: String) -> void:
	if _busy or id.is_empty(): return
	_busy = true
	if is_instance_valid(_check_button): _check_button.disabled = true
	if is_instance_valid(_dialog_status): _dialog_status.text = "Проверяем оплату…"
	var response: Dictionary = await CloudAPI.refresh_boblox_order(id)
	if not is_inside_tree() or UserSession.user_id != _session_id: return
	_busy = false
	if is_instance_valid(_check_button): _check_button.disabled = false
	if response.get("ok", false):
		var data := _payload(response)
		var state := str(data.get("order", {}).get("status", "pending"))
		_set_account(data.get("account", {}))
		if is_instance_valid(_dialog_status): _dialog_status.text = _status_text(state)
		if state in ["succeeded", "canceled"]:
			_clear_request_key(str(data.get("order", {}).get("product_id", "")))
	else:
		_notice.text = _error(response)
		if is_instance_valid(_dialog_status): _dialog_status.text = _error(response)
	if is_instance_valid(_dialog): _update_checkout_button()
	_render()

func _clear_request_key(product_id: String) -> void:
	var config := ConfigFile.new()
	config.load("user://boblox_pending.cfg")
	config.erase_section_key("requests", "%s:%s" % [_session_id, product_id])
	config.save("user://boblox_pending.cfg")

static func _safe_payment_url(url: String) -> bool:
	if not url.begins_with("https://"): return false
	var host := url.trim_prefix("https://").split("/")[0].to_lower()
	return host == "yookassa.ru" or host.ends_with(".yookassa.ru") or host == "yoomoney.ru" or host.ends_with(".yoomoney.ru")

static func _payload(response: Dictionary) -> Dictionary:
	var data: Variant = response.get("data", response)
	return data if data is Dictionary else {}

static func _error(response: Dictionary) -> String:
	var data := _payload(response)
	return str(data.get("error", response.get("error", "Не удалось связаться с сервером. Повторите попытку.")))

static func _status_text(state: String) -> String:
	return {"creating": "Создаётся заказ", "pending": "Ожидает оплаты", "waiting_for_capture": "Обрабатывается", "succeeded": "Оплачено", "canceled": "Отменено"}.get(state, state)

static func _date(ms: int) -> String:
	return Time.get_datetime_string_from_unix_time(ms / 1000).replace("T", " ").substr(0, 16) + " UTC"

static func _rubles(kopecks: Variant) -> String:
	return str(int(kopecks) / 100) if int(kopecks) % 100 == 0 else "%.2f" % (float(kopecks) / 100.0)

static func _label(text: String, font_size := 16, color := INK, centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

static func _icon(path: String, pixels: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

static func _style(color: Color, padding := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#dddddd")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func _button(text: String, primary := true) -> Button:
	var button := Button.new()
	button.set_meta("classic_flat", true)
	button.text = text
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color("#777777"))
	button.add_theme_stylebox_override("normal", _style(GREEN if primary else Color("#f8f8f8"), 9))
	button.add_theme_stylebox_override("hover", _style(Color("#007620") if primary else Color("#e9eef1"), 9))
	button.add_theme_stylebox_override("pressed", _style(Color("#00651d") if primary else Color("#dde9f1"), 9))
	button.add_theme_stylebox_override("disabled", _style(Color("#eeeeee"), 9))
	return button
