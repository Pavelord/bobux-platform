extends SceneTree

func _initialize() -> void:
	await process_frame
	var engine := root.get_node("LuaScriptEngine")
	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	root.add_child(workspace)
	var script_node := Node.new()
	workspace.add_child(script_node)
	var source := """
local remote = Instance.new('RemoteEvent', workspace)
local player = game:GetService('Players').LocalPlayer
local seen = false
remote.OnServerEvent:Connect(function(sender, a, b, c, d, ...)
    print('payload', sender.Name, a, b, c, d, select('#', ...))
    assert(sender.Name == player.Name, 'remote sender')
    assert(a == 1 and b == nil and c == 3 and d == 4, 'remote payload order')
    assert(select('#', ...) == 1, 'remote trailing nil')
    seen = true
end)
remote:FireServer(1, nil, 3, 4, nil)
assert(seen, 'server event callback')
local clientSeen = false
remote.OnClientEvent:Connect(function(a, b, c)
    assert(a == 'reply' and b == nil and c == 7, 'client payload')
    clientSeen = true
end)
remote:FireClient(player, 'reply', nil, 7)
assert(clientSeen, 'target client callback')
local event = Instance.new('BindableEvent', workspace)
local count = 0
event.Event:Connect(function(...) count = select('#', ...) end)
event:Fire(1, 2, nil, 4, 5, nil)
assert(count == 6, 'bindable arbitrary arity')
local func = Instance.new('RemoteFunction', workspace)
func.OnServerInvoke = function(sender, a, b, c)
    assert(sender.Name == player.Name and b == nil, 'invoke sender/payload')
    return a + c
end
assert(func:InvokeServer(2, nil, 5) == 7, 'invoke response')
local model = Instance.new('Model', workspace)
assert(not model:IsA('BasePart'), 'Model is not BasePart')
local part = Instance.new('Part', model)
part.Name = 'Center'
part.Position = Vector3.new(15, 20, 25)
model.PrimaryPart = part
model:SetPrimaryPartCFrame(CFrame.new(2, 3, 4))
assert((part.Position - Vector3.new(2, 3, 4)).Magnitude < 0.01, 'PrimaryPart placement')
workspace.ContractsPassed = true
"""
	var result: Dictionary = engine.start_script(source, script_node, {"retain": true})
	for frame in range(40):
		await create_timer(0.01).timeout
	var ok := bool(workspace.get_meta("ContractsPassed", false))
	print("[validate_roblox_import_contracts] ok=", ok, " start=", result, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts()
	workspace.queue_free()
	await process_frame
	quit(0 if ok else 1)
