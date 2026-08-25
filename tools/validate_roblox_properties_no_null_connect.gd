extends SceneTree


func _initialize() -> void:
	var properties_script: Script = load("res://addons/roblox_studio/roblox_properties.gd")
	if properties_script == null:
		push_error("Could not load RobloxProperties")
		quit(1)
		return
	var builder = properties_script.new()
	var container := VBoxContainer.new()
	get_root().add_child(container)
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.set_meta("roblox_class", "Part")
	part.set_meta("block_name", "ValidationPart")
	get_root().add_child(part)
	builder.build_into(container, part, get_root())
	print("RobloxProperties null-callable validation OK rows=%d" % container.get_child_count())
	container.queue_free()
	part.queue_free()
	await process_frame
	quit(0)
