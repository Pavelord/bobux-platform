@tool
class_name RobloxProperties
extends RefCounted

## Roblox-style Properties panel content builder for Bobux Studio.
##
## Produces a categorized, collapsible property list for the currently selected
## node — the same layout Roblox Studio uses (Data / Behavior / Appearance
## sections), so users coming from Roblox find familiar controls.
##
## The panel is rebuilt for each selection via `build_into(container, node,
## studio)`. Studio is the editor node that owns the block-editing callbacks
## (`_rebuild_block_material`, `_update_block_collision`, `_refresh_explorer`,
## `_commit_editor_history`); we route value changes back through those so the
## existing save/load + gizmo pipeline keeps working.

const ROBLOX_CLASS_META := "roblox_class"
const DEFAULT_BLOCK_DAMAGE := 25.0

const MATERIAL_OPTIONS := ["Plastic", "SmoothPlastic", "Wood", "WoodPlanks", "Concrete", "Metal", "Glass", "Neon", "Slate"]
const SHAPE_OPTIONS := ["Box", "Sphere", "Cylinder", "Wedge", "CornerWedge", "Truss", "Water", "Spawn", "Checkpoint", "Teleport"]
const SCRIPT_TYPES := ["Script", "LocalScript", "ModuleScript"]

var _studio: Node = null
var _target: Node = null
var _updating: bool = false
var _filter_text: String = ""


func set_filter_text(value: String) -> void:
	_filter_text = value.strip_edges().to_lower()


func build_into(container: VBoxContainer, node: Node, studio: Node) -> void:
	_studio = studio
	_target = node
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	if node == null or not is_instance_valid(node):
		var placeholder := Label.new()
		placeholder.text = "Select an instance to view its properties."
		placeholder.add_theme_color_override("font_color", Color("#777777"))
		placeholder.add_theme_font_size_override("font_size", 11)
		container.add_child(placeholder)
		return

	var roblox_class := str(node.get_meta(ROBLOX_CLASS_META, _infer_class(node)))

	# Build per-class property groups.
	match roblox_class:
		"Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", \
		"SpawnLocation", "Seat", "VehicleSeat", "UnionOperation", \
		"NegateOperation", "IntersectOperation":
			_build_part_properties(container, node)
		"Model", "Folder", "Configuration":
			_build_container_properties(container, node)
		"Tool", "HopperBin":
			_build_tool_properties(container, node)
		"Humanoid":
			_build_humanoid_properties(container, node)
		"BodyColors":
			_build_body_colors_properties(container, node)
		"Animator", "AnimationController":
			_build_animator_properties(container, node, roblox_class)
		"Attachment":
			_build_attachment_properties(container, node)
		"Motor6D", "Weld", "WeldConstraint", "HingeConstraint", "BallSocketConstraint", "SpringConstraint":
			_build_constraint_properties(container, node, roblox_class)
		"Terrain":
			_build_terrain_properties(container, node)
		"Script", "LocalScript", "ModuleScript":
			_build_script_properties(container, node)
		"PointLight", "SpotLight", "SurfaceLight":
			_build_light_properties(container, node, roblox_class)
		"Sound":
			_build_sound_properties(container, node)
		"Decal", "Texture":
			_build_decal_properties(container, node, roblox_class)
		"ScreenGui", "Frame", "TextLabel", "TextButton", "TextBox", \
		"ImageLabel", "ImageButton":
			_build_gui_properties(container, node, roblox_class)
		"Camera":
			_build_camera_properties(container, node)
		"RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction":
			_build_passthrough_properties(container, node, roblox_class)
		"BoolValue", "IntValue", "NumberValue", "StringValue", "Vector3Value", \
		"Color3Value", "CFrameValue", "BrickColorValue", "ObjectValue":
			_build_value_properties(container, node, roblox_class)
		_:
			if bool(node.get_meta("is_roblox_service", false)):
				_build_service_properties(container, node, roblox_class)
			else:
				_build_generic_properties(container, node)

	# Tags and Attributes belong to every Roblox Instance. Keep them in one
	# shared editor so authored and imported objects use the same persistence
	# contract instead of class-specific placeholders.
	_build_instance_metadata_sections(container, node)


# ── Section helpers ──────────────────────────────────────────────────────────

func _add_section(container: VBoxContainer, title: String) -> VBoxContainer:
	var header_btn := Button.new()
	header_btn.text = "v " + title
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.flat = true
	header_btn.custom_minimum_size = Vector2(0, 24)
	header_btn.add_theme_font_size_override("font_size", 11)
	header_btn.add_theme_color_override("font_color", Color("#333333"))
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color("#E6E8EB")
	header_style.border_color = Color("#C8CBD0")
	header_style.border_width_bottom = 1
	header_style.content_margin_left = 5
	header_style.content_margin_right = 5
	header_style.content_margin_top = 3
	header_style.content_margin_bottom = 3
	header_btn.add_theme_stylebox_override("normal", header_style)
	header_btn.add_theme_stylebox_override("hover", header_style)
	header_btn.add_theme_stylebox_override("pressed", header_style)
	header_btn.pressed.connect(_toggle_section.bind(header_btn))
	container.add_child(header_btn)

	var body := VBoxContainer.new()
	body.set_meta("section_title", title)
	body.add_theme_constant_override("separation", 0)
	body.visible = true
	header_btn.set_meta("body", body)
	container.add_child(body)
	return body


func _toggle_section(header_btn: Button) -> void:
	var body: VBoxContainer = header_btn.get_meta("body", null)
	if body == null:
		return
	body.visible = not body.visible
	header_btn.text = ("v " if body.visible else "> ") + header_btn.text.substr(2)


func _row(parent: VBoxContainer, label: String, control: Control) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 25)
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color.WHITE
	row_style.border_color = Color("#E0E2E5")
	row_style.border_width_bottom = 1
	row_style.content_margin_left = 5
	row_style.content_margin_right = 4
	row_panel.add_theme_stylebox_override("panel", row_style)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	row_panel.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(112, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#34373B"))
	hbox.add_child(lbl)
	var divider := VSeparator.new()
	divider.add_theme_color_override("separator", Color("#D7D9DC"))
	hbox.add_child(divider)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 22.0)
	_style_property_control(control)
	hbox.add_child(control)
	row_panel.visible = _filter_text.is_empty() or label.to_lower().find(_filter_text) >= 0
	parent.add_child(row_panel)

