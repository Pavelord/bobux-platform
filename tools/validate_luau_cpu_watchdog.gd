extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
	print("[cpu_watchdog] ", "PASS " if value else "FAIL ", label)

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "CPUWatchdog"
	world.set_meta("roblox_class", "Workspace")
	root.add_child(world)
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
__sleep_native()
__busy_native()
local total = 0
for i = 1, 10000 do total += i end
assert(total == 50005000)
script.Parent:SetAttribute('FiniteDone', true)
""", context, {"retain": true, "defer_initial_resume": true})
	var runtime: Dictionary = engine._script_runtimes[result.runtime_id]
	check(runtime.lua.has_method("get_vm_cpu_time_usec"), "native runtime exposes a VM CPU clock")
	engine._push_lua_binding(runtime.lua, "__sleep_native", func(): OS.delay_msec(700))
	engine._push_lua_binding(runtime.lua, "__busy_native", func():
		var until_time := Time.get_ticks_usec() + 650000
		while Time.get_ticks_usec() < until_time: pass
	)
	var wall_start := Time.get_ticks_msec()
	var deadline := wall_start + 4000
	while not world.get_meta("attribute_FiniteDone", false) and Time.get_ticks_msec() < deadline and engine.get_runtime_diagnostics().failed == 0:
		await process_frame
	check(world.get_meta("attribute_FiniteDone", false) and Time.get_ticks_msec() - wall_start >= 1300 and engine.get_runtime_diagnostics().failed == 0, "OS wait and expensive native work do not kill finite Luau")
	var task_context := Node.new()
	world.add_child(task_context)
	engine.start_script("""
task.defer(function() while true do end end)
task.defer(function() task.wait(0); script.Parent:SetAttribute('SiblingDone', true) end)
""", task_context, {"retain": true})
	deadline = Time.get_ticks_msec() + 2500
	while (engine.get_runtime_diagnostics().failed < 1 or not world.get_meta("attribute_SiblingDone", false)) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(engine.get_runtime_diagnostics().failed == 1 and world.get_meta("attribute_SiblingDone", false), "infinite task is stopped while its sibling completes")
	var callback_context := Node.new()
	world.add_child(callback_context)
	engine.start_script("""
task.spawn(function() while true do end end)
script.Parent:SetAttribute('ParentContinued', true)
task.defer(function() task.wait(0); script.Parent:SetAttribute('AfterImmediateDone', true) end)
""", callback_context, {"retain": true})
	deadline = Time.get_ticks_msec() + 2500
	while not world.get_meta("attribute_AfterImmediateDone", false) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.get_meta("attribute_ParentContinued", false) and world.get_meta("attribute_AfterImmediateDone", false), "immediate task timeout does not poison its parent")
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	print("[cpu_watchdog] failures=", failures, " diagnostics=", engine.get_runtime_diagnostics())
	quit(0 if failures.is_empty() else 1)
