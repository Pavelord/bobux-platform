@tool
class_name RobloxSkyMaterial
extends RefCounted

## Builds a Roblox-like cloudy panorama sky for imported places.
## Godot's ProceduralSkyMaterial has a gray ground horizon that makes Roblox
## maps look like they are floating on a gray table. A generated panorama keeps
## the horizon blue and gives older places the familiar clouded Roblox backdrop.

const SKY_WIDTH := 768
const SKY_HEIGHT := 384
const SKYBOX_FACE_PROPS := {
	"Ft": "SkyboxFt",
	"Bk": "SkyboxBk",
	"Lf": "SkyboxLf",
	"Rt": "SkyboxRt",
	"Up": "SkyboxUp",
	"Dn": "SkyboxDn",
}


static func apply_to_environment(env: Environment, sky_color: Color) -> void:
	if env == null:
		return
	var sky := Sky.new()
	var material := PanoramaSkyMaterial.new()
	material.panorama = make_texture(sky_color)
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_color = sky_color


static func apply_skybox_from_properties(env: Environment, props: Dictionary, fallback_color: Color) -> bool:
	var face_paths := skybox_face_paths_from_properties(props)
	if face_paths.is_empty():
		return false
	return apply_skybox_to_environment(env, face_paths, fallback_color)


static func apply_skybox_to_environment(env: Environment, face_paths: Dictionary, fallback_color: Color) -> bool:
	if env == null:
		return false
	var texture := make_skybox_texture(face_paths, fallback_color)
	if texture == null:
		return false
	var sky := Sky.new()
	var material := PanoramaSkyMaterial.new()
	material.panorama = texture
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_color = fallback_color
	return true


static func make_texture(sky_color: Color) -> Texture2D:
	return ImageTexture.create_from_image(make_image(sky_color))


static func make_image(sky_color: Color) -> Image:
	var image := Image.create(SKY_WIDTH, SKY_HEIGHT, false, Image.FORMAT_RGBA8)
	var top := sky_color.lightened(0.18)
	var horizon := Color(0.78, 0.94, 1.0).lerp(sky_color, 0.18)
	var lower := Color(0.58, 0.80, 0.95).lerp(sky_color, 0.28)
	for y in range(SKY_HEIGHT):
		var v := float(y) / float(maxi(SKY_HEIGHT - 1, 1))
		var row_color := top.lerp(horizon, clampf(v / 0.52, 0.0, 1.0))
		if v > 0.52:
			row_color = horizon.lerp(lower, clampf((v - 0.52) / 0.48, 0.0, 1.0))
		for x in range(SKY_WIDTH):
			var u := float(x) / float(maxi(SKY_WIDTH - 1, 1))
			var cloud := _cloud_amount(u, v)
			var cloud_color := Color(1.0, 1.0, 1.0).lerp(Color(0.88, 0.94, 1.0), clampf(v * 1.4, 0.0, 1.0))
			image.set_pixel(x, y, row_color.lerp(cloud_color, cloud))
	return image


