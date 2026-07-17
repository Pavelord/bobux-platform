class_name RobloxInventoryController
extends CanvasLayer

signal inventory_visibility_changed(visible: bool)
signal selected_tool_changed(tool: Node)

const MAX_HOTBAR_SLOTS: int = 10
const REFRESH_INTERVAL_SECONDS: float = 0.20
const DESKTOP_SLOT_SIZE := Vector2(62.0, 62.0)
const MOBILE_SLOT_SIZE := Vector2(52.0, 52.0)

var _lua_engine: Node = null
var _context_node: Node = null
var _character_provider: Callable = Callable()
var _refresh_accumulator: float = 0.0
var _inventory_signature: String = ""
var _tool_by_instance_id: Dictionary = {}
var _equipped_tool_id: int = 0

var _root: Control = null
var _hotbar: HBoxContainer = null
var _inventory_panel: Panel = null
var _inventory_grid: GridContainer = null
var _empty_label: Label = null
var _mobile_use_button: Button = null


func configure(lua_engine: Node, context_node: Node, character_provider: Callable = Callable()) -> void:
	_lua_engine = lua_engine
	_context_node = context_node
	_character_provider = character_provider
	if is_inside_tree():
		refresh_now(true)


func _ready() -> void:
	name = "RobloxInventoryController"
	layer = 9
	_build_interface()
	set_process(true)
	set_process_unhandled_input(true)
	refresh_now(true)


func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator < REFRESH_INTERVAL_SECONDS:
		return
	_refresh_accumulator = 0.0
	refresh_now(false)


func _unhandled_input(event: InputEvent) -> void:
	if _is_text_input_focused():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_QUOTELEFT:
			toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		var slot_index := _slot_index_for_key(key_event.keycode)
		if slot_index >= 0:
			_activate_hotbar_slot(slot_index)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _equipped_tool_id > 0:
			activate_equipped_tool()
	elif event is InputEventScreenTouch:
		# Touch activation has a dedicated button so camera drags never fire tools.
		return


func toggle_inventory() -> void:
	set_inventory_visible(not is_inventory_visible())


func set_inventory_visible(value: bool) -> void:
	if _inventory_panel == null:
		return
	_inventory_panel.visible = value
	if value:
		refresh_now(true)
	inventory_visibility_changed.emit(value)


func is_inventory_visible() -> bool:
	return _inventory_panel != null and _inventory_panel.visible


func refresh_now(force_rebuild: bool = false) -> void:
	if _lua_engine == null or not is_instance_valid(_lua_engine) or not _lua_engine.has_method("get_local_inventory_state"):
		return
	var context := _context_node if is_instance_valid(_context_node) else get_tree().current_scene
	var character: Node = null
	if not _character_provider.is_null() and _character_provider.is_valid():
		var candidate: Variant = _character_provider.call()
		if candidate is Node and is_instance_valid(candidate):
			character = candidate as Node
	var state_variant: Variant = _lua_engine.call("get_local_inventory_state", context, character)
	if not (state_variant is Dictionary):
		return
	var state := state_variant as Dictionary
	var tools: Array = state.get("tools", []) if state.get("tools", []) is Array else []
	var equipped: Node = state.get("equipped_tool", null) as Node
	var signature_parts: Array[String] = []
	_tool_by_instance_id.clear()
	for tool_variant in tools:
		if not (tool_variant is Node) or not is_instance_valid(tool_variant):
			continue
		var tool := tool_variant as Node
		var tool_id := tool.get_instance_id()
		_tool_by_instance_id[tool_id] = tool
		signature_parts.append("%d:%s:%d" % [tool_id, str(tool.name), tool.get_parent().get_instance_id() if tool.get_parent() != null else 0])
	_equipped_tool_id = equipped.get_instance_id() if equipped != null and is_instance_valid(equipped) else 0
	var signature := "|".join(signature_parts) + "#%d" % _equipped_tool_id
	if not force_rebuild and signature == _inventory_signature:
		return
	_inventory_signature = signature
	_rebuild_hotbar(tools)
	_rebuild_inventory_grid(tools)
	if _mobile_use_button != null:
		_mobile_use_button.visible = _equipped_tool_id > 0 and DisplayServer.is_touchscreen_available()


