extends SceneTree
var failures: Array[String] = []

func check(ok: bool, label_: String) -> void:
	print("[boat_core] ", label_, "=", ok)
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex-tmp/roblox_compat/8.json"))
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
	importer.scale_factor = 0.5
	importer.defer_studio_explorer_refresh = true
	await importer.import_json_async(parsed, studio.placement_parent, studio)
	studio.current_roblox_place_manifest = studio.get_meta("roblox_place_manifest")
	var engine := root.get_node("LuaScriptEngine")
	await engine.install_roblox_manifest_async(studio.get_meta("roblox_place_manifest"), studio.placement_parent)
	await studio._start_studio_playtest()
	for frame in range(30): await create_timer(0.02).timeout
	var state: Dictionary = engine.get_local_inventory_state(studio.placement_parent)
	var player: Node = state.local_player
	var data := player.get_node_or_null("Data/WoodBlock")
	check(data != null and data.get_meta("Value", 0) == 8, "original PlayerData gives eight wood blocks")
	var team = engine.BobuxInstance.new(player)._get(&"Team")
	check(team != null and team.GetPlayers().size() == 1, "original team script assigns player")
	var builds: Node = studio.placement_parent.get_node_or_null(str(team._get(&"Name")) + "/Builds") if team != null else null
	check(builds != null, "team Builds folder resolves")
	var template: Node = studio.data_model.get_service("ReplicatedStorage").get_node("Objects/WoodBlock")
	var tool: Node = state.backpack.get_node("BuildingTool")
	check(engine.equip_local_tool(tool, studio.placement_parent), "original building tool equips")
	for frame in range(10): await create_timer(0.02).timeout
	check(player.get_node("PlayerGui/Build/ScrollingFrame").visible, "original equipped script opens build GUI")
	engine.unequip_local_tool(tool, studio.placement_parent)
	for frame in range(4): await create_timer(0.02).timeout
	check(not player.get_node("PlayerGui/Build/ScrollingFrame").visible, "original unequipped script hides build GUI")
	var anchor := Node.new()
	anchor.set_meta("roblox_class", "BoolValue")
	anchor.set_meta("Value", true)
	studio.placement_parent.add_child(anchor)
	var target := Vector3(10, 12, 15)
	engine.BobuxInstance.new(tool.get_node("RemoteEvent")).DispatchPacked("FireServer", [target, engine.BobuxCFrame.new(), engine.BobuxInstance.new(template), engine.BobuxInstance.new(anchor)], 4)
	for frame in range(20): await create_timer(0.02).timeout
	var placed: Node = builds.get_node_or_null("WoodBlock") if builds != null else null
	check(placed != null, "original BuildingTool creates wood block")
	if placed != null:
		var primary = engine.BobuxInstance.new(placed)._get(&"PrimaryPart")
		check(primary != null and placed.is_ancestor_of(primary.node), "clone PrimaryPart references cloned child")
		if primary != null:
			check((primary._get(&"Position") as Vector3).distance_to(target) < 0.1, "primary part remains at requested position")
			check(data.get_meta("Value", 0) == 7, "building spends one block")
			engine.BobuxInstance.new(state.backpack.get_node("DeleteTool/RemoteEvent")).DispatchPacked("FireServer", [primary], 1)
			for frame in range(10): await create_timer(0.02).timeout
			check(not is_instance_valid(placed) or placed.is_queued_for_deletion(), "original DeleteTool removes block")
			check(data.get_meta("Value", 0) == 8, "deleting refunds one block")
	check(engine.get_runtime_diagnostics().failed == 0, "original core scripts report no runtime errors")
	print("[boat_core] diagnostics=", engine.get_runtime_diagnostics(), " failures=", failures)
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
