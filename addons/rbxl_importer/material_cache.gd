@tool
class_name RbxlMaterialCache
extends RefCounted

## Cache of Roblox → Godot material mappings.
##
## Roblox `Material` enum values are mapped to a StandardMaterial3D approximation
## (roughness / metallic / emission / transparency). Materials are cached by a
## (material_id, color, transparency, reflectance) key so identical parts share
## one resource.


# Roblox Material enum value → display parameters.
# Source: Roblox Enum.Material (values are the enum ordinals).
const ROBLOX_MATERIALS := {
	0:   {"name": "Plastic",       "roughness": 0.45, "metallic": 0.0},
	1:   {"name": "Wood",          "roughness": 0.96, "metallic": 0.0},
	2:   {"name": "Slate",         "roughness": 0.50, "metallic": 0.0},
	3:   {"name": "Concrete",      "roughness": 0.82, "metallic": 0.0},
	4:   {"name": "Metal",         "roughness": 0.22, "metallic": 0.85},
	5:   {"name": "Brick",         "roughness": 0.90, "metallic": 0.0},
	6:   {"name": "Grass",         "roughness": 0.97, "metallic": 0.0},
	7:   {"name": "Sand",          "roughness": 0.96, "metallic": 0.0},
	8:   {"name": "WoodPlanks",    "roughness": 0.88, "metallic": 0.0},
	9:   {"name": "Rock",          "roughness": 0.86, "metallic": 0.0},
	10:  {"name": "Glacier",       "roughness": 0.06, "metallic": 0.0},
	11:  {"name": "Snow",          "roughness": 0.82, "metallic": 0.0},
	12:  {"name": "Asphalt",       "roughness": 0.91, "metallic": 0.0},
	13:  {"name": "LeafyGrass",    "roughness": 0.97, "metallic": 0.0},
	14:  {"name": "Salt",          "roughness": 0.86, "metallic": 0.0},
	15:  {"name": "Limestone",     "roughness": 0.80, "metallic": 0.0},
	16:  {"name": "Pavement",      "roughness": 0.84, "metallic": 0.0},
	17:  {"name": "ForceField",    "roughness": 0.30, "metallic": 0.0, "transparent": true, "alpha": 0.4},
	256: {"name": "Plastic",       "roughness": 0.45, "metallic": 0.0},
	272: {"name": "SmoothPlastic", "roughness": 0.10, "metallic": 0.0},
	280: {"name": "Neon",          "roughness": 0.20, "metallic": 0.0, "emission": 1.5},
	288: {"name": "Neon",          "roughness": 0.20, "metallic": 0.0, "emission": 2.0},
	304: {"name": "Metal",         "roughness": 0.22, "metallic": 0.85},
	512: {"name": "Wood",          "roughness": 0.96, "metallic": 0.0},
	528: {"name": "WoodPlanks",    "roughness": 0.88, "metallic": 0.0},
	544: {"name": "Marble",        "roughness": 0.20, "metallic": 0.0},
	800: {"name": "Concrete",      "roughness": 0.82, "metallic": 0.0},
	1024:{"name": "Metal",         "roughness": 0.22, "metallic": 0.85},
	1040:{"name": "DiamondPlate",  "roughness": 0.30, "metallic": 0.90},
	1056:{"name": "Foil",          "roughness": 0.12, "metallic": 1.0},
	1280:{"name": "Grass",         "roughness": 0.97, "metallic": 0.0},
	1296:{"name": "LeafyGrass",    "roughness": 0.97, "metallic": 0.0},
	1312:{"name": "Sand",          "roughness": 0.96, "metallic": 0.0},
	1328:{"name": "Fabric",        "roughness": 0.92, "metallic": 0.0},
	1344:{"name": "Snow",          "roughness": 0.82, "metallic": 0.0},
	1360:{"name": "Mud",           "roughness": 1.00, "metallic": 0.0},
	1376:{"name": "Ground",        "roughness": 0.95, "metallic": 0.0},
	1392:{"name": "Asphalt",       "roughness": 0.91, "metallic": 0.0},
	1408:{"name": "Pavement",      "roughness": 0.84, "metallic": 0.0},
	1424:{"name": "Limestone",     "roughness": 0.80, "metallic": 0.0},
	1440:{"name": "Basalt",        "roughness": 0.86, "metallic": 0.0},
	1536:{"name": "Ice",           "roughness": 0.00, "metallic": 0.0, "transparent": true, "alpha": 0.55},
	1552:{"name": "Glacier",       "roughness": 0.06, "metallic": 0.0},
	1792:{"name": "Glass",         "roughness": 0.05, "metallic": 0.0, "transparent": true, "alpha": 0.35},
	1808:{"name": "ForceField",    "roughness": 0.30, "metallic": 0.0, "transparent": true, "alpha": 0.4},
}

