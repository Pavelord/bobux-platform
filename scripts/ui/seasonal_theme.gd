extends Node
## Seasonal app chrome. Author-created place interfaces are deliberately outside
## this controller: it mounts on login/lobby/settings, never on the world root.
## Every replacement keeps its local override so switching back is lossless.

const BACKDROP := preload("res://scripts/ui/seasonal_backdrop.gd")
const PAGE := Color("121216")
const SURFACE := Color("202026")
const RAISED := Color("2a2524")
const EDGE := Color("514032")
const ACCENT := Color("ff9b3d")
const TEXT := Color("ffc18a")
const MUTED := Color("c99c77")
const ICON_ROOT := "res://assets/ui/halloween/"
const COLOR_KEYS := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_placeholder_color", "font_selected_color", "font_unselected_color", "font_hovered_color", "default_color", "caret_color", "selection_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]
const NAV_ICONS := {"NavHomeBtn": "home", "NavProfileBtn": "profile", "NavMessagesBtn": "messages", "NavFriendsBtn": "friends", "NavCharacterBtn": "avatar", "NavInventoryBtn": "inventory", "NavTradeBtn": "trade", "NavGroupsBtn": "groups", "NavForumBtn": "forum", "NavBlogBtn": "blog", "NavPromocodesBtn": "promocodes", "NavRobux": "wallet", "HeaderSettings": "settings", "HeaderNavigation": "menu", "HeaderPurchases": "inventory", "HeaderBobloxBalance": "wallet", "LogoutBtn": "logout", "UpgradeBtn": "moon"}
static var _textures: Dictionary = {}

var _surface: Control
var _records: Dictionary = {}
var _windows: Dictionary = {}
var _pending: Dictionary = {}
var _original_theme: Theme
var _theme: Theme
var _enabled := false
var _applying := false
var _backdrop: Control
var _home_banner: Control

static func preferences() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("ClientPreferences") if tree != null else null

static func is_halloween() -> bool:
	var prefs := preferences()
	return prefs == null or str(prefs.get("values").get("app_theme", "halloween")) == "halloween"

static func color(token: String, classic: Color) -> Color:
	if not is_halloween(): return classic
	return {"page": PAGE, "surface": SURFACE, "edge": EDGE, "accent": ACCENT, "text": TEXT, "muted": MUTED}.get(token, classic)

static func texture(kind: String) -> Texture2D:
	var is_logo := kind in ["logo", "header_logo", "login_logo"]
	var path := "res://assets/branding/halloween/bobux_logo_ui.png" if is_logo else "res://assets/branding/halloween/bobux_app_icon.png"
	if not is_halloween() or (not ResourceLoader.exists(path) and not FileAccess.file_exists(path)):
		path = "res://assets/branding/bobux_logo_ui.png" if is_logo else "res://icon.svg"
	var result := _load_texture(path)
	if kind in ["header_logo", "login_logo"] and is_halloween() and result != null:
		if _textures.has(kind): return _textures[kind] as Texture2D
		# The supplied wordmark has a square glow canvas. Crop its display
		# region for a short header without rewriting any supplied pixels.
		var atlas := AtlasTexture.new()
		atlas.atlas = result
		atlas.region = Rect2(0, result.get_height() * (0.15 if kind == "login_logo" else 0.35), result.get_width(), result.get_height() * (0.65 if kind == "login_logo" else 0.32))
		_textures[kind] = atlas
		return atlas
	return result

static func _load_texture(path: String) -> Texture2D:
	if _textures.has(path): return _textures[path] as Texture2D
	var result: Texture2D
	if path.ends_with(".svg") and FileAccess.file_exists(path):
		# Source SVGs remain reviewable without a project-wide editor import.
		# Exported textures still use their imported ResourceLoader remap below.
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path)) == OK: result = ImageTexture.create_from_image(image)
	elif FileAccess.file_exists(path + ".import"):
		result = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK: result = ImageTexture.create_from_image(image)
	if result != null: _textures[path] = result
	return result

