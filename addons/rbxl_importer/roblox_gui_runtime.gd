extends RefCounted

const DEFAULT_ROOT_NAME: String = "RobloxGuiRuntime"
const DEFAULT_GROUP_NAME: String = "roblox_gui_runtime"
const HOTBAR_NAME: String = "RobloxToolHotbar"

static func clear_from(parent: Node, root_name: String = DEFAULT_ROOT_NAME) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		if child.name == root_name or child.is_in_group(DEFAULT_GROUP_NAME):
			child.queue_free()


static func apply_manifest(parent: Node, manifest_variant: Variant, options: Dictionary = {}) -> Control:
	if parent == null:
		return null
	var runtime_options := options.duplicate(true)
	var root_name := str(options.get("root_name", DEFAULT_ROOT_NAME))
	if bool(options.get("replace", true)):
		clear_from(parent, root_name)
	if not (manifest_variant is Dictionary):
		return null
	var parent_control := parent as Control
	if parent_control != null:
		parent_control.clip_contents = true
		if (bool(runtime_options.get("editor_preview", false)) or bool(runtime_options.get("fit_to_viewport", false))) and not runtime_options.has("gui_offset_scale"):
			var parent_size := parent_control.size
			if parent_size.x > 16.0 and parent_size.y > 16.0:
				var design_size := _vector2_from_variant(runtime_options.get("design_size", [1366.0, 768.0]), Vector2(1366.0, 768.0))
				runtime_options["gui_offset_scale"] = clampf(minf(parent_size.x / maxf(design_size.x, 1.0), parent_size.y / maxf(design_size.y, 1.0)), 0.42, 1.0)
	var manifest: Dictionary = manifest_variant
	var root := Control.new()
	root.name = root_name
	root.add_to_group(DEFAULT_GROUP_NAME)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE if bool(options.get("ignore_mouse", true)) else Control.MOUSE_FILTER_PASS
	root.z_index = int(options.get("z_index", 200))
	parent.add_child(root)
	var gui_count := 0
	var tool_count := 0
	if bool(runtime_options.get("draw_gui", true)):
		gui_count = _build_gui_tree(root, manifest, runtime_options)
	if bool(runtime_options.get("draw_tools", true)):
		tool_count = _build_tool_hotbar(root, manifest, runtime_options)
	root.set_meta("built_gui_controls", gui_count)
	root.set_meta("built_tool_controls", tool_count)
	return root


static func _build_gui_tree(root: Control, manifest: Dictionary, options: Dictionary) -> int:
	var gui_list: Array = manifest.get("gui", []) if manifest.get("gui", []) is Array else []
	if gui_list.is_empty():
		return 0
	var edges: Array = manifest.get("hierarchy", []) if manifest.get("hierarchy", []) is Array else []
	var parent_by_ref := _build_parent_map(edges)
	var services_by_ref := _build_service_map(manifest)
	var gui_by_ref: Dictionary = {}
	for entry_variant in gui_list:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var ref := _normalize_ref(entry.get("ref", ""))
		if not ref.is_empty():
			gui_by_ref[ref] = entry
	var built: Dictionary = {}
	var built_visual_count := 0
	var pass_count := 0
	while built.size() < gui_by_ref.size() and pass_count < 16:
		var progressed := false
		for ref_variant in gui_by_ref.keys():
			var ref := str(ref_variant)
			if built.has(ref):
				continue
			var entry: Dictionary = gui_by_ref[ref]
			if not _belongs_to_starter_gui_entry(entry, ref, parent_by_ref, services_by_ref):
				built[ref] = true
				continue
			var roblox_class := str(entry.get("class", "GuiObject"))
			if not _is_visual_gui_class(roblox_class):
				built[ref] = true
				continue
			var parent_control: Control = root
			var parent_ref := _normalize_ref(entry.get("parent_ref", parent_by_ref.get(ref, "")))
			if not parent_ref.is_empty() and gui_by_ref.has(parent_ref):
				if not built.has(parent_ref):
					continue
				var candidate := root.find_child(_node_name_for_ref(parent_ref), true, false) as Control
				if candidate != null:
					parent_control = candidate
			var control := _create_control_for_entry(entry, options)
			parent_control.add_child(control)
			built[ref] = true
			built_visual_count += 1
			progressed = true
		if not progressed:
			break
		pass_count += 1
	_apply_gui_decorators(root, gui_by_ref, parent_by_ref, options)
	return built_visual_count


