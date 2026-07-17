class_name AvatarUI
extends RefCounted

const AVATAR_ROOM_BG_PATH := "res://assets/avatar/avatar_room_bg.jpg"
const SHIRT_TEMPLATE_REFERENCE_PATH := "res://assets/avatar/shirt_template_reference.jpg"
const PANTS_TEMPLATE_REFERENCE_PATH := "res://assets/avatar/pants_template_reference.jpg"
const AVATAR_TEMPLATE_PROCESSOR: Script = preload("res://scripts/avatar/avatar_template_processor.gd")
const AVATAR_PREVIEW_INPUT_OVERLAY_SCRIPT: Script = preload("res://scripts/ui/avatar_preview_input_overlay.gd")
const AVATAR_ITEM_CARD_WIDTH := 144
const AVATAR_ITEM_CARD_HEIGHT := 214
const AVATAR_ITEM_PREVIEW_WIDTH := 132
const AVATAR_ITEM_PREVIEW_HEIGHT := 128
const AVATAR_ITEM_PREVIEW_TEXTURE_SIZE := 512
const BODY_PARTS := [
	{"label": "Head", "key": "head", "player_key": "head_color"},
	{"label": "Torso", "key": "torso", "player_key": "torso_color"},
	{"label": "L Arm", "key": "left_arm", "player_key": "left_arm_color"},
	{"label": "R Arm", "key": "right_arm", "player_key": "right_arm_color"},
	{"label": "L Leg", "key": "left_leg", "player_key": "left_leg_color"},
	{"label": "R Leg", "key": "right_leg", "player_key": "right_leg_color"},
]
const BODY_PALETTE := [
	Color(0.96, 0.8, 0.2),
	Color(0.05, 0.4, 0.7),
	Color(0.65, 0.8, 0.2),
	Color(1.0, 1.0, 1.0),
	Color(0.18, 0.18, 0.18),
	Color(0.62, 0.62, 0.62),
	Color(0.95, 0.35, 0.13),
	Color(0.85, 0.0, 0.35),
	Color(0.05, 0.85, 0.92),
	Color(0.1, 0.15, 0.95),
	Color(0.45, 0.05, 0.95),
	Color(0.2, 0.9, 0.25),
	Color(0.97, 0.78, 0.62),
	Color(0.77, 0.58, 0.42),
	Color(0.42, 0.25, 0.14),
]

var lobby: Control
var current_category := "Body"
var wardrobe_container: GridContainer
var wearing_container: GridContainer
var template_status_label: Label
var body_select_status_label: Label

var _category_buttons: Dictionary = {}
var _body_part_buttons: Dictionary = {}
var _palette_buttons: Array = []
var _categorized_items: Dictionary = {}
var _local_visual_item_payloads: Dictionary = {}
var _cloud_catalog: Array = []
var _user_inventory_ids: Array = []
var _user_avatar_data: Dictionary = {}
var _preview_player: Node = null
var _avatar_file_dialog: FileDialog = null
var _pending_template_kind := ""
var _selected_body_part_key := "torso"
var _cloud_inventory_loaded := false
var _cloud_inventory_loading := false
var _avatar_sync_in_flight := false
var _avatar_sync_pending := false
var _remote_item_texture_cache: Dictionary = {}
var _remote_item_texture_loading: Dictionary = {}


func init(parent_lobby: Control) -> void:
	lobby = parent_lobby
	if not is_instance_valid(lobby):
		return
	_load_session_avatar_data()
	var avatar_view := lobby.get_node_or_null("%MainTabs/AvatarView")
	if avatar_view == null:
		return
	_prepare_avatar_surface(avatar_view)
	_install_preview_background(avatar_view)
	_preview_player = _find_child_recursive(avatar_view, "PreviewPlayer")
	_build_left_avatar_controls(avatar_view)
	_install_preview_interaction(avatar_view)
	_build_right_catalog_ui(avatar_view)
	_group_catalog()
	_refresh_ui()
	_apply_visuals_to_preview_player()


func ensure_cloud_inventory_loaded() -> void:
	if _cloud_inventory_loaded or _cloud_inventory_loading:
		return
	await _load_cloud_inventory()


func reload_cloud_inventory() -> void:
	_load_session_avatar_data()
	_cloud_inventory_loaded = false
	await _load_cloud_inventory()


func _extract_response_array(response: Dictionary) -> Array:
	var data: Variant = response.get("data", [])
	if data is Array:
		return data
	if data is Dictionary:
		for key in ["items", "models", "avatar_items", "data"]:
			var nested: Variant = (data as Dictionary).get(key, [])
			if nested is Array:
				return nested
	return []

func _load_cloud_inventory() -> void:
	_cloud_inventory_loading = true
	_cloud_catalog.clear()
	var cloud_api := _get_cloud_api()
	if cloud_api != null:
		if cloud_api.has_method("fetch_catalog"):
			var catalog_result: Variant = await cloud_api.fetch_catalog()
			if catalog_result is Dictionary:
				var items := _extract_response_array(catalog_result)
				for item in items:
					if item is Dictionary:
						_cloud_catalog.append(item)
		if cloud_api.has_method("fetch_avatar_marketplace_items"):
			var marketplace_result: Variant = await cloud_api.fetch_avatar_marketplace_items()
			if marketplace_result is Dictionary:
				var items := _extract_response_array(marketplace_result)
				for item in items:
					if item is Dictionary:
						_cloud_catalog.append(item)
		if cloud_api.has_method("load_player_profile"):
			var current_user_id := ""
			if typeof(UserSession) != TYPE_NIL:
				current_user_id = UserSession.user_id.strip_edges()
			if current_user_id.is_empty() and cloud_api.has_method("get_current_user_id"):
				current_user_id = str(cloud_api.get_current_user_id()).strip_edges()
			var profile_result: Variant = {}
			if not current_user_id.is_empty():
				profile_result = await cloud_api.load_player_profile(current_user_id)
			# Guard: after await, this node may have been freed (user left avatar screen)
			if not is_instance_valid(self):
				return
			if profile_result is Dictionary:
				var profile_response := profile_result as Dictionary
				var profile: Dictionary = profile_response.get("data", {}) if profile_response.get("data", {}) is Dictionary else profile_response
				if profile.has("inventory_items") and profile["inventory_items"] is Array:
					_user_inventory_ids = profile["inventory_items"]
	if not is_instance_valid(self):
		return
	_cloud_inventory_loaded = true
	_cloud_inventory_loading = false
	_normalize_avatar_data()
	var equipped_changed := _sanitize_equipped_avatar_item_ids()
	_group_catalog()
	_refresh_ui()
	_apply_visuals_to_preview_player()
	if equipped_changed:
		_queue_avatar_sync()


func _load_session_avatar_data() -> void:
	var session_avatar: Dictionary = {}
	if typeof(UserSession) != TYPE_NIL:
		session_avatar = UserSession.avatar_data.duplicate(true)
	_user_avatar_data = session_avatar
	if typeof(UserSession) != TYPE_NIL and UserSession.inventory_items is Array:
		_user_inventory_ids = UserSession.inventory_items.duplicate(true)
	_normalize_avatar_data()


