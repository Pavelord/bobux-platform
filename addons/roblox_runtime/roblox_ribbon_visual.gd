@tool
extends MeshInstance3D

## Lightweight visual approximation for Roblox Beam and Trail instances.
## Texture IDs stay in roblox_properties; this helper never requests assets.

var _roblox_class := "Beam"
var _attachment0: Node3D
var _attachment1: Node3D
var _properties: Dictionary = {}
var _stud_scale := 0.5
var _ribbon_mesh: ImmediateMesh
var _ribbon_material: StandardMaterial3D
var _trail_samples: Array[Dictionary] = []
var _last_sample_usec := 0


func configure_ribbon(roblox_class: String, attachment0: Node3D, attachment1: Node3D,
		properties: Dictionary, stud_scale: float) -> void:
	_roblox_class = roblox_class
	_attachment0 = attachment0
	_attachment1 = attachment1
	_properties = properties.duplicate(true)
	_stud_scale = maxf(stud_scale, 0.001)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon_material = StandardMaterial3D.new()
	_ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_material.vertex_color_use_as_albedo = true
	mesh = _ribbon_mesh
	set_process(true)
	_update_material_color()


func _process(_delta: float) -> void:
	if _ribbon_mesh == null:
		return
	if not bool(_property("Enabled", true)):
		_ribbon_mesh.clear_surfaces()
		if _roblox_class == "Trail":
			_trail_samples.clear()
		return
	if _roblox_class == "Trail":
		_update_trail()
	else:
		_update_beam()


func _update_beam() -> void:
	_ribbon_mesh.clear_surfaces()
	if not is_instance_valid(_attachment0) or not is_instance_valid(_attachment1):
		return
	var start := _attachment0.global_position
	var finish := _attachment1.global_position
	var segment_count := clampi(int(_number_property("Segments", 10.0)), 1, 32)
	var width0 := maxf(_number_property("Width0", 1.0) * _stud_scale, 0.001)
	var width1 := maxf(_number_property("Width1", 1.0) * _stud_scale, 0.001)
	var curve0 := _number_property("CurveSize0", 0.0) * _stud_scale
	var curve1 := _number_property("CurveSize1", 0.0) * _stud_scale
	var up0 := _attachment0.global_basis.y.normalized()
	var up1 := _attachment1.global_basis.y.normalized()
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ribbon_material)
	for index in range(segment_count + 1):
		var amount := float(index) / float(segment_count)
		var inverse := 1.0 - amount
		var center := start.lerp(finish, amount) + up0 * curve0 * inverse * inverse + up1 * curve1 * amount * amount
		var tangent := (finish - start).normalized()
		var side := _facing_side(tangent, center)
		var width := lerpf(width0, width1, amount)
		var color := _base_color()
		color.a *= 1.0 - clampf(_number_property("Transparency", 0.15), 0.0, 1.0)
		_ribbon_mesh.surface_set_color(color)
		_ribbon_mesh.surface_add_vertex(to_local(center - side * width * 0.5))
		_ribbon_mesh.surface_add_vertex(to_local(center + side * width * 0.5))
	_ribbon_mesh.surface_end()


