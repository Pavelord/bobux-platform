extends SceneTree

var observed: Array = []


func _initialize() -> void:
	if not ClassDB.class_exists("LuaAPI"):
		push_error("LuaAPI is unavailable")
		quit(1)
		return
	var lua: Variant = ClassDB.instantiate("LuaAPI")
	var bind_error: Variant = lua.call("bind_libraries", PackedStringArray(["base", "table"]))
	if bind_error != null and bind_error.has_method("get_message") and not str(bind_error.call("get_message")).is_empty():
		push_error("bind_libraries failed: %s" % str(bind_error.call("get_message")))
		quit(1)
		return
	lua.call("push_variant", "return_array", func(): return ["part", Vector3(1.0, 2.0, 3.0), Vector3.UP])
	lua.call("push_variant", "report", func(a: Variant = null, b: Variant = null, c: Variant = null):
		observed = [a, b, c]
		print("[validate_luaapi_multiple_returns] report=%s" % str(observed))
	)
	var error: Variant = lua.call("do_string", "local a, b, c = return_array(); report(a, b, c)")
	if error != null and error.has_method("get_message") and not str(error.call("get_message")).is_empty():
		push_error("Lua execution failed: %s" % str(error.call("get_message")))
		quit(1)
		return
	print("[validate_luaapi_multiple_returns] observed=%s" % str(observed))
	quit(0)
