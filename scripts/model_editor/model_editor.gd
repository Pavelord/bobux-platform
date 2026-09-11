extends Control

const RuntimeObjLoaderClass = preload("res://addons/roblox_studio/runtime_obj_loader.gd")

signal back_requested
signal save_requested(model_data: Dictionary)
signal publish_requested(model_data: Dictionary)

const RbxlMaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const CANONICAL_MODEL_EXPORT_DIR := "user://studio_drafts/model_sources"
const MODEL_IMPORT_STAGING_DIR := "user://studio_drafts/model_imports"
const MAX_MODEL_IMPORT_BYTES: int = 256 * 1024 * 1024
const MODEL_FILE_FILTER := "*.glb,*.gltf,*.obj;3D model files;model/gltf-binary,model/gltf+json,text/plain"

enum ToolMode {
	SELECT,
	MOVE,
	SCALE,
	ROTATE
}

const PAGE_MIN_SIZE := Vector2(1120, 740)
const TOP_BAR := Color(0.105, 0.105, 0.105)
const TAB_BAR := Color(0.14, 0.14, 0.14)
const RIBBON_BG := Color(0.18, 0.18, 0.18)
const DOCK_BG := Color(0.145, 0.145, 0.145)
const DOCK_HEADER := Color(0.19, 0.19, 0.19)
const DOCK_BODY := Color(0.12, 0.12, 0.12)
const VIEWPORT_FRAME := Color(0.075, 0.075, 0.075)
const BORDER := Color(0.28, 0.28, 0.28)
const TEXT := Color(0.88, 0.88, 0.88)
const MUTED_TEXT := Color(0.62, 0.62, 0.62)
const ACCENT := Color(0.05, 0.52, 0.86)
const GREEN := Color(0.12, 0.62, 0.28)

var _tool_mode: int = ToolMode.SELECT
var _snap_enabled: bool = true
var _snap_step: float = 1.0
var _selected_node: Node3D = null
var _part_counter: int = 0
var _camera_distance: float = 30.0
var _camera_yaw: float = -0.55
var _camera_pitch: float = -0.48
var _camera_target: Vector3 = Vector3.ZERO
var _dragging_camera: bool = false
var _refreshing_explorer: bool = false
var _property_fields: Dictionary = {}
var _model_clipboard: Dictionary = {}

var _subviewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _world_root: Node3D = null
var _parts_root: Node3D = null
var _camera: Camera3D = null
var _explorer_tree: Tree = null
var _properties_box: VBoxContainer = null
var _status_label: Label = null
var _part_count_label: Label = null
var _active_tool_label: Label = null
var _color_button: ColorPickerButton = null
var _source_model_path: String = ""
var _source_model_loaded: bool = false
var _canonical_source_model_path: String = ""

func _ready() -> void:
	custom_minimum_size = PAGE_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_build_world()
	if _source_model_path.strip_edges().is_empty():
		_insert_part("Block")
		_select_node(_parts_root.get_child(0) as Node3D)
	else:
		call_deferred("_load_source_model", _source_model_path)

func open_source_model(source_path: String) -> void:
	_source_model_path = source_path.strip_edges()
	if _parts_root != null:
		call_deferred("_load_source_model", _source_model_path)

func _process(_delta: float) -> void:
	_update_camera_transform()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _is_text_input_focused():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_Q:
				_set_tool_mode(ToolMode.SELECT)
			KEY_W:
				_set_tool_mode(ToolMode.MOVE)
			KEY_E:
				_set_tool_mode(ToolMode.ROTATE)
			KEY_R:
				_set_tool_mode(ToolMode.SCALE)
			KEY_DELETE:
				_delete_selected()
			KEY_C:
				if key_event.ctrl_pressed:
					_copy_selected()
			KEY_V:
				if key_event.ctrl_pressed:
					_paste_selected()
			KEY_D:
				if key_event.ctrl_pressed:
					_duplicate_selected()
			KEY_UP:
				_nudge_selected(Vector3(0, 0, -_snap_step))
			KEY_DOWN:
				_nudge_selected(Vector3(0, 0, _snap_step))
			KEY_LEFT:
				_nudge_selected(Vector3(-_snap_step, 0, 0))
			KEY_RIGHT:
				_nudge_selected(Vector3(_snap_step, 0, 0))
			KEY_PAGEUP:
				_nudge_selected(Vector3(0, _snap_step, 0))
			KEY_PAGEDOWN:
				_nudge_selected(Vector3(0, -_snap_step, 0))

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_create_window_title_bar())
	root.add_child(_create_tab_bar())
	root.add_child(_create_ribbon())
	root.add_child(_create_workspace_body())
	root.add_child(_create_command_bar())

func _create_window_title_bar() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 28)
	panel.add_theme_stylebox_override("panel", _flat_style(TOP_BAR, TOP_BAR))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	for dot_color in [Color(0.95, 0.28, 0.26), Color(0.95, 0.72, 0.24), Color(0.22, 0.78, 0.32)]:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(11, 11)
		dot.color = dot_color
		row.add_child(dot)

	var title := Label.new()
	title.text = "Untitled Model - Bobux Studio"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	row.add_child(title)

	var save_btn := Button.new()
	save_btn.text = "Save Draft"
	save_btn.custom_minimum_size = Vector2(96, 24)
	save_btn.add_theme_stylebox_override("normal", _button_style(GREEN, GREEN.darkened(0.18)))
	save_btn.add_theme_color_override("font_color", Color.WHITE)
	save_btn.pressed.connect(_emit_save_draft)
	row.add_child(save_btn)

	var publish_btn := Button.new()
	publish_btn.text = "Publish"
	publish_btn.custom_minimum_size = Vector2(86, 24)
	publish_btn.add_theme_stylebox_override("normal", _button_style(Color(0.11, 0.53, 0.82), Color(0.04, 0.33, 0.58)))
	publish_btn.add_theme_color_override("font_color", Color.WHITE)
	publish_btn.pressed.connect(_emit_publish_model)
	row.add_child(publish_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(70, 24)
	back_btn.add_theme_stylebox_override("normal", _button_style(Color(0.24, 0.24, 0.24), BORDER))
	back_btn.add_theme_color_override("font_color", TEXT)
	back_btn.pressed.connect(func(): back_requested.emit())
	row.add_child(back_btn)

	return panel

func _create_tab_bar() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 28)
	panel.add_theme_stylebox_override("panel", _flat_style(TAB_BAR, TAB_BAR))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	for tab_name in ["FILE", "HOME", "MODEL", "AVATAR", "TEST", "VIEW", "PLUGINS"]:
		var tab := Button.new()
		tab.text = tab_name
		tab.flat = true
		tab.custom_minimum_size = Vector2(74, 28)
		tab.add_theme_font_size_override("font_size", 11)
		tab.add_theme_color_override("font_color", Color.WHITE if tab_name == "HOME" else MUTED_TEXT)
		if tab_name == "HOME":
			tab.add_theme_stylebox_override("normal", _tab_style(true))
			tab.add_theme_stylebox_override("hover", _tab_style(true))
		else:
			tab.add_theme_stylebox_override("normal", _tab_style(false))
			tab.add_theme_stylebox_override("hover", _flat_style(Color(0.18, 0.18, 0.18), Color(0.18, 0.18, 0.18)))
		row.add_child(tab)

	return panel

