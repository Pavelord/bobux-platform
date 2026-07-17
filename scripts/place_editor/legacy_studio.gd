extends Node3D

const ACCELERATION = 10.0
const MAX_SPEED = 25.0
const MOUSE_SENSITIVITY = 0.005
const SPAWN_DECAL_PATH = "res://images/spawn.png"
const BOX_SELECT_MIN_DRAG: float = 8.0
const GIZMO_MIN_SCALE: float = 1.2
const GIZMO_SCALE_DISTANCE_FACTOR: float = 0.12
const MIN_BLOCK_SCALE: float = 0.25
const MOVE_GRID_SNAP: float = 0.5
const SCALE_GRID_SNAP: float = 0.25
const ROTATION_SNAP_DEGREES: float = 15.0
const SELECTION_BODY_NAME: String = "SelectionBody"
const COLLISION_BODY_NAME: String = "CollisionBody"
const SPECIAL_VISUALS_NAME: String = "SpecialVisuals"
const STUDIO_TOP_BAR_HEIGHT: float = 110.0
const SELECTION_RAY_MASK: int = 1
const GIZMO_RAY_MASK: int = 1 << 1
const COLLISION_PREVIEW_MASK: int = 1 << 2
const ILLEGAL_MAP_NAME_CHARS: Array[String] = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
const DEFAULT_PLAYER_MOVE_SPEED: float = 24.0
const DEFAULT_PLAYER_SPRINT_MULTIPLIER: float = 1.25
const DEFAULT_PLAYER_JUMP_VELOCITY: float = 31.0
const DEFAULT_MODE_MUSIC_VOLUME: float = 0.65
const MODE_MUSIC_FILE_BASENAME: String = "mode_music"
const MODE_SKY_FILE_BASENAME: String = "mode_sky"
const DEFAULT_BLOCK_DAMAGE: float = 25.0
const SHAPE_OPTIONS: Array[String] = ["Select", "Box", "Sphere", "Wedge", "Cylinder", "Spawn", "Checkpoint", "Teleport"]
const CLOUD_INLINE_ASSET_MAX_BYTES: int = 24 * 1024 * 1024
const CLOUD_INLINE_ASSET_TOTAL_MAX_BYTES: int = 96 * 1024 * 1024
const CLOUD_INLINE_ASSET_MAX_TRACKS: int = 32
const CLOUD_THUMBNAIL_MAX_DIMENSION: int = 320
const CLOUD_THUMBNAIL_FALLBACK_MAX_BYTES: int = 256 * 1024
const RbxlRuntimeImporter = preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
const RBXL_RUNTIME_OBJECT_GROUP: String = "studio_runtime_objects"

@export var camera: Camera3D
@export var placement_parent: Node3D
@export var sun_light: DirectionalLight3D

var velocity = Vector3.ZERO
var is_dragging = false
var ray_length = 1000.0
var current_color = Color.WHITE
var current_shape: String = "Select" # Select, Box, Sphere, Wedge, Cylinder
var current_material_type: String = "Plastic"
var selected_block: Node3D = null
var is_dragging_block: bool = false
var drag_plane: Plane

# UI references built at runtime
var explorer_tree: Tree = null
var inspector_panel: VBoxContainer = null
var player_settings_panel: VBoxContainer = null
var atmosphere_settings_panel: VBoxContainer = null
var toolbar_hbox: HBoxContainer = null
var name_edit: LineEdit = null
var transparency_slider: HSlider = null
var can_collide_check: CheckBox = null
var damage_enabled_check: CheckBox = null
var damage_amount_spin: SpinBox = null
var material_option: OptionButton = null
var color_picker: ColorPickerButton = null
var time_slider: HSlider = null
var toolbar_status_label: Label = null
var inspector_summary_label: Label = null
var player_move_speed_spin: SpinBox = null
var player_sprint_multiplier_spin: SpinBox = null
var player_jump_velocity_spin: SpinBox = null
var atmosphere_music_path_edit: LineEdit = null
var atmosphere_music_list: VBoxContainer = null
var atmosphere_music_volume_slider: HSlider = null
var atmosphere_music_volume_label: Label = null
var atmosphere_sky_path_edit: LineEdit = null
var music_file_dialog: FileDialog = null
var sky_file_dialog: FileDialog = null
var rbxl_file_dialog: FileDialog = null
var toolbox_dialog: AcceptDialog = null
var publish_progress_dialog: AcceptDialog = null
var publish_progress_label: Label = null
var publish_progress_bar: ProgressBar = null
var mobile_studio_controls_layer: CanvasLayer = null
var mobile_studio_joystick_base: Panel = null
var mobile_studio_joystick_knob: Panel = null
var mobile_studio_move_vector: Vector2 = Vector2.ZERO
var mobile_studio_look_touch_active: bool = false

# Map data
var current_map_name: String = "Untitled Place"
var current_map_folder: String = ""
var custom_icon_set: bool = false
var current_music_source_paths: Array[String] = []
var current_sky_source_path: String = ""
var current_imported_sound_assets: Array[Dictionary] = []

# Selection & transform state
var selected_blocks: Array[Node3D] = []
var selection_highlight_root: Node3D = null
var selection_highlight_material: StandardMaterial3D = null
var transform_gizmo_root: Node3D = null
var shape_buttons: Dictionary = {}
var transform_mode_buttons: Dictionary = {}
var current_transform_mode: String = "move"
var active_gizmo_axis: String = ""
var active_gizmo_mode: String = ""
var active_gizmo_sign: int = 1
var gizmo_drag_plane: Plane
var gizmo_drag_axis_world: Vector3 = Vector3.ZERO
var gizmo_drag_start_hit: Vector3 = Vector3.ZERO
var gizmo_drag_start_position: Vector3 = Vector3.ZERO
var gizmo_drag_start_scale: Vector3 = Vector3.ONE
var gizmo_drag_start_basis: Basis = Basis.IDENTITY
var gizmo_drag_start_vector: Vector3 = Vector3.ZERO
var gizmo_drag_start_pivot: Vector3 = Vector3.ZERO
var gizmo_drag_start_positions: Dictionary = {}
var gizmo_drag_start_scales: Dictionary = {}
var gizmo_drag_start_bases: Dictionary = {}
var gizmo_drag_start_offsets: Dictionary = {}
var is_gizmo_dragging: bool = false
var gizmo_drag_start_mouse: Vector2 = Vector2.ZERO
var gizmo_drag_screen_axis: Vector2 = Vector2.RIGHT
var gizmo_drag_units_per_pixel: float = 0.02
var is_scaling: bool = false
var scale_start_mouse: Vector2 = Vector2.ZERO
var scale_start_val: Vector3 = Vector3.ONE

# Box select UI
var selection_overlay_layer: CanvasLayer = null
var selection_box_rect: Panel = null
var box_select_start: Vector2 = Vector2.ZERO
var box_select_current: Vector2 = Vector2.ZERO
var is_box_selecting: bool = false
var box_select_pending_block: Node3D = null
var block_clipboard: Array = []
var undo_history: Array = []
var redo_history: Array = []
var is_restoring_history: bool = false

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not camera:
		camera = Camera3D.new()
		add_child(camera)
		camera.position.y = 5.0
		camera.position.z = 10.0
	_reset_studio_camera_interpolation()

	_build_toolbar()
	_build_explorer_panel()
	_build_inspector_panel()
	_setup_rbxl_import_dialog()
	_build_selection_overlay()
	_create_selection_highlight()
	_create_transform_gizmo()

	# Try to load last edited map
	if GameState.selected_map_folder != "":
		current_map_folder = GameState.selected_map_folder
		var meta_path := current_map_folder + "/meta.json"
		if FileAccess.file_exists(meta_path):
			var f := FileAccess.open(meta_path, FileAccess.READ)
			if f:
				var json := JSON.new()
				if json.parse(f.get_as_text()) == OK:
					current_map_name = json.data.get("name", "Untitled Place")
				f.close()

	if current_map_folder != "":
		_load_map_from_folder(current_map_folder)
		# Check if icon already exists (user may have set a custom one)
		if FileAccess.file_exists(current_map_folder + "/icon.png"):
			custom_icon_set = true

	# If no blocks loaded, create a default baseplate as a studio_parts object
	var parent_node = placement_parent if placement_parent else self
	var has_blocks := false
	for child in parent_node.get_children():
		if child.is_in_group("studio_parts"):
			has_blocks = true
			break
	if not has_blocks:
		_create_default_baseplate()
	_commit_editor_history("Initial", false)
	_setup_mobile_studio_controls()

func _process(delta: float) -> void:
	_process_movement(delta)
	_update_selection_highlight()
	_update_transform_gizmo()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var text_input_focused := _is_text_input_focused()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_dragging = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				is_dragging = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if text_input_focused:
			return

		if event.button_index == MOUSE_BUTTON_LEFT and not is_dragging:
			if event.pressed:
				if current_shape == "Select":
					var gizmo_result := _get_ray_intersection(GIZMO_RAY_MASK)
					var gizmo_handle := _get_gizmo_handle_from_ray_result(gizmo_result)
					if gizmo_handle:
						_begin_gizmo_drag(gizmo_handle)
						return

					var clicked_block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
					_begin_box_selection(get_viewport().get_mouse_position(), clicked_block)
					return
				else:
					_attempt_placement()
					return
			else:
				if is_box_selecting:
					_complete_box_selection()
				if is_gizmo_dragging:
					_end_gizmo_drag()
				return

		# Middle click to delete
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_attempt_deletion()
			return

	if event is InputEventMouseMotion:
		if is_dragging:
			camera.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
			camera.rotation.x = clamp(camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
			_reset_studio_camera_interpolation()
		elif is_gizmo_dragging and is_instance_valid(selected_block):
			_update_gizmo_drag(get_viewport().get_mouse_position())
		elif is_box_selecting:
			box_select_current = get_viewport().get_mouse_position()
			_update_selection_box_visual()
		return

	if event is InputEventKey and text_input_focused:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.ctrl_pressed:
			match key_event.keycode:
				KEY_C:
					_copy_selected_blocks()
					return
				KEY_V:
					_paste_clipboard_blocks()
					return
				KEY_A:
					_select_all_blocks()
					return
				KEY_D:
					_duplicate_selected_blocks()
					return
				KEY_Z:
					_undo_editor_action()
					return
				KEY_Y:
					_redo_editor_action()
					return
		match key_event.keycode:
			KEY_DELETE:
				_delete_selected_blocks()
			KEY_ESCAPE:
				_clear_selection()
			KEY_F:
				_focus_camera_on_selection()
			KEY_G:
				_set_transform_mode("move")
			KEY_T:
				_set_transform_mode("scale")
			KEY_R:
				_set_transform_mode("rotate")
			KEY_Y:
				if selected_block and is_instance_valid(selected_block):
					selected_block.rotation_degrees.y = snappedf(selected_block.rotation_degrees.y + 90.0, 90.0)
					_update_block_collision(selected_block)
					_update_inspector()
					_commit_editor_history("Rotate")
		return

func _process_movement(delta: float) -> void:
	if _is_text_input_focused():
		velocity = Vector3.ZERO
		return
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mobile_studio_move_vector.length() > 0.05:
		input_dir = mobile_studio_move_vector
	var direction = (camera.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var up_dir = 0.0
	if Input.is_physical_key_pressed(KEY_E): up_dir += 1.0
	if Input.is_physical_key_pressed(KEY_Q): up_dir -= 1.0
	direction += camera.transform.basis.y * up_dir

	var current_speed = MAX_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		current_speed *= 2.5
	if mobile_studio_move_vector.length() > 0.05:
		current_speed *= 0.82

	if direction.length() > 0:
		velocity = velocity.lerp(direction * current_speed, ACCELERATION * delta)
	else:
		velocity = velocity.lerp(Vector3.ZERO, ACCELERATION * delta)

	camera.position += velocity * delta
	_reset_studio_camera_interpolation()

func _reset_studio_camera_interpolation() -> void:
	if camera == null:
		return
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()

func _setup_mobile_studio_controls() -> void:
	if not _is_mobile_studio_runtime() or mobile_studio_controls_layer != null:
		return
	mobile_studio_controls_layer = CanvasLayer.new()
	mobile_studio_controls_layer.name = "StudioMobileControls"
	mobile_studio_controls_layer.layer = 95
	add_child(mobile_studio_controls_layer)

	mobile_studio_joystick_base = Panel.new()
	mobile_studio_joystick_base.name = "StudioMoveJoystick"
	mobile_studio_joystick_base.anchor_left = 0.0
	mobile_studio_joystick_base.anchor_top = 1.0
	mobile_studio_joystick_base.anchor_right = 0.0
	mobile_studio_joystick_base.anchor_bottom = 1.0
	mobile_studio_joystick_base.offset_left = 54.0
	mobile_studio_joystick_base.offset_top = -198.0
	mobile_studio_joystick_base.offset_right = 198.0
	mobile_studio_joystick_base.offset_bottom = -54.0
	mobile_studio_joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	mobile_studio_joystick_base.add_theme_stylebox_override("panel", _make_mobile_round_style(Color(0.08, 0.10, 0.12, 0.34), Color(1, 1, 1, 0.22), 72))
	mobile_studio_joystick_base.gui_input.connect(_on_mobile_studio_joystick_input)
	mobile_studio_controls_layer.add_child(mobile_studio_joystick_base)

	mobile_studio_joystick_knob = Panel.new()
	mobile_studio_joystick_knob.name = "StudioMoveKnob"
	mobile_studio_joystick_knob.anchor_left = 0.5
	mobile_studio_joystick_knob.anchor_top = 0.5
	mobile_studio_joystick_knob.anchor_right = 0.5
	mobile_studio_joystick_knob.anchor_bottom = 0.5
	mobile_studio_joystick_knob.offset_left = -31.0
	mobile_studio_joystick_knob.offset_top = -31.0
	mobile_studio_joystick_knob.offset_right = 31.0
	mobile_studio_joystick_knob.offset_bottom = 31.0
	mobile_studio_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_studio_joystick_knob.add_theme_stylebox_override("panel", _make_mobile_round_style(Color(0.94, 0.96, 1.0, 0.72), Color(0, 0, 0, 0.14), 31))
	mobile_studio_joystick_base.add_child(mobile_studio_joystick_knob)

	var look_area := Control.new()
	look_area.name = "StudioLookArea"
	look_area.anchor_left = 0.42
	look_area.anchor_top = 0.0
	look_area.anchor_right = 1.0
	look_area.anchor_bottom = 1.0
	look_area.mouse_filter = Control.MOUSE_FILTER_PASS
	look_area.gui_input.connect(_on_mobile_studio_look_input)
	mobile_studio_controls_layer.add_child(look_area)

func _is_mobile_studio_runtime() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	var mobile_runtime := get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))