static func _build_tool_hotbar(root: Control, manifest: Dictionary, options: Dictionary) -> int:
	var tools: Array = manifest.get("tools", []) if manifest.get("tools", []) is Array else []
	if tools.is_empty():
		return 0
	var edges: Array = manifest.get("hierarchy", []) if manifest.get("hierarchy", []) is Array else []
	var parent_by_ref := _build_parent_map(edges)
	var services_by_ref := _build_service_map(manifest)
	var starter_tools: Array[Dictionary] = []
	for tool_variant in tools:
		if not (tool_variant is Dictionary):
			continue
		var tool_data: Dictionary = tool_variant
		var ref := str(tool_data.get("ref", "")).strip_edges()
		if _belongs_to_service(ref, parent_by_ref, services_by_ref, ["StarterPack", "Backpack"]):
			starter_tools.append(tool_data)
	# Old manifests did not describe services. Keep their limited compatibility
	# fallback, but never expose ServerStorage tools from a scoped place manifest.
	if starter_tools.is_empty() and services_by_ref.is_empty():
		for tool_variant in tools:
			if tool_variant is Dictionary:
				starter_tools.append(tool_variant)
			if starter_tools.size() >= 10:
				break
	if starter_tools.is_empty():
		return 0
	var hotbar := HBoxContainer.new()
	hotbar.name = HOTBAR_NAME
	hotbar.anchor_left = 0.5
	hotbar.anchor_right = 0.5
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = -260.0
	hotbar.offset_right = 260.0
	hotbar.offset_top = -82.0
	hotbar.offset_bottom = -18.0
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar.add_theme_constant_override("separation", 6)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE if bool(options.get("ignore_mouse", true)) else Control.MOUSE_FILTER_PASS
	root.add_child(hotbar)
	var max_tools: int = mini(starter_tools.size(), 10)
	for i in range(max_tools):
		var tool_data: Dictionary = starter_tools[i]
		var btn := Button.new()
		btn.name = "Tool_%d" % (i + 1)
		btn.text = "%d\n%s" % [i + 1, str(tool_data.get("name", "Tool")).left(14)]
		btn.custom_minimum_size = Vector2(50, 58)
		btn.disabled = bool(options.get("editor_preview", false))
		btn.tooltip_text = str(tool_data.get("name", "Tool"))
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if bool(options.get("ignore_mouse", true)) else Control.MOUSE_FILTER_STOP
		btn.set_meta("roblox_ref", _normalize_ref(tool_data.get("ref", "")))
		btn.set_meta("roblox_class", "Tool")
		_apply_button_style(btn, Color(0.12, 0.12, 0.13, 0.82), Color(0.75, 0.75, 0.78, 0.95), Color.WHITE)
		hotbar.add_child(btn)
	return max_tools


static func _create_control_for_entry(entry: Dictionary, options: Dictionary) -> Control:
	var roblox_class := str(entry.get("class", "Frame"))
	var props: Dictionary = entry.get("properties", {}) if entry.get("properties", {}) is Dictionary else {}
	var control: Control
	match roblox_class:
		"ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup":
			control = Control.new()
			control.clip_contents = true
		"TextButton":
			control = Button.new()
			(control as Button).text = str(props.get("Text", entry.get("name", "Button")))
			(control as Button).disabled = bool(options.get("editor_preview", false))
		"TextBox":
			control = LineEdit.new()
			(control as LineEdit).text = str(props.get("Text", ""))
			(control as LineEdit).editable = not bool(options.get("editor_preview", false))
		"TextLabel":
			control = Label.new()
			(control as Label).text = str(props.get("Text", entry.get("name", "")))
			(control as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			(control as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		"ImageLabel", "ImageButton":
			control = _make_image_control(entry, props, options)
		"ScrollingFrame":
			control = ScrollContainer.new()
		_:
			control = Panel.new()
	var normalized_ref := _normalize_ref(entry.get("ref", ""))
	control.name = _node_name_for_ref(normalized_ref)
	control.set_meta("roblox_ref", normalized_ref)
	control.set_meta("roblox_class", roblox_class)
	control.set_meta("roblox_layout_order", int(props.get("LayoutOrder", 0)))
	control.set_meta("roblox_display_order", int(props.get("DisplayOrder", 0)))
	control.tooltip_text = "%s: %s" % [roblox_class, str(entry.get("name", ""))]
	control.visible = bool(props.get("Enabled", props.get("Visible", true)))
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE if bool(options.get("ignore_mouse", true)) else Control.MOUSE_FILTER_PASS
	_apply_udim2_layout(control, props, options)
	_apply_visual_style(control, roblox_class, props, options)
	if bool(options.get("suppress_fullscreen_blockers", true)) and _is_probable_fullscreen_blocker(entry, props, options):
		control.visible = false
		control.set_meta("bobux_suppressed_fullscreen_blocker", true)
	return control


static func _make_image_control(entry: Dictionary, props: Dictionary, options: Dictionary) -> Control:
	var image_texture := _load_gui_image_texture(props)
	if image_texture != null:
		var control: Control
		if str(entry.get("class", "")) == "ImageButton":
			var button := Button.new()
			button.text = ""
			button.disabled = bool(options.get("editor_preview", false))
			control = button
			_attach_texture_child(control, image_texture, props)
		else:
			control = Panel.new()
			_attach_texture_child(control, image_texture, props)
		control.set_meta("bobux_image_loaded", true)
		return control
	return _make_image_placeholder(entry, props, options)


static func _make_image_placeholder(entry: Dictionary, props: Dictionary, options: Dictionary) -> Control:
	var panel := Panel.new()
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var image_text := str(props.get("Image", "")).strip_edges()
	label.text = str(entry.get("name", "Image")) if image_text.is_empty() else image_text.replace("rbxassetid://", "#").replace("http://www.roblox.com/asset/?id=", "#").left(36)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.42, 0.46, 0.52))
	panel.add_child(label)
	panel.set_meta("bobux_image_missing", true)
	return panel


static func _attach_texture_child(control: Control, texture: Texture2D, props: Dictionary) -> void:
	var rect := TextureRect.new()
	rect.name = "RobloxImage"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.texture = _atlas_texture_from_image_rect(texture, props)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = _texture_stretch_mode_from_scale_type(props.get("ScaleType", 0))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image_color := _color_from_variant(props.get("ImageColor3", [1.0, 1.0, 1.0]), Color.WHITE)
	var image_alpha := 1.0 - clampf(float(props.get("ImageTransparency", 0.0)), 0.0, 1.0)
	rect.self_modulate = _color_with_alpha(image_color, image_alpha)
	control.add_child(rect)