func _style_property_control(control: Control) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.WHITE
	normal.border_color = Color("#C8CBD0")
	normal.set_border_width_all(1)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color("#2B7CD3")
	if control is LineEdit:
		control.add_theme_stylebox_override("normal", normal)
		control.add_theme_stylebox_override("focus", focus)
		control.add_theme_font_size_override("font_size", 11)
	elif control is SpinBox:
		var edit := (control as SpinBox).get_line_edit()
		edit.add_theme_stylebox_override("normal", normal)
		edit.add_theme_stylebox_override("focus", focus)
		edit.add_theme_font_size_override("font_size", 11)
	elif control is OptionButton or control is ColorPickerButton:
		control.add_theme_stylebox_override("normal", normal)
		control.add_theme_stylebox_override("focus", focus)
		control.add_theme_font_size_override("font_size", 11)
	elif control is HSlider:
		control.custom_minimum_size.y = 22


func _vec3_row(parent: VBoxContainer, label: String, value: Vector3, step: float, min_val: float, max_val: float, on_change: Callable) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = label
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color("#555555"))
	vbox.add_child(title)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	var spinboxes: Array[SpinBox] = []
	var axis_labels: PackedStringArray = PackedStringArray(["X", "Y", "Z"])
	var axis_values: PackedFloat32Array = PackedFloat32Array([value.x, value.y, value.z])
	for axis_idx in range(3):
		var axis_label: String = axis_labels[axis_idx]
		var sp := SpinBox.new()
		sp.step = step
		sp.min_value = min_val
		sp.max_value = max_val
		sp.value = float(axis_values[axis_idx])
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.suffix = axis_label
		spinboxes.append(sp)
		hbox.add_child(sp)
	vbox.add_child(hbox)
	parent.add_child(vbox)
	# Wire changes — bundle all three axes into the callback.
	if on_change.is_null():
		for readonly_sp in spinboxes:
			readonly_sp.editable = false
		return
	for sp in spinboxes:
		sp.value_changed.connect(func(_v: float):
			on_change.call(Vector3(spinboxes[0].value, spinboxes[1].value, spinboxes[2].value)))


func _color_row(parent: VBoxContainer, label: String, color: Color, on_change: Callable) -> void:
	var cp := ColorPickerButton.new()
	cp.color = color
	cp.custom_minimum_size = Vector2(40, 24)
	if not on_change.is_null():
		cp.color_changed.connect(on_change)
	else:
		cp.disabled = true
	_row(parent, label, cp)


func _bool_row(parent: VBoxContainer, label: String, value: bool, on_change: Callable) -> void:
	var cb := CheckBox.new()
	cb.button_pressed = value
	if not on_change.is_null():
		cb.toggled.connect(on_change)
	else:
		cb.disabled = true
	_row(parent, label, cb)


func _string_row(parent: VBoxContainer, label: String, value: String, on_change: Callable) -> void:
	var le := LineEdit.new()
	le.text = value
	if not on_change.is_null():
		le.text_changed.connect(on_change)
	else:
		le.editable = false
	_row(parent, label, le)


func _option_row(parent: VBoxContainer, label: String, options: Array, value: String, on_change: Callable) -> void:
	var ob := OptionButton.new()
	for opt in options:
		ob.add_item(opt)
	var idx := options.find(value)
	if idx >= 0:
		ob.select(idx)
	if not on_change.is_null():
		ob.item_selected.connect(func(i: int): on_change.call(options[i]))
	else:
		ob.disabled = true
	_row(parent, label, ob)


func _slider_row(parent: VBoxContainer, label: String, value: float, min_val: float, max_val: float, step: float, on_change: Callable) -> void:
	var sl := HSlider.new()
	sl.min_value = min_val
	sl.max_value = max_val
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not on_change.is_null():
		sl.value_changed.connect(on_change)
	else:
		sl.editable = false
	_row(parent, label, sl)


# ── Part properties ─────────────────────────────────────────────────────────

