extends SceneTree

# Selects an original disaster in an isolated copy of the published world.
# Production map/source files are read only. Fire keeps its full 90s duration.
var main: Node
var controller: Node
var failures: Array[String] = []
var peak_fire := 0
var first_damage := -1
var min_health := 100.0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var disaster := "fire"
	for arg in args:
		if arg.begins_with("--disaster="): disaster = arg.trim_prefix("--disaster=")
	if disaster == "flood": disaster = "flooding"
	var engine := root.get_node("LuaScriptEngine")
	root.get_node("GameState").selected_map_folder = "res://.codex-tmp/performance/nds-server-regression/server/Godot/app_userdata/Bobux/validation/nds_performance"
	main = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/nds_network_runtime.gd"))
	root.add_child(main)
	current_scene = main
	main.world.position = Vector3(600000, 0, 630000)
	await main._load_selected_map()
	controller = main.world.get_node("Script")
	var character: CharacterBody3D = main.add_probe_player(1)
	engine.bind_local_player_character(character)
	character.global_position = main.world.global_position + Vector3(0, 15, 0)
	var source: String = controller.get_meta("lua_source", "")
	var cut := source.find("while true do\n\twait(20)")
	if cut < 0: quit(2); return
	source = source.substr(0, cut) + """
math.randomseed(2026)
workspace.Structure:ClearAllChildren()
local ns=game.Lighting.Structures['Sunny Ranch']:Clone()
ns.Parent=workspace.Structure
ns:SetAttribute('BobuxRepairLegacySeams',true)
ns:MakeJoints()
spread(ns,function(p) if p:IsA('BasePart') and not p:FindFirstChild('KeepAnchored') then p.Anchored=false end end)
script:SetAttribute('Ready',true)
"""
	source += disaster + ".Start()\nscript:SetAttribute('Done',true)"
	engine.reset_runtime_diagnostics()
	engine.start_script(source, controller, {"realm":"server", "retain":true})
	var deadline := Time.get_ticks_msec() + 140000
	var started := Time.get_ticks_msec()
	var observation := 0
	while Time.get_ticks_msec() < deadline and not controller.get_meta("attribute_Done", false) and engine.get_runtime_diagnostics().failed == 0:
		await process_frame
		min_health = minf(min_health, float(character.get_health()))
		if min_health < 100 and first_damage < 0: first_damage = Time.get_ticks_msec() - started
		if Time.get_ticks_msec() - observation < 100: continue
		observation = Time.get_ticks_msec()
		var fires: Array[Node] = []
		for node in main.world.get_node("Structure").find_children("*", "GPUParticles3D", true, false):
			if str(node.get_meta("roblox_class", "")) == "Fire": fires.append(node)
		peak_fire = maxi(peak_fire, fires.size())
		# Hold the character beside actual burning geometry, testing the original
		# region query and Humanoid API rather than synthesizing TakeDamage.
		if disaster == "fire" and not fires.is_empty(): character.global_position = fires[0].global_position
	var completed: bool = controller.get_meta("attribute_Done", false)
	if not completed: failures.append("original disaster did not finish")
	if engine.get_runtime_diagnostics().failed != 0: failures.append("runtime failure")
	if disaster == "fire" and peak_fire == 0: failures.append("original fire never ignited")
	if disaster == "fire" and min_health >= 100: failures.append("character beside burning part received no damage")
	print("[halloween-disaster] disaster=", disaster, " completed=", completed, " elapsed_ms=", Time.get_ticks_msec()-started, " peak_fire=", peak_fire, " min_health=", min_health, " first_damage_ms=", first_damage, " diagnostics=", engine.get_runtime_diagnostics(), " failures=", failures)
	engine.stop_all_scripts(main)
	quit(0 if failures.is_empty() else 1)
