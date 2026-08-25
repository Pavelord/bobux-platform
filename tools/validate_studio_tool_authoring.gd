extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var workspace: Node = studio.get("placement_parent")
	var data_model: Node = studio.get("data_model")
	studio._insert_roblox_instance(workspace, "Model")
	var model := _last_direct_child_of_class(workspace, "Model")
	studio._insert_roblox_instance(model, "TrussPart")
	var truss := _last_direct_child_of_class(model, "TrussPart") as MeshInstance3D
	var hierarchy_ok := model != null and truss != null and truss.get_parent() == model

	var properties: Variant = studio.get("roblox_properties")
	properties.call("_on_part_name_changed", "ClimbTower", truss)
	properties.call("_on_part_position_changed", Vector3(3.0, 4.0, -2.0), truss)
	properties.call("_on_part_color_changed", Color("#36A852"), truss)
	properties.call("_on_part_anchored_changed", false, truss)
	properties.call("_on_part_can_collide_changed", false, truss)
	properties.call("_on_part_meta_bool_changed", true, truss, "Locked")
	var properties_ok := (
		str(truss.name) == "ClimbTower"
		and truss.position.is_equal_approx(Vector3(3.0, 4.0, -2.0))
		and (truss.get_meta("bobux_color", Color.BLACK) as Color).is_equal_approx(Color("#36A852"))
		and not bool(truss.get_meta("anchored", true))
		and not bool(truss.get_meta("can_collide", true))
		and bool(truss.get_meta("Locked", false))
	)

	var explorer_helper: Variant = studio.get("roblox_explorer")
	explorer_helper.call("set_filter_text", "climbtower")
	studio._refresh_explorer()
	var explorer: Tree = studio.get("explorer_tree")
	var model_visible := _tree_contains_node(explorer.get_root(), model.get_instance_id())
	var truss_visible := _tree_contains_node(explorer.get_root(), truss.get_instance_id())
	explorer_helper.call("set_filter_text", "")
	studio._refresh_explorer()
	var explorer_ok := model_visible and truss_visible

	var starter_pack: Node = data_model.ensure_service("StarterPack")
	studio._add_tool_to_node(starter_pack)
	var template_tool := _last_direct_child_of_class(starter_pack, "Tool")
	var handle := template_tool.get_node_or_null("Handle") if template_tool != null else null
	var local_script := template_tool.get_node_or_null("ToolClient") if template_tool != null else null
	var tool_structure_ok := template_tool != null and handle != null and local_script != null
	if local_script != null:
		local_script.set_meta("code", """
local tool = script.Parent
tool:SetAttribute("ScriptStarted", true)
tool.Equipped:Connect(function()
	tool:SetAttribute("EquippedSeen", true)
end)
tool.Activated:Connect(function()
	tool:SetAttribute("ActivatedSeen", true)
end)
tool.Unequipped:Connect(function()
	tool:SetAttribute("UnequippedSeen", true)
end)
""")
		local_script.set_meta("lua_source", local_script.get_meta("code"))

	await studio._start_studio_playtest()
	for _frame in range(20):
		await process_frame
	var player: CharacterBody3D = studio.get("studio_playtest_player") as CharacterBody3D
	var lua_engine: Node = get_root().get_node_or_null("LuaScriptEngine")
	var state_variant: Variant = lua_engine.call("get_local_inventory_state", workspace, player) if lua_engine != null else {}
	var state: Dictionary = state_variant as Dictionary if state_variant is Dictionary else {}
	var tools: Array = state.get("tools", []) if state.get("tools", []) is Array else []
	var live_tool: Node = tools[0] as Node if not tools.is_empty() else null
	var cloned_ok := live_tool != null and live_tool != template_tool and live_tool.get_node_or_null("Handle") != null
	var local_script_ok := cloned_ok and bool(live_tool.get_meta("attribute_ScriptStarted", false))
	var equipped := bool(lua_engine.call("equip_local_tool", live_tool, workspace, player)) if live_tool != null and lua_engine != null else false
	await process_frame
	var activated := bool(lua_engine.call("activate_local_tool", live_tool, workspace)) if live_tool != null and lua_engine != null else false
	await process_frame
	var unequipped := bool(lua_engine.call("unequip_local_tool", live_tool, workspace)) if live_tool != null and lua_engine != null else false
	await process_frame
	var lifecycle_ok := (
		equipped and activated and unequipped
		and bool(live_tool.get_meta("attribute_EquippedSeen", false))
		and bool(live_tool.get_meta("attribute_ActivatedSeen", false))
		and bool(live_tool.get_meta("attribute_UnequippedSeen", false))
	)
	var inventory_controller: CanvasLayer = studio.get("studio_inventory_controller") as CanvasLayer
	var hotbar := inventory_controller.get_node_or_null("InventoryRoot/Hotbar") if inventory_controller != null else null
	var inventory_ok := inventory_controller != null and hotbar != null and hotbar.get_child_count() > 0
	var diagnostics: Dictionary = lua_engine.call("get_runtime_diagnostics") if lua_engine != null else {}
	var live_script: Node = live_tool.get_node_or_null("ToolClient") if live_tool != null else null
	print("[validate_studio_tool_authoring] diagnostics tools=%d live_path=%s script_class=%s source_len=%d hotbar=%d runtime=%s status=%s" % [
		tools.size(),
		str(live_tool.get_path()) if live_tool != null else "<none>",
		str(live_script.get_meta("roblox_class", "")) if live_script != null else "<none>",
		str(live_script.get_meta("code", "")).length() if live_script != null else 0,
		hotbar.get_child_count() if hotbar != null else -1,
		str(diagnostics),
		str(studio.get("toolbar_status_label").text) if studio.get("toolbar_status_label") != null else "",
	])

	await studio._stop_studio_playtest()
	await process_frame
	var ok := hierarchy_ok and properties_ok and explorer_ok and tool_structure_ok and cloned_ok and local_script_ok and lifecycle_ok and inventory_ok
	print("[validate_studio_tool_authoring] ok=%s hierarchy=%s properties=%s explorer=%s tool=%s cloned=%s local_script=%s lifecycle=%s inventory=%s" % [
		str(ok), str(hierarchy_ok), str(properties_ok), str(explorer_ok), str(tool_structure_ok),
		str(cloned_ok), str(local_script_ok), str(lifecycle_ok), str(inventory_ok),
	])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _last_direct_child_of_class(parent: Node, roblox_class: String) -> Node:
	if parent == null:
		return null
	var result: Node = null
	for child in parent.get_children():
		if str(child.get_meta("roblox_class", "")) == roblox_class:
			result = child
	return result


func _tree_contains_node(item: TreeItem, node_id: int) -> bool:
	if item == null:
		return false
	var metadata: Variant = item.get_metadata(0)
	if metadata is int and int(metadata) == node_id:
		return true
	var child := item.get_first_child()
	while child != null:
		if _tree_contains_node(child, node_id):
			return true
		child = child.get_next()
	return false