func _build_part_properties(container: VBoxContainer, node: Node) -> void:
	var part := node as MeshInstance3D
	if part == null:
		_build_generic_properties(container, node)
		return

	var roblox_class := str(part.get_meta(ROBLOX_CLASS_META, "Part"))
	var shape_name := str(part.get_meta("shape_type", "Box"))
	var mat: StandardMaterial3D = part.get_active_material(0) as StandardMaterial3D
	var color: Color = part.get_meta("bobux_color", mat.albedo_color if mat != null else Color(0.639, 0.635, 0.647))

	# --- Appearance ---
	var appearance := _add_section(container, "Appearance")
	_option_row(appearance, "LevelOfDetail", ["Automatic", "Disabled", "Auto"], "Automatic", Callable())
	_color_row(appearance, "BrickColor", color, _on_part_color_changed.bind(part))
	_bool_row(appearance, "CastShadow", part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, _on_part_cast_shadow_changed.bind(part))
	_color_row(appearance, "Color", color, _on_part_color_changed.bind(part))
	_option_row(appearance, "Material", MATERIAL_OPTIONS, str(part.get_meta("material_type", "Plastic")), _on_part_material_changed.bind(part))
	_string_row(appearance, "MaterialVariant", str(part.get_meta("MaterialVariant", "")), _on_part_meta_string_changed.bind(part, "MaterialVariant"))
	_slider_row(appearance, "Transparency", float(part.get_meta("transparency", 0.0)), 0.0, 1.0, 0.05, _on_part_transparency_changed.bind(part))
	_slider_row(appearance, "Reflectance", float(part.get_meta("Reflectance", 0.0)), 0.0, 1.0, 0.05, _on_part_reflectance_changed.bind(part))
	_option_row(appearance, "Shape", SHAPE_OPTIONS, shape_name, _on_part_shape_changed.bind(part))

	# --- Data ---
	var data := _add_section(container, "Data")
	_bool_row(data, "Archivable", bool(part.get_meta("Archivable", true)), _on_part_meta_bool_changed.bind(part, "Archivable"))
	_string_row(data, "ClassName", roblox_class, Callable())
	_string_row(data, "Name", str(part.get_meta("block_name", part.name)), _on_part_name_changed.bind(part))
	_string_row(data, "Parent", part.get_parent().name if part.get_parent() else "", Callable())
	_string_row(data, "UniqueId", str(part.get_instance_id()), Callable())

	# --- Transform (CFrame + Size like Roblox) ---
	var transform := _add_section(container, "Transform")
	_vec3_row(transform, "Origin Position", part.position, 0.5, -10000, 10000, _on_part_position_changed.bind(part))
	_vec3_row(transform, "Orientation", part.rotation_degrees, 1.0, -360, 360, _on_part_rotation_changed.bind(part))
	var scale: Vector3 = part.scale
	_vec3_row(transform, "Size", scale, 0.5, 0.1, 10000, _on_part_size_changed.bind(part))

	# --- Behavior ---
	var behavior := _add_section(container, "Behavior")
	_option_row(behavior, "ModelStreaming", ["Default", "Atomic", "PersistentPerPlayer", "Emphasized"], "Default", Callable())
	_bool_row(behavior, "Anchored", bool(part.get_meta("anchored", true)), _on_part_anchored_changed.bind(part))
	_bool_row(behavior, "CanCollide", bool(part.get_meta("can_collide", true)), _on_part_can_collide_changed.bind(part))
	_bool_row(behavior, "CanQuery", bool(part.get_meta("CanQuery", true)), _on_part_meta_bool_changed.bind(part, "CanQuery"))
	_bool_row(behavior, "CanTouch", bool(part.get_meta("CanTouch", true)), _on_part_meta_bool_changed.bind(part, "CanTouch"))
	_bool_row(behavior, "Locked", bool(part.get_meta("Locked", false)), _on_part_meta_bool_changed.bind(part, "Locked"))
	_bool_row(behavior, "Massless", bool(part.get_meta("Massless", false)), _on_part_meta_bool_changed.bind(part, "Massless"))

	var permissions := _add_section(container, "Permissions")
	_bool_row(permissions, "IsSandboxed", false, Callable())

	# --- Custom Bobux gameplay (kept, but grouped) ---
	var bobux := _add_section(container, "Bobux Gameplay")
	_bool_row(bobux, "DealsDamage", bool(part.get_meta("deals_damage", false)), _on_part_damage_enabled_changed.bind(part))
	_spinbox_row(bobux, "DamageAmount", float(part.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)), 1.0, 0.0, 1000.0, _on_part_damage_amount_changed.bind(part))


func _spinbox_row(parent: VBoxContainer, label: String, value: float, step: float, min_val: float, max_val: float, on_change: Callable) -> void:
	var sp := SpinBox.new()
	sp.step = step
	sp.min_value = min_val
	sp.max_value = max_val
	sp.value = value
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not on_change.is_null():
		sp.value_changed.connect(on_change)
	else:
		sp.editable = false
	_row(parent, label, sp)


# ── Container (Model/Folder) properties ─────────────────────────────────────

func _build_container_properties(container: VBoxContainer, node: Node) -> void:
	var roblox_class := str(node.get_meta(ROBLOX_CLASS_META, "Model"))
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", roblox_class, Callable())
	_string_row(data, "Parent", str(node.get_parent().name) if node.get_parent() != null else "", Callable())
	_bool_row(data, "Archivable", bool(properties.get("Archivable", node.get_meta("Archivable", true))), _on_meta_bool_changed.bind(node, "Archivable"))
	# Containers show their world transform so designers can move whole groups.
	var n3d := node as Node3D
	if n3d != null:
		var transform := _add_section(container, "Transform")
		_vec3_row(transform, "Position", n3d.position, 0.5, -10000, 10000, _on_node_position_changed.bind(n3d))
		_vec3_row(transform, "Orientation", n3d.rotation_degrees, 1.0, -360, 360, _on_node_rotation_changed.bind(n3d))
		if roblox_class == "Model":
			var pivot := _add_section(container, "Pivot")
			_string_row(pivot, "PrimaryPart", str(properties.get("PrimaryPart", node.get_meta("PrimaryPart", ""))), _on_model_primary_part_changed.bind(node))
			_spinbox_row(pivot, "Scale", float(properties.get("Scale", node.get_meta("ModelScale", n3d.scale.x))), 0.05, 0.01, 100.0, _on_model_scale_changed.bind(n3d))
			var world_pivot := n3d.global_position if n3d.is_inside_tree() else n3d.position
			_vec3_row(pivot, "WorldPivot", world_pivot, 0.5, -10000, 10000, _on_model_world_pivot_changed.bind(n3d))
			var behavior := _add_section(container, "Behavior")
			_option_row(behavior, "ModelStreamingMode", ["Default", "Atomic", "Persistent", "PersistentPerPlayer"], str(properties.get("ModelStreamingMode", "Default")), _on_meta_string_changed.bind(node, "ModelStreamingMode"))


