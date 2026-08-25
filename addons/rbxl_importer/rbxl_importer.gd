@tool
class_name RbxlEditorImportPlugin
extends EditorImportPlugin

## EditorImportPlugin: drop a `.rbxl` / `.rbxlx` file into Godot's FileSystem
## dock → produces a `.tscn` PackedScene. The heavy lifting (decompression,
## interleaving, zigzag) happens in `rbxl_converter.py`, which is invoked as a
## subprocess. The JSON intermediate is then turned into a node tree by
## `instance_builder.gd`.
##
## A parallel runtime path (`rbxl_runtime_importer.gd`) is used by the in-game
## Place Editor, which imports directly into the live scene tree without going
## through the editor importer.

const _Converter := preload("res://addons/rbxl_importer/rbxl_converter_bridge.gd")
const _Builder := preload("res://addons/rbxl_importer/instance_builder.gd")

const _PythonCandidates := [
	"python",
	"python3",
	"py",
]


func _get_importer_name() -> String:
	return "bobux.rbxl_importer"


func _get_visible_name() -> String:
	return "Roblox Place File (.rbxl / .rbxlx)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["rbxl", "rbxlx"])


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_save_extension() -> String:
	return "tscn"


func _get_resource_type() -> String:
	return "PackedScene"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return "Default"


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [
		{"name": "import_scripts", "default_value": true,
		 "property_hint": PROPERTY_HINT_NONE,
		 "hint_string": "Convert Roblox Script/LocalScript/ModuleScript to GDScript stubs"},
		{"name": "import_terrain", "default_value": true,
		 "property_hint": PROPERTY_HINT_NONE,
		 "hint_string": "Build Terrain voxels (placeholder meshes when detailed voxels are unavailable)"},
		{"name": "import_lighting", "default_value": true,
		 "property_hint": PROPERTY_HINT_NONE,
		 "hint_string": "Build Lighting + Sky + Atmosphere"},
		{"name": "scale_factor", "default_value": 0.5,
		 "property_hint": PROPERTY_HINT_RANGE,
		 "hint_string": "0.01,4.0,0.001"},
		{"name": "merge_parts", "default_value": false,
		 "property_hint": PROPERTY_HINT_NONE,
		 "hint_string": "Place every part under a single Workspace node (true) or preserve full Roblox hierarchy (false)"},
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, options: Dictionary,
		platform_variants: Array, gen_files: Array) -> Error:
	var cache_dir := ProjectSettings.globalize_path("user://rbxl_import_cache")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var json_path := _unique_intermediate_json_path(cache_dir, source_file)
	var converter := _Converter.new()
	var py_error := converter.convert_file(source_file, json_path)
	if py_error != OK:
		push_error("[RBXL Importer] Converter failed: %s" % converter.last_error)
		return py_error

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("[RBXL Importer] Could not open intermediate JSON: %s" % json_path)
		return ERR_FILE_NOT_FOUND
	var json_text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(json_path)

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[RBXL Importer] Intermediate JSON is invalid.")
		return ERR_PARSE_ERROR
	var json: Dictionary = parsed

	var builder := _Builder.new()
	var root: Node = builder.build(json, options)
	if root == null:
		push_error("[RBXL Importer] Scene builder returned null for %s" % source_file)
		return ERR_PARSE_ERROR

	var packed := PackedScene.new()
	var pack_error: int = packed.pack(root)
	if pack_error != OK:
		push_error("[RBXL Importer] Failed to pack scene: %d" % pack_error)
		return pack_error

	var save_err: int = ResourceSaver.save(packed, save_path + "." + _get_save_extension())
	if save_err != OK:
		push_error("[RBXL Importer] ResourceSaver failed: %d" % save_err)
		return save_err

	print("[RBXL Importer] Imported %s → %s.tscn (%d instances)" %
		[source_file, save_path, builder.imported_instance_count])
	return OK


func _unique_intermediate_json_path(cache_dir: String, source_path: String) -> String:
	var base_name := source_path.get_file().get_basename().validate_filename()
	if base_name.is_empty():
		base_name = "place"
	var token := "%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), get_instance_id()]
	return cache_dir.path_join("%s.%s.intermediate.json" % [base_name, token])
