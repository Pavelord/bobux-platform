extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var place := Node3D.new()
	root.add_child(place)
	current_scene = place
	var world := Node3D.new()
	world.name = "Workspace"
	world.position = Vector3(600000,0,630000)
	world.set_meta("roblox_class","Workspace")
	world.set_meta("roblox_stud_scale",.5)
	place.add_child(world)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex-tmp/performance/map-audit/lift-map-data.json"))
	engine.install_roblox_manifest(data.roblox_manifest,world)
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.world_stud_scale = .5
	character.set_meta("bobux_studio_playtest",true)
	character.set_meta("bobux_workspace_instance_id",world.get_instance_id())
	place.add_child(character)
	character.set_physics_process(false)
	engine.bind_local_player_character(character)
	engine.script_message.connect(func(context,message,error):
		if error or "floor tick:" in message: failures.append(str(context.name)+": "+message))
	var source := FileAccess.get_file_as_string("res://.codex-tmp/performance/map-audit/lift-script-2.luau")
	var cut := source.find("local function onCharacter(plr, ch)")
	if cut < 0: quit(2); return
	# Select the original floor and original tick/delay/damage functions only.
	# The fixture positions the player at the authored warning circle.
	source = source.substr(0,cut) + """
math.randomseed(20261010)
local plr=Players.LocalPlayer
local _,hum,hrp=charOf(plr)
assert(hum and hrp,'real character contract missing')
hum.Health=100
CurrentFloorFolder=Instance.new('Folder',workspace)
local def
for _,f in ipairs(Floors) do if f.name=='Метеоритный дождь' then def=f end end
assert(def,'authored meteor floor missing')
local ctx={}
def.build(CurrentFloorFolder,ctx)
ctx.next=0
hrp.CFrame=CFrame.new(0,2,-62)
def.tick(.05,ctx)
local mark
for _,p in ipairs(CurrentFloorFolder:GetChildren()) do
 if p:IsA('BasePart') and math.abs(p.Size.X-.2)<.01 and math.abs(p.Size.Y-8)<.01 then mark=p end
end
assert(mark,'authored meteor warning missing')
hrp.CFrame=CFrame.new(mark.Position+Vector3.new(0,2,0))
task.wait(1.8)
assert(hum.Health==55,'authored meteor delay lost real 45 HP damage: '..hum.Health)
assert(plr:GetAttribute('LastKiller')==nil,'nonlethal impact incorrectly killed player')
script:SetAttribute('MeteorPassed',true)
print('original Lift meteor real HP=',hum.Health)
"""
	var context := engine.find_instance_by_ref(world,str(data.roblox_manifest.scripts.filter(func(e): return e.name=="ElevatorServer")[0].ref)) as Node
	engine.reset_runtime_diagnostics()
	engine.start_script(source,context,{"realm":"server","is_server":true,"retain":true})
	var deadline := Time.get_ticks_msec()+12000
	while not context.get_meta("attribute_MeteorPassed",false) and engine.get_runtime_diagnostics().failed==0 and Time.get_ticks_msec()<deadline: await process_frame
	var passed: bool = context.get_meta("attribute_MeteorPassed",false) and failures.is_empty() and engine.get_runtime_diagnostics().failed==0
	print("[halloween-lift-meteor] PASS=",passed," health=",character.get_health()," diagnostics=",engine.get_runtime_diagnostics()," failures=",failures)
	engine.stop_all_scripts(place)
	place.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	quit(0 if passed else 1)
