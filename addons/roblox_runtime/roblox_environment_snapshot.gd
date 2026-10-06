extends RefCounted

# JSON-safe render settings shared by Studio and published places. Sky images
# are resolved separately; these values must not inherit the lobby's exposure.
const ENV_PROPERTIES := [
	"tonemap_mode", "tonemap_exposure", "tonemap_white", "reflected_light_source",
	"ambient_light_sky_contribution", "background_energy_multiplier",
	"adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation",
	"ssao_enabled", "ssil_enabled", "sdfgi_enabled", "ssr_enabled", "volumetric_fog_enabled",
	"fog_sky_affect", "fog_sun_scatter", "fog_aerial_perspective"
]
const SUN_PROPERTIES := ["light_energy", "light_indirect_energy", "light_volumetric_fog_energy", "shadow_enabled", "light_angular_distance"]

static func capture(env: Environment, sun: DirectionalLight3D) -> Dictionary:
	var result := {"environment": {}, "sun": {}}
	if env != null:
		for key in ENV_PROPERTIES: result.environment[key] = env.get(key)
	if sun != null:
		for key in SUN_PROPERTIES: result.sun[key] = sun.get(key)
		result.sun["color"] = [sun.light_color.r, sun.light_color.g, sun.light_color.b]
		result.sun["rotation"] = [sun.rotation_degrees.x, sun.rotation_degrees.y, sun.rotation_degrees.z]
	return result

static func apply(env: Environment, sun: DirectionalLight3D, settings: Dictionary) -> void:
	if settings.is_empty(): return
	var snapshot: Dictionary = settings.get("render_snapshot", {})
	var saved_env: Dictionary = snapshot.get("environment", {})
	var defaults := Environment.new()
	for key in ENV_PROPERTIES:
		env.set(key, saved_env.get(key, defaults.get(key)))
	if sun == null: return
	var saved_sun: Dictionary = snapshot.get("sun", {})
	if not saved_sun.is_empty():
		for key in SUN_PROPERTIES:
			if saved_sun.has(key): sun.set(key, saved_sun[key])
		var color: Array = saved_sun.get("color", [1.0, 0.97, 0.90])
		var angles: Array = saved_sun.get("rotation", [-45.0, -45.0, 0.0])
		sun.light_color = Color(color[0], color[1], color[2])
		sun.rotation_degrees = Vector3(angles[0], angles[1], angles[2])
	elif settings.get("lighting") is Dictionary:
		# Published maps from before snapshots still contain the Roblox source.
		var props: Dictionary = settings.lighting
		sun.light_energy = clampf(0.55 + float(props.get("Brightness", 2.0)) * 0.58, 0.35, 3.2)
		sun.light_color = Color(1.0, 0.97, 0.90)
		sun.shadow_enabled = bool(props.get("GlobalShadows", true))
		sun.rotation_degrees.y = -45.0