func _build_tool_properties(container: VBoxContainer, node: Node) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.get_meta("Name", node.name)), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", str(node.get_meta(ROBLOX_CLASS_META, "Tool")), Callable())
	_string_row(data, "Parent", str(node.get_parent().name) if node.get_parent() != null else "", Callable())
	_bool_row(data, "Archivable", bool(properties.get("Archivable", true)), _on_meta_bool_changed.bind(node, "Archivable"))

	var appearance := _add_section(container, "Appearance")
	_string_row(appearance, "ToolTip", str(properties.get("ToolTip", node.get_meta("ToolTip", ""))), _on_meta_string_changed.bind(node, "ToolTip"))
	_string_row(appearance, "TextureId", str(properties.get("TextureId", "")), _on_meta_string_changed.bind(node, "TextureId"))

	var behavior := _add_section(container, "Behavior")
	_bool_row(behavior, "CanBeDropped", bool(properties.get("CanBeDropped", true)), _on_meta_bool_changed.bind(node, "CanBeDropped"))
	_bool_row(behavior, "Enabled", bool(properties.get("Enabled", true)), _on_meta_bool_changed.bind(node, "Enabled"))
	_bool_row(behavior, "ManualActivationOnly", bool(properties.get("ManualActivationOnly", false)), _on_meta_bool_changed.bind(node, "ManualActivationOnly"))
	_bool_row(behavior, "RequiresHandle", bool(properties.get("RequiresHandle", true)), _on_meta_bool_changed.bind(node, "RequiresHandle"))

	var grip := _add_section(container, "Grip")
	_vec3_row(grip, "GripPos", _property_vector3(properties.get("GripPos", Vector3.ZERO)), 0.05, -100.0, 100.0, _on_meta_vector_changed.bind(node, "GripPos"))
	_vec3_row(grip, "GripForward", _property_vector3(properties.get("GripForward", Vector3(0.0, 0.0, -1.0))), 0.05, -1.0, 1.0, _on_meta_vector_changed.bind(node, "GripForward"))
	_vec3_row(grip, "GripRight", _property_vector3(properties.get("GripRight", Vector3(1.0, 0.0, 0.0))), 0.05, -1.0, 1.0, _on_meta_vector_changed.bind(node, "GripRight"))
	_vec3_row(grip, "GripUp", _property_vector3(properties.get("GripUp", Vector3(0.0, 1.0, 0.0))), 0.05, -1.0, 1.0, _on_meta_vector_changed.bind(node, "GripUp"))


func _build_service_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var data := _add_section(container, "Data")
	var lbl := Label.new()
	lbl.text = "Service: " + roblox_class
	lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	data.add_child(lbl)


func _build_humanoid_properties(container: VBoxContainer, node: Node) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "RigType", str(properties.get("RigType", "R6")), Callable())
	var behavior := _add_section(container, "Behavior")
	_spinbox_row(behavior, "WalkSpeed", float(properties.get("WalkSpeed", 16.0)), 0.5, 0.0, 100.0, _on_meta_number_changed.bind(node, "WalkSpeed"))
	_spinbox_row(behavior, "JumpPower", float(properties.get("JumpPower", 50.0)), 0.5, 0.0, 200.0, _on_meta_number_changed.bind(node, "JumpPower"))
	_spinbox_row(behavior, "HipHeight", float(properties.get("HipHeight", 2.0)), 0.1, 0.0, 20.0, _on_meta_number_changed.bind(node, "HipHeight"))
	_bool_row(behavior, "AutoRotate", bool(properties.get("AutoRotate", true)), _on_meta_bool_changed.bind(node, "AutoRotate"))
	var health := _add_section(container, "Health")
	_spinbox_row(health, "Health", float(properties.get("Health", 100.0)), 1.0, 0.0, 10000.0, _on_meta_number_changed.bind(node, "Health"))
	_spinbox_row(health, "MaxHealth", float(properties.get("MaxHealth", 100.0)), 1.0, 1.0, 10000.0, _on_meta_number_changed.bind(node, "MaxHealth"))


func _build_body_colors_properties(container: VBoxContainer, node: Node) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", "BodyColors", Callable())
	var appearance := _add_section(container, "Appearance")
	var mappings := [
		["HeadColor3", "Head"],
		["TorsoColor3", "Torso"],
		["LeftArmColor3", "Left Arm"],
		["RightArmColor3", "Right Arm"],
		["LeftLegColor3", "Left Leg"],
		["RightLegColor3", "Right Leg"],
	]
	for mapping in mappings:
		var property_name := str(mapping[0])
		var part_name := str(mapping[1])
		_color_row(appearance, property_name, _property_color(properties.get(property_name, Color.WHITE)), _on_body_color_changed.bind(node, property_name, part_name))


func _build_animator_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", roblox_class, Callable())
	_string_row(data, "Parent", str(node.get_parent().name) if node.get_parent() != null else "", Callable())
	var playback := _add_section(container, "Playback")
	_bool_row(playback, "Enabled", bool(node.get_meta("Enabled", true)), _on_meta_bool_changed.bind(node, "Enabled"))
	_spinbox_row(playback, "Speed", float(node.get_meta("Speed", 1.0)), 0.05, 0.0, 10.0, _on_meta_number_changed.bind(node, "Speed"))
	_string_row(playback, "Tracks", str(node.get_meta("AnimationTracks", 0)), Callable())


func _build_attachment_properties(container: VBoxContainer, node: Node) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	if node is Node3D:
		var transform := _add_section(container, "Transform")
		_vec3_row(transform, "Position", (node as Node3D).position, 0.05, -10000, 10000, _on_node_position_changed.bind(node as Node3D))
		_vec3_row(transform, "Orientation", (node as Node3D).rotation_degrees, 1.0, -360, 360, _on_node_rotation_changed.bind(node as Node3D))


func _build_constraint_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "ClassName", roblox_class, Callable())
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "Part0", str(node.get_meta("Part0", "")), Callable())
	_string_row(data, "Part1", str(node.get_meta("Part1", "")), Callable())
	var behavior := _add_section(container, "Behavior")
	_bool_row(behavior, "Enabled", bool(node.get_meta("Enabled", true)), _on_direct_meta_bool_changed.bind(node, "Enabled"))


func _build_terrain_properties(container: VBoxContainer, node: Node) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {})
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "CellSize", str(properties.get("CellSize", 2.0)), Callable())
	_string_row(data, "VoxelCells", str((properties.get("Cells", []) as Array).size()), Callable())


func _build_script_properties(container: VBoxContainer, node: Node) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_option_row(data, "ClassName", SCRIPT_TYPES, str(node.get_meta("script_type", "Script")), _on_script_type_changed.bind(node))

	var src := _add_section(container, "Source")
	var source_label := Label.new()
	var source_text: String = str(node.get_meta("code", node.get_meta("lua_source", "")))
	source_label.text = "Source: %d chars" % source_text.length()
	source_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	src.add_child(source_label)
	var open_button := Button.new()
	open_button.text = "Open Script Editor"
	open_button.pressed.connect(_open_script_editor.bind(node))
	src.add_child(open_button)

	var behavior := _add_section(container, "Behavior")
	_bool_row(behavior, "Enabled", not bool(node.get_meta("disabled", false)), _on_script_enabled_changed.bind(node))
	_bool_row(behavior, "RunContext", false, Callable())


