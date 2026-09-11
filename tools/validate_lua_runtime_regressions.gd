extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	root.add_child(workspace)
	var dependency := _node(workspace, "Dependency", "ModuleScript")
	dependency.set_meta("code", "return {value = 6}")
	var library := _node(workspace, "Library", "ModuleScript")
	library.set_meta("code", """
local dependency = require(script.Parent.Dependency)
local Library = {}
Library.__index = Library
function Library.new(value)
    return setmetatable({value = value + dependency.value}, Library)
end
function Library:double() return self.value * 2 end
return Library
""")
	var yielding := _node(workspace, "Yielding", "ModuleScript")
	yielding.set_meta("code", "task.wait(0.02); return {value = 9}")
	var cycle := _node(workspace, "Cycle", "ModuleScript")
	cycle.set_meta("code", "return require(script)")
	var source := """
local library = require(script.Parent.Library)
assert(library == require(script.Parent.Library), "module cache must preserve table identity")
assert(library.new(4):double() == 20, "nested modules and metatables")
assert(require(script.Parent.Yielding).value == 9, "yielding module")
local ok, err = pcall(require, script.Parent.Cycle)
assert(not ok and tostring(err):find("Circular"), "circular dependencies report an error")
script.Parent.ModulesPassed = true
"""
	_start(engine, workspace, "Modules", source)
	_start(engine, workspace, "Tasks", """
local finished = false
local argsPassed = false
local spawned = task.spawn(function(a, b, c)
    argsPassed = a == 1 and b == nil and c == 3
    task.wait(0.06)
    finished = true
end, 1, nil, 3)
assert(argsPassed and not finished, "spawn runs independently up to first yield")
assert(type(spawned) == "thread", "task.spawn returns a thread")
local delayed = false
task.delay(0.06, function() delayed = true end)
assert(not delayed, "delay must wait")
local deferred = false
task.defer(function() deferred = true end)
assert(not deferred, "defer must run on a later scheduler cycle")
local cancelled = task.delay(0.01, function() error("cancelled task ran") end)
task.cancel(cancelled)
local elapsed = task.wait(0.09)
assert(elapsed >= 0.08 and finished and delayed and deferred, "tasks must resume with elapsed wait time")
script.Parent.TasksPassed = true
""")
	_start(engine, workspace, "Signals", """
local event = Instance.new("BindableEvent", script.Parent)
local first, second, once = 0, 0, 0
local connection = event.Event:Connect(function() first = first + 1 end)
event.Event:Connect(function() second = second + 1 end)
event.Event:Once(function() once = once + 1 end)
event:Fire()
connection:Disconnect()
event:Fire()
assert(first == 1 and second == 2 and once == 1, "connections disconnect independently and Once fires once")
assert(connection.Connected == false, "connection status")
script.Parent.SignalsPassed = true
""")
	for _frame in range(25):
		if _frame == 0:
			_start(engine, workspace, "NestedConnection", """
local run = game:GetService('RunService')
local count = 0
local nested
task.spawn(function()
    nested = run.Heartbeat:Connect(function() count = count + 1 end)
end)
task.wait(0.03)
collectgarbage('collect')
collectgarbage('collect')
task.wait(0.08)
assert(count > 0, 'Nested callback must survive exporting coroutine collection')
nested:Disconnect()
script.Parent.NestedPassed = true
""")
		await create_timer(0.015).timeout
	for flag in ["ModulesPassed", "TasksPassed", "SignalsPassed", "NestedPassed"]:
		if not bool(workspace.get_meta(flag, false)):
			_failures.append(flag)
	print("[validate_lua_runtime_regressions] failures=", _failures, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts()
	workspace.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if _failures.is_empty() else 1)

func _node(parent: Node, node_name: String, class_name_value: String) -> Node:
	var child := Node.new()
	child.name = node_name
	child.set_meta("roblox_class", class_name_value)
	parent.add_child(child)
	return child

func _start(engine: Node, workspace: Node, node_name: String, source: String) -> void:
	var result: Dictionary = engine.start_script(source, _node(workspace, node_name, "Script"), {"realm": "server", "is_server": true})
	if not bool(result.get("ok", false)):
		_failures.append("%s: %s" % [node_name, result.get("error", "unknown error")])