func _normalize_avatar_data() -> void:
	for part_variant in BODY_PARTS:
		var part: Dictionary = part_variant
		var avatar_key := str(part.get("key", ""))
		var player_key := str(part.get("player_key", ""))
		var default_color := _get_default_body_color(avatar_key)
		if not _user_avatar_data.has(avatar_key) and _user_avatar_data.has(player_key):
			_user_avatar_data[avatar_key] = _user_avatar_data[player_key]
		var resolved_color := _resolve_avatar_color_value(_user_avatar_data.get(avatar_key, default_color), default_color)
		_user_avatar_data[avatar_key] = resolved_color
		_user_avatar_data[player_key] = resolved_color
	if not _user_avatar_data.has("equipped") or not (_user_avatar_data["equipped"] is Array):
		_user_avatar_data["equipped"] = []
	if not _user_avatar_data.has("face_texture_path") or str(_user_avatar_data.get("face_texture_path", "")).is_empty():
		_user_avatar_data["face_texture_path"] = GameState.DEFAULT_FACE_TEXTURE_PATH
	if not _user_avatar_data.has("chest_badge_texture_path"):
		_user_avatar_data["chest_badge_texture_path"] = GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH
	if not _user_avatar_data.has("shirt_texture_path"):
		_user_avatar_data["shirt_texture_path"] = ""
	if not _user_avatar_data.has("pants_texture_path"):
		_user_avatar_data["pants_texture_path"] = ""
	if not _user_avatar_data.has("saved_shirt_texture_paths") or not (_user_avatar_data["saved_shirt_texture_paths"] is Array):
		_user_avatar_data["saved_shirt_texture_paths"] = []
	if not _user_avatar_data.has("saved_pants_texture_paths") or not (_user_avatar_data["saved_pants_texture_paths"] is Array):
		_user_avatar_data["saved_pants_texture_paths"] = []


func _prepare_avatar_surface(avatar_view: Control) -> void:
	var content := _get_avatar_content(avatar_view)
	if content == null:
		var margin := MarginContainer.new()
		margin.name = "AvatarMargin"
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 24)
		margin.add_theme_constant_override("margin_right", 24)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		avatar_view.add_child(margin)
		content = HBoxContainer.new()
		content.name = "Content"
		content.add_theme_constant_override("separation", 28)
		margin.add_child(content)
	if content.size_flags_horizontal == 0:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if content.size_flags_vertical == 0:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _get_avatar_content(avatar_view: Control) -> HBoxContainer:
	var scene_main_row := avatar_view.get_node_or_null("Content/MainRow")
	if scene_main_row is HBoxContainer:
		return scene_main_row
	var scene_content := avatar_view.get_node_or_null("Content")
	if scene_content is HBoxContainer:
		return scene_content
	var direct := avatar_view.get_node_or_null("AvatarMargin/Content")
	if direct is HBoxContainer:
		return direct
	for child in avatar_view.get_children():
		if child is MarginContainer:
			var nested := (child as Node).get_node_or_null("Content")
			if nested is HBoxContainer:
				return nested
	return null


func _install_preview_background(avatar_view: Control) -> void:
	var content := _get_avatar_content(avatar_view)
	if content == null:
		return
	var preview_panel := _get_preview_panel(content)
	if preview_panel == null:
		return
	if preview_panel.get_node_or_null("BobuxAvatarRoomBg") != null:
		return
	var bg := TextureRect.new()
	bg.name = "BobuxAvatarRoomBg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	var texture := _load_texture_from_any_path(AVATAR_ROOM_BG_PATH)
	if texture is Texture2D:
		bg.texture = texture
	preview_panel.clip_contents = true
	preview_panel.add_child(bg)
	preview_panel.move_child(bg, 0)