func _on_mobile_studio_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_update_mobile_studio_joystick(touch.position)
		else:
			_reset_mobile_studio_joystick()
	elif event is InputEventScreenDrag:
		_update_mobile_studio_joystick((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			_update_mobile_studio_joystick(button.position)
		else:
			_reset_mobile_studio_joystick()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		_update_mobile_studio_joystick((event as InputEventMouseMotion).position)

func _update_mobile_studio_joystick(local_position: Vector2) -> void:
	if mobile_studio_joystick_base == null or mobile_studio_joystick_knob == null:
		return
	var base_size := mobile_studio_joystick_base.size
	var center := base_size * 0.5
	var radius := maxf(48.0, minf(base_size.x, base_size.y) * 0.42)
	var delta := (local_position - center).limit_length(radius)
	mobile_studio_move_vector = delta / radius
	var knob_size := mobile_studio_joystick_knob.size
	mobile_studio_joystick_knob.position = center + delta - knob_size * 0.5

func _reset_mobile_studio_joystick() -> void:
	mobile_studio_move_vector = Vector2.ZERO
	if mobile_studio_joystick_base == null or mobile_studio_joystick_knob == null:
		return
	var center := mobile_studio_joystick_base.size * 0.5
	mobile_studio_joystick_knob.position = center - mobile_studio_joystick_knob.size * 0.5

func _on_mobile_studio_look_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventScreenTouch:
		mobile_studio_look_touch_active = (event as InputEventScreenTouch).pressed
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		camera.rotation.y -= drag.relative.x * MOUSE_SENSITIVITY
		camera.rotation.x = clamp(camera.rotation.x - drag.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
		_reset_studio_camera_interpolation()
	elif event is InputEventMouseButton:
		mobile_studio_look_touch_active = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and mobile_studio_look_touch_active:
		var motion := event as InputEventMouseMotion
		camera.rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
		camera.rotation.x = clamp(camera.rotation.x - motion.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
		_reset_studio_camera_interpolation()

func _make_mobile_round_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _is_text_input_focused() -> bool:
	var focused: Node = get_viewport().gui_get_focus_owner()
	while focused:
		if focused is LineEdit or focused is TextEdit or focused is SpinBox:
			return true
		focused = focused.get_parent()
	return false

func _get_editor_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	var parent = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child is Node3D and child.is_in_group("studio_parts") and not child.is_queued_for_deletion():
			parts.append(child)
	return parts

func _set_selection(blocks: Array) -> void:
	var filtered: Array[Node3D] = []
	for block in blocks:
		if block is Node3D and is_instance_valid(block) and block.is_in_group("studio_parts") and not filtered.has(block):
			filtered.append(block)

	selected_blocks = filtered
	selected_block = selected_blocks[0] if not selected_blocks.is_empty() else null
	if selected_block:
		_update_inspector()
	else:
		_clear_inspector()
	_sync_explorer_selection()
	_sync_selection_highlight_instances()
	_update_transform_gizmo()
	_update_selection_status()

func _clear_selection() -> void:
	selected_blocks.clear()
	selected_block = null
	_clear_inspector()
	_sync_explorer_selection()
	_sync_selection_highlight_instances()
	_update_transform_gizmo()
	_update_selection_status()

func _select_all_blocks() -> void:
	var all_parts := _get_editor_parts()
	if all_parts.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "No blocks to select"
		return
	_set_selection(all_parts)
	if toolbar_status_label:
		toolbar_status_label.text = "Selected all %d block(s)" % all_parts.size()

func _delete_selected_blocks() -> void:
	if selected_blocks.is_empty():
		if selected_block and is_instance_valid(selected_block):
			selected_blocks = [selected_block]
		else:
			return

	var blocks_to_delete := selected_blocks.duplicate()
	_clear_selection()
	for block in blocks_to_delete:
		if is_instance_valid(block):
			block.queue_free()
	call_deferred("_refresh_explorer")
	_commit_editor_history("Delete")

func _copy_selected_blocks() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	if valid_blocks.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Nothing to copy"
		return
	block_clipboard.clear()
	for block in valid_blocks:
		block_clipboard.append(_serialize_block_for_clipboard(block))
	if toolbar_status_label:
		toolbar_status_label.text = "Copied %d block(s)" % block_clipboard.size()

func _duplicate_selected_blocks() -> void:
	if _get_valid_selected_blocks().is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Nothing to duplicate"
		return
	_copy_selected_blocks()
	_paste_clipboard_blocks()

func _paste_clipboard_blocks() -> void:
	if block_clipboard.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Clipboard is empty"
		return
	var parent := placement_parent if placement_parent else self
	var created: Array[Node3D] = []
	var paste_offset := Vector3(MOVE_GRID_SNAP * 2.0, 0.0, MOVE_GRID_SNAP * 2.0)
	for block_data_variant in block_clipboard:
		if not (block_data_variant is Dictionary):
			continue
		var block_data: Dictionary = (block_data_variant as Dictionary).duplicate(true)
		var pasted := _create_block_from_clipboard(block_data, paste_offset)
		if pasted == null:
			continue
		parent.add_child(pasted)
		created.append(pasted)
	if created.is_empty():
		return
	_set_selection(created)
	_refresh_explorer()
	if toolbar_status_label:
		toolbar_status_label.text = "Pasted %d block(s)" % created.size()
	_commit_editor_history("Paste")

func _serialize_block_for_clipboard(block: Node3D) -> Dictionary:
	var shape_type: String = str(block.get_meta("shape_type", "Box"))
	var color := Color.WHITE
	if block is MeshInstance3D:
		var material := (block as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if material:
			color = material.albedo_color
	return {
		"name": str(block.get_meta("block_name", block.name)),
		"shape": shape_type,
		"position": block.position,
		"rotation_degrees": block.rotation_degrees,
		"scale": block.scale,
		"color": color,
		"material": str(block.get_meta("material_type", "Plastic")),
		"transparency": float(block.get_meta("transparency", 0.0)),
		"can_collide": bool(block.get_meta("can_collide", true)),
		"deals_damage": bool(block.get_meta("deals_damage", false)),
		"damage_amount": float(block.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)),
		"is_spawn": bool(block.get_meta("is_spawn", false))
	}

func _create_block_from_clipboard(block_data: Dictionary, paste_offset: Vector3, preserve_original_name: bool = false) -> MeshInstance3D:
	var shape_type: String = str(block_data.get("shape", "Box"))
	if bool(block_data.get("is_spawn", false)) and shape_type == "Box":
		shape_type = "Spawn"
	var color: Color = block_data.get("color", Color.WHITE) if block_data.get("color", Color.WHITE) is Color else Color.WHITE
	var material_type: String = str(block_data.get("material", "Plastic"))
	var transparency: float = float(block_data.get("transparency", 0.0))
	var can_collide: bool = bool(block_data.get("can_collide", true))
	var original_name: String = str(block_data.get("name", shape_type)).strip_edges()
	var block_name := original_name if preserve_original_name else _make_unique_block_copy_name(original_name)
	var mesh_inst := _build_block_instance(shape_type, color, material_type, transparency, can_collide, block_name)
	mesh_inst.position = _vector3_from_variant(block_data.get("position", Vector3.ZERO), Vector3.ZERO) + paste_offset
	mesh_inst.rotation_degrees = _vector3_from_variant(block_data.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	mesh_inst.scale = _vector3_from_variant(block_data.get("scale", Vector3.ONE), Vector3.ONE)
	mesh_inst.set_meta("is_spawn", shape_type == "Spawn")
	mesh_inst.set_meta("deals_damage", bool(block_data.get("deals_damage", false)))
	mesh_inst.set_meta("damage_amount", float(block_data.get("damage_amount", DEFAULT_BLOCK_DAMAGE)))
	_update_block_collision(mesh_inst)
	return mesh_inst

func _make_unique_block_copy_name(original_name: String) -> String:
	var base_name := original_name.strip_edges()
	if base_name.is_empty():
		base_name = "Part"
	return "%s_Copy_%04d" % [base_name, randi() % 10000]

func _vector3_from_variant(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]))
	if value is Dictionary:
		return Vector3(float((value as Dictionary).get("x", fallback.x)), float((value as Dictionary).get("y", fallback.y)), float((value as Dictionary).get("z", fallback.z)))
	return fallback

func _capture_editor_snapshot(label: String) -> Dictionary:
	var blocks: Array = []
	for block in _get_editor_parts():
		blocks.append(_serialize_block_for_clipboard(block))
	return {
		"label": label,
		"blocks": blocks
	}

func _commit_editor_history(label: String, clear_redo: bool = true) -> void:
	if is_restoring_history:
		return
	var snapshot := _capture_editor_snapshot(label)
	undo_history.append(snapshot)
	if undo_history.size() > 80:
		undo_history.pop_front()
	if clear_redo:
		redo_history.clear()

func _restore_editor_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("blocks"):
		return
	is_restoring_history = true
	var parent := placement_parent if placement_parent else self
	for block in _get_editor_parts():
		if is_instance_valid(block):
			block.queue_free()
	await get_tree().process_frame
	var restored_blocks: Array = snapshot.get("blocks", []) if snapshot.get("blocks", []) is Array else []
	for block_variant in restored_blocks:
		if not (block_variant is Dictionary):
			continue
		var block := _create_block_from_clipboard((block_variant as Dictionary).duplicate(true), Vector3.ZERO, true)
		if block:
			parent.add_child(block)
	is_restoring_history = false
	_clear_selection()
	_refresh_explorer()
	_update_selection_status()

func _undo_editor_action() -> void:
	if undo_history.size() <= 1:
		if toolbar_status_label:
			toolbar_status_label.text = "Nothing to undo"
		return
	var current_snapshot: Dictionary = undo_history.pop_back()
	redo_history.append(current_snapshot)
	var previous_snapshot: Dictionary = undo_history[undo_history.size() - 1]
	await _restore_editor_snapshot(previous_snapshot)
	if toolbar_status_label:
		toolbar_status_label.text = "Undo: %s" % str(previous_snapshot.get("label", "Edit"))

func _redo_editor_action() -> void:
	if redo_history.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Nothing to redo"
		return
	var snapshot: Dictionary = redo_history.pop_back()
	undo_history.append(snapshot)
	await _restore_editor_snapshot(snapshot)
	if toolbar_status_label:
		toolbar_status_label.text = "Redo: %s" % str(snapshot.get("label", "Edit"))

func _focus_camera_on_selection() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	if valid_blocks.is_empty() or camera == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Select a block to focus"
		return
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	for block in valid_blocks:
		for point in _get_node_world_corners(block):
			min_point = min_point.min(point)
			max_point = max_point.max(point)
	var center := (min_point + max_point) * 0.5
	var bounds_size := max_point - min_point
	var distance := clampf(bounds_size.length() * 1.35, 8.0, 160.0)
	var forward := -camera.global_transform.basis.z.normalized()
	camera.global_position = center - forward * distance + Vector3.UP * maxf(2.0, bounds_size.y * 0.35)
	_reset_studio_camera_interpolation()
	if toolbar_status_label:
		toolbar_status_label.text = "Focused selection"

func _update_selection_status() -> void:
	var selected_count := selected_blocks.size()
	if toolbar_status_label:
		if selected_count <= 0:
			toolbar_status_label.text = "No selection | %s" % current_transform_mode.capitalize()
		elif selected_count == 1 and selected_block:
			var block_name: String = selected_block.get_meta("block_name", selected_block.name)
			toolbar_status_label.text = "%s | %s" % [block_name, current_transform_mode.capitalize()]
		else:
			toolbar_status_label.text = "%d selected | %s" % [selected_count, current_transform_mode.capitalize()]
	if inspector_summary_label:
		if selected_count <= 0:
			inspector_summary_label.text = "Select a block to edit its properties."
		elif selected_count == 1 and selected_block:
			var shape_type: String = selected_block.get_meta("shape_type", "Box")
			inspector_summary_label.text = "Editing %s (%s)" % [selected_block.get_meta("block_name", selected_block.name), shape_type]
		else:
			inspector_summary_label.text = "%d blocks selected. Inspector edits the primary block." % selected_count

func _begin_box_selection(start_pos: Vector2, pending_block: Node3D = null) -> void:
	is_box_selecting = true
	box_select_start = start_pos
	box_select_current = start_pos
	box_select_pending_block = pending_block
	_update_selection_box_visual()

func _complete_box_selection() -> void:
	if not is_box_selecting:
		return
	var rect := Rect2(box_select_start, box_select_current - box_select_start).abs()
	is_box_selecting = false
	_clear_selection_box_visual()
	if rect.size.length() < BOX_SELECT_MIN_DRAG:
		if box_select_pending_block and is_instance_valid(box_select_pending_block):
			_set_selection([box_select_pending_block])
		else:
			_clear_selection()
		box_select_pending_block = null
		return

	var found: Array[Node3D] = []
	for block in _get_editor_parts():
		var screen_rect = _get_block_screen_rect(block)
		if screen_rect != null and rect.intersects(screen_rect):
			found.append(block)
	box_select_pending_block = null
	_set_selection(found)

func _update_selection_box_visual() -> void:
	if selection_box_rect == null:
		return
	var rect := Rect2(box_select_start, box_select_current - box_select_start).abs()
	selection_box_rect.visible = is_box_selecting
	selection_box_rect.position = rect.position
	selection_box_rect.size = rect.size

func _clear_selection_box_visual() -> void:
	if selection_box_rect:
		selection_box_rect.visible = false

func _get_block_screen_rect(block: Node3D) -> Variant:
	if camera == null:
		return null

	var points: Array[Vector3] = _get_node_world_corners(block)
	if points.is_empty():
		return null

	var visible_points: Array[Vector2] = []
	for point in points:
		if camera.is_position_behind(point):
			continue
		visible_points.append(camera.unproject_position(point))

	if visible_points.is_empty():
		return null

	var min_point := visible_points[0]
	var max_point := visible_points[0]
	for i in range(1, visible_points.size()):
		min_point = min_point.min(visible_points[i])
		max_point = max_point.max(visible_points[i])
	return Rect2(min_point, max_point - min_point)

func _get_node_world_center(node: Node3D) -> Vector3:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh:
			var local_center := mesh_node.mesh.get_aabb().get_center()
			return mesh_node.to_global(local_center)
	return node.global_position

func _get_node_world_corners(node: Node3D) -> Array[Vector3]:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh:
			return _get_aabb_world_corners(mesh_node, mesh_node.mesh.get_aabb())
	return [node.global_position]

func _get_aabb_world_corners(node: Node3D, aabb: AABB) -> Array[Vector3]:
	var min_point := aabb.position
	var max_point := aabb.position + aabb.size
	var local_points: Array[Vector3] = [
		Vector3(min_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, min_point.z),
		Vector3(min_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, min_point.z),
		Vector3(min_point.x, min_point.y, max_point.z),
		Vector3(max_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, max_point.z),
		Vector3(max_point.x, max_point.y, max_point.z),
	]
	var world_points: Array[Vector3] = []
	for local_point in local_points:
		world_points.append(node.to_global(local_point))
	return world_points

# ===== RAY CASTING =====
func _get_ray_intersection(collision_mask: int = SELECTION_RAY_MASK) -> Dictionary:
	if not camera:
		return {}
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var space_state := world.direct_space_state
	if space_state == null:
		return {}
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = collision_mask
	return space_state.intersect_ray(query)

func _get_block_from_ray_result(result: Dictionary) -> Node3D:
	if result.is_empty() or not (result.collider is Node):
		return null
	var node: Node = result.collider.get_parent()
	while node and node != self:
		if node is Node3D and node.is_in_group("studio_parts"):
			return node
		node = node.get_parent()
	return null

func _get_gizmo_handle_from_ray_result(result: Dictionary) -> Node3D:
	if result.is_empty() or not (result.collider is Node):
		return null
	var node: Node = result.collider
	while node and node != self:
		if node is Node3D and node.has_meta("gizmo_mode") and node.has_meta("gizmo_axis"):
			return node
		node = node.get_parent()
	return null

func _try_select_block() -> bool:
	var block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
	if block:
		_select_block(block)
		return true
	return false

func _select_block(block: Node3D) -> void:
	_set_selection([block])

func _attempt_placement() -> void:
	var result = _get_ray_intersection(SELECTION_RAY_MASK)
	if result:
		var offset = result.normal * (0.5 if current_shape != "Spawn" else 0.25)
		var pos = (result.position + offset).snapped(Vector3(0.5, 0.5, 0.5))
		_place_block(pos)
	else:
		var mouse_pos = get_viewport().get_mouse_position()
		var origin = camera.project_ray_origin(mouse_pos)
		var normal = camera.project_ray_normal(mouse_pos)
		var pos = (origin + normal * 10.0).snapped(Vector3(0.5, 0.5, 0.5))
		_place_block(pos)

func _attempt_deletion() -> void:
	var block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
	if block == null:
		return
	_set_selection([block])
	_delete_selected_blocks()

# ===== BLOCK PLACEMENT =====
func _place_block(pos: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource: Mesh = _create_mesh_for_shape(current_shape)
	var mat := _create_material(current_color, current_material_type)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource

	mesh_inst.position = pos
	mesh_inst.scale = _get_default_block_scale(current_shape)
	mesh_inst.add_to_group("studio_parts")
	mesh_inst.set_meta("block_name", current_shape + "_" + str(randi() % 10000))
	mesh_inst.set_meta("material_type", current_material_type)
	mesh_inst.set_meta("shape_type", current_shape)
	mesh_inst.set_meta("is_spawn", current_shape == "Spawn")
	mesh_inst.set_meta("can_collide", true)
	mesh_inst.set_meta("deals_damage", false)
	mesh_inst.set_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)
	mesh_inst.set_meta("transparency", 0.0)
	_rebuild_block_helpers(mesh_inst)

	var parent = placement_parent if placement_parent else self
	parent.add_child(mesh_inst)
	_set_selection([mesh_inst])
	_refresh_explorer()
	_commit_editor_history("Place %s" % current_shape)

func _build_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource: Mesh = _create_mesh_for_shape(shape_name)
	var mat := _create_material(color, material_type, transparency)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource
	mesh_inst.scale = _get_default_block_scale(shape_name)
	mesh_inst.add_to_group("studio_parts")
	mesh_inst.set_meta("block_name", block_name)
	mesh_inst.set_meta("material_type", material_type)
	mesh_inst.set_meta("shape_type", shape_name)
	mesh_inst.set_meta("is_spawn", shape_name == "Spawn")
	mesh_inst.set_meta("can_collide", can_collide)
	mesh_inst.set_meta("deals_damage", false)
	mesh_inst.set_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)
	mesh_inst.set_meta("transparency", transparency)
	_rebuild_block_helpers(mesh_inst)
	return mesh_inst

func _create_mesh_for_shape(shape_name: String) -> Mesh:
	if shape_name == "Spawn" or shape_name == "Checkpoint" or shape_name == "Teleport":
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereMesh.new()
		"Cylinder":
			return CylinderMesh.new()
		"Wedge":
			var wedge := PrismMesh.new()
			wedge.size = Vector3(1, 1, 1)
			return wedge
		_: # Box
			return BoxMesh.new()

func _create_collision_for_shape(shape_name: String) -> Shape3D:
	if shape_name == "Spawn" or shape_name == "Checkpoint" or shape_name == "Teleport":
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereShape3D.new()
		"Cylinder":
			return CylinderShape3D.new()
		"Wedge":
			return BoxShape3D.new() # Approximate wedge with box
		_:
			return BoxShape3D.new()

func _create_material(color: Color, mat_type: String, transparency: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0 - transparency)
	mat.roughness = 0.8

	match mat_type:
		"Neon":
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.0
		"Glass":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.3
			mat.roughness = 0.1
			mat.metallic = 0.1
		"Metal":
			mat.metallic = 0.9
			mat.roughness = 0.2
		_: # Plastic
			mat.roughness = 0.8

	if transparency > 0.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 1.0 - transparency

	return mat

func _get_default_block_scale(shape_name: String) -> Vector3:
	match shape_name:
		"Spawn":
			return Vector3(4.0, 0.5, 4.0)
		"Checkpoint", "Teleport":
			return Vector3(4.0, 1.0, 4.0)
		_:
			return Vector3.ONE

func _get_block_shape(block: Node3D) -> String:
	if block.get_meta("is_spawn", false):
		return "Spawn"
	return str(block.get_meta("shape_type", "Box"))

func _rebuild_block_helpers(block: MeshInstance3D) -> void:
	_rebuild_body_shape(block, SELECTION_BODY_NAME, false)
	_rebuild_body_shape(block, COLLISION_BODY_NAME, not block.get_meta("can_collide", true))
	_refresh_special_block_visuals(block)

func _rebuild_body_shape(block: MeshInstance3D, body_name: String, disabled: bool) -> void:
	var body := block.get_node_or_null(body_name) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = body_name
		block.add_child(body)
	body.collision_mask = 0
	body.input_ray_pickable = true
	if body_name == SELECTION_BODY_NAME:
		body.collision_layer = SELECTION_RAY_MASK
	else:
		body.collision_layer = COLLISION_PREVIEW_MASK

	var collision_shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		body.add_child(collision_shape)

	var shape_type := _get_block_shape(block)
	collision_shape.shape = _create_collision_for_shape(shape_type)
	_apply_collision_shape_size(collision_shape, shape_type, block.scale)
	collision_shape.disabled = disabled

func _refresh_special_block_visuals(block: MeshInstance3D) -> void:
	var existing := block.get_node_or_null(SPECIAL_VISUALS_NAME)
	if existing:
		existing.queue_free()

	var shape_type := _get_block_shape(block)
	if shape_type != "Spawn" and shape_type != "Checkpoint" and shape_type != "Teleport":
		return

	var visuals := Node3D.new()
	visuals.name = SPECIAL_VISUALS_NAME
	block.add_child(visuals)

	match shape_type:
		"Spawn":
			visuals.add_child(_create_spawn_decal_node(block.scale))
		"Checkpoint":
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.08
			pole_mesh.bottom_radius = 0.08
			pole_mesh.height = 2.2
			pole.mesh = pole_mesh
			pole.position = Vector3(0.0, (block.scale.y * 0.5) + 1.1, 0.0)
			var pole_mat := StandardMaterial3D.new()
			pole_mat.albedo_color = Color(0.96, 0.96, 0.96)
			pole.mesh.surface_set_material(0, pole_mat)
			visuals.add_child(pole)

			var flag := MeshInstance3D.new()
			var flag_mesh := BoxMesh.new()
			flag_mesh.size = Vector3(0.9, 0.45, 0.08)
			flag.mesh = flag_mesh
			flag.position = Vector3(0.45, (block.scale.y * 0.5) + 1.65, 0.0)
			var block_material := block.get_active_material(0) as StandardMaterial3D
			var flag_color := block_material.albedo_color if block_material else Color(1.0, 0.82, 0.22)
			var flag_mat := StandardMaterial3D.new()
			flag_mat.albedo_color = flag_color.lightened(0.2)
			flag_mat.emission_enabled = true
			flag_mat.emission = flag_color
			flag_mat.emission_energy_multiplier = 0.55
			flag.mesh.surface_set_material(0, flag_mat)
			visuals.add_child(flag)
		"Teleport":
			var beam := MeshInstance3D.new()
			var beam_mesh := CylinderMesh.new()
			beam_mesh.top_radius = 0.35
			beam_mesh.bottom_radius = 0.6
			beam_mesh.height = 3.2
			beam.mesh = beam_mesh
			beam.position = Vector3(0.0, (block.scale.y * 0.5) + 1.6, 0.0)
			var block_material := block.get_active_material(0) as StandardMaterial3D
			var beam_color := block_material.albedo_color if block_material else Color(0.2, 0.75, 1.0)
			var beam_mat := StandardMaterial3D.new()
			beam_mat.albedo_color = Color(beam_color.r, beam_color.g, beam_color.b, 0.35)
			beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam_mat.emission_enabled = true
			beam_mat.emission = beam_color
			beam_mat.emission_energy_multiplier = 1.15
			beam.mesh.surface_set_material(0, beam_mat)
			visuals.add_child(beam)
func _update_block_collision(block: Node3D) -> void:
	if block == null or not is_instance_valid(block) or not (block is MeshInstance3D):
		return
	_rebuild_block_helpers(block as MeshInstance3D)

func _create_spawn_decal_node(block_scale: Vector3) -> Sprite3D:
	var decal := Sprite3D.new()
	decal.name = "SpawnDecal"
	decal.texture = _load_spawn_decal_texture()
	decal.position = Vector3(0.0, (block_scale.y * 0.5) + 0.26, 0.0)
	decal.axis = Vector3.AXIS_Y
	if block_scale.x > 0.0:
		decal.scale.x = 1.0 / block_scale.x
	if block_scale.z > 0.0:
		decal.scale.z = 1.0 / block_scale.z
	decal.pixel_size = 0.0035
	return decal

func _apply_collision_shape_size(collision_shape: CollisionShape3D, shape_name: String, _block_scale: Vector3) -> void:
	if collision_shape == null or collision_shape.shape == null:
		return
	var normalized_shape := shape_name
	if normalized_shape == "Spawn" or normalized_shape == "Checkpoint" or normalized_shape == "Teleport":
		normalized_shape = "Box"
	match normalized_shape:
		"Sphere":
			var sphere_shape := collision_shape.shape as SphereShape3D
			if sphere_shape:
				sphere_shape.radius = 0.5
		"Cylinder":
			var cylinder_shape := collision_shape.shape as CylinderShape3D
			if cylinder_shape:
				cylinder_shape.radius = 0.5
				cylinder_shape.height = 1.0
		_:
			var box_shape := collision_shape.shape as BoxShape3D
			if box_shape:
				box_shape.size = Vector3.ONE

# ===== SELECTION HIGHLIGHT =====
func _build_selection_overlay() -> void:
	selection_overlay_layer = CanvasLayer.new()
	selection_overlay_layer.name = "SelectionOverlay"
	selection_overlay_layer.layer = 8
	add_child(selection_overlay_layer)

	selection_box_rect = Panel.new()
	selection_box_rect.visible = false
	selection_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect_style := StyleBoxFlat.new()
	rect_style.bg_color = Color(0.18, 0.52, 0.95, 0.14)
	rect_style.border_color = Color(0.22, 0.62, 1.0, 0.9)
	rect_style.border_width_bottom = 2
	rect_style.border_width_left = 2
	rect_style.border_width_right = 2
	rect_style.border_width_top = 2
	selection_box_rect.add_theme_stylebox_override("panel", rect_style)
	selection_overlay_layer.add_child(selection_box_rect)

func _create_selection_highlight() -> void:
	selection_highlight_root = Node3D.new()
	selection_highlight_root.name = "SelectionHighlightRoot"
	add_child(selection_highlight_root)

	selection_highlight_material = StandardMaterial3D.new()
	selection_highlight_material.albedo_color = Color(0.22, 0.62, 1.0, 0.18)
	selection_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_highlight_material.cull_mode = BaseMaterial3D.CULL_FRONT
	selection_highlight_material.no_depth_test = true
	selection_highlight_material.emission_enabled = true
	selection_highlight_material.emission = Color(0.22, 0.62, 1.0, 1.0)
	selection_highlight_material.emission_energy_multiplier = 0.35

func _sync_selection_highlight_instances() -> void:
	if selection_highlight_root == null:
		return
	for child in selection_highlight_root.get_children():
		child.queue_free()

	for block in _get_valid_selected_blocks():
		var highlight := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		highlight.mesh = box
		highlight.material_override = selection_highlight_material
		highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		selection_highlight_root.add_child(highlight)

func _update_selection_highlight() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	if valid_blocks.size() != selected_blocks.size():
		selected_blocks = valid_blocks
		selected_block = selected_blocks[0] if not selected_blocks.is_empty() else null
		if selected_block == null:
			_clear_inspector()
		_sync_explorer_selection()
		_update_selection_status()

	if selection_highlight_root == null:
		return

	if valid_blocks.size() != selection_highlight_root.get_child_count():
		_sync_selection_highlight_instances()

	selection_highlight_root.visible = not valid_blocks.is_empty()
	for i in range(valid_blocks.size()):
		var highlight: MeshInstance3D = selection_highlight_root.get_child(i) as MeshInstance3D
		var block: Node3D = valid_blocks[i]
		highlight.global_position = block.global_position
		highlight.rotation = block.rotation
		highlight.scale = block.scale * 1.04

func _create_transform_gizmo() -> void:
	transform_gizmo_root = Node3D.new()
	transform_gizmo_root.name = "TransformGizmoRoot"
	add_child(transform_gizmo_root)

	var axis_colors := {
		"x": Color(0.97, 0.32, 0.32),
		"y": Color(0.25, 0.83, 0.42),
		"z": Color(0.28, 0.56, 1.0)
	}
	for mode in ["move", "scale", "rotate"]:
		for axis in ["x", "y", "z"]:
			transform_gizmo_root.add_child(_create_gizmo_handle(mode, axis, axis_colors[axis], 1))
			if mode == "scale":
				transform_gizmo_root.add_child(_create_gizmo_handle(mode, axis, axis_colors[axis], -1))
	transform_gizmo_root.visible = false

func _create_gizmo_handle(mode: String, axis: String, color: Color, direction_sign: int = 1) -> Node3D:
	var handle := Node3D.new()
	handle.name = "%s_%s_%s" % [mode, axis, "pos" if direction_sign >= 0 else "neg"]
	handle.set_meta("gizmo_mode", mode)
	handle.set_meta("gizmo_axis", axis)
	handle.set_meta("gizmo_sign", direction_sign)
	var axis_sign := 1.0 if direction_sign >= 0 else -1.0

	var visual_root := Node3D.new()
	visual_root.rotation_degrees = _get_axis_rotation_degrees(axis)
	handle.add_child(visual_root)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.045
	shaft_mesh.bottom_radius = 0.045
	shaft_mesh.height = 1.0
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.5 * axis_sign, 0.0)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = color
	shaft_mat.emission_enabled = true
	shaft_mat.emission = color
	shaft_mat.emission_energy_multiplier = 0.45
	shaft.mesh.surface_set_material(0, shaft_mat)
	visual_root.add_child(shaft)

	var tip := MeshInstance3D.new()
	if mode == "scale":
		var cube := BoxMesh.new()
		cube.size = Vector3(0.24, 0.24, 0.24)
		tip.mesh = cube
	elif mode == "rotate":
		var rotate_sphere := SphereMesh.new()
		rotate_sphere.radius = 0.18
		rotate_sphere.height = 0.36
		tip.mesh = rotate_sphere
	else:
		var move_sphere := SphereMesh.new()
		move_sphere.radius = 0.14
		move_sphere.height = 0.28
		tip.mesh = move_sphere
	tip.position = Vector3(0.0, 1.15 * axis_sign, 0.0)
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = color.lightened(0.12)
	tip_mat.emission_enabled = true
	tip_mat.emission = color
	tip_mat.emission_energy_multiplier = 0.8
	tip.mesh.surface_set_material(0, tip_mat)
	visual_root.add_child(tip)

	var pick_body := StaticBody3D.new()
	pick_body.name = "PickBody"
	pick_body.collision_layer = GIZMO_RAY_MASK
	pick_body.collision_mask = 0
	pick_body.input_ray_pickable = true
	pick_body.rotation_degrees = _get_axis_rotation_degrees(axis)
	handle.add_child(pick_body)

	var shaft_pick_shape := CollisionShape3D.new()
	var shaft_pick := CylinderShape3D.new()
	shaft_pick.radius = 0.18
	shaft_pick.height = 1.2
	shaft_pick_shape.shape = shaft_pick
	shaft_pick_shape.position = Vector3(0.0, 0.58 * axis_sign, 0.0)
	pick_body.add_child(shaft_pick_shape)

	var axis_pick_shape := CollisionShape3D.new()
	var axis_pick := BoxShape3D.new()
	axis_pick.size = Vector3(0.4, 1.4, 0.4)
	axis_pick_shape.shape = axis_pick
	axis_pick_shape.position = Vector3(0.0, 0.72 * axis_sign, 0.0)
	pick_body.add_child(axis_pick_shape)

	var pick_shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.34 if mode == "rotate" else 0.3
	pick_shape.shape = sphere_shape
	pick_shape.position = Vector3(0.0, 1.15 * axis_sign, 0.0)
	pick_body.add_child(pick_shape)

	return handle

func _update_transform_gizmo() -> void:
	if transform_gizmo_root == null:
		return

	var valid_blocks := _get_valid_selected_blocks()
	if current_shape != "Select" or valid_blocks.is_empty():
		transform_gizmo_root.visible = false
		return

	transform_gizmo_root.visible = true
	transform_gizmo_root.global_position = _get_selection_pivot()
	var distance_to_camera := camera.global_position.distance_to(transform_gizmo_root.global_position) if camera else 10.0
	var gizmo_scale := maxf(GIZMO_MIN_SCALE, distance_to_camera * GIZMO_SCALE_DISTANCE_FACTOR)
	transform_gizmo_root.scale = Vector3.ONE * gizmo_scale

	for child in transform_gizmo_root.get_children():
		if child is Node3D:
			var handle := child as Node3D
			var is_active_mode := str(handle.get_meta("gizmo_mode", "")) == current_transform_mode
			handle.visible = is_active_mode
			var pick_body := handle.get_node_or_null("PickBody") as StaticBody3D
			if pick_body:
				pick_body.input_ray_pickable = is_active_mode
				pick_body.collision_layer = GIZMO_RAY_MASK if is_active_mode else 0

func _begin_gizmo_drag(gizmo_handle: Node3D) -> void:
	active_gizmo_mode = str(gizmo_handle.get_meta("gizmo_mode", current_transform_mode))
	active_gizmo_axis = str(gizmo_handle.get_meta("gizmo_axis", "x"))
	active_gizmo_sign = -1 if int(gizmo_handle.get_meta("gizmo_sign", 1)) < 0 else 1
	gizmo_drag_axis_world = _get_axis_vector(active_gizmo_axis)
	if active_gizmo_mode == "scale":
		gizmo_drag_axis_world *= float(active_gizmo_sign)
	gizmo_drag_start_pivot = _get_selection_pivot()
	gizmo_drag_plane = _make_rotation_drag_plane(gizmo_drag_axis_world, gizmo_drag_start_pivot) if active_gizmo_mode == "rotate" else _make_axis_drag_plane(gizmo_drag_axis_world, gizmo_drag_start_pivot)
	gizmo_drag_start_mouse = get_viewport().get_mouse_position()

	if camera:
		var pivot_screen: Vector2 = camera.unproject_position(gizmo_drag_start_pivot)
		var axis_screen: Vector2 = camera.unproject_position(gizmo_drag_start_pivot + (gizmo_drag_axis_world * 2.0)) - pivot_screen
		if axis_screen.length_squared() > 0.0001:
			gizmo_drag_screen_axis = axis_screen.normalized()
		else:
			gizmo_drag_screen_axis = Vector2.RIGHT
		gizmo_drag_units_per_pixel = maxf(0.01, camera.global_position.distance_to(gizmo_drag_start_pivot) * 0.0025)
	else:
		gizmo_drag_screen_axis = Vector2.RIGHT
		gizmo_drag_units_per_pixel = 0.02

	var mouse_hit = _get_mouse_plane_intersection(get_viewport().get_mouse_position(), gizmo_drag_plane)
	gizmo_drag_start_hit = mouse_hit if mouse_hit != null else gizmo_drag_start_pivot
	gizmo_drag_start_vector = gizmo_drag_start_hit - gizmo_drag_start_pivot
	gizmo_drag_start_positions.clear()
	gizmo_drag_start_scales.clear()
	gizmo_drag_start_bases.clear()
	gizmo_drag_start_offsets.clear()

	for block in _get_valid_selected_blocks():
		var block_id: int = block.get_instance_id()
		gizmo_drag_start_positions[block_id] = block.global_position
		gizmo_drag_start_scales[block_id] = block.scale
		gizmo_drag_start_bases[block_id] = block.global_basis
		gizmo_drag_start_offsets[block_id] = block.global_position - gizmo_drag_start_pivot

	is_gizmo_dragging = true

func _update_gizmo_drag(mouse_position: Vector2) -> void:
	if not is_gizmo_dragging:
		return

	var mouse_hit = _get_mouse_plane_intersection(mouse_position, gizmo_drag_plane)
	var axis_delta: float = (mouse_position - gizmo_drag_start_mouse).dot(gizmo_drag_screen_axis) * gizmo_drag_units_per_pixel
	if mouse_hit != null:
		axis_delta = (mouse_hit - gizmo_drag_start_hit).dot(gizmo_drag_axis_world)
	if active_gizmo_mode == "rotate":
		if mouse_hit == null:
			return
	match active_gizmo_mode:
		"move":
			var snapped_delta: float = snappedf(axis_delta, MOVE_GRID_SNAP)
			for block in _get_valid_selected_blocks():
				var start_pos: Vector3 = gizmo_drag_start_positions.get(block.get_instance_id(), block.global_position)
				block.global_position = start_pos + (gizmo_drag_axis_world * snapped_delta)
		"scale":
			var scale_delta: float = axis_delta
			for block in _get_valid_selected_blocks():
				var block_id: int = block.get_instance_id()
				var start_pos: Vector3 = gizmo_drag_start_positions.get(block_id, block.global_position)
				var start_scale: Vector3 = gizmo_drag_start_scales.get(block_id, block.scale)
				var start_axis_scale: float = _get_axis_component(start_scale, active_gizmo_axis)
				var next_axis_scale: float = maxf(MIN_BLOCK_SCALE, snappedf(start_axis_scale + scale_delta, SCALE_GRID_SNAP))
				var applied_delta: float = next_axis_scale - start_axis_scale
				block.scale = _with_axis_component(start_scale, active_gizmo_axis, next_axis_scale)
				block.global_position = start_pos + (gizmo_drag_axis_world * (applied_delta * 0.5))
				_update_block_collision(block)
		"rotate":
			if mouse_hit == null:
				return
			var current_vector: Vector3 = mouse_hit - gizmo_drag_start_pivot
			if gizmo_drag_start_vector.length_squared() < 0.0001 or current_vector.length_squared() < 0.0001:
				return
			var snapped_angle: float = snappedf(
				_signed_angle_around_axis(gizmo_drag_start_vector.normalized(), current_vector.normalized(), gizmo_drag_axis_world),
				deg_to_rad(ROTATION_SNAP_DEGREES)
			)
			var rotation_basis: Basis = Basis(gizmo_drag_axis_world, snapped_angle)
			for block in _get_valid_selected_blocks():
				var block_id: int = block.get_instance_id()
				var start_offset: Vector3 = gizmo_drag_start_offsets.get(block_id, block.global_position - gizmo_drag_start_pivot)
				var start_basis: Basis = gizmo_drag_start_bases.get(block_id, block.global_basis)
				block.global_position = gizmo_drag_start_pivot + (rotation_basis * start_offset)
				block.global_basis = rotation_basis * start_basis

	_update_inspector()

func _end_gizmo_drag() -> void:
	if not is_gizmo_dragging:
		return
	is_gizmo_dragging = false
	for block in _get_valid_selected_blocks():
		_update_block_collision(block)
	_update_inspector()
	_commit_editor_history("Transform")

func _get_valid_selected_blocks() -> Array[Node3D]:
	var valid: Array[Node3D] = []
	for block in selected_blocks:
		if block is Node3D and is_instance_valid(block) and block.is_in_group("studio_parts"):
			valid.append(block)
	return valid

func _get_selection_pivot() -> Vector3:
	var valid_blocks := _get_valid_selected_blocks()
	if valid_blocks.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	for block in valid_blocks:
		center += _get_node_world_center(block)
	return center / float(valid_blocks.size())

func _get_axis_vector(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		_:
			return Vector3.BACK

func _get_axis_rotation_degrees(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3(0.0, 0.0, -90.0)
		"z":
			return Vector3(90.0, 0.0, 0.0)
		_:
			return Vector3.ZERO

func _get_axis_component(value: Vector3, axis: String) -> float:
	match axis:
		"x":
			return value.x
		"y":
			return value.y
		_:
			return value.z

func _with_axis_component(value: Vector3, axis: String, axis_value: float) -> Vector3:
	match axis:
		"x":
			value.x = axis_value
		"y":
			value.y = axis_value
		_:
			value.z = axis_value
	return value

func _get_mouse_plane_intersection(mouse_position: Vector2, plane: Plane):
	if camera == null:
		return null
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	return plane.intersects_ray(ray_origin, ray_direction)

func _make_axis_drag_plane(axis_world: Vector3, pivot: Vector3) -> Plane:
	var camera_forward := (-camera.global_basis.z).normalized() if camera else Vector3.FORWARD
	var plane_normal := axis_world.cross(camera_forward).cross(axis_world)
	if plane_normal.length_squared() < 0.0001:
		plane_normal = axis_world.cross(Vector3.UP)
	if plane_normal.length_squared() < 0.0001:
		plane_normal = axis_world.cross(Vector3.RIGHT)
	return Plane(plane_normal.normalized(), pivot)

func _make_rotation_drag_plane(axis_world: Vector3, pivot: Vector3) -> Plane:
	return Plane(axis_world.normalized(), pivot)

func _signed_angle_around_axis(from_vector: Vector3, to_vector: Vector3, axis: Vector3) -> float:
	var cross_vector := from_vector.cross(to_vector)
	return atan2(axis.dot(cross_vector), from_vector.dot(to_vector))

# ===== UI: TOOLBAR =====
func _build_toolbar() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "ToolbarLayer"
	ui_layer.layer = 6
	add_child(ui_layer)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = STUDIO_TOP_BAR_HEIGHT
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.11, 0.15, 0.97)
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.22, 0.28, 0.35, 1.0)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	panel_style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", panel_style)
	ui_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	root.add_child(top_row)

	var title := Label.new()
	title.text = "Studio"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	top_row.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Select, scale, rotate, and wire special blocks"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.74, 0.82, 1.0))
	top_row.add_child(subtitle)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_spacer)

	var save_btn := _create_toolbar_button("Save", 72, Color(0.18, 0.53, 0.82))
	save_btn.pressed.connect(_on_save_button_pressed)
	top_row.add_child(save_btn)

	var publish_btn := _create_toolbar_button("Publish", 88, Color(0.13, 0.62, 0.39))
	publish_btn.pressed.connect(_on_publish_pressed)
	top_row.add_child(publish_btn)

	var rbxl_btn := _create_toolbar_button("Import RBXL", 104, Color(0.49, 0.34, 0.74))
	rbxl_btn.pressed.connect(_on_import_rbxl_pressed)
	top_row.add_child(rbxl_btn)

	var back_btn := _create_toolbar_button("Back", 72, Color(0.67, 0.24, 0.24))
	back_btn.pressed.connect(_on_back_pressed)
	top_row.add_child(back_btn)

	var toolbar_scroll := ScrollContainer.new()
	toolbar_scroll.custom_minimum_size = Vector2(0, 40)
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(toolbar_scroll)

	toolbar_hbox = HBoxContainer.new()
	toolbar_hbox.add_theme_constant_override("separation", 6)
	toolbar_hbox.custom_minimum_size = Vector2(1180, 0)
	toolbar_scroll.add_child(toolbar_hbox)

	toolbar_status_label = Label.new()
	toolbar_status_label.text = "No selection | Move"
	toolbar_status_label.custom_minimum_size = Vector2(170, 0)
	toolbar_status_label.add_theme_font_size_override("font_size", 11)
	toolbar_status_label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.9))
	toolbar_hbox.add_child(toolbar_status_label)

	var shape_label := Label.new()
	shape_label.text = "Create"
	shape_label.add_theme_font_size_override("font_size", 11)
	shape_label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.9, 1.0))
	toolbar_hbox.add_child(shape_label)

	for shape_name in SHAPE_OPTIONS:
		var button_width := 64.0
		if shape_name == "Checkpoint" or shape_name == "Teleport":
			button_width = 88.0
		elif shape_name == "Cylinder":
			button_width = 76.0
		elif shape_name == "Sphere" or shape_name == "Select":
			button_width = 68.0
		var shape_button := _create_toolbar_button(shape_name, button_width, Color(0.24, 0.36, 0.55), true)
		shape_button.pressed.connect(_set_shape.bind(shape_name))
		toolbar_hbox.add_child(shape_button)
		shape_buttons[shape_name] = shape_button

	var toolbox_btn := _create_toolbar_button("Toolbox", 82, Color(0.75, 0.44, 0.12))
	toolbox_btn.pressed.connect(_open_toolbox_dialog)
	toolbar_hbox.add_child(toolbox_btn)

	var transform_label := Label.new()
	transform_label.text = "Transform"
	transform_label.add_theme_font_size_override("font_size", 11)
	transform_label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.9, 1.0))
	toolbar_hbox.add_child(transform_label)

	for pair in [["move", "Move"], ["scale", "Scale"], ["rotate", "Rotate"]]:
		var transform_button := _create_toolbar_button(pair[1], 62, Color(0.29, 0.46, 0.32), true)
		transform_button.pressed.connect(_set_transform_mode.bind(pair[0]))
		toolbar_hbox.add_child(transform_button)
		transform_mode_buttons[pair[0]] = transform_button

	var edit_label := Label.new()
	edit_label.text = "Edit"
	edit_label.add_theme_font_size_override("font_size", 11)
	edit_label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.9, 1.0))
	toolbar_hbox.add_child(edit_label)

	var undo_btn := _create_toolbar_button("Undo", 62, Color(0.48, 0.37, 0.28))
	undo_btn.pressed.connect(_undo_editor_action)
	toolbar_hbox.add_child(undo_btn)

	var redo_btn := _create_toolbar_button("Redo", 62, Color(0.48, 0.37, 0.28))
	redo_btn.pressed.connect(_redo_editor_action)
	toolbar_hbox.add_child(redo_btn)

	var copy_btn := _create_toolbar_button("Copy", 62, Color(0.42, 0.37, 0.64))
	copy_btn.pressed.connect(_copy_selected_blocks)
	toolbar_hbox.add_child(copy_btn)

	var paste_btn := _create_toolbar_button("Paste", 64, Color(0.42, 0.37, 0.64))
	paste_btn.pressed.connect(_paste_clipboard_blocks)
	toolbar_hbox.add_child(paste_btn)

	var duplicate_btn := _create_toolbar_button("Duplicate", 88, Color(0.42, 0.37, 0.64))
	duplicate_btn.pressed.connect(_duplicate_selected_blocks)
	toolbar_hbox.add_child(duplicate_btn)

	var select_all_btn := _create_toolbar_button("Select All", 82, Color(0.33, 0.42, 0.58))
	select_all_btn.pressed.connect(_select_all_blocks)
	toolbar_hbox.add_child(select_all_btn)

	var clear_btn := _create_toolbar_button("Clear", 62, Color(0.33, 0.42, 0.58))
	clear_btn.pressed.connect(_clear_selection)
	toolbar_hbox.add_child(clear_btn)

	var focus_btn := _create_toolbar_button("Focus", 62, Color(0.33, 0.42, 0.58))
	focus_btn.pressed.connect(_focus_camera_on_selection)
	toolbar_hbox.add_child(focus_btn)

	color_picker = ColorPickerButton.new()
	color_picker.custom_minimum_size = Vector2(56, 32)
	color_picker.color = current_color
	color_picker.color_changed.connect(_on_color_changed)
	toolbar_hbox.add_child(color_picker)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_hbox.add_child(spacer)

	var hints := Label.new()
	hints.text = "RMB orbit | Ctrl+A all | F focus | Esc clear | G/T/R gizmo | Y +90"
	hints.add_theme_font_size_override("font_size", 10)
	hints.add_theme_color_override("font_color", Color(0.74, 0.82, 0.9, 0.85))
	toolbar_hbox.add_child(hints)

	_refresh_toolbar_states()

