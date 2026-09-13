extends RefCounted

const Lexer = preload("res://addons/roblox_studio/roblox_lua_lexer.gd")

# Rewrites operate on lexical boundaries, never inside comments/string payloads.
static func interpolate(source: String) -> String:
	var output := ""
	var index := 0
	while index < source.length():
		var opaque := _opaque_end(source, index)
		if opaque > index:
			output += source.substr(index, opaque - index)
			index = opaque
		elif source[index] == "`":
			var parsed := _template(source, index)
			# Keep malformed syntax for the compiler to diagnose; don't repair it.
			if not parsed.ok: return source
			output += str(parsed.code)
			index = int(parsed.end)
		else:
			output += source[index]
			index += 1
	return output

static func _opaque_end(source: String, start: int) -> int:
	var index := start
	var comment := source.substr(index, 2) == "--"
	if comment: index += 2
	if index < source.length() and source[index] == "[":
		var equals := index + 1
		while equals < source.length() and source[equals] == "=": equals += 1
		if equals < source.length() and source[equals] == "[":
			var close := "]" + "=".repeat(equals - index - 1) + "]"
			var finish := source.find(close, equals + 1)
			return source.length() if finish < 0 else finish + close.length()
	if comment:
		var newline := source.find("\n", index)
		return source.length() if newline < 0 else newline + 1
	if source[start] in ["'", '"']:
		index = start + 1
		while index < source.length():
			if source[index] == "\\": index += 2
			elif source[index] == source[start]: return index + 1
			else: index += 1
		return source.length()
	return start

static func _template(source: String, start: int) -> Dictionary:
	var pieces: Array[String] = []
	var literal := ""
	var index := start + 1
	while index < source.length():
		var character := source[index]
		if character == "`":
			pieces.append('"' + literal + '"')
			return {"ok": true, "code": "(" + " .. ".join(pieces) + ")", "end": index + 1}
		if character == "\\":
			if index + 1 >= source.length(): break
			var escaped := source[index + 1]
			if escaped in ["`", "{", "}"]: literal += escaped
			elif escaped == "\n": literal += "\\n"
			elif escaped == "\r":
				literal += "\\n"
				if source.substr(index + 2, 1) == "\n": index += 1
			else:
				literal += "\\" + escaped
				# Braces in Unicode escape sequences are part of the literal.
				if escaped == "u" and source.substr(index + 2, 1) == "{":
					var finish := source.find("}", index + 3)
					if finish < 0: break
					literal += source.substr(index + 2, finish - index - 1)
					index = finish - 1
			index += 2
			continue
		if character == "{":
			pieces.append('"' + literal + '"')
			literal = ""
			var expression := _expression(source, index + 1)
			if not expression.ok or str(expression.code).strip_edges().is_empty(): break
			pieces.append("tostring((" + str(expression.code) + "))")
			index = int(expression.end)
			continue
		if character == '"': literal += '\\"'
		elif character == "\n": literal += "\\n"
		elif character == "\r": literal += "\\r"
		else: literal += character
		index += 1
	return {"ok": false}

static func _expression(source: String, start: int) -> Dictionary:
	var output := ""
	var depth := 1
	var index := start
	while index < source.length():
		var opaque := _opaque_end(source, index)
		if opaque > index:
			output += source.substr(index, opaque - index)
			index = opaque
			continue
		var character := source[index]
		if character == "`":
			var nested := _template(source, index)
			if not nested.ok: return nested
			output += str(nested.code)
			index = int(nested.end)
			continue
		if character == "{": depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0: return {"ok": true, "code": output, "end": index + 1}
		output += character
		index += 1
	return {"ok": false}

static func rewrite_continue(source: String) -> String:
	var tokens := Lexer.tokens(source)
	var stack: Array[Dictionary] = []
	var loops: Array[Dictionary] = []
	var edits: Array[Dictionary] = []
	var prefix := "__bobux_continue_"
	while prefix in source: prefix += "x"
	for index in range(tokens.size()):
		var token: Dictionary = tokens[index]
		var word := str(token.text)
		var previous := str(tokens[index - 1].text) if index > 0 else ""
		var next := str(tokens[index + 1].text) if index + 1 < tokens.size() else ""
		if previous in [".", ":"]: continue
		if word in ["for", "while", "repeat"]:
			var loop := {"kind": word, "pending": word != "repeat", "body": int(token.end), "close": -1, "used": false, "label": prefix + str(loops.size())}
			loops.append(loop)
			stack.append(loop)
		elif word in ["function", "if"]:
			stack.append({"kind": word})
		elif word == "do":
			if not stack.is_empty() and stack[-1].get("pending", false):
				stack[-1].pending = false
				stack[-1].body = int(token.end)
			else: stack.append({"kind": "do"})
		elif word in ["end", "until"]:
			if stack.is_empty(): continue
			var block: Dictionary = stack.pop_back()
			if block.has("label"): block.close = int(token.start)
		elif word == "continue" and not previous in ["local", "return", "=", ",", "(", "["] and not next in ["(", ")", "]", "}", "=", ".", ":", "[", ",", "+", "-", "*", "/"]:
			for depth in range(stack.size() - 1, -1, -1):
				var block: Dictionary = stack[depth]
				if block.kind == "function": break
				if block.has("label") and not block.pending:
					block.used = true
					edits.append({"start": int(token.start), "end": int(token.end), "text": "goto " + str(block.label)})
					break
	for loop in loops:
		if int(loop.close) < 0: continue
		if not loop.used:
			if loop.kind == "for": edits.append({"start": loop.body, "end": loop.body, "text": " __bobux_checkpoint(); "})
			continue
		# An inner do scope permits jumping past locals in for/while bodies.
		# repeat locals stay in scope for its until condition, as in Luau.
		if loop.kind != "repeat": edits.append({"start": loop.body, "end": loop.body, "text": " do __bobux_checkpoint(); " if loop.kind == "for" else " do "})
		edits.append({"start": loop.close, "end": loop.close, "text": ("end " if loop.kind != "repeat" else "") + "::" + str(loop.label) + ":: "})
	edits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start) > int(b.start))
	for edit in edits: source = source.left(edit.start) + str(edit.text) + source.substr(edit.end)
	return source
