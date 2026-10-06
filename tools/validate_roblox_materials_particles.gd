extends SceneTree

const CACHE = preload("res://addons/rbxl_importer/material_cache.gd")
const PARTICLES = preload("res://addons/roblox_runtime/roblox_particles.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.scale = Vector3(8, 2, 4)
	world.add_child(part)
	var props := {"Material": "Enum.Material.Brick", "Color": [0.7, 0.2, 0.1], "TopSurface": "Studs", "BottomSurface": {"Value": 4}, "LeftSurface": "Universal"}
	engine._apply_manifest_part_appearance(part, props)
	var material := part.material_override as StandardMaterial3D
	check(material != null and material.albedo_texture != null, "storage template lost material texture")
	check(material.albedo_color.is_equal_approx(Color(0.7, 0.2, 0.1)), "storage template lost Part color")
	check(material.uv1_scale.is_equal_approx(Vector3(2, 0.5, 1)), "material tiles must follow physical stud size")
	check(material.next_pass.get_shader_parameter("face_types") == Vector4(3,4,0,5), "named and numeric SurfaceTypes differ")
	check(material.next_pass.get_shader_parameter("surface_atlas") is Texture2D, "classic surface atlas is missing")
	var texture_cache := CACHE.new()
	for material_name in CACHE.NAMED_MATERIAL_ENUMS.keys():
		if material_name in ["Plastic", "SmoothPlastic", "Neon", "ForceField", "Water"]:
			continue
		var named_material: StandardMaterial3D = texture_cache.get_named_material(Color.WHITE, str(material_name))
		var texture := named_material.albedo_texture as Texture2D if named_material != null else null
		check(texture != null and texture.get_width() > 4 and texture.get_height() > 4, "%s needs a real non-placeholder albedo texture" % str(material_name))
	var before := material.albedo_color
	engine.BobuxInstance.wrap(part)._set(&"Color", Color(0.1, 0.15, 0.2))
	check(part.material_override.next_pass.get_shader_parameter("part_color").is_equal_approx(Color(0.1, 0.15, 0.2)), "fire color changes do not reach surface overlay")
	check(material.albedo_color == before, "changing one Part recolors cached materials")
	check(CACHE.surface_type_value("Enum.SurfaceType.Weld") == 2, "Weld mapping")
	var emitter := GPUParticles3D.new()
	emitter.set_meta("roblox_class", "ParticleEmitter")
	emitter.set_meta("roblox_properties", {
		"Color": [{"time":0, "color":[1,0,0]}, {"time":1, "color":[0,0,1]}],
		"Size": [{"time":0, "value":2}, {"time":1, "value":6}],
		"Transparency": [{"time":0, "value":0}, {"time":1, "value":1}],
		"Lifetime":[1,2], "Speed":[4,8], "Rate":10
	})
	world.add_child(emitter)
	PARTICLES.configure(emitter)
	var process := emitter.process_material as ParticleProcessMaterial
	check(emitter.amount == 20 and emitter.lifetime == 2, "ParticleEmitter rate/lifetime")
	check(process.color_ramp.gradient.sample(1).a == 0, "ColorSequence/Transparency fade")
	check(is_equal_approx(process.scale_curve.curve.sample(1), 6), "NumberSequence size")
	print("[roblox_materials_particles] failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
