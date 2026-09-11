extends RefCounted

# Semantic checks for known invalid Roblox members, separate from Lua syntax.
static func errors(source: String) -> Array[String]:
	var result: Array[String] = []
	var tokens := preload("res://addons/roblox_studio/roblox_lua_lexer.gd").tokens(source)
	var code := ""
	var end := 0
	for token in tokens:
		var gap := source.substr(end, int(token.start) - end)
		code += "\n".repeat(gap.count("\n")) + " "
		var value: String = token.text
		# Preserve the Humanoid name only for binding detection. Comments and
		# other literal payloads must never be mistaken for member accesses.
		if value.begins_with("'") or value.begins_with('"') or value.begins_with("[[") or value.begins_with("[="):
			code += value if value in ["'Humanoid'", '"Humanoid"'] else "''"
		else:
			code += value
		end = int(token.end)
	var bindings := RegEx.new()
	bindings.compile("(?m)\\blocal\\s+(\\w+)\\s*=\\s*[^\\n;]*(?:(?:WaitForChild|FindFirstChildOfClass|FindFirstChild)\\s*\\(\\s*[\"']Humanoid[\"']\\s*\\)|\\.\\s*Humanoid\\b)")
	var names := {}
	for found in bindings.search_all(code):
		names[found.get_string(1)] = true
	var members := {"JumpRequested": "Use UserInputService.JumpRequest.", "JumpRequest": "Use UserInputService.JumpRequest.", "State": "Use Humanoid:GetState() or StateChanged.", "Velocity": "Set HumanoidRootPart.AssemblyLinearVelocity.", "AssemblyLinearVelocity": "Set HumanoidRootPart.AssemblyLinearVelocity.", "Gravity": "There is no per-Humanoid Gravity property. Control falling through HumanoidRootPart.AssemblyLinearVelocity."}
	for name_ in names:
		for member in members:
			var access := RegEx.new()
			access.compile("\\b" + str(name_) + "\\s*\\.\\s*" + str(member) + "\\b")
			if access.search(code) != null:
				result.append("Humanoid.%s is not a Roblox member. %s" % [member, members[member]])
	return result