func _create_ribbon() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 94)
	panel.add_theme_stylebox_override("panel", _flat_style(RIBBON_BG, BORDER))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	row.add_child(_ribbon_group("Clipboard", [
		_ribbon_action("Copy", Callable(self, "_copy_selected")),
		_ribbon_action("Paste", Callable(self, "_paste_selected")),
		_ribbon_action("Cut", Callable(self, "_delete_selected")),
		_ribbon_action("Duplicate", Callable(self, "_duplicate_selected"))
	], 120))
	row.add_child(_ribbon_group("Tools", [
		_ribbon_tool("Select", ToolMode.SELECT),
		_ribbon_tool("Move", ToolMode.MOVE),
		_ribbon_tool("Scale", ToolMode.SCALE),
		_ribbon_tool("Rotate", ToolMode.ROTATE)
	], 230))
	row.add_child(_ribbon_group("Insert", [
		_ribbon_insert("Part", "Block"),
		_ribbon_insert("Sphere", "Sphere"),
		_ribbon_insert("Cylinder", "Cylinder"),
		_ribbon_insert("Ramp", "Ramp")
	], 240))
	row.add_child(_ribbon_group("Edit", [
		_ribbon_action("Color", Callable(self, "_randomize_selected_color")),
		_ribbon_action("Anchor", Callable(self, "_toggle_selected_anchored")),
		_ribbon_action("Group", Callable(self, "_not_implemented_group"))
	], 170))
	row.add_child(_ribbon_group("Test", [
		_ribbon_action("Play", Callable(self, "_emit_save_draft")),
		_ribbon_action("Stop", Callable(self, "_not_implemented_group"))
	], 120))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_active_tool_label = Label.new()
	_active_tool_label.text = "Mode: Select"
	_active_tool_label.add_theme_font_size_override("font_size", 12)
	_active_tool_label.add_theme_color_override("font_color", MUTED_TEXT)
	row.add_child(_active_tool_label)

	return panel

func _create_workspace_body() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)

	body.add_child(_create_left_dock())
	body.add_child(_create_center_view())
	body.add_child(_create_right_dock())

	return body

func _create_left_dock() -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(250, 0)
	stack.add_theme_constant_override("separation", 0)
	stack.add_child(_create_terrain_panel())
	stack.add_child(_create_toolbox_panel())
	return stack

func _create_center_view() -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 0)

	var document_tab := Panel.new()
	document_tab.custom_minimum_size = Vector2(0, 28)
	document_tab.add_theme_stylebox_override("panel", _flat_style(Color(0.11, 0.11, 0.11), BORDER))
	var tab_row := HBoxContainer.new()
	tab_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	document_tab.add_child(tab_row)
	var tab_label := Label.new()
	tab_label.text = "  Place1  x"
	tab_label.custom_minimum_size = Vector2(110, 28)
	tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab_label.add_theme_font_size_override("font_size", 12)
	tab_label.add_theme_color_override("font_color", TEXT)
	tab_row.add_child(tab_label)
	stack.add_child(document_tab)

	var viewport_panel := Panel.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.add_theme_stylebox_override("panel", _flat_style(VIEWPORT_FRAME, VIEWPORT_FRAME))
	stack.add_child(viewport_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 3)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	viewport_panel.add_child(margin)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.gui_input.connect(_on_viewport_gui_input)
	margin.add_child(_viewport_container)

	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(960, 560)
	_subviewport.world_3d = World3D.new()
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.msaa_3d = Viewport.MSAA_2X
	_viewport_container.add_child(_subviewport)

	return stack

func _create_right_dock() -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(330, 0)
	stack.add_theme_constant_override("separation", 0)
	stack.add_child(_create_explorer_panel())
	stack.add_child(_create_properties_panel())
	return stack

func _create_terrain_panel() -> Panel:
	var panel := _dock_panel("Terrain Editor", 190)
	var box := _dock_body(panel)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	box.add_child(tabs)
	for tab in ["Create", "Edit"]:
		var button := Button.new()
		button.text = tab
		button.custom_minimum_size = Vector2(70, 28)
		button.add_theme_stylebox_override("normal", _dark_button_style())
		button.add_theme_color_override("font_color", TEXT)
		tabs.add_child(button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	actions.add_child(_terrain_action("Import"))
	actions.add_child(_terrain_action("Generate"))
	actions.add_child(_terrain_action("Clear"))
	return panel

func _create_toolbox_panel() -> Panel:
	var panel := _dock_panel("Toolbox", 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := _dock_body(panel)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	box.add_child(tabs)
	for tab in ["Models", "Parts", "Recent", "Lights"]:
		var button := Button.new()
		button.text = tab
		button.custom_minimum_size = Vector2(54, 26)
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_stylebox_override("normal", _dark_button_style())
		button.add_theme_color_override("font_color", TEXT)
		tabs.add_child(button)

	var search := LineEdit.new()
	search.placeholder_text = "Search assets..."
	search.custom_minimum_size = Vector2(0, 28)
	box.add_child(search)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for asset in [
		{"name": "Vehicle", "kind": "Block", "color": Color(0.65, 0.06, 0.04)},
		{"name": "Structure", "kind": "Block", "color": Color(0.58, 0.30, 0.08)},
		{"name": "Light", "kind": "Light", "color": Color(0.96, 0.82, 0.08)},
		{"name": "Spawn", "kind": "Spawn", "color": Color(0.04, 0.68, 0.26)},
		{"name": "Sphere", "kind": "Sphere", "color": Color(0.16, 0.44, 0.85)},
		{"name": "Ramp", "kind": "Ramp", "color": Color(0.90, 0.34, 0.10)}
	]:
		grid.add_child(_toolbox_tile(asset))
	return panel

func _create_explorer_panel() -> Panel:
	var panel := _dock_panel("Explorer", 315)
	var box := _dock_body(panel)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter workspace"
	filter.custom_minimum_size = Vector2(0, 26)
	box.add_child(filter)
	_explorer_tree = Tree.new()
	_explorer_tree.hide_root = false
	_explorer_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_explorer_tree.add_theme_color_override("font_color", TEXT)
	_explorer_tree.item_selected.connect(_on_explorer_item_selected)
	box.add_child(_explorer_tree)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	actions.add_child(_small_dock_button("Duplicate", Callable(self, "_duplicate_selected")))
	actions.add_child(_small_dock_button("Delete", Callable(self, "_delete_selected")))
	return panel

func _create_properties_panel() -> Panel:
	var panel := _dock_panel("Properties", 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := _dock_body(panel)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter Properties"
	filter.custom_minimum_size = Vector2(0, 26)
	box.add_child(filter)
	_properties_box = VBoxContainer.new()
	_properties_box.add_theme_constant_override("separation", 7)
	_properties_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_properties_box)
	_rebuild_properties_panel()
	return panel

func _create_command_bar() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 28)
	panel.add_theme_stylebox_override("panel", _flat_style(Color(0.09, 0.09, 0.09), BORDER))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var prompt := Label.new()
	prompt.text = "Run a command"
	prompt.custom_minimum_size = Vector2(120, 28)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.add_theme_color_override("font_color", MUTED_TEXT)
	row.add_child(prompt)
	_status_label = Label.new()
	_status_label.text = "Ready. RMB drag: orbit camera. Mouse wheel: zoom."
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", TEXT)
	row.add_child(_status_label)
	_part_count_label = Label.new()
	_part_count_label.text = "0 parts"
	_part_count_label.custom_minimum_size = Vector2(80, 28)
	_part_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_part_count_label.add_theme_font_size_override("font_size", 12)
	_part_count_label.add_theme_color_override("font_color", MUTED_TEXT)
	row.add_child(_part_count_label)
	return panel

func _build_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "ModelEditorWorld"
	_subviewport.add_child(_world_root)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.86, 0.86)
	env.ambient_light_energy = 0.62
	world_env.environment = env
	_world_root.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-48, -38, 0)
	light.light_energy = 1.65
	light.shadow_enabled = true
	_world_root.add_child(light)

	_camera = Camera3D.new()
	_camera.name = "StudioCamera"
	_camera.current = true
	_camera.near = 0.08
	_camera.far = 600.0
	_world_root.add_child(_camera)

	_parts_root = Node3D.new()
	_parts_root.name = "Workspace"
	_world_root.add_child(_parts_root)
	_world_root.add_child(_create_grid_floor())
	_refresh_explorer()

