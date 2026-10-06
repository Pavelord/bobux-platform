extends RefCounted

const CONTENT_KEYS := ["BobuxMeshResource", "MeshId", "MeshID", "SoundId", "Image", "Texture", "TextureID", "TextureId", "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap"]

static func is_asset_reference(value: String) -> bool:
	var text := value.strip_edges().to_lower().replace("\\", "/")
	if not _legacy_asset_id(text).is_empty(): return true
	return text.begins_with("http://") or text.begins_with("https://") or text.begins_with("rbxasset") or text.begins_with("www.") or text.is_valid_int() or text.begins_with("asset?") or text.begins_with("asset/?") or text.begins_with("/asset?") or text.begins_with("/asset/?")

static func _legacy_asset_id(value: String) -> String:
	var leaf := value.replace("\\", "/").get_file().to_lower()
	if not leaf.begins_with("asset?"): return ""
	for field in leaf.trim_prefix("asset?").split("&"):
		if field.begins_with("id=") and field.substr(3).is_valid_int(): return field.substr(3)
	return ""

static func canonical_content(value: String) -> String:
	# Some old saves prepended their cache directory to a scheme-less asset
	# URL. It was never a local file. Recover the stable Roblox content ID.
	var id := _legacy_asset_id(value)
	if not id.is_empty() and not value.begins_with("http://") and not value.begins_with("https://"):
		return "rbxassetid://" + id
	return value

# Older saves localized runtime objects but kept the original web URL in the
# DataModel. Join by referent so published maps never depend on editor caches.
static func bind_runtime_assets(manifest: Dictionary, runtime_objects: Array) -> Dictionary:
	var assets := {}
	for object in runtime_objects:
		if not object is Dictionary: continue
		var file := str(object.get("file", object.get("resolved_path", object.get("path", ""))))
		if file.is_empty(): continue
		if is_asset_reference(file) or is_asset_reference(file.get_file()): continue
		var key := "Texture" if str(object.get("class", "")) in ["Decal", "Texture"] else "SoundId" if str(object.get("class", "")) == "Sound" else ""
		if not key.is_empty(): assets[str(object.get("roblox_ref", ""))] = {"key":key,"path":file}
	var result := manifest.duplicate(false)
	for section in ["instances", "tools", "gui", "storage_libraries"]:
		var entries: Array = []
		for entry in manifest.get(section, []):
			if not entry is Dictionary: continue
			var copy: Dictionary = entry.duplicate(false)
			var asset: Dictionary = assets.get(str(entry.get("ref", "")), {})
			if not asset.is_empty():
				var props: Dictionary = entry.get("properties", {}).duplicate(false)
				# Published manifests have their own canonical filenames. An older
				# runtime record can still name an editor-only rbxl_texture file.
				var existing := str(props.get(asset.key, ""))
				if existing.is_empty() or is_asset_reference(existing):
					props[asset.key] = asset.path
				copy["properties"] = props
			entries.append(copy)
		result[section] = entries
	return result

static func resolve(manifest: Dictionary, folder: String) -> Dictionary:
	var result := manifest.duplicate(false)
	for section in ["instances", "tools", "gui", "storage_libraries"]:
		var entries: Array = manifest.get(section, [])
		var resolved: Array = []
		for entry in entries:
			if not entry is Dictionary: continue
			var copy: Dictionary = entry.duplicate(false)
			var props: Dictionary = entry.get("properties", {})
			var copied := false
			for key in CONTENT_KEYS:
				var original := str(props.get(key, ""))
				var path := canonical_content(original)
				if path != original:
					if not copied:
						props = props.duplicate(false)
						copied = true
					props[key] = path
				if not path.is_empty() and not is_asset_reference(path) and not path.contains(":") and not path.begins_with("/") and not ".." in path.replace("\\", "/").split("/"):
					if not copied:
						props = props.duplicate(false)
						copied = true
					props[key] = folder.path_join(path)
			copy["properties"] = props
			resolved.append(copy)
		result[section] = resolved
	return result
