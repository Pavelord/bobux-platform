extends SceneTree

# Requires the imported 2011 map saved at user://validation/nds_performance.
# -- --tsunami tests the original 60s wave; default tests the original 90s tornado.
const PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
var main: Node
var samples: Array[float] = []
var heights := {}
var lifted := {}
var turning := {}
var previous_angles := {}
var wave_offsets := {}
var wave_error := 0.0
var observed_wave := false

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var folder := "user://validation/nds_performance"
	if not FileAccess.file_exists(folder.path_join("map_data.json")):
		push_error("Save the imported NDS fixture to " + folder)
		quit(2)
		return
	root.get_node("GameState").selected_map_folder = folder
	main = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/published_runtime_fixture.gd"))
	root.add_child(main)
	current_scene = main
	var load_start := Time.get_ticks_msec()
	await main._load_selected_map()
	print("[nds] published_build_ms=",Time.get_ticks_msec()-load_start)
	var engine := root.get_node("LuaScriptEngine")
	engine.stop_all_scripts(main)
	engine.reset_runtime_diagnostics()
	var controller: Node = main.world.get_node("Script")
	var source: String = controller.get_meta("lua_source", "")
	var loop_start := source.find("while true do\n\twait(20)")
	if loop_start < 0: quit(2); return
	source = source.substr(0,loop_start) + """
math.randomseed(2011)
workspace.Structure:ClearAllChildren()
local ns=game.Lighting.Structures['Fort Indestructable']:Clone()
ns.Parent=workspace.Structure
ns:SetAttribute('BobuxRepairLegacySeams',true)
ns:MakeJoints()
spread(ns,function(p) if p:IsA('BasePart') and not p:FindFirstChild('KeepAnchored') then p.Anchored=false end end)
script:SetAttribute('Ready',true)
"""
	var wave := OS.get_cmdline_user_args().has("--tsunami")
	source += "tsunami.Start()" if wave else "tornado.Start()"
	source += "\nscript:SetAttribute('Done',true)"
	engine.start_script(source,controller,{"realm":"server","retain":true})
	var deadline := Time.get_ticks_msec()+140000
	var ready_at := 0
	var observation_at := 0
	while Time.get_ticks_msec()<deadline and not controller.get_meta("attribute_Done",false) and engine.get_runtime_diagnostics().failed==0:
		await process_frame
		if not controller.get_meta("attribute_Ready",false): continue
		if ready_at==0: ready_at=Time.get_ticks_msec()
		if Time.get_ticks_msec()-ready_at>2000: samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if Time.get_ticks_msec()-observation_at<50: continue
		observation_at=Time.get_ticks_msec()
		observe(main.world.get_node("Structure"),wave)
	samples.sort()
	var completed: bool = controller.get_meta("attribute_Done",false)
	var ok: bool = completed and engine.get_runtime_diagnostics().failed==0
	if wave: ok = ok and observed_wave and wave_error<0.02
	else: ok = ok and lifted.size()>=3 and turning.size()>=3
	print("[nds] disaster=", "tsunami" if wave else "tornado", " completed=",completed," lifted=",lifted.size()," orbiting=",turning.size()," wave_relative_error=",wave_error," frame_p50_ms=",percentile(0.5)," frame_p95_ms=",percentile(0.95)," diagnostics=",engine.get_runtime_diagnostics()," PASS=",ok)
	engine.stop_all_scripts(main)
	quit(0 if ok else 1)

func percentile(fraction: float) -> float:
	return samples[mini(int(samples.size()*fraction),samples.size()-1)] if not samples.is_empty() else 0.0

func observe(structure: Node, wave: bool) -> void:
	if wave:
		var model := structure.get_node_or_null("TsunamiWave")
		if model == null or model.get_node_or_null("Center") == null: return
		observed_wave=true
		var center: Node3D = model.get_node("Center")
		var frame := Transform3D(center.global_basis.orthonormalized(),center.global_position)
		for part in model.get_children():
			if not part is MeshInstance3D: continue
			var offset: Vector3 = frame.affine_inverse()*part.global_position
			var id: int = part.get_instance_id()
			if not wave_offsets.has(id): wave_offsets[id]=offset
			wave_error=maxf(wave_error,offset.distance_to(wave_offsets[id]))
		return
	var tornado := structure.get_node_or_null("TornadoPart") as Node3D
	for part in structure.find_children("*","MeshInstance3D",true,false):
		var id: int = part.get_instance_id()
		if not heights.has(id): heights[id]=part.global_position.y
		if not part.has_node("TornadoTag"): continue
		if part.global_position.y-float(heights[id])>5.0: lifted[id]=true
		if tornado==null: continue
		var offset: Vector3 = part.global_position-tornado.global_position
		var angle := atan2(offset.x,offset.z)
		if previous_angles.has(id) and lifted.has(id) and absf(angle_difference(previous_angles[id],angle))>0.03: turning[id]=true
		previous_angles[id]=angle
