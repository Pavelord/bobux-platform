extends SceneTree

func _initialize() -> void:
	await process_frame
	var service := root.get_node("ToolboxAssetService")
	var library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
	if not await service.refresh_catalog():
		push_error("Server Toolbox index download failed: " + service.last_error)
		quit(1)
		return
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(library.SERVER_INDEX))
	var checked := {"model": 0, "sound": 0}
	for type_ in ["model", "sound"]:
		var entries: Array = parsed.assets.filter(func(x): return x.type == type_)
		for sample in range(50):
			var entry: Dictionary = entries[sample * (entries.size() - 1) / 49]
			if not await service.ensure_asset(entry.id):
				push_error(service.last_error)
				quit(1)
				return
			var downloaded := library.get_asset(entry.id)
			if not str(downloaded.file).begins_with("user://toolbox_cache/assets/"):
				push_error("Test must use the server cache, never res:// fallback")
				quit(1)
				return
			if type_ == "model":
				var model: Node3D = library.load_model(downloaded.file)
				if model == null or library.bounds(model).size.length() <= 0:
					push_error("Server model failed: " + entry.id)
					quit(1)
					return
				model.free()
			else:
				var sound: AudioStream = library.load_sound(downloaded.file)
				if sound == null or sound.get_length() <= 0:
					push_error("Server sound failed: " + entry.id)
					quit(1)
					return
			checked[type_] += 1
		print("[toolbox_server] validated=" + JSON.stringify(checked))
	var icon_path: String = await service.ensure_thumbnail(parsed.assets[0])
	var ok := not icon_path.is_empty() and Image.load_from_file(icon_path) != null
	print("[toolbox_server] catalog=%d models=%d sounds=%d thumbnail=%s" % [parsed.assets.size(), checked.model, checked.sound, ok])
	quit(0 if ok else 1)
