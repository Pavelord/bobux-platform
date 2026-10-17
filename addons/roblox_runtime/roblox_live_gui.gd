extends Node

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
const Gui = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")
var engine: Node
var player_gui: Node
var host: Control
var _views: Dictionary = {}
var _styles: Dictionary = {}
var _decorator_styles: Dictionary = {}
var _elapsed := 0.0
var _next_profile_msec := 0

func _ready() -> void:
	for view in host.find_children("*", "Control", true, false):
		var ref := str(view.get_meta("roblox_ref", ""))
		if not ref.is_empty(): _views[ref] = view
	sync_now()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1: return
	_elapsed = 0
	sync_now()

func sync_now() -> void:
	var profile_started := Time.get_ticks_usec()
	if not is_instance_valid(player_gui) or not is_instance_valid(host):
		queue_free()
		return
	var seen := {}
	var options: Dictionary = host.get_meta("bobux_gui_runtime_options", {}).duplicate()
	if bool(options.get("fit_to_viewport", false)):
		var design := Gui._vector2_from_variant(options.get("design_size", [1366.0, 768.0]), Vector2(1366, 768))
		options["gui_offset_scale"] = clampf(minf(host.size.x / maxf(design.x, 1.0), host.size.y / maxf(design.y, 1.0)), 0.42, 1.0)
	var pending: Array = [[player_gui, host]]
	var decorators: Array = []
	var visited := 0
	var styled := 0
	var decorated := 0
	while not pending.is_empty():
		var pair: Array = pending.pop_back()
		var target: Node = pair[0]
		var visual_parent: Control = pair[1]
		for child in target.get_children():
			visited += 1
			if not child is Control:
				if str(child.get_meta("roblox_class", "")).begins_with("UI"):
					decorators.append([child, visual_parent])
				else:
					pending.append([child, visual_parent])
				continue
			var class_name_ := str(child.get_meta("roblox_class", "Frame"))
			var ref := str(child.get_meta("roblox_ref", ""))
			if ref.is_empty():
				ref = "runtime:%d" % child.get_instance_id()
				child.set_meta("roblox_ref", ref)
			seen[ref] = true
			var candidate: Variant = _views.get(ref)
			var view: Control = candidate if is_instance_valid(candidate) and not (candidate as Control).is_queued_for_deletion() else null
			if view == null:
				view = DataModel.create_instance(class_name_, str(child.name)) as Control
				if view == null: continue
				view.visibility_layer = 1
				view.set_meta("roblox_ref", ref)
				visual_parent.add_child(view)
				_views[ref] = view
				engine._bind_gui_controls_recursive(view, {ref: child})
			elif view.get_parent() != visual_parent:
				if view.get_parent() == null:
					visual_parent.add_child(view)
				else:
					view.reparent(visual_parent, false)
			var props: Dictionary = child.get_meta("roblox_properties", {})
			child.set_meta("bobux_gui_view", weakref(view))
			# Changes reach labels/frames as well as buttons. Layout is evaluated
			# against the visible viewport, not the invisible DataModel hierarchy.
			# Text and visibility synchronize separately. A clock/countdown should
			# not rebuild StyleBoxes, invalidate font layouts and reset decorators.
			var style_props := props.duplicate(false)
			style_props.erase("Text")
			style_props.erase("Visible")
			var style_hash := hash([style_props, visual_parent.size, options])
			if _styles.get(ref) != style_hash:
				styled += 1
				Gui._apply_udim2_layout(view, props, options)
				Gui._apply_visual_style(view, class_name_, props, options)
				if class_name_ in ["ImageLabel", "ImageButton"]:
					preload("res://addons/roblox_runtime/roblox_live_image.gd").sync_image(view, props)
				_styles[ref] = style_hash
			engine._sync_bound_gui_control(view, child)
			view.mouse_filter = Control.MOUSE_FILTER_STOP if view is BaseButton or view is LineEdit else Control.MOUSE_FILTER_STOP if bool(props.get("Active", false)) else Control.MOUSE_FILTER_IGNORE
			pending.append([child, _scroll_content(view, props) if view is ScrollContainer else view])
	# Layout objects live alongside their controls in Roblox. Apply them after
	# all children exist, including GUIs cloned out of tools during Play.
	var seen_decorators := {}
	for pair in decorators:
		var data: Node = pair[0]
		var view: Control = pair[1]
		var props: Dictionary = data.get_meta("roblox_properties", {})
		var kind := str(data.get_meta("roblox_class", ""))
		var dependencies: Array = [props, view.size, _styles.get(str(view.get_meta("roblox_ref", ""))), options]
		if kind in ["UIListLayout", "UIGridLayout", "UIPadding"]:
			for child in view.get_children():
				if child is Control:
					dependencies.append([child.get_instance_id(), child.size, child.get_combined_minimum_size(), child.visible, child.get_meta("roblox_properties", {}).get("LayoutOrder", 0)])
		var id := data.get_instance_id()
		seen_decorators[id] = true
		var signature := hash(dependencies)
		if _decorator_styles.get(id) == signature: continue
		decorated += 1
		_decorator_styles[id] = signature
		match kind:
			"UIGridLayout": Gui._apply_grid_layout_to_control(view, props)
			"UIListLayout": Gui._apply_list_layout_to_control(view, props)
			"UIPadding": Gui._apply_padding_to_control(view, props)
			"UICorner": Gui._apply_corner_to_control(view, props)
			"UIStroke": Gui._apply_stroke_to_control(view, props)
			"UIScale": view.scale = Vector2.ONE * float(props.get("Scale", 1.0))
			"UIAspectRatioConstraint": Gui._apply_aspect_ratio_constraint_to_control(view, props)
			"UISizeConstraint": Gui._apply_size_constraint_to_control(view, props)
			"UITextSizeConstraint": Gui._apply_text_size_constraint_to_control(view, props)
			"UIGradient": Gui._apply_gradient_tint_to_control(view, props)
	for id in _decorator_styles.keys():
		if not seen_decorators.has(id): _decorator_styles.erase(id)
	for ref in _views.keys():
		if seen.has(ref): continue
		var stale: Variant = _views[ref]
		if is_instance_valid(stale): stale.queue_free()
		_views.erase(ref)
		_styles.erase(ref)
	if OS.get_cmdline_user_args().has("--profile-loading") and Time.get_ticks_msec() >= _next_profile_msec:
		_next_profile_msec = Time.get_ticks_msec() + 1000
		print("[gui-span] sync_ms=", (Time.get_ticks_usec()-profile_started)/1000.0, " visited=", visited, " styled=", styled, " decorated=", decorated)