func _create_grid_floor() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GridFloor"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120, 120)
	mesh.subdivide_width = 60
	mesh.subdivide_depth = 60
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.50, 0.56)
	mat.roughness = 0.96
	mesh_instance.set_surface_override_material(0, mat)
	return mesh_instance

func _ribbon_group(title: String, controls: Array, width: float) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(width, 76)
	panel.add_theme_stylebox_override("panel", _flat_style(Color(0.16, 0.16, 0.16), Color(0.23, 0.23, 0.23)))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	for control in controls:
		row.add_child(control)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", MUTED_TEXT)
	box.add_child(label)
	return panel

func _ribbon_action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(58, 46)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _dark_button_style())
	button.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.22, 0.22), ACCENT))
	button.add_theme_color_override("font_color", TEXT)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

func _ribbon_tool(text: String, mode: int) -> Button:
	var button := _ribbon_action(text, Callable())
	button.pressed.connect(func(): _set_tool_mode(mode))
	return button

func _ribbon_insert(text: String, kind: String) -> Button:
	var button := _ribbon_action(text, Callable())
	button.pressed.connect(func(): _insert_part(kind))
	return button

func _dock_panel(title: String, height: float) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, height)
	panel.add_theme_stylebox_override("panel", _flat_style(DOCK_BG, BORDER))
	var root := VBoxContainer.new()
	root.name = "DockRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	var header := Panel.new()
	header.custom_minimum_size = Vector2(0, 25)
	header.add_theme_stylebox_override("panel", _flat_style(DOCK_HEADER, BORDER))
	root.add_child(header)
	var label := Label.new()
	label.text = "  " + title
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	header.add_child(label)
	var body := VBoxContainer.new()
	body.name = "DockBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	return panel

func _dock_body(panel: Panel) -> VBoxContainer:
	var root := panel.get_node("DockRoot") as VBoxContainer
	var body := root.get_node("DockBody") as VBoxContainer
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	body.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box

func _terrain_action(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(70, 54)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _dark_button_style())
	button.add_theme_color_override("font_color", TEXT)
	if text == "Import":
		button.pressed.connect(_open_model_import_dialog)
	else:
		button.pressed.connect(func(): _set_status("%s terrain action is planned for the terrain block." % text))
	return button

func _open_model_import_dialog() -> void:
	if _show_system_model_import_dialog():
		return
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([MODEL_FILE_FILTER])
	if OS.has_feature("android"):
		if OS.has_method("request_permissions"):
			OS.request_permissions()
		if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
			dialog.current_dir = "/storage/emulated/0/Download"
		elif DirAccess.dir_exists_absolute("/storage/emulated/0"):
			dialog.current_dir = "/storage/emulated/0"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		_load_source_model(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(760, 520))

func _show_system_model_import_dialog() -> bool:
	if OS.has_feature("android") and OS.has_method("request_permissions"):
		OS.request_permissions()
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
		_load_source_model(str(selected_paths[0]))
	var error: Error = DisplayServer.file_dialog_show(
		"Import Model",
		start_dir,
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray([MODEL_FILE_FILTER]),
		callback
	)
	return error == OK

func _toolbox_tile(asset: Dictionary) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [str(asset.get("name", "")), str(asset.get("kind", ""))]
	button.custom_minimum_size = Vector2(104, 62)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 11)
	var color := Color(asset.get("color", ACCENT))
	button.add_theme_stylebox_override("normal", _button_style(color.darkened(0.25), color.darkened(0.42)))
	button.add_theme_stylebox_override("hover", _button_style(color, color.lightened(0.12)))
	button.add_theme_color_override("font_color", Color.WHITE)
	var kind := str(asset.get("kind", "Block"))
	button.pressed.connect(func(): _insert_toolbox_asset(kind))
	return button

func _small_dock_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(88, 28)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _dark_button_style())
	button.add_theme_color_override("font_color", TEXT)
	button.pressed.connect(callback)
	return button

func _set_tool_mode(mode: int) -> void:
	_tool_mode = mode
	var names := {
		ToolMode.SELECT: "Select",
		ToolMode.MOVE: "Move",
		ToolMode.SCALE: "Scale",
		ToolMode.ROTATE: "Rotate"
	}
	var label := str(names.get(mode, "Select"))
	if _active_tool_label:
		_active_tool_label.text = "Mode: " + label
	_set_status("Tool set to %s." % label)

func _insert_toolbox_asset(kind: String) -> void:
	match kind:
		"Spawn":
			_insert_part("Block")
			if _selected_node:
				_selected_node.name = "SpawnPoint%d" % _part_counter
				_selected_node.set_meta("kind", "SpawnPoint")
				_apply_part_color(_selected_node, Color(0.1, 0.82, 0.28))
				_refresh_explorer()
		"Light":
			_insert_part("Sphere")
			if _selected_node:
				_selected_node.name = "PointLightMarker%d" % _part_counter
				_selected_node.set_meta("kind", "LightMarker")
				_apply_part_color(_selected_node, Color(1.0, 0.86, 0.16))
				_refresh_explorer()
		_:
			_insert_part(kind)

