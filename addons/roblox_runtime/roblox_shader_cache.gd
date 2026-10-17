extends RefCounted
## Published mesh files embed independent Shader resources even when their code
## is identical. Share the program while preserving each material's uniforms.
static var _programs: Dictionary = {}
const COMPATIBILITY = preload("res://addons/roblox_runtime/roblox_shader_compatibility.gd")

static func share_mesh_programs(mesh: Mesh) -> void:
	if mesh == null or mesh.get_meta("bobux_programs_shared", false): return
	for index in mesh.get_surface_count():
		var material := mesh.surface_get_material(index)
		while material != null:
			if material is ShaderMaterial and material.shader != null:
				var program: Shader = material.shader
				var key := str(program.get_meta("bobux_source_shader_hash", program.code.sha256_text()))
				var cached: WeakRef = _programs.get(key)
				var shared := cached.get_ref() as Shader if cached != null else null
				if shared == null:
					var compatible := COMPATIBILITY.perspective_position_fallback(program.code)
					shared = program
					if compatible != program.code:
						shared = Shader.new()
						shared.code = compatible
						shared.set_meta("bobux_source_shader_hash", key)
					_programs[key] = weakref(shared)
				material.shader = shared
			material = material.next_pass
	mesh.set_meta("bobux_programs_shared", true)
	if _programs.size() > 256:
		for key in _programs.keys():
			if _programs[key].get_ref() == null: _programs.erase(key)
