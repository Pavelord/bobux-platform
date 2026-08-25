extends SceneTree


func _init() -> void:
	var lua = ClassDB.instantiate("LuaAPI")
	var bind_error = lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "coroutine"]))
	if bind_error != null and bind_error.has_method("get_message") and not str(bind_error.get_message()).is_empty():
		push_error("bind_libraries failed: %s" % bind_error.get_message())
		quit(1)
		return
	var coroutine = lua.new_coroutine()
	coroutine.push_variant("report", func(value): print("REPORT ", value))
	var load_error = coroutine.load_string("report('start'); coroutine.yield(0.05); report('resume'); return 42")
	if load_error != null and load_error.has_method("get_message") and not str(load_error.get_message()).is_empty():
		push_error("load_string failed: %s" % load_error.get_message())
		quit(1)
		return
	var first = coroutine.resume([])
	print("FIRST type=", type_string(typeof(first)), " value=", first, " done=", coroutine.is_done())
	var second = coroutine.resume([])
	print("SECOND type=", type_string(typeof(second)), " value=", second, " done=", coroutine.is_done())
	quit(0 if coroutine.is_done() else 1)
