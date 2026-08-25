extends SceneTree

const DESKTOP_CAPTURE := "user://creator_hub_desktop.png"
const MOBILE_CAPTURE := "user://creator_hub_mobile_guide.png"


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://scenes/creation_hub/creation_hub.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var hub := packed.instantiate() as Control
	root.add_child(hub)
	for _frame in range(5):
		await process_frame
	var desktop_image := root.get_texture().get_image()
	if desktop_image == null or desktop_image.is_empty() or desktop_image.save_png(DESKTOP_CAPTURE) != OK:
		push_error("[capture_creator_hub] Failed to save desktop capture")
		quit(1)
		return

	root.size = Vector2i(800, 600)
	hub.set("_compact_layout", true)
	hub.call("_show_guide")
	for _frame in range(5):
		await process_frame
	var mobile_image := root.get_texture().get_image()
	if mobile_image == null or mobile_image.is_empty() or mobile_image.save_png(MOBILE_CAPTURE) != OK:
		push_error("[capture_creator_hub] Failed to save compact capture")
		quit(1)
		return
	print("[capture_creator_hub] Captures saved")
	quit(0)