func _create_toolbar_button(text: String, width: float, accent_color: Color, toggle_mode := false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle_mode
	button.custom_minimum_size = Vector2(width, 32)
	button.set_meta("accent_color", accent_color)
	_style_toolbar_button(button, false)
	return button

func _setup_rbxl_import_dialog() -> void:
	if rbxl_file_dialog != null and is_instance_valid(rbxl_file_dialog):
		return
	rbxl_file_dialog = FileDialog.new()
	rbxl_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	rbxl_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	rbxl_file_dialog.filters = PackedStringArray(["*.rbxl, *.rbxlx ; Roblox Place Files"])
	rbxl_file_dialog.use_native_dialog = true
	rbxl_file_dialog.title = "Import Roblox Place"
	rbxl_file_dialog.file_selected.connect(_on_rbxl_file_selected)
	add_child(rbxl_file_dialog)

func _on_import_rbxl_pressed() -> void:
	_setup_rbxl_import_dialog()
	if rbxl_file_dialog:
		rbxl_file_dialog.popup_centered(Vector2(760, 460))

func _on_rbxl_file_selected(path: String) -> void:
	var clean_path := path.strip_edges()
	if clean_path.is_empty():
		return
	if toolbar_status_label:
		toolbar_status_label.text = "Importing RBXL..."
	if _should_replace_map_for_rbxl_import():
		_clear_map_for_rbxl_import()
		await get_tree().process_frame
	var importer := RbxlRuntimeImporter.new()
	importer.scale_factor = 0.5
	importer.import_lighting = true
	importer.replace_existing = false
	importer.import_progress.connect(func(done: int, total: int, message: String) -> void:
		if toolbar_status_label:
			toolbar_status_label.text = "Importing %s (%d/%d)" % [message, done, maxi(total, 1)]
	)
	var report: Dictionary = importer.import_file(clean_path, self)
	if bool(report.get("ok", false)):
		custom_icon_set = false
		if toolbar_status_label:
			var warning_count: int = report.get("warnings", []).size() if report.get("warnings", []) is Array else 0
			var warning_suffix := " with %d warning(s)" % warning_count if warning_count > 0 else ""
			toolbar_status_label.text = "Imported RBXL: %d part(s), %d object(s), %d sound(s)%s" % [
				int(report.get("parts", 0)),
				int(report.get("runtime_objects", 0)),
				int(report.get("sounds", 0)),
				warning_suffix
			]
	else:
		if toolbar_status_label:
			toolbar_status_label.text = "RBXL import failed: %s" % str(report.get("error", "Unknown error"))

func _should_replace_map_for_rbxl_import() -> bool:
	var parts := _get_editor_parts()
	if parts.is_empty():
		return true
	if parts.size() != 1:
		return false
	var only_part: Node3D = parts[0]
	var block_name := str(only_part.get_meta("block_name", only_part.name))
	var shape_name := str(only_part.get_meta("shape_type", "Box"))
	return block_name == "Baseplate" and shape_name == "Box" and only_part.scale.distance_to(Vector3(40.0, 1.0, 40.0)) < 0.05

func _clear_map_for_rbxl_import() -> void:
	for block in _get_editor_parts():
		if is_instance_valid(block):
			block.queue_free()
	_clear_runtime_object_nodes()
	current_music_source_paths.clear()
	current_imported_sound_assets.clear()
	_refresh_music_source_ui()

func _clear_runtime_object_nodes() -> void:
	var parent: Node = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child.is_in_group(RBXL_RUNTIME_OBJECT_GROUP):
			child.queue_free()

func _register_imported_sound_asset(sound_data: Dictionary) -> void:
	var stored := sound_data.duplicate(true)
	var sound_id := str(stored.get("sound_id", "")).strip_edges()
	var known := false
	for existing in current_imported_sound_assets:
		if str(existing.get("sound_id", "")).strip_edges() == sound_id and not sound_id.is_empty():
			known = true
			break
	if not known:
		current_imported_sound_assets.append(stored)
	var resolved_path := str(stored.get("resolved_path", "")).strip_edges()
	if bool(stored.get("as_music", false)) and not resolved_path.is_empty() and FileAccess.file_exists(resolved_path):
		if not current_music_source_paths.has(resolved_path):
			current_music_source_paths.append(resolved_path)
	_refresh_music_source_ui()

func _refresh_music_source_ui() -> void:
	if atmosphere_music_path_edit:
		if current_music_source_paths.is_empty():
			atmosphere_music_path_edit.text = ""
		elif current_music_source_paths.size() == 1:
			atmosphere_music_path_edit.text = current_music_source_paths[0].get_file()
		else:
			atmosphere_music_path_edit.text = "%d tracks, %.1f MB" % [
				current_music_source_paths.size(),
				float(_get_playlist_total_size_bytes(current_music_source_paths)) / 1048576.0
			]
		atmosphere_music_path_edit.placeholder_text = "No music selected"
	_rebuild_music_track_list()

func _open_toolbox_dialog() -> void:
	if toolbox_dialog != null and is_instance_valid(toolbox_dialog):
		toolbox_dialog.queue_free()
	toolbox_dialog = AcceptDialog.new()
	toolbox_dialog.title = "Toolbox"
	toolbox_dialog.ok_button_text = "Close"
	add_child(toolbox_dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 420)
	root.add_theme_constant_override("separation", 10)
	toolbox_dialog.add_child(root)
	var intro := Label.new()
	intro.text = "Reusable models from your drafts and Bobux Cloud marketplace."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var entries: Array[Dictionary] = []
	for draft_entry in _load_local_model_draft_entries():
		entries.append(draft_entry)
	if CloudAPI != null and CloudAPI.is_configured():
		var cloud_response: Dictionary = await CloudAPI.fetch_marketplace_models(96, true, false)
		if bool(cloud_response.get("ok", false)):
			for cloud_variant in _extract_toolbox_response_array(cloud_response):
				if not (cloud_variant is Dictionary):
					continue
				var cloud_entry: Dictionary = cloud_variant
				cloud_entry["publish_state"] = "cloud"
				entries.append(cloud_entry)
		elif toolbar_status_label:
			toolbar_status_label.text = "Toolbox cloud load failed: %s" % str(cloud_response.get("error", "Unknown error"))
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No model drafts or marketplace models yet."
		list.add_child(empty)
	for entry in entries:
		list.add_child(_create_toolbox_model_row(entry))
	toolbox_dialog.popup_centered(Vector2i(620, 500))

func _create_toolbox_model_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 44)
	var title := Label.new()
	title.text = str(entry.get("name", entry.get("draft_id", "Model Draft"))).strip_edges()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var insert_btn := Button.new()
	insert_btn.text = "Insert"
	insert_btn.custom_minimum_size = Vector2(96, 34)
	insert_btn.pressed.connect(func() -> void:
		_insert_model_draft_into_place(entry)
		if toolbox_dialog != null:
			toolbox_dialog.hide()
	)
	row.add_child(insert_btn)
	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size = Vector2(86, 34)
	details_btn.pressed.connect(func() -> void:
		_show_toolbox_model_details(entry)
	)
	row.add_child(details_btn)
	var get_btn := Button.new()
	get_btn.text = "Get"
	get_btn.custom_minimum_size = Vector2(68, 34)
	get_btn.disabled = str(entry.get("id", "")).strip_edges().is_empty()
	get_btn.pressed.connect(func() -> void:
		get_btn.disabled = true
		var result: Dictionary = await CloudAPI.get_catalog_item(str(entry.get("id", "")).strip_edges(), "model")
		get_btn.text = "Owned" if bool(result.get("ok", false)) else "Retry"
		get_btn.disabled = bool(result.get("ok", false))
	)
	row.add_child(get_btn)
	var like_btn := Button.new()
	like_btn.text = "Like"
	like_btn.custom_minimum_size = Vector2(68, 34)
	like_btn.disabled = str(entry.get("id", "")).strip_edges().is_empty()
	like_btn.pressed.connect(func() -> void:
		like_btn.disabled = true
		var result: Dictionary = await CloudAPI.like_catalog_asset("model", str(entry.get("id", "")).strip_edges())
		like_btn.text = "Liked" if bool(result.get("ok", false)) else "Retry"
		like_btn.disabled = bool(result.get("ok", false))
	)
	row.add_child(like_btn)
	return row

