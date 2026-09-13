extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	workspace.set_meta("roblox_stud_scale", 0.5)
	root.add_child(workspace)
	var context := Node.new()
	context.name = "LegacyDisasterRegression"
	context.set_meta("roblox_class", "Script")
	workspace.add_child(context)
	var source := """
local disaster = {}
disaster.Name = 'Meteor Shower'
disaster.Value = 7
assert(disaster.Name == 'Meteor Shower' and disaster.Value == 7, 'ordinary Lua table properties')
local seen = 0
workspace.ChildAdded:Connect(function(item)
    assert(item ~= nil, 'ChildAdded argument was lost')
    if item.Name == 'EventProbe' then seen = seen + 1 end
end)
local part = Instance.new('Part')
part.Name = 'EventProbe'
part.Anchored = true
part.Position = Vector3.new(2, 20, 0)
part.Parent = workspace
task.wait(0.02)
assert(seen == 1, 'ChildAdded must fire once with the correct Instance')
assert(part.className == 'Part', 'legacy className')
local region = Region3.new(Vector3.new(-2, 17, -3), Vector3.new(5, 23, 3))
local hits = workspace:FindPartsInRegion3(region, nil, 20)
assert(#hits == 1 and hits[1] == part, 'legacy Region3 query')
assert(#workspace:FindPartsInRegion3(region, part, 20) == 0, 'Region3 ignore')
game.Debris:AddItem(part, 0.02)
task.wait(0.08)
assert(part.Parent == nil, 'legacy game.Debris path')
local template = Instance.new('Script')
template.Name = 'ClonedScript'
template.Disabled = true
template.Source = "script.Parent:SetAttribute('CloneExecuted', true)"
local clone = template:Clone()
clone.Disabled = false
clone.Parent = workspace
task.wait(0.1)
assert(workspace:GetAttribute('CloneExecuted'), 'enabled cloned Workspace script')
script:SetAttribute('LuaPassed', true)
"""
	var started: Dictionary = engine.start_script(source, context, {"realm": "server"})
	if not started.get("ok", false): failures.append(str(started))
	await create_timer(0.8).timeout
	if not context.get_meta("attribute_LuaPassed", false): failures.append("Lua integration")
	var model := Node3D.new()
	model.set_meta("roblox_class", "Model")
	workspace.add_child(model)
	var lower := _part(model, Vector3(0, 5, 0), true)
	var upper := _part(model, Vector3(0, 6, 0), false)
	var neighbor := _part(model, Vector3(4, 6, 0), false)
	engine.BobuxInstance.new(model).MakeJoints()
	var physics := preload("res://addons/roblox_runtime/roblox_part_physics.gd")
	if physics.body_for(lower) != physics.body_for(upper): failures.append("stud/inlet assembly missing")
	if physics.body_for(neighbor) == physics.body_for(lower): failures.append("non-touching part incorrectly joined")
	var initial := upper.global_position
	await create_timer(0.15).timeout
	if upper.global_position.distance_to(initial) > 0.03: failures.append("anchored assembly drifted")
	engine.BobuxInstance.new(upper).BreakJoints()
	engine.BobuxInstance.new(upper)._set(&"Velocity", Vector3(20, 15, 0))
	await create_timer(0.2).timeout
	if physics.body_for(lower) == physics.body_for(upper): failures.append("BreakJoints did not separate the part")
	print("[assembly] visual=",upper.global_position," body=",physics.body_for(upper).global_position," velocity=",physics.body_for(upper).linear_velocity," freeze=",physics.body_for(upper).freeze," groups=",model.get_node("RobloxSurfaceJoints/WeldedAssemblies").groups.size())
	if upper.global_position.x <= initial.x + 0.2: failures.append("detached part did not move")
	print("[legacy_disaster_runtime] failures=", failures, " diagnostics=", engine.get_runtime_diagnostics())
	engine.stop_all_scripts(workspace)
	workspace.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if failures.is_empty() else 1)

func _part(parent: Node, position_: Vector3, anchored: bool) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.position = position_
	part.set_meta("roblox_class", "Part")
	part.set_meta("anchored", anchored)
	part.set_meta("roblox_properties", {"TopSurface": 3, "BottomSurface": 4})
	parent.add_child(part)
	return part
