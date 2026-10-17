extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("[halloween-character] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var world := Node3D.new()
	world.name = "ContractWorkspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	world.position = Vector3(600000, 0, 630000)
	root.add_child(world)
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.name = "1"
	character.world_stud_scale = 0.5
	character.set_meta("bobux_studio_playtest", true)
	character.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	world.add_child(character)
	character.set_physics_process(false)
	character.position = Vector3(15, 7, -12)
	var script_node := Node.new()
	world.add_child(script_node)
	var engine := root.get_node("LuaScriptEngine")
	engine.bind_local_player_character(character)
	var torso := character.get_node("Torso") as Node3D
	var query := preload("res://addons/roblox_runtime/roblox_spatial_query.gd")
	var outside := query.in_box(world,Transform3D(Basis.IDENTITY,torso.global_position+Vector3(.8,0,0)),Vector3.ONE*.1,[],false,0,false)
	check(not outside.has(torso),"spatial queries use the visible torso scale rather than double-sized proxies")
	var result: Dictionary = engine.start_script("""
local ch=game.Players.LocalPlayer.Character
local h=ch:FindFirstChildOfClass('Humanoid')
h.Health=100
local events=0
h.HealthChanged:Connect(function() events+=1 end)
for i=1,60 do h:TakeDamage(4/60) end
assert(math.abs(h.Health-96)<0.0001,'fractional damage was lost: '..tostring(h.Health))
assert(events==60,'fractional HealthChanged callbacks were dropped')
h.MaxHealth=150.5
h.Health=150.25
assert(h.MaxHealth==150.5 and h.Health==150.25,'fractional/dynamic MaxHealth lost')
h.Health=96
print('contract root=',ch.HumanoidRootPart.Position,'head=',ch.Head.Position)
assert(math.abs(ch.HumanoidRootPart.Position.X-30)<0.1 and math.abs(ch.HumanoidRootPart.Position.Z-24)<0.1,'root part world origin leaked')
assert((ch.Head.Position-ch.HumanoidRootPart.Position).Magnitude<8,'head scale/origin differs from root')
script:SetAttribute('HealthPassed',true)
local cam=workspace.CurrentCamera
assert(cam,'active camera missing')
cam.CameraType=Enum.CameraType.Scriptable
cam.CFrame=CFrame.lookAt(Vector3.new(10,20,30),Vector3.new(0,1,0))
script:SetAttribute('CameraWritten',true)
task.wait(0.3)
assert((cam.CFrame.Position-Vector3.new(10,20,30)).Magnitude<0.1,'SpringArm/character overwrote Scriptable camera')
cam.CameraType=Enum.CameraType.Custom
task.wait(0.3)
script:SetAttribute('Done',true)
""", script_node, {"retain":true})
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec()<deadline and not script_node.get_meta("attribute_Done",false) and engine.get_runtime_diagnostics().failed==0:
		await process_frame
		character._update_local_camera_rig_render_phase(0.016)
	check(result.get("ok",false) and script_node.get_meta("attribute_HealthPassed",false), "actual Luau fractional damage, events, MaxHealth and nonzero room coordinates")
	check(script_node.get_meta("attribute_Done",false), "Scriptable camera survives player render and SpringArm physics, Custom restores")
	check(not character.player_camera.top_level and character.player_camera.position.distance_to(Vector3(0,0,character.spring_arm.get_hit_length()))<0.1,"camera returned to player rig")
	check(engine.get_runtime_diagnostics().failed==0,"no unexpected Luau failure")
	engine.stop_all_scripts(world)
	print("[halloween-character] failures=",failures)
	quit(0 if failures.is_empty() else 1)