func _build_light_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var light := node as Light3D
	if light == null:
		_build_generic_properties(container, node)
		return
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	var appearance := _add_section(container, "Appearance")
	_color_row(appearance, "Color", light.light_color, _on_light_color_changed.bind(light))
	_slider_row(appearance, "Brightness", light.light_energy, 0.0, 20.0, 0.1, _on_light_energy_changed.bind(light))
	if roblox_class == "SpotLight":
		_slider_row(appearance, "Angle", light.spot_angle, 0.0, 180.0, 1.0, _on_spot_angle_changed.bind(light))


func _build_sound_properties(container: VBoxContainer, node: Node) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "SoundId", str(properties.get("SoundId", node.get_meta("SoundId", ""))), _on_meta_string_changed.bind(node, "SoundId"))
	var behavior := _add_section(container, "Behavior")
	_slider_row(behavior, "Volume", float(properties.get("Volume", 0.5)), 0.0, 4.0, 0.05, _on_sound_volume_changed.bind(node))
	_slider_row(behavior, "PlaybackSpeed", float(properties.get("PlaybackSpeed", 1.0)), 0.05, 4.0, 0.05, _on_sound_speed_changed.bind(node))
	_bool_row(behavior, "Looped", bool(properties.get("Looped", false)), _on_sound_looped_changed.bind(node))
	_bool_row(behavior, "Playing", bool(properties.get("Playing", false)), _on_sound_playing_changed.bind(node))


func _build_decal_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", roblox_class, Callable())
	var appearance := _add_section(container, "Appearance")
	_string_row(appearance, "Texture", str(properties.get("Texture", node.get_meta("Texture", ""))), _on_meta_string_changed.bind(node, "Texture"))
	_slider_row(appearance, "Transparency", float(properties.get("Transparency", node.get_meta("Transparency", 0.0))), 0.0, 1.0, 0.05, _on_meta_number_changed.bind(node, "Transparency"))
	_color_row(appearance, "Color3", _property_color(properties.get("Color3", Color.WHITE)), _on_meta_color_changed.bind(node, "Color3"))


func _build_value_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	var value: Variant = properties.get("Value", node.get_meta("Value", _default_value_for_class(roblox_class)))
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", roblox_class, Callable())
	match roblox_class:
		"BoolValue":
			_bool_row(data, "Value", bool(value), _on_meta_bool_changed.bind(node, "Value"))
		"IntValue", "NumberValue":
			_spinbox_row(data, "Value", float(value), 1.0 if roblox_class == "IntValue" else 0.1, -1000000000.0, 1000000000.0, _on_meta_number_changed.bind(node, "Value"))
		"Vector3Value":
			_vec3_row(data, "Value", _property_vector3(value), 0.1, -1000000.0, 1000000.0, _on_meta_vector_changed.bind(node, "Value"))
		"Color3Value", "BrickColorValue":
			_color_row(data, "Value", _property_color(value), _on_meta_color_changed.bind(node, "Value"))
		_:
			_string_row(data, "Value", str(value), _on_meta_string_changed.bind(node, "Value"))


func _default_value_for_class(roblox_class: String) -> Variant:
	match roblox_class:
		"BoolValue":
			return false
		"IntValue", "NumberValue":
			return 0
		"Vector3Value":
			return Vector3.ZERO
		"Color3Value", "BrickColorValue":
			return Color.WHITE
		_:
			return ""


func _build_gui_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	var ctrl := node as Control
	if ctrl != null:
		var transform := _add_section(container, "Layout")
		_vec3_row(transform, "Position", Vector3(ctrl.position.x, ctrl.position.y, 0), 1.0, -9999, 9999, _on_control_position_changed.bind(ctrl))
		_vec3_row(transform, "Size", Vector3(ctrl.size.x, ctrl.size.y, 0), 1.0, 0, 9999, _on_control_size_changed.bind(ctrl))
		_spinbox_row(transform, "ZIndex", float(ctrl.z_index), 1.0, -1000.0, 1000.0, _on_control_z_index_changed.bind(ctrl))
		var appearance := _add_section(container, "Appearance")
		_bool_row(appearance, "Visible", ctrl.visible, _on_control_visible_changed.bind(ctrl))
		if ctrl is Label:
			_string_row(appearance, "Text", (ctrl as Label).text, _on_control_text_changed.bind(ctrl))
		elif ctrl is Button:
			_string_row(appearance, "Text", (ctrl as Button).text, _on_control_text_changed.bind(ctrl))
		elif ctrl is LineEdit:
			_string_row(appearance, "Text", (ctrl as LineEdit).text, _on_control_text_changed.bind(ctrl))


func _build_camera_properties(container: VBoxContainer, node: Node) -> void:
	var cam := node as Camera3D
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	if cam != null:
		var appearance := _add_section(container, "Appearance")
		_slider_row(appearance, "FieldOfView", cam.fov, 1.0, 170.0, 1.0, _on_camera_fov_changed.bind(cam))


func _build_passthrough_properties(container: VBoxContainer, node: Node, roblox_class: String) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	var note := Label.new()
	note.text = "%s: fires across the client/server boundary. Use Connect to subscribe." % roblox_class
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	data.add_child(note)


func _build_instance_metadata_sections(container: VBoxContainer, node: Node) -> void:
	var tags_section := _add_section(container, "Tags")
	var tags_text := ", ".join(PackedStringArray(_get_node_tags(node)))
	_string_row(tags_section, "Tags", tags_text, _on_tags_changed.bind(node))

	var attributes_section := _add_section(container, "Attributes")
	var attributes := _get_node_attributes(node)
	var keys: Array[String] = []
	for key_variant in attributes.keys():
		keys.append(str(key_variant))
	keys.sort()
	for key in keys:
		_attribute_row(attributes_section, node, key, attributes[key])

	var editor := HBoxContainer.new()
	editor.add_theme_constant_override("separation", 4)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Attribute name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_child(name_input)
	var value_input := LineEdit.new()
	value_input.placeholder_text = "Value"
	value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_child(value_input)
	var add_button := Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "Add attribute"
	add_button.custom_minimum_size = Vector2(28, 24)
	add_button.pressed.connect(func():
		var attribute_name := name_input.text.strip_edges()
		if attribute_name.is_empty():
			return
		_set_node_attribute(node, attribute_name, _parse_attribute_value(value_input.text))
		_refresh_property_editor(node)
	)
	editor.add_child(add_button)
	_row(attributes_section, "New", editor)


