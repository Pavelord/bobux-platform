extends SceneTree


func _initialize() -> void:
	var loader_script: Script = load("res://addons/rbxl_importer/roblox_mesh_json_loader.gd")
	if loader_script == null:
		push_error("Could not load mesh JSON loader")
		quit(1)
		return
	var mesh: Mesh = loader_script.load_mesh("user://rbxl_assets/923015909.mesh.json")
	if mesh == null:
		push_error("Build a Boat mesh cache sample did not load")
		quit(1)
		return
	print("Build a Boat mesh cache OK surfaces=%d" % mesh.get_surface_count())
	quit(0)
