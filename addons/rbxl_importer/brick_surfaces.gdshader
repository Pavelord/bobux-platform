shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Roblox's original 128 x 2048 atlas: four 128 x 512 strips, each 2 x 8 studs.
// Studs / crossed Weld+Glue / Inlet / alternating Universal.
uniform sampler2D surface_atlas : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform vec4 part_color : source_color = vec4(1.0);
uniform vec4 face_types;
uniform vec2 end_types;
uniform float stud_scale = 0.5;
uniform float opacity = 1.0;
varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	// Measure in studs, independently of the Part's size. Local coordinates
	// keep the pattern attached when the Part moves or rotates.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	surface_position = VERTEX * scale / stud_scale;
	surface_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(surface_normal);
	vec2 coords = surface_position.xz;
	float kind = n.y > 0.0 ? face_types.x : face_types.y;
	if (abs(n.x) > 0.9) {
		coords = surface_position.zy;
		kind = n.x > 0.0 ? face_types.z : face_types.w;
	} else if (abs(n.z) > 0.9) {
		coords = surface_position.xy;
		kind = n.z > 0.0 ? end_types.x : end_types.y;
	} else if (abs(n.y) < 0.9) {
		kind = 0.0;
	}
	float strip = kind == 3.0 ? 0.0 : ((kind == 1.0 || kind == 2.0) ? 1.0 : (kind == 4.0 ? 2.0 : 3.0));
	vec2 tiled = coords / vec2(2.0, 8.0);
	vec2 atlas_uv = vec2(fract(tiled.x), (strip + fract(tiled.y)) * 0.25);
	// Prevent mip derivatives from spiking at the fract seam.
	vec3 detail = textureGrad(surface_atlas, atlas_uv, dFdx(tiled) * vec2(1.0, 0.25), dFdy(tiled) * vec2(1.0, 0.25)).rgb;
	// The atlas has a neutral 128/255 background (0.216 in linear space).
	// Keep the imported Part's color instead of painting every brick gray.
	float neutral = OUTPUT_IS_SRGB ? (128.0 / 255.0) : 0.21586;
	ALBEDO = clamp(part_color.rgb * detail / neutral, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.8;
	ALPHA = (kind >= 1.0 && kind <= 5.0) ? opacity : 0.0;
}
