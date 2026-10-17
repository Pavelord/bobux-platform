extends Node
## Ownership and dates come from the API. No client clock can unlock rewards.
const CATALOG := preload("res://scripts/lobby/catalog_builder.gd")
const RENDERER := preload("res://scripts/lobby/catalog_thumbnail_renderer.gd")
const PUMPKIN_ID := "event_halloween_2026_pumpkin"
const ACK_PATH := "user://events/halloween2026_seen.json"
var _timer: Timer
var _in_flight := false
var _account := ""
var _dialog: CanvasLayer
var _dialog_user := ""
var _seen: Dictionary = {}
var _state: Dictionary = {}
var _auth_elapsed := 0.0
var _watched_user := ""
var _pending_greeting: Dictionary = {}
var _pending_greeting_user := ""

func _ready() -> void:
	var trailer := get_node_or_null("/root/UpdateTrailer")
	if trailer != null and trailer.has_signal("finished"): trailer.connect("finished", _after_trailer)
	if FileAccess.file_exists(ACK_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACK_PATH))
		if saved is Dictionary: _seen = saved
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--performance-probe"):
		set_process(false)
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start(5)

func _process(delta: float) -> void:
	if _timer == null: return
	_auth_elapsed += delta
	if _auth_elapsed < 5: return
	_auth_elapsed = 0
	var user_id := UserSession.user_id if UserSession.is_logged_in and CloudAPI.has_authenticated_session() else ""
	if user_id != _watched_user:
		_watched_user = user_id
		_timer.start(0.1)

func _poll() -> void:
	if _in_flight: return
	var user_id := UserSession.user_id if UserSession.is_logged_in and CloudAPI.has_authenticated_session() else ""
	if _account != user_id:
		_account = user_id
		_state.clear()
		if is_instance_valid(_dialog): _dialog.queue_free()
	if user_id.is_empty():
		_timer.start(5)
		return
	_in_flight = true
	var response: Dictionary = await CloudAPI.fetch_halloween_event()
	_in_flight = false
	if user_id != UserSession.user_id or not UserSession.is_logged_in:
		_timer.start(5)
		return
	if bool(response.get("ok", false)) and response.get("data") is Dictionary:
		_state = response.data
		consume_state(_state, user_id)
		# Schedule against the server instant, including the exact Moscow boundary.
		var seconds := _timestamp(_state.get("reward_at", "")) - _timestamp(_state.get("server_time", ""))
		_timer.start(clampf(seconds + 1, 5, 3600) if seconds > 0 else 3600)
	else:
		# Network failures stay in the background; no login/profile loading cover.
		_timer.start(60)

static func _timestamp(value: Variant) -> float:
	var text := str(value).trim_suffix("Z").get_slice(".", 0)
	return Time.get_unix_time_from_datetime_string(text) if not text.is_empty() else 0

func consume_state(state: Dictionary, user_id: String) -> void:
	if user_id.is_empty() or str(state.get("event_id", "")) != "halloween_2026": return
	var now := _timestamp(state.get("server_time", ""))
	var reward_at := _timestamp(state.get("reward_at", ""))
	if reward_at <= 0 or now < reward_at: return
	var trailer := get_node_or_null("/root/UpdateTrailer")
	if trailer != null and trailer.has_method("is_active") and trailer.call("is_active"):
		_pending_greeting = state.duplicate(true)
		_pending_greeting_user = user_id
		return
	var pumpkin: Dictionary = {}
	for raw in state.get("items", []):
		if raw is Dictionary and str(raw.get("id", "")) == PUMPKIN_ID and bool(state.get("pumpkin_owned", false)):
			pumpkin = raw.duplicate(true)
			pumpkin["owned"] = true
			if user_id == UserSession.user_id: _remember_owned(pumpkin)
	var key := user_id.sha256_text()
	if bool(_seen.get(key, false)) or is_instance_valid(_dialog): return
	_show_dialog(user_id, pumpkin)

func _after_trailer(_completed: bool) -> void:
	var state := _pending_greeting
	var account := _pending_greeting_user
	_pending_greeting = {}
	_pending_greeting_user = ""
	if not state.is_empty() and account == UserSession.user_id and UserSession.is_logged_in: consume_state(state, account)