func _install_preview_interaction(avatar_view: Control) -> void:
	var content := _get_avatar_content(avatar_view)
	if content == null:
		return
	var preview_panel := _get_preview_panel(content)
	if preview_panel == null:
		return
	var sub_container := _find_child_recursive(preview_panel, "SubViewportContainer") as SubViewportContainer
	if sub_container == null:
		return
	var sub := _find_child_recursive(preview_panel, "SubViewport") as SubViewport
	if sub == null:
		return
	var camera := sub.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	var old_overlay := preview_panel.get_node_or_null("AvatarPreviewInputOverlay")
	if old_overlay != null:
		preview_panel.remove_child(old_overlay)
		old_overlay.free()
	var overlay: Control = AVATAR_PREVIEW_INPUT_OVERLAY_SCRIPT.new() as Control
	overlay.name = "AvatarPreviewInputOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.focus_mode = Control.FOCUS_ALL
	overlay.mouse_default_cursor_shape = Control.CURSOR_DRAG
	overlay.z_index = 400
	preview_panel.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	sub_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var camera_state := {
		"yaw": 0.0,
		"pitch": 0.04,
		"distance": 4.6,
		"dragging": false
	}
	var update_preview_camera := func() -> void:
		if camera == null or not is_instance_valid(camera):
			return
		var target := Vector3(0.0, 3.0, 0.0)
		var yaw := float(camera_state["yaw"])
		var pitch := float(camera_state["pitch"])
		var distance := float(camera_state["distance"])
		var offset := Vector3(
			sin(yaw) * cos(pitch),
			sin(pitch),
			cos(yaw) * cos(pitch)
		) * distance
		camera.position = target + offset
		camera.look_at(target, Vector3.UP)
	update_preview_camera.call()
	var handle_preview_input := func(event: InputEvent, input_receiver: Control = null) -> void:
		var receiver: Control = input_receiver if input_receiver != null else overlay
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index == MOUSE_BUTTON_LEFT or mouse_button.button_index == MOUSE_BUTTON_RIGHT:
				if mouse_button.pressed:
					receiver.grab_focus()
				camera_state["dragging"] = mouse_button.pressed
				receiver.accept_event()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
				camera_state["distance"] = maxf(2.8, float(camera_state["distance"]) - 0.35)
				update_preview_camera.call()
				receiver.accept_event()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
				camera_state["distance"] = minf(7.2, float(camera_state["distance"]) + 0.35)
				update_preview_camera.call()
				receiver.accept_event()
		elif event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			var button_dragging := bool(camera_state["dragging"]) or ((motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0) or ((motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0)
			if not button_dragging:
				return
			camera_state["yaw"] = float(camera_state["yaw"]) - motion.relative.x * 0.008
			camera_state["pitch"] = clampf(float(camera_state["pitch"]) - motion.relative.y * 0.006, -0.55, 0.75)
			update_preview_camera.call()
			receiver.accept_event()
	if overlay.has_method("set_input_handler"):
		overlay.call("set_input_handler", handle_preview_input)
	sub_container.gui_input.connect(handle_preview_input.bind(sub_container))
	var old_controls := preview_panel.get_node_or_null("AvatarPreviewOrbitControls")
	if old_controls != null:
		preview_panel.remove_child(old_controls)
		old_controls.queue_free()
	var orbit_controls := HBoxContainer.new()
	orbit_controls.name = "AvatarPreviewOrbitControls"
	orbit_controls.mouse_filter = Control.MOUSE_FILTER_STOP
	orbit_controls.add_theme_constant_override("separation", 6)
	orbit_controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	orbit_controls.offset_left = -218
	orbit_controls.offset_top = -42
	orbit_controls.offset_right = -12
	orbit_controls.offset_bottom = -10
	preview_panel.add_child(orbit_controls)
	var rotate_left_btn := Button.new()
	rotate_left_btn.text = "<"
	rotate_left_btn.tooltip_text = "Rotate left"
	rotate_left_btn.custom_minimum_size = Vector2(46, 32)
	rotate_left_btn.pressed.connect(func() -> void:
		camera_state["yaw"] = float(camera_state["yaw"]) + 0.32
		update_preview_camera.call()
	)
	orbit_controls.add_child(rotate_left_btn)
	var rotate_right_btn := Button.new()
	rotate_right_btn.text = ">"
	rotate_right_btn.tooltip_text = "Rotate right"
	rotate_right_btn.custom_minimum_size = Vector2(46, 32)
	rotate_right_btn.pressed.connect(func() -> void:
		camera_state["yaw"] = float(camera_state["yaw"]) - 0.32
		update_preview_camera.call()
	)
	orbit_controls.add_child(rotate_right_btn)
	var reset_orbit_btn := Button.new()
	reset_orbit_btn.text = "Reset"
	reset_orbit_btn.custom_minimum_size = Vector2(82, 32)
	reset_orbit_btn.pressed.connect(func() -> void:
		camera_state["yaw"] = 0.0
		camera_state["pitch"] = 0.04
		camera_state["distance"] = 4.6
		update_preview_camera.call()
	)
	orbit_controls.add_child(reset_orbit_btn)


func _get_preview_panel(content: HBoxContainer) -> Control:
	var direct := content.get_node_or_null("LeftColumn/PreviewPanel")
	if direct is Control:
		return direct
	var found := _find_child_recursive(content, "PreviewPanel")
	return found if found is Control else null


func _build_left_avatar_controls(avatar_view: Control) -> void:
	var content := _get_avatar_content(avatar_view)
	if content == null or content.get_child_count() == 0:
		return
	var left_col := content.get_node_or_null("LeftColumn")
	if not (left_col is VBoxContainer):
		var first_child := content.get_child(0)
		if first_child is VBoxContainer:
			left_col = first_child
	if not (left_col is VBoxContainer):
		return

	# Re-parent PreviewPanel to Content/MainRow to place it in the center (between left and right columns)
	var preview_panel = left_col.get_node_or_null("PreviewPanel")
	if preview_panel != null:
		left_col.remove_child(preview_panel)
		content.add_child(preview_panel)
		content.move_child(preview_panel, 1) # Put in the center column
		preview_panel.custom_minimum_size = Vector2(360, 360)
		preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	left_col.custom_minimum_size = Vector2(220, 0)
	
	# Hide unused PC-only label components in the left column
	for node_name in ["RedrawLabel", "AvatarTypeLabel", "TypeRow", "TypeNote", "ColorsTitle", "ColorsSubtitle"]:
		var node = left_col.get_node_or_null(node_name)
		if node != null:
			node.visible = false

	# Setup BodyDiagram buttons
	_body_part_buttons.clear()
	var diagram = left_col.get_node_or_null("BodyPartsRow/BodyDiagram")
	if diagram != null:
		var btn_head = diagram.get_node_or_null("HeadRow/BtnHead") as Button
		if btn_head:
			for c in btn_head.pressed.get_connections(): btn_head.pressed.disconnect(c.callable)
			btn_head.pressed.connect(_on_body_part_pressed.bind("head"))
			_body_part_buttons["head"] = btn_head
		var btn_left_arm = diagram.get_node_or_null("UpperBodyRow/BtnLeftArm") as Button
		if btn_left_arm:
			for c in btn_left_arm.pressed.get_connections(): btn_left_arm.pressed.disconnect(c.callable)
			btn_left_arm.pressed.connect(_on_body_part_pressed.bind("left_arm"))
			_body_part_buttons["left_arm"] = btn_left_arm
		var btn_torso = diagram.get_node_or_null("UpperBodyRow/BtnTorso") as Button
		if btn_torso:
			for c in btn_torso.pressed.get_connections(): btn_torso.pressed.disconnect(c.callable)
			btn_torso.pressed.connect(_on_body_part_pressed.bind("torso"))
			_body_part_buttons["torso"] = btn_torso
		var btn_right_arm = diagram.get_node_or_null("UpperBodyRow/BtnRightArm") as Button
		if btn_right_arm:
			for c in btn_right_arm.pressed.get_connections(): btn_right_arm.pressed.disconnect(c.callable)
			btn_right_arm.pressed.connect(_on_body_part_pressed.bind("right_arm"))
			_body_part_buttons["right_arm"] = btn_right_arm
		var btn_left_leg = diagram.get_node_or_null("LowerBodyRow/BtnLeftLeg") as Button
		if btn_left_leg:
			for c in btn_left_leg.pressed.get_connections(): btn_left_leg.pressed.disconnect(c.callable)
			btn_left_leg.pressed.connect(_on_body_part_pressed.bind("left_leg"))
			_body_part_buttons["left_leg"] = btn_left_leg
		var btn_right_leg = diagram.get_node_or_null("LowerBodyRow/BtnRightLeg") as Button
		if btn_right_leg:
			for c in btn_right_leg.pressed.get_connections(): btn_right_leg.pressed.disconnect(c.callable)
			btn_right_leg.pressed.connect(_on_body_part_pressed.bind("right_leg"))
			_body_part_buttons["right_leg"] = btn_right_leg

	# Setup Color Palette grid (make it 2 columns, vertical, next to the body diagram)
	var color_grid = left_col.get_node_or_null("BodyPartsRow/ColorGrid") as GridContainer
	if color_grid != null:
		color_grid.columns = 2
		_palette_buttons.clear()
		var color_buttons := color_grid.get_children()
		for i in range(mini(color_buttons.size(), BODY_PALETTE.size())):
			var button = color_buttons[i] as Button
			if button != null:
				var color: Color = BODY_PALETTE[i]
				_apply_swatch_style(button, color, false)
				for c in button.pressed.get_connections():
					button.pressed.disconnect(c.callable)
				button.pressed.connect(_on_palette_color_pressed.bind(color))
				_palette_buttons.append({"button": button, "color": color})

	# Setup body select status label under the body parts diagram
	var status_parent = left_col.get_node_or_null("BodyPartsRow")
	if status_parent != null:
		body_select_status_label = left_col.get_node_or_null("BodySelectStatusLabel") as Label
		if body_select_status_label == null:
			body_select_status_label = Label.new()
			body_select_status_label.name = "BodySelectStatusLabel"
			body_select_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body_select_status_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18))
			body_select_status_label.add_theme_font_size_override("font_size", 14)
			left_col.add_child(body_select_status_label)
	
	_refresh_body_controls()


func _build_right_catalog_ui(avatar_view: Control) -> void:
	var content := _get_avatar_content(avatar_view)
	if content == null:
		return
	var right_col: VBoxContainer = content.get_node_or_null("RightColumn") as VBoxContainer
	if right_col == null:
		for child in content.get_children():
			if child is VBoxContainer and child.name != "LeftColumn":
				right_col = child
				break
	if right_col == null:
		right_col = VBoxContainer.new()
		right_col.name = "RightColumn"
		right_col.custom_minimum_size = Vector2(420, 560)
		right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(right_col)
	right_col.custom_minimum_size = Vector2(420, 560)
	for child in right_col.get_children():
		right_col.remove_child(child)
		child.queue_free()
	var block := PanelContainer.new()
	block.name = "BobuxWardrobeBlock"
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.94), Color(0.08, 0.08, 0.08, 0.95), 2, 8))
	right_col.add_child(block)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block.add_child(outer)
	var title := Label.new()
	title.text = "Catalog"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	outer.add_child(title)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	outer.add_child(tabs)
	_category_buttons.clear()
	for category_name in ["Body", "Clothes", "Accessories", "Face"]:
		var button := Button.new()
		button.text = category_name
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(92, 36)
		button.pressed.connect(_on_category_pressed.bind(category_name))
		tabs.add_child(button)
		_category_buttons[category_name] = button

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	wardrobe_container = GridContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	wardrobe_container.columns = 2
	wardrobe_container.add_theme_constant_override("h_separation", 12)
	wardrobe_container.add_theme_constant_override("v_separation", 12)
	wardrobe_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wardrobe_container)
	var wearing_title := Label.new()
	wearing_title.text = "Currently Wearing"
	wearing_title.add_theme_font_size_override("font_size", 18)
	wearing_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	outer.add_child(wearing_title)
	wearing_container = GridContainer.new()
	wearing_container.columns = 1
	wearing_container.add_theme_constant_override("h_separation", 6)
	wearing_container.add_theme_constant_override("v_separation", 6)
	wearing_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(wearing_container)
	_ensure_file_dialog(avatar_view)


