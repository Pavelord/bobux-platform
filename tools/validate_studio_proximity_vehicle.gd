extends SceneTree

const Prefabs = preload("res://addons/roblox_studio/studio_prefab_library.gd")
const Interaction = preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd")
var errors: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[proximity_vehicle] %s=%s" % [label_, ok])
	if not ok: errors.append(label_)

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	studio._apply_studio_ai_actions([{"type": "create_part", "name": "TestFloor", "size": [200, 1, 200]}])
	studio.placement_parent.get_node("TestFloor").position = Vector3(0, -0.5, 0)
	for id in ["pistol_pickup", "rpg_dispenser", "buff_coin", "car", "points_button", "target_dummy"]:
		var options := {"EquipOnSpawn": true, "Speed": 34, "PointsPerClick": 5} if id in ["buff_coin", "points_button"] else {}
		check(studio._apply_studio_ai_actions(Prefabs.plan(id, options).actions) > 0, id + " authored")
	var pistol: Node3D = studio.placement_parent.get_node("Pistol")
	pistol.position = Vector3(0, 3, 0)
	var pad: Node3D = studio.placement_parent.get_node("ItemDispenser")
	pad.position = Vector3(30, 0.25, 0)
	var car: Node3D = studio.placement_parent.get_node("Car")
	car.position = Vector3(-30, 0, 0)
	studio.placement_parent.get_node("TargetDummy").position = Vector3(0, 0, -20)
	var engine := root.get_node("LuaScriptEngine")
	await studio._start_studio_playtest()
	await create_timer(0.5).timeout
	var character: CharacterBody3D = studio.studio_playtest_player
	character.global_position = Vector3(0, 1, 2)
	var state: Dictionary = engine.get_local_inventory_state(studio.placement_parent, character)
	check(character.get_node_or_null("BuffCoin") != null and character.get_humanoid_walk_speed() == 34, "coin initially equipped and configurable speed applied")
	character._apply_animation_pose()
	check(character.right_arm_pivot.position.x < 0 and character.left_arm_pivot.position.x > 0, "anatomical right hand for +Z facing avatar")
	check(Interaction.nearest_prompt(studio.placement_parent, character) == pistol.get_node("ProximityPrompt"), "nearest E prompt selected")
	var observer := Camera3D.new()
	studio.placement_parent.add_child(observer)
	observer.global_position = Vector3(8, 8, 12)
	observer.look_at(pistol.get_node("Handle").global_position)
	observer.make_current()
	await process_frame
	studio.studio_inventory_controller.refresh_now(true)
	var hud: Button = studio.studio_inventory_controller.find_child("ProximityAction", true, false)
	check(hud != null and hud.visible and "Подобрать" in hud.text, "visible E button describes pickup")
	check((hud.position + hud.size * 0.5).distance_to(observer.unproject_position(pistol.get_node("Handle").global_position)) < 2, "E button projects onto object")
	observer.look_at(observer.global_position + Vector3(0, 0, 10))
	studio.studio_inventory_controller.refresh_now(true)
	check(not hud.visible, "prompt behind camera hidden")
	observer.look_at(pistol.get_node("Handle").global_position)
	studio.studio_inventory_controller.refresh_now(true)
	if hud != null: hud.pressed.emit()
	await process_frame
	check(pistol.get_parent() == state.backpack, "E HUD picks world Tool into Backpack")
	check(engine.equip_local_tool(pistol, studio.placement_parent, character), "picked tool equips")
	check(character.get_humanoid_walk_speed() != 34, "previous held buff restored")
	check(pistol.get_node("WeaponController").has_meta("bobux_script_runtime_id"), "picked LocalScript started")
	engine.activate_local_tool(pistol, studio.placement_parent)
	await process_frame
	check(studio.placement_parent.get_node_or_null("Bullet") != null, "picked weapon actually shoots")
	character.global_position = pad.global_position + Vector3(0, 1, 2)
	check(Interaction.activate_nearest_prompt(studio.placement_parent, character, engine), "dispenser E activated")
	await process_frame
	var rpg: Node = state.backpack.get_node_or_null("RPG")
	check(rpg != null, "dispenser clones real Tool into Backpack")
	if rpg != null:
		check(engine.equip_local_tool(rpg, studio.placement_parent, character), "cloned tool equips")
		engine.activate_local_tool(rpg, studio.placement_parent)
		await process_frame
		check(studio.placement_parent.get_node_or_null("Rocket") != null, "fresh cloned controller shoots rocket")
		Interaction.activate_nearest_prompt(studio.placement_parent, character, engine)
		check(state.backpack.get_node_or_null("RPG") == null, "dispenser avoids duplicate equipped tool")
	var button: Node = state.local_player.get_node("PlayerGui/ScoreGui/AddPoint")
	engine.fire_roblox_instance_event(button, "Activated", [])
	check(int(state.local_player.get_node("leaderstats/Points").get_meta("Value", 0)) == 5, "configurable GUI awards five points")
	var dummy: Node = studio.placement_parent.get_node("TargetDummy")
	check(dummy.find_child("HumanoidHealthDisplay", true, false) != null, "idle NPC health visible before damage")
	character.global_position = car.global_position + Vector3(0, 2, 0)
	check(Interaction.activate_nearest_prompt(studio.placement_parent, character, engine), "car E activation")
	await create_timer(0.8).timeout
	var motor: VehicleBody3D = car.get_node_or_null("VehiclePhysics")
	check(motor != null and character._seated_part == car.get_node("VehicleSeat"), "VehicleSeat controls physics car")
	if motor != null:
		var before := motor.global_position
		Input.action_press("move_forward")
		await create_timer(1.5).timeout
		Input.action_release("move_forward")
		print("[proximity_vehicle] car before=%s after=%s velocity=%s force=%s" % [before, motor.global_position, motor.linear_velocity, motor.engine_force])
		check(Vector2(motor.global_position.x - before.x, motor.global_position.z - before.z).length() > 1, "vehicle moves horizontally under wheel traction")
		character._leave_seat(true)
		await physics_frame
		check(character._seated_part == null, "Space exit releases seat")
	check(int(engine.get_runtime_diagnostics().failed) == 0, "no runtime errors " + str(engine.get_runtime_diagnostics()))
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	engine._input(InputEventMouseMotion.new())
	print("[proximity_vehicle] errors=%s" % [errors])
	quit(0 if errors.is_empty() else 1)