const _DEFAULT := {"name": "Plastic", "roughness": 0.45, "metallic": 0.0}
const NAMED_MATERIAL_ENUMS := {
	"Plastic": 256,
	"SmoothPlastic": 272,
	"Wood": 512,
	"WoodPlanks": 528,
	"Concrete": 800,
	"Brick": 5,
	"Grass": 1280,
	"Sand": 1312,
	"Metal": 1024,
	"Glass": 1792,
	"Neon": 288,
	"Slate": 2,
	"Rock": 9,
	"Ice": 1536,
}
const NAMED_MATERIAL_PATTERNS := {
	"Wood": "wood",
	"WoodPlanks": "wood_planks",
	"Concrete": "stone",
	"Brick": "brick",
	"Grass": "foliage",
	"Sand": "sand",
	"Slate": "slate",
	"Rock": "stone",
	"Ice": "ice",
	"Metal": "metal",
}

var _cache: Dictionary = {}
var _surface_texture_cache: Dictionary = {}
var use_procedural_material_fallbacks: bool = false
var use_roblox_surface_patterns: bool = true


static func resolve_material_enum(value: Variant) -> Dictionary:
	var key: int = int(value) if value != null else 256
	if ROBLOX_MATERIALS.has(key):
		return ROBLOX_MATERIALS[key]
	# Fallback by name lookup: try common plastic-ish id range.
	return _DEFAULT


## Build (or fetch a cached) StandardMaterial3D for the given Roblox properties.
## `color_rgb` is [r,g,b] in 0..1, `material_id` is the Roblox Material enum.
func get_part_material(props: Dictionary) -> StandardMaterial3D:
	var pattern := ""
	if use_roblox_surface_patterns:
		pattern = surface_pattern_from_properties(props)
	if use_procedural_material_fallbacks:
		if pattern.is_empty():
			pattern = material_pattern_from_properties(props)
	return get_material(
		part_color_from_properties(props),
		_prop(props, "Material", 256),
		_prop(props, "Transparency", 0.0),
		_prop(props, "Reflectance", 0.0),
		pattern
	)


## Material used by Bobux Studio-created parts and by their runtime copy. The
## texture is deliberately neutral/grayscale so the selected Part color remains
## authoritative, matching Roblox's color-tinted material workflow.
func get_named_material(color: Color, material_name: String, transparency: float = 0.0) -> StandardMaterial3D:
	var normalized_name := material_name if NAMED_MATERIAL_ENUMS.has(material_name) else "Plastic"
	var pattern := str(NAMED_MATERIAL_PATTERNS.get(normalized_name, ""))
	var material := get_material(
		color,
		int(NAMED_MATERIAL_ENUMS.get(normalized_name, 256)),
		transparency,
		0.0,
		pattern
	).duplicate(true) as StandardMaterial3D
	if material != null:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.uv1_triplanar = not pattern.is_empty()
	return material


func get_material(color_rgb: Variant, material_id: Variant, transparency: Variant, reflectance: Variant, surface_pattern: String = "") -> StandardMaterial3D:
	var color := _color_from_array(color_rgb)
	var t := float(transparency) if transparency != null else 0.0
	var r := float(reflectance) if reflectance != null else 0.0
	var mdata := resolve_material_enum(material_id)

	var cache_key := "%d|%.4f,%.4f,%.4f|%.3f|%.3f|%s" % [int(material_id), color.r, color.g, color.b, t, r, surface_pattern]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.roughness = float(mdata.get("roughness", 0.5))
	mat.metallic = float(mdata.get("metallic", 0.0))
	mat.metallic_specular = 0.5 + r * 0.5

	if t > 0.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = clampf(1.0 - t, 0.0, 1.0)
	if bool(mdata.get("transparent", false)):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = minf(mat.albedo_color.a, float(mdata.get("alpha", 0.4)))

	var emission_val := float(mdata.get("emission", 0.0))
	if emission_val > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_val
	if not surface_pattern.is_empty():
		mat.albedo_texture = _get_surface_pattern_texture(surface_pattern)
		mat.uv1_triplanar = true
		mat.uv1_scale = _uv_scale_for_pattern(surface_pattern)
		if surface_pattern == "water":
			mat.roughness = 0.12
			mat.metallic_specular = 0.82
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = minf(mat.albedo_color.a, 0.78)
		elif surface_pattern == "foliage":
			mat.roughness = 1.0
		elif surface_pattern == "wood":
			mat.roughness = 0.92

	_cache[cache_key] = mat
	return mat