func _ensure_file_dialog(owner_node: Node) -> void:
	if is_instance_valid(_avatar_file_dialog):
		return
	_avatar_file_dialog = FileDialog.new()
	_avatar_file_dialog.use_native_dialog = true
	_avatar_file_dialog.name = "AvatarTemplateFileDialog"
	_avatar_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_avatar_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_avatar_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image files"])
	_avatar_file_dialog.file_selected.connect(_on_template_file_selected)
	owner_node.add_child(_avatar_file_dialog)


func _group_catalog() -> void:
	_categorized_items.clear()
	_local_visual_item_payloads.clear()
	for category_name in ["Body", "Clothes", "Accessories", "Face"]:
		_categorized_items[category_name] = []
	_register_local_visual_item("Face", "classic_smile", "Classic Smile", "face_texture_path", str(_user_avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)), GameState.DEFAULT_FACE_TEXTURE_PATH)
	_register_local_visual_item("Accessories", "bobux_chest_badge", "Bobux Chest Badge", "chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH, GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)
	var shirt_path := str(_user_avatar_data.get("shirt_texture_path", ""))
	var saved_shirts := _get_saved_visual_paths("saved_shirt_texture_paths", shirt_path)
	for shirt_index in range(saved_shirts.size()):
		var saved_shirt_path := str(saved_shirts[shirt_index])
		_register_local_visual_item("Clothes", "uploaded_shirt_%d" % shirt_index, "Uploaded Shirt %d" % (shirt_index + 1), "shirt_texture_path", saved_shirt_path, saved_shirt_path)
	var pants_path := str(_user_avatar_data.get("pants_texture_path", ""))
	var saved_pants := _get_saved_visual_paths("saved_pants_texture_paths", pants_path)
	for pants_index in range(saved_pants.size()):
		var saved_pants_path := str(saved_pants[pants_index])
		_register_local_visual_item("Clothes", "uploaded_pants_%d" % pants_index, "Uploaded Pants %d" % (pants_index + 1), "pants_texture_path", saved_pants_path, saved_pants_path)
	var included_item_ids: Dictionary = {}
	for raw_item in _cloud_catalog:
		if not (raw_item is Dictionary):
			continue
		var item := raw_item as Dictionary
		var item_id := str(item.get("id", item.get("item_id", "")))
		if item_id.is_empty() or item_id in ["classic_head", "blue_torso", "green_legs"]:
			continue
		if not _is_cloud_item_owned(item):
			continue
		var category_name := _category_from_cloud_item(item)
		if not _categorized_items.has(category_name):
			category_name = "Accessories"
		_categorized_items[category_name].append(item)
		included_item_ids[item_id] = true
	for raw_item in _get_avatar_item_payloads_from_avatar_data():
		if not (raw_item is Dictionary):
			continue
		var item := raw_item as Dictionary
		var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
		if item_id.is_empty() or bool(included_item_ids.get(item_id, false)):
			continue
		if not _is_cloud_item_owned(item):
			continue
		var category_name := _category_from_cloud_item(item)
		if not _categorized_items.has(category_name):
			category_name = "Accessories"
		_categorized_items[category_name].append(item)
		included_item_ids[item_id] = true


func _register_local_visual_item(category_name: String, item_id: String, display_name: String, avatar_key: String, texture_path: String, preview_path: String) -> void:
	var item := {
		"id": item_id,
		"name": display_name,
		"type": "local_visual",
		"avatar_key": avatar_key,
		"texture_path": texture_path,
		"thumbnail_path": preview_path,
		"owned": true,
	}
	_local_visual_item_payloads[item_id] = item
	_categorized_items[category_name].append(item)


func _get_saved_visual_paths(list_key: String, active_path: String) -> Array:
	var paths: Array = []
	var raw_paths: Variant = _user_avatar_data.get(list_key, [])
	if raw_paths is Array:
		for raw_path in raw_paths:
			var clean_path := str(raw_path).strip_edges()
			if not clean_path.is_empty() and not (clean_path in paths):
				paths.append(clean_path)
	var clean_active := active_path.strip_edges()
	if not clean_active.is_empty() and not (clean_active in paths):
		paths.append(clean_active)
	if _is_cloud_ownership_context_ready():
		var filtered_paths: Array = []
		for raw_path in paths:
			var clean_path := str(raw_path).strip_edges()
			if clean_path.is_empty():
				continue
			if _is_owned_cloud_clothing_texture_path(clean_path):
				continue
			if not (clean_path in filtered_paths):
				filtered_paths.append(clean_path)
		paths = filtered_paths
	_user_avatar_data[list_key] = paths
	return paths


func _category_from_cloud_item(item: Dictionary) -> String:
	var item_data := _get_cloud_item_data(item)
	var raw_category := str(item.get("category", item.get("type", ""))).to_lower()
	if raw_category.is_empty() or raw_category in ["avatar_item", "avatar_items", "avatar items", "item"]:
		raw_category = str(item_data.get("category", item_data.get("item_kind", item_data.get("kind", "")))).to_lower()
	if raw_category in ["body", "head", "torso", "leg", "arm"]:
		return "Body"
	if raw_category in ["shirt", "pants", "clothes", "clothing", "tshirt", "t-shirt"]:
		return "Clothes"
	if raw_category in ["face"]:
		return "Face"
	return "Accessories"


func _refresh_ui() -> void:
	for category_name in _category_buttons.keys():
		var button := _category_buttons[category_name] as Button
		button.button_pressed = category_name == current_category
	if wardrobe_container != null:
		_clear_children(wardrobe_container)
		var items: Array = _categorized_items.get(current_category, [])
		if items.is_empty():
			var empty := Label.new()
			empty.text = "No items yet."
			empty.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
			wardrobe_container.add_child(empty)
		else:
			for raw_item in items:
				if raw_item is Dictionary:
					wardrobe_container.add_child(_create_item_card(raw_item))
	if wearing_container != null:
		_clear_children(wearing_container)
		for item in _get_wearing_items():
			wearing_container.add_child(_create_wearing_chip(item))
	_refresh_body_controls()


func _get_wearing_items() -> Array:
	var result: Array = []
	var included_ids: Dictionary = {}
	for local_id in _local_visual_item_payloads.keys():
		var item := _local_visual_item_payloads[local_id] as Dictionary
		var avatar_key := str(item.get("avatar_key", ""))
		if avatar_key.is_empty():
			continue
		if str(_user_avatar_data.get(avatar_key, "")) == str(item.get("texture_path", "")):
			result.append(item)
			included_ids[local_id] = true
	for raw_item in _cloud_catalog:
		if raw_item is Dictionary and _is_cloud_item_owned(raw_item as Dictionary) and _is_item_wearing(raw_item as Dictionary):
			var item_id := str((raw_item as Dictionary).get("id", (raw_item as Dictionary).get("item_id", ""))).strip_edges()
			if not bool(included_ids.get(item_id, false)):
				result.append(raw_item)
				included_ids[item_id] = true
	for raw_item in _get_avatar_item_payloads_from_avatar_data():
		if raw_item is Dictionary and _is_cloud_item_owned(raw_item as Dictionary) and _is_item_wearing(raw_item as Dictionary):
			var item_id := str((raw_item as Dictionary).get("id", (raw_item as Dictionary).get("item_id", ""))).strip_edges()
			if not bool(included_ids.get(item_id, false)):
				result.append(raw_item)
				included_ids[item_id] = true
	return result


func _get_equipped_avatar_item_payloads() -> Array:
	var result: Array = []
	for item_id in _get_owned_equipped_item_ids(true):
		var item := _get_cloud_catalog_item_by_id(item_id)
		if item.is_empty():
			continue
		result.append(item.duplicate(true))
	return result


func _create_item_card(item: Dictionary) -> Control:
	var item_id := str(item.get("id", item.get("item_id", "")))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(AVATAR_ITEM_CARD_WIDTH, AVATAR_ITEM_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 1), Color(0.08, 0.08, 0.08), 1, 4))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(AVATAR_ITEM_PREVIEW_WIDTH, AVATAR_ITEM_PREVIEW_HEIGHT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var texture := _load_texture_for_item(item)
	if texture is Texture2D:
		preview.texture = texture
	else:
		var placeholder = load("res://assets/avatar/bobux_chest_badge.png")
		if placeholder is Texture2D:
			preview.texture = placeholder
		_load_remote_texture_for_item_async(item, preview)
	box.add_child(preview)
	var title := Label.new()
	title.text = str(item.get("name", item.get("title", item_id)))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(AVATAR_ITEM_PREVIEW_WIDTH, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	box.add_child(title)
	var action := Button.new()
	action.text = "Unequip" if _is_item_wearing(item) else "Wear"
	action.custom_minimum_size = Vector2(AVATAR_ITEM_PREVIEW_WIDTH, 32)
	action.pressed.connect(_toggle_item.bind(item_id))
	box.add_child(action)
	return card


func _create_wearing_chip(item: Dictionary) -> Control:
	var item_id := str(item.get("id", item.get("item_id", "")))
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(0, 30)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.48, 0.82, 1), Color(0.08, 0.48, 0.82, 1), 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	var title := Label.new()
	title.text = str(item.get("name", item.get("title", item.get("id", "Item"))))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(title)
	var remove_button := Button.new()
	remove_button.text = "x"
	remove_button.custom_minimum_size = Vector2(24, 22)
	remove_button.focus_mode = Control.FOCUS_NONE
	if not item_id.is_empty():
		remove_button.pressed.connect(_toggle_item.bind(item_id))
	row.add_child(remove_button)
	return chip


func _is_item_wearing(item: Dictionary) -> bool:
	var item_id := str(item.get("id", item.get("item_id", "")))
	if _local_visual_item_payloads.has(item_id):
		var payload := _local_visual_item_payloads[item_id] as Dictionary
		return str(_user_avatar_data.get(str(payload.get("avatar_key", "")), "")) == str(payload.get("texture_path", ""))
	if not _is_cloud_item_owned(item):
		return false
	var clothing_key := _get_cloud_clothing_texture_key(item)
	if not clothing_key.is_empty():
		var texture_path := _get_cloud_clothing_texture_path(item)
		return not texture_path.is_empty() and str(_user_avatar_data.get(clothing_key, "")) == texture_path
	var equipped: Array = _user_avatar_data.get("equipped", [])
	return item_id in equipped


func _toggle_item(item_id: String) -> void:
	if item_id.is_empty():
		return
	if _local_visual_item_payloads.has(item_id):
		var payload := _local_visual_item_payloads[item_id] as Dictionary
		var avatar_key := str(payload.get("avatar_key", ""))
		var texture_path := str(payload.get("texture_path", ""))
		if avatar_key.is_empty():
			return
		var current_path := str(_user_avatar_data.get(avatar_key, ""))
		if avatar_key == "face_texture_path":
			_user_avatar_data[avatar_key] = texture_path
		elif current_path == texture_path:
			_user_avatar_data[avatar_key] = _get_default_visual_texture_for_key(avatar_key)
		else:
			_user_avatar_data[avatar_key] = texture_path
	else:
		var cloud_item := _get_cloud_catalog_item_by_id(item_id)
		if cloud_item.is_empty() or not _is_cloud_item_owned(cloud_item):
			return
		var clothing_key := _get_cloud_clothing_texture_key(cloud_item)
		if not clothing_key.is_empty():
			_toggle_cloud_clothing_item(item_id, cloud_item, clothing_key)
		else:
			var equipped: Array = _user_avatar_data.get("equipped", [])
			if item_id in equipped:
				equipped.erase(item_id)
			else:
				equipped.append(item_id)
			_user_avatar_data["equipped"] = equipped
	_queue_avatar_sync()
	_group_catalog()
	_refresh_ui()
	_apply_visuals_to_preview_player()


func _get_default_visual_texture_for_key(avatar_key: String) -> String:
	if avatar_key == "face_texture_path":
		return GameState.DEFAULT_FACE_TEXTURE_PATH
	return ""


func _on_category_pressed(category_name: String) -> void:
	current_category = category_name
	_refresh_ui()


func _open_template_picker(template_kind: String) -> void:
	_pending_template_kind = template_kind
	if _show_system_template_picker(template_kind):
		return
	if is_instance_valid(_avatar_file_dialog):
		if OS.has_feature("android"):
			_request_android_media_permissions()
			if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
				_avatar_file_dialog.current_dir = "/storage/emulated/0/Download"
		_avatar_file_dialog.title = "Choose %s template" % template_kind.capitalize()
		_avatar_file_dialog.popup_centered_ratio(0.7)


func _show_system_template_picker(template_kind: String) -> bool:
	if OS.has_feature("android"):
		_request_android_media_permissions()
	if not DisplayServer.has_method("file_dialog_show"):
		return false
	var start_dir := ""
	if OS.has_feature("android"):
		if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
			start_dir = "/storage/emulated/0/Download"
		elif DirAccess.dir_exists_absolute("/storage/emulated/0"):
			start_dir = "/storage/emulated/0"
	var callback := func(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
		if not status or selected_paths.is_empty():
			return
		_on_template_file_selected(str(selected_paths[0]))
	var error: Error = DisplayServer.file_dialog_show(
		"Choose %s template" % template_kind.capitalize(),
		start_dir,
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image files"]),
		callback
	)
	return error == OK


func _on_template_file_selected(source_path: String) -> void:
	if _pending_template_kind.is_empty():
		return
	var saved_path := _copy_template_to_user_storage(source_path, _pending_template_kind)
	if saved_path.is_empty():
		if template_status_label != null:
			template_status_label.text = "Could not import template. Try a PNG or JPG file."
		return
	if _pending_template_kind == "shirt":
		_user_avatar_data["shirt_texture_path"] = saved_path
		_remember_saved_visual_path("saved_shirt_texture_paths", saved_path)
		current_category = "Clothes"
	else:
		_user_avatar_data["pants_texture_path"] = saved_path
		_remember_saved_visual_path("saved_pants_texture_paths", saved_path)
		current_category = "Clothes"
	if template_status_label != null:
		template_status_label.text = "%s template imported and applied." % _pending_template_kind.capitalize()
	_pending_template_kind = ""
	_queue_avatar_sync()
	_group_catalog()
	_refresh_ui()
	_apply_visuals_to_preview_player()


func _remember_saved_visual_path(list_key: String, saved_path: String) -> void:
	var clean_path := saved_path.strip_edges()
	if clean_path.is_empty():
		return
	var paths: Array = []
	var raw_paths: Variant = _user_avatar_data.get(list_key, [])
	if raw_paths is Array:
		paths = (raw_paths as Array).duplicate()
	if not (clean_path in paths):
		paths.append(clean_path)
	_user_avatar_data[list_key] = paths


func _copy_template_to_user_storage(source_path: String, template_kind: String) -> String:
	var result: Dictionary = AVATAR_TEMPLATE_PROCESSOR.import_template_to_user_storage(source_path, template_kind, _get_avatar_template_owner_hint())
	if not bool(result.get("ok", false)):
		push_warning("[AvatarUI] Template import failed: %s" % str(result.get("error", "Unknown error")))
		return ""
	return str(result.get("path", ""))

func _request_android_media_permissions() -> void:
	if not OS.has_feature("android"):
		return
	if OS.has_method("request_permissions"):
		OS.request_permissions()


func _show_template_paths() -> void:
	if template_status_label == null:
		return
	template_status_label.text = "Template references: Shirt: %s | Pants: %s" % [SHIRT_TEMPLATE_REFERENCE_PATH, PANTS_TEMPLATE_REFERENCE_PATH]


func _apply_visuals_to_preview_player() -> void:
	if not is_instance_valid(_preview_player):
		return
	_normalize_avatar_data()
	_preview_player.set("is_ui_preview", true)
	_preview_player.set("use_local_avatar_fallback", false)
	_preview_player.set("render_avatar_visual_decals", true)
	_preview_player.set("render_avatar_clothing_decals", true)
	_preview_player.set("face_texture_path", str(_user_avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)))
	_preview_player.set("chest_badge_texture_path", str(_user_avatar_data.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)))
	_preview_player.set("shirt_texture_path", str(_user_avatar_data.get("shirt_texture_path", "")))
	_preview_player.set("pants_texture_path", str(_user_avatar_data.get("pants_texture_path", "")))
	_preview_player.set("equipped_avatar_items", _get_equipped_avatar_item_payloads())
	for part_variant in BODY_PARTS:
		var part: Dictionary = part_variant
		var avatar_key := str(part.get("key", ""))
		var player_key := str(part.get("player_key", ""))
		if avatar_key.is_empty() or player_key.is_empty():
			continue
		var resolved_color := _resolve_avatar_color_value(_user_avatar_data.get(avatar_key, _get_default_body_color(avatar_key)), _get_default_body_color(avatar_key))
		_preview_player.set(player_key, resolved_color)
	if _preview_player.has_method("_apply_avatar_color_if_needed"):
		_preview_player.call_deferred("_apply_avatar_color_if_needed")
	if _preview_player.has_method("force_avatar_visual_refresh"):
		_preview_player.call_deferred("force_avatar_visual_refresh")
	elif _preview_player.has_method("_apply_avatar_visuals_if_needed"):
		_preview_player.call_deferred("_apply_avatar_visuals_if_needed")


