extends SceneTree

class FrameProbe:
	extends Node
	var max_delta: float = 0.0
	var frames: int = 0
	var status_label: Label = null
	var slow_frames: Array[Dictionary] = []

	func _process(delta: float) -> void:
		max_delta = maxf(max_delta, delta)
		frames += 1
		if delta >= 0.03:
			slow_frames.append({
				"delta": delta,
				"status": status_label.text if status_label != null else "",
			})
			slow_frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("delta", 0.0)) > float(b.get("delta", 0.0)))
			if slow_frames.size() > 12:
				slow_frames.resize(12)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	var frame_count := 240
	if not args.is_empty():
		source_path = str(args[0])
	if args.size() > 1:
		frame_count = maxi(int(args[1]), 1)
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	var probe := FrameProbe.new()
	get_root().add_child(probe)
	get_root().add_child(studio)
	await process_frame
	await process_frame
	probe.status_label = studio.get("toolbar_status_label") as Label
	await studio._on_rbxl_file_selected(source_path)
	await process_frame
	var import_report: Dictionary = studio.get("last_rbxl_import_report")
	print("[validate_rbxl_playtest_runtime] import skipped=%d skipped_classes=%s warnings=%s" % [
		int(import_report.get("skipped", 0)), str(import_report.get("skipped_classes", {})), str(import_report.get("warnings", [])),
	])
	probe.max_delta = 0.0
	probe.frames = 0
	probe.slow_frames.clear()
	var startup_started_usec := Time.get_ticks_usec()
	await studio._start_studio_playtest()
	var startup_seconds := float(Time.get_ticks_usec() - startup_started_usec) / 1000000.0
	for _frame in range(frame_count):
		await process_frame
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	if lua_engine == null or not lua_engine.has_method("get_runtime_diagnostics"):
		push_error("LuaScriptEngine diagnostics are unavailable")
		quit(1)
		return
	var diagnostics: Dictionary = lua_engine.get_runtime_diagnostics()
	var status_text := ""
	var status_label: Variant = studio.get("toolbar_status_label")
	if status_label is Label:
		status_text = (status_label as Label).text
	print("[validate_rbxl_playtest_runtime] startup=%.3fs frames=%d max_frame=%.4fs started=%d completed=%d failed=%d active=%d status=%s" % [
		startup_seconds,
		probe.frames,
		probe.max_delta,
		int(diagnostics.get("started", 0)),
		int(diagnostics.get("completed", 0)),
		int(diagnostics.get("failed", 0)),
		int(diagnostics.get("active", 0)),
		status_text,
	])
	print("[validate_rbxl_playtest_runtime] slow_frames=%s" % JSON.stringify(probe.slow_frames))
	var errors: Array = diagnostics.get("last_errors", []) if diagnostics.get("last_errors", []) is Array else []
	for error_variant in errors.slice(0, mini(errors.size(), 24)):
		print("[validate_rbxl_playtest_runtime] runtime_error=%s" % str(error_variant))
	var responsive := probe.frames >= frame_count and probe.max_delta < 0.5
	var started_enough := int(diagnostics.get("started", 0)) >= 350
	var startup_ok := startup_seconds < 20.0
	var ok := responsive and started_enough and startup_ok and bool(studio.get("studio_playtest_active"))
	print("[validate_rbxl_playtest_runtime] stop_begin")
	await studio._stop_studio_playtest()
	print("[validate_rbxl_playtest_runtime] stop_complete")
	probe.queue_free()
	studio.queue_free()
	await process_frame
	await process_frame
	if lua_engine.has_method("release_stopped_script_states"):
		lua_engine.release_stopped_script_states()
	await process_frame
	quit(0 if ok else 1)
