extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var assets_3d: Array = studio._get_toolbox_entries("3D Assets")
	var gameplay: Array = studio._get_toolbox_entries("Gameplay")
	var effects: Array = studio._get_toolbox_entries("Visual Effects")
	var gui_assets: Array = studio._get_toolbox_entries("2D Assets")
	var categories_ok := assets_3d.size() >= 9 and gameplay.size() >= 8 and effects.size() >= 6 and gui_assets.size() >= 7

	var workspace: Node = studio.get("placement_parent")
	var before_parts: int = studio._get_editor_parts().size()
	studio._activate_toolbox_entry({"action": "insert_shape", "value": "Sphere"})
	var after_parts: int = studio._get_editor_parts().size()
	var part_ok := after_parts == before_parts + 1
	var inserted_part: MeshInstance3D = studio._get_editor_parts().back() if part_ok else null
	part_ok = part_ok and inserted_part.mesh is SphereMesh

	studio._activate_toolbox_entry({"action": "insert_class", "value": "Tool"})
	var data_model: Node = studio.get("data_model")
	var starter_pack: Node = data_model.get_service("StarterPack")
	var tool: Node = starter_pack.find_child("Tool", false, false)
	var tool_ok := tool != null and tool.find_child("Handle", false, false) != null and tool.find_child("ToolClient", false, false) != null

	studio.set("explorer_selected_node", workspace)
	studio._insert_local_image_asset("res://assets/avatar/default_face.png")
	var image_nodes: Array = data_model.find_all_of_class("ImageLabel")
	var image_ok := not image_nodes.is_empty() and image_nodes.back() is TextureRect and (image_nodes.back() as TextureRect).texture != null

	studio._populate_toolbox_dock("Gameplay")
	var dock_list: ItemList = studio.get("toolbox_items_list")
	var dock_ok := dock_list != null and dock_list.item_count == gameplay.size() and dock_list.item_count > 0

	var ok := categories_ok and part_ok and tool_ok and image_ok and dock_ok
	print("[validate_studio_toolbox_assets] ok=%s categories=%s part=%s tool=%s image=%s dock=%s" % [
		str(ok), str(categories_ok), str(part_ok), str(tool_ok), str(image_ok), str(dock_ok),
	])
	studio.free()
	quit(0 if ok else 1)
