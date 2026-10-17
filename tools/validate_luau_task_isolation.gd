extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	root.add_child(world)
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
task.defer(function() while true do end end)
for i = 1, 12 do
    task.defer(function()
        task.wait(0.02)
        script.Parent:SetAttribute('Done' .. i, true)
    end)
end
""", context, {"retain": true})
	await create_timer(2.0).timeout
	var completed := 0
	for i in range(1,13):
		if world.get_meta("attribute_Done%d" % i, false): completed += 1
	var ok: bool = result.get("ok",false) and completed == 12
	print("[task-isolation] PASS=",ok," completed=",completed," diagnostics=",engine.get_runtime_diagnostics())
	engine.stop_all_scripts(world)
	quit(0 if ok else 1)
