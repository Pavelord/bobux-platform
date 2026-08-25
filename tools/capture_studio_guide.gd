extends SceneTree

const CAPTURE_PATH := "user://studio_guide.png"


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[capture_studio_guide] Studio scene is unavailable")
		quit(1)
		return
	var studio := packed.instantiate() as Control
	root.add_child(studio)
	for _frame_index in range(8):
		await process_frame
	studio.call("_open_studio_user_guide")
	for _frame_index in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(CAPTURE_PATH) != OK:
		push_error("[capture_studio_guide] Failed to save capture")
		quit(1)
		return
	print("[capture_studio_guide] Capture saved")
	quit(0)