static func _apply_udim2_layout(control: Control, props: Dictionary, options: Dictionary = {}) -> void:
	var size := _udim2_from_variant(props.get("Size", {}), {"x": {"scale": 0.0, "offset": 180.0}, "y": {"scale": 0.0, "offset": 48.0}})
	var pos := _udim2_from_variant(props.get("Position", {}), {"x": {"scale": 0.0, "offset": 0.0}, "y": {"scale": 0.0, "offset": 0.0}})
	if _is_gui_root_class(str(control.get_meta("roblox_class", ""))):
		control.set_anchors_preset(Control.PRESET_FULL_RECT)
		control.offset_left = 0.0
		control.offset_top = 0.0
		control.offset_right = 0.0
		control.offset_bottom = 0.0
		control.clip_contents = true
		return
	var anchor := _vector2_from_variant(props.get("AnchorPoint", []), Vector2.ZERO)
	var sx := float(size["x"].get("scale", 0.0))
	var sy := float(size["y"].get("scale", 0.0))
	var ox := float(size["x"].get("offset", 0.0))
	var oy := float(size["y"].get("offset", 0.0))
	var pxs := float(pos["x"].get("scale", 0.0))
	var pys := float(pos["y"].get("scale", 0.0))
	var pox := float(pos["x"].get("offset", 0.0))
	var poy := float(pos["y"].get("offset", 0.0))
	var offset_scale := float(options.get("gui_offset_scale", 1.0))
	if offset_scale > 0.0 and not is_equal_approx(offset_scale, 1.0):
		ox *= offset_scale
		oy *= offset_scale
		pox *= offset_scale
		poy *= offset_scale
	var left_anchor := pxs - anchor.x * sx
	var right_anchor := pxs + sx - anchor.x * sx
	var top_anchor := pys - anchor.y * sy
	var bottom_anchor := pys + sy - anchor.y * sy
	var left_offset := pox - anchor.x * ox
	var right_offset := pox + ox - anchor.x * ox
	var top_offset := poy - anchor.y * oy
	var bottom_offset := poy + oy - anchor.y * oy
	if right_anchor < left_anchor or (is_equal_approx(right_anchor, left_anchor) and right_offset < left_offset):
		var temp_anchor := left_anchor
		left_anchor = right_anchor
		right_anchor = temp_anchor
		var temp_offset := left_offset
		left_offset = right_offset
		right_offset = temp_offset
	if bottom_anchor < top_anchor or (is_equal_approx(bottom_anchor, top_anchor) and bottom_offset < top_offset):
		var temp_anchor_y := top_anchor
		top_anchor = bottom_anchor
		bottom_anchor = temp_anchor_y
		var temp_offset_y := top_offset
		top_offset = bottom_offset
		bottom_offset = temp_offset_y
	control.anchor_left = left_anchor
	control.anchor_top = top_anchor
	control.anchor_right = right_anchor
	control.anchor_bottom = bottom_anchor
	control.offset_left = left_offset
	control.offset_top = top_offset
	control.offset_right = right_offset
	control.offset_bottom = bottom_offset
	control.set_meta("bobux_gui_size_scale", Vector2(sx, sy))
	control.set_meta("bobux_gui_size_offset", Vector2(ox, oy))
	if is_equal_approx(ox, 0.0) and is_equal_approx(sx, 0.0):
		control.offset_right = control.offset_left + 180.0
	if is_equal_approx(oy, 0.0) and is_equal_approx(sy, 0.0):
		control.offset_bottom = control.offset_top + 48.0
	if props.has("Rotation"):
		control.rotation_degrees = float(props.get("Rotation", 0.0))
	if props.has("ClipsDescendants"):
		control.clip_contents = bool(props.get("ClipsDescendants", false))


static func _apply_visual_style(control: Control, roblox_class: String, props: Dictionary, options: Dictionary = {}) -> void:
	if _is_gui_root_class(roblox_class):
		control.z_index = _clamped_canvas_z_index(int(props.get("DisplayOrder", props.get("ZIndex", 0))) * 32)
		return
	var bg := _color_from_variant(props.get("BackgroundColor3", [1.0, 1.0, 1.0]), Color(0.18, 0.18, 0.2))
	var bg_alpha := 1.0 - clampf(float(props.get("BackgroundTransparency", props.get("Transparency", 0.0))), 0.0, 1.0)
	if bool(options.get("editor_preview", false)):
		bg_alpha = minf(bg_alpha, float(options.get("editor_preview_max_alpha", 1.0)))
	var fg := _color_from_variant(props.get("TextColor3", [1.0, 1.0, 1.0]), Color.WHITE)
	var border_width := int(maxf(0.0, float(props.get("BorderSizePixel", 1))))
	control.set_meta("bobux_gui_bg", _color_with_alpha(bg, bg_alpha))
	control.set_meta("bobux_gui_border", Color(0.0, 0.0, 0.0, 0.22))
	control.set_meta("bobux_gui_border_width", border_width)
	control.set_meta("bobux_gui_radius", 2)
	control.set_meta("bobux_gui_fg", fg)
	if control is Label:
		var label := control as Label
		label.horizontal_alignment = _horizontal_alignment_from_roblox(props.get("TextXAlignment", 2))
		label.vertical_alignment = _vertical_alignment_from_roblox(props.get("TextYAlignment", 1))
		label.add_theme_color_override("font_color", _color_with_alpha(fg, 1.0 - clampf(float(props.get("TextTransparency", 0.0)), 0.0, 1.0)))
		label.add_theme_font_size_override("font_size", int(clampf(float(props.get("TextSize", 18.0)), 8.0, 72.0)))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if bool(props.get("TextWrapped", false)) else TextServer.AUTOWRAP_OFF
		if bool(props.get("TextScaled", false)):
			var text_size := _control_pixel_size(control)
			label.add_theme_font_size_override("font_size", int(clampf(minf(text_size.x, text_size.y) * 0.42, 8.0, 56.0)))
		_apply_text_outline(label, props)
		_apply_control_box_style(control, fg)
	elif control is Button:
		var button := control as Button
		button.alignment = _horizontal_alignment_from_roblox(props.get("TextXAlignment", 2))
		button.add_theme_font_size_override("font_size", int(clampf(float(props.get("TextSize", 18.0)), 8.0, 72.0)))
		_apply_control_box_style(control, fg)
	elif control is LineEdit:
		var edit := control as LineEdit
		edit.alignment = _horizontal_alignment_from_roblox(props.get("TextXAlignment", 0))
		edit.add_theme_color_override("font_color", fg)
		_apply_control_box_style(control, fg)
	elif control is Panel:
		_apply_control_box_style(control, fg)
	if props.has("ZIndex"):
		control.z_index = _clamped_canvas_z_index(int(props.get("ZIndex", 0)))