func _show_toolbox_model_details(entry: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = str(entry.get("name", "Model Details")).strip_edges()
	dialog.ok_button_text = "Close"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(440, 260)
	root.add_theme_constant_override("separation", 8)
	dialog.add_child(root)
	var name_label := Label.new()
	name_label.text = str(entry.get("name", "Untitled Model")).strip_edges()
	name_label.add_theme_font_size_override("font_size", 22)
	root.add_child(name_label)
	var author := Label.new()
	author.text = "By %s" % str(entry.get("owner_name", "Unknown")).strip_edges()
	author.add_theme_color_override("font_color", Color(0.25, 0.55, 0.85))
	root.add_child(author)
	var description := Label.new()
	description.text = str(entry.get("description", "No description yet.")).strip_edges()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(description)
	var stats := Label.new()
	stats.text = "%s · %d like(s) · %d use(s)" % [
		str(entry.get("visibility", "public")).capitalize(),
		int(entry.get("likes_count", 0)),
		int(entry.get("uses_count", 0))
	]
	stats.add_theme_color_override("font_color", Color(0.58, 0.58, 0.58))
	root.add_child(stats)
	dialog.popup_centered(Vector2i(500, 320))

func _insert_model_draft_into_place(entry: Dictionary) -> void:
	var source_entry: Dictionary = _toolbox_model_data_from_entry(entry)
	var parts: Array = _toolbox_extract_parts_from_model_data(source_entry)
	if parts.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "This model has no placeable parts. Re-publish it with the updated Model Editor."
		return
	var parent_node: Node3D = placement_parent if placement_parent else self
	var inserted_blocks: Array[Node3D] = []
	var paste_offset := Vector3(0.0, 2.0, 0.0)
	for part_variant in parts:
		if not (part_variant is Dictionary):
			continue
		var block_data := _model_part_to_studio_block(part_variant as Dictionary)
		var block := _create_block_from_clipboard(block_data, paste_offset)
		if block == null:
			continue
		block.set_meta("toolbox_model_draft", str(entry.get("draft_id", entry.get("id", ""))))
		parent_node.add_child(block)
		inserted_blocks.append(block)
	if inserted_blocks.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Could not insert this model draft."
		return
	_set_selection(inserted_blocks)
	_commit_editor_history("Insert model draft")
	if toolbar_status_label:
		toolbar_status_label.text = "Inserted model: %s" % str(entry.get("name", entry.get("draft_id", "Model")))

func _toolbox_model_data_from_entry(entry: Dictionary) -> Dictionary:
	var candidates: Array = [entry]
	for key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
		if entry.has(key):
			candidates.append(entry.get(key))
	for candidate in candidates:
		var candidate_dict := _toolbox_dictionary_from_jsonish_variant(candidate)
		if candidate_dict.is_empty():
			continue
		if not _toolbox_extract_parts_from_model_data(candidate_dict).is_empty():
			return candidate_dict
		for nested_key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
			if not candidate_dict.has(nested_key):
				continue
			var nested_dict := _toolbox_dictionary_from_jsonish_variant(candidate_dict.get(nested_key))
			if not _toolbox_extract_parts_from_model_data(nested_dict).is_empty():
				return nested_dict
	return {}

func _toolbox_extract_parts_from_model_data(model_data: Dictionary) -> Array:
	for key in ["parts", "model_parts", "serialized_parts", "blocks", "objects", "nodes", "children"]:
		var candidate: Variant = model_data.get(key, [])
		if candidate is Array:
			var result: Array = []
			var candidate_array := candidate as Array
			for part_variant in candidate_array:
				if part_variant is Dictionary:
					result.append(part_variant)
				elif part_variant is String:
					var parsed_part := _toolbox_dictionary_from_jsonish_variant(part_variant)
					if not parsed_part.is_empty():
						result.append(parsed_part)
			if not result.is_empty():
				return result
	for nested_key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
		if not model_data.has(nested_key):
			continue
		var nested_dict := _toolbox_dictionary_from_jsonish_variant(model_data.get(nested_key))
		if nested_dict.is_empty():
			continue
		var nested_parts := _toolbox_extract_parts_from_model_data(nested_dict)
		if not nested_parts.is_empty():
			return nested_parts
	return []

func _toolbox_dictionary_from_jsonish_variant(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is String:
		var clean := (value as String).strip_edges()
		if clean.is_empty():
			return {}
		var parsed: Variant = JSON.parse_string(clean)
		if parsed is Dictionary:
			return parsed as Dictionary
	return {}

func _create_toolbox_model_placeholder_part(entry: Dictionary, source_entry: Dictionary) -> Dictionary:
	var display_name := str(entry.get("name", source_entry.get("name", entry.get("draft_id", "Imported Model")))).strip_edges()
	if display_name.is_empty():
		display_name = "Imported Model"
	return {
		"name": display_name,
		"kind": "ImportedPlaceholder",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [3.0, 2.0, 3.0],
		"color": "ffb347",
		"anchored": true,
		"can_collide": true
	}

func _extract_toolbox_response_array(response: Dictionary) -> Array:
	var data: Variant = response.get("data", [])
	if data is Array:
		return data
	if data is Dictionary:
		for key in ["models", "items", "data"]:
			var nested: Variant = (data as Dictionary).get(key, [])
			if nested is Array:
				return nested
	return []

func _model_part_to_studio_block(model_part: Dictionary) -> Dictionary:
	var kind: String = str(model_part.get("kind", model_part.get("shape", "Block"))).strip_edges()
	var clean_kind := kind.to_lower()
	var shape: String = "Box"
	if clean_kind == "sphere" or clean_kind == "ball":
		shape = "Sphere"
	elif clean_kind == "cylinder" or clean_kind == "tube":
		shape = "Cylinder"
	elif clean_kind == "ramp" or clean_kind == "wedge" or clean_kind == "prism":
		shape = "Wedge"
	return {
		"name": str(model_part.get("name", kind)).strip_edges(),
		"shape": shape,
		"position": _vector3_from_variant(model_part.get("position", Vector3.ZERO), Vector3.ZERO),
		"rotation_degrees": _vector3_from_variant(model_part.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO),
		"scale": _vector3_from_variant(model_part.get("scale", Vector3.ONE), Vector3.ONE),
		"color": Color.html(str(model_part.get("color", "ffffff"))),
		"material": "Plastic",
		"transparency": 0.0,
		"can_collide": bool(model_part.get("can_collide", true)),
		"deals_damage": false,
		"damage_amount": DEFAULT_BLOCK_DAMAGE,
		"is_spawn": false
	}

func _load_local_model_draft_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var draft_root: String = _get_model_drafts_root_path()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(draft_root)):
		return result
	var dir := DirAccess.open(draft_root)
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or file_name.get_extension().to_lower() != "json":
			continue
		var path := draft_root.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			var entry := parsed as Dictionary
			entry["draft_path"] = path
			result.append(entry)
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("created_at", "")) > str(b.get("created_at", ""))
	)
	return result

