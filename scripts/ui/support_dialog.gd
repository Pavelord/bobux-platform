extends Node
## A voluntary external support page, independent of purchases and currency.
const SUPPORT_URL := "https://www.donationalerts.com/r/bobux_ceo"
const TELEGRAM_URL := "https://t.me/pavelord"
const MENU_ID := 100
var _host: Control
var _popup: CanvasLayer
var _panel: PanelContainer
var _status: Label
var _rainbow: ShaderMaterial
var external_opener: Callable
var _previous_back_quit := true

static func mount(host: Control) -> Node:
	if host.has_node("BobuxSupport"): return host.get_node("BobuxSupport")
	var controller := load("res://scripts/ui/support_dialog.gd").new() as Node
	controller.name = "BobuxSupport"
	controller.set("_host", host)
	host.add_child(controller)
	return controller

func _ready() -> void:
	var sidebar := _host.get_node("Body/HBox/Sidebar")
	var upgrade := sidebar.get_node("UpgradeBtn")
	var holder := PanelContainer.new()
	holder.name = "SupportSidebar"
	holder.custom_minimum_size.y = 44
	holder.set_meta("seasonal_ignore", true)
	var background := ColorRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform bool animated = true; void fragment(){ float t=animated ? TIME*0.12 : 0.0; vec3 c=0.5+0.5*cos(6.28318*(UV.x+t+vec3(0.0,0.333,0.667))); float edge=step(min(min(UV.x,1.0-UV.x)*4.0,min(UV.y,1.0-UV.y)),0.045); COLOR=vec4(mix(c*0.38+vec3(0.07),c*0.85,edge),1.0); }"
	_rainbow = ShaderMaterial.new()
	_rainbow.shader = shader
	background.material = _rainbow
	holder.add_child(background)
	var button := Button.new()
	button.name = "SupportButton"
	button.text = "Поддержать"
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_shadow_color", Color.BLACK)
	button.add_theme_constant_override("shadow_offset_y", 1)
	for state in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(show_dialog)
	holder.add_child(button)
	sidebar.add_child(holder)
	sidebar.move_child(holder, upgrade.get_index())
	var menu := _host.find_child("HeaderNavigation", true, false) as MenuButton
	if menu != null:
		menu.get_popup().add_separator()
		menu.get_popup().add_item("Поддержать", MENU_ID)
		menu.get_popup().id_pressed.connect(func(id: int):
			if id == MENU_ID: show_dialog())
	var preferences := get_node_or_null("/root/ClientPreferences")
	if preferences != null:
		preferences.changed.connect(_preferences_changed)
		_rainbow.set_shader_parameter("animated", bool(preferences.values.get("interface_animations", true)))
	set_process_input(false)

func _preferences_changed(key: String, value: Variant) -> void:
	if key == "interface_animations": _rainbow.set_shader_parameter("animated", bool(value))

func _label(text: String, size: int = 17) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("ffd3ad"))
	return label

func _button(text: String, name: String) -> Button:
	var button := Button.new()
	button.name = name
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("ffd4ae"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("4e3021") if state == "normal" else Color("684128")
		style.border_color = Color("cb8547")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, style)
	return button

func show_dialog() -> void:
	if is_instance_valid(_popup): return
	_previous_back_quit = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	_popup = CanvasLayer.new()
	_popup.name = "BobuxSupportDialog"
	_popup.layer = 190
	add_child(_popup)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(shade)
	_panel = PanelContainer.new()
	_panel.set_meta("seasonal_ignore", true)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("221d25")
	style.border_color = Color("b87335")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 20)
	_panel.add_theme_stylebox_override("panel", style)
	_popup.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "SupportScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	var title := _label("Поддержать Bobux", 25)
	title.add_theme_color_override("font_color", Color("ff9b3d"))
	content.add_child(title)
	content.add_child(_label("Сейчас покупка игровой валюты недоступна. Вы можете поддержать разработку Bobux."))
	var support := _button("Поддержать", "OpenDonationAlerts")
	support.set_meta("external_url", SUPPORT_URL)
	support.pressed.connect(_open_external.bind(SUPPORT_URL))
	content.add_child(support)
	content.add_child(_label("Скриншот поддержки можно отправить в Telegram @pavelord", 15))
	var telegram := _button("Telegram @pavelord", "OpenSupportTelegram")
	telegram.set_meta("external_url", TELEGRAM_URL)
	telegram.pressed.connect(_open_external.bind(TELEGRAM_URL))
	content.add_child(telegram)
	_status = _label("", 14)
	_status.hide()
	content.add_child(_status)
	var close := _button("Закрыть", "CloseSupportDialog")
	close.pressed.connect(close_dialog)
	content.add_child(close)
	get_viewport().size_changed.connect(_fit_dialog)
	_fit_dialog()
	set_process_input(true)
	close.grab_focus()

func _fit_dialog() -> void:
	if not is_instance_valid(_panel): return
	var viewport := get_viewport().get_visible_rect().size
	_panel.size = Vector2(minf(540, maxf(240, viewport.x - 32)), minf(440, maxf(160, viewport.y - 32)))
	_panel.position = (viewport - _panel.size) * 0.5

func _open_external(url: String) -> void:
	var result: Error = external_opener.call(url) if external_opener.is_valid() else OS.shell_open(url)
	if result != OK and is_instance_valid(_status):
		_status.text = "Не удалось открыть ссылку. Попробуйте ещё раз."
		_status.show()

func _input(event: InputEvent) -> void:
	if is_instance_valid(_popup) and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_dialog()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(_popup): close_dialog()

func close_dialog() -> void:
	set_process_input(false)
	get_tree().quit_on_go_back = _previous_back_quit
	if get_viewport().size_changed.is_connected(_fit_dialog): get_viewport().size_changed.disconnect(_fit_dialog)
	if is_instance_valid(_popup): _popup.queue_free()
	_popup = null
	_panel = null

func _exit_tree() -> void:
	if is_instance_valid(_popup) and get_tree() != null: get_tree().quit_on_go_back = _previous_back_quit