func _insert_part(kind: String) -> void:
	if _parts_root == null:
		return
	_part_counter += 1
	var part := StaticBody3D.new()
	part.name = "%s%d" % [kind, _part_counter]
	part.set_meta("kind", kind)
	part.set_meta("anchored", true)
	part.set_meta("can_collide", true)
	var initial_color := _color_for_kind(kind)
	part.set_meta("bobux_color", initial_color)
	part.position = _snap_vector(Vector3((_part_counter % 4) * 3.5 - 5.0, 1.0, floorf(float(_part_counter) / 4.0) * 3.5))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _create_mesh_for_kind(kind)
	mesh_instance.set_surface_override_material(0, _create_part_material(initial_color))
	part.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = _create_shape_for_kind(kind)
	part.add_child(collision)

	_parts_root.add_child(part)
	_refresh_explorer()
	_select_node(part)
	_set_status("Inserted %s." % part.name)

func _create_mesh_for_kind(kind: String) -> Mesh:
	match kind:
		"Sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 1.2
			sphere.height = 2.4
			return sphere
		"Cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 1.15
			cylinder.bottom_radius = 1.15
			cylinder.height = 2.4
			return cylinder
		"Ramp":
			var ramp := BoxMesh.new()
			ramp.size = Vector3(4, 1.2, 4)
			return ramp
		_:
			var box := BoxMesh.new()
			box.size = Vector3(4, 2, 4)
			return box

func _create_shape_for_kind(kind: String) -> Shape3D:
	match kind:
		"Sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = 1.2
			return sphere
		"Cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 1.15
			cylinder.height = 2.4
			return cylinder
		_:
			var box := BoxShape3D.new()
			box.size = Vector3(4, 2, 4)
			return box

func _create_part_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	return mat

func _clear_parts() -> void:
	if _parts_root == null:
		return
	for child in _parts_root.get_children():
		child.queue_free()
	_selected_node = null
	_refresh_explorer()

func _load_source_model(source_path: String) -> void:
	var clean_path: String = source_path.strip_edges()
	if clean_path.is_empty() or _parts_root == null:
		return
	if clean_path.begins_with("content://"):
		clean_path = _stage_android_model_uri(clean_path)
		if clean_path.is_empty():
			_set_status("Could not read the selected model from Android storage.")
			return
	_clear_parts()
	_source_model_path = clean_path
	_source_model_loaded = false
	_canonical_source_model_path = ""
	var loaded_resource: Resource = null
	var extension := clean_path.get_extension().to_lower()
	if extension == "glb" or extension == "gltf":
		var scene_from_gltf := _load_gltf_scene(clean_path)
		if scene_from_gltf != null:
			var wrapper := Node3D.new()
			wrapper.name = "Imported_%s" % clean_path.get_file().get_basename()
			wrapper.set_meta("kind", "ImportedScene")
			wrapper.set_meta("source_path", clean_path)
			wrapper.add_child(scene_from_gltf)
			_parts_root.add_child(wrapper)
			_prune_imported_ground_planes(wrapper)
			_normalize_imported_model_root(wrapper)
			_select_node(wrapper)
			_source_model_loaded = true
			_set_status("Loaded glTF source model: %s" % clean_path.get_file())
			return
	if extension == "obj":
		var obj_mesh := _load_obj_mesh(clean_path)
		if obj_mesh != null:
			_add_imported_mesh_part(clean_path, obj_mesh)
			_source_model_loaded = true
			_set_status("Loaded OBJ source model: %s" % clean_path.get_file())
			return
	if clean_path.begins_with("res://") or clean_path.begins_with("user://"):
		loaded_resource = ResourceLoader.load(clean_path)
	if loaded_resource is PackedScene:
		var instance := (loaded_resource as PackedScene).instantiate()
		if instance is Node3D:
			var wrapper := Node3D.new()
			wrapper.name = clean_path.get_file().get_basename()
			wrapper.set_meta("kind", "ImportedScene")
			wrapper.set_meta("source_path", clean_path)
			wrapper.add_child(instance)
			_parts_root.add_child(wrapper)
			_prune_imported_ground_planes(wrapper)
			_normalize_imported_model_root(wrapper)
			_select_node(wrapper)
			_source_model_loaded = true
	elif loaded_resource is Mesh:
		var part := StaticBody3D.new()
		part.name = clean_path.get_file().get_basename()
		part.set_meta("kind", "ImportedMesh")
		part.set_meta("source_path", clean_path)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = loaded_resource as Mesh
		part.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = (loaded_resource as Mesh).create_trimesh_shape()
		part.add_child(collision)
		_parts_root.add_child(part)
		_normalize_imported_model_root(part)
		_select_node(part)
		_source_model_loaded = true
	if not _source_model_loaded:
		_set_status("Could not load this model for publishing. Use .glb/.gltf/.obj or a Godot-imported res:// scene/mesh: %s" % clean_path.get_file())
		_refresh_explorer()
	else:
		_set_status("Loaded source model: %s" % clean_path.get_file())

func _stage_android_model_uri(source_uri: String) -> String:
	if source_uri.strip_edges().is_empty():
		return ""
	if Engine.has_singleton("AndroidRuntime"):
		var android_runtime := Engine.get_singleton("AndroidRuntime")
		if android_runtime != null and android_runtime.has_method("updatePersistableUriPermission"):
			android_runtime.call("updatePersistableUriPermission", source_uri, true)
	var source_file := FileAccess.open(source_uri, FileAccess.READ)
	if source_file == null:
		return ""
	var source_length := source_file.get_length()
	if source_length <= 0 or source_length > MAX_MODEL_IMPORT_BYTES:
		source_file.close()
		return ""
	var source_bytes := source_file.get_buffer(source_length)
	source_file.close()
	var extension := _detect_selected_model_extension(source_uri, source_bytes)
	if extension.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODEL_IMPORT_STAGING_DIR))
	var staged_path := MODEL_IMPORT_STAGING_DIR.path_join(
		"android_model_%d.%s" % [Time.get_ticks_msec(), extension]
	)
	var staged_file := FileAccess.open(staged_path, FileAccess.WRITE)
	if staged_file == null:
		return ""
	staged_file.store_buffer(source_bytes)
	staged_file.close()
	if not FileAccess.file_exists(staged_path):
		return ""
	return staged_path

func _detect_selected_model_extension(source_path: String, source_bytes: PackedByteArray) -> String:
	var clean_path := source_path.split("?", false)[0]
	var extension := clean_path.get_extension().to_lower()
	if extension in ["glb", "gltf", "obj"]:
		return extension
	if source_bytes.size() >= 4 \
		and source_bytes[0] == 0x67 \
		and source_bytes[1] == 0x6c \
		and source_bytes[2] == 0x54 \
		and source_bytes[3] == 0x46:
		return "glb"
	var sample_size := mini(source_bytes.size(), 8192)
	var text_sample := source_bytes.slice(0, sample_size).get_string_from_utf8().strip_edges()
	if text_sample.begins_with("{") and text_sample.contains("\"asset\"") and text_sample.contains("\"version\""):
		return "gltf"
	if text_sample.begins_with("#") \
		or text_sample.begins_with("v ") \
		or text_sample.contains("\nv ") \
		or text_sample.contains("\nf "):
		return "obj"
	return ""

