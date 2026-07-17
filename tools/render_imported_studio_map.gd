extends SceneTree

const RbxlRuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path := "C:\\Users\\Pavel\\Downloads\\Ronaldinho2k20 - Escape Memes Obby.rbxl"
	var output_path := "C:\\robloxclone\\tmp_imported_studio_map.png"
	if args.size() >= 1:
		source_path = str(args[0])
	if args.size() >= 2:
		output_path = str(args[1])
	get_root().size = Vector2i(1600, 900)
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var game_state := get_root().get_node_or_null("GameState")
	if game_state != null:
		game_state.set("selected_map_folder", "")
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	if source_path.get_extension().to_lower() == "json":
		await _import_preconverted_json(studio, source_path)
	else:
		await studio._on_rbxl_file_selected(source_path)
	await process_frame
	if studio.has_method("_clear_roblox_gui_preview"):
		studio._clear_roblox_gui_preview()
	_frame_imported_parts(studio)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var error := image.save_png(output_path)
	print("[render_imported_studio_map] path=%s parts=%d error=%d" % [
		output_path, studio._get_editor_parts().size(), error
	])
	studio.free()
	quit(0 if error == OK else 1)


func _import_preconverted_json(studio: Node, source_path: String) -> void:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		push_error("Could not open converted RBXL JSON: %s" % source_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Converted RBXL JSON is malformed: %s" % source_path)
		return
	studio._clear_map_for_rbxl_import()
	var importer := RbxlRuntimeImporter.new()
	importer.scale_factor = 0.5
	importer.import_lighting = true
	importer.replace_existing = false
	importer.parts_per_frame = 192
	importer.meta_per_frame = 384
	var report: Dictionary = await importer.import_json_async(
		parsed as Dictionary,
		studio.get("placement_parent") as Node3D,
		studio
	)
	if not bool(report.get("ok", false)):
		push_error("Converted RBXL import failed: %s" % str(report.get("error", "unknown")))
		return
	studio.set("current_roblox_environment_settings", studio._collect_roblox_environment_settings())
	studio.set("current_roblox_place_manifest", studio._collect_roblox_place_manifest_from_import())
	studio._apply_imported_roblox_environment_preview()

func _frame_imported_parts(studio: Node) -> void:
	var parts: Array = studio._get_editor_parts()
	if parts.is_empty():
		return
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	for part_variant in parts:
		if not (part_variant is Node3D):
			continue
		var part := part_variant as Node3D
		var position := part.global_position
		var scale := part.global_transform.basis.get_scale().abs()
		if not position.is_finite() or not scale.is_finite() or maxf(scale.x, maxf(scale.y, scale.z)) > 5000.0:
			continue
		xs.append(position.x)
		ys.append(position.y)
		zs.append(position.z)
	if xs.is_empty():
		return
	xs.sort()
	ys.sort()
	zs.sort()
	var low_index := clampi(int(floor(float(xs.size() - 1) * 0.03)), 0, xs.size() - 1)
	var high_index := clampi(int(ceil(float(xs.size() - 1) * 0.97)), 0, xs.size() - 1)
	var minimum := Vector3(xs[low_index], ys[low_index], zs[low_index])
	var maximum := Vector3(xs[high_index], ys[high_index], zs[high_index])
	var center := (minimum + maximum) * 0.5
	var span := maximum - minimum
	var distance := maxf(span.length() * 0.72, 24.0)
	var camera := studio.get("camera") as Camera3D
	if camera != null:
		camera.global_position = center + Vector3(distance * 0.58, distance * 0.48, distance * 0.72)
		camera.look_at(center, Vector3.UP)
