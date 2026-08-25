extends SceneTree

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
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
	if hub.custom_minimum_size.x < 720.0 or hub.custom_minimum_size.y < 480.0:
		push_error("[validate_creation_hub] CreationHub minimum size is below the supported desktop window")
		quit(1)
		return
	var page_host := hub.find_child("CreatorPageHost", true, false) as Control
	if page_host == null or page_host.get_child_count() == 0:
		push_error("[validate_creation_hub] Dashboard page was not created")
		quit(1)
		return

	var required_signals := ["create_game_requested", "create_model_requested", "create_avatar_item_requested", "catalog_requested", "home_requested"]
	for signal_name in required_signals:
		if not hub.has_signal(signal_name):
			push_error("[validate_creation_hub] Missing signal %s" % signal_name)
			quit(1)
			return

	hub.call("_show_guide")
	await process_frame
	var guide_text := _find_first_rich_text(hub)
	if guide_text == null or guide_text.text.length() < 300:
		push_error("[validate_creation_hub] Built-in Studio guide is missing or too short")
		quit(1)
		return

	root.size = Vector2i(800, 600)
	hub.set("_compact_layout", true)
	hub.call("_show_guide")
	await process_frame
	if _find_first_option_button(hub) == null:
		push_error("[validate_creation_hub] Compact guide navigation was not created")
		quit(1)
		return

	print("[validate_creation_hub] CreationHub runtime OK")
	quit(0)


func _find_first_rich_text(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node as RichTextLabel
	for child in node.get_children():
		var found := _find_first_rich_text(child)
		if found != null:
			return found
	return null


func _find_first_option_button(node: Node) -> OptionButton:
	if node is OptionButton:
		return node as OptionButton
	for child in node.get_children():
		var found := _find_first_option_button(child)
		if found != null:
			return found
	return null