func _attribute_row(parent: VBoxContainer, node: Node, key: String, value: Variant) -> void:
	var editor := HBoxContainer.new()
	editor.add_theme_constant_override("separation", 4)
	var value_input := LineEdit.new()
	value_input.text = _attribute_value_text(value)
	value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_input.text_changed.connect(func(text_value: String):
		_set_node_attribute(node, key, _parse_attribute_value(text_value))
	)
	editor.add_child(value_input)
	var remove_button := Button.new()
	remove_button.text = "x"
	remove_button.tooltip_text = "Remove attribute"
	remove_button.custom_minimum_size = Vector2(28, 24)
	remove_button.pressed.connect(func():
		_remove_node_attribute(node, key)
		_refresh_property_editor(node)
	)
	editor.add_child(remove_button)
	_row(parent, key, editor)


func _replace_nul_codepoints(value: String, replacement: String) -> String:
	var result := ""
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		result += replacement if codepoint == 0 else String.chr(codepoint)
	return result


func _get_node_tags(node: Node) -> Array[String]:
	var raw: Variant = node.get_meta("roblox_tags") if node.has_meta("roblox_tags") else null
	if raw == null:
		var properties: Dictionary = node.get_meta("roblox_properties", {})
		raw = properties.get("Tags", [])
	var result: Array[String] = []
	if raw is Array:
		for value in raw as Array:
			var tag := str(value).strip_edges()
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	elif raw is String:
		var normalized := _replace_nul_codepoints(str(raw), ",")
		for value in normalized.split(",", false):
			var tag := str(value).strip_edges()
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	return result


func _get_node_attributes(node: Node) -> Dictionary:
	var raw: Variant = node.get_meta("roblox_attributes") if node.has_meta("roblox_attributes") else null
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	var properties: Dictionary = node.get_meta("roblox_properties", {})
	if properties.get("Attributes", {}) is Dictionary:
		return (properties.get("Attributes", {}) as Dictionary).duplicate(true)
	return {}


func _on_tags_changed(value: String, node: Node) -> void:
	var tags: Array[String] = []
	for raw_tag in value.split(",", false):
		var tag := str(raw_tag).strip_edges()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	node.set_meta("roblox_tags", tags)
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties["Tags"] = tags.duplicate()
	node.set_meta("roblox_properties", properties)
	_commit_property_change()


func _set_node_attribute(node: Node, key: String, value: Variant) -> void:
	node.set_meta("attribute_" + key, value)
	var attributes := _get_node_attributes(node)
	attributes[key] = value
	node.set_meta("roblox_attributes", attributes)
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties["Attributes"] = attributes.duplicate(true)
	node.set_meta("roblox_properties", properties)
	_commit_property_change()


func _remove_node_attribute(node: Node, key: String) -> void:
	if node.has_meta("attribute_" + key): node.remove_meta("attribute_" + key)
	var attributes := _get_node_attributes(node)
	attributes.erase(key)
	node.set_meta("roblox_attributes", attributes)
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties["Attributes"] = attributes.duplicate(true)
	node.set_meta("roblox_properties", properties)
	_commit_property_change()


func _parse_attribute_value(text_value: String) -> Variant:
	var value := text_value.strip_edges()
	var lowered := value.to_lower()
	if lowered == "true":
		return true
	if lowered == "false":
		return false
	if value.is_valid_int():
		return value.to_int()
	if value.is_valid_float():
		return value.to_float()
	if (value.begins_with("[") and value.ends_with("]")) or (value.begins_with("{") and value.ends_with("}")):
		var parsed: Variant = JSON.parse_string(value)
		if parsed != null:
			return parsed
	return value


func _attribute_value_text(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)


func _refresh_property_editor(node: Node) -> void:
	if _studio != null and _studio.has_method("_show_properties_for_node"):
		_studio.call_deferred("_show_properties_for_node", node)


func _build_generic_properties(container: VBoxContainer, node: Node) -> void:
	var data := _add_section(container, "Data")
	_string_row(data, "Name", str(node.name), _on_node_name_changed.bind(node))
	_string_row(data, "ClassName", str(node.get_meta(ROBLOX_CLASS_META, _infer_class(node))), Callable())
	_string_row(data, "Parent", str(node.get_parent().name) if node.get_parent() != null else "", Callable())
	_bool_row(data, "Archivable", bool(node.get_meta("Archivable", true)), _on_meta_bool_changed.bind(node, "Archivable"))


func _infer_class(node: Node) -> String:
	if node.is_in_group("studio_parts"):
		return "Part"
	if node.is_in_group("bobux_scripts"):
		return str(node.get_meta("script_type", "Script"))
	if node is MeshInstance3D:
		return "Part"
	if node is Camera3D:
		return "Camera"
	if node is Light3D:
		return "Light"
	if node is AudioStreamPlayer3D:
		return "Sound"
	if node is Control:
		return "GuiObject"
	return "Instance"


# ── Change handlers (route back through studio callbacks) ───────────────────

func _refresh_after_block(part: MeshInstance3D) -> void:
	if _studio == null:
		return
	if _studio.has_method("_update_block_collision"):
		_studio._update_block_collision(part)
	if _studio.has_method("_refresh_explorer"):
		_studio._refresh_explorer()
	if _studio.has_method("_update_selection_status"):
		_studio._update_selection_status()
	if _studio.has_method("_commit_editor_history"):
		_studio._commit_editor_history("Edit Property")


