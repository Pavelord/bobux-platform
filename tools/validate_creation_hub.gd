extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/creation_hub/creation_hub.tscn") as PackedScene
	if scene == null:
		push_error("[validate_creation_hub] Failed to load CreationHub scene")
		quit(1)
		return

	var hub := scene.instantiate() as Control
	if hub == null:
		push_error("[validate_creation_hub] CreationHub root is not Control")
		quit(1)
		return

	root.add_child(hub)
	await process_frame

	if hub.get_child_count() == 0:
		push_error("[validate_creation_hub] CreationHub did not build page content")
		quit(1)
		return
	if hub.custom_minimum_size.x < 900.0 or hub.custom_minimum_size.y < 600.0:
		push_error("[validate_creation_hub] CreationHub page size is too small")
		quit(1)
		return

	var required_signals := ["create_game_requested", "create_model_requested", "create_avatar_item_requested", "catalog_requested", "home_requested"]
	for signal_name in required_signals:
		if not hub.has_signal(signal_name):
			push_error("[validate_creation_hub] Missing signal %s" % signal_name)
			quit(1)
			return

	print("[validate_creation_hub] CreationHub runtime OK")
	quit(0)