static func mount(surface: Control) -> Node:
	var current: Node = surface
	while current != null:
		var existing := current.get_node_or_null("SeasonalTheme")
		if existing != null: return existing
		current = current.get_parent()
	var controller: Node = load("res://scripts/ui/seasonal_theme.gd").new()
	controller.name = "SeasonalTheme"
	controller.set("_surface", surface)
	surface.add_child(controller)
	return controller

func _ready() -> void:
	_original_theme = _surface.theme
	_theme = _make_theme()
	get_tree().node_added.connect(_on_node_added)
	var prefs := preferences()
	if prefs != null and prefs.has_signal("changed"):
		prefs.connect("changed", _preference_changed)
	_backdrop = BACKDROP.new()
	_backdrop.name = "HalloweenAtmosphere"
	_backdrop.set_meta("seasonal_ignore", true)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.add_child(_backdrop)
	_surface.move_child(_backdrop, 0)
	_install_home_banner()
	refresh()

func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added): tree.node_added.disconnect(_on_node_added)

func _preference_changed(key: String, _value: Variant) -> void:
	if key == "app_theme": refresh()
	if key == "interface_animations" and is_instance_valid(_backdrop): _backdrop.call("update_animation_setting")

func refresh() -> void:
	_enabled = is_halloween()
	_applying = true
	_surface.theme = _theme if _enabled else _original_theme
	_backdrop.visible = _enabled
	if is_instance_valid(_home_banner): _home_banner.visible = _enabled
	_backdrop.call("update_animation_setting")
	_applying = false
	_visit(_surface)
	_surface.queue_redraw()
	var sidebar := _surface.get_node_or_null("Body/HBox/Sidebar") as Control
	if sidebar != null: sidebar.queue_redraw()

