extends Node
## Opt-in benchmark: res://scripts/diagnostics/runtime_performance_probe.tscn
## -- --maps=park,valley,nds --seconds=30 --runs=2
## Android uses a separate com.bobux.performance debug package.

const MAPS := {
	"park": "akx0oto939gi501_bobux_park_krut",
	"valley": "akx0oto939gi501_dolina_semi_vetrov",
	"nds": "z9ovqynlv860sgw_narural disaster survival - bobux edition",
	"nds_legacy": "z9ovqynlv860sgw_natural disaster survival - bobux edition",
	"lift": "evd29np4936q499_normalnyi_lift",
	"city_rp": "evd29np4936q499_бобукс сити рп",
}
@onready var root: Window = get_tree().root
var current_scene: Node:
	get: return get_tree().current_scene
	set(value): get_tree().current_scene = value

var results: Array = []
var failures: Array[String] = []
var seconds := 30.0
var run_count := 2
var selected: Array[String] = ["park", "valley", "nds"]
var tag := "benchmark"
var bottlenecks := false
var server_url := "ws://109.71.245.162/ws"
var frame_times: Array[float] = []
var cpu_times: Array[float] = []
var physics_times: Array[float] = []
var sampling := false
var previous_usec := 0

func _ready() -> void:
	run.call_deferred()

func sample_frame() -> void:
	var now := Time.get_ticks_usec()
	if sampling and previous_usec > 0:
		frame_times.append((now - previous_usec) / 1000.0)
		cpu_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	previous_usec = now

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var stalls := 0
	for value in values:
		total += value
		if value > 50.0: stalls += 1
	return {"frames": values.size(), "mean_ms": total / values.size(),
		"p50_ms": sorted[int((sorted.size()-1)*0.50)], "p95_ms": sorted[int((sorted.size()-1)*0.95)],
		"p99_ms": sorted[int((sorted.size()-1)*0.99)], "max_ms": sorted.back(),
		"over_50ms": stalls, "fps": 1000.0 / maxf(total / values.size(), 0.001)}

func reset_samples() -> void:
	frame_times.clear()
	cpu_times.clear()
	physics_times.clear()
	previous_usec = 0