func _get_model_drafts_root_path() -> String:
	var owner_key: String = UserSession.user_id.strip_edges().replace("-", "") if UserSession != null else ""
	if owner_key.is_empty() and UserSession != null:
		owner_key = UserSession.username.strip_edges().to_lower().replace(" ", "_")
	if owner_key.is_empty():
		owner_key = "guest"
	return "user://studio_drafts/models".path_join(owner_key)

func _style_toolbar_button(button: Button, active: bool) -> void:
	var accent: Color = button.get_meta("accent_color", Color(0.25, 0.38, 0.55))
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent if active else Color(accent.r * 0.42, accent.g * 0.42, accent.b * 0.42, 0.85)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var hover := normal.duplicate()
	hover.bg_color = accent.lightened(0.12)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	button.add_theme_font_size_override("font_size", 11)
	button.button_pressed = active if button.toggle_mode else false

func _refresh_toolbar_states() -> void:
	for shape_name in shape_buttons.keys():
		_style_toolbar_button(shape_buttons[shape_name], shape_name == current_shape)
	for mode_name in transform_mode_buttons.keys():
		_style_toolbar_button(transform_mode_buttons[mode_name], mode_name == current_transform_mode)

func _set_shape(shape_name: String) -> void:
	current_shape = shape_name
	if current_shape != "Select":
		is_box_selecting = false
		_clear_selection_box_visual()
		if is_gizmo_dragging:
			_end_gizmo_drag()
	_refresh_toolbar_states()
	_update_transform_gizmo()
	_update_selection_status()

func _set_transform_mode(mode_name: String) -> void:
	current_transform_mode = mode_name
	_refresh_toolbar_states()
	_update_transform_gizmo()
	_update_selection_status()

# ===== UI: EXPLORER (Left Panel) =====
func _build_explorer_panel() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "ExplorerLayer"
	ui_layer.layer = 4
	add_child(ui_layer)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top = STUDIO_TOP_BAR_HEIGHT
	panel.offset_right = 240
	panel.anchor_right = 0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1)
	panel_style.border_width_right = 1
	panel_style.border_color = Color(0.82, 0.82, 0.82, 1)
	panel.add_theme_stylebox_override("panel", panel_style)
	ui_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Explorer"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	explorer_tree = Tree.new()
	explorer_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	explorer_tree.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1))
	explorer_tree.add_theme_font_size_override("font_size", 12)
	explorer_tree.item_selected.connect(_on_explorer_item_selected)
	vbox.add_child(explorer_tree)

	_refresh_explorer()

func _refresh_explorer() -> void:
	if explorer_tree == null:
		return
	explorer_tree.clear()
	var root := explorer_tree.create_item()
	root.set_text(0, "Workspace")

	var parent = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child.is_in_group("studio_parts") and not child.is_queued_for_deletion():
			var item := explorer_tree.create_item(root)
			var block_name: String = child.get_meta("block_name", child.name)
			item.set_text(0, block_name)
			item.set_metadata(0, child.get_instance_id())
	_sync_explorer_selection()

func _highlight_in_explorer(_block: Node3D) -> void:
	_sync_explorer_selection()

func _sync_explorer_selection() -> void:
	if explorer_tree == null:
		return
	var root := explorer_tree.get_root()
	if root == null:
		return

	var selected_ids: Dictionary = {}
	for block in _get_valid_selected_blocks():
		selected_ids[block.get_instance_id()] = true

	var selected_count := selected_ids.size()
	root.set_text(0, "Workspace" if selected_count <= 0 else "Workspace (%d selected)" % selected_count)

	var child_item := root.get_first_child()
	while child_item:
		var instance_id_variant = child_item.get_metadata(0)
		var instance_id: int = int(instance_id_variant) if instance_id_variant != null else -1
		var block_node := instance_from_id(instance_id)
		var block_name := child_item.get_text(0).trim_prefix("[Selected] ")
		if block_node and block_node is Node3D:
			block_name = str(block_node.get_meta("block_name", block_node.name))
		if selected_ids.has(instance_id):
			child_item.set_text(0, "[Selected] " + block_name)
		else:
			child_item.set_text(0, block_name)
		child_item = child_item.get_next()

func _on_explorer_item_selected() -> void:
	var selected = explorer_tree.get_selected()
	if selected == null:
		return
	var instance_id = selected.get_metadata(0)
	if instance_id == null:
		return
	var node = instance_from_id(instance_id)
	if node and node.is_in_group("studio_parts"):
		_select_block(node)

# ===== UI: INSPECTOR (Right Panel) =====
func _build_inspector_panel() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "InspectorLayer"
	ui_layer.layer = 4
	add_child(ui_layer)

	var panel := Panel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -280
	panel.offset_top = STUDIO_TOP_BAR_HEIGHT
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.clip_contents = true
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1)
	panel_style.border_width_left = 1
	panel_style.border_color = Color(0.82, 0.82, 0.82, 1)
	panel.add_theme_stylebox_override("panel", panel_style)
	ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	var inspector_root := VBoxContainer.new()
	inspector_root.add_theme_constant_override("separation", 10)
	margin.add_child(inspector_root)

	var title := Label.new()
	title.text = "Properties"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	inspector_root.add_child(title)

	inspector_summary_label = Label.new()
	inspector_summary_label.text = "Select a block to edit its properties."
	inspector_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_summary_label.add_theme_font_size_override("font_size", 11)
	inspector_summary_label.add_theme_color_override("font_color", Color(0.38, 0.42, 0.47, 1))
	inspector_root.add_child(inspector_summary_label)

	var sep := HSeparator.new()
	inspector_root.add_child(sep)

	var inspector_tabs := TabContainer.new()
	inspector_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_root.add_child(inspector_tabs)

	inspector_panel = VBoxContainer.new()
	inspector_panel.name = "Block"
	inspector_panel.add_theme_constant_override("separation", 10)
	inspector_tabs.add_child(inspector_panel)

	player_settings_panel = VBoxContainer.new()
	player_settings_panel.name = "Player"
	player_settings_panel.add_theme_constant_override("separation", 10)
	inspector_tabs.add_child(player_settings_panel)

	atmosphere_settings_panel = VBoxContainer.new()
	atmosphere_settings_panel.name = "Atmosphere"
	atmosphere_settings_panel.add_theme_constant_override("separation", 10)
	inspector_tabs.add_child(atmosphere_settings_panel)

	# Name
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(name_label)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Block name..."
	name_edit.add_theme_font_size_override("font_size", 13)
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = Color(0.18, 0.18, 0.22, 1)
	name_style.corner_radius_top_left = 4
	name_style.corner_radius_top_right = 4
	name_style.corner_radius_bottom_right = 4
	name_style.corner_radius_bottom_left = 4
	name_edit.add_theme_stylebox_override("normal", name_style)
	name_edit.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	name_edit.text_changed.connect(_on_name_changed)
	inspector_panel.add_child(name_edit)

	# Transparency
	var trans_label := Label.new()
	trans_label.text = "Transparency"
	trans_label.add_theme_font_size_override("font_size", 12)
	trans_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(trans_label)

	transparency_slider = HSlider.new()
	transparency_slider.min_value = 0.0
	transparency_slider.max_value = 1.0
	transparency_slider.step = 0.05
	transparency_slider.custom_minimum_size = Vector2(0, 20)
	transparency_slider.value_changed.connect(_on_transparency_changed)
	inspector_panel.add_child(transparency_slider)

	# CanCollide
	can_collide_check = CheckBox.new()
	can_collide_check.text = "CanCollide"
	can_collide_check.button_pressed = true
	can_collide_check.add_theme_font_size_override("font_size", 12)
	can_collide_check.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	can_collide_check.toggled.connect(_on_can_collide_toggled)
	inspector_panel.add_child(can_collide_check)

	damage_enabled_check = CheckBox.new()
	damage_enabled_check.text = "Deals Damage"
	damage_enabled_check.button_pressed = false
	damage_enabled_check.add_theme_font_size_override("font_size", 12)
	damage_enabled_check.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	damage_enabled_check.toggled.connect(_on_damage_enabled_toggled)
	inspector_panel.add_child(damage_enabled_check)

	var damage_label := Label.new()
	damage_label.text = "Damage Amount"
	damage_label.add_theme_font_size_override("font_size", 12)
	damage_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(damage_label)

	damage_amount_spin = SpinBox.new()
	damage_amount_spin.min_value = 1.0
	damage_amount_spin.max_value = 100.0
	damage_amount_spin.step = 1.0
	damage_amount_spin.value = DEFAULT_BLOCK_DAMAGE
	damage_amount_spin.custom_minimum_size = Vector2(0, 28)
	damage_amount_spin.prefix = "Damage: "
	damage_amount_spin.value_changed.connect(_on_damage_amount_changed)
	inspector_panel.add_child(damage_amount_spin)

	# Material
	var mat_label := Label.new()
	mat_label.text = "Material"
	mat_label.add_theme_font_size_override("font_size", 12)
	mat_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(mat_label)

	material_option = OptionButton.new()
	material_option.add_item("Plastic", 0)
	material_option.add_item("Neon", 1)
	material_option.add_item("Glass", 2)
	material_option.add_item("Metal", 3)
	material_option.add_theme_font_size_override("font_size", 12)
	material_option.item_selected.connect(_on_material_changed)
	inspector_panel.add_child(material_option)

	# Block Color
	var block_color_label := Label.new()
	block_color_label.text = "Block Color"
	block_color_label.add_theme_font_size_override("font_size", 12)
	block_color_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(block_color_label)

	var block_color_picker := ColorPickerButton.new()
	block_color_picker.custom_minimum_size = Vector2(0, 32)
	block_color_picker.color = Color.WHITE
	block_color_picker.color_changed.connect(_on_block_color_changed)
	block_color_picker.name = "BlockColorPicker"
	inspector_panel.add_child(block_color_picker)

	# Position
	var pos_label := Label.new()
	pos_label.text = "Position (X, Y, Z)"
	pos_label.name = "PositionLabel"
	pos_label.add_theme_font_size_override("font_size", 12)
	pos_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(pos_label)

	var pos_hbox := HBoxContainer.new()
	pos_hbox.name = "PositionHBox"
	inspector_panel.add_child(pos_hbox)
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.name = axis
		spin.min_value = -10000
		spin.max_value = 10000
		spin.step = 0.5
		spin.custom_minimum_size = Vector2(50, 28)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.add_theme_font_size_override("font_size", 11)
		spin.prefix = axis + ":"
		spin.value_changed.connect(_on_transform_entered)
		pos_hbox.add_child(spin)

	# Scale
	var scale_label := Label.new()
	scale_label.text = "Scale (X, Y, Z)"
	scale_label.name = "ScaleLabel"
	scale_label.add_theme_font_size_override("font_size", 12)
	scale_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(scale_label)

	var scale_hbox := HBoxContainer.new()
	scale_hbox.name = "ScaleHBox"
	inspector_panel.add_child(scale_hbox)
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.name = axis
		spin.min_value = 0.1
		spin.max_value = 10000
		spin.step = 0.5
		spin.value = 1.0
		spin.custom_minimum_size = Vector2(50, 28)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.add_theme_font_size_override("font_size", 11)
		spin.prefix = axis + ":"
		spin.value_changed.connect(_on_transform_entered)
		scale_hbox.add_child(spin)

	var delete_btn := Button.new()
	delete_btn.name = "DeleteButton"
	delete_btn.text = "Delete Selected"
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	delete_btn.pressed.connect(_delete_selected_blocks)
	inspector_panel.add_child(delete_btn)

	# Time of Day
	var sep2 := HSeparator.new()
	inspector_panel.add_child(sep2)

	var time_label := Label.new()
	time_label.text = "Time of Day"
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	inspector_panel.add_child(time_label)

	time_slider = HSlider.new()
	time_slider.min_value = 0.0
	time_slider.max_value = 24.0
	time_slider.value = 12.0
	time_slider.step = 0.5
	time_slider.custom_minimum_size = Vector2(0, 20)
	time_slider.value_changed.connect(_on_time_changed)
	inspector_panel.add_child(time_slider)

	var player_summary := Label.new()
	player_summary.text = "These settings affect only the current map."
	player_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_summary.add_theme_font_size_override("font_size", 11)
	player_summary.add_theme_color_override("font_color", Color(0.38, 0.42, 0.47, 1))
	player_settings_panel.add_child(player_summary)

	var move_speed_label := Label.new()
	move_speed_label.text = "Walk Speed"
	move_speed_label.add_theme_font_size_override("font_size", 12)
	move_speed_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	player_settings_panel.add_child(move_speed_label)

	player_move_speed_spin = SpinBox.new()
	player_move_speed_spin.min_value = 4.0
	player_move_speed_spin.max_value = 80.0
	player_move_speed_spin.step = 0.5
	player_move_speed_spin.custom_minimum_size = Vector2(0, 28)
	player_move_speed_spin.prefix = "Speed: "
	player_move_speed_spin.value_changed.connect(_on_player_settings_changed)
	player_settings_panel.add_child(player_move_speed_spin)

	var sprint_label := Label.new()
	sprint_label.text = "Sprint Multiplier"
	sprint_label.add_theme_font_size_override("font_size", 12)
	sprint_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	player_settings_panel.add_child(sprint_label)

	player_sprint_multiplier_spin = SpinBox.new()
	player_sprint_multiplier_spin.min_value = 1.0
	player_sprint_multiplier_spin.max_value = 3.0
	player_sprint_multiplier_spin.step = 0.05
	player_sprint_multiplier_spin.custom_minimum_size = Vector2(0, 28)
	player_sprint_multiplier_spin.prefix = "Sprint: "
	player_sprint_multiplier_spin.value_changed.connect(_on_player_settings_changed)
	player_settings_panel.add_child(player_sprint_multiplier_spin)

	var jump_label := Label.new()
	jump_label.text = "Jump Power"
	jump_label.add_theme_font_size_override("font_size", 12)
	jump_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	player_settings_panel.add_child(jump_label)

	player_jump_velocity_spin = SpinBox.new()
	player_jump_velocity_spin.min_value = 6.0
	player_jump_velocity_spin.max_value = 60.0
	player_jump_velocity_spin.step = 0.5
	player_jump_velocity_spin.custom_minimum_size = Vector2(0, 28)
	player_jump_velocity_spin.prefix = "Jump: "
	player_jump_velocity_spin.value_changed.connect(_on_player_settings_changed)
	player_settings_panel.add_child(player_jump_velocity_spin)

	var atmosphere_summary := Label.new()
	atmosphere_summary.text = "Customize music and sky for this map only."
	atmosphere_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	atmosphere_summary.add_theme_font_size_override("font_size", 11)
	atmosphere_summary.add_theme_color_override("font_color", Color(0.38, 0.42, 0.47, 1))
	atmosphere_settings_panel.add_child(atmosphere_summary)

	var music_label := Label.new()
	music_label.text = "Mode Music"
	music_label.add_theme_font_size_override("font_size", 12)
	music_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	atmosphere_settings_panel.add_child(music_label)

	var music_path_hbox := HBoxContainer.new()
	music_path_hbox.add_theme_constant_override("separation", 6)
	atmosphere_settings_panel.add_child(music_path_hbox)

	atmosphere_music_path_edit = LineEdit.new()
	atmosphere_music_path_edit.placeholder_text = "No music selected"
	atmosphere_music_path_edit.editable = false
	atmosphere_music_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_path_hbox.add_child(atmosphere_music_path_edit)

	var music_browse_button := Button.new()
	music_browse_button.text = "Add Track"
	music_browse_button.pressed.connect(_on_music_browse_pressed)
	music_path_hbox.add_child(music_browse_button)

	var music_clear_button := Button.new()
	music_clear_button.text = "Clear"
	music_clear_button.pressed.connect(_on_music_clear_pressed)
	music_path_hbox.add_child(music_clear_button)

	var music_list_panel := PanelContainer.new()
	music_list_panel.custom_minimum_size = Vector2(0, 104)
	var music_list_style := StyleBoxFlat.new()
	music_list_style.bg_color = Color(0.955, 0.965, 0.975, 1.0)
	music_list_style.border_color = Color(0.78, 0.82, 0.86, 1.0)
	music_list_style.border_width_left = 1
	music_list_style.border_width_top = 1
	music_list_style.border_width_right = 1
	music_list_style.border_width_bottom = 1
	music_list_style.corner_radius_top_left = 6
	music_list_style.corner_radius_top_right = 6
	music_list_style.corner_radius_bottom_left = 6
	music_list_style.corner_radius_bottom_right = 6
	music_list_panel.add_theme_stylebox_override("panel", music_list_style)
	atmosphere_settings_panel.add_child(music_list_panel)

	var music_list_scroll := ScrollContainer.new()
	music_list_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	music_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	music_list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	music_list_panel.add_child(music_list_scroll)

	atmosphere_music_list = VBoxContainer.new()
	atmosphere_music_list.add_theme_constant_override("separation", 4)
	atmosphere_music_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_list_scroll.add_child(atmosphere_music_list)

	atmosphere_music_volume_label = Label.new()
	atmosphere_music_volume_label.text = "Volume: 65%"
	atmosphere_music_volume_label.add_theme_font_size_override("font_size", 11)
	atmosphere_music_volume_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	atmosphere_settings_panel.add_child(atmosphere_music_volume_label)

	atmosphere_music_volume_slider = HSlider.new()
	atmosphere_music_volume_slider.min_value = 0.0
	atmosphere_music_volume_slider.max_value = 100.0
	atmosphere_music_volume_slider.step = 1.0
	atmosphere_music_volume_slider.value = DEFAULT_MODE_MUSIC_VOLUME * 100.0
	atmosphere_music_volume_slider.custom_minimum_size = Vector2(0, 20)
	atmosphere_music_volume_slider.value_changed.connect(_on_music_volume_changed)
	atmosphere_settings_panel.add_child(atmosphere_music_volume_slider)

	var sky_label := Label.new()
	sky_label.text = "Sky Panorama"
	sky_label.add_theme_font_size_override("font_size", 12)
	sky_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	atmosphere_settings_panel.add_child(sky_label)

	var sky_path_hbox := HBoxContainer.new()
	sky_path_hbox.add_theme_constant_override("separation", 6)
	atmosphere_settings_panel.add_child(sky_path_hbox)

	atmosphere_sky_path_edit = LineEdit.new()
	atmosphere_sky_path_edit.placeholder_text = "No sky selected"
	atmosphere_sky_path_edit.editable = false
	atmosphere_sky_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sky_path_hbox.add_child(atmosphere_sky_path_edit)

	var sky_browse_button := Button.new()
	sky_browse_button.text = "Browse"
	sky_browse_button.pressed.connect(_on_sky_browse_pressed)
	sky_path_hbox.add_child(sky_browse_button)

	var sky_clear_button := Button.new()
	sky_clear_button.text = "Clear"
	sky_clear_button.pressed.connect(_on_sky_clear_pressed)
	sky_path_hbox.add_child(sky_clear_button)

	music_file_dialog = FileDialog.new()
	music_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	music_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	music_file_dialog.filters = PackedStringArray(["*.mp3, *.ogg ; Audio Files"])
	music_file_dialog.use_native_dialog = true
	music_file_dialog.title = "Add Music Tracks"
	music_file_dialog.file_selected.connect(_on_music_file_selected)
	music_file_dialog.files_selected.connect(_on_music_files_selected)
	panel.add_child(music_file_dialog)

	sky_file_dialog = FileDialog.new()
	sky_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	sky_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	sky_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files"])
	sky_file_dialog.use_native_dialog = true
	sky_file_dialog.title = "Select Sky Image"
	sky_file_dialog.file_selected.connect(_on_sky_file_selected)
	panel.add_child(sky_file_dialog)

	_clear_inspector()
	_apply_player_settings_to_ui(_get_default_player_settings())
	_apply_mode_settings_to_ui(_get_default_mode_settings())

