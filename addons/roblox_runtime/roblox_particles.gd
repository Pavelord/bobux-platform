extends RefCounted

static var _billboard_material: StandardMaterial3D

static func billboard_material() -> StandardMaterial3D:
	if _billboard_material != null: return _billboard_material
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5)
	texture.fill_to = Vector2(1.0,0.5)
	texture.gradient = Gradient.new()
	texture.gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
	_billboard_material = StandardMaterial3D.new()
	_billboard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_billboard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_billboard_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_billboard_material.vertex_color_use_as_albedo = true
	_billboard_material.albedo_texture = texture
	return _billboard_material

# Both the DataModel and legacy runtime-object loader use the same effect.
# Scalar *_xml properties are names used by the old Roblox serializer.
static func property(node: Node, key: String, fallback: Variant) -> Variant:
	if node.has_meta(key): return node.get_meta(key)
	var props: Dictionary = node.get_meta("roblox_properties", {})
	for candidate in props:
		if str(candidate).to_lower().trim_suffix("_xml") == key.to_lower(): return props[candidate]
	return fallback

static func number(node: Node, key: String, fallback: float) -> float:
	var value: Variant = property(node, key, null)
	# Old saves may carry a generic Node3D Size alongside the scalar size_xml.
	if not (value is int or value is float or value is String):
		var props: Dictionary = node.get_meta("roblox_properties", {})
		for candidate in props:
			if str(candidate).to_lower() == key.to_lower() + "_xml": value = props[candidate]
	if value is String:
		if not value.is_valid_float(): return fallback
		value = value.to_float()
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	return fallback