func _queue_avatar_sync() -> void:
	_normalize_avatar_data()
	_sync_cached_equipped_avatar_item_payloads()
	if typeof(UserSession) != TYPE_NIL:
		UserSession.avatar_data = _user_avatar_data.duplicate(true)
		UserSession.inventory_items = _user_inventory_ids.duplicate(true)
		if UserSession.has_method("apply_avatar_to_game_state"):
			UserSession.apply_avatar_to_game_state()
		if UserSession.has_method("save_profile"):
			UserSession.save_profile()
	if is_instance_valid(lobby) and lobby.has_method("_refresh_all_local_avatar_previews_from_session"):
		lobby.call("_refresh_all_local_avatar_previews_from_session")
	if typeof(GameState) != TYPE_NIL and GameState.has_method("apply_avatar_data"):
		GameState.apply_avatar_data(_user_avatar_data)
	if _avatar_sync_in_flight:
		_avatar_sync_pending = true
		return
	_sync_avatar_profile_async.call_deferred()


func _sync_cached_equipped_avatar_item_payloads() -> void:
	var equipped: Array = _user_avatar_data.get("equipped", []) if _user_avatar_data.get("equipped", []) is Array else []
	if equipped.is_empty():
		_user_avatar_data["equipped_avatar_item_payloads"] = []
		return
	var payloads: Array = []
	var seen: Dictionary = {}
	for raw_id in equipped:
		var item_id := str(raw_id).strip_edges()
		if item_id.is_empty() or bool(seen.get(item_id, false)):
			continue
		var item := _get_cloud_catalog_item_by_id(item_id)
		if item.is_empty() or not _is_cloud_item_owned(item):
			continue
		payloads.append(item.duplicate(true))
		seen[item_id] = true
	_user_avatar_data["equipped_avatar_item_payloads"] = payloads


