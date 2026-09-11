extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var prefs := root.get_node("ClientPreferences")
	var original: Dictionary = prefs.values.duplicate()
	var original_path: String = prefs.config_path
	prefs.config_path = "user://client_preferences_validation.cfg"
	prefs.update("volume", 0.37)
	prefs.update("mouse_sensitivity", 2.0)
	prefs.update("invert_y", true)
	var config := ConfigFile.new()
	var saved := config.load(prefs.config_path) == OK and is_equal_approx(config.get_value("client", "volume", 0), 0.37)
	var dialog := load("res://scripts/lobby/client_settings.gd").new() as Control
	root.add_child(dialog)
	await process_frame
	var slider := dialog.find_child("volume", true, false) as HSlider
	var shown := slider != null and is_equal_approx(slider.value, 37.0)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest",true)
	root.add_child(player)
	player.set_physics_process(false)
	var pivot := player.get_node("CameraPivot") as Node3D
	pivot.rotation = Vector3.ZERO
	player._apply_camera_rotation_delta(0.1, 0.1)
	var camera_ok := is_equal_approx(pivot.rotation.y,-0.2) and is_equal_approx(pivot.rotation.x,0.2)
	prefs.update("mouse_sensitivity",100.0)
	var clamped: bool = prefs.values.mouse_sensitivity == 3.0
	# Restore real device state; tests only write their own temporary config.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs.config_path))
	prefs.config_path = original_path
	prefs.values = original
	prefs.apply()
	dialog.queue_free(); player.queue_free()
	await process_frame
	print("[client_preferences] saved=",saved," UI=",shown," camera=",camera_ok," bounds=",clamped)
	quit(0 if saved and shown and camera_ok and clamped else 1)
