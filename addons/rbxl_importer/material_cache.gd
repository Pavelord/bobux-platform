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
	256: {"name": "Plastic", "roughness": 0.45, "metallic": 0.0},
	272: {"name": "SmoothPlastic", "roughness": 0.1, "metallic": 0.0},
	288: {"name": "Neon", "roughness": 0.2, "metallic": 0.0, "emission": 2.0},
	512: {"name": "Wood", "roughness": 0.85, "metallic": 0.0},
	528: {"name": "WoodPlanks", "roughness": 0.85, "metallic": 0.0},
	784: {"name": "Marble", "roughness": 0.2, "metallic": 0.0},
	788: {"name": "Basalt", "roughness": 0.85, "metallic": 0.0},
	800: {"name": "Slate", "roughness": 0.85, "metallic": 0.0},
	804: {"name": "CrackedLava", "roughness": 0.85, "metallic": 0.0},
	816: {"name": "Concrete", "roughness": 0.85, "metallic": 0.0},
	820: {"name": "Limestone", "roughness": 0.85, "metallic": 0.0},
	832: {"name": "Granite", "roughness": 0.85, "metallic": 0.0},
	836: {"name": "Pavement", "roughness": 0.85, "metallic": 0.0},
	848: {"name": "Brick", "roughness": 0.85, "metallic": 0.0},
	864: {"name": "Pebble", "roughness": 0.85, "metallic": 0.0},
	880: {"name": "Cobblestone", "roughness": 0.85, "metallic": 0.0},
	896: {"name": "Rock", "roughness": 0.85, "metallic": 0.0},
	912: {"name": "Sandstone", "roughness": 0.85, "metallic": 0.0},
	1040: {"name": "CorrodedMetal", "roughness": 0.85, "metallic": 0.55},
	1056: {"name": "DiamondPlate", "roughness": 0.3, "metallic": 0.9},
	1072: {"name": "Foil", "roughness": 0.12, "metallic": 1.0},
	1088: {"name": "Metal", "roughness": 0.22, "metallic": 0.85},
	1280: {"name": "Grass", "roughness": 0.85, "metallic": 0.0},
	1284: {"name": "LeafyGrass", "roughness": 0.85, "metallic": 0.0},
	1296: {"name": "Sand", "roughness": 0.85, "metallic": 0.0},
	1312: {"name": "Fabric", "roughness": 0.85, "metallic": 0.0},
	1328: {"name": "Snow", "roughness": 0.85, "metallic": 0.0},
	1344: {"name": "Mud", "roughness": 0.85, "metallic": 0.0},
	1360: {"name": "Ground", "roughness": 0.85, "metallic": 0.0},
	1376: {"name": "Asphalt", "roughness": 0.85, "metallic": 0.0},
	1392: {"name": "Salt", "roughness": 0.85, "metallic": 0.0},
	1536: {"name": "Ice", "roughness": 0.08, "metallic": 0.0},
	1552: {"name": "Glacier", "roughness": 0.12, "metallic": 0.0},
	1568: {"name": "Glass", "roughness": 0.05, "metallic": 0.0, "transparent": true, "alpha": 0.35},
	1584: {"name": "ForceField", "roughness": 0.85, "metallic": 0.0},
	1792: {"name": "Air", "roughness": 0.85, "metallic": 0.0},
	2048: {"name": "Water", "roughness": 0.12, "metallic": 0.0},
	2304: {"name": "Cardboard", "roughness": 0.85, "metallic": 0.0},
	2305: {"name": "Carpet", "roughness": 0.85, "metallic": 0.0},
	2306: {"name": "CeramicTiles", "roughness": 0.85, "metallic": 0.0},
	2307: {"name": "ClayRoofTiles", "roughness": 0.85, "metallic": 0.0},
	2308: {"name": "RoofShingles", "roughness": 0.85, "metallic": 0.0},
	2309: {"name": "Leather", "roughness": 0.85, "metallic": 0.0},
	2310: {"name": "Plaster", "roughness": 0.85, "metallic": 0.0},
	2311: {"name": "Rubber", "roughness": 0.85, "metallic": 0.0},
}

