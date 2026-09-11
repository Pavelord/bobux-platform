extends Node

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
const Gui = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")
var engine: Node
var player_gui: Node
var host: Control
var _views: Dictionary = {}
var _styles: Dictionary = {}
var _elapsed := 0.0

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
	if not is_instance_valid(player_gui) or not is_instance_valid(host):
		queue_free()
		return
	var seen := {}
	var pending: Array = [[player_gui, host]]
	var decorators: Array = []
	var visited := 0
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
			var view: Control = candidate if is_instance_valid(candidate) else null
			if view == null:
				view = DataModel.create_instance(class_name_, str(child.name)) as Control
				if view == null: continue
				view.visibility_layer = 1
				view.set_meta("roblox_ref", ref)
				visual_parent.add_child(view)
				_views[ref] = view
				engine._bind_gui_controls_recursive(view, {ref: child})
			elif view.get_parent() != visual_parent:
				view.reparent(visual_parent, false)
			var props: Dictionary = child.get_meta("roblox_properties", {})
			# Changes reach labels/frames as well as buttons. Layout is evaluated
			# against the visible viewport, not the invisible DataModel hierarchy.
			var style_hash := hash([props, visual_parent.size])
			if _styles.get(ref) != style_hash:
				Gui._apply_udim2_layout(view, props)
				Gui._apply_visual_style(view, class_name_, props)
				_styles[ref] = style_hash
			engine._sync_bound_gui_control(view, child)
			view.mouse_filter = Control.MOUSE_FILTER_STOP if view is BaseButton or view is LineEdit else Control.MOUSE_FILTER_PASS
			pending.append([child, _scroll_content(view, props) if view is ScrollContainer else view])
	# Layout objects live alongside their controls in Roblox. Apply them after
	# all children exist, including GUIs cloned out of tools during Play.
	for pair in decorators:
		var data: Node = pair[0]
		var view: Control = pair[1]
		var props: Dictionary = data.get_meta("roblox_properties", {})
		match str(data.get_meta("roblox_class", "")):
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
	for ref in _views.keys():
		if seen.has(ref): continue
		var stale: Variant = _views[ref]
		if is_instance_valid(stale): stale.queue_free()
		_views.erase(ref)
		_styles.erase(ref)

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
