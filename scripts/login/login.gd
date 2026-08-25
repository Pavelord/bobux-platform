extends Control

const LOGO_TEXTURE_PATH: String = "res://assets/branding/bobux_logo_ui.png"
const BACKGROUND_TEXTURE_PATH: String = "res://assets/branding/login_background.png"

var username_input: LineEdit = null
var password_input: LineEdit = null
var login_button: Button = null
var signup_button: Button = null
var status_label: Label = null
var _auto_login_in_flight: bool = false

func _ready() -> void:
	_disable_mobile_gameplay_controls()
	_build_login_screen()
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	if mobile_runtime != null and mobile_runtime.has_method("check_for_updates"):
		mobile_runtime.call_deferred("check_for_updates", true)
	login_button.pressed.connect(_on_login)
	signup_button.pressed.connect(_on_signup)
	status_label.text = ""

	var remembered_username: String = UserSession.get_last_profile_username()
	if not remembered_username.is_empty():
		username_input.text = remembered_username
		username_input.caret_column = username_input.text.length()

	status_label.text = "Preparing login..."
	status_label.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42, 1.0))
	call_deferred("_try_restore_saved_session", remembered_username)

func _try_restore_saved_session(remembered_username: String) -> void:
	if _auto_login_in_flight:
		return
	_auto_login_in_flight = true
	await get_tree().process_frame
	status_label.text = "Checking saved session..."
	var auth_result: Dictionary = await CloudAPI.ensure_authenticated_session()
	if not _auto_login_in_flight:
		return
	if bool(auth_result.get("ok", false)):
		status_label.text = "Loading your profile..."
		var session_username: String = CloudAPI.get_current_username()
		var preferred_username: String = session_username if not session_username.is_empty() else remembered_username
		var profile_result: Dictionary = await CloudAPI.authenticate_or_create_profile(preferred_username)
		if not _auto_login_in_flight:
			return
		if bool(profile_result.get("ok", false)):
			UserSession.begin_cloud_session(CloudAPI.get_current_user_id(), str(profile_result.get("username", preferred_username)).strip_edges())
			_go_to_lobby()
			return

	status_label.text = "Sign in to continue."
	status_label.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42, 1.0))
	_auto_login_in_flight = false

func _build_login_screen() -> void:
	for child in get_children():
		child.queue_free()
	var mobile_beta: bool = _is_mobile_beta()

	var background := TextureRect.new()
	background.name = "Background"
	background.texture = _load_image_texture(BACKGROUND_TEXTURE_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.name = "Atmosphere"
	shade.color = Color(0.02, 0.05, 0.07, 0.16)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var logo := TextureRect.new()
	logo.name = "BobuxLogo"
	logo.texture = _load_image_texture(LOGO_TEXTURE_PATH)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if mobile_beta:
		var viewport_size: Vector2 = get_viewport_rect().size
		var logo_width: float = clampf(viewport_size.x * 0.34, 250.0, 520.0)
		var logo_height: float = clampf(viewport_size.y * 0.18, 96.0, 160.0)
		logo.anchor_left = 0.5
		logo.anchor_top = 0.0
		logo.anchor_right = 0.5
		logo.anchor_bottom = 0.0
		logo.offset_left = -logo_width * 0.5
		logo.offset_top = 18.0
		logo.offset_right = logo_width * 0.5
		logo.offset_bottom = 18.0 + logo_height
	else:
		logo.anchor_left = 0.39
		logo.anchor_top = 0.045
		logo.anchor_right = 0.985
		logo.anchor_bottom = 0.36
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var slogan := Label.new()
	slogan.text = "Play, build, and race with friends"
	if mobile_beta:
		slogan.anchor_left = 0.5
		slogan.anchor_top = 0.0
		slogan.anchor_right = 0.5
		slogan.anchor_bottom = 0.0
		slogan.offset_left = -360.0
		slogan.offset_top = 168.0
		slogan.offset_right = 360.0
		slogan.offset_bottom = 210.0
	else:
		slogan.anchor_left = 0.52
		slogan.anchor_top = 0.39
		slogan.anchor_right = 0.94
		slogan.anchor_bottom = 0.48
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.add_theme_font_size_override("font_size", 21 if mobile_beta else 24)
	slogan.add_theme_color_override("font_color", Color.WHITE)
	slogan.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	slogan.add_theme_constant_override("shadow_offset_y", 3)
	slogan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slogan)

	var card := Panel.new()
	card.name = "LoginCard"
	if mobile_beta:
		var viewport_size: Vector2 = get_viewport_rect().size
		var card_width: float = clampf(viewport_size.x * 0.58, 460.0, 780.0)
		var card_height: float = clampf(viewport_size.y * 0.46, 320.0, 430.0)
		card.anchor_left = 0.5
		card.anchor_top = 0.5
		card.anchor_right = 0.5
		card.anchor_bottom = 0.5
		card.offset_left = -card_width * 0.5
		card.offset_top = -card_height * 0.38
		card.offset_right = card_width * 0.5
		card.offset_bottom = -card_height * 0.38 + card_height
	else:
		card.anchor_left = 0.06
		card.anchor_top = 0.18
		card.anchor_right = 0.38
		card.anchor_bottom = 0.82
	card.add_theme_stylebox_override("panel", _make_card_style())
	add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24 if mobile_beta else 34)
	margin.add_theme_constant_override("margin_top", 20 if mobile_beta else 30)
	margin.add_theme_constant_override("margin_right", 24 if mobile_beta else 34)
	margin.add_theme_constant_override("margin_bottom", 20 if mobile_beta else 28)
	card.add_child(margin)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 11 if mobile_beta else 16)
	margin.add_child(form)

	var title := Label.new()
	title.text = "WELCOME TO BOBUX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24 if mobile_beta else 26)
	title.add_theme_color_override("font_color", Color(0.12, 0.14, 0.16, 1.0))
	form.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Mobile beta: friends and places are ready. Studio stays on PC." if mobile_beta else "Log in or create an account to continue."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48, 1.0))
	form.add_child(subtitle)

	username_input = _make_input("Username")
	username_input.name = "UsernameInput"
	form.add_child(username_input)

	password_input = _make_input("Password")
	password_input.name = "PasswordInput"
	password_input.secret = true
	form.add_child(password_input)

	login_button = _make_primary_button("Log In")
	login_button.name = "LoginButton"
	form.add_child(login_button)

	signup_button = _make_secondary_button("Create Account")
	signup_button.name = "SignupButton"
	form.add_child(signup_button)

	status_label = Label.new()
	status_label.name = "LoginStatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	form.add_child(status_label)

	var footer := Label.new()
	footer.text = "Bobux is an online multiplayer game. Published worlds are loaded from the cloud."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6, 1.0))
	form.add_child(footer)

