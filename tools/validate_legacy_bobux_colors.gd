extends SceneTree


func _initialize() -> void:
	var legacy_block := {
		"cr": 0.09,
		"cg": 0.35,
		"cb": 0.04,
		"ca": 1.0,
		"material": "Plastic",
	}
	var expected := Color(0.09, 0.35, 0.04, 1.0)
	var main_scene: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	var studio: Node = (load("res://scenes/place_editor/studio.tscn") as PackedScene).instantiate()
	var runtime_color: Color = main_scene.call("_color_from_block_data", legacy_block, Color.WHITE)
	var studio_color: Color = studio.call("_color_from_block_data", legacy_block, Color.WHITE)
	var runtime_material: StandardMaterial3D = main_scene.call("_create_material", runtime_color, "Plastic", 0.0)
	var datamodel_compatible_block := legacy_block.duplicate(true)
	datamodel_compatible_block["roblox_class"] = "Part"
	var runtime_preserves_bobux_material := not bool(main_scene.call("_should_apply_saved_roblox_block_material", datamodel_compatible_block))
	var studio_preserves_bobux_material := not bool(studio.call("_should_apply_saved_roblox_block_material", datamodel_compatible_block))
	var imported_metadata_without_color := legacy_block.duplicate(true)
	imported_metadata_without_color["roblox_ref"] = "legacy-colored-part"
	imported_metadata_without_color["roblox_properties"] = {
		"Material": 512,
		"Transparency": 0.0,
		"Name": "ColoredPart",
	}
	var material_cache := RbxlMaterialCache.new()
	var canonical_import_color: Color = main_scene.call("_color_from_block_data", imported_metadata_without_color, Color.WHITE)
	var canonical_import_material := material_cache.get_part_material_with_color(
		imported_metadata_without_color["roblox_properties"],
		canonical_import_color
	)
	var ok := (
		runtime_color.is_equal_approx(expected)
		and studio_color.is_equal_approx(expected)
		and runtime_material != null
		and runtime_material.albedo_color.is_equal_approx(expected)
		and runtime_preserves_bobux_material
		and studio_preserves_bobux_material
		and canonical_import_material != null
		and canonical_import_material.albedo_color.is_equal_approx(expected)
	)
	print("[validate_legacy_bobux_colors] ok=%s runtime=%s studio=%s material=%s imported_material=%s runtime_preserves=%s studio_preserves=%s" % [
		str(ok), str(runtime_color), str(studio_color), str(runtime_material.albedo_color if runtime_material != null else Color.BLACK),
		str(canonical_import_material.albedo_color if canonical_import_material != null else Color.BLACK),
		str(runtime_preserves_bobux_material), str(studio_preserves_bobux_material),
	])
	main_scene.free()
	studio.free()
	quit(0 if ok else 1)