static func _apply_gui_decorators(root: Control, gui_by_ref: Dictionary, parent_by_ref: Dictionary, options: Dictionary) -> void:
	var apply_order: Array[String] = [
		"UIScale", "UIAspectRatioConstraint", "UISizeConstraint",
		"UITextSizeConstraint", "UICorner", "UIStroke", "UIGradient",
		"UIPadding", "UIListLayout", "UIGridLayout"
	]
	for target_class in apply_order:
		for ref_variant in gui_by_ref.keys():
			var ref := str(ref_variant)
			var entry: Dictionary = gui_by_ref[ref]
			var roblox_class := str(entry.get("class", ""))
			if roblox_class != target_class:
				continue
			var parent_ref := _normalize_ref(entry.get("parent_ref", parent_by_ref.get(ref, "")))
			if parent_ref.is_empty():
				continue
			var target := root.find_child(_node_name_for_ref(parent_ref), true, false) as Control
			if target == null:
				continue
			var props: Dictionary = entry.get("properties", {}) if entry.get("properties", {}) is Dictionary else {}
			match roblox_class:
				"UICorner":
					_apply_corner_to_control(target, props)
				"UIStroke":
					_apply_stroke_to_control(target, props)
				"UIScale":
					target.scale *= float(props.get("Scale", 1.0))
				"UIAspectRatioConstraint":
					_apply_aspect_ratio_constraint_to_control(target, props)
				"UISizeConstraint":
					_apply_size_constraint_to_control(target, props)
				"UITextSizeConstraint":
					_apply_text_size_constraint_to_control(target, props)
				"UIPadding":
					_apply_padding_to_control(target, props)
				"UIListLayout":
					_apply_list_layout_to_control(target, props)
				"UIGridLayout":
					_apply_grid_layout_to_control(target, props)
				"UIGradient":
					_apply_gradient_tint_to_control(target, props)


static func _apply_corner_to_control(control: Control, props: Dictionary) -> void:
	var corner := _udim_from_variant(props.get("CornerRadius", {}), {"scale": 0.0, "offset": 8.0})
	var control_size := Vector2(absf(control.offset_right - control.offset_left), absf(control.offset_bottom - control.offset_top))
	var radius := int(clampf(float(corner.get("offset", 8.0)) + minf(control_size.x, control_size.y) * float(corner.get("scale", 0.0)), 0.0, 96.0))
	control.set_meta("bobux_gui_radius", radius)
	_apply_control_box_style(control, control.get_meta("bobux_gui_fg", Color.WHITE))


static func _apply_stroke_to_control(control: Control, props: Dictionary) -> void:
	var stroke_color := _color_from_variant(props.get("Color", props.get("StrokeColor3", [0.0, 0.0, 0.0])), Color.BLACK)
	var alpha := 1.0 - clampf(float(props.get("Transparency", 0.0)), 0.0, 1.0)
	control.set_meta("bobux_gui_border", _color_with_alpha(stroke_color, alpha))
	control.set_meta("bobux_gui_border_width", int(clampf(float(props.get("Thickness", 1.0)), 0.0, 16.0)))
	_apply_control_box_style(control, control.get_meta("bobux_gui_fg", Color.WHITE))


static func _apply_aspect_ratio_constraint_to_control(control: Control, props: Dictionary) -> void:
	var ratio := maxf(0.01, float(props.get("AspectRatio", 1.0)))
	var size := _control_pixel_size(control)
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var current_ratio := size.x / maxf(size.y, 0.01)
	if is_equal_approx(current_ratio, ratio):
		return
	var dominant_axis := int(props.get("DominantAxis", 0))
	if dominant_axis == 1:
		var new_width := size.y * ratio
		_resize_control_pixels(control, Vector2(new_width, size.y))
	else:
		var new_height := size.x / ratio
		_resize_control_pixels(control, Vector2(size.x, new_height))


static func _apply_size_constraint_to_control(control: Control, props: Dictionary) -> void:
	var size := _control_pixel_size(control)
	var min_size := _vector2_from_variant(props.get("MinSize", []), Vector2.ZERO)
	var max_size := _vector2_from_variant(props.get("MaxSize", []), Vector2(100000.0, 100000.0))
	var clamped := Vector2(
		clampf(size.x, maxf(min_size.x, 0.0), maxf(max_size.x, maxf(min_size.x, 1.0))),
		clampf(size.y, maxf(min_size.y, 0.0), maxf(max_size.y, maxf(min_size.y, 1.0)))
	)
	if clamped != size:
		_resize_control_pixels(control, clamped)


