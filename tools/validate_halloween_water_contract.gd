extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	world.name = "Workspace"
	world.position = Vector3(600000,0,630000)
	world.set_meta("roblox_class","Workspace")
	world.set_meta("roblox_stud_scale",.5)
	root.add_child(world)
	var structure := Node3D.new()
	structure.name = "Structure"
	structure.set_meta("roblox_class","Model")
	world.add_child(structure)
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.world_stud_scale = .5
	character.set_meta("bobux_studio_playtest",true)
	character.set_meta("bobux_workspace_instance_id",world.get_instance_id())
	world.add_child(character)
	character.set_physics_process(false)
	var engine := root.get_node("LuaScriptEngine")
	engine.bind_local_player_character(character)
	var context := Node.new()
	world.add_child(context)
	var original := FileAccess.get_file_as_string("res://.codex-tmp/performance/map-audit/nds-current-script-001.luau").replace("\r","")
	var begin := original.find("function archiveWaveHit(")
	var end := original.find("function archiveFunnel(",begin)
	if begin<0 or end<0: quit(2); return
	# Run the exact published collision function, not a synthesized damage test.
	var source := "local archiveWaveDamaged={} local archiveWaveParts={}\n"+original.substr(begin,end-begin)+"""
waveangle=0; wavehight=50; wavelength=500
local ch=game.Players.LocalPlayer.Character
local h=ch.Humanoid
local torso=ch.Torso
local function checkPoint(p,expected,label)
 h.Health=100
 torso.CFrame=CFrame.new(p)
 local wave=Instance.new('Model',workspace.Structure)
 archiveWaveHit(wave,CFrame.new(0,36,0),Vector3.new(-1,0,0),50)
 assert(h.Health==expected,label..' health='..h.Health)
 wave:Destroy()
end
checkPoint(Vector3.new(60,36,0),100,'ahead of visible wave')
checkPoint(Vector3.new(-110,36,0),100,'behind visible wave')
checkPoint(Vector3.new(0,36,260),100,'outside wave width')
checkPoint(Vector3.new(0,80,0),100,'above wave')
checkPoint(Vector3.new(0,36,0),0,'inside wave')
script:SetAttribute('WaterPassed',true)
"""
	engine.reset_runtime_diagnostics()
	engine.start_script(source,context,{"realm":"server","retain":true})
	var deadline := Time.get_ticks_msec()+5000
	while not context.get_meta("attribute_WaterPassed",false) and engine.get_runtime_diagnostics().failed==0 and Time.get_ticks_msec()<deadline: await process_frame
	var passed: bool = context.get_meta("attribute_WaterPassed",false) and engine.get_runtime_diagnostics().failed==0
	print("[halloween-water-contract] PASS=",passed," nonzero_origin=",world.global_position," diagnostics=",engine.get_runtime_diagnostics())
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if passed else 1)