func _scroll_content(view: ScrollContainer, props: Dictionary) -> Control:
	var canvas := view.get_node_or_null("_RobloxCanvas") as Control
	if canvas == null:
		canvas = Control.new()
		canvas.name = "_RobloxCanvas"
		canvas.mouse_filter = Control.MOUSE_FILTER_PASS
		view.add_child(canvas)
	var size_data := Gui._udim2_from_variant(props.get("CanvasSize", {}), {"x": {"scale": 0, "offset": 0}, "y": {"scale": 2, "offset": 0}})
	canvas.custom_minimum_size = Vector2(
		maxf(view.size.x, float(size_data.x.scale) * view.size.x + float(size_data.x.offset)),
		maxf(view.size.y, float(size_data.y.scale) * view.size.y + float(size_data.y.offset)))
	canvas.size = canvas.custom_minimum_size
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if bool(props.get("ScrollingEnabled", true)) else ScrollContainer.SCROLL_MODE_DISABLED
	view.vertical_scroll_mode = view.horizontal_scroll_mode
	return canvas

# Authored GUI buttons also accept real touch events while the game camera has
# captured the mouse. Do not turn a camera drag into a button activation.
var _button_touches: Dictionary = {}
func _input(event: InputEvent) -> void:
	if not is_instance_valid(host) or not host.is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		if event.pressed:
			var button := _touch_button_at(host, event.position)
			if button == null: return
			_button_touches[event.index] = {"button": button, "start": event.position, "cancelled": false}
			get_viewport().set_input_as_handled()
		elif _button_touches.has(event.index):
			var press: Dictionary = _button_touches[event.index]
			_button_touches.erase(event.index)
			get_viewport().set_input_as_handled()
			var button: Variant = press.button
			if is_instance_valid(button) and not press.cancelled and not event.canceled and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
				button.pressed.emit()
	elif event is InputEventScreenDrag and _button_touches.has(event.index):
		if event.position.distance_to(_button_touches[event.index].start) > 20:
			_button_touches[event.index].cancelled = true
		get_viewport().set_input_as_handled()

func _touch_button_at(control: Control, point: Vector2) -> BaseButton:
	if not control.is_visible_in_tree(): return null
	if control.clip_contents and not control.get_global_rect().has_point(point): return null
	var children := control.get_children()
	children.sort_custom(func(a, b): return a.z_index < b.z_index if a is Control and b is Control else false)
	children.reverse()
	for child in children:
		if child is Control:
			var hit := _touch_button_at(child, point)
			if hit != null: return hit
	if control is BaseButton and not control.disabled and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point): return control
	return null