func _clear_inspector() -> void:
	if name_edit: name_edit.text = ""
	if transparency_slider: transparency_slider.value = 0.0
	if can_collide_check: can_collide_check.button_pressed = true
	if damage_enabled_check: damage_enabled_check.button_pressed = false
	if damage_amount_spin:
		damage_amount_spin.set_value_no_signal(DEFAULT_BLOCK_DAMAGE)
		damage_amount_spin.editable = false
	if material_option: material_option.selected = 0
	_set_spinbox_values("PositionHBox", Vector3.ZERO)
	_set_spinbox_values("ScaleHBox", Vector3.ONE)

func _set_spinbox_values(hbox_name: String, vec: Vector3) -> void:
	var hbox = inspector_panel.get_node_or_null(hbox_name)
	if hbox:
		for child in hbox.get_children():
			if child is SpinBox:
				match child.name:
					"X": child.set_value_no_signal(vec.x)
					"Y": child.set_value_no_signal(vec.y)
					"Z": child.set_value_no_signal(vec.z)

func _update_inspector() -> void:
	if selected_block == null or not is_instance_valid(selected_block):
		return
	var block_name: String = selected_block.get_meta("block_name", selected_block.name)
	name_edit.text = block_name
	transparency_slider.value = selected_block.get_meta("transparency", 0.0)
	can_collide_check.button_pressed = selected_block.get_meta("can_collide", true)
	if damage_enabled_check:
		damage_enabled_check.button_pressed = selected_block.get_meta("deals_damage", false)
	if damage_amount_spin:
		damage_amount_spin.set_value_no_signal(float(selected_block.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)))
		damage_amount_spin.editable = damage_enabled_check.button_pressed if damage_enabled_check else false

	var mat_type: String = selected_block.get_meta("material_type", "Plastic")
	var mat_idx := 0
	match mat_type:
		"Neon": mat_idx = 1
		"Glass": mat_idx = 2
		"Metal": mat_idx = 3
	material_option.selected = mat_idx

	# Get block color
	var block_color_picker = inspector_panel.get_node_or_null("BlockColorPicker")
	if block_color_picker and selected_block is MeshInstance3D:
		var mesh_block := selected_block as MeshInstance3D
		var mat = mesh_block.get_active_material(0) as StandardMaterial3D
		if mat:
			block_color_picker.color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 1.0)

	# Position
	_set_spinbox_values("PositionHBox", selected_block.position)
	# Scale
	_set_spinbox_values("ScaleHBox", selected_block.scale)

# ===== INSPECTOR CALLBACKS =====
func _on_transform_entered(value: float) -> void:
	if not selected_block or not is_instance_valid(selected_block): return
	var pos_hbox = inspector_panel.get_node_or_null("PositionHBox")
	if pos_hbox:
		var n_pos = Vector3.ZERO
		for c in pos_hbox.get_children():
			if c is SpinBox:
				if c.name == "X": n_pos.x = c.value
				if c.name == "Y": n_pos.y = c.value
				if c.name == "Z": n_pos.z = c.value
		selected_block.position = n_pos
		
	var scale_hbox = inspector_panel.get_node_or_null("ScaleHBox")
	if scale_hbox:
		var n_scale = Vector3.ONE
		for c in scale_hbox.get_children():
			if c is SpinBox:
				if c.name == "X": n_scale.x = c.value
				if c.name == "Y": n_scale.y = c.value
				if c.name == "Z": n_scale.z = c.value
		selected_block.scale = n_scale
		_update_block_collision(selected_block)
		_update_selection_highlight()
func _on_name_changed(new_name: String) -> void:
	if selected_block and is_instance_valid(selected_block):
		selected_block.set_meta("block_name", new_name)
		_refresh_explorer()

func _on_transparency_changed(value: float) -> void:
	if selected_block and is_instance_valid(selected_block):
		selected_block.set_meta("transparency", value)
		if selected_block is MeshInstance3D:
			_rebuild_block_material(selected_block as MeshInstance3D)

func _on_can_collide_toggled(toggled: bool) -> void:
	if selected_block and is_instance_valid(selected_block):
		selected_block.set_meta("can_collide", toggled)
		_update_block_collision(selected_block)

func _on_damage_enabled_toggled(toggled: bool) -> void:
	if selected_block and is_instance_valid(selected_block):
		selected_block.set_meta("deals_damage", toggled)
	if damage_amount_spin:
		damage_amount_spin.editable = toggled

func _on_damage_amount_changed(value: float) -> void:
	if selected_block and is_instance_valid(selected_block):
		selected_block.set_meta("damage_amount", value)

func _on_material_changed(index: int) -> void:
	if selected_block and is_instance_valid(selected_block):
		var mat_types := ["Plastic", "Neon", "Glass", "Metal"]
		var mat_type: String = mat_types[index] if index < mat_types.size() else "Plastic"
		selected_block.set_meta("material_type", mat_type)
		if selected_block is MeshInstance3D:
			_rebuild_block_material(selected_block as MeshInstance3D)

func _on_block_color_changed(color: Color) -> void:
	if selected_block and is_instance_valid(selected_block) and selected_block is MeshInstance3D:
		var mesh_block := selected_block as MeshInstance3D
		var mat_type: String = selected_block.get_meta("material_type", "Plastic")
		var transparency: float = selected_block.get_meta("transparency", 0.0)
		var new_mat := _create_material(color, mat_type, transparency)
		mesh_block.mesh.surface_set_material(0, new_mat)
		_refresh_special_block_visuals(mesh_block)

func _rebuild_block_material(block: MeshInstance3D) -> void:
	var mat = block.get_active_material(0) as StandardMaterial3D
	var color := Color.WHITE
	if mat:
		color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 1.0)
	var mat_type: String = block.get_meta("material_type", "Plastic")
	var transparency: float = block.get_meta("transparency", 0.0)
	var new_mat := _create_material(color, mat_type, transparency)
	block.mesh.surface_set_material(0, new_mat)
	_refresh_special_block_visuals(block)

func _on_color_changed(color: Color) -> void:
	current_color = color

func _on_time_changed(value: float) -> void:
	if not sun_light: return
	var time_ratio = value / 24.0
	var angle = (time_ratio * 360.0) - 90.0
	sun_light.rotation_degrees.x = -angle

func _on_player_settings_changed(_value: float) -> void:
	pass

func _get_default_player_settings() -> Dictionary:
	return {
		"move_speed": DEFAULT_PLAYER_MOVE_SPEED,
		"sprint_multiplier": DEFAULT_PLAYER_SPRINT_MULTIPLIER,
		"jump_velocity": DEFAULT_PLAYER_JUMP_VELOCITY
	}

func _get_current_player_settings() -> Dictionary:
	var settings := _get_default_player_settings()
	if player_move_speed_spin:
		settings["move_speed"] = player_move_speed_spin.value
	if player_sprint_multiplier_spin:
		settings["sprint_multiplier"] = player_sprint_multiplier_spin.value
	if player_jump_velocity_spin:
		settings["jump_velocity"] = player_jump_velocity_spin.value
	return settings

func _apply_player_settings_to_ui(settings: Dictionary) -> void:
	var merged_settings := _get_default_player_settings()
	for key in settings.keys():
		merged_settings[key] = settings[key]
	if player_move_speed_spin:
		player_move_speed_spin.set_value_no_signal(float(merged_settings.get("move_speed", DEFAULT_PLAYER_MOVE_SPEED)))
	if player_sprint_multiplier_spin:
		player_sprint_multiplier_spin.set_value_no_signal(float(merged_settings.get("sprint_multiplier", DEFAULT_PLAYER_SPRINT_MULTIPLIER)))
	if player_jump_velocity_spin:
		player_jump_velocity_spin.set_value_no_signal(float(merged_settings.get("jump_velocity", DEFAULT_PLAYER_JUMP_VELOCITY)))

func _on_music_browse_pressed() -> void:
	if music_file_dialog:
		music_file_dialog.popup_centered(Vector2(720, 420))

func _on_sky_browse_pressed() -> void:
	if sky_file_dialog:
		sky_file_dialog.popup_centered(Vector2(720, 420))

func _on_music_file_selected(path: String) -> void:
	if current_music_source_paths.size() >= CLOUD_INLINE_ASSET_MAX_TRACKS:
		push_warning("[Studio] Track limit reached (%d). Remove some tracks before adding new ones." % CLOUD_INLINE_ASSET_MAX_TRACKS)
		if toolbar_status_label:
			toolbar_status_label.text = "Track limit reached (%d max)" % CLOUD_INLINE_ASSET_MAX_TRACKS
		return
	if not current_music_source_paths.has(path):
		current_music_source_paths.append(path)
	_refresh_atmosphere_path_labels()

func _on_music_files_selected(paths: PackedStringArray) -> void:
	var skipped: int = 0
	for path in paths:
		if current_music_source_paths.size() >= CLOUD_INLINE_ASSET_MAX_TRACKS:
			skipped += 1
			continue
		var clean_path: String = str(path).strip_edges()
		if clean_path.is_empty() or current_music_source_paths.has(clean_path):
			continue
		current_music_source_paths.append(clean_path)
	if skipped > 0:
		push_warning("[Studio] Skipped %d track(s) — playlist limit is %d." % [skipped, CLOUD_INLINE_ASSET_MAX_TRACKS])
		if toolbar_status_label:
			toolbar_status_label.text = "Skipped %d track(s) (max %d)" % [skipped, CLOUD_INLINE_ASSET_MAX_TRACKS]
	_refresh_atmosphere_path_labels()

func _remove_music_track_at(index: int) -> void:
	if index < 0 or index >= current_music_source_paths.size():
		return
	current_music_source_paths.remove_at(index)
	_refresh_atmosphere_path_labels()

func _on_sky_file_selected(path: String) -> void:
	current_sky_source_path = path
	_apply_editor_sky_preview()
	_refresh_atmosphere_path_labels()

func _on_music_clear_pressed() -> void:
	current_music_source_paths.clear()
	_refresh_atmosphere_path_labels()

func _on_sky_clear_pressed() -> void:
	current_sky_source_path = ""
	_apply_editor_sky_preview()
	_refresh_atmosphere_path_labels()

func _on_music_volume_changed(value: float) -> void:
	if atmosphere_music_volume_label:
		atmosphere_music_volume_label.text = "Volume: %d%%" % roundi(value)

func _get_default_mode_settings() -> Dictionary:
	return {
		"music_playlist": [],
		"music_volume": DEFAULT_MODE_MUSIC_VOLUME,
		"skybox_file": "",
		"roblox_sound_assets": []
	}

func _apply_mode_settings_to_ui(settings: Dictionary, folder: String = "") -> void:
	var merged_settings := _get_default_mode_settings()
	for key in settings.keys():
		merged_settings[key] = settings[key]

	current_music_source_paths.clear()
	current_sky_source_path = ""
	current_imported_sound_assets.clear()
	var music_playlist: Array = merged_settings.get("music_playlist", [])
	if music_playlist.is_empty():
		var legacy_music_file := str(merged_settings.get("music_file", "")).strip_edges()
		if not legacy_music_file.is_empty():
			music_playlist = [legacy_music_file]
	var skybox_file := str(merged_settings.get("skybox_file", "")).strip_edges()
	for music_file_variant in music_playlist:
		var music_file := str(music_file_variant).strip_edges()
		if not music_file.is_empty() and not folder.is_empty():
			current_music_source_paths.append(folder + "/" + music_file)
	if not skybox_file.is_empty() and not folder.is_empty():
		current_sky_source_path = folder + "/" + skybox_file
	var imported_sounds: Array = merged_settings.get("roblox_sound_assets", []) if merged_settings.get("roblox_sound_assets", []) is Array else []
	for sound_variant in imported_sounds:
		if sound_variant is Dictionary:
			current_imported_sound_assets.append((sound_variant as Dictionary).duplicate(true))

	if atmosphere_music_volume_slider:
		atmosphere_music_volume_slider.set_value_no_signal(clampf(float(merged_settings.get("music_volume", DEFAULT_MODE_MUSIC_VOLUME)), 0.0, 1.0) * 100.0)
	_on_music_volume_changed(atmosphere_music_volume_slider.value if atmosphere_music_volume_slider else DEFAULT_MODE_MUSIC_VOLUME * 100.0)
	_apply_editor_sky_preview()
	_refresh_atmosphere_path_labels()

func _refresh_atmosphere_path_labels() -> void:
	if atmosphere_music_path_edit:
		if current_music_source_paths.is_empty():
			atmosphere_music_path_edit.text = ""
		elif current_music_source_paths.size() == 1:
			atmosphere_music_path_edit.text = current_music_source_paths[0].get_file()
		else:
			atmosphere_music_path_edit.text = "%d tracks, %.1f MB" % [
				current_music_source_paths.size(),
				float(_get_playlist_total_size_bytes(current_music_source_paths)) / 1048576.0
			]
		atmosphere_music_path_edit.placeholder_text = "No music selected"
	_rebuild_music_track_list()
	if atmosphere_sky_path_edit:
		atmosphere_sky_path_edit.text = current_sky_source_path.get_file() if not current_sky_source_path.is_empty() else ""
		atmosphere_sky_path_edit.placeholder_text = "No sky selected"

func _rebuild_music_track_list() -> void:
	if atmosphere_music_list == null:
		return
	for child in atmosphere_music_list.get_children():
		child.queue_free()
	if current_music_source_paths.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No tracks yet. Add MP3 or OGG files for this mode."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", Color(0.42, 0.46, 0.5, 1.0))
		atmosphere_music_list.add_child(empty_label)
		return
	for i in range(current_music_source_paths.size()):
		atmosphere_music_list.add_child(_create_music_track_row(i, current_music_source_paths[i]))

func _create_music_track_row(index: int, path: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 28)

	var number_label := Label.new()
	number_label.text = "%02d" % (index + 1)
	number_label.custom_minimum_size = Vector2(28, 0)
	number_label.add_theme_font_size_override("font_size", 11)
	number_label.add_theme_color_override("font_color", Color(0.38, 0.42, 0.47, 1.0))
	row.add_child(number_label)

	var track_label := Label.new()
	track_label.text = path.get_file()
	track_label.clip_text = true
	track_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_label.add_theme_font_size_override("font_size", 11)
	track_label.add_theme_color_override("font_color", Color(0.12, 0.15, 0.18, 1.0))
	row.add_child(track_label)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.custom_minimum_size = Vector2(72, 24)
	remove_button.focus_mode = Control.FOCUS_NONE
	remove_button.pressed.connect(_remove_music_track_at.bind(index))
	row.add_child(remove_button)
	return row

func _apply_editor_sky_preview() -> void:
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	if current_sky_source_path.is_empty():
		env_node.environment.sky = null
		env_node.environment.background_mode = Environment.BG_COLOR
		return
	var image := _load_image_from_path(current_sky_source_path)
	if image == null:
		env_node.environment.sky = null
		env_node.environment.background_mode = Environment.BG_COLOR
		return
	var sky_texture := ImageTexture.create_from_image(image)
	var panorama_material := PanoramaSkyMaterial.new()
	panorama_material.panorama = sky_texture
	var sky := Sky.new()
	sky.sky_material = panorama_material
	env_node.environment.sky = sky
	env_node.environment.background_mode = Environment.BG_SKY

