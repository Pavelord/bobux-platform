extends Node
## Device preferences, independent of account/map data.
const PATH := "user://client_preferences.cfg"
const DEFAULTS := {"volume": 1.0, "mouse_sensitivity": 1.0, "invert_y": false, "fullscreen": false, "vsync": true}
var config_path := PATH
var values := DEFAULTS.duplicate()

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		for key in DEFAULTS:
			values[key] = _validated(key, config.get_value("client", key, DEFAULTS[key]))
	apply()

func _validated(key: String, value: Variant) -> Variant:
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

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(values.volume, 0.0001)))
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	if not OS.has_feature("mobile"):
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired: DisplayServer.window_set_mode(desired)