static func _apply_text_size_constraint_to_control(control: Control, props: Dictionary) -> void:
	var min_text := int(clampf(float(props.get("MinTextSize", props.get("TextMinimumSize", 1))), 1.0, 256.0))
	var max_text := int(clampf(float(props.get("MaxTextSize", props.get("TextMaximumSize", 100))), 1.0, 256.0))
	var current := max_text
	if control is Label and (control as Label).has_theme_font_size_override("font_size"):
		current = (control as Label).get_theme_font_size("font_size")
	elif control is Button and (control as Button).has_theme_font_size_override("font_size"):
		current = (control as Button).get_theme_font_size("font_size")
	var clamped := clampi(current, min_text, max_text)
	if control is Label:
		(control as Label).add_theme_font_size_override("font_size", clamped)
	elif control is Button:
		(control as Button).add_theme_font_size_override("font_size", clamped)


static func _apply_gradient_tint_to_control(control: Control, props: Dictionary) -> void:
	if not props.has("Transparency"):
		return
	var transparency := clampf(float(props.get("Transparency", 0.0)), 0.0, 1.0)
	if transparency <= 0.0:
		return
	control.modulate.a *= 1.0 - transparency


static func _resize_control_pixels(control: Control, new_size: Vector2) -> void:
	new_size.x = maxf(new_size.x, 1.0)
	new_size.y = maxf(new_size.y, 1.0)
	control.anchor_right = control.anchor_left
	control.anchor_bottom = control.anchor_top
	control.offset_right = control.offset_left + new_size.x
	control.offset_bottom = control.offset_top + new_size.y


static func _apply_padding_to_control(control: Control, props: Dictionary) -> void:
	var target_size := _control_pixel_size(control)
	var padding := {
		"left": _udim_to_pixels(props.get("PaddingLeft", {}), target_size.x, 0.0),
		"right": _udim_to_pixels(props.get("PaddingRight", {}), target_size.x, 0.0),
		"top": _udim_to_pixels(props.get("PaddingTop", {}), target_size.y, 0.0),
		"bottom": _udim_to_pixels(props.get("PaddingBottom", {}), target_size.y, 0.0),
	}
	control.set_meta("bobux_gui_padding", padding)
	if control.has_meta("bobux_gui_layout_applied"):
		return
	for child in _direct_visual_children(control):
		child.offset_left += float(padding["left"])
		child.offset_right -= float(padding["right"])
		child.offset_top += float(padding["top"])
		child.offset_bottom -= float(padding["bottom"])


static func _apply_list_layout_to_control(control: Control, props: Dictionary) -> void:
	var target_size := _control_pixel_size(control)
	var padding := _padding_from_meta(control)
	var horizontal := _fill_direction_is_horizontal(props.get("FillDirection", "Vertical"))
	var gap := _udim_to_pixels(props.get("Padding", {}), target_size.x if horizontal else target_size.y, 0.0)
	var children := _sorted_visual_children(control)
	var cursor_x := float(padding["left"])
	var cursor_y := float(padding["top"])
	for child in children:
		var child_size := _control_pixel_size(child)
		child.anchor_left = 0.0
		child.anchor_right = 0.0
		child.anchor_top = 0.0
		child.anchor_bottom = 0.0
		child.offset_left = cursor_x
		child.offset_top = cursor_y
		child.offset_right = cursor_x + child_size.x
		child.offset_bottom = cursor_y + child_size.y
		if horizontal:
			cursor_x += child_size.x + gap
		else:
			cursor_y += child_size.y + gap
	control.set_meta("bobux_gui_layout_applied", true)


static func _apply_grid_layout_to_control(control: Control, props: Dictionary) -> void:
	var target_size := _control_pixel_size(control)
	var padding := _padding_from_meta(control)
	var cell_size := _udim2_from_variant(props.get("CellSize", {}), {"x": {"scale": 0.0, "offset": 100.0}, "y": {"scale": 0.0, "offset": 100.0}})
	var cell_pad := _udim2_from_variant(props.get("CellPadding", {}), {"x": {"scale": 0.0, "offset": 6.0}, "y": {"scale": 0.0, "offset": 6.0}})
	var available_width := maxf(1.0, target_size.x - float(padding["left"]) - float(padding["right"]))
	var cell_w := maxf(1.0, float(cell_size["x"].get("offset", 100.0)) + target_size.x * float(cell_size["x"].get("scale", 0.0)))
	var cell_h := maxf(1.0, float(cell_size["y"].get("offset", 100.0)) + target_size.y * float(cell_size["y"].get("scale", 0.0)))
	var pad_x := maxf(0.0, float(cell_pad["x"].get("offset", 6.0)) + target_size.x * float(cell_pad["x"].get("scale", 0.0)))
	var pad_y := maxf(0.0, float(cell_pad["y"].get("offset", 6.0)) + target_size.y * float(cell_pad["y"].get("scale", 0.0)))
	var columns := maxi(1, int(floor((available_width + pad_x) / (cell_w + pad_x))))
	var children := _sorted_visual_children(control)
	for i in range(children.size()):
		var child: Control = children[i]
		var col := i % columns
		var row := int(floor(float(i) / float(columns)))
		var x := float(padding["left"]) + col * (cell_w + pad_x)
		var y := float(padding["top"]) + row * (cell_h + pad_y)
		child.anchor_left = 0.0
		child.anchor_right = 0.0
		child.anchor_top = 0.0
		child.anchor_bottom = 0.0
		child.offset_left = x
		child.offset_top = y
		child.offset_right = x + cell_w
		child.offset_bottom = y + cell_h
	control.set_meta("bobux_gui_layout_applied", true)


