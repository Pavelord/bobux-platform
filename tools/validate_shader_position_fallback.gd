extends SceneTree

const COMPAT = preload("res://addons/roblox_runtime/roblox_shader_compatibility.gd")
const CACHE = preload("res://addons/roblox_runtime/roblox_shader_cache.gd")
const AUDIT = "res://.codex-tmp/performance/valley-visual-motion/shaders.json"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	var original := "shader_type spatial; uniform float tint = 1.0; void vertex(){ VERTEX.y += 0.1; if (PROJECTION_MATRIX[3][3] > 0.5) { POSITION = vec4(4.0, 4.0, 4.0, 1.0); } } void fragment(){ ALBEDO=vec3(tint); }"
	var fixed: String = COMPAT.perspective_position_fallback(original)
	check(fixed != original and fixed.contains("MODELVIEW_MATRIX * vec4(VERTEX, 1.0)"), "Guard gets perspective fallback after vertex deformation")
	check(COMPAT.perspective_position_fallback(fixed) == fixed, "Adapter is idempotent")
	for unchanged: String in [
		original.replace("shader_type spatial;", "shader_type canvas_item;"),
		original.replace("shader_type spatial;", "shader_type spatial; render_mode world_vertex_coords;"),
		original.replace("shader_type spatial;", "shader_type spatial; render_mode skip_vertex_transform;"),
		original.replace("} } void", "} else { POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0); } } void"),
		original.replace("} } void", "} VERTEX.y += 2.0; } void"),
		original.replace("POSITION = vec4", "VERTEX = vec4"),
		"shader_type spatial; void vertex(){ /* if(PROJECTION_MATRIX[3][3] > 0.5) { POSITION=vec4(1.0); } */ }",
		original.replace("VERTEX.y += 0.1;", "POSITION=vec4(1.0); VERTEX.y += 0.1;"),
	]: check(COMPAT.perspective_position_fallback(unchanged) == unchanged, "Valid/unrelated shader remains exact")
	check(COMPAT.perspective_position_fallback(original.replace("void vertex(){", "/*POSITION=x;*/ void vertex(){")) != original.replace("void vertex(){", "/*POSITION=x;*/ void vertex(){"), "Commented assignment is ignored")
	var programs: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIT))
	var adapted := 0
	if programs is Dictionary:
		for key: String in programs:
			var entry: Dictionary = programs[key]
			var code: String = entry.code
			var result: String = COMPAT.perspective_position_fallback(code)
			var water: bool = "w0305b.res" in entry.files
			check((result != code) == water, "Only original water program needs fallback: " + str(entry.files))
			if result != code: adapted += 1
		check(adapted == 1 and programs.size() == 14, "All fourteen original programs audited")
	else: failures.append("Original Valley shader audit missing")
	var shader := Shader.new()
	shader.code = original
	var first := ShaderMaterial.new()
	first.shader = shader
	first.set_shader_parameter("tint", 0.25)
	var second := ShaderMaterial.new()
	second.shader = shader
	second.set_shader_parameter("tint", 0.75)
	var first_mesh := BoxMesh.new()
	first_mesh.material = first
	var second_mesh := BoxMesh.new()
	second_mesh.material = second
	CACHE.share_mesh_programs(first_mesh)
	CACHE.share_mesh_programs(second_mesh)
	check(shader.code == original, "Authored Shader resource is not mutated")
	check(first.shader == second.shader and first.shader != shader and first.shader.code == fixed, "Compatible programs shared independently of original")
	check(is_equal_approx(first.get_shader_parameter("tint"), 0.25) and is_equal_approx(second.get_shader_parameter("tint"), 0.75), "Per-material uniforms preserved")
	print("[shader-position-fallback] checks=", checks, " original_programs=14 adapted=", adapted, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
