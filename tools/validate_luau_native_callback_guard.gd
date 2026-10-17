extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	root.add_child(world)
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
__invoke_native(function() while true do end end)
task.wait(0)
""", context, {"retain": true, "defer_initial_resume": true})
	var runtime: Dictionary = engine._script_runtimes[result.runtime_id]
	engine._push_lua_binding(runtime.lua, "__invoke_native", func(callback: Callable) -> Variant:
		return callback.call()
	)
	var start := Time.get_ticks_msec()
	var deadline := start + 2500
	while engine.get_runtime_diagnostics().failed == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	var diagnostics: Dictionary = engine.get_runtime_diagnostics()
	var ok: bool = result.get("ok", false) and diagnostics.failed == 1 and diagnostics.active == 0 and Time.get_ticks_msec() - start < 1500
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	print("[native-callback-guard] PASS=", ok, " elapsed_ms=", Time.get_ticks_msec() - start, " diagnostics=", diagnostics)
	quit(0 if ok else 1)
