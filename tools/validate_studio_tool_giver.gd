extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var parts: Array = studio._get_editor_parts()
	var data_model: Node = studio.get("data_model")
	if parts.is_empty() or data_model == null:
		push_error("Studio world is incomplete")
		quit(1)
		return

	var server_storage: Node = data_model.ensure_service("ServerStorage")
	var starter_pack: Node = data_model.ensure_service("StarterPack")
	studio._add_tool_to_node(starter_pack)
	var template_tool: Node = null
	for child in starter_pack.get_children():
		if str(child.get_meta("roblox_class", "")) == "Tool":
			template_tool = child
	if template_tool == null:
		push_error("Could not author ServerStorage Tool")
		quit(1)
		return
	template_tool.name = "GiverHammer"
	template_tool.set_meta("Name", "GiverHammer")
	template_tool.set_meta("block_name", "GiverHammer")
	starter_pack.remove_child(template_tool)
	server_storage.add_child(template_tool, true)

	var giver_script := Node.new()
	giver_script.name = "GiveTool"
	giver_script.set_meta("roblox_class", "Script")
	giver_script.set_meta("script_type", "Script")
	giver_script.set_meta("code", """
local template = game.ServerStorage:FindFirstChild("GiverHammer")
script.Parent.Touched:Connect(function(hit)
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if player and template and not player.Backpack:FindFirstChild("GiverHammer") then
		template:Clone().Parent = player.Backpack
	end
end)
""")
	parts[0].add_child(giver_script)

	await studio._start_studio_playtest()
	for _frame in range(150):
		await physics_frame
		await process_frame
	var player: CharacterBody3D = studio.get("studio_playtest_player") as CharacterBody3D
	var lua_engine: Node = get_root().get_node_or_null("LuaScriptEngine")
	var state_variant: Variant = lua_engine.call("get_local_inventory_state", studio.get("placement_parent"), player) if lua_engine != null else {}
	var state: Dictionary = state_variant as Dictionary if state_variant is Dictionary else {}
	var tools: Array = state.get("tools", []) if state.get("tools", []) is Array else []
	var found := false
	for tool in tools:
		if tool is Node and str((tool as Node).name) == "GiverHammer":
			found = true
			break
	var diagnostics: Dictionary = lua_engine.call("get_runtime_diagnostics") if lua_engine != null else {}
	await studio._stop_studio_playtest()
	var ok := found and int(diagnostics.get("failed", 0)) == 0
	print("[validate_studio_tool_giver] ok=%s found=%s tools=%d diagnostics=%s" % [
		str(ok), str(found), tools.size(), str(diagnostics),
	])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