func _load_image_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture != null:
		return texture
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _make_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.94)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.82, 0.84, 0.86, 1)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 8)
	return style


func _is_mobile_beta() -> bool:
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))


func _disable_mobile_gameplay_controls() -> void:
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	if mobile_runtime != null and mobile_runtime.has_method("disable_gameplay_touch_controls"):
		mobile_runtime.call("disable_gameplay_touch_controls")

func _make_input(placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.custom_minimum_size = Vector2(0, 46)
	input.placeholder_text = placeholder
	input.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 1))
	input.add_theme_color_override("font_placeholder_color", Color(0.62, 0.62, 0.62, 1))
	input.add_theme_stylebox_override("normal", _make_input_style())
	input.add_theme_stylebox_override("focus", _make_input_focus_style())
	return input

func _make_input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.68, 0.68, 0.68, 1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

func _make_input_focus_style() -> StyleBoxFlat:
	var style := _make_input_style()
	style.border_color = Color(0.0, 0.47, 0.74, 1)
	style.border_width_bottom = 2
	return style

func _make_primary_button(button_text: String) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.0, 0.70, 0.31, 1)))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.0, 0.78, 0.36, 1)))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.0, 0.58, 0.27, 1)))
	return button

func _make_secondary_button(button_text: String) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.12, 0.14, 0.16, 1))
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.92, 0.93, 0.94, 1), Color(0.68, 0.7, 0.72, 1)))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.97, 0.98, 0.99, 1), Color(0.55, 0.57, 0.6, 1)))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.84, 0.86, 0.88, 1), Color(0.55, 0.57, 0.6, 1)))
	return button

func _make_button_style(bg: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	if border.a > 0.0:
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = border
	return style

func _on_login() -> void:
	Analytics.log_button_click("login")
	_auto_login_in_flight = false
	var uname: String = username_input.text.strip_edges()
	var pwd: String = password_input.text
	_set_inputs_enabled(false)
	status_label.text = "Signing in..."
	status_label.add_theme_color_override("font_color", Color(0.22, 0.32, 0.42, 1))
	CloudAPI.reset_authenticated_session(true)
	var result: Dictionary = await CloudAPI.sign_in_with_credentials(uname, pwd)
	if bool(result.get("ok", false)):
		_go_to_lobby()
	else:
		_set_inputs_enabled(true)
		status_label.text = str(result.get("error", "Invalid username or password."))
		status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

func _on_signup() -> void:
	Analytics.log_button_click("signup")
	_auto_login_in_flight = false
	var uname: String = username_input.text.strip_edges()
	var pwd: String = password_input.text
	if uname.length() < 3:
		status_label.text = "Username must be at least 3 characters."
		status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		return
	if pwd.strip_edges().length() < 6:
		status_label.text = "Password must be at least 6 characters."
		status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		return
	_set_inputs_enabled(false)
	status_label.text = "Creating account..."
	status_label.add_theme_color_override("font_color", Color(0.22, 0.32, 0.42, 1))
	CloudAPI.reset_authenticated_session(true)
	var result: Dictionary = await CloudAPI.sign_up_with_credentials(uname, pwd)
	if bool(result.get("ok", false)):
		_go_to_lobby()
	else:
		_set_inputs_enabled(true)
		status_label.text = str(result.get("error", "Could not create account."))
		status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

func _set_inputs_enabled(enabled: bool) -> void:
	username_input.editable = enabled
	password_input.editable = enabled
	login_button.disabled = not enabled
	signup_button.disabled = not enabled

func _go_to_lobby() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/lobby/lobby.tscn")
	queue_free()
