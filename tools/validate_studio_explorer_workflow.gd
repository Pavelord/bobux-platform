extends SceneTree


const EXPECTED_SERVICES := [
	"Workspace", "Players", "Lighting", "MaterialService", "ReplicatedFirst",
	"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui",
	"StarterPack", "StarterPlayer", "Teams", "SoundService", "TextChatService",
]


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

	var workspace: Node = studio.get("placement_parent")
	studio._insert_roblox_instance(workspace, "Model")
	var source_model := _last_direct_child_of_class(workspace, "Model")
	source_model.name = "SourceModel"
	source_model.set_meta("block_name", "SourceModel")
	studio._insert_roblox_instance(source_model, "Part")
	var part := _last_direct_child_of_class(source_model, "Part")
	part.name = "NestedPart"
	part.set_meta("block_name", "NestedPart")
	studio._insert_roblox_instance(workspace, "Model")
	var target_model := _last_direct_child_of_class(workspace, "Model")
	target_model.name = "TargetModel"
	target_model.set_meta("block_name", "TargetModel")

	studio._refresh_explorer()
	await process_frame
	var explorer: Tree = studio.get("explorer_tree")
	var service_order_ok := _service_order(explorer.get_root()) == EXPECTED_SERVICES
	var source_item := _find_item(explorer.get_root(), source_model.get_instance_id())
	var target_item := _find_item(explorer.get_root(), target_model.get_instance_id())
	var nested_item := _find_item(explorer.get_root(), part.get_instance_id())
	var hierarchy_ok := source_item != null and target_item != null and nested_item != null and nested_item.get_parent() == source_item

	var drop_ok := false
	if target_item != null:
		var target_rect := explorer.get_item_area_rect(target_item, 0)
		var drop_position := target_rect.position + target_rect.size * 0.5
		var drag_data := {"kind": "roblox_explorer_node", "node_id": part.get_instance_id()}
		drop_ok = bool(studio._explorer_can_drop_data(drop_position, drag_data))
		if drop_ok:
			studio._explorer_drop_data(drop_position, drag_data)
	await process_frame
	drop_ok = drop_ok and part.get_parent() == target_model

	var explorer_helper: Variant = studio.get("roblox_explorer")
	explorer_helper.call("set_filter_text", "nestedpart")
	studio._refresh_explorer()
	var filter_ok := _find_item(explorer.get_root(), target_model.get_instance_id()) != null and _find_item(explorer.get_root(), part.get_instance_id()) != null
	explorer_helper.call("set_filter_text", "")
	studio._refresh_explorer()

	var count_before := target_model.get_child_count()
	studio._duplicate_node(part)
	await process_frame
	var duplicate_ok := target_model.get_child_count() == count_before + 1
	var duplicate: Node = null
	for child in target_model.get_children():
		if child != part and str(child.get_meta("roblox_class", "")) == "Part":
			duplicate = child
			break
	var had_duplicate := duplicate != null
	if had_duplicate:
		studio._delete_node(duplicate)
		await process_frame
		await process_frame
	var delete_ok := had_duplicate and not is_instance_valid(duplicate) and target_model.get_child_count() == count_before
	if not delete_ok:
		print("[validate_studio_explorer_workflow] delete debug duplicate_valid=%s queued=%s children=%d expected=%d locked=%s" % [
			str(is_instance_valid(duplicate)),
			str(duplicate.is_queued_for_deletion() if is_instance_valid(duplicate) else false),
			target_model.get_child_count(), count_before, str(studio._is_studio_editing_locked()),
		])

	var ok := service_order_ok and hierarchy_ok and drop_ok and filter_ok and duplicate_ok and delete_ok
	print("[validate_studio_explorer_workflow] ok=%s services=%s hierarchy=%s drop=%s filter=%s duplicate=%s delete=%s" % [
		str(ok), str(service_order_ok), str(hierarchy_ok), str(drop_ok), str(filter_ok), str(duplicate_ok), str(delete_ok),
	])
	studio.free()
	quit(0 if ok else 1)


func _service_order(root: TreeItem) -> Array[String]:
	var result: Array[String] = []
	if root == null:
		return result
	var item := root.get_first_child()
	while item != null:
		result.append(item.get_text(0))
		item = item.get_next()
	return result


func _last_direct_child_of_class(parent: Node, roblox_class: String) -> Node:
	var result: Node = null
	for child in parent.get_children():
		if str(child.get_meta("roblox_class", "")) == roblox_class:
			result = child
	return result


func _find_item(item: TreeItem, node_id: int) -> TreeItem:
	if item == null:
		return null
	if item.get_metadata(0) is int and int(item.get_metadata(0)) == node_id:
		return item
	var child := item.get_first_child()
	while child != null:
		var found := _find_item(child, node_id)
		if found != null:
			return found
		child = child.get_next()
	return null