func _install_home_banner() -> void:
	var content := _surface.get_node_or_null("Body/HBox/MainTabs/HomeView/Content") as Container
	if content == null: return
	# Let native containers measure wrapped text after their real width is
	# assigned. Copying a MarginContainer's transient minimum height into a
	# plain Panel locked the first narrow/zero-width wrap into a giant banner.
	_home_banner = PanelContainer.new()
	_home_banner.name = "HalloweenWelcome"
	_home_banner.set_meta("seasonal_ignore", true)
	_home_banner.custom_minimum_size.y = 108
	_home_banner.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2b211d")
	style.border_color = Color("785139")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_home_banner.add_theme_stylebox_override("panel", style)
	content.add_child(_home_banner)
	content.move_child(_home_banner, mini(1, content.get_child_count() - 1))
	var embers: Control = BACKDROP.new()
	embers.set("paint_background", false)
	embers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home_banner.add_child(embers)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 18)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 13)
	_home_banner.add_child(margin)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)
	var mark := TextureRect.new()
	mark.texture = texture("icon")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(64, 68)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	for entry in [["HALLOWEEN · 2026", 11, MUTED], ["Хеллоуин в Bobux", 21, ACCENT], ["Загляни в каталог за праздничным подарком.", 13, TEXT]]:
		var label := Label.new()
		label.text = entry[0]
		label.add_theme_font_size_override("font_size", entry[1])
		label.add_theme_color_override("font_color", entry[2])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	var action := Button.new()
	action.name = "HalloweenCatalogOpen"
	action.text = "В каталог  →"
	action.custom_minimum_size = Vector2(134, 44)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for key in ["normal", "hover", "pressed"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("4e3021") if key == "normal" else Color("684128")
		button_style.border_color = ACCENT.darkened(0.3)
		button_style.set_border_width_all(1)
		button_style.set_corner_radius_all(3)
		action.add_theme_stylebox_override(key, button_style)
	action.add_theme_color_override("font_color", ACCENT)
	action.pressed.connect(func():
		_surface.call("_switch_tab", 11)
		load("res://scripts/lobby/catalog_builder.gd").open_halloween(_surface))
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(action)
	var replay := Button.new()
	replay.name = "HalloweenTrailerReplay"
	replay.text = "Смотреть трейлер"
	replay.custom_minimum_size = Vector2(134, 44)
	for key in ["normal", "hover", "pressed"]: replay.add_theme_stylebox_override(key, action.get_theme_stylebox(key).duplicate())
	replay.add_theme_color_override("font_color", ACCENT)
	replay.pressed.connect(func():
		var player := _surface.get_node_or_null("/root/UpdateTrailer")
		if player != null and player.has_method("play_trailer"): player.call("play_trailer", true))
	actions.add_child(replay)
	row.add_child(actions)
	var fit_banner := func():
		if not is_instance_valid(_home_banner): return
		row.vertical = _home_banner.size.x < 580
		mark.visible = not row.vertical
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL if row.vertical else Control.SIZE_SHRINK_END
	_home_banner.resized.connect(fit_banner)
	fit_banner.call_deferred()

func _excluded(node: Node) -> bool:
	var current: Node = node
	while current != null and current != _surface:
		if current is SubViewport or current.has_meta("seasonal_ignore") or current.name == "DevelopView" or current.name == "StudioOverlay": return true
		current = current.get_parent()
	return false

func _visit(node: Node) -> void:
	if _excluded(node) or node.is_queued_for_deletion(): return
	if node is Control: _style_control(node as Control)
	elif node is Window: _style_window(node as Window)
	for child in node.get_children(): _visit(child)

func _on_node_added(node: Node) -> void:
	if node is Control and _surface.is_ancestor_of(node) and not _excluded(node):
		if node.is_visible_in_tree(): _style_control(node as Control)
		else: _queue(node as Control)
	elif node is Window and _surface.is_ancestor_of(node) and not _excluded(node): _style_window(node as Window)

func prepare_page(page: Control) -> void:
	# A newly selected tab must be themed before its first visible frame.
	# Only this requested subtree is visited; hidden/background updates retain
	# their bounded queue and the running lobby has no recurring full-tree scan.
	if is_instance_valid(page): _visit(page)

func _style_window(window: Window) -> void:
	if not is_instance_valid(window): return
	var id := window.get_instance_id()
	if not _windows.has(id):
		_windows[id] = {"ref": weakref(window), "theme": window.theme}
		window.tree_exited.connect(func(): _windows.erase(id), CONNECT_ONE_SHOT)
	window.theme = _theme if _enabled else _windows[id].theme

func _queue(control: Control) -> void:
	_pending[control.get_instance_id()] = weakref(control)
	set_process(true)

func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	for id in _pending.keys():
		var control := (_pending[id] as WeakRef).get_ref() as Control
		_pending.erase(id)
		if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion(): _style_control(control)
		if Time.get_ticks_usec() - started > 1800: break
	if _pending.is_empty(): set_process(false)

func _style_changed(control: Control) -> void:
	if not _applying and _enabled and is_instance_valid(control):
		if control.is_visible_in_tree(): _style_control(control)
		else: _queue(control)

func _forget(id: int) -> void:
	# Reparenting briefly exits the tree too. Keep the classic snapshot until
	# the node actually leaves this app surface or has been freed.
	_forget_exited.call_deferred(id)

func _forget_exited(id: int) -> void:
	if not _records.has(id): return
	var control := (_records[id].ref as WeakRef).get_ref() as Control
	if is_instance_valid(control):
		if control.is_inside_tree() and (control == _surface or _surface.is_ancestor_of(control)):
			_queue(control)
			return
		_applying = true
		_restore(control, _records[id])
		_applying = false
		var changed := _style_changed.bind(control)
		if control.theme_changed.is_connected(changed): control.theme_changed.disconnect(changed)
	_records.erase(id)
	_pending.erase(id)

func _style_control(control: Control) -> void:
	if _excluded(control): return
	var id := control.get_instance_id()
	if not _records.has(id):
		_records[id] = {"ref": weakref(control), "original": {}, "applied": {}}
	var changed := _style_changed.bind(control)
	if not control.theme_changed.is_connected(changed): control.theme_changed.connect(changed)
	var exited := _forget.bind(id)
	if not control.tree_exited.is_connected(exited): control.tree_exited.connect(exited, CONNECT_ONE_SHOT)
	var record: Dictionary = _records[id]
	_applying = true
	if not _enabled:
		_restore(control, record)
		_applying = false
		return
	var preserve := bool(control.get_meta("seasonal_preserve_color", false)) or str(control.name).begins_with("BtnColor")
	if not preserve and (control is Label or control is BaseButton or control is LineEdit or control is TextEdit or control is RichTextLabel or control is TabContainer or control is Tree or control is ItemList):
		for key in COLOR_KEYS:
			if key != "font_color" and not control.has_theme_color_override(key): continue
			var tint := MUTED if "disabled" in key or "placeholder" in key or "unselected" in key else TEXT
			if "hover" in key or "focus" in key or "selected" in key or "caret" in key or "icon" in key: tint = ACCENT
			if key == "selection_color": tint = Color(0.65, 0.27, 0.06, 0.55)
			_override_color(control, record, key, tint)
	if not preserve:
		for info in control.get_property_list():
			var property := str(info.name)
			if property.begins_with("theme_override_styles/"):
				var key := property.get_slice("/", 1)
				if control.has_theme_stylebox_override(key): _override_style(control, record, key)
		if control is Panel or control is PanelContainer or control is TabContainer: _override_style(control, record, "panel")
		if control is Button and not control.get_meta("classic_flat", false):
			for key in ["normal", "hover", "pressed", "disabled", "focus"]: _override_style(control, record, key)
	if control is Button and NAV_ICONS.has(str(control.name)):
		var path := ICON_ROOT + str(NAV_ICONS[str(control.name)]) + ".svg"
		var icon := _load_texture(path)
		if icon != null: _override_property(control, record, "icon", icon)
		if str(control.name) in ["HeaderNavigation", "HeaderPurchases"]: _override_property(control, record, "text", "")
	elif control is Button and str(control.name) in ["Nav1", "Nav2"]:
		_override_property(control, record, "icon", null)
	if control is TextureRect:
		var original_texture: Texture2D = control.texture
		if record.original.has("property:texture"): original_texture = record.original["property:texture"]
		if original_texture != null and original_texture.resource_path == "res://assets/branding/bobux_logo_ui.png":
			_override_property(control, record, "texture", texture("header_logo" if str(control.name) == "BobuxLogoTexture" else ("login_logo" if str(control.name) == "BobuxLogo" else "logo")))
		elif original_texture != null and original_texture.resource_path == "res://assets/branding/login_background.png":
			_override_property(control, record, "texture", _load_texture(ICON_ROOT + "login_background.svg"))
	if control is ColorRect and not preserve:
		var original: Color = control.color
		if record.original.has("property:color"): original = record.original["property:color"]
		if original.s < 0.15 or str(control.name) in ["Atmosphere", "LoadingOverlay"]:
			_override_property(control, record, "color", Color(PAGE, original.a) if control.size.y > 8 or original.a < 1 else EDGE)
	_applying = false

func _remember(record: Dictionary, key: String, current: Variant) -> void:
	if not record.original.has(key) or not record.applied.has(key) or current != record.applied[key]: record.original[key] = current

func _override_color(control: Control, record: Dictionary, key: String, value: Color) -> void:
	var current: Variant = control.get_theme_color(key) if control.has_theme_color_override(key) else null
	_remember(record, "color:" + key, current)
	if current != value: control.add_theme_color_override(key, value)
	record.applied["color:" + key] = value

func _override_style(control: Control, record: Dictionary, key: String) -> void:
	var current: Variant = control.get_theme_stylebox(key) if control.has_theme_stylebox_override(key) else null
	_remember(record, "style:" + key, current)
	var base: StyleBox = record.original["style:" + key]
	if base == null: base = _theme.get_stylebox(key, control.get_class())
	if not (base is StyleBoxFlat): return
	if record.applied.has("style:" + key) and current == record.applied["style:" + key]: return
	var styled := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	var original_alpha := styled.bg_color.a
	styled.bg_color = Color(SURFACE, original_alpha)
	if key == "fill": styled.bg_color = Color(ACCENT, original_alpha)
	if key in ["hover", "pressed", "tab_selected", "selected"]: styled.bg_color = Color(RAISED, original_alpha)
	var primary := control is Button and original_alpha > 0.4 and (base as StyleBoxFlat).bg_color.s > 0.45
	if primary:
		styled.bg_color = Color("57311e") if key == "normal" else Color("734123")
		styled.set_border_width_all(maxi(1, styled.border_width_left))
	if control == _surface or control is TabContainer: styled.bg_color = Color(PAGE, original_alpha)
	if str(control.name) == "TopBar": styled.bg_color = Color("18151a")
	styled.border_color = ACCENT.darkened(0.35) if primary or key in ["focus", "pressed", "tab_selected"] else EDGE
	if original_alpha > 0 and not (control is TabContainer):
		# Preserve authored portrait circles and softly rounded cards. A global
		# radius of three flattened every Home/Friends avatar into a square.
		if control is Button and maxi(styled.corner_radius_top_left, styled.corner_radius_top_right) == 0:
			styled.set_corner_radius_all(4)
		if control is Button or control is PanelContainer or control is Panel:
			styled.set_border_width_all(1)
	styled.shadow_color = Color(0, 0, 0, minf(styled.shadow_color.a, 0.24))
	control.add_theme_stylebox_override(key, styled)
	record.applied["style:" + key] = styled

func _override_property(control: Control, record: Dictionary, key: String, value: Variant) -> void:
	_remember(record, "property:" + key, control.get(key))
	if control.get(key) != value: control.set(key, value)
	record.applied["property:" + key] = value

func _restore(control: Control, record: Dictionary) -> void:
	for compound in record.original:
		var category := str(compound).get_slice(":", 0)
		var key := str(compound).get_slice(":", 1)
		var original: Variant = record.original[compound]
		if category == "color":
			if original == null: control.remove_theme_color_override(key)
			else: control.add_theme_color_override(key, original)
		elif category == "style":
			if original == null: control.remove_theme_stylebox_override(key)
			else: control.add_theme_stylebox_override(key, original)
		elif category == "property": control.set(key, original)
	record.applied.clear()

func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	for type in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "LineEdit", "TextEdit", "RichTextLabel", "TabContainer", "PopupMenu", "ItemList", "Tree"]:
		for key in COLOR_KEYS: result.set_color(key, type, MUTED if "disabled" in key or "placeholder" in key else TEXT)
	for type in ["Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "LineEdit", "TextEdit", "PopupMenu", "Panel", "PanelContainer", "TabContainer", "ItemList", "Tree"]:
		for key in ["normal", "hover", "pressed", "disabled", "focus", "panel", "tab_selected", "tab_unselected", "tab_hovered"]:
			var style := StyleBoxFlat.new()
			style.bg_color = RAISED if key in ["hover", "pressed", "tab_selected", "tab_hovered"] else SURFACE
			style.border_color = ACCENT.darkened(0.35) if key in ["focus", "pressed", "tab_selected"] else EDGE
			style.set_border_width_all(1)
			style.set_corner_radius_all(3)
			style.content_margin_left = 10
			style.content_margin_right = 10
			style.content_margin_top = 6
			style.content_margin_bottom = 6
			result.set_stylebox(key, type, style)
	for type in ["HScrollBar", "VScrollBar", "HSlider", "VSlider", "ProgressBar"]:
		for key in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed", "slider", "grabber_area", "grabber_area_highlight", "background", "fill"]:
			var style := StyleBoxFlat.new()
			style.bg_color = ACCENT.darkened(0.24) if key in ["grabber", "grabber_highlight", "grabber_pressed", "fill", "grabber_area_highlight"] else SURFACE
			style.set_corner_radius_all(4)
			style.content_margin_top = 3
			style.content_margin_bottom = 3
			style.content_margin_left = 3
			style.content_margin_right = 3
			result.set_stylebox(key, type, style)
	result.set_icon("checked", "CheckButton", _load_texture(ICON_ROOT + "toggle_on.svg"))
	result.set_icon("unchecked", "CheckButton", _load_texture(ICON_ROOT + "toggle_off.svg"))
	result.set_icon("arrow", "OptionButton", _load_texture(ICON_ROOT + "chevron.svg"))
	return result