func run() -> void:
	if not OS.has_feature("android") and not OS.get_user_data_dir().replace("\\", "/").contains(".codex-tmp/"):
		push_error("Benchmark requires isolated APPDATA under .codex-tmp")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--maps="): selected.assign(arg.trim_prefix("--maps=").split(","))
		if arg.begins_with("--seconds="): seconds = clampf(arg.trim_prefix("--seconds=").to_float(), 5, 180)
		if arg.begins_with("--runs="): run_count = clampi(arg.trim_prefix("--runs=").to_int(), 1, 5)
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		if arg == "--bottlenecks": bottlenecks = true
		if arg.begins_with("--server="): server_url = arg.trim_prefix("--server=")
	get_tree().process_frame.connect(sample_frame)
	root.get_node("UserSession").username = "PerformanceProbe"
	print("[perf] BEGIN ", JSON.stringify({"platform": OS.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "tag": tag, "maps": selected, "runs": run_count}))
	for iteration in run_count:
		for key in selected:
			if not MAPS.has(key):
				failures.append("Unknown map: " + key)
				continue
			await benchmark(key, iteration)
	var report := {"tag": tag, "platform": OS.get_name(), "results": results, "failures": failures}
	DirAccess.make_dir_recursive_absolute("user://performance")
	var output := FileAccess.open("user://performance/%s.json" % tag.validate_filename(), FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(report, "\t"))
	print("[perf] REPORT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func benchmark(key: String, iteration: int) -> void:
	var lua_engine := root.get_node("LuaScriptEngine")
	var initial_failed := int(lua_engine.get_runtime_diagnostics().failed)
	lua_engine._native_access_profile.clear()
	lua_engine._native_profile.clear()
	var state := root.get_node("GameState")
	state.configure_target_join({"server_url": server_url,
		"room_id": "%s:validation:performance-20261009" % MAPS[key],
		"map_id": MAPS[key], "map_name": key, "create_if_missing": true, "max_players": 4}, {})
	reset_samples()
	sampling = true
	var started := Time.get_ticks_msec()
	var main_packed: PackedScene = await root.get_node("GameSceneLoader").get_main()
	if main_packed == null:
		failures.append("Main scene resource load failed")
		sampling = false
		return
	var main: Node = main_packed.instantiate()
	root.add_child(main)
	current_scene = main
	var ready_at := 0
	var last_progress := started
	while Time.get_ticks_msec() - started < 150000:
		await get_tree().process_frame
		if not is_instance_valid(main) or current_scene != main:
			failures.append("%s run %d disconnected: %s" % [key, iteration, state.last_network_error])
			sampling = false
			await cleanup_runtime(main)
			return
		var now := Time.get_ticks_msec()
		if main._runtime_world_ready and not state.network_gameplay_frozen and main._get_local_player() != null:
			ready_at = now
			break
		if now - last_progress >= 5000:
			last_progress = now
			print("[perf] JOIN ", key, " elapsed_ms=", now-started, " loaded=", main._map_loaded)
	var join_stats := stats(frame_times)
	sampling = false
	if ready_at == 0:
		failures.append("%s join timed out" % key)
		await cleanup_runtime(main)
		return
	print("[perf] READY ", key, " run=", iteration, " join_ms=",ready_at-started, " join_frames=",JSON.stringify(join_stats))
	# Intros build controls cooperatively; wait until the visible button exists.
	var touched := false
	var intro_started := Time.get_ticks_msec()
	var intro_deadline := intro_started + (90000 if key == "park" else 30000)
	while key in ["park", "valley"] and not touched and Time.get_ticks_msec() < intro_deadline:
		await get_tree().process_frame
		if key == "park" and lua_engine.get_runtime_diagnostics().active > 0: continue
		for button in main.find_children("*", "Button", true, false):
			if not _is_drawn_button(button): continue
			if button.name == "StartButton" or button.text.begins_with("ПОЕХАТЬ") or button.text.begins_with("Начать"):
				touched = await _touch_start_button(button)
				break
	var intro_ms := Time.get_ticks_msec() - intro_started
	if key in ["park", "valley"] and not touched: failures.append("%s start control unavailable after intro wait" % key)
	print("[perf] START ", key, " touched=", touched, " intro_ms=", intro_ms)
	# The park's existing departure and road cutscenes last about 14 seconds.
	# Measure gameplay after they finish, not a mixture of lobby and cutscenes.
	await get_tree().create_timer(18.0 if key == "park" else 3.0).timeout
	lua_engine._native_access_profile.clear()
	lua_engine._native_profile.clear()
	reset_samples()
	sampling = true
	var play_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - play_started < seconds * 1000:
		await get_tree().process_frame
		if not is_instance_valid(main) or current_scene != main:
			failures.append("%s gameplay disconnected" % key)
			sampling = false
			await cleanup_runtime(main)
			return
		# Exercise the camera throughout the sample without changing map state.
		var player: Node = main._get_local_player()
		if player != null and OS.get_cmdline_user_args().has("--rotate-camera") and key != "park":
			player.rotate_y(0.15 * (frame_times.back() / 1000.0 if not frame_times.is_empty() else 0.016))
	sampling = false
	var record := {"map": key, "run": iteration, "join_ms": ready_at-started,
		"join_frames": join_stats, "frame": stats(frame_times), "cpu": stats(cpu_times),
		"physics": stats(physics_times), "touch_start": touched, "intro_ms": intro_ms,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"runtime": root.get_node("LuaScriptEngine").get_runtime_diagnostics()}
	print("[perf] RESULT ", JSON.stringify(record))
	if int(record.runtime.failed) > initial_failed:
		failures.append("%s runtime failed %d new scripts: %s" % [key, int(record.runtime.failed) - initial_failed, record.runtime.last_errors])
	if OS.get_cmdline_user_args().has("--batch-ab"):
		# Render both images with the entire simulation paused at one pose.
		# The normal gameplay sample above retains all scripts and physics.
		get_tree().paused = true
		var before: Image = await capture_frame(key + "-before")
		var batch_started := Time.get_ticks_msec()
		record["render_batches"] = preload("res://addons/roblox_runtime/roblox_render_batches.gd").build(main.world)
		record["render_batches"]["build_ms"] = Time.get_ticks_msec() - batch_started
		var after: Image = await capture_frame(key + "-after")
		if before != null and after != null:
			before.convert(Image.FORMAT_RGBA8)
			after.convert(Image.FORMAT_RGBA8)
			var left := before.get_data()
			var right := after.get_data()
			var changed := 0
			var difference := 0.0
			var samples := 0
			var stride := maxi(1, left.size() / 16384) * 4
			if left.size() == right.size():
				for pixel in range(0, left.size() - 3, stride):
					var delta_: int = absi(int(left[pixel]) - int(right[pixel])) + absi(int(left[pixel + 1]) - int(right[pixel + 1])) + absi(int(left[pixel + 2]) - int(right[pixel + 2]))
					difference += delta_ / 765.0
					if delta_ > 6: changed += 1
					samples += 1
				record["batch_visual"] = {"exact": left == right, "mean_rgb_difference": difference / maxf(samples, 1), "changed_fraction": float(changed) / maxf(samples, 1), "samples": samples}
		get_tree().paused = false
		await get_tree().create_timer(3.0).timeout
		reset_samples()
		sampling = true
		await get_tree().create_timer(seconds).timeout
		sampling = false
		record["batched_frame"] = stats(frame_times)
		record["batched_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		# Android logcat limits each line. Keep the A/B result below that limit.
		print("[perf] BATCH_AB ", key, " ", JSON.stringify({"map": key, "run": iteration, "batch_visual": record.get("batch_visual", {}), "render_batches": record["render_batches"], "batched_frame": record["batched_frame"], "batched_draw_calls": record["batched_draw_calls"]}))
	if lua_engine._profile_native_enabled:
		for property in lua_engine._native_access_profile:
			print("[perf] NATIVE ", key, " ", property, " ", JSON.stringify(lua_engine._native_access_profile[property]))
		print("[perf] NATIVE_SLOW ", key, " ", JSON.stringify(lua_engine._native_profile))
	if bottlenecks:
		var engine := root.get_node("LuaScriptEngine")
		var was_paused: bool = engine._scripts_paused
		engine._scripts_paused = true
		var previous_mode: ProcessMode = main.process_mode
		var hidden_layers: Array[CanvasLayer] = []
		var disabled_helpers: Array[Node] = []
		for phase in ["lua_paused", "lua_paused_no_3d", "gui_only_paused", "gui_paused", "main_paused", "player_paused", "scene_disabled", "no_canvas"]:
			root.disable_3d = phase != "lua_paused"
			if phase in ["gui_only_paused", "gui_paused"]:
				for helper in main.find_children("*", "Node", true, false):
					var script: Script = helper.get_script()
					if script != null and (script.resource_path.ends_with("roblox_live_gui.gd") or (phase == "gui_paused" and script.resource_path.ends_with("roblox_inventory_controller.gd"))) and helper.is_processing():
						disabled_helpers.append(helper)
						helper.set_process(false)
			if phase == "main_paused": main.set_process(false)
			if phase == "player_paused":
				var player: Node = main._get_local_player()
				if player != null:
					player.set_process(false)
					player.set_physics_process(false)
			if phase == "scene_disabled": main.process_mode = Node.PROCESS_MODE_DISABLED
			if phase == "no_canvas":
				for layer in root.find_children("*", "CanvasLayer", true, false):
					if layer.visible:
						hidden_layers.append(layer)
						layer.visible = false
			reset_samples()
			sampling = true
			await get_tree().create_timer(5.0).timeout
			sampling = false
			record[phase] = stats(frame_times)
			print("[perf] DIAGNOSTIC ", key, " ", phase, " ", JSON.stringify(record[phase]))
		root.disable_3d = false
		for layer in hidden_layers: layer.visible = true
		main.process_mode = previous_mode
		main.set_process(true)
		for helper in disabled_helpers: helper.set_process(true)
		var player: Node = main._get_local_player()
		if player != null:
			player.set_process(true)
			player.set_physics_process(true)
		engine._scripts_paused = was_paused
	var leave_started := Time.get_ticks_msec()
	await cleanup_runtime(main)
	record["leave_ms"] = Time.get_ticks_msec() - leave_started
	results.append(record)

func cleanup_runtime(main: Node) -> void:
	if is_instance_valid(main) and not main.is_queued_for_deletion() and current_scene == main:
		await main.leave_game()
	else:
		root.get_node("NetworkManager").disconnect_from_session()
		if is_instance_valid(main) and not main.is_queued_for_deletion(): main.queue_free()
	# Drain gradual destruction so a later run does not measure the previous map.
	var cleanup_deadline := Time.get_ticks_msec() + 20000
	while not root.get_node("ImportedPlaceNetwork")._retired.is_empty() and Time.get_ticks_msec() < cleanup_deadline:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	# Leave creates Lobby. Its background requests must finish with that scene
	# before the next isolated runtime measurement starts.
	if current_scene != null:
		var lobby := current_scene
		current_scene = null
		lobby.queue_free()
		await get_tree().process_frame

func _is_drawn_button(button: Variant) -> bool:
	if not is_instance_valid(button) or not button is Button or not button.is_visible_in_tree():
		return false
	var viewport: Viewport = button.get_viewport()
	if viewport == null or (button.visibility_layer & viewport.canvas_cull_mask) == 0:
		return false
	var rect: Rect2 = button.get_global_rect()
	return rect.has_area() and viewport.get_visible_rect().has_point(rect.get_center())

func _touch_start_button(button: Button) -> bool:
	if not _is_drawn_button(button): return false
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = button.get_global_rect().get_center()
		touch.pressed = pressed
		root.push_input(touch, true)
		await get_tree().process_frame
	# The DataModel contains hidden Buttons as well. Passing means the drawable
	# mirror received the event and the original callback closed its intro.
	var close_deadline := Time.get_ticks_msec() + 2000
	while _is_drawn_button(button) and Time.get_ticks_msec() < close_deadline:
		await get_tree().process_frame
	return not _is_drawn_button(button)

func capture_frame(label_: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://performance")
	var path := "user://performance/%s-%s.png" % [tag.validate_filename(), label_.validate_filename()]
	var frame := root.get_texture().get_image()
	var error := frame.save_png(path)
	print("[perf] IMAGE ", path, " result=", error)
	return frame
