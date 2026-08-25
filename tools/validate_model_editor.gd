extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/model_editor/model_editor.tscn") as PackedScene
	if scene == null:
		push_error("[validate_model_editor] Failed to load ModelEditor scene")
		quit(1)
		return

	var editor := scene.instantiate() as Control
	if editor == null:
		push_error("[validate_model_editor] ModelEditor root is not Control")
		quit(1)
		return

	root.add_child(editor)
	await process_frame
	await process_frame

	if editor.custom_minimum_size.x < 1000.0 or editor.custom_minimum_size.y < 650.0:
		push_error("[validate_model_editor] ModelEditor page size is too small")
		quit(1)
		return

	var required_signals := ["back_requested", "save_requested"]
	for signal_name in required_signals:
		if not editor.has_signal(signal_name):
			push_error("[validate_model_editor] Missing signal %s" % signal_name)
			quit(1)
			return

	var viewport := editor.find_child("ModelEditorWorld", true, false)
	if viewport == null:
		push_error("[validate_model_editor] ModelEditor world was not built")
		quit(1)
		return

	print("[validate_model_editor] ModelEditor runtime OK")
	quit(0)