func _load_obj_mesh(source_path: String) -> Mesh:
	return RuntimeObjLoaderClass.load_mesh(source_path)

func _add_imported_mesh_part(source_path: String, mesh: Mesh) -> void:
	if mesh == null or _parts_root == null:
		return
	var part := StaticBody3D.new()
	part.name = source_path.get_file().get_basename()
	part.set_meta("kind", "ImportedMesh")
	part.set_meta("source_path", source_path)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	part.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		shape = BoxShape3D.new()
	collision.shape = shape
	part.add_child(collision)
	_parts_root.add_child(part)
	_normalize_imported_model_root(part)
	_select_node(part)

func _load_gltf_scene(source_path: String) -> Node3D:
	if not FileAccess.file_exists(source_path):
		return null
	var gltf_document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := gltf_document.append_from_file(source_path, gltf_state)
	if error != OK:
		_set_status("Could not preview glTF file (%s): error %s" % [source_path.get_file(), str(error)])
		return null
	var scene_node: Node = gltf_document.generate_scene(gltf_state)
	if scene_node is Node3D:
		RbxlMaterialCache.enable_embedded_vertex_colors(scene_node)
		return scene_node as Node3D
	return null

func _prune_imported_ground_planes(root: Node3D) -> void:
	if root == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	if meshes.size() <= 1:
		return
	var overall := _combined_mesh_bounds(root, meshes)
	if overall.size == Vector3.ZERO:
		return
	var longest_axis := maxf(overall.size.x, overall.size.z)
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_bounds := _mesh_bounds_in_root(root, mesh_instance)
		if mesh_bounds.size == Vector3.ZERO:
			continue
		var flat_enough := mesh_bounds.size.y <= maxf(longest_axis * 0.035, 0.08)
		var wide_enough := mesh_bounds.size.x >= overall.size.x * 0.82 and mesh_bounds.size.z >= overall.size.z * 0.82
		var near_bottom := mesh_bounds.position.y <= overall.position.y + maxf(overall.size.y * 0.08, 0.12)
		if flat_enough and wide_enough and near_bottom:
			var mesh_parent := mesh_instance.get_parent()
			var node_to_remove: Node = mesh_instance
			if mesh_parent != null and mesh_parent != root and mesh_parent.get_child_count() == 1:
				node_to_remove = mesh_parent
			var holder_node := node_to_remove.get_parent()
			if holder_node != null:
				holder_node.remove_child(node_to_remove)
			node_to_remove.queue_free()

func _normalize_imported_model_root(root: Node3D) -> void:
	if root == null:
		return
	root.position = Vector3.ZERO
	root.rotation_degrees = Vector3.ZERO
	root.scale = Vector3.ONE
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	if meshes.is_empty():
		return
	var bounds := _combined_mesh_bounds(root, meshes)
	if bounds.size == Vector3.ZERO:
		return
	var max_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if max_axis <= 0.001:
		return
	var target_size := 3.2
	var uniform_scale := clampf(target_size / max_axis, 0.04, 24.0)
	var center := bounds.get_center()
	root.scale = Vector3.ONE * uniform_scale
	root.position = Vector3(-center.x * uniform_scale, -bounds.position.y * uniform_scale, -center.z * uniform_scale)

func _combined_mesh_bounds(root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var has_bounds := false
	var combined := AABB()
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_bounds := _mesh_bounds_in_root(root, mesh_instance)
		if mesh_bounds.size == Vector3.ZERO:
			continue
		combined = mesh_bounds if not has_bounds else combined.merge(mesh_bounds)
		has_bounds = true
	return combined if has_bounds else AABB()

func _mesh_bounds_in_root(root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	if root == null or mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var aabb := mesh_instance.mesh.get_aabb()
	var root_to_mesh := root.global_transform.affine_inverse() * mesh_instance.global_transform
	var corners := [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z)
	]
	var first: Vector3 = root_to_mesh * corners[0]
	var bounds := AABB(first, Vector3.ZERO)
	for index in range(1, corners.size()):
		bounds = bounds.expand(root_to_mesh * corners[index])
	return bounds

func _color_for_kind(kind: String) -> Color:
	match kind:
		"Sphere":
			return Color(0.95, 0.82, 0.18)
		"Cylinder":
			return Color(0.18, 0.48, 0.92)
		"Ramp":
			return Color(0.92, 0.38, 0.16)
		_:
			return Color(0.32, 0.62, 0.30)

func _refresh_explorer() -> void:
	if _explorer_tree == null or _parts_root == null:
		return
	_refreshing_explorer = true
	_explorer_tree.clear()
	var root_item := _explorer_tree.create_item()
	root_item.set_text(0, "Workspace")
	root_item.set_metadata(0, _parts_root)
	for service_name in ["Players", "Lighting", "MaterialService", "ReplicatedStorage", "ServerStorage", "StarterGui", "StarterPack", "SoundService"]:
		var service_item := _explorer_tree.create_item(root_item)
		service_item.set_text(0, service_name)
		service_item.set_metadata(0, null)
	for child in _parts_root.get_children():
		if child is Node3D:
			var item := _explorer_tree.create_item(root_item)
			item.set_text(0, child.name)
			item.set_metadata(0, child)
			if child == _selected_node:
				item.select(0)
	root_item.set_collapsed(false)
	if _part_count_label:
		_part_count_label.text = "%d parts" % _parts_root.get_child_count()
	_refreshing_explorer = false

func _on_explorer_item_selected() -> void:
	if _refreshing_explorer or _explorer_tree == null:
		return
	var item := _explorer_tree.get_selected()
	if item == null:
		return
	var node := item.get_metadata(0) as Node3D
	if node != null and node != _parts_root:
		_select_node(node)

func _select_node(node: Node3D) -> void:
	_selected_node = node
	_focus_camera_on(node)
	_refresh_selection_visuals()
	_rebuild_properties_panel()
	_refresh_explorer()
	if node != null:
		_set_status("Selected %s." % node.name)

func _refresh_selection_visuals() -> void:
	if _parts_root == null:
		return
	for child in _parts_root.get_children():
		if not (child is Node3D):
			continue
		var mesh := (child as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.scale = Vector3.ONE * (1.045 if child == _selected_node else 1.0)

func _rebuild_properties_panel() -> void:
	if _properties_box == null:
		return
	for child in _properties_box.get_children():
		child.queue_free()
	_property_fields.clear()
	_color_button = null

	if _selected_node == null:
		var empty := _property_label("Select a part in Explorer.")
		_properties_box.add_child(empty)
		return

	var class_label := _property_label(_selected_node.name + "  (" + str(_selected_node.get_meta("kind", "Part")) + ")")
	class_label.add_theme_color_override("font_color", TEXT)
	_properties_box.add_child(class_label)

	_add_line_edit_property("Name", _selected_node.name, func(value: String): _rename_selected(value))
	_properties_box.add_child(_section_label("Transform"))
	_add_vector3_property("Position", "position", _selected_node.position, -512.0, 512.0, 0.25)
	_add_vector3_property("Rotation", "rotation_degrees", _selected_node.rotation_degrees, -360.0, 360.0, 1.0)
	_add_vector3_property("Scale", "scale", _selected_node.scale, 0.1, 20.0, 0.1)
	_properties_box.add_child(_section_label("Appearance"))

	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(0, 30)
	_color_button.color = _get_part_color(_selected_node)
	_color_button.color_changed.connect(func(color: Color): _apply_part_color(_selected_node, color))
	_properties_box.add_child(_color_button)

	_properties_box.add_child(_section_label("Physics"))
	_add_check_property("Anchored", bool(_selected_node.get_meta("anchored", true)), func(enabled: bool):
		if _selected_node:
			_selected_node.set_meta("anchored", enabled)
	)
	_add_check_property("CanCollide", bool(_selected_node.get_meta("can_collide", true)), func(enabled: bool):
		if _selected_node:
			_selected_node.set_meta("can_collide", enabled)
			var collision := _selected_node.get_node_or_null("Collision") as CollisionShape3D
			if collision:
				collision.disabled = not enabled
	)

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	return label

func _property_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED_TEXT)
	return label

func _add_line_edit_property(label_text: String, value: String, callback: Callable) -> void:
	_properties_box.add_child(_property_label(label_text))
	var edit := LineEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 28)
	edit.text_submitted.connect(callback)
	edit.focus_exited.connect(func(): callback.call(edit.text))
	_properties_box.add_child(edit)

