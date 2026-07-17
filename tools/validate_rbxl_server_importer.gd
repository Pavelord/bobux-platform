extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://addons/rbxl_importer/importer.gd")
	if script == null:
		push_error("Could not load RbxlServerImporter script")
		quit(1)
		return
	var importer: Node = script.new()
	if importer == null:
		push_error("Could not instantiate RbxlServerImporter")
		quit(1)
		return
	get_root().add_child(importer)
	if not importer.has_method("import_rbxl"):
		push_error("RbxlServerImporter is missing import_rbxl()")
		quit(1)
		return
	print("RbxlServerImporter validation OK")
	importer.queue_free()
	quit(0)
