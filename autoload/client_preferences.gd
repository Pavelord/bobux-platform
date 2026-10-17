extends Node
## Device preferences, independent of account/map data.
const PATH := "user://client_preferences.cfg"
signal changed(key: String, value: Variant)
const DEFAULTS := {"volume": 1.0, "mouse_sensitivity": 1.0, "invert_y": false, "fullscreen": false, "vsync": true, "app_theme": "halloween", "hud_style": "classic", "interface_animations": true}
var config_path := PATH
var values := DEFAULTS.duplicate()
var _applied_window_icon_path := ""

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		for key in DEFAULTS:
			values[key] = _validated(key, config.get_value("client", key, DEFAULTS[key]))
	apply()

func _validated(key: String, value: Variant) -> Variant:
	if key == "app_theme": return value if value is String and value in ["halloween", "classic"] else DEFAULTS[key]
	if key == "hud_style": return value if value is String and value in ["classic", "compact"] else DEFAULTS[key]
	if key == "volume": return clampf(float(value), 0.0, 1.0) if value is float or value is int else 1.0
	if key == "mouse_sensitivity": return clampf(float(value), 0.25, 3.0) if value is float or value is int else 1.0
	return value if value is bool else DEFAULTS[key]

func update(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key): return
	values[key] = _validated(key, value)
	apply()
	var config := ConfigFile.new()
	for setting in values: config.set_value("client", setting, values[setting])
	config.save(config_path)
	changed.emit(key, values[key])

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(values.volume, 0.0001)))
	if DisplayServer.get_name() == "headless": return
	_apply_window_icon()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	if not OS.has_feature("mobile"):
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired: DisplayServer.window_set_mode(desired)

func _apply_window_icon() -> void:
	var path: String = "res://assets/branding/halloween/bobux_app_icon.png" if values.app_theme == "halloween" else "res://icon.svg"
	if path == _applied_window_icon_path: return
	var image: Image
	if FileAccess.file_exists(path + ".import"):
		var texture := load(path) as Texture2D
		if texture != null: image = texture.get_image()
	elif FileAccess.file_exists(path):
		image = Image.new()
		if image.load(path) != OK: image = null
	if image == null or image.is_empty(): return
	DisplayServer.set_icon(image)
	_applied_window_icon_path = path