func _sync_avatar_profile_async() -> void:
	_avatar_sync_in_flight = true
	var cloud_api := _get_cloud_api()
	if cloud_api != null and cloud_api.has_method("update_profile_avatar"):
		await cloud_api.update_profile_avatar(_user_avatar_data, _user_inventory_ids)
	if cloud_api != null and cloud_api.has_method("update_avatar_outfit"):
		await cloud_api.update_avatar_outfit(_build_avatar_outfit_payload())
	_avatar_sync_in_flight = false
	if _avatar_sync_pending:
		_avatar_sync_pending = false
		_sync_avatar_profile_async.call_deferred()


func _build_avatar_outfit_payload() -> Dictionary:
	var equipped_items: Array = _get_owned_equipped_item_ids(_is_cloud_ownership_context_ready())
	var saved_shirt_paths: Array = []
	var raw_saved_shirts: Variant = _user_avatar_data.get("saved_shirt_texture_paths", [])
	if raw_saved_shirts is Array:
		saved_shirt_paths = (raw_saved_shirts as Array).duplicate(true)
	var saved_pants_paths: Array = []
	var raw_saved_pants: Variant = _user_avatar_data.get("saved_pants_texture_paths", [])
	if raw_saved_pants is Array:
		saved_pants_paths = (raw_saved_pants as Array).duplicate(true)
	var payload := {
		"head_color": _avatar_color_to_hex("head"),
		"torso_color": _avatar_color_to_hex("torso"),
		"left_arm_color": _avatar_color_to_hex("left_arm"),
		"right_arm_color": _avatar_color_to_hex("right_arm"),
		"left_leg_color": _avatar_color_to_hex("left_leg"),
		"right_leg_color": _avatar_color_to_hex("right_leg"),
		"equipped_items": equipped_items,
		"body_type": "R6",
		"face_texture_path": str(_user_avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)),
		"chest_badge_texture_path": str(_user_avatar_data.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)),
		"shirt_texture_path": str(_user_avatar_data.get("shirt_texture_path", "")),
		"pants_texture_path": str(_user_avatar_data.get("pants_texture_path", "")),
		"saved_shirt_texture_paths": saved_shirt_paths,
		"saved_pants_texture_paths": saved_pants_paths
	}
	return payload


func _avatar_color_to_hex(part_key: String) -> String:
	var color := _resolve_avatar_color_value(
		_user_avatar_data.get(part_key, _get_default_body_color(part_key)),
		_get_default_body_color(part_key)
	)
	return "#" + color.to_html(false)


func _load_texture_for_item(item: Dictionary) -> Texture2D:
	for candidate in _get_item_texture_candidates(item):
		var texture := _load_texture_from_any_path(str(candidate))
		if texture is Texture2D:
			return texture
	return null


func _get_item_texture_candidates(item: Dictionary) -> Array:
	var candidates: Array = []
	for key in ["thumbnail_path", "thumbnail_url", "thumbnail", "texture_path", "template_url", "image_path", "icon_path"]:
		var candidate := str(item.get(key, ""))
		if not candidate.is_empty():
			candidates.append(candidate)
	var item_data := _get_cloud_item_data(item)
	for key in ["thumbnail_path", "thumbnail_url", "thumbnail", "texture_path", "template_url", "atlas_path", "image_path", "icon_path"]:
		var candidate := str(item_data.get(key, ""))
		if not candidate.is_empty():
			candidates.append(candidate)
	return candidates


func _load_texture_from_any_path(path: String) -> Texture2D:
	if path.begins_with("http://") or path.begins_with("https://"):
		var cached: Texture2D = _remote_item_texture_cache.get(path, null) as Texture2D
		return cached
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is Texture2D:
				return res
		var image_res := Image.new()
		if image_res.load(path) == OK:
			return _make_item_preview_texture(image_res)
		return null
	if path.begins_with("user://"):
		var image := Image.new()
		if image.load(path) != OK:
			return null
		return _make_item_preview_texture(image)
	if FileAccess.file_exists(path):
		var image_file := Image.new()
		if image_file.load(path) != OK:
			return null
		return _make_item_preview_texture(image_file)
	return null


