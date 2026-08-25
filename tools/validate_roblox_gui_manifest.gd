extends SceneTree

const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
const RobloxGuiRuntime := preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")

class FakeStudio:
	extends Node3D
	var placement_parent: Node3D
	var sun_light: DirectionalLight3D
	var time_slider: HSlider
	func _init() -> void:
		placement_parent = Node3D.new()
		placement_parent.name = "Blocks"
		add_child(placement_parent)
		var env := WorldEnvironment.new()
		env.name = "WorldEnvironment"
		env.environment = Environment.new()
		add_child(env)
		sun_light = DirectionalLight3D.new()
		add_child(sun_light)
		time_slider = HSlider.new()
		add_child(time_slider)
	func _build_imported_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = block_name
		mesh_inst.mesh = BoxMesh.new()
		mesh_inst.set_meta("shape_type", shape_name)
		mesh_inst.set_meta("block_name", block_name)
		mesh_inst.set_meta("material_type", material_type)
		mesh_inst.set_meta("transparency", transparency)
		mesh_inst.set_meta("can_collide", can_collide)
		mesh_inst.add_to_group("studio_parts")
		return mesh_inst
	func _build_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
		return _build_imported_block_instance(shape_name, color, material_type, transparency, can_collide, block_name)
	func _update_block_collision(_block: Node3D) -> void:
		pass
	func _register_imported_sound_asset(_sound_data: Dictionary) -> void:
		pass

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Build a Boat FULLY WORKING (Subscribe to FrenchBread).rbxl"
	if not args.is_empty():
		source_path = str(args[0])
	var studio := FakeStudio.new()
	get_root().add_child(studio)
	var importer := RuntimeImporter.new()
	importer.max_runtime_preview_nodes = 0
	importer.max_texture_preview_nodes = 0
	var report: Dictionary = importer.import_file(source_path, studio)
	var manifest: Dictionary = studio.get_meta("roblox_place_manifest", {}) if studio.get_meta("roblox_place_manifest", {}) is Dictionary else {}
	var root_control := Control.new()
	root_control.name = "GuiRoot"
	get_root().add_child(root_control)
	var gui_root := RobloxGuiRuntime.apply_manifest(root_control, manifest, {
		"root_name": "GuiValidation",
		"draw_gui": true,
		"draw_tools": false,
		"editor_preview": true,
		"ignore_mouse": true
	})
	var built_gui := int(gui_root.get_meta("built_gui_controls", 0)) if gui_root != null else 0
	var visual_stats := _collect_gui_visual_stats(gui_root)
	var starter_gui_refs := _count_starter_gui_refs(manifest)
	if built_gui <= 0 and starter_gui_refs > 0:
		var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
		var gui: Array = manifest.get("gui", []) if manifest.get("gui", []) is Array else []
		print("[validate_roblox_gui_manifest] service_samples=%s" % JSON.stringify(services.slice(0, mini(services.size(), 5))))
		print("[validate_roblox_gui_manifest] gui_samples=%s" % JSON.stringify(gui.slice(0, mini(gui.size(), 5))))
	var ok := bool(report.get("ok", false)) and (starter_gui_refs == 0 or built_gui > 0)
	print("[validate_roblox_gui_manifest] ok=%s gui_refs=%d starter_gui_refs=%d built_gui=%d images=%d missing_images=%d suppressed=%d report_errors=%d" % [
		str(ok),
		int(report.get("gui_refs", 0)),
		starter_gui_refs,
		built_gui,
		int(visual_stats.get("images", 0)),
		int(visual_stats.get("missing_images", 0)),
		int(visual_stats.get("suppressed", 0)),
		int(report.get("errors", 0))
	])
	quit(0 if ok else 1)

func _collect_gui_visual_stats(root_node: Node) -> Dictionary:
	var stats := {"images": 0, "missing_images": 0, "suppressed": 0}
	if root_node == null:
		return stats
	_collect_gui_visual_stats_recursive(root_node, stats)
	return stats

func _collect_gui_visual_stats_recursive(node: Node, stats: Dictionary) -> void:
	if bool(node.get_meta("bobux_image_loaded", false)):
		stats["images"] = int(stats.get("images", 0)) + 1
	if bool(node.get_meta("bobux_image_missing", false)):
		stats["missing_images"] = int(stats.get("missing_images", 0)) + 1
	if bool(node.get_meta("bobux_suppressed_fullscreen_blocker", false)):
		stats["suppressed"] = int(stats.get("suppressed", 0)) + 1
	for child in node.get_children():
		_collect_gui_visual_stats_recursive(child, stats)

func _count_starter_gui_refs(manifest: Dictionary) -> int:
	var parent_by_ref := {}
	var edges: Array = manifest.get("hierarchy", []) if manifest.get("hierarchy", []) is Array else []
	for edge_variant in edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var child_ref := _normalize_ref(edge.get("child", ""))
		if child_ref.is_empty():
			continue
		parent_by_ref[child_ref] = _normalize_ref(edge.get("parent", ""))
	var service_by_ref := {}
	var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	for service_variant in services:
		if not (service_variant is Dictionary):
			continue
		var service: Dictionary = service_variant
		var ref := _normalize_ref(service.get("ref", ""))
		if ref.is_empty():
			continue
		service_by_ref[ref] = str(service.get("name", service.get("class", "")))
	var total := 0
	var gui: Array = manifest.get("gui", []) if manifest.get("gui", []) is Array else []
	for gui_variant in gui:
		if not (gui_variant is Dictionary):
			continue
		var gui_entry: Dictionary = gui_variant
		if _belongs_to_service(_normalize_ref(gui_entry.get("ref", "")), parent_by_ref, service_by_ref, "StarterGui"):
			total += 1
	return total

func _belongs_to_service(ref: String, parent_by_ref: Dictionary, service_by_ref: Dictionary, service_name: String) -> bool:
	var cursor := _normalize_ref(ref)
	var guard := 0
	while not cursor.is_empty() and guard < 512:
		if service_by_ref.has(cursor):
			return str(service_by_ref[cursor]) == service_name
		cursor = _normalize_ref(parent_by_ref.get(cursor, ""))
		guard += 1
	return false

func _normalize_ref(raw: Variant) -> String:
	var text := str(raw).strip_edges()
	if text.ends_with(".0") and text.is_valid_float():
		text = str(int(round(text.to_float())))
	return text
