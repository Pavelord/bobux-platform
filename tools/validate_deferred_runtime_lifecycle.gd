extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var failures: Array[String] = []
	var world := Node3D.new()
	root.add_child(world)
	var context := Node.new()
	world.add_child(context)
	var source := "local v = ''\n" + "v = 'literal :Connect() unchanged'\n".repeat(3000) + "script.Parent:SetAttribute('Done', true)"
	var queued: Dictionary = engine.start_script(source, context, {"defer_compilation": true, "retain": true})
	if not queued.get("queued", false): failures.append("Deferred start rejected")
	var deadline := Time.get_ticks_msec() + 10000
	var frames := 0
	while not world.has_meta("attribute_Done") and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
	if not world.get_meta("attribute_Done", false) or frames < 2: failures.append("Worker did not finish across frames")
	var state: Variant = engine._retained_lua_states.values()[0].lua if not engine._retained_lua_states.is_empty() else null
	var state_ref: WeakRef = weakref(state) if state != null else null
	state = null
	engine.stop_all_scripts(world)
	engine.queue_stopped_state_cleanup(world)
	await process_frame
	if state_ref != null and state_ref.get_ref() == null: failures.append("Native state released before owner")
	world.queue_free()
	for frame in 4: await process_frame
	if not engine._stopped_state_cleanup_jobs.is_empty(): failures.append("Stopped state job leaked")
	if state_ref != null and state_ref.get_ref() != null: failures.append("Native state leaked after owner")
	# Cancel a queued worker while it is preparing; it must not start a dead script.
	context = Node.new()
	root.add_child(context)
	engine.start_script(source + "\n-- uncached", context, {"defer_compilation": true})
	await process_frame
	engine.stop_all_scripts(context)
	context.queue_free()
	deadline = Time.get_ticks_msec() + 5000
	while engine._source_preparation_thread != null and Time.get_ticks_msec() < deadline: await process_frame
	if not engine._pending_script_starts.is_empty() or engine._source_preparation_thread != null: failures.append("Canceled preparation leaked")
	# stop_script handles an individual reservation too, by ID or live context.
	# Leave the owner alive to catch a queued worker restarting it after Stop.
	for by_id in [true, false]:
		context = Node.new()
		root.add_child(context)
		var stopped_source := source + "\n-- stopped individually " + str(by_id)
		var pending: Dictionary = engine.start_script(stopped_source, context, {"defer_compilation": true})
		engine._process_pending_script_starts()
		engine.stop_script(int(pending.runtime_id) if by_id else context)
		if context.has_meta("bobux_script_runtime_id"): failures.append("Stopped reservation marker leaked")
		deadline = Time.get_ticks_msec() + 5000
		while engine._source_preparation_thread != null and Time.get_ticks_msec() < deadline: await process_frame
		for frame in 4: await process_frame
		if not engine._pending_script_starts.is_empty(): failures.append("Individual stopped compilation remained queued")
		if context.has_meta("bobux_script_runtime_id") or root.get_meta("attribute_Done", false): failures.append("Stopped deferred Script ran again")
		context.queue_free()
		await process_frame
	print("[deferred-lifecycle] frames=", frames, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
