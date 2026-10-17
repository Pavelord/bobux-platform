extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(760, 430)
	for selection in ["halloween", "classic"]:
		ProjectSettings.set_setting("launcher/theme", selection)
		var launcher = load("res://tools/fixtures/download_launcher.gd").new()
		root.add_child(launcher)
		launcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await create_timer(0.6).timeout
		launcher._set_status("Downloading update...", "", 0.54)
		launcher._set_download_progress(128 * 1024 * 1024, 245 * 1024 * 1024, "game build")
		launcher._action_button.disabled = false
		if selection == "halloween":
			assert(launcher.get_node_or_null("HalloweenBackdrop") != null)
			assert(launcher._cancel_button != null)
			assert(launcher._progress_bar.size.y < 15)
			for control in [launcher._action_button, launcher._cancel_button, launcher._progress_bar, launcher._detail_label]:
				assert(Rect2(Vector2.ZERO, Vector2(760, 430)).encloses(control.get_global_rect()), str(control.name) + " must fit the window")
		else:
			assert(launcher.get_node_or_null("HalloweenBackdrop") == null)
		await process_frame
		await RenderingServer.frame_post_draw
		var output: String = OS.get_user_data_dir().path_join("seasonal_launcher/%s.png" % selection)
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		root.get_texture().get_image().save_png(output)
		print("SEASONAL_LAUNCHER_SCREENSHOT " + output)
		launcher._fail("Не удалось связаться с сервером обновления. HTTP status=503")
		await process_frame
		for control in [launcher._action_button, launcher._recovery_menu, launcher._detail_label]:
			assert(Rect2(Vector2.ZERO, Vector2(760, 430)).encloses(control.get_global_rect()), "Recovery controls must fit " + selection)
		await RenderingServer.frame_post_draw
		var error_output: String = OS.get_user_data_dir().path_join("seasonal_launcher/%s-error.png" % selection)
		root.get_texture().get_image().save_png(error_output)
		print("SEASONAL_LAUNCHER_SCREENSHOT " + error_output)
		launcher.queue_free()
		await process_frame
	print("SEASONAL_LAUNCHER_UI_OK: seasonal design, original design, progress, touch targets")
	quit(0)
