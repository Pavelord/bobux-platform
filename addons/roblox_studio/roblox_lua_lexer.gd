extends RefCounted

static func protect_strings(source: String) -> Dictionary:
	var prefix := "BOBUX_LITERAL_"
	while prefix in source: prefix += "X"
	var literals := {}
	var replacements: Array[Dictionary] = []
	var spans := tokens(source)
	spans.reverse()
	for token in spans:
		var value := str(token.text)
		if not (value.begins_with("'") or value.begins_with('"') or value.begins_with("`") or (value.begins_with("[") and value.length() > 1)): continue
		var placeholder := '"' + prefix + str(literals.size()) + '"'
		literals[placeholder] = value
		replacements.append({"start": token.start, "end": token.end, "text": placeholder})
	return {"source": apply_edits(source, replacements), "literals": literals}

static func restore_strings(source: String, literals: Dictionary) -> String:
	if literals.is_empty(): return source
	# Placeholders share a collision-free prefix. Scan it once instead of
	# copying the entire script once for every literal in a large place.
	var first := str(literals.keys()[0])
	var prefix := first.left(first.length() - 2)
	var pieces := PackedStringArray()
	var cursor := 0
	var start := source.find(prefix)
	while start >= 0:
		var finish := source.find('"', start + prefix.length())
		if finish < 0: break
		var placeholder := source.substr(start, finish - start + 1)
		if literals.has(placeholder):
			pieces.append(source.substr(cursor, start - cursor))
			pieces.append(str(literals[placeholder]))
			cursor = finish + 1
		start = source.find(prefix, finish + 1)
	pieces.append(source.substr(cursor))
	return "".join(pieces)

static func apply_edits(source: String, edits: Array[Dictionary]) -> String:
	# Descending offsets preserve the previous rewrite order, including multiple
	# insertions at one position. Assemble spans once without quadratic copies.
	edits.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.start) > int(b.start))
	var pieces := PackedStringArray()
	var cursor := source.length()
	for edit in edits:
		pieces.append(source.substr(int(edit.end), cursor - int(edit.end)))
		pieces.append(str(edit.text))
		cursor = int(edit.start)
	pieces.append(source.left(cursor))
	pieces.reverse()
	return "".join(pieces)

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
		if character in ["'", '"', "`"]:
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