## Return one of Bobux Studio's coarse material categories ("Plastic", "Neon",
## "Glass", "Metal") so imported parts round-trip through `_build_block_instance`
## in the in-game editor. Falls back to "Plastic".
static func roblox_material_to_bobux(material_id: Variant) -> String:
	var mdata := resolve_material_enum(material_id)
	var name: String = mdata.get("name", "Plastic")
	match name:
		"Neon":
			return "Neon"
		"Glass", "Ice", "ForceField", "Glacier":
			return "Glass"
		"Metal", "DiamondPlate", "Foil":
			return "Metal"
		_:
			return "Plastic"


static func part_color_from_properties(props: Dictionary) -> Color:
	var color_value: Variant = _prop(props, "Color", null)
	if color_value != null:
		return _color_from_array(color_value)
	color_value = _prop(props, "Color3uint8", null)
	if color_value != null:
		return _color_from_array(color_value)
	color_value = _prop(props, "BrickColor", null)
	if color_value != null:
		return roblox_brick_color_to_color(color_value)
	return Color(0.639, 0.635, 0.647)


static func roblox_brick_color_to_color(brick_color_id: Variant) -> Color:
	var id := int(brick_color_id) if brick_color_id != null else 194
	var palette := {
		1: Color8(242, 243, 243),
		5: Color8(215, 197, 154),
		9: Color8(232, 186, 200),
		11: Color8(128, 187, 219),
		18: Color8(204, 142, 105),
		21: Color8(196, 40, 28),
		23: Color8(13, 105, 172),
		24: Color8(245, 205, 48),
		26: Color8(27, 42, 53),
		28: Color8(40, 127, 71),
		29: Color8(161, 196, 140),
		37: Color8(75, 151, 75),
		38: Color8(160, 95, 53),
		45: Color8(180, 210, 228),
		1001: Color8(248, 248, 248),
		1002: Color8(205, 205, 205),
		1003: Color8(17, 17, 17),
		1004: Color8(255, 0, 0),
		1005: Color8(255, 176, 0),
		1006: Color8(180, 128, 255),
		1007: Color8(163, 75, 75),
		1008: Color8(193, 190, 66),
		1009: Color8(255, 255, 0),
		1010: Color8(0, 0, 255),
		1011: Color8(0, 32, 96),
		1012: Color8(33, 84, 185),
		1013: Color8(4, 175, 236),
		1014: Color8(170, 85, 0),
		1015: Color8(170, 0, 170),
		1016: Color8(255, 102, 204),
		1017: Color8(255, 175, 0),
		1018: Color8(18, 238, 212),
		1019: Color8(0, 255, 255),
		1020: Color8(0, 255, 0),
		1021: Color8(58, 125, 21),
		1022: Color8(127, 142, 100),
		1023: Color8(140, 91, 159),
		1024: Color8(175, 221, 255),
	}
	return palette.get(id, Color(0.639, 0.635, 0.647))


