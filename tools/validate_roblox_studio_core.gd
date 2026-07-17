extends SceneTree

const DataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")
const ExplorerClass = preload("res://addons/roblox_studio/roblox_explorer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var workspace := Node3D.new()
	workspace.name = "Blocks"
	host.add_child(workspace)
	var part := MeshInstance3D.new()
	part.name = "TestPart"
	part.set_meta("roblox_class", "Part")
	part.add_to_group("studio_parts")
	workspace.add_child(part)

	var data_model := DataModelClass.new()
	host.add_child(data_model)
	data_model.register_workspace_alias(workspace)

	var script_node := DataModelClass.create_instance("Script", "ServerScript")
	script_node.set_meta("code", "print('studio core')")
	data_model.ensure_service("ServerScriptService").add_child(script_node)
	var screen_gui := DataModelClass.create_instance("ScreenGui", "TestGui")
	var text_button := DataModelClass.create_instance("TextButton", "TestButton")
	text_button.set_meta("roblox_properties", {"Text": "Play", "Size": {"x": {"scale": 0.0, "offset": 160.0}, "y": {"scale": 0.0, "offset": 48.0}}})
	screen_gui.add_child(text_button)
	data_model.ensure_service("StarterGui").add_child(screen_gui)

	var tree := Tree.new()
	root.add_child(tree)
	var explorer := ExplorerClass.new()
	explorer.rebuild(tree, data_model)

	var workspace_item := explorer.find_item_for_node(tree, workspace)
	var part_item := explorer.find_item_for_node(tree, part)
	var script_item := explorer.find_item_for_node(tree, script_node)
	var manifest: Dictionary = data_model.build_manifest({})
	var serialized_ok := (manifest.get("scripts", []) as Array).size() == 1 and (manifest.get("gui", []) as Array).size() == 2
	var ok := workspace_item != null and part_item != null and script_item != null and serialized_ok
	print("[validate_roblox_studio_core] workspace=", workspace_item != null,
		" part=", part_item != null, " script=", script_item != null,
		" serialized=", serialized_ok)
	quit(0 if ok else 1)
