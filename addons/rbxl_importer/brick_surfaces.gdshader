shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D studs_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D inlets_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 face_types;
uniform vec2 end_types;
uniform float stud_scale = 0.5;
uniform float opacity = 1.0;
varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	// Each source image contains four studs per axis. Model scale increases
	// the number of repeats; moving or rotating a brick never slides its pattern.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	surface_position = VERTEX * scale / (4.0 * stud_scale);
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
	vec4 sample_color = kind == 3.0 ? texture(studs_texture, coords) : texture(inlets_texture, coords);
	ALBEDO = sample_color.rgb;
	ROUGHNESS = 0.8;
	ALPHA = (kind == 3.0 || kind == 4.0 || kind == 5.0) ? sample_color.a * opacity : 0.0;
}