static func _color_from_array(arr: Variant) -> Color:
	if arr == null:
		return Color(0.639, 0.635, 0.647)
	if arr is Color:
		return arr
	if arr is String:
		var clean := (arr as String).strip_edges()
		if clean.begins_with("#"):
			clean = clean.substr(1)
		if clean.length() == 6 or clean.length() == 8:
			return Color.html(clean)
	if arr is Array or arr is PackedFloat32Array:
		var a := arr as Array
		var r := float(a[0]) if a.size() > 0 else 0.639
		var g := float(a[1]) if a.size() > 1 else 0.635
		var b := float(a[2]) if a.size() > 2 else 0.647
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
		return Color(r, g, b)
	if arr is Dictionary:
		var dict := arr as Dictionary
		var r := float(dict.get("r", dict.get("R", dict.get("x", dict.get("X", 0.639)))))
		var g := float(dict.get("g", dict.get("G", dict.get("y", dict.get("Y", 0.635)))))
		var b := float(dict.get("b", dict.get("B", dict.get("z", dict.get("Z", 0.647)))))
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
		return Color(r, g, b)
	return Color(0.639, 0.635, 0.647)


func clear() -> void:
	_cache.clear()


static func surface_pattern_from_properties(props: Dictionary) -> String:
	var size := _vector3_prop(props, "Size", Vector3.ONE)
	var horizontal := maxf(absf(size.x), absf(size.z))
	var is_plate_like := absf(size.y) <= maxf(1.25, horizontal * 0.20)
	if not is_plate_like:
		return ""

	var has_studs := false
	var has_inlets := false
	for key in ["TopSurface", "BottomSurface"]:
		var surface := int(_prop(props, key, 0))
		match surface:
			3:
				has_studs = true
			4, 5:
				has_inlets = true
	if has_studs and has_inlets:
		return "universal"
	if has_studs:
		return "studs"
	if has_inlets:
		return "inlets"
	return ""


static func material_pattern_from_properties(props: Dictionary) -> String:
	var name := str(_prop(props, "Name", "")).to_lower()
	if name.find("water") >= 0 or name.find("river") >= 0 or name.find("ocean") >= 0 or name.find("sea") >= 0:
		return "water"
	if name.find("grass") >= 0 or name.find("leaf") >= 0 or name.find("leaves") >= 0 or name.find("foliage") >= 0:
		return "foliage"
	if name.find("wood") >= 0 or name.find("trunk") >= 0 or name.find("log") >= 0:
		return "wood"
	if name.find("dirt") >= 0 or name.find("mud") >= 0 or name.find("ground") >= 0:
		return "soil"
	var material_id := int(_prop(props, "Material", 256))
	var material_name := str(resolve_material_enum(material_id).get("name", "Plastic")).to_lower()
	match material_name:
		"grass", "leafygrass":
			return "foliage"
		"wood", "woodplanks":
			return "wood"
		"sand", "sandstone", "limestone":
			return "sand"
		"slate", "concrete", "granite", "rock", "cobblestone", "basalt", "pebble", "marble":
			return "stone"
		"brick":
			return "brick"
		"mud", "ground":
			return "soil"
		"ice", "glacier":
			return "ice"
		"fabric":
			return "fabric"
	return ""


