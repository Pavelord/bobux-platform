extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "SchedulingRegression"
	root.add_child(world)
	var objects := Node.new()
	objects.name = "Objects"
	world.add_child(objects)
	for group_index in 24:
		var group := Node.new()
		objects.add_child(group)
		for item_index in 64:
			var item := Node.new()
			item.set_meta("roblox_class", "Folder")
			group.add_child(item)
	var script_node := Node.new()
	world.add_child(script_node)
	var result: Dictionary = engine.start_script("""
local first = script.Parent.Objects:GetChildren()[1]
local remembered = {[first] = 'same instance'}
assert(rawequal(first, script.Parent.Objects:GetChildren()[1]), 'Instance userdata identity changed')
assert(remembered[script.Parent.Objects:GetChildren()[1]] == 'same instance', 'Instance table key cannot be looked up')
local marker = Instance.new('Folder')
marker.Name = 'IdentityProbe'
marker.Parent = first
remembered[marker] = 42
assert(remembered[first.IdentityProbe] == 42, 'new Instance identity changed after parenting')
marker:Destroy()
local function count(node)
    local total = 1
    for _, child in ipairs(node:GetChildren()) do total += count(child) end
    return total
end
local ok, total = pcall(count, script.Parent.Objects)
assert(ok and total == 1561, 'recursive traversal lost its stack during preemption')
task.wait(0.02)
script.Parent:SetAttribute('Completed', total)
""", script_node, {"retain": true})
	var frames := 0
	var deadline := Time.get_ticks_msec() + 8000
	while not world.has_meta("attribute_Completed") and Time.get_ticks_msec() < deadline and engine.get_runtime_diagnostics().failed == 0:
		await process_frame
		frames += 1
	var ok: bool = bool(result.get("ok", false)) and world.get_meta("attribute_Completed", 0) == 1561 and frames > 1
	print("[luau_scheduling] completed=", ok, " frames=", frames, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	quit(0 if ok else 1)
