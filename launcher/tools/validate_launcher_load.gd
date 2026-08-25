extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://scripts/launcher.gd",
		"res://scenes/launcher.tscn"
	]
	var failed := false
	for path in paths:
		var resource := ResourceLoader.load(path)
		if resource == null and not FileAccess.file_exists(path):
			push_error("[validate_launcher_load] Failed to load %s" % path)
			failed = true
		else:
			print("[validate_launcher_load] Loaded %s" % path)
	for asset_path in [
		"res://assets/branding/bobux_logo_ui.png",
		"res://assets/branding/bobux_app_icon.png"
	]:
		if FileAccess.file_exists(asset_path):
			print("[validate_launcher_load] Found %s" % asset_path)
		else:
			push_error("[validate_launcher_load] Missing %s" % asset_path)
			failed = true
	quit(1 if failed else 0)
