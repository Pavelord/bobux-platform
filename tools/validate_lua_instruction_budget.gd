extends SceneTree


func _initialize() -> void:
	await process_frame
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	if lua_engine == null:
		push_error("LuaScriptEngine autoload is unavailable")
		quit(1)
		return
	var context := Node.new()
	context.name = "RunawayScript"
	get_root().add_child(context)
	lua_engine.reset_runtime_diagnostics()
	var started_usec := Time.get_ticks_usec()
	var result: Dictionary = lua_engine.start_script(
		"local n = 0 repeat n = n + 1 until false",
		context,
		{"source_name": "InstructionBudgetTest", "retain": true}
	)
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var diagnostics: Dictionary = lua_engine.get_runtime_diagnostics()
	var error_text := str(result.get("error", ""))
	# Native Luau cooperatively slices long work. Repeated preemption must not
	# let a runaway script reset its cumulative execution allowance.
	while bool(result.get("ok", false)) and diagnostics.failed == 0 and Time.get_ticks_usec() - started_usec < 8000000:
		await process_frame
		diagnostics = lua_engine.get_runtime_diagnostics()
	if not diagnostics.last_errors.is_empty(): error_text = str(diagnostics.last_errors.back())
	var ok := int(diagnostics.failed) == 1
	ok = ok and elapsed_ms < 500.0
	ok = ok and error_text.contains("execution budget")
	print("[validate_lua_instruction_budget] ok=%s elapsed_ms=%.2f error=%s diagnostics=%s" % [ok, elapsed_ms, error_text, diagnostics])
	var handler: Dictionary = lua_engine.start_script("script.Event:Connect(function() local n = 0 repeat n = n + 1 until false end)", context, {"retain": true, "source_name": "RunawayCallback"})
	var registry: Dictionary = context.get_meta("_bobux_event_registry", {})
	var callback_started := Time.get_ticks_usec()
	if registry.has("Event"):
		registry["Event"].Fire()
	var callback_ms := float(Time.get_ticks_usec() - callback_started) / 1000.0
	var callback_diagnostics: Dictionary = lua_engine.get_runtime_diagnostics()
	var callback_ok := bool(handler.get("ok", false)) and registry.has("Event") and callback_ms < 500 and int(callback_diagnostics.get("failed", 0)) == 2
	ok = ok and callback_ok
	print("[validate_lua_instruction_budget] external_callback=%s elapsed_ms=%.2f" % [callback_ok, callback_ms])
	registry.clear()
	lua_engine.stop_all_scripts()
	lua_engine.reset_runtime_diagnostics()
	var yielding_context := Node.new()
	yielding_context.name = "YieldingTaskScript"
	get_root().add_child(yielding_context)
	var yielding_result: Dictionary = lua_engine.start_script(
		"local ticks = 0; task.spawn(function() while true do ticks = ticks + 1; script:SetAttribute('YieldTicks', ticks); task.wait(0.001) end end)",
		yielding_context,
		{"source_name": "YieldingTaskTest", "retain": true}
	)
	for _frame in range(6):
		await process_frame
	var yielding_diagnostics: Dictionary = lua_engine.get_runtime_diagnostics()
	var yielding_ok := bool(yielding_result.get("ok", false))
	yielding_ok = yielding_ok and int(yielding_context.get_meta("attribute_YieldTicks", 0)) > 0
	yielding_ok = yielding_ok and int(yielding_diagnostics.get("failed", 0)) == 0
	print("[validate_lua_instruction_budget] yielding_task=", yielding_ok,
		" ticks=", yielding_context.get_meta("attribute_YieldTicks", 0),
		" diagnostics=", yielding_diagnostics)
	ok = ok and yielding_ok
	lua_engine.stop_all_scripts()
	context.queue_free()
	yielding_context.queue_free()
	await process_frame
	lua_engine.release_stopped_script_states()
	quit(0 if ok else 1)
