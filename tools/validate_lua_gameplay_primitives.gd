extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[gameplay_api] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	var scene := Node3D.new()
	scene.name = "World"
	scene.set_meta("roblox_class", "Workspace")
	scene.set_meta("roblox_stud_scale", 1.0)
	root.add_child(scene)
	current_scene = scene
	var floor_ := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(80, 1, 80)
	floor_.position.y = -0.5
	floor_.add_child(shape)
	scene.add_child(floor_)
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.name = "Character"
	character.set_meta("bobux_studio_playtest", true)
	scene.add_child(character)
	var engine := root.get_node("LuaScriptEngine")
	engine.bind_local_player_character(character)
	var context := Node.new()
	context.name = "GameplayPrimitives"
	scene.add_child(context)
	var source := """
local character = game:GetService('Players').LocalPlayer.Character
assert(Vector3.new(3,4,0).Magnitude == 5)
assert(Vector3.new(1,0,0):Dot(Vector3.new(2,0,0)) == 2)
assert(Vector3.new(1,0,0):Cross(Vector3.new(0,1,0)) == Vector3.new(0,0,1))
assert(Vector3.new(0,0,0):Lerp(Vector3.new(2,0,0), 0.5).X == 1)
assert(character == game:GetService('Players').LocalPlayer.Character)
local h = character:WaitForChild('Humanoid')
h:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
assert(h:GetStateEnabled(Enum.HumanoidStateType.Jumping) == false)
h:ChangeState(Enum.HumanoidStateType.Jumping)
assert(character.HumanoidRootPart.AssemblyLinearVelocity.Y == 0)
h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
h.UseJumpPower = false
h.JumpHeight = 20
h:ChangeState(Enum.HumanoidStateType.Jumping)
assert(character.HumanoidRootPart.AssemblyLinearVelocity.Y > 40)

local part = Instance.new('Part')
part.Name = 'Projectile'
part.Size = Vector3.new(1, 1, 1)
part.Position = Vector3.new(10, 8, 0)
part.Anchored = false
part.CanCollide = false
part.Parent = workspace
part.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
task.wait(0.3)
assert(part.Position.X > 11, 'Part velocity must move geometry')
print('checkpoint velocity')
local oldSize = part.Size
part.CFrame = CFrame.new(12, 8, 0)
assert(part.Size == oldSize, 'CFrame must preserve size')
print('checkpoint cframe')
part.Anchored = true
print('checkpoint froze')
local held = part.Position
task.wait(0.15)
print('checkpoint freeze wait', typeof(part.Position), typeof(held))
assert((part.Position - held).Magnitude < 0.1, 'Anchored must stop physics')
print('checkpoint frozen check')
part:Destroy()

print('checkpoint anchored')
local params = RaycastParams.new()
local position = character.HumanoidRootPart.Position
print('checkpoint ray setup')
local result = workspace:Raycast(position + Vector3.new(-10, 0, 0), Vector3.new(20, 0, 0), params)
print('checkpoint ray result')
print(result, result and result.Instance.Name, result and result.Instance.Parent.Name, character.Name)
assert(result and result.Instance.Parent == character, 'Raycast must hit character')
result.Instance.Parent.Humanoid:TakeDamage(12)
assert(h.Health == 88, 'ray hit damages real character')
local block = Instance.new('Part')
block.Name = 'DebrisTarget'
block.Anchored = true
block.Position = Vector3.new(20, 3, 0)
block.Size = Vector3.new(1,1,1)
block.Parent = workspace
local blast = Instance.new('Explosion')
blast.Position = Vector3.new(18,3,0)
blast.BlastRadius = 5
blast.BlastPressure = 300000
blast.DestroyJointRadiusPercent = 0
blast.Hit:Connect(function(hit, distance)
    if hit == block then
        hit.Anchored = false
        script:SetAttribute('ExplosionHit', distance)
    end
end)
blast.Parent = workspace
task.wait(0.3)
assert(script:GetAttribute('ExplosionHit'), 'explosion reports actual hit part')
assert(block.Position.X > 20.1, 'unanchored construction scatters from impulse')
script:SetAttribute('Completed', true)
"""
	check(bool(engine.start_script(source, context, {"retain": true}).ok), "general Lua script starts")
	await create_timer(1.2).timeout
	check(bool(context.get_meta("attribute_Completed", false)), "state control, physics and damage assertions pass")
	var model := Node3D.new()
	model.name = "Zombie"
	model.set_meta("roblox_class", "Model")
	model.position = Vector3(10, 3, 10)
	scene.add_child(model)
	var data_model := load("res://addons/roblox_studio/roblox_data_model.gd")
	var h: Node = data_model.create_instance("Humanoid", "Humanoid")
	model.add_child(h)
	var part: Node3D = data_model.create_instance("Part", "HumanoidRootPart")
	model.add_child(part)
	var script_node := Node.new()
	model.add_child(script_node)
	var movement := """
local npc = script.Parent
local humanoid = npc.Humanoid
humanoid.WalkSpeed = 8
humanoid.MoveToFinished:Connect(function(reached) script:SetAttribute('Reached', reached) end)
humanoid:MoveTo(npc.HumanoidRootPart.Position + Vector3.new(6, 0, 0))
"""
	engine.start_script(movement, script_node, {"retain": true})
	check(model.position.x < 10.1, "Humanoid MoveTo does not teleport")
	await create_timer(1.5).timeout
	check(model.position.x > 14 and bool(script_node.get_meta("attribute_Reached", false)), "NPC walks to goal and fires MoveToFinished")
	check(int(engine.get_runtime_diagnostics().failed) == 0, "no Lua failures")
	engine.stop_all_scripts()
	scene.queue_free()
	await process_frame
	await process_frame
	print("[gameplay_api] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
