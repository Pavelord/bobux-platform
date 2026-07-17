extends SceneTree

const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

class FakeStudio:
	extends Node3D
	var placement_parent: Node3D
	var sun_light: DirectionalLight3D
	var time_slider: HSlider
	func _init() -> void:
		placement_parent = Node3D.new()
		placement_parent.name = "Blocks"
		add_child(placement_parent)
		var environment := WorldEnvironment.new()
		environment.name = "WorldEnvironment"
		environment.environment = Environment.new()
		add_child(environment)
		sun_light = DirectionalLight3D.new()
		add_child(sun_light)
		time_slider = HSlider.new()
		add_child(time_slider)
	func _build_imported_block_instance(shape_name: String, color: Color, material_type: String,
			transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.name = block_name
		node.mesh = BoxMesh.new()
		node.add_to_group("studio_parts")
		node.set_meta("shape_type", shape_name)
		node.set_meta("material_type", material_type)
		node.set_meta("transparency", transparency)
		node.set_meta("can_collide", can_collide)
		return node
	func _build_block_instance(shape_name: String, color: Color, material_type: String,
			transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		return _build_imported_block_instance(shape_name, color, material_type, transparency, can_collide, block_name)
	func _update_block_collision(_block: Node3D) -> void:
		pass
	func _register_imported_sound_asset(_sound_data: Dictionary) -> void:
		pass

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	if not args.is_empty():
		source_path = str(args[0])
	var studio := FakeStudio.new()
	get_root().add_child(studio)
	var importer := RuntimeImporter.new()
	importer.max_runtime_preview_nodes = 0
	importer.max_texture_preview_nodes = 0
	var report := importer.import_file(source_path, studio)
	var manifest: Dictionary = studio.get_meta("roblox_place_manifest", {})
	var scripts: Array = manifest.get("scripts", []) if manifest.get("scripts", []) is Array else []
	var script_engine := get_root().get_node_or_null("LuaScriptEngine")
	if script_engine == null:
		push_error("LuaScriptEngine autoload is missing")
		quit(1)
		return
	var passed := 0
	var failed := 0
	var examples: Array[String] = []
	var failure_groups: Dictionary = {}
	for script_variant in scripts:
		if not (script_variant is Dictionary):
			continue
		var script := script_variant as Dictionary
		var result: Dictionary = script_engine.validate_script_source(str(script.get("source", "")))
		if bool(result.get("ok", false)):
			passed += 1
		else:
			failed += 1
			var error := str(result.get("error", "unknown")).replace("\n", " ")
			var key := error.get_slice(":", 0).strip_edges()
			failure_groups[key] = int(failure_groups.get(key, 0)) + 1
			if examples.size() < 12:
				examples.append("%s[%s]: %s" % [script.get("name", "Script"), script.get("class", "Script"), error])
	print("[validate_rbxl_script_compilation] import_ok=%s scripts=%d passed=%d failed=%d rate=%.2f groups=%s" % [
		str(bool(report.get("ok", false))), scripts.size(), passed, failed,
		(float(passed) / maxf(float(scripts.size()), 1.0)) * 100.0, str(failure_groups)
	])
	for example in examples:
		print("[script_compile_example] %s" % example)
	quit(0 if bool(report.get("ok", false)) else 1)
