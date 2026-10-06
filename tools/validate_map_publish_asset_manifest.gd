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
		"roblox_manifest": {"instances": [{"properties": {"SoundId": "http://novetus.mygamesonline.org/asset?id=12221990"}}, {"properties": {"SoundId": "rbxassetid://12222152"}}]},
		"blocks": [{"roblox_mesh_json_asset": "mesh.json"}],
		"runtime_objects": [{"file": "theme.ogg"}, {"file":"asset?id=27471524"}, {"file":"user://maps/nds/asset?id=27471524"}, {"file":"C:/old/map/asset?id=27471524"}, {"file":"./asset?id=27471524"}],
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
		and files.size() == 3
	)
	print("[validate_map_publish_asset_manifest] ok=%s files=%s" % [str(ok), str(files)])
	var legacy := "user://cache/users/probe/maps/Baseplate/novetus.mygamesonline.org/asset?id=27471524"
	var resolved := preload("res://addons/roblox_runtime/roblox_manifest_assets.gd").resolve({"instances":[{"properties":{"TextureID":legacy}}]}, folder)
	ok = ok and resolved.instances[0].properties.TextureID == "rbxassetid://27471524"
	var saved_path := "user://autosave/studio_latest/map_data.json"
	if FileAccess.file_exists(saved_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved_path))
		if saved is Dictionary:
			var actual: Array[String] = studio.call("_collect_publish_asset_file_names", saved, [], "")
			ok = ok and not actual.has("asset?id=27471524")
			print("[validate_map_publish_asset_manifest] actual_autosave_references=",actual.size()," contains_broken_asset=",actual.has("asset?id=27471524"))
	studio.free()
	quit(0 if ok else 1)


func _write_probe(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(PackedByteArray([1, 2, 3]))
		file.close()
