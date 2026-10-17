extends Node
## Bundled update premiere: one successful viewing per account and release.
## Networking remains active; only the covered lobby's rendering is suspended.
signal finished(completed: bool)
const VIDEO_PATH := "res://assets/video/bobux_halloween_2026.ogv"
const RELEASE_ID := "halloween-2026-premiere-57"
const SEEN_PATH := "user://events/update_trailers.json"
const INTRO_FADE := 0.55
const OUTRO_FADE := 0.25
var seen_path := SEEN_PATH
var _seen: Dictionary = {}
var _layer: CanvasLayer
var _screen: Control
var _video: VideoStreamPlayer
var _cover: ColorRect
var _skip: Button
var _transition: Tween
var _scene: WeakRef
var _scene_process_mode := Node.PROCESS_MODE_INHERIT
var _scene_visible := true
var _preview_modes: Array[Dictionary] = []
var _account := ""
var _started := false
var _closing := false
var _suspended := false
var _elapsed := 0.0
var _run := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_seen()
	set_process(false)
	set_process_input(false)

func is_active() -> bool:
	return is_instance_valid(_layer)

func has_seen(user_id: String) -> bool:
	return not user_id.strip_edges().is_empty() and bool(_seen.get(_seen_key(user_id), false))

func maybe_play_first_visit(user_id: String) -> bool:
	if user_id.strip_edges().is_empty() or has_seen(user_id): return false
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"): return false
	if OS.get_cmdline_user_args().has("--performance-probe") or OS.get_cmdline_user_args().has("--skip-update-trailer"): return false
	return play_trailer(false, user_id)

