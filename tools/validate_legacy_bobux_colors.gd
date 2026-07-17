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
	var ok := (
		runtime_color.is_equal_approx(expected)
		and studio_color.is_equal_approx(expected)
		and runtime_material != null
		and runtime_material.albedo_color.is_equal_approx(expected)
	)
	print("[validate_legacy_bobux_colors] ok=%s runtime=%s studio=%s material=%s" % [
		str(ok), str(runtime_color), str(studio_color), str(runtime_material.albedo_color if runtime_material != null else Color.BLACK),
	])
	main_scene.free()
	studio.free()
	quit(0 if ok else 1)