func _update_trail() -> void:
	if not is_instance_valid(_attachment0):
		_ribbon_mesh.clear_surfaces()
		_trail_samples.clear()
		return
	var now_usec := Time.get_ticks_usec()
	var lifetime := clampf(_number_property("Lifetime", 2.0), 0.03, 60.0)
	var first := _attachment0.global_position
	var second: Vector3
	if is_instance_valid(_attachment1):
		second = _attachment1.global_position
	else:
		var fallback_side := _facing_side(Vector3.FORWARD, first)
		var half_width := maxf(_number_property("Width0", 1.0) * _stud_scale * 0.5, 0.001)
		second = first + fallback_side * half_width * 2.0
	var sample_interval := int(maxf(_number_property("MinLength", 0.05) * _stud_scale, 0.005) * 1000000.0)
	var should_sample := _trail_samples.is_empty() or now_usec - _last_sample_usec >= 33000
	if should_sample and not _trail_samples.is_empty():
		var last: Dictionary = _trail_samples.back()
		var previous_a: Vector3 = last["a"]
		var previous_b: Vector3 = last["b"]
		var previous_center: Vector3 = previous_a.lerp(previous_b, 0.5)
		should_sample = previous_center.distance_to(first.lerp(second, 0.5)) >= maxf(float(sample_interval) / 1000000.0, 0.005) or now_usec - _last_sample_usec >= 100000
	if should_sample:
		_trail_samples.append({"a": first, "b": second, "time": now_usec})
		_last_sample_usec = now_usec
	while not _trail_samples.is_empty() and now_usec - int(_trail_samples[0]["time"]) > int(lifetime * 1000000.0):
		_trail_samples.pop_front()
	while _trail_samples.size() > 256:
		_trail_samples.pop_front()
	_ribbon_mesh.clear_surfaces()
	if _trail_samples.size() < 2:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ribbon_material)
	var transparency := clampf(_number_property("Transparency", 0.0), 0.0, 1.0)
	for index in range(1, _trail_samples.size()):
		var previous: Dictionary = _trail_samples[index - 1]
		var current: Dictionary = _trail_samples[index]
		var previous_a: Vector3 = previous["a"]
		var previous_b: Vector3 = previous["b"]
		var current_a: Vector3 = current["a"]
		var current_b: Vector3 = current["b"]
		var age := clampf(float(now_usec - int(current["time"])) / float(lifetime * 1000000.0), 0.0, 1.0)
		var color := _base_color()
		color.a *= (1.0 - transparency) * (1.0 - age)
		_ribbon_mesh.surface_set_color(color)
		_ribbon_mesh.surface_add_vertex(to_local(previous_a))
		_ribbon_mesh.surface_add_vertex(to_local(previous_b))
		_ribbon_mesh.surface_add_vertex(to_local(current_a))
		_ribbon_mesh.surface_add_vertex(to_local(previous_b))
		_ribbon_mesh.surface_add_vertex(to_local(current_b))
		_ribbon_mesh.surface_add_vertex(to_local(current_a))
	_ribbon_mesh.surface_end()


func _facing_side(direction: Vector3, center: Vector3) -> Vector3:
	var view_direction := Vector3.UP
	if is_inside_tree() and get_viewport() != null and get_viewport().get_camera_3d() != null:
		view_direction = get_viewport().get_camera_3d().global_position - center
	var side := direction.cross(view_direction)
	if side.length_squared() < 0.000001:
		side = direction.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	return side.normalized()


func _update_material_color() -> void:
	if _ribbon_material != null:
		_ribbon_material.albedo_color = _base_color()


func _base_color() -> Color:
	var value: Variant = _property("Color", [1.0, 1.0, 1.0])
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		var channels: Array = value
		return Color(float(channels[0]), float(channels[1]), float(channels[2]), 1.0)
	if value is Dictionary:
		var color_data: Dictionary = value
		for key in ["value", "color", "Color3"]:
			if color_data.has(key):
				var nested: Variant = color_data[key]
				if nested is Array and (nested as Array).size() >= 3:
					var channels: Array = nested
					return Color(float(channels[0]), float(channels[1]), float(channels[2]), 1.0)
		if color_data.has("r") and color_data.has("g") and color_data.has("b"):
			return Color(float(color_data["r"]), float(color_data["g"]), float(color_data["b"]), 1.0)
	return Color.WHITE


func _number_property(name: String, fallback: float) -> float:
	var value: Variant = _property(name, fallback)
	if value is int or value is float:
		return float(value)
	if value is Array and not (value as Array).is_empty():
		var first: Variant = (value as Array)[0]
		if first is int or first is float:
			return float(first)
		if first is Dictionary:
			var point: Dictionary = first
			var point_value: Variant = point.get("value", point.get("Value", fallback))
			if point_value is int or point_value is float:
				return float(point_value)
	if value is Dictionary:
		var data: Dictionary = value
		for key in ["value", "Value", "default"]:
			var nested: Variant = data.get(key, null)
			if nested is int or nested is float:
				return float(nested)
	return fallback


func _property(name: String, fallback: Variant) -> Variant:
	if _properties.has(name):
		return _properties[name]
	var lowercase := name.to_lower()
	for key in _properties.keys():
		if str(key).to_lower().trim_suffix("_xml") == lowercase:
			return _properties[key]
	return fallback
