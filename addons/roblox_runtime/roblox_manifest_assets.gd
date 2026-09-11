extends RefCounted

static func resolve(manifest: Dictionary, folder: String) -> Dictionary:
	var result := manifest.duplicate(false)
	for section in ["instances", "tools", "gui", "storage_libraries"]:
		var entries: Array = manifest.get(section, [])
		var resolved: Array = []
		for entry in entries:
			if not entry is Dictionary: continue
			var copy: Dictionary = entry.duplicate(false)
			var props: Dictionary = entry.get("properties", {}).duplicate(true)
			for key in ["BobuxMeshResource", "SoundId"]:
				var path := str(props.get(key, ""))
				if not path.is_empty() and not path.contains(":") and not path.begins_with("/") and not ".." in path.replace("\\", "/").split("/"):
					props[key] = folder.path_join(path)
			copy["properties"] = props
			resolved.append(copy)
		result[section] = resolved
	return result
