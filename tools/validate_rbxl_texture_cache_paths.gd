extends SceneTree


func _initialize() -> void:
	var importer_script: Script = load("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
	if importer_script == null:
		push_error("Could not load RbxlRuntimeImporter")
		quit(1)
		return
	var importer = importer_script.new()
	var path: String = importer._resolve_texture_content_to_local_path("rbxassetid://5941024965")
	if path.is_empty():
		push_error("Texture cache path for 5941024965 was not resolved")
		quit(1)
		return
	var texture: Texture2D = importer._load_texture_from_path(path)
	if texture == null:
		push_error("Texture cache path for 5941024965 did not load: %s" % path)
		quit(1)
		return
	print("RBXL texture cache path OK %s" % path)
	quit(0)
