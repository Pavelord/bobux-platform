extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	engine.set_process(false)
	engine._ensure_run_service_events()
	var signals := [engine._run_service_stepped, engine._run_service_heartbeat, engine._run_service_render_stepped]
	var calls: Array[int] = [0, 0, 0]
	var deltas: Array = []
	for signal_index in 3:
		for handler in 12:
			if signal_index == 0:
				signals[signal_index].Connect(func(_time, dt): calls[0] += 1; deltas.append(dt))
			else:
				var slot := signal_index
				signals[signal_index].Connect(func(dt): calls[slot] += 1; deltas.append(dt))
	engine._run_service_heartbeat.Connect(func(_dt):
		var until := Time.get_ticks_usec() + 3000
		while Time.get_ticks_usec() < until: pass
	)
	engine._process(0.125)
	var complete_delivery := calls == [12, 12, 12] and deltas.size() == 36 and deltas.all(func(dt): return dt == 0.125)
	for frame_signal in signals: frame_signal.Disconnect()
	engine.set_process(true)
	var host := Node3D.new()
	host.name = "Owner"
	root.add_child(host)
	var world := Node3D.new()
	host.add_child(world)
	var services: Dictionary = engine._ensure_roblox_service_nodes(root, world)
	assert(services.Players.get_parent().get_parent() == host)
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
local started, completed, total = 0, 0, 0
local connection = game:GetService('RunService').Heartbeat:Connect(function(dt)
    started += 1
    total += dt
    script.Parent:SetAttribute('Started', started)
    task.wait(0.01)
    completed += 1
    script.Parent:SetAttribute('Completed', completed)
    script.Parent:SetAttribute('Total', total)
end)
script.Parent:SetAttribute('Connected', true)
""", context, {"retain": true})
	assert(result.get("ok", false))
	var deadline := Time.get_ticks_msec() + 5000
	while not world.get_meta("attribute_Connected", false) and Time.get_ticks_msec() < deadline:
		await process_frame
	engine.set_process(false)
	var before := int(world.get_meta("attribute_Started", 0))
	engine._run_service_heartbeat.Fire(0.1)
	engine._run_service_heartbeat.Fire(0.2)
	engine._run_service_heartbeat.Fire(0.3)
	var delivered := int(world.get_meta("attribute_Started", 0)) - before
	deadline = Time.get_ticks_msec() + 1000
	while int(world.get_meta("attribute_Completed", 0)) < before + 3 and Time.get_ticks_msec() < deadline:
		await process_frame
		engine._process_lua_tasks()
	var ok: bool = complete_delivery and delivered == 3 and int(world.get_meta("attribute_Completed", 0)) == before + 3 and engine.get_runtime_diagnostics().failed == 0
	engine.stop_all_scripts(host)
	engine.queue_stopped_state_cleanup(host)
	host.queue_free()
	engine.set_process(true)
	for frame in 5: await process_frame
	ok = ok and engine._task_runtime_ids.is_empty() and engine._retained_lua_states.is_empty()
	print("[frame-events] PASS=", ok, " delivered=", delivered, " yielding callbacks, owner cleanup")
	quit(0 if ok else 1)
