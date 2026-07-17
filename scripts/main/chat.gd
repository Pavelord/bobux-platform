extends CanvasLayer

@onready var chat_panel: Panel = $ChatPanel
@onready var chat_container: VBoxContainer = $ChatPanel/Margin/VBox
@onready var message_scroll: ScrollContainer = $ChatPanel/Margin/VBox/ScrollContainer
@onready var message_list: VBoxContainer = $ChatPanel/Margin/VBox/ScrollContainer/MessageList
@onready var chat_input: LineEdit = $ChatPanel/Margin/VBox/ChatInput

var chat_active: bool = false
var chat_visible: bool = false
var _fade_timer: float = 0.0
const FADE_DELAY: float = 10.0
const FADE_ALPHA_IDLE: float = 0.0
const FADE_ALPHA_ACTIVE: float = 1.0
const CHAT_ICON_PATH: String = "res://assets/ui/chat_icon.png"

var toggle_button: Button = null
var notification_dot: ColorRect = null

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"

func _ready() -> void:
	if _is_headless_runtime():
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	chat_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	chat_input.visible = false
	chat_input.keep_editing_on_text_submit = false
	chat_panel.modulate.a = FADE_ALPHA_IDLE
	chat_panel.visible = false
	chat_input.text_submitted.connect(_on_text_submitted)
	chat_input.focus_entered.connect(func() -> void:
		chat_active = true
		chat_visible = true
		chat_panel.visible = true
		chat_panel.modulate.a = FADE_ALPHA_ACTIVE
		_fade_timer = FADE_DELAY
	)
	chat_input.focus_exited.connect(func() -> void:
		chat_active = false
		_fade_timer = FADE_DELAY
	)
	if not NetworkManager.chat_message_received.is_connected(_on_chat_message_received):
		NetworkManager.chat_message_received.connect(_on_chat_message_received)
	_fade_timer = 0.0
	var mobile_runtime = get_node_or_null("/root/MobileRuntime")
	var is_mobile_platform: bool = mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta"))
	var layout_offset: float = 104.0 if is_mobile_platform else 72.0
	_create_toggle_button()
	apply_top_left_layout(layout_offset)

func _create_toggle_button() -> void:
	toggle_button = Button.new()
	toggle_button.text = ""
	var mobile_runtime = get_node_or_null("/root/MobileRuntime")
	var is_mobile_platform: bool = mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta"))
	var btn_size: float = 72.0 if is_mobile_platform else 56.0
	var x_pos: float = 104.0 if is_mobile_platform else 72.0
	toggle_button.custom_minimum_size = Vector2(btn_size, btn_size)
	toggle_button.position = Vector2(x_pos, 16)
	toggle_button.z_index = 10
	toggle_button.focus_mode = Control.FOCUS_NONE
	var icon_texture := load(CHAT_ICON_PATH) as Texture2D
	if icon_texture != null:
		toggle_button.icon = icon_texture
		toggle_button.expand_icon = true
	else:
		toggle_button.text = "Chat"
	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.75)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.3, 0.85)
	hover_style.corner_radius_top_left = 8
	hover_style.corner_radius_top_right = 8
	hover_style.corner_radius_bottom_right = 8
	hover_style.corner_radius_bottom_left = 8
	toggle_button.add_theme_stylebox_override("normal", style)
	toggle_button.add_theme_stylebox_override("hover", hover_style)
	toggle_button.add_theme_stylebox_override("pressed", hover_style)
	toggle_button.add_theme_font_size_override("font_size", 12)
	toggle_button.pressed.connect(_on_toggle_pressed)
	add_child(toggle_button)

	notification_dot = ColorRect.new()
	notification_dot.name = "ChatNotificationDot"
	notification_dot.visible = false
	notification_dot.color = Color(0.95, 0.1, 0.05, 1.0)
	notification_dot.anchor_left = 1.0
	notification_dot.anchor_right = 1.0
	notification_dot.offset_left = -16.0
	notification_dot.offset_top = 4.0
	notification_dot.offset_right = -4.0
	notification_dot.offset_bottom = 16.0
	toggle_button.add_child(notification_dot)

