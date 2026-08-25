extends SceneTree

func _initialize() -> void:
	if not ClassDB.class_exists("LuaAPI"):
		print("LuaAPI unavailable")
		quit(1)
		return
	var lua: Variant = ClassDB.instantiate("LuaAPI")
	var names: Array[String] = []
	for method_variant in lua.get_method_list():
		if method_variant is Dictionary:
			names.append(str((method_variant as Dictionary).get("name", "")))
	names.sort()
	print("[inspect_luaapi_methods] %s" % JSON.stringify(names))
	quit(0)
