extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[main_scripts] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	var probe := GDScript.new()
	probe.source_code = "extends \"res://scripts/main/main.gd\"\nfunc _ready(): pass\nfunc _process(_delta): pass\nfunc _refresh_runtime_inventory(): pass\nfunc _is_dedicated_server_runtime(): return false\n"
	check(probe.reload() == OK, "main harness compiles")
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(probe)
	root.add_child(main)
	current_scene = main
	var world := main.get_node("World") as Node3D
	world.set_meta("roblox_class", "Workspace")
	var engine := root.get_node("LuaScriptEngine")
	var manifest := {"services": [{"ref": "starter", "class": "StarterPlayer", "name": "StarterPlayer"}],
		"instances": [{"ref": "characters", "class": "StarterCharacterScripts", "name": "StarterCharacterScripts", "parent_ref": "starter"}],
		"scripts": [{"ref": "jump", "class": "LocalScript", "name": "Movement", "parent_ref": "characters", "service_name": "StarterPlayer", "source": "local h = script.Parent:WaitForChild('Humanoid')\nscript.Parent:SetAttribute('Runs', (script.Parent:GetAttribute('Runs') or 0) + 1)\nh.WalkSpeed = 27"}]}
	check(bool(engine.install_roblox_manifest(manifest, world).ok), "manifest installs")
	await main._load_manifest_scripts_into_map(manifest, {}, world, Vector3.ZERO, "")
	var template: Node = engine.find_instance_by_ref(world, "jump")
	check(not template.has_meta("bobux_script_runtime_id"), "StarterCharacterScripts template remains inert")
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.set_meta("bobux_studio_playtest", true)
	world.add_child(character)
	main._bind_runtime_local_character(character.get_instance_id())
	await create_timer(0.3).timeout
	check(character.get_node_or_null("Movement") != null, "script cloned under character")
	check(character.get_humanoid_walk_speed() == 27, "normal mode script changes actual humanoid")
	main._bind_runtime_local_character(character.get_instance_id())
	await create_timer(0.2).timeout
	check(int(character.get_meta("attribute_Runs", -1)) == 1, "repeated binding does not restart same script")
	check(int(engine.get_runtime_diagnostics().failed) == 0, "normal mode has no Lua errors")
	var sleeping: Dictionary = engine.start_script("task.spawn(function() task.wait(0.1); script:SetAttribute('Late',true) end)", character, {"retain": true})
	check(bool(sleeping.ok), "sleeping task starts before character destruction")
	engine.start_script("error('must never start after deletion')", character, {"defer_compilation":true})
	character.free()
	await create_timer(0.2).timeout
	engine._process_pending_script_starts()
	engine._process_lua_tasks()
	var context := Node.new()
	world.add_child(context)
	check(bool(engine.start_script("game:GetService('RunService').Heartbeat:Connect(function() end)\ntask.spawn(function() while true do task.wait(0.05) end end)", context, {"retain":true}).ok), "scene owns live callbacks and repeating tasks")
	main.queue_free()
	await process_frame
	await process_frame
	engine._input(InputEventMouseMotion.new())
	engine._process_lua_tasks()
	var stopped: Dictionary = engine.get_runtime_diagnostics()
	check(int(stopped.active)==0 and int(stopped.pending)==0 and int(stopped.retained)==0, "real Main teardown stops scene scripts without test cleanup")
	engine.release_stopped_script_states()
	print("[main_scripts] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