func _on_meta_number_changed(value: float, node: Node, key: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties[key] = value
	node.set_meta("roblox_properties", properties)
	node.set_meta(key, value)
	_commit_property_change()


func _on_meta_bool_changed(value: bool, node: Node, key: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties[key] = value
	node.set_meta("roblox_properties", properties)
	node.set_meta(key, value)
	_commit_property_change()


func _on_meta_string_changed(value: String, node: Node, key: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties[key] = value
	node.set_meta("roblox_properties", properties)
	node.set_meta(key, value)
	_commit_property_change()


func _on_meta_vector_changed(value: Vector3, node: Node, key: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties[key] = [value.x, value.y, value.z]
	node.set_meta("roblox_properties", properties)
	node.set_meta(key, value)
	_commit_property_change()


func _on_meta_color_changed(value: Color, node: Node, key: String) -> void:
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties[key] = [value.r, value.g, value.b]
	node.set_meta("roblox_properties", properties)
	node.set_meta(key, value)
	_commit_property_change()


func _property_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		var data := value as Dictionary
		return Vector3(float(data.get("x", data.get("X", 0.0))), float(data.get("y", data.get("Y", 0.0))), float(data.get("z", data.get("Z", 0.0))))
	return Vector3.ZERO


func _property_color(value: Variant) -> Color:
	if value is Color:
		return value as Color
	if value is Array and (value as Array).size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if (value as Array).size() >= 4 else 1.0)
	if value is Dictionary:
		var data := value as Dictionary
		return Color(
			float(data.get("r", data.get("R", data.get("x", 1.0)))),
			float(data.get("g", data.get("G", data.get("y", 1.0)))),
			float(data.get("b", data.get("B", data.get("z", 1.0)))),
			float(data.get("a", data.get("A", 1.0)))
		)
	if value is String and Color.html_is_valid(str(value)):
		return Color.from_string(str(value), Color.WHITE)
	return Color.WHITE


func _commit_property_change() -> void:
	if _studio != null and _studio.has_method("_commit_editor_history"):
		_studio.call("_commit_editor_history", "Edit Property")


func _on_direct_meta_bool_changed(value: bool, node: Node, key: String) -> void:
	node.set_meta(key, value)
	_commit_property_change()


func _on_body_color_changed(value: Color, body_colors: Node, property_name: String, part_name: String) -> void:
	if body_colors == null:
		return
	_on_meta_color_changed(value, body_colors, property_name)
	var character := body_colors.get_parent()
	if character == null:
		return
	var part := character.find_child(part_name, true, false) as MeshInstance3D
	if part == null:
		return
	part.set_meta("block_color", value)
	part.set_meta("bobux_color", Color(value.r, value.g, value.b, 1.0))
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio.call("_rebuild_block_material", part)


func _on_part_meta_bool_changed(value: bool, part: MeshInstance3D, key: String) -> void:
	if part == null:
		return
	part.set_meta(key, value)
	_refresh_after_block(part)


func _on_part_meta_string_changed(value: String, part: MeshInstance3D, key: String) -> void:
	if part == null:
		return
	part.set_meta(key, value)
	_refresh_after_block(part)


func _on_part_name_changed(new_name: String, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("block_name", new_name)
	part.name = new_name
	_refresh_after_block(part)


func _on_part_class_changed(new_class: String, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta(ROBLOX_CLASS_META, new_class)
	_refresh_after_block(part)


func _on_part_position_changed(pos: Vector3, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.position = pos
	_refresh_after_block(part)


func _on_part_rotation_changed(rot_deg: Vector3, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.rotation_degrees = rot_deg
	_refresh_after_block(part)


func _on_part_size_changed(size: Vector3, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.scale = size
	_refresh_after_block(part)


func _on_part_anchored_changed(value: bool, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("anchored", value)
	_refresh_after_block(part)


func _on_part_can_collide_changed(value: bool, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("can_collide", value)
	if _studio != null and _studio.has_method("_rebuild_block_helpers"):
		_studio._rebuild_block_helpers(part)
	_refresh_after_block(part)


func _on_part_color_changed(color: Color, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("block_color", color)
	part.set_meta("bobux_color", Color(color.r, color.g, color.b, 1.0))
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio._rebuild_block_material(part)
	_refresh_after_block(part)


func _on_part_cast_shadow_changed(value: bool, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if value else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_after_block(part)


func _on_part_material_changed(material_name: String, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("material_type", material_name)
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio._rebuild_block_material(part)
	_refresh_after_block(part)


func _on_part_transparency_changed(value: float, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("transparency", value)
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio._rebuild_block_material(part)
	_refresh_after_block(part)


func _on_part_reflectance_changed(value: float, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("Reflectance", value)
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio.call("_rebuild_block_material", part)
	_refresh_after_block(part)


func _on_part_shape_changed(shape: String, part: MeshInstance3D) -> void:
	if part == null:
		return
	var previous_material := str(part.get_meta("material_type", "Plastic"))
	part.set_meta("shape_type", shape)
	part.set_meta("is_spawn", shape == "Spawn")
	if shape == "Water":
		part.set_meta("material_type", "Water")
		part.set_meta("can_collide", false)
		part.set_meta("transparency", maxf(float(part.get_meta("transparency", 0.0)), 0.28))
		part.set_meta("bobux_color", Color(0.12, 0.55, 0.92, 0.72))
	elif previous_material.strip_edges().to_lower() == "water":
		part.set_meta("material_type", "Plastic")
		part.set_meta("can_collide", true)
		part.set_meta("transparency", 0.0)
	if _studio != null and _studio.has_method("_create_mesh_for_shape"):
		var replacement: Variant = _studio.call("_create_mesh_for_shape", shape)
		if replacement is Mesh:
			part.mesh = replacement as Mesh
	if _studio != null and _studio.has_method("_rebuild_block_material"):
		_studio._rebuild_block_material(part)
	if _studio != null and _studio.has_method("_update_block_collision"):
		_studio.call("_update_block_collision", part)
	elif _studio != null and _studio.has_method("_rebuild_block_helpers"):
		_studio._rebuild_block_helpers(part)
	_refresh_after_block(part)


func _on_part_damage_enabled_changed(value: bool, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("deals_damage", value)
	_refresh_after_block(part)


func _on_part_damage_amount_changed(value: float, part: MeshInstance3D) -> void:
	if part == null:
		return
	part.set_meta("damage_amount", value)
	_refresh_after_block(part)


func _on_node_name_changed(new_name: String, node: Node) -> void:
	if node == null:
		return
	node.name = new_name
	node.set_meta("block_name", new_name)
	node.set_meta("Name", new_name)
	if _studio != null and _studio.has_method("_refresh_explorer"):
		_studio._refresh_explorer()
	_commit_property_change()


func _on_node_position_changed(pos: Vector3, n3d: Node3D) -> void:
	if n3d == null:
		return
	n3d.position = pos
	_commit_property_change()


func _on_node_rotation_changed(rot: Vector3, n3d: Node3D) -> void:
	if n3d == null:
		return
	n3d.rotation_degrees = rot
	_commit_property_change()


func _on_model_primary_part_changed(value: String, node: Node) -> void:
	if node == null:
		return
	var primary_part_name := value.strip_edges()
	node.set_meta("PrimaryPart", primary_part_name)
	var properties: Dictionary = node.get_meta("roblox_properties", {}).duplicate(true)
	properties["PrimaryPart"] = primary_part_name
	node.set_meta("roblox_properties", properties)
	_commit_property_change()


func _on_model_scale_changed(value: float, model: Node3D) -> void:
	if model == null:
		return
	var scale_value := maxf(value, 0.01)
	model.scale = Vector3.ONE * scale_value
	model.set_meta("ModelScale", scale_value)
	var properties: Dictionary = model.get_meta("roblox_properties", {}).duplicate(true)
	properties["Scale"] = scale_value
	model.set_meta("roblox_properties", properties)
	_commit_property_change()


func _on_model_world_pivot_changed(value: Vector3, model: Node3D) -> void:
	if model == null:
		return
	if model.is_inside_tree():
		model.global_position = value
	else:
		model.position = value
	var properties: Dictionary = model.get_meta("roblox_properties", {}).duplicate(true)
	properties["WorldPivot"] = [value.x, value.y, value.z]
	model.set_meta("roblox_properties", properties)
	_commit_property_change()


func _on_script_type_changed(new_type: String, node: Node) -> void:
	if node == null:
		return
	node.set_meta("script_type", new_type)
	node.set_meta(ROBLOX_CLASS_META, new_type)
	if _studio != null and _studio.has_method("_refresh_explorer"):
		_studio._refresh_explorer()
	_commit_property_change()


func _on_script_enabled_changed(value: bool, node: Node) -> void:
	if node == null:
		return
	node.set_meta("enabled", value)
	node.set_meta("disabled", not value)
	_commit_property_change()


func _open_script_editor(node: Node) -> void:
	if node == null or _studio == null:
		return
	if _studio.has_method("_open_script_in_editor"):
		_studio.call("_open_script_in_editor", node)


func _on_sound_volume_changed(value: float, node: Node) -> void:
	_on_meta_number_changed(value, node, "Volume")
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).volume_db = linear_to_db(maxf(value, 0.0001)) if value > 0.0 else -80.0
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).volume_db = linear_to_db(maxf(value, 0.0001)) if value > 0.0 else -80.0


func _on_sound_speed_changed(value: float, node: Node) -> void:
	_on_meta_number_changed(value, node, "PlaybackSpeed")
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).pitch_scale = maxf(value, 0.05)
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).pitch_scale = maxf(value, 0.05)


func _on_sound_looped_changed(value: bool, node: Node) -> void:
	_on_meta_bool_changed(value, node, "Looped")


func _on_sound_playing_changed(value: bool, node: Node) -> void:
	_on_meta_bool_changed(value, node, "Playing")
	if not node.is_inside_tree():
		return
	if node is AudioStreamPlayer3D:
		if value:
			(node as AudioStreamPlayer3D).play()
		else:
			(node as AudioStreamPlayer3D).stop()
	elif node is AudioStreamPlayer:
		if value:
			(node as AudioStreamPlayer).play()
		else:
			(node as AudioStreamPlayer).stop()


func _on_light_color_changed(color: Color, light: Light3D) -> void:
	if light == null:
		return
	light.light_color = color


func _on_light_energy_changed(value: float, light: Light3D) -> void:
	if light == null:
		return
	light.light_energy = value


func _on_spot_angle_changed(value: float, light: SpotLight3D) -> void:
	if light == null:
		return
	light.spot_angle = value


func _on_camera_fov_changed(value: float, cam: Camera3D) -> void:
	if cam == null:
		return
	cam.fov = value


func _on_control_visible_changed(value: bool, ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.visible = value
	_update_control_manifest_properties(ctrl, {"Visible": value, "Enabled": value})


func _on_control_position_changed(value: Vector3, ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.position = Vector2(value.x, value.y)
	_update_control_manifest_properties(ctrl, {"Position": _control_udim2(ctrl.position)})


func _on_control_size_changed(value: Vector3, ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.size = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
	_update_control_manifest_properties(ctrl, {"Size": _control_udim2(ctrl.size)})


func _on_control_z_index_changed(value: float, ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.z_index = roundi(value)
	_update_control_manifest_properties(ctrl, {"ZIndex": ctrl.z_index})


func _on_control_text_changed(value: String, ctrl: Control) -> void:
	if ctrl == null:
		return
	if ctrl is Label:
		(ctrl as Label).text = value
	elif ctrl is Button:
		(ctrl as Button).text = value
	elif ctrl is LineEdit:
		(ctrl as LineEdit).text = value
	_update_control_manifest_properties(ctrl, {"Text": value})


func _update_control_manifest_properties(ctrl: Control, changes: Dictionary) -> void:
	var properties: Dictionary = {}
	if ctrl.get_meta("roblox_properties", {}) is Dictionary:
		properties = (ctrl.get_meta("roblox_properties", {}) as Dictionary).duplicate(true)
	for key in changes.keys():
		properties[key] = changes[key]
	ctrl.set_meta("roblox_properties", properties)
	if _studio != null and _studio.has_method("_on_data_model_gui_changed"):
		_studio.call_deferred("_on_data_model_gui_changed")


func _control_udim2(value: Vector2) -> Dictionary:
	return {
		"x": {"scale": 0.0, "offset": value.x},
		"y": {"scale": 0.0, "offset": value.y},
	}