static func _apply_control_box_style(control: Control, fg: Color) -> void:
	var bg: Color = control.get_meta("bobux_gui_bg", Color.TRANSPARENT)
	var border: Color = control.get_meta("bobux_gui_border", Color(0.0, 0.0, 0.0, 0.22))
	var border_width := int(control.get_meta("bobux_gui_border_width", 1))
	var radius := int(control.get_meta("bobux_gui_radius", 2))
	if control is Button:
		_apply_button_style(control as Button, bg, bg.darkened(0.16), fg, border, border_width, radius)
	elif control is LineEdit:
		(control as LineEdit).add_theme_stylebox_override("normal", _stylebox(bg, border, border_width, radius))
	elif control is Panel:
		(control as Panel).add_theme_stylebox_override("panel", _stylebox(bg, border, border_width, radius))
	elif control is Label:
		(control as Label).add_theme_stylebox_override("normal", _stylebox(bg, border, border_width, radius))


static func _direct_visual_children(control: Control) -> Array[Control]:
	var result: Array[Control] = []
	for child in control.get_children():
		var child_control := child as Control
		if child_control == null:
			continue
		if child_control.name == "RobloxImage":
			continue
		if str(child_control.get_meta("roblox_ref", "")).is_empty():
			continue
		result.append(child_control)
	return result


static func _sorted_visual_children(control: Control) -> Array[Control]:
	var children := _direct_visual_children(control)
	for i in range(children.size()):
		var best := i
		for j in range(i + 1, children.size()):
			var a := int(children[best].get_meta("roblox_layout_order", 0))
			var b := int(children[j].get_meta("roblox_layout_order", 0))
			if b < a:
				best = j
		if best != i:
			var tmp := children[i]
			children[i] = children[best]
			children[best] = tmp
	return children


static func _padding_from_meta(control: Control) -> Dictionary:
	if control.has_meta("bobux_gui_padding") and control.get_meta("bobux_gui_padding") is Dictionary:
		return control.get_meta("bobux_gui_padding")
	return {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}


static func _control_pixel_size(control: Control) -> Vector2:
	var direct := Vector2(
		maxf(maxf(absf(control.offset_right - control.offset_left), control.size.x), 1.0),
		maxf(maxf(absf(control.offset_bottom - control.offset_top), control.size.y), 1.0)
	)
	if direct.x > 1.0 and direct.y > 1.0:
		return direct
	if control.has_meta("bobux_gui_size_scale") and control.has_meta("bobux_gui_size_offset"):
		var parent := control.get_parent() as Control
		if parent != null:
			var parent_size := _control_pixel_size(parent)
			var scale := control.get_meta("bobux_gui_size_scale") as Vector2
			var offset := control.get_meta("bobux_gui_size_offset") as Vector2
			return Vector2(
				maxf(absf(parent_size.x * scale.x + offset.x), direct.x),
				maxf(absf(parent_size.y * scale.y + offset.y), direct.y)
			)
	return direct


static func _udim_to_pixels(raw: Variant, basis: float, fallback: float) -> float:
	var udim := _udim_from_variant(raw, {"scale": 0.0, "offset": fallback})
	return float(udim.get("offset", fallback)) + basis * float(udim.get("scale", 0.0))


static func _fill_direction_is_horizontal(raw: Variant) -> bool:
	if raw == null:
		return false
	if raw is String:
		return str(raw).to_lower().find("horizontal") >= 0
	if raw is Dictionary:
		return false
	return int(raw) == 0


static func _apply_button_style(button: Button, bg: Color, pressed: Color, fg: Color, border: Color = Color(0.0, 0.0, 0.0, 0.34), border_width: int = 1, radius: int = 2) -> void:
	button.add_theme_stylebox_override("normal", _stylebox(bg, border, border_width, radius))
	button.add_theme_stylebox_override("hover", _stylebox(bg.lightened(0.08), border, border_width, radius))
	button.add_theme_stylebox_override("pressed", _stylebox(pressed, border.darkened(0.08), border_width, radius))
	button.add_theme_stylebox_override("disabled", _stylebox(bg.darkened(0.08), _color_with_alpha(border, border.a * 0.62), border_width, radius))
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", _color_with_alpha(fg, 0.7))


static func _load_gui_image_texture(props: Dictionary) -> Texture2D:
	var paths: Array[String] = []
	for key in ["ResolvedImagePath", "resolved_path", "path", "file"]:
		var candidate := str(props.get(key, "")).strip_edges()
		if not candidate.is_empty():
			paths.append(candidate)
	var image_source := _content_to_string(props.get("Image", ""))
	var asset_id := str(props.get("ImageAssetId", "")).strip_edges()
	if asset_id.is_empty():
		asset_id = _sanitize_asset_id(image_source)
	if not asset_id.is_empty():
		for ext in ["png", "jpg", "jpeg", "webp"]:
			# Converter downloads can be an exact asset payload or a thumbnail.
			paths.append("user://rbxl_assets/%s.asset.%s" % [asset_id, ext])
			paths.append("user://rbxl_assets/%s.thumbnail.%s" % [asset_id, ext])
			paths.append("user://rbxl_assets/%s.%s" % [asset_id, ext])
			paths.append("res://addons/rbxl_importer/builtin_assets/%s.%s" % [asset_id, ext])
	if image_source.begins_with("rbxasset://"):
		var asset_path := image_source.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		paths.append("res://addons/rbxl_importer/builtin_assets/%s" % asset_path)
		paths.append("res://images/%s" % asset_path.get_file())
	if image_source.begins_with("res://") or image_source.begins_with("user://") or image_source.find(":") == 1:
		paths.append(image_source)
	for path in paths:
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		if path.begins_with("res://"):
			var resource := load(path)
			if resource is Texture2D:
				return resource as Texture2D
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


