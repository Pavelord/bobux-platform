extends SceneTree


func _init() -> void:
	for class_id in ["LuaAPI", "LuaCoroutine", "LuaError", "LuaFunction"]:
		print("CLASS ", class_id, " exists=", ClassDB.class_exists(class_id))
		if not ClassDB.class_exists(class_id):
			continue
		var methods: Array = ClassDB.class_get_method_list(class_id, true)
		for method_variant in methods:
			if not (method_variant is Dictionary):
				continue
			var method: Dictionary = method_variant
			print("  ", method.get("name", ""), " args=", method.get("args", []), " return=", method.get("return", {}))
	quit(0)
