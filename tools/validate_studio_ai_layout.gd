extends SceneTree

const CAPTURE_PATH := "user://studio_ai_layout.png"


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1440, 900)
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	studio.call("_show_studio_ai_window")
	await create_timer(0.5).timeout
	var dock := studio.get("studio_ai_dock") as Control
	var prompt := studio.get("studio_ai_prompt_edit") as TextEdit
	var submit := studio.get("studio_ai_submit_button") as Button
	var ok := dock != null and dock.is_visible_in_tree() and prompt != null and prompt.has_focus() and submit != null and submit.text == "Create in Studio"
	var image := root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(CAPTURE_PATH)
	print("[validate_studio_ai_layout] ok=%s capture=%s" % [str(ok), ProjectSettings.globalize_path(CAPTURE_PATH)])
	studio.call("_toggle_tool_window", "toolbox")
	await create_timer(0.3).timeout
	image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png("user://studio_toolbox_layout.png")
	studio.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
