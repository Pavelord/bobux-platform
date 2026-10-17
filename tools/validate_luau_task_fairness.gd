extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "TaskFairness"
	world.set_meta("roblox_class", "Workspace")
	root.add_child(world)
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
local running = true
for i = 1, 3 do
    task.defer(function()
        while running do
            local untilTime = os.clock() + 0.003
            while os.clock() < untilTime do end
            task.wait(0)
        end
    end)
end
for i = 1, 24 do
    task.defer(function(value, suffix, missing)
        assert(value == i and suffix == 'ok' and missing == nil, 'task arguments changed')
        task.wait(0)
        script.Parent:SetAttribute('Done' .. i, true)
    end, i, 'ok', nil)
end
task.delay(0.15, function() running = false; script.Parent:SetAttribute('Stopped', true) end)
""", context, {"retain": true})
	var frames := 0
	var deadline := Time.get_ticks_msec() + 2500
	while frames < 160 and Time.get_ticks_msec() < deadline and not world.get_meta("attribute_Stopped", false):
		await process_frame
		frames += 1
	var completed := 0
	for index in range(1, 25):
		if world.get_meta("attribute_Done%d" % index, false): completed += 1
	var ok: bool = result.get("ok", false) and completed == 24 and world.get_meta("attribute_Stopped", false) and engine.get_runtime_diagnostics().failed == 0
	print("[task_fairness] ok=", ok, " completed=", completed, " frames=", frames, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	quit(0 if ok else 1)