func _collect_mode_settings_for_save(folder: String) -> Dictionary:
	var settings := _get_default_mode_settings()
	var music_volume_percent := atmosphere_music_volume_slider.value if atmosphere_music_volume_slider else (DEFAULT_MODE_MUSIC_VOLUME * 100.0)
	settings["music_volume"] = clampf(float(music_volume_percent) / 100.0, 0.0, 1.0)
	settings["music_playlist"] = _store_mode_playlist_files(current_music_source_paths, folder)
	settings["skybox_file"] = _store_mode_asset_file(current_sky_source_path, folder, MODE_SKY_FILE_BASENAME)
	settings["roblox_sound_assets"] = current_imported_sound_assets.duplicate(true)
	return settings

func _store_mode_playlist_files(source_paths: Array[String], folder: String) -> Array[String]:
	var stored_files: Array[String] = []
	for i in range(source_paths.size()):
		var stored_file := _store_mode_asset_file(source_paths[i], folder, "%s_%02d" % [MODE_MUSIC_FILE_BASENAME, i + 1])
		if not stored_file.is_empty():
			stored_files.append(stored_file)
	return stored_files

func _store_mode_asset_file(source_path: String, folder: String, target_basename: String) -> String:
	var resolved_source := _resolve_existing_file_path_for_folder(source_path, folder)
	if resolved_source.is_empty():
		return ""
	var extension := resolved_source.get_extension().to_lower()
	if extension.is_empty():
		return ""
	var destination_path := folder + "/" + target_basename + "." + extension
	var source_file := FileAccess.open(resolved_source, FileAccess.READ)
	if source_file == null:
		return ""
	var data := source_file.get_buffer(source_file.get_length())
	source_file.close()
	var target_file := FileAccess.open(destination_path, FileAccess.WRITE)
	if target_file == null:
		return ""
	target_file.store_buffer(data)
	target_file.close()
	return destination_path.get_file()

func _resolve_existing_file_path_for_folder(path: String, folder: String) -> String:
	var resolved_path := _resolve_existing_file_path(path)
	if not resolved_path.is_empty():
		return resolved_path
	if not folder.is_empty():
		var folder_path := folder.path_join(path)
		if FileAccess.file_exists(folder_path):
			return folder_path
	return ""

func _resolve_existing_file_path(path: String) -> String:
	if path.is_empty():
		return ""
	var candidate_paths: Array[String] = [path]
	var global_path := ProjectSettings.globalize_path(path)
	if global_path != path:
		candidate_paths.append(global_path)
	for candidate in candidate_paths:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

func _store_runtime_object_asset_files(objects: Array[Dictionary], folder: String) -> void:
	var stored_by_source: Dictionary = {}
	var sound_index: int = 1
	for data in objects:
		if str(data.get("class", "")) != "Sound":
			continue
		var source_path := _runtime_object_sound_source_path(data, folder)
		if source_path.is_empty():
			continue
		var stored_file := str(stored_by_source.get(source_path, "")).strip_edges()
		if stored_file.is_empty():
			stored_file = _store_mode_asset_file(source_path, folder, "rbxl_sound_%02d" % sound_index)
			if stored_file.is_empty():
				continue
			stored_by_source[source_path] = stored_file
			sound_index += 1
		data["file"] = stored_file
		data["resolved_path"] = stored_file
		data["path"] = stored_file

func _runtime_object_sound_source_path(data: Dictionary, folder: String) -> String:
	for key in ["file", "resolved_path", "path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if candidate.is_empty():
			continue
		var resolved_path := _resolve_existing_file_path_for_folder(candidate, folder)
		if not resolved_path.is_empty():
			return resolved_path
	return ""

func _collect_runtime_objects_for_save() -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	var parent: Node = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child.is_in_group(RBXL_RUNTIME_OBJECT_GROUP):
			objects.append(_runtime_object_data_from_node(child))
	return objects

func _runtime_object_data_from_node(node: Node) -> Dictionary:
	var data: Dictionary = {}
	if node.has_meta("runtime_object_data") and node.get_meta("runtime_object_data") is Dictionary:
		data = (node.get_meta("runtime_object_data") as Dictionary).duplicate(true)
	if node is Node3D:
		var node3d := node as Node3D
		data["px"] = snappedf(node3d.position.x, 0.001)
		data["py"] = snappedf(node3d.position.y, 0.001)
		data["pz"] = snappedf(node3d.position.z, 0.001)
		data["rx"] = snappedf(node3d.rotation_degrees.x, 0.001)
		data["ry"] = snappedf(node3d.rotation_degrees.y, 0.001)
		data["rz"] = snappedf(node3d.rotation_degrees.z, 0.001)
	data["name"] = str(data.get("name", node.name)).strip_edges()
	if not data.has("class"):
		data["class"] = str(node.get_meta("roblox_class", "RuntimeObject"))
	return data

func _load_runtime_objects_from_map(raw_objects: Variant) -> void:
	if not (raw_objects is Array):
		return
	var parent: Node = placement_parent if placement_parent else self
	for object_variant in raw_objects:
		if not (object_variant is Dictionary):
			continue
		var runtime_node := _create_runtime_object_node_from_data(object_variant as Dictionary)
		if runtime_node == null:
			continue
		parent.add_child(runtime_node)

func _create_runtime_object_node_from_data(data: Dictionary) -> Node3D:
	var roblox_class := str(data.get("class", "RuntimeObject"))
	var runtime_node: Node3D
	match roblox_class:
		"PointLight", "SurfaceLight":
			var light := OmniLight3D.new()
			light.light_color = _runtime_object_color(data)
			light.light_energy = float(data.get("brightness", 1.0)) * 2.0
			light.omni_range = float(data.get("range", 8.0))
			runtime_node = light
		"SpotLight":
			var light := SpotLight3D.new()
			light.light_color = _runtime_object_color(data)
			light.light_energy = float(data.get("brightness", 1.0)) * 2.0
			light.spot_range = float(data.get("range", 8.0))
			light.spot_angle = float(data.get("angle", 45.0))
			runtime_node = light
		"Sound":
			runtime_node = Node3D.new()
			var player := AudioStreamPlayer3D.new()
			player.name = "AudioPreview"
			var volume := maxf(float(data.get("volume", 1.0)), 0.0001)
			player.volume_db = linear_to_db(volume)
			runtime_node.add_child(player)
		"ParticleEmitter", "Fire", "Smoke", "Sparkles":
			var particles := GPUParticles3D.new()
			particles.amount = maxi(1, int(data.get("rate", 16.0)))
			particles.emitting = bool(data.get("enabled", true))
			runtime_node = particles
		"Camera":
			var cam := Camera3D.new()
			cam.fov = float(data.get("fov", 70.0))
			runtime_node = cam
		"Decal", "Texture":
			var decal := Decal.new()
			decal.size = Vector3(4.0, 4.0, 4.0)
			runtime_node = decal
		_:
			runtime_node = Node3D.new()
	runtime_node.name = str(data.get("name", roblox_class)).strip_edges()
	if runtime_node.name.is_empty():
		runtime_node.name = roblox_class
	runtime_node.position = Vector3(float(data.get("px", 0.0)), float(data.get("py", 0.0)), float(data.get("pz", 0.0)))
	runtime_node.rotation_degrees = Vector3(float(data.get("rx", 0.0)), float(data.get("ry", 0.0)), float(data.get("rz", 0.0)))
	runtime_node.add_to_group(RBXL_RUNTIME_OBJECT_GROUP)
	runtime_node.set_meta("runtime_object_data", data.duplicate(true))
	runtime_node.set_meta("roblox_class", roblox_class)
	return runtime_node

func _runtime_object_color(data: Dictionary) -> Color:
	var raw: Variant = data.get("color", [1.0, 1.0, 1.0])
	if raw is Array:
		var arr := raw as Array
		return Color(
			float(arr[0]) if arr.size() > 0 else 1.0,
			float(arr[1]) if arr.size() > 1 else 1.0,
			float(arr[2]) if arr.size() > 2 else 1.0
		)
	return Color.WHITE

# ===== SAVE / LOAD / PUBLISH =====
func _on_save_button_pressed() -> void:
	if current_map_folder.is_empty():
		var folder_name := _get_unique_map_folder_name(_sanitize_map_folder_name(_normalize_map_name(current_map_name)))
		current_map_folder = UserSession.get_maps_root_path() + "/" + folder_name
	_save_map(current_map_folder)

func _on_publish_pressed() -> void:
	# Show a popup to enter name and description
	var popup := AcceptDialog.new()
	popup.title = "Publish Map"
	popup.dialog_text = ""
	popup.min_size = Vector2(400, 300)
	popup.ok_button_text = "Publish!"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = "Map Name:"
	vbox.add_child(name_label)

	var map_name_edit := LineEdit.new()
	map_name_edit.text = current_map_name
	map_name_edit.placeholder_text = "My Awesome Place"
	vbox.add_child(map_name_edit)

	var existing_meta := _load_map_meta(current_map_folder)

	var desc_label := Label.new()
	desc_label.text = "Description:"
	vbox.add_child(desc_label)

	var desc_edit := TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 80)
	desc_edit.placeholder_text = "Enter a description..."
	desc_edit.text = str(existing_meta.get("description", ""))
	vbox.add_child(desc_edit)
	
	var icon_label := Label.new()
	icon_label.text = "Icon (Options):"
	vbox.add_child(icon_label)
	
	var icon_hbox = HBoxContainer.new()
	vbox.add_child(icon_hbox)
	
	var icon_path_edit = LineEdit.new()
	icon_path_edit.placeholder_text = "Default (Screenshot)"
	icon_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_path_edit.editable = false
	icon_hbox.add_child(icon_path_edit)
	
	var browse_btn = Button.new()
	browse_btn.text = " Browse... "
	icon_hbox.add_child(browse_btn)

	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.png, *.jpg, *.jpeg ; Image Files"]
	file_dialog.title = "Select Icon Image"
	file_dialog.use_native_dialog = true
	add_child(file_dialog)
	
	browse_btn.pressed.connect(func(): file_dialog.popup_centered(Vector2(600, 400)))
	file_dialog.file_selected.connect(func(path: String): icon_path_edit.text = path)

	popup.add_child(vbox)
	add_child(popup)
	popup.popup_centered()

	popup.confirmed.connect(func():
		current_map_name = _normalize_map_name(map_name_edit.text)
		var folder := current_map_folder
		if folder.is_empty():
			var folder_name := _get_unique_map_folder_name(_sanitize_map_folder_name(current_map_name))
			folder = UserSession.get_maps_root_path() + "/" + folder_name
		current_map_folder = folder
		if icon_path_edit.text != "":
			custom_icon_set = true
		popup.hide()
		await _publish_map(folder, current_map_name, desc_edit.text.strip_edges(), icon_path_edit.text)
		popup.queue_free()
	)
	popup.canceled.connect(func():
		popup.queue_free()
	)

func _publish_map(folder: String, map_name: String, description: String, custom_icon_path: String = "") -> Dictionary:
	_show_publish_progress("Publishing Map", "Saving local map files...", 0.04)
	# Ensure directory exists
	UserSession.ensure_current_storage()
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	var folder_name := folder.get_file()
	if maps_dir:
		if not maps_dir.dir_exists(folder_name):
			maps_dir.make_dir(folder_name)

	# Take screenshot for icon or use custom
	if custom_icon_path != "" and FileAccess.file_exists(custom_icon_path):
		var img := _load_image_from_path(custom_icon_path)
		if img:
			img.save_png(folder + "/icon.png")
		else:
			# If we can't load the image, take a screenshot instead
			var fallback_image := get_viewport().get_texture().get_image()
			if fallback_image:
				fallback_image.save_png(folder + "/icon.png")
	else:
		var image := get_viewport().get_texture().get_image()
		if image:
			image.save_png(folder + "/icon.png")

	# Save meta.json
	var meta := _load_map_meta(folder).duplicate(true)
	meta["name"] = map_name
	meta["creator"] = UserSession.username if UserSession.is_logged_in else "Unknown"
	meta["description"] = description
	meta["draft_unsaved"] = false
	meta["is_published"] = true
	var meta_file := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()

	# Save map_data.json
	_save_map(folder)
	print("[Studio] Publishing '%s' to Bobux Cloud..." % map_name)
	_show_publish_progress("Publishing Map", "Uploading %s to Bobux Cloud..." % map_name, 0.24)
	var cloud_result: Dictionary = await _upload_published_map_to_cloud(folder, map_name)
	if bool(cloud_result.get("ok", false)):
		print("[Studio] Published '%s'!" % map_name)
		_finish_publish_progress(true, "Published! The mode is now visible in Bobux.")
	else:
		var error_text := str(cloud_result.get("error", "Unknown cloud error"))
		push_warning("[Studio] Local save completed, but cloud publish failed: %s" % error_text)
		_finish_publish_progress(false, "Cloud publish failed: %s" % error_text)
	return cloud_result

func _upload_published_map_to_cloud(folder: String, map_name: String) -> Dictionary:
	if not CloudAPI.is_configured():
		return {"ok": false, "error": "Cloud API is not configured."}
	var map_payload := _read_json_dictionary(folder + "/map_data.json")
	if map_payload.is_empty():
		push_warning("[Studio] Cloud upload skipped because map_data.json could not be read.")
		return {"ok": false, "error": "map_data.json could not be read."}
	var meta := _load_map_meta(folder)
	var resolved_cloud_map_id: String = str(meta.get("cloud_map_id", "")).strip_edges()
	if resolved_cloud_map_id.is_empty() and CloudAPI.has_method("resolve_cloud_map_id_for_name"):
		resolved_cloud_map_id = str(CloudAPI.resolve_cloud_map_id_for_name(map_name, meta)).strip_edges()
	if resolved_cloud_map_id.is_empty():
		return {"ok": false, "error": "Could not resolve cloud map id before uploading assets."}
	var profile_result: Dictionary = await CloudAPI.authenticate_or_create_profile(UserSession.username if UserSession.is_logged_in else "Unknown")
	if not bool(profile_result.get("ok", false)):
		return profile_result
	map_payload = await _embed_mode_assets_for_cloud(map_payload, folder, resolved_cloud_map_id)
	_show_publish_progress("Publishing Map", "Preparing thumbnail...", 0.84)
	var thumbnail_payload: String = _encode_image_file_as_data_uri(folder + "/icon.png")
	_show_publish_progress("Publishing Map", "Sending map data to Bobux Cloud...", 0.9)
	var upload_result := await CloudAPI.upload_map_to_cloud(
		map_payload,
		map_name,
		{
			"description": str(meta.get("description", "")),
			"cloud_map_id": resolved_cloud_map_id,
			"cloud_version_id": str(meta.get("cloud_version_id", "")),
			"owner_name": UserSession.username if UserSession.is_logged_in else "Unknown",
			"thumbnail": thumbnail_payload,
			"is_published": true
		}
	)
	if not bool(upload_result.get("ok", false)):
		push_warning("[Studio] Cloud upload failed: %s" % str(upload_result.get("error", "Unknown cloud error")))
		return upload_result
	var cloud_map_id := _extract_cloud_map_id(upload_result.get("data", {}))
	if cloud_map_id.is_empty():
		push_warning("[Studio] Cloud upload succeeded but returned no map id.")
		return {"ok": false, "error": "Cloud upload succeeded but returned no map id."}
	meta["cloud_map_id"] = cloud_map_id
	meta["draft_unsaved"] = false
	meta["is_published"] = true
	UserSession.unmark_deleted_game(cloud_map_id, map_name)
	var cloud_version_id := _extract_cloud_map_version(upload_result.get("data", {}), str(meta.get("cloud_version_id", "")))
	if not cloud_version_id.is_empty():
		meta["cloud_version_id"] = cloud_version_id
	var meta_file := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()
	print("[Studio] Cloud map id saved: %s" % cloud_map_id)
	return upload_result

func _embed_mode_assets_for_cloud(map_payload: Dictionary, folder: String, cloud_map_id: String) -> Dictionary:
	var payload: Dictionary = map_payload.duplicate(true)
	var mode_settings: Dictionary = payload.get("mode_settings", {}) if payload.get("mode_settings", {}) is Dictionary else {}
	var asset_blobs: Dictionary = {}
	var asset_urls: Dictionary = {}
	var playlist: Array = mode_settings.get("music_playlist", []) if mode_settings.get("music_playlist", []) is Array else []
	var publish_asset_files := _collect_publish_asset_file_names(payload, playlist)
	var embedded_assets: int = 0
	var skipped_assets: int = 0
	var asset_total: int = publish_asset_files.size()
	for index in range(publish_asset_files.size()):
		var file_variant: Variant = publish_asset_files[index]
		var relative_file_name: String = str(file_variant).strip_edges()
		if relative_file_name.is_empty():
			continue
		var absolute_path: String = folder.path_join(relative_file_name)
		var file_size: int = _get_file_size_bytes(absolute_path)
		if file_size <= 0:
			skipped_assets += 1
			continue
		if file_size > 50 * 1024 * 1024:
			skipped_assets += 1
			push_warning("[Studio] Skipping map asset '%s' during cloud publish. Size %.2f MB (Storage safety limit 50 MB)." % [
				relative_file_name,
				float(file_size) / 1048576.0
			])
			continue
		_show_publish_progress(
			"Publishing Map",
			"Uploading asset %d/%d: %s" % [index + 1, maxi(asset_total, 1), relative_file_name.get_file()],
			0.30 + 0.48 * float(index + 1) / float(maxi(asset_total, 1))
		)
		await get_tree().process_frame
		var storage_result: Dictionary = await CloudAPI.upload_map_asset_file(
			cloud_map_id,
			relative_file_name,
			absolute_path,
			"",
			CloudAPI.HTTP_MEDIA_UPLOAD_TIMEOUT_SECONDS,
			1
		)
		if bool(storage_result.get("ok", false)):
			var asset_data: Dictionary = storage_result.get("asset", {}) if storage_result.get("asset", {}) is Dictionary else {}
			var public_url: String = str(asset_data.get("public_url", "")).strip_edges()
			if not public_url.is_empty():
				asset_urls[relative_file_name] = public_url
				embedded_assets += 1
				continue
		var upload_error: String = str(storage_result.get("error", "Unknown storage error"))
		push_warning("[Studio] Storage upload failed for map asset '%s': %s" % [
			relative_file_name,
			upload_error
		])
		skipped_assets += 1
		if toolbar_status_label:
			toolbar_status_label.text = "Skipped asset: %s" % relative_file_name.get_file()
		_show_publish_progress(
			"Publishing Map",
			"Skipped asset %d/%d: %s" % [index + 1, maxi(asset_total, 1), relative_file_name.get_file()],
			0.30 + 0.48 * float(index + 1) / float(maxi(asset_total, 1))
		)
		await get_tree().process_frame
		continue
	var skybox_file: String = str(mode_settings.get("skybox_file", "")).strip_edges()
	if not skybox_file.is_empty():
		_show_publish_progress("Publishing Map", "Embedding skybox...", 0.80)
		await get_tree().process_frame
		var sky_base64: String = _encode_file_to_base64(folder.path_join(skybox_file), CLOUD_INLINE_ASSET_MAX_BYTES)
		if not sky_base64.is_empty():
			asset_blobs[skybox_file] = sky_base64
	if not asset_blobs.is_empty():
		payload["mode_asset_blobs"] = asset_blobs
	if not asset_urls.is_empty():
		payload["mode_asset_urls"] = asset_urls
	if skipped_assets > 0:
		payload["mode_asset_warning"] = "%d map asset(s) could not be uploaded. Compress audio as OGG for cloud play." % skipped_assets
		if toolbar_status_label:
			toolbar_status_label.text = "Published with %d skipped map asset(s)" % skipped_assets
	else:
		_show_publish_progress("Publishing Map", "Uploaded %d map asset(s)." % embedded_assets, 0.82)
	return payload