func activate_equipped_tool() -> bool:
	if _equipped_tool_id <= 0 or not _tool_by_instance_id.has(_equipped_tool_id):
		return false
	var tool := _tool_by_instance_id[_equipped_tool_id] as Node
	if tool == null or not is_instance_valid(tool) or not _lua_engine.has_method("activate_local_tool"):
		return false
	return bool(_lua_engine.call("activate_local_tool", tool, _context_node))


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "InventoryRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_hotbar = HBoxContainer.new()
	_hotbar.name = "Hotbar"
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	_hotbar.offset_left = -360.0
	_hotbar.offset_right = 360.0
	_hotbar.offset_top = -78.0
	_hotbar.offset_bottom = -10.0
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_hotbar)

	_inventory_panel = Panel.new()
	_inventory_panel.name = "BackpackPanel"
	_inventory_panel.anchor_left = 0.5
	_inventory_panel.anchor_right = 0.5
	_inventory_panel.anchor_top = 0.5
	_inventory_panel.anchor_bottom = 0.5
	_inventory_panel.offset_left = -280.0
	_inventory_panel.offset_right = 280.0
	_inventory_panel.offset_top = -220.0
	_inventory_panel.offset_bottom = 210.0
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_inventory_panel)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 18.0
	content.offset_top = 14.0
	content.offset_right = -18.0
	content.offset_bottom = -16.0
	content.add_theme_constant_override("separation", 10)
	_inventory_panel.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close inventory"
	close_button.custom_minimum_size = Vector2(38.0, 34.0)
	close_button.pressed.connect(set_inventory_visible.bind(false))
	header.add_child(close_button)

	var hint := Label.new()
	hint.text = "Select a tool to equip it. Press the same slot again to unequip."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#B8BDC6"))
	content.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 4
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", 8)
	_inventory_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_inventory_grid)

	_empty_label = Label.new()
	_empty_label.text = "Backpack is empty"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.custom_minimum_size = Vector2(0.0, 120.0)
	_inventory_grid.add_child(_empty_label)

	_mobile_use_button = Button.new()
	_mobile_use_button.name = "UseEquippedTool"
	_mobile_use_button.text = "USE"
	_mobile_use_button.anchor_left = 1.0
	_mobile_use_button.anchor_right = 1.0
	_mobile_use_button.anchor_top = 1.0
	_mobile_use_button.anchor_bottom = 1.0
	_mobile_use_button.offset_left = -154.0
	_mobile_use_button.offset_right = -76.0
	_mobile_use_button.offset_top = -172.0
	_mobile_use_button.offset_bottom = -94.0
	_mobile_use_button.visible = false
	_mobile_use_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_mobile_use_button.pressed.connect(activate_equipped_tool)
	_root.add_child(_mobile_use_button)


func _rebuild_hotbar(tools: Array) -> void:
	if _hotbar == null:
		return
	for child in _hotbar.get_children():
		_hotbar.remove_child(child)
		child.queue_free()
	var slot_size := MOBILE_SLOT_SIZE if DisplayServer.is_touchscreen_available() else DESKTOP_SLOT_SIZE
	var visible_count := mini(tools.size(), MAX_HOTBAR_SLOTS)
	_hotbar.visible = visible_count > 0
	for index in range(visible_count):
		var tool := tools[index] as Node
		if tool == null or not is_instance_valid(tool):
			continue
		var button := Button.new()
		button.name = "Slot%d" % (index + 1)
		button.text = "%d\n%s" % [(index + 1) % 10, _display_tool_name(tool)]
		button.tooltip_text = str(tool.get_meta("ToolTip", tool.name))
		button.custom_minimum_size = slot_size
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_stylebox_override("normal", _slot_style(tool.get_instance_id() == _equipped_tool_id, false))
		button.add_theme_stylebox_override("hover", _slot_style(tool.get_instance_id() == _equipped_tool_id, true))
		button.pressed.connect(_on_tool_pressed.bind(tool.get_instance_id()))
		_hotbar.add_child(button)


