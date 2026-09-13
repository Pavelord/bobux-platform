extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var cases := [
		["for skips one iteration", "local n=0\nfor i=1,4 do\n if i==2 then continue end\n local value=i\n n=n+value\nend\nreturn n", 8],
		["while locals and continue", "local i,n=0,0\nwhile i<4 do\n i=i+1\n if i==2 then continue end\n local value=i\n n=n+value\nend\nreturn n", 8],
		["nested continue and break", "local n=0\nfor i=1,3 do\n if i==2 then continue end\n for j=1,4 do\n if j==2 then continue end\n if j==4 then break end\n n=n+10*i+j\n end\nend\nreturn n", 88],
		["repeat condition still executes", "local n=0\nrepeat\n n=n+1\n local done=n>=4\n if n<3 then continue end\nuntil done\nreturn n", 4],
		["continue function name", "local continue=function() return 3 end\nlocal n=0\nfor i=1,2 do\n n=n+continue()\n local alias=continue\n n=n+alias()\nend\nreturn n", 12],
		["strings and comments unchanged", "--[[ `bad { continue` ]]\nlocal n='`literal {1}`'\nfor i=1,2 do\n -- continue\n if i==1 then continue end\n n=n..[[ continue ` ]]\nend\nreturn n", "`literal {1}` continue ` "],
		["interpolation evaluates once in order", "local n=0\nlocal function nextValue() n=n+1 return n end\nreturn `{nextValue()}:{nextValue()}:{n}`", "1:2:2"],
		["nested template and table expression", 'local n=2\nreturn `outer {`inner {n}`} {({value="}"}).value}`', "outer inner 2 }"],
		["literal percent braces quotes", 'return `100% \\{literal} \\` "quoted"`', '100% {literal} ` "quoted"'],
		["interpolation nil boolean tostring", "local t=setmetatable({}, {__tostring=function() return 'custom' end})\nreturn `{nil}:{false}:{t}`", "nil:false:custom"],
		["unicode and escaped newline", 'return `\\u{41}\\nB`', "A\nB"],
		["multiline template", "return `first\nsecond {2+3}`", "first\nsecond 5"],
	]
	for test in cases:
		var context := Node.new()
		root.add_child(context)
		var source := "local function run()\n" + str(test[1]) + "\nend\nscript:SetAttribute('Result',run())"
		var result: Dictionary = engine.start_script(source, context, {})
		var actual: Variant = context.get_meta("attribute_Result", null)
		var ok: bool = bool(result.get("ok", false)) and actual == test[2]
		print("[luau_semantics] ", test[0], "=", ok, " result=", actual)
		if not ok:
			failures.append(str(test[0]))
			print(result)
			print(engine._prepare_lua_body(source))
		engine.stop_all_scripts(context)
		context.queue_free()
		await process_frame
	# Broken templates must fail, rather than silently become a different string.
	for invalid in ["return `unterminated", "return `empty {}`"]:
		var prepared: String = engine._prepare_lua_body(invalid)
		if not "`" in prepared: failures.append("malformed interpolation silently accepted")
	engine.release_stopped_script_states()
	print("[luau_semantics] failures=", failures)
	quit(0 if failures.is_empty() else 1)
