extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if scene == null:
		push_error("[validate_avatar_item_creator_interaction] Could not load lobby scene")
		quit(1)
		return
	var lobby := scene.instantiate()
	root.add_child(lobby)
	await process_frame
	if lobby.has_method("_ensure_avatar_ui_initialized"):
		lobby.call("_ensure_avatar_ui_initialized")
		for _avatar_wait in range(4):
			await process_frame
	await _validate_wardrobe_preview_interaction(lobby)
	if not lobby.has_method("_show_avatar_item_creator_page"):
		push_error("[validate_avatar_item_creator_interaction] Lobby has no avatar item creator page method")
		quit(1)
		return
	lobby.call("_show_avatar_item_creator_page")
	for _i in range(8):
		await process_frame
	var overlay := _find_child_recursive(lobby, "AvatarItemPreviewInputOverlay") as Control
	if overlay == null:
		push_error("[validate_avatar_item_creator_interaction] Preview input overlay was not created")
		quit(1)
		return
	var sub_viewport := overlay.get_parent().get_node_or_null("AvatarItemPreviewViewportContainer/AvatarItemPreviewViewport") as SubViewport
	var camera := sub_viewport.get_node_or_null("AvatarItemPreviewCamera") as Camera3D if sub_viewport != null else null
	if camera == null:
		push_error("[validate_avatar_item_creator_interaction] Preview camera was not created")
		quit(1)
		return
	var overlay_handler: Variant = overlay.get("input_handler")
	if not (overlay_handler is Callable) or not (overlay_handler as Callable).is_valid():
		push_error("[validate_avatar_item_creator_interaction] Preview overlay has no local input handler")
		quit(1)
		return
	if overlay.size.x <= 1.0 or overlay.size.y <= 1.0:
		push_error("[validate_avatar_item_creator_interaction] Preview overlay has no usable size: %s" % str(overlay.size))
		quit(1)
		return
	var container := _find_child_recursive(lobby, "AvatarItemPreviewViewportContainer") as Control
	if container == null or container.gui_input.get_connections().is_empty():
		push_error("[validate_avatar_item_creator_interaction] Preview viewport container has no fallback gui_input handler")
		quit(1)
		return
	var before_position := camera.position
	_emit_preview_drag(overlay, Vector2(220, 220), Vector2(300, 230))
	await process_frame
	if before_position.distance_to(camera.position) < 0.01:
		push_error("[validate_avatar_item_creator_interaction] Preview drag did not move the camera; overlay=%s connections=%d before=%s after=%s" % [str(overlay.size), overlay.gui_input.get_connections().size(), str(before_position), str(camera.position)])
		quit(1)
		return
	before_position = camera.position
	_emit_preview_drag(container, Vector2(220, 220), Vector2(280, 235))
	await process_frame
	if before_position.distance_to(camera.position) < 0.01:
		push_error("[validate_avatar_item_creator_interaction] Preview viewport fallback drag did not move the camera")
		quit(1)
		return
	var publish_button: Button = null
	for _wait_i in range(120):
		publish_button = _find_child_recursive(lobby, "PublishAvatarItem") as Button
		if publish_button != null:
			break
		await process_frame
	if publish_button == null:
		push_error("[validate_avatar_item_creator_interaction] Publish button is missing")
		quit(1)
		return
	var price := _find_child_recursive(lobby, "AvatarItemPrice") as SpinBox
	if price == null or price.min_value != 0 or price.step != 1:
		push_error("Avatar item price field is missing or invalid")
		quit(1)
		return
	price.value = 75
	if int(price.value) != 75:
		quit(1)
		return
	var manual_thumbnail_input := _find_line_edit_by_placeholder(lobby, "Thumbnail image path")
	if manual_thumbnail_input != null:
		push_error("[validate_avatar_item_creator_interaction] Manual thumbnail input is still visible")
		quit(1)
		return
	if not lobby.has_method("_copy_avatar_template_references_to_user_dir"):
		push_error("[validate_avatar_item_creator_interaction] Template download helper is missing")
		quit(1)
		return
	var copied_templates: Array = lobby.call("_copy_avatar_template_references_to_user_dir")
	if copied_templates.size() < 2:
		push_error("[validate_avatar_item_creator_interaction] Template download did not copy both references: %s" % str(copied_templates))
		quit(1)
		return
	for copied_path_variant in copied_templates:
		if not FileAccess.file_exists(str(copied_path_variant)):
			push_error("[validate_avatar_item_creator_interaction] Copied template path is missing: %s" % str(copied_path_variant))
			quit(1)
			return
	var attachment_root := _find_child_recursive(lobby, "AttachmentPreview") as Node3D
	var position_row := _find_child_recursive(lobby, "PositionRow") as HBoxContainer
	var rotation_row := _find_child_recursive(lobby, "RotationRow") as HBoxContainer
	var scale_row := _find_child_recursive(lobby, "ScaleRow") as HBoxContainer
	if attachment_root == null or position_row == null or rotation_row == null or scale_row == null:
		push_error("[validate_avatar_item_creator_interaction] Model attachment transform controls are missing")
		quit(1)
		return
	var pos_x := position_row.get_node_or_null("X") as SpinBox
	if pos_x == null:
		push_error("[validate_avatar_item_creator_interaction] Position X control is missing")
		quit(1)
		return
	var before_attachment_x := attachment_root.position.x
	pos_x.value += 0.5
	await process_frame
	if absf(attachment_root.position.x - before_attachment_x) < 0.1:
		push_error("[validate_avatar_item_creator_interaction] Position transform control did not update the attachment preview")
		quit(1)
		return
	lobby.call("_rebuild_avatar_item_attachment_preview", attachment_root, {
		"id": "validator_model",
		"name": "Validator Model",
		"data": {
			"parts": [{
				"name": "ValidatorPart",
				"kind": "Block",
				"position": [0.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.0, 1.0, 1.0],
				"color": "ffb347"
			}]
		}
	})
	await process_frame
	var gizmo_root := attachment_root.get_node_or_null("AttachmentGizmos")
	if gizmo_root == null:
		push_error("[validate_avatar_item_creator_interaction] Model attachment gizmos were not created")
		quit(1)
		return
	for gizmo_name in ["GizmoX", "GizmoY", "GizmoZ", "GizmoScale"]:
		if gizmo_root.get_node_or_null(gizmo_name) == null:
			push_error("[validate_avatar_item_creator_interaction] Missing model attachment gizmo %s" % gizmo_name)
			quit(1)
			return
	print("[validate_avatar_item_creator_interaction] Avatar item creator interaction OK")
	quit(0)

