extends SceneTree

func _initialize() -> void:
	await process_frame
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "Workspace"
	world.set_meta("roblox_class", "Workspace")
	root.add_child(world)
	var script := Node.new()
	script.name = "AsyncTween"
	world.add_child(script)
	var errors: Array[String] = []
	var result: Dictionary = engine.start_script("""
local literal = ':connect( untouched :disconnect('
assert(literal == ':con' .. 'nect( untouched :dis' .. 'connect(', 'source strings stay unchanged')
task.delay(0.025, function()
    local folder = Instance.new('Folder', workspace)
    folder.Name = 'Later'
    local part = Instance.new('Part', folder)
    part.Name = 'Moving'
    part.Anchored = true
    part.Position = Vector3.new(0, 10, 0)
end)
local part = workspace:WaitForChild('Later', 1):WaitForChild('Moving', 1)
assert(part ~= nil, 'chained waits')
assert(workspace:WaitForChild('Missing', 0.02) == nil, 'wait timeout')
local fired = 0
local connection = part:GetPropertyChangedSignal('Transparency'):connect(function() fired = fired + 1 end)
part.Transparency = 0.2
connection:disconnect()
part.Transparency = 0.4
assert(fired == 1, 'property connection and lowercase disconnect')
local tween = game:GetService('TweenService'):Create(part, TweenInfo.new(0.12), {Position = Vector3.new(12, 10, 0)})
tween:Play()
task.wait(0.04)
assert(part.Position.X > 0 and part.Position.X < 12, 'tween interpolates over time')
tween:Pause()
local pausedX = part.Position.X
task.wait(0.035)
assert(math.abs(part.Position.X - pausedX) < 0.001, 'pause stops tween')
tween:Play()
tween.Completed:Wait()
assert(math.abs(part.Position.X - 12) < 0.001, 'tween completes')
local event = Instance.new('BindableEvent', workspace)
task.delay(0.02, function() event:Fire(7, 'done') end)
local value, text = event.Event:Wait()
assert(value == 7 and text == 'done', 'signal wait returns values')
workspace.AsyncTweenPassed = true
""", script, {"realm": "studio", "is_server": true})
	if not result.get("ok", false):
		errors.append(str(result.get("error")))
	await create_timer(0.65).timeout
	if not bool(world.get_meta("AsyncTweenPassed", false)):
		errors.append("async/tween assertions did not finish")
	print("[validate_lua_async_tween] errors=", errors, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts()
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if errors.is_empty() else 1)