# Serialized NumberSequence/ColorSequence are arrays of keypoint dictionaries,
# whereas Color3 and NumberRange are arrays of numbers. Keep these distinct.
static func scalar(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float(): return value.to_float()
	return fallback

static func color_value(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if value is Color: return value
	if value is Array and value.size() >= 3 and (value[0] is float or value[0] is int):
		return Color(scalar(value[0], fallback.r), scalar(value[1], fallback.g), scalar(value[2], fallback.b))
	return fallback

static func sequence_value(value: Variant, time: float, fallback: float) -> float:
	if not value is Array or value.is_empty(): return scalar(value, fallback)
	var previous_time := 0.0
	var previous := fallback
	for point in value:
		if not point is Dictionary: continue
		var point_time := scalar(point.get("time"), previous_time)
		var point_value := scalar(point.get("value"), previous)
		if point_time >= time:
			return lerpf(previous, point_value, clampf((time - previous_time) / maxf(point_time - previous_time, 0.00001), 0, 1)) if point_time > previous_time else point_value
		previous_time = point_time
		previous = point_value
	return previous

static func emitter_ramp(colors: Variant, transparency: Variant) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	var points: Array = colors if colors is Array and not colors.is_empty() and colors[0] is Dictionary else [{"time": 0.0, "color": colors}, {"time": 1.0, "color": colors}]
	# Include transparency keypoints as well so fades don't disappear when the
	# color is constant. Color interpolation is performed by a separate gradient.
	var color_gradient := Gradient.new()
	color_gradient.offsets = PackedFloat32Array()
	color_gradient.colors = PackedColorArray()
	var times: Array[float] = [0.0, 1.0]
	for point in points:
		if not point is Dictionary: continue
		var time := clampf(scalar(point.get("time"), 0), 0, 1)
		color_gradient.add_point(time, color_value(point.get("color")))
		if not times.has(time): times.append(time)
	if transparency is Array:
		for point in transparency:
			if point is Dictionary:
				var time := clampf(scalar(point.get("time"), 0), 0, 1)
				if not times.has(time): times.append(time)
	times.sort()
	for time in times:
		var color := color_gradient.sample(time)
		color.a = 1.0 - clampf(sequence_value(transparency, time, 0), 0, 1)
		gradient.add_point(time, color)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

static func configure(particles: GPUParticles3D, stud_scale: float = 0.5) -> void:
	var kind := str(particles.get_meta("roblox_class", "Smoke"))
	var fire := kind == "Fire"
	var smoke := kind == "Smoke"
	var diameter := maxf(number(particles, "Size", 5.0 if fire else 1.0), 0.1) * stud_scale
	var rise := number(particles, "RiseVelocity" if smoke else "Heat", 1.0 if smoke else 9.0) * stud_scale
	particles.emitting = bool(property(particles, "Enabled", true))
	particles.amount = clampi(int(number(particles, "Rate", 40 if fire else 32)), 1, 512)
	particles.lifetime = 1.1 if fire else 3.0
	particles.local_coords = false
	# A spreading fire may create hundreds of emitters in one frame. Warming
	# every emitter through a full lifetime stalls the renderer at each ignition.
	particles.preprocess = 0.0
	particles.fixed_fps = 30
	# Child effects must not inherit their Part's Size as a transform scale.
	if particles.is_inside_tree(): particles.global_basis = Basis.IDENTITY
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0 if smoke else 18.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = rise * 0.8
	process.initial_velocity_max = rise * 1.2
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = diameter * 0.12
	process.scale_min = 0.6
	process.scale_max = 1.0
	var raw: Variant = property(particles, "Color", Color(1.0, 0.47, 0.08) if fire else Color(0.65, 0.65, 0.65))
	var color := color_value(raw)
	process.color = color
	var fade := Gradient.new()
	var opacity := clampf(number(particles, "Opacity", 0.5 if smoke else 0.9), 0.0, 1.0)
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	fade.colors = PackedColorArray([Color(1,1,1,0), Color(1,1,1,opacity), Color(1,1,1,opacity*0.65), Color(1,1,1,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	if kind == "ParticleEmitter":
		var lifetime_range: Variant = property(particles, "Lifetime", [1.0, 1.0])
		var min_lifetime := 1.0
		if lifetime_range is Array and lifetime_range.size() >= 2:
			min_lifetime = maxf(scalar(lifetime_range[0], 1), 0.01)
			particles.lifetime = maxf(scalar(lifetime_range[1], min_lifetime), min_lifetime)
		process.lifetime_randomness = clampf(1.0 - min_lifetime / particles.lifetime, 0.0, 1.0)
		var rate := maxf(number(particles, "Rate", 5), 0)
		particles.amount = clampi(ceili(rate * particles.lifetime), 1, 512)
		particles.emitting = particles.emitting and rate > 0
		particles.preprocess = 0.0
		particles.local_coords = bool(property(particles, "LockedToPart", false))
		var speed: Variant = property(particles, "Speed", [1.0, 1.0])
		if speed is Array and speed.size() >= 2:
			process.initial_velocity_min = scalar(speed[0], 1) * stud_scale
			process.initial_velocity_max = maxf(scalar(speed[1], 1) * stud_scale, process.initial_velocity_min)
		var directions := [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.LEFT, Vector3.DOWN, Vector3.FORWARD]
		process.direction = directions[clampi(int(number(particles, "EmissionDirection", 1)), 0, 5)]
		process.color = Color.WHITE
		process.color_ramp = emitter_ramp(raw, property(particles, "Transparency", 0.0))
		var sizes: Variant = property(particles, "Size", 1.0)
		var curve := Curve.new()
		curve.max_value = 100.0
		if sizes is Array:
			for point in sizes:
				if point is Dictionary: curve.add_point(Vector2(clampf(scalar(point.get("time"), 0), 0, 1), maxf(scalar(point.get("value"), 1), 0)))
		if curve.point_count == 0:
			curve.add_point(Vector2(0, maxf(scalar(sizes, 1), 0)))
			curve.add_point(Vector2(1, maxf(scalar(sizes, 1), 0)))
		var size_curve := CurveTexture.new()
		size_curve.curve = curve
		process.scale_min = 1.0
		process.scale_max = 1.0
		process.scale_curve = size_curve
		diameter = stud_scale
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter * (1.4 if fire else 1.0))
	quad.material = billboard_material()
	particles.draw_pass_1 = quad
	var extent := diameter + absf(rise) * particles.lifetime
	particles.visibility_aabb = AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