func apply_top_left_layout(x_offset: float = 72.0) -> void:
	if toggle_button:
		toggle_button.position = Vector2(x_offset, 16)
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_right = 0.0
	chat_panel.anchor_top = 0.0
	chat_panel.anchor_bottom = 0.0
	chat_panel.offset_left = x_offset
	chat_panel.offset_top = 64.0
	chat_panel.offset_right = x_offset + 320.0
	chat_panel.offset_bottom = 248.0

func _on_toggle_pressed() -> void:
	var next_visible := not chat_visible
	if next_visible:
		var main_node := get_tree().current_scene
		if main_node and main_node.has_method("close_game_menu"):
			main_node.call("close_game_menu")
	set_chat_visible_state(next_visible, false)
	if next_visible and notification_dot:
		notification_dot.hide()

func _process(delta: float) -> void:
	if not chat_visible:
		return
	if chat_active:
		return
	if _fade_timer > 0.0:
		_fade_timer -= delta
		if _fade_timer <= 0.0:
			_fade_timer = 0.0
	var target_alpha: float = FADE_ALPHA_ACTIVE if _fade_timer > 0.0 else FADE_ALPHA_IDLE
	chat_panel.modulate.a = lerpf(chat_panel.modulate.a, target_alpha, 4.0 * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if not chat_active and not chat_input.has_focus():
			var main_node := get_tree().current_scene
			if main_node and main_node.has_method("close_game_menu"):
				main_node.call("close_game_menu")
			set_chat_visible_state(true, true)
			get_viewport().set_input_as_handled()

func _on_text_submitted(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		set_chat_visible_state(true, false)
		return
	var username: String = UserSession.username if UserSession.is_logged_in else "Player"
	var msg: String = "[%s]: %s" % [username, clean_text]
	NetworkManager.broadcast_message(msg)
	# Trigger chat bubble on our player
	_trigger_chat_bubble(clean_text)
	chat_input.text = ""
	set_chat_visible_state(true, false)
	_fade_timer = FADE_DELAY
	get_viewport().set_input_as_handled()

func _trigger_chat_bubble(text: String) -> void:
	var main_node = get_tree().current_scene
	if main_node == null:
		return
	var players_node = main_node.get_node_or_null("World/Players")
	if players_node == null:
		return
	var my_id_int: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	if my_id_int <= 0:
		return
	var my_player = players_node.get_node_or_null(str(my_id_int))
	# AUDIT FIX VULN-2: Route chat bubbles through the server-side relay
	# instead of calling rpc("show_chat_bubble") directly. This lets the
	# server validate content length and enforce rate-limiting.
	if my_player and my_player.has_method("request_chat_bubble_local"):
		my_player.call("request_chat_bubble_local", text)
	elif main_node.has_method("_relay_chat_bubble_to_server"):
		main_node.call("_relay_chat_bubble_to_server", my_id_int, text)

func _on_chat_message_received(msg: String, _sender_id: int) -> void:
	var label := Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_list.add_child(label)
	# BUGFIX: show a clear new-message indicator when chat is closed.
	if not chat_visible and notification_dot:
		notification_dot.show()
	chat_panel.modulate.a = FADE_ALPHA_ACTIVE
	_fade_timer = FADE_DELAY
	await get_tree().process_frame
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
	while message_list.get_child_count() > 50:
		message_list.get_child(0).queue_free()

func close_chat_panel() -> void:
	set_chat_visible_state(false, false)

func set_chat_visible_state(should_show: bool, focus_input: bool) -> void:
	chat_visible = should_show
	chat_panel.visible = should_show
	if should_show:
		if notification_dot:
			notification_dot.hide()
		chat_panel.modulate.a = FADE_ALPHA_ACTIVE
		_fade_timer = FADE_DELAY
		chat_active = focus_input
		chat_input.visible = true
		if focus_input:
			chat_input.grab_focus()
			chat_input.text = ""
		else:
			chat_input.release_focus()
	else:
		chat_active = false
		chat_input.visible = false
		chat_input.release_focus()