func _load_remote_texture_for_item_async(item: Dictionary, target: TextureRect) -> void:
	if target == null:
		return
	for candidate in _get_item_texture_candidates(item):
		var url := str(candidate).strip_edges()
		if not (url.begins_with("http://") or url.begins_with("https://")):
			continue
		if _remote_item_texture_cache.has(url):
			target.texture = _remote_item_texture_cache[url]
			return
		if bool(_remote_item_texture_loading.get(url, false)):
			return
		_remote_item_texture_loading[url] = true
		var request := HTTPRequest.new()
		if is_instance_valid(lobby):
			lobby.add_child(request)
		else:
			_remote_item_texture_loading.erase(url)
			return
		var err := request.request(url)
		if err != OK:
			_remote_item_texture_loading.erase(url)
			request.queue_free()
			return
		request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			_remote_item_texture_loading.erase(url)
			if is_instance_valid(request):
				request.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
				return
			var image := Image.new()
			if image.load_png_from_buffer(body) != OK:
				if image.load_jpg_from_buffer(body) != OK and image.load_webp_from_buffer(body) != OK:
					return
			var texture := _make_item_preview_texture(image)
			if texture == null:
				return
			_remote_item_texture_cache[url] = texture
			if is_instance_valid(target):
				target.texture = texture
		)
		return