func _collect_publish_asset_file_names(payload: Dictionary, playlist: Array) -> Array[String]:
	var result: Array[String] = []
	for file_variant in playlist:
		_append_publish_asset_file_name(result, str(file_variant).strip_edges())
	var runtime_objects: Array = payload.get("runtime_objects", []) if payload.get("runtime_objects", []) is Array else []
	for object_variant in runtime_objects:
		if not (object_variant is Dictionary):
			continue
		var data: Dictionary = object_variant
		if str(data.get("class", "")) != "Sound":
			continue
		for key in ["file", "resolved_path", "path"]:
			_append_publish_asset_file_name(result, str(data.get(key, "")).strip_edges())
	return result

func _append_publish_asset_file_name(result: Array[String], value: String) -> void:
	if value.is_empty():
		return
	if value.begins_with("res://") or value.begins_with("user://") or value.find(":") == 1:
		value = value.get_file()
	value = value.replace("\\", "/").get_file()
	if value.is_empty() or result.has(value):
		return
	result.append(value)

func _get_file_size_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = file.get_length()
	file.close()
	return length

func _get_playlist_total_size_bytes(paths: Array[String]) -> int:
	var total_size: int = 0
	for path in paths:
		var resolved_path := _resolve_existing_file_path(path)
		if resolved_path.is_empty():
			continue
		total_size += _get_file_size_bytes(resolved_path)
	return total_size

func _encode_file_to_base64(path: String, max_bytes: int = -1) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var file_length: int = file.get_length()
	if max_bytes > 0 and file_length > max_bytes:
		file.close()
		push_warning("[Studio] Skipping cloud inline asset '%s' because it is %.2f MB (limit %.2f MB)." % [
			path.get_file(),
			float(file_length) / 1048576.0,
			float(max_bytes) / 1048576.0
		])
		if toolbar_status_label:
			toolbar_status_label.text = "Music too large: %s" % path.get_file()
		return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Marshalls.raw_to_base64(bytes)

func _encode_image_file_as_data_uri(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var image := Image.new()
	var load_error: Error = image.load(path)
	if load_error == OK and image.get_width() > 0 and image.get_height() > 0:
		var largest_dimension: int = maxi(image.get_width(), image.get_height())
		if largest_dimension > CLOUD_THUMBNAIL_MAX_DIMENSION:
			var resize_scale: float = float(CLOUD_THUMBNAIL_MAX_DIMENSION) / float(largest_dimension)
			image.resize(
				maxi(1, int(round(float(image.get_width()) * resize_scale))),
				maxi(1, int(round(float(image.get_height()) * resize_scale))),
				Image.INTERPOLATE_BILINEAR
			)
		var png_bytes: PackedByteArray = image.save_png_to_buffer()
		if not png_bytes.is_empty():
			return "data:image/png;base64,%s" % Marshalls.raw_to_base64(png_bytes)
	var encoded_body: String = _encode_file_to_base64(path, CLOUD_THUMBNAIL_FALLBACK_MAX_BYTES)
	if encoded_body.is_empty():
		return ""
	var extension: String = path.get_extension().to_lower()
	var mime_type: String = "image/png"
	if extension == "jpg" or extension == "jpeg":
		mime_type = "image/jpeg"
	elif extension == "webp":
		mime_type = "image/webp"
	return "data:%s;base64,%s" % [mime_type, encoded_body]

func _ensure_publish_progress_dialog() -> void:
	if publish_progress_dialog != null and is_instance_valid(publish_progress_dialog):
		return
	publish_progress_dialog = AcceptDialog.new()
	publish_progress_dialog.title = "Publishing Map"
	publish_progress_dialog.min_size = Vector2(460, 170)
	publish_progress_dialog.exclusive = true

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(420, 110)
	publish_progress_dialog.add_child(box)

	publish_progress_label = Label.new()
	publish_progress_label.text = "Preparing..."
	publish_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	publish_progress_label.add_theme_font_size_override("font_size", 14)
	box.add_child(publish_progress_label)

	publish_progress_bar = ProgressBar.new()
	publish_progress_bar.min_value = 0.0
	publish_progress_bar.max_value = 100.0
	publish_progress_bar.value = 0.0
	publish_progress_bar.show_percentage = false
	publish_progress_bar.custom_minimum_size = Vector2(0, 18)
	box.add_child(publish_progress_bar)
	add_child(publish_progress_dialog)

func _show_publish_progress(title: String, message: String, progress_ratio: float) -> void:
	_ensure_publish_progress_dialog()
	publish_progress_dialog.title = title
	if publish_progress_label:
		publish_progress_label.text = message
	if publish_progress_bar:
		publish_progress_bar.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	var ok_button := publish_progress_dialog.get_ok_button()
	if ok_button:
		ok_button.visible = false
	if not publish_progress_dialog.visible:
		publish_progress_dialog.popup_centered()

func _finish_publish_progress(success: bool, message: String) -> void:
	_ensure_publish_progress_dialog()
	publish_progress_dialog.title = "Publish Complete" if success else "Publish Failed"
	if publish_progress_label:
		publish_progress_label.text = message
	if publish_progress_bar:
		publish_progress_bar.value = 100.0 if success else 0.0
	var ok_button := publish_progress_dialog.get_ok_button()
	if ok_button:
		ok_button.visible = true
		ok_button.text = "Done" if success else "Close"
	if not publish_progress_dialog.visible:
		publish_progress_dialog.popup_centered()

func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _extract_cloud_map_id(payload: Variant) -> String:
	if payload is Dictionary:
		if payload.has("id"):
			return str(payload["id"]).strip_edges()
		if payload.has("map_id"):
			return str(payload["map_id"]).strip_edges()
		if payload.has("data"):
			return _extract_cloud_map_id(payload["data"])
	if payload is Array and not payload.is_empty():
		return _extract_cloud_map_id(payload[0])
	return ""

func _extract_cloud_map_version(payload: Variant, fallback: String = "") -> String:
	if payload is Dictionary:
		if payload.has("cloud_version_id"):
			return str(payload["cloud_version_id"]).strip_edges()
		if payload.has("version_id"):
			return str(payload["version_id"]).strip_edges()
		if payload.has("updated_at"):
			return str(payload["updated_at"]).strip_edges()
		if payload.has("data"):
			return _extract_cloud_map_version(payload["data"], fallback)
	if payload is Array and not payload.is_empty():
		return _extract_cloud_map_version(payload[0], fallback)
	return fallback.strip_edges()

func _save_map(folder: String) -> void:
	# Ensure directory
	UserSession.ensure_current_storage()
	# Ensure specific folder
	var folder_name := folder.get_file()
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir and not maps_dir.dir_exists(folder_name):
		maps_dir.make_dir(folder_name)
	var mode_settings := _collect_mode_settings_for_save(folder)

	var parent = placement_parent if placement_parent else self
	var blocks_data := []

	for child in parent.get_children():
		if child.is_in_group("studio_parts"):
			var shape_type: String = child.get_meta("shape_type", "Box")
			var col := Color.WHITE
			if child is MeshInstance3D:
				var mat = (child as MeshInstance3D).get_active_material(0) as StandardMaterial3D
				if mat:
					col = mat.albedo_color
			blocks_data.append({
				"name": child.get_meta("block_name", child.name),
				"px": snappedf(child.position.x, 0.01),
				"py": snappedf(child.position.y, 0.01),
				"pz": snappedf(child.position.z, 0.01),
				"rx": snappedf(child.rotation_degrees.x, 0.01),
				"ry": snappedf(child.rotation_degrees.y, 0.01),
				"rz": snappedf(child.rotation_degrees.z, 0.01),
				"sx": snappedf(child.scale.x, 0.01),
				"sy": snappedf(child.scale.y, 0.01),
				"sz": snappedf(child.scale.z, 0.01),
				"cr": snappedf(col.r, 0.01),
				"cg": snappedf(col.g, 0.01),
				"cb": snappedf(col.b, 0.01),
				"ca": snappedf(col.a, 0.01),
				"shape": shape_type,
				"material": child.get_meta("material_type", "Plastic"),
				"transparency": child.get_meta("transparency", 0.0),
				"can_collide": child.get_meta("can_collide", true),
				"deals_damage": child.get_meta("deals_damage", false),
				"damage_amount": child.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE),
				"is_spawn": child.get_meta("is_spawn", false)
			})

	var time_val = time_slider.value if time_slider else 12.0
	var runtime_objects := _collect_runtime_objects_for_save()
	_store_runtime_object_asset_files(runtime_objects, folder)
	var data = {
		"time_of_day": time_val,
		"player_settings": _get_current_player_settings(),
		"mode_settings": mode_settings,
		"blocks": blocks_data,
		"runtime_objects": runtime_objects
	}

	var file = FileAccess.open(folder + "/map_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[Studio] Saved to %s (%d blocks)" % [folder, blocks_data.size()])

	_save_map_meta(folder)

	# Take screenshot only if user hasn't set a custom icon
	if not custom_icon_set:
		var image := get_viewport().get_texture().get_image()
		if image:
			image.save_png(folder + "/icon.png")

func _load_map_from_folder(folder: String) -> void:
	var path := folder + "/map_data.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[Studio] Failed to parse map data.")
		return
	var data: Dictionary = json.data

	for block in _get_editor_parts():
		block.queue_free()
	_clear_runtime_object_nodes()
	await get_tree().process_frame

	if time_slider and data.has("time_of_day"):
		time_slider.value = data["time_of_day"]
	_apply_player_settings_to_ui(data.get("player_settings", _get_default_player_settings()))
	_apply_mode_settings_to_ui(data.get("mode_settings", _get_default_mode_settings()), folder)

	var blocks: Array = data.get("blocks", [])
	for block_data in blocks:
		var target_parent = placement_parent if placement_parent else self
		var pos := Vector3(
			block_data.get("px", 0.0),
			block_data.get("py", 0.0),
			block_data.get("pz", 0.0)
		)
		var col := Color(
			block_data.get("cr", 1.0),
			block_data.get("cg", 1.0),
			block_data.get("cb", 1.0),
			block_data.get("ca", 1.0)
		)
		var shape: String = block_data.get("shape", "Box")
		var deals_damage: bool = block_data.get("deals_damage", false)
		var damage_amount: float = float(block_data.get("damage_amount", DEFAULT_BLOCK_DAMAGE))
		if shape == "KillPart":
			shape = "Box"
			deals_damage = true
			damage_amount = maxf(damage_amount, 100.0)
		if block_data.get("is_spawn", false) and shape == "Box":
			shape = "Spawn"
		var mat_type: String = block_data.get("material", "Plastic")
		var transparency: float = block_data.get("transparency", 0.0)
		var can_collide: bool = block_data.get("can_collide", true)
		var block_name: String = block_data.get("name", shape + "_block")

		if shape == "Obby1" or shape == "Obby2":
			var scene_path = "res://maps/templates/" + shape.to_lower() + "/" + shape.to_lower() + ".tscn"
			if ResourceLoader.exists(scene_path):
				var scene = load(scene_path)
				var inst = scene.instantiate()
				inst.position = pos
				inst.rotation_degrees = Vector3(
					block_data.get("rx", 0.0), block_data.get("ry", 0.0), block_data.get("rz", 0.0)
				)
				var b_scale = Vector3(
					block_data.get("sx", 1.0), block_data.get("sy", 1.0), block_data.get("sz", 1.0)
				)
				inst.scale = b_scale
				inst.add_to_group("studio_parts")
				inst.set_meta("block_name", block_name)
				inst.set_meta("shape_type", shape)
				inst.set_meta("material_type", "Plastic")
				inst.set_meta("can_collide", false)
				inst.set_meta("transparency", 0.0)
				inst.set_meta("is_spawn", false)
				_update_block_collision(inst)
				target_parent.add_child(inst)
			continue

		var mesh_inst := _build_block_instance(shape, col, mat_type, transparency, can_collide, block_name)
		mesh_inst.position = pos
		mesh_inst.rotation_degrees = Vector3(
			block_data.get("rx", 0.0),
			block_data.get("ry", 0.0),
			block_data.get("rz", 0.0)
		)
		mesh_inst.scale = Vector3(
			block_data.get("sx", 1.0),
			block_data.get("sy", 1.0),
			block_data.get("sz", 1.0)
		)
		mesh_inst.set_meta("is_spawn", shape == "Spawn")
		mesh_inst.set_meta("deals_damage", deals_damage)
		mesh_inst.set_meta("damage_amount", damage_amount)
		_update_block_collision(mesh_inst)
		target_parent.add_child(mesh_inst)

	_load_runtime_objects_from_map(data.get("runtime_objects", []))
	print("[Studio] Loaded %d blocks from %s" % [blocks.size(), folder])
	_refresh_explorer()

func _normalize_map_name(raw_name: String) -> String:
	var clean_name := raw_name.strip_edges()
	if clean_name.is_empty():
		return "Untitled Place"
	return clean_name

func _sanitize_map_folder_name(display_name: String) -> String:
	var clean_name := _normalize_map_name(display_name)
	for illegal_char in ILLEGAL_MAP_NAME_CHARS:
		clean_name = clean_name.replace(illegal_char, "_")
	return clean_name

func _get_unique_map_folder_name(base_folder_name: String) -> String:
	var clean_folder_name := _sanitize_map_folder_name(base_folder_name)
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir == null or not maps_dir.dir_exists(clean_folder_name):
		return clean_folder_name

	var suffix := 2
	var candidate := "%s %d" % [clean_folder_name, suffix]
	while maps_dir.dir_exists(candidate):
		suffix += 1
		candidate = "%s %d" % [clean_folder_name, suffix]
	return candidate

func _load_map_meta(folder: String) -> Dictionary:
	if folder.is_empty():
		return {}
	var meta_path := folder + "/meta.json"
	if not FileAccess.file_exists(meta_path):
		return {}
	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	if meta_file == null:
		return {}
	var json := JSON.new()
	var parse_result := json.parse(meta_file.get_as_text())
	meta_file.close()
	if parse_result != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _save_map_meta(folder: String, description: String = "") -> void:
	var meta := _load_map_meta(folder)
	meta["name"] = _normalize_map_name(current_map_name)
	meta["draft_unsaved"] = false
	UserSession.unmark_deleted_game(str(meta.get("cloud_map_id", meta.get("map_id", ""))).strip_edges(), str(meta.get("name", "")).strip_edges())
	if not meta.has("creator") or str(meta.get("creator", "")).is_empty():
		meta["creator"] = UserSession.username if UserSession.is_logged_in else "Unknown"
	if description != "":
		meta["description"] = description
	elif not meta.has("description"):
		meta["description"] = ""

	var meta_file := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()

func _create_default_baseplate() -> void:
	var mesh_inst := _build_block_instance("Box", Color(0.45, 0.55, 0.45), "Plastic", 0.0, true, "Baseplate")
	mesh_inst.position = Vector3(0.0, -0.5, 0.0)
	mesh_inst.scale = Vector3(40.0, 1.0, 40.0)
	mesh_inst.set_meta("is_spawn", false)
	_update_block_collision(mesh_inst)

	var parent_node = placement_parent if placement_parent else self
	parent_node.add_child(mesh_inst)
	_refresh_explorer()

func _on_back_pressed() -> void:
	_cleanup_unsaved_draft_if_needed()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")

func _cleanup_unsaved_draft_if_needed() -> void:
	if current_map_folder.strip_edges().is_empty():
		return
	var meta: Dictionary = _load_map_meta(current_map_folder)
	if not bool(meta.get("draft_unsaved", false)):
		return
	if GameState.selected_map_folder == current_map_folder:
		GameState.selected_map_folder = ""
	_remove_dir_recursive(current_map_folder)

func _remove_dir_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var subdirs: Array[String] = []
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				subdirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name in files:
		dir.remove(file_name)
	for subdir_name in subdirs:
		_remove_dir_recursive(dir_path.path_join(subdir_name))
	var parent_dir := DirAccess.open(dir_path.get_base_dir())
	if parent_dir != null:
		parent_dir.remove(dir_path.get_file())

func _load_image_from_path(path: String) -> Image:
	var candidate_paths: Array[String] = [path]
	var global_path := ProjectSettings.globalize_path(path)
	if global_path != path:
		candidate_paths.append(global_path)

	for candidate in candidate_paths:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if not file:
			continue
		var bytes := file.get_buffer(file.get_length())
		file.close()
		if bytes.size() < 4:
			continue

		var img := Image.new()
		if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
			if img.load_png_from_buffer(bytes) == OK:
				return img
		if bytes[0] == 0xFF and bytes[1] == 0xD8:
			if img.load_jpg_from_buffer(bytes) == OK:
				return img
		if bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
			if img.load_webp_from_buffer(bytes) == OK:
				return img
		if img.load_png_from_buffer(bytes) == OK:
			return img
		if img.load_jpg_from_buffer(bytes) == OK:
			return img
		if img.load_webp_from_buffer(bytes) == OK:
			return img

	return null

func _create_placeholder_spawn_decal() -> Texture2D:
	var placeholder_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	placeholder_img.fill(Color(0.2, 0.8, 0.2, 0.6))
	for i in range(128):
		for j in range(128):
			if j >= 60 and j < 68:
				placeholder_img.set_pixel(i, j, Color(1, 1, 1, 0.9))
			if i >= 60 and i < 68:
				placeholder_img.set_pixel(i, j, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(placeholder_img)

func _load_spawn_decal_texture() -> Texture2D:
	var imported_texture := load(SPAWN_DECAL_PATH) as Texture2D
	if imported_texture:
		return imported_texture
	var img := _load_image_from_path(SPAWN_DECAL_PATH)
	if img:
		return ImageTexture.create_from_image(img)
	return _create_placeholder_spawn_decal()
