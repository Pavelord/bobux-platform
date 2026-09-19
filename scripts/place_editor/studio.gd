extends Control
const AudioFileLoader = preload("res://addons/roblox_runtime/audio_file_loader.gd")

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
# Layer 2 is reserved for player-to-player collision in Play mode. Editor
# handles must live on a separate ray-only layer or the character can stand on
# an invisible gizmo instead of touching the map.
const GIZMO_RAY_MASK: int = 1 << 3
const COLLISION_PREVIEW_MASK: int = 1 << 2
const ILLEGAL_MAP_NAME_CHARS: Array[String] = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
const DEFAULT_PLAYER_MOVE_SPEED: float = 16.0
const DEFAULT_PLAYER_SPRINT_MULTIPLIER: float = 1.25
const DEFAULT_PLAYER_JUMP_VELOCITY: float = 53.15
const ROBLOX_DEFAULT_WALK_SPEED: float = 16.0
const ROBLOX_DEFAULT_JUMP_POWER: float = 50.0
const DEFAULT_MODE_MUSIC_VOLUME: float = 0.65
const MODE_MUSIC_FILE_BASENAME: String = "mode_music"
const MODE_SKY_FILE_BASENAME: String = "mode_sky"
const DEFAULT_BLOCK_DAMAGE: float = 25.0
const SHAPE_OPTIONS: Array[String] = [
	"Select", "Box", "Sphere", "Cylinder", "Wedge", "CornerWedge",
	"Truss", "Water", "Spawn", "Checkpoint", "Teleport"
]
const CLOUD_INLINE_ASSET_MAX_BYTES: int = 24 * 1024 * 1024
const CLOUD_INLINE_ASSET_TOTAL_MAX_BYTES: int = 96 * 1024 * 1024
const CLOUD_INLINE_ASSET_MAX_TRACKS: int = 32
const CLOUD_MAP_ASSET_UPLOAD_CONCURRENCY: int = 3
const CLOUD_MAP_ASSET_MAX_BYTES: int = 50 * 1024 * 1024
const CLOUD_MAP_ASSET_FAILURES_KEY: String = "__bobux_publish_asset_failures"
const CLOUD_THUMBNAIL_MAX_DIMENSION: int = 320
const CLOUD_THUMBNAIL_FALLBACK_MAX_BYTES: int = 256 * 1024
const STUDIO_AUTOSAVE_INTERVAL_SECONDS: float = 300.0
const STUDIO_AUTOSAVE_FOLDER: String = "user://autosave/studio_latest"
const STUDIO_MODEL_CACHE_FOLDER: String = "user://studio_model_cache"
# Keep editor input responsive while large imported places are copied into the
# isolated Play session. These batches target sub-50 ms work slices on modest
# PCs instead of minimizing the number of rendered preparation frames.
const PLAYTEST_SCRIPT_START_BATCH: int = 24
const PLAYTEST_SNAPSHOT_BATCH: int = 32
const STUDIO_PLAYTEST_PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const STUDIO_PLAYTEST_COLLISION_MASK: int = 1 << 2

# ── RBXL importer integration ───────────────────────────────────────────────
# preload the runtime importer that converts .rbxl / .rbxlx place files into
# studio_parts blocks (see addons/rbxl_importer/).
const RbxlRuntimeImporter = preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
const RbxlWedgeMeshBuilder = preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")
const RobloxGuiRuntime = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")
const RobloxSkyMaterial = preload("res://addons/rbxl_importer/roblox_sky_material.gd")
const RobloxMeshJsonLoader = preload("res://addons/rbxl_importer/roblox_mesh_json_loader.gd")
const RbxlMaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const RbxlServerImporterScript = preload("res://addons/rbxl_importer/importer.gd")
const RBXL_RUNTIME_OBJECT_GROUP: String = "studio_runtime_objects"
const RBXL_REMOTE_PREFETCH_SETTING: String = "bobux/prefetch_remote_rbxl_assets"

# ── Roblox Studio emulation (live DataModel, Explorer, Properties) ──────────
# These modules turn the editor into a Roblox Studio look-alike: a real
# DataModel node tree (Workspace/Players/Lighting/...), a recursive Explorer
# that mirrors it, and a categorized Properties panel. See
# addons/roblox_studio/.
const RobloxDataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")
const RobloxExplorerClass = preload("res://addons/roblox_studio/roblox_explorer.gd")
const RobloxPropertiesClass = preload("res://addons/roblox_studio/roblox_properties.gd")
const RobloxTerrainEditorClass = preload("res://addons/roblox_studio/roblox_terrain_editor.gd")
const RobloxCharacterFactoryClass = preload("res://addons/roblox_studio/roblox_character_factory.gd")
const RuntimeObjLoaderClass = preload("res://addons/roblox_studio/runtime_obj_loader.gd")
const RobloxInventoryControllerClass = preload("res://addons/roblox_runtime/roblox_inventory_controller.gd")
const StudioGuideDataClass = preload("res://scripts/creation_hub/studio_guide_data.gd")

@export var camera: Camera3D
@export var placement_parent: Node3D
@export var sun_light: DirectionalLight3D

## Live Roblox DataModel node (game). Holds Workspace, Players, Lighting, … as
## real child nodes so the Explorer and Lua engine share one source of truth.
var data_model: RobloxDataModelClass = null
## Helper that builds the Explorer tree from `data_model`. Stateless across
## rebuilds (collapsed/expanded state is remembered internally).
var roblox_explorer: RobloxExplorerClass = null
## Helper that builds the Properties panel for the current selection.
var roblox_properties: RobloxPropertiesClass = null
var roblox_terrain_editor: RobloxTerrainEditorClass = null
var explorer_selected_node: Node = null
var syncing_explorer_selection: bool = false
## True once the DataModel has been wired into the scene. Guards against
## `_refresh_explorer` running before services exist (e.g. during _build_*).
var roblox_data_model_ready: bool = false
var rbxl_material_cache := RbxlMaterialCache.new()

var velocity = Vector3.ZERO
var is_dragging = false
var is_orbit_dragging: bool = false
var orbit_pivot: Vector3 = Vector3.ZERO
var ray_length = 1000.0
var current_color = Color.WHITE
var current_shape: String = "Select" # Select, Box, Sphere, Wedge, Cylinder
var current_material_type: String = "Plastic"
var selected_block: Node3D = null
var is_dragging_block: bool = false
var drag_plane: Plane

# UI references built at runtime
var explorer_tree: Tree = null
var explorer_search_edit: LineEdit = null
var explorer_filter_text: String = ""
var inspector_panel: VBoxContainer = null
var player_settings_panel: VBoxContainer = null
var authored_player_settings: Dictionary = {}
var atmosphere_settings_panel: VBoxContainer = null
var toolbar_hbox: HBoxContainer = null
var name_edit: LineEdit = null
var transparency_slider: HSlider = null
var can_collide_check: CheckBox = null
var damage_enabled_check: CheckBox = null
var damage_amount_spin: SpinBox = null
var material_option: OptionButton = null
var color_picker: Button = null
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
var studio_music_dialog: AcceptDialog = null
var studio_music_player: AudioStreamPlayer = null
var studio_music_volume := DEFAULT_MODE_MUSIC_VOLUME
var studio_music_track := 0
var sky_file_dialog: FileDialog = null
var rbxl_file_dialog: FileDialog = null
var last_rbxl_import_report: Dictionary = {}
var toolbox_dialog: AcceptDialog = null
var toolbox_asset_entries: Array[Dictionary] = []
var toolbox_active_category: String = "3D Assets"
var toolbox_cloud_model_cache: Array[Dictionary] = []
var toolbox_cloud_models_loaded: bool = false
var toolbox_cloud_models_loading: bool = false
var publish_progress_dialog: AcceptDialog = null
var publish_progress_label: Label = null
var publish_progress_bar: ProgressBar = null
var mobile_studio_controls_layer: CanvasLayer = null
var mobile_studio_joystick_base: Panel = null
var mobile_studio_joystick_knob: Panel = null
var mobile_studio_move_vector: Vector2 = Vector2.ZERO
var mobile_studio_joystick_touch_index: int = -1
var mobile_studio_look_touch_active: bool = false
var mobile_studio_action_panel: PanelContainer = null
var mobile_studio_action_buttons: Dictionary = {}
var mobile_studio_view_touches: Dictionary = {}
var mobile_studio_primary_touch_index: int = -1
var mobile_studio_primary_touch_origin: Vector2 = Vector2.ZERO
var mobile_studio_primary_touch_moved: bool = false
var mobile_studio_pinch_distance: float = 0.0
var mobile_studio_force_runtime_for_tests: bool = false
var studio_viewport_mouse_position: Vector2 = Vector2.ZERO

# Map data
var current_map_name: String = "Untitled Place"
var current_map_folder: String = ""
var custom_icon_set: bool = false
var current_music_source_paths: Array[String] = []
var current_sky_source_path: String = ""
var current_imported_sound_assets: Array[Dictionary] = []
var current_roblox_environment_settings: Dictionary = {}
var current_roblox_place_manifest: Dictionary = {}
var roblox_gui_preview_generation: int = 0

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
var box_select_additive: bool = false
var box_select_pending_block: Node3D = null
var block_clipboard: Array = []
var undo_history: Array = []
var redo_history: Array = []
var is_restoring_history: bool = false
var studio_playtest_active: bool = false
var studio_playtest_paused: bool = false
var studio_playtest_snapshot: Dictionary = {}
var studio_playtest_generation: int = 0
var studio_playtest_player: CharacterBody3D = null
var studio_inventory_controller: CanvasLayer = null
var studio_test_control_buttons: Dictionary = {}
var studio_playtest_control_state: Array[Dictionary] = []
var studio_playtest_respawn_triggers: Array[Area3D] = []
var studio_autosave_timer: Timer = null
var studio_operation_busy: bool = false
var studio_operation_name: String = ""

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not camera:
		camera = Camera3D.new()
		placement_parent.get_parent().add_child(camera)
		camera.position.y = 5.0
		camera.position.z = 10.0
	_reset_studio_camera_interpolation()

	_build_main_white_layout()
	LuaScriptEngine.script_message.connect(_on_lua_script_message)
	_setup_roblox_data_model()
	_build_explorer_panel()
	_build_inspector_panel()
	_setup_rbxl_import_dialog()
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
		show_grid_enabled = false
		_toggle_grid_visibility(false)
		_load_map_from_folder(current_map_folder)
		# Check if icon already exists (user may have set a custom one)
		if FileAccess.file_exists(current_map_folder + "/icon.png"):
			custom_icon_set = true
	_refresh_studio_title_text()

	# If no blocks loaded, create a default baseplate as a studio_parts object
	var has_blocks := not _get_editor_parts().is_empty()
	if not has_blocks:
		_create_default_baseplate()
	_commit_editor_history("Initial", false)
	_setup_mobile_studio_controls()
	_setup_studio_autosave()

func _process(delta: float) -> void:
	_process_movement(delta)
	_update_selection_highlight()
	_update_transform_gizmo()

func _input(event: InputEvent) -> void:
	if not studio_playtest_active or not is_instance_valid(studio_inventory_controller) or _is_text_input_focused():
		return
	# CanvasLayer lives in the embedded viewport. Route game shortcuts before
	# editor focus navigation consumes Tab or prevents the viewport receiving it.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("interact") and preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd").activate_nearest_prompt(placement_parent, studio_playtest_player, LuaScriptEngine):
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_TAB, KEY_QUOTELEFT, KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
			studio_inventory_controller._unhandled_input(event)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_L:
		_focus_command_bar()
		get_viewport().set_input_as_handled()
		return
	# While Test is running the player camera and character own viewport input.
	# Returning without marking the event handled still lets the CharacterBody3D
	# receive it, while preventing editor selection/orbit from running underneath.
	if studio_playtest_active:
		return
	var text_input_focused := _is_text_input_focused()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_dragging = true
				is_orbit_dragging = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				is_dragging = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if text_input_focused:
			return

		# The embedded SubViewport normally receives this through gui_input. Keep
		# an unhandled-input path as well for platform/window configurations where
		# Godot forwards the click directly to the scene root.
		if _handle_terrain_viewport_input(event):
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and (event.alt_pressed or is_orbit_dragging):
			if event.pressed:
				_begin_studio_orbit()
			else:
				is_orbit_dragging = false
				if not is_dragging:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if event.button_index == MOUSE_BUTTON_LEFT and not is_dragging:
			if event.pressed:
				if current_shape == "Select":
					if current_editor_tool != "select":
						var gizmo_result := _get_ray_intersection(GIZMO_RAY_MASK)
						var gizmo_handle := _get_gizmo_handle_from_ray_result(gizmo_result)
						if gizmo_handle:
							_begin_gizmo_drag(gizmo_handle)
							return

					var clicked_block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
					_begin_box_selection(_get_studio_mouse_position(), clicked_block, event.ctrl_pressed)
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
		if _handle_terrain_viewport_input(event):
			get_viewport().set_input_as_handled()
			return
		if is_dragging:
			_apply_camera_look_delta(event.relative)
		elif is_orbit_dragging:
			_apply_studio_orbit_delta(event.relative)
		elif is_gizmo_dragging and is_instance_valid(selected_block):
			_update_gizmo_drag(_get_studio_mouse_position())
		elif is_box_selecting:
			box_select_current = _get_studio_mouse_position()
			_update_selection_box_visual()
		return

	if event is InputEventKey and text_input_focused:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.ctrl_pressed:
			match key_event.keycode:
				KEY_1:
					_set_shape("Select")
					return
				KEY_2:
					_set_shape("Select")
					_set_transform_mode("move")
					return
				KEY_3:
					_set_shape("Select")
					_set_transform_mode("scale")
					return
				KEY_4:
					_set_shape("Select")
					_set_transform_mode("rotate")
					return
				KEY_5:
					_set_shape("Select")
					_set_transform_mode("transform")
					return
				KEY_6:
					_set_shape("Select")
					_set_transform_mode("geometric")
					return
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
					if explorer_selected_node != null and is_instance_valid(explorer_selected_node) and not explorer_selected_node.is_in_group("studio_parts"):
						_duplicate_node(explorer_selected_node)
					else:
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
				if explorer_selected_node != null and is_instance_valid(explorer_selected_node) and not bool(explorer_selected_node.get_meta("is_roblox_service", false)):
					_delete_node(explorer_selected_node)
				else:
					_delete_selected_blocks()
			KEY_ESCAPE:
				_clear_selection()
			KEY_F2:
				if explorer_selected_node != null and is_instance_valid(explorer_selected_node) and not bool(explorer_selected_node.get_meta("is_roblox_service", false)):
					_rename_item_dialog(explorer_selected_node)
				elif selected_block and is_instance_valid(selected_block):
					_rename_item_dialog(selected_block)
			KEY_F:
				_focus_camera_on_selection()
			KEY_KP_1:
				_set_studio_axis_view(Vector3.FORWARD)
			KEY_KP_3:
				_set_studio_axis_view(Vector3.RIGHT)
			KEY_KP_7:
				_set_studio_axis_view(Vector3.DOWN)
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
	if studio_playtest_active:
		velocity = Vector3.ZERO
		return
	if _is_text_input_focused():
		velocity = Vector3.ZERO
		return
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mobile_studio_move_vector.length() > 0.05:
		input_dir = mobile_studio_move_vector

	var up_dir = 0.0
	if Input.is_physical_key_pressed(KEY_E): up_dir += 1.0
	if Input.is_physical_key_pressed(KEY_Q): up_dir -= 1.0

	var viewport_has_keyboard_focus := viewport_container_node == null or not is_instance_valid(viewport_container_node) or viewport_container_node.has_focus() or is_dragging
	if not viewport_has_keyboard_focus and mobile_studio_move_vector.length() <= 0.05:
		velocity = velocity.lerp(Vector3.ZERO, ACCELERATION * delta)
		return

	var direction = (camera.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction += camera.transform.basis.y * up_dir

	var current_speed = MAX_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		current_speed *= 2.5
	if mobile_studio_move_vector.length() > 0.05:
		current_speed *= 0.82

	if direction.length() > 0.001:
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

func _apply_camera_look_delta(relative: Vector2) -> void:
	if camera == null:
		return
	camera.rotation.y -= relative.x * MOUSE_SENSITIVITY
	camera.rotation.x = clamp(camera.rotation.x - relative.y * MOUSE_SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
	_reset_studio_camera_interpolation()

func _begin_studio_orbit() -> void:
	if camera == null:
		return
	orbit_pivot = _get_selection_pivot() if not _get_valid_selected_blocks().is_empty() else _get_camera_orbit_fallback_pivot()
	is_orbit_dragging = true
	is_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_studio_orbit_delta(relative: Vector2) -> void:
	if camera == null:
		return
	var offset := camera.global_position - orbit_pivot
	if offset.length_squared() < 0.0001:
		offset = Vector3(0, 0, 8)
	var yaw := Basis(Vector3.UP, -relative.x * MOUSE_SENSITIVITY)
	offset = yaw * offset
	var right := camera.global_basis.x.normalized()
	var pitch := Basis(right, -relative.y * MOUSE_SENSITIVITY)
	var next_offset := pitch * offset
	if absf(next_offset.normalized().dot(Vector3.UP)) < 0.985:
		offset = next_offset
	camera.global_position = orbit_pivot + offset
	camera.look_at(orbit_pivot, Vector3.UP)
	velocity = Vector3.ZERO
	_reset_studio_camera_interpolation()

func _get_camera_orbit_fallback_pivot() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var result := _get_ray_intersection(SELECTION_RAY_MASK)
	var hit_position = result.get("position", null)
	if hit_position is Vector3:
		return hit_position
	return camera.global_position + (-camera.global_basis.z.normalized() * 16.0)

func _set_studio_mouse_from_viewport_container(local_position: Vector2) -> void:
	studio_viewport_mouse_position = _viewport_container_to_subviewport_position(local_position)

func _get_studio_mouse_position() -> Vector2:
	if viewport_container_node != null and is_instance_valid(viewport_container_node) and camera != null:
		var main_mouse := get_viewport().get_mouse_position()
		var local_mouse := viewport_container_node.get_global_transform_with_canvas().affine_inverse() * main_mouse
		if Rect2(Vector2.ZERO, viewport_container_node.size).has_point(local_mouse):
			_set_studio_mouse_from_viewport_container(local_mouse)
	return studio_viewport_mouse_position

func _viewport_container_to_subviewport_position(local_position: Vector2) -> Vector2:
	if viewport_container_node == null or not is_instance_valid(viewport_container_node):
		return local_position
	var container_size := viewport_container_node.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local_position
	var viewport_size := container_size
	if camera != null and camera.get_viewport() != null:
		viewport_size = Vector2(camera.get_viewport().size)
	return Vector2(
		clampf(local_position.x / container_size.x, 0.0, 1.0) * viewport_size.x,
		clampf(local_position.y / container_size.y, 0.0, 1.0) * viewport_size.y
	)

func _on_studio_viewport_gui_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if _is_mobile_studio_runtime() and _handle_mobile_studio_viewport_input(event):
		accept_event()
		return
	# During Play the embedded SubViewport owns pointer input. Do not consume the
	# event here: SubViewportContainer will forward it to the player camera and
	# runtime GUI after this handler returns.
	if studio_playtest_active:
		if event is InputEventMouse:
			var pointer_viewport := _get_studio_subviewport()
			pointer_viewport.set_meta("bobux_pointer_position", event.position * Vector2(pointer_viewport.size) / viewport_container_node.size.max(Vector2.ONE))
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			get_viewport().gui_release_focus()
			if viewport_container_node != null:
				viewport_container_node.grab_focus()
			if event.button_index == MOUSE_BUTTON_LEFT:
				var play_viewport := _get_studio_subviewport()
				var viewport_position: Vector2 = event.position * Vector2(play_viewport.size) / viewport_container_node.size.max(Vector2.ONE)
				if preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd").activate_click(play_viewport.get_camera_3d(), viewport_position, placement_parent, studio_playtest_player, LuaScriptEngine):
					accept_event()
					return
		var route_to_camera := false
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			route_to_camera = button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		elif event is InputEventMouseMotion:
			route_to_camera = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (
				studio_playtest_player != null
				and is_instance_valid(studio_playtest_player)
				and bool(studio_playtest_player.get("_embedded_camera_dragging"))
			)
		if route_to_camera and studio_playtest_player != null and is_instance_valid(studio_playtest_player):
			if studio_playtest_player.has_method("handle_embedded_playtest_pointer_input"):
				studio_playtest_player.call("handle_embedded_playtest_pointer_input", event)
			else:
				studio_playtest_player.call("_unhandled_input", event)
			accept_event()
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		_set_studio_mouse_from_viewport_container(mouse_button.position)
		if mouse_button.pressed:
			get_viewport().gui_release_focus()
			if viewport_container_node:
				viewport_container_node.grab_focus()
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera_to_mouse(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP, mouse_button.position)
			accept_event()
			return
		if _handle_terrain_viewport_input(mouse_button):
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			is_dragging = mouse_button.pressed
			if is_dragging:
				is_orbit_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_button.pressed else Input.MOUSE_MODE_VISIBLE
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and (mouse_button.alt_pressed or is_orbit_dragging):
			if mouse_button.pressed:
				_begin_studio_orbit()
			else:
				is_orbit_dragging = false
				if not is_dragging:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not is_dragging:
			if mouse_button.pressed:
				if current_shape == "Select":
					if current_editor_tool != "select":
						var gizmo_result := _get_ray_intersection(GIZMO_RAY_MASK)
						var gizmo_handle := _get_gizmo_handle_from_ray_result(gizmo_result)
						if gizmo_handle:
							_begin_gizmo_drag(gizmo_handle)
							accept_event()
							return

					var clicked_block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
					_begin_box_selection(_get_studio_mouse_position(), clicked_block, mouse_button.ctrl_pressed)
				else:
					_attempt_placement()
			else:
				if is_box_selecting:
					_complete_box_selection()
				if is_gizmo_dragging:
					_end_gizmo_drag()
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE and mouse_button.pressed:
			_attempt_deletion()
			accept_event()
			return
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_set_studio_mouse_from_viewport_container(motion.position)
		if _handle_terrain_viewport_input(motion):
			accept_event()
			return
		if is_dragging:
			_apply_camera_look_delta(motion.relative)
			accept_event()
		elif is_orbit_dragging:
			_apply_studio_orbit_delta(motion.relative)
			accept_event()
		elif is_gizmo_dragging and is_instance_valid(selected_block):
			_update_gizmo_drag(_get_studio_mouse_position())
			accept_event()
		elif is_box_selecting:
			box_select_current = _get_studio_mouse_position()
			_update_selection_box_visual()
			accept_event()

func _handle_terrain_viewport_input(event: InputEvent) -> bool:
	if current_editor_tool != "terrain" or roblox_terrain_editor == null or not roblox_terrain_editor.is_brush_active():
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or button.alt_pressed:
			return false
		if button.pressed:
			return roblox_terrain_editor.begin_stroke(_terrain_brush_world_position())
		roblox_terrain_editor.end_stroke()
		return true
	if event is InputEventMouseMotion:
		return roblox_terrain_editor.continue_stroke(_terrain_brush_world_position())
	return false

func _terrain_brush_world_position() -> Vector3:
	var result := _get_ray_intersection(SELECTION_RAY_MASK)
	if result.get("position", null) is Vector3:
		return result.get("position") as Vector3
	return _get_editor_drop_position(12.0, false)

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
	_build_mobile_studio_action_bar()
	_apply_mobile_studio_layout()

func _is_mobile_studio_runtime() -> bool:
	if mobile_studio_force_runtime_for_tests:
		return true
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	var mobile_runtime := get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))

func _on_mobile_studio_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if mobile_studio_joystick_touch_index >= 0:
				return
			mobile_studio_joystick_touch_index = touch.index
			_update_mobile_studio_joystick(touch.position)
		elif touch.index == mobile_studio_joystick_touch_index:
			mobile_studio_joystick_touch_index = -1
			_reset_mobile_studio_joystick()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == mobile_studio_joystick_touch_index:
			_update_mobile_studio_joystick(drag.position)
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
		_apply_camera_look_delta(drag.relative)
	elif event is InputEventMouseButton:
		mobile_studio_look_touch_active = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and mobile_studio_look_touch_active:
		var motion := event as InputEventMouseMotion
		_apply_camera_look_delta(motion.relative)


func _handle_mobile_studio_viewport_input(event: InputEvent) -> bool:
	if studio_playtest_active:
		return false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_set_studio_mouse_from_viewport_container(touch.position)
		if touch.pressed:
			mobile_studio_view_touches[touch.index] = touch.position
			if mobile_studio_primary_touch_index < 0:
				mobile_studio_primary_touch_index = touch.index
				mobile_studio_primary_touch_origin = touch.position
				mobile_studio_primary_touch_moved = false
				if _handle_terrain_viewport_input(_screen_touch_as_mouse_button(touch)):
					return true
				if current_shape == "Select" and current_editor_tool != "select":
					var gizmo_result := _get_ray_intersection(GIZMO_RAY_MASK)
					var gizmo_handle := _get_gizmo_handle_from_ray_result(gizmo_result)
					if gizmo_handle != null:
						_begin_gizmo_drag(gizmo_handle)
			else:
				mobile_studio_primary_touch_moved = true
			_update_mobile_studio_pinch_distance()
			return true

		var was_primary := touch.index == mobile_studio_primary_touch_index
		if current_editor_tool == "terrain" and roblox_terrain_editor != null and roblox_terrain_editor.is_brush_active():
			roblox_terrain_editor.end_stroke()
		if was_primary and is_gizmo_dragging:
			_end_gizmo_drag()
		elif was_primary and not mobile_studio_primary_touch_moved and mobile_studio_view_touches.size() <= 1:
			_handle_mobile_studio_viewport_tap()
		mobile_studio_view_touches.erase(touch.index)
		if was_primary:
			mobile_studio_primary_touch_index = -1
			for remaining_index in mobile_studio_view_touches.keys():
				mobile_studio_primary_touch_index = int(remaining_index)
				mobile_studio_primary_touch_origin = mobile_studio_view_touches[remaining_index]
				mobile_studio_primary_touch_moved = true
				break
		_update_mobile_studio_pinch_distance()
		return true

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_set_studio_mouse_from_viewport_container(drag.position)
		mobile_studio_view_touches[drag.index] = drag.position
		if mobile_studio_view_touches.size() >= 2:
			var new_distance := _mobile_studio_touch_distance()
			if mobile_studio_pinch_distance > 0.0 and new_distance > 0.0:
				_zoom_mobile_studio_camera(new_distance - mobile_studio_pinch_distance)
			mobile_studio_pinch_distance = new_distance
			mobile_studio_primary_touch_moved = true
			return true
		if drag.index != mobile_studio_primary_touch_index:
			return true
		if drag.position.distance_to(mobile_studio_primary_touch_origin) > 10.0:
			mobile_studio_primary_touch_moved = true
		if current_editor_tool == "terrain" and roblox_terrain_editor != null and roblox_terrain_editor.is_brush_active():
			roblox_terrain_editor.continue_stroke(_terrain_brush_world_position())
		elif is_gizmo_dragging and selected_block != null and is_instance_valid(selected_block):
			_update_gizmo_drag(studio_viewport_mouse_position)
		else:
			_apply_camera_look_delta(drag.relative * 0.82)
		return true
	return false


func _screen_touch_as_mouse_button(touch: InputEventScreenTouch) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = touch.pressed
	button.position = touch.position
	return button


func _handle_mobile_studio_viewport_tap() -> void:
	if current_shape == "Select":
		var clicked_block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
		if clicked_block != null:
			_set_selection([clicked_block])
		else:
			_clear_selection()
	else:
		_attempt_placement()


func _mobile_studio_touch_distance() -> float:
	if mobile_studio_view_touches.size() < 2:
		return 0.0
	var positions: Array = mobile_studio_view_touches.values()
	return (positions[0] as Vector2).distance_to(positions[1] as Vector2)


func _update_mobile_studio_pinch_distance() -> void:
	mobile_studio_pinch_distance = _mobile_studio_touch_distance()


func _zoom_mobile_studio_camera(distance_delta: float) -> void:
	if camera == null or absf(distance_delta) < 0.1:
		return
	var zoom_amount := clampf(distance_delta * 0.028, -4.0, 4.0)
	camera.global_position += -camera.global_basis.z.normalized() * zoom_amount
	_reset_studio_camera_interpolation()


func _build_mobile_studio_action_bar() -> void:
	if mobile_studio_controls_layer == null or mobile_studio_action_panel != null:
		return
	mobile_studio_action_panel = PanelContainer.new()
	mobile_studio_action_panel.name = "StudioMobileActionBar"
	mobile_studio_action_panel.anchor_left = 0.0
	mobile_studio_action_panel.anchor_top = 1.0
	mobile_studio_action_panel.anchor_right = 1.0
	mobile_studio_action_panel.anchor_bottom = 1.0
	mobile_studio_action_panel.offset_left = 216.0
	mobile_studio_action_panel.offset_top = -66.0
	mobile_studio_action_panel.offset_right = -8.0
	mobile_studio_action_panel.offset_bottom = -8.0
	mobile_studio_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	mobile_studio_action_panel.add_theme_stylebox_override(
		"panel",
		_studio_panel_style(Color(0.96, 0.97, 0.98, 0.96), Color(0.55, 0.58, 0.62, 0.9), 1, 5)
	)
	mobile_studio_controls_layer.add_child(mobile_studio_action_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "ActionScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 12
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	mobile_studio_action_panel.add_child(scroll)
	var row := HBoxContainer.new()
	row.name = "ActionRow"
	row.add_theme_constant_override("separation", 3)
	scroll.add_child(row)
	for action_name in [
		"Select", "Move", "Scale", "Rotate", "Part", "Undo", "Redo",
		"Explorer", "Properties", "Toolbox", "Save", "Publish", "Play", "Stop", "Reset"
	]:
		var button := _create_ribbon_button(action_name, 54.0 if action_name in ["Explorer", "Properties", "Publish"] else 48.0)
		button.custom_minimum_size.y = 50.0
		button.pressed.connect(_on_mobile_studio_action_pressed.bind(action_name))
		row.add_child(button)
		mobile_studio_action_buttons[action_name] = button


func _on_mobile_studio_action_pressed(action_name: String) -> void:
	match action_name:
		"Select":
			_set_shape("Select")
		"Move", "Scale", "Rotate":
			_set_shape("Select")
			_set_transform_mode(action_name.to_lower())
		"Part":
			_place_shape_from_ribbon("Box")
		"Undo":
			_undo_editor_action()
		"Redo":
			_redo_editor_action()
		"Explorer", "Properties", "Toolbox":
			_toggle_mobile_studio_panel(action_name.to_lower())
		"Save":
			_on_save_button_pressed()
		"Publish":
			_on_publish_pressed()
		"Play", "Stop", "Reset":
			_on_studio_test_control_pressed(action_name)


func _toggle_mobile_studio_panel(window_name: String) -> void:
	if window_name == "toolbox":
		var next_visible := toolbox_dock_panel != null and not toolbox_dock_panel.visible
		if right_side != null:
			right_side.visible = false
		if toolbox_dock_panel != null:
			toolbox_dock_panel.visible = next_visible
		return
	if toolbox_dock_panel != null:
		toolbox_dock_panel.visible = false
	if right_side == null:
		return
	var target := explorer_dock_panel if window_name == "explorer" else properties_dock_panel
	var next_visible := not (right_side.visible and target != null and target.visible)
	right_side.visible = next_visible
	if explorer_dock_panel != null:
		explorer_dock_panel.visible = next_visible and window_name == "explorer"
	if properties_dock_panel != null:
		properties_dock_panel.visible = next_visible and window_name == "properties"


func _apply_mobile_studio_layout() -> void:
	if not _is_mobile_studio_runtime():
		return
	if toolbox_dock_panel != null:
		toolbox_dock_panel.custom_minimum_size.x = 250.0
		toolbox_dock_panel.visible = false
	if right_side != null:
		right_side.custom_minimum_size.x = 260.0
		right_side.visible = false
	var status_bar := main_container.get_node_or_null("StatusBar") as Control if main_container != null else null
	if status_bar != null:
		status_bar.visible = false

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
	var parent: Node = placement_parent if placement_parent else self
	# Imported places also contain thousands of script/template/service nodes.
	# Walking that entire hierarchy used to block the first Play frame merely to
	# find the comparatively small set of editable geometry. Group lookup keeps
	# this operation proportional to actual Studio parts.
	if is_inside_tree():
		for candidate in get_tree().get_nodes_in_group("studio_parts"):
			if candidate is Node3D and is_instance_valid(candidate) \
			and not candidate.is_queued_for_deletion() \
			and (candidate == parent or parent.is_ancestor_of(candidate)):
				parts.append(candidate as Node3D)
		return parts
	_collect_editor_parts_recursive(parent, parts)
	return parts

func _collect_editor_parts_recursive(root: Node, out_parts: Array[Node3D]) -> void:
	for child in root.get_children():
		if child is Node3D and child.is_in_group("studio_parts") and not child.is_queued_for_deletion():
			out_parts.append(child as Node3D)
		_collect_editor_parts_recursive(child, out_parts)

func _set_selection(blocks: Array) -> void:
	var filtered: Array[Node3D] = []
	for block in blocks:
		if block is Node3D and is_instance_valid(block) and block.is_in_group("studio_parts") and not filtered.has(block):
			filtered.append(block)

	selected_blocks = filtered
	selected_block = selected_blocks[0] if not selected_blocks.is_empty() else null
	explorer_selected_node = null
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
	explorer_selected_node = null
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
	if _is_studio_editing_locked():
		return
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
	var parent: Node = placement_parent if placement_parent else self
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
	var color := _get_bobux_block_color(block, Color.WHITE)
	var serialized := {
		"name": str(block.get_meta("block_name", block.name)),
		"shape": shape_type,
		"position": block.position,
		"rotation_degrees": block.rotation_degrees,
		"scale": block.scale,
		"color": color,
		"material": str(block.get_meta("material_type", "Plastic")),
		"transparency": float(block.get_meta("transparency", 0.0)),
		"can_collide": bool(block.get_meta("can_collide", true)),
		"anchored": bool(block.get_meta("anchored", true)),
		"deals_damage": bool(block.get_meta("deals_damage", false)),
		"damage_amount": float(block.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)),
		"is_spawn": bool(block.get_meta("is_spawn", false))
	}
	if block.has_meta("bobux_mesh_resource_asset"):
		serialized["bobux_mesh_resource_asset"] = str(block.get_meta("bobux_mesh_resource_asset", ""))
	if block.has_meta("bobux_ai_effects"):
		serialized["bobux_ai_effects"] = block.get_meta("bobux_ai_effects", []).duplicate(true)
	if block.has_meta("bobux_ai_interaction"):
		serialized["bobux_ai_interaction"] = block.get_meta("bobux_ai_interaction", {}).duplicate(true)
	for physics_key in [
		"bobux_physics_mode", "bobux_physics_mass", "bobux_physics_friction",
		"bobux_physics_bounce", "bobux_physics_gravity_scale",
		"bobux_physics_linear_damp", "bobux_physics_angular_damp"
	]:
		if block.has_meta(physics_key):
			serialized[physics_key] = block.get_meta(physics_key)
	return serialized

func _create_block_from_clipboard(block_data: Dictionary, paste_offset: Vector3, preserve_original_name: bool = false) -> MeshInstance3D:
	var shape_type: String = str(block_data.get("shape", "Box"))
	if bool(block_data.get("is_spawn", false)) and shape_type == "Box":
		shape_type = "Spawn"
	var color: Color = _color_from_block_data(block_data, Color.WHITE)
	var material_type: String = str(block_data.get("material", "Plastic"))
	var transparency: float = float(block_data.get("transparency", 0.0))
	var can_collide: bool = bool(block_data.get("can_collide", true))
	var original_name: String = str(block_data.get("name", shape_type)).strip_edges()
	var block_name := original_name if preserve_original_name else _make_unique_block_copy_name(original_name)
	var mesh_inst := _build_block_instance(shape_type, color, material_type, transparency, can_collide, block_name)
	mesh_inst.position = _vector3_from_variant(block_data.get("position", Vector3.ZERO), Vector3.ZERO) + paste_offset
	mesh_inst.rotation_degrees = _vector3_from_variant(block_data.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	mesh_inst.scale = _vector3_from_variant(block_data.get("scale", Vector3.ONE), Vector3.ONE)
	mesh_inst.set_meta("anchored", bool(block_data.get("anchored", true)))
	mesh_inst.set_meta("is_spawn", shape_type == "Spawn")
	mesh_inst.set_meta("deals_damage", bool(block_data.get("deals_damage", false)))
	mesh_inst.set_meta("damage_amount", float(block_data.get("damage_amount", DEFAULT_BLOCK_DAMAGE)))
	if block_data.get("bobux_ai_effects", []) is Array:
		mesh_inst.set_meta("bobux_ai_effects", (block_data.get("bobux_ai_effects", []) as Array).duplicate(true))
	if block_data.get("bobux_ai_interaction", {}) is Dictionary:
		mesh_inst.set_meta("bobux_ai_interaction", (block_data.get("bobux_ai_interaction", {}) as Dictionary).duplicate(true))
	for physics_key in [
		"bobux_physics_mode", "bobux_physics_mass", "bobux_physics_friction",
		"bobux_physics_bounce", "bobux_physics_gravity_scale",
		"bobux_physics_linear_damp", "bobux_physics_angular_damp"
	]:
		if block_data.has(physics_key):
			mesh_inst.set_meta(physics_key, block_data[physics_key])
	_apply_saved_bobux_mesh_resource(mesh_inst, block_data, "")
	_update_block_collision(mesh_inst)
	_rebuild_studio_ai_components(mesh_inst)
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

func _capture_editor_snapshot_async(label: String, playtest_generation: int) -> Dictionary:
	var blocks: Array = []
	var parts := _get_editor_parts()
	for index in range(parts.size()):
		if playtest_generation != studio_playtest_generation or not studio_playtest_active:
			return {}
		blocks.append(_serialize_block_for_clipboard(parts[index]))
		if (index + 1) % PLAYTEST_SNAPSHOT_BATCH == 0:
			if toolbar_status_label:
				toolbar_status_label.text = "Preparing Play test %d/%d..." % [index + 1, parts.size()]
			await get_tree().process_frame
	return {
		"label": label,
		"blocks": blocks,
	}


func _capture_playtest_scene_snapshot_async(label: String, playtest_generation: int) -> Dictionary:
	var scene_roots: Array[Node] = []
	if placement_parent == null:
		return {"label": label, "scene_roots": scene_roots}
	var source_roots := placement_parent.get_children()
	for root_index in range(source_roots.size()):
		if playtest_generation != studio_playtest_generation or not studio_playtest_active:
			for detached_root in scene_roots:
				if detached_root != null and is_instance_valid(detached_root):
					detached_root.free()
			return {}
		var source_root := source_roots[root_index] as Node
		if source_root == null or bool(source_root.get_meta("bobux_runtime_generated", false)):
			continue
		var duplicate_root := source_root.duplicate()
		if duplicate_root == null:
			push_warning("[Studio] Could not snapshot Workspace root %s" % str(source_root.name))
			continue
		_copy_playtest_snapshot_metadata_tree(source_root, duplicate_root)
		_clear_playtest_runtime_metadata_tree(duplicate_root)
		scene_roots.append(duplicate_root)
		if (root_index + 1) % PLAYTEST_SNAPSHOT_BATCH == 0:
			if toolbar_status_label:
				toolbar_status_label.text = "Preparing Play test %d/%d..." % [root_index + 1, source_roots.size()]
			await get_tree().process_frame
	return {
		"label": label,
		"scene_roots": scene_roots,
		# Manifest entries are immutable during a play test. Keeping a shallow
		# snapshot avoids duplicating 20-50 MB of nested Roblox metadata.
		"roblox_manifest": current_roblox_place_manifest.duplicate(false),
	}


func _copy_playtest_snapshot_metadata_tree(source: Node, target: Node) -> void:
	if source == null or target == null:
		return
	for key_variant in source.get_meta_list():
		var key := str(key_variant)
		if _is_playtest_runtime_metadata_key(key):
			continue
		var value: Variant = source.get_meta(key_variant)
		if value is Dictionary:
			value = (value as Dictionary).duplicate(false)
		elif value is Array:
			value = (value as Array).duplicate(false)
		target.set_meta(key, value)
	var child_count := mini(source.get_child_count(), target.get_child_count())
	for child_index in range(child_count):
		_copy_playtest_snapshot_metadata_tree(source.get_child(child_index), target.get_child(child_index))


func _clear_playtest_runtime_metadata_tree(root: Node) -> void:
	if root == null:
		return
	for key_variant in root.get_meta_list():
		var key := str(key_variant)
		if _is_playtest_runtime_metadata_key(key):
			root.remove_meta(key_variant)
	for child in root.get_children():
		_clear_playtest_runtime_metadata_tree(child)


func _is_playtest_runtime_metadata_key(key: String) -> bool:
	return key.begins_with("_bobux_") or key in [
		"bobux_runtime_generated",
		"bobux_touch_collision_count",
		"bobux_touch_notifications",
		"bobux_character_instance_id",
		"bobux_player_instance_id",
		"bobux_bound_target_path",
		"bobux_lua_event_bound",
	]


func _restore_playtest_scene_snapshot(snapshot: Dictionary) -> void:
	if placement_parent == null or not snapshot.has("scene_roots"):
		return
	is_restoring_history = true
	_clear_selection()
	var current_roots := placement_parent.get_children()
	for root in current_roots:
		if root != null and is_instance_valid(root):
			placement_parent.remove_child(root)
			root.queue_free()
	await get_tree().process_frame
	var scene_roots: Array = snapshot.get("scene_roots", []) if snapshot.get("scene_roots", []) is Array else []
	for root_index in range(scene_roots.size()):
		var root_variant: Variant = scene_roots[root_index]
		if not (root_variant is Node) or not is_instance_valid(root_variant):
			continue
		var restored_root := root_variant as Node
		placement_parent.add_child(restored_root, true)
		if (root_index + 1) % PLAYTEST_SNAPSHOT_BATCH == 0:
			if toolbar_status_label:
				toolbar_status_label.text = "Restoring scene %d/%d..." % [root_index + 1, scene_roots.size()]
			await get_tree().process_frame
	if snapshot.get("roblox_manifest", {}) is Dictionary:
		current_roblox_place_manifest = (snapshot.get("roblox_manifest", {}) as Dictionary).duplicate(false)
	is_restoring_history = false
	_clear_selection()
	_refresh_explorer()
	_update_selection_status()

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
	var parent: Node = placement_parent if placement_parent else self
	for block in _get_editor_parts():
		if is_instance_valid(block):
			block.queue_free()
	await get_tree().process_frame
	var restored_blocks: Array = snapshot.get("blocks", []) if snapshot.get("blocks", []) is Array else []
	for restore_index in range(restored_blocks.size()):
		var block_variant: Variant = restored_blocks[restore_index]
		if not (block_variant is Dictionary):
			continue
		var block := _create_block_from_clipboard((block_variant as Dictionary).duplicate(true), Vector3.ZERO, true)
		if block:
			parent.add_child(block)
		if (restore_index + 1) % PLAYTEST_SNAPSHOT_BATCH == 0:
			if toolbar_status_label:
				toolbar_status_label.text = "Restoring scene %d/%d..." % [restore_index + 1, restored_blocks.size()]
			await get_tree().process_frame
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

func _begin_box_selection(start_pos: Vector2, pending_block: Node3D = null, additive: bool = false) -> void:
	is_box_selecting = true
	box_select_start = start_pos
	box_select_current = start_pos
	box_select_pending_block = pending_block
	box_select_additive = additive
	_update_selection_box_visual()

func _complete_box_selection() -> void:
	if not is_box_selecting:
		return
	var rect := Rect2(box_select_start, box_select_current - box_select_start).abs()
	is_box_selecting = false
	_clear_selection_box_visual()
	if rect.size.length() < BOX_SELECT_MIN_DRAG:
		if box_select_pending_block and is_instance_valid(box_select_pending_block):
			_apply_click_selection(box_select_pending_block, box_select_additive)
		else:
			if not box_select_additive:
				_clear_selection()
		box_select_pending_block = null
		box_select_additive = false
		return

	var found: Array[Node3D] = []
	for block in _get_editor_parts():
		var screen_rect = _get_block_screen_rect(block)
		if screen_rect != null and rect.intersects(screen_rect as Rect2, true):
			found.append(block)
	box_select_pending_block = null
	if box_select_additive:
		var merged: Array[Node3D] = _get_valid_selected_blocks()
		for block in found:
			if not merged.has(block):
				merged.append(block)
		_set_selection(merged)
	else:
		_set_selection(found)
	box_select_additive = false

func _apply_click_selection(block: Node3D, additive: bool) -> void:
	if block == null or not is_instance_valid(block):
		if not additive:
			_clear_selection()
		return
	if not additive:
		_set_selection([block])
		return
	var merged: Array[Node3D] = _get_valid_selected_blocks()
	if merged.has(block):
		merged.erase(block)
	else:
		merged.append(block)
	_set_selection(merged)

func _update_selection_box_visual() -> void:
	if selection_box_rect == null:
		return
	var rect := Rect2(box_select_start, box_select_current - box_select_start).abs()
	selection_box_rect.visible = is_box_selecting
	var visual_start := _subviewport_to_root_canvas_position(rect.position)
	var visual_end := _subviewport_to_root_canvas_position(rect.end)
	var visual_rect := Rect2(visual_start, visual_end - visual_start).abs()
	selection_box_rect.position = visual_rect.position
	selection_box_rect.size = visual_rect.size


func _subviewport_to_root_canvas_position(point: Vector2) -> Vector2:
	if viewport_container_node == null or not is_instance_valid(viewport_container_node):
		return point
	var viewport_size := Vector2(viewport_container_node.size)
	if camera != null and camera.get_viewport() != null:
		viewport_size = Vector2(camera.get_viewport().size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return point
	var local_point := Vector2(
		point.x / viewport_size.x * viewport_container_node.size.x,
		point.y / viewport_size.y * viewport_container_node.size.y
	)
	return viewport_container_node.get_global_transform_with_canvas() * local_point

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
	var mouse_pos = _get_studio_mouse_position()
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
	if block and not bool(block.get_meta("locked", false)):
		_select_block(block)
		return true
	return false

func _select_block(block: Node3D) -> void:
	if block == null or bool(block.get_meta("locked", false)):
		if toolbar_status_label:
			toolbar_status_label.text = "Part is locked. Select it in Explorer to unlock it."
		return
	_set_selection([block])

func _attempt_placement() -> void:
	if _is_studio_editing_locked():
		return
	var result = _get_ray_intersection(SELECTION_RAY_MASK)
	if result:
		var offset = result.normal * (0.5 if current_shape != "Spawn" else 0.25)
		var pos = (result.position + offset).snapped(Vector3(0.5, 0.5, 0.5))
		_place_block(pos)
	else:
		_place_block(_get_editor_drop_position(10.0))

func _attempt_deletion() -> void:
	if _is_studio_editing_locked():
		return
	var block := _get_block_from_ray_result(_get_ray_intersection(SELECTION_RAY_MASK))
	if block == null or bool(block.get_meta("locked", false)):
		return
	_set_selection([block])
	_delete_selected_blocks()

# ===== BLOCK PLACEMENT =====
func _place_block(pos: Vector3) -> void:
	if _is_studio_editing_locked():
		return
	var placement_material: String = "Water" if current_shape == "Water" else current_material_type
	var placement_color: Color = Color(0.12, 0.55, 0.92, 0.72) if current_shape == "Water" else current_color
	var placement_can_collide: bool = current_shape != "Water"
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource: Mesh = _create_mesh_for_shape(current_shape)
	var mat := _create_material(placement_color, placement_material, 0.28 if current_shape == "Water" else 0.0)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource
	if current_shape in ["Cone", "Wedge", "WedgePart", "CornerWedge", "CornerWedgePart", "Truss", "TrussPart"]:
		_ensure_mesh_materials_double_sided(mesh_inst)

	mesh_inst.position = pos
	mesh_inst.scale = _get_default_block_scale(current_shape)
	mesh_inst.add_to_group("studio_parts")
	mesh_inst.set_meta("block_name", current_shape + "_" + str(randi() % 10000))
	mesh_inst.set_meta("roblox_class", _roblox_class_for_shape(current_shape))
	mesh_inst.set_meta("bobux_color", placement_color)
	mesh_inst.set_meta("material_type", placement_material)
	mesh_inst.set_meta("shape_type", current_shape)
	mesh_inst.set_meta("is_spawn", current_shape == "Spawn")
	mesh_inst.set_meta("can_collide", placement_can_collide)
	mesh_inst.set_meta("deals_damage", false)
	mesh_inst.set_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)
	mesh_inst.set_meta("transparency", 0.28 if current_shape == "Water" else 0.0)
	_rebuild_block_helpers(mesh_inst)
	_configure_studio_water_volume(mesh_inst)

	var parent = placement_parent if placement_parent else self
	parent.add_child(mesh_inst)
	_set_selection([mesh_inst])
	_refresh_explorer()
	_commit_editor_history("Place %s" % current_shape)

func _build_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
	return _build_block_instance_internal(shape_name, color, material_type, transparency, can_collide, block_name, true)

func _build_imported_block_instance(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String) -> MeshInstance3D:
	return _build_block_instance_internal(shape_name, color, material_type, transparency, can_collide, block_name, false)

func _build_block_instance_internal(shape_name: String, color: Color, material_type: String, transparency: float, can_collide: bool, block_name: String, build_helpers: bool) -> MeshInstance3D:
	if shape_name == "Water":
		material_type = "Water"
		transparency = maxf(transparency, 0.28)
	if material_type.strip_edges().to_lower() == "water":
		can_collide = false
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource: Mesh = _create_mesh_for_shape(shape_name)
	var mat := _create_material(color, material_type, transparency)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource
	mesh_inst.scale = _get_default_block_scale(shape_name)
	mesh_inst.add_to_group("studio_parts")
	mesh_inst.set_meta("block_name", block_name)
	mesh_inst.set_meta("roblox_class", _roblox_class_for_shape(shape_name))
	mesh_inst.set_meta("bobux_color", color)
	mesh_inst.set_meta("material_type", material_type)
	mesh_inst.set_meta("shape_type", shape_name)
	mesh_inst.set_meta("is_spawn", shape_name in ["Spawn", "SpawnLocation"])
	mesh_inst.set_meta("can_collide", can_collide)
	mesh_inst.set_meta("deals_damage", false)
	mesh_inst.set_meta("damage_amount", DEFAULT_BLOCK_DAMAGE)
	mesh_inst.set_meta("transparency", transparency)
	if build_helpers:
		_rebuild_block_helpers(mesh_inst)
		_configure_studio_water_volume(mesh_inst)
	return mesh_inst


func _roblox_class_for_shape(shape_name: String) -> String:
	match shape_name:
		"Wedge", "WedgePart":
			return "WedgePart"
		"CornerWedge", "CornerWedgePart":
			return "CornerWedgePart"
		"Truss", "TrussPart":
			return "TrussPart"
		"Spawn", "SpawnLocation":
			return "SpawnLocation"
		"Seat":
			return "Seat"
		"VehicleSeat":
			return "VehicleSeat"
		_:
			return "Part"

func _create_mesh_for_shape(shape_name: String) -> Mesh:
	if shape_name in ["Water", "Spawn", "SpawnLocation", "Checkpoint", "Teleport", "Seat", "VehicleSeat"]:
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereMesh.new()
		"Cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.cap_top = true
			cone.cap_bottom = true
			return cone
		"Cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.cap_top = true
			cylinder.cap_bottom = true
			return cylinder
		"Wedge", "WedgePart":
			return RbxlWedgeMeshBuilder.build_wedge(Vector3.ONE)
		"CornerWedge", "CornerWedgePart":
			return RbxlWedgeMeshBuilder.build_corner_wedge(Vector3.ONE)
		"Truss", "TrussPart":
			return RbxlWedgeMeshBuilder.build_truss(Vector3.ONE)
		_: # Box
			return BoxMesh.new()

func _create_collision_for_shape(shape_name: String) -> Shape3D:
	if shape_name in ["Water", "Spawn", "SpawnLocation", "Checkpoint", "Teleport", "Seat", "VehicleSeat"]:
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereShape3D.new()
		"Cylinder", "Cone":
			return CylinderShape3D.new()
		"Wedge", "WedgePart", "CornerWedge", "CornerWedgePart":
			var wedge_mesh := _create_mesh_for_shape(shape_name)
			return wedge_mesh.create_convex_shape(true, false) if wedge_mesh != null else BoxShape3D.new()
		"Truss", "TrussPart":
			return BoxShape3D.new()
		_:
			return BoxShape3D.new()

func _create_material(color: Color, mat_type: String, transparency: float = 0.0) -> StandardMaterial3D:
	var mat := rbxl_material_cache.get_named_material(color, mat_type, transparency)
	if mat != null:
		return mat
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(color.r, color.g, color.b, 1.0 - transparency)
	fallback.roughness = 0.8
	if transparency > 0.0:
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return fallback

func _get_default_block_scale(shape_name: String) -> Vector3:
	match shape_name:
		"Water":
			return Vector3(12.0, 2.0, 12.0)
		"Truss", "TrussPart":
			return Vector3(2.0, 8.0, 2.0)
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
	var use_mesh_collision := bool(block.get_meta("roblox_mesh_applied", false)) and block.mesh != null
	if use_mesh_collision:
		collision_shape.shape = block.mesh.create_trimesh_shape()
	else:
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
	_configure_studio_water_volume(block as MeshInstance3D)

func _configure_studio_water_volume(block: MeshInstance3D) -> void:
	if block == null or not is_instance_valid(block):
		return
	var existing := block.get_node_or_null("WaterVolume")
	if existing != null:
		existing.queue_free()
	var is_water := str(block.get_meta("material_type", block.get_meta("roblox_material_name", ""))).strip_edges().to_lower() == "water"
	if not is_water:
		if block.is_in_group("roblox_water"):
			block.remove_from_group("roblox_water")
		return
	block.set_meta("material_type", "Water")
	block.set_meta("can_collide", false)
	block.add_to_group("roblox_water")
	var collision_body := block.get_node_or_null(COLLISION_BODY_NAME) as StaticBody3D
	var source_shape := collision_body.get_node_or_null("CollisionShape3D") as CollisionShape3D if collision_body != null else null
	if source_shape == null or source_shape.shape == null:
		var selection_body := block.get_node_or_null(SELECTION_BODY_NAME) as StaticBody3D
		source_shape = selection_body.get_node_or_null("CollisionShape3D") as CollisionShape3D if selection_body != null else null
	if source_shape == null or source_shape.shape == null:
		return
	if collision_body != null:
		var solid_shape := collision_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if solid_shape != null:
			solid_shape.disabled = true
	var area := Area3D.new()
	area.name = "WaterVolume"
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = true
	area.monitorable = true
	area.add_to_group("roblox_water")
	area.set_meta("roblox_class", "TerrainWater")
	var area_shape := CollisionShape3D.new()
	area_shape.name = "WaterShape"
	area_shape.shape = source_shape.shape.duplicate(true)
	area_shape.position = source_shape.position
	area.add_child(area_shape)
	block.add_child(area)

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
		"Cylinder", "Cone":
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
	placement_parent.get_parent().add_child(selection_highlight_root)

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
	placement_parent.get_parent().add_child(transform_gizmo_root)

	var axis_colors := {
		"x": Color(0.97, 0.32, 0.32),
		"y": Color(0.25, 0.83, 0.42),
		"z": Color(0.28, 0.56, 1.0)
	}
	for mode in ["move", "scale", "rotate"]:
		for axis in ["x", "y", "z"]:
			transform_gizmo_root.add_child(_create_gizmo_handle(mode, axis, axis_colors[axis], 1))
			if mode in ["move", "scale"]:
				transform_gizmo_root.add_child(_create_gizmo_handle(mode, axis, axis_colors[axis], -1))
	transform_gizmo_root.add_child(_create_gizmo_center_handle())
	transform_gizmo_root.visible = false

func _create_gizmo_center_handle() -> Node3D:
	var handle := Node3D.new()
	handle.name = "move_view_center"
	handle.set_meta("gizmo_mode", "move")
	handle.set_meta("gizmo_axis", "view")
	handle.set_meta("gizmo_sign", 1)

	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(0.24, 0.24, 0.24)
	var cube := _create_gizmo_mesh_instance("FreeMoveBox", cube_mesh, Color.WHITE, 0.98)
	handle.add_child(cube)

	var pick_body := StaticBody3D.new()
	pick_body.name = "PickBody"
	pick_body.collision_layer = GIZMO_RAY_MASK
	pick_body.collision_mask = 0
	pick_body.input_ray_pickable = true
	handle.add_child(pick_body)

	var pick_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.42, 0.42, 0.42)
	pick_shape.shape = box_shape
	pick_body.add_child(pick_shape)
	return handle

func _create_gizmo_handle(mode: String, axis: String, color: Color, direction_sign: int = 1) -> Node3D:
	var handle := Node3D.new()
	handle.name = "%s_%s_%s" % [mode, axis, "pos" if direction_sign >= 0 else "neg"]
	handle.set_meta("gizmo_mode", mode)
	handle.set_meta("gizmo_axis", axis)
	handle.set_meta("gizmo_sign", direction_sign)
	var axis_sign := 1.0 if direction_sign >= 0 else -1.0

	var visual_root := Node3D.new()
	handle.add_child(visual_root)

	if mode == "rotate":
		visual_root.rotation_degrees = _get_ring_rotation_degrees(axis)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.96
		ring_mesh.outer_radius = 1.04
		ring_mesh.rings = 64
		ring_mesh.ring_segments = 10
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = ring_mesh
		ring.material_override = _create_gizmo_material(color, 0.95)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual_root.add_child(ring)
	else:
		visual_root.rotation_degrees = _get_axis_rotation_degrees(axis)
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.035
		shaft_mesh.bottom_radius = 0.035
		shaft_mesh.height = 1.15
		var shaft := _create_gizmo_mesh_instance("Shaft", shaft_mesh, color, 0.95)
		shaft.position = Vector3(0.0, 0.58 * axis_sign, 0.0)
		visual_root.add_child(shaft)

		if mode == "scale":
			var cube := BoxMesh.new()
			cube.size = Vector3(0.25, 0.25, 0.25)
			var cube_tip := _create_gizmo_mesh_instance("ScaleBox", cube, color.lightened(0.08), 0.98)
			cube_tip.position = Vector3(0.0, 1.22 * axis_sign, 0.0)
			visual_root.add_child(cube_tip)
		else:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.15
			cone.height = 0.32
			var cone_tip := _create_gizmo_mesh_instance("ArrowHead", cone, color.lightened(0.08), 0.98)
			cone_tip.position = Vector3(0.0, 1.28 * axis_sign, 0.0)
			if axis_sign < 0.0:
				cone_tip.rotation_degrees.z = 180.0
			visual_root.add_child(cone_tip)
			if direction_sign > 0:
				_add_gizmo_move_plane(handle, axis)

	var pick_body := StaticBody3D.new()
	pick_body.name = "PickBody"
	pick_body.collision_layer = GIZMO_RAY_MASK
	pick_body.collision_mask = 0
	pick_body.input_ray_pickable = true
	handle.add_child(pick_body)

	if mode == "rotate":
		for point_index in range(24):
			var angle := TAU * float(point_index) / 24.0
			var ring_pick_shape := CollisionShape3D.new()
			var ring_pick := SphereShape3D.new()
			ring_pick.radius = 0.11
			ring_pick_shape.shape = ring_pick
			ring_pick_shape.position = _get_ring_pick_point(axis, angle)
			pick_body.add_child(ring_pick_shape)
		return handle

	pick_body.rotation_degrees = _get_axis_rotation_degrees(axis)

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
	sphere_shape.radius = 0.3
	pick_shape.shape = sphere_shape
	pick_shape.position = Vector3(0.0, 1.15 * axis_sign, 0.0)
	pick_body.add_child(pick_shape)

	return handle

func _create_gizmo_mesh_instance(name: String, mesh: Mesh, color: Color, alpha: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = _create_gizmo_material(color, alpha)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _create_gizmo_material(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	material.no_depth_test = true
	if alpha < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _add_gizmo_move_plane(handle: Node3D, axis: String) -> void:
	var plane_axes := {
		"x": ["xy", Vector3(0.26, 0.26, 0.0), Vector3(90, 0, 0), Color(1.0, 0.9, 0.25, 0.18)],
		"y": ["yz", Vector3(0.0, 0.26, 0.26), Vector3(0, 0, 90), Color(0.25, 0.8, 1.0, 0.18)],
		"z": ["xz", Vector3(0.26, 0.0, 0.26), Vector3(0, 0, 0), Color(0.4, 1.0, 0.4, 0.18)]
	}
	if not plane_axes.has(axis):
		return
	var spec: Array = plane_axes[axis]
	var plane_position: Vector3 = spec[1]
	var plane_rotation: Vector3 = spec[2]
	var plane_color: Color = spec[3]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.42, 0.42)
	var plane := MeshInstance3D.new()
	plane.name = "Plane_" + str(spec[0])
	plane.mesh = mesh
	plane.position = plane_position
	plane.rotation_degrees = plane_rotation
	plane.material_override = _create_gizmo_material(plane_color, 0.18)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	handle.add_child(plane)

func _update_transform_gizmo() -> void:
	if transform_gizmo_root == null:
		return

	var valid_blocks := _get_valid_selected_blocks()
	if studio_playtest_active or current_shape != "Select" or current_editor_tool == "select" or current_editor_tool == "terrain" or valid_blocks.is_empty() or _selection_has_locked_parts():
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
			var handle_mode := str(handle.get_meta("gizmo_mode", ""))
			var is_active_mode := handle_mode == current_transform_mode
			if current_transform_mode == "transform":
				is_active_mode = handle_mode in ["move", "scale", "rotate"]
			elif current_transform_mode == "geometric":
				is_active_mode = handle_mode == "move"
			handle.visible = is_active_mode
			var pick_body := handle.get_node_or_null("PickBody") as StaticBody3D
			if pick_body:
				pick_body.input_ray_pickable = is_active_mode
				pick_body.collision_layer = GIZMO_RAY_MASK if is_active_mode else 0

func _begin_gizmo_drag(gizmo_handle: Node3D) -> void:
	if _is_studio_editing_locked():
		return
	if _selection_has_locked_parts():
		if toolbar_status_label:
			toolbar_status_label.text = "Unlock the selection before transforming it"
		return
	active_gizmo_mode = str(gizmo_handle.get_meta("gizmo_mode", current_transform_mode))
	active_gizmo_axis = str(gizmo_handle.get_meta("gizmo_axis", "x"))
	active_gizmo_sign = -1 if int(gizmo_handle.get_meta("gizmo_sign", 1)) < 0 else 1
	gizmo_drag_axis_world = _get_axis_vector(active_gizmo_axis)
	if active_gizmo_axis == "view":
		gizmo_drag_axis_world = Vector3.ZERO
	elif active_gizmo_mode == "scale":
		gizmo_drag_axis_world *= float(active_gizmo_sign)
	gizmo_drag_start_pivot = _get_selection_pivot()
	if active_gizmo_axis == "view":
		var camera_forward := (-camera.global_basis.z).normalized() if camera else Vector3.FORWARD
		gizmo_drag_plane = Plane(camera_forward, gizmo_drag_start_pivot)
	else:
		gizmo_drag_plane = _make_rotation_drag_plane(gizmo_drag_axis_world, gizmo_drag_start_pivot) if active_gizmo_mode == "rotate" else _make_axis_drag_plane(gizmo_drag_axis_world, gizmo_drag_start_pivot)
	gizmo_drag_start_mouse = _get_studio_mouse_position()

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

	var mouse_hit = _get_mouse_plane_intersection(_get_studio_mouse_position(), gizmo_drag_plane)
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
	if active_gizmo_mode == "rotate" and mouse_hit != null:
		axis_delta = (mouse_hit - gizmo_drag_start_hit).dot(gizmo_drag_axis_world)
	if active_gizmo_mode == "rotate":
		if mouse_hit == null:
			return
	match active_gizmo_mode:
		"move":
			if active_gizmo_axis == "view":
				if mouse_hit == null:
					return
				var free_delta: Vector3 = _snap_vector_delta(mouse_hit - gizmo_drag_start_hit)
				for block in _get_valid_selected_blocks():
					var start_pos: Vector3 = gizmo_drag_start_positions.get(block.get_instance_id(), block.global_position)
					block.global_position = start_pos + free_delta
			else:
				var snapped_delta: float = _snap_distance_delta(axis_delta)
				for block in _get_valid_selected_blocks():
					var start_pos: Vector3 = gizmo_drag_start_positions.get(block.get_instance_id(), block.global_position)
					block.global_position = start_pos + (gizmo_drag_axis_world * snapped_delta)
		"scale":
			var scale_delta: float = _snap_scale_delta(axis_delta)
			if Input.is_physical_key_pressed(KEY_SHIFT):
				var reference_size := maxf(gizmo_drag_start_scale.length(), 1.0)
				var factor := maxf(0.01, 1.0 + scale_delta / reference_size)
				for block in _get_valid_selected_blocks():
					var block_id := block.get_instance_id()
					var start_pos: Vector3 = gizmo_drag_start_positions.get(block_id, block.global_position)
					block.scale = gizmo_drag_start_scales.get(block_id, block.scale) * factor
					block.global_position = gizmo_drag_start_pivot + (start_pos - gizmo_drag_start_pivot) * factor
					_update_block_collision(block)
				return
			for block in _get_valid_selected_blocks():
				var block_id: int = block.get_instance_id()
				var start_pos: Vector3 = gizmo_drag_start_positions.get(block_id, block.global_position)
				var start_scale: Vector3 = gizmo_drag_start_scales.get(block_id, block.scale)
				var start_axis_scale: float = _get_axis_component(start_scale, active_gizmo_axis)
				var next_axis_scale: float = maxf(MIN_BLOCK_SCALE, start_axis_scale + scale_delta)
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
			var snapped_angle: float = _snap_rotation_delta(
				_signed_angle_around_axis(gizmo_drag_start_vector.normalized(), current_vector.normalized(), gizmo_drag_axis_world),
			)
			var rotation_basis: Basis = Basis(gizmo_drag_axis_world, snapped_angle)
			for block in _get_valid_selected_blocks():
				var block_id: int = block.get_instance_id()
				var start_offset: Vector3 = gizmo_drag_start_offsets.get(block_id, block.global_position - gizmo_drag_start_pivot)
				var start_basis: Basis = gizmo_drag_start_bases.get(block_id, block.global_basis)
				block.global_position = gizmo_drag_start_pivot + (rotation_basis * start_offset)
				block.global_basis = rotation_basis * start_basis

	_update_inspector()

func _snap_distance_delta(delta: float) -> float:
	if snap_enabled_check != null and is_instance_valid(snap_enabled_check) and not snap_enabled_check.button_pressed:
		return delta
	var step := MOVE_GRID_SNAP
	if snap_step_spin != null and is_instance_valid(snap_step_spin):
		step = maxf(0.001, float(snap_step_spin.value))
	return snappedf(delta, step)

func _snap_vector_delta(delta: Vector3) -> Vector3:
	if snap_enabled_check != null and is_instance_valid(snap_enabled_check) and not snap_enabled_check.button_pressed:
		return delta
	var step := MOVE_GRID_SNAP
	if snap_step_spin != null and is_instance_valid(snap_step_spin):
		step = maxf(0.001, float(snap_step_spin.value))
	return Vector3(snappedf(delta.x, step), snappedf(delta.y, step), snappedf(delta.z, step))

func _snap_scale_delta(delta: float) -> float:
	if snap_enabled_check != null and is_instance_valid(snap_enabled_check) and not snap_enabled_check.button_pressed:
		return delta
	return snappedf(delta, SCALE_GRID_SNAP)

func _snap_rotation_delta(delta: float) -> float:
	if angle_snap_enabled_check != null and is_instance_valid(angle_snap_enabled_check) and not angle_snap_enabled_check.button_pressed:
		return delta
	var degrees_step := ROTATION_SNAP_DEGREES
	if angle_snap_step_spin != null and is_instance_valid(angle_snap_step_spin):
		degrees_step = maxf(0.1, float(angle_snap_step_spin.value))
	return snappedf(delta, deg_to_rad(degrees_step))

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


func _selection_has_locked_parts() -> bool:
	for block in _get_valid_selected_blocks():
		if bool(block.get_meta("locked", false)):
			return true
	return false

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

func _get_ring_rotation_degrees(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3(0.0, 0.0, 90.0)
		"z":
			return Vector3(90.0, 0.0, 0.0)
		_:
			return Vector3.ZERO

func _get_ring_pick_point(axis: String, angle: float) -> Vector3:
	var radius := 1.02
	match axis:
		"x":
			return Vector3(0.0, cos(angle) * radius, sin(angle) * radius)
		"z":
			return Vector3(cos(angle) * radius, sin(angle) * radius, 0.0)
		_:
			return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

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
var main_container: VBoxContainer = null
var left_panel: TabContainer = null
var right_side: VSplitContainer = null
var script_editor_tabs: TabContainer = null
var viewport_container_node: SubViewportContainer = null
var explorer_popup: PopupMenu = null
var open_scripts: Dictionary = {}
var properties_dock_panel: PanelContainer = null
var properties_title_label: Label = null
var properties_filter_edit: LineEdit = null
var explorer_dock_panel: PanelContainer = null
var toolbox_dock_panel: PanelContainer = null
var toolbox_content_tabs: TabContainer = null
var toolbox_items_list: ItemList = null
var viewport_frame_panel: PanelContainer = null
var command_line_edit: LineEdit = null
var command_history: Array[String] = []
var command_history_cursor: int = 0
var studio_ai_window: Window = null
var studio_ai_dock: Control = null
var studio_ai_prompt_edit: TextEdit = null
var studio_ai_result_label: RichTextLabel = null
var studio_ai_submit_button: Button = null
var studio_ai_request_active: bool = false
var studio_ai_last_errors: Array[String] = []
var document_tab_button: Button = null
var document_tabs_container: HBoxContainer = null
var document_tab_spacer: Control = null
var script_document_buttons: Dictionary = {}
var active_document_script_id: int = 0
var studio_grid_root: Node3D = null
var ribbon_tab_buttons: Dictionary = {}
var active_ribbon_tab: String = "Home"
var ribbon_tools_container: HBoxContainer = null
var current_editor_tool: String = "select"
var snap_enabled_check: CheckBox = null
var angle_snap_enabled_check: CheckBox = null
var snap_step_spin: SpinBox = null
var angle_snap_step_spin: SpinBox = null
var show_grid_enabled: bool = true
var show_colliders_enabled: bool = false
var studio_wireframe_enabled: bool = false
var studio_gui_preview_enabled: bool = false
var studio_audio_muted: bool = false
var studio_toolbar_icon_cache: Dictionary = {}
const STUDIO_ICON_ROOT := "res://assets/studio/icons/lucide"
const STUDIO_ICON_FILES := {
	"Select": "mouse-pointer-2.svg", "Move": "move.svg", "Scale": "scaling.svg",
	"Rotate": "rotate-cw.svg", "Transform": "boxes.svg", "Geometric": "box-select.svg",
	"Part": "box.svg", "Terrain": "mountain.svg", "Character": "person-standing.svg",
	"GUI": "panels-top-left.svg", "Script": "file-code-2.svg", "Import": "download.svg",
	"Material": "circle-dot.svg", "Color": "palette.svg", "Group": "group.svg", "Lock": "lock.svg",
	"Anchor": "anchor.svg", "Explorer": "list-tree.svg", "Properties": "sliders-horizontal.svg",
	"Toolbox": "briefcase-business.svg", "Assets": "images.svg", "Play": "play.svg",
	"Pause": "pause.svg", "Stop": "square.svg", "Reset": "refresh-cw.svg", "Record": "circle.svg",
	"Refresh": "refresh-cw.svg", "Close": "x.svg", "More": "ellipsis.svg",
	"Search": "search.svg", "History": "history.svg", "Command": "terminal.svg",
	"AI": "boxes.svg",
		"Save": "save.svg", "Open": "folder-open.svg", "Add": "plus.svg",
		"Delete": "trash-2.svg", "Copy": "copy.svg", "Undo": "undo-2.svg", "Redo": "redo-2.svg",
		"ChevronDown": "chevron-down.svg",
	}

func _build_main_white_layout() -> void:
	viewport_container_node = get_node_or_null("SubViewportContainer")
	if viewport_container_node:
		remove_child(viewport_container_node)
	
	main_container = VBoxContainer.new()
	main_container.name = "StudioRoot"
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", 0)
	add_child(main_container)
	
	_build_studio_menu_bar()
	_build_toolbar_white()
	
	var split_main := HBoxContainer.new()
	split_main.name = "MainSplit"
	split_main.add_theme_constant_override("separation", 0)
	split_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(split_main)
	
	toolbox_dock_panel = _build_toolbox_dock()
	split_main.add_child(toolbox_dock_panel)
	
	var center_split := VBoxContainer.new()
	center_split.name = "ViewportColumn"
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_split.add_theme_constant_override("separation", 0)
	split_main.add_child(center_split)
	
	_build_viewport_document_header(center_split)

	viewport_frame_panel = PanelContainer.new()
	viewport_frame_panel.name = "ViewportContainer"
	viewport_frame_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_frame_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_frame_panel.clip_contents = true
	viewport_frame_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#888888"), Color("#B7B7B7"), 1))
	center_split.add_child(viewport_frame_panel)
	
	if viewport_container_node:
		viewport_container_node.mouse_filter = Control.MOUSE_FILTER_STOP
		viewport_container_node.focus_mode = Control.FOCUS_CLICK
		viewport_container_node.clip_contents = true
		viewport_container_node.stretch = true
		viewport_container_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		viewport_container_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if not viewport_container_node.gui_input.is_connected(_on_studio_viewport_gui_input):
			viewport_container_node.gui_input.connect(_on_studio_viewport_gui_input)
		viewport_frame_panel.add_child(viewport_container_node)
		viewport_container_node.call_deferred("grab_focus")
		
	script_editor_tabs = TabContainer.new()
	script_editor_tabs.name = "ScriptEditorTabs"
	script_editor_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_editor_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_editor_tabs.tabs_visible = false
	script_editor_tabs.visible = false
	center_split.add_child(script_editor_tabs)
	
	right_side = VSplitContainer.new()
	right_side.name = "RightDockSplit"
	right_side.custom_minimum_size = Vector2(286, 0)
	right_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_side.add_theme_constant_override("separation", 1)
	split_main.add_child(right_side)
	explorer_dock_panel = _build_explorer_dock()
	explorer_dock_panel.custom_minimum_size = Vector2(286, 260)
	right_side.add_child(explorer_dock_panel)
	properties_dock_panel = PanelContainer.new()
	properties_dock_panel.name = "PropertiesPanel"
	properties_dock_panel.custom_minimum_size = Vector2(286, 220)
	properties_dock_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	properties_dock_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F7F7F7"), Color("#C8C8C8"), 1))
	right_side.add_child(properties_dock_panel)
	var right_inspector_panel := _build_properties_dock(properties_dock_panel)
	right_side.set_deferred("split_offset", 390)

	if right_inspector_panel != null:
		inspector_panel = right_inspector_panel
	
	_build_command_bar()
	_build_selection_overlay()
	_ensure_studio_grid()

func _build_command_bar() -> void:
	if main_container == null:
		return
	var command_panel := PanelContainer.new()
	command_panel.name = "StatusBar"
	command_panel.custom_minimum_size = Vector2(0, 32)
	command_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F5F5F5"), Color("#CCCCCC"), 1))
	main_container.add_child(command_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	command_panel.add_child(row)
	toolbar_status_label = Label.new()
	toolbar_status_label.text = "No selection"
	toolbar_status_label.custom_minimum_size = Vector2(190, 0)
	toolbar_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_status_label.add_theme_font_size_override("font_size", 11)
	toolbar_status_label.add_theme_color_override("font_color", Color("#555555"))
	row.add_child(toolbar_status_label)
	command_line_edit = LineEdit.new()
	command_line_edit.name = "CommandLine"
	command_line_edit.placeholder_text = "Execute a command with Ctrl+L or use Ctrl+Up/Down for history"
	command_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_line_edit.add_theme_font_size_override("font_size", 11)
	command_line_edit.add_theme_color_override("font_placeholder_color", Color(0.50, 0.52, 0.56))
	command_line_edit.add_theme_color_override("font_color", Color(0.16, 0.17, 0.19))
	command_line_edit.add_theme_stylebox_override("normal", _studio_line_edit_style())
	command_line_edit.text_submitted.connect(_execute_command_bar)
	command_line_edit.gui_input.connect(_on_command_bar_gui_input)
	row.add_child(command_line_edit)
	var history_btn := Button.new()
	history_btn.text = "History"
	history_btn.custom_minimum_size = Vector2(74, 24)
	_style_white_button(history_btn)
	history_btn.pressed.connect(_show_command_history_popup.bind(history_btn))
	row.add_child(history_btn)
	var ai_btn := Button.new()
	ai_btn.text = "Bobux AI"
	ai_btn.tooltip_text = "Ask AI to create Luau scripts, parts, or complete models"
	ai_btn.custom_minimum_size = Vector2(86, 24)
	_style_white_button(ai_btn)
	ai_btn.pressed.connect(_show_studio_ai_window)
	row.add_child(ai_btn)
	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.custom_minimum_size = Vector2(62, 24)
	run_btn.disabled = false
	_style_white_button(run_btn)
	run_btn.pressed.connect(func() -> void: _execute_command_bar(command_line_edit.text))
	row.add_child(run_btn)


func _show_studio_ai_window() -> void:
	_set_tool_window_visible("toolbox", true)
	if toolbox_content_tabs != null:
		toolbox_content_tabs.current_tab = 1
	if studio_ai_prompt_edit != null and is_instance_valid(studio_ai_prompt_edit):
		studio_ai_prompt_edit.grab_focus()
		studio_ai_prompt_edit.set_caret_line(studio_ai_prompt_edit.get_line_count() - 1)


func _build_studio_ai_window() -> void:
	studio_ai_window = Window.new()
	studio_ai_window.name = "BobuxAIWindow"
	studio_ai_window.title = "Bobux AI Builder"
	studio_ai_window.min_size = Vector2i(440, 420)
	studio_ai_window.close_requested.connect(studio_ai_window.hide)
	add_child(studio_ai_window)
	var surface := PanelContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F7F8FA"), Color("#D1D4D8"), 1))
	studio_ai_window.add_child(surface)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	surface.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Create with Bobux AI"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#202124"))
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Describe a Luau script or a 3D build. The assistant can add validated Parts, Models and Scripts to this place."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#5F6368"))
	column.add_child(hint)
	studio_ai_prompt_edit = TextEdit.new()
	studio_ai_prompt_edit.placeholder_text = "Examples:\nCreate an anchored wooden house with a door and four windows\nWrite a script that makes the selected part change color when touched"
	studio_ai_prompt_edit.custom_minimum_size = Vector2(0, 150)
	studio_ai_prompt_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	studio_ai_prompt_edit.add_theme_color_override("font_color", Color("#202124"))
	studio_ai_prompt_edit.add_theme_color_override("font_placeholder_color", Color("#6B7078"))
	studio_ai_prompt_edit.add_theme_color_override("background_color", Color.WHITE)
	column.add_child(studio_ai_prompt_edit)
	studio_ai_result_label = RichTextLabel.new()
	studio_ai_result_label.bbcode_enabled = true
	studio_ai_result_label.fit_content = false
	studio_ai_result_label.custom_minimum_size = Vector2(0, 120)
	studio_ai_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	studio_ai_result_label.add_theme_color_override("default_color", Color("#202124"))
	studio_ai_result_label.add_theme_stylebox_override("normal", _studio_panel_style(Color.WHITE, Color("#DADCE0"), 1))
	studio_ai_result_label.text = "[color=#5f6368]The generated plan and result will appear here.[/color]"
	column.add_child(studio_ai_result_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var close_button := Button.new()
	close_button.text = "Close"
	_style_white_button(close_button)
	close_button.pressed.connect(studio_ai_window.hide)
	actions.add_child(close_button)
	studio_ai_submit_button = Button.new()
	studio_ai_submit_button.text = "Create in Studio"
	studio_ai_submit_button.tooltip_text = "Generate a validated plan and apply it to the current place"
	_style_white_button(studio_ai_submit_button)
	studio_ai_submit_button.pressed.connect(_request_and_apply_studio_ai)
	actions.add_child(studio_ai_submit_button)


func _request_and_apply_studio_ai() -> void:
	if studio_ai_request_active or studio_ai_prompt_edit == null or _is_studio_editing_locked():
		return
	var prompt := studio_ai_prompt_edit.text.strip_edges()
	if prompt.length() < 3:
		_append_studio_ai_message("Bobux AI", "Describe what should be created.", "#b3261e")
		return
	studio_ai_request_active = true
	studio_ai_submit_button.disabled = true
	_append_studio_ai_message("You", prompt, "#202124")
	studio_ai_prompt_edit.clear()
	_append_studio_ai_message("Bobux AI", "Preparing a validated Studio plan...", "#5f6368")
	await ToolboxAssetService.refresh_catalog()
	if not is_inside_tree(): return
	var context := _build_studio_ai_context(prompt)
	var requested_selection := str(context.get("selected_ref", ""))
	var response: Dictionary = preload("res://addons/roblox_studio/studio_ai_planner.gd").plan_for_request(prompt, context)
	if response.is_empty():
		var script_contract := "\nStudio scripting requirements: plain Luau, no HTML entities or markdown in source. Player input uses UserInputService.JumpRequest (never Humanoid.JumpRequested). Character scripts must be LocalScript parent=StarterCharacterScripts and use script.Parent:WaitForChild('Humanoid'). General client scripts use StarterPlayerScripts, Players.LocalPlayer.Character or CharacterAdded:Wait(). StateChanged supplies oldState and newState. Save stores code; Play runs it."
		var scripting_request := RegEx.new()
		scripting_request.compile("(?i)(скрипт|script|lua|прыж|jump|gui|кнопк|button|монет|coin|бафф|buff|летат|fly)")
		var provider_prompt := prompt + script_contract if scripting_request.search(prompt) != null and prompt.length() + script_contract.length() <= 4000 else prompt
		response = await CloudAPI.request_studio_ai(provider_prompt, context)
		response = _normalize_studio_ai_editor_response(response)
		if bool(response.get("ok", false)):
			var repair_feedback := _studio_ai_source_feedback(response.get("actions", []))
			if not repair_feedback.is_empty() and provider_prompt.length() < 2800:
				_append_studio_ai_message("Bobux AI", "Проверка обнаружила ошибку в Lua. Запрашиваю исправленный вариант...", "#975c00")
				response = await CloudAPI.request_studio_ai(provider_prompt + "\nPrevious generated source failed compilation. Return a corrected complete plan.\n" + repair_feedback.left(1000), context)
	response = _normalize_studio_ai_editor_response(response)
	if not bool(response.get("ok", false)):
		_finish_studio_ai_request()
		_append_studio_ai_message("Bobux AI", str(response.get("error", "Bobux AI request failed.")), "#b3261e")
		return
	var actions_value: Variant = response.get("actions", [])
	var actions: Array = actions_value if actions_value is Array else []
	var expanded := preload("res://addons/roblox_studio/studio_ai_planner.gd").expand_actions(actions)
	if not expanded.ok:
		_finish_studio_ai_request()
		_append_studio_ai_message("Bobux AI", expanded.error, "#b3261e")
		return
	actions = expanded.actions
	for action in actions:
		if action is Dictionary and action.get("type") in ["spawn_asset", "attach_sound"]:
			if not await ToolboxAssetService.ensure_asset(str(action.get("asset_id", ""))):
				_finish_studio_ai_request()
				_append_studio_ai_message("Bobux AI", ToolboxAssetService.last_error, "#b3261e")
				return
	var applied := _apply_studio_ai_actions(actions, requested_selection)
	_finish_studio_ai_request()
	var details := "\n".join(studio_ai_last_errors)
	if applied <= 0:
		_append_studio_ai_message("Bobux AI", "%s\nNothing was changed in the place. %s" % [str(response.get("message", "No supported actions were returned.")), details], "#b3261e")
		return
	_append_studio_ai_message("Bobux AI", "%s\nApplied: %d object change(s).%s" % [str(response.get("message", "Done.")), applied, "\n" + details if not details.is_empty() else ""], "#137333" if details.is_empty() else "#975c00")


func _finish_studio_ai_request() -> void:
	studio_ai_request_active = false
	if is_instance_valid(studio_ai_submit_button): studio_ai_submit_button.disabled = false

func _build_studio_ai_context(query: String = "") -> Dictionary:
	var selected := _get_selected_editor_node()
	var context := {
		"map_name": current_map_name,
		"world_units": "studs",
		"avatar_metrics": {
			"height": 5.8,
			"width": 4.0,
			"depth": 2.0,
			"comfortable_door": [5.0, 8.0],
			"comfortable_room_height": 12.0
		},
		"selected_name": selected.name if selected != null else "",
		"selected_ref": _studio_ai_node_reference(selected),
		"selected_class": str(selected.get_meta("roblox_class", selected.get_class())) if selected != null else "",
		"selected_position": _vector3_to_array((selected as Node3D).global_position) if selected is Node3D else []
	}
	var pending: Array[Node] = []
	if selected != null:
		pending.append(selected)
	if data_model != null:
		pending.append_array(data_model.get_children())
	if placement_parent != null:
		pending.append(placement_parent)
	var seen := {}
	var scene: Array = []
	var source_budget := 24000
	while not pending.is_empty() and scene.size() < 160:
		var node := pending.pop_front() as Node
		if not _is_studio_ai_scene_node(node) or seen.has(node.get_instance_id()):
			continue
		seen[node.get_instance_id()] = true
		pending.append_array(node.get_children())
		var roblox_class := str(node.get_meta("roblox_class", ""))
		if roblox_class.is_empty() and node != placement_parent:
			continue
		var entry := {"ref": _studio_ai_node_reference(node), "name": str(node.name), "class": roblox_class, "parent": _studio_ai_node_reference(node.get_parent())}
		entry["attributes"] = LuaScriptEngine.BobuxInstance.new(node).GetAttributes()
		entry["properties"] = node.get_meta("roblox_properties", {}).duplicate(true)
		if node is Node3D:
			entry["position"] = _vector3_to_array((node as Node3D).global_position)
			entry["rotation"] = _vector3_to_array((node as Node3D).rotation_degrees)
		if node is MeshInstance3D:
			entry["size"] = _vector3_to_array((node as MeshInstance3D).scale)
			entry["color"] = "#" + _get_bobux_block_color(node, Color.WHITE).to_html(false)
			entry["material"] = str(node.get_meta("material_type", "Plastic"))
			entry["anchored"] = bool(node.get_meta("anchored", true))
			entry["can_collide"] = bool(node.get_meta("can_collide", true))
		if roblox_class in ["Script", "LocalScript", "ModuleScript"] and source_budget > 0:
			var source := str(node.get_meta("code", node.get_meta("lua_source", "")))
			var script_tab := open_scripts.get(node.get_instance_id(), null) as Control
			if is_instance_valid(script_tab):
				var editor: CodeEdit = null
				for child in script_tab.get_children():
					if child is CodeEdit:
						editor = child
						break
				if editor is CodeEdit:
					source = (editor as CodeEdit).text
			entry["source"] = source.left(mini(source_budget, 16000 if node == selected else 2000))
			entry["source_truncated"] = str(entry["source"]).length() < source.length()
			source_budget -= str(entry["source"]).length()
		scene.append(entry)
	context["scene"] = scene
	context["scene_truncated"] = not pending.is_empty()
	context["prefabs"] = preload("res://addons/roblox_studio/studio_prefab_library.gd").entries()
	context["player_settings"] = _get_current_player_settings()
	context["environment"] = current_roblox_environment_settings.duplicate(true)
	context["asset_candidates"] = preload("res://addons/roblox_studio/toolbox_asset_library.gd").ai_candidates(query) if not query.is_empty() else []
	return context

func _studio_ai_source_feedback(actions: Variant) -> String:
	if not actions is Array:
		return ""
	var feedback: Array[String] = []
	for action in actions:
		if not action is Dictionary or not str(action.get("type", "")) in ["create_script", "update_script"]:
			continue
		var source := str(action.get("source", ""))
		var validation: Dictionary = LuaScriptEngine.validate_script_source(source)
		for problem in preload("res://addons/roblox_studio/roblox_script_contract.gd").errors(source):
			feedback.append("%s: %s" % [action.get("name", "Script"), problem])
		if not bool(validation.get("ok", false)):
			feedback.append("%s: %s\nSource: %s" % [action.get("name", "Script"), validation.get("error", "Invalid Lua"), source.left(600)])
	return "\n".join(feedback)


func _normalize_studio_ai_editor_response(response: Dictionary) -> Dictionary:
	if response.has("actions") or not bool(response.get("ok", false)):
		return response
	var payload: Variant = response.get("data", {})
	if payload is String:
		var parsed_payload: Variant = JSON.parse_string((payload as String).strip_edges())
		if parsed_payload != null:
			payload = parsed_payload
	if not payload is Dictionary:
		return response
	var normalized: Dictionary = response.duplicate(true)
	for key_variant in (payload as Dictionary).keys():
		normalized[key_variant] = (payload as Dictionary)[key_variant]
	normalized["ok"] = bool(response.get("ok", false)) and bool((payload as Dictionary).get("ok", true))
	return normalized


func _append_studio_ai_message(author: String, message: String, color: String) -> void:
	if studio_ai_result_label == null or not is_instance_valid(studio_ai_result_label):
		return
	var safe_author := author.replace("[", "(").replace("]", ")")
	var safe_message := message.replace("[", "(").replace("]", ")")
	if studio_ai_result_label.text.contains("Ask for a build"):
		studio_ai_result_label.clear()
	studio_ai_result_label.append_text("[b]%s[/b]\n[color=%s]%s[/color]\n\n" % [safe_author, color, safe_message])
	studio_ai_result_label.scroll_to_line(maxi(0, studio_ai_result_label.get_line_count() - 1))


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _execute_command_bar(source: String) -> void:
	var command := source.strip_edges()
	if command.is_empty():
		return
	if command_history.is_empty() or command_history.back() != command:
		command_history.append(command)
		if command_history.size() > 64:
			command_history.pop_front()
	command_history_cursor = command_history.size()
	var context := _get_selected_editor_node()
	if context == null:
		context = data_model if data_model != null else self
	var result: Dictionary = LuaScriptEngine.run_script(command, context)
	if bool(result.get("ok", false)):
		toolbar_status_label.text = "Command completed%s" % (" (scheduled)" if bool(result.get("scheduled", false)) else "")
		command_line_edit.clear()
	else:
		toolbar_status_label.text = "Command error: %s" % str(result.get("error", "Unknown error"))


func _on_command_bar_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or command_history.is_empty():
		return
	if event.keycode == KEY_UP:
		command_history_cursor = maxi(0, command_history_cursor - 1)
		command_line_edit.text = command_history[command_history_cursor]
		command_line_edit.caret_column = command_line_edit.text.length()
		command_line_edit.accept_event()
	elif event.keycode == KEY_DOWN:
		command_history_cursor = mini(command_history.size(), command_history_cursor + 1)
		command_line_edit.text = "" if command_history_cursor >= command_history.size() else command_history[command_history_cursor]
		command_line_edit.caret_column = command_line_edit.text.length()
		command_line_edit.accept_event()


func _show_command_history_popup(anchor: Control) -> void:
	var popup := PopupMenu.new()
	if command_history.is_empty():
		popup.add_item("No commands yet")
		popup.set_item_disabled(0, true)
	else:
		var start := maxi(0, command_history.size() - 12)
		for index in range(start, command_history.size()):
			popup.add_item(command_history[index].left(80), index)
		popup.id_pressed.connect(func(index: int) -> void:
			command_line_edit.text = command_history[index]
			command_line_edit.caret_column = command_line_edit.text.length()
			command_line_edit.grab_focus()
		)
	add_child(popup)
	popup.position = Vector2i(anchor.global_position + Vector2(0, -popup.size.y))
	popup.popup()

func _build_properties_dock(parent: Control) -> VBoxContainer:
	var properties_root := VBoxContainer.new()
	properties_root.name = "Properties"
	properties_root.add_theme_constant_override("separation", 0)
	parent.add_child(properties_root)
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	header.add_theme_constant_override("separation", 4)
	properties_root.add_child(header)
	properties_title_label = Label.new()
	properties_title_label.text = "Properties"
	properties_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	properties_title_label.add_theme_font_size_override("font_size", 12)
	properties_title_label.add_theme_color_override("font_color", Color("#333333"))
	header.add_child(properties_title_label)
	var close_btn := _create_studio_icon_button("Close", "Close Properties", Vector2(26, 24))
	close_btn.pressed.connect(_set_tool_window_visible.bind("properties", false))
	header.add_child(close_btn)
	properties_filter_edit = LineEdit.new()
	properties_filter_edit.name = "PropertiesFilter"
	properties_filter_edit.placeholder_text = "Filter Properties (Ctrl+Shift+P)"
	properties_filter_edit.custom_minimum_size = Vector2(0, 26)
	properties_filter_edit.add_theme_font_size_override("font_size", 11)
	properties_filter_edit.add_theme_stylebox_override("normal", _studio_line_edit_style())
	properties_filter_edit.text_changed.connect(_on_properties_filter_changed)
	properties_root.add_child(properties_filter_edit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	properties_root.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.name = "PropertiesContent"
	panel.add_theme_constant_override("separation", 4)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	return panel

func _build_toolbar_white() -> void:
	var toolbar_container := PanelContainer.new()
	toolbar_container.name = "ToolbarContainer"
	toolbar_container.custom_minimum_size = Vector2(0, 92)
	toolbar_container.add_theme_stylebox_override("panel", _studio_panel_style(Color("#FAFAFA"), Color("#D4D4D4"), 1))
	main_container.add_child(toolbar_container)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	toolbar_container.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	margin.add_child(vbox)

	_build_ribbon_tabs(vbox)
	ribbon_tools_container = HBoxContainer.new()
	ribbon_tools_container.name = "RibbonTools"
	ribbon_tools_container.custom_minimum_size = Vector2(0, 62)
	ribbon_tools_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _is_mobile_studio_runtime() else Control.SIZE_EXPAND_FILL
	ribbon_tools_container.add_theme_constant_override("separation", 3)
	if _is_mobile_studio_runtime():
		var ribbon_scroll := ScrollContainer.new()
		ribbon_scroll.name = "RibbonToolsScroll"
		ribbon_scroll.custom_minimum_size = Vector2(0, 62)
		ribbon_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		ribbon_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ribbon_scroll.scroll_deadzone = 12
		ribbon_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(ribbon_scroll)
		ribbon_scroll.add_child(ribbon_tools_container)
	else:
		vbox.add_child(ribbon_tools_container)
	_populate_home_ribbon()
	_refresh_toolbar_states()

func _clear_ribbon_tools() -> void:
	if ribbon_tools_container == null:
		return
	for child in ribbon_tools_container.get_children():
		ribbon_tools_container.remove_child(child)
		child.queue_free()
	shape_buttons.clear()
	transform_mode_buttons.clear()

func _populate_home_ribbon() -> void:
	_clear_ribbon_tools()
	if ribbon_tools_container == null:
		return
	var transform_group := _create_ribbon_group("Tools")
	ribbon_tools_container.add_child(transform_group)
	var select_btn := _create_ribbon_button("Select", 42)
	select_btn.toggle_mode = true
	select_btn.pressed.connect(_set_shape.bind("Select"))
	_add_to_ribbon_group(transform_group, select_btn)
	shape_buttons["Select"] = select_btn
	for pair in [["move", "Move"], ["scale", "Scale"], ["rotate", "Rotate"], ["transform", "Transform"], ["geometric", "Geometric"]]:
		var mode_key := str(pair[0])
		var mode_title := str(pair[1])
		var mode_btn := _create_ribbon_button(mode_title, 48 if mode_key in ["transform", "geometric"] else 42)
		mode_btn.toggle_mode = true
		mode_btn.set_meta("accent_color", Color("#0066CC"))
		mode_btn.pressed.connect(func() -> void:
			_set_shape("Select")
			_set_transform_mode(mode_key)
		)
		_add_to_ribbon_group(transform_group, mode_btn)
		transform_mode_buttons[mode_key] = mode_btn
		if mode_key == "scale": mode_btn.tooltip_text = "Scale an axis; hold Shift to resize the whole selection uniformly. Model → Resize sets an exact multiplier."
	_add_to_ribbon_group(transform_group, _create_snap_controls())

	ribbon_tools_container.add_child(_create_ribbon_separator())

	var insert_group := _create_ribbon_group("Insert")
	ribbon_tools_container.add_child(insert_group)
	_add_to_ribbon_group(insert_group, _create_part_insert_control())
	_add_ribbon_action(insert_group, "Terrain", _open_terrain_panel_popup, 48)
	_add_ribbon_action(insert_group, "Character", _insert_character_placeholder, 54)
	_add_ribbon_action(insert_group, "GUI", _insert_gui_placeholder, 46)
	_add_ribbon_action(insert_group, "Script", _insert_script_from_ribbon, 48)
	_add_ribbon_action(insert_group, "Audio", _on_music_browse_pressed, 48)
	_add_ribbon_action(insert_group, "AI", _show_studio_ai_window, 42)
	_add_ribbon_action(insert_group, "Import", _on_import_rbxl_pressed, 48)

	ribbon_tools_container.add_child(_create_ribbon_separator())

	var object_group := _create_ribbon_group("Edit")
	ribbon_tools_container.add_child(object_group)
	var material_btn := _create_ribbon_button("Material", 52)
	material_btn.pressed.connect(_open_material_selector)
	_add_to_ribbon_group(object_group, material_btn)
	color_picker = _create_ribbon_button("Color", 48)
	color_picker.pressed.connect(_open_color_selector)
	_add_to_ribbon_group(object_group, color_picker)
	var group_btn := _create_ribbon_button("Group", 44)
	group_btn.pressed.connect(_group_selected_blocks)
	_add_to_ribbon_group(object_group, group_btn)
	var lock_btn := _create_ribbon_button("Lock", 40)
	lock_btn.pressed.connect(_toggle_selected_lock)
	_add_to_ribbon_group(object_group, lock_btn)
	var anchor_btn := _create_ribbon_button("Anchor", 44)
	anchor_btn.pressed.connect(_toggle_selected_anchor)
	_add_to_ribbon_group(object_group, anchor_btn)

	ribbon_tools_container.add_child(_create_ribbon_separator())

	var windows_group := _create_ribbon_group("Windows")
	ribbon_tools_container.add_child(windows_group)
	for pair in [["Explorer", "explorer"], ["Properties", "properties"], ["Toolbox", "toolbox"], ["Assets", "assets"]]:
		var window_btn := _create_ribbon_button(pair[0], 50)
		window_btn.pressed.connect(_toggle_tool_window.bind(pair[1]))
		_add_to_ribbon_group(windows_group, window_btn)

func _create_part_insert_control() -> Control:
	var cluster := HBoxContainer.new()
	cluster.add_theme_constant_override("separation", 0)
	var part_btn := _create_ribbon_button("Part", 48)
	part_btn.pressed.connect(_place_shape_from_ribbon.bind("Box"))
	shape_buttons["Box"] = part_btn
	cluster.add_child(part_btn)
	var menu := MenuButton.new()
	menu.text = ""
	menu.icon = _get_toolbar_icon("ChevronDown", Color("#34373C"))
	menu.add_theme_color_override("icon_normal_color", Color("#34373C"))
	menu.add_theme_color_override("icon_hover_color", Color("#1677D2"))
	menu.tooltip_text = "Choose Part type: Block, Truss / Ladder, Water, Spawn..."
	menu.custom_minimum_size = Vector2(26, 50)
	_style_white_button(menu)
	var shape_specs := [
		["Block", "Box"],
		["Ball", "Sphere"],
		["Cylinder", "Cylinder"],
		["Wedge", "Wedge"],
		["Corner Wedge", "CornerWedge"],
		["Truss / Ladder", "Truss"],
		["Water", "Water"],
		["Spawn", "Spawn"],
		["Checkpoint", "Checkpoint"],
		["Teleport", "Teleport"],
	]
	for shape_spec in shape_specs:
		menu.get_popup().add_item(str(shape_spec[0]))
	menu.get_popup().index_pressed.connect(func(index: int) -> void:
		_place_shape_from_ribbon(str(shape_specs[index][1]))
	)
	cluster.add_child(menu)
	return cluster

func _add_ribbon_action(group: VBoxContainer, label_text: String, callback: Callable, width: float = 50.0) -> Button:
	var button := _create_ribbon_button(label_text, width)
	if not callback.is_null():
		button.pressed.connect(callback)
	else:
		button.disabled = true
	_add_to_ribbon_group(group, button)
	return button

func _build_studio_menu_bar() -> void:
	var menu_panel := PanelContainer.new()
	menu_panel.name = "MenuBar"
	menu_panel.custom_minimum_size = Vector2(0, 30)
	menu_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F5F5F5"), Color("#DDDDDD"), 1))
	main_container.add_child(menu_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	if _is_mobile_studio_runtime():
		var menu_scroll := ScrollContainer.new()
		menu_scroll.name = "MenuBarScroll"
		menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		menu_scroll.scroll_deadzone = 12
		menu_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		menu_panel.add_child(menu_scroll)
		menu_scroll.add_child(row)
	else:
		menu_panel.add_child(row)
	for menu_name in ["File", "Edit", "View", "Plugins", "Test", "Window", "Help"]:
		row.add_child(_create_studio_menu_button(menu_name))
	if not _is_mobile_studio_runtime():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var test_mode := OptionButton.new()
	test_mode.name = "TestMode"
	test_mode.custom_minimum_size = Vector2(90, 24)
	test_mode.add_item("Test")
	test_mode.add_item("Server")
	test_mode.add_item("Client")
	test_mode.add_theme_font_size_override("font_size", 11)
	row.add_child(test_mode)
	for spec in [
		["Play", Color("#0066CC")],
		["Pause", Color("#777777")],
		["Stop", Color("#CC5555")],
		["Reset", Color("#D4841D")],
		["Record", Color("#888888")]
	]:
		var action_name := str(spec[0])
		var btn := Button.new()
		btn.text = ""
		btn.tooltip_text = action_name
		btn.custom_minimum_size = Vector2(30, 24)
		btn.icon = _get_toolbar_icon(action_name, Color("#222222"))
		btn.add_theme_color_override("icon_normal_color", spec[1])
		btn.add_theme_color_override("icon_hover_color", spec[1].lightened(0.12))
		btn.add_theme_color_override("icon_pressed_color", spec[1].darkened(0.12))
		btn.set_meta("accent_color", spec[1])
		_style_white_button(btn)
		btn.pressed.connect(func() -> void:
			_on_studio_test_control_pressed(action_name)
		)
		studio_test_control_buttons[action_name] = btn
		row.add_child(btn)
	_refresh_studio_test_control_states()


func _refresh_studio_test_control_states() -> void:
	for action_variant in studio_test_control_buttons.keys():
		var action_name := str(action_variant)
		var button := studio_test_control_buttons[action_variant] as Button
		if button == null or not is_instance_valid(button):
			continue
		button.disabled = (
			not (action_name in ["Stop", "Reset"])
			if studio_playtest_active
			else action_name in ["Pause", "Stop", "Reset"]
		)
	for action_variant in mobile_studio_action_buttons.keys():
		var action_name := str(action_variant)
		var mobile_button := mobile_studio_action_buttons[action_variant] as Button
		if mobile_button == null or not is_instance_valid(mobile_button):
			continue
		mobile_button.disabled = (
			not (action_name in ["Stop", "Reset"])
			if studio_playtest_active
			else action_name in ["Stop", "Reset"]
		)
	if mobile_studio_joystick_base != null:
		mobile_studio_joystick_base.visible = not studio_playtest_active


func _set_studio_playtest_ui_locked(locked: bool) -> void:
	if locked:
		studio_playtest_control_state.clear()
		var controls: Array[Control] = []
		_collect_studio_controls(main_container, controls)
		var stop_button := studio_test_control_buttons.get("Stop") as Button
		var reset_button := studio_test_control_buttons.get("Reset") as Button
		for control in controls:
			if control == null or not is_instance_valid(control):
				continue
			if control == viewport_container_node or (viewport_container_node != null and viewport_container_node.is_ancestor_of(control)):
				continue
			if control == stop_button or control == reset_button:
				continue
			var state := {
				"node": control,
				"mouse_filter": control.mouse_filter,
				"focus_mode": control.focus_mode,
			}
			if control is BaseButton:
				state["disabled"] = (control as BaseButton).disabled
				(control as BaseButton).disabled = true
			elif control is LineEdit:
				state["editable"] = (control as LineEdit).editable
				(control as LineEdit).editable = false
			elif control is TextEdit:
				state["editable"] = (control as TextEdit).editable
				(control as TextEdit).editable = false
			elif control is SpinBox:
				state["editable"] = (control as SpinBox).editable
				(control as SpinBox).editable = false
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.focus_mode = Control.FOCUS_NONE
			studio_playtest_control_state.append(state)
		if viewport_container_node != null:
			viewport_container_node.mouse_filter = Control.MOUSE_FILTER_STOP
			viewport_container_node.focus_mode = Control.FOCUS_ALL
			viewport_container_node.call_deferred("grab_focus")
		if stop_button != null:
			stop_button.disabled = false
			stop_button.mouse_filter = Control.MOUSE_FILTER_STOP
			stop_button.focus_mode = Control.FOCUS_ALL
		if transform_gizmo_root != null:
			transform_gizmo_root.visible = false
		_clear_selection_box_visual()
	else:
		for state in studio_playtest_control_state:
			var control_variant: Variant = state.get("node")
			if not is_instance_valid(control_variant) or not (control_variant is Control):
				continue
			var control := control_variant as Control
			control.mouse_filter = int(state.get("mouse_filter", Control.MOUSE_FILTER_STOP))
			control.focus_mode = int(state.get("focus_mode", Control.FOCUS_NONE))
			if control is BaseButton and state.has("disabled"):
				(control as BaseButton).disabled = bool(state["disabled"])
			elif control is LineEdit and state.has("editable"):
				(control as LineEdit).editable = bool(state["editable"])
			elif control is TextEdit and state.has("editable"):
				(control as TextEdit).editable = bool(state["editable"])
			elif control is SpinBox and state.has("editable"):
				(control as SpinBox).editable = bool(state["editable"])
		studio_playtest_control_state.clear()
	_refresh_studio_test_control_states()


func _collect_studio_controls(root: Node, output: Array[Control]) -> void:
	if root == null:
		return
	for child in root.get_children(true):
		if child is Control:
			output.append(child as Control)
		_collect_studio_controls(child, output)

func _create_studio_menu_button(menu_name: String) -> MenuButton:
	var menu := MenuButton.new()
	menu.name = "%sMenu" % menu_name
	menu.text = menu_name
	menu.flat = true
	menu.custom_minimum_size = Vector2(64, 24)
	menu.add_theme_font_size_override("font_size", 11)
	menu.add_theme_color_override("font_color", Color("#333333"))
	menu.add_theme_color_override("font_hover_color", Color("#0066CC"))
	var popup := menu.get_popup()
	match menu_name:
		"File":
			popup.add_item("New", 101)
			popup.add_item("Open Place...", 107)
			popup.add_item("Import Roblox Place...", 102)
			popup.add_item("Open Maps Folder", 108)
			popup.add_separator()
			popup.add_item("Save", 103)
			popup.add_item("Save As...", 104)
			popup.add_item("Publish", 105)
			popup.add_separator()
			popup.add_item("Capture Viewport", 109)
			popup.add_separator()
			popup.add_item("Exit", 106)
		"Edit":
			popup.add_item("Undo", 201)
			popup.add_item("Redo", 202)
			popup.add_separator()
			popup.add_item("Cut", 203)
			popup.add_item("Copy", 204)
			popup.add_item("Paste", 205)
			popup.add_item("Duplicate", 208)
			popup.add_item("Delete", 206)
			popup.add_separator()
			popup.add_item("Group", 209)
			popup.add_item("Ungroup", 210)
			popup.add_separator()
			popup.add_item("Lock Selection", 211)
			popup.add_item("Unlock Selection", 212)
			popup.add_item("Anchor Selection", 213)
			popup.add_item("Unanchor Selection", 214)
			popup.add_separator()
			popup.add_item("Select All", 207)
		"View":
			popup.add_item("Zoom In", 305)
			popup.add_item("Zoom Out", 306)
			popup.add_check_item("Full Screen", 307)
			popup.set_item_checked(popup.get_item_index(307), DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
			popup.add_separator()
			popup.add_item("Reset Camera", 301)
			popup.add_check_item("Show Grid", 302)
			popup.set_item_checked(popup.get_item_index(302), show_grid_enabled)
			popup.add_check_item("Wireframe Rendering", 308)
			popup.set_item_checked(popup.get_item_index(308), studio_wireframe_enabled)
			popup.add_check_item("Show Game UI", 309)
			popup.set_item_checked(popup.get_item_index(309), studio_gui_preview_enabled)
			popup.add_check_item("Show Colliders", 303)
			popup.set_item_checked(popup.get_item_index(303), show_colliders_enabled)
			popup.add_item("Focus Selection", 304)
			popup.add_separator()
			popup.add_item("Expand Explorer", 312)
			popup.add_item("Collapse Explorer", 313)
			popup.add_item("Screenshot", 310)
			popup.add_check_item("Mute Audio", 311)
			popup.set_item_checked(popup.get_item_index(311), studio_audio_muted)
		"Plugins":
			popup.add_item("Plugin Manager", 601)
			popup.add_item("Plugins Folder", 602)
		"Test":
			popup.add_item("Start Test", 401)
			popup.add_item("Pause Test", 403)
			popup.add_item("Stop Test", 402)
			popup.add_item("Reset Character", 405)
			popup.add_item("Record Viewport", 404)
		"Window":
			popup.add_check_item("Explorer", 501)
			popup.set_item_checked(popup.get_item_index(501), true)
			popup.add_check_item("Properties", 502)
			popup.set_item_checked(popup.get_item_index(502), true)
			popup.add_check_item("Toolbox", 503)
			popup.set_item_checked(popup.get_item_index(503), true)
			popup.add_item("Assets", 504)
			popup.add_separator()
			popup.add_item("Output", 506)
			popup.add_item("Command Bar", 507)
			popup.add_item("Insert Object...", 508)
		"Help":
			popup.add_item("Bobux Studio Guide", 701)
			popup.add_item("Technical Architecture Notes", 703)
			popup.add_separator()
			popup.add_item("About Bobux Studio", 702)
	popup.id_pressed.connect(_on_studio_menu_action.bind(menu_name))
	return menu

func _on_studio_menu_action(id: int, _menu_name: String = "") -> void:
	match id:
		101:
			_on_studio_file_menu_id_pressed(1)
		102:
			_on_import_rbxl_pressed()
		103:
			_on_save_button_pressed()
		104:
			_open_save_place_as_dialog()
		105:
			_on_publish_pressed()
		106:
			_on_back_pressed()
		107:
			_open_local_place_dialog()
		108:
			_open_maps_folder()
		109:
			_capture_studio_viewport()
		201:
			_undo_editor_action()
		202:
			_redo_editor_action()
		203:
			_copy_selected_blocks()
			_delete_selected_blocks()
		204:
			_copy_selected_blocks()
		205:
			_paste_clipboard_blocks()
		206:
			_delete_selected_blocks()
		207:
			_select_all_blocks()
		208:
			_duplicate_selected_blocks()
		209:
			_group_selected_blocks()
		210:
			_ungroup_selected_models()
		211:
			_set_selected_locked(true)
		212:
			_set_selected_locked(false)
		213:
			_set_selected_anchored(true)
		214:
			_set_selected_anchored(false)
		301:
			_reset_studio_camera()
		302:
			show_grid_enabled = not show_grid_enabled
			_toggle_grid_visibility(show_grid_enabled)
			_set_studio_menu_item_checked(_menu_name, id, show_grid_enabled)
		303:
			show_colliders_enabled = not show_colliders_enabled
			_toggle_collision_preview(show_colliders_enabled)
			_set_studio_menu_item_checked(_menu_name, id, show_colliders_enabled)
		304:
			_focus_camera_on_selection()
		305:
			_zoom_camera_to_mouse(true, _studio_viewport_center())
		306:
			_zoom_camera_to_mouse(false, _studio_viewport_center())
		307:
			_toggle_studio_fullscreen()
			_set_studio_menu_item_checked(_menu_name, id, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		308:
			_toggle_studio_wireframe()
			_set_studio_menu_item_checked(_menu_name, id, studio_wireframe_enabled)
		309:
			_toggle_studio_gui_preview()
			_set_studio_menu_item_checked(_menu_name, id, studio_gui_preview_enabled)
		310:
			_capture_studio_viewport()
		311:
			_toggle_studio_audio_mute()
			_set_studio_menu_item_checked(_menu_name, id, studio_audio_muted)
		312:
			_set_explorer_collapsed_recursive(false)
		313:
			_set_explorer_collapsed_recursive(true)
		401:
			_start_studio_playtest()
		402:
			_stop_studio_playtest()
		403:
			_toggle_studio_playtest_pause()
		404:
			_capture_studio_viewport()
		405:
			_reset_studio_playtest_character()
		501:
			_toggle_tool_window("explorer")
			_set_studio_menu_item_checked(_menu_name, id, explorer_dock_panel != null and explorer_dock_panel.visible)
		502:
			_toggle_tool_window("properties")
			_set_studio_menu_item_checked(_menu_name, id, properties_dock_panel != null and properties_dock_panel.visible)
		503:
			_toggle_tool_window("toolbox")
			_set_studio_menu_item_checked(_menu_name, id, toolbox_dock_panel != null and toolbox_dock_panel.visible)
		504:
			_open_assets_dialog()
		506:
			_open_output_panel()
		507:
			_focus_command_bar()
		508:
			_open_insert_object_dialog()
		601:
			_open_plugin_manager_dialog()
		602:
			_open_plugins_folder()
		701:
			_open_studio_user_guide()
		702:
			_show_studio_about_dialog()
		703:
			_open_studio_architecture_guide()


func _set_studio_menu_item_checked(menu_name: String, id: int, checked: bool) -> void:
	if main_container == null or menu_name.is_empty():
		return
	var menu := main_container.find_child("%sMenu" % menu_name, true, false) as MenuButton
	if menu == null:
		return
	var popup := menu.get_popup()
	var index := popup.get_item_index(id)
	if index >= 0 and popup.is_item_checkable(index):
		popup.set_item_checked(index, checked)


func _studio_viewport_center() -> Vector2:
	if viewport_container_node != null and is_instance_valid(viewport_container_node):
		return viewport_container_node.size * 0.5
	return Vector2(get_viewport().size) * 0.5


func _toggle_studio_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		if toolbar_status_label:
			toolbar_status_label.text = "Full screen is unavailable in headless mode"
		return
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if toolbar_status_label:
		toolbar_status_label.text = "Full screen %s" % ("disabled" if fullscreen else "enabled")


func _toggle_studio_wireframe() -> void:
	var viewport := _get_studio_subviewport()
	if viewport == null:
		return
	studio_wireframe_enabled = not studio_wireframe_enabled
	viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if studio_wireframe_enabled else Viewport.DEBUG_DRAW_DISABLED
	if toolbar_status_label:
		toolbar_status_label.text = "Wireframe %s" % ("enabled" if studio_wireframe_enabled else "disabled")


func _toggle_studio_gui_preview() -> void:
	studio_gui_preview_enabled = not studio_gui_preview_enabled
	if studio_gui_preview_enabled or studio_playtest_active:
		await _refresh_roblox_gui_preview()
	else:
		_clear_roblox_gui_preview()
	if toolbar_status_label:
		toolbar_status_label.text = "Game UI preview %s" % ("shown" if studio_gui_preview_enabled else "hidden")


func _toggle_studio_audio_mute() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	studio_audio_muted = not studio_audio_muted
	AudioServer.set_bus_mute(master_bus, studio_audio_muted)
	if toolbar_status_label:
		toolbar_status_label.text = "Studio audio %s" % ("muted" if studio_audio_muted else "enabled")


func _open_studio_architecture_guide() -> void:
	var guide_path := "res://docs/ROBLOX_CHARACTER_AND_INVENTORY_PARITY_PROMPT.md"
	if not FileAccess.file_exists(guide_path):
		if toolbar_status_label:
			toolbar_status_label.text = "Architecture guide is missing"
		return
	OS.shell_open(ProjectSettings.globalize_path(guide_path))
	if toolbar_status_label:
		toolbar_status_label.text = "Opened Studio architecture guide"


func _open_studio_user_guide() -> void:
	var topics: Array = StudioGuideDataClass.get_topics()
	if topics.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Studio guide is unavailable"
		return

	var dialog := AcceptDialog.new()
	dialog.title = "Bobux Studio Guide"
	dialog.ok_button_text = "Close"
	dialog.exclusive = true
	add_child(dialog)

	var compact := _is_mobile_studio_runtime() or get_viewport_rect().size.x < 900.0
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(700, 520) if compact else Vector2(1080, 680)
	root.add_theme_constant_override("separation", 10)
	dialog.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var heading := Label.new()
	heading.text = "Bobux Studio: подробное руководство"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 24 if compact else 28)
	heading.add_theme_color_override("font_color", Color("#F4F5F7"))
	header.add_child(heading)
	var progress := Label.new()
	progress.add_theme_color_override("font_color", Color("#B7BBC2"))
	header.add_child(progress)

	var topic_picker: OptionButton = null
	var topic_list: ItemList = null
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 17 if compact else 18)
	body.add_theme_font_size_override("bold_font_size", 17 if compact else 18)
	body.add_theme_font_size_override("mono_font_size", 16 if compact else 17)
	body.add_theme_constant_override("line_separation", 5)
	body.add_theme_color_override("default_color", Color("#E6E8EC"))

	if compact:
		topic_picker = OptionButton.new()
		topic_picker.custom_minimum_size = Vector2(0, 42)
		topic_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for topic_variant in topics:
			var topic: Dictionary = topic_variant if topic_variant is Dictionary else {}
			topic_picker.add_item(str(topic.get("title", "Раздел")))
		root.add_child(topic_picker)
		root.add_child(body)
	else:
		var split := HSplitContainer.new()
		split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		split.split_offset = 300
		root.add_child(split)
		topic_list = ItemList.new()
		topic_list.custom_minimum_size = Vector2(292, 0)
		topic_list.add_theme_font_size_override("font_size", 16)
		topic_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		topic_list.allow_reselect = true
		for topic_variant in topics:
			var topic: Dictionary = topic_variant if topic_variant is Dictionary else {}
			topic_list.add_item(str(topic.get("title", "Раздел")))
		split.add_child(topic_list)
		var body_margin := MarginContainer.new()
		body_margin.add_theme_constant_override("margin_left", 14)
		body_margin.add_child(body)
		split.add_child(body_margin)

	var current_index := [0]
	var show_topic := func(index: int) -> void:
		var safe_index := clampi(index, 0, topics.size() - 1)
		current_index[0] = safe_index
		var topic: Dictionary = topics[safe_index] if topics[safe_index] is Dictionary else {}
		body.text = "[font_size=%d][b]%s[/b][/font_size]\n\n%s" % [24 if compact else 27, str(topic.get("title", "Studio Guide")), str(topic.get("body", ""))]
		body.scroll_to_line(0)
		progress.text = "%d / %d" % [safe_index + 1, topics.size()]
		if topic_picker != null:
			topic_picker.select(safe_index)
		if topic_list != null:
			topic_list.select(safe_index)

	if topic_picker != null:
		topic_picker.item_selected.connect(show_topic)
	if topic_list != null:
		topic_list.item_selected.connect(show_topic)

	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_END
	navigation.add_theme_constant_override("separation", 8)
	root.add_child(navigation)
	var previous_button := Button.new()
	previous_button.text = "Назад"
	previous_button.custom_minimum_size = Vector2(110, 38)
	previous_button.pressed.connect(func() -> void: show_topic.call(current_index[0] - 1))
	navigation.add_child(previous_button)
	var next_button := Button.new()
	next_button.text = "Далее"
	next_button.custom_minimum_size = Vector2(110, 38)
	next_button.pressed.connect(func() -> void: show_topic.call(current_index[0] + 1))
	navigation.add_child(next_button)

	show_topic.call(0)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(700, 560) if compact else Vector2i(960, 680))
	if toolbar_status_label:
		toolbar_status_label.text = "Opened Bobux Studio guide"


func _show_studio_about_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "About Bobux Studio"
	dialog.dialog_text = "Bobux Studio\nRoblox-style DataModel editor, Luau runtime and play-test environment."
	dialog.ok_button_text = "Close"
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 190))

func _build_ribbon_tabs(parent: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "RibbonTabs"
	tabs.custom_minimum_size = Vector2(0, 26)
	tabs.add_theme_constant_override("separation", 4)
	if _is_mobile_studio_runtime():
		var tabs_scroll := ScrollContainer.new()
		tabs_scroll.name = "RibbonTabsScroll"
		tabs_scroll.custom_minimum_size = Vector2(0, 26)
		tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs_scroll.scroll_deadzone = 12
		tabs_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		parent.add_child(tabs_scroll)
		tabs_scroll.add_child(tabs)
	else:
		parent.add_child(tabs)
		var left_spacer := Control.new()
		left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(left_spacer)
	for tab_name in ["Home", "Avatar", "UI", "Script", "Model", "Plugins", "Misc", "Learn", "+"]:
		var tab := Button.new()
		tab.text = tab_name
		tab.flat = true
		tab.custom_minimum_size = Vector2(92 if tab_name != "+" else 38, 24)
		tab.add_theme_font_size_override("font_size", 11)
		tab.add_theme_color_override("font_color", Color("#333333"))
		tab.add_theme_color_override("font_hover_color", Color("#0066CC"))
		if tab_name == "Home":
			tab.add_theme_stylebox_override("normal", _studio_panel_style(Color("#E8E8E8"), Color("#E8E8E8"), 0, 4))
		tab.pressed.connect(_on_ribbon_tab_pressed.bind(tab_name))
		ribbon_tab_buttons[tab_name] = tab
		tabs.add_child(tab)
	if not _is_mobile_studio_runtime():
		var right_spacer := Control.new()
		right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(right_spacer)

func _on_ribbon_tab_pressed(tab_name: String) -> void:
	if tab_name == "Learn":
		preload("res://addons/roblox_studio/studio_script_library.gd").open(self, _apply_studio_ai_actions)
		return
	if tab_name == "+":
		_open_plugin_manager_dialog()
		return
	active_ribbon_tab = tab_name
	for name_variant in ribbon_tab_buttons.keys():
		var name := str(name_variant)
		var button := ribbon_tab_buttons[name] as Button
		if button == null:
			continue
		if name == active_ribbon_tab:
			button.add_theme_stylebox_override("normal", _studio_panel_style(Color("#E6E7E9"), Color("#E6E7E9"), 0, 4))
			button.add_theme_color_override("font_color", Color("#1E2024"))
		else:
			button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			button.add_theme_color_override("font_color", Color("#4A4D52"))
	_rebuild_ribbon_for_active_tab()
	if toolbar_status_label:
		toolbar_status_label.text = "%s ribbon" % tab_name

func _rebuild_ribbon_for_active_tab() -> void:
	match active_ribbon_tab:
		"Avatar":
			_populate_avatar_ribbon()
		"UI":
			_populate_ui_ribbon()
		"Script":
			_populate_script_ribbon()
		"Model":
			_populate_model_ribbon()
		"Plugins":
			_populate_plugins_ribbon()
		"Misc":
			_populate_misc_ribbon()
		_:
			_populate_home_ribbon()
	_refresh_toolbar_states()

func _populate_avatar_ribbon() -> void:
	_clear_ribbon_tools()
	var avatar_group := _create_ribbon_group("Avatar")
	ribbon_tools_container.add_child(avatar_group)
	_add_ribbon_action(avatar_group, "Settings", _open_avatar_settings_dialog, 56)
	_add_ribbon_action(avatar_group, "Character", _insert_character_placeholder, 60)
	_add_ribbon_action(avatar_group, "Setup", _setup_selected_character, 48)
	_add_ribbon_action(avatar_group, "Accessory", _insert_accessory_container, 60)
	_add_ribbon_action(avatar_group, "Adapt", _adapt_selected_character, 48)
	_add_ribbon_action(avatar_group, "Clip Editor", _open_clip_editor, 62)

func _populate_ui_ribbon() -> void:
	_clear_ribbon_tools()
	var insert_group := _create_ribbon_group("Insert")
	ribbon_tools_container.add_child(insert_group)
	_add_ribbon_action(insert_group, "GUI", _insert_gui_placeholder, 46)
	for spec in [["Frame", "Frame"], ["Label", "TextLabel"], ["Button", "TextButton"], ["Input", "TextBox"], ["Image", "ImageLabel"]]:
		_add_ribbon_action(insert_group, str(spec[0]), _insert_gui_instance.bind(str(spec[1])), 50)
	ribbon_tools_container.add_child(_create_ribbon_separator())
	var layout_group := _create_ribbon_group("Layout")
	ribbon_tools_container.add_child(layout_group)
	_add_ribbon_action(layout_group, "Appearance", _focus_selected_gui_properties, 66)
	_add_ribbon_action(layout_group, "List", _insert_gui_instance.bind("UIListLayout"), 42)
	_add_ribbon_action(layout_group, "Grid", _insert_gui_instance.bind("UIGridLayout"), 42)
	_add_ribbon_action(layout_group, "Corner", _insert_gui_instance.bind("UICorner"), 50)
	_add_ribbon_action(layout_group, "Stroke", _insert_gui_instance.bind("UIStroke"), 48)
	_add_ribbon_action(layout_group, "Constraint", _insert_gui_instance.bind("UIAspectRatioConstraint"), 62)

func _populate_script_ribbon() -> void:
	_clear_ribbon_tools()
	var navigation_group := _create_ribbon_group("Navigate")
	ribbon_tools_container.add_child(navigation_group)
	_add_ribbon_action(navigation_group, "Back", _script_history_back, 42)
	_add_ribbon_action(navigation_group, "Forward", _script_history_forward, 48)
	var source_group := _create_ribbon_group("Source")
	ribbon_tools_container.add_child(source_group)
	_add_ribbon_action(source_group, "Script", _insert_script_from_ribbon, 48)
	_add_ribbon_action(source_group, "Format", _format_active_script, 50)
	_add_ribbon_action(source_group, "Find", _find_in_active_script, 42)
	_add_ribbon_action(source_group, "Go To Line", _go_to_line_in_active_script, 58)
	var debug_group := _create_ribbon_group("Debug")
	ribbon_tools_container.add_child(debug_group)
	_add_ribbon_action(debug_group, "Command", _focus_command_bar, 54)
	_add_ribbon_action(debug_group, "Output", _open_output_panel, 48)
	_add_ribbon_action(debug_group, "Breakpoints", _toggle_active_script_breakpoint, 64)
	_add_ribbon_action(debug_group, "Analysis", _analyze_active_script, 52)

func _populate_model_ribbon() -> void:
	_clear_ribbon_tools()
	var tools_group := _create_ribbon_group("Tools")
	ribbon_tools_container.add_child(tools_group)
	for pair in [["select", "Select"], ["move", "Move"], ["scale", "Scale"], ["rotate", "Rotate"]]:
		var key := str(pair[0])
		var button := _create_ribbon_button(str(pair[1]), 44)
		button.toggle_mode = true
		button.pressed.connect(func() -> void:
			if key == "select":
				_set_shape("Select")
			else:
				_set_transform_mode(key)
		)
		_add_to_ribbon_group(tools_group, button)
		if key == "select":
			shape_buttons["Select"] = button
		else:
			transform_mode_buttons[key] = button
	_add_ribbon_action(tools_group, "Resize", _open_uniform_scale_dialog, 52)
	var insert_group := _create_ribbon_group("Insert")
	ribbon_tools_container.add_child(insert_group)
	_add_to_ribbon_group(insert_group, _create_part_insert_control())
	_add_ribbon_action(insert_group, "Effect", _insert_effect_for_selection, 48)
	_add_ribbon_action(insert_group, "Attachment", _insert_attachment_for_selection, 62)
	_add_ribbon_action(insert_group, "Constraint", _insert_constraint_for_selection, 62)
	_add_ribbon_action(insert_group, "Weld", _weld_selected_blocks, 44)
	var edit_group := _create_ribbon_group("Edit")
	ribbon_tools_container.add_child(edit_group)
	_add_ribbon_action(edit_group, "Material", _open_material_selector, 54)
	_add_ribbon_action(edit_group, "Color", _open_color_selector, 44)
	_add_ribbon_action(edit_group, "Group", _group_selected_blocks, 46)
	_add_ribbon_action(edit_group, "Lock", _toggle_selected_lock, 42)
	_add_ribbon_action(edit_group, "Anchor", _toggle_selected_anchor, 48)
	_add_ribbon_action(edit_group, "Align", _align_selected_blocks, 44)

func _open_uniform_scale_dialog() -> void:
	if _is_studio_editing_locked(): return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Размер модели целиком"
	dialog.ok_button_text = "Применить"
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = "Множитель по всем осям (2 = вдвое больше):"
	column.add_child(label)
	var factor := SpinBox.new()
	factor.min_value = 0.01
	factor.max_value = 100
	factor.step = 0.05
	factor.value = 1
	column.add_child(factor)
	dialog.add_child(column)
	dialog.confirmed.connect(func(): _scale_selection_uniformly(factor.value); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(440, 130))

func _scale_selection_uniformly(factor: float) -> void:
	if _is_studio_editing_locked() or not is_finite(factor) or factor <= 0: return
	factor = clampf(factor, 0.01, 100.0)
	var target := _get_selected_editor_node()
	var model: Node3D = null
	var cursor := target
	while is_instance_valid(cursor) and cursor != placement_parent:
		if cursor is Node3D and str(cursor.get_meta("roblox_class", "")) in ["Model", "Tool"]: model = cursor
		cursor = cursor.get_parent()
	if model != null:
		model.scale *= factor
		model.set_meta("ModelScale", model.scale.x)
		var properties: Dictionary = model.get_meta("roblox_properties", {}).duplicate(true)
		properties["Scale"] = model.scale.x
		model.set_meta("roblox_properties", properties)
	else:
		var pivot := _get_selection_pivot()
		for block in _get_valid_selected_blocks():
			block.global_position = pivot + (block.global_position - pivot) * factor
			block.scale *= factor
			_update_block_collision(block)
	_refresh_explorer()
	_update_transform_gizmo()
	_commit_editor_history("Resize model ×%s" % factor)

func _populate_plugins_ribbon() -> void:
	_clear_ribbon_tools()
	var plugin_group := _create_ribbon_group("Plugins")
	ribbon_tools_container.add_child(plugin_group)
	_add_ribbon_action(plugin_group, "Manager", _open_plugin_manager_dialog, 54)
	_add_ribbon_action(plugin_group, "Folder", _open_plugins_folder, 48)
	_add_ribbon_action(plugin_group, "Проверить карту", _audit_studio_map, 112)
	_add_ribbon_action(plugin_group, "Boblox", _open_boblox_wallet, 60)

func _audit_studio_map() -> void:
	if _is_studio_editing_locked(): return
	var roots: Array = [placement_parent]
	for service in ["StarterPack", "StarterGui", "StarterPlayer", "ServerScriptService", "ServerStorage", "ReplicatedStorage"]:
		roots.append(data_model.ensure_service(service))
	var issues := preload("res://addons/roblox_studio/studio_map_audit.gd").inspect(roots, get_tree().root.get_node("LuaScriptEngine"))
	var dialog := AcceptDialog.new()
	dialog.title = "Проверка карты · Lua и структура"
	var text_ := TextEdit.new()
	text_.editable = false
	text_.custom_minimum_size = Vector2(700, 380)
	text_.text = "Ошибок синтаксиса и проверяемой структуры не найдено. Поведение скриптов проверьте в Play." if issues.is_empty() else "\n\n".join(issues)
	dialog.add_child(text_)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _open_boblox_wallet() -> void:
	var dialog := preload("res://addons/roblox_studio/boblox_wallet_dialog.gd").new()
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 320))
	dialog.refresh()

func _populate_misc_ribbon() -> void:
	_clear_ribbon_tools()
	var view_group := _create_ribbon_group("Windows")
	ribbon_tools_container.add_child(view_group)
	for pair in [["Explorer", "explorer"], ["Properties", "properties"], ["Toolbox", "toolbox"], ["Assets", "assets"]]:
		_add_ribbon_action(view_group, str(pair[0]), _toggle_tool_window.bind(str(pair[1])), 56)
	var view_tools := _create_ribbon_group("Viewport")
	ribbon_tools_container.add_child(view_tools)
	_add_ribbon_action(view_tools, "Grid", _toggle_grid_from_ribbon, 42)
	_add_ribbon_action(view_tools, "Colliders", _toggle_colliders_from_ribbon, 56)
	_add_ribbon_action(view_tools, "Focus", _focus_camera_on_selection, 44)


func _get_selected_editor_node() -> Node:
	if explorer_selected_node != null and is_instance_valid(explorer_selected_node):
		return explorer_selected_node
	if selected_block != null and is_instance_valid(selected_block):
		return selected_block
	return placement_parent


func _get_selected_character_root() -> Node3D:
	var cursor := _get_selected_editor_node()
	while cursor != null:
		if cursor is Node3D and str(cursor.get_meta("roblox_class", "")) == "Model":
			var humanoid := cursor.find_child("Humanoid", true, false)
			if humanoid != null and str(humanoid.get_meta("roblox_class", "")) == "Humanoid":
				return cursor as Node3D
		cursor = cursor.get_parent()
	if placement_parent != null:
		for candidate in placement_parent.get_children():
			if candidate is Node3D and candidate.is_in_group("studio_character_models"):
				return candidate as Node3D
	return null


func _ensure_character_humanoid(character: Node3D) -> Node:
	var humanoid := character.find_child("Humanoid", true, false)
	if humanoid != null:
		return humanoid
	humanoid = Node.new()
	humanoid.name = "Humanoid"
	humanoid.set_meta("roblox_class", "Humanoid")
	humanoid.set_meta("roblox_properties", {
		"WalkSpeed": 16.0, "JumpPower": 50.0, "HipHeight": 2.0,
		"MaxHealth": 100.0, "Health": 100.0, "AutoRotate": true, "RigType": "R6",
	})
	character.add_child(humanoid, true)
	return humanoid


func _open_avatar_settings_dialog() -> void:
	var character := _get_selected_character_root()
	if character == null:
		_insert_character_placeholder()
		character = _get_selected_character_root()
	if character == null:
		return
	var humanoid := _ensure_character_humanoid(character)
	var properties: Dictionary = humanoid.get_meta("roblox_properties", {}).duplicate(true)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Avatar Settings - %s" % character.name
	dialog.ok_button_text = "Apply"
	add_child(dialog)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size = Vector2(360, 190)
	dialog.add_child(grid)
	var controls: Dictionary = {}
	for spec in [["Walk speed", "WalkSpeed", 0.0, 100.0, 16.0], ["Jump power", "JumpPower", 0.0, 200.0, 50.0], ["Hip height", "HipHeight", 0.0, 20.0, 2.0], ["Max health", "MaxHealth", 1.0, 10000.0, 100.0]]:
		var label := Label.new()
		label.text = str(spec[0])
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = float(spec[2])
		spin.max_value = float(spec[3])
		spin.step = 0.5
		spin.value = float(properties.get(spec[1], spec[4]))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spin)
		controls[spec[1]] = spin
	dialog.confirmed.connect(func() -> void:
		for property_name in controls.keys():
			properties[property_name] = (controls[property_name] as SpinBox).value
		properties["Health"] = minf(float(properties.get("Health", 100.0)), float(properties.get("MaxHealth", 100.0)))
		humanoid.set_meta("roblox_properties", properties)
		_show_properties_for_node(humanoid)
		_commit_editor_history("Avatar Settings")
	)
	dialog.popup_centered(Vector2i(400, 260))


func _setup_selected_character() -> void:
	var character := _get_selected_character_root()
	if character == null:
		_insert_character_placeholder()
		character = _get_selected_character_root()
	if character == null:
		return
	var humanoid := _ensure_character_humanoid(character)
	character.set_meta("PrimaryPart", "HumanoidRootPart")
	character.set_meta("bobux_character_ready", true)
	explorer_selected_node = humanoid
	_refresh_explorer()
	_show_properties_for_node(humanoid)
	_commit_editor_history("Setup Character")
	if toolbar_status_label:
		toolbar_status_label.text = "%s is configured as an R6 Humanoid" % character.name


func _insert_accessory_container() -> void:
	var character := _get_selected_character_root()
	if character == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Select or create a character first"
		return
	var accessory := Node3D.new()
	accessory.name = "Accessory"
	accessory.set_meta("roblox_class", "Accessory")
	accessory.set_meta("AttachmentPoint", "HatAttachment")
	character.add_child(accessory, true)
	var handle := _build_block_instance("Sphere", Color("#D5D8DC"), "Plastic", 0.0, false, "Handle")
	handle.name = "Handle"
	handle.scale = Vector3(0.65, 0.25, 0.65)
	var head := character.find_child("Head", true, false) as Node3D
	handle.position = (head.position if head != null else Vector3(0, 4.6, 0)) + Vector3(0, 0.78, 0)
	handle.set_meta("roblox_class", "Part")
	handle.set_meta("accessory_attachment", "HatAttachment")
	accessory.add_child(handle, true)
	_set_selection([handle])
	_refresh_explorer()
	_commit_editor_history("Insert Accessory")


func _adapt_selected_character() -> void:
	var character := _get_selected_character_root()
	if character == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Select a character model to adapt"
		return
	_ensure_character_humanoid(character)
	var joint_specs := [
		["RootJoint", "HumanoidRootPart", "Torso"], ["Neck", "Torso", "Head"],
		["Left Shoulder", "Torso", "Left Arm"], ["Right Shoulder", "Torso", "Right Arm"],
		["Left Hip", "Torso", "Left Leg"], ["Right Hip", "Torso", "Right Leg"],
	]
	for spec in joint_specs:
		if character.find_child(str(spec[0]), false, false) != null:
			continue
		var joint := Node.new()
		joint.name = str(spec[0])
		joint.set_meta("roblox_class", "Motor6D")
		joint.set_meta("Part0", str(spec[1]))
		joint.set_meta("Part1", str(spec[2]))
		character.add_child(joint, true)
	character.set_meta("bobux_character_ready", true)
	_refresh_explorer()
	_commit_editor_history("Adapt Character")
	if toolbar_status_label:
		toolbar_status_label.text = "Humanoid and R6 Motor6D links repaired"


func _open_clip_editor() -> void:
	var character := _get_selected_character_root()
	if character == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Select a character before opening Clip Editor"
		return
	var player := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		player.set_meta("roblox_class", "Animator")
		character.add_child(player, true)
	var library := player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)
	if not library.has_animation("Idle"):
		var idle := Animation.new()
		idle.length = 1.0
		idle.loop_mode = Animation.LOOP_LINEAR
		library.add_animation("Idle", idle)
	var dialog := AcceptDialog.new()
	dialog.title = "Clip Editor - %s" % character.name
	dialog.ok_button_text = "Close"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(420, 220)
	dialog.add_child(root)
	var clips := ItemList.new()
	clips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for clip_name in library.get_animation_list():
		clips.add_item(str(clip_name))
	root.add_child(clips)
	var row := HBoxContainer.new()
	root.add_child(row)
	var play := Button.new()
	play.text = "Play"
	play.pressed.connect(func() -> void:
		if clips.get_selected_items().size() > 0:
			player.play(str(clips.get_item_text(clips.get_selected_items()[0])))
	)
	row.add_child(play)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(player.stop)
	row.add_child(stop)
	dialog.popup_centered(Vector2i(460, 300))


func _ensure_starter_screen_gui() -> Node:
	if data_model == null:
		return null
	var starter_gui := data_model.ensure_service("StarterGui")
	for child in starter_gui.get_children():
		if str(child.get_meta("roblox_class", "")) == "ScreenGui":
			return child
	var screen_gui := RobloxDataModelClass.create_instance("ScreenGui", "ScreenGui")
	starter_gui.add_child(screen_gui, true)
	return screen_gui


func _insert_gui_instance(roblox_class: String) -> void:
	if data_model == null or _is_studio_editing_locked():
		return
	var selected_parent := _get_selected_editor_node()
	if not (selected_parent is Control) and not (selected_parent is CanvasLayer):
		selected_parent = _ensure_starter_screen_gui()
	if selected_parent == null:
		return
	var instance := RobloxDataModelClass.create_instance(roblox_class, roblox_class)
	if instance is Label:
		(instance as Label).text = "TextLabel"
	elif instance is Button:
		(instance as Button).text = "TextButton"
	elif instance is LineEdit:
		(instance as LineEdit).placeholder_text = "TextBox"
	selected_parent.add_child(instance, true)
	explorer_selected_node = instance
	_on_data_model_gui_changed()
	_refresh_explorer()
	_show_properties_for_node(instance)
	_commit_editor_history("Insert %s" % roblox_class)


func _focus_selected_gui_properties() -> void:
	var node := _get_selected_editor_node()
	if node is Control or node is CanvasLayer:
		_show_properties_for_node(node)
		_set_tool_window_visible("properties", true)
	elif toolbar_status_label:
		toolbar_status_label.text = "Select a GUI instance in Explorer"


func _get_active_script_tab() -> Control:
	if script_editor_tabs == null or not script_editor_tabs.visible or script_editor_tabs.get_child_count() == 0:
		return null
	var index := clampi(script_editor_tabs.current_tab, 0, script_editor_tabs.get_child_count() - 1)
	return script_editor_tabs.get_child(index) as Control


func _find_code_edit(root: Node) -> CodeEdit:
	if root is CodeEdit:
		return root as CodeEdit
	for child in root.get_children():
		var found := _find_code_edit(child)
		if found != null:
			return found
	return null


func _find_output_log(root: Node) -> RichTextLabel:
	if root is RichTextLabel:
		return root as RichTextLabel
	for child in root.get_children():
		var found := _find_output_log(child)
		if found != null:
			return found
	return null


func _active_script_node() -> Node:
	var active_tab := _get_active_script_tab()
	if active_tab == null:
		return null
	for instance_id in open_scripts.keys():
		if open_scripts[instance_id] == active_tab:
			return instance_from_id(int(instance_id))
	return null


func _script_history_back() -> void:
	if script_editor_tabs == null or script_editor_tabs.get_child_count() < 2:
		return
	script_editor_tabs.current_tab = posmod(script_editor_tabs.current_tab - 1, script_editor_tabs.get_child_count())


func _script_history_forward() -> void:
	if script_editor_tabs == null or script_editor_tabs.get_child_count() < 2:
		return
	script_editor_tabs.current_tab = posmod(script_editor_tabs.current_tab + 1, script_editor_tabs.get_child_count())


func _format_active_script() -> void:
	var code := _find_code_edit(_get_active_script_tab()) if _get_active_script_tab() != null else null
	if code == null:
		return
	var formatted: PackedStringArray = []
	for raw_line in code.text.replace("\r\n", "\n").split("\n"):
		formatted.append(str(raw_line).rstrip(" \t"))
	code.text = "\n".join(formatted)
	var script_node := _active_script_node()
	if script_node != null:
		_commit_script_editor_source(script_node, code.text)


func _find_in_active_script() -> void:
	var code := _find_code_edit(_get_active_script_tab()) if _get_active_script_tab() != null else null
	if code == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Find in Script"
	dialog.ok_button_text = "Find"
	add_child(dialog)
	var search := LineEdit.new()
	search.placeholder_text = "Search text"
	search.custom_minimum_size = Vector2(360, 30)
	dialog.add_child(search)
	dialog.confirmed.connect(func() -> void:
		var needle := search.text
		if needle.is_empty():
			return
		for line_index in range(code.get_line_count()):
			var column := code.get_line(line_index).find(needle)
			if column >= 0:
				code.set_caret_line(line_index)
				code.set_caret_column(column)
				code.select(line_index, column, line_index, column + needle.length())
				code.center_viewport_to_caret()
				return
	)
	dialog.popup_centered(Vector2i(400, 130))


func _go_to_line_in_active_script() -> void:
	var code := _find_code_edit(_get_active_script_tab()) if _get_active_script_tab() != null else null
	if code == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Go To Line"
	add_child(dialog)
	var line_spin := SpinBox.new()
	line_spin.min_value = 1
	line_spin.max_value = maxi(1, code.get_line_count())
	line_spin.value = code.get_caret_line() + 1
	line_spin.custom_minimum_size = Vector2(220, 30)
	dialog.add_child(line_spin)
	dialog.confirmed.connect(func() -> void:
		code.set_caret_line(clampi(int(line_spin.value) - 1, 0, code.get_line_count() - 1))
		code.center_viewport_to_caret()
	)
	dialog.popup_centered(Vector2i(260, 130))


func _focus_command_bar() -> void:
	if command_line_edit != null:
		command_line_edit.grab_focus()


func _open_output_panel() -> void:
	var active_tab := _get_active_script_tab()
	if active_tab == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Open a script to view Output"
		return
	var output := _find_output_log(active_tab)
	if output != null:
		output.get_parent().get_parent().visible = true
		output.scroll_to_line(maxi(0, output.get_line_count() - 1))


func _toggle_active_script_breakpoint() -> void:
	var code := _find_code_edit(_get_active_script_tab()) if _get_active_script_tab() != null else null
	if code == null:
		return
	var line := code.get_caret_line()
	var breakpoints: PackedInt32Array = code.get_breakpointed_lines()
	code.set_line_as_breakpoint(line, not breakpoints.has(line))


func _analyze_active_script() -> void:
	var code := _find_code_edit(_get_active_script_tab()) if _get_active_script_tab() != null else null
	if code == null:
		return
	var validation: Dictionary = LuaScriptEngine.validate_script_source(code.text)
	var output := _find_output_log(_get_active_script_tab())
	var message := "Analysis passed: Luau source compiles." if bool(validation.get("ok", false)) else "Analysis failed: %s" % str(validation.get("error", "Unknown error"))
	if output != null:
		output.append_text("[Analysis] %s\n" % message)
	if toolbar_status_label:
		toolbar_status_label.text = message


func _resolve_model_action_parent() -> Node3D:
	var selected := _get_selected_editor_node()
	if selected is Node3D:
		return selected as Node3D
	return placement_parent


func _insert_effect_for_selection() -> void:
	var parent := _resolve_model_action_parent()
	if parent == null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "ParticleEmitter"
	particles.amount = 32
	particles.lifetime = 1.5
	particles.emitting = true
	particles.set_meta("roblox_class", "ParticleEmitter")
	var process := ParticleProcessMaterial.new()
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0, -2.0, 0)
	particles.process_material = process
	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.08
	draw_mesh.height = 0.16
	particles.draw_pass_1 = draw_mesh
	parent.add_child(particles, true)
	_refresh_explorer()
	_commit_editor_history("Insert ParticleEmitter")


func _insert_attachment_for_selection() -> void:
	var parent := _resolve_model_action_parent()
	if parent == null:
		return
	var attachment := Node3D.new()
	attachment.name = "Attachment"
	attachment.set_meta("roblox_class", "Attachment")
	attachment.set_meta("roblox_properties", {"Position": [0.0, 0.0, 0.0], "Axis": [1.0, 0.0, 0.0]})
	parent.add_child(attachment, true)
	explorer_selected_node = attachment
	_refresh_explorer()
	_show_properties_for_node(attachment)
	_commit_editor_history("Insert Attachment")


func _insert_constraint_for_selection() -> void:
	var blocks := _get_valid_selected_blocks()
	if blocks.size() < 2:
		if toolbar_status_label:
			toolbar_status_label.text = "Select two parts for a constraint"
		return
	var constraint := Node.new()
	constraint.name = "HingeConstraint"
	constraint.set_meta("roblox_class", "HingeConstraint")
	constraint.set_meta("Part0", blocks[0].get_path())
	constraint.set_meta("Part1", blocks[1].get_path())
	constraint.set_meta("Enabled", true)
	blocks[0].get_parent().add_child(constraint, true)
	explorer_selected_node = constraint
	_refresh_explorer()
	_show_properties_for_node(constraint)
	_commit_editor_history("Insert Constraint")


func _weld_selected_blocks() -> void:
	var blocks := _get_valid_selected_blocks()
	if blocks.size() < 2:
		if toolbar_status_label:
			toolbar_status_label.text = "Select two or more parts to weld"
		return
	for index in range(1, blocks.size()):
		var weld := Node.new()
		weld.name = "WeldConstraint"
		weld.set_meta("roblox_class", "WeldConstraint")
		weld.set_meta("Part0", blocks[0].get_path())
		weld.set_meta("Part1", blocks[index].get_path())
		weld.set_meta("Enabled", true)
		blocks[0].add_child(weld, true)
	_refresh_explorer()
	_commit_editor_history("Weld Parts")
	if toolbar_status_label:
		toolbar_status_label.text = "Created %d WeldConstraint(s)" % (blocks.size() - 1)


func _align_selected_blocks() -> void:
	var blocks := _get_valid_selected_blocks()
	if blocks.size() < 2:
		if toolbar_status_label:
			toolbar_status_label.text = "Select two or more parts to align"
		return
	var popup := PopupMenu.new()
	popup.add_item("Align X", 0)
	popup.add_item("Align Y", 1)
	popup.add_item("Align Z", 2)
	popup.id_pressed.connect(func(axis: int) -> void:
		var origin := blocks[0].global_position
		for index in range(1, blocks.size()):
			var position := blocks[index].global_position
			position[axis] = origin[axis]
			blocks[index].global_position = position
		_commit_editor_history("Align Parts")
	)
	add_child(popup)
	popup.position = Vector2i(get_viewport().get_mouse_position())
	popup.popup()


func _toggle_selected_lock() -> void:
	var blocks := _get_valid_selected_blocks()
	for block in blocks:
		block.set_meta("locked", not bool(block.get_meta("locked", false)))
	_commit_editor_history("Toggle Locked")
	_update_inspector()
	_update_transform_gizmo()


func _open_plugin_manager_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Plugin Manager"
	dialog.ok_button_text = "Close"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(520, 320)
	dialog.add_child(root)
	var intro := Label.new()
	intro.text = "Installed project plugins"
	root.add_child(intro)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for folder_name in DirAccess.get_directories_at("res://addons"):
		if FileAccess.file_exists("res://addons/%s/plugin.cfg" % folder_name):
			list.add_item(str(folder_name))
	root.add_child(list)
	var open_folder := Button.new()
	open_folder.text = "Open Plugins Folder"
	open_folder.pressed.connect(_open_plugins_folder)
	root.add_child(open_folder)
	dialog.popup_centered(Vector2i(560, 390))


func _open_plugins_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path("res://addons"))


func _toggle_grid_from_ribbon() -> void:
	show_grid_enabled = not show_grid_enabled
	_toggle_grid_visibility(show_grid_enabled)
	if toolbar_status_label:
		toolbar_status_label.text = "Grid %s" % ("shown" if show_grid_enabled else "hidden")


func _toggle_colliders_from_ribbon() -> void:
	show_colliders_enabled = not show_colliders_enabled
	_toggle_collision_preview(show_colliders_enabled)

func _build_viewport_document_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	document_tabs_container = header
	header.name = "DocumentTabs"
	header.custom_minimum_size = Vector2(0, 30)
	header.add_theme_constant_override("separation", 2)
	parent.add_child(header)
	var props_hint := Label.new()
	props_hint.text = ""
	props_hint.custom_minimum_size = Vector2(0, 0)
	header.add_child(props_hint)
	var tab := Button.new()
	document_tab_button = tab
	tab.text = "%s" % current_map_name
	tab.custom_minimum_size = Vector2(154, 28)
	tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_white_button(tab)
	tab.pressed.connect(_show_viewport_document)
	header.add_child(tab)
	var spacer := Control.new()
	document_tab_spacer = spacer
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_refresh_document_tab_styles()

func _show_viewport_document() -> void:
	active_document_script_id = 0
	if script_editor_tabs != null:
		script_editor_tabs.visible = false
	if viewport_container_node != null:
		viewport_container_node.visible = true
	_refresh_document_tab_styles()
	if viewport_container_node != null:
		viewport_container_node.call_deferred("grab_focus")

func _show_script_document(instance_id: int) -> void:
	if not open_scripts.has(instance_id) or not is_instance_valid(open_scripts[instance_id]):
		return
	active_document_script_id = instance_id
	viewport_container_node.visible = false
	script_editor_tabs.visible = true
	var index := script_editor_tabs.get_tab_idx_from_control(open_scripts[instance_id])
	if index >= 0:
		script_editor_tabs.current_tab = index
	_refresh_document_tab_styles()

func _ensure_script_document_button(script_node: Node) -> Button:
	var instance_id := script_node.get_instance_id()
	if script_document_buttons.has(instance_id) and is_instance_valid(script_document_buttons[instance_id]):
		return script_document_buttons[instance_id] as Button
	if document_tabs_container == null:
		return null
	var button := Button.new()
	button.name = "Document_%d" % instance_id
	button.text = script_node.name
	button.tooltip_text = "%s (%s)" % [script_node.name, str(script_node.get_meta("script_type", "Script"))]
	button.custom_minimum_size = Vector2(138, 28)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_show_script_document.bind(instance_id))
	document_tabs_container.add_child(button)
	if document_tab_spacer != null:
		document_tabs_container.move_child(button, document_tab_spacer.get_index())
	script_document_buttons[instance_id] = button
	_refresh_document_tab_styles()
	return button

func _refresh_document_tab_styles() -> void:
	if document_tab_button != null:
		_style_document_tab_button(document_tab_button, active_document_script_id == 0)
	for id_variant in script_document_buttons.keys():
		var id := int(id_variant)
		var button := script_document_buttons[id] as Button
		if button != null and is_instance_valid(button):
			_style_document_tab_button(button, id == active_document_script_id)

func _style_document_tab_button(button: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#FFFFFF") if active else Color("#ECEDEF")
	normal.border_color = Color("#1888D8") if active else Color("#C5C7CA")
	normal.border_width_bottom = 2 if active else 1
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#F7FAFC")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_color_override("font_color", Color("#202124"))
	button.add_theme_font_size_override("font_size", 12)

func _refresh_studio_title_text() -> void:
	if document_tab_button != null and is_instance_valid(document_tab_button):
		document_tab_button.text = current_map_name

func _build_explorer_dock() -> PanelContainer:
	var explorer_container := PanelContainer.new()
	explorer_container.name = "ExplorerPanel"
	explorer_container.custom_minimum_size = Vector2(286, 0)
	explorer_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	explorer_container.add_theme_stylebox_override("panel", _studio_panel_style(Color.WHITE, Color("#C9CDD2"), 1))
	var explorer_vbox := VBoxContainer.new()
	explorer_vbox.add_theme_constant_override("separation", 4)
	explorer_container.add_child(explorer_vbox)
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	header.add_theme_constant_override("separation", 4)
	explorer_vbox.add_child(header)
	var explorer_title := Label.new()
	explorer_title.text = "Explorer"
	explorer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explorer_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explorer_title.add_theme_font_size_override("font_size", 12)
	explorer_title.add_theme_color_override("font_color", Color("#333333"))
	header.add_child(explorer_title)
	var insert_btn := _create_studio_icon_button("Add", "Insert Object", Vector2(26, 24))
	insert_btn.pressed.connect(_open_insert_object_dialog)
	header.add_child(insert_btn)
	var refresh_btn := _create_studio_icon_button("Refresh", "Refresh Explorer", Vector2(26, 24))
	refresh_btn.pressed.connect(_refresh_explorer)
	header.add_child(refresh_btn)
	var close_btn := _create_studio_icon_button("Close", "Close Explorer", Vector2(26, 24))
	close_btn.pressed.connect(_set_tool_window_visible.bind("explorer", false))
	header.add_child(close_btn)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 4)
	explorer_vbox.add_child(search_row)
	explorer_search_edit = LineEdit.new()
	explorer_search_edit.placeholder_text = "Search"
	explorer_search_edit.custom_minimum_size = Vector2(0, 26)
	explorer_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explorer_search_edit.add_theme_font_size_override("font_size", 11)
	explorer_search_edit.add_theme_color_override("font_color", Color("#333333"))
	explorer_search_edit.add_theme_color_override("font_placeholder_color", Color(0.52, 0.54, 0.58))
	explorer_search_edit.add_theme_stylebox_override("normal", _studio_line_edit_style())
	explorer_search_edit.text_changed.connect(_on_explorer_search_changed)
	search_row.add_child(explorer_search_edit)
	var options_btn := _create_studio_icon_button("More", "Explorer options", Vector2(30, 24))
	options_btn.pressed.connect(_show_explorer_options_menu.bind(options_btn))
	search_row.add_child(options_btn)
	explorer_tree = Tree.new()
	explorer_tree.name = "ExplorerTree"
	explorer_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	explorer_tree.allow_reselect = true
	explorer_tree.allow_rmb_select = true
	explorer_tree.select_mode = Tree.SELECT_MULTI
	explorer_tree.hide_folding = false
	explorer_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	explorer_tree.set_drag_forwarding(_explorer_get_drag_data, _explorer_can_drop_data, _explorer_drop_data)
	explorer_tree.add_theme_font_size_override("font_size", 11)
	explorer_tree.add_theme_color_override("font_color", Color("#222222"))
	explorer_tree.add_theme_color_override("font_selected_color", Color.WHITE)
	explorer_tree.add_theme_color_override("guide_color", Color("#D3D6DA"))
	explorer_tree.add_theme_color_override("drop_position_color", Color("#1874D1"))
	explorer_tree.add_theme_stylebox_override("panel", _studio_panel_style(Color.WHITE, Color("#D7DADF"), 1))
	explorer_tree.add_theme_stylebox_override("selected", _studio_panel_style(Color("#4D88F7"), Color("#4D88F7"), 0, 3))
	explorer_tree.add_theme_stylebox_override("selected_focus", _studio_panel_style(Color("#4D88F7"), Color("#4D88F7"), 0, 3))
	explorer_tree.add_theme_stylebox_override("hovered", _studio_panel_style(Color("#E9F2FF"), Color("#E9F2FF"), 0, 3))
	explorer_tree.add_theme_stylebox_override("hovered_dimmed", _studio_panel_style(Color("#F3F7FC"), Color("#F3F7FC"), 0, 3))
	explorer_tree.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Tree depth must remain visually obvious in a narrow dock. Two pixels made
	# Workspace children look like top-level services even though the DataModel
	# hierarchy was correct.
	explorer_tree.add_theme_constant_override("item_margin", 14)
	explorer_tree.add_theme_constant_override("v_separation", 2)
	explorer_tree.add_theme_constant_override("icon_max_width", 16)
	explorer_tree.item_selected.connect(_on_explorer_item_selected)
	explorer_tree.item_mouse_selected.connect(_on_explorer_item_mouse_selected)
	explorer_tree.item_activated.connect(_on_explorer_item_double_clicked)
	explorer_vbox.add_child(explorer_tree)
	return explorer_container

func _build_toolbox_dock() -> PanelContainer:
	var dock := PanelContainer.new()
	dock.name = "ToolboxPanel"
	dock.custom_minimum_size = Vector2(270, 0)
	dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F7F7F7"), Color("#C8C8C8"), 1))
	toolbox_content_tabs = TabContainer.new()
	toolbox_content_tabs.name = "ToolboxAITabs"
	toolbox_content_tabs.theme = preload("res://addons/roblox_studio/toolbox_library_panel.gd").library_theme()
	dock.add_child(toolbox_content_tabs)
	var browser := preload("res://addons/roblox_studio/toolbox_library_panel.gd").new()
	browser.name = "Toolbox"
	browser.asset_requested.connect(_insert_library_asset)
	browser.prefab_requested.connect(_open_studio_prefab_options)
	browser.legacy_requested.connect(_open_toolbox_dialog)
	toolbox_content_tabs.add_child(browser)
	var ai_page := _build_studio_ai_dock_chat()
	ai_page.name = "AI"
	toolbox_content_tabs.add_child(ai_page)
	return dock

func _open_studio_prefab_options(prefab_id: String) -> void:
	if _is_studio_editing_locked(): return
	var library = preload("res://addons/roblox_studio/studio_prefab_library.gd")
	var dialog := ConfirmationDialog.new()
	dialog.title = "Настроить заготовку · " + prefab_id
	dialog.ok_button_text = "Добавить в карту"
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var controls := {}
	for key in library.parameters(prefab_id):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(key)
		label.custom_minimum_size.x = 180
		row.add_child(label)
		var value: Variant = library.parameters(prefab_id)[key]
		if value is bool:
			var field := CheckBox.new()
			field.button_pressed = value
			controls[key] = field
			row.add_child(field)
		elif value is String:
			var field := LineEdit.new()
			field.text = value
			field.custom_minimum_size.x = 240
			controls[key] = field
			row.add_child(field)
		else:
			var field := SpinBox.new()
			field.min_value = -10000
			field.max_value = 100000
			field.step = 0.05 if float(value) < 1 else 1.0
			field.value = value
			controls[key] = field
			row.add_child(field)
		column.add_child(row)
	dialog.confirmed.connect(func():
		var options := {}
		for key in controls:
			if controls[key] is CheckBox: options[key] = controls[key].button_pressed
			elif controls[key] is LineEdit: options[key] = controls[key].text
			else: options[key] = controls[key].value
		dialog.queue_free()
		_apply_studio_prefab(prefab_id, options)
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(440, 160))

func _apply_studio_prefab(prefab_id: String, options: Dictionary) -> void:
	var plan := preload("res://addons/roblox_studio/studio_prefab_library.gd").plan(prefab_id, options)
	if not plan.ok: toolbar_status_label.text = plan.error; return
	for action in plan.actions:
		if action.get("type") in ["spawn_asset", "attach_sound"]:
			if not await ToolboxAssetService.ensure_asset(str(action.asset_id)):
				toolbar_status_label.text = ToolboxAssetService.last_error
				return
	var count := _apply_studio_ai_actions(plan.actions)
	toolbar_status_label.text = "%s · %d изменений" % [prefab_id, count] if studio_ai_last_errors.is_empty() else "\n".join(studio_ai_last_errors)

func _insert_library_asset(asset_id: String) -> void:
	if _is_studio_editing_locked(): return
	if toolbar_status_label: toolbar_status_label.text = "Загрузка ассета с сервера…"
	if not await ToolboxAssetService.ensure_asset(asset_id):
		if toolbar_status_label: toolbar_status_label.text = ToolboxAssetService.last_error
		return
	if _is_studio_editing_locked(): return
	var library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
	var entry: Dictionary = library.get_asset(asset_id)
	if entry.is_empty(): return
	var selected := _get_selected_editor_node()
	var action := {"type": "spawn_asset" if entry.type == "model" else "attach_sound", "asset_id": asset_id}
	if entry.type == "sound" and selected != null:
		action["parent"] = _studio_ai_node_reference(selected)
	_apply_studio_ai_actions([action])


func _build_studio_ai_dock_chat() -> Control:
	var panel := PanelContainer.new()
	studio_ai_dock = panel
	panel.name = "BobuxAIChat"
	panel.custom_minimum_size = Vector2(0, 214)
	panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F1F3F4"), Color("#CDD1D5"), 1, 3))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Bobux AI"
	title.tooltip_text = "Create parts, models and Luau scripts in the current place"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("#202124"))
	column.add_child(title)
	studio_ai_result_label = RichTextLabel.new()
	studio_ai_result_label.bbcode_enabled = true
	studio_ai_result_label.custom_minimum_size = Vector2(0, 76)
	studio_ai_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	studio_ai_result_label.add_theme_font_size_override("normal_font_size", 10)
	studio_ai_result_label.add_theme_color_override("default_color", Color("#202124"))
	studio_ai_result_label.add_theme_stylebox_override("normal", _studio_panel_style(Color.WHITE, Color("#DADCE0"), 1, 2))
	studio_ai_result_label.text = "[color=#5f6368]Ask for a build or a Luau script. The result is applied to this place.[/color]"
	column.add_child(studio_ai_result_label)
	studio_ai_prompt_edit = TextEdit.new()
	studio_ai_prompt_edit.placeholder_text = "Write a request..."
	studio_ai_prompt_edit.custom_minimum_size = Vector2(0, 52)
	studio_ai_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	studio_ai_prompt_edit.add_theme_font_size_override("font_size", 11)
	studio_ai_prompt_edit.add_theme_color_override("font_color", Color("#202124"))
	studio_ai_prompt_edit.add_theme_color_override("font_placeholder_color", Color("#777B82"))
	studio_ai_prompt_edit.add_theme_color_override("background_color", Color.WHITE)
	column.add_child(studio_ai_prompt_edit)
	studio_ai_submit_button = Button.new()
	studio_ai_submit_button.text = "Create in Studio"
	studio_ai_submit_button.tooltip_text = "Send this request and apply the validated result"
	studio_ai_submit_button.custom_minimum_size = Vector2(0, 28)
	_style_white_button(studio_ai_submit_button, Color("#1677D2"))
	studio_ai_submit_button.pressed.connect(_request_and_apply_studio_ai)
	column.add_child(studio_ai_submit_button)
	return panel

func _create_studio_icon_button(icon_name: String, tooltip: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = ""
	button.tooltip_text = tooltip
	button.custom_minimum_size = minimum_size
	button.icon = _get_toolbar_icon(icon_name, Color("#34373C"))
	button.add_theme_color_override("icon_normal_color", Color("#34373C"))
	button.add_theme_color_override("icon_hover_color", Color("#1677D2"))
	button.add_theme_color_override("icon_pressed_color", Color("#0E5EA8"))
	_style_icon_button(button)
	return button

func _style_icon_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	var hover := _studio_panel_style(Color("#E7F2FC"), Color("#B9D7F1"), 1, 3)
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _style_toolbox_category_button(button: Button) -> void:
	var normal := _studio_panel_style(Color("#E9EAEC"), Color("#D2D4D7"), 1, 4)
	var hover := _studio_panel_style(Color("#E4F1FC"), Color("#7DB5E5"), 1, 4)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#26282C"))
	button.add_theme_color_override("font_hover_color", Color("#1169B1"))

func _show_explorer_options_menu(source_button: Button) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Expand all", 1)
	menu.add_item("Collapse all", 2)
	menu.add_separator()
	menu.add_item("Refresh", 3)
	menu.id_pressed.connect(func(id: int) -> void:
		match id:
			1:
				_set_explorer_collapsed_recursive(false)
			2:
				_set_explorer_collapsed_recursive(true)
			3:
				_refresh_explorer()
		menu.queue_free()
	)
	add_child(menu)
	var popup_position := source_button.global_position + Vector2(0, source_button.size.y)
	menu.position = Vector2i(roundi(popup_position.x), roundi(popup_position.y))
	menu.popup()

func _set_explorer_collapsed_recursive(collapsed: bool) -> void:
	if explorer_tree == null:
		return
	var root_item := explorer_tree.get_root()
	if root_item == null:
		return
	_set_tree_item_collapsed_recursive(root_item, collapsed)

func _set_tree_item_collapsed_recursive(item: TreeItem, collapsed: bool) -> void:
	item.collapsed = collapsed
	var child := item.get_first_child()
	while child != null:
		_set_tree_item_collapsed_recursive(child, collapsed)
		child = child.get_next()

func _filter_toolbox_items(search: LineEdit) -> void:
	var items := toolbox_items_list
	if items == null:
		return
	var query := search.text.strip_edges().to_lower()
	for index in range(items.item_count):
		items.set_item_disabled(index, not query.is_empty() and items.get_item_text(index).to_lower().find(query) < 0)

func _on_toolbox_category_pressed(category: String) -> void:
	_populate_toolbox_dock(category)

func _on_toolbox_item_activated(index: int) -> void:
	var items := toolbox_items_list
	if items == null or index < 0 or index >= items.item_count:
		return
	var entry_variant: Variant = items.get_item_metadata(index)
	if entry_variant is Dictionary:
		_activate_toolbox_entry(entry_variant as Dictionary)


func _populate_toolbox_dock(category: String) -> void:
	if toolbox_items_list == null:
		return
	toolbox_active_category = category
	toolbox_asset_entries = _get_toolbox_entries(category)
	toolbox_items_list.clear()
	for entry in toolbox_asset_entries:
		_add_toolbox_dock_entry(entry)
	if toolbox_items_list.item_count == 0:
		toolbox_items_list.add_item("No assets found")
		toolbox_items_list.set_item_disabled(0, true)
	if toolbar_status_label:
		toolbar_status_label.text = "Toolbox: %s (%d item(s))" % [category, toolbox_asset_entries.size()]
	if category in ["3D Assets", "Models"]:
		_append_cloud_toolbox_models.call_deferred(category)

func _add_toolbox_dock_entry(entry: Dictionary) -> void:
	if toolbox_items_list == null:
		return
	var label := str(entry.get("label", "Asset"))
	var icon_name := str(entry.get("icon", "Assets"))
	var icon: Texture2D = _get_toolbar_icon(icon_name, Color("#34373C"))
	var thumbnail := _load_toolbox_thumbnail_texture(_resolve_toolbox_model_thumbnail(entry))
	if thumbnail != null:
		icon = thumbnail
	toolbox_items_list.add_item(label, icon)
	var index := toolbox_items_list.item_count - 1
	toolbox_items_list.set_item_metadata(index, entry)
	toolbox_items_list.set_item_tooltip(index, str(entry.get("path", entry.get("description", label))))

func _append_cloud_toolbox_models(category: String) -> void:
	if category not in ["3D Assets", "Models"] or toolbox_items_list == null:
		return
	if not toolbox_cloud_models_loaded and not toolbox_cloud_models_loading and CloudAPI != null and CloudAPI.is_configured():
		toolbox_cloud_models_loading = true
		var response: Dictionary = await CloudAPI.fetch_marketplace_models(96, true, false)
		toolbox_cloud_models_loading = false
		if bool(response.get("ok", false)):
			toolbox_cloud_model_cache.clear()
			for raw_entry in _extract_toolbox_response_array(response):
				if raw_entry is Dictionary:
					var cloud_entry := (raw_entry as Dictionary).duplicate(true)
					cloud_entry["publish_state"] = "cloud"
					toolbox_cloud_model_cache.append(cloud_entry)
			toolbox_cloud_models_loaded = true
		elif toolbar_status_label:
			toolbar_status_label.text = "Toolbox cloud load failed: %s" % str(response.get("error", "Unknown error"))
	if toolbox_active_category != category or toolbox_items_list == null:
		return
	var seen: Dictionary = {}
	for existing in toolbox_asset_entries:
		var identity := _studio_model_identity(existing)
		if not identity.is_empty():
			seen[identity] = true
	for cloud_entry in toolbox_cloud_model_cache:
		var identity := _studio_model_identity(cloud_entry)
		if not identity.is_empty() and seen.has(identity):
			continue
		if not identity.is_empty():
			seen[identity] = true
		var entry := {
			"label": str(cloud_entry.get("name", "Marketplace model")),
			"action": "model_draft",
			"payload": cloud_entry,
			"icon": "Assets",
			"description": "Insert published model"
		}
		toolbox_asset_entries.append(entry)
		_add_toolbox_dock_entry(entry)
	if toolbar_status_label:
		toolbar_status_label.text = "Toolbox: %s (%d item(s))" % [category, toolbox_asset_entries.size()]


func _get_toolbox_entries(category: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	match category:
		"3D Assets", "Models":
			for spec in [
				["Part", "insert_shape", "Box", "Part"],
				["Sphere", "insert_shape", "Sphere", "Part"],
				["Cylinder", "insert_shape", "Cylinder", "Part"],
				["Cone", "insert_shape", "Cone", "Part"],
				["WedgePart", "insert_class", "WedgePart", "Part"],
				["CornerWedgePart", "insert_class", "CornerWedgePart", "Part"],
				["TrussPart", "insert_class", "TrussPart", "Part"],
				["SpawnLocation", "insert_class", "SpawnLocation", "Part"],
				["R6 Character", "insert_class", "Character", "Character"],
				["Tool with Handle", "insert_class", "Tool", "Toolbox"],
			]:
				entries.append(_toolbox_entry(str(spec[0]), str(spec[1]), str(spec[2]), str(spec[3])))
			for asset_name in ["Coin", "Tree", "Crate", "Chair", "Table", "Lamp", "Door", "Ladder", "Arch", "Stairs", "Hammer"]:
				entries.append({
					"label": asset_name,
					"action": "builtin_model",
					"value": asset_name,
					"icon": "Assets",
					"description": "Insert the built-in %s model" % asset_name,
				})
			if category in ["3D Assets", "Models"]:
				for draft in _load_local_model_draft_entries(64):
					entries.append({
						"label": str(draft.get("name", draft.get("title", "Model draft"))),
						"action": "model_draft", "payload": draft, "icon": "Assets",
						"description": "Insert saved model draft",
					})
		"Meshes":
			for path in _scan_studio_asset_files(["res://assets", "res://models", "user://rbxl_assets"], [".glb", ".gltf", ".obj", ".mesh.json"], 192):
				entries.append(_toolbox_file_entry(path, "mesh_file", "Part"))
		"Visual Effects":
			for spec in [["PointLight", "PointLight"], ["SpotLight", "SpotLight"], ["ParticleEmitter", "ParticleEmitter"], ["Fire", "Fire"], ["Smoke", "Smoke"], ["Sparkles", "Sparkles"]]:
				entries.append(_toolbox_entry(str(spec[0]), "insert_class", str(spec[1]), "Color"))
		"2D Assets", "Decals":
			for spec in [["Frame", "Frame"], ["TextLabel", "TextLabel"], ["TextButton", "TextButton"], ["TextBox", "TextBox"], ["ImageLabel", "ImageLabel"], ["ImageButton", "ImageButton"], ["ScrollingFrame", "ScrollingFrame"]]:
				entries.append(_toolbox_entry(str(spec[0]), "insert_class", str(spec[1]), "GUI"))
			for path in _scan_studio_asset_files(["res://images", "res://assets"], [".png", ".jpg", ".jpeg", ".webp", ".svg"], 192):
				entries.append(_toolbox_file_entry(path, "image_file", "Assets"))
		"Gameplay":
			for spec in [
				["Tool", "Tool"], ["SpawnLocation", "SpawnLocation"], ["TrussPart", "TrussPart"],
				["Script", "Script"], ["LocalScript", "LocalScript"], ["ModuleScript", "ModuleScript"],
				["RemoteEvent", "RemoteEvent"], ["BindableEvent", "BindableEvent"],
			]:
				entries.append(_toolbox_entry(str(spec[0]), "insert_class", str(spec[1]), "Script" if "Script" in str(spec[1]) else "Part"))
		"Audio":
			entries.append(_toolbox_entry("Sound", "insert_class", "Sound", "Assets"))
			for path in _scan_studio_asset_files(["res://audio", "res://music", "res://assets"], [".ogg", ".wav", ".mp3"], 128):
				entries.append(_toolbox_file_entry(path, "audio_file", "Assets"))
		"Video":
			for path in _scan_studio_asset_files(["res://video", "res://assets"], [".ogv"], 96):
				entries.append(_toolbox_file_entry(path, "video_file", "Assets"))
		"Plugins":
			for folder_name in DirAccess.get_directories_at("res://addons"):
				var plugin_path := "res://addons/%s/plugin.cfg" % folder_name
				if FileAccess.file_exists(plugin_path):
					entries.append({"label": str(folder_name), "action": "plugin", "path": plugin_path, "icon": "Toolbox"})
	return entries

func _toolbox_model_payload(entry: Dictionary) -> Dictionary:
	var payload: Variant = entry.get("payload", entry)
	return _toolbox_dictionary_from_jsonish_variant(payload)

func _studio_model_identity(entry: Dictionary) -> String:
	var payload := _toolbox_model_payload(entry)
	for candidate in _model_metadata_candidates(payload, entry):
		var cloud_id := str(candidate.get("cloud_model_id", "")).strip_edges()
		if not cloud_id.is_empty():
			return "cloud:%s" % cloud_id
	for candidate in _model_metadata_candidates(payload, entry):
		if str(candidate.get("publish_state", "")).strip_edges().to_lower() == "cloud":
			var cloud_id := str(candidate.get("id", "")).strip_edges()
			if not cloud_id.is_empty():
				return "cloud:%s" % cloud_id
	for candidate in _model_metadata_candidates(payload, entry):
		var draft_id := str(candidate.get("draft_id", candidate.get("id", ""))).strip_edges()
		if not draft_id.is_empty():
			return "draft:%s" % draft_id
	return ""

func _resolve_toolbox_model_thumbnail(entry: Dictionary) -> String:
	var payload := _toolbox_model_payload(entry)
	for candidate in _model_metadata_candidates(payload, entry):
		for key in ["thumbnail", "thumbnail_url", "preview_thumbnail_path", "preview_thumbnail", "thumbnail_path", "preview_path", "icon_path"]:
			var value := str(candidate.get(key, "")).strip_edges()
			if not value.is_empty() and value != "<null>":
				return value
	return ""

func _load_toolbox_thumbnail_texture(source: String) -> Texture2D:
	var clean := source.strip_edges()
	if clean.is_empty() or clean.begins_with("http://") or clean.begins_with("https://"):
		return null
	var image := Image.new()
	var loaded := false
	if clean.begins_with("data:image/") or clean.begins_with("base64:"):
		var encoded := clean
		if encoded.begins_with("data:image/"):
			var comma_index := encoded.find(",")
			if comma_index >= 0:
				encoded = encoded.substr(comma_index + 1)
		else:
			encoded = encoded.substr(7)
		var bytes := Marshalls.base64_to_raw(encoded)
		if not bytes.is_empty():
			loaded = image.load_png_from_buffer(bytes) == OK \
				or image.load_jpg_from_buffer(bytes) == OK \
				or image.load_webp_from_buffer(bytes) == OK
	elif FileAccess.file_exists(clean):
		loaded = image.load(clean) == OK
	if not loaded or image.is_empty():
		return null
	var longest_side := maxi(image.get_width(), image.get_height())
	if longest_side > 128:
		var ratio := 128.0 / float(longest_side)
		image.resize(
			maxi(1, roundi(float(image.get_width()) * ratio)),
			maxi(1, roundi(float(image.get_height()) * ratio)),
			Image.INTERPOLATE_LANCZOS
		)
	return ImageTexture.create_from_image(image)


func _toolbox_entry(label: String, action: String, value: String, icon_name: String) -> Dictionary:
	return {"label": label, "action": action, "value": value, "icon": icon_name}


func _toolbox_file_entry(path: String, action: String, icon_name: String) -> Dictionary:
	return {"label": path.get_file(), "action": action, "path": path, "icon": icon_name}


func _scan_studio_asset_files(roots: Array[String], suffixes: Array[String], limit: int) -> Array[String]:
	var result: Array[String] = []
	var pending: Array[String] = roots.duplicate()
	var visited_folders := 0
	var visited_files := 0
	const MAX_INDEX_FOLDERS := 160
	const MAX_INDEX_FILES := 6000
	while not pending.is_empty() and result.size() < limit and visited_folders < MAX_INDEX_FOLDERS and visited_files < MAX_INDEX_FILES:
		var folder: String = pending.pop_front()
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		visited_folders += 1
		dir.list_dir_begin()
		while result.size() < limit and visited_files < MAX_INDEX_FILES:
			var file_name := dir.get_next()
			if file_name.is_empty():
				break
			if file_name.begins_with("."):
				continue
			var path: String = folder.path_join(file_name)
			if dir.current_is_dir():
				pending.append(path)
				continue
			visited_files += 1
			var lower_name := file_name.to_lower()
			for suffix in suffixes:
				if lower_name.ends_with(suffix):
					result.append(path)
					break
		dir.list_dir_end()
	result.sort()
	return result


func _activate_toolbox_entry(entry: Dictionary) -> void:
	if _is_studio_editing_locked():
		return
	var action := str(entry.get("action", ""))
	match action:
		"insert_shape":
			_place_shape_from_ribbon(str(entry.get("value", "Box")))
		"builtin_model":
			var model := _create_builtin_model(
				str(entry.get("value", entry.get("label", ""))),
				{"bobux_ai_generated": false},
				_get_editor_drop_position(10.0)
			)
			if model != null:
				explorer_selected_node = model
				_refresh_explorer()
				_show_properties_for_node(model)
				_commit_editor_history("Insert built-in model")
		"insert_class":
			_insert_roblox_instance(_get_selected_editor_node(), str(entry.get("value", "Part")))
		"model_draft":
			var payload: Variant = entry.get("payload", {})
			if payload is Dictionary:
				_insert_model_draft_into_place(payload as Dictionary)
		"mesh_file":
			_insert_local_mesh_asset(str(entry.get("path", "")))
		"image_file":
			_insert_local_image_asset(str(entry.get("path", "")))
		"audio_file":
			_insert_local_audio_asset(str(entry.get("path", "")))
		"video_file":
			_insert_local_video_asset(str(entry.get("path", "")))
		"plugin":
			_open_plugin_manager_dialog()


func _insert_local_mesh_asset(path: String) -> void:
	if path.is_empty():
		return
	var target_parent := _resolve_studio_3d_parent(_get_selected_editor_node())
	if not (target_parent is Node3D):
		target_parent = placement_parent
	var loaded: Resource = null
	if path.to_lower().ends_with(".mesh.json"):
		loaded = RobloxMeshJsonLoader.load_mesh(ProjectSettings.globalize_path(path))
	else:
		loaded = ResourceLoader.load(path)
	if loaded is Mesh:
		var block := _build_imported_block_instance("Box", Color.WHITE, "Plastic", 0.0, true, path.get_basename().get_file())
		block.mesh = loaded as Mesh
		block.set_meta("roblox_class", "MeshPart")
		block.set_meta("shape_type", "MeshPart")
		block.set_meta("source_asset_path", path)
		(target_parent as Node3D).add_child(block, true)
		block.global_position = _get_editor_drop_position(10.0)
		_update_block_collision(block)
		_set_selection([block])
	elif loaded is PackedScene:
		var instance := (loaded as PackedScene).instantiate()
		var wrapper := Node3D.new()
		wrapper.name = path.get_basename().get_file()
		wrapper.set_meta("roblox_class", "Model")
		wrapper.set_meta("source_asset_path", path)
		(target_parent as Node3D).add_child(wrapper, true)
		wrapper.global_position = _get_editor_drop_position(10.0)
		wrapper.add_child(instance, true)
		var mesh_nodes: Array[MeshInstance3D] = []
		_collect_mesh_instances(instance, mesh_nodes)
		for mesh_node in mesh_nodes:
			mesh_node.add_to_group("studio_parts")
			mesh_node.set_meta("roblox_class", "MeshPart")
			mesh_node.set_meta("block_name", mesh_node.name)
			mesh_node.set_meta("shape_type", "MeshPart")
			mesh_node.set_meta("can_collide", true)
			mesh_node.set_meta("transparency", 0.0)
			mesh_node.set_meta("source_asset_path", path)
			_update_block_collision(mesh_node)
		if not mesh_nodes.is_empty():
			_set_selection([mesh_nodes[0]])
		explorer_selected_node = wrapper
	else:
		if toolbar_status_label:
			toolbar_status_label.text = "Unsupported mesh asset: %s" % path.get_file()
		return
	_refresh_explorer()
	_commit_editor_history("Insert mesh asset")
	if toolbar_status_label:
		toolbar_status_label.text = "Inserted mesh: %s" % path.get_file()


func _collect_mesh_instances(root: Node, result: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, result)


func _insert_local_image_asset(path: String) -> void:
	var texture := load(path) as Texture2D if path.begins_with("res://") else _load_texture_from_file_path(ProjectSettings.globalize_path(path))
	if texture == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Could not load image: %s" % path.get_file()
		return
	var selected := _get_selected_editor_node()
	var created: Node = null
	if selected is MeshInstance3D:
		var decal := Decal.new()
		decal.name = path.get_basename().get_file()
		decal.texture_albedo = texture
		decal.size = Vector3(2.0, 0.25, 2.0)
		decal.position = Vector3(0.0, 0.55, 0.0)
		decal.set_meta("roblox_class", "Decal")
		decal.set_meta("Texture", path)
		selected.add_child(decal, true)
		created = decal
	else:
		var gui := _ensure_starter_screen_gui()
		var image_label := RobloxDataModelClass.create_instance("ImageLabel", path.get_basename().get_file()) as TextureRect
		image_label.texture = texture
		image_label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image_label.size = Vector2(256, 256)
		image_label.set_meta("Image", path)
		gui.add_child(image_label, true)
		created = image_label
		_on_data_model_gui_changed()
	explorer_selected_node = created
	_refresh_explorer()
	_show_properties_for_node(created)
	_commit_editor_history("Insert image asset")


func _insert_local_audio_asset(path: String) -> void:
	var stream := AudioFileLoader.load_stream(path, false)
	if stream == null or data_model == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Could not load audio: %s" % path.get_file()
		return
	var sound := RobloxDataModelClass.create_instance("Sound", path.get_basename().get_file()) as AudioStreamPlayer3D
	sound.stream = stream
	sound.set_meta("SoundId", path)
	sound.set_meta("roblox_properties", {"SoundId": path, "Volume": 1.0, "Looped": false, "Playing": false})
	var selected := _get_selected_editor_node()
	var parent: Node = selected if selected is Node3D and not bool(selected.get_meta("is_roblox_service", false)) else data_model.ensure_service("SoundService")
	parent.add_child(sound, true)
	explorer_selected_node = sound
	_refresh_explorer()
	_show_properties_for_node(sound)
	_commit_editor_history("Insert audio asset")


func _insert_local_video_asset(path: String) -> void:
	var stream := ResourceLoader.load(path) as VideoStream
	if stream == null:
		if toolbar_status_label:
			toolbar_status_label.text = "Could not load video: %s" % path.get_file()
		return
	var gui := _ensure_starter_screen_gui()
	if gui == null:
		return
	var player := VideoStreamPlayer.new()
	player.name = path.get_basename().get_file()
	player.stream = stream
	player.autoplay = false
	player.position = Vector2(48, 48)
	player.size = Vector2(480, 270)
	player.set_meta("roblox_class", "VideoFrame")
	player.set_meta("Video", path)
	gui.add_child(player, true)
	explorer_selected_node = player
	_on_data_model_gui_changed()
	_refresh_explorer()
	_show_properties_for_node(player)
	_commit_editor_history("Insert video asset")

func _studio_panel_style(fill: Color, border: Color, border_width: int = 1, radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _studio_line_edit_style() -> StyleBoxFlat:
	var style := _studio_panel_style(Color.WHITE, Color("#CCCCCC"), 1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func _create_ribbon_separator() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 50)
	return sep

func _create_snap_controls() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "SnapControls"
	root.custom_minimum_size = Vector2(104, 50)
	root.add_theme_constant_override("separation", 1)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 2)
	root.add_child(row1)
	snap_enabled_check = CheckBox.new()
	snap_enabled_check.text = "Snap"
	snap_enabled_check.button_pressed = true
	snap_enabled_check.add_theme_font_size_override("font_size", 9)
	row1.add_child(snap_enabled_check)
	snap_step_spin = SpinBox.new()
	snap_step_spin.min_value = 0.1
	snap_step_spin.max_value = 64.0
	snap_step_spin.step = 0.5
	snap_step_spin.value = 1.0
	snap_step_spin.suffix = " st"
	snap_step_spin.custom_minimum_size = Vector2(62, 22)
	row1.add_child(snap_step_spin)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 2)
	root.add_child(row2)
	angle_snap_enabled_check = CheckBox.new()
	angle_snap_enabled_check.text = "Angle"
	angle_snap_enabled_check.button_pressed = true
	angle_snap_enabled_check.add_theme_font_size_override("font_size", 9)
	row2.add_child(angle_snap_enabled_check)
	angle_snap_step_spin = SpinBox.new()
	angle_snap_step_spin.min_value = 1.0
	angle_snap_step_spin.max_value = 180.0
	angle_snap_step_spin.step = 1.0
	angle_snap_step_spin.value = 45.0
	angle_snap_step_spin.suffix = " deg"
	angle_snap_step_spin.custom_minimum_size = Vector2(62, 22)
	row2.add_child(angle_snap_step_spin)
	return root

func _set_tool_window_visible(window_name: String, visible: bool) -> void:
	match window_name:
		"properties":
			if properties_dock_panel:
				properties_dock_panel.visible = visible
		"explorer":
			if explorer_dock_panel:
				explorer_dock_panel.visible = visible
		"toolbox":
			if toolbox_dock_panel:
				toolbox_dock_panel.visible = visible
			if visible and toolbox_content_tabs != null:
				toolbox_content_tabs.current_tab = 0
	if _is_mobile_studio_runtime():
		if window_name == "toolbox" and visible and right_side != null:
			right_side.visible = false
		elif window_name in ["properties", "explorer"]:
			if visible and toolbox_dock_panel != null:
				toolbox_dock_panel.visible = false
			if right_side != null:
				right_side.visible = (
					(explorer_dock_panel != null and explorer_dock_panel.visible)
					or (properties_dock_panel != null and properties_dock_panel.visible)
				)

func _toggle_tool_window(window_name: String) -> void:
	if window_name == "toolbox" and toolbox_content_tabs != null and toolbox_content_tabs.current_tab != 0:
		_set_tool_window_visible("toolbox", true)
		return
	if _is_mobile_studio_runtime() and window_name in ["properties", "explorer", "toolbox"]:
		_toggle_mobile_studio_panel(window_name)
		return
	match window_name:
		"properties":
			if properties_dock_panel:
				properties_dock_panel.visible = not properties_dock_panel.visible
		"explorer":
			if explorer_dock_panel:
				explorer_dock_panel.visible = not explorer_dock_panel.visible
		"toolbox":
			if toolbox_dock_panel:
				toolbox_dock_panel.visible = not toolbox_dock_panel.visible
		"assets":
			_open_assets_dialog()

func _reset_studio_camera() -> void:
	if camera == null:
		return
	camera.global_position = Vector3(24, 24, 24)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	velocity = Vector3.ZERO
	_reset_studio_camera_interpolation()
	if toolbar_status_label:
		toolbar_status_label.text = "Camera reset"

func _zoom_camera_to_mouse(zoom_in: bool, viewport_position: Vector2) -> void:
	if camera == null:
		return
	var ray_dir := camera.project_ray_normal(_viewport_container_to_subviewport_position(viewport_position)).normalized()
	var zoom_distance := 3.0 if zoom_in else -3.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		zoom_distance *= 3.0
	camera.global_position += ray_dir * zoom_distance
	velocity = Vector3.ZERO
	_reset_studio_camera_interpolation()

func _set_studio_axis_view(direction: Vector3) -> void:
	if camera == null:
		return
	var focus := _get_selection_pivot() if not _get_valid_selected_blocks().is_empty() else Vector3.ZERO
	var distance := 36.0
	var dir := direction.normalized()
	camera.global_position = focus - dir * distance
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.95:
		up = Vector3.FORWARD
	camera.look_at(focus, up)
	velocity = Vector3.ZERO
	_reset_studio_camera_interpolation()
	if toolbar_status_label:
		toolbar_status_label.text = "Viewport axis view"

func _on_studio_test_control_pressed(action_name: String) -> void:
	match action_name:
		"Play":
			_start_studio_playtest()
		"Pause":
			_toggle_studio_playtest_pause()
		"Stop":
			_stop_studio_playtest()
		"Reset":
			_reset_studio_playtest_character()
		"Record":
			_capture_studio_viewport()


func _capture_studio_viewport() -> void:
	if DisplayServer.get_name() == "headless":
		if toolbar_status_label:
			toolbar_status_label.text = "Viewport capture is unavailable in headless mode"
		return
	var viewport := _get_studio_subviewport()
	if viewport == null or not is_instance_valid(viewport):
		if toolbar_status_label:
			toolbar_status_label.text = "Viewport capture failed: viewport is unavailable"
		return
	if toolbar_status_label:
		toolbar_status_label.text = "Capturing viewport..."
	await RenderingServer.frame_post_draw
	var viewport_texture := viewport.get_texture()
	var image := viewport_texture.get_image() if viewport_texture != null else null
	if image == null or image.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Viewport capture failed: empty frame"
		return
	var capture_dir := "user://studio_captures"
	var absolute_dir := ProjectSettings.globalize_path(capture_dir)
	var make_dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		if toolbar_status_label:
			toolbar_status_label.text = "Viewport capture failed: cannot create output folder"
		return
	var now := Time.get_datetime_dict_from_system()
	var file_name := "Studio_%04d%02d%02d_%02d%02d%02d.png" % [
		int(now.get("year", 0)), int(now.get("month", 0)), int(now.get("day", 0)),
		int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0))
	]
	var output_path := capture_dir.path_join(file_name)
	var save_error := image.save_png(output_path)
	if toolbar_status_label:
		toolbar_status_label.text = (
			"Viewport saved: %s" % ProjectSettings.globalize_path(output_path)
			if save_error == OK
			else "Viewport capture failed: error %d" % save_error
		)

func _start_studio_playtest() -> void:
	if studio_playtest_active:
		if toolbar_status_label:
			toolbar_status_label.text = "Play test already running"
		return
	studio_playtest_generation += 1
	var playtest_generation := studio_playtest_generation
	studio_playtest_active = true
	studio_playtest_paused = false
	# Generated and edited scripts open their own document. Play must bring the
	# game viewport back before locking editor controls and routing input.
	_show_viewport_document()
	_set_studio_playtest_ui_locked(true)
	if not current_music_source_paths.is_empty(): _play_studio_music(0)
	if toolbar_status_label:
		toolbar_status_label.text = "Preparing Play test scene..."
	studio_playtest_snapshot = await _capture_playtest_scene_snapshot_async("PlayTestSnapshot", playtest_generation)
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	# DataModel edits update current_roblox_place_manifest at their mutation
	# boundary. Re-serializing thousands of imported instances here made Play
	# spend minutes rebuilding an unchanged map before the first frame.
	# The interactive PlayerGui is rebuilt after the playtest character and its
	# live player containers exist. Building the same multi-thousand-control GUI
	# here as well doubled Play startup time on imported places.
	_clear_roblox_gui_preview()
	_set_shape("Select")
	_clear_selection()
	_activate_studio_playtest_dynamic_parts()
	if LuaScriptEngine != null and LuaScriptEngine.has_method("reset_runtime_diagnostics"):
		LuaScriptEngine.reset_runtime_diagnostics()
	if toolbar_status_label:
		toolbar_status_label.text = "Preparing Play test scripts..."
	await get_tree().process_frame
	var server_report := await _run_studio_playtest_server_scripts(playtest_generation)
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	await _await_playtest_script_compilation(playtest_generation, "server")
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	# Roblox starts server scripts before the first character joins. Client
	# scripts run only after StarterGui/StarterPack/StarterPlayer templates have
	# been cloned into their live player containers.
	await get_tree().process_frame
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	_prepare_studio_playtest_respawn_triggers()
	_spawn_studio_playtest_player()
	await get_tree().process_frame
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	# PlayerGui is created while the local player is bound. Rebuild the visual
	# HUD now so its buttons target those live clones instead of StarterGui.
	await _refresh_roblox_gui_preview()
	await get_tree().process_frame
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	var client_report := await _run_studio_playtest_local_scripts(playtest_generation)
	await _await_playtest_script_compilation(playtest_generation, "client")
	if not studio_playtest_active or playtest_generation != studio_playtest_generation:
		return
	var started_total := int(server_report.get("started", 0)) + int(client_report.get("started", 0))
	var failed_total := int(server_report.get("failed", 0)) + int(client_report.get("failed", 0))
	var inactive_total := (
		int(server_report.get("skipped_context", 0)) + int(server_report.get("skipped_disabled", 0))
		+ int(client_report.get("skipped_context", 0)) + int(client_report.get("skipped_disabled", 0))
	)
	if toolbar_status_label:
		toolbar_status_label.text = "Play test: %d running, %d rejected, %d inactive" % [
			started_total,
			failed_total,
			inactive_total,
		]


func _activate_studio_playtest_dynamic_parts() -> void:
	if placement_parent == null:
		return
	for part_node in _get_editor_parts():
		if not (part_node is MeshInstance3D):
			continue
		var part := part_node as MeshInstance3D
		var physics_mode := str(part.get_meta("bobux_physics_mode", "Static")).strip_edges().to_lower()
		if physics_mode != "dynamic" and bool(part.get_meta("anchored", true)):
			continue
		_create_studio_playtest_rigid_body(part)


func _create_studio_playtest_rigid_body(part: MeshInstance3D) -> RigidBody3D:
	if part == null or not is_instance_valid(part) or part.get_parent() == null:
		return null
	var static_body := part.get_node_or_null(COLLISION_BODY_NAME) as StaticBody3D
	if static_body != null:
		var static_shape := static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if static_shape != null:
			static_shape.disabled = true
	var rigid_body := RigidBody3D.new()
	rigid_body.name = "%s_PhysicsBody" % part.name
	rigid_body.set_meta("bobux_runtime_generated", true)
	rigid_body.set_meta("bobux_visual_instance_id", part.get_instance_id())
	rigid_body.collision_layer = STUDIO_PLAYTEST_COLLISION_MASK
	rigid_body.collision_mask = STUDIO_PLAYTEST_COLLISION_MASK | 2
	rigid_body.mass = maxf(0.05, float(part.get_meta("bobux_physics_mass", 1.0)))
	rigid_body.gravity_scale = maxf(0.0, float(part.get_meta("bobux_physics_gravity_scale", 1.0)))
	rigid_body.linear_damp = maxf(0.0, float(part.get_meta("bobux_physics_linear_damp", 0.1)))
	rigid_body.angular_damp = maxf(0.0, float(part.get_meta("bobux_physics_angular_damp", 0.1)))
	rigid_body.continuous_cd = true
	rigid_body.contact_monitor = true
	rigid_body.max_contacts_reported = 8
	var physical_material := PhysicsMaterial.new()
	physical_material.friction = clampf(float(part.get_meta("bobux_physics_friction", 0.5)), 0.0, 1.0)
	physical_material.bounce = clampf(float(part.get_meta("bobux_physics_bounce", 0.0)), 0.0, 1.0)
	rigid_body.physics_material_override = physical_material
	part.get_parent().add_child(rigid_body, true)
	var visual_scale := part.global_basis.get_scale().abs()
	rigid_body.global_transform = Transform3D(part.global_basis.orthonormalized(), part.global_position)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	if bool(part.get_meta("roblox_mesh_applied", false)) and part.mesh != null:
		collision_shape.shape = part.mesh.create_convex_shape(true, false)
	else:
		collision_shape.shape = _create_collision_for_shape(_get_block_shape(part))
		_apply_collision_shape_size(collision_shape, _get_block_shape(part), visual_scale)
	collision_shape.scale = visual_scale
	collision_shape.disabled = not bool(part.get_meta("can_collide", true))
	rigid_body.add_child(collision_shape)
	var remote := RemoteTransform3D.new()
	remote.name = "VisualFollower"
	remote.update_position = true
	remote.update_rotation = true
	remote.update_scale = false
	rigid_body.add_child(remote)
	remote.remote_path = remote.get_path_to(part)
	part.set_meta("_bobux_physics_body_instance_id", rigid_body.get_instance_id())
	return rigid_body


func _await_playtest_script_compilation(playtest_generation: int, realm_label: String) -> void:
	if LuaScriptEngine == null or not LuaScriptEngine.has_method("get_runtime_diagnostics"):
		return
	var frames_waited := 0
	while studio_playtest_active and playtest_generation == studio_playtest_generation:
		var diagnostics: Dictionary = LuaScriptEngine.get_runtime_diagnostics()
		var pending := int(diagnostics.get("pending", 0))
		if pending <= 0:
			break
		if toolbar_status_label:
			toolbar_status_label.text = "Compiling %s scripts (%d remaining)..." % [realm_label, pending]
		frames_waited += 1
		# A malformed place may contain thousands of generated script copies. Keep
		# Stop responsive and avoid waiting forever if the extension stalls.
		if frames_waited >= 2400:
			push_warning("[Studio] Timed out waiting for %s script compilation (%d pending)." % [realm_label, pending])
			break
		await get_tree().process_frame
	# Initial resumes install Touched/event callbacks after compilation. Give the
	# scheduler one frame to run them before spawning the character or declaring
	# the client ready.
	await get_tree().process_frame

func _toggle_studio_playtest_pause() -> void:
	if not studio_playtest_active:
		if toolbar_status_label:
			toolbar_status_label.text = "Start Play before Pause"
		return
	studio_playtest_paused = not studio_playtest_paused
	if LuaScriptEngine != null and LuaScriptEngine.has_method("set_scripts_paused"):
		LuaScriptEngine.set_scripts_paused(studio_playtest_paused)
	if toolbar_status_label:
		toolbar_status_label.text = "Play test %s" % ("paused" if studio_playtest_paused else "resumed")

func _stop_studio_playtest() -> void:
	if is_instance_valid(studio_music_player): studio_music_player.stop()
	if not studio_playtest_active:
		if toolbar_status_label:
			toolbar_status_label.text = "Play test is not running"
		return
	studio_playtest_active = false
	studio_playtest_paused = false
	studio_playtest_generation += 1
	if LuaScriptEngine != null:
		if LuaScriptEngine.has_method("set_scripts_paused"):
			LuaScriptEngine.set_scripts_paused(false)
		if LuaScriptEngine.has_method("stop_all_scripts"):
			# Script callbacks can be connected to viewport GUI, RunService and
			# detached InsertService models as well as DataModel/Workspace nodes.
			# Clear the complete runtime graph before releasing Lua states.
			LuaScriptEngine.stop_all_scripts()
	_clear_studio_playtest_respawn_triggers()
	_despawn_studio_playtest_player()
	if not studio_playtest_snapshot.is_empty():
		await _restore_playtest_scene_snapshot(studio_playtest_snapshot)
	studio_playtest_snapshot.clear()
	# Restoring queues the playtest nodes for deferred deletion. Keep Lua states
	# alive through one additional frame so callbacks owned by those nodes are
	# destroyed before the extension closes their lua_State.
	await get_tree().process_frame
	if LuaScriptEngine != null and LuaScriptEngine.has_method("release_stopped_script_states"):
		LuaScriptEngine.release_stopped_script_states()
	_reset_studio_camera()
	_refresh_roblox_gui_preview()
	_set_studio_playtest_ui_locked(false)
	if toolbar_status_label:
		toolbar_status_label.text = "Play test stopped and scene restored"


func _reset_studio_playtest_character() -> void:
	if not studio_playtest_active:
		if toolbar_status_label:
			toolbar_status_label.text = "Start Play before Reset Character"
		return
	if studio_playtest_player == null or not is_instance_valid(studio_playtest_player):
		_spawn_studio_playtest_player()
		if toolbar_status_label:
			toolbar_status_label.text = "Play test character recreated"
		return
	if studio_playtest_player.has_method("force_respawn"):
		studio_playtest_player.call("force_respawn")
	else:
		var spawn_position := _get_studio_playtest_spawn_global_position()
		studio_playtest_player.global_position = spawn_position
		studio_playtest_player.velocity = Vector3.ZERO
		if studio_playtest_player.has_method("set_initial_spawn_position"):
			studio_playtest_player.call("set_initial_spawn_position", spawn_position)
		studio_playtest_player.reset_physics_interpolation()
	if toolbar_status_label:
		toolbar_status_label.text = "Character reset"


func _get_workspace_stud_scale() -> float:
	if placement_parent != null and placement_parent.has_meta("roblox_stud_scale"):
		return clampf(float(placement_parent.get_meta("roblox_stud_scale", 1.0)), 0.25, 2.0)
	return 1.0


func _spawn_studio_playtest_player() -> void:
	_despawn_studio_playtest_player()
	if placement_parent == null or STUDIO_PLAYTEST_PLAYER_SCENE == null:
		return
	var player_variant := STUDIO_PLAYTEST_PLAYER_SCENE.instantiate()
	if not (player_variant is CharacterBody3D):
		if player_variant != null:
			player_variant.queue_free()
		return
	var player := player_variant as CharacterBody3D
	player.name = "Character"
	player.set_meta("Name", "Character")
	player.set_meta("roblox_class", "Model")
	player.set_meta("bobux_runtime_generated", true)
	player.set_meta("bobux_studio_playtest", true)
	player.set_meta("bobux_world_collision_mask", STUDIO_PLAYTEST_COLLISION_MASK)
	player.set("is_ui_preview", false)
	var world_stud_scale := _get_workspace_stud_scale()
	if player.has_method("apply_world_stud_scale"):
		player.call("apply_world_stud_scale", world_stud_scale)
	else:
		player.scale = Vector3.ONE * world_stud_scale
	var display_name := UserSession.username.strip_edges() if UserSession != null else ""
	player.set("display_name", display_name if not display_name.is_empty() else "Player")
	_create_studio_playtest_character_api(player)
	placement_parent.add_child(player, true)
	var spawn_position := _get_studio_playtest_spawn_global_position()
	player.global_position = spawn_position
	if player.has_method("set_initial_spawn_position"):
		player.call("set_initial_spawn_position", spawn_position)
	if player.has_method("configure_spawn_points"):
		var spawn_points: Array[Vector3] = []
		for spawn_part in _get_studio_playtest_spawn_parts():
			spawn_points.append(_get_part_respawn_global_position(spawn_part))
		if spawn_points.is_empty():
			spawn_points.append(spawn_position)
		player.call("configure_spawn_points", spawn_points, spawn_points.find(spawn_position))
	if player.has_method("apply_movement_settings"):
		player.call("apply_movement_settings", _get_current_player_settings())
	studio_playtest_player = player
	if camera != null:
		camera.current = false
	if LuaScriptEngine != null and LuaScriptEngine.has_method("bind_local_player_character"):
		LuaScriptEngine.bind_local_player_character(player)
	_ensure_studio_inventory_controller()
	player.reset_physics_interpolation()


func _create_studio_playtest_character_api(player: CharacterBody3D) -> void:
	if player.has_method("ensure_roblox_character_contract"):
		player.call("ensure_roblox_character_contract")
		return
	var humanoid := player.get_node_or_null("Humanoid")
	if humanoid == null:
		humanoid = Node.new()
		humanoid.name = "Humanoid"
		player.add_child(humanoid)
	humanoid.set_meta("roblox_class", "Humanoid")
	humanoid.set_meta("bobux_character_body_instance_id", player.get_instance_id())
	humanoid.set_meta("Health", 100.0)
	humanoid.set_meta("MaxHealth", 100.0)
	humanoid.set_meta("WalkSpeed", player.get_humanoid_walk_speed())
	humanoid.set_meta("JumpPower", player.get_humanoid_jump_power())
	humanoid.set_meta("bobux_runtime_generated", true)
	var proxy_specs := {
		"HumanoidRootPart": Vector3(0.0, 2.3, 0.0),
		"Torso": Vector3(0.0, 3.0, 0.0),
		"Head": Vector3(0.0, 4.6, 0.0),
	}
	for proxy_name_variant in proxy_specs.keys():
		var proxy_name := str(proxy_name_variant)
		var proxy := Node3D.new()
		proxy.name = proxy_name
		proxy.position = proxy_specs[proxy_name_variant]
		proxy.set_meta("roblox_class", "Part")
		proxy.set_meta("bobux_character_part_proxy", true)
		proxy.set_meta("bobux_character_body_instance_id", player.get_instance_id())
		proxy.set_meta("bobux_runtime_generated", true)
		player.add_child(proxy)


func _despawn_studio_playtest_player() -> void:
	if LuaScriptEngine != null and LuaScriptEngine.has_method("unbind_local_player_character"):
		LuaScriptEngine.unbind_local_player_character(studio_playtest_player)
	if studio_playtest_player != null and is_instance_valid(studio_playtest_player):
		studio_playtest_player.queue_free()
	studio_playtest_player = null
	if studio_inventory_controller != null and is_instance_valid(studio_inventory_controller):
		studio_inventory_controller.queue_free()
	studio_inventory_controller = null
	if camera != null and is_instance_valid(camera):
		camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ensure_studio_inventory_controller() -> void:
	if studio_inventory_controller != null and is_instance_valid(studio_inventory_controller):
		if studio_inventory_controller.has_method("refresh_now"):
			studio_inventory_controller.call("refresh_now", true)
		return
	var viewport := _get_studio_subviewport()
	if viewport == null:
		return
	var controller_variant := RobloxInventoryControllerClass.new()
	if not (controller_variant is CanvasLayer):
		return
	studio_inventory_controller = controller_variant as CanvasLayer
	studio_inventory_controller.set("show_local_player_list", true)
	studio_inventory_controller.call("configure", LuaScriptEngine, placement_parent, Callable(self, "_get_studio_playtest_player"))
	viewport.add_child(studio_inventory_controller)


func _get_studio_subviewport() -> SubViewport:
	if viewport_container_node != null and is_instance_valid(viewport_container_node):
		return viewport_container_node.get_node_or_null("SubViewport") as SubViewport
	return get_node_or_null("SubViewportContainer/SubViewport") as SubViewport


func _get_studio_playtest_player() -> CharacterBody3D:
	return studio_playtest_player if studio_playtest_player != null and is_instance_valid(studio_playtest_player) else null


func _get_studio_playtest_spawn_global_position() -> Vector3:
	var fallback_part: Node3D = null
	var fallback_score := -INF
	for part in _get_editor_parts():
		if part == null or not is_instance_valid(part):
			continue
		var is_spawn := bool(part.get_meta("is_spawn", false)) or str(part.get_meta("roblox_class", "")) == "SpawnLocation"
		if is_spawn:
			return _get_part_respawn_global_position(part)
		if not bool(part.get_meta("can_collide", true)):
			continue
		var part_scale := part.global_basis.get_scale().abs()
		var horizontal_area := part_scale.x * part_scale.z
		var flatness := maxf(part_scale.x, part_scale.z) / maxf(part_scale.y, 0.05)
		var score := horizontal_area * minf(flatness, 50.0)
		if score > fallback_score:
			fallback_score = score
			fallback_part = part
	if fallback_part != null:
		return _get_part_respawn_global_position(fallback_part)
	return Vector3(0.0, 8.0, 0.0)


func _get_studio_playtest_spawn_parts() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for part in _get_editor_parts():
		if part != null and is_instance_valid(part) and (bool(part.get_meta("is_spawn", false)) or str(part.get_meta("roblox_class", "")) == "SpawnLocation"):
			result.append(part)
	return result


func _get_part_respawn_global_position(part: Node3D) -> Vector3:
	if part == null or not is_instance_valid(part):
		return Vector3(0.0, 8.0, 0.0)
	var corners := _get_node_world_corners(part)
	if corners.is_empty():
		return part.global_position + Vector3.UP * 0.6
	var min_point := corners[0]
	var max_point := corners[0]
	for corner in corners:
		min_point = min_point.min(corner)
		max_point = max_point.max(corner)
	return Vector3((min_point.x + max_point.x) * 0.5, max_point.y + 0.12, (min_point.z + max_point.z) * 0.5)


func _prepare_studio_playtest_respawn_triggers() -> void:
	_clear_studio_playtest_respawn_triggers()
	if placement_parent == null:
		return
	for part in _get_editor_parts():
		if part == null or not is_instance_valid(part):
			continue
		var shape_type := str(part.get_meta("shape_type", ""))
		var roblox_class := str(part.get_meta("roblox_class", ""))
		var is_respawn_surface := bool(part.get_meta("is_spawn", false)) or roblox_class == "SpawnLocation" or shape_type == "Checkpoint"
		if not is_respawn_surface:
			continue
		var corners := _get_node_world_corners(part)
		if corners.is_empty():
			continue
		var min_point := corners[0]
		var max_point := corners[0]
		for corner in corners:
			min_point = min_point.min(corner)
			max_point = max_point.max(corner)
		var area := Area3D.new()
		area.name = "RespawnTrigger_%s" % part.name
		area.collision_layer = 0
		area.collision_mask = 1 << 1
		area.monitoring = true
		area.monitorable = false
		area.set_meta("bobux_runtime_generated", true)
		placement_parent.add_child(area)
		area.global_position = Vector3((min_point.x + max_point.x) * 0.5, max_point.y + 1.8, (min_point.z + max_point.z) * 0.5)
		var collision := CollisionShape3D.new()
		var trigger_shape := BoxShape3D.new()
		trigger_shape.size = Vector3(maxf(max_point.x - min_point.x, 0.8), 3.6, maxf(max_point.z - min_point.z, 0.8))
		collision.shape = trigger_shape
		area.add_child(collision)
		area.body_entered.connect(_on_studio_respawn_trigger_entered.bind(_get_part_respawn_global_position(part), part.name))
		studio_playtest_respawn_triggers.append(area)


func _on_studio_respawn_trigger_entered(body: Node3D, respawn_target: Vector3, checkpoint_name: String) -> void:
	if not studio_playtest_active or body == null or body != studio_playtest_player:
		return
	if body.has_method("set_respawn_position"):
		body.call("set_respawn_position", respawn_target)
	if toolbar_status_label != null:
		toolbar_status_label.text = "Checkpoint active: %s" % checkpoint_name


func _clear_studio_playtest_respawn_triggers() -> void:
	for area in studio_playtest_respawn_triggers:
		if area != null and is_instance_valid(area):
			area.queue_free()
	studio_playtest_respawn_triggers.clear()


func _run_studio_playtest_server_scripts(playtest_generation: int) -> Dictionary:
	if data_model == null or LuaScriptEngine == null or not LuaScriptEngine.has_method("start_script"):
		return {"started": 0, "failed": 0, "skipped_context": 0, "skipped_disabled": 0}
	var runnable: Array = []
	var seen_script_nodes: Dictionary = {}
	for node_variant in data_model.find_all_of_class("Script"):
		if node_variant is Node:
			var node_id := (node_variant as Node).get_instance_id()
			if seen_script_nodes.has(node_id):
				continue
			seen_script_nodes[node_id] = true
			runnable.append(node_variant)
	return await _start_studio_playtest_script_nodes(runnable, playtest_generation, "server")


func _run_studio_playtest_local_scripts(playtest_generation: int) -> Dictionary:
	if LuaScriptEngine == null or not LuaScriptEngine.has_method("get_local_inventory_state"):
		return {"started": 0, "failed": 0, "skipped_context": 0, "skipped_disabled": 0}
	var state_variant: Variant = LuaScriptEngine.call("get_local_inventory_state", placement_parent, studio_playtest_player)
	if not (state_variant is Dictionary):
		return {"started": 0, "failed": 0, "skipped_context": 0, "skipped_disabled": 0}
	var runnable: Array = LuaScriptEngine.collect_live_player_scripts(placement_parent, studio_playtest_player)
	var seen: Dictionary = {}
	if data_model != null:
		_collect_playtest_scripts_recursive(data_model.ensure_service("ReplicatedFirst"), "LocalScript", runnable, seen)
	return await _start_studio_playtest_script_nodes(runnable, playtest_generation, "player")


func _collect_playtest_scripts_recursive(root: Node, script_class: String, out: Array, seen: Dictionary) -> void:
	if root == null:
		return
	for child in root.get_children():
		var child_class := str(child.get_meta("roblox_class", child.get_meta("script_type", "")))
		if child_class == script_class and not seen.has(child.get_instance_id()):
			seen[child.get_instance_id()] = true
			out.append(child)
		_collect_playtest_scripts_recursive(child, script_class, out, seen)


func _start_studio_playtest_script_nodes(runnable: Array, playtest_generation: int, realm: String) -> Dictionary:
	if LuaScriptEngine == null or not LuaScriptEngine.has_method("start_script"):
		return {"started": 0, "failed": 0, "skipped_context": 0, "skipped_disabled": 0}
	var started := 0
	var failed := 0
	var skipped_context := 0
	var skipped_disabled := 0
	var processed := 0
	for script_variant in runnable:
		if not studio_playtest_active or playtest_generation != studio_playtest_generation:
			break
		var script_node := script_variant as Node
		if script_node == null or bool(script_node.get_meta("disabled", false)):
			skipped_disabled += 1
			continue
		var script_class := str(script_node.get_meta("roblox_class", script_node.get_meta("script_type", "Script")))
		if script_node.has_meta("bobux_script_runtime_id"):
			continue
		if realm == "server" and not _is_script_runnable_in_playtest(script_node, script_class):
			skipped_context += 1
			continue
		if realm == "client" and script_class != "LocalScript":
			skipped_context += 1
			continue
		var source := str(script_node.get_meta("code", script_node.get_meta("lua_source", ""))).strip_edges()
		if source.is_empty():
			skipped_disabled += 1
			continue
		var result: Dictionary = LuaScriptEngine.start_script(source, script_node, {
			"realm": "server" if script_class == "Script" else "client",
			"is_server": script_class == "Script",
			"source_name": str(script_node.get_path()),
			"retain": true,
			"defer_initial_resume": true,
			"defer_compilation": true,
		})
		if bool(result.get("ok", false)):
			started += 1
		else:
			failed += 1
		processed += 1
		if processed % PLAYTEST_SCRIPT_START_BATCH == 0:
			if toolbar_status_label:
				toolbar_status_label.text = "Starting scripts %d/%d..." % [processed, runnable.size()]
			await get_tree().process_frame
	return {
		"started": started,
		"failed": failed,
		"skipped_context": skipped_context,
		"skipped_disabled": skipped_disabled,
		"candidates": runnable.size(),
	}


func _is_script_runnable_in_playtest(script_node: Node, script_class: String) -> bool:
	var service_name := _roblox_service_ancestor_name(script_node)
	if script_class == "Script":
		return service_name in ["Workspace", "ServerScriptService"]
	if script_class == "LocalScript":
		# Starter containers are cloned into PlayerGui/Backpack/PlayerScripts by
		# Roblox. Bobux currently executes their live editor counterparts, while
		# storage templates remain inert until a script explicitly clones them.
		return service_name in ["StarterGui", "StarterPack", "StarterPlayer", "Players"]
	return false


func _roblox_service_ancestor_name(node: Node) -> String:
	var cursor := node
	while cursor != null:
		var roblox_class := str(cursor.get_meta("roblox_class", ""))
		if roblox_class in [
			"Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage",
			"ServerScriptService", "ServerStorage", "StarterGui", "StarterPack",
			"StarterPlayer", "SoundService", "TextChatService"
		]:
			return roblox_class
		cursor = cursor.get_parent()
	return ""

func _is_studio_editing_locked(show_message: bool = true) -> bool:
	if studio_operation_busy:
		if show_message and toolbar_status_label:
			toolbar_status_label.text = "%s is still running" % (studio_operation_name if not studio_operation_name.is_empty() else "Studio operation")
		return true
	if not studio_playtest_active:
		return false
	if show_message and toolbar_status_label:
		toolbar_status_label.text = "Stop Play before editing the scene"
	return true

func _begin_studio_operation(operation_name: String) -> bool:
	if studio_operation_busy:
		if toolbar_status_label:
			toolbar_status_label.text = "%s is already running" % (studio_operation_name if not studio_operation_name.is_empty() else "Studio operation")
		return false
	studio_operation_busy = true
	studio_operation_name = operation_name.strip_edges()
	return true

func _end_studio_operation() -> void:
	studio_operation_busy = false
	studio_operation_name = ""

func _setup_studio_autosave() -> void:
	if studio_autosave_timer != null and is_instance_valid(studio_autosave_timer):
		return
	studio_autosave_timer = Timer.new()
	studio_autosave_timer.name = "StudioAutosaveTimer"
	studio_autosave_timer.wait_time = STUDIO_AUTOSAVE_INTERVAL_SECONDS
	studio_autosave_timer.one_shot = false
	studio_autosave_timer.timeout.connect(_autosave_current_studio_place)
	add_child(studio_autosave_timer)
	studio_autosave_timer.start()

func _autosave_current_studio_place() -> void:
	# Import, publish and large scene rebuilds own the Workspace while they run.
	# Starting an autosave in the middle of one of those operations used to
	# serialize a half-built map, stall the main thread and occasionally replace
	# the useful autosave with an empty scene.
	if studio_operation_busy or studio_playtest_active or is_restoring_history:
		return
	_ensure_directory_path(STUDIO_AUTOSAVE_FOLDER)
	var previous_folder := current_map_folder
	var save_ok := await _save_map(STUDIO_AUTOSAVE_FOLDER)
	current_map_folder = previous_folder
	if not save_ok:
		if toolbar_status_label:
			toolbar_status_label.text = "Autosave failed"
		return
	var meta := _load_map_meta(STUDIO_AUTOSAVE_FOLDER)
	meta["autosave"] = true
	meta["autosaved_from"] = previous_folder
	meta["autosaved_at_unix"] = Time.get_unix_time_from_system()
	var meta_file := FileAccess.open(STUDIO_AUTOSAVE_FOLDER + "/meta.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()
	if toolbar_status_label:
		toolbar_status_label.text = "Autosaved studio_latest"

func _ensure_directory_path(folder: String) -> void:
	if folder.strip_edges().is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

func _toggle_grid_visibility(visible: bool) -> void:
	if studio_grid_root != null and is_instance_valid(studio_grid_root):
		studio_grid_root.visible = visible

func _toggle_collision_preview(enabled: bool) -> void:
	for part in _get_editor_parts():
		var collision_body := part.get_node_or_null(COLLISION_BODY_NAME)
		if collision_body is Node3D:
			(collision_body as Node3D).visible = enabled
	if toolbar_status_label:
		toolbar_status_label.text = "Collider preview %s" % ("enabled" if enabled else "disabled")

func _ensure_studio_grid() -> void:
	if studio_grid_root != null and is_instance_valid(studio_grid_root):
		studio_grid_root.visible = show_grid_enabled
		return
	if placement_parent == null or placement_parent.get_parent() == null:
		return
	studio_grid_root = MeshInstance3D.new()
	studio_grid_root.name = "StudioGrid"
	var grid_mesh := ImmediateMesh.new()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var extent := 100
	for i in range(-extent, extent + 1):
		var line_color := Color(0.25, 0.31, 0.40, 0.72) if i % 5 == 0 else Color(0.38, 0.44, 0.53, 0.42)
		grid_mesh.surface_set_color(line_color)
		grid_mesh.surface_add_vertex(Vector3(i, 0.02, -extent))
		grid_mesh.surface_add_vertex(Vector3(i, 0.02, extent))
		grid_mesh.surface_add_vertex(Vector3(-extent, 0.02, i))
		grid_mesh.surface_add_vertex(Vector3(extent, 0.02, i))
	grid_mesh.surface_end()
	studio_grid_root.mesh = grid_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	studio_grid_root.material_override = mat
	studio_grid_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	studio_grid_root.set_meta("bobux_editor_only", true)
	studio_grid_root.add_to_group("bobux_editor_only")
	studio_grid_root.visible = show_grid_enabled
	placement_parent.get_parent().add_child(studio_grid_root)

func _place_shape_from_ribbon(shape_name: String) -> void:
	var previous_shape := current_shape
	current_shape = shape_name
	_place_block(_get_editor_drop_position(10.0))
	current_shape = previous_shape
	_set_shape("Select")

func _get_editor_drop_position(distance: float = 10.0, use_viewport_center: bool = true) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var ray_position := Vector2(camera.get_viewport().size) * 0.5 if use_viewport_center and camera.get_viewport() != null else _get_studio_mouse_position()
	var origin := camera.project_ray_origin(ray_position)
	var direction := camera.project_ray_normal(ray_position).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_length)
	query.collision_mask = SELECTION_RAY_MASK
	var space_state := camera.get_world_3d().direct_space_state if camera.get_world_3d() != null else null
	if space_state != null:
		var result := space_state.intersect_ray(query)
		if result.has("position"):
			var hit_position: Vector3 = result.get("position", origin + direction * distance)
			var hit_normal: Vector3 = result.get("normal", Vector3.UP)
			return (hit_position + hit_normal * 0.5).snapped(Vector3.ONE * _get_position_snap_step())
	return (origin + direction * distance).snapped(Vector3.ONE * _get_position_snap_step())

func _get_position_snap_step() -> float:
	if snap_enabled_check != null and is_instance_valid(snap_enabled_check) and not snap_enabled_check.button_pressed:
		return 0.001
	if snap_step_spin != null and is_instance_valid(snap_step_spin):
		return maxf(0.001, float(snap_step_spin.value))
	return 0.5

func _open_terrain_panel_popup() -> void:
	if placement_parent == null:
		return
	if roblox_terrain_editor == null:
		roblox_terrain_editor = RobloxTerrainEditorClass.new()
	roblox_terrain_editor.open(self, placement_parent)
	if toolbar_status_label:
		toolbar_status_label.text = "Terrain editor ready"

func _activate_terrain_brush_tool() -> void:
	current_shape = "Select"
	current_editor_tool = "terrain"
	is_box_selecting = false
	_clear_selection_box_visual()
	if is_gizmo_dragging:
		_end_gizmo_drag()
	_refresh_toolbar_states()
	_update_transform_gizmo()
	if toolbar_status_label:
		toolbar_status_label.text = "Terrain brush active - drag in the viewport"

func _insert_character_placeholder() -> void:
	_add_character_to_node(placement_parent)
	if toolbar_status_label:
		toolbar_status_label.text = "Inserted R6 character with Humanoid and Motor6D rig"

func _insert_gui_placeholder() -> void:
	if data_model == null:
		return
	var starter_gui := data_model.ensure_service("StarterGui")
	var gui := RobloxDataModelClass.create_instance("ScreenGui", "ScreenGui")
	starter_gui.add_child(gui, true)
	var frame := RobloxDataModelClass.create_instance("Frame", "Frame")
	if frame is Control:
		(frame as Control).position = Vector2(80, 72)
		(frame as Control).size = Vector2(360, 220)
	frame.set_meta("roblox_properties", {
		"Position": {"x": {"scale": 0.0, "offset": 80.0}, "y": {"scale": 0.0, "offset": 72.0}},
		"Size": {"x": {"scale": 0.0, "offset": 360.0}, "y": {"scale": 0.0, "offset": 220.0}},
		"BackgroundColor3": [0.16, 0.18, 0.22],
		"BackgroundTransparency": 0.08,
		"Visible": true,
	})
	gui.add_child(frame, true)
	var title := RobloxDataModelClass.create_instance("TextLabel", "Title")
	if title is Label:
		(title as Label).text = "New interface"
		(title as Label).position = Vector2(20, 18)
		(title as Label).size = Vector2(320, 48)
	title.set_meta("roblox_properties", {
		"Text": "New interface", "TextSize": 24, "TextColor3": [1.0, 1.0, 1.0],
		"BackgroundTransparency": 1.0,
		"Position": {"x": {"scale": 0.0, "offset": 20.0}, "y": {"scale": 0.0, "offset": 18.0}},
		"Size": {"x": {"scale": 0.0, "offset": 320.0}, "y": {"scale": 0.0, "offset": 48.0}},
	})
	frame.add_child(title, true)
	var button := RobloxDataModelClass.create_instance("TextButton", "ActionButton")
	if button is Button:
		(button as Button).text = "Action"
		(button as Button).position = Vector2(80, 132)
		(button as Button).size = Vector2(200, 52)
	button.set_meta("roblox_properties", {
		"Text": "Action", "TextSize": 18, "TextColor3": [1.0, 1.0, 1.0],
		"BackgroundColor3": [0.0, 0.48, 0.82], "BackgroundTransparency": 0.0,
		"Position": {"x": {"scale": 0.0, "offset": 80.0}, "y": {"scale": 0.0, "offset": 132.0}},
		"Size": {"x": {"scale": 0.0, "offset": 200.0}, "y": {"scale": 0.0, "offset": 52.0}},
	})
	frame.add_child(button, true)
	_on_data_model_gui_changed()
	_refresh_explorer()
	_show_properties_for_node(frame)
	_commit_editor_history("Insert ScreenGui")
	if toolbar_status_label:
		toolbar_status_label.text = "Inserted ScreenGui in StarterGui"

func _insert_script_from_ribbon() -> void:
	var selected := _get_selected_editor_node()
	if selected != null:
		_add_script_to_node(selected)
	elif data_model != null:
		_add_script_to_node(data_model.ensure_service("ServerScriptService"), "", "Script")
	else:
		_add_script_to_node(null, "ServerScriptService", "Script")

func _open_material_selector() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Material"
	dialog.ok_button_text = "Close"
	add_child(dialog)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.custom_minimum_size = Vector2(360, 180)
	dialog.add_child(grid)
	for mat_name in ["Plastic", "SmoothPlastic", "Wood", "WoodPlanks", "Concrete", "Metal", "Glass", "Neon", "Slate"]:
		var btn := Button.new()
		btn.text = mat_name
		btn.custom_minimum_size = Vector2(112, 34)
		btn.pressed.connect(func() -> void:
			current_material_type = mat_name
			for block in _get_valid_selected_blocks():
				block.set_meta("material_type", mat_name)
				if block is MeshInstance3D:
					_rebuild_block_material(block)
			_update_inspector()
			_commit_editor_history("Change Material")
			dialog.hide()
		)
		_style_white_button(btn)
		grid.add_child(btn)
	dialog.popup_centered(Vector2i(420, 260))

func _open_color_selector() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Color"
	dialog.ok_button_text = "Done"
	add_child(dialog)
	var picker := ColorPicker.new()
	picker.color = current_color
	picker.custom_minimum_size = Vector2(420, 360)
	picker.color_changed.connect(_on_color_changed)
	dialog.add_child(picker)
	dialog.popup_centered(Vector2i(460, 420))

func _open_assets_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Assets"
	dialog.ok_button_text = "Close"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(640, 420)
	root.add_theme_constant_override("separation", 8)
	dialog.add_child(root)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	for tab_spec in [["Models", "Models"], ["Decals", "Decals"], ["Meshes", "Meshes"], ["Audio", "Audio"], ["Plugins", "Plugins"]]:
		var tab_name := str(tab_spec[0])
		var category := str(tab_spec[1])
		var page := VBoxContainer.new()
		page.name = tab_name
		page.add_theme_constant_override("separation", 6)
		var entries := _get_toolbox_entries(category)
		var summary := Label.new()
		summary.text = "%d available %s item(s). Double-click to insert or open." % [entries.size(), tab_name.to_lower()]
		summary.add_theme_color_override("font_color", Color("#55585C"))
		page.add_child(summary)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_theme_stylebox_override("panel", _studio_panel_style(Color.WHITE, Color("#D4D6D9"), 1, 2))
		for entry in entries:
			list.add_item(str(entry.get("label", "Asset")), _get_toolbar_icon(str(entry.get("icon", "Assets")), Color("#34373C")))
			var index := list.item_count - 1
			list.set_item_metadata(index, entry)
			list.set_item_tooltip(index, str(entry.get("path", entry.get("description", entry.get("label", "Asset")))))
		if list.item_count == 0:
			list.add_item("No matching project assets")
			list.set_item_disabled(0, true)
		list.item_activated.connect(_on_assets_dialog_item_activated.bind(list))
		page.add_child(list)
		tabs.add_child(page)
	dialog.popup_centered(Vector2i(700, 500))


func _on_assets_dialog_item_activated(index: int, list: ItemList) -> void:
	if list == null or index < 0 or index >= list.item_count:
		return
	var entry_variant: Variant = list.get_item_metadata(index)
	if entry_variant is Dictionary:
		_activate_toolbox_entry(entry_variant as Dictionary)

func _group_selected_blocks() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	if valid_blocks.size() < 2:
		if toolbar_status_label:
			toolbar_status_label.text = "Select two or more parts to group"
		return
	var group_model := Node3D.new()
	group_model.name = "Model_%04d" % (randi() % 10000)
	group_model.set_meta("roblox_class", "Model")
	group_model.set_meta("block_name", group_model.name)
	var common_parent := valid_blocks[0].get_parent()
	if common_parent == null:
		common_parent = placement_parent
	common_parent.add_child(group_model, true)
	for block in valid_blocks:
		var original_transform := block.global_transform
		block.reparent(group_model, true)
		block.global_transform = original_transform
		block.set_meta("model_group", group_model.name)
	explorer_selected_node = group_model
	_set_selection([])
	_refresh_explorer()
	_commit_editor_history("Group")
	if toolbar_status_label:
		toolbar_status_label.text = "Grouped %d part(s) as %s" % [valid_blocks.size(), group_model.name]


func _ungroup_selected_models() -> void:
	if _is_studio_editing_locked():
		return
	var models: Array[Node3D] = []
	var selected_node := _get_selected_editor_node()
	if selected_node is Node3D and str(selected_node.get_meta("roblox_class", "")) == "Model":
		models.append(selected_node as Node3D)
	for block in _get_valid_selected_blocks():
		var parent := block.get_parent()
		if parent is Node3D and str(parent.get_meta("roblox_class", "")) == "Model" and not models.has(parent):
			models.append(parent as Node3D)
	if models.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Select a Model to ungroup"
		return
	var moved_parts: Array[Node3D] = []
	var ungrouped := 0
	for model in models:
		if model == null or not is_instance_valid(model) or model.get_parent() == null:
			continue
		var destination := model.get_parent()
		for child in model.get_children().duplicate():
			child.reparent(destination, true)
			if child is Node3D and child.is_in_group("studio_parts"):
				moved_parts.append(child as Node3D)
		model.queue_free()
		ungrouped += 1
	explorer_selected_node = null
	if not moved_parts.is_empty():
		_set_selection(moved_parts)
	else:
		_clear_selection()
	call_deferred("_refresh_explorer")
	_commit_editor_history("Ungroup")
	if toolbar_status_label:
		toolbar_status_label.text = "Ungrouped %d model(s)" % ungrouped


func _get_property_action_parts() -> Array[Node3D]:
	var parts := _get_valid_selected_blocks()
	if not parts.is_empty():
		return parts
	var selected_node: Node = explorer_selected_node if explorer_selected_node != null and is_instance_valid(explorer_selected_node) else null
	if selected_node is Node3D and selected_node.is_in_group("studio_parts"):
		parts.append(selected_node as Node3D)
	elif selected_node != null:
		_collect_editor_parts_recursive(selected_node, parts)
	return parts


func _set_selected_locked(locked: bool) -> void:
	var blocks := _get_property_action_parts()
	if blocks.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Select one or more parts"
		return
	for block in blocks:
		block.set_meta("locked", locked)
	_update_inspector()
	_update_transform_gizmo()
	_commit_editor_history("Lock Selection" if locked else "Unlock Selection")
	if toolbar_status_label:
		toolbar_status_label.text = "%s %d part(s)" % ["Locked" if locked else "Unlocked", blocks.size()]


func _set_selected_anchored(anchored: bool) -> void:
	var blocks := _get_property_action_parts()
	if blocks.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "Select one or more parts"
		return
	for block in blocks:
		block.set_meta("anchored", anchored)
	_update_inspector()
	_commit_editor_history("Anchor Selection" if anchored else "Unanchor Selection")
	if toolbar_status_label:
		toolbar_status_label.text = "%s %d part(s)" % ["Anchored" if anchored else "Unanchored", blocks.size()]

func _toggle_selected_can_collide() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	for block in valid_blocks:
		var next_value := not bool(block.get_meta("can_collide", true))
		block.set_meta("can_collide", next_value)
		_update_block_collision(block)
	_update_inspector()
	_commit_editor_history("Toggle CanCollide")

func _toggle_selected_anchor() -> void:
	var valid_blocks := _get_valid_selected_blocks()
	for block in valid_blocks:
		block.set_meta("anchored", not bool(block.get_meta("anchored", true)))
	_update_inspector()
	_commit_editor_history("Toggle Anchored")


func _open_local_place_dialog() -> void:
	UserSession.ensure_current_storage()
	var maps_root := UserSession.get_maps_root_path()
	_ensure_directory_path(maps_root)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Open Place"
	dialog.ok_button_text = "Open"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 390)
	root.add_theme_constant_override("separation", 8)
	dialog.add_child(root)
	var summary := Label.new()
	summary.text = "Local places"
	summary.add_theme_color_override("font_color", Color("#4A4D52"))
	root.add_child(summary)
	var list := ItemList.new()
	list.name = "PlaceList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	list.add_theme_stylebox_override("panel", _studio_panel_style(Color.WHITE, Color("#D0D2D5"), 1, 2))
	root.add_child(list)
	var directory := DirAccess.open(maps_root)
	var entries: Array[Dictionary] = []
	if directory != null:
		directory.list_dir_begin()
		var entry_name := directory.get_next()
		while not entry_name.is_empty():
			if directory.current_is_dir() and not entry_name.begins_with("."):
				var folder := maps_root.path_join(entry_name)
				if FileAccess.file_exists(folder.path_join("map_data.json")):
					var meta := _load_map_meta(folder)
					entries.append({
						"name": str(meta.get("name", entry_name)),
						"folder": folder,
					})
			entry_name = directory.get_next()
		directory.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	for entry in entries:
		list.add_item(str(entry.get("name", "Untitled Place")), _get_toolbar_icon("Open", Color("#4B5563")))
		list.set_item_metadata(list.item_count - 1, str(entry.get("folder", "")))
	if list.item_count == 0:
		list.add_item("No saved places")
		list.set_item_disabled(0, true)
		dialog.get_ok_button().disabled = true
	else:
		list.select(0)
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var folder := str(list.get_item_metadata(selected[0]))
		_open_local_place_folder(folder)
		dialog.queue_free()
	)
	list.item_activated.connect(func(index: int) -> void:
		if index < 0 or index >= list.item_count or list.is_item_disabled(index):
			return
		var folder := str(list.get_item_metadata(index))
		_open_local_place_folder(folder)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2i(600, 450))


func _open_local_place_folder(folder: String) -> void:
	if folder.is_empty() or not FileAccess.file_exists(folder.path_join("map_data.json")):
		if toolbar_status_label:
			toolbar_status_label.text = "Place could not be opened"
		return
	current_map_folder = folder
	var meta := _load_map_meta(folder)
	current_map_name = _normalize_map_name(str(meta.get("name", folder.get_file())))
	custom_icon_set = FileAccess.file_exists(folder.path_join("icon.png"))
	GameState.selected_map_folder = folder
	GameState.selected_map = current_map_name
	_refresh_studio_title_text()
	if toolbar_status_label:
		toolbar_status_label.text = "Opening %s..." % current_map_name
	await _load_map_from_folder(folder)
	_commit_editor_history("Open Place")
	if toolbar_status_label:
		toolbar_status_label.text = "Opened %s" % current_map_name


func _open_save_place_as_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save Place As"
	dialog.ok_button_text = "Save"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(420, 90)
	root.add_theme_constant_override("separation", 6)
	dialog.add_child(root)
	var label := Label.new()
	label.text = "Place name"
	root.add_child(label)
	var name_field := LineEdit.new()
	name_field.text = current_map_name
	name_field.placeholder_text = "Untitled Place"
	name_field.select_all_on_focus = true
	root.add_child(name_field)
	dialog.confirmed.connect(func() -> void:
		current_map_name = _normalize_map_name(name_field.text)
		var folder_name := _get_unique_map_folder_name(_sanitize_map_folder_name(current_map_name))
		current_map_folder = UserSession.get_maps_root_path().path_join(folder_name)
		GameState.selected_map_folder = current_map_folder
		GameState.selected_map = current_map_name
		custom_icon_set = false
		await _save_map(current_map_folder)
		_refresh_studio_title_text()
		if toolbar_status_label:
			toolbar_status_label.text = "Saved as %s" % current_map_name
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2i(470, 180))
	name_field.grab_focus()


func _open_maps_folder() -> void:
	UserSession.ensure_current_storage()
	var maps_root := UserSession.get_maps_root_path()
	_ensure_directory_path(maps_root)
	OS.shell_open(maps_root)
	if toolbar_status_label:
		toolbar_status_label.text = "Opened local maps folder"

func _on_studio_file_menu_id_pressed(id: int) -> void:
	match id:
		1:
			_clear_map_for_rbxl_import()
			show_grid_enabled = true
			_toggle_grid_visibility(true)
			current_map_name = "Untitled Place"
			current_map_folder = ""
			custom_icon_set = false
			_refresh_studio_title_text()
			_create_default_baseplate()
			_refresh_explorer()
			_commit_editor_history("New Place")
			if toolbar_status_label:
				toolbar_status_label.text = "New place"
		2:
			_on_import_rbxl_pressed()
		3:
			_on_save_button_pressed()
		4:
			_on_publish_pressed()
		5:
			_on_back_pressed()

func _create_ribbon_group(title: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.custom_minimum_size = Vector2(0, 60)
	group.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 2)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(row)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#777777"))
	group.add_child(label)
	return group

func _add_to_ribbon_group(group: VBoxContainer, control: Control) -> void:
	var row := group.get_node_or_null("Buttons") as HBoxContainer
	if row:
		row.add_child(control)
	else:
		group.add_child(control)

func _create_ribbon_button(text: String, width: float, accent_color := Color(0.29, 0.29, 0.29)) -> Button:
	var button := Button.new()
	button.text = ""
	button.tooltip_text = text
	button.custom_minimum_size = Vector2(width, 50)
	button.set_meta("accent_color", accent_color)
	button.set_meta("ribbon_label", text)
	button.add_theme_font_size_override("font_size", 11)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_ribbon_button_base(button)

	var content := VBoxContainer.new()
	content.name = "RibbonButtonContent"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 2
	content.offset_top = 2
	content.offset_right = -2
	content.offset_bottom = -2
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	button.add_child(content)

	var icon := TextureRect.new()
	icon.name = "RibbonIcon"
	icon.texture = _get_toolbar_icon(text, _get_ribbon_icon_color(text, false))
	icon.self_modulate = _get_ribbon_icon_color(text, false)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)

	var label := Label.new()
	label.name = "RibbonLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#333333"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	return button

func _style_ribbon_button_base(button: Button) -> void:
	var normal := _studio_panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	var hover := _studio_panel_style(Color("#E7F2FC"), Color("#A8CDEA"), 1, 3)
	hover.content_margin_left = 0
	hover.content_margin_right = 0
	hover.content_margin_top = 0
	hover.content_margin_bottom = 0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _set_ribbon_button_content_visual(button: Button, icon_color: Color, text_color: Color) -> void:
	var icon := button.get_node_or_null("RibbonButtonContent/RibbonIcon") as TextureRect
	var label := button.get_node_or_null("RibbonButtonContent/RibbonLabel") as Label
	var label_text := _get_ribbon_button_label(button)
	if icon != null:
		icon.texture = _get_toolbar_icon(label_text, icon_color)
		icon.self_modulate = icon_color
	if label != null:
		label.add_theme_color_override("font_color", text_color)

func _get_ribbon_button_label(button: Button) -> String:
	return str(button.get_meta("ribbon_label", button.text))

func _get_ribbon_icon_color(label: String, active: bool) -> Color:
	if active:
		return Color("#0066CC")
	match label:
		"Move", "Scale", "Rotate", "Transform":
			return Color("#1E6FE8")
		"Geometric", "Part":
			return Color("#7B55D9")
		"Terrain":
			return Color("#2A9D55")
		"Character":
			return Color("#0E9F9A")
		"GUI":
			return Color("#C04C8A")
		"Script":
			return Color("#4D8B1F")
		"Import":
			return Color("#2B7FD6")
		"Material":
			return Color("#6C7780")
		"Group":
			return Color("#444444")
		"Lock", "Anchor":
			return Color("#333333")
		"Explorer":
			return Color("#2E74B5")
		"Properties":
			return Color("#6B5AAE")
		"Toolbox":
			return Color("#9B6A21")
		"Assets":
			return Color("#327C55")
		_:
			return Color("#333333")

func _get_toolbar_icon(name: String, color: Color) -> Texture2D:
	var icon_file := str(STUDIO_ICON_FILES.get(name, ""))
	if not icon_file.is_empty():
		var resource_path := "%s/%s" % [STUDIO_ICON_ROOT, icon_file]
		var resource_key := "svg:%s" % resource_path
		if studio_toolbar_icon_cache.has(resource_key):
			return studio_toolbar_icon_cache[resource_key]
		var svg_texture := load(resource_path) as Texture2D
		if svg_texture != null:
			studio_toolbar_icon_cache[resource_key] = svg_texture
			return svg_texture
	var key := "%s:%s" % [name, color.to_html()]
	if studio_toolbar_icon_cache.has(key):
		return studio_toolbar_icon_cache[key]
	var image := Image.create_empty(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var dark := color
	var light := color.lightened(0.35)
	match name:
		"Select":
			_draw_icon_line(image, Vector2i(5, 4), Vector2i(17, 13), dark)
			_draw_icon_line(image, Vector2i(5, 4), Vector2i(8, 18), dark)
			_draw_icon_line(image, Vector2i(8, 18), Vector2i(11, 13), dark)
		"Move":
			_draw_icon_arrow(image, Vector2i(12, 20), Vector2i(12, 4), dark)
			_draw_icon_arrow(image, Vector2i(4, 12), Vector2i(20, 12), dark)
		"Scale":
			_draw_icon_rect(image, Rect2i(6, 6, 11, 11), dark, false)
			_draw_icon_rect(image, Rect2i(15, 3, 5, 5), dark, true)
			_draw_icon_line(image, Vector2i(12, 12), Vector2i(17, 5), dark)
		"Rotate":
			_draw_icon_circle(image, Vector2i(12, 12), 7, dark)
			_draw_icon_arrow(image, Vector2i(16, 5), Vector2i(20, 8), dark)
		"Transform":
			_draw_icon_arrow(image, Vector2i(12, 19), Vector2i(12, 5), dark)
			_draw_icon_rect(image, Rect2i(4, 14, 6, 6), dark, false)
			_draw_icon_circle(image, Vector2i(18, 17), 3, dark)
		"Geometric":
			_draw_icon_rect(image, Rect2i(5, 6, 6, 6), dark, false)
			_draw_icon_rect(image, Rect2i(13, 6, 6, 6), light, true)
			_draw_icon_rect(image, Rect2i(9, 14, 6, 6), dark, false)
		"Part":
			_draw_icon_rect(image, Rect2i(6, 6, 12, 12), dark, true)
			_draw_icon_rect(image, Rect2i(6, 6, 12, 12), Color("#111111"), false)
		"Terrain":
			_draw_icon_line(image, Vector2i(4, 16), Vector2i(9, 10), dark)
			_draw_icon_line(image, Vector2i(9, 10), Vector2i(14, 15), dark)
			_draw_icon_line(image, Vector2i(14, 15), Vector2i(20, 8), dark)
		"Character":
			_draw_icon_circle(image, Vector2i(12, 6), 3, dark)
			_draw_icon_line(image, Vector2i(12, 9), Vector2i(12, 17), dark)
			_draw_icon_line(image, Vector2i(7, 12), Vector2i(17, 12), dark)
			_draw_icon_line(image, Vector2i(12, 17), Vector2i(8, 21), dark)
			_draw_icon_line(image, Vector2i(12, 17), Vector2i(16, 21), dark)
		"GUI":
			_draw_icon_rect(image, Rect2i(4, 5, 16, 12), dark, false)
			_draw_icon_rect(image, Rect2i(7, 8, 10, 2), dark, true)
			_draw_icon_rect(image, Rect2i(7, 12, 6, 2), dark, true)
		"Script":
			_draw_icon_rect(image, Rect2i(6, 4, 12, 16), dark, false)
			_draw_icon_line(image, Vector2i(8, 9), Vector2i(16, 9), dark)
			_draw_icon_line(image, Vector2i(8, 13), Vector2i(15, 13), dark)
			_draw_icon_line(image, Vector2i(8, 17), Vector2i(13, 17), dark)
		"Import":
			_draw_icon_arrow(image, Vector2i(12, 4), Vector2i(12, 15), dark)
			_draw_icon_rect(image, Rect2i(5, 16, 14, 4), dark, false)
		"Material":
			_draw_icon_circle(image, Vector2i(11, 12), 7, dark)
			_draw_icon_circle(image, Vector2i(15, 9), 3, light)
		"Group":
			_draw_icon_rect(image, Rect2i(4, 5, 7, 7), dark, false)
			_draw_icon_rect(image, Rect2i(13, 12, 7, 7), dark, false)
			_draw_icon_rect(image, Rect2i(8, 8, 8, 8), light, false)
		"Lock":
			_draw_icon_rect(image, Rect2i(7, 11, 10, 8), dark, true)
			_draw_icon_rect(image, Rect2i(7, 11, 10, 8), Color("#111111"), false)
			_draw_icon_circle(image, Vector2i(12, 11), 5, dark)
		"Anchor":
			_draw_icon_line(image, Vector2i(12, 4), Vector2i(12, 18), dark)
			_draw_icon_line(image, Vector2i(7, 12), Vector2i(17, 12), dark)
			_draw_icon_line(image, Vector2i(8, 19), Vector2i(16, 19), dark)
		"Explorer":
			_draw_icon_rect(image, Rect2i(5, 5, 14, 14), dark, false)
			_draw_icon_line(image, Vector2i(8, 9), Vector2i(16, 9), dark)
			_draw_icon_line(image, Vector2i(8, 13), Vector2i(16, 13), dark)
		"Properties":
			_draw_icon_rect(image, Rect2i(5, 4, 14, 16), dark, false)
			_draw_icon_rect(image, Rect2i(8, 8, 8, 2), dark, true)
			_draw_icon_rect(image, Rect2i(8, 13, 5, 2), dark, true)
		"Toolbox":
			_draw_icon_rect(image, Rect2i(5, 8, 14, 10), dark, false)
			_draw_icon_rect(image, Rect2i(9, 5, 6, 4), dark, false)
		"Assets":
			_draw_icon_rect(image, Rect2i(4, 7, 16, 12), dark, false)
			_draw_icon_line(image, Vector2i(5, 15), Vector2i(10, 10), dark)
			_draw_icon_line(image, Vector2i(10, 10), Vector2i(14, 14), dark)
		"Play":
			_draw_icon_triangle(image, Vector2i(8, 5), Vector2i(8, 19), Vector2i(18, 12), dark)
		"Pause":
			_draw_icon_rect(image, Rect2i(7, 5, 4, 14), dark, true)
			_draw_icon_rect(image, Rect2i(14, 5, 4, 14), dark, true)
		"Stop":
			_draw_icon_rect(image, Rect2i(7, 7, 10, 10), dark, true)
		"Record":
			_draw_icon_circle(image, Vector2i(12, 12), 6, dark)
		_:
			_draw_icon_rect(image, Rect2i(6, 6, 12, 12), dark, false)
	var tex := ImageTexture.create_from_image(image)
	studio_toolbar_icon_cache[key] = tex
	return tex

func _style_white_button(btn: Button, border_color := Color(0.8, 0.8, 0.8)) -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color("#FDFDFD")
	style_normal.border_color = border_color if border_color != Color(0.8, 0.8, 0.8) else Color("#CCCCCC")
	style_normal.set_border_width_all(1)
	style_normal.corner_radius_top_left = 2
	style_normal.corner_radius_top_right = 2
	style_normal.corner_radius_bottom_left = 2
	style_normal.corner_radius_bottom_right = 2
	style_normal.content_margin_left = 7
	style_normal.content_margin_right = 7
	style_normal.content_margin_top = 4
	style_normal.content_margin_bottom = 4
	
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color("#EAF3FF")
	style_hover.border_color = Color("#0066CC")
	style_hover.set_border_width_all(1)
	style_hover.corner_radius_top_left = 2
	style_hover.corner_radius_top_right = 2
	style_hover.corner_radius_bottom_left = 2
	style_hover.corner_radius_bottom_right = 2
	style_hover.content_margin_left = 7
	style_hover.content_margin_right = 7
	style_hover.content_margin_top = 4
	style_hover.content_margin_bottom = 4
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_color_override("font_color", Color("#222222"))
	btn.add_theme_color_override("font_hover_color", Color("#0066CC"))
	btn.add_theme_color_override("font_pressed_color", Color("#0055AA"))

func _draw_icon_point(image: Image, point: Vector2i, color: Color) -> void:
	if point.x >= 0 and point.x < image.get_width() and point.y >= 0 and point.y < image.get_height():
		image.set_pixelv(point, color)

func _draw_icon_line(image: Image, from_point: Vector2i, to_point: Vector2i, color: Color) -> void:
	var x0 := from_point.x
	var y0 := from_point.y
	var x1 := to_point.x
	var y1 := to_point.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_draw_icon_point(image, Vector2i(x0, y0), color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func _draw_icon_rect(image: Image, rect: Rect2i, color: Color, filled: bool) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var is_border := x == rect.position.x or y == rect.position.y or x == rect.position.x + rect.size.x - 1 or y == rect.position.y + rect.size.y - 1
			if filled or is_border:
				_draw_icon_point(image, Vector2i(x, y), color)

func _draw_icon_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var r2 := radius * radius
	var inner := maxi(0, radius - 1)
	var inner2 := inner * inner
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var d2 := (x - center.x) * (x - center.x) + (y - center.y) * (y - center.y)
			if d2 <= r2 and d2 >= inner2:
				_draw_icon_point(image, Vector2i(x, y), color)

func _draw_icon_triangle(image: Image, a: Vector2i, b: Vector2i, c: Vector2i, color: Color) -> void:
	var min_x = mini(a.x, mini(b.x, c.x))
	var max_x = maxi(a.x, maxi(b.x, c.x))
	var min_y = mini(a.y, mini(b.y, c.y))
	var max_y = maxi(a.y, maxi(b.y, c.y))
	var area := _edge_function(a, b, c)
	if area == 0:
		return
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2i(x, y)
			var w0 := _edge_function(b, c, p)
			var w1 := _edge_function(c, a, p)
			var w2 := _edge_function(a, b, p)
			if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
				_draw_icon_point(image, p, color)

func _edge_function(a: Vector2i, b: Vector2i, c: Vector2i) -> int:
	return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)

func _draw_icon_arrow(image: Image, from_point: Vector2i, to_point: Vector2i, color: Color) -> void:
	_draw_icon_line(image, from_point, to_point, color)
	var dir := Vector2(float(to_point.x - from_point.x), float(to_point.y - from_point.y)).normalized()
	var side := Vector2(-dir.y, dir.x)
	var p1 := Vector2(to_point) - dir * 5.0 + side * 3.0
	var p2 := Vector2(to_point) - dir * 5.0 - side * 3.0
	_draw_icon_line(image, to_point, Vector2i(roundi(p1.x), roundi(p1.y)), color)
	_draw_icon_line(image, to_point, Vector2i(roundi(p2.x), roundi(p2.y)), color)

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
	if studio_operation_busy:
		_is_studio_editing_locked(true)
		return
	_setup_rbxl_import_dialog()
	if rbxl_file_dialog:
		rbxl_file_dialog.popup_centered(Vector2(760, 460))

func _on_rbxl_file_selected(path: String) -> void:
	var clean_path := path.strip_edges()
	if clean_path.is_empty():
		return
	if not _begin_studio_operation("RBXL import"):
		return
	if toolbar_status_label:
		toolbar_status_label.text = "Importing RBXL..."
	var remote_place: Dictionary = {}
	if OS.has_feature("mobile"):
		toolbar_status_label.text = "Преобразование карты на сервере..."
		var converted: Dictionary = await CloudAPI.convert_roblox_place(clean_path)
		if not bool(converted.get("ok", false)):
			toolbar_status_label.text = str(converted.get("error", "Ошибка серверного импорта"))
			_end_studio_operation()
			return
		var payload: Dictionary = converted.get("data", {}) if converted.get("data") is Dictionary else {}
		remote_place = payload.get("place", {}) if payload.get("place") is Dictionary else {}
		if not remote_place.get("instances") is Dictionary:
			toolbar_status_label.text = "Сервер не вернул структуру карты. Текущая карта сохранена."
			_end_studio_operation()
			return
	elif _should_prefetch_rbxl_assets_remotely():
		await _prefetch_rbxl_assets_from_server(clean_path)
	_clear_map_for_rbxl_import()
	show_grid_enabled = false
	_toggle_grid_visibility(false)
	await get_tree().process_frame
	var importer := RbxlRuntimeImporter.new()
	importer.scale_factor = 0.5
	importer.import_lighting = true
	importer.replace_existing = false
	importer.parts_per_frame = 96
	importer.meta_per_frame = 192
	importer.defer_studio_explorer_refresh = true
	importer.import_progress.connect(func(done: int, total: int, message: String) -> void:
		if toolbar_status_label:
			toolbar_status_label.text = "Importing %s (%d/%d)" % [message, done, maxi(total, 1)]
	)
	var report: Dictionary = await importer.import_json_async(remote_place, placement_parent, self) if not remote_place.is_empty() else await importer.import_file_async(clean_path, self)
	last_rbxl_import_report = report.duplicate(true)
	show_grid_enabled = false
	_toggle_grid_visibility(false)
	if bool(report.get("ok", false)):
		custom_icon_set = false
		current_roblox_environment_settings = _collect_roblox_environment_settings()
		current_roblox_place_manifest = _collect_roblox_place_manifest_from_import()
		_apply_imported_roblox_environment_preview()
		await _refresh_roblox_gui_preview()
		await _install_roblox_manifest_data_model_preview()
		if toolbar_status_label:
			var warning_count: int = report.get("warnings", []).size() if report.get("warnings", []) is Array else 0
			var warning_suffix := " with %d warning(s)" % warning_count if warning_count > 0 else ""
			toolbar_status_label.text = "Imported RBXL: %d part(s), %d object(s), %d sound(s)%s" % [
				int(report.get("parts", 0)),
				int(report.get("runtime_objects", 0)),
				int(report.get("sounds", 0)),
				warning_suffix
			]
			var asset_refs := int(report.get("asset_refs", 0))
			var script_refs := int(report.get("script_refs", 0))
			var constraint_refs := int(report.get("constraint_refs", 0))
			var tool_refs := int(report.get("tool_refs", 0))
			var gui_refs := int(report.get("gui_refs", 0))
			var storage_libraries := int(report.get("storage_libraries", 0))
			if asset_refs > 0 or script_refs > 0 or constraint_refs > 0 or tool_refs > 0 or gui_refs > 0 or storage_libraries > 0:
				toolbar_status_label.text += " | Roblox: %d asset(s), %d script(s), %d constraint(s), %d tool(s), %d gui, %d storage item(s)" % [
					asset_refs, script_refs, constraint_refs, tool_refs, gui_refs, storage_libraries
				]
			var hidden_parts := int(report.get("hidden_parts", 0))
			if hidden_parts > 0:
				toolbar_status_label.text += " | Storage kept: %d hidden part(s)" % hidden_parts
	else:
		if toolbar_status_label:
			toolbar_status_label.text = "RBXL import failed: %s" % str(report.get("error", "Unknown error"))
	_end_studio_operation()

func _should_prefetch_rbxl_assets_remotely() -> bool:
	RbxlServerImporterScript.ensure_project_settings()
	if not ProjectSettings.has_setting(RBXL_REMOTE_PREFETCH_SETTING):
		ProjectSettings.set_setting(RBXL_REMOTE_PREFETCH_SETTING, true)
		ProjectSettings.set_initial_value(RBXL_REMOTE_PREFETCH_SETTING, true)
		ProjectSettings.set_as_basic(RBXL_REMOTE_PREFETCH_SETTING, true)
	return bool(ProjectSettings.get_setting(RBXL_REMOTE_PREFETCH_SETTING, true))

func _prefetch_rbxl_assets_from_server(path: String) -> void:
	var server_importer := RbxlServerImporterScript.new()
	server_importer.request_timeout_seconds = 4.0
	add_child(server_importer)
	var health: Dictionary = await server_importer.ping_server()
	if not bool(health.get("ok", false)):
		if toolbar_status_label:
			toolbar_status_label.text = "Remote asset server unavailable; using local import..."
		server_importer.queue_free()
		await get_tree().process_frame
		return
	server_importer.request_timeout_seconds = 180.0
	server_importer.import_progress.connect(func(stage: String, progress: float, message: String, done: int, total: int) -> void:
		if toolbar_status_label:
			toolbar_status_label.text = "Remote assets: %s (%d/%d)" % [message, done, maxi(total, 1)]
	)
	var result: Dictionary = await server_importer.import_rbxl(path)
	if toolbar_status_label:
		if bool(result.get("ok", false)):
			toolbar_status_label.text = "Remote assets cached; importing into studio..."
		else:
			toolbar_status_label.text = "Remote asset cache failed, using local import: %s" % str(result.get("error", "unknown"))
	server_importer.queue_free()
	await get_tree().process_frame

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
	_clear_selection()
	_clear_workspace_manifest_nodes()
	for block in _get_editor_parts():
		if is_instance_valid(block):
			var block_parent := block.get_parent()
			if block_parent != null:
				block_parent.remove_child(block)
			block.free()
	_clear_runtime_object_nodes()
	current_music_source_paths.clear()
	current_imported_sound_assets.clear()
	current_roblox_environment_settings.clear()
	current_roblox_place_manifest.clear()
	_clear_imported_roblox_script_nodes()
	if data_model != null and is_instance_valid(data_model) and data_model.has_method("clear_services"):
		data_model.clear_services()
	_clear_roblox_gui_preview()
	_refresh_music_source_ui()

func _clear_workspace_manifest_nodes() -> void:
	var parent: Node = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child.is_in_group("studio_parts"):
			continue
		if not child.has_meta("roblox_ref"):
			continue
		parent.remove_child(child)
		child.free()

func _clear_runtime_object_nodes() -> void:
	var parent: Node = placement_parent if placement_parent else self
	var runtime_nodes: Array[Node] = []
	_collect_nodes_in_group_recursive(parent, RBXL_RUNTIME_OBJECT_GROUP, runtime_nodes)
	for runtime_node in runtime_nodes:
		if is_instance_valid(runtime_node):
			runtime_node.queue_free()

func _collect_nodes_in_group_recursive(root: Node, group_name: StringName, out_nodes: Array[Node]) -> void:
	for child in root.get_children():
		if child.is_in_group(group_name):
			out_nodes.append(child)
		_collect_nodes_in_group_recursive(child, group_name, out_nodes)

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

func _build_toolbox_tab() -> void:
	var toolbox := VBoxContainer.new()
	toolbox.name = "Toolbox"
	toolbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(toolbox)
	
	var search_edit := LineEdit.new()
	search_edit.placeholder_text = "Search catalog..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbox.add_child(search_edit)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	toolbox.add_child(scroll)
	
	var items_vbox := VBoxContainer.new()
	scroll.add_child(items_vbox)
	
	# Load some drafts / catalog items
	var label := Label.new()
	label.text = "Double click / Drag model\nto insert into Workspace."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	items_vbox.add_child(label)

func _build_terrain_tab() -> void:
	var terrain := VBoxContainer.new()
	terrain.name = "Terrain"
	terrain.add_theme_constant_override("separation", 8)
	left_panel.add_child(terrain)
	
	var label := Label.new()
	label.text = "Terrain generator tools."
	label.add_theme_font_size_override("font_size", 12)
	terrain.add_child(label)

func _show_explorer_context_menu(item: TreeItem, pos: Vector2) -> void:
	if explorer_popup:
		explorer_popup.queue_free()
	explorer_popup = PopupMenu.new()
	add_child(explorer_popup)
	
	var metadata = item.get_metadata(0)
	
	if metadata is String:
		var service_name: String = metadata
		explorer_popup.add_item("Properties", 1)
		explorer_popup.add_item("Add Script", 2)
		explorer_popup.id_pressed.connect(func(id):
			match id:
				1:
					_show_service_properties(service_name)
				2:
					_add_script_to_node(null, service_name)
		)
	else:
		var instance_id: int = int(metadata)
		var node := instance_from_id(instance_id)
		if node:
			var is_service := bool(node.get_meta("is_roblox_service", false))
			explorer_popup.add_item("Properties", 1)
			if not is_service:
				explorer_popup.add_item("Rename (F2)", 10)
				explorer_popup.add_item("Delete (Del)", 11)
				explorer_popup.add_item("Duplicate (Ctrl+D)", 12)
			explorer_popup.add_separator()
			
			var add_submenu := PopupMenu.new()
			add_submenu.name = "AddChildMenu"
			var insert_classes := {
				20: "Part", 21: "WedgePart", 22: "CornerWedgePart", 23: "TrussPart",
				24: "MeshPart", 25: "SpawnLocation", 26: "Model", 27: "Folder",
				28: "Character", 29: "Humanoid", 30: "Tool", 31: "Script",
				32: "LocalScript", 33: "ModuleScript", 34: "ScreenGui",
				35: "Frame", 36: "TextLabel", 37: "TextButton",
				38: "TextBox", 39: "ImageLabel", 40: "ImageButton",
				41: "Attachment", 42: "WeldConstraint", 43: "RemoteEvent",
				44: "RemoteFunction", 45: "BindableEvent", 46: "NumberValue",
				47: "BoolValue", 48: "StringValue", 49: "Sound", 50: "PointLight",
			}
			for insert_id_variant in insert_classes.keys():
				var insert_id := int(insert_id_variant)
				add_submenu.add_item(str(insert_classes[insert_id]), insert_id)
			explorer_popup.add_child(add_submenu)
			explorer_popup.add_submenu_item("Insert Object...", "AddChildMenu")
			
			explorer_popup.id_pressed.connect(func(id):
				match id:
					1:
						_show_properties_for_node(node)
					10:
						_rename_item_dialog(node)
					11:
						_delete_node(node)
					12:
						_duplicate_node(node)
			)
			add_submenu.id_pressed.connect(func(id):
				if insert_classes.has(id):
					_insert_roblox_instance(node, str(insert_classes[id]))
			)
			
	explorer_popup.position = get_viewport().get_mouse_position()
	explorer_popup.popup()


func _explorer_get_drag_data(at_position: Vector2) -> Variant:
	var item := explorer_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var metadata = item.get_metadata(0)
	if not (metadata is int):
		return null
	var node := instance_from_id(int(metadata))
	if node == null or bool(node.get_meta("is_roblox_service", false)):
		return null
	var preview := Label.new()
	preview.text = "  %s  " % str(node.get_meta("block_name", node.name))
	preview.add_theme_color_override("font_color", Color.WHITE)
	preview.add_theme_stylebox_override("normal", _studio_panel_style(Color("#2D78D2"), Color("#1F5FA9"), 1, 3))
	explorer_tree.set_drag_preview(preview)
	return {"kind": "roblox_explorer_node", "node_id": node.get_instance_id()}


func _explorer_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or str((data as Dictionary).get("kind", "")) != "roblox_explorer_node":
		return false
	var item := explorer_tree.get_item_at_position(at_position)
	if item == null:
		return false
	var target_metadata = item.get_metadata(0)
	if not (target_metadata is int):
		return false
	var source := instance_from_id(int((data as Dictionary).get("node_id", -1)))
	var target := instance_from_id(int(target_metadata))
	if source == null or target == null or source == target or source.is_ancestor_of(target):
		return false
	if source is Control and not (target is Control) and not (target is CanvasLayer):
		return false
	return not bool(source.get_meta("is_roblox_service", false))


func _explorer_drop_data(at_position: Vector2, data: Variant) -> void:
	if not _explorer_can_drop_data(at_position, data):
		return
	var item := explorer_tree.get_item_at_position(at_position)
	var source := instance_from_id(int((data as Dictionary).get("node_id", -1)))
	var target := instance_from_id(int(item.get_metadata(0)))
	if source == null or target == null:
		return
	source.reparent(target, true)
	item.collapsed = false
	explorer_selected_node = source
	_refresh_explorer()
	_show_properties_for_node(source)
	_commit_editor_history("Reparent %s" % source.name)

func _on_explorer_item_mouse_selected(pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		var item := explorer_tree.get_item_at_position(pos)
		if item:
			explorer_tree.set_selected(item, 0)
			_show_explorer_context_menu(item, pos)

func _on_explorer_item_double_clicked() -> void:
	var selected := explorer_tree.get_selected()
	if selected == null:
		return
	var metadata = selected.get_metadata(0)
	if metadata is int:
		var node := instance_from_id(metadata)
		if node and node.is_in_group("bobux_scripts"):
			_open_script_in_editor(node)
		elif node and not bool(node.get_meta("is_roblox_service", false)):
			_rename_item_dialog(node)


func _open_insert_object_dialog() -> void:
	if data_model == null or _is_studio_editing_locked():
		return
	var target_parent := _get_selected_editor_node()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Insert Object"
	dialog.ok_button_text = "Insert"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(470, 430)
	root.add_theme_constant_override("separation", 6)
	dialog.add_child(root)
	var parent_label := Label.new()
	parent_label.text = "Parent: %s" % str(target_parent.get_meta("block_name", target_parent.name) if target_parent != null else "Workspace")
	parent_label.add_theme_color_override("font_color", Color("#55585C"))
	root.add_child(parent_label)
	var search := LineEdit.new()
	search.placeholder_text = "Search objects"
	search.add_theme_stylebox_override("normal", _studio_line_edit_style())
	root.add_child(search)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	list.add_theme_stylebox_override("panel", _studio_panel_style(Color.WHITE, Color("#D0D2D5"), 1, 2))
	root.add_child(list)
	var classes: Array[String] = [
		"Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "Seat", "VehicleSeat", "SpawnLocation",
		"Model", "Folder", "Character", "Humanoid", "Animator", "BodyColors",
		"Tool", "Script", "LocalScript", "ModuleScript",
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", "TextButton",
		"TextBox", "ImageLabel", "ImageButton", "UIListLayout", "UIGridLayout", "UICorner",
		"UIStroke", "UIAspectRatioConstraint", "Attachment", "WeldConstraint", "Motor6D",
		"RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction",
		"NumberValue", "IntValue", "BoolValue", "StringValue", "ObjectValue", "Vector3Value",
		"CFrameValue", "Color3Value", "Sound", "PointLight", "SpotLight", "ParticleEmitter"
	]
	var populate := func(query: String) -> void:
		list.clear()
		var normalized := query.strip_edges().to_lower()
		for object_type in classes:
			if not normalized.is_empty() and object_type.to_lower().find(normalized) < 0:
				continue
			list.add_item(object_type, _get_toolbar_icon(_studio_icon_name_for_class(object_type), Color("#39424E")))
			list.set_item_metadata(list.item_count - 1, object_type)
		if list.item_count > 0:
			list.select(0)
		dialog.get_ok_button().disabled = list.item_count == 0
	populate.call("")
	search.text_changed.connect(func(query: String) -> void: populate.call(query))
	var insert_selected := func(index: int) -> void:
		if index < 0 or index >= list.item_count:
			return
		var object_type := str(list.get_item_metadata(index))
		if object_type.is_empty():
			return
		_insert_roblox_instance(target_parent, object_type)
		dialog.queue_free()
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if not selected.is_empty():
			insert_selected.call(selected[0])
	)
	list.item_activated.connect(func(index: int) -> void: insert_selected.call(index))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2i(520, 500))
	search.grab_focus()


func _studio_icon_name_for_class(object_type: String) -> String:
	if object_type in ["Script", "LocalScript", "ModuleScript"]:
		return "Script"
	if object_type in ["ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton"]:
		return "GUI"
	if object_type in ["Character", "Humanoid", "Animator", "BodyColors"]:
		return "Character"
	if object_type in ["Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "SpawnLocation"]:
		return "Part"
	if object_type in ["Sound"]:
		return "Assets"
	return "Add"


func _insert_roblox_instance(selected_parent: Node, roblox_class: String) -> void:
	if _is_studio_editing_locked() or data_model == null:
		return
	if roblox_class in ["Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "Seat", "VehicleSeat"]:
		_add_shape_to_node(_resolve_insert_parent(selected_parent, roblox_class), roblox_class)
		return
	if roblox_class == "Character":
		_add_character_to_node(_resolve_insert_parent(selected_parent, "Model"))
		return
	if roblox_class == "Tool":
		_add_tool_to_node(_resolve_insert_parent(selected_parent, roblox_class))
		return
	if roblox_class == "SpawnLocation":
		_add_spawn_to_node(_resolve_insert_parent(selected_parent, roblox_class))
		return
	if roblox_class == "PointLight":
		_add_light_to_node(_resolve_insert_parent(selected_parent, roblox_class))
		return
	if roblox_class == "Sound":
		_add_sound_to_node(_resolve_insert_parent(selected_parent, roblox_class))
		return
	var parent_node := _resolve_insert_parent(selected_parent, roblox_class)
	if parent_node == null:
		return
	var instance := RobloxDataModelClass.create_instance(roblox_class, roblox_class)
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		instance.set_meta("code", "-- %s\nprint('%s started')\n" % [roblox_class, roblox_class])
		instance.set_meta("lua_source", instance.get_meta("code"))
		instance.set_meta("disabled", false)
	if instance is Label:
		(instance as Label).text = "TextLabel"
	elif instance is Button:
		(instance as Button).text = "TextButton"
	parent_node.add_child(instance, true)
	_refresh_explorer()
	explorer_selected_node = instance
	_show_properties_for_node(instance)
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		_open_script_in_editor(instance)
	if RobloxDataModelClass.default_service_for_class(roblox_class) == "StarterGui" or instance is Control:
		_on_data_model_gui_changed()
	_commit_editor_history("Insert %s" % roblox_class)


func _resolve_insert_parent(selected_parent: Node, roblox_class: String) -> Node:
	var default_service := RobloxDataModelClass.default_service_for_class(roblox_class)
	if roblox_class in ["Tool", "HopperBin"]:
		var selected_class := str(selected_parent.get_meta("roblox_class", "")) if selected_parent != null else ""
		if selected_class in ["StarterPack", "Backpack"]:
			return selected_parent
		return data_model.ensure_service("StarterPack")
	if roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui"]:
		return data_model.ensure_service("StarterGui")
	if default_service == "StarterGui":
		if selected_parent is Control or selected_parent is CanvasLayer:
			return selected_parent
		return data_model.ensure_service("StarterGui")
	if roblox_class in ["Part", "Model", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "Seat", "VehicleSeat", "SpawnLocation"]:
		if selected_parent is Node3D:
			return selected_parent
		return placement_parent
	if selected_parent != null and not bool(selected_parent.get_meta("is_roblox_service", false)):
		return selected_parent
	if selected_parent != null and str(selected_parent.get_meta("roblox_class", "")) == default_service:
		return selected_parent
	return data_model.ensure_service(default_service)

func _rename_item_dialog(node: Node) -> void:
	if _is_studio_editing_locked() or bool(node.get_meta("is_roblox_service", false)):
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Rename"
	var edit := LineEdit.new()
	edit.text = node.get_meta("block_name", node.name)
	dialog.add_child(edit)
	dialog.confirmed.connect(func():
		var new_name := edit.text.strip_edges()
		if not new_name.is_empty():
			node.set_meta("block_name", new_name)
			node.name = new_name
			_refresh_explorer()
			_commit_editor_history("Rename node")
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 120))

func _delete_node(node: Node) -> void:
	if _is_studio_editing_locked() or bool(node.get_meta("is_roblox_service", false)):
		return
	node.queue_free()
	call_deferred("_refresh_explorer")
	_commit_editor_history("Delete node")

func _duplicate_node(node: Node) -> void:
	if _is_studio_editing_locked() or bool(node.get_meta("is_roblox_service", false)):
		return
	var dupe = node.duplicate()
	node.get_parent().add_child(dupe)
	var new_name = _make_unique_block_copy_name(node.get_meta("block_name", node.name))
	dupe.set_meta("block_name", new_name)
	dupe.name = new_name
	call_deferred("_refresh_explorer")
	_commit_editor_history("Duplicate node")

func _add_part(parent_node: Node) -> void:
	_add_shape_to_node(parent_node, "Part")


func _add_shape_to_node(parent_node: Node, roblox_class: String) -> void:
	if _is_studio_editing_locked():
		return
	var shape_name := {
		"WedgePart": "Wedge", "CornerWedgePart": "CornerWedge",
		"TrussPart": "Truss", "MeshPart": "Box", "Seat": "Box", "VehicleSeat": "Box",
	}.get(roblox_class, "Box") as String
	var part := _build_block_instance(shape_name, Color("#A3A2A5"), "Plastic", 0.0, true, "%s_%04d" % [roblox_class, randi() % 10000])
	part.set_meta("roblox_class", roblox_class)
	if roblox_class == "TrussPart":
		part.add_to_group("roblox_climbable")
		part.set_meta("climbable", true)
	elif roblox_class in ["Seat", "VehicleSeat"]:
		part.add_to_group("roblox_seat")
	var target_parent: Node = _resolve_studio_3d_parent(parent_node)
	target_parent.add_child(part)
	if target_parent is Node3D:
		part.global_position = _get_editor_drop_position(10.0)
	_set_selection([part])
	_refresh_explorer()
	_commit_editor_history("Add %s" % roblox_class)

func _add_model_container(parent_node: Node) -> void:
	if _is_studio_editing_locked():
		return
	var model := Node3D.new()
	model.name = "Model_%04d" % (randi() % 10000)
	model.set_meta("roblox_class", "Model")
	_resolve_studio_3d_parent(parent_node).add_child(model)
	model.global_position = _get_editor_drop_position(10.0)
	_refresh_explorer()
	_commit_editor_history("Add Model")


func _add_character_to_node(parent_node: Node) -> void:
	if _is_studio_editing_locked():
		return
	var target_parent := _resolve_studio_3d_parent(parent_node)
	if not (target_parent is Node3D):
		return
	var character: Node3D = RobloxCharacterFactoryClass.create_r6(
		self,
		target_parent as Node3D,
		_get_editor_drop_position(8.0),
		"R6Character"
	)
	if character == null:
		return
	explorer_selected_node = character
	_refresh_explorer()
	_show_properties_for_node(character)
	_commit_editor_history("Add R6 Character")


func _add_tool_to_node(parent_node: Node) -> void:
	if _is_studio_editing_locked() or data_model == null:
		return
	var tool := _create_authored_tool(parent_node, {})
	if tool == null:
		return

	explorer_selected_node = tool
	_refresh_explorer()
	_show_properties_for_node(tool)
	_commit_editor_history("Add Tool")

func _add_light_to_node(parent_node: Node) -> void:
	if _is_studio_editing_locked():
		return
	var light := OmniLight3D.new()
	light.name = "PointLight_%04d" % (randi() % 10000)
	light.set_meta("roblox_class", "PointLight")
	light.light_energy = 1.2
	light.omni_range = 18.0
	_resolve_studio_3d_parent(parent_node).add_child(light)
	light.global_position = _get_editor_drop_position(10.0)
	_refresh_explorer()
	_commit_editor_history("Add Light")

func _add_sound_to_node(parent_node: Node) -> void:
	if _is_studio_editing_locked():
		return
	var sound := AudioStreamPlayer3D.new()
	sound.name = "Sound_%04d" % (randi() % 10000)
	sound.set_meta("roblox_class", "Sound")
	_resolve_studio_3d_parent(parent_node).add_child(sound)
	sound.global_position = _get_editor_drop_position(10.0)
	_refresh_explorer()
	_commit_editor_history("Add Sound")

func _add_spawn_to_node(parent_node: Node) -> void:
	if _is_studio_editing_locked():
		return
	var previous_shape := current_shape
	current_shape = "Spawn"
	var part := _build_block_instance("Spawn", Color("#60D860"), "Plastic", 0.0, true, "SpawnLocation_%04d" % (randi() % 10000))
	_resolve_studio_3d_parent(parent_node).add_child(part)
	part.global_position = _get_editor_drop_position(10.0)
	_set_selection([part])
	current_shape = previous_shape
	_refresh_explorer()
	_commit_editor_history("Add SpawnLocation")

func _resolve_studio_3d_parent(parent_node: Node) -> Node:
	if parent_node is Node3D:
		return parent_node
	if placement_parent != null:
		return placement_parent
	return self

func _add_script_to_node(parent_node: Node, service_name: String = "", requested_class: String = "") -> void:
	if _is_studio_editing_locked():
		return
	var script_parent: Node = parent_node
	if service_name != "":
		if data_model != null:
			script_parent = data_model.ensure_service(service_name)
		if script_parent == null:
			script_parent = Node.new()
			script_parent.name = service_name
			add_child(script_parent)
			
	if script_parent == null:
		script_parent = placement_parent

	var script_class := requested_class.strip_edges()
	if script_class.is_empty():
		var parent_class := str(script_parent.get_meta("roblox_class", ""))
		script_class = "LocalScript" if _is_gui_script_parent(script_parent) or parent_class in ["StarterPlayerScripts", "StarterCharacterScripts", "PlayerScripts", "StarterGui"] else "Script"
	var new_script := RobloxDataModelClass.create_instance(script_class, script_class)
	new_script.add_to_group("bobux_scripts")
	new_script.set_meta("script_type", script_class)
	new_script.set_meta("roblox_class", script_class)
	new_script.set_meta("disabled", false)
	var source := "-- Server Script\nlocal object = script.Parent\nprint('Script loaded in: ' .. object.Name)\n"
	if script_class == "LocalScript":
		source = "-- LocalScript: runs on the player's copy during Play\nlocal player = game:GetService('Players').LocalPlayer\nprint('LocalScript loaded for ' .. player.Name)\n"
	new_script.set_meta("code", source)
	new_script.set_meta("lua_source", source)
	
	script_parent.add_child(new_script, true)
	explorer_selected_node = new_script
	_refresh_explorer()
	_commit_editor_history("Add %s" % script_class)
	_open_script_in_editor(new_script)


func _studio_ai_node_reference(node: Node) -> String:
	return "node:%d" % node.get_instance_id() if _is_studio_ai_scene_node(node) else ""


func _is_studio_ai_scene_node(node: Node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion() and (
		node == placement_parent or (is_instance_valid(placement_parent) and placement_parent.is_ancestor_of(node))
		or (is_instance_valid(data_model) and data_model.is_ancestor_of(node)))


func _resolve_studio_ai_reference(reference: String, selected: Node = null, aliases: Dictionary = {}) -> Node:
	var target: Node = null
	if reference == "selected":
		target = selected
	elif reference.begins_with("node:") and reference.trim_prefix("node:").is_valid_int():
		target = instance_from_id(int(reference.trim_prefix("node:"))) as Node
	elif reference.begins_with("action:"):
		target = aliases.get(reference.trim_prefix("action:"), null) as Node
	elif reference == "Workspace":
		target = placement_parent
	elif reference in ["StarterPlayerScripts", "StarterCharacterScripts"] and data_model != null:
		target = data_model.ensure_service("StarterPlayer").get_node_or_null(NodePath(reference))
	elif reference in ["ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "ReplicatedStorage", "ReplicatedFirst", "Lighting", "SoundService"] and data_model != null:
		target = data_model.ensure_service(reference)
	return target if _is_studio_ai_scene_node(target) else null


func _apply_studio_ai_actions(actions: Array, selected_ref: String = "") -> int:
	studio_ai_last_errors.clear()
	if _is_studio_editing_locked():
		studio_ai_last_errors.append("Stop the playtest before applying AI changes.")
		return 0
	var expanded := preload("res://addons/roblox_studio/studio_ai_planner.gd").expand_actions(actions)
	if not expanded.ok:
		studio_ai_last_errors.append(expanded.error)
		return 0
	actions = expanded.actions
	# Compile all returned sources before changing the place. Invalid code must not
	# silently replace working scripts, nor leave half of a dependent build applied.
	for action_variant in actions:
		if not action_variant is Dictionary:
			continue
		var candidate: Dictionary = action_variant
		if str(candidate.get("type", "")) in ["create_script", "update_script"]:
			studio_ai_last_errors.append_array(preload("res://addons/roblox_studio/roblox_script_contract.gd").errors(str(candidate.get("source", ""))))
			var validation: Dictionary = LuaScriptEngine.validate_script_source(str(candidate.get("source", "")))
			if not bool(validation.get("ok", false)):
				studio_ai_last_errors.append("%s: %s" % [str(candidate.get("name", "Script")), str(validation.get("error", "Invalid script source"))])
	if not studio_ai_last_errors.is_empty():
		return 0
	var captured_selection := _resolve_studio_ai_reference(selected_ref) if not selected_ref.is_empty() else _get_selected_editor_node()
	var aliases := {}
	var created_count := 0
	var created_parts: Array[Node3D] = []
	var drop_origin := _get_editor_drop_position(12.0)
	for action_variant in actions:
		if not action_variant is Dictionary:
			continue
		var action: Dictionary = action_variant
		var created_node: Node = null
		match str(action.get("type", "")):
			"spawn_asset", "attach_sound":
				var library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
				var asset_id := str(action.get("asset_id", ""))
				var parent := _resolve_studio_ai_reference(str(action.get("parent", "Workspace")), captured_selection, aliases)
				if str(action.get("type")) == "attach_sound":
					created_node = library.attach_sound(asset_id, parent)
				elif parent is Node3D:
					var rotation_ := _studio_ai_vector3(action.get("rotation", [0, 0, 0]), Vector3.ZERO, -360, 360) * PI / 180
					var position_ := _studio_ai_vector3(action.get("position", [0, 0, 0]), Vector3.ZERO, -512, 512)
					var scale_ := _studio_ai_vector3(action.get("scale", [1, 1, 1]), Vector3.ONE, 0.05, 20)
					created_node = library.spawn_asset(asset_id, parent, Transform3D(Basis.from_euler(rotation_).scaled(scale_), position_))
					if created_node != null:
						if parent == placement_parent: created_node.global_position += drop_origin
						var mesh_index := 0
						for mesh in created_node.find_children("*", "MeshInstance3D", true, false):
							_cache_exact_model_mesh(mesh, asset_id, mesh_index)
							_update_block_collision(mesh)
							mesh_index += 1
						explorer_selected_node = created_node
						created_parts.append(created_node)
				if created_node == null:
					studio_ai_last_errors.append("Asset unavailable or invalid target: " + asset_id)
				else:
					created_count += 1
			"create_instance":
				var class_name_ := str(action.get("class", ""))
				if class_name_ not in ["ScreenGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "UICorner", "UIStroke", "UIPadding", "UIListLayout", "Folder", "Model", "Humanoid", "Attachment", "Explosion", "Tool", "ClickDetector", "ProximityPrompt", "IntValue", "NumberValue", "StringValue", "BoolValue", "BindableEvent", "RemoteEvent"]:
					studio_ai_last_errors.append("Unsupported instance class: " + class_name_)
					continue
				var parent := _resolve_studio_ai_reference(str(action.get("parent", "StarterGui" if class_name_ == "ScreenGui" else "Workspace")), captured_selection, aliases)
				if parent == null:
					studio_ai_last_errors.append("Instance parent could not be resolved.")
					continue
				created_node = RobloxDataModelClass.create_instance(class_name_, str(action.get("name", class_name_)))
				parent.add_child(created_node)
				created_node.set_meta("bobux_ai_generated", true)
				_apply_studio_ai_instance_properties(created_node, action.get("properties", {}))
				created_count += 1
			"update_instance":
				var target := _resolve_studio_ai_reference(str(action.get("target", "")), captured_selection, aliases)
				if target != null and _apply_studio_ai_instance_properties(target, action.get("properties", {})):
					created_count += 1
				else:
					studio_ai_last_errors.append("Instance properties could not be updated.")
			"modify_selected", "modify_object":
				var target := captured_selection if str(action.get("type", "")) == "modify_selected" else _resolve_studio_ai_reference(str(action.get("target", "")), captured_selection, aliases)
				if _apply_studio_ai_object_update(target, action):
					created_count += 1
					if target is Node3D:
						created_parts.append(target as Node3D)
				else:
					studio_ai_last_errors.append("Cannot edit target: %s" % str(action.get("target", "selected")))
			"update_script":
				var target := _resolve_studio_ai_reference(str(action.get("target", "")), captured_selection, aliases)
				if _update_studio_ai_script(target, action):
					created_count += 1
				else:
					studio_ai_last_errors.append("Script target no longer exists or is not a script.")
			"create_script":
				created_node = _create_studio_ai_script(action, captured_selection, aliases)
				if created_node != null:
					created_count += 1
			"set_environment":
				if _apply_studio_ai_environment(action):
					created_count += 1
			"set_player_settings":
				var settings := _get_current_player_settings()
				for field in [["move_speed", 1, 200], ["jump_velocity", 1, 200], ["sprint_multiplier", 1, 10]]:
					if action.has(field[0]): settings[field[0]] = clampf(float(action[field[0]]), field[1], field[2])
				_apply_player_settings_to_ui(settings)
				created_count += 1
			"create_tool":
				var authored_tool := _create_authored_tool(null, action)
				if authored_tool != null:
					created_node = authored_tool
					created_parts.append(authored_tool)
					created_count += 1
			"insert_asset":
				var inserted_model := _create_builtin_model(str(action.get("asset", "")), action, drop_origin)
				if inserted_model != null:
					created_node = inserted_model
					for descendant in inserted_model.find_children("*", "MeshInstance3D", true, false):
						if descendant is Node3D:
							created_parts.append(descendant as Node3D)
					created_count += 1
			"create_part":
				var parent := _resolve_studio_ai_reference(str(action.get("parent", "Workspace")), captured_selection, aliases)
				var part := _create_studio_ai_part(action, parent, drop_origin, parent != placement_parent)
				if part != null:
					created_node = part
					created_parts.append(part)
					created_count += 1
			"create_model":
				var parent := _resolve_studio_ai_reference(str(action.get("parent", "Workspace")), captured_selection, aliases)
				if parent == null:
					studio_ai_last_errors.append("Model parent could not be resolved.")
					continue
				var model := Node3D.new()
				model.name = str(action.get("name", "Model")).strip_edges()
				if model.name.is_empty():
					model.name = "Model"
				model.set_meta("roblox_class", "Model")
				model.set_meta("bobux_ai_generated", true)
				parent.add_child(model)
				var offset := _studio_ai_vector3(action.get("position", [0, 0, 0]), Vector3.ZERO, -512.0, 512.0)
				if parent == placement_parent:
					model.global_position = drop_origin + offset
				else:
					model.position = offset
				model.rotation_degrees = _studio_ai_vector3(action.get("rotation", [0, 0, 0]), Vector3.ZERO, -360.0, 360.0)
				var model_created := 0
				var parts: Array = action.get("parts", []) if action.get("parts", []) is Array else []
				for part_variant in parts.slice(0, 96):
					if not part_variant is Dictionary:
						continue
					var model_part := _create_studio_ai_part(part_variant, model, Vector3.ZERO, true)
					if model_part != null:
						created_parts.append(model_part)
						model_created += 1
				created_count += model_created
				if model_created == 0:
					model.queue_free()
				else:
					created_node = model
		if created_node != null and not str(action.get("id", "")).is_empty():
			aliases[str(action["id"])] = created_node
	if created_count > 0:
		_on_data_model_gui_changed()
		if not created_parts.is_empty():
			_set_selection(created_parts)
		_refresh_explorer()
		_commit_editor_history("Bobux AI changes")
		if not created_parts.is_empty():
			call_deferred("_focus_camera_on_selection")
	return created_count


func _apply_studio_ai_instance_properties(target: Node, properties: Variant) -> bool:
	if not properties is Dictionary:
		return false
	var saved: Dictionary = target.get_meta("roblox_properties", {}).duplicate(true)
	var allowed := ["Text", "TextSize", "TextColor3", "TextTransparency", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "BorderColor3", "Position", "Size", "AnchorPoint", "Visible", "Enabled", "Active", "DisplayOrder", "ZIndex", "AutoButtonColor", "Image", "Value", "MaxActivationDistance", "RequiresHandle", "ToolTip", "ResetOnSpawn", "TextScaled", "TextWrapped"]
	allowed.append_array(["Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "AutoRotate", "BlastRadius", "BlastPressure", "DestroyJointRadiusPercent"])
	allowed.append_array(["ActionText", "ObjectText", "HoldDuration", "MaxSpeed", "Disabled"])
	var changed := false
	for key in properties:
		if str(key) == "Attributes" and properties[key] is Dictionary:
			for attribute in properties[key]:
				var value: Variant = properties[key][attribute]
				if value is String or value is bool or value is int or value is float:
					LuaScriptEngine.BobuxInstance.new(target).SetAttribute(str(attribute), value)
			saved["Attributes"] = target.get_meta("roblox_properties", {}).get("Attributes", {}).duplicate(true)
			changed = true
			continue
		if str(key) not in allowed:
			continue
		saved[key] = properties[key]
		if key in ["Text", "Value", "Visible", "Enabled", "MaxActivationDistance", "RequiresHandle", "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "AutoRotate", "BlastRadius", "BlastPressure", "DestroyJointRadiusPercent", "ActionText", "ObjectText", "HoldDuration", "MaxSpeed", "Disabled"]:
			LuaScriptEngine.BobuxInstance.new(target)._set(str(key), properties[key])
		changed = true
	target.set_meta("roblox_properties", saved)
	if target is Control:
		RobloxGuiRuntime._apply_udim2_layout(target, saved)
		RobloxGuiRuntime._apply_visual_style(target, str(target.get_meta("roblox_class", "Frame")), saved)
	return changed

func _create_studio_ai_script(action: Dictionary, selected: Node = null, aliases: Dictionary = {}) -> Node:
	var script_class := str(action.get("script_type", "Script"))
	if not script_class in ["Script", "LocalScript", "ModuleScript"]:
		script_class = "Script"
	var parent_name := str(action.get("parent", "StarterPlayerScripts" if script_class == "LocalScript" else "ServerScriptService"))
	var script_parent := _resolve_studio_ai_reference(parent_name, selected, aliases)
	if script_parent == null:
		studio_ai_last_errors.append("Script parent could not be resolved: %s" % parent_name)
		return null
	var script_node := RobloxDataModelClass.create_instance(script_class, str(action.get("name", script_class)))
	script_node.name = str(action.get("name", script_class)).strip_edges()
	if script_node.name.is_empty():
		script_node.name = script_class
	var source := LuaScriptEngine.normalize_script_source(str(action.get("source", "")).left(60000))
	script_node.add_to_group("bobux_scripts")
	script_node.set_meta("script_type", script_class)
	script_node.set_meta("roblox_class", script_class)
	script_node.set_meta("disabled", false)
	script_node.set_meta("code", source)
	script_node.set_meta("lua_source", source)
	script_node.set_meta("bobux_ai_generated", true)
	script_parent.add_child(script_node)
	_open_script_in_editor(script_node)
	return script_node


func _update_studio_ai_script(target: Node, action: Dictionary) -> bool:
	if not _is_studio_ai_scene_node(target) or not str(target.get_meta("roblox_class", "")) in ["Script", "LocalScript", "ModuleScript"]:
		return false
	if action.has("parent"):
		var script_parent := _resolve_studio_ai_reference(str(action["parent"]))
		if script_parent == null or script_parent == target or target.is_ancestor_of(script_parent):
			return false
		if target.get_parent() != script_parent:
			target.reparent(script_parent)
	if str(action.get("script_type", "")) in ["Script", "LocalScript", "ModuleScript"]:
		target.set_meta("roblox_class", str(action["script_type"]))
		target.set_meta("script_type", str(action["script_type"]))
	var source := LuaScriptEngine.normalize_script_source(str(action.get("source", "")).left(60000))
	target.set_meta("code", source)
	target.set_meta("lua_source", source)
	if action.has("disabled"):
		target.set_meta("disabled", bool(action["disabled"]))
		var properties: Dictionary = target.get_meta("roblox_properties", {})
		properties["Disabled"] = bool(action["disabled"])
		target.set_meta("roblox_properties", properties)
	if action.has("name"):
		target.name = str(action["name"])
		target.set_meta("Name", str(target.name))
	var tab := open_scripts.get(target.get_instance_id(), null) as Control
	if is_instance_valid(tab):
		for child in tab.get_children():
			if child is CodeEdit:
				(child as CodeEdit).text = source
	var document_button := script_document_buttons.get(target.get_instance_id(), null) as Button
	if is_instance_valid(document_button):
		document_button.text = str(target.name)
	_open_script_in_editor(target)
	return true


func _apply_studio_ai_object_update(target: Node, action: Dictionary) -> bool:
	if not _is_studio_ai_scene_node(target) or not target is Node3D or bool(target.get_meta("is_roblox_service", false)):
		return false
	var spatial := target as Node3D
	var roblox_class := str(target.get_meta("roblox_class", ""))
	if not target is MeshInstance3D and not roblox_class in ["Model", "Tool", "Folder"]:
		return false
	if action.has("name") and not str(action["name"]).strip_edges().is_empty():
		target.name = str(action["name"]).strip_edges()
		target.set_meta("Name", str(target.name))
		target.set_meta("block_name", str(target.name))
	if action.has("position"):
		spatial.global_position = _studio_ai_vector3(action["position"], spatial.global_position, -100000.0, 100000.0)
	if action.has("rotation"):
		spatial.rotation_degrees = _studio_ai_vector3(action["rotation"], spatial.rotation_degrees, -360.0, 360.0)
	if action.has("scale"):
		spatial.scale *= _studio_ai_vector3(action["scale"], Vector3.ONE, 0.1, 16.0)
	if target is MeshInstance3D:
		var part := target as MeshInstance3D
		if action.has("size"):
			var mesh_size := part.mesh.get_aabb().size if part.mesh != null else Vector3.ONE
			var requested_size := _studio_ai_vector3(action["size"], part.scale * mesh_size, 0.1, 256.0)
			part.scale = requested_size / mesh_size.max(Vector3.ONE * 0.001)
		_apply_studio_ai_part_update(part, action, true)
	else:
		var part_action := action.duplicate(true)
		for key in ["name", "position", "rotation", "size", "scale", "target"]:
			part_action.erase(key)
		for descendant in target.find_children("*", "MeshInstance3D", true, false):
			_apply_studio_ai_part_update(descendant as MeshInstance3D, part_action, true)
	if roblox_class == "Tool":
		for field in [["damage", 0.0, 200.0], ["cooldown", 0.1, 5.0], ["range", 1.0, 24.0]]:
			if action.has(field[0]):
				target.set_meta("bobux_tool_" + str(field[0]), clampf(float(action[field[0]]), field[1], field[2]))
	return true


func _apply_studio_ai_environment(action: Dictionary) -> bool:
	var previous: Dictionary = current_roblox_environment_settings
	var previous_lighting: Dictionary = previous.get("lighting", {})
	var sky_color := Color.from_string(str(action.get("sky_color", "#" + _color_from_array(previous.get("background_color", [0.47, 0.74, 0.95]), Color("#78BDF2")).to_html(false))), Color("#78BDF2"))
	var ambient_color := Color.from_string(str(action.get("ambient_color", "#" + _color_from_array(previous.get("ambient_color", [0.72, 0.83, 0.91]), Color("#B7D3E8")).to_html(false))), Color("#B7D3E8"))
	var sun_color := Color.from_string(str(action.get("sun_color", "#FFF1D2")), Color("#FFF1D2"))
	var brightness := clampf(float(action.get("brightness", previous_lighting.get("Brightness", 2.0))), 0.0, 8.0)
	var clock_time := clampf(float(action.get("clock_time", previous_lighting.get("ClockTime", 14.0))), 0.0, 24.0)
	var lighting_properties := {
		"ClockTime": clock_time,
		"Brightness": brightness,
		"Ambient": _color_to_array(ambient_color),
		"OutdoorAmbient": _color_to_array(ambient_color),
		"ColorShift_Top": _color_to_array(sun_color),
	}
	current_sky_source_path = ""
	current_roblox_environment_settings = {
		"custom_sky_color": action.has("sky_color") or bool(previous.get("custom_sky_color", false)),
		"lighting": lighting_properties.duplicate(true),
		"background_color": _color_to_array(sky_color),
		"ambient_color": _color_to_array(ambient_color),
		"ambient_energy": clampf(brightness * 0.32, 0.0, 2.0),
		"glow_enabled": brightness > 1.25,
		"glow_intensity": clampf(brightness * 0.18, 0.0, 1.25),
		"glow_bloom": 0.08,
		"fog_enabled": false,
	}
	set_meta("roblox_lighting_properties", lighting_properties.duplicate(true))
	if data_model != null:
		var lighting := data_model.ensure_service("Lighting")
		if lighting != null:
			lighting.set_meta("roblox_properties", lighting_properties.duplicate(true))
			lighting.set_meta("bobux_ai_generated", true)
	_apply_imported_roblox_environment_preview()
	if sun_light != null:
		sun_light.light_color = sun_color
		sun_light.light_energy = brightness
		sun_light.shadow_enabled = true
		var daylight_angle := lerpf(-165.0, 15.0, clock_time / 24.0)
		sun_light.rotation_degrees = Vector3(daylight_angle, -32.0, 0.0)
	return true


func _create_authored_tool(tool_parent: Node, specification: Dictionary = {}) -> Node3D:
	if data_model == null:
		return null
	if tool_parent == null or (bool(tool_parent.get_meta("is_roblox_service", false)) and str(tool_parent.get_meta("roblox_class", "")) != "StarterPack"):
		tool_parent = data_model.ensure_service("StarterPack")
	if tool_parent == null:
		return null
	var tool_kind := str(specification.get("tool_kind", "Hammer"))
	if not tool_kind in ["Hammer", "Sword", "Pickup"]:
		tool_kind = "Hammer"
	var default_name := "Tool" if specification.is_empty() else ("Bobux %s" % tool_kind)
	var tool_name := str(specification.get("name", default_name)).strip_edges()
	if tool_name.is_empty():
		tool_name = default_name
	var tool_color := Color.from_string(str(specification.get("color", "#6E97C8")), Color("#6E97C8"))
	var damage := clampf(float(specification.get("damage", 25.0)), 0.0, 200.0)
	var cooldown := clampf(float(specification.get("cooldown", 0.55)), 0.1, 5.0)
	var attack_range := clampf(float(specification.get("range", 5.0)), 1.0, 24.0)
	var fallback_handle_size := Vector3(0.55, 3.5, 0.55) if tool_kind != "Sword" else Vector3(0.45, 4.2, 0.45)
	var handle_size := _studio_ai_vector3(specification.get("handle_size", [fallback_handle_size.x, fallback_handle_size.y, fallback_handle_size.z]), fallback_handle_size, 0.15, 12.0)

	var tool := RobloxDataModelClass.create_instance("Tool", tool_name) as Node3D
	if tool == null:
		return null
	tool.name = tool_name
	tool.set_meta("Name", tool_name)
	tool.set_meta("block_name", tool_name)
	tool.set_meta("bobux_ai_generated", not specification.is_empty())
	tool.set_meta("bobux_tool_kind", tool_kind)
	tool.set_meta("bobux_tool_damage", damage)
	tool.set_meta("bobux_tool_cooldown", cooldown)
	tool.set_meta("bobux_tool_range", attack_range)
	tool.set_meta("bobux_tool_last_activation_msec", 0)
	tool.add_to_group("roblox_tools")
	tool.set_meta("inventory_source", true)
	var tool_properties: Dictionary = tool.get_meta("roblox_properties", {}) if tool.get_meta("roblox_properties", {}) is Dictionary else {}
	tool_properties["RequiresHandle"] = true
	tool_properties["CanBeDropped"] = false
	tool_properties["ToolTip"] = "%s - %.0f damage" % [tool_kind, damage]
	tool_properties["GripPos"] = [0.0, -0.35, 0.0]
	tool.set_meta("roblox_properties", tool_properties)
	tool.visible = false
	tool_parent.add_child(tool, true)

	var handle := _create_authored_tool_part(tool, "Handle", "Box", handle_size, Vector3.ZERO, tool_color.darkened(0.28), "Wood")
	if tool_kind == "Hammer":
		_create_authored_tool_part(tool, "HammerHead", "Box", Vector3(3.1, 1.05, 1.15), Vector3(0.0, handle_size.y * 0.47, 0.0), tool_color, "Metal")
		_create_authored_tool_part(tool, "HammerFace", "Cylinder", Vector3(1.35, 0.5, 1.35), Vector3(1.75, handle_size.y * 0.47, 0.0), tool_color.lightened(0.12), "Metal", Vector3(0.0, 0.0, 90.0))
	elif tool_kind == "Sword":
		_create_authored_tool_part(tool, "Blade", "Wedge", Vector3(0.65, 4.3, 0.28), Vector3(0.0, handle_size.y * 0.83, 0.0), tool_color.lightened(0.35), "Metal")
		_create_authored_tool_part(tool, "Guard", "Box", Vector3(2.3, 0.3, 0.55), Vector3(0.0, handle_size.y * 0.48, 0.0), tool_color, "Metal")
	if handle != null:
		handle.set_meta("bobux_tool_handle", true)

	var local_script := RobloxDataModelClass.create_instance("LocalScript", "ToolClient")
	var source := """local tool = script.Parent
local lastSwing = 0
tool.Equipped:Connect(function()
    tool:SetAttribute(\"Equipped\", true)
end)
tool.Unequipped:Connect(function()
    tool:SetAttribute(\"Equipped\", false)
end)
tool.Activated:Connect(function()
    local now = tick()
    if now - lastSwing < %.3f then return end
    lastSwing = now
    tool:SetAttribute(\"LastSwing\", now)
    print(tool.Name .. \" activated\")
end)
""" % cooldown
	local_script.set_meta("code", source)
	local_script.set_meta("lua_source", source)
	local_script.set_meta("disabled", false)
	local_script.set_meta("bobux_ai_generated", not specification.is_empty())
	tool.add_child(local_script, true)
	return tool


func _create_authored_tool_part(parent: Node3D, part_name: String, shape: String, size: Vector3, position: Vector3, color: Color, material: String, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := _build_imported_block_instance(shape, color, material, 0.0, false, part_name)
	part.name = part_name
	part.scale = size
	part.position = position
	part.rotation_degrees = rotation_degrees_value
	part.set_meta("Name", part_name)
	part.set_meta("block_name", part_name)
	part.set_meta("roblox_class", "Part")
	part.set_meta("anchored", false)
	part.set_meta("can_collide", false)
	parent.add_child(part, true)
	return part


func _create_builtin_model(asset_name: String, options: Dictionary = {}, drop_origin: Vector3 = Vector3.ZERO) -> Node3D:
	var canonical := asset_name.strip_edges().to_lower()
	if canonical == "hammer":
		var hammer_options := options.duplicate(true)
		hammer_options["tool_kind"] = "Hammer"
		return _create_authored_tool(null, hammer_options)
	var specs := _builtin_model_part_specs(canonical)
	if specs.is_empty():
		return null
	var model := Node3D.new()
	model.name = str(options.get("name", asset_name.capitalize())).strip_edges()
	if model.name.is_empty():
		model.name = asset_name.capitalize()
	model.set_meta("roblox_class", "Model")
	model.set_meta("bobux_builtin_asset", canonical)
	model.set_meta("bobux_ai_generated", bool(options.get("bobux_ai_generated", true)))
	placement_parent.add_child(model)
	var offset := _studio_ai_vector3(options.get("position", [0.0, 0.0, 0.0]), Vector3.ZERO, -512.0, 512.0)
	model.global_position = drop_origin + offset
	model.rotation_degrees = _studio_ai_vector3(options.get("rotation", [0.0, 0.0, 0.0]), Vector3.ZERO, -360.0, 360.0)
	model.scale = _studio_ai_vector3(options.get("scale", [1.0, 1.0, 1.0]), Vector3.ONE, 0.1, 16.0)
	var requested_color_text := str(options.get("color", "")).strip_edges()
	var tint_enabled := not requested_color_text.is_empty() and requested_color_text.to_upper() != "#A3A2A5"
	var requested_color := Color.from_string(requested_color_text, Color.WHITE)
	for spec_variant in specs:
		if not spec_variant is Dictionary:
			continue
		var spec: Dictionary = spec_variant
		var default_color := Color.from_string(str(spec.get("color", "#A3A2A5")), Color("#A3A2A5"))
		if tint_enabled and bool(spec.get("tint", true)):
			default_color = requested_color
		var part_action := {
			"name": str(spec.get("name", "Part")),
			"shape": str(spec.get("shape", "Box")),
			"size": spec.get("size", [1.0, 1.0, 1.0]),
			"position": spec.get("position", [0.0, 0.0, 0.0]),
			"rotation": spec.get("rotation", [0.0, 0.0, 0.0]),
			"color": default_color.to_html(false),
			"material": str(spec.get("material", "Plastic")),
			"anchored": true,
			"can_collide": bool(spec.get("can_collide", true)),
			"effects": spec.get("effects", []),
			"interaction": spec.get("interaction", {}),
		}
		var part := _create_studio_ai_part(part_action, model, Vector3.ZERO, true)
		if part != null and bool(spec.get("climbable", false)):
			part.set_meta("climbable", true)
			part.add_to_group("roblox_climbable")
	return model


func _builtin_model_part_specs(asset_name: String) -> Array[Dictionary]:
	match asset_name:
		"coin":
			return [{"name":"Coin", "shape":"Cylinder", "size":[2.6, 0.38, 2.6], "position":[0, 2.2, 0], "rotation":[90, 0, 0], "color":"#F5C542", "material":"Metal", "can_collide":false, "interaction":{"mode":"click", "action":"collect", "prompt":"Collect coin", "max_distance":16}}]
		"tree":
			return [
				{"name":"Trunk", "shape":"Cylinder", "size":[2.0, 8.0, 2.0], "position":[0, 4, 0], "color":"#7A4D2A", "material":"Wood", "tint":false},
				{"name":"CrownLow", "shape":"Sphere", "size":[7.2, 4.5, 7.2], "position":[0, 8.1, 0], "color":"#2E8B45", "material":"Grass"},
				{"name":"CrownHigh", "shape":"Sphere", "size":[5.4, 4.0, 5.4], "position":[0, 11.0, 0], "color":"#39A852", "material":"Grass"},
			]
		"crate":
			return [
				{"name":"CrateBody", "shape":"Box", "size":[4,4,4], "position":[0,2,0], "color":"#A86F3D", "material":"Wood"},
				{"name":"BraceA", "shape":"Box", "size":[0.35,5.2,0.25], "position":[0,2,2.08], "rotation":[0,0,45], "color":"#6D4427", "material":"Wood", "tint":false},
				{"name":"BraceB", "shape":"Box", "size":[0.35,5.2,0.25], "position":[0,2,2.1], "rotation":[0,0,-45], "color":"#6D4427", "material":"Wood", "tint":false},
			]
		"chair":
			return [
				{"name":"Seat", "shape":"Box", "size":[4,0.6,4], "position":[0,3,0], "color":"#9A6337", "material":"Wood"},
				{"name":"Back", "shape":"Box", "size":[4,4.5,0.55], "position":[0,5.4,-1.72], "color":"#9A6337", "material":"Wood"},
				{"name":"Leg1", "shape":"Box", "size":[0.55,3,0.55], "position":[-1.5,1.5,-1.5], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg2", "shape":"Box", "size":[0.55,3,0.55], "position":[1.5,1.5,-1.5], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg3", "shape":"Box", "size":[0.55,3,0.55], "position":[-1.5,1.5,1.5], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg4", "shape":"Box", "size":[0.55,3,0.55], "position":[1.5,1.5,1.5], "color":"#754724", "material":"Wood", "tint":false},
			]
		"table":
			return [
				{"name":"Top", "shape":"Box", "size":[8,0.7,5], "position":[0,4.2,0], "color":"#9A6337", "material":"Wood"},
				{"name":"Leg1", "shape":"Box", "size":[0.65,4.2,0.65], "position":[-3.2,2.1,-1.7], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg2", "shape":"Box", "size":[0.65,4.2,0.65], "position":[3.2,2.1,-1.7], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg3", "shape":"Box", "size":[0.65,4.2,0.65], "position":[-3.2,2.1,1.7], "color":"#754724", "material":"Wood", "tint":false},
				{"name":"Leg4", "shape":"Box", "size":[0.65,4.2,0.65], "position":[3.2,2.1,1.7], "color":"#754724", "material":"Wood", "tint":false},
			]
		"lamp":
			return [
				{"name":"Base", "shape":"Cylinder", "size":[2.4,0.5,2.4], "position":[0,0.25,0], "color":"#4B4F58", "material":"Metal", "tint":false},
				{"name":"Pole", "shape":"Cylinder", "size":[0.45,8,0.45], "position":[0,4.25,0], "color":"#4B4F58", "material":"Metal", "tint":false},
				{"name":"Light", "shape":"Sphere", "size":[2.2,2.2,2.2], "position":[0,8.7,0], "color":"#FFE08A", "material":"Neon", "can_collide":false, "effects":[{"type":"PointLight", "color":"#FFE08A", "enabled":true, "brightness":2.4, "range":18}]},
			]
		"door":
			return [
				{"name":"Door", "shape":"Box", "size":[5,8,0.45], "position":[0,4,0], "color":"#7A4728", "material":"Wood", "interaction":{"mode":"click", "action":"hide", "prompt":"Open door", "max_distance":16}},
				{"name":"Knob", "shape":"Sphere", "size":[0.45,0.45,0.45], "position":[1.8,4,0.32], "color":"#E1B34C", "material":"Metal", "can_collide":false, "tint":false},
			]
		"ladder":
			var ladder: Array[Dictionary] = [
				{"name":"LeftRail", "shape":"Box", "size":[0.45,12,0.45], "position":[-1.6,6,0], "color":"#B8B8B8", "material":"Metal", "climbable":true},
				{"name":"RightRail", "shape":"Box", "size":[0.45,12,0.45], "position":[1.6,6,0], "color":"#B8B8B8", "material":"Metal", "climbable":true},
			]
			for rung_index in range(7):
				ladder.append({"name":"Rung%d" % (rung_index + 1), "shape":"Cylinder", "size":[0.34,3.2,0.34], "position":[0,1.1 + rung_index * 1.65,0], "rotation":[0,0,90], "color":"#B8B8B8", "material":"Metal", "climbable":true})
			return ladder
		"arch":
			return [
				{"name":"LeftPillar", "shape":"Box", "size":[3,10,3], "position":[-5,5,0], "color":"#B8A58D", "material":"Concrete"},
				{"name":"RightPillar", "shape":"Box", "size":[3,10,3], "position":[5,5,0], "color":"#B8A58D", "material":"Concrete"},
				{"name":"ArchTop", "shape":"Cylinder", "size":[13,3,3], "position":[0,10,0], "rotation":[0,0,90], "color":"#B8A58D", "material":"Concrete"},
			]
		"stairs":
			var stairs: Array[Dictionary] = []
			for stair_index in range(8):
				stairs.append({"name":"Step%d" % (stair_index + 1), "shape":"Box", "size":[6,0.75,2.2], "position":[0,0.375 + stair_index * 0.75,stair_index * -1.7], "color":"#9A9DA3", "material":"Concrete"})
			return stairs
	return []


func _create_studio_ai_part(action: Dictionary, parent: Node, origin: Vector3, local_position: bool) -> MeshInstance3D:
	if parent == null:
		return null
	var shape := str(action.get("shape", "Box"))
	if not shape in ["Box", "Sphere", "Cylinder", "Cone", "Wedge", "CornerWedge", "Truss", "Water", "Spawn", "Checkpoint", "Teleport", "Seat", "VehicleSeat"]:
		shape = "Box"
	var color := Color.from_string(str(action.get("color", "#A3A2A5")), Color("#A3A2A5"))
	var material := str(action.get("material", "Plastic"))
	var can_collide := bool(action.get("can_collide", true))
	var part := _build_block_instance(shape, color, material, 0.0, can_collide, str(action.get("name", "Part")))
	part.name = str(action.get("name", "Part")).strip_edges()
	if part.name.is_empty():
		part.name = "Part"
	part.scale = _studio_ai_vector3(action.get("size", [4.0, 1.0, 2.0]), Vector3(4.0, 1.0, 2.0), 0.1, 256.0)
	part.rotation_degrees = _studio_ai_vector3(action.get("rotation", [0.0, 0.0, 0.0]), Vector3.ZERO, -360.0, 360.0)
	part.set_meta("anchored", bool(action.get("anchored", true)))
	part.set_meta("bobux_ai_generated", true)
	parent.add_child(part)
	var offset := _studio_ai_vector3(action.get("position", [0.0, 0.0, 0.0]), Vector3.ZERO, -512.0, 512.0)
	if local_position:
		part.position = offset
	else:
		part.global_position = origin + offset
	_apply_studio_ai_part_update(part, action, false)
	return part


func _apply_studio_ai_part_update(part: MeshInstance3D, action: Dictionary, preserve_transform: bool = true) -> void:
	if part == null or not is_instance_valid(part):
		return
	if action.has("name"):
		var requested_name := str(action.get("name", part.name)).strip_edges()
		if not requested_name.is_empty():
			part.name = requested_name
			part.set_meta("block_name", requested_name)
	if action.has("color"):
		var color := Color.from_string(str(action.get("color", "#A3A2A5")), _get_bobux_block_color(part, Color("#A3A2A5")))
		part.set_meta("bobux_color", Color(color.r, color.g, color.b, 1.0))
	if action.has("material"):
		part.set_meta("material_type", str(action.get("material", "Plastic")))
	if action.has("anchored"):
		part.set_meta("anchored", bool(action.get("anchored", true)))
	if action.has("physics_mode"):
		var physics_mode := str(action.get("physics_mode", "Static")).strip_edges().capitalize()
		part.set_meta("bobux_physics_mode", physics_mode)
		if physics_mode == "Dynamic":
			part.set_meta("anchored", false)
	for physics_field in [
		["mass", "bobux_physics_mass", 1.0, 0.05, 1000.0],
		["friction", "bobux_physics_friction", 0.5, 0.0, 1.0],
		["bounce", "bobux_physics_bounce", 0.0, 0.0, 1.0],
		["gravity_scale", "bobux_physics_gravity_scale", 1.0, -4.0, 4.0],
		["linear_damp", "bobux_physics_linear_damp", 0.1, 0.0, 32.0],
		["angular_damp", "bobux_physics_angular_damp", 0.1, 0.0, 32.0]
	]:
		var action_key := str(physics_field[0])
		if action.has(action_key):
			part.set_meta(
				str(physics_field[1]),
				clampf(float(action.get(action_key, physics_field[2])), float(physics_field[3]), float(physics_field[4]))
			)
	if action.has("can_collide"):
		part.set_meta("can_collide", bool(action.get("can_collide", true)))
	if action.has("effects") and action.get("effects", []) is Array:
		part.set_meta("bobux_ai_effects", (action.get("effects", []) as Array).duplicate(true))
	if action.has("interaction") and action.get("interaction", {}) is Dictionary:
		part.set_meta("bobux_ai_interaction", (action.get("interaction", {}) as Dictionary).duplicate(true))
	if not preserve_transform:
		part.set_meta("bobux_ai_generated", true)
	_rebuild_block_material(part)
	_rebuild_block_helpers(part)
	_rebuild_studio_ai_components(part)


func _rebuild_studio_ai_components(part: MeshInstance3D) -> void:
	if part == null or not is_instance_valid(part):
		return
	for child in part.get_children():
		if bool(child.get_meta("bobux_ai_component", false)):
			child.queue_free()
	var effects: Array = part.get_meta("bobux_ai_effects", []) if part.get_meta("bobux_ai_effects", []) is Array else []
	for index in range(effects.size()):
		if not effects[index] is Dictionary:
			continue
		var effect_spec: Dictionary = effects[index]
		var effect_type := str(effect_spec.get("type", ""))
		if not effect_type in ["Fire", "Smoke", "Sparkles", "PointLight"]:
			continue
		var effect_node := RobloxDataModelClass.create_instance(effect_type, "%s_%d" % [effect_type, index + 1])
		if effect_node == null:
			continue
		_configure_studio_ai_effect_node(effect_node, effect_spec)
		part.add_child(effect_node)
	var interaction: Dictionary = part.get_meta("bobux_ai_interaction", {}) if part.get_meta("bobux_ai_interaction", {}) is Dictionary else {}
	if interaction.is_empty():
		return
	var mode := str(interaction.get("mode", "click"))
	var interaction_class := "ProximityPrompt" if mode == "proximity" else ("TouchInterest" if mode == "touch" else "ClickDetector")
	var interaction_node := RobloxDataModelClass.create_instance(interaction_class, interaction_class)
	if interaction_node == null:
		interaction_node = Node.new()
	interaction_node.name = interaction_class
	interaction_node.set_meta("roblox_class", interaction_node.name)
	interaction_node.set_meta("bobux_ai_component", true)
	interaction_node.set_meta("bobux_runtime_generated", true)
	interaction_node.set_meta("bobux_ai_interaction", interaction.duplicate(true))
	interaction_node.set_meta("roblox_properties", {
		"Enabled": true,
		"ActionText": str(interaction.get("prompt", "Use")),
		"MaxActivationDistance": float(interaction.get("max_distance", 16.0))
	})
	interaction_node.set_meta("max_activation_distance", float(interaction.get("max_distance", 16.0)))
	interaction_node.set_meta("action_text", str(interaction.get("prompt", "Use")))
	if mode == "proximity":
		interaction_node.add_to_group("roblox_proximity_prompts")
	elif mode == "click":
		interaction_node.add_to_group("roblox_click_detectors")
	part.add_child(interaction_node)
	var interaction_source := _studio_ai_interaction_source(mode, str(interaction.get("action", "")))
	if not interaction_source.is_empty():
		var script_node := RobloxDataModelClass.create_instance("Script", "InteractionScript")
		if script_node != null:
			script_node.name = "InteractionScript"
			script_node.add_to_group("bobux_scripts")
			script_node.set_meta("script_type", "Script")
			script_node.set_meta("roblox_class", "Script")
			script_node.set_meta("disabled", false)
			script_node.set_meta("code", interaction_source)
			script_node.set_meta("lua_source", interaction_source)
			script_node.set_meta("bobux_ai_component", true)
			script_node.set_meta("bobux_ai_generated", true)
			part.add_child(script_node)


func _studio_ai_interaction_source(mode: String, action: String) -> String:
	var event_expression := "detector.MouseClick"
	if mode == "proximity":
		event_expression = "detector.Triggered"
	elif mode == "touch":
		event_expression = "part.Touched"
	var detector_lookup := "local detector = part:FindFirstChild(\"ClickDetector\")"
	if mode == "proximity":
		detector_lookup = "local detector = part:FindFirstChild(\"ProximityPrompt\")"
	elif mode == "touch":
		detector_lookup = "local detector = part"
	match action:
		"collect":
			return """local part = script.Parent
%s
local collected = false
%s:Connect(function(player)
    if collected then return end
    collected = true
    part:Destroy()
end)
""" % [detector_lookup, event_expression]
		"hide":
			return """local part = script.Parent
%s
local opened = false
%s:Connect(function(player)
    opened = not opened
    part.Transparency = opened and 1 or 0
    part.CanCollide = not opened
end)
""" % [detector_lookup, event_expression]
		"toggle_door":
			return """local door = script.Parent
%s
local closedPosition = door.Position
local openPosition = closedPosition + Vector3.new(0, math.max(door.Size.Y + 0.35, 4), 0)
local opened = false
%s:Connect(function(player)
    if opened then
        door.CanCollide = true
        door.Position = closedPosition
    else
        door.Position = openPosition
        door.CanCollide = false
    end
    opened = not opened
end)
""" % [detector_lookup, event_expression]
		"toggle_effect":
			return """local part = script.Parent
%s
%s:Connect(function(player)
	local effect = part:FindFirstChildOfClass("Fire")
	if effect == nil then effect = part:FindFirstChildOfClass("Smoke") end
	if effect == nil then effect = part:FindFirstChildOfClass("Sparkles") end
	if effect == nil then effect = part:FindFirstChildOfClass("PointLight") end
    if effect then effect.Enabled = not effect.Enabled end
end)
""" % [detector_lookup, event_expression]
	return ""


func _configure_studio_ai_effect_node(effect_node: Node, effect_spec: Dictionary) -> void:
	var effect_type := str(effect_spec.get("type", effect_node.name))
	var primary := Color.from_string(str(effect_spec.get("color", "#FF7814")), Color("#FF7814"))
	effect_node.name = effect_type
	effect_node.set_meta("roblox_class", effect_type)
	effect_node.set_meta("bobux_ai_component", true)
	effect_node.set_meta("bobux_runtime_generated", true)
	effect_node.set_meta("bobux_ai_effect", effect_spec.duplicate(true))
	effect_node.set_meta("roblox_properties", {
		"Enabled": bool(effect_spec.get("enabled", true)),
		"Color": [primary.r, primary.g, primary.b],
		"Brightness": float(effect_spec.get("brightness", 2.0)),
		"Range": float(effect_spec.get("range", 12.0)),
		"Rate": float(effect_spec.get("rate", 20.0))
	})
	if effect_node is GPUParticles3D:
		var particles := effect_node as GPUParticles3D
		particles.emitting = bool(effect_spec.get("enabled", true))
		particles.amount = maxi(1, int(effect_spec.get("rate", 20.0)))
		var process := particles.process_material as ParticleProcessMaterial
		if process == null:
			process = ParticleProcessMaterial.new()
			particles.process_material = process
		process.color = primary
	elif effect_node is Light3D:
		var light := effect_node as Light3D
		light.light_color = primary
		light.light_energy = float(effect_spec.get("brightness", 2.0))
		light.visible = bool(effect_spec.get("enabled", true))
		if light is OmniLight3D:
			(light as OmniLight3D).omni_range = float(effect_spec.get("range", 12.0))


func _studio_ai_vector3(value: Variant, fallback: Vector3, minimum: float, maximum: float) -> Vector3:
	if not value is Array or value.size() < 3:
		return fallback
	return Vector3(
		clampf(float(value[0]), minimum, maximum),
		clampf(float(value[1]), minimum, maximum),
		clampf(float(value[2]), minimum, maximum)
	)


func _is_gui_script_parent(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		var roblox_class := str(cursor.get_meta("roblox_class", ""))
		if roblox_class in [
			"StarterGui", "PlayerGui", "ScreenGui", "SurfaceGui", "BillboardGui",
			"CanvasGroup", "Frame", "ScrollingFrame", "TextLabel", "TextButton",
			"TextBox", "ImageLabel", "ImageButton"
		]:
			return true
		cursor = cursor.get_parent()
	return false

func _show_service_properties(service_name: String) -> void:
	_clear_inspector()
	var label := Label.new()
	label.text = "Service: " + service_name
	inspector_panel.add_child(label)

func _open_script_in_editor(script_node: Node) -> void:
	var inst_id := script_node.get_instance_id()
	_ensure_script_document_button(script_node)
	
	if open_scripts.has(inst_id):
		_show_script_document(inst_id)
		return
			
	var tab_root := VBoxContainer.new()
	tab_root.name = script_node.name
	script_editor_tabs.add_child(tab_root)
	open_scripts[inst_id] = tab_root
	_show_script_document(inst_id)
	
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	tab_root.add_child(toolbar)
	
	var save_btn := Button.new()
	save_btn.text = "Save"
	_style_white_button(save_btn)
	toolbar.add_child(save_btn)
	
	var keyboard_btn: Button = null
	if _is_mobile_studio_runtime():
		keyboard_btn = Button.new()
		keyboard_btn.text = "Keyboard"
		keyboard_btn.tooltip_text = "Focus the code editor and open the screen keyboard"
		_style_white_button(keyboard_btn)
		toolbar.add_child(keyboard_btn)
	
	var close_btn := Button.new()
	close_btn.text = "Close"
	_style_white_button(close_btn)
	toolbar.add_child(close_btn)
	
	var code_edit := CodeEdit.new()
	code_edit.text = script_node.get_meta("code", "")
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_lua_editor(code_edit)
	tab_root.add_child(code_edit)
	if keyboard_btn != null:
		keyboard_btn.pressed.connect(func() -> void:
			code_edit.grab_focus()
		)
		code_edit.call_deferred("grab_focus")
	var document_button := script_document_buttons.get(inst_id, null) as Button
	code_edit.text_changed.connect(func() -> void:
		if document_button != null and is_instance_valid(document_button) and not document_button.text.ends_with(" *"):
			document_button.text = "%s *" % script_node.name
	)
	
	var console_panel := PanelContainer.new()
	console_panel.custom_minimum_size = Vector2(0, 84 if _is_mobile_studio_runtime() else 120)
	console_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#17191D"), Color("#333840"), 1))
	tab_root.add_child(console_panel)
	
	var console_vbox := VBoxContainer.new()
	console_panel.add_child(console_vbox)
	
	var console_title := Label.new()
	console_title.text = "Output Log:"
	console_title.add_theme_font_size_override("font_size", 11)
	console_title.add_theme_color_override("font_color", Color("#D9DCE1"))
	console_vbox.add_child(console_title)
	
	var console_text := RichTextLabel.new()
	console_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console_text.scroll_following = true
	console_text.add_theme_color_override("default_color", Color("#C8CDD5"))
	console_vbox.add_child(console_text)
	
	save_btn.pressed.connect(func():
		if not is_instance_valid(script_node):
			console_text.append_text("[Error] Script instance no longer exists.\n")
			return
		code_edit.text = LuaScriptEngine.normalize_script_source(code_edit.text)
		var validation: Dictionary = LuaScriptEngine.validate_script_source(code_edit.text)
		if not bool(validation.get("ok", false)):
			console_text.append_text("[Compile Error] %s\n" % str(validation.get("error", "Unknown syntax error")))
			return
		_commit_script_editor_source(script_node, code_edit.text)
		if document_button != null and is_instance_valid(document_button):
			document_button.text = script_node.name
		console_text.append_text("[System] Saved. The script starts automatically with Play. Restart Play to apply changes.\n")
	)
	
	close_btn.pressed.connect(func():
		open_scripts.erase(inst_id)
		var doc_button := script_document_buttons.get(inst_id, null) as Button
		script_document_buttons.erase(inst_id)
		if doc_button != null and is_instance_valid(doc_button):
			doc_button.queue_free()
		tab_root.queue_free()
		_show_viewport_document()
	)
	
	script_editor_tabs.current_tab = script_editor_tabs.get_tab_idx_from_control(tab_root)


func _on_lua_script_message(context: Node, message: String, is_error: bool) -> void:
	if not _is_studio_ai_scene_node(context) and not (is_instance_valid(studio_playtest_player) and studio_playtest_player.is_ancestor_of(context)):
		return
	var reference := str(context.get_meta("roblox_ref", ""))
	for instance_id in open_scripts:
		var authored := instance_from_id(int(instance_id)) as Node
		if not is_instance_valid(authored):
			continue
		if authored != context and (reference.is_empty() or str(authored.get_meta("roblox_ref", "")) != reference):
			continue
		var output := _find_output_log(open_scripts[instance_id])
		if output != null:
			if output.get_line_count() > 500:
				output.clear()
			output.append_text(("[Error] " if is_error else "") + message + "\n")
	if is_error and toolbar_status_label != null:
		toolbar_status_label.text = "%s: %s" % [context.name, message.left(220)]

func _commit_script_editor_source(script_node: Node, source: String) -> void:
	if script_node == null:
		return
	script_node.set_meta("code", source)
	script_node.set_meta("lua_source", source)
	if data_model != null and data_model.has_method("build_manifest"):
		var live_manifest: Variant = data_model.call("build_manifest", current_roblox_place_manifest)
		if live_manifest is Dictionary:
			current_roblox_place_manifest = (live_manifest as Dictionary).duplicate(false)
	_commit_editor_history("Edit script source")

func setup_lua_editor(code_edit: CodeEdit) -> void:
	var highlighter := CodeHighlighter.new()
	for kw in [
		"and", "break", "do", "else", "elseif", "end", "false", "for",
		"function", "if", "in", "local", "nil", "not", "or", "repeat",
		"return", "then", "true", "until", "while", "continue"
	]:
		highlighter.add_keyword_color(kw, Color("#CC7832"))
	for type_name in ["number", "string", "boolean", "table", "any", "void"]:
		highlighter.add_keyword_color(type_name, Color("#4EC9B0"))
	for api in [
		"game", "workspace", "script", "print", "warn", "error",
		"wait", "task", "Instance", "Vector3", "Vector2", "CFrame",
		"Color3", "BrickColor", "UDim", "UDim2", "Enum", "math",
		"string", "table", "pairs", "ipairs", "next", "select",
		"tostring", "tonumber", "type", "typeof", "rawget", "rawset"
	]:
		highlighter.add_keyword_color(api, Color("#9CDCFE"))
	highlighter.add_color_region('"', '"', Color("#CE9178"))
	highlighter.add_color_region("'", "'", Color("#CE9178"))
	highlighter.add_color_region("[[", "]]", Color("#CE9178"))
	highlighter.add_color_region("--[[", "]]", Color("#6A9955"), false)
	highlighter.add_color_region("--", "", Color("#6A9955"), true)
	highlighter.number_color = Color("#B5CEA8")
	code_edit.syntax_highlighter = highlighter
	code_edit.indent_automatic = true
	code_edit.indent_size = 4
	code_edit.line_folding = true
	code_edit.gutters_draw_line_numbers = true
	code_edit.highlight_current_line = true
	code_edit.minimap_draw = not _is_mobile_studio_runtime()
	code_edit.minimap_width = 96
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if _is_mobile_studio_runtime() else TextEdit.LINE_WRAPPING_NONE
	code_edit.virtual_keyboard_enabled = true
	code_edit.add_theme_font_size_override("font_size", 17 if _is_mobile_studio_runtime() else 14)
	code_edit.add_theme_color_override("background_color", Color("#1E1E1E"))
	code_edit.add_theme_color_override("font_color", Color("#D4D4D4"))
	code_edit.add_theme_color_override("font_readonly_color", Color("#A7ACB5"))
	code_edit.add_theme_color_override("caret_color", Color("#F0F0F0"))
	code_edit.add_theme_color_override("current_line_color", Color("#292D33"))
	code_edit.add_theme_color_override("selection_color", Color("#264F78"))
	code_edit.add_theme_color_override("line_number_color", Color("#858585"))

func _set_item_icon(item: TreeItem, type_name: String) -> void:
	var icon: Texture2D = null
	if explorer_tree.has_theme_icon(type_name, "EditorIcons"):
		icon = explorer_tree.get_theme_icon(type_name, "EditorIcons")
	elif type_name == "Workspace":
		icon = explorer_tree.get_theme_icon("Node3D", "EditorIcons") if explorer_tree.has_theme_icon("Node3D", "EditorIcons") else null
	elif type_name == "Folder" or type_name == "Model":
		icon = explorer_tree.get_theme_icon("Folder", "EditorIcons") if explorer_tree.has_theme_icon("Folder", "EditorIcons") else null
	elif type_name == "Script" or type_name == "LocalScript" or type_name == "ModuleScript":
		icon = explorer_tree.get_theme_icon("Script", "EditorIcons") if explorer_tree.has_theme_icon("Script", "EditorIcons") else null
	
	if icon:
		item.set_icon(0, icon)

func _create_toolbar_button(text: String, width: float, accent_color: Color, toggle_mode := false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle_mode
	button.custom_minimum_size = Vector2(width, 32)
	button.set_meta("accent_color", accent_color)
	_style_toolbar_button(button, false)
	return button

func _open_toolbox_dialog() -> void:
	if toolbox_dialog != null and is_instance_valid(toolbox_dialog):
		toolbox_dialog.queue_free()
	toolbox_dialog = AcceptDialog.new()
	toolbox_dialog.title = "Toolbox"
	toolbox_dialog.ok_button_text = "Close"
	add_child(toolbox_dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(720, 500)
	root.add_theme_constant_override("separation", 8)
	toolbox_dialog.add_child(root)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var models_page := VBoxContainer.new()
	models_page.name = "Models"
	models_page.add_theme_constant_override("separation", 8)
	tabs.add_child(models_page)
	var search := LineEdit.new()
	search.placeholder_text = "Search Toolbox"
	search.custom_minimum_size = Vector2(0, 28)
	search.add_theme_stylebox_override("normal", _studio_line_edit_style())
	models_page.add_child(search)
	var builtin_grid := GridContainer.new()
	builtin_grid.columns = 4
	builtin_grid.add_theme_constant_override("h_separation", 8)
	builtin_grid.add_theme_constant_override("v_separation", 8)
	models_page.add_child(builtin_grid)
	for builtin in [
		["Part", "Box"],
		["WedgePart", "Wedge"],
		["Cylinder", "Cylinder"],
		["Cone", "Cone"],
		["Sphere", "Sphere"],
		["SpawnLocation", "Spawn"],
		["Checkpoint", "Checkpoint"],
		["Teleport", "Teleport"],
		["R6 Character", "Character"],
		["Coin", "Coin"],
		["Tree", "Tree"],
		["Crate", "Crate"],
		["Chair", "Chair"],
		["Table", "Table"],
		["Lamp", "Lamp"],
		["Door", "Door"],
		["Ladder", "Ladder"],
		["Arch", "Arch"],
		["Stairs", "Stairs"],
		["Hammer", "Hammer"]
	]:
		builtin_grid.add_child(_create_toolbox_builtin_card(str(builtin[0]), str(builtin[1])))

	var model_scroll := ScrollContainer.new()
	model_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	models_page.add_child(model_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	model_scroll.add_child(list)
	var drafts_label := Label.new()
	drafts_label.text = "My Models and Marketplace"
	drafts_label.add_theme_font_size_override("font_size", 12)
	drafts_label.add_theme_color_override("font_color", Color("#333333"))
	list.add_child(drafts_label)

	for tab_name in ["Decals", "Meshes", "Audio", "Video", "Plugins"]:
		var page := VBoxContainer.new()
		page.name = tab_name
		page.add_theme_constant_override("separation", 8)
		var tab_search := LineEdit.new()
		tab_search.placeholder_text = "Search %s" % tab_name
		tab_search.custom_minimum_size = Vector2(0, 28)
		tab_search.add_theme_stylebox_override("normal", _studio_line_edit_style())
		page.add_child(tab_search)
		var asset_list := ItemList.new()
		asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var asset_entries := _get_toolbox_entries(tab_name)
		for entry in asset_entries:
			asset_list.add_item(str(entry.get("label", "Asset")), _get_toolbar_icon(str(entry.get("icon", "Assets")), Color("#34373C")))
			var item_index := asset_list.item_count - 1
			asset_list.set_item_metadata(item_index, entry)
			asset_list.set_item_tooltip(item_index, str(entry.get("path", entry.get("description", entry.get("label", "Asset")))))
		if asset_list.item_count == 0:
			asset_list.add_item("No matching project assets")
			asset_list.set_item_disabled(0, true)
		asset_list.item_activated.connect(_on_assets_dialog_item_activated.bind(asset_list))
		page.add_child(asset_list)
		tabs.add_child(page)

	var entries: Array[Dictionary] = []
	var seen_model_ids: Dictionary = {}
	for draft_entry in _load_local_model_draft_entries():
		var local_identity := _studio_model_identity(draft_entry)
		if not local_identity.is_empty():
			seen_model_ids[local_identity] = true
		entries.append(draft_entry)
	if CloudAPI != null and CloudAPI.is_configured():
		var cloud_response: Dictionary = await CloudAPI.fetch_marketplace_models(96, true, false)
		if bool(cloud_response.get("ok", false)):
			for cloud_variant in _extract_toolbox_response_array(cloud_response):
				if not (cloud_variant is Dictionary):
					continue
				var cloud_entry: Dictionary = (cloud_variant as Dictionary).duplicate(true)
				cloud_entry["publish_state"] = "cloud"
				var cloud_identity := _studio_model_identity(cloud_entry)
				if not cloud_identity.is_empty() and seen_model_ids.has(cloud_identity):
					continue
				if not cloud_identity.is_empty():
					seen_model_ids[cloud_identity] = true
				entries.append(cloud_entry)
		elif toolbar_status_label:
			toolbar_status_label.text = "Toolbox cloud load failed: %s" % str(cloud_response.get("error", "Unknown error"))
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No model drafts or marketplace models yet."
		list.add_child(empty)
	for entry in entries:
		list.add_child(_create_toolbox_model_row(entry))
	toolbox_dialog.popup_centered(Vector2i(760, 560))

func _create_toolbox_builtin_card(title: String, shape_name: String) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(150, 92)
	card.tooltip_text = "Insert " + title
	_style_white_button(card)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6
	vbox.offset_top = 5
	vbox.offset_right = -6
	vbox.offset_bottom = -5
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(0, 42)
	preview.texture = _get_toolbox_preview_icon(title, shape_name)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(preview)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("#333333"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label)
	card.pressed.connect(func() -> void:
		_insert_toolbox_builtin(shape_name)
	)
	return card

func _insert_toolbox_builtin(shape_name: String) -> void:
	if _is_studio_editing_locked():
		return
	if shape_name == "Character":
		_insert_character_placeholder()
	elif shape_name in ["Coin", "Tree", "Crate", "Chair", "Table", "Lamp", "Door", "Ladder", "Arch", "Stairs", "Hammer"]:
		var model := _create_builtin_model(shape_name, {"bobux_ai_generated": false}, _get_editor_drop_position(10.0))
		if model != null:
			explorer_selected_node = model
			_refresh_explorer()
			_show_properties_for_node(model)
			_commit_editor_history("Insert built-in model")
	else:
		_place_shape_from_ribbon(shape_name)
	if toolbox_dialog != null and is_instance_valid(toolbox_dialog):
		toolbox_dialog.hide()

func _get_toolbox_preview_icon(title: String, shape_name: String) -> Texture2D:
	var key := "toolbox:%s:%s" % [title, shape_name]
	if studio_toolbar_icon_cache.has(key):
		return studio_toolbar_icon_cache[key]
	var image := Image.create_empty(96, 44, false, Image.FORMAT_RGBA8)
	image.fill(Color("#F6F8FA"))
	var primary := Color("#6FA8DC")
	match shape_name:
		"Character":
			primary = Color("#6FBF73")
		"Spawn", "Checkpoint", "Teleport":
			primary = Color("#8FD18F")
		"Wedge":
			primary = Color("#B38BFA")
		"Cylinder", "Cone", "Sphere":
			primary = Color("#77B7E5")
	for y in range(36, 40):
		for x in range(14, 82):
			image.set_pixel(x, y, Color(0, 0, 0, 0.08))
	match shape_name:
		"Sphere":
			_draw_icon_circle(image, Vector2i(48, 22), 14, primary)
			_draw_icon_circle(image, Vector2i(43, 17), 5, primary.lightened(0.45))
		"Cylinder":
			_draw_icon_rect(image, Rect2i(34, 14, 28, 20), primary, true)
			_draw_icon_circle(image, Vector2i(48, 14), 14, primary.lightened(0.12))
			_draw_icon_circle(image, Vector2i(48, 34), 14, primary.darkened(0.12))
		"Cone":
			_draw_icon_triangle(image, Vector2i(48, 7), Vector2i(31, 35), Vector2i(65, 35), primary)
			_draw_icon_line(image, Vector2i(31, 35), Vector2i(65, 35), primary.darkened(0.25))
		"Wedge":
			_draw_icon_triangle(image, Vector2i(30, 34), Vector2i(66, 34), Vector2i(66, 12), primary)
			_draw_icon_line(image, Vector2i(30, 34), Vector2i(66, 12), primary.darkened(0.35))
		"Character":
			_draw_icon_circle(image, Vector2i(48, 10), 5, Color("#F4C542"))
			_draw_icon_rect(image, Rect2i(39, 16, 18, 14), Color("#2E77BB"), true)
			_draw_icon_rect(image, Rect2i(31, 17, 7, 13), Color("#F4C542"), true)
			_draw_icon_rect(image, Rect2i(58, 17, 7, 13), Color("#F4C542"), true)
			_draw_icon_rect(image, Rect2i(40, 31, 7, 9), Color("#4BAE32"), true)
			_draw_icon_rect(image, Rect2i(49, 31, 7, 9), Color("#4BAE32"), true)
		_:
			_draw_icon_rect(image, Rect2i(31, 12, 34, 22), primary, true)
			_draw_icon_line(image, Vector2i(31, 12), Vector2i(42, 5), primary.lightened(0.35))
			_draw_icon_line(image, Vector2i(65, 12), Vector2i(76, 5), primary.lightened(0.25))
			_draw_icon_line(image, Vector2i(42, 5), Vector2i(76, 5), primary.lightened(0.35))
	var tex := ImageTexture.create_from_image(image)
	studio_toolbar_icon_cache[key] = tex
	return tex

func _create_toolbox_model_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 82)
	var preview_panel := Panel.new()
	preview_panel.custom_minimum_size = Vector2(72, 72)
	preview_panel.add_theme_stylebox_override("panel", _studio_panel_style(Color("#F5F6F7"), Color("#D4D6D9"), 1, 2))
	row.add_child(preview_panel)
	var thumbnail := _resolve_toolbox_model_thumbnail(entry)
	if not thumbnail.is_empty():
		CatalogBuilder._apply_item_thumbnail_async(self, thumbnail, preview_panel)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	row.add_child(title_box)
	var title := Label.new()
	title.text = str(entry.get("name", entry.get("draft_id", "Model Draft"))).strip_edges()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 13)
	title_box.add_child(title)
	var author := Label.new()
	author.text = "by %s" % str(entry.get("owner_username", entry.get("owner_name", UserSession.username))).strip_edges()
	author.clip_text = true
	author.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	author.add_theme_font_size_override("font_size", 10)
	author.add_theme_color_override("font_color", Color("#666A70"))
	title_box.add_child(author)
	var state := Label.new()
	state.text = "Published model" if str(entry.get("publish_state", "")).to_lower() == "cloud" else "Saved model draft"
	state.add_theme_font_size_override("font_size", 10)
	state.add_theme_color_override("font_color", Color("#777B80"))
	title_box.add_child(state)
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
	if _is_studio_editing_locked():
		return
	var source_entry: Dictionary = _toolbox_model_data_from_entry(entry)
	var exact_source_path := await _resolve_model_source_path(entry, source_entry)
	if not exact_source_path.is_empty() and _insert_exact_model_source(entry, source_entry, exact_source_path):
		return
	var parts: Array = _toolbox_extract_parts_from_model_data(source_entry)
	if parts.is_empty():
		if toolbar_status_label:
			toolbar_status_label.text = "This model has no placeable parts. Re-publish it with the updated Model Editor."
		return
	var parent_node: Node3D = placement_parent if placement_parent else self
	var inserted_blocks: Array[Node3D] = []
	var source_pivot := _calculate_model_parts_pivot(parts)
	var paste_offset := _get_editor_drop_position(10.0) - source_pivot
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

func _resolve_model_source_path(entry: Dictionary, source_entry: Dictionary) -> String:
	var candidates := _model_metadata_candidates(entry, source_entry)
	for candidate in candidates:
		for key in ["source_model_path", "source_asset_path", "source_path"]:
			var local_path := str((candidate as Dictionary).get(key, "")).strip_edges()
			if not local_path.is_empty() and FileAccess.file_exists(local_path):
				return local_path
	var source_url := ""
	var source_file_name := ""
	for candidate in candidates:
		var data := candidate as Dictionary
		if source_url.is_empty():
			source_url = str(data.get("source_url", data.get("source_file_url", ""))).strip_edges()
		if source_file_name.is_empty():
			source_file_name = str(data.get("source_file_name", "")).strip_edges()
	if source_url.is_empty() or CloudAPI == null or not CloudAPI.has_method("download_map_asset_file"):
		return ""
	var extension := source_file_name.get_extension().to_lower()
	if extension.is_empty():
		extension = source_url.split("?", false, 1)[0].get_extension().to_lower()
	if extension not in ["glb", "gltf", "obj"]:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STUDIO_MODEL_CACHE_FOLDER))
	var cache_name := "%s.%s" % [source_url.md5_text(), extension]
	var cache_path := STUDIO_MODEL_CACHE_FOLDER.path_join(cache_name)
	if FileAccess.file_exists(cache_path):
		var cached := FileAccess.open(cache_path, FileAccess.READ)
		if cached != null and cached.get_length() > 32:
			cached.close()
			return cache_path
		if cached != null:
			cached.close()
	if toolbar_status_label:
		toolbar_status_label.text = "Downloading original model geometry..."
	var download_result: Dictionary = await CloudAPI.download_map_asset_file(source_url, cache_path)
	if bool(download_result.get("ok", false)) and FileAccess.file_exists(cache_path):
		return cache_path
	push_warning("[Studio] Exact model download failed: %s" % str(download_result.get("error", "unknown error")))
	return ""

func _model_metadata_candidates(entry: Dictionary, source_entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var queue: Array = [entry, source_entry]
	var seen := {}
	while not queue.is_empty() and result.size() < 24:
		var value: Variant = queue.pop_front()
		var data := _toolbox_dictionary_from_jsonish_variant(value)
		if data.is_empty():
			continue
		var signature := JSON.stringify(data)
		if seen.has(signature):
			continue
		seen[signature] = true
		result.append(data)
		for key in ["metadata", "data", "model_data", "asset_data", "model", "asset", "source", "payload", "record", "row"]:
			if data.has(key):
				queue.append(data.get(key))
	return result

func _insert_exact_model_source(entry: Dictionary, source_entry: Dictionary, source_path: String) -> bool:
	var source_scene := _load_external_model_scene(source_path)
	if source_scene == null:
		return false
	var target_parent := _resolve_studio_3d_parent(_get_selected_editor_node())
	if not (target_parent is Node3D):
		target_parent = placement_parent
	var wrapper := Node3D.new()
	wrapper.name = str(entry.get("name", source_path.get_file().get_basename())).strip_edges()
	if wrapper.name.is_empty():
		wrapper.name = "Model"
	wrapper.set_meta("roblox_class", "Model")
	wrapper.set_meta("block_name", wrapper.name)
	wrapper.set_meta("source_asset_path", source_path)
	(target_parent as Node3D).add_child(wrapper, true)
	wrapper.global_position = _get_editor_drop_position(10.0)
	wrapper.add_child(source_scene, true)
	_apply_model_source_transform(source_scene, entry, source_entry)
	var mesh_nodes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_scene, mesh_nodes)
	if mesh_nodes.is_empty():
		wrapper.queue_free()
		return false
	var model_key := str(entry.get("id", entry.get("draft_id", source_path))).md5_text()
	var selected: Array[Node3D] = []
	for index in range(mesh_nodes.size()):
		var mesh_node := mesh_nodes[index]
		if mesh_node.mesh == null:
			continue
		mesh_node.add_to_group("studio_parts")
		mesh_node.set_meta("roblox_class", "MeshPart")
		mesh_node.set_meta("shape_type", "MeshPart")
		mesh_node.set_meta("block_name", mesh_node.name)
		mesh_node.set_meta("material_type", "Plastic")
		mesh_node.set_meta("can_collide", true)
		mesh_node.set_meta("transparency", 0.0)
		mesh_node.set_meta("source_asset_path", source_path)
		var active_material := mesh_node.get_active_material(0) as StandardMaterial3D
		if active_material != null:
			mesh_node.set_meta("bobux_color", active_material.albedo_color)
		_cache_exact_model_mesh(mesh_node, model_key, index)
		_ensure_mesh_materials_double_sided(mesh_node)
		_update_block_collision(mesh_node)
		selected.append(mesh_node)
	if selected.is_empty():
		wrapper.queue_free()
		return false
	_set_selection(selected)
	explorer_selected_node = wrapper
	_sync_explorer_selection()
	_refresh_explorer()
	_commit_editor_history("Insert exact model")
	if toolbar_status_label:
		toolbar_status_label.text = "Inserted original model geometry: %s" % wrapper.name
	return true

func _load_external_model_scene(source_path: String) -> Node3D:
	var extension := source_path.get_extension().to_lower()
	if extension in ["glb", "gltf"] and FileAccess.file_exists(source_path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(source_path, state) == OK:
			var scene := document.generate_scene(state) as Node3D
			RbxlMaterialCache.enable_embedded_vertex_colors(scene)
			return scene
	if extension == "obj" and FileAccess.file_exists(source_path):
		var obj_mesh_resource := RuntimeObjLoaderClass.load_mesh(source_path)
		if obj_mesh_resource is Mesh:
			var obj_root := Node3D.new()
			var obj_mesh := MeshInstance3D.new()
			obj_mesh.name = source_path.get_file().get_basename()
			obj_mesh.mesh = obj_mesh_resource as Mesh
			obj_root.add_child(obj_mesh)
			return obj_root
	if source_path.begins_with("res://") or source_path.begins_with("user://"):
		var loaded := ResourceLoader.load(source_path)
		if loaded is PackedScene:
			return (loaded as PackedScene).instantiate() as Node3D
		if loaded is Mesh:
			var mesh_root := Node3D.new()
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.name = source_path.get_file().get_basename()
			mesh_instance.mesh = loaded as Mesh
			mesh_root.add_child(mesh_instance)
			return mesh_root
	return null

func _apply_model_source_transform(source_scene: Node3D, entry: Dictionary, source_entry: Dictionary) -> void:
	var transform_data: Dictionary = {}
	for candidate in _model_metadata_candidates(entry, source_entry):
		if bool((candidate as Dictionary).get("canonical_transform_baked", false)):
			return
		if (candidate as Dictionary).get("source_model_transform", {}) is Dictionary:
			transform_data = ((candidate as Dictionary).get("source_model_transform", {}) as Dictionary).duplicate(true)
			if not transform_data.is_empty():
				break
	if transform_data.is_empty():
		_normalize_external_model_scene(source_scene)
		return
	source_scene.position = _vector3_from_variant(transform_data.get("position", Vector3.ZERO), Vector3.ZERO)
	source_scene.rotation_degrees = _vector3_from_variant(transform_data.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	source_scene.scale = _vector3_from_variant(transform_data.get("scale", Vector3.ONE), Vector3.ONE)

func _normalize_external_model_scene(source_scene: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_scene, meshes)
	if meshes.is_empty():
		return
	var bounds := AABB()
	var has_bounds := false
	for mesh_node in meshes:
		if mesh_node.mesh == null:
			continue
		var local_bounds := mesh_node.mesh.get_aabb()
		var relative := source_scene.global_transform.affine_inverse() * mesh_node.global_transform
		for corner in _aabb_corners(local_bounds):
			var point := relative * corner
			bounds = AABB(point, Vector3.ZERO) if not has_bounds else bounds.expand(point)
			has_bounds = true
	if not has_bounds:
		return
	var max_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if max_axis <= 0.001:
		return
	var uniform_scale := clampf(3.2 / max_axis, 0.04, 24.0)
	var center := bounds.get_center()
	source_scene.scale = Vector3.ONE * uniform_scale
	source_scene.position = Vector3(-center.x * uniform_scale, -bounds.position.y * uniform_scale, -center.z * uniform_scale)

func _aabb_corners(bounds: AABB) -> Array[Vector3]:
	var p := bounds.position
	var e := bounds.position + bounds.size
	return [
		Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z),
		Vector3(p.x, e.y, p.z), Vector3(p.x, p.y, e.z),
		Vector3(e.x, e.y, p.z), Vector3(e.x, p.y, e.z),
		Vector3(p.x, e.y, e.z), Vector3(e.x, e.y, e.z),
	]

func _cache_exact_model_mesh(mesh_node: MeshInstance3D, model_key: String, index: int) -> void:
	if mesh_node == null or mesh_node.mesh == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STUDIO_MODEL_CACHE_FOLDER))
	var mesh_copy := mesh_node.mesh.duplicate(true) as Mesh
	if mesh_copy == null:
		return
	for surface_index in range(mesh_copy.get_surface_count()):
		var material := mesh_node.get_active_material(surface_index)
		if material != null:
			var bundled := material.duplicate(true) as Material
			# Importer textures can retain external resource indices even with
			# FLAG_BUNDLE_RESOURCES. Embed their pixels in a fresh ImageTexture.
			for property in bundled.get_property_list():
				if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
				var value: Variant = bundled.get(property.name)
				if value is Texture2D:
					var bitmap: Image = value.get_image()
					if bitmap != null and not bitmap.is_empty(): bundled.set(property.name, ImageTexture.create_from_image(bitmap))
			mesh_copy.surface_set_material(surface_index, bundled)
	mesh_node.mesh = mesh_copy
	var resource_path := STUDIO_MODEL_CACHE_FOLDER.path_join("%s_%03d.res" % [model_key, index])
	if ResourceSaver.save(mesh_copy, resource_path, ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK:
		mesh_node.set_meta("bobux_mesh_resource_asset", resource_path)

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

func _calculate_model_parts_pivot(parts: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for part_variant in parts:
		if not (part_variant is Dictionary):
			continue
		var part := part_variant as Dictionary
		sum += _vector3_from_variant(part.get("position", Vector3.ZERO), Vector3.ZERO)
		count += 1
	if count <= 0:
		return Vector3.ZERO
	return sum / float(count)

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
		"color": _color_from_array(model_part.get("color", Color.WHITE), Color.WHITE),
		"material": "Plastic",
		"transparency": 0.0,
		"can_collide": bool(model_part.get("can_collide", true)),
		"deals_damage": false,
		"damage_amount": DEFAULT_BLOCK_DAMAGE,
		"is_spawn": false
	}

func _load_local_model_draft_entries(limit: int = 96) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var draft_root: String = _get_model_drafts_root_path()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(draft_root)):
		return result
	var dir := DirAccess.open(draft_root)
	if dir == null:
		return result
	dir.list_dir_begin()
	while result.size() < limit:
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
	var accent: Color = button.get_meta("accent_color", Color("#0066CC"))
	var label_text := _get_ribbon_button_label(button)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#DDEEFF") if active else Color("#FAFAFA")
	normal.border_color = accent if active else Color("#D0D0D0")
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 2
	normal.corner_radius_bottom_right = 2
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0

	var hover := normal.duplicate()
	hover.bg_color = Color("#CFE8FF") if active else Color("#EEF6FF")
	hover.border_color = Color("#2C8CD6")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#111111"))
	button.add_theme_color_override("font_hover_color", Color("#111111"))
	button.add_theme_color_override("font_pressed_color", Color("#111111"))
	button.add_theme_font_size_override("font_size", 11)
	_set_ribbon_button_content_visual(button, _get_ribbon_icon_color(label_text, active), Color("#111111"))
	button.button_pressed = active if button.toggle_mode else false

func _refresh_toolbar_states() -> void:
	for shape_name in shape_buttons.keys():
		var shape_active := false
		if shape_name == "Select":
			shape_active = current_editor_tool == "select"
		else:
			shape_active = current_editor_tool == "insert" and shape_name == current_shape
		_style_toolbar_button(shape_buttons[shape_name], shape_active)
	for mode_name in transform_mode_buttons.keys():
		_style_toolbar_button(transform_mode_buttons[mode_name], mode_name == current_editor_tool)

func _set_shape(shape_name: String) -> void:
	if roblox_terrain_editor != null and current_editor_tool == "terrain":
		roblox_terrain_editor.cancel_brush()
	current_shape = shape_name
	current_editor_tool = "select" if current_shape == "Select" else "insert"
	if current_shape != "Select":
		is_box_selecting = false
		_clear_selection_box_visual()
		if is_gizmo_dragging:
			_end_gizmo_drag()
	_refresh_toolbar_states()
	_update_transform_gizmo()
	_update_selection_status()

func _set_transform_mode(mode_name: String) -> void:
	if roblox_terrain_editor != null and current_editor_tool == "terrain":
		roblox_terrain_editor.cancel_brush()
	current_shape = "Select"
	current_transform_mode = mode_name
	current_editor_tool = mode_name
	_refresh_toolbar_states()
	_update_transform_gizmo()
	_update_selection_status()

# ===== UI: EXPLORER (Left Panel) =====
func _setup_roblox_data_model() -> void:
	# Build the live Roblox DataModel (game) as a SEPARATE node tree and
	# register the studio's block container as the Workspace alias. The
	# container is NOT reparented — it stays under World3D so the camera,
	# physics_object_picking, LuaScriptEngine path resolution and save/load all
	# keep working. The Explorer simply recurses into the alias to show parts.
	roblox_explorer = RobloxExplorerClass.new()
	roblox_explorer.set_filter_text(explorer_filter_text)
	roblox_properties = RobloxPropertiesClass.new()
	if data_model != null and is_instance_valid(data_model):
		roblox_data_model_ready = true
		return
	data_model = RobloxDataModelClass.new()
	data_model.name = "RobloxDataModel"
	data_model.set_meta("roblox_stud_scale", _get_workspace_stud_scale())
	# Attach the DataModel as a sibling of placement_parent (under World3D, but
	# NOT reparenting placement_parent itself).
	var world_host: Node = null
	if placement_parent:
		world_host = placement_parent.get_parent()
	if world_host == null:
		world_host = self # last-resort fallback
	world_host.add_child(data_model, true)
	# Register the block container as Workspace WITHOUT moving it.
	if placement_parent:
		placement_parent.set_meta("roblox_stud_scale", _get_workspace_stud_scale())
		data_model.register_workspace_alias(placement_parent)
	roblox_data_model_ready = true
	# The explorer was already created by _build_main_white_layout; populate it.
	if explorer_tree:
		_refresh_explorer()

func _build_explorer_panel() -> void:
	_refresh_explorer()

func _on_explorer_search_changed(text: String) -> void:
	explorer_filter_text = text.strip_edges()
	if roblox_explorer != null:
		roblox_explorer.set_filter_text(explorer_filter_text)
	_refresh_explorer()

var root_services: Dictionary = {}

func _refresh_explorer() -> void:
	if explorer_tree == null:
		return
	if roblox_data_model_ready and data_model != null and is_instance_valid(data_model):
		_refresh_explorer_from_data_model()
	else:
		_refresh_explorer_legacy()
	_sync_explorer_selection()

## Roblox-style Explorer: build the tree from the live DataModel node hierarchy.
## The recursive builder preserves collapsed/expanded state across rebuilds and
## tags every TreeItem with the underlying node's instance_id so selection,
## context menus and the Properties panel all route back to the real node.
func _refresh_explorer_from_data_model() -> void:
	roblox_explorer.show_runtime = studio_playtest_active
	roblox_explorer.rebuild(explorer_tree, data_model)
	# Rebuild the compatibility lookup: service name -> TreeItem. Several
	# legacy helpers (`_manifest_entry_service_name`, manifest population) key
	# off `root_services`, so we re-populate it after the rebuild.
	root_services = {}
	var hidden_root: TreeItem = explorer_tree.get_root()
	if hidden_root == null:
		return
	var service_item: TreeItem = hidden_root.get_first_child()
	while service_item != null:
		var svc_node_id = service_item.get_meta(RobloxExplorerClass.META_NODE_ID_KEY, -1)
		if svc_node_id != null and int(svc_node_id) > 0:
			var svc_node := instance_from_id(int(svc_node_id))
			if svc_node != null and bool(svc_node.get_meta("is_roblox_service", false)):
				var service_key := str(svc_node.get_meta("roblox_class", svc_node.name))
				root_services[service_key] = service_item
		service_item = service_item.get_next()
	# Imported manifest entries are installed as live DataModel nodes. Overlaying
	# virtual rows here would duplicate scripts, GUI and tools and make Explorer
	# actions target objects that do not exist.

## Fallback path used before the DataModel is wired up (e.g. if `_ready` order
## changes). Mirrors the original explorer layout: 14 virtual services + the
## studio_parts blocks under Workspace.
func _refresh_explorer_legacy() -> void:
	explorer_tree.clear()
	explorer_tree.hide_root = true
	var root := explorer_tree.create_item()

	root_services = {}
	var services := [
		"Workspace", "Players", "Lighting", "MaterialService", "ReplicatedFirst", 
		"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", 
		"StarterPack", "StarterPlayer", "Teams", "SoundService", "TextChatService"
	]

	for s in services:
		var item := explorer_tree.create_item(root)
		item.set_text(0, s)
		item.set_metadata(0, s)
		root_services[s] = item
		_set_item_icon(item, s)

	var ws_root = root_services["Workspace"]
	var parent = placement_parent if placement_parent else self
	for child in parent.get_children():
		if child.is_in_group("studio_parts") and not child.is_queued_for_deletion():
			var block_name: String = child.get_meta("block_name", child.name)
			var block_class := str(child.get_meta("shape_type", "Part"))
			if not _explorer_text_matches_filter(block_name, block_class):
				continue
			var item := explorer_tree.create_item(ws_root)
			item.set_text(0, block_name)
			item.set_metadata(0, child.get_instance_id())
			_set_item_icon(item, block_class)

			for subchild in child.get_children():
				if subchild.is_in_group("bobux_scripts"):
					var script_item := explorer_tree.create_item(item)
					script_item.set_text(0, subchild.name)
					script_item.set_metadata(0, subchild.get_instance_id())
					_set_item_icon(script_item, subchild.get_meta("script_type", "Script"))

	_populate_roblox_manifest_explorer()

func _explorer_text_matches_filter(display: String, roblox_class_name: String) -> bool:
	if explorer_filter_text.strip_edges().is_empty():
		return true
	var needle := explorer_filter_text.strip_edges().to_lower()
	return ("%s %s" % [display, roblox_class_name]).to_lower().find(needle) >= 0

func _populate_roblox_manifest_explorer() -> void:
	if current_roblox_place_manifest.is_empty() or explorer_tree == null:
		return
	var entries_by_ref: Dictionary = {}
	_add_manifest_entries_to_explorer_map(entries_by_ref, current_roblox_place_manifest.get("gui", []), "")
	_add_manifest_entries_to_explorer_map(entries_by_ref, current_roblox_place_manifest.get("tools", []), "StarterPack")
	_add_manifest_entries_to_explorer_map(entries_by_ref, current_roblox_place_manifest.get("scripts", []), "")
	_add_manifest_entries_to_explorer_map(entries_by_ref, current_roblox_place_manifest.get("storage_libraries", []), "")
	var children_by_parent: Dictionary = {}
	for ref_variant in entries_by_ref.keys():
		var ref := _normalize_roblox_manifest_ref(ref_variant)
		var entry: Dictionary = entries_by_ref[ref]
		var parent_ref := _normalize_roblox_manifest_ref(entry.get("parent_ref", ""))
		if parent_ref.is_empty() and entry.has("service_ref"):
			parent_ref = _normalize_roblox_manifest_ref(entry.get("service_ref", ""))
		if not children_by_parent.has(parent_ref):
			children_by_parent[parent_ref] = []
		(children_by_parent[parent_ref] as Array).append(ref)
	var service_entries: Dictionary = {}
	var services: Array = current_roblox_place_manifest.get("services", []) if current_roblox_place_manifest.get("services", []) is Array else []
	for service_variant in services:
		if service_variant is Dictionary:
			var service: Dictionary = service_variant
			var service_ref := _normalize_roblox_manifest_ref(service.get("ref", ""))
			var service_name := str(service.get("name", service.get("class", ""))).strip_edges()
			if not service_ref.is_empty() and not service_name.is_empty():
				service_entries[service_ref] = service_name
	for service_ref_variant in service_entries.keys():
		var service_ref := str(service_ref_variant)
		var service_name := str(service_entries[service_ref])
		var service_root: TreeItem = root_services.get(service_name) as TreeItem
		if service_root == null:
			continue
		_create_manifest_explorer_children(service_root, service_ref, entries_by_ref, children_by_parent, service_name, 0)
	for ref_variant in entries_by_ref.keys():
		var ref := _normalize_roblox_manifest_ref(ref_variant)
		var entry: Dictionary = entries_by_ref[ref]
		if bool(entry.get("_explorer_created", false)):
			continue
		var service_name := _manifest_entry_service_name(entry)
		var service_root: TreeItem = root_services.get(service_name) as TreeItem
		if service_root == null:
			service_root = root_services.get("ReplicatedStorage") as TreeItem
		if service_root != null:
			_create_manifest_explorer_item(service_root, ref, entry)

func _add_manifest_entries_to_explorer_map(entries_by_ref: Dictionary, raw_entries: Variant, fallback_service: String) -> void:
	if not (raw_entries is Array):
		return
	for entry_variant in raw_entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		var ref := _normalize_roblox_manifest_ref(entry.get("ref", ""))
		if ref.is_empty():
			continue
		entry["ref"] = ref
		entry["parent_ref"] = _normalize_roblox_manifest_ref(entry.get("parent_ref", ""))
		entry["root_ref"] = _normalize_roblox_manifest_ref(entry.get("root_ref", ""))
		if not fallback_service.is_empty() and str(entry.get("root_name", "")).strip_edges().is_empty():
			entry["root_name"] = fallback_service
		if entries_by_ref.has(ref):
			var existing: Dictionary = entries_by_ref[ref]
			for key in entry.keys():
				if not existing.has(key):
					existing[key] = entry[key]
			entries_by_ref[ref] = existing
		else:
			entries_by_ref[ref] = entry

func _create_manifest_explorer_children(parent_item: TreeItem, parent_ref: String, entries_by_ref: Dictionary,
		children_by_parent: Dictionary, service_name: String, depth: int) -> void:
	if depth > 32:
		return
	var children: Array = children_by_parent.get(parent_ref, [])
	children.sort_custom(func(a, b): return str(entries_by_ref.get(a, {}).get("name", "")).naturalnocasecmp_to(str(entries_by_ref.get(b, {}).get("name", ""))) < 0)
	for child_ref_variant in children:
		var child_ref := str(child_ref_variant)
		if not entries_by_ref.has(child_ref):
			continue
		var entry: Dictionary = entries_by_ref[child_ref]
		if not _manifest_entry_belongs_to_service(entry, service_name):
			continue
		var child_item := _create_manifest_explorer_item(parent_item, child_ref, entry)
		_create_manifest_explorer_children(child_item, child_ref, entries_by_ref, children_by_parent, service_name, depth + 1)

func _create_manifest_explorer_item(parent_item: TreeItem, ref: String, entry: Dictionary) -> TreeItem:
	var item := explorer_tree.create_item(parent_item)
	var roblox_class := str(entry.get("class", "Instance"))
	var display_name := str(entry.get("name", roblox_class)).strip_edges()
	if display_name.is_empty():
		display_name = roblox_class
	item.set_text(0, "%s  [%s]" % [display_name, roblox_class])
	item.set_metadata(0, "roblox_manifest:%s" % ref)
	_set_item_icon(item, roblox_class)
	entry["_explorer_created"] = true
	return item

func _manifest_entry_belongs_to_service(entry: Dictionary, service_name: String) -> bool:
	return _manifest_entry_service_name(entry) == service_name

func _manifest_entry_service_name(entry: Dictionary) -> String:
	for key in ["service_name", "root_name", "root_class", "parent_class"]:
		var value := str(entry.get(key, "")).strip_edges()
		if root_services.has(value):
			return value
	var roblox_class := str(entry.get("class", ""))
	if roblox_class in ["ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"]:
		return "StarterGui"
	if roblox_class == "Tool":
		return "StarterPack"
	if roblox_class in ["Script", "ModuleScript"]:
		return "ServerScriptService"
	if roblox_class == "LocalScript":
		return "StarterGui"
	return "ReplicatedStorage"

func _normalize_roblox_manifest_ref(raw: Variant) -> String:
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "<null>":
		return ""
	if text.ends_with(".0") and text.is_valid_float():
		text = str(int(round(text.to_float())))
	return text

func _highlight_in_explorer(_block: Node3D) -> void:
	_sync_explorer_selection()

func _sync_explorer_selection() -> void:
	if explorer_tree == null or syncing_explorer_selection:
		return

	var selected_ids: Dictionary = {}
	for block in _get_valid_selected_blocks():
		selected_ids[block.get_instance_id()] = true

	# When the live DataModel is active, route through the helper so selection
	# highlight works for any node (Parts, Scripts, Models, …), not only
	# Workspace blocks. Otherwise fall back to the legacy Workspace-only walk.
	if roblox_data_model_ready and roblox_explorer != null:
		var selected_nodes: Array = []
		for selected_part in _get_valid_selected_blocks():
			selected_nodes.append(selected_part)
		if explorer_selected_node != null and is_instance_valid(explorer_selected_node):
			selected_nodes.append(explorer_selected_node)
		syncing_explorer_selection = true
		roblox_explorer.sync_selection(explorer_tree, selected_nodes)
		syncing_explorer_selection = false
		return

	var ws_root: TreeItem = root_services.get("Workspace") as TreeItem
	if ws_root:
		var child_item: TreeItem = ws_root.get_first_child()
		while child_item:
			var instance_id_variant = child_item.get_metadata(0)
			var instance_id: int = int(instance_id_variant) if instance_id_variant != null else -1
			var block_node := instance_from_id(instance_id)
			var block_name: String = child_item.get_text(0).trim_prefix("[Selected] ")
			if block_node and block_node is Node3D:
				block_name = str(block_node.get_meta("block_name", block_node.name))
			if selected_ids.has(instance_id):
				child_item.set_text(0, "[Selected] " + block_name)
			else:
				child_item.set_text(0, block_name)
			child_item = child_item.get_next()

func _on_explorer_item_selected() -> void:
	if syncing_explorer_selection:
		return
	var selected_items: Array[TreeItem] = []
	var selected_cursor: TreeItem = explorer_tree.get_next_selected(null)
	while selected_cursor != null:
		selected_items.append(selected_cursor)
		selected_cursor = explorer_tree.get_next_selected(selected_cursor)
	if selected_items.is_empty():
		return
	var selected_parts: Array[Node3D] = []
	var selected_non_part: Node = null
	for selected_item in selected_items:
		var selected_metadata: Variant = selected_item.get_metadata(0)
		if not (selected_metadata is int):
			continue
		var selected_node := instance_from_id(int(selected_metadata))
		if selected_node == null or not is_instance_valid(selected_node):
			continue
		if selected_node.is_in_group("studio_parts") and selected_node is Node3D:
			selected_parts.append(selected_node as Node3D)
		else:
			selected_non_part = selected_node
	if not selected_parts.is_empty():
		explorer_selected_node = null
		_set_selection(selected_parts)
		return
	var selected: TreeItem = selected_items.back()
	var metadata: Variant = selected.get_metadata(0)
	# Live DataModel tree: metadata is the node's instance_id for every item.
	# Select it through the studio's selection pipeline so the gizmo, highlight
	# and Properties panel all update.
	if metadata is int:
		var node: Node = selected_non_part if selected_non_part != null else instance_from_id(int(metadata))
		if node == null or not is_instance_valid(node):
			return
		if node.is_in_group("studio_parts"):
			explorer_selected_node = null
			_select_block(node)
		else:
			# Non-part selection: clear block selection and refresh Properties so
			# the panel shows Script/Model/Light/Service properties.
			_set_selection([])
			explorer_selected_node = node
			_show_properties_for_node(node)
	elif metadata is String:
		# Legacy manifest/service rows (string metadata). Best-effort: clear the
		# block selection and surface a generic properties view.
		_set_selection([])

## Refresh the Properties panel for an arbitrary node (Part, Script, Model,
## service, …). Routes through the RobloxProperties helper when the live
## DataModel is active; otherwise no-ops so the legacy Block tab stays intact.
func _show_properties_for_node(node: Node) -> void:
	if not roblox_data_model_ready or roblox_properties == null:
		return
	if inspector_panel == null:
		return
	if properties_title_label != null:
		var roblox_class := str(node.get_meta("roblox_class", "Instance")) if node != null else ""
		var display_name := str(node.get_meta("block_name", node.name)) if node != null else ""
		properties_title_label.text = "Properties - %s \"%s\"" % [roblox_class, display_name] if node != null else "Properties"
	roblox_properties.build_into(inspector_panel, node, self)


func _on_properties_filter_changed(value: String) -> void:
	if roblox_properties == null:
		return
	roblox_properties.set_filter_text(value)
	var target := _get_selected_editor_node()
	if target == placement_parent and selected_block == null and explorer_selected_node == null:
		target = null
	_show_properties_for_node(target)

# ===== UI: INSPECTOR (Right Panel) =====
func _build_inspector_panel() -> void:
	# inspector_panel is already created in _build_main_white_layout
	if inspector_panel == null:
		return

	# === Roblox Studio Properties panel ===
	# Single clean container: content is rebuilt per-selection by
	# RobloxProperties (Data / Transform / Behavior / Appearance sections).
	# The legacy Block/Player/Atmosphere tabs were removed — Roblox Studio's
	# Properties panel does not have them. Player & atmosphere settings are
	# still applied to the map via _get_default_player_settings() etc., they
	# just live in the Ribbon / publish dialog instead.
	# `_build_properties_dock` already created the ScrollContainer and returned
	# its inner PropertiesContent VBox. Do not wrap it a second time: nested
	# expanding scroll views collapse the inner content to zero height.
	_clear_inspector()
	_apply_player_settings_to_ui(_get_default_player_settings())
	_apply_mode_settings_to_ui(_get_default_mode_settings())

	# FileDialogs for music/sky (kept here for the publish flow / atmospheric
	# settings callbacks — they are NOT part of the Properties panel itself).
	music_file_dialog = FileDialog.new()
	music_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	music_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	music_file_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio Files"])
	music_file_dialog.use_native_dialog = true
	music_file_dialog.title = "Add Music Tracks"
	music_file_dialog.file_selected.connect(_on_music_file_selected)
	music_file_dialog.files_selected.connect(_on_music_files_selected)
	add_child(music_file_dialog)

	sky_file_dialog = FileDialog.new()
	sky_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	sky_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	sky_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files"])
	sky_file_dialog.use_native_dialog = true
	sky_file_dialog.title = "Select Sky Image"
	sky_file_dialog.file_selected.connect(_on_sky_file_selected)
	add_child(sky_file_dialog)

func _clear_inspector() -> void:
	# When the live Roblox DataModel is active, the Properties panel is rebuilt
	# per-selection by RobloxProperties, so "clear" means rendering the empty
	# placeholder rather than touching the legacy widget handles.
	if roblox_data_model_ready and roblox_properties != null and inspector_panel != null:
		if properties_title_label != null:
			properties_title_label.text = "Properties"
		roblox_properties.build_into(inspector_panel, null, self)
		return
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
	# Live DataModel path: delegate to the categorized Roblox Properties panel
	# (Data / Transform / Behavior / Appearance) so Parts show the same fields
	# as Roblox Studio, including Rotation and Anchored which the legacy panel
	# never exposed.
	if roblox_data_model_ready and roblox_properties != null and inspector_panel != null:
		_show_properties_for_node(selected_block)
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
		selected_block.set_meta("bobux_color", Color(color.r, color.g, color.b, 1.0))
		var new_mat := _create_material(color, mat_type, transparency)
		mesh_block.mesh.surface_set_material(0, new_mat)
		_refresh_special_block_visuals(mesh_block)

func _rebuild_block_material(block: MeshInstance3D) -> void:
	var color := _get_bobux_block_color(block, Color.WHITE)
	var mat_type: String = block.get_meta("material_type", "Plastic")
	var transparency: float = block.get_meta("transparency", 0.0)
	var new_mat := _create_material(color, mat_type, transparency)
	var reflectance := clampf(float(block.get_meta("Reflectance", 0.0)), 0.0, 1.0)
	new_mat.metallic = reflectance
	new_mat.metallic_specular = lerpf(0.5, 1.0, reflectance)
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
	var settings := _get_current_player_settings()
	if studio_playtest_player != null and is_instance_valid(studio_playtest_player) \
	and studio_playtest_player.has_method("apply_movement_settings"):
		studio_playtest_player.call("apply_movement_settings", settings)
	if toolbar_status_label:
		toolbar_status_label.text = "Player: %.1f speed, x%.2f sprint, %.1f jump" % [
			float(settings.get("move_speed", DEFAULT_PLAYER_MOVE_SPEED)),
			float(settings.get("sprint_multiplier", DEFAULT_PLAYER_SPRINT_MULTIPLIER)),
			float(settings.get("jump_velocity", DEFAULT_PLAYER_JUMP_VELOCITY)),
		]

func _get_default_player_settings() -> Dictionary:
	return {
		"movement_version": 2,
		"move_speed": DEFAULT_PLAYER_MOVE_SPEED,
		"sprint_multiplier": DEFAULT_PLAYER_SPRINT_MULTIPLIER,
		"jump_velocity": DEFAULT_PLAYER_JUMP_VELOCITY
	}

func _get_current_player_settings() -> Dictionary:
	var settings := _get_default_player_settings()
	settings.merge(authored_player_settings, true)
	if player_move_speed_spin:
		settings["move_speed"] = player_move_speed_spin.value
	if player_sprint_multiplier_spin:
		settings["sprint_multiplier"] = player_sprint_multiplier_spin.value
	if player_jump_velocity_spin:
		settings["jump_velocity"] = player_jump_velocity_spin.value
	return settings

func _apply_player_settings_to_ui(settings: Dictionary) -> void:
	settings = preload("res://scripts/player/movement_settings.gd").normalize(settings)
	var merged_settings := _get_default_player_settings()
	for key in settings.keys():
		merged_settings[key] = settings[key]
	authored_player_settings = merged_settings.duplicate(true)
	if player_move_speed_spin:
		player_move_speed_spin.set_value_no_signal(float(merged_settings.get("move_speed", DEFAULT_PLAYER_MOVE_SPEED)))
	if player_sprint_multiplier_spin:
		player_sprint_multiplier_spin.set_value_no_signal(float(merged_settings.get("sprint_multiplier", DEFAULT_PLAYER_SPRINT_MULTIPLIER)))
	if player_jump_velocity_spin:
		player_jump_velocity_spin.set_value_no_signal(float(merged_settings.get("jump_velocity", DEFAULT_PLAYER_JUMP_VELOCITY)))

func _on_music_browse_pressed() -> void:
	if _is_studio_editing_locked(): return
	if not is_instance_valid(studio_music_dialog):
		studio_music_dialog = AcceptDialog.new()
		studio_music_dialog.title = "Фоновая музыка режима"
		studio_music_dialog.ok_button_text = "Готово"
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(480, 230)
		var info := Label.new()
		info.text = "Треки сохраняются с картой и передаются другим игрокам."
		column.add_child(info)
		var actions := HBoxContainer.new()
		column.add_child(actions)
		var browse := Button.new()
		browse.text = "Добавить MP3 / OGG / WAV"
		browse.pressed.connect(func(): music_file_dialog.popup_centered(Vector2(720, 420)))
		actions.add_child(browse)
		var stop := Button.new()
		stop.text = "Остановить"
		stop.pressed.connect(func(): if is_instance_valid(studio_music_player): studio_music_player.stop())
		actions.add_child(stop)
		atmosphere_music_volume_label = Label.new()
		column.add_child(atmosphere_music_volume_label)
		atmosphere_music_volume_slider = HSlider.new()
		atmosphere_music_volume_slider.max_value = 100
		atmosphere_music_volume_slider.value = studio_music_volume * 100
		atmosphere_music_volume_slider.value_changed.connect(_on_music_volume_changed)
		column.add_child(atmosphere_music_volume_slider)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 150
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(scroll)
		atmosphere_music_list = VBoxContainer.new()
		atmosphere_music_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(atmosphere_music_list)
		studio_music_dialog.add_child(column)
		add_child(studio_music_dialog)
		_on_music_volume_changed(studio_music_volume * 100)
	_rebuild_music_track_list()
	studio_music_dialog.popup_centered(Vector2i(600, 340))

func _play_studio_music(index: int) -> void:
	if current_music_source_paths.is_empty(): return
	studio_music_track = posmod(index, current_music_source_paths.size())
	var stream := AudioFileLoader.load_stream(current_music_source_paths[studio_music_track], true)
	if stream == null:
		if toolbar_status_label: toolbar_status_label.text = "Не удалось прочитать аудио: " + current_music_source_paths[studio_music_track].get_file()
		return
	if not is_instance_valid(studio_music_player):
		studio_music_player = AudioStreamPlayer.new()
		studio_music_player.name = "StudioModeMusic"
		add_child(studio_music_player)
		studio_music_player.finished.connect(func():
			if studio_playtest_active: _play_studio_music(studio_music_track + 1)
		)
	studio_music_player.stream = stream
	studio_music_player.volume_db = linear_to_db(maxf(studio_music_volume, 0.0001))
	studio_music_player.play()

func _on_sky_browse_pressed() -> void:
	if sky_file_dialog:
		sky_file_dialog.popup_centered(Vector2(720, 420))

func _on_music_file_selected(path: String) -> void:
	if AudioFileLoader.load_stream(path, false) == null:
		if toolbar_status_label: toolbar_status_label.text = "Файл не является поддерживаемым аудио."
		return
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
		if AudioFileLoader.load_stream(clean_path, false) == null:
			skipped += 1
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
	if is_instance_valid(studio_music_player): studio_music_player.stop()
	_refresh_atmosphere_path_labels()

func _on_sky_clear_pressed() -> void:
	current_sky_source_path = ""
	_apply_editor_sky_preview()
	_refresh_atmosphere_path_labels()

func _on_music_volume_changed(value: float) -> void:
	studio_music_volume = clampf(value / 100.0, 0, 1)
	if is_instance_valid(studio_music_player): studio_music_player.volume_db = linear_to_db(maxf(studio_music_volume, 0.0001))
	if atmosphere_music_volume_label:
		atmosphere_music_volume_label.text = "Volume: %d%%" % roundi(value)

func _get_default_mode_settings() -> Dictionary:
	return {
		"music_playlist": [],
		"music_volume": DEFAULT_MODE_MUSIC_VOLUME,
		"skybox_file": "",
		"roblox_sound_assets": [],
		"roblox_environment": {}
	}

func _apply_mode_settings_to_ui(settings: Dictionary, folder: String = "") -> void:
	var merged_settings := _get_default_mode_settings()
	for key in settings.keys():
		merged_settings[key] = settings[key]
	studio_music_volume = clampf(float(merged_settings.get("music_volume", DEFAULT_MODE_MUSIC_VOLUME)), 0, 1)

	current_music_source_paths.clear()
	current_sky_source_path = ""
	current_imported_sound_assets.clear()
	current_roblox_environment_settings.clear()
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
	if merged_settings.get("roblox_environment", {}) is Dictionary:
		current_roblox_environment_settings = (merged_settings.get("roblox_environment", {}) as Dictionary).duplicate(true)

	if atmosphere_music_volume_slider:
		atmosphere_music_volume_slider.set_value_no_signal(clampf(float(merged_settings.get("music_volume", DEFAULT_MODE_MUSIC_VOLUME)), 0.0, 1.0) * 100.0)
	_on_music_volume_changed(studio_music_volume * 100.0)
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
		empty_label.text = "Добавьте MP3, OGG или WAV. Треки будут играть по очереди."
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
	var listen := Button.new()
	listen.text = "▶"
	listen.tooltip_text = "Прослушать"
	listen.pressed.connect(_play_studio_music.bind(index))
	row.add_child(listen)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.custom_minimum_size = Vector2(72, 24)
	remove_button.focus_mode = Control.FOCUS_NONE
	remove_button.pressed.connect(_remove_music_track_at.bind(index))
	row.add_child(remove_button)
	return row

func _apply_editor_sky_preview() -> void:
	var env_node := get_node_or_null("SubViewportContainer/SubViewport/World3D/WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	if current_sky_source_path.is_empty():
		env_node.environment.sky = null
		if not current_roblox_environment_settings.is_empty():
			_apply_imported_roblox_environment_preview()
		else:
			_apply_roblox_procedural_sky_to_environment(env_node.environment, Color(0.52, 0.76, 0.96))
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

func _collect_roblox_environment_settings() -> Dictionary:
	var env_node := get_node_or_null("SubViewportContainer/SubViewport/World3D/WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = get_node_or_null("WorldEnvironment") as WorldEnvironment
	var settings: Dictionary = {}
	if has_meta("roblox_lighting_properties"):
		settings["lighting"] = (get_meta("roblox_lighting_properties") as Dictionary).duplicate(true) if get_meta("roblox_lighting_properties") is Dictionary else {}
	if has_meta("roblox_sky_properties"):
		settings["sky"] = (get_meta("roblox_sky_properties") as Dictionary).duplicate(true) if get_meta("roblox_sky_properties") is Dictionary else {}
	if has_meta("roblox_atmosphere_properties"):
		settings["atmosphere"] = (get_meta("roblox_atmosphere_properties") as Dictionary).duplicate(true) if get_meta("roblox_atmosphere_properties") is Dictionary else {}
	if env_node != null and env_node.environment != null:
		var env := env_node.environment
		settings["background_color"] = _color_to_array(env.background_color)
		settings["ambient_color"] = _color_to_array(env.ambient_light_color)
		settings["ambient_energy"] = env.ambient_light_energy
		settings["glow_enabled"] = env.glow_enabled
		settings["glow_intensity"] = env.glow_intensity
		settings["glow_bloom"] = env.glow_bloom
		settings["fog_enabled"] = bool(env.get("fog_enabled"))
		settings["fog_color"] = _color_to_array(env.get("fog_light_color") as Color if env.get("fog_light_color") is Color else Color(0.78, 0.78, 0.78))
		settings["fog_density"] = float(env.get("fog_density")) if env.get("fog_density") != null else 0.0
	return settings

func _collect_roblox_place_manifest_from_import() -> Dictionary:
	if has_meta("roblox_place_manifest") and get_meta("roblox_place_manifest") is Dictionary:
		return (get_meta("roblox_place_manifest") as Dictionary).duplicate(false)
	return {}

func _refresh_roblox_gui_preview() -> void:
	roblox_gui_preview_generation += 1
	var generation := roblox_gui_preview_generation
	if viewport_container_node == null or not is_instance_valid(viewport_container_node):
		return
	var play_interactive := studio_playtest_active
	if not play_interactive and not studio_gui_preview_enabled:
		_clear_roblox_gui_preview()
		return
	var gui_root := await RobloxGuiRuntime.apply_manifest_async(viewport_container_node, current_roblox_place_manifest, {
		"root_name": "RobloxStudioGuiPreview",
		"replace": true,
		"ignore_mouse": not play_interactive,
		"editor_preview": not play_interactive,
		"fit_to_viewport": true,
		"design_size": [1366.0, 768.0],
		"editor_preview_max_alpha": 1.0,
		"suppress_fullscreen_blockers": true,
		"suppress_neutral_fullscreen_frames": true,
		"draw_gui": true,
		"draw_tools": false,
		"z_index": 500
	}, 96)
	if generation != roblox_gui_preview_generation:
		if gui_root != null and is_instance_valid(gui_root):
			gui_root.queue_free()
		return
	if play_interactive and gui_root != null and LuaScriptEngine != null and LuaScriptEngine.has_method("bind_gui_controls"):
		var bind_report: Dictionary = LuaScriptEngine.bind_gui_controls(gui_root, placement_parent)
		gui_root.set_meta("bobux_gui_bind_report", bind_report)


func _on_data_model_gui_changed() -> void:
	if data_model == null or not data_model.has_method("build_manifest"):
		return
	var live_manifest: Variant = data_model.call("build_manifest", current_roblox_place_manifest)
	if live_manifest is Dictionary:
		current_roblox_place_manifest = (live_manifest as Dictionary).duplicate(false)
	_refresh_roblox_gui_preview()

func _clear_roblox_gui_preview() -> void:
	roblox_gui_preview_generation += 1
	if viewport_container_node == null or not is_instance_valid(viewport_container_node):
		return
	RobloxGuiRuntime.clear_from(viewport_container_node, "RobloxStudioGuiPreview")

func _install_roblox_manifest_data_model_preview() -> void:
	if current_roblox_place_manifest.is_empty():
		return
	if LuaScriptEngine == null or not LuaScriptEngine.has_method("install_roblox_manifest"):
		return
	if data_model != null and data_model.has_method("clear_services"):
		data_model.clear_services()
	var context_node: Node = placement_parent if placement_parent != null else self
	var preview_manifest := preload("res://addons/roblox_runtime/roblox_manifest_assets.gd").resolve(current_roblox_place_manifest, current_map_folder)
	if toolbar_status_label:
		toolbar_status_label.text = "Building Roblox DataModel..."
	var result: Dictionary = {}
	if LuaScriptEngine.has_method("install_roblox_manifest_async"):
		result = await LuaScriptEngine.install_roblox_manifest_async(preview_manifest, context_node, 384)
	else:
		result = LuaScriptEngine.install_roblox_manifest(preview_manifest, context_node)
	if not bool(result.get("ok", false)):
		push_warning("[Studio] Roblox manifest DataModel preview failed: %s" % str(result.get("error", "unknown error")))
	elif toolbar_status_label:
		toolbar_status_label.text = "DataModel ready: %d object(s), %d relationship(s)" % [
			int(result.get("created", 0)), int(result.get("reparented", 0))
		]
	_restore_authored_terrain()
	_refresh_explorer()

func _restore_authored_terrain() -> void:
	if placement_parent == null:
		return
	if roblox_terrain_editor == null:
		roblox_terrain_editor = RobloxTerrainEditorClass.new()
	var restore_result: Dictionary = roblox_terrain_editor.restore(self, placement_parent)
	if bool(restore_result.get("ok", false)) and toolbar_status_label != null:
		toolbar_status_label.text = "Terrain restored: %d voxel cell(s)" % int(restore_result.get("cells", 0))

func _install_imported_roblox_scripts_as_nodes() -> void:
	if current_roblox_place_manifest.is_empty() or data_model == null:
		return
	_clear_imported_roblox_script_nodes()
	var scripts: Array = current_roblox_place_manifest.get("scripts", []) if current_roblox_place_manifest.get("scripts", []) is Array else []
	for script_variant in scripts:
		if not (script_variant is Dictionary):
			continue
		var script_data: Dictionary = script_variant
		var script_class := str(script_data.get("class", "Script")).strip_edges()
		if not script_class in ["Script", "LocalScript", "ModuleScript"]:
			continue
		var script_name := str(script_data.get("name", script_class)).strip_edges()
		if script_name.is_empty():
			script_name = script_class
		var service_name := _roblox_script_service_for_manifest_entry(script_data)
		var script_parent: Node = _roblox_service_node_for_imported_script(service_name)
		if script_parent == null:
			continue
		var script_node := RobloxDataModelClass.create_instance(script_class, script_name)
		script_node.add_to_group("bobux_scripts")
		script_node.add_to_group("imported_roblox_scripts")
		script_node.set_meta("script_type", script_class)
		script_node.set_meta("code", str(script_data.get("source", "")))
		script_node.set_meta("disabled", bool(script_data.get("disabled", false)))
		script_node.set_meta("roblox_ref", str(script_data.get("ref", "")))
		script_node.set_meta("roblox_parent_ref", str(script_data.get("parent_ref", "")))
		script_node.set_meta("roblox_root_name", str(script_data.get("root_name", "")))
		script_parent.add_child(script_node, true)
	var seen_refs: Dictionary = {}
	_dedupe_imported_roblox_script_nodes(data_model, seen_refs)

func _clear_imported_roblox_script_nodes() -> void:
	if data_model == null:
		return
	_clear_imported_roblox_script_nodes_recursive(data_model)

func _clear_imported_roblox_script_nodes_recursive(root: Node) -> void:
	for child in root.get_children():
		if child.is_in_group("imported_roblox_scripts"):
			root.remove_child(child)
			child.free()
		else:
			_clear_imported_roblox_script_nodes_recursive(child)

func _dedupe_imported_roblox_script_nodes(root: Node, seen_refs: Dictionary) -> void:
	for child in root.get_children():
		if child.is_in_group("imported_roblox_scripts"):
			var ref := str(child.get_meta("roblox_ref", "")).strip_edges()
			if not ref.is_empty() and seen_refs.has(ref):
				root.remove_child(child)
				child.free()
				continue
			if not ref.is_empty():
				seen_refs[ref] = true
		_dedupe_imported_roblox_script_nodes(child, seen_refs)

func _roblox_script_service_for_manifest_entry(entry: Dictionary) -> String:
	for key in ["root_name", "root_class", "parent_class"]:
		var value := str(entry.get(key, "")).strip_edges()
		if not value.is_empty() and data_model != null and data_model.has_method("has_service") and data_model.has_service(value):
			return value
	var script_class := str(entry.get("class", "Script"))
	if script_class == "LocalScript":
		var parent_class := str(entry.get("parent_class", ""))
		if parent_class == "StarterPlayerScripts":
			return "StarterPlayer"
		if parent_class == "StarterPack":
			return "StarterPack"
		return "StarterGui"
	if script_class == "ModuleScript":
		return "ReplicatedStorage"
	return "ServerScriptService"

func _roblox_service_node_for_imported_script(service_name: String) -> Node:
	if data_model == null:
		return null
	var service: Node = data_model.ensure_service(service_name)
	if service_name == "StarterPlayer":
		var scripts := service.get_node_or_null("StarterPlayerScripts")
		if scripts != null:
			return scripts
	return service

func _apply_imported_roblox_environment_preview() -> void:
	var env_node := get_node_or_null("SubViewportContainer/SubViewport/World3D/WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		return
	if env_node.environment == null:
		env_node.environment = Environment.new()
	_apply_roblox_environment_settings_to_environment(env_node.environment, current_roblox_environment_settings)

func _apply_roblox_environment_settings_to_environment(env: Environment, settings: Dictionary) -> void:
	var sky_color := _color_from_array(settings.get("background_color", [0.52, 0.76, 0.96]), Color(0.52, 0.76, 0.96))
	if settings.has("lighting") and settings["lighting"] is Dictionary and not bool(settings.get("custom_sky_color", false)):
		var lighting: Dictionary = settings["lighting"]
		sky_color = _roblox_sky_color_for_hour(_hour_from_lighting_props(lighting))
	if settings.has("atmosphere") and settings["atmosphere"] is Dictionary:
		var atmosphere: Dictionary = settings["atmosphere"]
		var density := clampf(float(atmosphere.get("Density", 0.0)), 0.0, 1.0)
		sky_color = sky_color.lerp(_color_from_array(atmosphere.get("Color", [0.78, 0.78, 0.78]), Color(0.78, 0.78, 0.78)), density * 0.25)
	if not (settings.has("sky") and settings["sky"] is Dictionary and RobloxSkyMaterial.apply_skybox_from_properties(env, settings["sky"], sky_color)):
		_apply_roblox_procedural_sky_to_environment(env, sky_color)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _color_from_array(settings.get("ambient_color", [0.56, 0.66, 0.78]), Color(0.56, 0.66, 0.78))
	env.ambient_light_energy = clampf(float(settings.get("ambient_energy", 0.58)), 0.0, 2.0)
	env.glow_enabled = bool(settings.get("glow_enabled", env.glow_enabled))
	env.glow_intensity = clampf(float(settings.get("glow_intensity", env.glow_intensity)), 0.0, 2.0)
	env.glow_bloom = clampf(float(settings.get("glow_bloom", env.glow_bloom)), 0.0, 1.0)
	env.set("fog_enabled", bool(settings.get("fog_enabled", false)))
	env.set("fog_light_color", _color_from_array(settings.get("fog_color", [0.78, 0.78, 0.78]), Color(0.78, 0.78, 0.78)))
	env.set("fog_density", clampf(float(settings.get("fog_density", 0.0)), 0.0, 0.05))

func _apply_roblox_procedural_sky_to_environment(env: Environment, sky_color: Color) -> void:
	RobloxSkyMaterial.apply_to_environment(env, sky_color)

func _color_to_array(color: Color) -> Array[float]:
	return [color.r, color.g, color.b]

func _color_from_array(raw: Variant, fallback: Color) -> Color:
	if raw is Color:
		return raw
	if raw is String:
		var clean := (raw as String).strip_edges()
		if clean.begins_with("#"):
			clean = clean.substr(1)
		if clean.length() == 6 or clean.length() == 8:
			return Color.html(clean)
	if raw is Array:
		var arr := raw as Array
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
	if raw is Dictionary:
		var dict := raw as Dictionary
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

func _color_from_block_data(block_data: Dictionary, fallback: Color) -> Color:
	var has_roblox_color := _block_data_has_roblox_color(block_data)
	var roblox_color := _roblox_color_from_block_data(block_data, fallback) if has_roblox_color else fallback
	for key in ["color", "Color", "colour", "albedo", "albedo_color", "Color3", "Color3uint8"]:
		if block_data.has(key):
			var direct_color := _color_from_array(block_data.get(key), fallback)
			if has_roblox_color and _is_default_white_color(direct_color) and not _is_default_white_color(roblox_color):
				return roblox_color
			return direct_color
	if block_data.has("cr") or block_data.has("cg") or block_data.has("cb"):
		var r := float(block_data.get("cr", fallback.r))
		var g := float(block_data.get("cg", fallback.g))
		var b := float(block_data.get("cb", fallback.b))
		var a := float(block_data.get("ca", fallback.a))
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		var rgba_color := Color(r, g, b, a)
		if has_roblox_color and _is_default_white_color(rgba_color) and not _is_default_white_color(roblox_color):
			return roblox_color
		return rgba_color
	if has_roblox_color:
		return roblox_color
	return fallback

func _block_data_has_roblox_color(block_data: Dictionary) -> bool:
	if not (block_data.get("roblox_properties", {}) is Dictionary):
		return false
	var props: Dictionary = block_data.get("roblox_properties", {})
	for key in ["Color", "Color3", "Color3uint8", "BrickColor", "BrickColorId", "brick_color"]:
		for candidate in props.keys():
			if str(candidate).to_lower() == key.to_lower():
				return true
	return false

func _roblox_color_from_block_data(block_data: Dictionary, fallback: Color) -> Color:
	if not (block_data.get("roblox_properties", {}) is Dictionary):
		return fallback
	return RbxlMaterialCache.part_color_from_properties(block_data.get("roblox_properties", {}))

func _is_default_white_color(color: Color) -> bool:
	return color.r >= 0.985 and color.g >= 0.985 and color.b >= 0.985

func _should_apply_saved_roblox_block_material(block_data: Dictionary) -> bool:
	if not (block_data.get("roblox_properties", {}) is Dictionary):
		return false
	# Studio-created Bobux parts also carry `roblox_class=Part` so they can live
	# in the DataModel. That identity alone is not an imported Roblox material.
	# Feeding an empty property bag to RbxlMaterialCache produces Roblox's
	# default medium-gray and used to overwrite the part's saved Bobux color.
	var properties: Dictionary = block_data.get("roblox_properties", {})
	if properties.is_empty():
		return false
	if _block_data_has_explicit_roblox_identity(block_data):
		return true
	if _block_data_has_legacy_bobux_color(block_data):
		return false
	return true

func _block_data_has_explicit_roblox_identity(block_data: Dictionary) -> bool:
	for key in [
		"roblox_ref", "roblox_class", "roblox_material_id",
		"roblox_mesh_id", "roblox_texture_id",
		"roblox_mesh_exact_asset", "roblox_mesh_json_asset",
		"roblox_texture_asset_file", "roblox_proxy_geometry",
		"roblox_mesh_deferred", "roblox_special_mesh"
	]:
		if not block_data.has(key):
			continue
		var value: Variant = block_data.get(key)
		if value is Dictionary:
			if not (value as Dictionary).is_empty():
				return true
		elif value is Array:
			if not (value as Array).is_empty():
				return true
		elif not str(value).strip_edges().is_empty():
			return true
	var source_text: String = str(block_data.get("source", block_data.get("import_source", ""))).strip_edges().to_lower()
	return source_text.contains("roblox") or source_text.contains("rbxl")

func _block_data_has_legacy_bobux_color(block_data: Dictionary) -> bool:
	if block_data.has("cr") or block_data.has("cg") or block_data.has("cb"):
		return true
	for key in ["color", "colour", "albedo", "albedo_color"]:
		if block_data.has(key):
			return true
	return false

func _get_bobux_block_color(block: Node, fallback: Color = Color.WHITE) -> Color:
	if block == null:
		return fallback
	if block.has_meta("bobux_color"):
		var meta_color: Variant = block.get_meta("bobux_color")
		if meta_color is Color:
			return meta_color
		return _color_from_array(meta_color, fallback)
	if block is MeshInstance3D:
		var material := (block as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if material != null:
			return Color(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, material.albedo_color.a)
	return fallback

func _hour_from_time_of_day(value: String) -> float:
	var parts := value.split(":")
	if parts.is_empty():
		return 14.0
	return clampf(float(parts[0]), 0.0, 24.0)

func _hour_from_lighting_props(props: Dictionary) -> float:
	if props.has("ClockTime"):
		return clampf(float(props.get("ClockTime", 14.0)), 0.0, 24.0)
	return _hour_from_time_of_day(str(props.get("TimeOfDay", "14:00:00")))

func _roblox_sky_color_for_hour(hour: float) -> Color:
	var t := clampf(absf(hour - 12.0) / 12.0, 0.0, 1.0)
	return Color(0.52, 0.76, 0.96).lerp(Color(0.38, 0.50, 0.74), t * 0.55)

func _collect_mode_settings_for_save(folder: String) -> Dictionary:
	var settings := _get_default_mode_settings()
	var music_volume_percent := studio_music_volume * 100.0
	settings["music_volume"] = clampf(float(music_volume_percent) / 100.0, 0.0, 1.0)
	settings["music_playlist"] = _store_mode_playlist_files(current_music_source_paths, folder)
	settings["skybox_file"] = _store_mode_asset_file(current_sky_source_path, folder, MODE_SKY_FILE_BASENAME)
	settings["roblox_sound_assets"] = current_imported_sound_assets.duplicate(true)
	if not current_roblox_environment_settings.is_empty():
		settings["roblox_environment"] = current_roblox_environment_settings.duplicate(true)
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
	var texture_index: int = 1
	for object_index in range(objects.size()):
		var data: Dictionary = objects[object_index]
		var runtime_class := str(data.get("class", ""))
		match runtime_class:
			"Sound":
				var source_path := _runtime_object_asset_source_path(data, folder)
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
			"Decal", "Texture":
				var source_path := _runtime_object_asset_source_path(data, folder)
				if source_path.is_empty():
					continue
				var stored_file := str(stored_by_source.get(source_path, "")).strip_edges()
				if stored_file.is_empty():
					stored_file = _store_mode_asset_file(source_path, folder, "rbxl_texture_%02d" % texture_index)
					if stored_file.is_empty():
						continue
					stored_by_source[source_path] = stored_file
					texture_index += 1
				data["file"] = stored_file
				data["resolved_path"] = stored_file
				data["path"] = stored_file
			_:
				continue
		if object_index > 0 and object_index % 128 == 0:
			await get_tree().process_frame

func _store_manifest_asset_files(manifest: Dictionary, folder: String) -> void:
	var stored := {}
	for section in ["instances", "tools", "gui", "storage_libraries"]:
		for entry in manifest.get(section, []):
			var props: Dictionary = entry.get("properties", {})
			for key in ["BobuxMeshResource", "SoundId"]:
				var source := _resolve_existing_file_path_for_folder(str(props.get(key, "")), current_map_folder)
				if source.is_empty(): continue
				if not stored.has(source):
					stored[source] = _store_mode_asset_file(source, folder, "manifest_asset_%04d" % stored.size())
				if not str(stored[source]).is_empty(): props[key] = stored[source]

func _store_block_asset_files(blocks: Array, folder: String) -> void:
	var stored_by_source: Dictionary = {}
	var mesh_index: int = 1
	var bobux_mesh_index: int = 1
	var texture_index: int = 1
	for block_index in range(blocks.size()):
		var block_variant: Variant = blocks[block_index]
		if not (block_variant is Dictionary):
			continue
		var data: Dictionary = block_variant
		var bobux_mesh_source := _resolve_existing_file_path_for_folder(str(data.get("bobux_mesh_resource_asset", "")), folder)
		if not bobux_mesh_source.is_empty():
			var stored_bobux_mesh := str(stored_by_source.get(bobux_mesh_source, "")).strip_edges()
			if stored_bobux_mesh.is_empty():
				stored_bobux_mesh = _store_mode_asset_file(bobux_mesh_source, folder, "bobux_model_mesh_%03d" % bobux_mesh_index)
				if not stored_bobux_mesh.is_empty():
					stored_by_source[bobux_mesh_source] = stored_bobux_mesh
					bobux_mesh_index += 1
			if not stored_bobux_mesh.is_empty():
				data["bobux_mesh_resource_asset"] = stored_bobux_mesh
		var mesh_source := _block_mesh_asset_source_path(data, folder)
		if not mesh_source.is_empty():
			var stored_mesh := str(stored_by_source.get(mesh_source, "")).strip_edges()
			if stored_mesh.is_empty():
				stored_mesh = _store_mode_asset_file(mesh_source, folder, "rbxl_mesh_%02d" % mesh_index)
				if not stored_mesh.is_empty():
					stored_by_source[mesh_source] = stored_mesh
					mesh_index += 1
			if not stored_mesh.is_empty():
				data["roblox_mesh_json_asset"] = stored_mesh
		var texture_source := _block_texture_asset_source_path(data, folder)
		if not texture_source.is_empty():
			var stored_texture := str(stored_by_source.get(texture_source, "")).strip_edges()
			if stored_texture.is_empty():
				stored_texture = _store_mode_asset_file(texture_source, folder, "rbxl_mesh_texture_%02d" % texture_index)
				if not stored_texture.is_empty():
					stored_by_source[texture_source] = stored_texture
					texture_index += 1
			if not stored_texture.is_empty():
				data["roblox_texture_asset_file"] = stored_texture
		if block_index > 0 and block_index % 128 == 0:
			await get_tree().process_frame

func _block_mesh_asset_source_path(data: Dictionary, folder: String) -> String:
	var file_name := str(data.get("roblox_mesh_json_asset", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := _resolve_existing_file_path_for_folder(file_name, folder)
		if not resolved.is_empty():
			return resolved
		var cache_path := ProjectSettings.globalize_path("user://rbxl_assets/%s" % file_name.get_file())
		if FileAccess.file_exists(cache_path):
			return cache_path
	var mesh_id := _block_mesh_asset_id(data)
	if not mesh_id.is_empty():
		var cache_mesh := ProjectSettings.globalize_path("user://rbxl_assets/%s.mesh.json" % mesh_id)
		if FileAccess.file_exists(cache_mesh):
			return cache_mesh
	return ""

func _block_texture_asset_source_path(data: Dictionary, folder: String) -> String:
	var file_name := str(data.get("roblox_texture_asset_file", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := _resolve_existing_file_path_for_folder(file_name, folder)
		if not resolved.is_empty():
			return resolved
	var texture_id := _block_texture_asset_id(data)
	if texture_id.is_empty():
		return ""
	for ext in ["asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp", "png", "jpg", "jpeg", "webp"]:
		var cache_texture := ProjectSettings.globalize_path("user://rbxl_assets/%s.%s" % [texture_id, ext])
		if _texture_file_has_supported_magic(cache_texture):
			return cache_texture
	return ""

func _sanitize_numeric_asset_id(value: String) -> String:
	var out := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		if ch >= "0" and ch <= "9":
			out += ch
	return out

func _block_mesh_asset_id(data: Dictionary) -> String:
	var mesh_id := _sanitize_numeric_asset_id(str(data.get("roblox_mesh_id", "")).strip_edges())
	if not mesh_id.is_empty():
		return mesh_id
	if data.get("roblox_properties", {}) is Dictionary:
		var props: Dictionary = data.get("roblox_properties", {})
		for key in ["MeshId", "MeshID", "AssetId", "SourceAssetId"]:
			mesh_id = _sanitize_numeric_asset_id(str(props.get(key, "")).strip_edges())
			if not mesh_id.is_empty():
				return mesh_id
	return ""

func _block_texture_asset_id(data: Dictionary) -> String:
	var texture_id := _sanitize_numeric_asset_id(str(data.get("roblox_texture_id", "")).strip_edges())
	if not texture_id.is_empty():
		return texture_id
	if data.get("roblox_properties", {}) is Dictionary:
		var props: Dictionary = data.get("roblox_properties", {})
		for key in ["TextureID", "TextureId", "Texture"]:
			texture_id = _sanitize_numeric_asset_id(str(props.get(key, "")).strip_edges())
			if not texture_id.is_empty():
				return texture_id
	return ""

func _runtime_object_asset_source_path(data: Dictionary, folder: String) -> String:
	for key in ["file", "resolved_path", "path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if candidate.is_empty():
			continue
		var resolved_path := _resolve_existing_file_path_for_folder(candidate, folder)
		if not resolved_path.is_empty():
			return resolved_path
	var texture_id := str(data.get("texture", "")).strip_edges()
	if texture_id.begins_with("rbxasset://"):
		var asset_path := texture_id.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		var candidates: Array[String] = [
			"res://addons/rbxl_importer/builtin_assets/%s" % asset_path,
			"res://images/%s" % asset_path.get_file(),
		]
		if asset_path.to_lower() == "textures/spawnlocation.png":
			candidates.append(SPAWN_DECAL_PATH)
		for candidate in candidates:
			var resolved_path := _resolve_existing_file_path_for_folder(candidate, folder)
			if not resolved_path.is_empty():
				return resolved_path
	return ""

func _collect_runtime_objects_for_save() -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	var parent: Node = placement_parent if placement_parent else self
	var runtime_nodes: Array[Node] = []
	_collect_nodes_in_group_recursive(parent, RBXL_RUNTIME_OBJECT_GROUP, runtime_nodes)
	for node_index in range(runtime_nodes.size()):
		objects.append(_runtime_object_data_from_node(runtime_nodes[node_index]))
		if node_index > 0 and node_index % 256 == 0:
			await get_tree().process_frame
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
			decal.size = _runtime_decal_size(data)
			var decal_texture := _runtime_object_texture(data)
			if decal_texture != null:
				decal.texture_albedo = decal_texture
				decal.modulate.a = clampf(1.0 - float(data.get("transparency", 0.0)), 0.0, 1.0)
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

func _runtime_object_texture(data: Dictionary) -> Texture2D:
	var paths: Array[String] = []
	for key in ["resolved_path", "path", "file"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if not candidate.is_empty():
			paths.append(candidate)
	var texture_id := str(data.get("texture", "")).strip_edges()
	if texture_id.begins_with("rbxasset://"):
		var asset_path := texture_id.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		paths.append("res://addons/rbxl_importer/builtin_assets/%s" % asset_path)
		paths.append("res://images/%s" % asset_path.get_file())
		if asset_path.to_lower() == "textures/spawnlocation.png":
			paths.append(SPAWN_DECAL_PATH)
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D
	return null

func _runtime_decal_size(data: Dictionary) -> Vector3:
	var parent_scale := _vector3_from_variant(data.get("parent_scale", []), Vector3(4.0, 4.0, 4.0))
	return Vector3(
		maxf(absf(parent_scale.x), 0.5),
		maxf(absf(parent_scale.y), 0.5),
		maxf(absf(parent_scale.z), 0.5)
	) + Vector3(0.08, 0.08, 0.08)

# ===== SAVE / LOAD / PUBLISH =====
func _on_save_button_pressed() -> void:
	if current_map_folder.is_empty():
		var folder_name := _get_unique_map_folder_name(_sanitize_map_folder_name(_normalize_map_name(current_map_name)))
		current_map_folder = UserSession.get_maps_root_path() + "/" + folder_name
	await _save_map(current_map_folder)

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
	_ensure_directory_path(folder)
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	var folder_name := folder.get_file()
	if maps_dir:
		if not maps_dir.dir_exists(folder_name):
			maps_dir.make_dir(folder_name)

	# Take a clean viewport screenshot for the catalog thumbnail or use a custom
	# image. Capturing the root viewport also included the Studio ribbon/docks.
	if custom_icon_path != "" and FileAccess.file_exists(custom_icon_path):
		var img := _load_image_from_path(custom_icon_path)
		if img:
			_save_map_thumbnail_image(img, folder + "/icon.png")
		else:
			var fallback_image := _capture_studio_map_thumbnail()
			if fallback_image:
				_save_map_thumbnail_image(fallback_image, folder + "/icon.png")
	else:
		var image := _capture_studio_map_thumbnail()
		if image:
			_save_map_thumbnail_image(image, folder + "/icon.png")

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
	var save_ok := await _save_map(folder)
	if not save_ok:
		_finish_publish_progress(false, "Could not save map_data.json.")
		return {"ok": false, "error": "Could not save map_data.json."}
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
	var map_payload := await _read_json_dictionary_async(folder + "/map_data.json")
	if map_payload.is_empty():
		push_warning("[Studio] Cloud upload skipped because map_data.json could not be read.")
		return {"ok": false, "error": "map_data.json could not be read."}
	var meta := _load_map_meta(folder)
	var profile_result: Dictionary = await CloudAPI.authenticate_or_create_profile(UserSession.username if UserSession.is_logged_in else "Unknown")
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var resolved_cloud_map_id: String = str(meta.get("cloud_map_id", "")).strip_edges()
	if resolved_cloud_map_id.is_empty() and CloudAPI.has_method("find_own_published_map_by_name"):
		var existing_result: Dictionary = await CloudAPI.find_own_published_map_by_name(map_name)
		if bool(existing_result.get("ok", false)):
			resolved_cloud_map_id = _extract_cloud_map_id(existing_result.get("data", {}))
	if resolved_cloud_map_id.is_empty() and CloudAPI.has_method("resolve_cloud_map_id_for_name"):
		resolved_cloud_map_id = str(CloudAPI.resolve_cloud_map_id_for_name(map_name, meta)).strip_edges()
	if resolved_cloud_map_id.is_empty():
		return {"ok": false, "error": "Could not resolve cloud map id before uploading assets."}
	map_payload = await _embed_mode_assets_for_cloud(map_payload, folder, resolved_cloud_map_id)
	var failed_assets: Array = map_payload.get(CLOUD_MAP_ASSET_FAILURES_KEY, []) if map_payload.get(CLOUD_MAP_ASSET_FAILURES_KEY, []) is Array else []
	map_payload.erase(CLOUD_MAP_ASSET_FAILURES_KEY)
	if not failed_assets.is_empty():
		var first_failure: Dictionary = failed_assets[0] if failed_assets[0] is Dictionary else {}
		return {
			"ok": false,
			"error": "Could not upload %d required map asset(s). First failure: %s (%s). The previous published version was kept." % [
				failed_assets.size(),
				str(first_failure.get("file", "unknown asset")),
				str(first_failure.get("error", "upload failed"))
			],
			"failed_assets": failed_assets
		}
	_show_publish_progress("Publishing Map", "Preparing thumbnail...", 0.84)
	var thumbnail_payload: String = await _upload_map_thumbnail_for_cloud(folder, resolved_cloud_map_id)
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


func _capture_studio_map_thumbnail() -> Image:
	if DisplayServer.get_name() == "headless":
		return _build_headless_map_thumbnail()
	var source_viewport := _get_studio_subviewport()
	if source_viewport == null:
		source_viewport = get_viewport()
	if source_viewport == null or source_viewport.get_texture() == null:
		return null
	var image := source_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return _build_headless_map_thumbnail()
	return image


func _build_headless_map_thumbnail() -> Image:
	var image := Image.create(768, 432, false, Image.FORMAT_RGBA8)
	image.fill(Color("#9CCCF1"))
	image.fill_rect(Rect2i(0, 250, 768, 182), Color("#6E7D91"))
	image.fill_rect(Rect2i(0, 248, 768, 4), Color("#D8E6EF"))
	var parts := _get_editor_parts()
	var preview_count := mini(parts.size(), 9)
	for index in range(preview_count):
		var part := parts[index]
		if part == null:
			continue
		var color := _get_bobux_block_color(part, Color("#8A95A6"))
		var width := 56 + (index % 3) * 10
		var height := 34 + (index % 4) * 8
		var x := 88 + (index % 5) * 132
		var y := 290 - (index / 5) * 58
		image.fill_rect(Rect2i(x, y, width, height), color)
	return image


func _save_map_thumbnail_image(image: Image, target_path: String) -> Error:
	if image == null or image.is_empty():
		return ERR_INVALID_DATA
	var output := image.duplicate()
	var target_width := 768
	var target_height := 432
	var target_aspect := float(target_width) / float(target_height)
	var source_aspect := float(output.get_width()) / float(maxi(output.get_height(), 1))
	if source_aspect > target_aspect:
		var crop_width := maxi(1, int(round(float(output.get_height()) * target_aspect)))
		var crop_x := maxi(0, (output.get_width() - crop_width) / 2)
		output = output.get_region(Rect2i(crop_x, 0, crop_width, output.get_height()))
	elif source_aspect < target_aspect:
		var crop_height := maxi(1, int(round(float(output.get_width()) / target_aspect)))
		var crop_y := maxi(0, (output.get_height() - crop_height) / 2)
		output = output.get_region(Rect2i(0, crop_y, output.get_width(), crop_height))
	output.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return output.save_png(target_path)


func _upload_map_thumbnail_for_cloud(folder: String, cloud_map_id: String) -> String:
	var icon_path := folder.path_join("icon.png")
	if not FileAccess.file_exists(icon_path):
		return ""
	var upload_result: Dictionary = await CloudAPI.upload_map_asset_file(
		cloud_map_id,
		"thumbnail.png",
		icon_path,
		"image/png",
		CloudAPI.HTTP_MEDIA_UPLOAD_TIMEOUT_SECONDS,
		3
	)
	if bool(upload_result.get("ok", false)):
		var asset_data: Dictionary = upload_result.get("asset", {}) if upload_result.get("asset", {}) is Dictionary else {}
		var public_url := str(asset_data.get("public_url", "")).strip_edges()
		if not public_url.is_empty():
			return public_url
	push_warning("[Studio] Thumbnail storage upload failed; using compact inline fallback: %s" % str(upload_result.get("error", "unknown error")))
	return _encode_image_file_as_data_uri(icon_path)

func _embed_mode_assets_for_cloud(map_payload: Dictionary, folder: String, cloud_map_id: String) -> Dictionary:
	# Publishing may handle tens of megabytes of imported data. Only the root
	# dictionary is changed here, so a deep copy needlessly doubled peak memory.
	var payload: Dictionary = map_payload.duplicate(false)
	var mode_settings: Dictionary = payload.get("mode_settings", {}) if payload.get("mode_settings", {}) is Dictionary else {}
	var asset_blobs: Dictionary = {}
	var asset_urls: Dictionary = {}
	var failed_assets: Array[Dictionary] = []
	var playlist: Array = mode_settings.get("music_playlist", []) if mode_settings.get("music_playlist", []) is Array else []
	var publish_asset_files := _collect_publish_asset_file_names(payload, playlist, folder)
	var embedded_assets: int = 0
	var upload_entries: Array[Dictionary] = []
	for index in range(publish_asset_files.size()):
		var file_variant: Variant = publish_asset_files[index]
		var relative_file_name: String = str(file_variant).strip_edges()
		if relative_file_name.is_empty():
			continue
		var absolute_path: String = folder.path_join(relative_file_name)
		var file_size: int = _get_file_size_bytes(absolute_path)
		if file_size <= 0:
			failed_assets.append({"file": relative_file_name, "error": "file is missing or empty"})
			continue
		if file_size > CLOUD_MAP_ASSET_MAX_BYTES:
			failed_assets.append({"file": relative_file_name, "error": "file exceeds the 50 MB storage limit"})
			push_warning("[Studio] Skipping map asset '%s' during cloud publish. Size %.2f MB (Storage safety limit 50 MB)." % [
				relative_file_name,
				float(file_size) / 1048576.0
			])
			continue
		upload_entries.append({
			"file": relative_file_name,
			"path": absolute_path,
			"size": file_size,
			"index": index
		})

	var upload_cursor := 0
	var completed_assets := 0
	while upload_cursor < upload_entries.size():
		var batch_end := mini(upload_entries.size(), upload_cursor + CLOUD_MAP_ASSET_UPLOAD_CONCURRENCY)
		var batch_state := {"pending": batch_end - upload_cursor, "results": []}
		for entry_index in range(upload_cursor, batch_end):
			call_deferred("_upload_publish_map_asset_async", cloud_map_id, upload_entries[entry_index], batch_state)
		while int(batch_state.get("pending", 0)) > 0:
			await get_tree().process_frame
		var batch_results: Array = batch_state.get("results", []) if batch_state.get("results", []) is Array else []
		for result_variant in batch_results:
			if not (result_variant is Dictionary):
				continue
			var result_entry: Dictionary = result_variant
			var relative_file_name := str(result_entry.get("file", ""))
			var storage_result: Dictionary = result_entry.get("result", {}) if result_entry.get("result", {}) is Dictionary else {}
			if bool(storage_result.get("ok", false)):
				var asset_data: Dictionary = storage_result.get("asset", {}) if storage_result.get("asset", {}) is Dictionary else {}
				var public_url: String = str(asset_data.get("public_url", "")).strip_edges()
				if not public_url.is_empty():
					asset_urls[relative_file_name] = public_url
					embedded_assets += 1
				else:
					failed_assets.append({"file": relative_file_name, "error": "storage returned no public URL"})
			else:
				var upload_error: String = str(storage_result.get("error", "Unknown storage error"))
				failed_assets.append({"file": relative_file_name, "error": upload_error})
				push_warning("[Studio] Storage upload failed for map asset '%s': %s" % [relative_file_name, upload_error])
			completed_assets += 1
			_show_publish_progress(
				"Publishing Map",
				"Uploaded map assets %d/%d" % [completed_assets, maxi(upload_entries.size(), 1)],
				0.30 + 0.48 * float(completed_assets) / float(maxi(upload_entries.size(), 1))
			)
		upload_cursor = batch_end
		await get_tree().process_frame
	var skybox_file: String = str(mode_settings.get("skybox_file", "")).strip_edges()
	if not skybox_file.is_empty() and not asset_urls.has(skybox_file):
		_show_publish_progress("Publishing Map", "Embedding skybox...", 0.80)
		await get_tree().process_frame
		var sky_base64: String = _encode_file_to_base64(folder.path_join(skybox_file), CLOUD_INLINE_ASSET_MAX_BYTES)
		if not sky_base64.is_empty():
			asset_blobs[skybox_file] = sky_base64
	if not asset_blobs.is_empty():
		payload["mode_asset_blobs"] = asset_blobs
	if not asset_urls.is_empty():
		payload["mode_asset_urls"] = asset_urls
	if not failed_assets.is_empty():
		payload[CLOUD_MAP_ASSET_FAILURES_KEY] = failed_assets
		payload["mode_asset_warning"] = "%d required map asset(s) could not be uploaded." % failed_assets.size()
		if toolbar_status_label:
			toolbar_status_label.text = "Publish stopped: %d asset upload failure(s)" % failed_assets.size()
	else:
		_show_publish_progress("Publishing Map", "Uploaded %d map asset(s)." % embedded_assets, 0.82)
	return payload


func _upload_publish_map_asset_async(cloud_map_id: String, entry: Dictionary, state: Dictionary) -> void:
	var result: Dictionary = await CloudAPI.upload_map_asset_file(
		cloud_map_id,
		str(entry.get("file", "")),
		str(entry.get("path", "")),
		"",
		minf(CloudAPI.HTTP_UPLOAD_TIMEOUT_SECONDS, 45.0),
		3
	)
	var results: Array = state.get("results", []) if state.get("results", []) is Array else []
	results.append({"file": str(entry.get("file", "")), "result": result})
	state["results"] = results
	state["pending"] = maxi(0, int(state.get("pending", 1)) - 1)

func _collect_publish_asset_file_names(payload: Dictionary, playlist: Array, folder: String = "") -> Array[String]:
	var result: Array[String] = []
	for section in ["instances", "tools", "gui", "storage_libraries"]:
		for entry in payload.get("roblox_manifest", {}).get(section, []):
			for key in ["BobuxMeshResource", "SoundId"]:
				_append_publish_asset_file_name(result, str(entry.get("properties", {}).get(key, "")))
	for file_variant in playlist:
		_append_publish_asset_file_name(result, str(file_variant).strip_edges())
	var runtime_objects: Array = payload.get("runtime_objects", []) if payload.get("runtime_objects", []) is Array else []
	for object_variant in runtime_objects:
		if not (object_variant is Dictionary):
			continue
		var data: Dictionary = object_variant
		for key in ["file", "resolved_path", "path"]:
			_append_publish_asset_file_name(result, str(data.get(key, "")).strip_edges())
	var blocks: Array = payload.get("blocks", []) if payload.get("blocks", []) is Array else []
	for block_variant in blocks:
		if not (block_variant is Dictionary):
			continue
		var block_data: Dictionary = block_variant
		for key in ["bobux_mesh_resource_asset", "roblox_mesh_json_asset", "roblox_texture_asset_file"]:
			_append_publish_asset_file_name(result, str(block_data.get(key, "")).strip_edges())
	# The importer can introduce additional SurfaceAppearance, GUI, skybox,
	# animation and mesh resources without placing them in the three legacy
	# block fields above. The map folder is the publication boundary, so include
	# every supported asset actually stored there. This keeps the cloud package
	# complete as the import format grows.
	if not folder.strip_edges().is_empty():
		_append_publish_assets_from_folder(result, folder)
	return result

func _append_publish_asset_file_name(result: Array[String], value: String) -> void:
	if value.is_empty():
		return
	if value.begins_with("res://") or value.begins_with("user://") or value.find(":") == 1:
		value = value.get_file()
	value = value.replace("\\", "/")
	while value.begins_with("./"):
		value = value.substr(2)
	if value.contains("../") or value.begins_with("/"):
		value = value.get_file()
	if value.is_empty() or result.has(value):
		return
	result.append(value)


func _append_publish_assets_from_folder(result: Array[String], folder: String, relative_folder: String = "") -> void:
	var scan_path := folder if relative_folder.is_empty() else folder.path_join(relative_folder)
	var directory := DirAccess.open(scan_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == ".." or entry.begins_with("."):
			continue
		var relative_path := entry if relative_folder.is_empty() else relative_folder.path_join(entry)
		if directory.current_is_dir():
			_append_publish_assets_from_folder(result, folder, relative_path)
			continue
		if _is_publishable_map_asset_file(relative_path):
			_append_publish_asset_file_name(result, relative_path)
	directory.list_dir_end()


func _is_publishable_map_asset_file(relative_path: String) -> bool:
	var file_name := relative_path.get_file().to_lower()
	if file_name in ["map_data.json", "meta.json", "icon.png", "thumbnail.png"]:
		return false
	return relative_path.get_extension().to_lower() in [
		"png", "jpg", "jpeg", "webp", "bmp", "tga", "svg", "dds", "ktx",
		"ogg", "mp3", "wav",
		"json", "mesh", "res", "tres", "glb", "gltf", "obj",
		"lua", "luau"
	]

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

func _read_json_dictionary_async(path: String) -> Dictionary:
	var worker := Thread.new()
	var start_error := worker.start(_read_json_dictionary_worker.bind(path))
	if start_error != OK:
		return _read_json_dictionary(path)
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is Dictionary else {}

static func _read_json_dictionary_worker(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _write_json_dictionary_async(path: String, data: Dictionary) -> Dictionary:
	var worker := Thread.new()
	var start_error := worker.start(_write_json_dictionary_worker.bind(path, data))
	if start_error != OK:
		return _write_json_dictionary_worker(path, data)
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is Dictionary else {"ok": false, "error": "JSON writer returned no result."}

static func _write_json_dictionary_worker(path: String, data: Dictionary) -> Dictionary:
	var encoded := JSON.stringify(data).to_utf8_buffer()
	if encoded.is_empty():
		return {"ok": false, "error": "Map JSON serialization produced an empty payload."}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open map data file for writing."}
	file.store_buffer(encoded)
	file.close()
	return {"ok": true, "bytes": encoded.size()}

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

func _save_map(folder: String) -> bool:
	# Ensure directory
	UserSession.ensure_current_storage()
	_ensure_directory_path(folder)
	# Ensure specific folder
	var folder_name := folder.get_file()
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir and not maps_dir.dir_exists(folder_name):
		maps_dir.make_dir(folder_name)
	var mode_settings := _collect_mode_settings_for_save(folder)

	var blocks_data := []
	var editor_parts := _get_editor_parts()

	for child_index in range(editor_parts.size()):
		var child := editor_parts[child_index] as Node3D
		if child == null:
			continue
		if child.is_in_group("studio_parts"):
			var world_transform := child.global_transform
			var world_scale := world_transform.basis.get_scale().abs()
			var world_rotation := world_transform.basis.orthonormalized().get_euler()
			var shape_type: String = child.get_meta("shape_type", "Box")
			var col := _get_bobux_block_color(child, Color.WHITE)
			var block_entry := {
				"name": child.get_meta("block_name", child.name),
				"px": snappedf(world_transform.origin.x, 0.01),
				"py": snappedf(world_transform.origin.y, 0.01),
				"pz": snappedf(world_transform.origin.z, 0.01),
				"rx": snappedf(rad_to_deg(world_rotation.x), 0.01),
				"ry": snappedf(rad_to_deg(world_rotation.y), 0.01),
				"rz": snappedf(rad_to_deg(world_rotation.z), 0.01),
				"sx": snappedf(world_scale.x, 0.01),
				"sy": snappedf(world_scale.y, 0.01),
				"sz": snappedf(world_scale.z, 0.01),
				"cr": snappedf(col.r, 0.01),
				"cg": snappedf(col.g, 0.01),
				"cb": snappedf(col.b, 0.01),
				"ca": snappedf(col.a, 0.01),
				# Canonical RGBA value used by Studio, cloud storage and gameplay.
				# Legacy cr/cg/cb fields stay for backwards compatibility.
				"color": [col.r, col.g, col.b, col.a],
				"shape": shape_type,
				"material": child.get_meta("material_type", "Plastic"),
				"transparency": child.get_meta("transparency", 0.0),
				"can_collide": child.get_meta("can_collide", true),
				"anchored": child.get_meta("anchored", true),
				"deals_damage": child.get_meta("deals_damage", false),
				"damage_amount": child.get_meta("damage_amount", DEFAULT_BLOCK_DAMAGE),
				"is_spawn": child.get_meta("is_spawn", false)
			}
			for meta_key in [
				"roblox_ref", "roblox_class", "roblox_material_id",
				"roblox_mesh_id", "roblox_texture_id",
				"roblox_mesh_exact_asset", "roblox_mesh_json_asset",
				"roblox_texture_asset_file",
				"roblox_proxy_geometry", "roblox_mesh_deferred",
				"bobux_mesh_resource_asset", "bobux_ai_effects",
				"bobux_ai_interaction", "bobux_physics_mode",
				"bobux_physics_mass", "bobux_physics_friction",
				"bobux_physics_bounce", "bobux_physics_gravity_scale",
				"bobux_physics_linear_damp", "bobux_physics_angular_damp"
			]:
				if child.has_meta(meta_key):
					block_entry[meta_key] = child.get_meta(meta_key)
			if child.has_meta("roblox_properties") and child.get_meta("roblox_properties") is Dictionary:
				block_entry["roblox_properties"] = (child.get_meta("roblox_properties") as Dictionary).duplicate(true)
			if child.has_meta("roblox_special_mesh") and child.get_meta("roblox_special_mesh") is Dictionary:
				block_entry["roblox_special_mesh"] = (child.get_meta("roblox_special_mesh") as Dictionary).duplicate(true)
			blocks_data.append(block_entry)
		if child_index > 0 and child_index % 256 == 0:
			await get_tree().process_frame

	var time_val = time_slider.value if time_slider else 12.0
	await _store_block_asset_files(blocks_data, folder)
	var runtime_objects := await _collect_runtime_objects_for_save()
	await _store_runtime_object_asset_files(runtime_objects, folder)
	if data_model != null and data_model.has_method("build_manifest"):
		var authored_manifest: Variant = data_model.call("build_manifest", current_roblox_place_manifest)
		if authored_manifest is Dictionary:
			current_roblox_place_manifest = (authored_manifest as Dictionary).duplicate(false)
	_store_manifest_asset_files(current_roblox_place_manifest, folder)
	var data = {
		"time_of_day": time_val,
		"player_settings": _get_current_player_settings(),
		"mode_settings": mode_settings,
		"blocks": blocks_data,
		"runtime_objects": runtime_objects,
		"roblox_manifest": current_roblox_place_manifest.duplicate(false)
	}

	var write_result: Dictionary = await _write_json_dictionary_async(folder + "/map_data.json", data)
	if not bool(write_result.get("ok", false)):
		push_error("[Studio] Could not save map_data.json: %s" % str(write_result.get("error", "unknown error")))
		return false
	print("[Studio] Saved to %s (%d blocks, %.2f MB)" % [
		folder,
		blocks_data.size(),
		float(write_result.get("bytes", 0)) / 1048576.0
	])

	_save_map_meta(folder)

	# Take screenshot only if user hasn't set a custom icon
	if not custom_icon_set and DisplayServer.get_name() != "headless":
		var viewport := get_viewport()
		var viewport_texture := viewport.get_texture() if viewport != null else null
		var image := viewport_texture.get_image() if viewport_texture != null else null
		if image != null and not image.is_empty():
			image.save_png(folder + "/icon.png")
	return true

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
	current_map_folder = folder

	for block in _get_editor_parts():
		block.queue_free()
	_clear_authored_terrain_for_load()
	_clear_runtime_object_nodes()
	await get_tree().process_frame

	if time_slider and data.has("time_of_day"):
		time_slider.value = data["time_of_day"]
	_apply_player_settings_to_ui(data.get("player_settings", _get_default_player_settings()))
	current_roblox_place_manifest = data.get("roblox_manifest", {}) if data.get("roblox_manifest", {}) is Dictionary else {}
	_refresh_roblox_gui_preview()
	_apply_mode_settings_to_ui(data.get("mode_settings", _get_default_mode_settings()), folder)

	var blocks: Array = data.get("blocks", [])
	for block_data in blocks:
		var target_parent = placement_parent if placement_parent else self
		var pos := Vector3(
			block_data.get("px", 0.0),
			block_data.get("py", 0.0),
			block_data.get("pz", 0.0)
		)
		var col := _color_from_block_data(block_data, Color.WHITE)
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
				_restore_saved_roblox_block_metadata(inst, block_data)
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
		_restore_saved_roblox_block_metadata(mesh_inst, block_data)
		_apply_saved_roblox_part_material(mesh_inst, block_data)
		_apply_saved_bobux_mesh_resource(mesh_inst, block_data, folder)
		_apply_saved_roblox_mesh_asset(mesh_inst, block_data, folder)
		mesh_inst.set_meta("bobux_color", col)
		_update_block_collision(mesh_inst)
		target_parent.add_child(mesh_inst)

	_load_runtime_objects_from_map(data.get("runtime_objects", []))
	await _install_roblox_manifest_data_model_preview()
	print("[Studio] Loaded %d blocks from %s" % [blocks.size(), folder])
	_refresh_explorer()

func _clear_authored_terrain_for_load() -> void:
	if placement_parent == null:
		return
	for child in placement_parent.get_children():
		if str(child.get_meta("roblox_class", "")) == "Terrain" or child.is_in_group("studio_terrain"):
			child.queue_free()

func _restore_saved_roblox_block_metadata(block: Node, block_data: Dictionary) -> void:
	if block == null:
		return
	for meta_key in [
		"roblox_ref", "roblox_class", "roblox_material_id",
		"roblox_mesh_id", "roblox_texture_id",
		"roblox_mesh_exact_asset", "roblox_mesh_json_asset",
		"roblox_texture_asset_file",
		"roblox_proxy_geometry", "roblox_mesh_deferred",
		"bobux_mesh_resource_asset", "bobux_ai_effects",
		"bobux_ai_interaction", "bobux_physics_mode",
		"bobux_physics_mass", "bobux_physics_friction",
		"bobux_physics_bounce", "bobux_physics_gravity_scale",
		"bobux_physics_linear_damp", "bobux_physics_angular_damp"
	]:
		if block_data.has(meta_key):
			block.set_meta(meta_key, block_data[meta_key])
	if block_data.has("anchored"):
		block.set_meta("anchored", bool(block_data.get("anchored", true)))
	if block_data.get("roblox_properties", {}) is Dictionary:
		block.set_meta("roblox_properties", (block_data.get("roblox_properties", {}) as Dictionary).duplicate(true))
		var attributes: Dictionary = block_data.get("roblox_properties", {}).get("Attributes", {})
		for attribute in attributes:
			block.set_meta("attribute_" + str(attribute), attributes[attribute])
	if block_data.get("roblox_special_mesh", {}) is Dictionary:
		block.set_meta("roblox_special_mesh", (block_data.get("roblox_special_mesh", {}) as Dictionary).duplicate(true))
	if block is MeshInstance3D:
		_rebuild_studio_ai_components(block as MeshInstance3D)

func _apply_saved_roblox_part_material(mesh_inst: MeshInstance3D, block_data: Dictionary) -> void:
	if mesh_inst == null:
		return
	if not _should_apply_saved_roblox_block_material(block_data):
		return
	var props: Dictionary = (block_data.get("roblox_properties", {}) as Dictionary).duplicate(true)
	var canonical_color := _color_from_block_data(block_data, Color.WHITE)
	var material := rbxl_material_cache.get_part_material_with_color(props, canonical_color)
	if material != null:
		mesh_inst.set_surface_override_material(0, material)

func _apply_saved_bobux_mesh_resource(mesh_inst: MeshInstance3D, block_data: Dictionary, folder: String) -> void:
	if mesh_inst == null:
		return
	var file_name := str(block_data.get("bobux_mesh_resource_asset", "")).strip_edges()
	if file_name.is_empty():
		return
	var resource_path := _resolve_existing_file_path_for_folder(file_name, folder)
	if resource_path.is_empty():
		return
	var loaded := ResourceLoader.load(_resource_loader_path(resource_path))
	if not (loaded is Mesh):
		return
	var fallback_material := mesh_inst.get_active_material(0)
	mesh_inst.mesh = (loaded as Mesh).duplicate(true)
	_apply_material_to_missing_mesh_surfaces(mesh_inst, fallback_material)
	RbxlMaterialCache.enable_embedded_vertex_colors(mesh_inst)
	mesh_inst.set_meta("shape_type", "MeshPart")
	mesh_inst.set_meta("roblox_class", "MeshPart")
	mesh_inst.set_meta("bobux_mesh_resource_asset", file_name)
	_ensure_mesh_materials_double_sided(mesh_inst)

func _resource_loader_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var normalized := path.replace("\\", "/")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if normalized.begins_with(user_root + "/"):
		return "user://" + normalized.substr(user_root.length() + 1)
	return ProjectSettings.localize_path(path)

func _apply_saved_roblox_mesh_asset(mesh_inst: MeshInstance3D, block_data: Dictionary, folder: String) -> void:
	if mesh_inst == null:
		return
	var mesh_path := _saved_block_mesh_asset_path(block_data, folder)
	if mesh_path.is_empty():
		return
	var mesh := RobloxMeshJsonLoader.load_mesh(mesh_path)
	if mesh == null:
		return
	var material := mesh_inst.get_active_material(0)
	mesh_inst.mesh = mesh
	if material != null:
		_apply_material_to_missing_mesh_surfaces(mesh_inst, material)
	mesh_inst.set_meta("shape_type", "MeshPart")
	mesh_inst.set_meta("roblox_mesh_applied", true)
	_apply_saved_roblox_block_texture(mesh_inst, block_data, folder, true)
	RbxlMaterialCache.enable_embedded_vertex_colors(mesh_inst)
	_ensure_mesh_materials_double_sided(mesh_inst)

func _saved_block_mesh_asset_path(block_data: Dictionary, folder: String) -> String:
	var file_name := str(block_data.get("roblox_mesh_json_asset", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := _resolve_existing_file_path_for_folder(file_name, folder)
		if not resolved.is_empty():
			return resolved
	var mesh_id := _block_mesh_asset_id(block_data)
	if not mesh_id.is_empty():
		var cache_path := ProjectSettings.globalize_path("user://rbxl_assets/%s.mesh.json" % mesh_id)
		if FileAccess.file_exists(cache_path):
			return cache_path
	return ""

func _apply_saved_roblox_block_texture(mesh_inst: MeshInstance3D, block_data: Dictionary, folder: String, use_mesh_uvs: bool) -> void:
	var texture_path := _saved_block_texture_asset_path(block_data, folder)
	if texture_path.is_empty():
		return
	var texture := _load_texture_from_file_path(texture_path)
	if texture == null:
		return
	var material := mesh_inst.get_active_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
	else:
		material = material.duplicate(true) as StandardMaterial3D
	material.albedo_texture = texture
	material.uv1_triplanar = not use_mesh_uvs
	if material.albedo_color.a >= 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_material_to_all_mesh_surfaces(mesh_inst, material)

func _apply_material_to_all_mesh_surfaces(mesh_inst: MeshInstance3D, material: Material) -> void:
	if mesh_inst == null or material == null:
		return
	var surface_count := maxi(1, mesh_inst.mesh.get_surface_count() if mesh_inst.mesh != null else 1)
	for surface_index in range(surface_count):
		mesh_inst.set_surface_override_material(surface_index, material)

func _apply_material_to_missing_mesh_surfaces(mesh_inst: MeshInstance3D, fallback_material: Material) -> void:
	if mesh_inst == null or mesh_inst.mesh == null or fallback_material == null:
		return
	var mesh_has_own_appearance := false
	for surface_index in range(mesh_inst.mesh.get_surface_count()):
		if _mesh_surface_material_has_visible_appearance(mesh_inst.get_active_material(surface_index)):
			mesh_has_own_appearance = true
			break
	for surface_index in range(mesh_inst.mesh.get_surface_count()):
		var existing := mesh_inst.get_active_material(surface_index)
		if existing == null or not mesh_has_own_appearance:
			mesh_inst.set_surface_override_material(surface_index, fallback_material.duplicate(true))

func _mesh_surface_material_has_visible_appearance(material: Material) -> bool:
	if material == null:
		return false
	if not (material is BaseMaterial3D):
		return true
	var base := material as BaseMaterial3D
	for property_name in [
		"albedo_texture", "normal_texture", "orm_texture", "metallic_texture",
		"roughness_texture", "emission_texture"
	]:
		if base.get(property_name) is Texture2D:
			return true
	if base.vertex_color_use_as_albedo:
		return true
	var color := base.albedo_color
	return color.a < 0.985 or absf(color.r - 1.0) > 0.02 or absf(color.g - 1.0) > 0.02 or absf(color.b - 1.0) > 0.02

func _ensure_mesh_materials_double_sided(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	var surface_count := maxi(1, mesh_inst.mesh.get_surface_count())
	for surface_index in range(surface_count):
		var existing := mesh_inst.get_active_material(surface_index)
		if existing == null:
			var fallback := StandardMaterial3D.new()
			fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_inst.set_surface_override_material(surface_index, fallback)
		elif existing is BaseMaterial3D:
			var material := (existing as BaseMaterial3D).duplicate(true) as BaseMaterial3D
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_inst.set_surface_override_material(surface_index, material)

func _saved_block_texture_asset_path(block_data: Dictionary, folder: String) -> String:
	var file_name := str(block_data.get("roblox_texture_asset_file", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := _resolve_existing_file_path_for_folder(file_name, folder)
		if not resolved.is_empty():
			return resolved
	var texture_id := _block_texture_asset_id(block_data)
	if texture_id.is_empty():
		return ""
	for ext in ["asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp", "png", "jpg", "jpeg", "webp"]:
		var cache_texture := ProjectSettings.globalize_path("user://rbxl_assets/%s.%s" % [texture_id, ext])
		if _texture_file_has_supported_magic(cache_texture):
			return cache_texture
	return ""

func _texture_file_has_supported_magic(path: String) -> bool:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return false
	if path.begins_with("res://"):
		return load(path) is Texture2D
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(mini(file.get_length(), 16))
	file.close()
	return (
		bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	) or (
		bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
	) or (
		bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP"
	)

func _load_texture_from_file_path(path: String) -> Texture2D:
	if path.begins_with("res://"):
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var err := ERR_UNAVAILABLE
	if bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		err = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		err = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = image.load_webp_from_buffer(bytes)
	if err == OK:
		return ImageTexture.create_from_image(image)
	return null

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
	var mesh_inst := _build_block_instance("Box", Color("#68778E"), "SmoothPlastic", 0.0, true, "Baseplate")
	mesh_inst.position = Vector3(0.0, -0.5, 0.0)
	mesh_inst.scale = Vector3(200.0, 1.0, 200.0)
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
