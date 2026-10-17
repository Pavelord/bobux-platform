extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("launcher/theme", "halloween")
	var launcher = load("res://tools/fixtures/recovery_launcher.gd").new()
	root.add_child(launcher)
	var folder := OS.get_user_data_dir().path_join("recovery_contract_%d" % OS.get_process_id())
	launcher._install_root = folder
	launcher._game_dir = folder.path_join("Game")
	launcher._temp_dir = folder.path_join("_download")
	launcher._staging_dir = folder.path_join("_staging_game")
	launcher._launcher_staging_dir = folder.path_join("_staging_launcher")
	for path in [launcher._game_dir.path_join("Bobux.exe"), folder.path_join("session/profile.json"), launcher._temp_dir.path_join("game.zip.part"), launcher._staging_dir.path_join("partial.bin"), launcher._launcher_staging_dir.path_join("partial.bin")]:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("preserve or retry fixture")
		file.close()
	launcher._progress_bar.value = 66.0
	launcher._fail("HTTP status=404")
	assert(launcher._retry_available and launcher._recovery_menu.visible)
	assert(not launcher._recovery_menu.disabled)
	assert(is_equal_approx(launcher._progress_bar.value, 66.0), "Failure must not reset completed progress")
	assert(launcher._recovery_menu.get_popup().get_item_count() == 4)
	launcher._on_action_pressed()
	assert(launcher.restart_calls == 1 and not launcher._force_reinstall, "Retry keeps the normal resumable flow")
	launcher._on_recovery_selected(1)
	assert(launcher.restart_calls == 2 and launcher._force_reinstall)
	assert(FileAccess.file_exists(launcher._temp_dir.path_join("game.zip.part")), "Reinstall preserves reusable download")
	launcher._update_flow_running = true
	launcher._on_recovery_selected(2)
	assert(launcher.restart_calls == 2 and DirAccess.dir_exists_absolute(launcher._temp_dir), "No recovery mutation during an update")
	launcher._update_flow_running = false
	launcher._on_recovery_selected(2)
	assert(launcher.restart_calls == 3)
	for path in [launcher._temp_dir, launcher._staging_dir, launcher._launcher_staging_dir]:
		assert(not DirAccess.dir_exists_absolute(path), "Explicit start-over clears only update artifacts")
	assert(FileAccess.file_exists(launcher._game_dir.path_join("Bobux.exe")))
	assert(FileAccess.file_exists(folder.path_join("session/profile.json")))
	launcher._cancel_requested = true
	launcher._fail("Update paused. Press Retry to continue.")
	assert(not launcher._recovery_menu.visible and launcher._action_button.text == "Продолжить")
	launcher._delete_recursive_absolute(folder)
	launcher.queue_free()
	print("LAUNCHER_RECOVERY_OPTIONS_OK: Retry, cached reinstall, explicit restart, running guard, profile/install preservation, pause")
	quit(0)
