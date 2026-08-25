extends SceneTree


func _initialize() -> void:
	print("[diagnose_studio_startup] loading")
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	print("[diagnose_studio_startup] loaded=%s" % str(packed != null))
	if packed == null:
		quit(1)
		return
	var studio := packed.instantiate()
	print("[diagnose_studio_startup] instantiated")
	get_root().add_child(studio)
	print("[diagnose_studio_startup] added")
	await process_frame
	print("[diagnose_studio_startup] frame1")
	await process_frame
	print("[diagnose_studio_startup] frame2")
	studio.free()
	quit(0)
