extends SceneTree

const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
const QUERY = preload("res://addons/roblox_runtime/roblox_spatial_query.gd")
const PARTICLES = preload("res://addons/roblox_runtime/roblox_particles.gd")
const GUI = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, detail: String):
 if not ok: failures.append(detail)
func run():
 var engine=root.get_node("LuaScriptEngine")
 var workspace=Node3D.new()
 workspace.name="Workspace"
 workspace.set_meta("roblox_class","Workspace")
 workspace.set_meta("roblox_stud_scale",0.5)
 root.add_child(workspace)
 var character=load("res://scenes/player/player.tscn").instantiate()
 character.set_meta("bobux_studio_playtest",true)
 workspace.add_child(character)
 character.set_physics_process(false)
 character.apply_world_stud_scale(0.5)
 character.ensure_roblox_character_contract()
 engine.bind_local_player_character(character)
 var torso=engine.BobuxInstance.new(character.get_node("Torso"))
 var humanoid=engine.BobuxInstance.new(character.get_node("Humanoid"))
 check(torso._get(&"Anchored")==false,"character wrongly anchored in Lua")
 check(torso._get(&"CanCollide")==true,"character collision property")
 torso._set(&"Velocity",Vector3(60,120,20))
 check(character.velocity.is_equal_approx(Vector3(30,60,-10)),"tornado velocity does not reach CharacterBody")
 check(torso._get(&"Velocity").is_equal_approx(Vector3(60,120,20)),"character velocity reads wrong units")
 var hits=QUERY.in_box(workspace, Transform3D(Basis.IDENTITY,character.get_node("Torso").global_position),Vector3.ONE*8,[],false,0,false)
 check(hits.has(character.get_node("Torso")),"wave/region queries omit character")
 humanoid._set(&"Health",90)
 check(character.get_health()==90,"flood Health assignment has no effect")
 var context=DATA.create_instance("Script","DamageProbe")
 workspace.add_child(context)
 var source="""
local p=game.Players.LocalPlayer
local h=p.Character.Humanoid
h.Died:Connect(function() script:SetAttribute('Died',true) end)
local count=0
for _,item in ipairs(workspace:GetPartBoundsInBox(p.Character.Torso.CFrame,Vector3.new(8,8,8))) do
    if item.Parent==p.Character then count=count+1 end
end
assert(count>0,'Lua spatial queries lost character Parts')
script:SetAttribute('QueryPassed',true)
"""
 engine.start_script(source,context,{"realm":"server"})
 await create_timer(0.2).timeout
 torso.BreakJoints()
 await create_timer(0.2).timeout
 check(character.get_health()==0,"meteor BreakJoints does not kill")
 check(context.get_meta('attribute_Died',false),"Humanoid.Died is not emitted")
 check(context.get_meta('attribute_QueryPassed',false),"Lua character query integration")
 character.respawn_at_checkpoint()
 check(character.get_health()==100,"local respawn fails to restore health")
 var wave_probe=DATA.create_instance("Script","WaveProbe")
 workspace.add_child(wave_probe)
 var wave_source=preload("res://addons/rbxl_importer/legacy_place_migrations.gd").HELPERS+"""
waveangle=0
wavehight=50
wavelength=500
local h=game.Players.LocalPlayer.Character.Humanoid
local torso=game.Players.LocalPlayer.Character.Torso
torso.CFrame=CFrame.new(0,100,0)
local wave=Instance.new('Model',workspace)
archiveWaveHit(wave,CFrame.new(-300,100,0),Vector3.new(-1,0,0),50)
assert(h.Health==100,'wave kills before it reaches the player')
archiveWaveHit(wave,CFrame.new(300,100,0),Vector3.new(-1,0,0),50)
assert(h.Health==0,'swept tsunami does not kill the player')
script:SetAttribute('WavePassed',true)
"""
 engine.start_script(wave_source,wave_probe,{"realm":"server"})
 await create_timer(0.5).timeout
 check(wave_probe.get_meta('attribute_WavePassed',false),"tsunami swept player damage integration")

 var dm=DATA.new()
 var smoke=DATA.create_instance("Smoke","Smoke")
 workspace.add_child(smoke)
 engine._apply_manifest_entry_metadata(smoke,{"class":"Smoke","properties":{"Size":[1,1,1],"size_xml":60,"Enabled":true,"riseVelocity_xml":25}})
 check(smoke.draw_pass_1.size.x==30,"old saved array Size crashes/loses scalar Smoke.Size")
 for invalid in [null,{},[1,2,3],"wrong",INF]:
  smoke.set_meta("Size",invalid)
  PARTICLES.configure(smoke)
 check(smoke.draw_pass_1!=null,"invalid particle data crashes loading")
 smoke.set_meta("Size",24.0)
 var serialized=dm._serialize_node_properties(smoke,"Smoke")
 check(serialized.Size==24.0,"save overwrites particle Size with transform scale")
 var restored=DATA.create_instance("Smoke","RestoredSmoke")
 workspace.add_child(restored)
 engine._apply_manifest_entry_metadata(restored,{"class":"Smoke","properties":JSON.parse_string(JSON.stringify(serialized))})
 check(restored.draw_pass_1.size.x==12.0,"particle save/load size changed")

 var screen=DATA.create_instance("ScreenGui","Screen")
 workspace.add_child(screen)
 var frame=DATA.create_instance("Frame","List")
 screen.add_child(frame)
 var props={"Size":{"x":{"scale":0.5,"offset":0},"y":{"scale":0.5,"offset":0}},"Position":{"x":{"scale":0.5,"offset":0},"y":{"scale":0.1,"offset":0}}}
 frame.set_meta("roblox_properties",props)
 var rect=GUI.absolute_rect(frame)
 check(rect.size.y>100,"AbsoluteSize of scale-based GUI is zero")
 var saved_gui=dm._serialize_node_properties(frame,"Frame")
 check(saved_gui.Size.y.scale==0.5 and saved_gui.Position.x.scale==0.5,"publication flattens GUI UDim2 scales")
 var wrapper=engine.BobuxInstance.new(frame)
 check(wrapper._get(&"AbsoluteSize")==rect.size,"Lua AbsoluteSize does not use rendered layout")
 var wedge=DATA.create_instance("WedgePart","Wedge")
 workspace.add_child(wedge)
 check(wedge.mesh is ArrayMesh,"Instance.new WedgePart creates cube")
 check(QUERY.collision_shape(wedge) is ConvexPolygonShape3D,"wedge physics still a box")
 var arrays=wedge.mesh.surface_get_arrays(0)
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 for i in range(0,indices.size(),3):
  var a=indices[i]
  var b=indices[i+1]
  var c=indices[i+2]
  check((vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normals[a])<0,"wedge winding culls outer face")
 var flood=DATA.create_instance("Part","FloodLevel")
 workspace.add_child(flood)
 flood.scale=Vector3(5,0.5,5)
 var importer=preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
 importer.scale_factor=0.5
 importer._apply_mesh_runtime_to_parent(flood,"BlockMesh",{"scale":[1000,0.1,1000],"mesh_type":0},null)
 check(flood.scale==Vector3(5,0.5,5),"BlockMesh alters physical Part.Size")
 check((flood.global_transform*flood.get_aabb()).size.x>4000,"flood still a tiny rectangle")
 check((flood.global_transform*QUERY.bounds(flood)).size.x==5,"visual flood size leaks into physics")
 dm.free()
 print("[disaster_player_contract] failures=",failures," diagnostics=",engine.get_runtime_diagnostics())
 engine.stop_all_scripts(workspace)
 workspace.queue_free()
 await process_frame
 engine.release_stopped_script_states()
 quit(0 if failures.is_empty() else 1)
