extends CharacterBody3D

const AudioFileLoader = preload("res://addons/roblox_runtime/audio_file_loader.gd")

const MOVE_SPEED: float = 24.0
const RbxlMaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const SPRINT_MULTIPLIER: float = 1.25
const JUMP_VELOCITY: float = 31.0
const WALK_CYCLE_SPEED: float = 12.0
const LIMB_SWING_ANGLE: float = 0.82
const MOUSE_SENSITIVITY: float = 0.008
const CAMERA_MIN_PITCH: float = deg_to_rad(-70.0)
const CAMERA_MAX_PITCH: float = deg_to_rad(60.0)
const CAMERA_THIRD_PERSON_HEIGHT: float = 4.0
const CAMERA_FIRST_PERSON_HEIGHT: float = 4.6
const CAMERA_INTERPOLATION_TELEPORT_THRESHOLD: float = 2.5
const CAMERA_COLLISION_MIN_DISTANCE: float = 1.2
const CAMERA_COLLISION_MARGIN: float = 0.28
const CAMERA_COLLISION_RETURN_SPEED: float = 18.0
const GROUND_ACCELERATION: float = 380.0
const GROUND_DECELERATION: float = 540.0
const AIR_ACCELERATION: float = 78.0
const AIR_DECELERATION: float = 34.0
const JUMP_GRAVITY: float = 72.0
const JUMP_RELEASE_GRAVITY: float = 124.0
const FALL_GRAVITY: float = 185.0
const GRAVITY_FORCE: float = FALL_GRAVITY
const MAX_FALL_SPEED: float = 240.0
const FLOOR_STICK_VELOCITY: float = -2.2
const FALL_RESPAWN_Y: float = -60.0
const TELEPORT_COOLDOWN_MS: int = 450
const SAFE_REPOSITION_LIFT: float = 0.42
const RESPAWN_SERVER_TIMEOUT_SECONDS: float = 1.35
const VOID_HARD_RECOVERY_Y: float = FALL_RESPAWN_Y - 30.0
const MIN_SAFE_RESPAWN_Y: float = FALL_RESPAWN_Y + 12.0
const FALLBACK_RESPAWN_HEIGHT: float = 8.0
const DEFAULT_FACE_TEXTURE_PATH: String = "res://assets/avatar/default_face.png"
const DEFAULT_CHEST_BADGE_TEXTURE_PATH: String = "res://assets/avatar/bobux_chest_badge.png"
const AVATAR_DECAL_PREPROCESS_MAX_SIDE: int = 768
const AVATAR_DECAL_FINAL_MAX_SIDE: int = 512
const AVATAR_DECAL_CACHE_MAX_ENTRIES: int = 160
const AVATAR_FACE_DECAL_SIZE: Vector2 = Vector2(0.8, 0.58)
const AVATAR_FACE_DECAL_CENTER_Y: float = 0.02
const AVATAR_FACE_DECAL_RADIUS: float = 0.6
const AVATAR_FACE_DECAL_SURFACE_OFFSET: float = 0.012
const AVATAR_FACE_DECAL_SEGMENTS: int = 10
const AVATAR_TEMPLATE_REGION_BLEED_PX: int = 2
const AVATAR_TEMPLATE_TORSO_FRONT_REGION: Rect2 = Rect2(0.395, 0.151, 0.219, 0.219)
const AVATAR_TEMPLATE_TORSO_BACK_REGION: Rect2 = Rect2(0.730, 0.151, 0.219, 0.219)
const AVATAR_TEMPLATE_TORSO_RIGHT_SIDE_REGION: Rect2 = Rect2(0.284, 0.151, 0.109, 0.219)
const AVATAR_TEMPLATE_TORSO_LEFT_SIDE_REGION: Rect2 = Rect2(0.617, 0.151, 0.109, 0.219)
const AVATAR_TEMPLATE_TORSO_UP_REGION: Rect2 = Rect2(0.395, 0.039, 0.219, 0.109)
const AVATAR_TEMPLATE_TORSO_DOWN_REGION: Rect2 = Rect2(0.395, 0.370, 0.219, 0.109)
const AVATAR_TEMPLATE_RIGHT_ARM_OUTER_REGION: Rect2 = Rect2(0.035, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_ARM_BACK_REGION: Rect2 = Rect2(0.148, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_ARM_INNER_REGION: Rect2 = Rect2(0.261, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_ARM_FRONT_REGION: Rect2 = Rect2(0.373, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_ARM_UP_REGION: Rect2 = Rect2(0.373, 0.517, 0.109, 0.109)
const AVATAR_TEMPLATE_RIGHT_ARM_DOWN_REGION: Rect2 = Rect2(0.373, 0.850, 0.109, 0.109)
const AVATAR_TEMPLATE_LEFT_ARM_FRONT_REGION: Rect2 = Rect2(0.528, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_ARM_INNER_REGION: Rect2 = Rect2(0.641, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_ARM_BACK_REGION: Rect2 = Rect2(0.753, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_ARM_OUTER_REGION: Rect2 = Rect2(0.866, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_ARM_UP_REGION: Rect2 = Rect2(0.528, 0.517, 0.109, 0.109)
const AVATAR_TEMPLATE_LEFT_ARM_DOWN_REGION: Rect2 = Rect2(0.528, 0.850, 0.109, 0.109)
const AVATAR_TEMPLATE_RIGHT_LEG_OUTER_REGION: Rect2 = Rect2(0.035, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_LEG_BACK_REGION: Rect2 = Rect2(0.148, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_LEG_INNER_REGION: Rect2 = Rect2(0.261, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_LEG_FRONT_REGION: Rect2 = Rect2(0.373, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_RIGHT_LEG_UP_REGION: Rect2 = Rect2(0.373, 0.517, 0.109, 0.109)
const AVATAR_TEMPLATE_RIGHT_LEG_DOWN_REGION: Rect2 = Rect2(0.373, 0.850, 0.109, 0.109)
const AVATAR_TEMPLATE_LEFT_LEG_FRONT_REGION: Rect2 = Rect2(0.528, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_LEG_INNER_REGION: Rect2 = Rect2(0.641, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_LEG_BACK_REGION: Rect2 = Rect2(0.753, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_LEG_OUTER_REGION: Rect2 = Rect2(0.866, 0.628, 0.109, 0.219)
const AVATAR_TEMPLATE_LEFT_LEG_UP_REGION: Rect2 = Rect2(0.528, 0.517, 0.109, 0.109)
const AVATAR_TEMPLATE_LEFT_LEG_DOWN_REGION: Rect2 = Rect2(0.528, 0.850, 0.109, 0.109)
const AVATAR_TEMPLATE_NON_TEMPLATE_FRONT_REGIONS := [
	AVATAR_TEMPLATE_TORSO_FRONT_REGION,
	AVATAR_TEMPLATE_LEFT_LEG_FRONT_REGION,
	AVATAR_TEMPLATE_RIGHT_LEG_FRONT_REGION,
]
const AVATAR_TEMPLATE_GUIDE_SAMPLE_RECTS := [
	Rect2(0.020, 0.020, 0.160, 0.100),
	Rect2(0.800, 0.020, 0.160, 0.100),
	Rect2(0.040, 0.420, 0.140, 0.090),
	Rect2(0.785, 0.420, 0.140, 0.090),
	Rect2(0.410, 0.500, 0.170, 0.080),
]
const AVATAR_TEMPLATE_EDGE_GRAY_TOLERANCE: float = 0.18
const AVATAR_TEMPLATE_EDGE_SAMPLE_STEP: int = 16
const AVATAR_TEMPLATE_MIN_GLOBAL_GRAY_RATIO: float = 0.38
# Avatar decals now use the fixed Bobux R6 square atlas from assets/avatar.
const ENABLE_AVATAR_DECAL_LAYER: bool = true
const ENABLE_AVATAR_CLOTHING_DECALS: bool = true
const PLAYER_COLLISION_LAYER: int = 2
const WORLD_COLLISION_MASK: int = 1
const PLAYER_AND_WORLD_COLLISION_MASK: int = WORLD_COLLISION_MASK | PLAYER_COLLISION_LAYER
const FLOOR_SNAP_LENGTH: float = 0.68
const COYOTE_TIME: float = 0.14
const JUMP_BUFFER_TIME: float = 0.11
const SLOPE_CLIMB_ASSIST: float = 0.48
const SLOPE_MAX_UP_VELOCITY: float = 4.5
const SLOPE_VERTICAL_ACCELERATION: float = 28.0
const LOCAL_TURN_LERP_SPEED: float = 8.0
const AUTO_STEP_HEIGHT: float = 0.58
const AUTO_STEP_MAX_APPLIED_HEIGHT: float = 0.42
const AUTO_STEP_FORWARD_DISTANCE: float = 0.24
const AUTO_STEP_VERTICAL_SPEED: float = 17.0
const AUTO_STEP_FORWARD_SPEED: float = 3.8
const CLIMB_SPEED: float = 10.0
const CLIMB_SIDE_SPEED: float = 6.5
const CLIMB_SURFACE_PULL_SPEED: float = 2.4
const CLIMB_PROBE_DISTANCE: float = 1.35
const CLIMB_LOST_SURFACE_GRACE: float = 0.14
const CLIMB_JUMP_OUT_SPEED: float = 8.5
const CLIMB_JUMP_UP_FACTOR: float = 0.72
const CLIMB_LEDGE_FORWARD_SPEED: float = 5.2
const CLIMB_LEDGE_UP_SPEED: float = 3.4
const LEDGE_PROBE_DISTANCE: float = 1.15
const LEDGE_MANTLE_SPEED: float = 12.0
const LEDGE_MANTLE_MAX_HEIGHT: float = 3.75
const LEDGE_HANG_HAND_HEIGHT: float = 4.35
const LEDGE_HANG_WALL_CLEARANCE: float = 0.54
const LEDGE_HANG_SNAP_SPEED: float = 18.0
const LEDGE_GRAB_WINDOW_SECONDS: float = 0.42
const SWIM_SPEED: float = 15.0
const SWIM_VERTICAL_SPEED: float = 10.0
const SWIM_ACCELERATION: float = 52.0
const SWIM_IDLE_SINK_SPEED: float = 0.7
const SEAT_EXIT_COOLDOWN_MSEC: int = 900
const SEAT_ATTACH_HEIGHT: float = 0.12
const DEATH_RESPAWN_DELAY_SECONDS: float = 2.35
const DEATH_FRAGMENT_LIFETIME_SECONDS: float = 3.0
const PRIMARY_CAPSULE_RADIUS: float = 0.62
const PRIMARY_CAPSULE_HEIGHT: float = 4.45
const PRIMARY_CAPSULE_CENTER_Y: float = 2.28
const HITBOX_FEET_PADDING: Vector3 = Vector3(0.01, 0.01, 0.01)
const HITBOX_TORSO_PADDING: Vector3 = Vector3(0.01, 0.01, 0.01)
const HITBOX_HEAD_PADDING: Vector3 = Vector3(0.01, 0.01, 0.01)
const HITBOX_ARM_PADDING: Vector3 = Vector3(0.01, 0.01, 0.01)
const HITBOX_FEET_MIN: Vector3 = Vector3(1.9, 1.98, 0.92)
const HITBOX_TORSO_MIN: Vector3 = Vector3(1.4, 1.72, 0.46)
const HITBOX_HEAD_MIN: Vector3 = Vector3(0.96, 0.98, 0.86)
const HITBOX_ARM_MIN: Vector3 = Vector3(0.82, 1.72, 0.42)
const HITBOX_FEET_MAX: Vector3 = Vector3(2.04, 2.12, 1.02)
const HITBOX_TORSO_MAX: Vector3 = Vector3(1.64, 1.94, 0.62)
const HITBOX_HEAD_MAX: Vector3 = Vector3(1.1, 1.12, 0.98)
const HITBOX_ARM_MAX: Vector3 = Vector3(0.98, 1.9, 0.62)
const UI_PREVIEW_TARGET_HEIGHT: float = 4.4
const UI_PREVIEW_TARGET_WIDTH: float = 3.1
const UI_PREVIEW_TARGET_DEPTH: float = 2.6
const UI_PREVIEW_CENTER_HEIGHT: float = 2.45
const MAX_HEALTH: int = 100
const DEATH_SOUND_PATH: String = "res://robloxdeathsound.mp3"
const REMOTE_POSITION_LERP_SPEED: float = 20.0
const REMOTE_ROTATION_LERP_SPEED: float = 24.0
const CHAT_BUBBLE_MAX_LENGTH: int = 200
const CHAT_BUBBLE_RATE_LIMIT_MS: int = 1200
const ENABLE_REMOTE_INTERPOLATION: bool = true
const INTERPOLATION_BUFFER_DELAY_MS: float = 76.0
const POSITION_BUFFER_MAX_SIZE: int = 18
const BUFFER_MAX_AGE_MS: float = 500.0
const MAX_EXTRAPOLATION_MS: float = 120.0
const REMOTE_HARD_SNAP_DISTANCE: float = 7.5
const REMOTE_SNAPSHOT_POSITION_EPSILON: float = 0.012
const REMOTE_SNAPSHOT_VERTICAL_EPSILON: float = 0.026
const REMOTE_SNAPSHOT_ROTATION_EPSILON: float = deg_to_rad(1.2)
const REMOTE_SNAPSHOT_VISUAL_Y_EPSILON: float = deg_to_rad(1.2)
const REMOTE_GROUNDED_Y_SNAP_EPSILON: float = 0.16
const WEBSOCKET_DELTA_SYNC_HZ: float = 60.0
const DEFAULT_ALWAYS_SYNC_HZ: float = 30.0
const NETWORK_POSITION_SNAP_STEP: float = 0.012
const NETWORK_GROUNDED_Y_SNAP_STEP: float = 0.01
const NETWORK_AIRBORNE_Y_SNAP_STEP: float = 0.022
const NETWORK_VELOCITY_SNAP_STEP: float = 0.035
const NETWORK_ROOT_ROTATION_SNAP_STEP: float = deg_to_rad(1.0)
const UNSTUCK_MIN_SAFE_DISTANCE: float = 0.08
const UNSTUCK_STATIONARY_SECONDS: float = 0.34
const MAX_UNAUTHORISED_FRAME_DISPLACEMENT: float = 12.0

static var _avatar_decal_texture_cache: Dictionary = {}
static var _requested_textures: Dictionary = {}
static var _requested_remote_avatar_textures: Dictionary = {}
static var _failed_avatar_texture_paths: Dictionary = {}

enum CharacterState {
	IDLE,
	WALKING,
	RUNNING,
	JUMPING,
	FALLING,
	SEATED,
	CLIMBING,
	SWIMMING,
	DEAD
}

@export var animation_cycle: float = 0.0
@export var animation_weight: float = 0.0
@export var animation_airborne: bool = false
@export var display_name: String = "Player"
@export var is_ui_preview: bool = false
@export_range(0.25, 2.0, 0.05) var world_stud_scale: float = 1.0
@export var use_local_avatar_fallback: bool = false
@export var render_avatar_visual_decals: bool = true
@export var render_avatar_clothing_decals: bool = true
@export var current_health: int = MAX_HEALTH
@export var network_room_id: String = ""
@export var network_position: Vector3 = Vector3.ZERO
@export var network_position_origin: Vector3 = Vector3.ZERO
@export var network_rotation: Vector3 = Vector3.ZERO
@export var network_velocity: Vector3 = Vector3.ZERO
@export var network_visuals_y: float = 0.0
@export var network_grounded: bool = false
@export var network_character_state: int = CharacterState.IDLE


@export var head_color: Color = Color(0.96, 0.8, 0.2)
@export var torso_color: Color = Color(0.05, 0.4, 0.7)
@export var left_arm_color: Color = Color(0.96, 0.8, 0.2)
@export var right_arm_color: Color = Color(0.96, 0.8, 0.2)
@export var left_leg_color: Color = Color(0.65, 0.8, 0.2)
@export var right_leg_color: Color = Color(0.65, 0.8, 0.2)
@export var face_texture_path: String = ""
@export var chest_badge_texture_path: String = ""
@export var shirt_texture_path: String = ""
@export var pants_texture_path: String = ""
@export var equipped_avatar_items: Array = []

@onready var gravity_force: float = GRAVITY_FORCE
@onready var visuals: Node3D = $Visuals
@onready var collision_body: CollisionShape3D = get_node_or_null("CollisionBody") as CollisionShape3D
@onready var collision_left_leg: CollisionShape3D = get_node_or_null("CollisionLeftLeg") as CollisionShape3D
@onready var collision_right_leg: CollisionShape3D = get_node_or_null("CollisionRightLeg") as CollisionShape3D
@onready var collision_torso: CollisionShape3D = get_node_or_null("CollisionTorso") as CollisionShape3D
@onready var collision_head: CollisionShape3D = get_node_or_null("CollisionHead") as CollisionShape3D
@onready var collision_left_arm: CollisionShape3D = get_node_or_null("CollisionLeftArm") as CollisionShape3D
@onready var collision_right_arm: CollisionShape3D = get_node_or_null("CollisionRightArm") as CollisionShape3D
@onready var head_mesh: MeshInstance3D = $Visuals/Head
@onready var torso_mesh: MeshInstance3D = $Visuals/Torso
@onready var left_arm_pivot: Node3D = $Visuals/LeftArmPivot
@onready var right_arm_pivot: Node3D = $Visuals/RightArmPivot
@onready var left_leg_pivot: Node3D = $Visuals/LeftLegPivot
@onready var right_leg_pivot: Node3D = $Visuals/RightLegPivot
@onready var left_arm_mesh: MeshInstance3D = $Visuals/LeftArmPivot/LeftArm
@onready var right_arm_mesh: MeshInstance3D = $Visuals/RightArmPivot/RightArm
@onready var left_leg_mesh: MeshInstance3D = $Visuals/LeftLegPivot/LeftLeg
@onready var right_leg_mesh: MeshInstance3D = $Visuals/RightLegPivot/RightLeg
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var player_camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var state_synchronizer: MultiplayerSynchronizer = $StateSynchronizer
@onready var name_label: Label3D = $Visuals/NameLabel

var applied_colors: Dictionary = {}
var is_first_person: bool = false
var is_shift_lock: bool = false
var crosshair: ColorRect = null
var respawn_position: Vector3 = Vector3.ZERO
var _teleport_ready_at_msec: int = 0
var move_speed: float = MOVE_SPEED
var sprint_multiplier: float = SPRINT_MULTIPLIER
var jump_velocity_setting: float = JUMP_VELOCITY
var _logical_move_speed: float = MOVE_SPEED
var _logical_jump_velocity: float = JUMP_VELOCITY
var _is_respawning: bool = false
var _death_audio_player: AudioStreamPlayer = null
var spawn_points: Array[Vector3] = []
var _last_spawn_index: int = -1
var _has_checkpoint: bool = false
var _studio_touching_parts: Dictionary = {}
var _spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _chat_bubble_label: Label3D = null
var _chat_bubble_back: MeshInstance3D = null
var _chat_bubble_timer: Timer = null
var _remote_interp_initialized: bool = false
var _remote_position_buffer: Array[Dictionary] = []
var _remote_last_network_position: Vector3 = Vector3.ZERO
var _remote_last_network_rotation: Vector3 = Vector3.ZERO
var _remote_last_network_visuals_y: float = 0.0
var _remote_last_network_grounded: bool = false
var _remote_render_position: Vector3 = Vector3.ZERO
var _remote_render_rotation: Vector3 = Vector3.ZERO
var _remote_render_visuals_y: float = 0.0
var _remote_previous_render_position: Vector3 = Vector3.ZERO
var _room_visibility_filter_registered: bool = false
var _awaiting_authoritative_respawn: bool = false
var _respawn_request_token: int = 0
var _respawn_requested_at_msec: int = 0
var _default_collision_layer: int = 1
var _default_collision_mask: int = 1
var _last_chat_bubble_msec: int = 0
var _character_state: int = CharacterState.IDLE
var _coyote_time_left: float = 0.0
var _jump_buffer_time_left: float = 0.0
var _last_sprinting_input: bool = false
var _climbing_active: bool = false
var _climb_surface: Node = null
var _climb_normal: Vector3 = Vector3.ZERO
var _climb_surface_lost_time: float = 0.0
var _ledge_mantle_active: bool = false
var _ledge_mantle_target: Vector3 = Vector3.ZERO
var _ledge_hang_active: bool = false
var _ledge_grab_window_left: float = 0.0
var _ledge_hang_position: Vector3 = Vector3.ZERO
var _ledge_hang_normal: Vector3 = Vector3.ZERO
var _ledge_hang_top_position: Vector3 = Vector3.ZERO
var _swimming_active: bool = false
var _water_volume: Node = null
var _seated_part: Node3D = null
var _seat_exit_ready_at_msec: int = 0
var _death_fragment_root: Node3D = null
var _death_visual_active: bool = false
var _last_safe_position: Vector3 = Vector3.ZERO
var _previous_physics_position: Vector3 = Vector3.ZERO
var _has_safe_position: bool = false
var _camera_anchor_previous_position: Vector3 = Vector3.ZERO
var _camera_anchor_current_position: Vector3 = Vector3.ZERO
var _camera_anchor_initialized: bool = false
var _embedded_camera_dragging: bool = false
var _last_physics_timestamp_us: int = 0
var _physics_step_duration_us: int = 16667
var _camera_desired_spring_length: float = 8.5
var _stuck_timer: float = 0.0
var _face_decal: MeshInstance3D = null
var _chest_badge_decal: MeshInstance3D = null
var _shirt_front_decal: MeshInstance3D = null
var _shirt_back_decal: MeshInstance3D = null
var _shirt_left_side_decal: MeshInstance3D = null
var _shirt_right_side_decal: MeshInstance3D = null
var _shirt_up_decal: MeshInstance3D = null
var _shirt_down_decal: MeshInstance3D = null
var _left_arm_shirt_decal: MeshInstance3D = null
var _right_arm_shirt_decal: MeshInstance3D = null
var _left_arm_shirt_back_decal: MeshInstance3D = null
var _right_arm_shirt_back_decal: MeshInstance3D = null
var _left_arm_shirt_outer_decal: MeshInstance3D = null
var _left_arm_shirt_inner_decal: MeshInstance3D = null
var _right_arm_shirt_outer_decal: MeshInstance3D = null
var _right_arm_shirt_inner_decal: MeshInstance3D = null
var _left_arm_shirt_up_decal: MeshInstance3D = null
var _left_arm_shirt_down_decal: MeshInstance3D = null
var _right_arm_shirt_up_decal: MeshInstance3D = null
var _right_arm_shirt_down_decal: MeshInstance3D = null
var _left_pants_front_decal: MeshInstance3D = null
var _right_pants_front_decal: MeshInstance3D = null
var _left_pants_back_decal: MeshInstance3D = null
var _right_pants_back_decal: MeshInstance3D = null
var _left_pants_outer_decal: MeshInstance3D = null
var _left_pants_inner_decal: MeshInstance3D = null
var _right_pants_outer_decal: MeshInstance3D = null
var _right_pants_inner_decal: MeshInstance3D = null
var _left_pants_up_decal: MeshInstance3D = null
var _left_pants_down_decal: MeshInstance3D = null
var _right_pants_up_decal: MeshInstance3D = null
var _right_pants_down_decal: MeshInstance3D = null
var _applied_avatar_visual_key: String = ""
var _avatar_attachment_root: Node3D = null
var _applied_avatar_attachment_key: String = ""
static var _cached_custom_character_limbs: Array = []
static var _custom_character_cache_attempted: bool = false


func _process(delta: float) -> void:
	if _is_preview_instance():
		return
	if not _is_local_authority_safe():
		return
	_apply_mobile_camera_delta()
	_update_local_camera_rig_render_phase(delta)

func _enter_tree() -> void:
	var synchronizer := get_node_or_null("StateSynchronizer") as MultiplayerSynchronizer
	if synchronizer != null and not _is_preview_instance():
		_configure_state_synchronizer_for(synchronizer)

func _ready() -> void:
	_spawn_rng.randomize()
	respawn_position = global_position
	current_health = MAX_HEALTH
	_last_safe_position = global_position
	_previous_physics_position = global_position
	_has_safe_position = true
	if _is_preview_instance():
		# UI previews use the authored visual rig directly. Physics, camera,
		# chat and the runtime Humanoid contract are deliberately skipped so
		# a social page can render many avatars without blocking the main loop.
		name_label.visible = false
		visuals.visible = true
		visuals.scale = Vector3.ONE
		visuals.position = Vector3.ZERO
		if (
			not bool(get_meta("bobux_default_character_preview", false))
			and not bool(get_meta("bobux_skip_custom_character_mesh", false))
		):
			_load_custom_character()
		_set_collision_enabled(false)
		if not bool(get_meta("bobux_studio_character_preview", false)):
			_fit_ui_preview_visuals()
		if not bool(get_meta("bobux_default_character_preview", false)):
			_apply_avatar_color_if_needed()
			_apply_avatar_visuals_if_needed()
		_apply_animation_pose()
		return
	_configure_physics_motion()
	apply_world_stud_scale(world_stud_scale)
	_configure_camera_visual_stability()
	if spring_arm != null:
		_camera_desired_spring_length = spring_arm.spring_length
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_ensure_chat_bubble_nodes()
	ensure_roblox_character_contract()
	_configure_state_synchronizer()
	if not _is_studio_playtest_instance() and NetworkManager != null and NetworkManager.has_signal("room_summaries_updated") and not NetworkManager.room_summaries_updated.is_connected(_on_room_summaries_updated):
		NetworkManager.room_summaries_updated.connect(_on_room_summaries_updated)
	spring_arm.add_excluded_object(get_rid())
	var is_auth := _is_local_authority_safe()
	player_camera.current = is_auth
	if is_auth:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var mobile_runtime: Node = _get_mobile_runtime()
		if mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta")):
			mobile_runtime.call("set_gameplay_touch_controls_enabled", true)
		
		# Setup Crosshair
		var ui_layer = CanvasLayer.new()
		add_child(ui_layer)
		crosshair = ColorRect.new()
		crosshair.custom_minimum_size = Vector2(8, 8)
		crosshair.color = Color.WHITE
		crosshair.set_anchors_preset(Control.PRESET_CENTER)
		crosshair.visible = false
		ui_layer.add_child(crosshair)
		_death_audio_player = AudioStreamPlayer.new()
		_death_audio_player.name = "DeathAudioPlayer"
		_death_audio_player.bus = "Master"
		_death_audio_player.stream = _load_audio_stream_from_path(DEATH_SOUND_PATH)
		add_child(_death_audio_player)
	else:
		_remote_interp_initialized = false
		_remote_position_buffer.clear()
		name_label.visible = true
		# AUDIT FIX MEDIUM-1: Disable collision shapes for remote players on the
		# dedicated server so the physics engine doesn't waste CPU on O(NВІ)
		# broad-phase sweeps across 1,000 player bodies.
	name_label.text = display_name
	_load_custom_character()
	_fit_collision_shapes_to_visuals()
	_configure_collision_profile()
	_apply_avatar_color_if_needed()
	_apply_avatar_visuals_if_needed()
	_apply_animation_pose()
	_sync_authoritative_replication_state(true)
	# FIX Eye Strain Bug: Reset physics interpolation so Godot doesn't
	# interpolate from Vector3.ZERO to the actual spawn position on the
	# first rendered frame, which caused shadow jitter and camera shake.
	call_deferred("_reset_all_physics_interpolation")

func _exit_tree() -> void:
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	if not _is_preview_instance() and _is_local_authority_safe():
		var mobile_runtime: Node = _get_mobile_runtime()
		if mobile_runtime != null:
			mobile_runtime.call("set_gameplay_touch_controls_enabled", false)

func _unhandled_input(event: InputEvent) -> void:
	if _is_preview_instance():
		return
	if not _is_local_authority_safe():
		return
	if _is_text_input_focused():
		return
	
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		if not is_first_person:
			is_shift_lock = not is_shift_lock
			if is_shift_lock:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if crosshair: crosshair.visible = true
				var tween = create_tween()
				tween.tween_property(spring_arm, "position:x", 1.5, 0.15)
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if crosshair: crosshair.visible = false
				var tween = create_tween()
				tween.tween_property(spring_arm, "position:x", 0.0, 0.15)
				
	_handle_camera_pointer_input(event)


func handle_embedded_playtest_pointer_input(event: InputEvent) -> void:
	if _is_preview_instance() or not _is_local_authority_safe():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_embedded_camera_dragging = button.pressed
			if not is_first_person and not is_shift_lock:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if button.pressed else Input.MOUSE_MODE_VISIBLE
			return
	if event is InputEventMouseMotion and _embedded_camera_dragging:
		var motion := event as InputEventMouseMotion
		_apply_camera_rotation_delta(motion.relative.x * MOUSE_SENSITIVITY, motion.relative.y * MOUSE_SENSITIVITY)
		return
	_handle_camera_pointer_input(event)


func _handle_camera_pointer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not is_first_person and not is_shift_lock: # Only RMB controls camera in 3rd person naturally
				if event.pressed:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_camera_desired_spring_length(_camera_desired_spring_length - 1.0)
			_update_first_person_mode()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_camera_desired_spring_length(_camera_desired_spring_length + 1.0)
			_update_first_person_mode()
			
	var mobile_runtime = _get_mobile_runtime()
	var is_mobile: bool = mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta"))
	if event is InputEventMouseMotion and not is_mobile and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or is_first_person or is_shift_lock):
		if (is_first_person or is_shift_lock) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		_apply_camera_rotation_delta(mouse_event.relative.x * MOUSE_SENSITIVITY, mouse_event.relative.y * MOUSE_SENSITIVITY)

func _physics_process(delta: float) -> void:
	if _is_preview_instance():
		_apply_avatar_color_if_needed()
		_apply_avatar_visuals_if_needed()
		return
	_sync_body_collision_transforms()
	if _is_network_gameplay_frozen():
		velocity = Vector3.ZERO
		_apply_avatar_color_if_needed()
		_apply_avatar_visuals_if_needed()
		_apply_animation_pose()
		return
		
	if _is_local_authority_safe():
		if _is_respawning:
			velocity = Vector3.ZERO
			_apply_avatar_color_if_needed()
			_apply_avatar_visuals_if_needed()
			_apply_animation_pose()
			return
		if global_position.y < FALL_RESPAWN_Y:
			_handle_void_fall()
			if _is_respawning:
				_apply_avatar_color_if_needed()
				_apply_avatar_visuals_if_needed()
				_apply_animation_pose()
				return
		# Mobile Shift Lock Sync
		var mobile_runtime = _get_mobile_runtime()
		if mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta")):
			var target_sl: bool = bool(mobile_runtime.call("is_shift_lock_enabled"))
			if is_shift_lock != target_sl:
				is_shift_lock = target_sl
				if is_shift_lock:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					if crosshair: crosshair.visible = true
					var tween = create_tween()
					tween.tween_property(spring_arm, "position:x", 1.5, 0.15)
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					if crosshair: crosshair.visible = false
					var tween = create_tween()
					tween.tween_property(spring_arm, "position:x", 0.0, 0.15)
		_run_local_movement(delta)
		_emit_studio_playtest_touch_events()
		_update_safe_position_and_unstuck(delta)
		_record_local_camera_physics_anchor()
		_update_animation_state(delta)
		_sync_authoritative_replication_state()
	else:
		if ENABLE_REMOTE_INTERPOLATION:
			_apply_remote_interpolation(delta)
		else:
			_remote_interp_initialized = false
		_update_remote_animation_from_interpolation(delta)
	_apply_avatar_color_if_needed()
	_apply_avatar_visuals_if_needed()
	_apply_animation_pose()

# This function buffers remote snapshots and replays them with a small delay.
# We intentionally keep the playback simple and stable because aggressive spline
# interpolation caused visible overshoot and backtracking under WebSocket jitter.
func _apply_remote_interpolation(delta: float) -> void:
	var net_pos: Vector3 = network_position - network_position_origin
	var net_rot: Vector3 = network_rotation
	var net_vis_y: float = network_visuals_y
	if not _remote_interp_initialized:
		_remote_interp_initialized = true
		_remote_last_network_position = net_pos
		_remote_last_network_rotation = net_rot
		_remote_last_network_visuals_y = net_vis_y
		_remote_last_network_grounded = network_grounded
		_remote_render_position = net_pos
		_remote_render_rotation = net_rot
		_remote_render_visuals_y = net_vis_y
		_remote_previous_render_position = net_pos
		_remote_position_buffer.clear()
		global_position = net_pos
		rotation = net_rot
		visuals.rotation.y = net_vis_y
		return
	var horizontal_delta: Vector2 = Vector2(net_pos.x - _remote_last_network_position.x, net_pos.z - _remote_last_network_position.z)
	var vertical_delta: float = absf(net_pos.y - _remote_last_network_position.y)
	var pos_changed: bool = horizontal_delta.length() > REMOTE_SNAPSHOT_POSITION_EPSILON or vertical_delta > REMOTE_SNAPSHOT_VERTICAL_EPSILON
	var rot_changed: bool = absf(wrapf(net_rot.y - _remote_last_network_rotation.y, -PI, PI)) > REMOTE_SNAPSHOT_ROTATION_EPSILON
	var vis_changed: bool = absf(wrapf(net_vis_y - _remote_last_network_visuals_y, -PI, PI)) > REMOTE_SNAPSHOT_VISUAL_Y_EPSILON
	var grounded_changed: bool = network_grounded != _remote_last_network_grounded
	if pos_changed or rot_changed or vis_changed or grounded_changed:
		_remote_last_network_position = net_pos
		_remote_last_network_rotation = net_rot
		_remote_last_network_visuals_y = net_vis_y
		_remote_last_network_grounded = network_grounded
		_remote_position_buffer.append({
			"t": float(Time.get_ticks_msec()),
			"p": net_pos,
			"r": net_rot,
			"v": net_vis_y,
			"vel": network_velocity,
			"g": network_grounded
		})
		while _remote_position_buffer.size() > POSITION_BUFFER_MAX_SIZE:
			_remote_position_buffer.pop_front()
	var evict_threshold: float = float(Time.get_ticks_msec()) - BUFFER_MAX_AGE_MS
	while not _remote_position_buffer.is_empty() and float(_remote_position_buffer[0].get("t", 0.0)) < evict_threshold:
		_remote_position_buffer.pop_front()
	_interpolate_from_jitter_buffer(delta)
	global_position = _remote_render_position
	rotation = _remote_render_rotation
	visuals.rotation.y = _remote_render_visuals_y

func _sync_authoritative_replication_state(force: bool = false) -> void:
	if not force and not _is_local_authority_safe():
		return
	var grounded_now: bool = is_on_floor()
	var published_position: Vector3 = global_position + network_position_origin
	published_position.x = snappedf(published_position.x, NETWORK_POSITION_SNAP_STEP)
	published_position.z = snappedf(published_position.z, NETWORK_POSITION_SNAP_STEP)
	published_position.y = snappedf(published_position.y, NETWORK_GROUNDED_Y_SNAP_STEP if grounded_now else NETWORK_AIRBORNE_Y_SNAP_STEP)
	var published_velocity: Vector3 = velocity
	published_velocity.x = snappedf(published_velocity.x, NETWORK_VELOCITY_SNAP_STEP)
	published_velocity.z = snappedf(published_velocity.z, NETWORK_VELOCITY_SNAP_STEP)
	published_velocity.y = 0.0 if grounded_now and absf(published_velocity.y) <= 0.6 else snappedf(published_velocity.y, NETWORK_VELOCITY_SNAP_STEP)
	var published_rotation := Vector3.ZERO
	published_rotation.y = snappedf(rotation.y, NETWORK_ROOT_ROTATION_SNAP_STEP)
	network_position = published_position
	network_rotation = published_rotation
	network_velocity = published_velocity
	network_visuals_y = snappedf(visuals.rotation.y, NETWORK_ROOT_ROTATION_SNAP_STEP)
	network_grounded = grounded_now
	network_character_state = _character_state
	_sync_humanoid_runtime_properties(grounded_now)

func _update_remote_animation_from_interpolation(delta: float) -> void:
	if _is_local_authority_safe() or delta <= 0.0:
		return
	if network_character_state == CharacterState.CLIMBING:
		animation_airborne = false
		animation_weight = clampf(absf(network_velocity.y) / maxf(_world_units(CLIMB_SPEED), 0.001), 0.25, 1.0)
		animation_cycle = wrapf(animation_cycle + delta * WALK_CYCLE_SPEED * maxf(animation_weight, 0.45), 0.0, TAU)
		return
	animation_airborne = network_character_state == CharacterState.JUMPING or network_character_state == CharacterState.FALLING
	var horizontal_delta: Vector3 = global_position - _remote_previous_render_position
	_remote_previous_render_position = global_position
	var rendered_horizontal_speed: float = Vector2(horizontal_delta.x, horizontal_delta.z).length() / maxf(delta, 0.001)
	var authoritative_horizontal_speed: float = Vector2(network_velocity.x, network_velocity.z).length()
	var horizontal_speed: float = maxf(rendered_horizontal_speed, authoritative_horizontal_speed)
	var target_weight: float = 0.0 if animation_airborne else clampf(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0)
	animation_weight = move_toward(animation_weight, target_weight, delta * 8.0)
	if animation_weight > 0.035 and not animation_airborne:
		animation_cycle = wrapf(animation_cycle + delta * WALK_CYCLE_SPEED * maxf(animation_weight, 0.35), 0.0, TAU)
	else:
		animation_cycle = 0.0

func _interpolate_from_jitter_buffer(delta: float) -> void:
	if _remote_position_buffer.is_empty():
		return
	var render_time: float = float(Time.get_ticks_msec()) - INTERPOLATION_BUFFER_DELAY_MS
	var idx_before: int = -1
	var idx_after: int = -1
	for i in range(_remote_position_buffer.size()):
		if float(_remote_position_buffer[i].get("t", 0.0)) <= render_time:
			idx_before = i
		else:
			idx_after = i
			break
	if idx_before < 0:
		var first: Dictionary = _remote_position_buffer[0]
		_remote_render_position = Vector3(first.get("p", _remote_render_position))
		_remote_render_rotation = Vector3(first.get("r", _remote_render_rotation))
		_remote_render_visuals_y = float(first.get("v", _remote_render_visuals_y))
		if bool(first.get("g", false)):
			_remote_render_position.y = snappedf(_remote_render_position.y, NETWORK_GROUNDED_Y_SNAP_STEP)
		return
	if idx_after < 0:
		var last: Dictionary = _remote_position_buffer[_remote_position_buffer.size() - 1]
		var target_pos: Vector3 = Vector3(last.get("p", _remote_render_position))
		var target_rot: Vector3 = Vector3(last.get("r", _remote_render_rotation))
		var target_vis_y: float = float(last.get("v", _remote_render_visuals_y))
		var target_grounded: bool = bool(last.get("g", network_grounded))
		var extrapolation_window_ms: float = clampf(render_time - float(last.get("t", render_time)), 0.0, MAX_EXTRAPOLATION_MS)
		var estimated_velocity: Vector3 = _estimate_remote_snapshot_velocity()
		if estimated_velocity != Vector3.ZERO and extrapolation_window_ms > 0.0:
			var extrapolation_seconds: float = extrapolation_window_ms / 1000.0
			target_pos.x += estimated_velocity.x * extrapolation_seconds
			target_pos.z += estimated_velocity.z * extrapolation_seconds
		var alpha: float = clampf(delta * REMOTE_POSITION_LERP_SPEED, 0.0, 1.0)
		var vertical_alpha: float = clampf(delta * (REMOTE_POSITION_LERP_SPEED * 2.8), 0.0, 1.0)
		var rot_alpha: float = clampf(delta * REMOTE_ROTATION_LERP_SPEED, 0.0, 1.0)
		if _remote_render_position.distance_to(target_pos) > REMOTE_HARD_SNAP_DISTANCE:
			_remote_render_position = target_pos
		else:
			_remote_render_position.x = lerpf(_remote_render_position.x, target_pos.x, alpha)
			_remote_render_position.z = lerpf(_remote_render_position.z, target_pos.z, alpha)
			if target_grounded and absf(_remote_render_position.y - target_pos.y) <= REMOTE_GROUNDED_Y_SNAP_EPSILON:
				_remote_render_position.y = target_pos.y
			else:
				_remote_render_position.y = lerpf(_remote_render_position.y, target_pos.y, vertical_alpha)
		_remote_render_rotation.x = lerp_angle(_remote_render_rotation.x, target_rot.x, rot_alpha)
		_remote_render_rotation.y = lerp_angle(_remote_render_rotation.y, target_rot.y, rot_alpha)
		_remote_render_rotation.z = lerp_angle(_remote_render_rotation.z, target_rot.z, rot_alpha)
		_remote_render_visuals_y = lerp_angle(_remote_render_visuals_y, target_vis_y, rot_alpha)
		return
	var entry_a: Dictionary = _remote_position_buffer[idx_before]
	var entry_b: Dictionary = _remote_position_buffer[idx_after]
	var t_a: float = float(entry_a.get("t", 0.0))
	var t_b: float = float(entry_b.get("t", 0.0))
	var dt: float = maxf(t_b - t_a, 1.0)
	var t: float = clampf((render_time - t_a) / dt, 0.0, 1.0)
	var pos_a: Vector3 = Vector3(entry_a.get("p", Vector3.ZERO))
	var pos_b: Vector3 = Vector3(entry_b.get("p", Vector3.ZERO))
	var rot_a: Vector3 = Vector3(entry_a.get("r", Vector3.ZERO))
	var rot_b: Vector3 = Vector3(entry_b.get("r", Vector3.ZERO))
	var vis_y_a: float = float(entry_a.get("v", 0.0))
	var vis_y_b: float = float(entry_b.get("v", 0.0))
	var vel_a: Vector3 = Vector3(entry_a.get("vel", Vector3.ZERO))
	var vel_b: Vector3 = Vector3(entry_b.get("vel", vel_a))
	var grounded_a: bool = bool(entry_a.get("g", false))
	var grounded_b: bool = bool(entry_b.get("g", grounded_a))
	var delta_seconds: float = dt / 1000.0
	var interpolated_x: float = _hermite_float(pos_a.x, pos_b.x, vel_a.x * delta_seconds, vel_b.x * delta_seconds, t)
	var interpolated_z: float = _hermite_float(pos_a.z, pos_b.z, vel_a.z * delta_seconds, vel_b.z * delta_seconds, t)
	var interpolated_y: float = lerpf(pos_a.y, pos_b.y, t)
	if grounded_a and grounded_b and absf(pos_b.y - pos_a.y) <= 0.22 and absf(vel_b.y) <= 4.0:
		interpolated_y = pos_b.y if t >= 0.55 else interpolated_y
	_remote_render_position = Vector3(interpolated_x, interpolated_y, interpolated_z)
	_remote_render_rotation.x = lerp_angle(rot_a.x, rot_b.x, t)
	_remote_render_rotation.y = lerp_angle(rot_a.y, rot_b.y, t)
	_remote_render_rotation.z = lerp_angle(rot_a.z, rot_b.z, t)
	_remote_render_visuals_y = lerp_angle(vis_y_a, vis_y_b, t)

func _hermite_float(p0: float, p1: float, m0: float, m1: float, t: float) -> float:
	var tt: float = t * t
	var ttt: float = tt * t
	var h00: float = (2.0 * ttt) - (3.0 * tt) + 1.0
	var h10: float = ttt - (2.0 * tt) + t
	var h01: float = (-2.0 * ttt) + (3.0 * tt)
	var h11: float = ttt - tt
	return (h00 * p0) + (h10 * m0) + (h01 * p1) + (h11 * m1)

func _estimate_remote_snapshot_velocity() -> Vector3:
	if not network_velocity.is_zero_approx():
		return network_velocity
	if _remote_position_buffer.size() < 2:
		return Vector3.ZERO
	var latest: Dictionary = _remote_position_buffer[_remote_position_buffer.size() - 1]
	var previous: Dictionary = _remote_position_buffer[_remote_position_buffer.size() - 2]
	var latest_pos: Vector3 = Vector3(latest.get("p", Vector3.ZERO))
	var previous_pos: Vector3 = Vector3(previous.get("p", latest_pos))
	var latest_time: float = float(latest.get("t", 0.0))
	var previous_time: float = float(previous.get("t", latest_time))
	var dt_seconds: float = maxf((latest_time - previous_time) / 1000.0, 0.001)
	return (latest_pos - previous_pos) / dt_seconds

func _run_local_movement(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	_update_jump_timers(delta, on_floor)
	var jump_pressed := Input.is_action_just_pressed("jump") or _consume_mobile_jump_pressed()
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var mobile_input_vector: Vector2 = _get_mobile_move_vector()
	if mobile_input_vector.length_squared() > input_vector.length_squared():
		input_vector = mobile_input_vector
	if _update_seated_movement(jump_pressed):
		return
	_update_swimming_contact()
	if _swimming_active:
		_run_swimming_movement(delta, input_vector, jump_pressed)
		return
	if _ledge_hang_active:
		_update_ledge_hang(delta, input_vector, jump_pressed)
		return
	if _ledge_mantle_active:
		_update_ledge_mantle(delta)
		return
	if _is_text_input_focused():
		_stop_climbing()
		if not on_floor:
			velocity.y = maxf(velocity.y - _get_current_gravity() * delta, -_world_units(MAX_FALL_SPEED))
		elif velocity.y < 0.0:
			velocity.y = _world_units(FLOOR_STICK_VELOCITY)
		velocity.x = move_toward(velocity.x, 0.0, _world_units(GROUND_DECELERATION) * delta)
		velocity.z = move_toward(velocity.z, 0.0, _world_units(GROUND_DECELERATION) * delta)
		move_and_slide()
		if is_on_ceiling() and velocity.y > 0.0:
			velocity.y = 0.0
		_update_character_state(false)
		return
		
	var current_speed: float = move_speed
	var mobile_runtime = _get_mobile_runtime()
	var is_mobile_platform: bool = mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta"))
	if is_mobile_platform:
		_last_sprinting_input = bool(mobile_runtime.call("is_sprint_enabled"))
	else:
		_last_sprinting_input = Input.is_physical_key_pressed(KEY_CTRL)
	if _last_sprinting_input:
		current_speed *= sprint_multiplier
		
	if jump_pressed:
		_jump_buffer_time_left = JUMP_BUFFER_TIME
		_ledge_grab_window_left = LEDGE_GRAB_WINDOW_SECONDS
	else:
		_ledge_grab_window_left = maxf(_ledge_grab_window_left - delta, 0.0)

	var local_input_direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)
	
	var cam_basis: Basis = Basis.from_euler(Vector3(0, camera_pivot.rotation.y, 0))
	var world_move_direction: Vector3 = cam_basis * local_input_direction
	world_move_direction.y = 0.0
	
	if is_shift_lock or is_first_person:
		visuals.rotation.y = camera_pivot.rotation.y + PI
		if world_move_direction.length_squared() > 0.001:
			world_move_direction = world_move_direction.normalized()
	elif world_move_direction.length_squared() > 0.001:
		world_move_direction = world_move_direction.normalized()
		var target_angle: float = atan2(world_move_direction.x, world_move_direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, clampf(delta * LOCAL_TURN_LERP_SPEED, 0.0, 1.0))

	if on_floor and not jump_pressed and Time.get_ticks_msec() >= _seat_exit_ready_at_msec:
		var nearby_seat := _find_seat_below()
		if nearby_seat != null:
			_enter_seat(nearby_seat)
			_update_seated_movement(false)
			return
	if not on_floor and world_move_direction.length_squared() > 0.001 and _try_begin_ledge_hang(world_move_direction, jump_pressed or _ledge_grab_window_left > 0.0):
		_update_ledge_hang(delta, input_vector, false)
		return

	if _update_climbing_movement(delta, input_vector, world_move_direction, cam_basis, jump_pressed):
		return
		
	var desired_horizontal_velocity: Vector3 = world_move_direction * current_speed
	var slope_assist_y: float = 0.0
	if on_floor and world_move_direction.length_squared() > 0.001:
		var floor_normal: Vector3 = get_floor_normal()
		if floor_normal.dot(Vector3.UP) > 0.08 and floor_normal.dot(Vector3.UP) < 0.995:
			var slope_velocity: Vector3 = (world_move_direction * current_speed).slide(floor_normal)
			if slope_velocity.length_squared() > 0.001:
				desired_horizontal_velocity = Vector3(slope_velocity.x, 0.0, slope_velocity.z)
				slope_assist_y = clampf(
					slope_velocity.y * SLOPE_CLIMB_ASSIST,
					-_world_units(SLOPE_MAX_UP_VELOCITY),
					_world_units(SLOPE_MAX_UP_VELOCITY)
				)
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if world_move_direction.length_squared() > 0.001:
		var accel: float = _world_units(GROUND_ACCELERATION if on_floor else AIR_ACCELERATION)
		horizontal_velocity = horizontal_velocity.move_toward(desired_horizontal_velocity, accel * delta)
	else:
		var decel: float = _world_units(GROUND_DECELERATION if on_floor else AIR_DECELERATION)
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, decel * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	if on_floor:
		if slope_assist_y > 0.0:
			velocity.y = move_toward(maxf(velocity.y, 0.0), slope_assist_y, _world_units(SLOPE_VERTICAL_ACCELERATION) * delta)
		elif velocity.y < 0.0:
			velocity.y = _world_units(FLOOR_STICK_VELOCITY)
		if _should_consume_buffered_jump(on_floor):
			velocity.y = jump_velocity_setting
			_jump_buffer_time_left = 0.0
			_coyote_time_left = 0.0
			on_floor = false
	else:
		if _should_consume_buffered_jump(on_floor):
			velocity.y = jump_velocity_setting
			_jump_buffer_time_left = 0.0
			_coyote_time_left = 0.0
		else:
			velocity.y = maxf(velocity.y - _get_current_gravity() * delta, -_world_units(MAX_FALL_SPEED))
	# Keep floor snap active except during upward jump to prevent
	# getting stuck on ledges or teleporting off edges.
	if velocity.y > 0.5:
		floor_snap_length = 0.0
	else:
		floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
	move_and_slide()
	_try_auto_step_up(world_move_direction, delta, on_floor)
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0
	_update_character_state(_last_sprinting_input)

func _update_jump_timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_coyote_time_left = COYOTE_TIME
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)
	_jump_buffer_time_left = maxf(_jump_buffer_time_left - delta, 0.0)

func _should_consume_buffered_jump(on_floor: bool) -> bool:
	return _jump_buffer_time_left > 0.0 and (on_floor or _coyote_time_left > 0.0)

func _update_character_state(is_sprinting: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var next_state := CharacterState.IDLE
	if _is_respawning or current_health <= 0:
		next_state = CharacterState.DEAD
	elif _seated_part != null:
		next_state = CharacterState.SEATED
	elif _swimming_active:
		next_state = CharacterState.SWIMMING
	elif _climbing_active or _ledge_hang_active or _ledge_mantle_active:
		next_state = CharacterState.CLIMBING
	elif not is_on_floor():
		next_state = CharacterState.JUMPING if velocity.y > 0.0 else CharacterState.FALLING
	elif horizontal_speed > 0.35:
		next_state = CharacterState.RUNNING if is_sprinting else CharacterState.WALKING
	_set_character_state(next_state)

func _set_character_state(next_state: int) -> void:
	if _character_state == next_state:
		return
	_character_state = next_state
	var humanoid := get_node_or_null("Humanoid")
	if humanoid != null:
		humanoid.set_meta("HumanoidState", _character_state_name(next_state))
		humanoid.set_meta("MoveDirection", Vector3(velocity.x, 0.0, velocity.z).normalized() if Vector2(velocity.x, velocity.z).length_squared() > 0.001 else Vector3.ZERO)

func _update_climbing_movement(delta: float, input_vector: Vector2, world_move_direction: Vector3, camera_basis: Basis, jump_pressed: bool) -> bool:
	var probe_direction := -_climb_normal if _climbing_active and _climb_normal.length_squared() > 0.1 else world_move_direction
	var climb_hit := _probe_climbable_surface(probe_direction)
	if _climbing_active:
		if jump_pressed:
			_detach_from_climb(true)
			floor_snap_length = 0.0
			move_and_slide()
			_update_character_state(false)
			return true
		if climb_hit.is_empty():
			_climb_surface_lost_time += delta
			if _climb_surface_lost_time > CLIMB_LOST_SURFACE_GRACE:
				var was_moving_up := input_vector.y < -0.1
				var release_normal := _climb_normal
				_stop_climbing()
				if was_moving_up and release_normal.length_squared() > 0.1:
					velocity = (
						-release_normal * _world_units(CLIMB_LEDGE_FORWARD_SPEED)
						+ Vector3.UP * _world_units(CLIMB_LEDGE_UP_SPEED)
					)
					floor_snap_length = 0.0
					move_and_slide()
					_update_character_state(false)
					return true
				return false
		else:
			_accept_climb_hit(climb_hit)
	elif not climb_hit.is_empty() and input_vector.y < -0.08 and jump_pressed:
		var hit_normal: Vector3 = Vector3(climb_hit.get("normal", Vector3.ZERO))
		if world_move_direction.length_squared() > 0.001 and world_move_direction.dot(-hit_normal) > 0.08:
			_accept_climb_hit(climb_hit)

	if not _climbing_active:
		return false
	var camera_right := camera_basis * Vector3.RIGHT
	camera_right.y = 0.0
	camera_right = camera_right.slide(_climb_normal)
	if camera_right.length_squared() <= 0.001:
		camera_right = Vector3.UP.cross(_climb_normal)
	if camera_right.length_squared() > 0.001:
		camera_right = camera_right.normalized()
	var vertical_input := clampf(-input_vector.y, -1.0, 1.0)
	var side_input := clampf(input_vector.x, -1.0, 1.0)
	velocity = (
		Vector3.UP * vertical_input * _world_units(CLIMB_SPEED)
		+ camera_right * side_input * _world_units(CLIMB_SIDE_SPEED)
		- _climb_normal * _world_units(CLIMB_SURFACE_PULL_SPEED)
	)
	floor_snap_length = 0.0
	move_and_slide()
	_set_character_state(CharacterState.CLIMBING)
	return true

func _try_begin_ledge_hang(direction: Vector3, jump_pressed: bool) -> bool:
	if _ledge_hang_active or _ledge_mantle_active or _climbing_active or _swimming_active or _seated_part != null:
		return false
	# Walking into a wall may hold the ledge, but climbing onto it must be an
	# explicit jump/up action instead of an automatic teleport over the edge.
	if not jump_pressed:
		return false
	if get_world_3d() == null or collision_body == null or collision_body.shape == null:
		return false
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length_squared() <= 0.001:
		return false
	flat_direction = flat_direction.normalized()
	var space := get_world_3d().direct_space_state
	var low_origin := global_position + Vector3.UP * _world_units(1.75)
	var low_query := PhysicsRayQueryParameters3D.create(low_origin, low_origin + flat_direction * _world_units(LEDGE_PROBE_DISTANCE))
	low_query.exclude = [get_rid()]
	low_query.collision_mask = _get_player_and_world_collision_mask()
	var low_hit := space.intersect_ray(low_query)
	if low_hit.is_empty() or _node_has_special_role(low_hit.get("collider"), ["roblox_water"], ["Water"]):
		return false
	var upper_origin := global_position + Vector3.UP * _world_units(4.75)
	var upper_query := PhysicsRayQueryParameters3D.create(upper_origin, upper_origin + flat_direction * _world_units(LEDGE_PROBE_DISTANCE))
	upper_query.exclude = [get_rid()]
	upper_query.collision_mask = _get_player_and_world_collision_mask()
	if not space.intersect_ray(upper_query).is_empty():
		return false
	var down_origin := (
		global_position
		+ flat_direction * _world_units(LEDGE_PROBE_DISTANCE + 0.38)
		+ Vector3.UP * _world_units(5.15)
	)
	var down_query := PhysicsRayQueryParameters3D.create(down_origin, down_origin + Vector3.DOWN * _world_units(5.0))
	down_query.exclude = [get_rid()]
	down_query.collision_mask = _get_player_and_world_collision_mask()
	var top_hit := space.intersect_ray(down_query)
	if top_hit.is_empty():
		return false
	var top_position: Vector3 = top_hit.get("position", global_position)
	var ledge_height := top_position.y - global_position.y
	if ledge_height < _world_units(0.35) or ledge_height > _world_units(LEDGE_MANTLE_MAX_HEIGHT):
		return false
	var wall_normal: Vector3 = Vector3(low_hit.get("normal", -flat_direction))
	wall_normal.y = 0.0
	if wall_normal.length_squared() <= 0.001:
		wall_normal = -flat_direction
	wall_normal = wall_normal.normalized()
	_ledge_hang_normal = wall_normal
	_ledge_hang_top_position = top_position
	_ledge_hang_position = Vector3(
		top_position.x,
		top_position.y - _world_units(LEDGE_HANG_HAND_HEIGHT),
		top_position.z
	) + wall_normal * _world_units(LEDGE_HANG_WALL_CLEARANCE)
	_ledge_hang_active = true
	_ledge_grab_window_left = 0.0
	_stop_climbing()
	velocity = Vector3.ZERO
	floor_snap_length = 0.0
	_set_character_state(CharacterState.CLIMBING)
	return true

func _update_ledge_hang(delta: float, input_vector: Vector2, jump_pressed: bool) -> void:
	if not _ledge_hang_active:
		return
	if jump_pressed or input_vector.y > 0.35:
		_release_ledge_hang(jump_pressed)
		return
	if input_vector.y < -0.15:
		_ledge_mantle_target = (
			Vector3(_ledge_hang_top_position.x, _ledge_hang_top_position.y + _world_units(0.08), _ledge_hang_top_position.z)
			- _ledge_hang_normal * _world_units(0.42)
		)
		_ledge_hang_active = false
		_ledge_mantle_active = true
		return
	global_position = global_position.move_toward(_ledge_hang_position, _world_units(LEDGE_HANG_SNAP_SPEED) * delta)
	velocity = Vector3.ZERO
	floor_snap_length = 0.0
	_set_character_state(CharacterState.CLIMBING)

func _release_ledge_hang(push_away: bool) -> void:
	var release_normal := _ledge_hang_normal
	_ledge_hang_active = false
	_ledge_grab_window_left = 0.0
	_ledge_hang_normal = Vector3.ZERO
	_ledge_hang_top_position = Vector3.ZERO
	if push_away:
		velocity = release_normal * _world_units(CLIMB_JUMP_OUT_SPEED * 0.55) + Vector3.UP * jump_velocity_setting * 0.7
	else:
		velocity = Vector3.DOWN * _world_units(0.5)
	floor_snap_length = 0.0

func _update_ledge_mantle(delta: float) -> void:
	if not _ledge_mantle_active:
		return
	var distance := global_position.distance_to(_ledge_mantle_target)
	if distance <= _world_units(0.08):
		global_position = _ledge_mantle_target
		_ledge_mantle_active = false
		velocity = Vector3.ZERO
		floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
		_update_character_state(false)
		return
	global_position = global_position.move_toward(_ledge_mantle_target, _world_units(LEDGE_MANTLE_SPEED) * delta)
	velocity = Vector3.ZERO
	_set_character_state(CharacterState.CLIMBING)

func _update_swimming_contact() -> void:
	var water := _find_overlapping_special_node(["roblox_water"], ["Water"], ["TerrainWater", "Water"])
	_swimming_active = water != null
	_water_volume = water
	if _swimming_active:
		_stop_climbing()
		_ledge_hang_active = false
		_ledge_mantle_active = false
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		floor_snap_length = 0.0
	elif motion_mode != CharacterBody3D.MOTION_MODE_GROUNDED:
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)

func _run_swimming_movement(delta: float, input_vector: Vector2, jump_pressed: bool) -> void:
	var camera_basis := Basis.from_euler(Vector3(0.0, camera_pivot.rotation.y, 0.0))
	var direction := camera_basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		direction = direction.normalized()
		var target_angle := atan2(direction.x, direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, clampf(delta * LOCAL_TURN_LERP_SPEED, 0.0, 1.0))
	var vertical_input := 1.0 if Input.is_action_pressed("jump") or jump_pressed else -0.08
	var target_velocity := direction * _world_units(SWIM_SPEED)
	target_velocity.y = (
		_world_units(SWIM_VERTICAL_SPEED) * vertical_input
		if vertical_input > 0.0
		else -_world_units(SWIM_IDLE_SINK_SPEED)
	)
	velocity = velocity.move_toward(target_velocity, _world_units(SWIM_ACCELERATION) * delta)
	move_and_slide()
	_set_character_state(CharacterState.SWIMMING)

func _find_seat_below() -> Node3D:
	if get_world_3d() == null:
		return null
	var origin := global_position + Vector3.UP * _world_units(1.2)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * _world_units(2.0))
	query.exclude = [get_rid()]
	query.collision_mask = _get_player_and_world_collision_mask()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var seat_node := _special_ancestor(hit.get("collider"), [], ["Seat", "VehicleSeat"], [])
	return seat_node as Node3D if seat_node is Node3D else null

func _enter_seat(seat: Node3D) -> void:
	if seat == null or bool(seat.get_meta("Disabled", false)):
		return
	_seated_part = seat
	_stop_climbing()
	_ledge_hang_active = false
	_ledge_mantle_active = false
	velocity = Vector3.ZERO
	var humanoid := _ensure_humanoid_api_node()
	humanoid.set_meta("Sit", true)
	humanoid.set_meta("SeatPart", seat)
	seat.set_meta("Occupant", humanoid)
	_set_character_state(CharacterState.SEATED)

func _update_seated_movement(jump_pressed: bool) -> bool:
	if _seated_part == null or not is_instance_valid(_seated_part) or not _seated_part.is_inside_tree():
		_leave_seat(false)
		return false
	if jump_pressed:
		_leave_seat(true)
		return false
	var up := _seated_part.global_basis.y.normalized()
	var seat_half_height := maxf(absf(_seated_part.scale.y) * 0.5, _world_units(0.2))
	global_position = _seated_part.global_position + up * (seat_half_height + _world_units(SEAT_ATTACH_HEIGHT))
	rotation.y = _seated_part.global_rotation.y
	visuals.rotation.y = _seated_part.global_rotation.y
	velocity = Vector3.ZERO
	floor_snap_length = 0.0
	_set_character_state(CharacterState.SEATED)
	return true

func _leave_seat(apply_jump: bool) -> void:
	if _seated_part != null and is_instance_valid(_seated_part):
		_seated_part.set_meta("Occupant", null)
	_seated_part = null
	_seat_exit_ready_at_msec = Time.get_ticks_msec() + SEAT_EXIT_COOLDOWN_MSEC
	var humanoid := _ensure_humanoid_api_node()
	humanoid.set_meta("Sit", false)
	humanoid.set_meta("SeatPart", null)
	floor_snap_length = 0.0 if apply_jump else _world_units(FLOOR_SNAP_LENGTH)
	if apply_jump:
		velocity = Vector3.UP * jump_velocity_setting

func _find_overlapping_special_node(groups: Array[String], classes: Array[String], material_names: Array[String]) -> Node:
	if get_world_3d() == null or collision_body == null or collision_body.shape == null:
		return null
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_body.shape
	query.transform = collision_body.global_transform
	query.margin = 0.08
	query.collision_mask = 0x7FFFFFFF
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var node := _special_ancestor(result.get("collider"), groups, classes, material_names)
		if node != null:
			return node
	return null

func _node_has_special_role(value: Variant, groups: Array[String], classes: Array[String]) -> bool:
	return _special_ancestor(value, groups, classes, []) != null

func _special_ancestor(value: Variant, groups: Array[String], classes: Array[String], material_names: Array[String]) -> Node:
	var cursor := value as Node if value is Node else null
	while cursor != null:
		for group_name in groups:
			if cursor.is_in_group(group_name):
				return cursor
		var roblox_class := str(cursor.get_meta("roblox_class", ""))
		if roblox_class in classes:
			return cursor
		var material_name := str(cursor.get_meta("material_type", cursor.get_meta("roblox_material_name", "")))
		if material_name in material_names:
			return cursor
		cursor = cursor.get_parent()
	return null

func _probe_climbable_surface(direction: Vector3) -> Dictionary:
	if direction.length_squared() <= 0.001 or get_world_3d() == null or not is_inside_tree():
		return {}
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length_squared() <= 0.001:
		return {}
	flat_direction = flat_direction.normalized()
	var query_mask := _get_world_collision_mask()
	var side_direction := Vector3.UP.cross(flat_direction).normalized()
	# Several narrow rays keep imported TrussPart meshes climbable even when a
	# ray happens to pass through a decorative opening in their exact mesh.
	for probe_height in [1.1, 2.15, 3.2, 4.15]:
		for side_offset in [-0.34, 0.0, 0.34]:
			var origin := (
				global_position
				+ Vector3.UP * _world_units(float(probe_height))
				+ side_direction * _world_units(float(side_offset))
			)
			var query := PhysicsRayQueryParameters3D.create(
				origin,
				origin + flat_direction * _world_units(CLIMB_PROBE_DISTANCE)
			)
			query.exclude = [get_rid()]
			query.collision_mask = query_mask
			query.collide_with_bodies = true
			query.collide_with_areas = true
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and _is_climbable_collider(hit.get("collider")):
				return hit
	return {}

func _is_climbable_collider(collider: Variant) -> bool:
	var cursor := collider as Node if collider is Node else null
	while cursor != null:
		if cursor.is_in_group("roblox_climbable"):
			return true
		var roblox_class := str(cursor.get_meta("roblox_class", ""))
		var shape_type := str(cursor.get_meta("shape_type", ""))
		var semantic_name := str(cursor.get_meta("block_name", cursor.name)).to_lower()
		if (
			roblox_class == "TrussPart"
			or shape_type == "Truss"
			or "truss" in semantic_name
			or "ladder" in semantic_name
			or bool(cursor.get_meta("climbable", false))
			or bool(cursor.get_meta("Climbable", false))
		):
			return true
		cursor = cursor.get_parent()
	return false

func _accept_climb_hit(hit: Dictionary) -> void:
	_climbing_active = true
	_climb_surface = hit.get("collider") as Node if hit.get("collider") is Node else null
	_climb_normal = Vector3(hit.get("normal", Vector3.ZERO)).normalized()
	_climb_normal.y = 0.0
	if _climb_normal.length_squared() > 0.001:
		_climb_normal = _climb_normal.normalized()
	_climb_surface_lost_time = 0.0
	_coyote_time_left = 0.0
	_jump_buffer_time_left = 0.0

func _detach_from_climb(push_out: bool) -> void:
	var release_normal := _climb_normal
	_stop_climbing()
	if push_out and release_normal.length_squared() > 0.1:
		velocity = (
			release_normal * _world_units(CLIMB_JUMP_OUT_SPEED)
			+ Vector3.UP * jump_velocity_setting * CLIMB_JUMP_UP_FACTOR
		)

func _stop_climbing() -> void:
	_climbing_active = false
	_climb_surface = null
	_climb_normal = Vector3.ZERO
	_climb_surface_lost_time = 0.0

func _character_state_name(state: int) -> String:
	match state:
		CharacterState.WALKING, CharacterState.RUNNING:
			return "Running"
		CharacterState.JUMPING:
			return "Jumping"
		CharacterState.FALLING:
			return "Freefall"
		CharacterState.SEATED:
			return "Seated"
		CharacterState.CLIMBING:
			return "Climbing"
		CharacterState.SWIMMING:
			return "Swimming"
		CharacterState.DEAD:
			return "Dead"
		_:
			return "RunningNoPhysics" if state == CharacterState.IDLE else "None"

func _try_auto_step_up(move_direction: Vector3, delta: float, was_on_floor: bool) -> bool:
	if not was_on_floor or move_direction.length_squared() < 0.001 or not is_on_floor():
		return false
	var direction := move_direction.normalized()
	if not _has_forward_step_obstacle(direction):
		return false

	var base_transform := global_transform
	var lifted_transform := base_transform.translated(Vector3.UP * _world_units(AUTO_STEP_HEIGHT))
	var forward_motion := direction * _world_units(AUTO_STEP_FORWARD_DISTANCE)
	if test_move(lifted_transform, forward_motion):
		return false

	var probe_transform := lifted_transform.translated(forward_motion)
	var down_collision := KinematicCollision3D.new()
	var down_motion := Vector3.DOWN * _world_units(AUTO_STEP_HEIGHT + FLOOR_SNAP_LENGTH + 0.1)
	if not test_move(probe_transform, down_motion, down_collision):
		return false

	var landing_normal: Vector3 = down_collision.get_normal()
	if landing_normal.dot(Vector3.UP) < 0.74:
		return false

	var target_position: Vector3 = probe_transform.origin + down_collision.get_travel()
	var step_height: float = target_position.y - global_position.y
	if step_height <= _world_units(0.03) or step_height > _world_units(AUTO_STEP_MAX_APPLIED_HEIGHT):
		return false

	var horizontal_position := Vector2(global_position.x, global_position.z)
	var target_horizontal_position := Vector2(target_position.x, target_position.z)
	var stepped_horizontal := horizontal_position.move_toward(
		target_horizontal_position,
		_world_units(AUTO_STEP_FORWARD_SPEED) * delta
	)
	global_position.x = stepped_horizontal.x
	global_position.z = stepped_horizontal.y
	global_position.y = move_toward(
		global_position.y,
		target_position.y + _world_units(0.012),
		_world_units(AUTO_STEP_VERTICAL_SPEED) * delta
	)
	velocity.y = maxf(velocity.y, _world_units(FLOOR_STICK_VELOCITY))
	return true

func _has_forward_step_obstacle(direction: Vector3) -> bool:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var normal := collision.get_normal()
		if absf(normal.y) < 0.45 and normal.dot(direction) < -0.25:
			return true
	return false

func _update_safe_position_and_unstuck(delta: float) -> void:
	if _is_preview_instance() or _is_network_gameplay_frozen():
		_previous_physics_position = global_position
		return

	var moved_distance: float = global_position.distance_to(_previous_physics_position)
	if moved_distance > _world_units(MAX_UNAUTHORISED_FRAME_DISPLACEMENT) and Time.get_ticks_msec() >= _teleport_ready_at_msec and not _is_respawning:
		global_position = _previous_physics_position
		velocity = Vector3.ZERO
		_reset_all_physics_interpolation()
		return

	var overlaps_world: bool = _is_body_overlapping_world()
	if is_on_floor() and moved_distance > _world_units(UNSTUCK_MIN_SAFE_DISTANCE) and not overlaps_world:
		_last_safe_position = global_position
		_has_safe_position = true

	if overlaps_world and moved_distance < _world_units(0.05):
		_stuck_timer += delta
		if _stuck_timer >= UNSTUCK_STATIONARY_SECONDS and _has_safe_position:
			global_position = _last_safe_position + Vector3.UP * _world_units(SAFE_REPOSITION_LIFT)
			velocity = Vector3.ZERO
			_reset_all_physics_interpolation()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0

	_previous_physics_position = global_position

func _is_body_overlapping_world() -> bool:
	if collision_body == null or collision_body.shape == null or get_world_3d() == null:
		return false
	var query_shape: Shape3D = collision_body.shape.duplicate() as Shape3D
	if query_shape is CapsuleShape3D:
		var capsule := query_shape as CapsuleShape3D
		capsule.radius = maxf(capsule.radius - 0.04, 0.05)
		capsule.height = maxf(capsule.height - 0.08, 0.1)
	elif query_shape is BoxShape3D:
		var box := query_shape as BoxShape3D
		box.size = Vector3(
			maxf(box.size.x - 0.06, 0.05),
			maxf(box.size.y - 0.06, 0.05),
			maxf(box.size.z - 0.06, 0.05)
		)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = query_shape
	query.transform = collision_body.global_transform
	query.collision_mask = _get_world_collision_mask()
	query.margin = 0.0
	query.exclude = [get_rid()]
	var collisions := get_world_3d().direct_space_state.intersect_shape(query, 1)
	return not collisions.is_empty()

func _smooth_camera_follow(_delta: float) -> void:
	if camera_pivot == null:
		return
	if camera_pivot.top_level:
		return
	camera_pivot.position = Vector3(0.0, CAMERA_FIRST_PERSON_HEIGHT if is_first_person else CAMERA_THIRD_PERSON_HEIGHT, 0.0)

func _update_local_camera_rig_render_phase(_delta: float) -> void:
	if camera_pivot == null:
		return
	var camera_height := CAMERA_FIRST_PERSON_HEIGHT if is_first_person else CAMERA_THIRD_PERSON_HEIGHT
	if camera_pivot.top_level:
		var render_origin := _get_local_camera_render_anchor_position()
		if render_origin.distance_to(global_position) > CAMERA_INTERPOLATION_TELEPORT_THRESHOLD:
			render_origin = global_position
			_reset_local_camera_anchor(global_position)
		camera_pivot.global_position = render_origin + Vector3(0.0, camera_height, 0.0)
		camera_pivot.rotation.z = 0.0
	else:
		camera_pivot.position = Vector3(0.0, camera_height, 0.0)
	_update_camera_collision_distance(_delta)

func _set_camera_desired_spring_length(value: float) -> void:
	_camera_desired_spring_length = clampf(value, 0.0, 20.0)
	if spring_arm != null and _camera_desired_spring_length < 0.5:
		spring_arm.spring_length = _camera_desired_spring_length

func _update_camera_collision_distance(delta: float) -> void:
	if spring_arm == null:
		return
	if camera_pivot == null:
		return
	if _camera_desired_spring_length <= 0.05 or is_first_person:
		spring_arm.spring_length = _camera_desired_spring_length
		return
	var adjusted_length := _camera_desired_spring_length
	var desired_world_length := _world_units(_camera_desired_spring_length)
	var world := get_world_3d()
	if world != null and is_inside_tree():
		var origin := camera_pivot.global_position
		var direction := camera_pivot.global_transform.basis.z.normalized()
		var target := origin + direction * desired_world_length
		var query := PhysicsRayQueryParameters3D.create(origin, target)
		query.exclude = [get_rid()]
		query.collision_mask = _get_world_collision_mask()
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.has("position"):
			var hit_position: Vector3 = hit["position"]
			var adjusted_world_length := maxf(
				_world_units(CAMERA_COLLISION_MIN_DISTANCE),
				origin.distance_to(hit_position) - _world_units(CAMERA_COLLISION_MARGIN)
			)
			adjusted_length = adjusted_world_length / maxf(world_stud_scale, 0.0001)
	if delta <= 0.0 or adjusted_length < spring_arm.spring_length:
		spring_arm.spring_length = adjusted_length
	else:
		var alpha := clampf(delta * CAMERA_COLLISION_RETURN_SPEED, 0.0, 1.0)
		spring_arm.spring_length = lerpf(spring_arm.spring_length, adjusted_length, alpha)

func _record_local_camera_physics_anchor() -> void:
	if not _is_local_authority_safe():
		return
	var now_usec := Time.get_ticks_usec()
	if not _camera_anchor_initialized:
		_reset_local_camera_anchor(global_position)
		_last_physics_timestamp_us = now_usec
		return
	_camera_anchor_previous_position = _camera_anchor_current_position
	_camera_anchor_current_position = global_position
	if _last_physics_timestamp_us > 0:
		var measured_step := now_usec - _last_physics_timestamp_us
		if measured_step >= 1000 and measured_step <= 100000:
			_physics_step_duration_us = measured_step
	_last_physics_timestamp_us = now_usec

func _reset_local_camera_anchor(anchor_position: Vector3) -> void:
	_camera_anchor_previous_position = anchor_position
	_camera_anchor_current_position = anchor_position
	_camera_anchor_initialized = true
	_last_physics_timestamp_us = Time.get_ticks_usec()
	var physics_ticks := maxf(float(Engine.physics_ticks_per_second), 1.0)
	_physics_step_duration_us = maxi(1000, roundi(1000000.0 / physics_ticks))

func _get_local_camera_render_anchor_position() -> Vector3:
	if not _camera_anchor_initialized:
		_reset_local_camera_anchor(global_position)
	var time_since_last_physics := float(Time.get_ticks_usec() - _last_physics_timestamp_us)
	var step_duration := float(maxi(_physics_step_duration_us, 1000))
	var fraction := clampf(time_since_last_physics / step_duration, 0.0, 1.0)
	return _camera_anchor_previous_position.lerp(_camera_anchor_current_position, fraction)

func _apply_camera_rotation_delta(yaw_delta: float, pitch_delta: float) -> void:
	if camera_pivot == null:
		return
	camera_pivot.rotation.y -= yaw_delta
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - pitch_delta, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
	_sync_visual_rotation_to_camera_if_needed()

func _sync_visual_rotation_to_camera_if_needed() -> void:
	if visuals == null or camera_pivot == null:
		return
	if is_shift_lock or is_first_person:
		visuals.rotation.y = camera_pivot.rotation.y + PI

func _update_animation_state(delta: float) -> void:
	if _character_state == CharacterState.DEAD:
		animation_weight = 0.0
		animation_airborne = false
		return
	if _character_state == CharacterState.SEATED:
		animation_weight = 0.0
		animation_airborne = false
		return
	if _character_state == CharacterState.SWIMMING:
		animation_weight = clampf(velocity.length() / SWIM_SPEED, 0.25, 1.0)
		animation_airborne = false
		animation_cycle = wrapf(animation_cycle + delta * WALK_CYCLE_SPEED * 0.6, 0.0, TAU)
		return
	if _climbing_active or _ledge_hang_active or _ledge_mantle_active:
		animation_weight = clampf(
			maxf(
				absf(velocity.y) / maxf(_world_units(CLIMB_SPEED), 0.001),
				Vector2(velocity.x, velocity.z).length() / maxf(_world_units(CLIMB_SIDE_SPEED), 0.001)
			),
			0.25,
			1.0
		)
		animation_airborne = false
		animation_cycle = wrapf(animation_cycle + delta * WALK_CYCLE_SPEED * maxf(animation_weight, 0.45), 0.0, TAU)
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	animation_weight = clamp(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0)
	animation_airborne = not is_on_floor()
	if animation_weight > 0.05 and not animation_airborne:
		animation_cycle = wrapf(animation_cycle + delta * WALK_CYCLE_SPEED * maxf(animation_weight, 0.35), 0.0, TAU)
	else:
		animation_cycle = 0.0

func _apply_animation_pose() -> void:
	var rendered_state := _character_state if _is_local_authority_safe() else network_character_state
	if rendered_state == CharacterState.DEAD:
		return
	if rendered_state == CharacterState.SEATED:
		left_arm_pivot.rotation.x = deg_to_rad(-12.0)
		right_arm_pivot.rotation.x = deg_to_rad(-12.0)
		left_leg_pivot.rotation.x = deg_to_rad(-88.0)
		right_leg_pivot.rotation.x = deg_to_rad(-88.0)
		visuals.rotation.z = 0.0
		return
	if rendered_state == CharacterState.SWIMMING:
		var swim_swing := sin(animation_cycle) * 0.65 * animation_weight
		left_arm_pivot.rotation.x = deg_to_rad(-105.0) - swim_swing
		right_arm_pivot.rotation.x = deg_to_rad(-105.0) + swim_swing
		left_leg_pivot.rotation.x = swim_swing * 0.7
		right_leg_pivot.rotation.x = -swim_swing * 0.7
		visuals.rotation.z = 0.0
		return
	if rendered_state == CharacterState.CLIMBING:
		var climb_swing := sin(animation_cycle) * 0.72 * animation_weight
		left_arm_pivot.rotation.x = deg_to_rad(-132.0) - climb_swing
		right_arm_pivot.rotation.x = deg_to_rad(-132.0) + climb_swing
		left_leg_pivot.rotation.x = climb_swing * 0.72
		right_leg_pivot.rotation.x = -climb_swing * 0.72
		visuals.rotation.z = 0.0
		return
	var swing_scale: float = animation_weight
	if animation_airborne:
		# Point arms up/forward and spread legs
		left_arm_pivot.rotation.x = deg_to_rad(-150.0)
		right_arm_pivot.rotation.x = deg_to_rad(-150.0)
		left_leg_pivot.rotation.x = deg_to_rad(-15.0)
		right_leg_pivot.rotation.x = deg_to_rad(15.0)
		visuals.rotation.z = 0.0
		return
		
	var swing: float = sin(animation_cycle) * LIMB_SWING_ANGLE * swing_scale
	left_arm_pivot.rotation.x = -swing
	right_arm_pivot.rotation.x = swing
	left_leg_pivot.rotation.x = swing
	right_leg_pivot.rotation.x = -swing
	visuals.rotation.z = 0.0

func _apply_avatar_color_if_needed() -> void:
	var current_colors = {
		"head": head_color, "torso": torso_color, 
		"left_arm": left_arm_color, "right_arm": right_arm_color, 
		"left_leg": left_leg_color, "right_leg": right_leg_color
	}
	if applied_colors == current_colors:
		return
	applied_colors = current_colors
	head_mesh.material_override = _make_flat_material(head_color)
	torso_mesh.material_override = _make_flat_material(torso_color)
	left_arm_mesh.material_override = _make_flat_material(left_arm_color)
	right_arm_mesh.material_override = _make_flat_material(right_arm_color)
	left_leg_mesh.material_override = _make_flat_material(left_leg_color)
	right_leg_mesh.material_override = _make_flat_material(right_leg_color)

func _apply_avatar_visuals_if_needed() -> void:
	var resolved_face_path: String = _resolve_avatar_visual_texture_path(face_texture_path, "avatar_face_texture_path", DEFAULT_FACE_TEXTURE_PATH)
	var resolved_badge_path: String = _resolve_avatar_visual_texture_path(chest_badge_texture_path, "avatar_chest_badge_texture_path", "")
	var resolved_shirt_path: String = _resolve_avatar_visual_texture_path(shirt_texture_path, "avatar_shirt_texture_path", "")
	var resolved_pants_path: String = _resolve_avatar_visual_texture_path(pants_texture_path, "avatar_pants_texture_path", "")
	var active_face_path: String = resolved_face_path
	var active_badge_path: String = resolved_badge_path
	var active_shirt_path: String = resolved_shirt_path
	var active_pants_path: String = resolved_pants_path
	if not ENABLE_AVATAR_DECAL_LAYER:
		active_face_path = ""
		active_badge_path = ""
		active_shirt_path = ""
		active_pants_path = ""
	if not render_avatar_visual_decals:
		active_face_path = ""
		active_badge_path = ""
		active_shirt_path = ""
		active_pants_path = ""
	if not render_avatar_clothing_decals:
		active_shirt_path = ""
		active_pants_path = ""
	if not ENABLE_AVATAR_CLOTHING_DECALS:
		active_shirt_path = ""
		active_pants_path = ""
	var active_torso_clothing_path := active_shirt_path
	if active_torso_clothing_path.is_empty():
		active_torso_clothing_path = active_pants_path
	var visual_key: String = "%s|%s|%s|%s|%s" % [active_face_path, active_badge_path, active_shirt_path, active_pants_path, active_torso_clothing_path]
	_apply_avatar_attachment_items_if_needed()
	if not use_local_avatar_fallback:
		face_texture_path = resolved_face_path
		chest_badge_texture_path = resolved_badge_path
		shirt_texture_path = resolved_shirt_path
		pants_texture_path = resolved_pants_path
	if not ENABLE_AVATAR_DECAL_LAYER:
		_applied_avatar_visual_key = visual_key
		_hide_avatar_decal_nodes()
		return
	if visual_key == _applied_avatar_visual_key:
		return
	_applied_avatar_visual_key = visual_key
	_ensure_avatar_decal_nodes((not active_shirt_path.is_empty()) or (not active_pants_path.is_empty()), not active_badge_path.is_empty())
	_set_avatar_decal_texture(_face_decal, active_face_path, true, true)
	_set_avatar_decal_texture(_shirt_front_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_FRONT_REGION)
	_set_avatar_decal_texture(_shirt_back_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_BACK_REGION)
	_set_avatar_decal_texture(_shirt_left_side_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_LEFT_SIDE_REGION)
	_set_avatar_decal_texture(_shirt_right_side_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_RIGHT_SIDE_REGION)
	_set_avatar_decal_texture(_shirt_up_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_UP_REGION)
	_set_avatar_decal_texture(_shirt_down_decal, active_torso_clothing_path, false, false, AVATAR_TEMPLATE_TORSO_DOWN_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_FRONT_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_FRONT_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_back_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_BACK_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_back_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_BACK_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_outer_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_OUTER_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_inner_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_INNER_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_outer_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_OUTER_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_inner_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_INNER_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_up_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_UP_REGION)
	_set_avatar_decal_texture(_left_arm_shirt_down_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_LEFT_ARM_DOWN_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_up_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_UP_REGION)
	_set_avatar_decal_texture(_right_arm_shirt_down_decal, active_shirt_path, false, false, AVATAR_TEMPLATE_RIGHT_ARM_DOWN_REGION)
	_set_avatar_decal_texture(_chest_badge_decal, active_badge_path, true, true)
	_set_avatar_decal_texture(_left_pants_front_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_FRONT_REGION)
	_set_avatar_decal_texture(_right_pants_front_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_FRONT_REGION)
	_set_avatar_decal_texture(_left_pants_back_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_BACK_REGION)
	_set_avatar_decal_texture(_right_pants_back_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_BACK_REGION)
	_set_avatar_decal_texture(_left_pants_outer_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_OUTER_REGION)
	_set_avatar_decal_texture(_left_pants_inner_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_INNER_REGION)
	_set_avatar_decal_texture(_right_pants_outer_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_OUTER_REGION)
	_set_avatar_decal_texture(_right_pants_inner_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_INNER_REGION)
	_set_avatar_decal_texture(_left_pants_up_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_UP_REGION)
	_set_avatar_decal_texture(_left_pants_down_decal, active_pants_path, false, false, AVATAR_TEMPLATE_RIGHT_LEG_DOWN_REGION)
	_set_avatar_decal_texture(_right_pants_up_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_UP_REGION)
	_set_avatar_decal_texture(_right_pants_down_decal, active_pants_path, false, false, AVATAR_TEMPLATE_LEFT_LEG_DOWN_REGION)

func force_avatar_visual_refresh() -> void:
	_applied_avatar_visual_key = ""
	_applied_avatar_attachment_key = ""
	_apply_avatar_visuals_if_needed()

func _hide_avatar_decal_nodes() -> void:
	var decals: Array = [
		_face_decal, _chest_badge_decal, _shirt_front_decal, _shirt_back_decal,
		_shirt_left_side_decal, _shirt_right_side_decal, _shirt_up_decal, _shirt_down_decal, _left_arm_shirt_decal,
		_right_arm_shirt_decal, _left_arm_shirt_back_decal, _right_arm_shirt_back_decal,
		_left_arm_shirt_outer_decal, _left_arm_shirt_inner_decal,
		_right_arm_shirt_outer_decal, _right_arm_shirt_inner_decal,
		_left_arm_shirt_up_decal, _left_arm_shirt_down_decal, _right_arm_shirt_up_decal, _right_arm_shirt_down_decal,
		_left_pants_front_decal, _right_pants_front_decal, _left_pants_back_decal,
		_right_pants_back_decal, _left_pants_outer_decal, _left_pants_inner_decal,
		_right_pants_outer_decal, _right_pants_inner_decal,
		_left_pants_up_decal, _left_pants_down_decal, _right_pants_up_decal, _right_pants_down_decal,
	]
	for decal in decals:
		if decal != null and is_instance_valid(decal):
			decal.set_surface_override_material(0, null)
			decal.visible = false

func _apply_avatar_attachment_items_if_needed() -> void:
	var attachment_key := JSON.stringify(equipped_avatar_items)
	if attachment_key == _applied_avatar_attachment_key:
		return
	_applied_avatar_attachment_key = attachment_key
	_clear_avatar_attachment_nodes()
	if equipped_avatar_items.is_empty():
		return
	_ensure_avatar_attachment_root()
	for raw_item in equipped_avatar_items:
		if not (raw_item is Dictionary):
			continue
		var item := raw_item as Dictionary
		if _avatar_attachment_item_is_clothing(item):
			continue
		var attachment_node := _create_avatar_attachment_node(item)
		if attachment_node != null:
			_avatar_attachment_root.add_child(attachment_node)

func _ensure_avatar_attachment_root() -> void:
	if _avatar_attachment_root != null and is_instance_valid(_avatar_attachment_root):
		return
	_avatar_attachment_root = Node3D.new()
	_avatar_attachment_root.name = "AvatarAttachments"
	visuals.add_child(_avatar_attachment_root)

func _clear_avatar_attachment_nodes() -> void:
	if _avatar_attachment_root == null or not is_instance_valid(_avatar_attachment_root):
		return
	for child in _avatar_attachment_root.get_children():
		_avatar_attachment_root.remove_child(child)
		child.queue_free()

func _avatar_attachment_item_is_clothing(item: Dictionary) -> bool:
	var data := _avatar_attachment_item_data(item)
	var kind := str(item.get("category", item.get("type", item.get("item_kind", "")))).strip_edges().to_lower()
	if kind.is_empty() or kind in ["avatar_item", "avatar_items", "item"]:
		kind = str(data.get("category", data.get("item_kind", data.get("kind", "")))).strip_edges().to_lower()
	return kind in ["shirt", "shirts", "tshirt", "t-shirt", "tee", "pants", "pant", "trousers", "legs"]

func _create_avatar_attachment_node(item: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(item.get("name", item.get("id", "AvatarAttachment"))).strip_edges()
	if root.name.is_empty():
		root.name = "AvatarAttachment"
	var item_data := _avatar_attachment_item_data(item)
	var slot := _avatar_attachment_resolve_slot(item, item_data)
	var transform_data := _avatar_attachment_resolve_transform(item, item_data)
	root.position = _avatar_attachment_slot_position(slot) + _avatar_attachment_vector3(transform_data.get("position", []), Vector3.ZERO)
	root.rotation_degrees = _avatar_attachment_vector3(transform_data.get("rotation_degrees", []), Vector3.ZERO)
	root.scale = _avatar_attachment_vector3(transform_data.get("scale", []), Vector3.ONE)
	var parts := _avatar_attachment_extract_parts(item_data)
	var source_path := _avatar_attachment_source_path(item, item_data)
	if not source_path.is_empty():
		_load_avatar_attachment_source_async.call_deferred(root, source_path, parts)
		return root
	if parts.is_empty():
		parts.append({
			"name": "AttachmentPreview",
			"kind": "Block",
			"position": [0.0, 0.0, 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [0.65, 0.65, 0.65],
			"color": "ffb347"
		})
	for raw_part in parts:
		if raw_part is Dictionary:
			root.add_child(_create_avatar_attachment_part(raw_part as Dictionary))
	return root

func _avatar_attachment_resolve_slot(item: Dictionary, item_data: Dictionary) -> String:
	for source in _avatar_attachment_metadata_candidates(item, item_data):
		var candidate := str((source as Dictionary).get("attachment_slot", "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return "Head"

func _avatar_attachment_resolve_transform(item: Dictionary, item_data: Dictionary) -> Dictionary:
	for source in _avatar_attachment_metadata_candidates(item, item_data):
		var raw_transform: Variant = (source as Dictionary).get("attachment_transform", {})
		var transform_dict := _avatar_attachment_dictionary_from_jsonish_variant(raw_transform)
		if not transform_dict.is_empty():
			return transform_dict
		var inline_transform := _avatar_attachment_inline_transform_from_source(source as Dictionary)
		if not inline_transform.is_empty():
			return inline_transform
	return {}

func _avatar_attachment_inline_transform_from_source(source: Dictionary) -> Dictionary:
	var has_any := false
	var transform := {
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0]
	}
	for key in ["position", "pos", "translation"]:
		if source.has(key):
			transform["position"] = source.get(key)
			has_any = true
			break
	for key in ["rotation_degrees", "rotation", "rotation_deg"]:
		if source.has(key):
			transform["rotation_degrees"] = source.get(key)
			has_any = true
			break
	if source.has("scale"):
		transform["scale"] = source.get("scale")
		has_any = true
	return transform if has_any else {}

func _avatar_attachment_metadata_candidates(item: Dictionary, item_data: Dictionary) -> Array:
	var candidates: Array = []
	var queue: Array = [item, item_data]
	var visited: Dictionary = {}
	while not queue.is_empty() and candidates.size() < 32:
		var source: Variant = queue.pop_front()
		var source_dict := _avatar_attachment_dictionary_from_jsonish_variant(source)
		if source_dict.is_empty():
			continue
		var signature := JSON.stringify(source_dict)
		if visited.has(signature):
			continue
		visited[signature] = true
		candidates.append(source_dict)
		for key in ["metadata", "data", "model_data", "asset_data", "model", "asset", "source", "payload", "record", "row"]:
			if source_dict.has(key):
				queue.append(source_dict.get(key))
	return candidates

func _avatar_attachment_source_path(item: Dictionary, item_data: Dictionary) -> String:
	for source in [item, item_data]:
		if not (source is Dictionary):
			continue
		var source_dict := source as Dictionary
		for key in ["source_url", "source_file_url", "source_model_path", "model_url", "mesh_url", "path"]:
			var value := str(source_dict.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
		for nested_key in ["data", "model_data", "metadata", "asset", "payload"]:
			if not source_dict.has(nested_key):
				continue
			var nested := _avatar_attachment_dictionary_from_jsonish_variant(source_dict.get(nested_key))
			if nested.is_empty():
				continue
			var nested_path := _avatar_attachment_source_path(nested, {})
			if not nested_path.is_empty():
				return nested_path
	return ""

func _load_avatar_attachment_source_async(root: Node3D, source_path: String, fallback_parts: Array = []) -> void:
	if root == null or not is_instance_valid(root):
		return
	var loaded_model := await _instantiate_avatar_attachment_source(source_path)
	if root == null or not is_instance_valid(root):
		if loaded_model != null:
			loaded_model.queue_free()
		return
	if loaded_model != null:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
		root.add_child(loaded_model)
		_apply_avatar_attachment_source_fallback_colors(loaded_model, fallback_parts)
		if is_inside_tree():
			await get_tree().process_frame
		if root == null or not is_instance_valid(root) or loaded_model == null or not is_instance_valid(loaded_model):
			return
		_normalize_loaded_avatar_attachment_source(root, loaded_model)
		return
	if not fallback_parts.is_empty():
		for raw_part in fallback_parts:
			if raw_part is Dictionary:
				root.add_child(_create_avatar_attachment_part(raw_part as Dictionary))
		return
	root.add_child(_create_avatar_attachment_part({
		"name": "AttachmentPreview",
		"kind": "Block",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [0.65, 0.65, 0.65],
		"color": "ffb347"
	}))

func _instantiate_avatar_attachment_source(source_path: String) -> Node:
	var local_path := await _resolve_avatar_attachment_source_path(source_path)
	if local_path.is_empty():
		return null
	var extension := local_path.get_extension().to_lower()
	if extension == "glb" or extension == "gltf":
		var gltf_document := GLTFDocument.new()
		var gltf_state := GLTFState.new()
		var error := gltf_document.append_from_file(local_path, gltf_state)
		if error == OK:
			var scene := gltf_document.generate_scene(gltf_state)
			RbxlMaterialCache.enable_embedded_vertex_colors(scene)
			return scene
	elif extension == "obj":
		if ClassDB.class_exists("OBJMesh"):
			var obj_mesh: Object = ClassDB.instantiate("OBJMesh")
			if obj_mesh is Mesh:
				obj_mesh.set("file", local_path)
				var mesh_instance := MeshInstance3D.new()
				mesh_instance.mesh = obj_mesh
				return mesh_instance
	if local_path.begins_with("res://") or local_path.begins_with("user://"):
		if ResourceLoader.exists(local_path):
			var res := ResourceLoader.load(local_path)
			if res is PackedScene:
				return res.instantiate()
			if res is Mesh:
				var mesh_instance := MeshInstance3D.new()
				mesh_instance.mesh = res
				return mesh_instance
	return null

func _resolve_avatar_attachment_source_path(source_path: String) -> String:
	var clean_path := source_path.strip_edges()
	if clean_path.is_empty():
		return ""
	if not (clean_path.begins_with("http://") or clean_path.begins_with("https://")):
		return clean_path
	var cache_dir := "user://cache/avatar_attachments"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var url_path := clean_path.split("?", false, 1)[0]
	var extension := url_path.get_extension().to_lower()
	if extension not in ["glb", "gltf", "obj"]:
		extension = "glb"
	var file_name := "attachment_%s.%s" % [clean_path.md5_text(), extension]
	var local_path := cache_dir.path_join(file_name)
	if FileAccess.file_exists(local_path):
		var cached := FileAccess.open(local_path, FileAccess.READ)
		var cached_size := cached.get_length() if cached != null else 0
		if cached != null:
			cached.close()
		if cached_size > 32:
			return local_path
		DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
	var temporary_path := local_path + ".part"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var request := HTTPRequest.new()
	add_child(request)
	request.download_file = temporary_path
	request.timeout = 20.0
	var error := request.request(clean_path)
	var result: Array = []
	if error == OK:
		result = await request.request_completed
	request.queue_free()
	var successful := result.size() >= 2 \
		and int(result[0]) == HTTPRequest.RESULT_SUCCESS \
		and int(result[1]) >= 200 \
		and int(result[1]) < 300
	if successful and FileAccess.file_exists(temporary_path):
		var downloaded := FileAccess.open(temporary_path, FileAccess.READ)
		var downloaded_size := downloaded.get_length() if downloaded != null else 0
		if downloaded != null:
			downloaded.close()
		if downloaded_size > 32:
			if FileAccess.file_exists(local_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(local_path)) == OK:
				return local_path
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	return ""

func _normalize_loaded_avatar_attachment_source(root: Node3D, loaded_model: Node) -> void:
	if root == null or loaded_model == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_avatar_attachment_meshes(loaded_model, meshes)
	if meshes.is_empty():
		return
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		var mesh_bounds := _avatar_attachment_mesh_aabb_in_space(root, mesh_instance)
		if mesh_bounds.size.length_squared() <= 0.0001:
			continue
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	if not has_bounds:
		return
	var loaded_node := loaded_model as Node3D
	if loaded_node == null:
		return
	var center := bounds.get_center()
	var max_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale_factor := 1.0
	if max_axis > 2.2:
		scale_factor = 2.2 / max_axis
	loaded_node.position = (loaded_node.position - center) * scale_factor
	loaded_node.scale *= scale_factor

func _apply_avatar_attachment_source_fallback_colors(loaded_model: Node, fallback_parts: Array) -> void:
	if loaded_model == null or fallback_parts.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_avatar_attachment_meshes(loaded_model, meshes)
	if meshes.is_empty():
		return
	var parts_by_name: Dictionary = {}
	var ordered_parts: Array = []
	for part_variant in fallback_parts:
		if not (part_variant is Dictionary):
			continue
		var part: Dictionary = part_variant
		ordered_parts.append(part)
		var part_name := str(part.get("name", "")).strip_edges().to_lower()
		if not part_name.is_empty():
			parts_by_name[part_name] = part
	for index in range(meshes.size()):
		var mesh_instance := meshes[index]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var mesh_name := str(mesh_instance.name).strip_edges().to_lower()
		var part_data: Dictionary = parts_by_name.get(mesh_name, {}) if parts_by_name.get(mesh_name, {}) is Dictionary else {}
		if part_data.is_empty() and index < ordered_parts.size() and ordered_parts[index] is Dictionary:
			part_data = ordered_parts[index]
		if part_data.is_empty() or not _avatar_attachment_part_has_color(part_data):
			continue
		var surface_count := maxi(1, mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1)
		for surface_index in range(surface_count):
			if not _avatar_attachment_surface_needs_fallback_color(mesh_instance, surface_index):
				continue
			var fallback_color: Variant = _avatar_attachment_part_surface_color_value(part_data, surface_index)
			mesh_instance.set_surface_override_material(surface_index, _avatar_attachment_material(fallback_color))

func _avatar_attachment_mesh_needs_fallback_color(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var surface_count := maxi(1, mesh_instance.mesh.get_surface_count())
	for surface_index in range(surface_count):
		if not _avatar_attachment_surface_needs_fallback_color(mesh_instance, surface_index):
			return false
	return true

func _avatar_attachment_surface_needs_fallback_color(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var material: Material = mesh_instance.get_active_material(surface_index)
	if material is BaseMaterial3D:
		var base_material := material as BaseMaterial3D
		# A white multiplier is valid when the GLB supplies its appearance through
		# a texture or vertex colors. Only an actually blank white surface needs
		# the serialized model-editor fallback.
		for texture_property in [
			"albedo_texture",
			"normal_texture",
			"orm_texture",
			"metallic_texture",
			"roughness_texture",
			"emission_texture"
		]:
			if base_material.get(texture_property) is Texture2D:
				return false
		if base_material.vertex_color_use_as_albedo:
			return false
		var color := base_material.albedo_color
		return color.a <= 0.01 or (
			absf(color.r - 1.0) <= 0.08
			and absf(color.g - 1.0) <= 0.08
			and absf(color.b - 1.0) <= 0.08
		)
	# ShaderMaterial and custom imported materials already carry appearance.
	return material == null

func _avatar_attachment_part_has_color(part_data: Dictionary) -> bool:
	for key in ["color", "Color", "Color3", "Color3uint8", "BrickColor", "BrickColorId", "brick_color", "colour", "albedo", "albedo_color", "modulate"]:
		if part_data.has(key) and not str(part_data.get(key, "")).strip_edges().is_empty():
			return true
	for surface_variant in part_data.get("surface_materials", []):
		if surface_variant is Dictionary and (surface_variant as Dictionary).has("color"):
			return true
	return false

func _avatar_attachment_part_surface_color_value(part_data: Dictionary, surface_index: int) -> Variant:
	var first_surface_color: Variant = null
	for surface_variant in part_data.get("surface_materials", []):
		if not (surface_variant is Dictionary):
			continue
		var surface_data := surface_variant as Dictionary
		if not surface_data.has("color"):
			continue
		if first_surface_color == null:
			first_surface_color = surface_data.get("color")
		if int(surface_data.get("surface", -1)) == surface_index:
			return surface_data.get("color")
	if first_surface_color != null:
		return first_surface_color
	return _avatar_attachment_part_color_value(part_data)

func _avatar_attachment_part_color_value(part_data: Dictionary) -> Variant:
	for key in ["color", "Color", "Color3", "Color3uint8", "colour", "albedo", "albedo_color", "modulate"]:
		if part_data.has(key):
			return part_data.get(key)
	for key in ["BrickColor", "BrickColorId", "brick_color"]:
		if part_data.has(key):
			return RbxlMaterialCache.roblox_brick_color_to_color(part_data.get(key))
	return "ffffff"

func _collect_avatar_attachment_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_avatar_attachment_meshes(child, meshes)

func _avatar_attachment_mesh_aabb_in_space(space_root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	if space_root == null or mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var mesh_aabb := mesh_instance.get_aabb()
	var basis_points := [
		Vector3(mesh_aabb.position.x, mesh_aabb.position.y, mesh_aabb.position.z),
		Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y, mesh_aabb.position.z),
		Vector3(mesh_aabb.position.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z),
		Vector3(mesh_aabb.position.x, mesh_aabb.position.y, mesh_aabb.position.z + mesh_aabb.size.z),
		Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z),
		Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y, mesh_aabb.position.z + mesh_aabb.size.z),
		Vector3(mesh_aabb.position.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z + mesh_aabb.size.z),
		mesh_aabb.position + mesh_aabb.size
	]
	var to_space := space_root.global_transform.affine_inverse()
	var has_point := false
	var bounds := AABB()
	for local_point in basis_points:
		var point: Vector3 = to_space * (mesh_instance.global_transform * local_point)
		var point_aabb := AABB(point, Vector3.ZERO)
		bounds = point_aabb if not has_point else bounds.merge(point_aabb)
		has_point = true
	return bounds

func _avatar_attachment_item_data(item: Dictionary) -> Dictionary:
	var candidates: Array = [item]
	for key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
		if item.has(key):
			candidates.append(item.get(key))
	for candidate in candidates:
		var candidate_dict := _avatar_attachment_dictionary_from_jsonish_variant(candidate)
		if candidate_dict.is_empty():
			continue
		if not _avatar_attachment_extract_parts(candidate_dict).is_empty():
			return candidate_dict
		for nested_key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
			if not candidate_dict.has(nested_key):
				continue
			var nested_dict := _avatar_attachment_dictionary_from_jsonish_variant(candidate_dict.get(nested_key))
			if not _avatar_attachment_extract_parts(nested_dict).is_empty():
				return nested_dict
	var data: Variant = item.get("data", {})
	var data_dict := _avatar_attachment_dictionary_from_jsonish_variant(data)
	if not data_dict.is_empty():
		return data_dict
	return {}

func _avatar_attachment_extract_parts(model_data: Dictionary) -> Array:
	for key in ["parts", "model_parts", "serialized_parts", "blocks", "objects", "nodes", "children"]:
		var candidate: Variant = model_data.get(key, [])
		if candidate is Array:
			var result: Array = []
			for part_variant in candidate:
				if part_variant is Dictionary:
					result.append(part_variant)
				elif part_variant is String:
					var parsed: Variant = JSON.parse_string((part_variant as String).strip_edges())
					if parsed is Dictionary:
						result.append(parsed)
			if not result.is_empty():
				return result
	for nested_key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
		if model_data.has(nested_key):
			var nested := _avatar_attachment_dictionary_from_jsonish_variant(model_data.get(nested_key))
			if nested.is_empty():
				continue
			var nested_parts := _avatar_attachment_extract_parts(nested)
			if not nested_parts.is_empty():
				return nested_parts
	return []

func _avatar_attachment_dictionary_from_jsonish_variant(value: Variant) -> Dictionary:
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

func _create_avatar_attachment_part(part_data: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = str(part_data.get("name", "AttachmentPart")).strip_edges()
	if node.name.is_empty():
		node.name = "AttachmentPart"
	node.position = _avatar_attachment_vector3(part_data.get("position", part_data.get("pos", part_data.get("translation", []))), Vector3.ZERO)
	node.rotation_degrees = _avatar_attachment_vector3(part_data.get("rotation_degrees", part_data.get("rotation", part_data.get("rotation_deg", []))), Vector3.ZERO)
	node.scale = _avatar_attachment_vector3(part_data.get("scale", part_data.get("size", [])), Vector3.ONE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _avatar_attachment_mesh(str(part_data.get("kind", part_data.get("shape", part_data.get("type", "Block")))))
	mesh_instance.set_surface_override_material(0, _avatar_attachment_material(_avatar_attachment_part_color_value(part_data)))
	node.add_child(mesh_instance)
	return node

func _avatar_attachment_mesh(kind: String) -> Mesh:
	match kind.strip_edges().to_lower():
		"sphere", "ball":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			return sphere
		"cylinder", "tube":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			return cylinder
		"ramp", "wedge", "prism":
			return PrismMesh.new()
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box

func _avatar_attachment_material(color_value: Variant) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var color := Color.WHITE
	if color_value is Color:
		color = color_value as Color
	elif color_value is Array:
		var arr := color_value as Array
		var r := float(arr[0]) if arr.size() > 0 else 1.0
		var g := float(arr[1]) if arr.size() > 1 else 1.0
		var b := float(arr[2]) if arr.size() > 2 else 1.0
		var a := float(arr[3]) if arr.size() > 3 else 1.0
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		color = Color(r, g, b, a)
	elif color_value is Dictionary:
		var data := color_value as Dictionary
		var r := float(data.get("r", data.get("R", data.get("x", data.get("X", 1.0)))))
		var g := float(data.get("g", data.get("G", data.get("y", data.get("Y", 1.0)))))
		var b := float(data.get("b", data.get("B", data.get("z", data.get("Z", 1.0)))))
		var a := float(data.get("a", data.get("A", 1.0)))
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		color = Color(r, g, b, a)
	else:
		var color_text := str(color_value).strip_edges()
		if color_text.begins_with("#"):
			color_text = color_text.substr(1)
		if color_text.length() == 6 or color_text.length() == 8:
			color = Color.html(color_text)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color.lightened(0.12)
	material.emission_energy_multiplier = 0.12
	material.roughness = 0.72
	return material

func _avatar_attachment_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var array_value := value as Array
		return Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))
	if value is Dictionary:
		var dict_value := value as Dictionary
		return Vector3(float(dict_value.get("x", fallback.x)), float(dict_value.get("y", fallback.y)), float(dict_value.get("z", fallback.z)))
	return fallback

func _avatar_attachment_slot_position(slot_name: String) -> Vector3:
	match slot_name:
		"Head":
			return _avatar_attachment_local_position_for_node(head_mesh, Vector3(0.0, 4.6, 0.0)) + Vector3(0.0, 0.6, 0.0)
		"Torso":
			return _avatar_attachment_local_position_for_node(torso_mesh, Vector3(0.0, 3.0, 0.0))
		"LeftArm":
			return _avatar_attachment_local_position_for_node(left_arm_mesh, Vector3(-1.5, 3.0, 0.0))
		"RightArm":
			return _avatar_attachment_local_position_for_node(right_arm_mesh, Vector3(1.5, 3.0, 0.0))
		"LeftLeg":
			return _avatar_attachment_local_position_for_node(left_leg_mesh, Vector3(-0.5, 1.0, 0.0))
		"RightLeg":
			return _avatar_attachment_local_position_for_node(right_leg_mesh, Vector3(0.5, 1.0, 0.0))
		"Back":
			return _avatar_attachment_local_position_for_node(torso_mesh, Vector3(0.0, 3.0, 0.0)) + Vector3(0.0, 0.0, 0.72)
		_:
			return _avatar_attachment_local_position_for_node(head_mesh, Vector3(0.0, 4.6, 0.0)) + Vector3(0.0, 0.6, 0.0)

func _avatar_attachment_local_position_for_node(node: Node3D, fallback: Vector3) -> Vector3:
	if node == null or not is_instance_valid(node):
		return fallback
	if _avatar_attachment_root != null and is_instance_valid(_avatar_attachment_root) and _avatar_attachment_root.is_inside_tree() and node.is_inside_tree():
		return _avatar_attachment_root.to_local(node.global_transform.origin)
	return fallback

func _resolve_avatar_visual_texture_path(local_path: String, game_state_property: String, fallback: String) -> String:
	var clean_path: String = local_path.strip_edges()
	if GameState != null:
		var has_peer := _has_multiplayer_peer()
		var is_local_player := false
		if has_peer:
			is_local_player = (name == str(multiplayer.get_unique_id()))
		else:
			is_local_player = false
		
		if is_local_player or use_local_avatar_fallback:
			var game_state_path: String = str(GameState.get(game_state_property)).strip_edges()
			if game_state_path.is_empty():
				return fallback
			return game_state_path
	if clean_path.is_empty():
		return fallback
	return clean_path

func _ensure_avatar_decal_nodes(include_clothing: bool = true, include_badge: bool = true) -> void:
	if _face_decal == null:
		_face_decal = _create_avatar_face_decal("FaceDecal", head_mesh)
	if not include_clothing:
		if include_badge and _chest_badge_decal == null:
			_chest_badge_decal = _create_avatar_decal("ChestBadgeDecal", torso_mesh, Vector2(0.38, 0.38), Vector3(0.46, 0.32, 0.524))
		return
	if _shirt_front_decal == null:
		_shirt_front_decal = _create_avatar_decal("ShirtFrontDecal", torso_mesh, Vector2(2.02, 2.02), Vector3(0.0, 0.0, 0.506))
	if _shirt_back_decal == null:
		_shirt_back_decal = _create_avatar_decal("ShirtBackDecal", torso_mesh, Vector2(2.02, 2.02), Vector3(0.0, 0.0, -0.506), Vector3(0.0, 180.0, 0.0))
	if _shirt_left_side_decal == null:
		_shirt_left_side_decal = _create_avatar_decal("ShirtLeftSideDecal", torso_mesh, Vector2(1.02, 2.02), Vector3(1.006, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	if _shirt_right_side_decal == null:
		_shirt_right_side_decal = _create_avatar_decal("ShirtRightSideDecal", torso_mesh, Vector2(1.02, 2.02), Vector3(-1.006, 0.0, 0.0), Vector3(0.0, -90.0, 0.0))
	if _shirt_up_decal == null:
		_shirt_up_decal = _create_avatar_decal("ShirtUpDecal", torso_mesh, Vector2(2.02, 1.02), Vector3(0.0, 1.006, 0.0), Vector3(-90.0, 0.0, 0.0))
	if _shirt_down_decal == null:
		_shirt_down_decal = _create_avatar_decal("ShirtDownDecal", torso_mesh, Vector2(2.02, 1.02), Vector3(0.0, -1.006, 0.0), Vector3(90.0, 0.0, 0.0))
	if _left_arm_shirt_decal == null:
		_left_arm_shirt_decal = _create_avatar_decal("LeftArmShirtDecal", left_arm_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, 0.506))
	if _right_arm_shirt_decal == null:
		_right_arm_shirt_decal = _create_avatar_decal("RightArmShirtDecal", right_arm_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, 0.506))
	if _left_arm_shirt_back_decal == null:
		_left_arm_shirt_back_decal = _create_avatar_decal("LeftArmShirtBackDecal", left_arm_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, -0.506), Vector3(0.0, 180.0, 0.0))
	if _right_arm_shirt_back_decal == null:
		_right_arm_shirt_back_decal = _create_avatar_decal("RightArmShirtBackDecal", right_arm_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, -0.506), Vector3(0.0, 180.0, 0.0))
	if _left_arm_shirt_outer_decal == null:
		_left_arm_shirt_outer_decal = _create_avatar_decal("LeftArmShirtOuterDecal", left_arm_mesh, Vector2(1.02, 2.02), Vector3(0.506, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	if _left_arm_shirt_inner_decal == null:
		_left_arm_shirt_inner_decal = _create_avatar_decal("LeftArmShirtInnerDecal", left_arm_mesh, Vector2(1.02, 2.02), Vector3(-0.506, 0.0, 0.0), Vector3(0.0, -90.0, 0.0))
	if _right_arm_shirt_outer_decal == null:
		_right_arm_shirt_outer_decal = _create_avatar_decal("RightArmShirtOuterDecal", right_arm_mesh, Vector2(1.02, 2.02), Vector3(-0.506, 0.0, 0.0), Vector3(0.0, -90.0, 0.0))
	if _right_arm_shirt_inner_decal == null:
		_right_arm_shirt_inner_decal = _create_avatar_decal("RightArmShirtInnerDecal", right_arm_mesh, Vector2(1.02, 2.02), Vector3(0.506, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	if _left_arm_shirt_up_decal == null:
		_left_arm_shirt_up_decal = _create_avatar_decal("LeftArmShirtUpDecal", left_arm_mesh, Vector2(1.02, 1.02), Vector3(0.0, 1.006, 0.0), Vector3(-90.0, 0.0, 0.0))
	if _left_arm_shirt_down_decal == null:
		_left_arm_shirt_down_decal = _create_avatar_decal("LeftArmShirtDownDecal", left_arm_mesh, Vector2(1.02, 1.02), Vector3(0.0, -1.006, 0.0), Vector3(90.0, 0.0, 0.0))
	if _right_arm_shirt_up_decal == null:
		_right_arm_shirt_up_decal = _create_avatar_decal("RightArmShirtUpDecal", right_arm_mesh, Vector2(1.02, 1.02), Vector3(0.0, 1.006, 0.0), Vector3(-90.0, 0.0, 0.0))
	if _right_arm_shirt_down_decal == null:
		_right_arm_shirt_down_decal = _create_avatar_decal("RightArmShirtDownDecal", right_arm_mesh, Vector2(1.02, 1.02), Vector3(0.0, -1.006, 0.0), Vector3(90.0, 0.0, 0.0))
	if include_badge and _chest_badge_decal == null:
		_chest_badge_decal = _create_avatar_decal("ChestBadgeDecal", torso_mesh, Vector2(0.38, 0.38), Vector3(0.46, 0.32, 0.524))
	if _left_pants_front_decal == null:
		_left_pants_front_decal = _create_avatar_decal("LeftPantsFrontDecal", left_leg_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, 0.506))
	if _right_pants_front_decal == null:
		_right_pants_front_decal = _create_avatar_decal("RightPantsFrontDecal", right_leg_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, 0.506))
	if _left_pants_back_decal == null:
		_left_pants_back_decal = _create_avatar_decal("LeftPantsBackDecal", left_leg_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, -0.506), Vector3(0.0, 180.0, 0.0))
	if _right_pants_back_decal == null:
		_right_pants_back_decal = _create_avatar_decal("RightPantsBackDecal", right_leg_mesh, Vector2(1.02, 2.02), Vector3(0.0, 0.0, -0.506), Vector3(0.0, 180.0, 0.0))
	if _left_pants_outer_decal == null:
		_left_pants_outer_decal = _create_avatar_decal("LeftPantsOuterDecal", left_leg_mesh, Vector2(1.02, 2.02), Vector3(0.506, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	if _left_pants_inner_decal == null:
		_left_pants_inner_decal = _create_avatar_decal("LeftPantsInnerDecal", left_leg_mesh, Vector2(1.02, 2.02), Vector3(-0.506, 0.0, 0.0), Vector3(0.0, -90.0, 0.0))
	if _right_pants_outer_decal == null:
		_right_pants_outer_decal = _create_avatar_decal("RightPantsOuterDecal", right_leg_mesh, Vector2(1.02, 2.02), Vector3(-0.506, 0.0, 0.0), Vector3(0.0, -90.0, 0.0))
	if _right_pants_inner_decal == null:
		_right_pants_inner_decal = _create_avatar_decal("RightPantsInnerDecal", right_leg_mesh, Vector2(1.02, 2.02), Vector3(0.506, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	if _left_pants_up_decal == null:
		_left_pants_up_decal = _create_avatar_decal("LeftPantsUpDecal", left_leg_mesh, Vector2(1.02, 1.02), Vector3(0.0, 1.006, 0.0), Vector3(-90.0, 0.0, 0.0))
	if _left_pants_down_decal == null:
		_left_pants_down_decal = _create_avatar_decal("LeftPantsDownDecal", left_leg_mesh, Vector2(1.02, 1.02), Vector3(0.0, -1.006, 0.0), Vector3(90.0, 0.0, 0.0))
	if _right_pants_up_decal == null:
		_right_pants_up_decal = _create_avatar_decal("RightPantsUpDecal", right_leg_mesh, Vector2(1.02, 1.02), Vector3(0.0, 1.006, 0.0), Vector3(-90.0, 0.0, 0.0))
	if _right_pants_down_decal == null:
		_right_pants_down_decal = _create_avatar_decal("RightPantsDownDecal", right_leg_mesh, Vector2(1.02, 1.02), Vector3(0.0, -1.006, 0.0), Vector3(90.0, 0.0, 0.0))

func _create_avatar_decal(node_name: String, parent_mesh: MeshInstance3D, size: Vector2, local_position: Vector3, local_rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if parent_mesh == null:
		return null
	var stable_position := _stabilize_avatar_decal_position(local_position)
	var stable_size := _stabilize_avatar_decal_size(size)
	var existing := parent_mesh.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		var existing_quad := existing.mesh as QuadMesh
		if existing_quad != null:
			existing_quad.size = stable_size
		existing.rotation_degrees = local_rotation_degrees
		existing.position = stable_position
		return existing
	var decal := MeshInstance3D.new()
	decal.name = node_name
	var quad := QuadMesh.new()
	quad.size = stable_size
	decal.mesh = quad
	decal.position = stable_position
	decal.rotation_degrees = local_rotation_degrees
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.visible = false
	parent_mesh.add_child(decal)
	return decal

func _stabilize_avatar_decal_position(local_position: Vector3) -> Vector3:
	var result := local_position
	result.x = _stabilize_avatar_decal_axis(result.x)
	result.y = _stabilize_avatar_decal_axis(result.y)
	result.z = _stabilize_avatar_decal_axis(result.z)
	return result

func _stabilize_avatar_decal_axis(value: float) -> float:
	var sign_value := signf(value)
	var abs_value := absf(value)
	if is_equal_approx(abs_value, 0.506):
		return sign_value * 0.515
	if is_equal_approx(abs_value, 1.006):
		return sign_value * 1.015
	return value

func _stabilize_avatar_decal_size(size: Vector2) -> Vector2:
	if size.x < 0.9 and size.y < 0.9:
		return size
	return Vector2(size.x + 0.026, size.y + 0.026)

func _create_avatar_face_decal(node_name: String, parent_mesh: MeshInstance3D) -> MeshInstance3D:
	if parent_mesh == null:
		return null
	var existing := parent_mesh.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		existing.mesh = _make_curved_avatar_face_mesh()
		existing.position = Vector3.ZERO
		existing.rotation_degrees = Vector3.ZERO
		return existing
	var decal := MeshInstance3D.new()
	decal.name = node_name
	decal.mesh = _make_curved_avatar_face_mesh()
	decal.position = Vector3.ZERO
	decal.rotation_degrees = Vector3.ZERO
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.visible = false
	parent_mesh.add_child(decal)
	return decal

func _make_curved_avatar_face_mesh() -> ArrayMesh:
	var surface_radius := AVATAR_FACE_DECAL_RADIUS + AVATAR_FACE_DECAL_SURFACE_OFFSET
	var half_angle: float = asin(clampf((AVATAR_FACE_DECAL_SIZE.x * 0.5) / surface_radius, 0.05, 0.95))
	var half_height: float = AVATAR_FACE_DECAL_SIZE.y * 0.5
	var segment_count: int = maxi(2, AVATAR_FACE_DECAL_SEGMENTS)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for row in range(2):
		var row_t: float = float(row)
		var y: float = AVATAR_FACE_DECAL_CENTER_Y + lerpf(half_height, -half_height, row_t)
		for i in range(segment_count + 1):
			var t: float = float(i) / float(segment_count)
			var angle: float = lerpf(-half_angle, half_angle, t)
			vertices.append(Vector3(sin(angle) * surface_radius, y, cos(angle) * surface_radius))
			uvs.append(Vector2(t, row_t))
	var indices := PackedInt32Array()
	var bottom_offset: int = segment_count + 1
	for i in range(segment_count):
		var top_a: int = i
		var top_b: int = i + 1
		var bottom_a: int = bottom_offset + i
		var bottom_b: int = bottom_offset + i + 1
		indices.append(top_a)
		indices.append(bottom_a)
		indices.append(top_b)
		indices.append(top_b)
		indices.append(bottom_a)
		indices.append(bottom_b)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _set_avatar_decal_texture(decal: MeshInstance3D, texture_path: String, remove_edge_background: bool = false, crop_to_visible: bool = false, template_region: Rect2 = Rect2()) -> void:
	if decal == null:
		return
	var clean_path: String = texture_path.strip_edges()
	if clean_path.is_empty():
		decal.set_surface_override_material(0, null)
		decal.visible = false
		return
	var texture := _load_texture_from_any_path(clean_path, remove_edge_background, crop_to_visible, template_region)
	if texture == null:
		decal.set_surface_override_material(0, null)
		decal.visible = false
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.disable_receive_shadows = true
	material.render_priority = 2 if template_region.size != Vector2.ZERO else 0
	decal.set_surface_override_material(0, material)
	decal.visible = true

func _load_texture_from_any_path(texture_path: String, remove_edge_background: bool = false, crop_to_visible: bool = false, template_region: Rect2 = Rect2()) -> Texture2D:
	var clean_path: String = texture_path.strip_edges()
	if clean_path.is_empty():
		return null
	if clean_path.begins_with("user://avatar_templates/") and _has_multiplayer_peer() and not is_multiplayer_authority():
		_request_texture_from_authority(clean_path)
	if _is_http_avatar_texture_path(clean_path):
		var cached_remote_path := _get_remote_avatar_texture_cache_path(clean_path)
		if FileAccess.file_exists(cached_remote_path):
			if _avatar_texture_path_failed(cached_remote_path, cached_remote_path):
				_delete_avatar_texture_cache_file(cached_remote_path)
				_request_remote_avatar_texture(clean_path, cached_remote_path)
				return null
			clean_path = cached_remote_path
		else:
			_request_remote_avatar_texture(clean_path, cached_remote_path)
			return null
	var should_prepare: bool = remove_edge_background or crop_to_visible or template_region.size != Vector2.ZERO
	var cache_key: String = ""
	if should_prepare:
		cache_key = "%s|edge=%s|crop=%s|region=%s" % [clean_path, str(remove_edge_background), str(crop_to_visible), str(template_region)]
		var cached_texture: Texture2D = _avatar_decal_texture_cache.get(cache_key, null) as Texture2D
		if cached_texture != null:
			return cached_texture
	if clean_path.begins_with("res://") and ResourceLoader.exists(clean_path):
		var resource := load(clean_path)
		if not should_prepare:
			return resource as Texture2D
		if resource is Texture2D:
			var loaded_image: Image = (resource as Texture2D).get_image()
			return _cache_avatar_decal_texture(cache_key, _make_decal_texture_from_image(loaded_image, remove_edge_background, crop_to_visible, template_region))
	var resolved_path: String = _resolve_existing_file_path(clean_path)
	if resolved_path.is_empty() and clean_path.begins_with("user://"):
		var user_global_path: String = ProjectSettings.globalize_path(clean_path)
		if FileAccess.file_exists(user_global_path):
			resolved_path = user_global_path
	if resolved_path.is_empty():
		if clean_path.begins_with("user://avatar_templates/"):
			_request_texture_from_authority(clean_path)
		return null
	if _avatar_texture_path_failed(clean_path, resolved_path):
		return null
	if _is_avatar_texture_cache_path(clean_path) or _is_avatar_texture_cache_path(resolved_path):
		if not _file_has_probable_image_header(resolved_path):
			_mark_avatar_texture_load_failed(clean_path, resolved_path)
			return null
	var image := Image.new()
	if image.load(resolved_path) != OK:
		_mark_avatar_texture_load_failed(clean_path, resolved_path)
		return null
	return _cache_avatar_decal_texture(cache_key, _make_decal_texture_from_image(image, remove_edge_background, crop_to_visible, template_region))

func _avatar_texture_path_failed(path_a: String, path_b: String) -> bool:
	return _failed_avatar_texture_paths.has(path_a) or _failed_avatar_texture_paths.has(path_b)

func _mark_avatar_texture_load_failed(original_path: String, resolved_path: String) -> void:
	if not original_path.is_empty():
		_failed_avatar_texture_paths[original_path] = Time.get_ticks_msec()
	if not resolved_path.is_empty():
		_failed_avatar_texture_paths[resolved_path] = Time.get_ticks_msec()
	if _is_avatar_texture_cache_path(original_path) or _is_avatar_texture_cache_path(resolved_path):
		_delete_avatar_texture_cache_file(resolved_path if not resolved_path.is_empty() else original_path)

func _is_avatar_texture_cache_path(path_value: String) -> bool:
	var normalized := path_value.strip_edges().replace("\\", "/")
	return normalized.begins_with("user://cache/avatar_textures/") or normalized.find("/cache/avatar_textures/") != -1

func _delete_avatar_texture_cache_file(path_value: String) -> void:
	var normalized := path_value.strip_edges()
	if normalized.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(normalized) if normalized.begins_with("user://") else normalized
	if FileAccess.file_exists(absolute_path):
		var err := DirAccess.remove_absolute(absolute_path)
		if err != OK:
			push_warning("[Player] Could not remove corrupt avatar texture cache file: %s" % absolute_path)

func _file_has_probable_image_header(path_value: String) -> bool:
	if path_value.strip_edges().is_empty() or not FileAccess.file_exists(path_value):
		return false
	var file := FileAccess.open(path_value, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(mini(16, int(file.get_length())))
	file.close()
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return true
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return true
	if bytes.size() >= 12 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		return true
	return false

func _cache_avatar_decal_texture(cache_key: String, texture: Texture2D) -> Texture2D:
	if texture != null and not cache_key.is_empty():
		if _avatar_decal_texture_cache.size() >= AVATAR_DECAL_CACHE_MAX_ENTRIES and not _avatar_decal_texture_cache.has(cache_key):
			_avatar_decal_texture_cache.clear()
		_avatar_decal_texture_cache[cache_key] = texture
	return texture

func _request_texture_from_authority(clean_path: String) -> void:
	if not _has_multiplayer_peer() or is_multiplayer_authority():
		return
	var authority_id: int = get_multiplayer_authority()
	var request_key: String = "%s@%d" % [clean_path, authority_id]
	if _requested_textures.has(request_key):
		return
	_requested_textures[request_key] = true
	var file_name = clean_path.get_file()
	request_custom_texture.rpc_id(authority_id, file_name)

func _is_http_avatar_texture_path(value: String) -> bool:
	var clean := value.strip_edges()
	return clean.begins_with("http://") or clean.begins_with("https://")

func _get_remote_avatar_texture_cache_path(url: String) -> String:
	var cache_dir := "user://cache/avatar_textures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var no_query := url.get_slice("?", 0)
	var extension := no_query.get_extension().to_lower()
	if not (extension in ["png", "jpg", "jpeg", "webp"]):
		extension = "png"
	var hash_value: int = 5381
	for i in range(url.length()):
		hash_value = int((hash_value * 33 + url.unicode_at(i)) % 2147483647)
	return cache_dir.path_join("avatar_texture_%d.%s" % [hash_value, extension])

func _request_remote_avatar_texture(url: String, target_path: String) -> void:
	if not is_inside_tree() or url.is_empty() or target_path.is_empty():
		return
	if bool(_requested_remote_avatar_textures.get(url, false)):
		return
	_requested_remote_avatar_textures[url] = true
	var request := HTTPRequest.new()
	request.download_file = target_path
	request.timeout = 18.0
	add_child(request)
	var start_error := request.request(url)
	if start_error != OK:
		_requested_remote_avatar_textures.erase(url)
		request.queue_free()
		return
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_requested_remote_avatar_textures.erase(url)
		if is_instance_valid(request):
			request.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
			var absolute_target := ProjectSettings.globalize_path(target_path)
			if FileAccess.file_exists(absolute_target) and _file_has_probable_image_header(absolute_target):
				_failed_avatar_texture_paths.erase(target_path)
				_failed_avatar_texture_paths.erase(absolute_target)
				force_avatar_visual_refresh()
			else:
				_mark_avatar_texture_load_failed(target_path, absolute_target)
		else:
			_delete_avatar_texture_cache_file(target_path)
	)

@rpc("any_peer", "reliable")
func request_custom_texture(file_name: String) -> void:
	var requester_id = multiplayer.get_remote_sender_id()
	var local_path = "user://avatar_templates/" + file_name.get_file()
	if FileAccess.file_exists(local_path):
		var file = FileAccess.open(local_path, FileAccess.READ)
		if file:
			var bytes = file.get_buffer(file.get_length())
			file.close()
			receive_custom_texture.rpc_id(requester_id, file_name, bytes)

@rpc("any_peer", "reliable")
func receive_custom_texture(file_name: String, bytes: PackedByteArray) -> void:
	var local_path = "user://avatar_templates/" + file_name.get_file()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://avatar_templates"))
	var file = FileAccess.open(local_path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		force_avatar_visual_refresh()

func _make_decal_texture_from_image(image: Image, remove_edge_background: bool, crop_to_visible: bool, template_region: Rect2 = Rect2()) -> Texture2D:
	if image == null or image.is_empty():
		return null
	var prepared := image.duplicate()
	prepared.convert(Image.FORMAT_RGBA8)
	if template_region.size != Vector2.ZERO:
		prepared = _extract_template_region(prepared, template_region)
	var initial_longest_side: int = maxi(prepared.get_width(), prepared.get_height())
	if initial_longest_side > AVATAR_DECAL_PREPROCESS_MAX_SIDE:
		var initial_ratio: float = float(AVATAR_DECAL_PREPROCESS_MAX_SIDE) / float(initial_longest_side)
		prepared.resize(maxi(1, roundi(float(prepared.get_width()) * initial_ratio)), maxi(1, roundi(float(prepared.get_height()) * initial_ratio)), Image.INTERPOLATE_LANCZOS)
	if remove_edge_background:
		_make_edge_light_background_transparent(prepared)
	if crop_to_visible:
		prepared = _crop_image_to_visible_pixels(prepared)
	var longest_side: int = maxi(prepared.get_width(), prepared.get_height())
	if longest_side > AVATAR_DECAL_FINAL_MAX_SIDE:
		var ratio: float = float(AVATAR_DECAL_FINAL_MAX_SIDE) / float(longest_side)
		prepared.resize(maxi(1, roundi(float(prepared.get_width()) * ratio)), maxi(1, roundi(float(prepared.get_height()) * ratio)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(prepared)

func _is_front_template_region(region: Rect2) -> bool:
	for front_region in AVATAR_TEMPLATE_NON_TEMPLATE_FRONT_REGIONS:
		var typed_region: Rect2 = front_region
		if region.position.distance_to(typed_region.position) < 0.002 and region.size.distance_to(typed_region.size) < 0.002:
			return true
	return false

func _is_probable_clothing_template(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return false
	var aspect: float = float(width) / float(height)
	if aspect < 0.82 or aspect > 1.22:
		return false
	if _sample_template_global_gray_ratio(image) < AVATAR_TEMPLATE_MIN_GLOBAL_GRAY_RATIO:
		return false
	# Roblox-style clothing templates have a mostly gray guide background at
	# the corners. Plain uploaded logos/screenshots must not be split over arms.
	var corner_size: int = maxi(8, floori(float(mini(width, height)) * 0.08))
	var corner_samples: int = 0
	var corner_gray_samples: int = 0
	var corner_step: int = maxi(4, floori(float(corner_size) / 5.0))
	for x_offset in [0, width - corner_size]:
		for y_offset in [0, height - corner_size]:
			for x in range(x_offset, x_offset + corner_size, corner_step):
				for y in range(y_offset, y_offset + corner_size, corner_step):
					corner_samples += 1
					if _is_gray_template_pixel(image.get_pixel(clampi(x, 0, width - 1), clampi(y, 0, height - 1))):
						corner_gray_samples += 1
	if corner_samples <= 0 or float(corner_gray_samples) / float(corner_samples) < 0.86:
		return false
	var gray_samples: int = 0
	var total_samples: int = 0
	var step: int = maxi(4, floori(float(mini(width, height)) / float(AVATAR_TEMPLATE_EDGE_SAMPLE_STEP)))
	for x in range(0, width, step):
		total_samples += 2
		if _is_gray_template_pixel(image.get_pixel(x, 0)):
			gray_samples += 1
		if _is_gray_template_pixel(image.get_pixel(x, height - 1)):
			gray_samples += 1
	for y in range(0, height, step):
		total_samples += 2
		if _is_gray_template_pixel(image.get_pixel(0, y)):
			gray_samples += 1
		if _is_gray_template_pixel(image.get_pixel(width - 1, y)):
			gray_samples += 1
	if total_samples <= 0:
		return false
	if float(gray_samples) / float(total_samples) < 0.74:
		return false
	for guide_rect in AVATAR_TEMPLATE_GUIDE_SAMPLE_RECTS:
		var typed_rect: Rect2 = guide_rect
		if _sample_template_gray_ratio(image, typed_rect) < 0.72:
			return false
	return true

func _sample_template_global_gray_ratio(image: Image) -> float:
	if image == null or image.is_empty():
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return 0.0
	var step_x: int = maxi(1, floori(float(width) / 14.0))
	var step_y: int = maxi(1, floori(float(height) / 14.0))
	var total_samples: int = 0
	var gray_samples: int = 0
	for x in range(0, width, step_x):
		for y in range(0, height, step_y):
			total_samples += 1
			if _is_gray_template_pixel(image.get_pixel(clampi(x, 0, width - 1), clampi(y, 0, height - 1))):
				gray_samples += 1
	if total_samples <= 0:
		return 0.0
	return float(gray_samples) / float(total_samples)

func _sample_template_gray_ratio(image: Image, normalized_rect: Rect2) -> float:
	if image == null or image.is_empty():
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	var x0: int = clampi(floori(normalized_rect.position.x * float(width)), 0, width - 1)
	var y0: int = clampi(floori(normalized_rect.position.y * float(height)), 0, height - 1)
	var x1: int = clampi(ceili((normalized_rect.position.x + normalized_rect.size.x) * float(width)), 0, width)
	var y1: int = clampi(ceili((normalized_rect.position.y + normalized_rect.size.y) * float(height)), 0, height)
	x1 = maxi(x1, mini(width, x0 + 1))
	y1 = maxi(y1, mini(height, y0 + 1))
	var step_x: int = maxi(1, floori(float(x1 - x0) / 5.0))
	var step_y: int = maxi(1, floori(float(y1 - y0) / 5.0))
	var total_samples: int = 0
	var gray_samples: int = 0
	for x in range(x0, x1, step_x):
		for y in range(y0, y1, step_y):
			total_samples += 1
			if _is_gray_template_pixel(image.get_pixel(clampi(x, 0, width - 1), clampi(y, 0, height - 1))):
				gray_samples += 1
	if total_samples <= 0:
		return 0.0
	return float(gray_samples) / float(total_samples)

func _is_gray_template_pixel(color: Color) -> bool:
	if color.a < 0.2:
		return true
	var max_channel: float = maxf(color.r, maxf(color.g, color.b))
	var min_channel: float = minf(color.r, minf(color.g, color.b))
	var brightness: float = (color.r + color.g + color.b) / 3.0
	return absf(max_channel - min_channel) <= AVATAR_TEMPLATE_EDGE_GRAY_TOLERANCE and brightness > 0.35 and brightness < 0.85

func _make_center_square_region(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var width: int = image.get_width()
	var height: int = image.get_height()
	var side: int = mini(width, height)
	if side <= 0:
		return image
	var x: int = maxi(0, floori(float(width - side) * 0.5))
	var y: int = maxi(0, floori(float(height - side) * 0.5))
	return image.get_region(Rect2i(x, y, side, side))

func _make_transparent_template_region() -> Image:
	var transparent := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	transparent.fill(Color(1.0, 1.0, 1.0, 0.0))
	return transparent

func _extract_template_region(image: Image, normalized_region: Rect2) -> Image:
	if image == null or image.is_empty():
		return image
	var width: int = image.get_width()
	var height: int = image.get_height()
	var x: int = clampi(roundi(normalized_region.position.x * float(width)), 0, width - 1)
	var y: int = clampi(roundi(normalized_region.position.y * float(height)), 0, height - 1)
	var region_width: int = clampi(roundi(normalized_region.size.x * float(width)), 1, width - x)
	var region_height: int = clampi(roundi(normalized_region.size.y * float(height)), 1, height - y)
	var right_edge: int = mini(width, x + region_width + AVATAR_TEMPLATE_REGION_BLEED_PX)
	var bottom_edge: int = mini(height, y + region_height + AVATAR_TEMPLATE_REGION_BLEED_PX)
	x = maxi(0, x - AVATAR_TEMPLATE_REGION_BLEED_PX)
	y = maxi(0, y - AVATAR_TEMPLATE_REGION_BLEED_PX)
	region_width = maxi(1, right_edge - x)
	region_height = maxi(1, bottom_edge - y)
	return image.get_region(Rect2i(x, y, region_width, region_height))

func _make_edge_light_background_transparent(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue: Array[Vector2i] = []
	for x in range(width):
		_queue_light_pixel_if_needed(image, visited, queue, x, 0, width)
		_queue_light_pixel_if_needed(image, visited, queue, x, height - 1, width)
	for y in range(height):
		_queue_light_pixel_if_needed(image, visited, queue, 0, y, width)
		_queue_light_pixel_if_needed(image, visited, queue, width - 1, y, width)
	var cursor: int = 0
	while cursor < queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		var color: Color = image.get_pixel(point.x, point.y)
		color.a = 0.0
		image.set_pixel(point.x, point.y, color)
		_queue_light_pixel_if_needed(image, visited, queue, point.x + 1, point.y, width)
		_queue_light_pixel_if_needed(image, visited, queue, point.x - 1, point.y, width)
		_queue_light_pixel_if_needed(image, visited, queue, point.x, point.y + 1, width)
		_queue_light_pixel_if_needed(image, visited, queue, point.x, point.y - 1, width)

func _queue_light_pixel_if_needed(image: Image, visited: PackedByteArray, queue: Array[Vector2i], x: int, y: int, width: int) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	var index: int = y * width + x
	if visited[index] != 0:
		return
	visited[index] = 1
	var color: Color = image.get_pixel(x, y)
	if color.a < 0.05 or (color.r > 0.88 and color.g > 0.88 and color.b > 0.88):
		queue.append(Vector2i(x, y))

func _crop_image_to_visible_pixels(image: Image) -> Image:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var min_x: int = width
	var min_y: int = height
	var max_x: int = -1
	var max_y: int = -1
	for y in range(height):
		for x in range(width):
			if image.get_pixel(x, y).a > 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return image
	var padding: int = 6
	var visible_width: int = max_x - min_x + 1
	var visible_height: int = max_y - min_y + 1
	var square_size: int = maxi(visible_width, visible_height) + padding * 2
	square_size = mini(square_size, mini(width, height))
	if square_size <= 0:
		return image
	var center_x: float = float(min_x + max_x) * 0.5
	var center_y: float = float(min_y + max_y) * 0.5
	var crop_x: int = clampi(roundi(center_x - float(square_size) * 0.5), 0, maxi(0, width - square_size))
	var crop_y: int = clampi(roundi(center_y - float(square_size) * 0.5), 0, maxi(0, height - square_size))
	return image.get_region(Rect2i(crop_x, crop_y, square_size, square_size))

func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _get_mobile_runtime() -> Node:
	return get_node_or_null("/root/MobileRuntime")


func _get_mobile_move_vector() -> Vector2:
	var mobile_runtime: Node = _get_mobile_runtime()
	if mobile_runtime == null or not mobile_runtime.has_method("get_move_vector"):
		return Vector2.ZERO
	var value: Variant = mobile_runtime.call("get_move_vector")
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO


func _consume_mobile_jump_pressed() -> bool:
	var mobile_runtime: Node = _get_mobile_runtime()
	if mobile_runtime == null or not mobile_runtime.has_method("consume_jump_pressed"):
		return false
	return bool(mobile_runtime.call("consume_jump_pressed"))


func _apply_mobile_camera_delta() -> void:
	var mobile_runtime: Node = _get_mobile_runtime()
	if mobile_runtime == null or not mobile_runtime.has_method("consume_look_delta"):
		return
	if mobile_runtime.has_method("consume_zoom_delta"):
		var zoom_value: Variant = mobile_runtime.call("consume_zoom_delta")
		if zoom_value is float or zoom_value is int:
			var zoom_delta: float = float(zoom_value)
			if absf(zoom_delta) > 0.001:
				_set_camera_desired_spring_length(_camera_desired_spring_length + zoom_delta)
				_update_first_person_mode()
	var value: Variant = mobile_runtime.call("consume_look_delta")
	if not value is Vector2:
		return
	var mobile_look_delta: Vector2 = value as Vector2
	if mobile_look_delta.length_squared() <= 0.000001:
		return
	_apply_camera_rotation_delta(mobile_look_delta.x, mobile_look_delta.y)


func _is_preview_instance() -> bool:
	return is_ui_preview or (not _has_multiplayer_peer() and not _is_studio_playtest_instance())

func _ensure_humanoid_api_node() -> Node:
	var humanoid := get_node_or_null("Humanoid")
	if humanoid == null:
		humanoid = Node.new()
		humanoid.name = "Humanoid"
		add_child(humanoid, true)
	humanoid.set_meta("roblox_class", "Humanoid")
	humanoid.set_meta("bobux_character_body_instance_id", get_instance_id())
	humanoid.set_meta("Health", float(current_health))
	humanoid.set_meta("MaxHealth", float(MAX_HEALTH))
	humanoid.set_meta("WalkSpeed", _logical_move_speed)
	humanoid.set_meta("JumpPower", _logical_jump_velocity)
	humanoid.set_meta("AutoRotate", true)
	humanoid.set_meta("RigType", "R6")
	humanoid.set_meta("HumanoidState", _character_state_name(_character_state))
	if humanoid.get_node_or_null("Animator") == null:
		var animator := Node.new()
		animator.name = "Animator"
		animator.set_meta("roblox_class", "Animator")
		animator.set_meta("bobux_runtime_generated", true)
		humanoid.add_child(animator, true)
	return humanoid


func ensure_roblox_character_contract() -> void:
	set_meta("roblox_class", "Model")
	set_meta("PrimaryPart", "HumanoidRootPart")
	var humanoid := _ensure_humanoid_api_node()
	var proxy_specs := {
		"HumanoidRootPart": {"position": Vector3(0.0, 2.3, 0.0), "size": Vector3(2.0, 2.0, 1.0), "transparency": 1.0},
		"Torso": {"position": Vector3(0.0, 3.0, 0.0), "size": Vector3(2.0, 2.0, 1.0), "transparency": 0.0},
		"Head": {"position": Vector3(0.0, 4.6, 0.0), "size": Vector3(1.2, 1.2, 1.2), "transparency": 0.0},
		"Left Arm": {"position": Vector3(-1.5, 3.0, 0.0), "size": Vector3(1.0, 2.0, 1.0), "transparency": 0.0},
		"Right Arm": {"position": Vector3(1.5, 3.0, 0.0), "size": Vector3(1.0, 2.0, 1.0), "transparency": 0.0},
		"Left Leg": {"position": Vector3(-0.5, 1.0, 0.0), "size": Vector3(1.0, 2.0, 1.0), "transparency": 0.0},
		"Right Leg": {"position": Vector3(0.5, 1.0, 0.0), "size": Vector3(1.0, 2.0, 1.0), "transparency": 0.0},
	}
	var proxies: Dictionary = {}
	for proxy_name_variant in proxy_specs.keys():
		var proxy_name := str(proxy_name_variant)
		var proxy := get_node_or_null(proxy_name) as Node3D
		if proxy == null:
			proxy = Node3D.new()
			proxy.name = proxy_name
			add_child(proxy, true)
		var spec: Dictionary = proxy_specs[proxy_name_variant]
		proxy.position = spec.get("position", Vector3.ZERO)
		proxy.set_meta("roblox_class", "Part")
		proxy.set_meta("bobux_character_part_proxy", true)
		proxy.set_meta("bobux_character_body_instance_id", get_instance_id())
		proxy.set_meta("bobux_runtime_generated", true)
		proxy.set_meta("Size", spec.get("size", Vector3.ONE))
		proxy.set_meta("CanCollide", proxy_name != "HumanoidRootPart")
		proxy.set_meta("Transparency", float(spec.get("transparency", 0.0)))
		proxy.set_meta("Anchored", false)
		proxy.set_meta("roblox_properties", {
			"Name": proxy_name,
			"Size": spec.get("size", Vector3.ONE),
			"CanCollide": proxy_name != "HumanoidRootPart",
			"Transparency": float(spec.get("transparency", 0.0)),
			"Anchored": false,
		})
		proxies[proxy_name] = proxy

	var body_colors := get_node_or_null("Body Colors")
	if body_colors == null:
		body_colors = Node.new()
		body_colors.name = "Body Colors"
		body_colors.set_meta("roblox_class", "BodyColors")
		body_colors.set_meta("bobux_runtime_generated", true)
		add_child(body_colors, true)
	body_colors.set_meta("roblox_properties", {
		"HeadColor3": [0.957, 0.773, 0.259],
		"LeftArmColor3": [0.957, 0.773, 0.259],
		"RightArmColor3": [0.957, 0.773, 0.259],
		"TorsoColor3": [0.18, 0.467, 0.733],
		"LeftLegColor3": [0.294, 0.682, 0.196],
		"RightLegColor3": [0.294, 0.682, 0.196],
	})

	var joint_specs := [
		["RootJoint", "HumanoidRootPart", "Torso"],
		["Neck", "Torso", "Head"],
		["Left Shoulder", "Torso", "Left Arm"],
		["Right Shoulder", "Torso", "Right Arm"],
		["Left Hip", "Torso", "Left Leg"],
		["Right Hip", "Torso", "Right Leg"],
	]
	for joint_spec in joint_specs:
		var part0: Node = proxies.get(str(joint_spec[1]), null) as Node
		if part0 == null:
			continue
		var joint := part0.get_node_or_null(str(joint_spec[0]))
		if joint == null:
			joint = Node.new()
			joint.name = str(joint_spec[0])
			part0.add_child(joint, true)
		joint.set_meta("roblox_class", "Motor6D")
		joint.set_meta("Part0", str(joint_spec[1]))
		joint.set_meta("Part1", str(joint_spec[2]))
		joint.set_meta("bobux_runtime_generated", true)

	if humanoid != null:
		humanoid.set_meta("bobux_character_body_instance_id", get_instance_id())

func _sync_humanoid_runtime_properties(grounded_now: bool) -> void:
	var humanoid := _ensure_humanoid_api_node()
	humanoid.set_meta("Health", float(current_health))
	humanoid.set_meta("WalkSpeed", _logical_move_speed)
	humanoid.set_meta("JumpPower", _logical_jump_velocity)
	humanoid.set_meta("HumanoidState", _character_state_name(_character_state))
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	humanoid.set_meta("MoveDirection", planar_velocity.normalized() if planar_velocity.length_squared() > 0.001 else Vector3.ZERO)
	humanoid.set_meta("FloorMaterial", _resolve_humanoid_floor_material(grounded_now))

func _resolve_humanoid_floor_material(grounded_now: bool) -> String:
	if _swimming_active:
		return "Water"
	if _climbing_active or _ledge_hang_active or _ledge_mantle_active:
		return "Climbable"
	if not grounded_now:
		return "Air"
	# Resolve the actual surface under the body. Imported maps and native Studio
	# maps expose the same metadata, so scripts and footsteps see one material API.
	for collision_index in range(get_slide_collision_count() - 1, -1, -1):
		var collision := get_slide_collision(collision_index)
		if collision == null or collision.get_normal().dot(Vector3.UP) < 0.35:
			continue
		var collider_variant: Variant = collision.get_collider()
		if collider_variant is Node:
			var material_name := _material_name_from_collider(collider_variant as Node)
			if not material_name.is_empty():
				return material_name
	return "Plastic"

func _material_name_from_collider(collider: Node) -> String:
	var cursor: Node = collider
	while cursor != null:
		for metadata_key in ["surface_type", "material_type", "roblox_material_name", "Material"]:
			if cursor.has_meta(metadata_key):
				var canonical := _canonical_humanoid_material_name(str(cursor.get_meta(metadata_key)))
				if not canonical.is_empty():
					return canonical
		var properties: Variant = cursor.get_meta("roblox_properties", {})
		if properties is Dictionary:
			for property_key in (properties as Dictionary).keys():
				if str(property_key).to_lower() != "material":
					continue
				var canonical := _canonical_humanoid_material_name(str((properties as Dictionary).get(property_key)))
				if not canonical.is_empty():
					return canonical
		cursor = cursor.get_parent()
	return ""

static func _canonical_humanoid_material_name(raw_value: String) -> String:
	var normalized := raw_value.strip_edges().to_lower().replace("enum.material.", "").replace(" ", "").replace("_", "").replace("-", "")
	var canonical_by_key := {
		"air": "Air", "asphalt": "Asphalt", "basalt": "Basalt", "brick": "Brick",
		"cobblestone": "Cobblestone", "concrete": "Concrete", "corrodedmetal": "CorrodedMetal",
		"crackedlava": "CrackedLava", "diamondplate": "DiamondPlate", "fabric": "Fabric",
		"forcefield": "ForceField", "glass": "Glass", "grass": "Grass", "ground": "Ground",
		"ice": "Ice", "leafygrass": "LeafyGrass", "limestone": "Limestone", "marble": "Marble",
		"metal": "Metal", "mud": "Mud", "neon": "Neon", "pavement": "Pavement",
		"pebble": "Pebble", "plastic": "Plastic", "rock": "Rock", "roofshingles": "RoofShingles",
		"salt": "Salt", "sand": "Sand", "sandstone": "Sandstone", "slate": "Slate",
		"smoothplastic": "SmoothPlastic", "snow": "Snow", "water": "Water", "wood": "Wood",
		"woodplanks": "WoodPlanks", "climbable": "Climbable"
	}
	return str(canonical_by_key.get(normalized, ""))

func _has_multiplayer_peer() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()

func _is_local_authority_safe() -> bool:
	if not _has_multiplayer_peer():
		return _is_studio_playtest_instance()
	return is_multiplayer_authority()

func _is_studio_playtest_instance() -> bool:
	return bool(get_meta("bobux_studio_playtest", false))

func _is_dedicated_server_runtime() -> bool:
	return GameState != null and GameState.has_method("is_dedicated_server_runtime") and bool(GameState.is_dedicated_server_runtime())

func set_respawn_position(new_respawn_position: Vector3) -> void:
	if _is_preview_instance() or not _is_local_authority_safe():
		return
	respawn_position = new_respawn_position
	_has_checkpoint = true

func set_initial_spawn_position(new_spawn_position: Vector3) -> void:
	respawn_position = new_spawn_position
	_has_checkpoint = false

func set_network_position_origin(origin: Vector3) -> void:
	network_position_origin = origin if _is_vector3_finite(origin) else Vector3.ZERO
	_remote_interp_initialized = false
	_remote_position_buffer.clear()

func restore_checkpoint_state(checkpoint_position: Vector3) -> void:
	respawn_position = checkpoint_position
	_has_checkpoint = true

func configure_spawn_points(points: Array, initial_index: int = -1) -> void:
	spawn_points.clear()
	for point in points:
		if point is Vector3:
			spawn_points.append(point)
	_last_spawn_index = initial_index
	if _last_spawn_index < 0 and not spawn_points.is_empty():
		for i in range(spawn_points.size()):
			if spawn_points[i].distance_squared_to(respawn_position) < 0.01:
				_last_spawn_index = i
				break

func get_respawn_position() -> Vector3:
	return respawn_position

func get_health() -> int:
	return current_health

func get_max_health() -> int:
	return MAX_HEALTH

func apply_world_stud_scale(value: float) -> void:
	world_stud_scale = clampf(value, 0.25, 2.0)
	scale = Vector3.ONE * world_stud_scale
	gravity_force = _world_units(GRAVITY_FORCE)
	move_speed = _world_units(_logical_move_speed)
	jump_velocity_setting = _world_units(_logical_jump_velocity)
	safe_margin = maxf(_world_units(0.035), 0.006)
	floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
	set_meta("roblox_stud_scale", world_stud_scale)
	if is_inside_tree():
		_reset_all_physics_interpolation()

func get_humanoid_walk_speed() -> float:
	return _logical_move_speed

func set_humanoid_walk_speed(value: float) -> void:
	_logical_move_speed = maxf(0.0, value)
	move_speed = _world_units(_logical_move_speed)

func get_humanoid_jump_power() -> float:
	return _logical_jump_velocity

func set_humanoid_jump_power(value: float) -> void:
	_logical_jump_velocity = maxf(0.0, value)
	jump_velocity_setting = _world_units(_logical_jump_velocity)

func apply_movement_settings(settings: Dictionary) -> void:
	var merged_settings := {
		"move_speed": MOVE_SPEED,
		"sprint_multiplier": SPRINT_MULTIPLIER,
		"jump_velocity": JUMP_VELOCITY
	}
	for key in settings.keys():
		merged_settings[key] = settings[key]

	set_humanoid_walk_speed(maxf(1.0, float(merged_settings.get("move_speed", MOVE_SPEED))))
	sprint_multiplier = maxf(1.0, float(merged_settings.get("sprint_multiplier", SPRINT_MULTIPLIER)))
	set_humanoid_jump_power(maxf(1.0, float(merged_settings.get("jump_velocity", JUMP_VELOCITY))))

func take_damage(amount: float) -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_respawning or _is_network_gameplay_frozen():
		return
	current_health = maxi(0, current_health - maxi(1, roundi(amount)))
	if current_health <= 0:
		_handle_death_and_respawn()

func kill_now() -> void:
	take_damage(MAX_HEALTH)

func force_respawn() -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_network_gameplay_frozen():
		return
	var token: int = _begin_respawn_request()
	if _request_authoritative_respawn():
		_watch_authoritative_respawn_timeout(token)
		return
	_awaiting_authoritative_respawn = false
	respawn_at_checkpoint()

func can_use_teleport() -> bool:
	return Time.get_ticks_msec() >= _teleport_ready_at_msec

func teleport_to_position(target_position: Vector3) -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_network_gameplay_frozen():
		return
	_teleport_ready_at_msec = Time.get_ticks_msec() + TELEPORT_COOLDOWN_MS
	_stop_climbing()
	global_position = _get_safe_reposition_target(target_position)
	velocity = Vector3.ZERO
	floor_snap_length = 0.0
	# FIX Eye Strain Bug: Prevent interpolation from the old position.
	_reset_all_physics_interpolation()

func respawn_at_checkpoint() -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_network_gameplay_frozen():
		return
	var respawn_target: Vector3 = respawn_position if _has_checkpoint else _get_next_spawn_position()
	if _has_checkpoint:
		respawn_position = respawn_target
	else:
		respawn_position = respawn_target
	apply_authoritative_respawn_position(respawn_target, _has_checkpoint)

func _handle_death_and_respawn() -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_respawning or _is_network_gameplay_frozen():
		return
	var token: int = _begin_respawn_request()
	current_health = 0
	_set_character_state(CharacterState.DEAD)
	_sync_authoritative_replication_state(true)
	_play_death_sound()
	_spawn_death_fragments()
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(DEATH_RESPAWN_DELAY_SECONDS).timeout
	if token != _respawn_request_token or not _is_respawning:
		return
	if _request_authoritative_respawn():
		_watch_authoritative_respawn_timeout(token)
		return
	_awaiting_authoritative_respawn = false
	respawn_at_checkpoint()

func _handle_void_fall() -> void:
	if _is_preview_instance() or not _is_local_authority_safe():
		return
	if _is_network_gameplay_frozen():
		if global_position.y < VOID_HARD_RECOVERY_Y:
			_begin_respawn_request()
			_force_local_respawn_recovery()
		return
	if _is_respawning:
		var waited_msec: int = Time.get_ticks_msec() - _respawn_requested_at_msec
		if global_position.y < VOID_HARD_RECOVERY_Y or waited_msec > int(RESPAWN_SERVER_TIMEOUT_SECONDS * 1000.0):
			_force_local_respawn_recovery()
		return
	if global_position.y < VOID_HARD_RECOVERY_Y:
		_begin_respawn_request()
		_force_local_respawn_recovery()
		return
	_handle_death_and_respawn()

func _begin_respawn_request() -> int:
	_is_respawning = true
	_stop_climbing()
	_ledge_hang_active = false
	_ledge_mantle_active = false
	_swimming_active = false
	_water_volume = null
	if _seated_part != null:
		_leave_seat(false)
	_awaiting_authoritative_respawn = true
	_respawn_request_token += 1
	_respawn_requested_at_msec = Time.get_ticks_msec()
	velocity = Vector3.ZERO
	floor_snap_length = 0.0
	_set_collision_enabled(false)
	return _respawn_request_token

func _watch_authoritative_respawn_timeout(token: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(RESPAWN_SERVER_TIMEOUT_SECONDS).timeout
	if token != _respawn_request_token or not _is_respawning or not _awaiting_authoritative_respawn:
		return
	_force_local_respawn_recovery()

func _force_local_respawn_recovery() -> void:
	_awaiting_authoritative_respawn = false
	var respawn_base: Vector3 = respawn_position if _has_checkpoint else _get_next_spawn_position()
	var respawn_target := _get_safe_reposition_target(respawn_base)
	if not _is_vector3_finite(respawn_target):
		respawn_target = Vector3(0.0, FALLBACK_RESPAWN_HEIGHT, 0.0)
	# Keep the logical checkpoint at the surface. The safety lift belongs only to
	# this teleport; storing the lifted value would move every later respawn up.
	respawn_position = respawn_base if _is_vector3_finite(respawn_base) else respawn_target
	global_position = respawn_target
	velocity = Vector3.ZERO
	floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
	current_health = MAX_HEALTH
	_is_respawning = false
	_awaiting_authoritative_respawn = false
	_has_safe_position = true
	_last_safe_position = respawn_target
	_teleport_ready_at_msec = Time.get_ticks_msec() + TELEPORT_COOLDOWN_MS
	_stuck_timer = 0.0
	_previous_physics_position = respawn_target
	_restore_after_respawn()
	_reset_all_physics_interpolation()
	_sync_authoritative_replication_state(true)

func _request_authoritative_respawn() -> bool:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		return false
	var current_scene: Node = scene_tree.current_scene
	if current_scene == null or not current_scene.has_method("request_authoritative_respawn_for_local_player"):
		return false
	current_scene.call("request_authoritative_respawn_for_local_player")
	return true

func apply_authoritative_respawn_position(target_position: Vector3, treat_as_checkpoint: bool = false) -> void:
	if _is_preview_instance() or not _is_local_authority_safe() or _is_network_gameplay_frozen():
		return
	respawn_position = target_position
	_has_checkpoint = treat_as_checkpoint
	global_position = _get_safe_reposition_target(target_position)
	velocity = Vector3.ZERO
	floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
	current_health = MAX_HEALTH
	_is_respawning = false
	_awaiting_authoritative_respawn = false
	_has_safe_position = true
	_last_safe_position = global_position
	_teleport_ready_at_msec = Time.get_ticks_msec() + TELEPORT_COOLDOWN_MS
	_restore_after_respawn()
	# FIX Eye Strain Bug: Prevent interpolation from the old position.
	_reset_all_physics_interpolation()

func _spawn_death_fragments() -> void:
	if _death_visual_active or visuals == null or get_parent() == null:
		return
	_death_visual_active = true
	visuals.visible = false
	_death_fragment_root = Node3D.new()
	_death_fragment_root.name = "%s_DeathFragments" % name
	get_parent().add_child(_death_fragment_root)
	var source_meshes: Array[MeshInstance3D] = [
		head_mesh, torso_mesh, left_arm_mesh, right_arm_mesh, left_leg_mesh, right_leg_mesh
	]
	if _avatar_attachment_root != null:
		_collect_death_fragment_meshes(_avatar_attachment_root, source_meshes)
	for source in source_meshes:
		if source == null or source.mesh == null:
			continue
		var fragment := RigidBody3D.new()
		fragment.name = "%sFragment" % source.name
		fragment.mass = 0.65
		fragment.collision_layer = 0
		fragment.collision_mask = _get_world_collision_mask()
		_death_fragment_root.add_child(fragment)
		fragment.global_transform = source.global_transform
		var visual := MeshInstance3D.new()
		visual.mesh = source.mesh
		visual.material_override = source.material_override
		fragment.add_child(visual)
		var bounds := source.mesh.get_aabb()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(bounds.size.x, 0.18), maxf(bounds.size.y, 0.18), maxf(bounds.size.z, 0.18))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		fragment.add_child(collision)
		var outward := source.global_position - (global_position + Vector3.UP * 2.5)
		if outward.length_squared() <= 0.01:
			outward = Vector3(randf_range(-1.0, 1.0), 0.15, randf_range(-1.0, 1.0))
		fragment.linear_velocity = outward.normalized() * randf_range(0.7, 1.8) + Vector3.UP * randf_range(0.8, 1.8)
		fragment.angular_velocity = Vector3(randf_range(-1.8, 1.8), randf_range(-1.8, 1.8), randf_range(-1.8, 1.8))
	_cleanup_death_fragments_later(_death_fragment_root)

func _collect_death_fragment_meshes(root: Node, output: Array[MeshInstance3D]) -> void:
	for child in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			output.append(child as MeshInstance3D)
		_collect_death_fragment_meshes(child, output)

func _cleanup_death_fragments_later(fragment_root: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(DEATH_FRAGMENT_LIFETIME_SECONDS).timeout
	if is_instance_valid(fragment_root):
		fragment_root.queue_free()

func _restore_after_respawn() -> void:
	_death_visual_active = false
	if visuals != null:
		visuals.visible = true
	if _death_fragment_root != null and is_instance_valid(_death_fragment_root):
		_death_fragment_root.queue_free()
	_death_fragment_root = null
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_configure_collision_profile()
	_set_character_state(CharacterState.IDLE)

func _get_safe_reposition_target(target_position: Vector3) -> Vector3:
	var adjusted_target: Vector3 = _resolve_safe_respawn_base(target_position)
	adjusted_target.y += _world_units(SAFE_REPOSITION_LIFT)
	return adjusted_target

func _resolve_safe_respawn_base(target_position: Vector3) -> Vector3:
	var candidate: Vector3 = target_position
	if not _is_vector3_finite(candidate) or candidate.y < MIN_SAFE_RESPAWN_Y:
		if _has_safe_position and _is_vector3_finite(_last_safe_position) and _last_safe_position.y > MIN_SAFE_RESPAWN_Y:
			candidate = _last_safe_position
		elif not spawn_points.is_empty() and _is_vector3_finite(spawn_points[0]):
			candidate = spawn_points[0]
		elif _is_vector3_finite(respawn_position) and respawn_position.y > MIN_SAFE_RESPAWN_Y:
			candidate = respawn_position
		else:
			candidate = Vector3(0.0, FALLBACK_RESPAWN_HEIGHT, 0.0)
	candidate.y = maxf(candidate.y, MIN_SAFE_RESPAWN_Y)
	return candidate

func _is_vector3_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

# This function reports whether gameplay should be temporarily frozen during host migration or reconnects.
func _is_network_gameplay_frozen() -> bool:
	if _is_studio_playtest_instance():
		return false
	return bool(GameState.network_gameplay_frozen)

func _emit_studio_playtest_touch_events() -> void:
	if not _is_studio_playtest_instance() or LuaScriptEngine == null or not LuaScriptEngine.has_method("notify_part_touched"):
		return
	var current_contacts: Dictionary = {}
	set_meta("bobux_touch_collision_count", get_slide_collision_count())
	var hit_proxy: Node = get_node_or_null("HumanoidRootPart")
	if hit_proxy == null:
		hit_proxy = self
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var collider_variant := collision.get_collider()
		if not (collider_variant is Node):
			continue
		var collider := collider_variant as Node
		var touched_part := collider
		if collider.name in ["CollisionBody", "SelectionBody"] and collider.get_parent() != null:
			touched_part = collider.get_parent()
		if not touched_part.is_in_group("studio_parts"):
			continue
		var touched_id := touched_part.get_instance_id()
		current_contacts[touched_id] = true
		if not _studio_touching_parts.has(touched_id):
			LuaScriptEngine.notify_part_touched(touched_part, hit_proxy)
			set_meta("bobux_touch_notifications", int(get_meta("bobux_touch_notifications", 0)) + 1)
	_studio_touching_parts = current_contacts

func _play_death_sound() -> void:
	if _death_audio_player == null or _death_audio_player.stream == null:
		return
	_death_audio_player.stop()
	_death_audio_player.play()

func _get_next_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		return respawn_position
	if spawn_points.size() == 1:
		_last_spawn_index = 0
		return spawn_points[0]
	var next_index := _spawn_rng.randi_range(0, spawn_points.size() - 1)
	if next_index == _last_spawn_index:
		next_index = (next_index + 1 + _spawn_rng.randi_range(0, spawn_points.size() - 2)) % spawn_points.size()
	_last_spawn_index = next_index
	return spawn_points[next_index]

func _load_custom_character() -> void:
	if not _cached_custom_character_limbs.is_empty():
		_apply_cached_custom_character_limbs(_cached_custom_character_limbs)
		return
	if _custom_character_cache_attempted:
		return
	_custom_character_cache_attempted = true
	if not ResourceLoader.exists("res://files/RolandStudioNoHatsRBLX.obj"): return
	var obj_mesh: ArrayMesh = load("res://files/RolandStudioNoHatsRBLX.obj") as ArrayMesh
	if obj_mesh == null: return
	
	var surface_count: int = obj_mesh.get_surface_count()
	if surface_count < 6: return
	
	var limbs: Array = []
	for s in range(surface_count):
		var arrays = obj_mesh.surface_get_arrays(s)
		if arrays.size() == 0: continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() == 0: continue
		
		# Compute AABB for this surface
		var aabb: AABB = AABB(verts[0], Vector3.ZERO)
		for v in verts:
			aabb = aabb.expand(v)
		var center: Vector3 = aabb.get_center()
		
		# Recenter vertices around their own origin
		var new_verts: PackedVector3Array = PackedVector3Array()
		new_verts.resize(verts.size())
		for i in range(verts.size()):
			new_verts[i] = verts[i] - center
		arrays[Mesh.ARRAY_VERTEX] = new_verts
		
		var new_mesh: ArrayMesh = ArrayMesh.new()
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		limbs.append({"mesh": new_mesh, "center": center, "size": aabb.size})
	
	if limbs.size() < 6: return
	
	# Sort by Y descending: Head is highest, then arms/torso, then legs
	limbs.sort_custom(func(a, b): return a.center.y > b.center.y)
	
	head_mesh.mesh = limbs[0].mesh
	
	# Middle 3 items (indices 1,2,3) are torso + two arms
	var middle: Array = [limbs[1], limbs[2], limbs[3]]
	middle.sort_custom(func(a, b): return a.center.x < b.center.x)
	# Smallest X = left side of model
	left_arm_mesh.mesh = middle[0].mesh
	torso_mesh.mesh = middle[1].mesh
	right_arm_mesh.mesh = middle[2].mesh
	
	# Bottom 2 items (indices 4,5) are legs
	var legs: Array = [limbs[4], limbs[5]]
	legs.sort_custom(func(a, b): return a.center.x < b.center.x)
	left_leg_mesh.mesh = legs[0].mesh
	right_leg_mesh.mesh = legs[1].mesh
	_cached_custom_character_limbs = [
		head_mesh.mesh,
		torso_mesh.mesh,
		left_arm_mesh.mesh,
		right_arm_mesh.mesh,
		left_leg_mesh.mesh,
		right_leg_mesh.mesh
	]

func _apply_cached_custom_character_limbs(limb_meshes: Array) -> void:
	if limb_meshes.size() < 6:
		return
	head_mesh.mesh = limb_meshes[0] as Mesh
	torso_mesh.mesh = limb_meshes[1] as Mesh
	left_arm_mesh.mesh = limb_meshes[2] as Mesh
	right_arm_mesh.mesh = limb_meshes[3] as Mesh
	left_leg_mesh.mesh = limb_meshes[4] as Mesh
	right_leg_mesh.mesh = limb_meshes[5] as Mesh

func _fit_collision_shapes_to_visuals() -> void:
	_fit_primary_collision_shape()
	_fit_convex_collision_to_mesh(collision_left_leg, left_leg_mesh)
	_fit_convex_collision_to_mesh(collision_right_leg, right_leg_mesh)
	_fit_convex_collision_to_mesh(collision_torso, torso_mesh)
	_fit_convex_collision_to_mesh(collision_head, head_mesh)
	_fit_convex_collision_to_mesh(collision_left_arm, left_arm_mesh)
	_fit_convex_collision_to_mesh(collision_right_arm, right_arm_mesh)

func _fit_convex_collision_to_mesh(collision_shape: CollisionShape3D, mesh_instance: MeshInstance3D) -> void:
	if collision_shape == null or mesh_instance == null or mesh_instance.mesh == null:
		return
	var convex_shape: ConvexPolygonShape3D = mesh_instance.mesh.create_convex_shape(true, false)
	if convex_shape != null and not convex_shape.points.is_empty():
		collision_shape.shape = convex_shape
	_sync_collision_shape_to_mesh(collision_shape, mesh_instance)

func _sync_body_collision_transforms() -> void:
	_sync_collision_shape_to_mesh(collision_left_leg, left_leg_mesh)
	_sync_collision_shape_to_mesh(collision_right_leg, right_leg_mesh)
	_sync_collision_shape_to_mesh(collision_torso, torso_mesh)
	_sync_collision_shape_to_mesh(collision_head, head_mesh)
	_sync_collision_shape_to_mesh(collision_left_arm, left_arm_mesh)
	_sync_collision_shape_to_mesh(collision_right_arm, right_arm_mesh)

func _sync_collision_shape_to_mesh(collision_shape: CollisionShape3D, mesh_instance: MeshInstance3D) -> void:
	if collision_shape == null or mesh_instance == null or not is_inside_tree():
		return
	collision_shape.transform = global_transform.affine_inverse() * mesh_instance.global_transform

func _fit_primary_collision_shape() -> void:
	if collision_body == null:
		return
	var capsule := collision_body.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.radius = PRIMARY_CAPSULE_RADIUS
	capsule.height = PRIMARY_CAPSULE_HEIGHT
	collision_body.position = Vector3(0.0, PRIMARY_CAPSULE_CENTER_Y, 0.0)

func _disable_arm_collision_shapes() -> void:
	if collision_left_arm != null:
		collision_left_arm.disabled = true
	if collision_right_arm != null:
		collision_right_arm.disabled = true

func _fit_box_collision_from_bounds(collision_shape: CollisionShape3D, bounds: AABB, padding: Vector3, min_size: Vector3, max_size: Vector3, lock_x: bool = false, lock_z: bool = false) -> void:
	if collision_shape == null or bounds.size == Vector3.ZERO:
		return
	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape == null:
		return
	var expanded_size: Vector3 = bounds.size + padding
	if collision_shape == collision_torso:
		expanded_size.x *= 0.76
		expanded_size.z *= 0.42
	elif collision_shape == collision_left_arm or collision_shape == collision_right_arm:
		expanded_size.x *= 0.9
		expanded_size.z *= 0.54
	if min_size != Vector3.ZERO:
		expanded_size.x = maxf(expanded_size.x, min_size.x)
		expanded_size.y = maxf(expanded_size.y, min_size.y)
		expanded_size.z = maxf(expanded_size.z, min_size.z)
	if max_size != Vector3.ZERO:
		expanded_size.x = minf(expanded_size.x, max_size.x)
		expanded_size.y = minf(expanded_size.y, max_size.y)
		expanded_size.z = minf(expanded_size.z, max_size.z)
	box_shape.size = Vector3(
		maxf(expanded_size.x, 0.05),
		maxf(expanded_size.y, 0.05),
		maxf(expanded_size.z, 0.05)
	)
	var center: Vector3 = bounds.position + (bounds.size * 0.5)
	if lock_x:
		center.x = collision_shape.position.x
	if lock_z:
		center.z = collision_shape.position.z
	collision_shape.position = center

func _configure_collision_profile() -> void:
	if _is_preview_instance():
		_set_collision_enabled(false)
		return
	# The physical body follows each visible limb. The capsule remains available
	# for broad query helpers, but it is not enabled as an overlapping collider.
	# queries both the world and player layer; interpolated remote avatars are
	# blocker-only (layer 2, mask 0), so they can be bumped into without running
	# their own collision response against stale client-side world positions.
	_set_collision_enabled(true)
	var controls_physics := _is_dedicated_server_runtime() or _is_local_authority_safe()
	collision_layer = PLAYER_COLLISION_LAYER
	if controls_physics:
		var world_mask := _get_world_collision_mask()
		collision_mask = world_mask | PLAYER_COLLISION_LAYER
	else:
		collision_mask = 0

func _set_collision_enabled(enabled: bool) -> void:
	collision_layer = PLAYER_COLLISION_LAYER if enabled else 0
	collision_mask = _get_player_and_world_collision_mask() if enabled else 0
	if collision_body != null:
		collision_body.disabled = true
	for collision_shape in [collision_left_leg, collision_right_leg, collision_torso, collision_head, collision_left_arm, collision_right_arm]:
		if collision_shape != null:
			collision_shape.disabled = not enabled

func _combine_mesh_bounds(mesh_nodes: Array) -> AABB:
	var merged_bounds := AABB()
	var has_bounds: bool = false
	for mesh_node in mesh_nodes:
		if not (mesh_node is MeshInstance3D):
			continue
		var mesh_bounds: AABB = _get_mesh_bounds_in_body_space(mesh_node as MeshInstance3D)
		if mesh_bounds.size == Vector3.ZERO:
			continue
		if not has_bounds:
			merged_bounds = mesh_bounds
			has_bounds = true
			continue
		for corner in _get_aabb_corners(mesh_bounds):
			merged_bounds = merged_bounds.expand(corner)
	return merged_bounds if has_bounds else AABB()

func _get_mesh_bounds_in_body_space(mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var bounds_points: Array[Vector3] = []
	for corner in _get_aabb_corners(mesh_instance.mesh.get_aabb()):
		bounds_points.append(to_local(mesh_instance.to_global(corner)))
	if bounds_points.is_empty():
		return AABB()
	var mesh_bounds := AABB(bounds_points[0], Vector3.ZERO)
	for i in range(1, bounds_points.size()):
		mesh_bounds = mesh_bounds.expand(bounds_points[i])
	return mesh_bounds

func _fit_ui_preview_visuals() -> void:
	var bounds := _get_visuals_bounds()
	if bounds.size == Vector3.ZERO:
		return

	var scale_factor := 1.0
	if bounds.size.y > 0.0:
		scale_factor = minf(scale_factor, UI_PREVIEW_TARGET_HEIGHT / bounds.size.y)
	if bounds.size.x > 0.0:
		scale_factor = minf(scale_factor, UI_PREVIEW_TARGET_WIDTH / bounds.size.x)
	if bounds.size.z > 0.0:
		scale_factor = minf(scale_factor, UI_PREVIEW_TARGET_DEPTH / bounds.size.z)

	visuals.scale = Vector3.ONE * scale_factor
	var bounds_center := bounds.position + (bounds.size * 0.5)
	visuals.position = Vector3(
		-bounds_center.x * scale_factor,
		UI_PREVIEW_CENTER_HEIGHT - (bounds_center.y * scale_factor),
		-bounds_center.z * scale_factor
	)

func _get_visuals_bounds() -> AABB:
	var points: Array[Vector3] = []
	_collect_mesh_bounds_points(visuals, points)
	if points.is_empty():
		return AABB()

	var bounds := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		bounds = bounds.expand(points[i])
	return bounds

func _collect_mesh_bounds_points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb := mesh_instance.mesh.get_aabb()
			for corner in _get_aabb_corners(mesh_aabb):
				points.append(visuals.to_local(mesh_instance.to_global(corner)))

	for child in node.get_children():
		_collect_mesh_bounds_points(child, points)

func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var min_point := aabb.position
	var max_point := aabb.position + aabb.size
	return [
		Vector3(min_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, min_point.z),
		Vector3(min_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, min_point.z),
		Vector3(min_point.x, min_point.y, max_point.z),
		Vector3(max_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, max_point.z),
		Vector3(max_point.x, max_point.y, max_point.z),
	]

func _update_first_person_mode() -> void:
	var new_fp: bool = _camera_desired_spring_length < 0.5
	if new_fp != is_first_person:
		is_first_person = new_fp
		visuals.visible = not is_first_person
		if is_first_person:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Auto-capture in FPV
		else:
			if not is_shift_lock:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_local_camera_rig_render_phase(0.0)

# This function restores the expected cursor/camera control mode after host migration.
# We keep the same behavior as normal gameplay: visible cursor by default, captured only in FP/shift-lock.
func restore_mouse_mode_after_network_handover() -> void:
	if _is_preview_instance() or not _is_local_authority_safe():
		return
	refresh_camera_authority_mode()
	if is_first_person or is_shift_lock:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if crosshair:
			crosshair.visible = is_shift_lock
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if crosshair:
		crosshair.visible = false

func _configure_state_synchronizer() -> void:
	_configure_state_synchronizer_for(state_synchronizer)
	_configure_camera_visual_stability()
	_configure_collision_profile()

func refresh_camera_authority_mode() -> void:
	_configure_camera_visual_stability()
	if player_camera != null and not _is_preview_instance():
		player_camera.current = _is_local_authority_safe()
	_reset_local_camera_anchor(global_position)
	_update_local_camera_rig_render_phase(0.0)
	_reset_camera_rig_interpolation()

func assign_network_room(room_id: String) -> void:
	network_room_id = room_id.strip_edges()
	if state_synchronizer != null:
		state_synchronizer.update_visibility()

func _on_room_summaries_updated(_summaries: Array) -> void:
	if state_synchronizer != null:
		state_synchronizer.update_visibility()

func _is_peer_visible_for_room(peer_id: int) -> bool:
	# AUDIT FIX CRITICAL-1: An empty room_id now hides the player from ALL peers
	# instead of making them visible to everyone. This closes the cross-room
	# data leakage vector during the race window between peer_connected and
	# room join confirmation.
	if network_room_id.is_empty():
		return false
	if NetworkManager == null or not NetworkManager.has_method("get_peer_room_id"):
		return false
	var peer_room: String = NetworkManager.get_peer_room_id(peer_id)
	if peer_room.is_empty():
		return false
	return peer_room == network_room_id

func _should_filter_visibility_by_room() -> bool:
	return multiplayer != null and multiplayer.is_server()

func _use_conservative_websocket_replication() -> bool:
	if NetworkManager == null or not NetworkManager.has_method("get_active_transport_label"):
		return false
	var transport_label: String = str(NetworkManager.get_active_transport_label()).to_lower()
	return transport_label.contains("websocket")

func _configure_state_synchronizer_for(synchronizer: MultiplayerSynchronizer) -> void:
	if synchronizer == null:
		return
	var conservative_websocket_replication: bool = _use_conservative_websocket_replication()
	var transform_mode: int = SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE if conservative_websocket_replication else SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	var visual_rotation_mode: int = SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE if conservative_websocket_replication else SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()
	replication_config.add_property(^":network_position")
	replication_config.property_set_spawn(^":network_position", true)
	replication_config.property_set_replication_mode(^":network_position", transform_mode)
	replication_config.add_property(^":network_rotation")
	replication_config.property_set_spawn(^":network_rotation", true)
	replication_config.property_set_replication_mode(^":network_rotation", transform_mode)
	replication_config.add_property(^":network_velocity")
	replication_config.property_set_spawn(^":network_velocity", true)
	replication_config.property_set_replication_mode(^":network_velocity", transform_mode)
	replication_config.add_property(^":network_visuals_y")
	replication_config.property_set_spawn(^":network_visuals_y", true)
	replication_config.property_set_replication_mode(^":network_visuals_y", visual_rotation_mode)
	replication_config.add_property(^":network_grounded")
	replication_config.property_set_spawn(^":network_grounded", true)
	replication_config.property_set_replication_mode(^":network_grounded", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	replication_config.add_property(^":network_character_state")
	replication_config.property_set_spawn(^":network_character_state", true)
	replication_config.property_set_replication_mode(^":network_character_state", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	replication_config.add_property(^":current_health")
	replication_config.property_set_spawn(^":current_health", true)
	replication_config.property_set_replication_mode(^":current_health", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	if not conservative_websocket_replication:
		for prop in [":animation_cycle", ":animation_weight"]:
			replication_config.add_property(NodePath(prop))
			replication_config.property_set_spawn(NodePath(prop), true)
			replication_config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		
	replication_config.add_property(^":animation_airborne")
	replication_config.property_set_spawn(^":animation_airborne", true)
	replication_config.property_set_replication_mode(^":animation_airborne", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	replication_config.add_property(^":display_name")
	replication_config.property_set_spawn(^":display_name", true)
	replication_config.property_set_replication_mode(^":display_name", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	for prop in [":head_color", ":torso_color", ":left_arm_color", ":right_arm_color", ":left_leg_color", ":right_leg_color"]:
		replication_config.add_property(NodePath(prop))
		replication_config.property_set_spawn(NodePath(prop), true)
		replication_config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	for prop in [":face_texture_path", ":chest_badge_texture_path", ":shirt_texture_path", ":pants_texture_path"]:
		replication_config.add_property(NodePath(prop))
		replication_config.property_set_spawn(NodePath(prop), true)
		replication_config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	synchronizer.root_path = NodePath("..")
	if conservative_websocket_replication:
		var websocket_interval: float = 1.0 / WEBSOCKET_DELTA_SYNC_HZ
		synchronizer.delta_interval = websocket_interval
		synchronizer.replication_interval = websocket_interval
	else:
		synchronizer.delta_interval = 0.0
		synchronizer.replication_interval = 1.0 / DEFAULT_ALWAYS_SYNC_HZ
	synchronizer.replication_config = replication_config
	var filter_visibility_by_room: bool = _should_filter_visibility_by_room()
	synchronizer.public_visibility = not filter_visibility_by_room
	if filter_visibility_by_room:
		if not _room_visibility_filter_registered:
			synchronizer.add_visibility_filter(_is_peer_visible_for_room)
			_room_visibility_filter_registered = true
	else:
		if _room_visibility_filter_registered:
			synchronizer.remove_visibility_filter(_is_peer_visible_for_room)
			_room_visibility_filter_registered = false
	synchronizer.update_visibility()

func _ensure_chat_bubble_nodes() -> void:
	if _chat_bubble_back == null:
		var existing_back := visuals.get_node_or_null("ChatBubbleBack") as MeshInstance3D
		if existing_back:
			_chat_bubble_back = existing_back
		else:
			_chat_bubble_back = MeshInstance3D.new()
			_chat_bubble_back.name = "ChatBubbleBack"
			_chat_bubble_back.mesh = _make_chat_bubble_mesh(Vector2(2.4, 0.58))
			_chat_bubble_back.position = Vector3(0.0, 7.0, -0.015)
			var back_mat := StandardMaterial3D.new()
			back_mat.albedo_color = Color(1, 1, 1, 0.94)
			back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			back_mat.no_depth_test = false
			back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_chat_bubble_back.set_surface_override_material(0, back_mat)
			_chat_bubble_back.visible = false
			visuals.add_child(_chat_bubble_back)
	if _chat_bubble_back != null:
		var back_mat := _chat_bubble_back.get_surface_override_material(0) as StandardMaterial3D
		if back_mat == null:
			back_mat = StandardMaterial3D.new()
			_chat_bubble_back.set_surface_override_material(0, back_mat)
		back_mat.albedo_color = Color(1, 1, 1, 0.97)
		back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		back_mat.no_depth_test = false
		back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		back_mat.disable_receive_shadows = true
		back_mat.render_priority = 8
	if _chat_bubble_label == null:
		var existing_label := visuals.get_node_or_null("ChatBubble") as Label3D
		if existing_label:
			_chat_bubble_label = existing_label
		else:
			_chat_bubble_label = Label3D.new()
			_chat_bubble_label.name = "ChatBubble"
			_chat_bubble_label.font_size = 66
			_chat_bubble_label.outline_size = 0
			_chat_bubble_label.modulate = Color(0.02, 0.02, 0.02, 1)
			_chat_bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_chat_bubble_label.pixel_size = 0.0098
			_chat_bubble_label.position = Vector3(0.0, 7.0, 0.0)
			_chat_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_chat_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_chat_bubble_label.set("no_depth_test", false)
			_chat_bubble_label.set("shaded", false)
			_chat_bubble_label.visible = false
			visuals.add_child(_chat_bubble_label)
	if _chat_bubble_label != null:
		_chat_bubble_label.font_size = 66
		_chat_bubble_label.outline_size = 0
		_chat_bubble_label.modulate = Color(0.02, 0.02, 0.02, 1)
		_chat_bubble_label.outline_modulate = Color(1, 1, 1, 1)
		_chat_bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_chat_bubble_label.pixel_size = 0.0098
		_chat_bubble_label.position = Vector3(0.0, 7.0, 0.012)
		_chat_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chat_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_chat_bubble_label.set("no_depth_test", false)
		_chat_bubble_label.set("shaded", false)
		_chat_bubble_label.set("render_priority", 9)
		_chat_bubble_label.set("fixed_size", false)

	if _chat_bubble_timer == null:
		var existing_timer := get_node_or_null("ChatBubbleTimer") as Timer
		if existing_timer:
			_chat_bubble_timer = existing_timer
		else:
			_chat_bubble_timer = Timer.new()
			_chat_bubble_timer.name = "ChatBubbleTimer"
			_chat_bubble_timer.one_shot = true
			add_child(_chat_bubble_timer)
		if not _chat_bubble_timer.timeout.is_connected(_hide_chat_bubble):
			_chat_bubble_timer.timeout.connect(_hide_chat_bubble)

func _hide_chat_bubble() -> void:
	if _chat_bubble_back:
		_chat_bubble_back.visible = false
	if _chat_bubble_label:
		_chat_bubble_label.visible = false
		_chat_bubble_label.text = ""

func _make_chat_bubble_mesh(size: Vector2) -> ArrayMesh:
	var width: float = maxf(size.x, 0.6)
	var height: float = maxf(size.y, 0.32)
	var radius: float = minf(0.22, minf(width, height) * 0.45)
	var half_w: float = width * 0.5
	var half_h: float = height * 0.5
	var segments: int = 5
	var points: PackedVector2Array = PackedVector2Array()
	_append_rounded_rect_arc(points, Vector2(half_w - radius, half_h - radius), radius, 0.0, PI * 0.5, segments)
	_append_rounded_rect_arc(points, Vector2(-half_w + radius, half_h - radius), radius, PI * 0.5, PI, segments)
	_append_rounded_rect_arc(points, Vector2(-half_w + radius, -half_h + radius), radius, PI, PI * 1.5, segments)
	_append_rounded_rect_arc(points, Vector2(half_w - radius, -half_h + radius), radius, PI * 1.5, TAU, segments)

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var center := Vector3.ZERO
	for i in range(points.size()):
		var next_i: int = (i + 1) % points.size()
		vertices.append(center)
		vertices.append(Vector3(points[i].x, points[i].y, 0.0))
		vertices.append(Vector3(points[next_i].x, points[next_i].y, 0.0))
		normals.append(Vector3.FORWARD)
		normals.append(Vector3.FORWARD)
		normals.append(Vector3.FORWARD)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _append_rounded_rect_arc(points: PackedVector2Array, center: Vector2, radius: float, start_angle: float, end_angle: float, segments: int) -> void:
	for i in range(segments + 1):
		var t: float = float(i) / float(maxi(segments, 1))
		var angle: float = lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

func _wrap_chat_bubble_text(message: String, max_line_chars: int = 18, max_lines: int = 3) -> PackedStringArray:
	var words: PackedStringArray = message.strip_edges().split(" ", false)
	var lines: PackedStringArray = PackedStringArray()
	var current_line: String = ""
	for word in words:
		var clean_word: String = word.strip_edges()
		if clean_word.is_empty():
			continue
		while clean_word.length() > max_line_chars:
			var chunk: String = clean_word.substr(0, max_line_chars)
			clean_word = clean_word.substr(max_line_chars)
			if not current_line.is_empty():
				lines.append(current_line)
				current_line = ""
			lines.append(chunk)
			if lines.size() >= max_lines:
				break
		if lines.size() >= max_lines:
			break
		var candidate: String = clean_word if current_line.is_empty() else "%s %s" % [current_line, clean_word]
		if candidate.length() <= max_line_chars:
			current_line = candidate
		else:
			if not current_line.is_empty():
				lines.append(current_line)
			current_line = clean_word
			if lines.size() >= max_lines:
				break
	if lines.size() < max_lines and not current_line.is_empty():
		lines.append(current_line)
	if lines.is_empty():
		lines.append(message.left(max_line_chars))
	if lines.size() > max_lines:
		lines.resize(max_lines)
	return lines

func _longest_chat_line_length(lines: PackedStringArray) -> int:
	var longest: int = 1
	for line in lines:
		longest = maxi(longest, line.length())
	return longest

func _join_chat_lines(lines: PackedStringArray) -> String:
	var result: String = ""
	for i in range(lines.size()):
		if i > 0:
			result += "\n"
		result += lines[i]
	return result

func _make_flat_material(albedo_color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo_color
	material.roughness = 1.0
	# FIX Issue-3c: Explicit shading mode prevents black rendering on meshes
	# with incomplete or missing normals.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

func _load_audio_stream_from_path(path: String) -> AudioStream:
	return AudioFileLoader.load_stream(path)

func _resolve_existing_file_path(path: String) -> String:
	if path.is_empty():
		return ""
	var global_path := ProjectSettings.globalize_path(path)
	var candidate_paths: Array[String] = []
	if global_path != path:
		candidate_paths.append(global_path)
	candidate_paths.append(path)
	for candidate in candidate_paths:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

func _configure_physics_motion() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	# A small recovery margin keeps the capsule stable around cylinders and
	# spheres; the old 0.1 margin could repeatedly push it between adjacent
	# curved surfaces and feel like the character was stuck.
	safe_margin = maxf(_world_units(0.035), 0.006)
	floor_snap_length = _world_units(FLOOR_SNAP_LENGTH)
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_block_on_wall = false
	floor_max_angle = deg_to_rad(70.0)
	wall_min_slide_angle = deg_to_rad(14.0)
	slide_on_ceiling = true
	max_slides = 14

func _configure_camera_visual_stability() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	if visuals != null:
		visuals.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if camera_pivot != null:
		camera_pivot.top_level = false
		camera_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_update_local_camera_rig_render_phase(0.0)
	if spring_arm != null:
		spring_arm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		spring_arm.collision_mask = 0
	if player_camera != null:
		player_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		player_camera.near = 0.14
		player_camera.far = 420.0

func _reset_all_physics_interpolation() -> void:
	_reset_local_camera_anchor(global_position)
	reset_physics_interpolation()
	_reset_camera_rig_interpolation()
	if visuals != null:
		visuals.reset_physics_interpolation()

func _reset_camera_rig_interpolation() -> void:
	if camera_pivot != null:
		camera_pivot.reset_physics_interpolation()
	if spring_arm != null:
		spring_arm.reset_physics_interpolation()
	if player_camera != null and Engine.is_in_physics_frame():
		player_camera.reset_physics_interpolation()

func _world_units(value: float) -> float:
	return value * maxf(world_stud_scale, 0.0001)

func _get_world_collision_mask() -> int:
	if _is_studio_playtest_instance():
		return maxi(1, int(get_meta("bobux_world_collision_mask", WORLD_COLLISION_MASK)))
	return WORLD_COLLISION_MASK

func _get_player_and_world_collision_mask() -> int:
	return _get_world_collision_mask() | PLAYER_COLLISION_LAYER

func _get_current_gravity() -> float:
	if velocity.y > 0.0:
		var mobile_runtime: Node = _get_mobile_runtime()
		var mobile_jump_held: bool = mobile_runtime != null and mobile_runtime.has_method("is_jump_pressed") and bool(mobile_runtime.call("is_jump_pressed"))
		return _world_units(JUMP_GRAVITY if (Input.is_action_pressed("jump") or mobile_jump_held) else JUMP_RELEASE_GRAVITY)
	return _world_units(FALL_GRAVITY)

# --- Chat Bubbles ---
# AUDIT FIX VULN-2: Chat bubbles are now server-relayed. Clients call
# request_chat_bubble() which the server validates (rate-limit + length cap)
# before broadcasting via the authoritative _show_chat_bubble_authoritative().

func request_chat_bubble_local(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if clean_text.length() > CHAT_BUBBLE_MAX_LENGTH:
		clean_text = clean_text.left(CHAT_BUBBLE_MAX_LENGTH)
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_chat_bubble_msec < CHAT_BUBBLE_RATE_LIMIT_MS:
		return
	_last_chat_bubble_msec = now_msec
	var scene_root: Node = get_tree().current_scene if get_tree() != null else null
	if scene_root != null and scene_root.has_method("_relay_chat_bubble_to_server"):
		scene_root.call("_relay_chat_bubble_to_server", get_multiplayer_authority(), clean_text)
	else:
		_display_chat_bubble(clean_text)

@rpc("any_peer", "call_local", "reliable")
func show_chat_bubble(text: String) -> void:
	# Security note: This RPC must remain "any_peer" because the dedicated
	# server (peer 1) calls it on player nodes whose authority is the owning
	# peer. Content validation and rate-limiting are enforced server-side in
	# _process_chat_bubble_on_server() before this RPC is ever invoked.
	_display_chat_bubble(text)

func _display_chat_bubble(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if clean_text.length() > CHAT_BUBBLE_MAX_LENGTH:
		clean_text = clean_text.left(CHAT_BUBBLE_MAX_LENGTH)
	_ensure_chat_bubble_nodes()
	var wrapped_lines: PackedStringArray = _wrap_chat_bubble_text(clean_text)
	var display_text: String = _join_chat_lines(wrapped_lines)
	_chat_bubble_label.text = display_text
	if _chat_bubble_back != null:
		var longest_line: int = _longest_chat_line_length(wrapped_lines)
		var line_count: int = wrapped_lines.size()
		var text_width := clampf(float(longest_line) * 0.34 + 1.34, 2.15, 6.6)
		var text_height := clampf(1.04 + float(line_count - 1) * 0.68, 1.04, 2.42)
		_chat_bubble_back.mesh = _make_chat_bubble_mesh(Vector2(text_width, text_height))
		_chat_bubble_back.visible = true
	_chat_bubble_label.visible = true
	_chat_bubble_timer.start(9.0)