static func _atlas_texture_from_image_rect(texture: Texture2D, props: Dictionary) -> Texture2D:
	var rect_size := _vector2_from_variant(props.get("ImageRectSize", []), Vector2.ZERO)
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return texture
	var rect_offset := _vector2_from_variant(props.get("ImageRectOffset", []), Vector2.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(rect_offset, rect_size)
	return atlas


static func _horizontal_alignment_from_roblox(raw: Variant) -> HorizontalAlignment:
	if raw is String:
		var lower := str(raw).to_lower()
		if lower.find("left") >= 0:
			return HORIZONTAL_ALIGNMENT_LEFT
		if lower.find("right") >= 0:
			return HORIZONTAL_ALIGNMENT_RIGHT
		return HORIZONTAL_ALIGNMENT_CENTER
	var value := int(raw)
	if value == 0:
		return HORIZONTAL_ALIGNMENT_LEFT
	if value == 1:
		return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_CENTER


static func _vertical_alignment_from_roblox(raw: Variant) -> VerticalAlignment:
	if raw is String:
		var lower := str(raw).to_lower()
		if lower.find("top") >= 0:
			return VERTICAL_ALIGNMENT_TOP
		if lower.find("bottom") >= 0:
			return VERTICAL_ALIGNMENT_BOTTOM
		return VERTICAL_ALIGNMENT_CENTER
	var value := int(raw)
	if value == 0:
		return VERTICAL_ALIGNMENT_TOP
	if value == 2:
		return VERTICAL_ALIGNMENT_BOTTOM
	return VERTICAL_ALIGNMENT_CENTER


static func _apply_text_outline(label: Label, props: Dictionary) -> void:
	var transparency := clampf(float(props.get("TextStrokeTransparency", 1.0)), 0.0, 1.0)
	if transparency >= 1.0:
		return
	var color := _color_from_variant(props.get("TextStrokeColor3", [0.0, 0.0, 0.0]), Color.BLACK)
	label.add_theme_color_override("font_outline_color", _color_with_alpha(color, 1.0 - transparency))
	label.add_theme_constant_override("outline_size", 2)


static func _content_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return str(value).strip_edges()
	if value is Dictionary:
		var d: Dictionary = value
		for key in ["value", "url", "path", "asset_id", "id"]:
			var candidate := str(d.get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
	if value is Array:
		var arr := value as Array
		if not arr.is_empty():
			return _content_to_string(arr[0])
	return str(value).strip_edges()


static func _sanitize_asset_id(value: String) -> String:
	var out := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		if ch >= "0" and ch <= "9":
			out += ch
	return out


static func _texture_stretch_mode_from_scale_type(raw: Variant) -> TextureRect.StretchMode:
	if raw is String:
		var lower := str(raw).to_lower()
		if lower.find("tile") >= 0:
			return TextureRect.STRETCH_TILE
		if lower.find("fit") >= 0:
			return TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if lower.find("crop") >= 0:
			return TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return TextureRect.STRETCH_SCALE
	match int(raw):
		2:
			return TextureRect.STRETCH_TILE
		3:
			return TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		4:
			return TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_:
			return TextureRect.STRETCH_SCALE


static func _is_probable_fullscreen_blocker(entry: Dictionary, props: Dictionary, options: Dictionary = {}) -> bool:
	var roblox_class := str(entry.get("class", ""))
	if roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui"]:
		return false
	if not (roblox_class in ["Frame", "ImageLabel", "TextLabel", "CanvasGroup"]):
		return false
	if not bool(props.get("Visible", true)) or not bool(props.get("Enabled", true)):
		return false
	var size := _udim2_from_variant(props.get("Size", {}), {"x": {"scale": 0.0, "offset": 0.0}, "y": {"scale": 0.0, "offset": 0.0}})
	var pos := _udim2_from_variant(props.get("Position", {}), {"x": {"scale": 0.0, "offset": 0.0}, "y": {"scale": 0.0, "offset": 0.0}})
	var sx := float(size["x"].get("scale", 0.0))
	var sy := float(size["y"].get("scale", 0.0))
	var px := absf(float(pos["x"].get("scale", 0.0)))
	var py := absf(float(pos["y"].get("scale", 0.0)))
	if sx < 0.98 or sy < 0.98 or px > 0.04 or py > 0.04:
		return false
	var name_text := "%s %s" % [str(entry.get("name", "")), str(props.get("Text", ""))]
	var lower := name_text.to_lower()
	for token in ["loading", "loader", "splash", "fade", "transition", "intro", "blackout", "whiteout"]:
		if lower.find(token) >= 0:
			return true
	var bg := _color_from_variant(props.get("BackgroundColor3", [1.0, 1.0, 1.0]), Color.WHITE)
	var alpha := 1.0 - clampf(float(props.get("BackgroundTransparency", props.get("Transparency", 0.0))), 0.0, 1.0)
	var z_index := int(props.get("ZIndex", 0))
	var is_plain_white := bg.r > 0.92 and bg.g > 0.92 and bg.b > 0.92
	var is_plain_black := bg.r < 0.08 and bg.g < 0.08 and bg.b < 0.08
	var is_neutral := absf(bg.r - bg.g) < 0.035 and absf(bg.g - bg.b) < 0.035
	var has_text := not str(props.get("Text", "")).strip_edges().is_empty()
	var suppress_neutral := bool(options.get("suppress_neutral_fullscreen_frames", bool(options.get("editor_preview", false))))
	if alpha > 0.92 and suppress_neutral and is_neutral and not has_text:
		return true
	return alpha > 0.92 and z_index >= 5 and (is_plain_white or is_plain_black)


static func _color_with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


static func _stylebox(bg: Color, border: Color, border_width: int, radius: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


static func _clamped_canvas_z_index(value: int) -> int:
	return clampi(value, -4096, 4096)


static func _build_parent_map(edges: Array) -> Dictionary:
	var parent_by_ref: Dictionary = {}
	for edge_variant in edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var child_ref := _normalize_ref(edge.get("child", ""))
		if child_ref.is_empty():
			continue
		parent_by_ref[child_ref] = _normalize_ref(edge.get("parent", ""))
	return parent_by_ref


static func _build_service_map(manifest: Dictionary) -> Dictionary:
	var services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	var by_ref: Dictionary = {}
	for service_variant in services:
		if not (service_variant is Dictionary):
			continue
		var service: Dictionary = service_variant
		var ref := _normalize_ref(service.get("ref", ""))
		if ref.is_empty():
			continue
		by_ref[ref] = str(service.get("name", service.get("class", "")))
	return by_ref


static func _belongs_to_starter_gui(ref: String, parent_by_ref: Dictionary, services_by_ref: Dictionary) -> bool:
	if services_by_ref.is_empty():
		return true
	return _belongs_to_service(ref, parent_by_ref, services_by_ref, ["StarterGui"])


static func _belongs_to_starter_gui_entry(entry: Dictionary, ref: String,
		parent_by_ref: Dictionary, services_by_ref: Dictionary) -> bool:
	# The importer resolves this once from the complete RBXL ancestry. Prefer it
	# over reconstructing a chain at render time, where a trimmed legacy manifest
	# may no longer contain intermediary Tool/LocalScript nodes.
	var declared_service := str(entry.get("service_name", "")).strip_edges()
	if not declared_service.is_empty():
		return declared_service == "StarterGui"
	return _belongs_to_starter_gui(ref, parent_by_ref, services_by_ref)


static func _belongs_to_service(ref: String, parent_by_ref: Dictionary, services_by_ref: Dictionary, names: Array[String]) -> bool:
	var cursor := _normalize_ref(ref)
	var guard := 0
	while not cursor.is_empty() and guard < 512:
		if services_by_ref.has(cursor):
			return names.has(str(services_by_ref[cursor]))
		cursor = _normalize_ref(parent_by_ref.get(cursor, ""))
		guard += 1
	return false


static func _is_visual_gui_class(roblox_class: String) -> bool:
	return roblox_class in [
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel",
		"TextButton", "TextBox", "ImageLabel", "ImageButton",
		"ScrollingFrame", "ViewportFrame", "CanvasGroup"
	]


static func _is_gui_root_class(roblox_class: String) -> bool:
	return roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui"]


static func _node_name_for_ref(ref: String) -> String:
	var normalized := _normalize_ref(ref)
	return "RobloxGui_%s" % normalized.replace("-", "_").replace(".", "_")


static func _normalize_ref(raw: Variant) -> String:
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "<null>":
		return ""
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return text


static func _udim2_from_variant(raw: Variant, fallback: Dictionary) -> Dictionary:
	if raw is Dictionary:
		var dict: Dictionary = raw
		var x: Dictionary = dict.get("x", {}) if dict.get("x", {}) is Dictionary else {}
		var y: Dictionary = dict.get("y", {}) if dict.get("y", {}) is Dictionary else {}
		return {
			"x": {"scale": float(x.get("scale", fallback["x"].get("scale", 0.0))), "offset": float(x.get("offset", fallback["x"].get("offset", 0.0)))},
			"y": {"scale": float(y.get("scale", fallback["y"].get("scale", 0.0))), "offset": float(y.get("offset", fallback["y"].get("offset", 0.0)))},
		}
	if raw is Array:
		var arr: Array = raw
		if arr.size() >= 4:
			return {
				"x": {"scale": float(arr[0]), "offset": float(arr[1])},
				"y": {"scale": float(arr[2]), "offset": float(arr[3])},
			}
	return fallback


static func _udim_from_variant(raw: Variant, fallback: Dictionary) -> Dictionary:
	if raw is Dictionary:
		var dict: Dictionary = raw
		return {
			"scale": float(dict.get("scale", fallback.get("scale", 0.0))),
			"offset": float(dict.get("offset", fallback.get("offset", 0.0))),
		}
	if raw is Array:
		var arr: Array = raw
		return {
			"scale": float(arr[0]) if arr.size() > 0 else float(fallback.get("scale", 0.0)),
			"offset": float(arr[1]) if arr.size() > 1 else float(fallback.get("offset", 0.0)),
		}
	return fallback


static func _vector2_from_variant(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array:
		var arr: Array = raw
		return Vector2(float(arr[0]) if arr.size() > 0 else fallback.x, float(arr[1]) if arr.size() > 1 else fallback.y)
	if raw is Dictionary:
		var dict: Dictionary = raw
		return Vector2(float(dict.get("x", fallback.x)), float(dict.get("y", fallback.y)))
	return fallback


static func _color_from_variant(raw: Variant, fallback: Color) -> Color:
	if raw is Color:
		return raw
	if raw is Array:
		var arr: Array = raw
		return Color(
			float(arr[0]) if arr.size() > 0 else fallback.r,
			float(arr[1]) if arr.size() > 1 else fallback.g,
			float(arr[2]) if arr.size() > 2 else fallback.b,
			float(arr[3]) if arr.size() > 3 else fallback.a
		)
	if raw is Dictionary:
		var dict: Dictionary = raw
		return Color(float(dict.get("r", fallback.r)), float(dict.get("g", fallback.g)), float(dict.get("b", fallback.b)), float(dict.get("a", fallback.a)))
	return fallback
