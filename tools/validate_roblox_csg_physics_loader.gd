extends SceneTree


func _initialize() -> void:
	var path := "res://tmp_ronaldinho.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing real RBXL fixture: %s" % path)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Could not parse RBXL fixture")
		quit(1)
		return
	var instances: Dictionary = (parsed as Dictionary).get("instances", {})
	var property_value: Variant = null
	for value in instances.values():
		if value is Dictionary and str(value.get("class", "")) == "UnionOperation":
			var properties: Dictionary = value.get("properties", {})
			if properties.has("PhysicalConfigData"):
				property_value = properties["PhysicalConfigData"]
				break
	var mesh := RobloxCsgPhysicsLoader.load_from_property(property_value)
	var valid := mesh != null and mesh.get_surface_count() > 0
	var vertices := 0
	var indices := 0
	var finite_bounds := false
	if valid:
		var arrays := mesh.surface_get_arrays(0)
		vertices = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		indices = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var bounds := mesh.get_aabb()
		finite_bounds = bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length_squared() > 0.0001
	var ok := valid and vertices >= 3 and indices >= 3 and finite_bounds
	print("[validate_roblox_csg_physics_loader] ok=%s vertices=%d indices=%d finite=%s" % [str(ok), vertices, indices, str(finite_bounds)])
	quit(0 if ok else 1)
