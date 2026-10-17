extends SceneTree

const Lexer = preload("res://addons/roblox_studio/roblox_lua_lexer.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var failures: Array[String] = []
	var source := "-- untouched: \"BOBUX_LITERAL_\"\nlocal a = 'Привет 😀'; local b = [==[long \"quotes\"\ntext]==]; local c = `Hi {a}`"
	var protected := Lexer.protect_strings(source)
	if Lexer.restore_strings(protected.source, protected.literals) != source: failures.append("Literal round trip")
	var samples := [
		"folder:WaitForChild('A'):WaitForChild('B').Changed:Connect(function() end)",
		"obj:Invoke(obj.Child:InvokeServer(2), obj:Wait())",
		"-- literal :Connect(x)\nlocal s = ':WaitForChild(123)'\nlocal c = signal:connect(function() print(s) end)",
		"local s = `Привет {object:WaitForChild('Name').Value} 😀`",
		"local a&#32;=1 -- &nbsp;\nlocal s = '&nbsp;'",
		"local s = [==[&#32; :Connect() `opaque`]==]\nlocal t = `x {`y {1}`} z`",
	]
	# Optional local golden comparison uses exact sources captured before changes.
	# This fixture stays outside the exported game; normal regressions need no maps.
	var golden_path := "res://.codex-tmp/performance/golden_engine.gd"
	if FileAccess.file_exists(golden_path):
		var golden: Node = load(golden_path).new()
		golden.set("_lua", engine.get("_lua"))
		for sample in samples:
			if golden._prepare_lua_body(sample) != engine._prepare_lua_body(sample): failures.append("Golden compatibility: " + sample)
		var directory := DirAccess.open("res://.codex-tmp/performance/map-audit")
		var checked_sources := {}
		if directory:
			for file in directory.get_files():
				if not file.ends_with(".json"): continue
				var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.get_current_dir().path_join(file)))
				if not map is Dictionary: continue
				var scripts: Variant = map.get("scripts", map.get("roblox_manifest", {}).get("scripts", []))
				if not scripts is Array: continue
				for script in scripts:
					if not script is Dictionary or not script.has("source"): continue
					var code := str(script.source)
					var digest := code.sha256_text()
					if checked_sources.has(digest): continue
					checked_sources[digest] = true
					var started := Time.get_ticks_usec()
					var before: String = golden._prepare_lua_body(code)
					var old_ms := (Time.get_ticks_usec() - started) / 1000.0
					started = Time.get_ticks_usec()
					var after: String = engine._prepare_lua_body(code)
					var new_ms := (Time.get_ticks_usec() - started) / 1000.0
					if before != after: failures.append("Mode source parity: " + str(script.name))
					print("[source-preparation] ", script.name, " before_ms=", old_ms, " after_ms=", new_ms, " same=", before == after)
		golden.free()
	# Explicit expected adapter form catches regressions without golden fixtures.
	var rewritten: String = engine._prepare_lua_body("signal:Connect(function() end)")
	if rewritten != "__bobux_connect(signal, function() end)": failures.append("Connect adapter")
	print("[source-preparation] failures=", failures)
	quit(0 if failures.is_empty() else 1)