func _make_item_preview_texture(source: Image) -> Texture2D:
	if source == null or source.is_empty():
		return null
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var longest_side: int = maxi(image.get_width(), image.get_height())
	if longest_side > 1024:
		var ratio: float = 1024.0 / float(longest_side)
		image.resize(maxi(1, roundi(float(image.get_width()) * ratio)), maxi(1, roundi(float(image.get_height()) * ratio)), Image.INTERPOLATE_LANCZOS)
	image = _crop_item_preview_to_subject(image)
	image.resize(AVATAR_ITEM_PREVIEW_TEXTURE_SIZE, AVATAR_ITEM_PREVIEW_TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

func _crop_item_preview_to_subject(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var width := image.get_width()
	var height := image.get_height()
	if width <= 8 or height <= 8:
		return image
	var bg := image.get_pixel(0, 0)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(height):
		for x in range(width):
			var c := image.get_pixel(x, y)
			if c.a <= 0.04:
				continue
			var delta: float = absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			if delta < 0.12 and c.a >= 0.98:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return image
	var subject_width := max_x - min_x + 1
	var subject_height := max_y - min_y + 1
	if subject_width <= 4 or subject_height <= 4:
		return image
	var padding := maxi(8, roundi(float(maxi(subject_width, subject_height)) * 0.12))
	var crop_x := maxi(0, min_x - padding)
	var crop_y := maxi(0, min_y - padding)
	var crop_w := mini(width - crop_x, subject_width + padding * 2)
	var crop_h := mini(height - crop_y, subject_height + padding * 2)
	var square := maxi(crop_w, crop_h)
	var extra_x := int(maxi(0, square - crop_w) / 2)
	var extra_y := int(maxi(0, square - crop_h) / 2)
	crop_x = clampi(crop_x - extra_x, 0, maxi(0, width - square))
	crop_y = clampi(crop_y - extra_y, 0, maxi(0, height - square))
	square = mini(square, mini(width - crop_x, height - crop_y))
	if square <= 0:
		return image
	if square >= mini(width, height) - 2:
		return image
	return image.get_region(Rect2i(crop_x, crop_y, square, square))


func _get_cloud_catalog_item_by_id(item_id: String) -> Dictionary:
	var clean_id := item_id.strip_edges()
	if clean_id.is_empty():
		return {}
	for raw_item in _get_avatar_item_payloads_from_avatar_data():
		if raw_item is Dictionary and str((raw_item as Dictionary).get("id", (raw_item as Dictionary).get("item_id", ""))).strip_edges() == clean_id:
			return (raw_item as Dictionary)
	for raw_item in _cloud_catalog:
		if raw_item is Dictionary and str((raw_item as Dictionary).get("id", (raw_item as Dictionary).get("item_id", ""))).strip_edges() == clean_id:
			return (raw_item as Dictionary)
	return {}


func _get_avatar_item_payloads_from_avatar_data() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for list_key in ["owned_avatar_item_payloads", "equipped_avatar_item_payloads"]:
		var raw_list: Variant = _user_avatar_data.get(list_key, [])
		if not (raw_list is Array):
			continue
		for raw_payload in (raw_list as Array):
			if not (raw_payload is Dictionary):
				continue
			var payload := (raw_payload as Dictionary).duplicate(true)
			var payload_id := str(payload.get("id", payload.get("item_id", ""))).strip_edges()
			if payload_id.is_empty() or bool(seen.get(payload_id, false)):
				continue
			payload["id"] = payload_id
			payload["item_id"] = payload_id
			if not payload.has("owned"):
				payload["owned"] = true
			result.append(payload)
			seen[payload_id] = true
	return result


func _is_cloud_ownership_context_ready() -> bool:
	return _cloud_inventory_loaded or not _cloud_catalog.is_empty() or not _get_avatar_item_payloads_from_avatar_data().is_empty()


func _sanitize_equipped_avatar_item_ids() -> bool:
	var before: Array = _user_avatar_data.get("equipped", []) if _user_avatar_data.get("equipped", []) is Array else []
	var after := _get_owned_equipped_item_ids(true)
	return before != after


func _get_owned_equipped_item_ids(sanitize_avatar_data: bool) -> Array:
	var equipped: Array = _user_avatar_data.get("equipped", []) if _user_avatar_data.get("equipped", []) is Array else []
	var resolved: Array = []
	if not _is_cloud_ownership_context_ready():
		for raw_id in equipped:
			var pending_id := str(raw_id).strip_edges()
			if not pending_id.is_empty() and not (pending_id in resolved):
				resolved.append(pending_id)
		return resolved
	for raw_id in equipped:
		var item_id := str(raw_id).strip_edges()
		if item_id.is_empty() or item_id in resolved:
			continue
		var item := _get_cloud_catalog_item_by_id(item_id)
		if item.is_empty() or not _is_cloud_item_owned(item):
			continue
		resolved.append(item_id)
	if sanitize_avatar_data and resolved != equipped:
		_user_avatar_data["equipped"] = resolved.duplicate()
	_sync_cached_equipped_avatar_item_payloads()
	return resolved


func _is_cloud_item_owned(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
	if item_id.is_empty():
		return false
	if item_id in _user_inventory_ids:
		return true
	if typeof(UserSession) != TYPE_NIL and UserSession.inventory_items is Array and item_id in UserSession.inventory_items:
		return true
	if bool(item.get("owned", false)):
		return true
	var current_user_id := _get_current_user_id()
	return not current_user_id.is_empty() and str(item.get("owner_id", "")).strip_edges() == current_user_id


func _toggle_cloud_clothing_item(item_id: String, item: Dictionary, clothing_key: String) -> void:
	var texture_path := _get_cloud_clothing_texture_path(item)
	if texture_path.is_empty():
		return
	var equipped: Array = _user_avatar_data.get("equipped", [])
	if str(_user_avatar_data.get(clothing_key, "")) == texture_path:
		_user_avatar_data[clothing_key] = ""
		equipped.erase(item_id)
	else:
		_user_avatar_data[clothing_key] = texture_path
		for raw_equipped in equipped.duplicate():
			var equipped_id := str(raw_equipped)
			var equipped_item := _get_cloud_catalog_item_by_id(equipped_id)
			if _get_cloud_clothing_texture_key(equipped_item) == clothing_key:
				equipped.erase(raw_equipped)
		if not (item_id in equipped):
			equipped.append(item_id)
		var list_key := "saved_shirt_texture_paths" if clothing_key == "shirt_texture_path" else "saved_pants_texture_paths"
		_forget_saved_visual_path(list_key, texture_path)
	_user_avatar_data["equipped"] = equipped


func _forget_saved_visual_path(list_key: String, saved_path: String) -> void:
	var clean_path := saved_path.strip_edges()
	if clean_path.is_empty():
		return
	var raw_paths: Variant = _user_avatar_data.get(list_key, [])
	var paths: Array = []
	if raw_paths is Array:
		for raw_path in raw_paths:
			var candidate := str(raw_path).strip_edges()
			if candidate.is_empty() or candidate == clean_path:
				continue
			if not (candidate in paths):
				paths.append(candidate)
	_user_avatar_data[list_key] = paths


func _is_owned_cloud_clothing_texture_path(texture_path: String) -> bool:
	var clean_path := texture_path.strip_edges()
	if clean_path.is_empty():
		return false
	for raw_item in _cloud_catalog:
		if not (raw_item is Dictionary):
			continue
		var item := raw_item as Dictionary
		if not _is_cloud_item_owned(item):
			continue
		if _get_cloud_clothing_texture_path(item) == clean_path:
			return true
	return false


func _get_cloud_clothing_texture_key(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var item_data := _get_cloud_item_data(item)
	var kind := str(item.get("category", item.get("type", ""))).strip_edges().to_lower()
	if kind.is_empty() or kind in ["avatar_item", "avatar_items", "avatar items", "item"]:
		kind = str(item_data.get("item_kind", item_data.get("category", item_data.get("kind", "")))).strip_edges().to_lower()
	if kind in ["shirt", "shirts", "tshirt", "t-shirt", "tee"]:
		return "shirt_texture_path"
	if kind in ["pants", "pant", "trousers", "legs"]:
		return "pants_texture_path"
	return ""


func _get_cloud_clothing_texture_path(item: Dictionary) -> String:
	var item_data := _get_cloud_item_data(item)
	for key in ["texture_path", "template_url", "atlas_path", "source_url"]:
		var value := str(item_data.get(key, item.get(key, ""))).strip_edges()
		if not value.is_empty():
			return value
	return ""


func _get_cloud_item_data(item: Dictionary) -> Dictionary:
	var data: Variant = item.get("data", {})
	if data is Dictionary:
		return (data as Dictionary)
	if data is String:
		var parsed: Variant = JSON.parse_string((data as String).strip_edges())
		if parsed is Dictionary:
			return parsed as Dictionary
	return {}


func _get_current_user_id() -> String:
	if typeof(UserSession) != TYPE_NIL:
		return str(UserSession.user_id).strip_edges()
	var cloud_api := _get_cloud_api()
	if cloud_api != null and cloud_api.has_method("get_current_user_id"):
		return str(cloud_api.get_current_user_id()).strip_edges()
	return ""


func _get_avatar_template_owner_hint() -> String:
	if typeof(UserSession) != TYPE_NIL:
		if UserSession.is_logged_in and not str(UserSession.user_id).strip_edges().is_empty():
			return str(UserSession.user_id)
		return str(UserSession.username)
	return "local"


func _get_cloud_api() -> Node:
	if Engine.get_main_loop() == null:
		return null
	var root: Window = Engine.get_main_loop().root
	return root.get_node_or_null("CloudAPI")


func _make_panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _get_default_body_color(part_key: String) -> Color:
	match part_key:
		"head", "left_arm", "right_arm":
			return Color(0.96, 0.8, 0.2)
		"torso":
			return Color(0.05, 0.4, 0.7)
		"left_leg", "right_leg":
			return Color(0.65, 0.8, 0.2)
		_:
			return Color.WHITE


func _resolve_avatar_color_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Dictionary:
		var data := value as Dictionary
		return Color(
			float(data.get("r", fallback.r)),
			float(data.get("g", fallback.g)),
			float(data.get("b", fallback.b)),
			float(data.get("a", fallback.a))
		)
	var text := str(value).strip_edges()
	if text.begins_with("#") and (text.length() == 7 or text.length() == 9):
		return Color.html(text)
	return fallback


func _on_body_part_pressed(part_key: String) -> void:
	if part_key.is_empty():
		return
	_selected_body_part_key = part_key
	_refresh_body_controls()


func _on_palette_color_pressed(color: Color) -> void:
	if _selected_body_part_key.is_empty():
		_selected_body_part_key = "torso"
	var player_key := ""
	for part_variant in BODY_PARTS:
		var part: Dictionary = part_variant
		if str(part.get("key", "")) == _selected_body_part_key:
			player_key = str(part.get("player_key", ""))
			break
	_user_avatar_data[_selected_body_part_key] = color
	if not player_key.is_empty():
		_user_avatar_data[player_key] = color
	_queue_avatar_sync()
	_refresh_body_controls()
	_apply_visuals_to_preview_player()


func _refresh_body_controls() -> void:
	if not is_instance_valid(self):
		return
	if _selected_body_part_key.is_empty():
		_selected_body_part_key = "torso"
	for part_key in _body_part_buttons.keys():
		var button = _body_part_buttons[part_key]
		if not is_instance_valid(button):
			continue
		button.button_pressed = str(part_key) == _selected_body_part_key
		var current_color := _resolve_avatar_color_value(
			_user_avatar_data.get(part_key, _get_default_body_color(part_key)),
			_get_default_body_color(part_key)
		)
		var is_selected := str(part_key) == _selected_body_part_key
		var border_color := Color(0.0, 0.48, 0.82, 1) if is_selected else Color(0.6, 0.6, 0.6, 1)
		var border_width := 3 if is_selected else 1
		button.add_theme_stylebox_override("normal", _make_panel_style(current_color, border_color, border_width, 3))
		button.add_theme_stylebox_override("pressed", _make_panel_style(current_color.darkened(0.1), Color(0.0, 0.48, 0.82, 1), 3, 3))
		button.add_theme_stylebox_override("hover", _make_panel_style(current_color.lightened(0.1), Color(0.0, 0.48, 0.82, 1), 2, 3))
		button.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	var selected_color := _resolve_avatar_color_value(
		_user_avatar_data.get(_selected_body_part_key, _get_default_body_color(_selected_body_part_key)),
		_get_default_body_color(_selected_body_part_key)
	)
	for raw_entry in _palette_buttons:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var swatch = entry.get("button", null)
		if not is_instance_valid(swatch):
			continue
		var color := entry.get("color", Color.WHITE) as Color
		_apply_swatch_style(swatch, color, _colors_close(color, selected_color))
	if is_instance_valid(body_select_status_label):
		body_select_status_label.text = "Selected: %s. Pick a color and it saves to your avatar." % _get_selected_body_label()


func _get_selected_body_label() -> String:
	for part_variant in BODY_PARTS:
		var part: Dictionary = part_variant
		if str(part.get("key", "")) == _selected_body_part_key:
			return str(part.get("label", "Body"))
	return "Body"


func _apply_swatch_style(button: Button, color: Color, selected: bool) -> void:
	button.text = ""
	var border := Color(0.04, 0.48, 0.82, 1) if selected else Color(0.25, 0.25, 0.25, 0.65)
	var border_width := 3 if selected else 1
	button.add_theme_stylebox_override("normal", _make_panel_style(color, border, border_width, 3))
	button.add_theme_stylebox_override("hover", _make_panel_style(color.lightened(0.08), Color(0.04, 0.48, 0.82, 1), 2, 3))
	button.add_theme_stylebox_override("pressed", _make_panel_style(color.darkened(0.08), Color(0.04, 0.48, 0.82, 1), 3, 3))


func _colors_close(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.02 and abs(a.g - b.g) < 0.02 and abs(a.b - b.b) < 0.02 and abs(a.a - b.a) < 0.02


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _find_child_recursive(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_child_recursive(child, target_name)
		if found != null:
			return found
	return null
