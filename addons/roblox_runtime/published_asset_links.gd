extends RefCounted
## Recover media links from the established per-map storage directory in old
## publications. Only relative, traversal-free authored content is considered.
static func restore(data: Dictionary, external_url: String) -> bool:
	var marker := external_url.find("/map_data/")
	if marker < 0: return false
	var base := external_url.substr(0, marker)
	var urls: Dictionary = data.get("mode_asset_urls", {}).duplicate()
	var previous := urls.size()
	var manifest: Dictionary = data.get("roblox_manifest", {})
	var names := {}
	for section in ["instances", "gui", "tools", "storage_libraries"]:
		for entry in manifest.get(section, []):
			for key in preload("res://addons/roblox_runtime/roblox_manifest_assets.gd").CONTENT_KEYS:
				var value: Variant = entry.get("properties", {}).get(key, "")
				if value is String and not value.is_empty(): names[value] = true
	for block in data.get("blocks", []):
		for key in ["bobux_mesh_resource_asset", "roblox_mesh_json_asset", "roblox_texture_asset_file"]:
			var value: String = str(block.get(key, ""))
			if not value.is_empty(): names[value] = true
	for file in names:
		if urls.has(file) or file.contains(":") or file.begins_with("/") or file.contains("\\") or ".." in file.split("/"): continue
		if file.get_extension().to_lower() not in ["png","jpg","jpeg","webp","json","mesh","res","tres","ogg","mp3","wav"]: continue
		var encoded: PackedStringArray = []
		for segment in file.split("/"): encoded.append(segment.uri_encode())
		urls[file] = base + "/" + "/".join(encoded)
	if urls.size() == previous: return false
	data["mode_asset_urls"] = urls
	return true