func _rebuild_inventory_grid(tools: Array) -> void:
	if _inventory_grid == null:
		return
	for child in _inventory_grid.get_children():
		_inventory_grid.remove_child(child)
		child.queue_free()
	_empty_label = null
	if tools.is_empty():
		_empty_label = Label.new()
		_empty_label.text = "Backpack is empty"
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.custom_minimum_size = Vector2(480.0, 120.0)
		_inventory_grid.add_child(_empty_label)
		return
	for tool_variant in tools:
		var tool := tool_variant as Node
		if tool == null or not is_instance_valid(tool):
			continue
		var button := Button.new()
		button.text = _display_tool_name(tool)
		button.tooltip_text = str(tool.get_meta("ToolTip", tool.name))
		button.custom_minimum_size = Vector2(122.0, 74.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_stylebox_override("normal", _slot_style(tool.get_instance_id() == _equipped_tool_id, false))
		button.add_theme_stylebox_override("hover", _slot_style(tool.get_instance_id() == _equipped_tool_id, true))
		button.pressed.connect(_on_tool_pressed.bind(tool.get_instance_id()))
		_inventory_grid.add_child(button)


func _on_tool_pressed(tool_instance_id: int) -> void:
	if not _tool_by_instance_id.has(tool_instance_id) or _lua_engine == null:
		return
	var tool := _tool_by_instance_id[tool_instance_id] as Node
	if tool == null or not is_instance_valid(tool):
		return
	var character: Node = null
	if not _character_provider.is_null() and _character_provider.is_valid():
		var candidate: Variant = _character_provider.call()
		if candidate is Node and is_instance_valid(candidate):
			character = candidate as Node
	var changed := false
	if tool_instance_id == _equipped_tool_id and _lua_engine.has_method("unequip_local_tool"):
		changed = bool(_lua_engine.call("unequip_local_tool", tool, _context_node))
	elif _lua_engine.has_method("equip_local_tool"):
		changed = bool(_lua_engine.call("equip_local_tool", tool, _context_node, character))
	if changed:
		_inventory_signature = ""
		refresh_now(true)
		selected_tool_changed.emit(tool if tool_instance_id != _equipped_tool_id else null)


func _activate_hotbar_slot(slot_index: int) -> void:
	if _hotbar == null or slot_index < 0 or slot_index >= _hotbar.get_child_count():
		return
	var button := _hotbar.get_child(slot_index) as Button
	if button != null:
		button.pressed.emit()


func _slot_index_for_key(keycode: Key) -> int:
	match keycode:
		KEY_1: return 0
		KEY_2: return 1
		KEY_3: return 2
		KEY_4: return 3
		KEY_5: return 4
		KEY_6: return 5
		KEY_7: return 6
		KEY_8: return 7
		KEY_9: return 8
		KEY_0: return 9
	return -1


func _display_tool_name(tool: Node) -> String:
	var display_name := str(tool.get_meta("Name", tool.name)).strip_edges()
	if display_name.is_empty():
		display_name = "Tool"
	return display_name.left(16)


func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit or focused is CodeEdit


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.082, 0.094, 0.96)
	style.border_color = Color(0.28, 0.30, 0.34, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _slot_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.17, 0.96) if not hovered else Color(0.19, 0.20, 0.23, 0.98)
	style.border_color = Color("#2B9EE8") if selected else Color(0.38, 0.40, 0.44, 0.95)
	style.set_border_width_all(3 if selected else 1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
