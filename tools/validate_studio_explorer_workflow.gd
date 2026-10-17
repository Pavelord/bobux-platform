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
	var actual_services := _service_order(explorer.get_root())
	var service_order_ok := actual_services == EXPECTED_SERVICES
	var source_item := _find_item(explorer.get_root(), source_model.get_instance_id())
	var target_item := _find_item(explorer.get_root(), target_model.get_instance_id())
	var nested_item := _find_item(explorer.get_root(), part.get_instance_id())
	var hierarchy_ok := source_item != null and target_item != null and nested_item != null and nested_item.get_parent() == source_item
	var workspace_item := _find_item(explorer.get_root(), workspace.get_instance_id())
	var row_plus_ok := source_item != null and source_item.get_button_count(0) == 1 and workspace_item != null and workspace_item.get_button_count(0) == 1
	var rename_shortcut_ok := false
	if source_item != null:
		explorer.grab_focus()
		explorer.set_selected(source_item, 0)
		var rename_key := InputEventKey.new()
		rename_key.keycode = KEY_F2
		rename_key.pressed = true
		var rename_shortcut_handled: bool = studio._handle_explorer_keyboard_shortcut(rename_key)
		await process_frame
		var rename_dialog := studio.find_child("ExplorerRenameDialog", true, false) as ConfirmationDialog
		var rename_edit: LineEdit = null
		if rename_dialog != null:
			for child in rename_dialog.get_children():
				if child is LineEdit:
					rename_edit = child as LineEdit
					break
		if rename_edit != null and rename_dialog != null:
			rename_edit.text = "RenamedSourceModel"
			rename_dialog.emit_signal("confirmed")
			await process_frame
		rename_shortcut_ok = rename_shortcut_handled and source_model.name == "RenamedSourceModel" and _find_item(explorer.get_root(), source_model.get_instance_id()) != null
		source_item = _find_item(explorer.get_root(), source_model.get_instance_id())
	var quick_insert_ok := false
	if row_plus_ok:
		studio._on_explorer_tree_button_clicked(source_item, 0, 1, MOUSE_BUTTON_LEFT)
		await process_frame
		var insert_dialog := studio.find_child("InsertObjectDialog", true, false) as ConfirmationDialog
		var search := insert_dialog.find_child("SearchObjects", true, false) as LineEdit if insert_dialog != null else null
		var object_list := insert_dialog.find_child("InsertObjectList", true, false) as ItemList if insert_dialog != null else null
		if search != null and object_list != null:
			search.text = "Script"
			search.text_changed.emit("Script")
			if object_list.item_count > 0:
				object_list.select(0)
				insert_dialog.emit_signal("confirmed")
				await process_frame
				var inserted_script := _last_child_in_group(source_model, "bobux_scripts")
				var inserted_id := inserted_script.get_instance_id() if inserted_script != null else 0
				quick_insert_ok = inserted_script != null and inserted_script.get_parent() == source_model and str(inserted_script.get_meta("script_type", "")) == "Script" and studio.open_scripts.has(inserted_id) and studio.script_document_buttons.has(inserted_id)
				if quick_insert_ok:
					studio._delete_node(inserted_script)
					quick_insert_ok = inserted_script.get_parent() == null and _find_item(explorer.get_root(), inserted_id) == null and not studio.open_scripts.has(inserted_id) and not studio.script_document_buttons.has(inserted_id)
	# The insert/delete checks rebuild the Tree, so reacquire items before using
	# them in the drag-and-drop portion below.
	target_item = _find_item(explorer.get_root(), target_model.get_instance_id())

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
	var part_item := _find_item(explorer.get_root(), part.get_instance_id())
	explorer.grab_focus()
	if part_item != null:
		explorer.set_selected(part_item, 0)
	var duplicate_key := InputEventKey.new()
	duplicate_key.keycode = KEY_D
	duplicate_key.ctrl_pressed = true
	duplicate_key.pressed = true
	var duplicate_shortcut_ok: bool = studio._handle_explorer_keyboard_shortcut(duplicate_key)
	await process_frame
	var duplicate_ok: bool = duplicate_shortcut_ok and target_model.get_child_count() == count_before + 1
	var duplicate: Node = null
	for child in target_model.get_children():
		if child != part and str(child.get_meta("roblox_class", "")) == "Part":
			duplicate = child
			break
	var had_duplicate := duplicate != null
	var delete_shortcut_ok: bool = false
	if had_duplicate:
		var duplicate_item := _find_item(explorer.get_root(), duplicate.get_instance_id())
		explorer.grab_focus()
		if duplicate_item != null:
			explorer.set_selected(duplicate_item, 0)
		var delete_key := InputEventKey.new()
		delete_key.keycode = KEY_DELETE
		delete_key.pressed = true
		delete_shortcut_ok = studio._handle_explorer_keyboard_shortcut(delete_key)
		await process_frame
		await process_frame
	var delete_ok: bool = had_duplicate and delete_shortcut_ok and not is_instance_valid(duplicate) and target_model.get_child_count() == count_before
	if not delete_ok:
		print("[validate_studio_explorer_workflow] delete debug duplicate_valid=%s queued=%s children=%d expected=%d locked=%s" % [
			str(is_instance_valid(duplicate)),
			str(duplicate.is_queued_for_deletion() if is_instance_valid(duplicate) else false),
			target_model.get_child_count(), count_before, str(studio._is_studio_editing_locked()),
		])

	var ok: bool = service_order_ok and hierarchy_ok and row_plus_ok and rename_shortcut_ok and quick_insert_ok and drop_ok and filter_ok and duplicate_ok and delete_ok
	print("[validate_studio_explorer_workflow] ok=%s services=%s hierarchy=%s row_plus=%s rename=%s quick_insert=%s drop=%s filter=%s duplicate=%s delete=%s" % [
		str(ok), str(service_order_ok), str(hierarchy_ok), str(row_plus_ok), str(rename_shortcut_ok), str(quick_insert_ok), str(drop_ok), str(filter_ok), str(duplicate_ok), str(delete_ok),
	])
	if not service_order_ok:
		print("[validate_studio_explorer_workflow] actual services=", actual_services)
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


func _last_child_in_group(parent: Node, group_name: String) -> Node:
	var result: Node = null
	for child in parent.get_children():
		if child.is_in_group(group_name):
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
