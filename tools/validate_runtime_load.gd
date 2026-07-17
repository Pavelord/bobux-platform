extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://scripts/main/main.gd",
		"res://scripts/player/player.gd",
		"res://scripts/vehicles/chaos_car.gd",
		"res://scripts/vehicles/master_car_spawner.gd",
		"res://autoload/cloud_api.gd",
		"res://autoload/user_session.gd",
		"res://autoload/mobile_runtime.gd",
		"res://scripts/lobby/lobby.gd",
		"res://scripts/lobby/avatar_ui.gd",
		"res://scripts/lobby/friends_builder.gd",
		"res://scripts/lobby/games_builder.gd",
		"res://scripts/lobby/profile_builder.gd",
		"res://scripts/creation_hub/creation_hub.gd",
		"res://scripts/model_editor/model_editor.gd",
		"res://scripts/login/login.gd",
		"res://scripts/place_editor/studio.gd",
		"res://scenes/login/login.tscn",
		"res://scenes/lobby/lobby.tscn",
		"res://scenes/creation_hub/creation_hub.tscn",
		"res://scenes/model_editor/model_editor.tscn",
		"res://scenes/main/main.tscn",
		"res://scenes/player/player.tscn",
		"res://scenes/place_editor/studio.tscn"
	]
	var failed := false
	for path in paths:
		var resource := ResourceLoader.load(path)
		if resource == null:
			push_error("[validate_runtime_load] Failed to load %s" % path)
			failed = true
		else:
			print("[validate_runtime_load] Loaded %s" % path)
	quit(1 if failed else 0)