func _add_vector3_property(label_text: String, property_name: String, value: Vector3, min_value: float, max_value: float, step: float) -> void:
	_properties_box.add_child(_property_label(label_text))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_properties_box.add_child(row)
	for axis_index in range(3):
		var spin := SpinBox.new()
		spin.min_value = min_value
		spin.max_value = max_value
		spin.step = step
		spin.custom_minimum_size = Vector2(82, 28)
		spin.value = value[axis_index]
		_property_fields["%s_%d" % [property_name, axis_index]] = spin
		spin.value_changed.connect(func(_new_value: float): _apply_transform_properties())
		row.add_child(spin)

func _add_check_property(text: String, enabled: bool, callback: Callable) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = enabled
	check.add_theme_color_override("font_color", TEXT)
	check.toggled.connect(callback)
	_properties_box.add_child(check)

func _apply_transform_properties() -> void:
	if _selected_node == null:
		return
	var pos := _read_vector_property("position")
	var rot := _read_vector_property("rotation_degrees")
	var scale_value := _read_vector_property("scale")
	if _snap_enabled:
		pos = _snap_vector(pos)
	_selected_node.position = pos
	_selected_node.rotation_degrees = rot
	_selected_node.scale = Vector3(maxf(scale_value.x, 0.05), maxf(scale_value.y, 0.05), maxf(scale_value.z, 0.05))

func _read_vector_property(property_name: String) -> Vector3:
	var x_spin := _property_fields.get("%s_0" % property_name) as SpinBox
	var y_spin := _property_fields.get("%s_1" % property_name) as SpinBox
	var z_spin := _property_fields.get("%s_2" % property_name) as SpinBox
	if x_spin == null or y_spin == null or z_spin == null:
		return Vector3.ZERO
	return Vector3(float(x_spin.value), float(y_spin.value), float(z_spin.value))

func _apply_part_color(node: Node3D, color: Color) -> void:
	if node == null:
		return
	node.set_meta("bobux_color", Color(color.r, color.g, color.b, color.a))
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.set_surface_override_material(0, _create_part_material(color))

func _get_part_color(node: Node3D) -> Color:
	if node != null and node.has_meta("bobux_color"):
		var meta_color: Variant = node.get_meta("bobux_color")
		return _model_part_color_from_variant(meta_color, Color.WHITE)
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return Color.WHITE
	var mat := mesh.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat else Color.WHITE

func _model_part_color_from_data(data: Dictionary, fallback: Color = Color.WHITE) -> Color:
	for key in ["color", "Color", "Color3", "Color3uint8", "colour", "albedo", "albedo_color", "modulate"]:
		if data.has(key):
			return _model_part_color_from_variant(data.get(key), fallback)
	for key in ["BrickColor", "BrickColorId", "brick_color"]:
		if data.has(key):
			return RbxlMaterialCache.roblox_brick_color_to_color(data.get(key))
	return fallback