func _validate_wardrobe_preview_interaction(lobby: Node) -> void:
	var overlay := _find_child_recursive(lobby, "AvatarPreviewInputOverlay") as Control
	if overlay == null:
		push_error("[validate_avatar_item_creator_interaction] Wardrobe preview input overlay was not created")
		quit(1)
		return
	var preview_panel := overlay.get_parent()
	var sub := _find_child_recursive(preview_panel, "SubViewport") as SubViewport
	var camera := sub.get_node_or_null("Camera3D") as Camera3D if sub != null else null
	if camera == null:
		push_error("[validate_avatar_item_creator_interaction] Wardrobe preview camera was not found")
		quit(1)
		return
	var container := _find_child_recursive(preview_panel, "SubViewportContainer") as Control
	if container == null or container.gui_input.get_connections().is_empty():
		push_error("[validate_avatar_item_creator_interaction] Wardrobe viewport container has no fallback gui_input handler")
		quit(1)
		return
	var overlay_handler: Variant = overlay.get("input_handler")
	if not (overlay_handler is Callable) or not (overlay_handler as Callable).is_valid():
		push_error("[validate_avatar_item_creator_interaction] Wardrobe overlay has no local input handler")
		quit(1)
		return
	var before_position := camera.position
	_emit_preview_drag(overlay, Vector2(180, 180), Vector2(250, 190))
	await process_frame
	if before_position.distance_to(camera.position) < 0.01:
		push_error("[validate_avatar_item_creator_interaction] Wardrobe overlay drag did not move the camera")
		quit(1)
		return
	before_position = camera.position
	_emit_preview_drag(container, Vector2(180, 180), Vector2(250, 195))
	await process_frame
	if before_position.distance_to(camera.position) < 0.01:
		push_error("[validate_avatar_item_creator_interaction] Wardrobe viewport fallback drag did not move the camera")
		quit(1)
		return

func _emit_preview_drag(target: Control, from_pos: Vector2, to_pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_pos
	_emit_preview_input_event(target, press)
	var motion := InputEventMouseMotion.new()
	motion.position = to_pos
	motion.relative = to_pos - from_pos
	_emit_preview_input_event(target, motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to_pos
	_emit_preview_input_event(target, release)

func _emit_preview_input_event(target: Control, event: InputEvent) -> void:
	if target.get_script() != null and target.has_method("_gui_input"):
		target.call("_gui_input", event)
	else:
		target.gui_input.emit(event)

func _find_child_recursive(node: Node, node_name: String) -> Node:
	if node == null:
		return null
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_child_recursive(child, node_name)
		if found != null:
			return found
	return null

func _find_button_by_text(node: Node, text_value: String) -> Button:
	if node is Button and (node as Button).text == text_value:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text_value)
		if found != null:
			return found
	return null

func _find_line_edit_by_placeholder(node: Node, placeholder: String) -> LineEdit:
	if node is LineEdit and (node as LineEdit).placeholder_text == placeholder:
		return node as LineEdit
	for child in node.get_children():
		var found := _find_line_edit_by_placeholder(child, placeholder)
		if found != null:
			return found
	return null

func _find_direct_camera(node: Node) -> Camera3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null
