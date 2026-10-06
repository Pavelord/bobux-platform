extends RefCounted
## Mirrors image properties added or changed by running Roblox scripts.
## Uses the importer's stable image loader and renderer without changing it.
const Gui = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")

static func sync_image(control: Control, props: Dictionary) -> void:
	var key := hash([props.get("Image", ""), props.get("ImageRectSize"), props.get("ImageRectOffset"), props.get("ImageColor3"), props.get("ImageTransparency"), props.get("ScaleType")])
	if control.get_meta("bobux_live_image_key", -1) == key:
		return
	control.set_meta("bobux_live_image_key", key)
	for child in control.get_children():
		if child.name == "RobloxImage":
			control.remove_child(child)
			child.queue_free()
	var texture := Gui._load_gui_image_texture(props)
	if texture != null:
		Gui._attach_texture_child(control, texture, props)
