extends SceneTree


func _initialize() -> void:
	var scene := Node.new()
	scene.name = "InventoryRuntimeTest"
	get_root().add_child(scene)
	current_scene = scene
	var workspace := Node3D.new()
	workspace.name = "World"
	workspace.set_meta("roblox_class", "Workspace")
	scene.add_child(workspace)
	await process_frame
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	if lua_engine == null:
		push_error("LuaScriptEngine autoload is unavailable")
		quit(1)
		return

	var manifest := {
		"schema": "bobux.roblox_manifest.v2",
		"services": [
			{"ref": "service_players", "class": "Players", "name": "Players"},
			{"ref": "service_starter_pack", "class": "StarterPack", "name": "StarterPack"},
		],
		"tools": [
			{
				"ref": "tool_blaster",
				"class": "Tool",
				"name": "Test Blaster",
				"parent_ref": "service_starter_pack",
				"properties": {"RequiresHandle": true, "ToolTip": "Validation tool"},
			},
		],
		"instances": [
			{
				"ref": "tool_handle",
				"class": "Part",
				"name": "Handle",
				"parent_ref": "tool_blaster",
				"properties": {"BobuxPosition": [0.0, 0.0, 0.0], "BobuxSize": [0.4, 0.4, 1.6]},
			},
		],
		"hierarchy": [
			{"parent": "service_starter_pack", "child": "tool_blaster"},
			{"parent": "tool_blaster", "child": "tool_handle"},
		],
	}
	var install_result: Dictionary = lua_engine.install_roblox_manifest(manifest, workspace)
	var character := CharacterBody3D.new()
	character.name = "Character"
	workspace.add_child(character)
	lua_engine.bind_local_player_character(character)
	await process_frame

	var initial_state: Dictionary = lua_engine.get_local_inventory_state(workspace, character)
	var tools: Array = initial_state.get("tools", []) if initial_state.get("tools", []) is Array else []
	var tool: Node = tools[0] as Node if not tools.is_empty() else null
	var backpack: Node = initial_state.get("backpack", null)
	var initial_ok := bool(install_result.get("ok", false)) and tool != null and tool.get_parent() == backpack
	var hidden_ok := tool is Node3D and not (tool as Node3D).visible

	var equipped_ok: bool = tool != null and bool(lua_engine.equip_local_tool(tool, workspace, character))
	equipped_ok = equipped_ok and tool.get_parent() == character and bool(tool.get_meta("bobux_tool_equipped", false))
	var activation_ok: bool = tool != null and bool(lua_engine.activate_local_tool(tool, workspace))
	var unequipped_ok: bool = tool != null and bool(lua_engine.unequip_local_tool(tool, workspace))
	unequipped_ok = unequipped_ok and tool.get_parent() == backpack and not bool(tool.get_meta("bobux_tool_equipped", false))

	var controller := RobloxInventoryController.new()
	controller.configure(lua_engine, workspace, func() -> Node: return character)
	scene.add_child(controller)
	await process_frame
	await process_frame
	controller.refresh_now(true)
	await process_frame
	var hotbar := controller.find_child("Hotbar", true, false) as HBoxContainer
	var ui_ok := hotbar != null and hotbar.get_child_count() == 1
	if ui_ok:
		(hotbar.get_child(0) as Button).pressed.emit()
		await process_frame
		var equipped_state: Dictionary = lua_engine.get_local_inventory_state(workspace, character)
		ui_ok = equipped_state.get("equipped_tool", null) == tool

	var ok: bool = initial_ok and hidden_ok and equipped_ok and activation_ok and unequipped_ok and ui_ok
	print("[validate_roblox_inventory_runtime] ok=%s initial=%s hidden=%s equipped=%s activated=%s unequipped=%s ui=%s" % [
		str(ok), str(initial_ok), str(hidden_ok), str(equipped_ok), str(activation_ok), str(unequipped_ok), str(ui_ok),
	])
	scene.free()
	quit(0 if ok else 1)