func play_trailer(_replay: bool = true, user_id: String = "") -> bool:
	if is_active() or DisplayServer.get_name() == "headless": return false
	if not FileAccess.file_exists(VIDEO_PATH):
		push_warning("[UpdateTrailer] Bundled video is unavailable; lobby remains usable.")
		return false
	_account = user_id.strip_edges()
	if _account.is_empty():
		var session := get_node_or_null("/root/UserSession")
		if session != null: _account = str(session.get("user_id")).strip_edges()
	_started = false
	_closing = false
	_suspended = false
	_elapsed = 0.0
	_run += 1
	_build_overlay()
	set_process_input(true)
	_start_video.call_deferred(_run)
	return true

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "UpdateTrailerPremiere"
	_layer.layer = 240
	add_child(_layer)
	_screen = Control.new()
	_screen.name = "TrailerScreen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_screen)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(background)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(aspect)
	_video = VideoStreamPlayer.new()
	_video.name = "TrailerVideo"
	_video.expand = true
	_video.loop = false
	_video.buffering_msec = 300
	_video.volume_db = -80.0
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(func(): _finish(true, true))
	aspect.add_child(_video)
	_cover = ColorRect.new()
	_cover.name = "BlackTransition"
	_cover.color = Color.BLACK
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_cover)
	_skip = Button.new()
	_skip.name = "SkipTrailer"
	_skip.text = "Пропустить"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.visible = false
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -172.0
	_skip.offset_right = -16.0
	_skip.offset_top = 16.0
	_skip.offset_bottom = 64.0
	_skip.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.07, 0.75)
	style.border_color = Color("ff9b3d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	_skip.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.25, 0.13, 0.07, 0.95)
	_skip.add_theme_stylebox_override("hover", hover)
	_skip.add_theme_stylebox_override("pressed", hover)
	_skip.add_theme_color_override("font_color", Color("ffbb70"))
	_skip.pressed.connect(func(): _finish(false, _started))
	_screen.add_child(_skip)
	_screen.resized.connect(_layout_skip_button)
	_layout_skip_button()

func _layout_skip_button() -> void:
	if not is_instance_valid(_skip): return
	var logical_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(get_window().size)
	var scale := logical_size / window_size.max(Vector2.ONE)
	var mobile := OS.has_feature("android") or OS.has_feature("ios")
	var height := maxf(48.0, ceilf(48.0 * maxf(scale.x, scale.y))) if mobile else 48.0
	var right := 16.0
	var top := 16.0
	if mobile:
		var safe := DisplayServer.get_display_safe_area()
		if safe.has_area():
			right += maxf(0.0, (window_size.x - safe.end.x) * scale.x)
			top += maxf(0.0, safe.position.y * scale.y)
	_skip.offset_left = -maxf(156.0, height * 3.0) - right
	_skip.offset_right = -right
	_skip.offset_top = top
	_skip.offset_bottom = top + height

func _start_video(run_id: int) -> void:
	if run_id != _run or not is_active(): return
	# The first connection splash finishes before any frames/audio are consumed.
	while preload("res://scripts/ui/startup_connection_banner.gd").is_active(get_tree()):
		await get_tree().process_frame
		if run_id != _run or not is_active() or _closing: return
	_suspend_lobby()
	var stream := VideoStreamTheora.new()
	stream.file = VIDEO_PATH
	_video.stream = stream
	_video.play()
	# Keep the first frame black until the decoder has produced a frame.
	var wait_seconds := 0.0
	while wait_seconds < 4.0:
		await get_tree().process_frame
		if run_id != _run or not is_active() or _closing: return
		if _suspended: continue
		wait_seconds += get_process_delta_time()
		var texture := _video.get_video_texture()
		if _video.stream_position > 0.02 and texture != null and texture.get_width() > 0: break
	if _video.stream_position <= 0.02:
		push_warning("[UpdateTrailer] Playback did not start; premiere will retry on the next visit.")
		_finish(false, false)
		return
	_started = true
	set_process(true)
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(_cover, "color:a", 0.0, INTRO_FADE)
	_transition.tween_property(_video, "volume_db", 0.0, INTRO_FADE)

func _process(delta: float) -> void:
	if not is_active() or _closing or _suspended: return
	_elapsed += delta
	_skip.visible = _elapsed > 1.0
	# A corrupt decoder must never leave the user behind a permanent black screen.
	if _elapsed > 36.0:
		push_warning("[UpdateTrailer] Playback watchdog returned to the lobby.")
		_finish(false, false)

func _input(event: InputEvent) -> void:
	if not is_active() or _closing: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(false, _started)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and is_active():
		_suspended = true
		_video.paused = true
		if _transition != null and _transition.is_valid(): _transition.pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED and is_active():
		_suspended = false
		_video.paused = false
		if _transition != null and _transition.is_valid(): _transition.play()

func _finish(completed: bool, remember: bool) -> void:
	if not is_active() or _closing: return
	_closing = true
	set_process(false)
	set_process_input(false)
	if _transition != null and _transition.is_valid(): _transition.kill()
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(_cover, "color:a", 1.0, OUTRO_FADE)
	_transition.tween_property(_video, "volume_db", -80.0, OUTRO_FADE)
	await _transition.finished
	if not is_active(): return
	_video.stop()
	_video.stream = null
	_restore_lobby()
	# Revealing the lobby uses the same black cover; no stretched last-frame flash.
	_video.hide()
	_screen.get_child(0).hide()
	_skip.hide()
	_transition = create_tween()
	_transition.tween_property(_cover, "color:a", 0.0, 0.35)
	await _transition.finished
	if remember and not _account.is_empty(): _remember_seen(_account)
	_layer.queue_free()
	_layer = null
	_video = null
	_closing = false
	_suspended = false
	finished.emit(completed)

func _suspend_lobby() -> void:
	var current := get_tree().current_scene
	if current == null: return
	_scene = weakref(current)
	_scene_process_mode = current.process_mode
	current.process_mode = Node.PROCESS_MODE_DISABLED
	if current is CanvasItem:
		_scene_visible = current.visible
		current.hide()
	_preview_modes.clear()
	for node in current.find_children("*", "SubViewport", true, false):
		_preview_modes.append({"node": weakref(node), "mode": node.render_target_update_mode})
		node.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _restore_lobby() -> void:
	for entry in _preview_modes:
		var preview: SubViewport = entry.node.get_ref()
		if is_instance_valid(preview): preview.render_target_update_mode = entry.mode
	_preview_modes.clear()
	if _scene != null:
		var previous: Node = _scene.get_ref()
		if is_instance_valid(previous):
			previous.process_mode = _scene_process_mode
			if previous is CanvasItem: previous.visible = _scene_visible
	_scene = null

func _exit_tree() -> void:
	if _transition != null and _transition.is_valid(): _transition.kill()
	_restore_lobby()

func _seen_key(user_id: String) -> String:
	return RELEASE_ID + ":" + user_id.strip_edges().sha256_text()

func _load_seen() -> void:
	_seen.clear()
	if FileAccess.file_exists(seen_path):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(seen_path))
		if stored is Dictionary: _seen = stored

func _remember_seen(user_id: String) -> void:
	_seen[_seen_key(user_id)] = true
	DirAccess.make_dir_recursive_absolute(seen_path.get_base_dir())
	var file := FileAccess.open(seen_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_seen))