const _DEFAULT := {"name": "Plastic", "roughness": 0.45, "metallic": 0.0}
const MATERIAL_TEXTURE_ALIASES := {
	"Cardboard": "WoodPlanks",
	"Carpet": "Fabric",
	"Leather": "Fabric",
	"Plaster": "Concrete",
}
const NAMED_MATERIAL_ENUMS := {
	"Plastic": 256,
	"SmoothPlastic": 272,
	"Neon": 288,
	"Wood": 512,
	"WoodPlanks": 528,
	"Marble": 784,
	"Basalt": 788,
	"Slate": 800,
	"CrackedLava": 804,
	"Concrete": 816,
	"Limestone": 820,
	"Granite": 832,
	"Pavement": 836,
	"Brick": 848,
	"Pebble": 864,
	"Cobblestone": 880,
	"Rock": 896,
	"Sandstone": 912,
	"CorrodedMetal": 1040,
	"DiamondPlate": 1056,
	"Foil": 1072,
	"Metal": 1088,
	"Grass": 1280,
	"LeafyGrass": 1284,
	"Sand": 1296,
	"Fabric": 1312,
	"Snow": 1328,
	"Mud": 1344,
	"Ground": 1360,
	"Asphalt": 1376,
	"Salt": 1392,
	"Ice": 1536,
	"Glacier": 1552,
	"Glass": 1568,
	"ForceField": 1584,
	"Water": 2048,
	"Cardboard": 2304,
	"Carpet": 2305,
	"CeramicTiles": 2306,
	"ClayRoofTiles": 2307,
	"RoofShingles": 2308,
	"Leather": 2309,
	"Plaster": 2310,
	"Rubber": 2311,
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

func _apply_texture_pack(material: StandardMaterial3D, material_name: String) -> bool:
	if _is_renderless_server(): return false
	if material_name in ["Plastic", "SmoothPlastic", "Neon", "ForceField", "Air", "Water"]:
		return false
	var texture_name: String = str(MATERIAL_TEXTURE_ALIASES.get(material_name, material_name))
	var folder := ""
	var color_texture: Texture2D
	# Some pre-2022 folders contain 4x4 white placeholders for materials that
	# did not have a real texture. Keep looking so Modern/Ice and Modern/Foil
	# can provide their actual appearance instead of silently rendering white.
	for era in ["PartsPre2022", "Modern"]:
		var candidate_folder := "res://Roblox-Materials/%s/%s/" % [era, texture_name]
		var candidate_path := candidate_folder + "color.png"
		if not ResourceLoader.exists(candidate_path):
			continue
		var candidate_texture := load(candidate_path) as Texture2D
		if candidate_texture == null or candidate_texture.get_width() <= 4 or candidate_texture.get_height() <= 4:
			continue
		folder = candidate_folder
		color_texture = candidate_texture
		break
	if color_texture == null:
		return false
	material.albedo_texture = color_texture
	if ResourceLoader.exists(folder + "normal.png"):
		material.normal_enabled = true
		material.normal_texture = load(folder + "normal.png")
	if ResourceLoader.exists(folder + "roughness.png"):
		material.roughness = 1.0
		material.roughness_texture = load(folder + "roughness.png")
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ResourceLoader.exists(folder + "metalness.png"):
		material.metallic = 1.0
		material.metallic_texture = load(folder + "metalness.png")
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 8.0
	material.set_meta("bobux_texture_tile_studs", 8.0)
	return true

## Local triplanar coordinates follow rotation; physical scale controls repeats.
## A resized part gets its own material instance without duplicating textures.
static func sync_texture_scale(part: MeshInstance3D, stud_scale: float = -1.0) -> void:
	if part == null or part.mesh == null:
		return
	if stud_scale <= 0.0:
		stud_scale = 1.0
		var cursor: Node = part
		while cursor != null:
			if cursor.has_meta("roblox_stud_scale"):
				stud_scale = float(cursor.get_meta("roblox_stud_scale"))
				break
			cursor = cursor.get_parent()
	for index in part.mesh.get_surface_count():
		var original := part.get_active_material(index) as StandardMaterial3D
		if original == null or not original.uv1_triplanar or not original.has_meta("bobux_texture_tile_studs"):
			continue
		var basis := part.global_basis if part.is_inside_tree() else part.basis
		var scale_ := Vector3(basis.x.length(), basis.y.length(), basis.z.length())
		var repeats := scale_ / (float(original.get_meta("bobux_texture_tile_studs")) * maxf(stud_scale, 0.001))
		if original.uv1_scale.is_equal_approx(repeats):
			continue
		var material := original.duplicate(false) as StandardMaterial3D
		material.uv1_scale = repeats
		if part.material_override != null:
			part.material_override = material
			return
		part.set_surface_override_material(index, material)


static func resolve_material_enum(value: Variant) -> Dictionary:
	if value is Dictionary:
		value = value.get("Value", value.get("value", value.get("Name", value.get("name", 256))))
	var key := 256
	if value is int or value is float:
		key = int(value)
	elif value is String:
		key = int(value) if value.is_valid_int() else int(NAMED_MATERIAL_ENUMS.get(value.get_slice(".", value.count(".")), 256))
	if ROBLOX_MATERIALS.has(key):
		return ROBLOX_MATERIALS[key]
	# Fallback by name lookup: try common plastic-ish id range.
	return _DEFAULT


static func surface_type_value(value: Variant) -> int:
	if value is Dictionary:
		value = value.get("Value", value.get("value", value.get("Name", value.get("name", 0))))
	if value is int or value is float:
		return int(value)
	if value is String:
		if value.is_valid_int(): return int(value)
		return int({"Smooth": 0, "Glue": 1, "Weld": 2, "Studs": 3, "Inlet": 4,
			"Universal": 5, "Hinge": 6, "Motor": 7, "SteppingMotor": 8,
			"SmoothNoOutlines": 10}.get(value.get_slice(".", value.count(".")), 0))
	return 0


## Build (or fetch a cached) StandardMaterial3D for the given Roblox properties.
## `color_rgb` is [r,g,b] in 0..1, `material_id` is the Roblox Material enum.
static func _is_renderless_server() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var state := tree.root.get_node_or_null("GameState") if tree != null else null
	return state != null and bool(state.get("dedicated_server_mode"))

func get_part_material(props: Dictionary) -> StandardMaterial3D:
	# SurfaceType belongs to an individual face, independently of Material.
	var pattern := material_pattern_from_properties(props) if use_procedural_material_fallbacks else ""
	var base := get_material(part_color_from_properties(props), _prop(props, "Material", 256),
		_prop(props, "Transparency", 0.0), _prop(props, "Reflectance", 0.0), pattern)
	if not use_roblox_surface_patterns or _is_renderless_server():
		return base
	var faces := Vector4(surface_type_value(_prop(props, "TopSurface", 0)), surface_type_value(_prop(props, "BottomSurface", 0)),
		surface_type_value(_prop(props, "RightSurface", 0)), surface_type_value(_prop(props, "LeftSurface", 0)))
	var ends := Vector2(surface_type_value(_prop(props, "FrontSurface", 0)), surface_type_value(_prop(props, "BackSurface", 0)))
	if faces == Vector4.ZERO and ends == Vector2.ZERO:
		return base
	var scale_ := maxf(float(_prop(props, "BobuxStudScale", 0.5)), 0.001)
	var key := "faces|%s|%s|%s|%s" % [base.get_instance_id(), faces, ends, scale_]
	if _cache.has(key): return _cache[key]
	var result := base.duplicate() as StandardMaterial3D
	var overlay := ShaderMaterial.new()
	overlay.shader = preload("res://addons/rbxl_importer/brick_surfaces.gdshader")
	overlay.set_shader_parameter("surface_atlas", preload("res://Roblox-Materials/ClassicSurfaceTypes/studs_atlas_preview.png"))
	overlay.set_shader_parameter("part_color", base.albedo_color)
	overlay.set_shader_parameter("face_types", faces)
	overlay.set_shader_parameter("end_types", ends)
	overlay.set_shader_parameter("stud_scale", scale_)
	overlay.set_shader_parameter("opacity", base.albedo_color.a)
	result.next_pass = overlay
	_cache[key] = result
	return result


## Build a Roblox material while preserving the canonical color serialized by
## Bobux. Older maps can contain Material/Name metadata without a Roblox Color;
## resolving that property bag directly would silently replace the saved color
## with Roblox's default medium gray.
func get_part_material_with_color(props: Dictionary, canonical_color: Color) -> StandardMaterial3D:
	var resolved_props := props.duplicate(true)
	resolved_props["Color"] = [canonical_color.r, canonical_color.g, canonical_color.b]
	return get_part_material(resolved_props)


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
		material.uv1_triplanar = material.albedo_texture != null
	return material


func get_material(color_rgb: Variant, material_id: Variant, transparency: Variant, reflectance: Variant, surface_pattern: String = "") -> StandardMaterial3D:
	var color := _color_from_array(color_rgb)
	var t := float(transparency) if transparency != null else 0.0
	var r := float(reflectance) if reflectance != null else 0.0
	var mdata := resolve_material_enum(material_id)

	var cache_key := "%d|%.4f,%.4f,%.4f|%.3f|%.3f|%s" % [str(mdata.name).hash(), color.r, color.g, color.b, t, r, surface_pattern]
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
	if not _apply_texture_pack(mat, str(mdata.name)) and not surface_pattern.is_empty():
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
	return name if NAMED_MATERIAL_ENUMS.has(name) else "Plastic"


static func part_color_from_properties(props: Dictionary) -> Color:
	var color_value: Variant = _prop(props, "Color", null)
	if color_value != null:
		return _color_from_array(color_value)
	color_value = _prop(props, "Color3", null)
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
	return preload("res://addons/roblox_runtime/brick_color_palette.gd").resolve(brick_color_id)


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


## glTF permits COLOR_0 without a declared material. Godot preserves the
## vertex stream, but the default material does not display it. Enable that
## stream recursively while preserving imported textures and PBR values.
static func enable_embedded_vertex_colors(root: Node) -> int:
	if root == null:
		return 0
	var changed := 0
	if root is MeshInstance3D:
		changed += _enable_mesh_instance_vertex_colors(root as MeshInstance3D)
	for child in root.get_children():
		changed += enable_embedded_vertex_colors(child)
	return changed


static func _enable_mesh_instance_vertex_colors(mesh_instance: MeshInstance3D) -> int:
	if mesh_instance == null or not (mesh_instance.mesh is ArrayMesh):
		return 0
	var array_mesh := mesh_instance.mesh as ArrayMesh
	var changed := 0
	for surface_index in range(array_mesh.get_surface_count()):
		var format := int(array_mesh.surface_get_format(surface_index))
		if (format & int(Mesh.ARRAY_FORMAT_COLOR)) == 0:
			continue
		# Read the override and embedded surface material directly. Calling
		# get_active_material() on a COLOR_0-only glTF surface makes the headless
		# renderer query a null RenderingServer material and logs a false error.
		var active: Material = mesh_instance.get_surface_override_material(surface_index)
		if active == null:
			active = array_mesh.surface_get_material(surface_index)
		var material: StandardMaterial3D = null
		if active is StandardMaterial3D:
			material = (active as StandardMaterial3D).duplicate(true) as StandardMaterial3D
		elif active == null:
			material = StandardMaterial3D.new()
		else:
			# A ShaderMaterial owns its vertex-input contract.
			continue
		if material == null or material.vertex_color_use_as_albedo:
			continue
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		mesh_instance.set_surface_override_material(surface_index, material)
		changed += 1
	return changed


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
