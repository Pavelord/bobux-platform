extends SceneTree
var failures: Array[String] = []
var complete_count := 0
var skipped_count := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[update_trailer] ", label_, "=", ok)
	if not ok: failures.append(label_)
func run() -> void:
	await process_frame
	var trailer: Node = root.get_node("UpdateTrailer")
	trailer.seen_path = "user://validation/update_trailer_seen.json"
	trailer._seen.clear()
	check(not trailer.has_seen("premiere-probe-a"), "new release has not been acknowledged")
	if DisplayServer.get_name() == "headless":
		check(not trailer.maybe_play_first_visit("premiere-probe-a"), "server/headless never starts a premiere")
		trailer._remember_seen("premiere-probe-a")
		trailer._load_seen()
		check(trailer.has_seen("premiere-probe-a") and not trailer.has_seen("premiere-probe-b"), "acknowledgement survives restart and remains account-specific")
	else:
		root.size = Vector2i(960, 540)
		root.content_scale_size = root.size
		var lobby := Control.new()
		lobby.name = "TrailerValidationLobby"
		var preview := SubViewport.new()
		preview.size = Vector2i(64, 64)
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		lobby.add_child(preview)
		root.add_child(lobby)
		current_scene = lobby
		trailer.finished.connect(func(completed: bool):
			if completed: complete_count += 1
			else: skipped_count += 1)
		preload("res://scripts/ui/startup_connection_banner.gd").begin(self)
		check(trailer.maybe_play_first_visit("premiere-probe-a"), "first authenticated visit starts premiere")
		check(not trailer.play_trailer(true), "rapid repeated clicks cannot create overlapping decoders")
		await create_timer(0.3).timeout
		check(trailer._video.stream == null, "premiere consumes no frames or audio behind the connection splash")
		preload("res://scripts/ui/startup_connection_banner.gd").finish(self)
		while root.get_node_or_null("StartupConnectionBanner") != null: await process_frame
		await create_timer(1.5).timeout
		check(trailer._video != null and trailer._video.is_playing() and trailer._video.stream_position > 0.5, "real Theora decoder advances with audio")
		check(not lobby.visible and preview.render_target_update_mode == SubViewport.UPDATE_DISABLED, "covered lobby and avatar viewports do not render behind video")
		check(trailer._cover.color.a < 0.01, "opening black screen fades away")
		var rect: Rect2 = trailer._video.get_global_rect()
		check(is_equal_approx(rect.size.x / rect.size.y, 16.0 / 9.0), "video preserves its aspect ratio")
		var started := Time.get_ticks_msec()
		if OS.get_cmdline_user_args().has("--trailer-short-probe"):
			trailer._finish(true, true)
		while trailer.is_active() and Time.get_ticks_msec() - started < 38000:
			await create_timer(0.25).timeout
		check(not trailer.is_active() and complete_count == 1, "complete 30 second playback returns to lobby exactly once")
		check(lobby.visible and lobby.process_mode == Node.PROCESS_MODE_INHERIT and preview.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "lobby rendering and input state restore after premiere")
		trailer._load_seen()
		check(trailer.has_seen("premiere-probe-a") and not trailer.has_seen("premiere-probe-b"), "successful viewing persists for this account only")
		check(not trailer.maybe_play_first_visit("premiere-probe-a"), "returning from a mode does not replay the premiere")
		check(trailer.play_trailer(true, "premiere-probe-a"), "replay remains available after viewing")
		await create_timer(1.5).timeout
		trailer._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		var paused_position: float = trailer._video.stream_position
		await create_timer(0.35).timeout
		check(is_equal_approx(paused_position, trailer._video.stream_position), "backgrounding pauses the decoder instead of consuming the premiere")
		trailer._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		root.size = Vector2i(400, 740)
		root.content_scale_size = root.size
		await process_frame
		await process_frame
		rect = trailer._video.get_global_rect()
		check(rect.size.x <= 400.1 and is_equal_approx(rect.size.x / rect.size.y, 16.0 / 9.0), "portrait resizing letterboxes without cropping")
		var point: Vector2 = trailer._skip.get_global_rect().get_center()
		for pressed in [true, false]:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = point
			mouse.pressed = pressed
			root.push_input(mouse, true)
			await process_frame
		await create_timer(1.0).timeout
		check(not trailer.is_active() and skipped_count == 1 and lobby.visible, "skip click closes replay and restores lobby")
		lobby.queue_free()
	if FileAccess.file_exists(trailer.seen_path): DirAccess.remove_absolute(trailer.seen_path)
	await process_frame
	await root.get_node("GameSceneLoader").get_lobby()
	print("UPDATE_TRAILER_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures, "completed": complete_count, "skipped": skipped_count}))
	quit(0 if failures.is_empty() else 1)
