extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	await studio._start_studio_playtest()
	await process_frame
	var buttons: Dictionary = studio.get("studio_test_control_buttons")
	var play := buttons.get("Play") as Button
	var pause := buttons.get("Pause") as Button
	var stop := buttons.get("Stop") as Button
	var record := buttons.get("Record") as Button
	var controls_locked := play != null and pause != null and stop != null and record != null
	controls_locked = controls_locked and play.disabled and pause.disabled and not stop.disabled and record.disabled
	var player := studio.get("studio_playtest_player") as CharacterBody3D
	var method_available := player != null and player.has_method("handle_embedded_playtest_pointer_input")
	var pivot := player.get_node_or_null("CameraPivot") as Node3D if player != null else null
	var before := pivot.rotation if pivot != null else Vector3.ZERO
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	studio._on_studio_viewport_gui_input(press)
	var dragging_after_press := bool(player.get("_embedded_camera_dragging")) if player != null else false
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120.0, 36.0)
	studio._on_studio_viewport_gui_input(motion)
	var after_motion := pivot.rotation if pivot != null else Vector3.ZERO
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	studio._on_studio_viewport_gui_input(release)
	var camera_moved := pivot != null and not after_motion.is_equal_approx(before)
	await studio._stop_studio_playtest()
	await process_frame
	var restored := not play.disabled and pause.disabled and stop.disabled and not record.disabled
	var ok := controls_locked and camera_moved and restored
	print("[validate_studio_playtest_input_lock] ok=%s locked=%s camera=%s restored=%s before=%s after=%s dragging=%s method=%s" % [str(ok), str(controls_locked), str(camera_moved), str(restored), str(before), str(after_motion), str(dragging_after_press), str(method_available)])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