func _remember_owned(item: Dictionary) -> void:
	if not UserSession.inventory_items.has(PUMPKIN_ID): UserSession.inventory_items.append(PUMPKIN_ID)
	var payloads: Array = UserSession.avatar_data.get("owned_avatar_item_payloads", []).duplicate(true)
	payloads = payloads.filter(func(value): return not value is Dictionary or str(value.get("id", "")) != PUMPKIN_ID)
	payloads.push_front(item.duplicate(true))
	UserSession.avatar_data["owned_avatar_item_payloads"] = payloads
	UserSession.save_profile()

func _show_dialog(user_id: String, pumpkin: Dictionary) -> void:
	_dialog_user = user_id
	_dialog = CanvasLayer.new()
	_dialog.name = "HalloweenGreeting"
	_dialog.layer = 110
	add_child(_dialog)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202026")
	style.border_color = Color("c67832")
	style.set_border_width_all(2)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "С Хеллоуином!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("ff9b3d"))
	box.add_child(title)
	var description := Label.new()
	description.text = "Желаем весёлого Хеллоуина в Бобуксе!" if pumpkin.is_empty() else "Вот вам светящаяся тыква Pumpkin! Аксессуар Halloween 2026 уже в вашем инвентаре."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("ffd8b3"))
	box.add_child(description)
	if not pumpkin.is_empty():
		var preview := TextureRect.new()
		preview.name = "PumpkinPreview"
		preview.custom_minimum_size.y = 168
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(preview)
		var renderer := RENDERER.new()
		_dialog.add_child(renderer)
		renderer.request_preview(pumpkin, preview)
		var badge_row := CenterContainer.new()
		badge_row.add_child(CATALOG.limited_badge(true))
		box.add_child(badge_row)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var scene := get_tree().current_scene
	if not pumpkin.is_empty() and scene != null and scene.has_method("_refresh_all_local_avatar_previews_from_session"):
		var wear := Button.new()
		wear.name = "WearPumpkin"
		wear.text = "Надеть"
		wear.custom_minimum_size = Vector2(120, 44)
		wear.pressed.connect(func():
			if UserSession.user_id == user_id:
				_equip(pumpkin, scene)
			_acknowledge()
		)
		actions.add_child(wear)
	var close := Button.new()
	close.name = "CloseGreeting"
	close.text = "Отлично!"
	close.custom_minimum_size = Vector2(120, 44)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(_acknowledge)
	actions.add_child(close)
	var resize := func(): panel.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x - 32, 240, 440)
	get_viewport().size_changed.connect(resize)
	panel.tree_exiting.connect(func():
		if get_viewport().size_changed.is_connected(resize): get_viewport().size_changed.disconnect(resize)
	)
	resize.call()

func _equip(item: Dictionary, lobby: Node) -> void:
	_remember_owned(item)
	var equipped: Array = UserSession.avatar_data.get("equipped", []).duplicate()
	if not equipped.has(PUMPKIN_ID): equipped.append(PUMPKIN_ID)
	UserSession.avatar_data["equipped"] = equipped
	var payloads: Array = UserSession.avatar_data.get("equipped_avatar_item_payloads", []).duplicate(true)
	payloads = payloads.filter(func(value): return not value is Dictionary or str(value.get("id", "")) != PUMPKIN_ID)
	payloads.append(item.duplicate(true))
	UserSession.avatar_data["equipped_avatar_item_payloads"] = payloads
	UserSession.apply_avatar_to_game_state()
	UserSession.save_profile()
	var avatar_ui: Variant = lobby.get("avatar_ui")
	if avatar_ui != null and avatar_ui.has_method("reload_cloud_inventory"): avatar_ui.reload_cloud_inventory()
	lobby.call("_refresh_all_local_avatar_previews_from_session")
	lobby.call("_queue_avatar_cloud_sync")

func _acknowledge() -> void:
	_seen[_dialog_user.sha256_text()] = true
	DirAccess.make_dir_recursive_absolute("user://events")
	var file := FileAccess.open(ACK_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_seen))
		file.close()
	if is_instance_valid(_dialog):
		remove_child(_dialog)
		_dialog.queue_free()
	_dialog = null