static func _vector3_prop(props: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = _prop(props, key, null)
	if value is Vector3:
		return value
	if value is Array:
		var a := value as Array
		return Vector3(
			float(a[0]) if a.size() > 0 else fallback.x,
			float(a[1]) if a.size() > 1 else fallback.y,
			float(a[2]) if a.size() > 2 else fallback.z
		)
	if value is Dictionary:
		var d := value as Dictionary
		return Vector3(
			float(d.get("x", fallback.x)),
			float(d.get("y", fallback.y)),
			float(d.get("z", fallback.z))
		)
	return fallback


static func _prop(props: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if props.has(key):
		return props[key]
	var lower := key.to_lower()
	if props.has(lower):
		return props[lower]
	for candidate in props.keys():
		if str(candidate).to_lower() == lower:
			return props[candidate]
	return fallback


func _get_surface_pattern_texture(pattern: String) -> Texture2D:
	if _surface_texture_cache.has(pattern):
		return _surface_texture_cache[pattern]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.95, 0.95, 1.0))
	for y in range(64):
		for x in range(64):
			var local := Vector2(float(x % 8), float(y % 8))
			var center := Vector2(4.0, 4.0)
			var dist := local.distance_to(center)
			var pixel := Color(0.95, 0.95, 0.95, 1.0)
			var noise := _hash_noise(x, y)
			match pattern:
				"studs":
					if dist < 2.25:
						pixel = Color(1.0, 1.0, 1.0, 1.0)
					elif dist < 2.9:
						pixel = Color(0.82, 0.82, 0.82, 1.0)
				"inlets":
					if dist < 2.35:
						pixel = Color(0.78, 0.78, 0.78, 1.0)
					elif dist < 3.0:
						pixel = Color(0.99, 0.99, 0.99, 1.0)
				"universal":
					if dist < 2.1:
						pixel = Color(0.99, 0.99, 0.99, 1.0)
					elif dist < 3.0:
						pixel = Color(0.80, 0.80, 0.80, 1.0)
				"foliage":
					var vein := 0.13 if (x + y) % 17 < 2 else 0.0
					var leaf_value := 0.72 + noise * 0.22 - vein
					pixel = Color(leaf_value, leaf_value, leaf_value, 1.0)
				"wood":
					var stripe := 0.14 * sin(float(x) * 0.52 + sin(float(y) * 0.22) * 2.0)
					var wood_value := 0.72 + stripe + noise * 0.06
					pixel = Color(wood_value, wood_value, wood_value, 1.0)
				"wood_planks":
					var plank_mortar := x % 24 <= 1 or y % 16 <= 1
					var plank_stripe := 0.10 * sin(float(x) * 0.45 + float(int(y / 16)) * 1.7)
					var plank_value := 0.72 + plank_stripe + noise * 0.05
					pixel = Color(0.46, 0.46, 0.46, 1.0) if plank_mortar else Color(plank_value, plank_value, plank_value, 1.0)
				"stone":
					var crack := 0.22 if (x * 11 + y * 7) % 41 < 2 else 0.0
					var v := 0.58 + noise * 0.24 - crack
					pixel = Color(v, v, v, 1.0)
				"slate":
					var slate_line := 0.18 if (x + y * 2) % 23 < 2 else 0.0
					var slate_value := 0.62 + noise * 0.18 - slate_line
					pixel = Color(slate_value, slate_value, slate_value, 1.0)
				"brick":
					var mortar := x % 16 == 0 or y % 12 == 0 or ((int(y / 12) % 2) == 1 and (x + 8) % 16 == 0)
					var brick_value := 0.82 + noise * 0.10
					pixel = Color(brick_value, brick_value, brick_value, 1.0) if not mortar else Color(0.48, 0.48, 0.48, 1.0)
				"sand":
					var sand_value := 0.76 + noise * 0.18
					pixel = Color(sand_value, sand_value, sand_value, 1.0)
				"soil":
					pixel = Color(0.39 + noise * 0.11, 0.22 + noise * 0.07, 0.10 + noise * 0.04, 1.0)
				"water":
					var wave := 0.5 + 0.5 * sin(float(x) * 0.34 + sin(float(y) * 0.23) * 2.5)
					pixel = Color(0.18 + wave * 0.13, 0.62 + wave * 0.20, 0.92 + wave * 0.08, 0.78)
				"ice":
					var line := 0.12 if absf(sin(float(x + y) * 0.18)) > 0.92 else 0.0
					pixel = Color(0.72 + noise * 0.12, 0.90 + noise * 0.08, 1.0 - line, 0.86)
				"fabric":
					var weave := 0.12 if x % 6 == 0 or y % 6 == 0 else 0.0
					pixel = Color(0.72 - weave + noise * 0.05, 0.72 - weave + noise * 0.05, 0.74 - weave + noise * 0.05, 1.0)
				"metal":
					var brushed := 0.10 * sin(float(y) * 1.7) + noise * 0.05
					var metal_value := 0.74 + brushed
					pixel = Color(metal_value, metal_value, metal_value, 1.0)
			img.set_pixel(x, y, pixel)
	var tex := ImageTexture.create_from_image(img)
	_surface_texture_cache[pattern] = tex
	return tex


func _uv_scale_for_pattern(pattern: String) -> Vector3:
	match pattern:
		"studs", "inlets", "universal":
			return Vector3(0.78, 0.78, 0.78)
		"water":
			return Vector3(0.18, 0.18, 0.18)
		"wood", "wood_planks", "brick":
			return Vector3(0.32, 0.32, 0.32)
		_:
			return Vector3(0.24, 0.24, 0.24)


static func _hash_noise(x: int, y: int) -> float:
	var n := int(x * 374761393 + y * 668265263)
	n = (n ^ (n / 8192)) * 1274126177
	return float(abs(n ^ (n / 65536)) % 1024) / 1023.0
