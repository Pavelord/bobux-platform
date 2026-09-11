extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[studio_weapons] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var library = load("res://addons/roblox_studio/studio_gameplay_library.gd")
	studio._apply_studio_ai_actions([{"type": "create_part", "name": "TestFloor", "size": [80, 1, 80], "anchored": true}])
	studio.placement_parent.get_node("TestFloor").position = Vector3(0, -0.5, 0)
	var pistol_plan: Dictionary = library.weapon_plan(false, true)
	var rocket_plan: Dictionary = library.weapon_plan(true)
	check(studio._apply_studio_ai_actions(pistol_plan.actions) == pistol_plan.actions.size(), "pistol authored with initial equip")
	check(studio._apply_studio_ai_actions(rocket_plan.actions) == rocket_plan.actions.size(), "RPG authored")
	check(studio._apply_studio_ai_actions(library.npc_plan().actions) == 11, "NPC has body face Humanoid and controller")
	var npc: Node3D = studio.placement_parent.get_node("Zombie")
	npc.position = Vector3(0, 0, -20)
	npc.get_node("Chase").set_meta("disabled", true)
	var engine := root.get_node("LuaScriptEngine")
	await studio._start_studio_playtest()
	check(studio.viewport_container_node.is_visible_in_tree() and not studio.script_editor_tabs.visible, "Play opens game view after authoring scripts")
	await create_timer(0.3).timeout
	var character: CharacterBody3D = studio.studio_playtest_player
	character.global_position = Vector3(0, 1, 0)
	character.velocity = Vector3.ZERO
	var inventory: Dictionary = engine.get_local_inventory_state(studio.placement_parent, character)
	var pistol: Node = character.get_node_or_null("Pistol")
	check(pistol != null, "Humanoid EquipTool equips StarterPack clone on spawn")
	if pistol != null:
		check((-pistol.global_basis.z).normalized().dot(character.get_node("Visuals").global_basis.z.normalized()) > 0.99, "Roblox tool forward points away from avatar face")
	var aim := Camera3D.new()
	studio.placement_parent.add_child(aim)
	aim.global_position = Vector3(0, 3, 5)
	aim.look_at(npc.get_node("HumanoidRootPart").global_position)
	aim.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var motion := InputEventMouseMotion.new()
	motion.position = studio.viewport_container_node.size * 0.5
	studio._on_studio_viewport_gui_input(motion)
	await physics_frame
	await process_frame
	if pistol != null:
		check(engine.activate_local_tool(pistol, studio.placement_parent), "tool activation accepted")
		await process_frame
		check(studio.placement_parent.get_node_or_null("Bullet") != null, "shot creates visible projectile")
		await create_timer(0.35).timeout
		check(float(npc.get_node("Humanoid").get_meta("Health", 100)) < 100, "projectile hits NPC and damages Humanoid")
		var health_display: Label3D = npc.find_child("HumanoidHealthDisplay", true, false)
		check(health_display != null and health_display.text.contains("75 / 100 HP"), "NPC shows updated health above its head")
		check(studio.placement_parent.get_node_or_null("Bullet") == null, "projectile cleans up after hit")
	var rpg: Node = inventory.backpack.get_node_or_null("RPG")
	check(rpg != null and engine.equip_local_tool(rpg, studio.placement_parent, character), "RPG equips from inventory")
	if rpg != null:
		check(engine.activate_local_tool(rpg, studio.placement_parent), "RPG activation accepted")
		await process_frame
		check(studio.placement_parent.get_node_or_null("Rocket") != null, "RPG creates visible rocket")
		await create_timer(0.8).timeout
		check(studio.placement_parent.get_node_or_null("Explosion") != null, "rocket hit creates Explosion")
	# Run the authored NPC controller itself, not a mocked MoveTo callback.
	var humanoid: Node = npc.get_node("Humanoid")
	humanoid.set_meta("Health", 100)
	var before := npc.global_position
	var chase: Node = npc.get_node("Chase")
	chase.set_meta("disabled", false)
	engine.start_script(str(chase.get_meta("code")), chase, {"realm": "server", "retain": true})
	await create_timer(0.5).timeout
	check(npc.global_position.z > before.z + 1, "NPC script pursues actual player")
	check(int(engine.get_runtime_diagnostics().failed) == 0, "no Lua runtime errors")
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	engine._input(InputEventMouseMotion.new())
	print("[studio_weapons] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
