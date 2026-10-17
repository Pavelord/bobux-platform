extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var model := preload("res://addons/roblox_studio/roblox_data_model.gd").new()
	var engine := root.get_node("LuaScriptEngine")
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.material_override = StandardMaterial3D.new()
	part.set_meta("roblox_properties", {"Color": [0.8,0.1,0.2], "BrickColor": 21})
	root.add_child(part)
	var saved: Dictionary = model._serialize_node_properties(part,"Part")
	var ok: bool = is_equal_approx(saved.Color[0], 0.8) and is_equal_approx(saved.Color[1], 0.1)
	var wrapper = engine.BobuxInstance.wrap(part)
	wrapper._set("Color", Color(0.1,0.7,0.2))
	saved = model._serialize_node_properties(part,"Part")
	ok = ok and is_equal_approx(saved.Color[1],0.7)
	part.mesh = null
	ok = ok and wrapper._get("Color").is_equal_approx(Color(0.1,0.7,0.2))
	wrapper._set("BrickColor", 21)
	saved = model._serialize_node_properties(part,"Part")
	ok = ok and saved.Color[0] > 0.7 and saved.Color[1] < 0.3
	print("[imported-colors] PASS=",ok," deferred_color=",saved.Color)
	var colored := preload("res://addons/roblox_studio/roblox_data_model.gd").create_instance("Part") as MeshInstance3D
	root.add_child(colored)
	engine._apply_manifest_entry_metadata(colored, {"class":"Part","ref":"color-probe","properties":{"Color":[0.8,0.1,0.2]}})
	ok = ok and (colored.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.8,0.1,0.2))
	var main: Node = load("res://scripts/main/main.gd").new()
	var env := Environment.new()
	main._apply_roblox_environment_to_runtime_environment(env, {"lighting":{"Ambient":[0.5,0.5,0.5],"OutdoorAmbient":[0.5,0.5,0.5],"Brightness":1.0}})
	ok = ok and is_equal_approx(env.ambient_light_energy,0.42) and not env.glow_enabled
	print("[color-lighting] PASS=",ok," ambient=",env.ambient_light_energy)
	main.free()
	model.free()
	quit(0 if ok else 1)
