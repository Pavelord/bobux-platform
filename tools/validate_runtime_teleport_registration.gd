extends SceneTree

func _initialize() -> void:
	var runtime = load("res://scripts/main/main.gd").new()
	var first := MeshInstance3D.new()
	first.scale = Vector3(4.0, 0.4, 4.0)
	var second := MeshInstance3D.new()
	second.scale = Vector3(4.0, 0.4, 4.0)
	runtime.add_child(first)
	runtime.add_child(second)
	var pair_color := Color(0.2, 0.65, 1.0)
	runtime.call("_register_teleport_block", first, pair_color, "")
	runtime.call("_register_teleport_block", second, pair_color, "")
	runtime.call("_add_teleport_trigger", first, func(_body): pass)
	var key := str(first.get_meta("teleport_color_key", ""))
	var registry: Dictionary = runtime.get("_teleport_blocks_by_color")
	var cylinder: CylinderShape3D = null
	for child in first.get_children():
		if child is Area3D:
			for area_child in child.get_children():
				if area_child is CollisionShape3D and (area_child as CollisionShape3D).shape is CylinderShape3D:
					cylinder = (area_child as CollisionShape3D).shape as CylinderShape3D
	if key.is_empty() or not registry.has(key) or (registry[key] as Array).size() != 2 or cylinder == null or cylinder.radius < 1.8:
		push_error("[validate_runtime_teleport_registration] key=%s pair=%s radius=%s" % [key, (registry.get(key, []) as Array).size(), cylinder.radius if cylinder != null else -1.0])
		runtime.free()
		quit(1)
		return
	print("[validate_runtime_teleport_registration] pair and trigger OK")
	runtime.free()
	quit(0)
