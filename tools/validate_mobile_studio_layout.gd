extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		push_error("[validate_mobile_studio_layout] Studio scene failed to load")
		quit(1)
		return
	var studio := packed.instantiate()
	studio.set("mobile_studio_force_runtime_for_tests", true)
	root.add_child(studio)
	await process_frame
	await process_frame
	await process_frame

	var action_panel := studio.get("mobile_studio_action_panel") as Control
	var toolbox := studio.get("toolbox_dock_panel") as Control
	var right_dock := studio.get("right_side") as Control
	var viewport_container := studio.get("viewport_container_node") as Control
	var camera := studio.get("camera") as Camera3D
	var old_rotation := camera.rotation if camera != null else Vector3.ZERO
	var no_look_overlay := studio.find_child("StudioLookArea", true, false) == null
	var scrolls_present := (
		studio.find_child("MenuBarScroll", true, false) != null
		and studio.find_child("RibbonToolsScroll", true, false) != null
	)
	var compact_panels := toolbox != null and not toolbox.visible and right_dock != null and not right_dock.visible
	var actions_present := action_panel != null and action_panel.visible
	var joystick_owns_one_touch := false
	if studio.get("mobile_studio_joystick_base") != null:
		var joystick_base := studio.get("mobile_studio_joystick_base") as Control
		var joystick_press := InputEventScreenTouch.new()
		joystick_press.index = 11
		joystick_press.position = joystick_base.size * Vector2(0.8, 0.5)
		joystick_press.pressed = true
		studio.call("_on_mobile_studio_joystick_input", joystick_press)
		var moving_before_other_release: Vector2 = studio.get("mobile_studio_move_vector")
		var unrelated_release := InputEventScreenTouch.new()
		unrelated_release.index = 12
		unrelated_release.position = Vector2.ZERO
		unrelated_release.pressed = false
		studio.call("_on_mobile_studio_joystick_input", unrelated_release)
		var moving_after_other_release: Vector2 = studio.get("mobile_studio_move_vector")
		joystick_press.pressed = false
		studio.call("_on_mobile_studio_joystick_input", joystick_press)
		var stopped_after_owner_release: Vector2 = studio.get("mobile_studio_move_vector")
		joystick_owns_one_touch = (
			moving_before_other_release.length() > 0.1
			and moving_after_other_release.is_equal_approx(moving_before_other_release)
			and stopped_after_owner_release.is_zero_approx()
		)

	if viewport_container != null:
		var touch := InputEventScreenTouch.new()
		touch.index = 3
		touch.position = viewport_container.size * 0.55
		touch.pressed = true
		studio.call("_handle_mobile_studio_viewport_input", touch)
		var drag := InputEventScreenDrag.new()
		drag.index = 3
		drag.position = touch.position + Vector2(80.0, 36.0)
		drag.relative = Vector2(80.0, 36.0)
		studio.call("_handle_mobile_studio_viewport_input", drag)
		touch.position = drag.position
		touch.pressed = false
		studio.call("_handle_mobile_studio_viewport_input", touch)
	await process_frame
	var touch_rotates_camera := camera != null and not camera.rotation.is_equal_approx(old_rotation)

	studio.call("_toggle_mobile_studio_panel", "explorer")
	await process_frame
	var explorer_open := right_dock != null and right_dock.visible
	studio.call("_toggle_mobile_studio_panel", "toolbox")
	await process_frame
	var toolbox_exclusive := (
		toolbox != null and toolbox.visible
		and right_dock != null and not right_dock.visible
	)

	var ok := (
		actions_present
		and compact_panels
		and no_look_overlay
		and scrolls_present
		and touch_rotates_camera
		and explorer_open
		and toolbox_exclusive
		and joystick_owns_one_touch
	)
	print(
		"[validate_mobile_studio_layout] ok=%s actions=%s compact=%s no_overlay=%s scrolls=%s rotate=%s explorer=%s toolbox=%s joystick_owner=%s"
		% [ok, actions_present, compact_panels, no_look_overlay, scrolls_present, touch_rotates_camera, explorer_open, toolbox_exclusive, joystick_owns_one_touch]
	)
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
