extends SceneTree


func _initialize() -> void:
	var studio_script := load("res://scripts/place_editor/studio.gd") as GDScript
	var studio: Control = studio_script.new()
	var folder := "user://validation/map_publish_assets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("surface")))
	_write_probe(folder.path_join("mesh.json"))
	_write_probe(folder.path_join("surface/albedo.png"))
	_write_probe(folder.path_join("theme.ogg"))
	_write_probe(folder.path_join("map_data.json"))
	_write_probe(folder.path_join("icon.png"))
	_write_probe(folder.path_join("ignored.txt"))
	var payload := {
		"blocks": [{"roblox_mesh_json_asset": "mesh.json"}],
		"runtime_objects": [{"file": "theme.ogg"}],
	}
	var files: Array[String] = studio.call(
		"_collect_publish_asset_file_names",
		payload,
		["theme.ogg"],
		folder
	)
	var ok := (
		files.has("mesh.json")
		and files.has("surface/albedo.png")
		and files.has("theme.ogg")
		and not files.has("map_data.json")
		and not files.has("icon.png")
		and not files.has("ignored.txt")
	)
	print("[validate_map_publish_asset_manifest] ok=%s files=%s" % [str(ok), str(files)])
	studio.free()
	quit(0 if ok else 1)


func _write_probe(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(PackedByteArray([1, 2, 3]))
		file.close()
