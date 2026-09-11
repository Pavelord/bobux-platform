extends RefCounted

static func inspect(roots: Array, engine: Node) -> Array[String]:
	var issues: Array[String] = []
	var pending: Array = roots.duplicate()
	var visited := {}
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if not is_instance_valid(node) or visited.has(node.get_instance_id()): continue
		visited[node.get_instance_id()] = true
		if node.has_meta("bobux_runtime_generated"): continue
		pending.append_array(node.get_children())
		var class_ := str(node.get_meta("roblox_class", ""))
		var path := str(node.get_path())
		if class_ in ["Script", "LocalScript", "ModuleScript"]:
			var source := str(node.get_meta("code", node.get_meta("lua_source", node.get_meta("Source", ""))))
			if source.strip_edges().is_empty(): issues.append(path + ": пустой скрипт")
			else:
				var validation: Dictionary = engine.validate_script_source(source)
				if not validation.get("ok", false): issues.append(path + ": " + str(validation.get("error", "ошибка Lua")))
		if class_ == "Tool" and bool(node.get_meta("RequiresHandle", true)) and node.get_node_or_null("Handle") == null:
			issues.append(path + ": Tool требует деталь Handle")
		if class_ == "Humanoid" and node.get_parent().get_node_or_null("HumanoidRootPart") == null:
			issues.append(path + ": у NPC отсутствует HumanoidRootPart")
		if class_ == "ProximityPrompt" and not node.get_parent() is Node3D:
			issues.append(path + ": разместите ProximityPrompt внутри объекта или Attachment")
	return issues