static func make_skybox_texture(face_paths: Dictionary, fallback_color: Color) -> Texture2D:
	var faces: Dictionary = {}
	for face_variant in face_paths.keys():
		var face := str(face_variant)
		var path := str(face_paths[face_variant]).strip_edges()
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var image := Image.new()
		if image.load(path) == OK and image.get_width() > 0 and image.get_height() > 0:
			faces[face] = image
	if faces.is_empty():
		return null
	var fallback := make_image(fallback_color)
	var panorama := Image.create(SKY_WIDTH, SKY_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(SKY_HEIGHT):
		for x in range(SKY_WIDTH):
			var dir := _panorama_direction(x, y)
			var sample := _sample_skybox(faces, dir, fallback, x, y)
			panorama.set_pixel(x, y, sample)
	return ImageTexture.create_from_image(panorama)


static func skybox_face_paths_from_properties(props: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for face_variant in SKYBOX_FACE_PROPS.keys():
		var face := str(face_variant)
		var prop_name := str(SKYBOX_FACE_PROPS[face])
		var content := _content_to_string(props.get(prop_name, "")).strip_edges()
		if content.is_empty():
			continue
		var resolved := _resolve_texture_content_to_local_path(content)
		if not resolved.is_empty():
			result[face] = resolved
	return result


static func _panorama_direction(x: int, y: int) -> Vector3:
	var u := (float(x) + 0.5) / float(SKY_WIDTH)
	var v := (float(y) + 0.5) / float(SKY_HEIGHT)
	var lon := (u - 0.5) * TAU
	var lat := (0.5 - v) * PI
	var cp := cos(lat)
	return Vector3(sin(lon) * cp, sin(lat), -cos(lon) * cp).normalized()


static func _sample_skybox(faces: Dictionary, dir: Vector3, fallback: Image, fallback_x: int, fallback_y: int) -> Color:
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var az := absf(dir.z)
	var face := "Ft"
	var u := 0.5
	var v := 0.5
	if ax >= ay and ax >= az:
		if dir.x >= 0.0:
			face = "Rt"
			u = 0.5 + dir.z / maxf(ax * 2.0, 0.0001)
		else:
			face = "Lf"
			u = 0.5 - dir.z / maxf(ax * 2.0, 0.0001)
		v = 0.5 - dir.y / maxf(ax * 2.0, 0.0001)
	elif ay >= ax and ay >= az:
		if dir.y >= 0.0:
			face = "Up"
			u = 0.5 + dir.x / maxf(ay * 2.0, 0.0001)
			v = 0.5 + dir.z / maxf(ay * 2.0, 0.0001)
		else:
			face = "Dn"
			u = 0.5 + dir.x / maxf(ay * 2.0, 0.0001)
			v = 0.5 - dir.z / maxf(ay * 2.0, 0.0001)
	else:
		if dir.z >= 0.0:
			face = "Bk"
			u = 0.5 - dir.x / maxf(az * 2.0, 0.0001)
		else:
			face = "Ft"
			u = 0.5 + dir.x / maxf(az * 2.0, 0.0001)
		v = 0.5 - dir.y / maxf(az * 2.0, 0.0001)
	if not faces.has(face):
		return fallback.get_pixel(clampi(fallback_x, 0, fallback.get_width() - 1), clampi(fallback_y, 0, fallback.get_height() - 1))
	var image: Image = faces[face]
	var px := clampi(int(round(clampf(u, 0.0, 1.0) * float(image.get_width() - 1))), 0, image.get_width() - 1)
	var py := clampi(int(round(clampf(v, 0.0, 1.0) * float(image.get_height() - 1))), 0, image.get_height() - 1)
	return image.get_pixel(px, py)


static func _resolve_texture_content_to_local_path(content: Variant) -> String:
	var source := _content_to_string(content).strip_edges()
	if source.is_empty():
		return ""
	if source.begins_with("file://"):
		source = source.substr(7)
	if FileAccess.file_exists(source):
		return source
	var global_source := ProjectSettings.globalize_path(source)
	if global_source != source and FileAccess.file_exists(global_source):
		return global_source
	if source.begins_with("rbxasset://"):
		var asset_path := source.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		for candidate in [
			"res://addons/rbxl_importer/builtin_assets/%s" % asset_path,
			"res://images/%s" % asset_path.get_file(),
		]:
			if FileAccess.file_exists(candidate):
				return candidate
	var asset_id := _sanitize_asset_id(source)
	if asset_id.is_empty():
		return ""
	for ext in ["png", "jpg", "jpeg", "webp"]:
		for base in ["user://rbxl_assets", "res://addons/rbxl_importer/builtin_assets"]:
			var candidate := "%s/%s.%s" % [base, asset_id, ext]
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


static func _content_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return str(value).strip_edges()
	if value is Dictionary:
		var dict := value as Dictionary
		for key in ["value", "url", "path", "asset_id", "id"]:
			var candidate := str(dict.get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
	if value is Array:
		var arr := value as Array
		if not arr.is_empty():
			return _content_to_string(arr[0])
	return str(value).strip_edges()


static func _sanitize_asset_id(value: String) -> String:
	var out := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		if ch >= "0" and ch <= "9":
			out += ch
	return out


static func _cloud_amount(u: float, v: float) -> float:
	if v > 0.50:
		return 0.0
	var amount := 0.0
	var clouds := [
		Vector4(0.10, 0.19, 0.18, 0.055),
		Vector4(0.26, 0.13, 0.25, 0.070),
		Vector4(0.48, 0.22, 0.22, 0.060),
		Vector4(0.66, 0.16, 0.28, 0.075),
		Vector4(0.86, 0.25, 0.20, 0.060),
		Vector4(0.03, 0.33, 0.23, 0.065),
		Vector4(0.38, 0.35, 0.27, 0.060),
		Vector4(0.74, 0.34, 0.24, 0.055),
	]
	for cloud in clouds:
		var dx := absf(u - cloud.x)
		dx = minf(dx, 1.0 - dx)
		var dy := absf(v - cloud.y)
		var d := (dx / maxf(cloud.z, 0.001)) * (dx / maxf(cloud.z, 0.001)) + (dy / maxf(cloud.w, 0.001)) * (dy / maxf(cloud.w, 0.001))
		if d < 1.0:
			var puff := pow(1.0 - d, 1.8)
			amount = maxf(amount, puff)
	amount += 0.08 * sin((u * 37.0 + v * 19.0) * TAU) * clampf((0.50 - v) / 0.45, 0.0, 1.0)
	return clampf(amount * 0.92, 0.0, 0.88)