func _model_part_color_from_variant(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value as Color
	if value is String:
		var clean: String = (value as String).strip_edges()
		if clean.begins_with("#"):
			clean = clean.substr(1)
		if clean.length() == 6 or clean.length() == 8:
			return Color.html(clean)
	if value is Array:
		var arr := value as Array
		var r := float(arr[0]) if arr.size() > 0 else fallback.r
		var g := float(arr[1]) if arr.size() > 1 else fallback.g
		var b := float(arr[2]) if arr.size() > 2 else fallback.b
		var a := float(arr[3]) if arr.size() > 3 else fallback.a
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		return Color(r, g, b, a)
	if value is Dictionary:
		var dict := value as Dictionary
		var r := float(dict.get("r", dict.get("R", dict.get("x", dict.get("X", fallback.r)))))
		var g := float(dict.get("g", dict.get("G", dict.get("y", dict.get("Y", fallback.g)))))
		var b := float(dict.get("b", dict.get("B", dict.get("z", dict.get("Z", fallback.b)))))
		var a := float(dict.get("a", dict.get("A", fallback.a)))
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		return Color(r, g, b, a)
	return fallback

func _rename_selected(new_name: String) -> void:
	if _selected_node == null:
		return
	var clean := new_name.strip_edges()
	if clean.is_empty():
		return
	_selected_node.name = clean
	_refresh_explorer()

func _duplicate_selected() -> void:
	if _selected_node == null or _parts_root == null:
		return
	var clone := _selected_node.duplicate()
	clone.name = _selected_node.name + "_Copy"
	clone.position += Vector3(_snap_step, 0.0, _snap_step)
	_parts_root.add_child(clone)
	_refresh_explorer()
	_select_node(clone)

func _copy_selected() -> void:
	if _selected_node == null:
		return
	_model_clipboard = _serialize_part(_selected_node)
	_set_status("Copied %s." % _selected_node.name)

func _paste_selected() -> void:
	if _model_clipboard.is_empty() or _parts_root == null:
		_set_status("Clipboard is empty.")
		return
	var part := _create_part_from_data(_model_clipboard, Vector3(_snap_step, 0.0, _snap_step))
	if part == null:
		return
	_parts_root.add_child(part)
	_refresh_explorer()
	_select_node(part)
	_set_status("Pasted %s." % part.name)

func _delete_selected() -> void:
	if _selected_node == null or _selected_node == _parts_root:
		return
	var next_selection: Node3D = null
	for child in _parts_root.get_children():
		if child != _selected_node and child is Node3D:
			next_selection = child
			break
	_selected_node.queue_free()
	_selected_node = next_selection
	await get_tree().process_frame
	_refresh_explorer()
	_rebuild_properties_panel()
	_refresh_selection_visuals()

func _randomize_selected_color() -> void:
	if _selected_node == null:
		return
	_apply_part_color(_selected_node, Color.from_hsv(randf(), 0.62, 0.9))
	_rebuild_properties_panel()

func _toggle_selected_anchored() -> void:
	if _selected_node == null:
		return
	_selected_node.set_meta("anchored", not bool(_selected_node.get_meta("anchored", true)))
	_rebuild_properties_panel()

func _not_implemented_group() -> void:
	_set_status("This command is reserved for the next Studio block.")

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_camera = mouse_button.pressed
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			_pick_part_at_viewport_position(mouse_button.position)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_camera_distance = maxf(6.0, _camera_distance - 1.25)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_camera_distance = minf(110.0, _camera_distance + 1.25)
	elif event is InputEventMouseMotion and _dragging_camera:
		var motion := event as InputEventMouseMotion
		_camera_yaw -= motion.relative.x * 0.008
		_camera_pitch = clampf(_camera_pitch - motion.relative.y * 0.006, -1.25, -0.08)

func _focus_camera_on(node: Node3D) -> void:
	if node:
		_camera_target = node.global_position

func _pick_part_at_viewport_position(screen_position: Vector2) -> void:
	if _camera == null or _subviewport == null:
		return
	var world := _subviewport.world_3d
	if world == null:
		_set_status("Viewport physics world is still preparing.")
		return
	var space_state := world.direct_space_state
	if space_state == null:
		_set_status("Viewport physics world is still preparing.")
		return
	var viewport_size := Vector2(_subviewport.size)
	var container_size := _viewport_container.size if _viewport_container != null else viewport_size
	var pick_position := screen_position
	if container_size.x > 0.0 and container_size.y > 0.0 and viewport_size.x > 0.0 and viewport_size.y > 0.0:
		pick_position = Vector2(screen_position.x * viewport_size.x / container_size.x, screen_position.y * viewport_size.y / container_size.y)
	var origin := _camera.project_ray_origin(pick_position)
	var direction := _camera.project_ray_normal(pick_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider := result.get("collider") as Node
	while collider != null and collider.get_parent() != _parts_root:
		collider = collider.get_parent()
	if collider is Node3D:
		_select_node(collider as Node3D)

func _nudge_selected(offset: Vector3) -> void:
	if _selected_node == null:
		return
	match _tool_mode:
		ToolMode.MOVE, ToolMode.SELECT:
			_selected_node.position = _snap_vector(_selected_node.position + offset)
		ToolMode.ROTATE:
			_selected_node.rotation_degrees += Vector3(offset.z * 15.0, offset.x * 15.0, 0.0)
		ToolMode.SCALE:
			var scale_delta := Vector3(absf(offset.x) + absf(offset.z), absf(offset.y), absf(offset.x) + absf(offset.z))
			if offset.x < 0.0 or offset.z < 0.0 or offset.y < 0.0:
				scale_delta = -scale_delta
			_selected_node.scale = Vector3(
				maxf(0.1, _selected_node.scale.x + scale_delta.x),
				maxf(0.1, _selected_node.scale.y + scale_delta.y),
				maxf(0.1, _selected_node.scale.z + scale_delta.z)
			)
	_rebuild_properties_panel()
	_refresh_selection_visuals()
	_set_status("Adjusted %s." % _selected_node.name)

func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit or focus_owner is SpinBox

func _update_camera_transform() -> void:
	if _camera == null:
		return
	var dir := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	)
	_camera.global_position = _camera_target - (dir.normalized() * _camera_distance)
	_camera.look_at(_camera_target, Vector3.UP)

func _snap_vector(value: Vector3) -> Vector3:
	if not _snap_enabled or _snap_step <= 0.0:
		return value
	return Vector3(snappedf(value.x, _snap_step), snappedf(value.y, _snap_step), snappedf(value.z, _snap_step))

func _emit_save_draft() -> void:
	var model_data := _collect_model_data()
	save_requested.emit(model_data)
	_set_status("Draft serialized. You can publish it to Bobux Cloud when ready.")

func _emit_publish_model() -> void:
	var model_data := _collect_model_data()
	var parts: Array = model_data.get("parts", []) if model_data.get("parts", []) is Array else []
	if parts.is_empty():
		_set_status("Nothing to publish: import a supported model or add parts first.")
		return
	var thumbnail := await _capture_model_preview_data_uri(model_data)
	if not thumbnail.is_empty():
		model_data["preview_thumbnail"] = thumbnail
	publish_requested.emit(model_data)
	_set_status("Preparing model publish...")

func _collect_model_data() -> Dictionary:
	var canonical_source_path := _export_canonical_model_source()
	var effective_source_path := canonical_source_path
	if effective_source_path.is_empty():
		effective_source_path = _source_model_path
	var model_data := {
		"schema": "bobux_model_asset_v2",
		"created_at": Time.get_datetime_string_from_system(true),
		"source_model_path": effective_source_path,
		"canonical_source_model_path": canonical_source_path,
		"canonical_transform_baked": not canonical_source_path.is_empty(),
		"original_source_model_path": _source_model_path,
		"source_model_loaded": _source_model_loaded,
		"source_model_transform": _collect_source_model_transform(),
		"parts": _serialize_parts()
	}
	return model_data

func _export_canonical_model_source() -> String:
	if _parts_root == null or not is_instance_valid(_parts_root):
		return ""
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(_parts_root, meshes)
	if meshes.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANONICAL_MODEL_EXPORT_DIR))
	var source_key := _source_model_path
	if source_key.is_empty():
		source_key = "created_model"
	var export_name := "%s_%d.glb" % [source_key.md5_text(), Time.get_ticks_msec()]
	var export_path := CANONICAL_MODEL_EXPORT_DIR.path_join(export_name)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(_parts_root, state)
	if append_error != OK:
		push_warning("[ModelEditor] Could not prepare canonical GLB: %s" % error_string(append_error))
		return ""
	var write_error := document.write_to_filesystem(state, export_path)
	if write_error != OK or not FileAccess.file_exists(export_path):
		push_warning("[ModelEditor] Could not write canonical GLB: %s" % error_string(write_error))
		return ""
	_canonical_source_model_path = export_path
	return export_path

