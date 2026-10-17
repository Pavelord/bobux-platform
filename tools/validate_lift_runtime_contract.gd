extends SceneTree

const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
	print("[lift_contract] ", "PASS " if value else "FAIL ", label)

func module(parent: Node, label: String, source: String) -> Node:
	var node := DATA.create_instance("ModuleScript", label)
	node.set_meta("code", source)
	parent.add_child(node)
	return node

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "LiftContract"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	module(world, "Leaf", "return {value = 19}")
	module(world, "Nested", "local leaf = require(script.Parent.Leaf); local Class = {}; Class.__index = Class; function Class.new() return setmetatable({value = leaf.value}, Class) end; return Class")
	module(world, "Waiting", "task.wait(0.02); return {finished = true}")
	module(world, "Circular", "return require(script)")
	var context := Node.new()
	world.add_child(context)
	var result: Dictionary = engine.start_script("""
local Class = require(script.Parent.Nested)
assert(rawequal(Class, require(script.Parent.Nested)), 'module cache identity changed')
assert(Class.new().value == 19 and Class.__index == Class, 'nested module/class metatable lost')
assert(require(script.Parent.Waiting).finished, 'yielding module did not resume')
local circularOk, circularError = pcall(require, script.Parent.Circular)
assert(not circularOk and string.find(circularError, 'Circular ModuleScript'), 'circular require must fail without crashing')
script.Parent:SetAttribute('Modules', true)

local p = Instance.new('Part')
p.Name = 'Cylinder'
p.Anchored = true
p.Size = Vector3.new(6, 1.5, 6)
p.Shape = Enum.PartType.Cylinder
p.Parent = script.Parent
local light = Instance.new('PointLight')
light.Name = 'ElevatorLamp'
light.Color = Color3.fromRGB(255, 40, 20)
light.Brightness = 2.5
light.Range = 18
light.Parent = p
assert(light.Brightness == 2.5 and light.Range == 18, 'light properties lost their units')
local frame = Instance.new('Frame')
frame.Name = 'Tweened'
frame.Size = UDim2.new(0.2, 10, 0.4, 20)
frame.Position = UDim2.new(0.1, 5, 0.2, 6)
frame.Parent = script.Parent
local tween = game:GetService('TweenService'):Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
    Size = UDim2.new(0.8, 40, 0.6, 60), Position = UDim2.new(0.3, 15, 0.8, 26)
})
tween:Play()
task.wait(0.09)
script.Parent:SetAttribute('TweenMid', true)
task.wait(0.2)
script.Parent:SetAttribute('Done', true)
""", context, {"retain": true})
	var midpoint := {}
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and not world.get_meta("attribute_Done", false) and engine.get_runtime_diagnostics().failed == 0:
		await process_frame
		if world.get_meta("attribute_TweenMid", false) and midpoint.is_empty():
			var control := world.get_node_or_null("Tweened")
			if control != null: midpoint = control.get_meta("roblox_properties", {}).get("Size", {}).duplicate(true)
	check(result.get("ok", false) and world.get_meta("attribute_Done", false), "actual Luau executes runtime contract")
	check(world.get_meta("attribute_Modules", false), "nested, yielding and recursive-table ModuleScripts keep identity")
	check(float(midpoint.get("x", {}).get("scale", 0)) > 0.2 and float(midpoint.get("x", {}).get("scale", 1)) < 0.8, "UDim2 scale interpolates before completion")
	check(float(midpoint.get("x", {}).get("offset", 0)) > 10 and float(midpoint.get("x", {}).get("offset", 99)) < 40, "UDim2 offset interpolates before completion")
	var cylinder := world.get_node_or_null("Cylinder") as MeshInstance3D
	check(cylinder != null and cylinder.mesh is CylinderMesh and cylinder.get_meta("shape_type", "") == "Cylinder", "PartType.Cylinder creates cylindrical geometry")
	var light := world.get_node_or_null("Cylinder/ElevatorLamp") as OmniLight3D
	check(light != null and is_equal_approx(light.light_energy, 2.5) and is_equal_approx(light.omni_range, 9) and light.light_color.is_equal_approx(Color(1, 40.0/255.0, 20.0/255.0)), "PointLight setters update the native renderer")
	check(engine.get_runtime_diagnostics().failed == 0, "no runtime error")
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	print("[lift_contract] failures=", failures)
	quit(0 if failures.is_empty() else 1)
