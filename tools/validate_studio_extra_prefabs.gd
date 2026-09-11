extends SceneTree

const Prefabs = preload("res://addons/roblox_studio/studio_prefab_library.gd")
const Interaction = preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd")
var errors: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[extras] %s=%s" % [label_, ok])
	if not ok: errors.append(label_)

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	studio._apply_studio_ai_actions([{"type": "create_part", "name": "TestFloor", "size": [500, 1, 500]}])
	studio.placement_parent.get_node("TestFloor").position = Vector3(0, -0.5, 0)
	for id in ["lucky_spawner", "item_spawner", "sword", "hammer", "apple", "revolver", "flying_carpet", "npc_citizen", "npc_dialogue", "npc_patrol", "npc_boss", "airplane", "teams"]:
		check(studio._apply_studio_ai_actions(Prefabs.plan(id, {"Item": "hammer", "Cooldown": 0.1, "ReloadTime": 0.2}).actions) > 0 and studio.studio_ai_last_errors.is_empty(), id + " authored")
	var map: Node3D = studio.placement_parent
	map.get_node("LuckySpawner").position = Vector3(0, 0, 15)
	map.get_node("ItemSpawner").position = Vector3(20, 0, 0)
	map.get_node("NpcCitizen").position = Vector3(0, 0, -5)
	map.get_node("NpcDialogue").position = Vector3(30, 0, 0)
	map.get_node("NpcPatrol").position = Vector3(-40, 0, 0)
	map.get_node("NpcBoss").position = Vector3(-80, 0, -50)
	map.get_node("Airplane").position = Vector3(80, 2, 0)
	var engine := root.get_node("LuaScriptEngine")
	await studio._start_studio_playtest()
	await create_timer(0.5).timeout
	var character: CharacterBody3D = studio.studio_playtest_player
	var state: Dictionary = engine.get_local_inventory_state(map, character)
	var backpack: Node = state.backpack
	check(character.global_position.x < -15, "team spawn applies on initial character")
	check(state.local_player.has_meta("Team"), "player assigned team")
	var lucky: Node = map.get_node("LuckySpawner")
	character.set_lua_position(lucky.global_position + Vector3(0, 1, 2))
	var display_basis: Basis = lucky.get_node("Display").basis
	var count := backpack.get_child_count()
	check(Interaction.activate_nearest_prompt(map, character, engine), "lucky E trigger")
	await create_timer(0.15).timeout
	print("[extras] repeat position=%s spawner=%s" % [character.global_position, lucky.global_position])
	check(Interaction.activate_nearest_prompt(map, character, engine), "lucky repeat E trigger")
	await process_frame
	check(backpack.get_child_count() == count + 2, "two separately usable lucky blocks")
	check(not display_basis.is_equal_approx(lucky.get_node("Display").basis), "display cube rotates")
	var block: Node = backpack.get_node_or_null("LuckyBlock")
	check(block != null and engine.equip_local_tool(block, map, character), "lucky block equips")
	if block != null:
		count = backpack.get_child_count()
		engine.activate_local_tool(block, map)
		await process_frame
		check(backpack.get_child_count() == count + 1 and not is_instance_valid(block), "consume lucky block and grant random reward")
	character.set_lua_position(map.get_node("ItemSpawner").global_position + Vector3(0, 1, 2))
	count = backpack.get_child_count()
	Interaction.activate_nearest_prompt(map, character, engine)
	await process_frame
	check(backpack.get_child_count() == count + 1, "configured item spawner grants hammer")
	var apple: Node = backpack.get_node_or_null("Apple")
	character.set_health(40)
	if apple != null:
		engine.equip_local_tool(apple, map, character)
		engine.activate_local_tool(apple, map)
		await process_frame
		check(character.get_health() == 75 and not is_instance_valid(apple), "food heals and is consumed")
	else: check(false, "apple available")
	var sword: Node = backpack.get_node("Sword")
	engine.equip_local_tool(sword, map, character)
	character.set_lua_position(Vector3(0, 1, -1))
	character.velocity = Vector3.ZERO
	await physics_frame
	engine.activate_local_tool(sword, map)
	await create_timer(0.2).timeout
	check(float(map.get_node("NpcCitizen/Humanoid").get_meta("Health")) == 70, "sword damages visible NPC")
	var patrol: Node = map.get_node("NpcPatrol/RobloxHumanoidMotor")
	patrol.move_to(patrol.global_position + Vector3(0, 0, 10))
	await create_timer(0.15).timeout
	check(patrol._limbs.size() == 4 and not patrol._limbs[0].node.transform.is_equal_approx(patrol._limbs[0].rest), "NPC walking animates limbs")
	var boss_collision: CollisionShape3D = map.get_node_or_null("NpcBoss/RobloxHumanoidMotor/HumanoidCollision")
	check(boss_collision != null and boss_collision.shape.height > 7, "boss collision follows model size")
	character.set_lua_position(map.get_node("NpcDialogue").global_position + Vector3(0, 1, 2))
	Interaction.activate_nearest_prompt(map, character, engine)
	await process_frame
	check(state.local_player.get_node("PlayerGui").get_node_or_null("NpcDialogue") != null, "NPC E shows scripted GUI")
	var carpet: Node = backpack.get_node("FlyingCarpet")
	var old_speed: float = character.get_humanoid_walk_speed()
	engine.equip_local_tool(carpet, map, character)
	character.set_lua_position(Vector3(character.global_position.x, 15, character.global_position.z))
	await create_timer(0.15).timeout
	check(map.get_node_or_null("FlyingCarpetVisual") != null and absf(character.velocity.y) < 5 and character.get_humanoid_walk_speed() == 35, "equipped carpet supports flight")
	var revolver: Node = backpack.get_node("Revolver")
	engine.equip_local_tool(revolver, map, character)
	await process_frame
	check(map.get_node_or_null("FlyingCarpetVisual") == null and character.get_humanoid_walk_speed() == old_speed, "unequip carpet restores movement")
	var camera := Camera3D.new()
	map.add_child(camera)
	camera.global_position = character.global_position + Vector3(0, 5, 10)
	camera.look_at(character.global_position)
	camera.make_current()
	await process_frame
	for i in range(7):
		engine.activate_local_tool(revolver, map)
		await create_timer(0.12).timeout
	check(int(revolver.get_meta("attribute_Ammo", -1)) == 0, "revolver stops after six rounds")
	var reload_ := InputEventKey.new()
	reload_.keycode = KEY_R
	reload_.pressed = true
	engine._input(reload_)
	await create_timer(0.3).timeout
	check(int(revolver.get_meta("attribute_Ammo", -1)) == 6, "R reload restores six rounds")
	var plane: Node = map.get_node("Airplane")
	character.set_lua_position(plane.global_position + Vector3(0, 4, 2))
	check(Interaction.activate_nearest_prompt(map, character, engine), "aircraft E boarding")
	await physics_frame
	var motor: RigidBody3D = plane.get_node_or_null("AircraftPhysics")
	check(motor != null and character._seated_part == plane.get_node("PilotSeat"), "aircraft has physics and pilot")
	if motor != null:
		motor.global_position.y = 20
		motor.linear_velocity = Vector3(0, 0, 40)
		var before := motor.global_position
		Input.action_press("move_forward")
		await create_timer(0.8).timeout
		Input.action_release("move_forward")
		check(motor.global_position.z > before.z + 15 and motor.global_position.y > before.y, "aircraft thrust and velocity dependent lift")
		character._leave_seat(true)
		check(character._seated_part == null, "pilot can exit")
	check(int(engine.get_runtime_diagnostics().failed) == 0, "no Lua runtime errors " + str(engine.get_runtime_diagnostics()))
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	engine._input(InputEventMouseMotion.new())
	print("[extras] errors=%s" % [errors])
	quit(0 if errors.is_empty() else 1)
