extends PanelContainer
const UI := preload("res://scripts/lobby/boblox_shop.gd")
var _friends: VBoxContainer
var _feed: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _status: Label
var _input: LineEdit
var _send: Button
var _older: Button
var _peer := ""
var _generation := 0
var _loading := false
var _sending := false
var _friends_loading := false
var _first := 0
var _last := 0
var _request_id := ""
var _request_text := ""
var _search: LineEdit
var _empty: Label

func _ready() -> void:
	add_theme_stylebox_override("panel", UI._style(Color.WHITE, 0))
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 0)
	add_child(page)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UI._style(Color.WHITE, 18))
	page.add_child(header)
	var heading := HBoxContainer.new()
	header.add_child(heading)
	var title := UI._label("Messages", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var refresh := UI._button("Обновить", false)
	refresh.pressed.connect(refresh_friends)
	heading.add_child(refresh)
	var rule := ColorRect.new()
	rule.color = Color("#00a2e8")
	rule.custom_minimum_size.y = 3
	page.add_child(rule)
	var row := BoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	page.add_child(row)
	var contacts := PanelContainer.new()
	contacts.add_theme_stylebox_override("panel", UI._style(Color("#f5f5f5"), 12))
	row.add_child(contacts)
	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 12)
	contacts.add_child(sidebar)
	sidebar.add_child(UI._label("Друзья", 18))
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск друга"
	_search.custom_minimum_size.y = 34
	_search.text_changed.connect(func(query: String):
		for child in _friends.get_children(): child.visible = query.to_lower() in str(child.get_meta("username", "")).to_lower()
	)
	sidebar.add_child(_search)
	var friends_scroll := ScrollContainer.new()
	friends_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(friends_scroll)
	_friends = VBoxContainer.new()
	_friends.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends.add_theme_constant_override("separation", 3)
	friends_scroll.add_child(_friends)
	var conversation_panel := PanelContainer.new()
	conversation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conversation_panel.add_theme_stylebox_override("panel", UI._style(Color.WHITE, 18))
	row.add_child(conversation_panel)
	var conversation := VBoxContainer.new()
	conversation.add_theme_constant_override("separation", 12)
	conversation_panel.add_child(conversation)
	_title = UI._label("Личные сообщения", 22)
	conversation.add_child(_title)
	conversation.add_child(HSeparator.new())
	_older = UI._button("Ранее в переписке", false)
	_older.hide()
	_older.pressed.connect(func(): _refresh_history(true))
	conversation.add_child(_older)
	_empty = UI._label("Общайтесь с друзьями\nВыбери друга в списке, чтобы открыть вашу переписку.", 18, UI.MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.hide()
	conversation.add_child(_scroll)
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.add_theme_constant_override("separation", 12)
	_scroll.add_child(_feed)
	_status = UI._label("Личные сообщения доступны между друзьями.", 13, UI.MUTED)
	conversation.add_child(_status)
	conversation.add_child(HSeparator.new())
	var compose := HBoxContainer.new()
	compose.add_theme_constant_override("separation", 10)
	conversation.add_child(compose)
	_input = LineEdit.new()
	_input.name = "MessageInput"
	_input.placeholder_text = "Напиши сообщение…"
	_input.max_length = 2000
	_input.custom_minimum_size.y = 40
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.editable = false
	_input.text_submitted.connect(func(_text: String): _send_message())
	compose.add_child(_input)
	_send = UI._button("Отправить")
	_send.name = "SendMessage"
	_send.disabled = true
	_send.add_theme_stylebox_override("normal", UI._style(Color("#00a2e8"), 10))
	_send.pressed.connect(_send_message)
	compose.add_child(_send)
	for field in [_input, _search]:
		field.add_theme_stylebox_override("normal", UI._style(Color.WHITE, 8))
		field.add_theme_stylebox_override("focus", UI._style(Color("#f3faff"), 8))
		field.add_theme_stylebox_override("read_only", UI._style(Color("#f5f5f5"), 8))
		field.add_theme_color_override("font_color", Color("#333333"))
		field.add_theme_color_override("font_placeholder_color", Color("#999999"))
	var resize := func():
		row.vertical = size.x < 650
		contacts.custom_minimum_size = Vector2(0, 160) if row.vertical else Vector2(240, 0)
		friends_scroll.custom_minimum_size.y = 60 if row.vertical else 0
	resized.connect(resize)
	resize.call()
	var timer := Timer.new()
	timer.wait_time = 5
	timer.timeout.connect(func():
		if is_visible_in_tree() and not _peer.is_empty(): _refresh_history()
	)
	add_child(timer)
	timer.start()

func refresh_friends() -> void:
	if _friends_loading: return
	_friends_loading = true
	var result: Dictionary = await CloudAPI.get_friends_list()
	if not is_inside_tree(): return
	_friends_loading = false
	if not result.get("ok", false):
		_status.text = "Не удалось загрузить друзей. Войди в аккаунт и повтори."
		return
	for child in _friends.get_children(): _friends.remove_child(child); child.queue_free()
	for friend in result.get("data", []):
		if not friend is Dictionary: continue
		var peer := str(friend.get("id", friend.get("user_id", "")))
		var username := str(friend.get("username", "Friend"))
		var button := UI._button("", false)
		button.set_meta("username", username)
		button.set_meta("peer", peer)
		button.toggle_mode = true
		button.button_pressed = peer == _peer
		button.custom_minimum_size.y = 54
		button.add_theme_stylebox_override("normal", UI._style(Color("#f5f5f5"), 8))
		button.add_theme_stylebox_override("pressed", UI._style(Color("#dceef8"), 8))
		var label := UI._label(username, 15)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 14
		label.offset_right = -10
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		button.clip_text = true
		button.tooltip_text = username
		button.pressed.connect(func(): _select_peer(peer, username))
		_friends.add_child(button)
	if _friends.get_child_count() == 0: _status.text = "Добавь друга во вкладке Friends, чтобы начать общение."

func _select_peer(peer: String, username: String) -> void:
	_generation += 1
	_peer = peer
	_first = 0
	_last = 0
	_loading = false
	_input.clear()
	_request_id = ""
	_title.text = username
	_empty.hide()
	_scroll.show()
	for button in _friends.get_children(): button.set_pressed_no_signal(str(button.get_meta("peer", "")) == peer)
	_input.editable = true
	_send.disabled = _sending
	_older.hide()
	for child in _feed.get_children(): _feed.remove_child(child); child.queue_free()
	_refresh_history()

func _refresh_history(older := false) -> void:
	if _loading or _peer.is_empty(): return
	_loading = true
	var generation := _generation
	var was_at_bottom := _scroll.scroll_vertical + _scroll.size.y >= _scroll.get_v_scroll_bar().max_value - 40
	var result: Dictionary = await CloudAPI.get_direct_messages(_peer, _first if older else 0, 0 if older else _last)
	if not is_inside_tree() or generation != _generation: return
	_loading = false
	if not result.get("ok", false):
		_status.text = "Переписка недоступна. Проверь подключение и статус дружбы; сервер должен поддерживать сообщения."
		return
	var data := UI._payload(result)
	var initial := _last == 0
	if initial or older: _older.visible = data.get("has_more", false)
	var insert_at := 0
	for message in data.get("messages", []):
		var seq := int(message.get("seq", 0))
		if _feed.has_node("Message%d" % seq): continue
		var panel := PanelContainer.new()
		panel.name = "Message%d" % seq
		var mine := str(message.get("sender", "")) == UserSession.user_id
		panel.add_theme_stylebox_override("panel", UI._style(Color("#f3faff") if mine else Color("#fafafa"), 14))
		_feed.add_child(panel)
		if older: _feed.move_child(panel, insert_at); insert_at += 1
		var content := VBoxContainer.new()
		panel.add_child(content)
		var stamp := Time.get_datetime_string_from_unix_time(int(message.get("created_ms", 0)) / 1000).replace("T", " ").substr(0, 16)
		content.add_child(UI._label(("Ты" if mine else _title.text) + " · " + stamp + " UTC", 13, Color("#0076b4")))
		content.add_child(UI._label(str(message.get("body", "")), 16))
		_first = mini(_first, seq) if _first > 0 else seq
		_last = maxi(_last, seq)
	_status.text = "Сообщения сохраняются на сервере." if _last > 0 else "Начни разговор."
	if not older and (initial or was_at_bottom):
		await get_tree().process_frame
		if is_inside_tree() and generation == _generation: _scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _send_message() -> void:
	if _sending or _peer.is_empty() or _input.text.strip_edges().is_empty(): return
	var body := _input.text.strip_edges()
	if _request_id.is_empty() or body != _request_text:
		_request_id = Crypto.new().generate_random_bytes(16).hex_encode()
		_request_text = body
	var generation := _generation
	_sending = true
	_send.disabled = true
	var result: Dictionary = await CloudAPI.send_direct_message(_peer, body, _request_id)
	if not is_inside_tree(): return
	_sending = false
	_send.disabled = _peer.is_empty()
	if generation != _generation: return
	if result.get("ok", false):
		if _input.text.strip_edges() == body: _input.clear()
		_request_id = ""
		_refresh_history()
	else:
		_status.text = "Не отправлено. Текст сохранён — повтори попытку."