func _collect_source_model_transform() -> Dictionary:
	if _parts_root == null:
		return {}
	for child in _parts_root.get_children():
		if child is Node3D and str(child.get_meta("kind", "")) in ["ImportedScene", "ImportedMesh"]:
			var source_root := child as Node3D
			return {
				"position": [source_root.position.x, source_root.position.y, source_root.position.z],
				"rotation_degrees": [source_root.rotation_degrees.x, source_root.rotation_degrees.y, source_root.rotation_degrees.z],
				"scale": [source_root.scale.x, source_root.scale.y, source_root.scale.z],
			}
	return {}

func _serialize_parts() -> Array:
	var parts: Array = []
	if _parts_root == null:
		return parts
	for child in _parts_root.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		var imported_parts := _serialize_imported_scene_parts(node)
		if not imported_parts.is_empty():
			parts.append_array(imported_parts)
			continue
		parts.append(_serialize_part(node))
	return parts

func _serialize_imported_scene_parts(root: Node3D) -> Array:
	var kind := str(root.get_meta("kind", ""))
	if kind != "ImportedScene" and kind != "ImportedMesh":
		return []
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	if meshes.is_empty():
		return []
	var space_root: Node3D = _parts_root if _parts_root != null else root
	var combined_bounds := _combined_mesh_bounds_in_node_space(space_root, meshes)
	var center := combined_bounds.get_center()
	var result: Array = []
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := _mesh_bounds_in_node_space(space_root, mesh_instance)
		if mesh_bounds.size.length_squared() <= 0.0001:
			continue
		var mesh_center := mesh_bounds.get_center()
		var part_size := Vector3(
			maxf(mesh_bounds.size.x, 0.12),
			maxf(mesh_bounds.size.y, 0.12),
			maxf(mesh_bounds.size.z, 0.12)
		)
		result.append({
			"name": mesh_instance.name,
			"kind": "ImportedMeshPart",
			"source_kind": kind,
			"position": [mesh_center.x - center.x, mesh_center.y - center.y, mesh_center.z - center.z],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [part_size.x, part_size.y, part_size.z],
			"color": _get_mesh_instance_color(mesh_instance).to_html(false),
			"surface_materials": _serialize_mesh_surface_materials(mesh_instance),
			"anchored": true,
			"can_collide": true
		})
	return result

func _serialize_mesh_surface_materials(mesh_instance: MeshInstance3D) -> Array:
	var result: Array = []
	if mesh_instance == null or mesh_instance.mesh == null:
		return result
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var material := mesh_instance.get_active_material(surface_index)
		if not (material is BaseMaterial3D):
			continue
		var base := material as BaseMaterial3D
		var entry := {
			"surface": surface_index,
			"color": base.albedo_color.to_html(false),
			"metallic": base.metallic,
			"roughness": base.roughness,
			"vertex_color_use_as_albedo": base.vertex_color_use_as_albedo,
			"emission_enabled": base.emission_enabled,
			"emission": base.emission.to_html(false)
		}
		result.append(entry)
	return result

func _collect_mesh_instances(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, meshes)

func _combined_mesh_center(root: Node3D, meshes: Array[MeshInstance3D]) -> Vector3:
	return _combined_mesh_bounds_in_node_space(root, meshes).get_center()

func _combined_mesh_bounds_in_node_space(space_root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var has_bounds := false
	var combined := AABB()
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := _mesh_bounds_in_node_space(space_root, mesh_instance)
		if mesh_bounds.size.length_squared() <= 0.0001:
			continue
		combined = mesh_bounds if not has_bounds else combined.merge(mesh_bounds)
		has_bounds = true
	return combined if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)

func _mesh_bounds_in_node_space(space_root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	if space_root == null or mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var local_aabb := mesh_instance.mesh.get_aabb()
	var min_corner := local_aabb.position
	var max_corner := local_aabb.position + local_aabb.size
	var to_space := space_root.global_transform.affine_inverse() * mesh_instance.global_transform
	var points := [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z)
	]
	var bounds := AABB()
	var has_point := false
	for local_point in points:
		var space_point: Vector3 = to_space * local_point
		bounds = AABB(space_point, Vector3.ZERO) if not has_point else bounds.expand(space_point)
		has_point = true
	return bounds if has_point else AABB()

func _get_mesh_instance_color(mesh_instance: MeshInstance3D) -> Color:
	var mesh_material := mesh_instance.get_active_material(0)
	if mesh_material is BaseMaterial3D:
		return (mesh_material as BaseMaterial3D).albedo_color
	return Color(0.82, 0.82, 0.82, 1.0)

func _capture_model_preview_data_uri(model_data: Dictionary = {}) -> String:
	if model_data.is_empty(): model_data = _collect_model_data()
	var renderer := load("res://scripts/lobby/catalog_thumbnail_renderer.gd").new() as Node
	add_child(renderer)
	var texture: Texture2D = await renderer.render_item({"category": "model", "data": model_data}, true)
	renderer.queue_free()
	if texture == null: return ""
	var bytes := texture.get_image().save_png_to_buffer()
	return "data:image/png;base64,%s" % Marshalls.raw_to_base64(bytes) if not bytes.is_empty() else ""

func _serialize_part(node: Node3D) -> Dictionary:
	return {
		"name": node.name,
		"kind": str(node.get_meta("kind", "Block")),
		"position": [node.position.x, node.position.y, node.position.z],
		"rotation_degrees": [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z],
		"scale": [node.scale.x, node.scale.y, node.scale.z],
		"color": _get_part_color(node).to_html(false),
		"anchored": bool(node.get_meta("anchored", true)),
		"can_collide": bool(node.get_meta("can_collide", true))
	}

func _create_part_from_data(data: Dictionary, offset: Vector3 = Vector3.ZERO) -> Node3D:
	var kind := str(data.get("kind", "Block"))
	_part_counter += 1
	var part := StaticBody3D.new()
	part.name = "%s_Copy%d" % [str(data.get("name", kind)).strip_edges(), _part_counter]
	part.set_meta("kind", kind)
	part.set_meta("anchored", bool(data.get("anchored", true)))
	part.set_meta("can_collide", bool(data.get("can_collide", true)))
	var color := _model_part_color_from_data(data, Color.WHITE)
	part.set_meta("bobux_color", color)
	part.position = _array_to_vector3(data.get("position", []), Vector3.ZERO) + offset
	part.rotation_degrees = _array_to_vector3(data.get("rotation_degrees", []), Vector3.ZERO)
	part.scale = _array_to_vector3(data.get("scale", []), Vector3.ONE)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _create_mesh_for_kind(kind)
	mesh_instance.set_surface_override_material(0, _create_part_material(color))
	part.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = _create_shape_for_kind(kind)
	collision.disabled = not bool(data.get("can_collide", true))
	part.add_child(collision)
	return part

func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]))
	return fallback

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text

func _flat_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	return style

func _tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.17, 0.17) if active else TAB_BAR
	style.border_color = ACCENT if active else TAB_BAR
	style.border_width_bottom = 2 if active else 0
	return style

func _dark_button_style() -> StyleBoxFlat:
	return _button_style(Color(0.18, 0.18, 0.18), Color(0.26, 0.26, 0.26))

func _button_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
