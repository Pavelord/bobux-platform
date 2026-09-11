extends RefCounted

static func protect_strings(source: String) -> Dictionary:
	var prefix := "BOBUX_LITERAL_"
	while prefix in source: prefix += "X"
	var literals := {}
	var spans := tokens(source)
	spans.reverse()
	for token in spans:
		var value := str(token.text)
		if not (value.begins_with("'") or value.begins_with('"') or (value.begins_with("[") and value.length() > 1)): continue
		var placeholder := '"' + prefix + str(literals.size()) + '"'
		literals[placeholder] = value
		source = source.left(token.start) + placeholder + source.substr(token.end)
	return {"source": source, "literals": literals}

static func restore_strings(source: String, literals: Dictionary) -> String:
	for placeholder in literals: source = source.replace(placeholder, literals[placeholder])
	return source

static func tokens(source: String) -> Array[Dictionary]:
	# Token offsets let compatibility rewrites leave comments and string payloads
	# intact, and distinguish a chained receiver from the surrounding expression.
	var tokens: Array[Dictionary] = []
	var index := 0
	while index < source.length():
		var start := index
		var character := source[index]
		if character in [" ", "\t", "\n", "\r"]:
			index += 1
			continue
		var is_comment := source.substr(index, 2) == "--"
		if is_comment:
			index += 2
		var long_start := index
		if index < source.length() and source[index] == "[":
			var equals := index + 1
			while equals < source.length() and source[equals] == "=":
				equals += 1
			if equals < source.length() and source[equals] == "[":
				var close := "]" + "=".repeat(equals - index - 1) + "]"
				var close_index := source.find(close, equals + 1)
				index = source.length() if close_index < 0 else close_index + close.length()
				if not is_comment:
					tokens.append({"text": source.substr(start, index - start), "start": start, "end": index, "identifier": false})
				continue
		index = long_start
		if is_comment:
			var newline := source.find("\n", index)
			index = source.length() if newline < 0 else newline + 1
			continue
		if character in ["'", '"']:
			index += 1
			while index < source.length():
				if source[index] == "\\":
					index += 2
				elif source[index] == character:
					index += 1
					break
				else:
					index += 1
			tokens.append({"text": source.substr(start, index - start), "start": start, "end": index, "identifier": false})
			continue
		var identifier := character == "_" or character.to_lower() in "abcdefghijklmnopqrstuvwxyz"
		index += 1
		if identifier:
			while index < source.length() and (source[index] == "_" or source[index].to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789"):
				index += 1
		tokens.append({"text": source.substr(start, index - start), "start": start, "end": index, "identifier": identifier})
	return tokens
