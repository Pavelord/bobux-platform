extends CanvasLayer
## One initial splash; authentication and cached lobby loading continue behind it.
const SEASONAL := preload("res://scripts/ui/seasonal_theme.gd")
const ACTIVE_KEY := "bobux_initial_connection_banner"
const SHOWN_KEY := "bobux_initial_connection_shown"
const MIN_SHOW_MSEC := 900
var _started_msec := 0
var _finishing := false
var _finish_requested := false
var _host: Control
var _logo: TextureRect
var _spinner: TextureRect

static func begin(tree: SceneTree) -> void:
	if tree.root.has_meta(SHOWN_KEY): return
	tree.root.set_meta(SHOWN_KEY, true)
	var banner := load("res://scripts/ui/startup_connection_banner.gd").new() as CanvasLayer
	banner.name = "StartupConnectionBanner"
	tree.root.set_meta(ACTIVE_KEY, weakref(banner))
	# Login._ready runs while SceneTree is still adding its children.
	tree.root.add_child.call_deferred(banner)

static func is_active(tree: SceneTree) -> bool:
	if not tree.root.has_meta(ACTIVE_KEY): return false
	var reference: Variant = tree.root.get_meta(ACTIVE_KEY, null)
	if reference is WeakRef:
		var banner: Node = reference.get_ref()
		return is_instance_valid(banner) and not banner.is_queued_for_deletion()
	return false

static func finish(tree: SceneTree) -> void:
	if not tree.root.has_meta(ACTIVE_KEY): return
	var reference: Variant = tree.root.get_meta(ACTIVE_KEY)
	if reference is WeakRef:
		var banner: Node = reference.get_ref()
		if is_instance_valid(banner): banner.call("_finish_splash")

func _ready() -> void:
	name = "StartupConnectionBanner"
	layer = 250
	_started_msec = Time.get_ticks_msec()
	_host = Control.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_host)
	var background := ColorRect.new()
	background.color = Color("141119") if SEASONAL.is_halloween() else Color("eeeeee")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(background)
	var backdrop := preload("res://scripts/ui/seasonal_backdrop.gd").new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.visible = SEASONAL.is_halloween()
	_host.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 22)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(content)
	_logo = TextureRect.new()
	_logo.name = "StartupHalloweenLogo"
	_logo.texture = SEASONAL.texture("login_logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_logo)
	var label := Label.new()
	label.name = "ConnectionLabel"
	label.text = "Подключение к Бобукс…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", SEASONAL.color("text", Color("363636")))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	var spinner_center := CenterContainer.new()
	spinner_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spinner_center)
	_spinner = TextureRect.new()
	_spinner.texture = SEASONAL.texture("app_icon")
	_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spinner.custom_minimum_size = Vector2(32, 32)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spinner_center.add_child(_spinner)
	_host.resized.connect(_layout_logo)
	_layout_logo()
	# A lost request cannot trap the user indefinitely behind the splash.
	get_tree().create_timer(6.0).timeout.connect(_release_when_usable)
	if _finish_requested: _finish_splash.call_deferred()

func _release_when_usable() -> void:
	var scene := get_tree().current_scene
	# Loading a cached scene is asynchronous. Keep the animated splash rather
	# than revealing an empty clear screen before the scene exists.
	if is_instance_valid(scene) and scene is CanvasItem and scene.visible:
		_finish_splash()
	elif not _finishing:
		get_tree().create_timer(0.25).timeout.connect(_release_when_usable)

func _layout_logo() -> void:
	if not is_instance_valid(_logo): return
	var width := clampf(get_viewport().get_visible_rect().size.x - 56.0, 200.0, 420.0)
	_logo.custom_minimum_size = Vector2(width, width * 0.55)

func _process(delta: float) -> void:
	if is_instance_valid(_spinner):
		_spinner.pivot_offset = _spinner.size * 0.5
		_spinner.rotation += delta * 1.4

func _finish_splash() -> void:
	if not is_inside_tree():
		_finish_requested = true
		return
	if _finishing: return
	_finishing = true
	var remaining: int = maxi(0, MIN_SHOW_MSEC - (Time.get_ticks_msec() - _started_msec))
	if remaining > 0: await get_tree().create_timer(float(remaining) / 1000.0).timeout
	if not is_inside_tree(): return
	var tween := create_tween()
	tween.tween_property(_host, "modulate:a", 0.0, 0.25)
	await tween.finished
	if not is_inside_tree(): return
	if get_tree().root.has_meta(ACTIVE_KEY): get_tree().root.remove_meta(ACTIVE_KEY)
	queue_free()
