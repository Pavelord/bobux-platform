extends SceneTree

const Motor = preload("res://addons/roblox_runtime/roblox_humanoid_motor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print("[humanoid-npc] ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var engine_script = load("res://autoload/lua_script_engine.gd")
	var world := Node3D.new()
	world.name = "NPCContractWorkspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	var model := Node3D.new()
	model.name = "NPC"
	model.position = Vector3(3, 20, -4)
	model.set_meta("roblox_class", "Model")
	world.add_child(model)
	var root_part := Node3D.new()
	root_part.name = "HumanoidRootPart"
	root_part.set_meta("roblox_class", "Part")
	model.add_child(root_part)
	var humanoid := Node.new()
	humanoid.name = "Humanoid"
	humanoid.set_meta("roblox_class", "Humanoid")
	model.add_child(humanoid)
	var motor := Motor.ensure(humanoid)
	check(motor != null, "authored model receives motor without replacing Instance tree")
	motor.set_physics_process(false)
	var camera := Camera3D.new()
	camera.name = "ContractCamera"
	world.add_child(camera)
	camera.make_current()
	camera.rotation.y = PI / 2.0
	var target := Node3D.new()
	target.name = "MovingTarget"
	target.set_meta("roblox_class", "Part")
	world.add_child(target)
	target.position = Vector3(4, 0, 0)
	var context := Node.new()
	context.name = "NPCScript"
	model.add_child(context)
	var script := """
local h = script.Parent.Humanoid
local enum = Enum.HumanoidStateType
local expected = {FallingDown=0,Ragdoll=1,GettingUp=2,Jumping=3,Swimming=4,Freefall=5,Flying=6,Landed=7,Running=8,RunningNoPhysics=10,StrafingNoPhysics=11,Climbing=12,Seated=13,PlatformStanding=14,Dead=15,Physics=16,None=18}
for name,id in pairs(expected) do assert(enum[name] == id, 'wrong state ID: '..name) end
assert(enum.Standing == nil and enum.LedgeGrab == nil, 'custom state leaked into Roblox enum')
assert(h.UseJumpPower == true and h.JumpHeight == 7.2, 'jump defaults differ')
assert(h.RigType == Enum.HumanoidRigType.R6 and Enum.HumanoidRigType.R15 == 1, 'RigType enum/default absent')
assert(h.RootPart.Name == 'HumanoidRootPart', 'RootPart binding absent')
assert(workspace.Gravity == 196.2, 'workspace default gravity absent')

local enabledEvents = 0
h.StateEnabledChanged:Connect(function(state, enabled)
 assert(type(enabled) == 'boolean', 'StateEnabledChanged bool missing')
 enabledEvents += 1
end)
h:SetStateEnabled(enum.Jumping, false)
h:SetStateEnabled(enum.Jumping, false)
h:ChangeState(enum.Jumping)
assert(h:GetState() == enum.Running, 'disabled state entered')
h:SetStateEnabled(enum.Jumping, true)
h:SetStateEnabled(enum.Jumping, true)
task.wait(0.03)
assert(enabledEvents == 4, 'StateEnabledChanged must fire for every call, including unchanged values')

local entries = {}
for _,name in ipairs({'Jumping','FreeFalling','FallingDown','GettingUp','PlatformStanding','Ragdoll'}) do
 h[name]:Connect(function(active)
  assert(type(active) == 'boolean', name..' active argument is wrong')
  table.insert(entries, name..':'..tostring(active))
 end)
end
local seats = {}
h.Seated:Connect(function(...)
 assert(select('#',...) == 2, 'Seated must retain two arguments including nil on exit')
 local active,seat = ...
 assert(type(active) == 'boolean', 'Seated active missing')
 table.insert(seats, active)
end)
h:ChangeState(enum.FallingDown)
h:ChangeState(enum.GettingUp)
h:ChangeState(enum.Ragdoll)
h:ChangeState(enum.PlatformStanding)
h:ChangeState(enum.Seated)
h:ChangeState(enum.Running)
task.wait(0.03)
assert(#entries == 8, 'Boolean entry/exit signals not balanced: '..tostring(#entries))
assert(entries[1] == 'FallingDown:true' and entries[2] == 'FallingDown:false' and entries[3] == 'GettingUp:true', 'transition signal order/args wrong')
assert(#seats == 2 and seats[1] == true and seats[2] == false, 'Seated delivered duplicates or missed exit')

h:Move(Vector3.new(0,0,-0.5), true)
assert(math.abs(h.MoveDirection.X+1) < 0.0001, 'relativeToCamera moved backwards or used world axes')
h:Move(Vector3.new(0.5,0,0), false)
assert(math.abs(h.MoveDirection.X-1) < 0.0001, 'world-space Move mirrored X')
h:MoveTo(Vector3.new(12,0,0), workspace.MovingTarget)
assert(h.WalkToPart.Name == 'MovingTarget' and h.WalkToPoint.X == 12, 'MoveTo part/point binding absent')
h:Move(Vector3.new(0,0,0), false)
assert(h.MoveDirection.Magnitude == 0, 'Move did not stop NPC')
local function assertInvalidNumbersPreserved(target)
 for _,property in ipairs({'Health','MaxHealth','WalkSpeed','JumpPower','JumpHeight','HipHeight','MaxSlopeAngle'}) do
  local before = target[property]
  local invalids = property == 'MaxHealth' and {0/0,-math.huge} or {0/0,math.huge,-math.huge}
  for _,invalid in ipairs(invalids) do
   target[property] = invalid
   assert(target[property] == before, 'invalid numeric write changed '..property)
  end
 end
end
assertInvalidNumbersPreserved(h)
local unbound = Instance.new('Humanoid')
unbound.Parent = workspace
assertInvalidNumbersPreserved(unbound)
unbound.MaxHealth = math.huge
unbound.Health = math.huge
assert(unbound.MaxHealth == math.huge and unbound.Health == math.huge, 'infinite logical health must remain supported')
unbound:TakeDamage(100)
assert(unbound.Health == math.huge, 'finite damage poisoned infinite health')
unbound:Destroy()
script:SetAttribute('APIPassed', true)

h.Health = 60
h:TakeDamage(-0.25)
assert(h.Health == 60.25, 'negative TakeDamage must heal')
local field = Instance.new('ForceField')
field.Name = 'RenamedProtection'
field.Parent = h.RootPart
h:TakeDamage(10)
h:TakeDamage(-10)
assert(h.Health == 60.25, 'root ForceField must block damage and healing')
field.Parent = h.Parent
h:TakeDamage(10)
assert(h.Health == 60.25, 'renamed parent ForceField not recognized')
field.Parent = workspace
h:TakeDamage(0.25)
assert(h.Health == 60, 'Workspace ForceField must not protect all characters')
field:Destroy()
h.Health=100

local healthArgs = 0
local died = 0
h.HealthChanged:Connect(function(...)
 assert(select('#', ...) == 1, 'HealthChanged must have one argument')
 healthArgs += 1
end)
h.Died:Connect(function(...) assert(select('#', ...) == 0, 'Died must have zero args'); died += 1 end)
h:TakeDamage(0.25)
assert(h.Health == 99.75, 'fractional NPC damage lost')
h:ChangeState(enum.Dead)
task.wait(0.03)
assert(h.Health == 0 and h:GetState() == enum.Dead, 'ChangeState Dead did not kill NPC')
assert(died == 1 and healthArgs == 2, 'NPC death/health signals repeated')
h.Health=100
assert(h.Health==0, 'dead NPC was revived by a Health assignment')
script:SetAttribute('Done', true)
"""
	var result: Dictionary = engine.start_script(script, context, {"retain": true})
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and not context.get_meta("attribute_Done", false) and engine.get_runtime_diagnostics().failed == 0:
		await process_frame
	check(result.get("ok", false) and context.get_meta("attribute_APIPassed", false), "real Luau enum, shared signals, Move, camera axes, moving target")
	check(context.get_meta("attribute_Done", false), "real Luau NPC fractional health and idempotent death")
	check(engine.get_runtime_diagnostics().failed == 0, "no Luau execution error")
	# The real camera is also pitched, so camera-relative motion must remain
	# horizontal while retaining the rendered forward direction.
	camera.rotation = Vector3(-0.7, -PI / 2.0, 0.0)
	var proxy_move = engine_script.BobuxInstance.wrap(humanoid)
	proxy_move._humanoid_move(Vector3(0, 0, -0.5), true)
	check(proxy_move._get(&"MoveDirection").distance_to(Vector3.RIGHT) < 0.0001, "pitched camera-relative Move uses horizontal visible forward")

	# A fresh NPC stays alive for physical tests. These compare our documented
	# contract and scale consistency, not undocumented Roblox timings.
	var physical_model := Node3D.new()
	physical_model.name = "PhysicalNPC"
	physical_model.position.y = 40
	world.add_child(physical_model)
	var physical_root := Node3D.new()
	physical_root.name = "HumanoidRootPart"
	physical_model.add_child(physical_root)
	var physical_h := Node.new()
	physical_h.name = "Humanoid"
	physical_h.set_meta("roblox_class", "Humanoid")
	physical_model.add_child(physical_h)
	var physics_motor := Motor.ensure(physical_h)
	physics_motor.set_physics_process(false)
	check(is_equal_approx(physics_motor.get_workspace_gravity(), 196.2), "NPC default gravity is 196.2 stud/s2")
	world.set_meta("Gravity", 40.0)
	check(is_equal_approx(physics_motor.get_workspace_gravity(), 40.0), "NPC sees live workspace Gravity mutation")
	physical_h.set_meta("UseJumpPower", false)
	physical_h.set_meta("JumpHeight", 10.0)
	physics_motor.request_humanoid_state(3)
	check(is_equal_approx(physics_motor.velocity.y, sqrt(800.0) * 0.5), "NPC JumpHeight uses live gravity and existing scale (ballistic approximation)")
	var upward_velocity := physics_motor.velocity.y
	physics_motor.request_humanoid_state(5)
	check(is_equal_approx(physics_motor.velocity.y, upward_velocity), "explicit Freefall keeps ascending momentum")
	physical_h.set_meta("UseJumpPower", true)
	physical_h.set_meta("JumpPower", 30.0)
	physics_motor.request_humanoid_state(3)
	check(is_equal_approx(physics_motor.get_humanoid_jump_power(), 30.0) and physics_motor.velocity.y > 15.0 and physics_motor.velocity.y < 16.0, "NPC authored JumpPower stays literal while calibrated motion preserves stud scale")
	var speed_before: float = physics_motor.get_humanoid_walk_speed()
	var power_before: float = physics_motor.get_humanoid_jump_power()
	physics_motor.set_humanoid_walk_speed(INF)
	physics_motor.set_humanoid_walk_speed(NAN)
	physics_motor.set_humanoid_jump_power(INF)
	physics_motor.set_humanoid_jump_power(NAN)
	check(physics_motor.get_humanoid_walk_speed() == speed_before and physics_motor.get_humanoid_jump_power() == power_before, "direct NPC numeric setters reject NaN/Inf and preserve values")
	physics_motor.request_humanoid_state(16)
	physics_motor.velocity = Vector3(1, 0, -2)
	physics_motor.set_physics_process(true)
	await physics_frame
	var before := physics_motor.velocity
	for _i in range(6): await physics_frame
	var after := physics_motor.velocity
	physics_motor.set_physics_process(false)
	check(absf((after.y-before.y)+2.0) < 0.03 and is_equal_approx(after.x, before.x) and is_equal_approx(after.z,before.z), "Physics state preserves horizontal momentum, uses world gravity over six real ticks")
	physics_motor.request_humanoid_state(8)
	target.position = Vector3(8, 40, 0)
	physics_motor.move_to_part(Vector3(12, 40, 0), target)
	var target_local := target.to_local(Vector3(12, 40, 0))
	target.position += Vector3(3, 0, 2)
	target.rotation.y = PI / 2.0
	physics_motor.set_physics_process(true)
	for _i in range(2): await physics_frame
	physics_motor.set_physics_process(false)
	check(physics_motor.destination.distance_to(target.to_global(target_local)) < 0.0001, "MoveTo follows moved and rotated target with original local offset")
	physics_motor.set_lua_position(Vector3(0, 4, 0))
	check(not physics_motor.has_destination, "root CFrame/position teleport cancels moving-target walk")
	var floor := StaticBody3D.new()
	floor.name = "PhysicalFloor"
	floor.position.y = -0.5
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	world.add_child(floor)
	var observed_states: Array[int] = [physics_motor.get_runtime_humanoid_state()]
	var state_proxy = engine_script.BobuxInstance.wrap(physical_h)
	state_proxy._shared_event("StateChanged").Connect(func(_previous, next): observed_states.append(int(next)))
	physics_motor.velocity = Vector3.ZERO
	physics_motor.set_physics_process(true)
	for _i in range(90):
		await physics_frame
		if physics_motor.is_on_floor() and physics_motor.get_runtime_humanoid_state() == 8: break
	physics_motor.set_physics_process(false)
	check(observed_states.has(5) and observed_states.has(7) and observed_states.back() == 8, "actual NPC floor contact publishes Freefall, Landed, then Running")

	var proxy = engine_script.BobuxInstance.wrap(physical_h)
	physical_h.set_meta("HumanoidState", "RunningNoPhysics")
	physical_h.set_meta("bobux_character_body_instance_id", 0)
	check(proxy.GetState() == 10, "GetState string RunningNoPhysics resolves to ID 10")
	engine.stop_all_scripts(world)
	world.queue_free()
	for _i in range(4): await process_frame
	print("[humanoid-npc] failures=", failures)
	quit(0 if failures.is_empty() else 1)
