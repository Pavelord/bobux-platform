extends Node # This makes the script control the runtime game scene that owns the world, networking, and small in-game HUD.

const MAX_CLIENTS: int = 10
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const CHAOS_CAR_SCRIPT: Script = preload("res://scripts/vehicles/chaos_car.gd")
const MASTER_CAR_SPAWNER_SCRIPT: Script = preload("res://scripts/vehicles/master_car_spawner.gd")
const RbxlWedgeMeshBuilder = preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")
const RobloxGuiRuntime = preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")
const RobloxInventoryControllerClass = preload("res://addons/roblox_runtime/roblox_inventory_controller.gd")
const RobloxTerrainEditorClass = preload("res://addons/roblox_studio/roblox_terrain_editor.gd")
const RobloxDataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")
const RobloxSkyMaterial = preload("res://addons/rbxl_importer/roblox_sky_material.gd")
const RobloxMeshJsonLoader = preload("res://addons/rbxl_importer/roblox_mesh_json_loader.gd")
const RbxlMaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const AudioFileLoader = preload("res://addons/roblox_runtime/audio_file_loader.gd")
const LOBBY_SCENE_PATH: String = "res://scenes/lobby/lobby.tscn"
const SPAWN_DECAL_PATH: String = "res://images/spawn.png"
const CHECKPOINT_TRIGGER_EXTRA_HEIGHT: float = 1.6
const DAMAGE_TRIGGER_EXTRA_HEIGHT: float = 1.6
const TELEPORT_TRIGGER_HEIGHT: float = 2.8
const TELEPORT_EXIT_HEIGHT: float = 2.5
const TELEPORT_COOLDOWN_MSEC: int = 650
const CHECKPOINT_RESPAWN_HEIGHT: float = 2.2
const PLAYER_TRIGGER_COLLISION_MASK: int = 1 | 2
const DEFAULT_PLAYER_MOVE_SPEED: float = 16.0
const DEFAULT_PLAYER_SPRINT_MULTIPLIER: float = 1.25
const DEFAULT_PLAYER_JUMP_VELOCITY: float = 53.15
const DEFAULT_MODE_MUSIC_VOLUME: float = 0.65
const NETWORK_SYNC_RATE_HZ: float = 60.0
const HOST_KEEPALIVE_INTERVAL: float = 1.0
const HOST_KEEPALIVE_TIMEOUT_SECONDS: float = 12.0
const SERVER_PUSH_KEEPALIVE_INTERVAL_SECONDS: float = 2.0
const VERBOSE_KEEPALIVE_LOGS: bool = false
const HANDOVER_READY_TIMEOUT_SECONDS: float = 2.5
const DUPLICATE_PLAYER_GUARD_INTERVAL_MSEC: int = 250
const LEADERBOARD_REFRESH_INTERVAL_MSEC: int = 220
const FRIEND_REQUEST_POLL_INTERVAL_MSEC: int = 3000
const FRIEND_STATUS_REFRESH_INTERVAL_MSEC: int = 15000
const SNAPSHOT_SPAWN_WAIT_FRAMES: int = 45
const CHARACTER_SPAWN_TIMEOUT_MSEC: int = 30000
const MAX_REPLICATED_SPAWN_POINTS: int = 64
const NETWORK_LOADING_TWEEN_SECONDS: float = 0.22
var _account_badge_cache: Dictionary = {}
var _account_badge_requests: Dictionary = {}

const BOBUX_LOADING_LOGO_PATH: String = "res://assets/branding/bobux_logo_ui.png"
const BOBUX_LOADING_SPINNER_PATH: String = "res://assets/branding/bobux_app_icon.png"
const DUPLICATE_SESSION_ERROR_MESSAGE: String = "Этот аккаунт уже находится в игре."
const ROOM_RUNTIME_SPACING: float = 5000.0
const ROOM_RUNTIME_GRID_COLUMNS: int = 128
const ROOM_SPAWN_GROUP_PREFIX: String = "spawn_locations_room_"
const RBXL_RUNTIME_OBJECT_GROUP: String = "runtime_imported_objects"
const VEHICLE_SPAWN_COOLDOWN_MSEC: int = 1400
const VEHICLE_TRIGGER_HEIGHT: float = 3.2
const VEHICLE_SPAWNER_POLL_INTERVAL_MSEC: int = 220
const VEHICLE_SPAWN_ZONE_RADIUS: float = 8.5
const DESTRUCTIBLE_DEBRIS_LIFETIME: float = 8.0
const MAP_LOAD_BLOCKS_PER_FRAME: int = 36
const MAP_LOAD_RUNTIME_OBJECTS_PER_FRAME: int = 96
const MAP_LOAD_MANIFEST_NODES_PER_FRAME: int = 192
const MAP_LOAD_MANIFEST_SCRIPTS_PER_FRAME: int = 32
const MAP_LOAD_GUI_CONTROLS_PER_FRAME: int = 96
const MAP_LOAD_THREADED_POLL_INTERVAL_SECONDS: float = 0.015
const CHAT_BUBBLE_MAX_LENGTH: int = 200
const CHAT_BUBBLE_SERVER_RATE_LIMIT_MS: int = 800
const MENU_ICON_PATH: String = "res://assets/ui/menu_icon.png"
const CHAT_ICON_PATH: String = "res://assets/ui/chat_icon.png"
const MOBILE_INVENTORY_ICON_PATH: String = "res://assets/mobile/inventory_icon.png"
const MOBILE_BOBUX_BADGE_ICON_PATH: String = "res://assets/mobile/bobux_badge_icon.png"
const MOBILE_DEVELOPER_BADGE_ICON_PATH: String = "res://assets/mobile/developer_badge_icon.png"
const PERSISTENT_WORLD_CHILDREN := [
	"WorldEnvironment",
	"Sun",
	"Players",
	"PlayerSpawner",
	"FallbackCamera"
]

@onready var world: Node3D = $World
@onready var players: Node3D = $World/Players
@onready var player_spawner: MultiplayerSpawner = $World/PlayerSpawner
@onready var fallback_camera: Camera3D = $World/FallbackCamera
@onready var leave_button: Button = get_node_or_null("HUD/LeaveButton") as Button
@onready var hint_label: Label = get_node_or_null("HUD/HintLabel") as Label

var peer_colors: Dictionary = {}
var peer_usernames: Dictionary = {}
var peer_user_ids: Dictionary = {}
var peer_profiles: Dictionary = {}
var _room_runtime_preparations: Dictionary = {}
var peer_avatar_visuals: Dictionary = {}
var _runtime_rbxl_material_cache := RbxlMaterialCache.new()
var _runtime_object_texture_cache: Dictionary = {}
var _peer_checkpoint_positions: Dictionary = {}
var _peer_spawn_infos: Dictionary = {}
var _peer_teleport_ready_at_msec: Dictionary = {}
var _peer_tool_damage_ready_at_msec: Dictionary = {}
var _peer_registered: Dictionary = {}
var _smart_play_failed: bool = false
var _teleport_blocks_by_color: Dictionary = {}
var _fallback_spawn_positions: Array[Vector3] = []
var _map_player_settings: Dictionary = {}
var _map_mode_settings: Dictionary = {}
var _map_roblox_manifest: Dictionary = {}
var _map_asset_urls: Dictionary = {}
var _pending_map_asset_downloads: Dictionary = {}
var _failed_map_asset_downloads: Dictionary = {}
var _mode_music_player: AudioStreamPlayer = null
var _health_bar: ProgressBar = null
var _ping_label: Label = null
var _game_menu_button: Button = null
var _game_menu_panel: Panel = null
var _system_menu_layer: CanvasLayer = null
var _game_menu_tween: Tween
var _tool_damage_protocol: Node
var _server_supports_tool_damage: bool = false
var _respawn_button: Button = null
var _menu_leave_button: Button = null
var _master_volume_slider: HSlider = null
var _escape_menu_players_page: VBoxContainer = null
var _escape_menu_settings_page: VBoxContainer = null
var _escape_menu_player_rows: VBoxContainer = null
var _playlist_files: Array[String] = []
var _current_playlist_index: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _network_loading_overlay: ColorRect = null
var _network_loading_layer: CanvasLayer = null
var _network_loading_card: Panel = null
var _network_loading_experience_label: Label = null
var _network_loading_title: Label = null
var _network_loading_subtitle: Label = null
var _network_loading_transport: Label = null
var _network_loading_transport_badge: Label = null
var _network_loading_bar: ProgressBar = null
var _network_loading_tween: Tween = null
var _network_loading_spinner: TextureRect = null
var _runtime_world_ready: bool = false
var _map_load_in_progress: bool = false
var _host_keepalive_timer: Timer = null
var _host_last_pong_msec: int = 0
var _last_ping_rtt_msec: int = -1
var _server_push_keepalive_accumulator: float = 0.0
var _soft_keepalive_timeout_count: int = 0
var _migration_corner_badge: Panel = null
var _migration_corner_label: Label = null
var _leaderboard_panel: Panel = null
var _leaderboard_title: Label = null
var _leaderboard_rows: VBoxContainer = null
var _runtime_top_hud_layer: CanvasLayer = null
var _runtime_inventory_controller: CanvasLayer = null
var _runtime_inventory_button: Button = null
var _mobile_top_bar: Panel = null
var _mobile_player_list_panel: Panel = null
var _mobile_player_list_rows: VBoxContainer = null
var _friend_request_popup: Panel = null
var _friend_request_popup_label: Label = null
var _friend_request_popup_sender_id: String = ""
var _leaderboard_pending_requests: Dictionary = {}
var _leaderboard_friend_user_ids: Dictionary = {}
var _vehicle_spawn_prompt_panel: Panel = null
var _vehicle_spawn_prompt_label: Label = null
var _friend_request_poll_in_flight: bool = false
var _friend_status_refresh_in_flight: bool = false
var _next_friend_request_poll_msec: int = 0
var _next_friend_status_refresh_msec: int = 0
var _migration_local_authority_before_handover: int = 0
var _migration_peer_states: Dictionary = {}
var _migration_local_state: Dictionary = {}
var _migration_locked_local_state: Dictionary = {}
var _last_local_runtime_state: Dictionary = {}
var _pending_existing_peer_snapshots: Dictionary = {}
var _pending_existing_peer_snapshot_jobs: Dictionary = {}
var _handover_payload_cache: Dictionary = {}
var _handover_target_peer_id: int = 0
var _handover_ready_peer_id: int = 0
var _leave_in_progress: bool = false
var _post_migration_guard_until_msec: int = 0
var _post_migration_guard_next_tick_msec: int = 0
var _next_duplicate_player_guard_msec: int = 0
var _next_leaderboard_refresh_msec: int = 0
var _map_loaded: bool = false
var _room_runtime_roots: Dictionary = {}
var _room_runtime_map_roots: Dictionary = {}
var _room_runtime_origins: Dictionary = {}
var _room_runtime_fallback_spawns: Dictionary = {}
var _room_runtime_teleports: Dictionary = {}
var _room_runtime_player_settings: Dictionary = {}
var _room_runtime_mode_settings: Dictionary = {}
var _room_runtime_roblox_manifests: Dictionary = {}
var _room_runtime_map_folders: Dictionary = {}
var _room_runtime_map_ids: Dictionary = {}
var _room_runtime_cloud_versions: Dictionary = {}
var _next_room_runtime_index: int = 0
var _chaos_cars_by_id: Dictionary = {}
var _chaos_car_id_by_owner: Dictionary = {}
var _vehicle_spawn_cooldowns: Dictionary = {}
var _next_vehicle_spawner_poll_msec: int = 0
var _threaded_scene_cache: Dictionary = {}
var _destructible_blocks_by_key: Dictionary = {}
var _peer_last_chat_bubble_msec: Dictionary = {}

func _is_dedicated_server_runtime() -> bool:
	return GameState != null and GameState.has_method("is_dedicated_server_runtime") and bool(GameState.is_dedicated_server_runtime())

func _ready() -> void:
	_tool_damage_protocol = preload("res://scripts/main/tool_damage_protocol.gd").new()
	_tool_damage_protocol.name = "ToolDamageProtocol"
	add_child(_tool_damage_protocol)
	_rng.randomize()
	player_spawner.spawn_path = player_spawner.get_path_to(players)
	player_spawner.spawn_function = _spawn_custom
	if leave_button != null:
		leave_button.visible = false
		if not leave_button.pressed.is_connected(_on_leave_pressed):
			leave_button.pressed.connect(_on_leave_pressed)
	if hint_label != null:
		hint_label.visible = false
	_configure_runtime_visual_stability()
	_build_runtime_hud()
	_ensure_runtime_inventory_controller()
	_ensure_host_keepalive_timer()
	_ensure_mode_music_player()
	if not NetworkManager.player_connected.is_connected(_on_peer_connected):
		NetworkManager.player_connected.connect(_on_peer_connected)
	if not NetworkManager.player_disconnected.is_connected(_on_peer_disconnected):
		NetworkManager.player_disconnected.connect(_on_peer_disconnected)
	if not NetworkManager.connected_to_server.is_connected(_on_connected_to_server):
		NetworkManager.connected_to_server.connect(_on_connected_to_server)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	if not NetworkManager.hosting_started.is_connected(_on_hosting_started):
		NetworkManager.hosting_started.connect(_on_hosting_started)
	if not NetworkManager.transport_status_changed.is_connected(_on_transport_status_changed):
		NetworkManager.transport_status_changed.connect(_on_transport_status_changed)
	if not NetworkManager.transport_progress_updated.is_connected(_on_transport_progress_updated):
		NetworkManager.transport_progress_updated.connect(_on_transport_progress_updated)
	if NetworkManager.has_signal("room_peer_profiles_updated") and not NetworkManager.room_peer_profiles_updated.is_connected(_on_room_peer_profiles_updated):
		NetworkManager.room_peer_profiles_updated.connect(_on_room_peer_profiles_updated)
	if NetworkManager.has_signal("room_emptied") and not NetworkManager.room_emptied.is_connected(_on_room_emptied):
		NetworkManager.room_emptied.connect(_on_room_emptied)
	
	# FIX B (Death Loop): Do NOT load the map here on the client.
	# The client MUST wait for the server's _confirm_room_join RPC.
	# Only the server (dedicated or host) loads the map in _ready().
	if _is_dedicated_server_runtime():
		_map_loaded = true
		_runtime_world_ready = true
	elif GameState.launch_mode == GameState.LaunchMode.HOST:
		await _load_selected_map()
		_map_loaded = true
		_runtime_world_ready = true
	_apply_network_sync_rate(self)
	
	_start_session_from_game_state()

func _configure_runtime_visual_stability() -> void:
	var sun_light: DirectionalLight3D = world.get_node_or_null("Sun") as DirectionalLight3D if world != null else null
	if sun_light != null:
		sun_light.shadow_enabled = true
		sun_light.set("directional_shadow_mode", DirectionalLight3D.SHADOW_ORTHOGONAL)
		sun_light.set("directional_shadow_blend_splits", true)
		sun_light.set("shadow_bias", 0.055)
		sun_light.set("shadow_normal_bias", 0.72)
		sun_light.set("shadow_blur", 0.85)
		sun_light.set("directional_shadow_max_distance", 140.0)
		sun_light.set("directional_shadow_fade_start", 0.92)
	if fallback_camera != null:
		fallback_camera.near = 0.14
		fallback_camera.far = 420.0

func _process(delta: float) -> void:
	if _network_loading_spinner != null and _network_loading_spinner.visible:
		_network_loading_spinner.rotation += delta * 2.35
	if _is_dedicated_server_runtime():
		_push_keepalive_ticks_from_main(delta)
		_poll_vehicle_spawners_if_needed()
		_poll_duplicate_player_guard()
		return
	_capture_local_runtime_state_snapshot()
	_update_local_player_hud()
	_update_ping_indicator()
	_update_leaderboard_if_needed()
	_poll_incoming_friend_requests_if_needed()
	_poll_friend_status_if_needed()
	_poll_vehicle_spawners_if_needed()
	_poll_post_migration_stabilizer()
	_poll_duplicate_player_guard()

func _log_keepalive(message: String) -> void:
	if VERBOSE_KEEPALIVE_LOGS:
		print(message)

func _push_keepalive_ticks_from_main(delta: float) -> void:
	if delta <= 0.0 or not multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		_server_push_keepalive_accumulator = 0.0
		return
	_server_push_keepalive_accumulator += delta
	if _server_push_keepalive_accumulator < SERVER_PUSH_KEEPALIVE_INTERVAL_SECONDS:
		return
	_server_push_keepalive_accumulator = 0.0
	for peer_id_variant in multiplayer.get_peers():
		var peer_id: int = int(peer_id_variant)
		if peer_id <= 0:
			continue
		_receive_host_keepalive_pong.rpc_id(peer_id, -1)
		_log_keepalive("[Tick] Host Main pushed keepalive tick to peer %d" % peer_id)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.poll()

func _build_runtime_hud() -> void:
	if _is_dedicated_server_runtime():
		if leave_button:
			leave_button.visible = false
		if hint_label:
			hint_label.visible = false
		return
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null and leave_button != null:
		hud = leave_button.get_parent() as CanvasLayer
	if hud == null:
		return
	_hide_legacy_runtime_hud_controls()
	_build_network_loading_overlay(hud)
	_build_migration_corner_badge(hud)
	_build_leaderboard_panel(hud)
	_build_friend_request_popup(hud)
	_build_vehicle_spawn_prompt(hud)

	_game_menu_button = Button.new()
	var mobile_runtime = get_node_or_null("/root/MobileRuntime")
	var is_mobile_platform: bool = mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta"))
	var btn_size: float = 72.0 if is_mobile_platform else 56.0
	_game_menu_button.anchor_left = 0.0
	_game_menu_button.anchor_top = 0.0
	_game_menu_button.anchor_right = 0.0
	_game_menu_button.anchor_bottom = 0.0
	_game_menu_button.offset_left = 16.0
	_game_menu_button.offset_top = 16.0
	_game_menu_button.offset_right = 16.0 + btn_size
	_game_menu_button.offset_bottom = 16.0 + btn_size
	_game_menu_button.text = ""
	_game_menu_button.custom_minimum_size = Vector2(btn_size, btn_size)
	var menu_icon := load(MENU_ICON_PATH) as Texture2D
	if menu_icon != null:
		_game_menu_button.icon = menu_icon
		_game_menu_button.expand_icon = true
	else:
		_game_menu_button.text = "Menu"
		_game_menu_button.add_theme_font_size_override("font_size", 14)
	_game_menu_button.focus_mode = Control.FOCUS_NONE
	_game_menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_menu_button.z_index = 220
	var menu_button_style := StyleBoxFlat.new()
	menu_button_style.bg_color = Color(0.15, 0.15, 0.18, 0.78)
	menu_button_style.corner_radius_top_left = 10
	menu_button_style.corner_radius_top_right = 10
	menu_button_style.corner_radius_bottom_right = 10
	menu_button_style.corner_radius_bottom_left = 10
	var menu_button_hover := menu_button_style.duplicate()
	menu_button_hover.bg_color = Color(0.23, 0.23, 0.27, 0.88)
	_game_menu_button.add_theme_stylebox_override("normal", menu_button_style)
	_game_menu_button.add_theme_stylebox_override("hover", menu_button_hover)
	_game_menu_button.add_theme_stylebox_override("pressed", menu_button_hover)
	_game_menu_button.pressed.connect(_on_game_menu_button_pressed)
	_system_menu_layer = CanvasLayer.new()
	_system_menu_layer.name = "SystemMenu"
	_system_menu_layer.layer = 900
	_system_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_system_menu_layer)
	_system_menu_layer.add_child(_game_menu_button)
	_game_menu_button.visible = false
	_game_menu_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_game_menu_panel = Panel.new()
	_game_menu_panel.anchor_left = 0.0
	_game_menu_panel.anchor_top = 0.0
	_game_menu_panel.anchor_right = 1.0
	_game_menu_panel.anchor_bottom = 1.0
	_game_menu_panel.offset_left = 0.0
	_game_menu_panel.offset_top = 0.0
	_game_menu_panel.offset_right = 0.0
	_game_menu_panel.offset_bottom = 0.0
	_game_menu_panel.visible = false
	_game_menu_panel.z_index = 210
	_game_menu_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var menu_panel_style := StyleBoxFlat.new()
	menu_panel_style.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	_game_menu_panel.add_theme_stylebox_override("panel", menu_panel_style)
	_system_menu_layer.add_child(_game_menu_panel)

	var menu_margin := MarginContainer.new()
	menu_margin.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_margin.anchor_left = 0.5
	menu_margin.anchor_top = 0.0
	menu_margin.anchor_right = 0.5
	menu_margin.anchor_bottom = 1.0
	menu_margin.offset_left = -420.0
	menu_margin.offset_top = 42.0
	menu_margin.offset_right = 420.0
	menu_margin.offset_bottom = -28.0
	menu_margin.add_theme_constant_override("margin_left", 0)
	menu_margin.add_theme_constant_override("margin_top", 0)
	menu_margin.add_theme_constant_override("margin_right", 0)
	menu_margin.add_theme_constant_override("margin_bottom", 0)
	_game_menu_panel.add_child(menu_margin)
	var fit_menu := func():
		var half_width := minf(420.0, maxf(140.0, get_viewport().get_visible_rect().size.x * 0.5 - 16.0))
		menu_margin.offset_left = -half_width
		menu_margin.offset_right = half_width
	menu_margin.get_viewport().size_changed.connect(fit_menu)
	fit_menu.call()

	var menu_vbox := VBoxContainer.new()
	menu_vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_vbox.add_theme_constant_override("separation", 10)
	menu_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_margin.add_child(menu_vbox)

	var tab_bar := HBoxContainer.new()
	tab_bar.custom_minimum_size = Vector2(0.0, 56.0)
	tab_bar.add_theme_constant_override("separation", 8)
	menu_vbox.add_child(tab_bar)

	var players_tab := _make_escape_menu_tab_button("Players")
	players_tab.pressed.connect(func(): _set_escape_menu_page("players"))
	tab_bar.add_child(players_tab)
	var settings_tab := _make_escape_menu_tab_button("Settings")
	settings_tab.pressed.connect(func(): _set_escape_menu_page("settings"))
	tab_bar.add_child(settings_tab)

	var page_card := Panel.new()
	page_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var page_style := StyleBoxFlat.new()
	page_style.bg_color = Color(0.2, 0.22, 0.26, 0.62)
	page_style.corner_radius_top_left = 6
	page_style.corner_radius_top_right = 6
	page_style.corner_radius_bottom_right = 6
	page_style.corner_radius_bottom_left = 6
	page_card.add_theme_stylebox_override("panel", page_style)
	menu_vbox.add_child(page_card)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 12)
	page_margin.add_theme_constant_override("margin_top", 10)
	page_margin.add_theme_constant_override("margin_right", 12)
	page_margin.add_theme_constant_override("margin_bottom", 10)
	page_card.add_child(page_margin)

	var pages := Control.new()
	pages.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_child(pages)

	_escape_menu_players_page = VBoxContainer.new()
	_escape_menu_players_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_escape_menu_players_page.add_theme_constant_override("separation", 8)
	pages.add_child(_escape_menu_players_page)

	var invite_label := Label.new()
	invite_label.text = "Invite friends to play"
	invite_label.add_theme_font_size_override("font_size", 17)
	invite_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_escape_menu_players_page.add_child(invite_label)

	var player_scroll := ScrollContainer.new()
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_escape_menu_players_page.add_child(player_scroll)

	_escape_menu_player_rows = VBoxContainer.new()
	_escape_menu_player_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_escape_menu_player_rows.add_theme_constant_override("separation", 8)
	player_scroll.add_child(_escape_menu_player_rows)

	_escape_menu_settings_page = VBoxContainer.new()
	_escape_menu_settings_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_escape_menu_settings_page.add_theme_constant_override("separation", 12)
	pages.add_child(_escape_menu_settings_page)

	var sound_label := Label.new()
	sound_label.text = "Volume"
	sound_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	sound_label.add_theme_font_size_override("font_size", 18)
	_escape_menu_settings_page.add_child(sound_label)

	_master_volume_slider = HSlider.new()
	_master_volume_slider.min_value = 0.0
	_master_volume_slider.max_value = 100.0
	_master_volume_slider.step = 1.0
	_master_volume_slider.custom_minimum_size = Vector2(0, 20)
	_master_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_master_volume_slider.focus_mode = Control.FOCUS_NONE
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)
	_escape_menu_settings_page.add_child(_master_volume_slider)
	_sync_master_volume_slider()

	var shadows_toggle := CheckBox.new()
	shadows_toggle.text = "Soft shadows"
	shadows_toggle.button_pressed = true
	shadows_toggle.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	shadows_toggle.toggled.connect(func(enabled: bool):
		var sun_light: DirectionalLight3D = world.get_node_or_null("Sun") as DirectionalLight3D if world != null else null
		if sun_light != null:
			sun_light.shadow_enabled = enabled
	)
	_escape_menu_settings_page.add_child(shadows_toggle)
	_add_mobile_controls_settings_if_needed(_escape_menu_settings_page)

	var bottom_buttons := HBoxContainer.new()
	bottom_buttons.add_theme_constant_override("separation", 16)
	menu_vbox.add_child(bottom_buttons)

	_respawn_button = Button.new()
	_respawn_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_respawn_button.text = "Reset"
	_respawn_button.tooltip_text = "Reset Character"
	_respawn_button.custom_minimum_size = Vector2(0, 62)
	_respawn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_respawn_button.focus_mode = Control.FOCUS_NONE
	_respawn_button.pressed.connect(_on_respawn_pressed)
	bottom_buttons.add_child(_respawn_button)

	_menu_leave_button = Button.new()
	_menu_leave_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_leave_button.text = "Leave"
	_menu_leave_button.custom_minimum_size = Vector2(0, 62)
	_menu_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_leave_button.focus_mode = Control.FOCUS_NONE
	_menu_leave_button.pressed.connect(_on_leave_pressed)
	bottom_buttons.add_child(_menu_leave_button)

	var resume_button := Button.new()
	resume_button.process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.text = "Resume"
	resume_button.custom_minimum_size = Vector2(0, 62)
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_button.focus_mode = Control.FOCUS_NONE
	resume_button.pressed.connect(func(): close_game_menu())
	bottom_buttons.add_child(resume_button)
	_set_escape_menu_page("players")
	_raise_game_menu_hud_to_front()

	_health_bar = ProgressBar.new()
	_health_bar.anchor_left = 1.0
	_health_bar.anchor_top = 0.0
	_health_bar.anchor_right = 1.0
	_health_bar.anchor_bottom = 0.0
	_health_bar.offset_left = -196.0
	_health_bar.offset_top = 18.0
	_health_bar.offset_right = -16.0
	_health_bar.offset_bottom = 36.0
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.16, 0.16, 0.18, 0.92)
	bg_style.corner_radius_top_left = 7
	bg_style.corner_radius_top_right = 7
	bg_style.corner_radius_bottom_right = 7
	bg_style.corner_radius_bottom_left = 7
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.82, 0.36, 1.0)
	fill_style.corner_radius_top_left = 7
	fill_style.corner_radius_top_right = 7
	fill_style.corner_radius_bottom_right = 7
	fill_style.corner_radius_bottom_left = 7
	_health_bar.add_theme_stylebox_override("background", bg_style)
	_health_bar.add_theme_stylebox_override("fill", fill_style)
	hud.add_child(_health_bar)

	_ping_label = Label.new()
	_ping_label.anchor_left = 1.0
	_ping_label.anchor_top = 0.0
	_ping_label.anchor_right = 1.0
	_ping_label.anchor_bottom = 0.0
	_ping_label.offset_left = -196.0
	_ping_label.offset_top = 38.0
	_ping_label.offset_right = -16.0
	_ping_label.offset_bottom = 58.0
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_label.text = "Ping: --"
	_ping_label.add_theme_font_size_override("font_size", 12)
	_ping_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	hud.add_child(_ping_label)

	var chat_box := get_node_or_null("ChatBox")
	if chat_box:
		if chat_box.has_method("apply_top_left_layout"):
			chat_box.call("apply_top_left_layout", 8.0)
	_build_mobile_runtime_hud(hud)

func _hide_legacy_runtime_hud_controls() -> void:
	if leave_button != null:
		leave_button.visible = false
		leave_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint_label != null:
		hint_label.visible = false
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud := get_node_or_null("HUD")
	if hud == null:
		return
	for node_path in ["LeaveButton", "HintLabel"]:
		var legacy_node := hud.get_node_or_null(node_path)
		if legacy_node == null:
			continue
		if legacy_node is CanvasItem:
			(legacy_node as CanvasItem).visible = false
		if legacy_node is Control:
			(legacy_node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.remove_child(legacy_node)
		legacy_node.queue_free()
	leave_button = null
	hint_label = null

func _raise_game_menu_hud_to_front() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null and leave_button != null:
		hud = leave_button.get_parent() as CanvasLayer
	if hud == null:
		return
	if _game_menu_panel != null and _game_menu_panel.get_parent() == hud:
		_game_menu_panel.z_index = 210
		hud.move_child(_game_menu_panel, hud.get_child_count() - 1)
	if _game_menu_button != null and _game_menu_button.get_parent() == hud:
		_game_menu_button.z_index = 220
		hud.move_child(_game_menu_button, hud.get_child_count() - 1)

func _build_vehicle_spawn_prompt(hud: CanvasLayer) -> void:
	if hud == null or _vehicle_spawn_prompt_panel != null:
		return
	_vehicle_spawn_prompt_panel = Panel.new()
	_vehicle_spawn_prompt_panel.visible = false
	_vehicle_spawn_prompt_panel.anchor_left = 0.5
	_vehicle_spawn_prompt_panel.anchor_top = 1.0
	_vehicle_spawn_prompt_panel.anchor_right = 0.5
	_vehicle_spawn_prompt_panel.anchor_bottom = 1.0
	_vehicle_spawn_prompt_panel.offset_left = -150.0
	_vehicle_spawn_prompt_panel.offset_top = -116.0
	_vehicle_spawn_prompt_panel.offset_right = 150.0
	_vehicle_spawn_prompt_panel.offset_bottom = -70.0
	_vehicle_spawn_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.78)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.14)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	_vehicle_spawn_prompt_panel.add_theme_stylebox_override("panel", style)
	hud.add_child(_vehicle_spawn_prompt_panel)

	_vehicle_spawn_prompt_label = Label.new()
	_vehicle_spawn_prompt_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vehicle_spawn_prompt_label.text = "[E] Spawn Car"
	_vehicle_spawn_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vehicle_spawn_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vehicle_spawn_prompt_label.add_theme_font_size_override("font_size", 21)
	_vehicle_spawn_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_vehicle_spawn_prompt_panel.add_child(_vehicle_spawn_prompt_label)

func _build_network_loading_overlay(hud: CanvasLayer) -> void:
	if _network_loading_overlay != null: return
	_network_loading_layer = CanvasLayer.new()
	_network_loading_layer.layer = 1000
	add_child(_network_loading_layer)
	var overlay = load("res://scripts/ui/experience_loading.gd").new()
	overlay.visible = false
	overlay.rotate_spinner = false # Main's existing animation owns this spinner.
	_network_loading_layer.add_child(overlay)
	_network_loading_overlay = overlay
	_network_loading_card = overlay.card
	_network_loading_experience_label = overlay.experience
	_network_loading_title = overlay.title
	_network_loading_subtitle = overlay.subtitle
	_network_loading_transport = overlay.transport
	_network_loading_transport_badge = overlay.transport_badge
	_network_loading_bar = overlay.bar
	_network_loading_spinner = overlay.spinner

func _build_leaderboard_panel(hud: CanvasLayer) -> void:
	if hud == null or _leaderboard_panel != null:
		return
	_leaderboard_panel = Panel.new()
	_leaderboard_panel.visible = false
	_leaderboard_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_leaderboard_panel.anchor_left = 1.0
	_leaderboard_panel.anchor_top = 0.0
	_leaderboard_panel.anchor_right = 1.0
	_leaderboard_panel.anchor_bottom = 0.0
	_leaderboard_panel.offset_left = -320.0
	_leaderboard_panel.offset_top = 86.0
	_leaderboard_panel.offset_right = -16.0
	_leaderboard_panel.offset_bottom = 346.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.34, 0.54, 0.78, 0.45)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	panel_style.shadow_size = 8
	_leaderboard_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(_leaderboard_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_leaderboard_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_leaderboard_title = Label.new()
	_leaderboard_title.text = "Players"
	_leaderboard_title.add_theme_font_size_override("font_size", 18)
	_leaderboard_title.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0, 1.0))
	root.add_child(_leaderboard_title)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var name_header := Label.new()
	name_header.text = "Player"
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_header.add_theme_font_size_override("font_size", 11)
	name_header.add_theme_color_override("font_color", Color(0.67, 0.75, 0.84, 0.9))
	header.add_child(name_header)

	var ping_header := Label.new()
	ping_header.text = "Ping"
	ping_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_header.custom_minimum_size = Vector2(72.0, 0.0)
	ping_header.add_theme_font_size_override("font_size", 11)
	ping_header.add_theme_color_override("font_color", Color(0.67, 0.75, 0.84, 0.9))
	header.add_child(ping_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_leaderboard_rows = VBoxContainer.new()
	_leaderboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaderboard_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_leaderboard_rows)

func _build_mobile_runtime_hud(hud: CanvasLayer) -> void:
	if hud == null or _mobile_top_bar != null:
		return
	_runtime_top_hud_layer = CanvasLayer.new()
	_runtime_top_hud_layer.name = "RuntimeTopHudLayer"
	_runtime_top_hud_layer.layer = 8
	add_child(_runtime_top_hud_layer)

	_mobile_top_bar = Panel.new()
	_mobile_top_bar.name = "MobileRuntimeTopBar"
	_mobile_top_bar.anchor_left = 0.0
	_mobile_top_bar.anchor_top = 0.0
	_mobile_top_bar.anchor_right = 1.0
	_mobile_top_bar.anchor_bottom = 0.0
	_mobile_top_bar.offset_left = 0.0
	_mobile_top_bar.offset_top = 0.0
	_mobile_top_bar.offset_right = 0.0
	_mobile_top_bar.offset_bottom = 60.0
	_mobile_top_bar.z_index = 130
	_mobile_top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.39, 0.41, 0.45, 0.96)
	_mobile_top_bar.add_theme_stylebox_override("panel", top_style)
	_runtime_top_hud_layer.add_child(_mobile_top_bar)

	var left_buttons := HBoxContainer.new()
	left_buttons.anchor_left = 0.0
	left_buttons.anchor_top = 0.0
	left_buttons.anchor_right = 0.0
	left_buttons.anchor_bottom = 1.0
	left_buttons.offset_left = 4.0
	left_buttons.offset_top = 4.0
	left_buttons.offset_right = 214.0
	left_buttons.offset_bottom = -4.0
	left_buttons.add_theme_constant_override("separation", 8)
	_mobile_top_bar.add_child(left_buttons)

	var menu_button := _make_mobile_top_button(MENU_ICON_PATH, "MENU")
	menu_button.pressed.connect(_on_game_menu_button_pressed)
	left_buttons.add_child(menu_button)

	var chat_button := _make_mobile_top_button(CHAT_ICON_PATH, "CHAT")
	chat_button.pressed.connect(_toggle_mobile_chat)
	left_buttons.add_child(chat_button)

	_runtime_inventory_button = _make_mobile_top_button(MOBILE_INVENTORY_ICON_PATH, "BAG")
	_runtime_inventory_button.tooltip_text = "Inventory"
	_runtime_inventory_button.pressed.connect(_toggle_runtime_inventory)
	left_buttons.add_child(_runtime_inventory_button)

	_set_mobile_chat_builtin_toggle_visible(false)
	call_deferred("_set_mobile_chat_builtin_toggle_visible", false)
	if _health_bar != null:
		if _health_bar.get_parent() != null and _health_bar.get_parent() != _runtime_top_hud_layer:
			_health_bar.reparent(_runtime_top_hud_layer)
		_health_bar.z_index = 135
		_health_bar.offset_left = -154.0
		_health_bar.offset_top = 28.0
		_health_bar.offset_right = -12.0
		_health_bar.offset_bottom = 43.0
	if _ping_label != null:
		_ping_label.visible = false

	_mobile_player_list_panel = Panel.new()
	_mobile_player_list_panel.name = "MobilePlayerList"
	_mobile_player_list_panel.anchor_left = 1.0
	_mobile_player_list_panel.anchor_top = 0.0
	_mobile_player_list_panel.anchor_right = 1.0
	_mobile_player_list_panel.anchor_bottom = 0.0
	_mobile_player_list_panel.offset_left = -190.0
	_mobile_player_list_panel.offset_top = 66.0
	_mobile_player_list_panel.offset_right = -2.0
	_mobile_player_list_panel.offset_bottom = 226.0
	_mobile_player_list_panel.z_index = 125
	_mobile_player_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.30, 0.31, 0.33, 0.18)
	list_style.border_width_left = 1
	list_style.border_width_top = 1
	list_style.border_width_right = 1
	list_style.border_width_bottom = 1
	list_style.border_color = Color(0.82, 0.86, 0.90, 0.24)
	_mobile_player_list_panel.add_theme_stylebox_override("panel", list_style)
	_runtime_top_hud_layer.add_child(_mobile_player_list_panel)

	var list_margin := MarginContainer.new()
	list_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	list_margin.add_theme_constant_override("margin_left", 4)
	list_margin.add_theme_constant_override("margin_top", 4)
	list_margin.add_theme_constant_override("margin_right", 4)
	list_margin.add_theme_constant_override("margin_bottom", 4)
	_mobile_player_list_panel.add_child(list_margin)

	_mobile_player_list_rows = VBoxContainer.new()
	_mobile_player_list_rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mobile_player_list_rows.add_theme_constant_override("separation", 3)
	list_margin.add_child(_mobile_player_list_rows)
	_refresh_mobile_player_list()

func _make_mobile_top_button(icon_path: String, fallback_text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(58.0, 52.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.expand_icon = true
	var icon_texture := load(icon_path) as Texture2D
	if icon_texture != null:
		button.icon = icon_texture
	else:
		button.text = fallback_text
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.43, 0.45, 0.49, 0.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	var hover := style.duplicate()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _ensure_runtime_inventory_controller() -> void:
	if _is_dedicated_server_runtime() or _runtime_inventory_controller != null:
		return
	var controller_variant := RobloxInventoryControllerClass.new()
	if not (controller_variant is CanvasLayer):
		return
	_runtime_inventory_controller = controller_variant as CanvasLayer
	if _runtime_inventory_controller.has_method("configure"):
		_runtime_inventory_controller.call("configure", LuaScriptEngine, self, Callable(self, "_get_local_player"))
	add_child(_runtime_inventory_controller)


func _toggle_runtime_inventory() -> void:
	_ensure_runtime_inventory_controller()
	if _runtime_inventory_controller != null and _runtime_inventory_controller.has_method("toggle_inventory"):
		_runtime_inventory_controller.call("toggle_inventory")


func _refresh_runtime_inventory() -> void:
	_ensure_runtime_inventory_controller()
	if _runtime_inventory_controller != null and _runtime_inventory_controller.has_method("refresh_now"):
		_runtime_inventory_controller.call("refresh_now", true)

func _toggle_mobile_chat() -> void:
	var chat_box := get_node_or_null("ChatBox")
	if chat_box == null or not chat_box.has_method("set_chat_visible_state"):
		return
	if _game_menu_panel != null and _game_menu_panel.visible:
		close_game_menu()
	var is_visible: bool = bool(chat_box.get("chat_visible"))
	chat_box.call("set_chat_visible_state", not is_visible, true)

func _set_runtime_top_hud_visible(should_show: bool) -> void:
	if _runtime_top_hud_layer != null:
		_runtime_top_hud_layer.visible = should_show

func _set_mobile_chat_builtin_toggle_visible(should_show: bool) -> void:
	var chat_box := get_node_or_null("ChatBox")
	if chat_box == null:
		return
	var toggle_variant: Variant = chat_box.get("toggle_button")
	if toggle_variant is Button:
		var toggle := toggle_variant as Button
		toggle.visible = should_show
		toggle.mouse_filter = Control.MOUSE_FILTER_STOP if should_show else Control.MOUSE_FILTER_IGNORE

func _refresh_mobile_player_list() -> void:
	if _mobile_player_list_rows == null:
		return
	for child in _mobile_player_list_rows.get_children():
		child.queue_free()
	var peer_ids: Array[int] = _get_sorted_leaderboard_peer_ids()
	if peer_ids.is_empty():
		peer_ids.append(_get_runtime_local_peer_id())
	var row_limit: int = 6 if _is_mobile_runtime_platform() else 8
	var row_count: int = mini(peer_ids.size(), row_limit)
	if _mobile_player_list_panel != null:
		_mobile_player_list_panel.offset_bottom = 66.0 + 8.0 + float(row_count) * 31.0
	for index in range(row_count):
		_mobile_player_list_rows.add_child(_build_mobile_player_list_row(peer_ids[index]))

func _is_mobile_runtime_platform() -> bool:
	var mobile_runtime = get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))

func _build_mobile_player_list_row(peer_id: int) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.40, 0.41, 0.43, 0.86)
	row_style.border_width_bottom = 1
	row_style.border_color = Color(0.86, 0.88, 0.90, 0.35)
	row.add_theme_stylebox_override("panel", row_style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 2)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	margin.add_child(hbox)

	var username: String = _get_mobile_player_display_name(peer_id)
	var name_label := Label.new()
	name_label.text = username
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.48))
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	hbox.add_child(name_label)
	_attach_runtime_account_badges(name_label, peer_id)

	if username.to_lower() == "pavelord":
		hbox.add_child(_make_mobile_badge_icon(MOBILE_BOBUX_BADGE_ICON_PATH))
	if _is_mobile_player_current_mode_creator(peer_id, username):
		hbox.add_child(_make_mobile_badge_icon(MOBILE_DEVELOPER_BADGE_ICON_PATH))
	return row

func _make_mobile_badge_icon(path: String) -> TextureRect:
	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(22.0, 22.0)
	badge.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := load(path) as Texture2D
	if texture != null:
		badge.texture = texture
	return badge

func _get_mobile_player_display_name(peer_id: int) -> String:
	var username: String = str(peer_usernames.get(peer_id, "")).strip_edges()
	if username.is_empty() and _is_local_leaderboard_peer(peer_id) and UserSession.is_logged_in:
		username = UserSession.username
	if username.is_empty():
		username = "Player"
	return username

func _is_mobile_player_current_mode_creator(peer_id: int, username: String) -> bool:
	var creator: String = _get_current_mode_creator_username().to_lower()
	var clean_username: String = username.strip_edges().to_lower()
	if not creator.is_empty() and clean_username == creator:
		return true
	return peer_id == 1 and creator.is_empty()

func _get_current_mode_creator_username() -> String:
	var metadata: Dictionary = GameState.get_selected_map_metadata() if GameState != null and GameState.has_method("get_selected_map_metadata") else {}
	var candidates: Array[String] = ["creator_username", "creator", "owner_username", "owner_name", "author", "created_by", "username"]
	for key in candidates:
		var value: String = str(metadata.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	var server_info: Dictionary = GameState.target_server_info if GameState != null and GameState.target_server_info is Dictionary else {}
	for key in candidates:
		var value: String = str(server_info.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _build_friend_request_popup(hud: CanvasLayer) -> void:
	if hud == null or _friend_request_popup != null:
		return
	_friend_request_popup = Panel.new()
	_friend_request_popup.visible = false
	_friend_request_popup.anchor_left = 1.0
	_friend_request_popup.anchor_top = 1.0
	_friend_request_popup.anchor_right = 1.0
	_friend_request_popup.anchor_bottom = 1.0
	_friend_request_popup.offset_left = -360.0
	_friend_request_popup.offset_top = -132.0
	_friend_request_popup.offset_right = -18.0
	_friend_request_popup.offset_bottom = -18.0
	_friend_request_popup.z_index = 120
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.09, 0.1, 0.13, 0.94)
	popup_style.corner_radius_top_left = 12
	popup_style.corner_radius_top_right = 12
	popup_style.corner_radius_bottom_right = 12
	popup_style.corner_radius_bottom_left = 12
	popup_style.border_width_left = 1
	popup_style.border_width_top = 1
	popup_style.border_width_right = 1
	popup_style.border_width_bottom = 1
	popup_style.border_color = Color(0.55, 0.62, 0.72, 0.35)
	popup_style.shadow_color = Color(0.0, 0.0, 0.0, 0.26)
	popup_style.shadow_size = 10
	_friend_request_popup.add_theme_stylebox_override("panel", popup_style)
	hud.add_child(_friend_request_popup)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_friend_request_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_friend_request_popup_label = Label.new()
	_friend_request_popup_label.text = "Friend request"
	_friend_request_popup_label.add_theme_font_size_override("font_size", 15)
	_friend_request_popup_label.add_theme_color_override("font_color", Color.WHITE)
	root.add_child(_friend_request_popup_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)

	var accept_button := Button.new()
	accept_button.text = "Accept"
	accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_button.focus_mode = Control.FOCUS_NONE
	accept_button.pressed.connect(func(): _respond_to_friend_request_from_ui(_friend_request_popup_sender_id, true))
	buttons.add_child(accept_button)

	var decline_button := Button.new()
	decline_button.text = "Decline"
	decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_button.focus_mode = Control.FOCUS_NONE
	decline_button.pressed.connect(func(): _respond_to_friend_request_from_ui(_friend_request_popup_sender_id, false))
	buttons.add_child(decline_button)

func _set_leaderboard_visible(should_show: bool) -> void:
	if _mobile_player_list_panel != null:
		_mobile_player_list_panel.visible = should_show
		if should_show:
			_next_friend_status_refresh_msec = 0
			_next_leaderboard_refresh_msec = 0
			_refresh_mobile_player_list()
		return
	if _leaderboard_panel == null:
		return
	_leaderboard_panel.visible = should_show
	if should_show:
		_next_friend_status_refresh_msec = 0
		_next_leaderboard_refresh_msec = 0
		_update_leaderboard_if_needed(true)

func _is_runtime_player_list_visible() -> bool:
	if _mobile_player_list_panel != null:
		return _mobile_player_list_panel.visible
	return _leaderboard_panel != null and _leaderboard_panel.visible

func _update_leaderboard_if_needed(force: bool = false) -> void:
	if (_leaderboard_panel == null or _leaderboard_rows == null) and _mobile_player_list_rows == null:
		return
	var now_msec: int = Time.get_ticks_msec()
	if not force and now_msec < _next_leaderboard_refresh_msec:
		return
	_next_leaderboard_refresh_msec = now_msec + LEADERBOARD_REFRESH_INTERVAL_MSEC
	if (_leaderboard_panel == null or not _leaderboard_panel.visible) and not force:
		_refresh_mobile_player_list()
		return
	_refresh_leaderboard_rows()

func _refresh_leaderboard_rows() -> void:
	if _leaderboard_rows == null:
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	var peer_ids: Array[int] = _get_sorted_leaderboard_peer_ids()
	if _leaderboard_title != null:
		_leaderboard_title.text = "Players %d" % peer_ids.size()
	for peer_id in peer_ids:
		_leaderboard_rows.add_child(_build_leaderboard_row(peer_id))
	_refresh_mobile_player_list()

func _build_leaderboard_row(peer_id: int) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0.0, 34.0)
	row.text = ""
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.11, 0.12, 0.16, 0.84)
	row_style.corner_radius_top_left = 10
	row_style.corner_radius_top_right = 10
	row_style.corner_radius_bottom_right = 10
	row_style.corner_radius_bottom_left = 10
	var row_hover := row_style.duplicate()
	row_hover.bg_color = Color(0.16, 0.18, 0.23, 0.92)
	row.add_theme_stylebox_override("normal", row_style)
	row.add_theme_stylebox_override("hover", row_hover)
	row.add_theme_stylebox_override("pressed", row_hover)
	row.pressed.connect(func(): _on_leaderboard_player_pressed(peer_id))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	var username: String = peer_usernames.get(peer_id, UserSession.username if _is_local_leaderboard_peer(peer_id) and UserSession.is_logged_in else "Player")
	var is_host_row: bool = peer_id == 1
	name_label.text = "%s%s" % [username, "  [Host]" if is_host_row else ""]
	hbox.add_child(name_label)
	_attach_runtime_account_badges(name_label, peer_id)

	var user_id: String = _get_user_id_for_leaderboard_peer(peer_id)
	if not user_id.is_empty() and _leaderboard_pending_requests.has(user_id):
		margin.mouse_filter = Control.MOUSE_FILTER_PASS
		var accept_button := Button.new()
		accept_button.text = "Accept"
		accept_button.custom_minimum_size = Vector2(62.0, 24.0)
		accept_button.focus_mode = Control.FOCUS_NONE
		accept_button.add_theme_color_override("font_color", Color.WHITE)
		accept_button.pressed.connect(func(): _respond_to_friend_request_from_ui(user_id, true))
		hbox.add_child(accept_button)
		var decline_button := Button.new()
		decline_button.text = "Decline"
		decline_button.custom_minimum_size = Vector2(66.0, 24.0)
		decline_button.focus_mode = Control.FOCUS_NONE
		decline_button.add_theme_color_override("font_color", Color.WHITE)
		decline_button.pressed.connect(func(): _respond_to_friend_request_from_ui(user_id, false))
		hbox.add_child(decline_button)
	else:
		var ping_label := Label.new()
		ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ping_label.custom_minimum_size = Vector2(80.0, 0.0)
		ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ping_label.add_theme_font_size_override("font_size", 12)
		ping_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95, 0.92))
		ping_label.text = _get_ping_text_for_peer(peer_id)
		hbox.add_child(ping_label)
	return row

func _get_user_id_for_leaderboard_peer(peer_id: int) -> String:
	if _is_local_leaderboard_peer(peer_id):
		return CloudAPI.get_current_user_id() if CloudAPI != null and CloudAPI.has_method("get_current_user_id") else ""
	return str(peer_user_ids.get(peer_id, "")).strip_edges()

func _on_leaderboard_player_pressed(peer_id: int) -> void:
	if _is_local_leaderboard_peer(peer_id):
		return
	var user_id: String = _get_user_id_for_leaderboard_peer(peer_id)
	var username: String = str(peer_usernames.get(peer_id, "Player")).strip_edges()
	if user_id.is_empty():
		_show_small_runtime_notice("%s profile is still syncing. Try again in a second." % (username if not username.is_empty() else "Player"))
		return
	if _is_friend_user_id(user_id):
		_show_small_runtime_notice("%s is already your friend." % (username if not username.is_empty() else "Player"))
		return
	if _leaderboard_pending_requests.has(user_id):
		_show_incoming_friend_request_popup(_leaderboard_pending_requests[user_id])
		return
	_send_friend_request_from_leaderboard(user_id, username)

func _send_friend_request_from_leaderboard(user_id: String, username: String) -> void:
	if CloudAPI == null or not CloudAPI.has_method("send_friend_request"):
		return
	var response: Dictionary = await CloudAPI.send_friend_request(user_id, username)
	if bool(response.get("ok", false)):
		_show_small_runtime_notice(_format_runtime_friend_request_status(response, username))
		_next_friend_request_poll_msec = 0
		_next_friend_status_refresh_msec = 0
		if bool(_friend_request_response_flag(response, "already_friends")):
			_leaderboard_friend_user_ids[user_id.strip_edges()] = true
		if (_leaderboard_panel != null and _leaderboard_panel.visible) or (_game_menu_panel != null and _game_menu_panel.visible):
			_refresh_leaderboard_rows()
			_refresh_escape_menu_player_rows()
	else:
		_show_small_runtime_notice(str(response.get("error", "Could not send friend request.")))

func _friend_request_response_payload(response: Dictionary) -> Dictionary:
	var payload: Variant = response.get("data", {})
	if payload is Dictionary:
		return payload
	return {}

func _friend_request_response_flag(response: Dictionary, flag_name: String) -> bool:
	if bool(response.get(flag_name, false)):
		return true
	var payload: Dictionary = _friend_request_response_payload(response)
	return bool(payload.get(flag_name, false))

func _format_runtime_friend_request_status(response: Dictionary, username: String) -> String:
	var display_name: String = username.strip_edges()
	if display_name.is_empty():
		var payload: Dictionary = _friend_request_response_payload(response)
		var profile: Dictionary = payload.get("target_profile", {}) if payload.get("target_profile", {}) is Dictionary else {}
		display_name = str(profile.get("username", "")).strip_edges()
	if display_name.is_empty():
		display_name = "player"
	if _friend_request_response_flag(response, "already_friends"):
		return "%s is already your friend." % display_name
	if _friend_request_response_flag(response, "incoming_pending"):
		return "%s already sent you a request. Open Tab to accept it." % display_name
	if _friend_request_response_flag(response, "pending"):
		return "Friend request sent to %s." % display_name
	return "Friend request updated for %s." % display_name

func _poll_incoming_friend_requests_if_needed() -> void:
	if CloudAPI == null or not CloudAPI.has_method("get_incoming_friend_requests"):
		return
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	if _friend_request_poll_in_flight:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_friend_request_poll_msec:
		return
	_friend_request_poll_in_flight = true
	_next_friend_request_poll_msec = now_msec + FRIEND_REQUEST_POLL_INTERVAL_MSEC
	var response: Dictionary = await CloudAPI.get_incoming_friend_requests()
	_friend_request_poll_in_flight = false
	if not bool(response.get("ok", false)):
		return
	var previous_requests: Dictionary = _leaderboard_pending_requests.duplicate(true)
	_leaderboard_pending_requests.clear()
	var requests: Array = response.get("data", []) if response.get("data", []) is Array else []
	for request_variant in requests:
		if not (request_variant is Dictionary):
			continue
		var request: Dictionary = request_variant
		var sender_id: String = _get_friend_request_sender_id(request)
		if sender_id.is_empty():
			continue
		_leaderboard_pending_requests[sender_id] = request
		if not previous_requests.has(sender_id):
			_show_incoming_friend_request_popup(request)
	if _leaderboard_panel != null and _leaderboard_panel.visible:
		_refresh_leaderboard_rows()

func _poll_friend_status_if_needed() -> void:
	if CloudAPI == null or not CloudAPI.has_method("get_friends_list"):
		return
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	if _friend_status_refresh_in_flight:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_friend_status_refresh_msec:
		return
	_friend_status_refresh_in_flight = true
	_next_friend_status_refresh_msec = now_msec + FRIEND_STATUS_REFRESH_INTERVAL_MSEC
	var response: Dictionary = await CloudAPI.get_friends_list()
	_friend_status_refresh_in_flight = false
	if not bool(response.get("ok", false)):
		return
	_leaderboard_friend_user_ids.clear()
	for friend_variant in CloudAPI._extract_array_payload(response.get("data", [])):
		if not (friend_variant is Dictionary):
			continue
		var friend: Dictionary = friend_variant
		var friend_id: String = str(friend.get("friend_user_id", friend.get("id", friend.get("user_id", "")))).strip_edges()
		if friend_id.is_empty() and friend.get("profile", {}) is Dictionary:
			friend_id = str((friend.get("profile", {}) as Dictionary).get("id", "")).strip_edges()
		if not friend_id.is_empty():
			_leaderboard_friend_user_ids[friend_id] = true
	if (_leaderboard_panel != null and _leaderboard_panel.visible) or (_game_menu_panel != null and _game_menu_panel.visible):
		_refresh_leaderboard_rows()
		_refresh_escape_menu_player_rows()

func _is_friend_user_id(user_id: String) -> bool:
	var clean_user_id: String = user_id.strip_edges()
	return not clean_user_id.is_empty() and _leaderboard_friend_user_ids.has(clean_user_id)

func _get_friend_request_sender_id(request: Dictionary) -> String:
	return str(request.get("from_user", "")).strip_edges()

func _get_friend_request_sender_name(request: Dictionary) -> String:
	var profile: Dictionary = request.get("sender_profile", {}) if request.get("sender_profile", {}) is Dictionary else {}
	var username: String = str(profile.get("username", "")).strip_edges()
	if username.is_empty():
		username = str(request.get("from_username", "")).strip_edges()
	return username if not username.is_empty() else "Player"

func _show_incoming_friend_request_popup(request: Dictionary) -> void:
	if _friend_request_popup == null or _friend_request_popup_label == null:
		return
	var sender_id: String = _get_friend_request_sender_id(request)
	if sender_id.is_empty():
		return
	_friend_request_popup_sender_id = sender_id
	_friend_request_popup_label.text = "%s sent you a friend request." % _get_friend_request_sender_name(request)
	_friend_request_popup.modulate.a = 1.0
	_friend_request_popup.visible = true
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(_friend_request_popup, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func():
		if _friend_request_popup != null and _friend_request_popup_sender_id == sender_id:
			_friend_request_popup.visible = false
			_friend_request_popup.modulate.a = 1.0
	)

func _respond_to_friend_request_from_ui(sender_id: String, accept_request: bool) -> void:
	var clean_sender_id: String = sender_id.strip_edges()
	if clean_sender_id.is_empty() or CloudAPI == null:
		return
	var response: Dictionary = {}
	if accept_request and CloudAPI.has_method("accept_friend_request"):
		response = await CloudAPI.accept_friend_request(clean_sender_id)
	elif not accept_request and CloudAPI.has_method("decline_friend_request"):
		response = await CloudAPI.decline_friend_request(clean_sender_id)
	else:
		return
	if bool(response.get("ok", false)):
		_leaderboard_pending_requests.erase(clean_sender_id)
		if _friend_request_popup != null and _friend_request_popup_sender_id == clean_sender_id:
			_friend_request_popup.visible = false
		_show_small_runtime_notice("Friend request accepted." if accept_request else "Friend request declined.")
	else:
		_show_small_runtime_notice(str(response.get("error", "Could not update friend request.")))
	if _leaderboard_panel != null and _leaderboard_panel.visible:
		_refresh_leaderboard_rows()

func _show_small_runtime_notice(message: String) -> void:
	var clean_message: String = message.strip_edges()
	if clean_message.is_empty():
		return
	print("[Notice] %s" % clean_message)
	var hud: CanvasLayer = _friend_request_popup.get_parent() as CanvasLayer if _friend_request_popup != null else null
	if hud == null:
		return
	var notice := Label.new()
	notice.text = clean_message
	notice.anchor_left = 1.0
	notice.anchor_top = 1.0
	notice.anchor_right = 1.0
	notice.anchor_bottom = 1.0
	notice.offset_left = -360.0
	notice.offset_top = -170.0
	notice.offset_right = -18.0
	notice.offset_bottom = -140.0
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.add_theme_font_size_override("font_size", 13)
	notice.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	hud.add_child(notice)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(notice, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		if is_instance_valid(notice):
			notice.queue_free()
	)

func _get_sorted_leaderboard_peer_ids() -> Array[int]:
	var peer_ids: Dictionary = {}
	var player_peer_ids: Dictionary = {}
	var current_room_id: String = _get_effective_local_room_id()
	var room_member_peer_ids: Dictionary = _get_current_room_member_peer_lookup(current_room_id)
	var strict_room_members: bool = not current_room_id.is_empty() and not room_member_peer_ids.is_empty()
	if players != null:
		for child in players.get_children():
			if child is CharacterBody3D:
				var child_peer_id: int = _extract_peer_id_from_player(child as CharacterBody3D)
				if child_peer_id > 0 and _peer_belongs_to_leaderboard_room(child_peer_id, current_room_id, room_member_peer_ids, strict_room_members):
					peer_ids[child_peer_id] = true
					player_peer_ids[child_peer_id] = true
	for peer_id_variant in peer_usernames.keys():
		var known_peer_id: int = int(peer_id_variant)
		if _should_include_leaderboard_peer(known_peer_id, player_peer_ids, current_room_id, room_member_peer_ids, strict_room_members):
			peer_ids[known_peer_id] = true
	if multiplayer.multiplayer_peer != null:
		for peer_id_variant in multiplayer.get_peers():
			var remote_peer_id: int = int(peer_id_variant)
			if _should_include_leaderboard_peer(remote_peer_id, player_peer_ids, current_room_id, room_member_peer_ids, strict_room_members):
				peer_ids[remote_peer_id] = true
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0:
		peer_ids[runtime_local_peer_id] = true
	elif NetworkManager != null and NetworkManager.is_host():
		peer_ids[1] = true
	var sorted_peer_ids: Array[int] = []
	for peer_id_variant in peer_ids.keys():
		sorted_peer_ids.append(int(peer_id_variant))
	sorted_peer_ids.sort()
	return sorted_peer_ids

func _get_current_room_member_peer_lookup(current_room_id: String) -> Dictionary:
	var lookup: Dictionary = {}
	var clean_room_id: String = current_room_id.strip_edges()
	if clean_room_id.is_empty() or NetworkManager == null or not NetworkManager.has_method("get_room_member_peer_ids"):
		return lookup
	for peer_variant in NetworkManager.get_room_member_peer_ids(clean_room_id):
		var peer_id: int = int(peer_variant)
		if peer_id > 0:
			lookup[peer_id] = true
	return lookup

func _peer_belongs_to_leaderboard_room(peer_id: int, current_room_id: String, room_member_peer_ids: Dictionary, strict_room_members: bool) -> bool:
	if peer_id <= 0:
		return false
	if _is_local_leaderboard_peer(peer_id):
		return true
	if strict_room_members:
		return room_member_peer_ids.has(peer_id)
	var clean_room_id: String = current_room_id.strip_edges()
	if clean_room_id.is_empty():
		return _peer_matches_effective_local_room(peer_id)
	var peer_room_id: String = _get_peer_room_id(peer_id)
	return not peer_room_id.is_empty() and peer_room_id == clean_room_id

func _should_include_leaderboard_peer(peer_id: int, player_peer_ids: Dictionary, current_room_id: String = "", room_member_peer_ids: Dictionary = {}, strict_room_members: bool = false) -> bool:
	if peer_id <= 0:
		return false
	if not _peer_belongs_to_leaderboard_room(peer_id, current_room_id, room_member_peer_ids, strict_room_members):
		return false
	if player_peer_ids.has(peer_id):
		return true
	if _is_local_leaderboard_peer(peer_id):
		return true
	if peer_id == 1 and (NetworkManager == null or not NetworkManager.is_host()):
		return false
	return peer_user_ids.has(peer_id) or peer_usernames.has(peer_id)

func _is_local_leaderboard_peer(peer_id: int) -> bool:
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0:
		return runtime_local_peer_id == peer_id
	return NetworkManager != null and NetworkManager.is_host() and peer_id == 1

func _get_ping_text_for_peer(peer_id: int) -> String:
	if NetworkManager != null and NetworkManager.is_host() and peer_id == 1:
		return "Host"
	if _is_local_leaderboard_peer(peer_id):
		if _last_ping_rtt_msec >= 0:
			return "%d ms" % _last_ping_rtt_msec
		return "..."
	if peer_id == 1:
		return "Host"
	return "--"

# This function builds a small, Roblox-style corner badge that shows during host migration
# instead of an ugly full-screen overlay. Players see characters freeze for ~1 second
# while this badge subtly indicates what's happening.
func _build_migration_corner_badge(hud: CanvasLayer) -> void:
	if hud == null or _migration_corner_badge != null:
		return
	_migration_corner_badge = Panel.new()
	_migration_corner_badge.visible = false
	_migration_corner_badge.z_index = 100
	_migration_corner_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_migration_corner_badge.anchor_left = 1.0
	_migration_corner_badge.anchor_top = 0.0
	_migration_corner_badge.anchor_right = 1.0
	_migration_corner_badge.anchor_bottom = 0.0
	_migration_corner_badge.offset_left = -210.0
	_migration_corner_badge.offset_top = 46.0
	_migration_corner_badge.offset_right = -12.0
	_migration_corner_badge.offset_bottom = 86.0
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
	badge_style.corner_radius_top_left = 8
	badge_style.corner_radius_top_right = 8
	badge_style.corner_radius_bottom_right = 8
	badge_style.corner_radius_bottom_left = 8
	badge_style.border_width_left = 2
	badge_style.border_width_top = 2
	badge_style.border_width_right = 2
	badge_style.border_width_bottom = 2
	badge_style.border_color = Color(0.35, 0.65, 1.0, 0.5)
	_migration_corner_badge.add_theme_stylebox_override("panel", badge_style)
	hud.add_child(_migration_corner_badge)
	hud.move_child(_migration_corner_badge, hud.get_child_count() - 1)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_migration_corner_badge.add_child(hbox)

	var spinner := Label.new()
	spinner.text = "*"
	spinner.add_theme_font_size_override("font_size", 18)
	spinner.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0, 1.0))
	hbox.add_child(spinner)

	_migration_corner_label = Label.new()
	_migration_corner_label.text = "Reconnecting..."
	_migration_corner_label.add_theme_font_size_override("font_size", 13)
	_migration_corner_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96, 0.95))
	hbox.add_child(_migration_corner_label)

func _show_migration_corner_badge() -> void:
	if _migration_corner_badge != null:
		_migration_corner_badge.show()

func _hide_migration_corner_badge() -> void:
	if _migration_corner_badge != null:
		_migration_corner_badge.hide()

# This function creates the client-side heartbeat timer that detects silent host death during migration-sensitive sessions.
func _ensure_host_keepalive_timer() -> void:
	if _host_keepalive_timer != null:
		return
	_host_keepalive_timer = Timer.new()
	_host_keepalive_timer.name = "HostKeepAliveTimer"
	_host_keepalive_timer.one_shot = false
	_host_keepalive_timer.wait_time = HOST_KEEPALIVE_INTERVAL
	_host_keepalive_timer.timeout.connect(_on_host_keepalive_timeout)
	add_child(_host_keepalive_timer)

func _show_network_loading(title: String, subtitle: String, progress_ratio: float) -> void:
	if _network_loading_overlay == null:
		return
	var was_hidden: bool = not _network_loading_overlay.visible
	_network_loading_overlay.visible = true
	_network_loading_title.text = title
	_network_loading_subtitle.text = subtitle
	if _network_loading_transport and _network_loading_transport.text.is_empty():
		_network_loading_transport.text = "Connecting via dedicated WebSocket..."
	_update_network_transport_badge(_network_loading_transport.text if _network_loading_transport else "")
	_network_loading_bar.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	if was_hidden:
		if _network_loading_tween != null:
			_network_loading_tween.kill()
		_network_loading_tween = create_tween()
		_network_loading_overlay.modulate.a = 0.0
		_network_loading_card.scale = Vector2(0.96, 0.96)
		_network_loading_tween.set_parallel(true)
		_network_loading_tween.tween_property(_network_loading_overlay, "modulate:a", 1.0, NETWORK_LOADING_TWEEN_SECONDS)
		_network_loading_tween.tween_property(_network_loading_card, "scale", Vector2.ONE, NETWORK_LOADING_TWEEN_SECONDS)

func _hide_network_loading() -> void:
	_host_last_pong_msec = Time.get_ticks_msec()
	if _network_loading_overlay:
		if _network_loading_tween != null:
			_network_loading_tween.kill()
		_network_loading_tween = create_tween()
		_network_loading_tween.set_parallel(true)
		_network_loading_tween.tween_property(_network_loading_overlay, "modulate:a", 0.0, NETWORK_LOADING_TWEEN_SECONDS)
		_network_loading_tween.tween_property(_network_loading_card, "scale", Vector2(0.97, 0.97), NETWORK_LOADING_TWEEN_SECONDS)
		_network_loading_tween.finished.connect(_finalize_hide_network_loading, CONNECT_ONE_SHOT)
	if _network_loading_transport:
		_network_loading_transport.text = ""
	if _network_loading_transport_badge:
		_network_loading_transport_badge.text = ""

func _finalize_hide_network_loading() -> void:
	if _network_loading_overlay != null:
		_network_loading_overlay.visible = false

func _on_transport_status_changed(message: String) -> void:
	if _network_loading_transport:
		_network_loading_transport.text = message
	_update_network_transport_badge(message)

# BUG FIX #4: Update the loading bar in real-time using progress from the parallel connect poller.
func _on_transport_progress_updated(phase: String, progress: float) -> void:
	# The server also expires reserved peers while MapManager downloads files.
	# Start at socket authentication, before either map download or construction.
	if phase == "auth" or phase == "map":
		_start_host_keepalive()
	if _network_loading_overlay == null or not _network_loading_overlay.visible:
		return
	var bar_value: float = 0.0
	match phase:
		"connecting":
			# Map 0..1 progress into the 0.28..0.90 bar range during connection
			bar_value = lerpf(0.28, 0.90, clampf(progress, 0.0, 1.0))
		"connected":
			bar_value = 0.95
		"failed":
			bar_value = 1.0
		_:
			bar_value = clampf(progress, 0.0, 1.0)
	if _network_loading_bar:
		var target_value: float = bar_value * 100.0
		var bar_tween := create_tween()
		bar_tween.tween_property(_network_loading_bar, "value", target_value, 0.12)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_on_game_menu_button_pressed()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_game_menu_panel) and _game_menu_panel.visible:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		# BUGFIX: desktop starts windowed; F11 toggles fullscreen explicitly.
		_toggle_fullscreen_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not (event is InputEventKey and (event as InputEventKey).echo):
		if _request_local_vehicle_spawn_from_pad():
			get_viewport().set_input_as_handled()
			return
		if _activate_nearest_roblox_proximity_prompt():
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _activate_roblox_click_detector(mouse_event.position):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.keycode == KEY_TAB:
		if event.pressed and not event.echo:
			_set_leaderboard_visible(not _is_runtime_player_list_visible())
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_on_game_menu_button_pressed()
		get_viewport().set_input_as_handled()

func _activate_nearest_roblox_proximity_prompt() -> bool:
	return preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd").activate_nearest_prompt(
		self, _get_local_player(), LuaScriptEngine, _perform_bobux_ai_interaction, _runtime_object_belongs_to_local_room)


func _activate_roblox_click_detector(screen_position: Vector2) -> bool:
	if _game_menu_panel != null and _game_menu_panel.visible:
		return false
	if _pointer_is_over_interactive_runtime_ui():
		return false
	return preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd").activate_click(
		get_viewport().get_camera_3d(), screen_position, self, _get_local_player(), LuaScriptEngine,
		_perform_bobux_ai_interaction, _runtime_object_belongs_to_local_room)


func _find_roblox_click_detector_near_hit(hit_node: Node) -> Node:
	var cursor := hit_node
	var depth := 0
	while cursor != null and depth < 8:
		if cursor.is_in_group("roblox_click_detectors"):
			return cursor
		var pending: Array[Node] = []
		for child in cursor.get_children():
			if child is Node:
				pending.append(child as Node)
		while not pending.is_empty():
			var candidate: Node = pending.pop_back()
			if candidate.is_in_group("roblox_click_detectors"):
				return candidate
			for child in candidate.get_children():
				if child is Node:
					pending.append(child as Node)
		cursor = cursor.get_parent()
		depth += 1
	return null


func _perform_bobux_ai_interaction(source: Node, actor: Node = null) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var interaction: Dictionary = source.get_meta("bobux_ai_interaction", {}) if source.get_meta("bobux_ai_interaction", {}) is Dictionary else {}
	var target: Node3D = null
	var cursor: Node = source
	while cursor != null:
		if cursor is Node3D and cursor.get_meta("bobux_ai_interaction", {}) is Dictionary and not (cursor.get_meta("bobux_ai_interaction", {}) as Dictionary).is_empty():
			target = cursor as Node3D
			interaction = (cursor.get_meta("bobux_ai_interaction", {}) as Dictionary).duplicate(true)
			break
		cursor = cursor.get_parent()
	if target == null or interaction.is_empty() or bool(target.get_meta("bobux_ai_interaction_busy", false)):
		return false
	var action := str(interaction.get("action", "toggle_effect"))
	match action:
		"toggle_effect":
			var changed := false
			var pending: Array[Node] = [target]
			while not pending.is_empty():
				var node: Node = pending.pop_back()
				for child in node.get_children():
					if child is Node:
						pending.append(child as Node)
				if node is GPUParticles3D and bool(node.get_meta("bobux_ai_component", false)):
					(node as GPUParticles3D).emitting = not (node as GPUParticles3D).emitting
					changed = true
				elif node is Light3D and bool(node.get_meta("bobux_ai_component", false)):
					(node as Light3D).visible = not (node as Light3D).visible
					changed = true
			return changed
		"collect":
			var local_player := _get_local_player()
			if local_player == null or (actor != null and actor != local_player):
				return false
			var inventory: Dictionary = LuaScriptEngine.get_local_inventory_state(self, local_player) if LuaScriptEngine != null and LuaScriptEngine.has_method("get_local_inventory_state") else {}
			var backpack: Node = inventory.get("backpack", null) as Node
			if backpack == null:
				return false
			var tool := RobloxDataModelClass.create_instance("Tool", target.name)
			tool.name = target.name
			tool.set_meta("roblox_class", "Tool")
			tool.set_meta("bobux_inventory_order", Time.get_ticks_msec())
			if target is MeshInstance3D:
				var handle := MeshInstance3D.new()
				handle.name = "Handle"
				handle.set_meta("roblox_class", "Part")
				handle.mesh = (target as MeshInstance3D).mesh.duplicate(true) if (target as MeshInstance3D).mesh != null else null
				handle.material_override = (target as MeshInstance3D).material_override
				tool.add_child(handle)
			backpack.add_child(tool)
			_refresh_runtime_inventory()
			target.set_meta("bobux_ai_interaction_busy", true)
			_queue_free_runtime_ai_target(target)
			return true
		"toggle_door":
			var is_open := bool(target.get_meta("bobux_door_open", false))
			if not target.has_meta("bobux_door_closed_position"):
				target.set_meta("bobux_door_closed_position", target.position)
			var closed_position: Vector3 = target.get_meta("bobux_door_closed_position", target.position)
			var open_distance := maxf(absf(target.global_basis.get_scale().y) + 0.35, 4.0)
			var destination := closed_position if is_open else closed_position + Vector3.UP * open_distance
			target.set_meta("bobux_ai_interaction_busy", true)
			if is_open:
				_set_runtime_ai_target_collision_enabled(target, true)
			var tween := target.create_tween()
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(target, "position", destination, 0.38)
			tween.finished.connect(func() -> void:
				if target == null or not is_instance_valid(target):
					return
				target.set_meta("bobux_door_open", not is_open)
				if not is_open:
					_set_runtime_ai_target_collision_enabled(target, false)
				target.set_meta("bobux_ai_interaction_busy", false)
			)
			return true
		"hide":
			target.visible = false
			_set_runtime_ai_target_collision_enabled(target, false)
			return true
		"destroy":
			target.set_meta("bobux_ai_interaction_busy", true)
			_queue_free_runtime_ai_target(target)
			return true
	return false


func _runtime_physics_body_for_visual(target: Node) -> RigidBody3D:
	if target == null or not target.has_meta("_bobux_physics_body_instance_id"):
		return null
	var body_object := instance_from_id(int(target.get_meta("_bobux_physics_body_instance_id", 0)))
	return body_object as RigidBody3D if body_object is RigidBody3D and is_instance_valid(body_object) else null


func _set_runtime_ai_target_collision_enabled(target: Node, enabled: bool) -> void:
	if target == null:
		return
	for descendant in target.find_children("*", "CollisionShape3D", true, false):
		if descendant is CollisionShape3D:
			(descendant as CollisionShape3D).set_deferred("disabled", not enabled)
	var physics_body := _runtime_physics_body_for_visual(target)
	if physics_body != null:
		for descendant in physics_body.find_children("*", "CollisionShape3D", true, false):
			if descendant is CollisionShape3D:
				(descendant as CollisionShape3D).set_deferred("disabled", not enabled)


func _queue_free_runtime_ai_target(target: Node) -> void:
	if target == null:
		return
	var physics_body := _runtime_physics_body_for_visual(target)
	if physics_body != null and not physics_body.is_queued_for_deletion():
		physics_body.call_deferred("queue_free")
	if not target.is_queued_for_deletion():
		target.call_deferred("queue_free")


func _on_bobux_ai_touch_interaction(body: Node, touch_area: Area3D) -> void:
	if touch_area == null or not is_instance_valid(touch_area):
		return
	var local_player := _get_local_player()
	if body == local_player:
		_perform_bobux_ai_interaction(touch_area, body)

func _nearest_node3d_ancestor(node: Node) -> Node3D:
	var cursor := node
	while cursor != null:
		if cursor is Node3D:
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null

func _runtime_object_belongs_to_local_room(node: Node) -> bool:
	var local_room_id := _get_effective_local_room_id().strip_edges()
	if local_room_id.is_empty():
		return true
	var cursor := node
	while cursor != null:
		var object_room_id := str(cursor.get_meta("room_id", "")).strip_edges()
		if not object_room_id.is_empty():
			return object_room_id == local_room_id
		cursor = cursor.get_parent()
	return true

func _pointer_is_over_interactive_runtime_ui() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton or control is LineEdit or control is TextEdit or control is ScrollContainer:
			return true
		control = control.get_parent() as Control
	return false

func _toggle_fullscreen_mode() -> void:
	var current_mode := DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_host_migrated(_new_host_id: int) -> void:
	# Seamless Roblox-style: no big overlay, just the small corner badge
	_show_migration_corner_badge()

# This function freezes the current scene while the room elects or reconnects to a replacement host.
# Seamless Roblox-style: gameplay freezes silently, only a small corner badge appears.
# CRITICAL: Do NOT clear session entities - we preserve all player nodes for no-death migration.
func _on_host_migration_started(_message: String, _became_host: bool) -> void:
	_stop_host_keepalive()
	_migration_peer_states.clear()
	_migration_local_state = {}
	_migration_locked_local_state = {}
	var local_player: CharacterBody3D = _get_local_player()
	var cached_local_peer_id: int = int(NetworkManager.get_cached_migration_local_peer_id()) if NetworkManager != null and NetworkManager.has_method("get_cached_migration_local_peer_id") else 0
	if local_player == null and cached_local_peer_id > 0 and players != null:
		local_player = players.get_node_or_null(str(cached_local_peer_id)) as CharacterBody3D
	if players != null:
		for child in players.get_children():
			if child is CharacterBody3D:
				var state: Dictionary = _build_character_runtime_state(child as CharacterBody3D)
				_migration_peer_states[child.name] = state
				if child == local_player:
					_migration_local_state = state.duplicate(true)
	if _migration_local_state.is_empty() and not _last_local_runtime_state.is_empty():
		_migration_local_state = _last_local_runtime_state.duplicate(true)
	_migration_locked_local_state = _migration_local_state.duplicate(true)
	if not _handover_payload_cache.is_empty():
		_apply_handover_world_state(_handover_payload_cache)

	if local_player != null:
		_migration_local_authority_before_handover = local_player.get_multiplayer_authority()
	elif cached_local_peer_id > 0:
		_migration_local_authority_before_handover = cached_local_peer_id
	_set_gameplay_frozen(true)
	if _migration_corner_label != null:
		_migration_corner_label.text = "Reconnecting..."
	_show_migration_corner_badge()

# This function unfreezes gameplay once the migration flow finishes and the replacement room is ready again.
# Uses resume_game_after_migration() for no-death authority handover instead of respawning.
func _on_host_migration_completed(became_host: bool) -> void:
	_handover_payload_cache.clear()
	_handover_target_peer_id = 0
	_handover_ready_peer_id = 0
	if became_host:
		_post_migration_guard_until_msec = Time.get_ticks_msec() + 4000
		_post_migration_guard_next_tick_msec = 0
		call_deferred("resume_game_after_migration")
	else:
		_post_migration_guard_until_msec = 0
		_post_migration_guard_next_tick_msec = 0
		_finish_migration_unfreeze(null)
	call_deferred("_schedule_post_migration_cleanup")
	if not NetworkManager.is_host():
		_start_host_keepalive()

func _schedule_post_migration_cleanup() -> void:
	await get_tree().create_timer(0.35).timeout
	_cleanup_stale_entities_after_migration()
	_dedupe_player_nodes()

# No-death authority handover: reassigns authority on existing player nodes
# instead of respawning them. This is the key to making migration invisible.
func resume_game_after_migration() -> void:
	var previous_local_peer_id: int = _migration_local_authority_before_handover
	if previous_local_peer_id <= 0 and NetworkManager.has_method("get_cached_migration_local_peer_id"):
		previous_local_peer_id = int(NetworkManager.get_cached_migration_local_peer_id())
	var migrated_local_player := _rebind_local_player_after_migration(previous_local_peer_id)
	migrated_local_player = _ensure_local_player_after_migration(migrated_local_player, previous_local_peer_id)
	if _migration_locked_local_state.is_empty() and not _migration_local_state.is_empty():
		_migration_locked_local_state = _migration_local_state.duplicate(true)
	if migrated_local_player != null and NetworkManager != null and NetworkManager.is_host():
		migrated_local_player = _recreate_local_host_player_via_spawner(migrated_local_player)
	if migrated_local_player != null and not _migration_locked_local_state.is_empty():
		_apply_character_runtime_state(migrated_local_player, _migration_locked_local_state)
		call_deferred("_apply_character_runtime_state_late", migrated_local_player.get_instance_id(), _migration_locked_local_state.duplicate(true))
		print("[Main][Migration] Restoring camera state: body_y=%s cam_x=%s cam_y=%s arm_pos=%s arm_len=%s" % [
			str(_migration_locked_local_state.get("body_y", "n/a")),
			str(_migration_locked_local_state.get("camera_x", "n/a")),
			str(_migration_locked_local_state.get("camera_pivot_y", "n/a")),
			str(_migration_locked_local_state.get("camera_arm_pos", "n/a")),
			str(_migration_locked_local_state.get("camera_distance", "n/a"))
		])
	if migrated_local_player != null:
		print("[Main][Migration] Local stabilized: node=%s authority=%d runtime_id=%d pos=%s" % [
			migrated_local_player.name,
			migrated_local_player.get_multiplayer_authority(),
			_get_runtime_local_peer_id(),
			str(migrated_local_player.global_position)
		])
	else:
		print("[Main][Migration] Local stabilization failed: no local player node found.")
	_finish_migration_unfreeze(migrated_local_player)
	_migration_local_authority_before_handover = 0
	_migration_local_state = {}
	print("[Main] Migration complete: authority transferred, no respawn.")

# This function captures transform, velocity, body yaw, and camera yaw/pitch so host migration can restore
# both position and look direction without the "respawned in place" feeling.
func _build_character_runtime_state(character: CharacterBody3D) -> Dictionary:
	if character == null:
		return {}
	var state: Dictionary = {
		"transform": character.transform,
		"velocity": character.velocity,
		"body_y": character.rotation.y
	}
	var visuals: Node3D = character.get_node_or_null("Visuals") as Node3D
	if visuals != null:
		state["visuals_y"] = visuals.rotation.y
	var camera_pivot: Node3D = character.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot != null:
		state["camera_pivot_pos"] = camera_pivot.position
		state["camera_x"] = camera_pivot.rotation.x
		state["camera_pivot_y"] = camera_pivot.rotation.y
	var spring_arm: SpringArm3D = character.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	if spring_arm != null:
		state["camera_distance"] = spring_arm.spring_length
		state["camera_arm_pos"] = spring_arm.position
	return state

# This function applies one captured runtime state back onto a character body, including camera yaw/pitch.
func _apply_character_runtime_state(character: CharacterBody3D, state: Dictionary) -> void:
	if character == null or state.is_empty():
		return
	if state.has("transform"):
		character.transform = state["transform"]
	if state.has("velocity"):
		character.velocity = state["velocity"]
	var visuals: Node3D = character.get_node_or_null("Visuals") as Node3D
	if visuals != null and state.has("visuals_y"):
		visuals.rotation.y = float(state["visuals_y"])
	var camera_pivot: Node3D = character.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot != null:
		if state.has("camera_pivot_pos"):
			camera_pivot.position = state["camera_pivot_pos"]
		if state.has("camera_x"):
			camera_pivot.rotation.x = float(state["camera_x"])
		if state.has("camera_pivot_y"):
			camera_pivot.rotation.y = float(state["camera_pivot_y"])
	var spring_arm: SpringArm3D = character.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	if spring_arm != null:
		if state.has("camera_distance"):
			spring_arm.spring_length = float(state["camera_distance"])
		if state.has("camera_arm_pos"):
			spring_arm.position = state["camera_arm_pos"]
	if state.has("body_y"):
		character.rotation.y = float(state["body_y"])
	elif state.has("camera_y"):
		# Backward compatibility for snapshots captured before body_y/camera_pivot_y were introduced.
		character.rotation.y = float(state["camera_y"])

# This function reapplies runtime pose one frame later so Player._ready() initialization
# (for example default local visual/camera setup) does not override migrated camera direction.
func _apply_character_runtime_state_late(character_instance_id: int, state: Dictionary) -> void:
	if character_instance_id <= 0 or state.is_empty():
		return
	await get_tree().process_frame
	var instance_obj: Object = instance_from_id(character_instance_id)
	if instance_obj == null or not is_instance_valid(instance_obj) or not (instance_obj is CharacterBody3D):
		return
	_apply_character_runtime_state(instance_obj as CharacterBody3D, state)

# This function applies the cached visual identity for one peer onto an already existing player node.
func _apply_peer_visual_identity_to_player(player: CharacterBody3D, peer_id: int) -> void:
	if player == null or peer_id <= 0:
		return
	var chosen_colors: Dictionary = peer_colors.get(peer_id, _get_current_colors())
	player.set("head_color", chosen_colors.get("head", GameState.DEFAULT_AVATAR_COLOR))
	player.set("torso_color", chosen_colors.get("torso", GameState.DEFAULT_AVATAR_COLOR))
	player.set("left_arm_color", chosen_colors.get("left_arm", GameState.DEFAULT_AVATAR_COLOR))
	player.set("right_arm_color", chosen_colors.get("right_arm", GameState.DEFAULT_AVATAR_COLOR))
	player.set("left_leg_color", chosen_colors.get("left_leg", GameState.DEFAULT_AVATAR_COLOR))
	player.set("right_leg_color", chosen_colors.get("right_leg", GameState.DEFAULT_AVATAR_COLOR))
	player.set("display_name", peer_usernames.get(peer_id, UserSession.username if UserSession.is_logged_in else "Player"))
	_apply_avatar_visuals_to_player(player, peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals()))

func _apply_avatar_visuals_to_player(player: CharacterBody3D, avatar_visuals: Dictionary) -> void:
	if player == null:
		return
	player.set("face_texture_path", str(avatar_visuals.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)))
	player.set("chest_badge_texture_path", str(avatar_visuals.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)))
	player.set("shirt_texture_path", str(avatar_visuals.get("shirt_texture_path", "")))
	player.set("pants_texture_path", str(avatar_visuals.get("pants_texture_path", "")))
	var equipped_items: Array = avatar_visuals.get("equipped_avatar_items", []) if avatar_visuals.get("equipped_avatar_items", []) is Array else []
	player.set("equipped_avatar_items", equipped_items.duplicate(true))
	if player.has_method("force_avatar_visual_refresh"):
		player.call_deferred("force_avatar_visual_refresh")
	elif player.has_method("_apply_avatar_visuals_if_needed"):
		player.call_deferred("_apply_avatar_visuals_if_needed")

# This function moves one peer's runtime state dictionary entries onto a new peer id during host migration.
func _move_peer_runtime_state(old_peer_id: int, new_peer_id: int) -> void:
	if old_peer_id <= 0 or new_peer_id <= 0 or old_peer_id == new_peer_id:
		return
	var sources: Array[Dictionary] = [peer_colors, peer_usernames, peer_user_ids, peer_avatar_visuals, _peer_checkpoint_positions]
	for source in sources:
		if source.has(old_peer_id):
			var value: Variant = source[old_peer_id]
			source.erase(new_peer_id)
			source[new_peer_id] = value
			source.erase(old_peer_id)
	
	if _migration_peer_states.has(str(old_peer_id)):
		var state_val = _migration_peer_states[str(old_peer_id)]
		_migration_peer_states[str(new_peer_id)] = state_val
		_migration_peer_states.erase(str(old_peer_id))

# This function reassigns the preserved local player node to peer 1 so the new host keeps the same body without respawning.
func _rebind_local_player_after_migration(previous_local_peer_id: int) -> CharacterBody3D:
	var preserved_player: CharacterBody3D = null
	if previous_local_peer_id > 0:
		preserved_player = players.get_node_or_null(str(previous_local_peer_id)) as CharacterBody3D
	var stale_host_player: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
		
	# ALWAYS move state because the node might be spawned AFTER this function returns!
	_move_peer_runtime_state(previous_local_peer_id, 1)
	peer_colors[1] = _get_current_colors()
	peer_usernames[1] = UserSession.username if UserSession.is_logged_in else "Player"
	peer_user_ids[1] = SupabaseClient.get_user_id()

	# Keep /Players/1 stable when possible: adopt existing host node and copy the preserved state into it.
	# This avoids transient "Node not found: .../Players/1/StateSynchronizer" replication path errors.
	if stale_host_player != null and preserved_player != null and stale_host_player != preserved_player:
		var preserved_state: Dictionary = _build_character_runtime_state(preserved_player)
		_apply_character_runtime_state(stale_host_player, preserved_state)
		_apply_peer_visual_identity_to_player(stale_host_player, 1)
		stale_host_player.set_multiplayer_authority(1, true)
		_refresh_player_camera_authority_mode(stale_host_player)
		if stale_host_player.has_method("_configure_state_synchronizer"):
			stale_host_player.call("_configure_state_synchronizer")
		if preserved_player.has_method("set_process"):
			preserved_player.set_process(false)
			preserved_player.set_physics_process(false)
		preserved_player.queue_free()
		return stale_host_player
	if stale_host_player == null and preserved_player != null and preserved_player.name != "1":
		var adopted_host_state: Dictionary = _build_character_runtime_state(preserved_player)
		var adopted_host: CharacterBody3D = _spawn_local_player_direct(1, adopted_host_state)
		if adopted_host != null:
			_apply_character_runtime_state(adopted_host, adopted_host_state)
			_apply_peer_visual_identity_to_player(adopted_host, 1)
			adopted_host.set_multiplayer_authority(1, true)
			_refresh_player_camera_authority_mode(adopted_host)
			if adopted_host.has_method("_configure_state_synchronizer"):
				adopted_host.call("_configure_state_synchronizer")
			preserved_player.queue_free()
			return adopted_host
	
	if preserved_player == null:
		var promoted_host: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
		return promoted_host
		
	if stale_host_player != null and stale_host_player != preserved_player:
		stale_host_player.name = "__stale_host_%d" % Time.get_ticks_msec()
	if preserved_player.name != "1":
		preserved_player.name = "1"
	_apply_peer_visual_identity_to_player(preserved_player, 1)
	preserved_player.set_multiplayer_authority(1, true)
	_refresh_player_camera_authority_mode(preserved_player)
	if preserved_player.has_method("_configure_state_synchronizer"):
		preserved_player.call("_configure_state_synchronizer")
	if stale_host_player != null and stale_host_player != preserved_player:
		stale_host_player.queue_free()

	return preserved_player

# This function force-stabilizes the local host body after migration so authority, transform, and camera remain usable.
func _ensure_local_player_after_migration(candidate: CharacterBody3D, previous_local_peer_id: int) -> CharacterBody3D:
	var local_player: CharacterBody3D = candidate
	if local_player == null:
		local_player = _get_local_player()
	if local_player == null and previous_local_peer_id > 0:
		local_player = players.get_node_or_null(str(previous_local_peer_id)) as CharacterBody3D
	if local_player == null:
		local_player = players.get_node_or_null("1") as CharacterBody3D
	if local_player == null:
		var fallback_state: Dictionary = _migration_local_state.duplicate(true)
		if fallback_state.is_empty() and not _migration_locked_local_state.is_empty():
			fallback_state = _migration_locked_local_state.duplicate(true)
		if fallback_state.is_empty() and not _last_local_runtime_state.is_empty():
			fallback_state = _last_local_runtime_state.duplicate(true)
		if fallback_state.is_empty() and _migration_peer_states.has("1") and _migration_peer_states["1"] is Dictionary:
			fallback_state = (_migration_peer_states["1"] as Dictionary).duplicate(true)
		local_player = _spawn_local_player_direct(1, fallback_state)
	if local_player == null:
		return null

	var existing_host_node: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
	if local_player.name != "1":
		if existing_host_node != null and existing_host_node != local_player:
			var fallback_state_from_local: Dictionary = _build_character_runtime_state(local_player)
			_apply_character_runtime_state(existing_host_node, fallback_state_from_local)
			_apply_peer_visual_identity_to_player(existing_host_node, 1)
			existing_host_node.set_multiplayer_authority(1, true)
			_refresh_player_camera_authority_mode(existing_host_node)
			if existing_host_node.has_method("_configure_state_synchronizer"):
				existing_host_node.call("_configure_state_synchronizer")
			local_player.queue_free()
			local_player = existing_host_node
		else:
			var replacement_state: Dictionary = _build_character_runtime_state(local_player)
			var replacement_host: CharacterBody3D = _spawn_local_player_direct(1, replacement_state)
			if replacement_host != null and replacement_host != local_player:
				_apply_character_runtime_state(replacement_host, replacement_state)
				_apply_peer_visual_identity_to_player(replacement_host, 1)
				replacement_host.set_multiplayer_authority(1, true)
				_refresh_player_camera_authority_mode(replacement_host)
				if replacement_host.has_method("_configure_state_synchronizer"):
					replacement_host.call("_configure_state_synchronizer")
				local_player.queue_free()
				local_player = replacement_host
			else:
				local_player.name = "1"
	if existing_host_node != null and existing_host_node != local_player and existing_host_node.name.begins_with("__stale_host_"):
		existing_host_node.queue_free()
	_apply_peer_visual_identity_to_player(local_player, 1)
	local_player.set_multiplayer_authority(1, true)
	_refresh_player_camera_authority_mode(local_player)
	if local_player.has_method("_configure_state_synchronizer"):
		local_player.call("_configure_state_synchronizer")

	var previous_state_key: String = str(previous_local_peer_id)
	if previous_local_peer_id > 0 and _migration_peer_states.has(previous_state_key) and not _migration_peer_states.has("1"):
		_migration_peer_states["1"] = _migration_peer_states[previous_state_key]
		_migration_peer_states.erase(previous_state_key)
	if _migration_peer_states.has("1"):
		var state: Dictionary = _migration_peer_states["1"]
		_apply_character_runtime_state(local_player, state)
		_migration_peer_states.erase("1")
	return local_player

# This function creates one local emergency player node directly (without MultiplayerSpawner)
# so host migration can recover even if the spawner already purged replicated nodes.
func _spawn_local_player_direct(peer_id: int, state: Dictionary = {}) -> CharacterBody3D:
	if players == null or peer_id <= 0:
		return null
	var existing_player: CharacterBody3D = players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if existing_player != null:
		return existing_player
	var player_instance: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	player_instance.name = str(peer_id)
	player_instance.set_multiplayer_authority(peer_id, true)
	var initial_spawn_position: Vector3 = _get_spawn_position_for_peer(peer_id)
	player_instance.position = initial_spawn_position
	if player_instance.has_method("assign_network_room") and NetworkManager != null and NetworkManager.has_method("get_peer_room_id"):
		player_instance.call("assign_network_room", NetworkManager.get_peer_room_id(peer_id))
	if state.has("transform"):
		player_instance.transform = state["transform"]

	var chosen_colors: Dictionary = peer_colors.get(peer_id, _get_current_colors())
	player_instance.set("head_color", chosen_colors.get("head", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("torso_color", chosen_colors.get("torso", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("left_arm_color", chosen_colors.get("left_arm", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("right_arm_color", chosen_colors.get("right_arm", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("left_leg_color", chosen_colors.get("left_leg", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("right_leg_color", chosen_colors.get("right_leg", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("display_name", peer_usernames.get(peer_id, UserSession.username if UserSession.is_logged_in else "Player"))
	_apply_avatar_visuals_to_player(player_instance, peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals()))
	if player_instance.has_method("apply_movement_settings"):
		player_instance.call("apply_movement_settings", _get_room_player_settings(_get_peer_room_id(peer_id)))
	if player_instance.has_method("set_initial_spawn_position"):
		player_instance.call("set_initial_spawn_position", initial_spawn_position)
	if _peer_checkpoint_positions.has(peer_id) and player_instance.has_method("restore_checkpoint_state"):
		player_instance.call("restore_checkpoint_state", _peer_checkpoint_positions[peer_id])

	players.add_child(player_instance)
	_apply_network_sync_rate(player_instance)
	if player_instance.has_method("refresh_camera_authority_mode"):
		player_instance.call_deferred("refresh_camera_authority_mode")
	_apply_character_runtime_state(player_instance, state)
	call_deferred("_apply_character_runtime_state_late", player_instance.get_instance_id(), state.duplicate(true))
	return player_instance

# This function rebuilds the local promoted host node through MultiplayerSpawner so SceneMultiplayer
# keeps a valid /Players/1/StateSynchronizer path for late joiners after migration.
func _recreate_local_host_player_via_spawner(local_player: CharacterBody3D) -> CharacterBody3D:
	if local_player == null or players == null:
		return local_player
	if NetworkManager == null or not NetworkManager.is_host():
		return local_player
	var local_state: Dictionary = _build_character_runtime_state(local_player)
	_migration_peer_states["1"] = local_state.duplicate(true)
	_apply_peer_visual_identity_to_player(local_player, 1)
	local_player.free()
	_spawn_player_for_peer(1)
	var recreated: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
	if recreated == null:
		recreated = _spawn_local_player_direct(1, local_state)
	if recreated != null:
		_apply_character_runtime_state(recreated, local_state)
		call_deferred("_apply_character_runtime_state_late", recreated.get_instance_id(), local_state.duplicate(true))
		recreated.set_multiplayer_authority(1, true)
		_refresh_player_camera_authority_mode(recreated)
		if recreated.has_method("_configure_state_synchronizer"):
			recreated.call("_configure_state_synchronizer")
	return recreated

# This function force-resumes gameplay, input, and camera ownership after migration even if the promotion path only partially completed.
func _finish_migration_unfreeze(current_player: CharacterBody3D) -> void:
	_set_gameplay_frozen(false)
	get_tree().paused = false
	_hide_migration_corner_badge()
	_hide_network_loading()
	set_process(true)
	set_physics_process(true)
	var local_player: CharacterBody3D = current_player
	if local_player == null:
		local_player = _get_local_player()
	if local_player == null and NetworkManager != null and NetworkManager.is_host():
		local_player = _ensure_local_player_after_migration(null, _migration_local_authority_before_handover)
	if local_player != null:
		local_player.set_process(true)
		local_player.set_physics_process(true)
		_refresh_player_camera_authority_mode(local_player)
		var camera: Camera3D = local_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if camera != null:
			camera.current = true
		var label: Label3D = local_player.get_node_or_null("Visuals/NameLabel") as Label3D
		if label != null:
			label.visible = false
		fallback_camera.current = false
		_restore_mouse_mode_after_migration(local_player)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if NetworkManager != null and NetworkManager.is_host():
		_post_migration_guard_until_msec = maxi(_post_migration_guard_until_msec, Time.get_ticks_msec() + 3000)
		_post_migration_guard_next_tick_msec = 0

# This function keeps the newly promoted host stable for a short window so late disconnect callbacks
# cannot steal camera/input ownership or delete the local authority body.
func _poll_post_migration_stabilizer() -> void:
	if _post_migration_guard_until_msec <= 0:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec >= _post_migration_guard_until_msec:
		var settled_local_player: CharacterBody3D = _get_local_player()
		if settled_local_player != null:
			_last_local_runtime_state = _build_character_runtime_state(settled_local_player)
		_migration_locked_local_state = {}
		_post_migration_guard_until_msec = 0
		_post_migration_guard_next_tick_msec = 0
		return
	if now_msec < _post_migration_guard_next_tick_msec:
		return
	_post_migration_guard_next_tick_msec = now_msec + 120
	if NetworkManager == null or not NetworkManager.is_host():
		return
	if NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return
	_set_gameplay_frozen(false)
	get_tree().paused = false
	var local_player: CharacterBody3D = _get_local_player()
	if local_player == null:
		local_player = _ensure_local_player_after_migration(null, _migration_local_authority_before_handover)
		if local_player != null:
			print("[Main][Migration] Guard restored local authority body.")
	if local_player != null:
		local_player.set_process(true)
		local_player.set_physics_process(true)
		local_player.set_process_input(true)
		local_player.set_process_unhandled_input(true)
		local_player.set_process_unhandled_key_input(true)
		_refresh_player_camera_authority_mode(local_player)
		if not _migration_locked_local_state.is_empty():
			_apply_character_runtime_state(local_player, _migration_locked_local_state)
		elif not _last_local_runtime_state.is_empty():
			_apply_character_runtime_state(local_player, _last_local_runtime_state)
		var camera: Camera3D = local_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if camera != null:
			camera.current = true
		fallback_camera.current = false
		_restore_mouse_mode_after_migration(local_player)

# This function keeps one recent authoritative snapshot of the local player transform/velocity/camera,
# so host migration can recover position even if the spawner briefly deletes the node.
func _capture_local_runtime_state_snapshot() -> void:
	if players == null:
		return
	if NetworkManager != null and NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return
	if _post_migration_guard_until_msec > 0 and not _migration_locked_local_state.is_empty():
		return
	var local_player: CharacterBody3D = _get_local_player()
	if local_player == null:
		return
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	var authority_id: int = local_player.get_multiplayer_authority()
	var authority_matches_local: bool = runtime_local_peer_id > 0 and authority_id == runtime_local_peer_id
	var authority_matches_promoted_host: bool = NetworkManager != null and NetworkManager.is_host() and authority_id == 1
	if not authority_matches_local and not authority_matches_promoted_host:
		return
	_last_local_runtime_state = _build_character_runtime_state(local_player)

# This function restores local cursor mode after migration using player state (shift-lock / first-person).
func _restore_mouse_mode_after_migration(local_player: CharacterBody3D) -> void:
	if local_player != null and local_player.has_method("restore_mouse_mode_after_network_handover"):
		local_player.call("restore_mouse_mode_after_network_handover")
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _cleanup_stale_entities_after_migration() -> void:
	if players == null:
		return
	if multiplayer.multiplayer_peer == null:
		return
	var local_player_node: CharacterBody3D = _get_local_player()
	var keep_host_peer_one: bool = NetworkManager != null and NetworkManager.is_host()
	var live_peer_ids: Dictionary = {}
	for peer_id_variant in multiplayer.get_peers():
		live_peer_ids[int(peer_id_variant)] = true
	var local_peer_id: int = _get_runtime_local_peer_id()
	if local_peer_id > 0:
		live_peer_ids[local_peer_id] = true
	for child in players.get_children():
		if not (child is CharacterBody3D):
			continue
		if local_player_node != null and child == local_player_node:
			continue
		var peer_id: int = _extract_peer_id_from_player(child as CharacterBody3D)
		if peer_id <= 0:
			continue
		if keep_host_peer_one and peer_id == 1:
			continue
		if live_peer_ids.has(peer_id):
			continue
		child.queue_free()
	for state_dict in [peer_colors, peer_usernames, peer_user_ids, peer_avatar_visuals, _peer_checkpoint_positions]:
		var stale_keys: Array = []
		for key_variant in state_dict.keys():
			var peer_id: int = int(key_variant)
			if peer_id <= 0 or live_peer_ids.has(peer_id):
				continue
			if keep_host_peer_one and peer_id == 1:
				continue
			stale_keys.append(key_variant)
		for key_variant in stale_keys:
			state_dict.erase(key_variant)
	_dedupe_player_nodes()

func _poll_duplicate_player_guard() -> void:
	if players == null:
		return
	if NetworkManager != null and NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_duplicate_player_guard_msec:
		return
	_next_duplicate_player_guard_msec = now_msec + DUPLICATE_PLAYER_GUARD_INTERVAL_MSEC
	_dedupe_player_nodes()

func _dedupe_player_nodes() -> void:
	if players == null:
		return
	var preferred_by_peer: Dictionary = {}
	var duplicates_to_free: Array[CharacterBody3D] = []
	var duplicate_peer_ids_by_user: Array[int] = []
	for child in players.get_children():
		if not (child is CharacterBody3D):
			continue
		var character: CharacterBody3D = child as CharacterBody3D
		var peer_id: int = _extract_peer_id_from_player(character)
		if peer_id <= 0:
			continue
		if not preferred_by_peer.has(peer_id):
			preferred_by_peer[peer_id] = character
			continue
		var current_preferred: CharacterBody3D = preferred_by_peer[peer_id] as CharacterBody3D
		var keep_candidate: CharacterBody3D = _choose_preferred_player_node(peer_id, current_preferred, character)
		var remove_candidate: CharacterBody3D = character if keep_candidate == current_preferred else current_preferred
		preferred_by_peer[peer_id] = keep_candidate
		if remove_candidate != null:
			duplicates_to_free.append(remove_candidate)
	for peer_id_variant in preferred_by_peer.keys():
		var peer_id: int = int(peer_id_variant)
		var preferred: CharacterBody3D = preferred_by_peer[peer_id_variant] as CharacterBody3D
		if preferred == null:
			continue
		var changed_name: bool = preferred.name != str(peer_id)
		var changed_authority: bool = preferred.get_multiplayer_authority() != peer_id
		if preferred.name != str(peer_id):
			preferred.name = str(peer_id)
		if changed_authority:
			preferred.set_multiplayer_authority(peer_id, true)
		if changed_name or changed_authority:
			_apply_peer_visual_identity_to_player(preferred, peer_id)
		if changed_authority and preferred.has_method("_configure_state_synchronizer"):
			preferred.call("_configure_state_synchronizer")
	# Second pass: collapse stale clones that may carry different peer IDs but the same cloud user_id.
	# This can happen during migration handover windows and looks like a "ghost player".
	var preferred_by_user: Dictionary = {}
	for child in players.get_children():
		if not (child is CharacterBody3D):
			continue
		var character: CharacterBody3D = child as CharacterBody3D
		var peer_id: int = _extract_peer_id_from_player(character)
		if peer_id <= 0:
			continue
		var user_id: String = str(peer_user_ids.get(peer_id, "")).strip_edges().to_lower()
		if user_id.is_empty():
			continue
		if not preferred_by_user.has(user_id):
			preferred_by_user[user_id] = character
			continue
		var current_preferred: CharacterBody3D = preferred_by_user[user_id] as CharacterBody3D
		var keep_candidate: CharacterBody3D = _choose_preferred_player_node_for_user(current_preferred, character)
		var remove_candidate: CharacterBody3D = character if keep_candidate == current_preferred else current_preferred
		preferred_by_user[user_id] = keep_candidate
		if remove_candidate != null and not duplicates_to_free.has(remove_candidate):
			duplicates_to_free.append(remove_candidate)
			var remove_peer_id: int = _extract_peer_id_from_player(remove_candidate)
			if remove_peer_id > 0 and not duplicate_peer_ids_by_user.has(remove_peer_id):
				duplicate_peer_ids_by_user.append(remove_peer_id)
	for stale_peer_id in duplicate_peer_ids_by_user:
		peer_colors.erase(stale_peer_id)
		peer_usernames.erase(stale_peer_id)
		peer_user_ids.erase(stale_peer_id)
		peer_avatar_visuals.erase(stale_peer_id)
		_peer_checkpoint_positions.erase(stale_peer_id)
	if not duplicates_to_free.is_empty():
		print("[Main][Dedup] Removing %d duplicate player node(s)." % duplicates_to_free.size())
	for duplicate_node in duplicates_to_free:
		if duplicate_node == null or not is_instance_valid(duplicate_node):
			continue
		if duplicate_node.has_method("set_process"):
			duplicate_node.set_process(false)
			duplicate_node.set_physics_process(false)
		duplicate_node.queue_free()

func _extract_peer_id_from_player(player: CharacterBody3D) -> int:
	if player == null:
		return 0
	var authority_id: int = player.get_multiplayer_authority()
	if authority_id > 0:
		return authority_id
	var name_id: int = int(player.name)
	if name_id > 0:
		return name_id
	return 0

func _find_player_node_by_peer_id(peer_id: int) -> CharacterBody3D:
	if players == null or peer_id <= 0:
		return null
	var canonical: CharacterBody3D = players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if canonical != null:
		return canonical
	for child in players.get_children():
		if not (child is CharacterBody3D):
			continue
		var character: CharacterBody3D = child as CharacterBody3D
		if _extract_peer_id_from_player(character) == peer_id:
			return character
	return null

func _choose_preferred_player_node(peer_id: int, first: CharacterBody3D, second: CharacterBody3D) -> CharacterBody3D:
	if first == null:
		return second
	if second == null:
		return first
	var canonical_name: String = str(peer_id)
	var first_name_match: bool = first.name == canonical_name
	var second_name_match: bool = second.name == canonical_name
	if first_name_match != second_name_match:
		return first if first_name_match else second
	var first_camera: Camera3D = first.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	var second_camera: Camera3D = second.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	var first_camera_current: bool = first_camera != null and first_camera.current
	var second_camera_current: bool = second_camera != null and second_camera.current
	if first_camera_current != second_camera_current:
		return first if first_camera_current else second
	return first

func _is_peer_id_live_for_session(peer_id: int) -> bool:
	if peer_id <= 0:
		return false
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0 and peer_id == runtime_local_peer_id:
		return true
	if multiplayer.multiplayer_peer == null:
		return false
	for peer_id_variant in multiplayer.get_peers():
		if int(peer_id_variant) == peer_id:
			return true
	return false

func _wait_for_peer_disconnect_settle(peer_id: int, max_frames: int = 12) -> void:
	if peer_id <= 0:
		return
	var remaining_frames: int = maxi(max_frames, 1)
	while remaining_frames > 0 and (_is_peer_id_live_for_session(peer_id) or _find_player_node_by_peer_id(peer_id) != null):
		await get_tree().process_frame
		remaining_frames -= 1

func _choose_preferred_player_node_for_user(first: CharacterBody3D, second: CharacterBody3D) -> CharacterBody3D:
	if first == null:
		return second
	if second == null:
		return first
	var first_peer_id: int = _extract_peer_id_from_player(first)
	var second_peer_id: int = _extract_peer_id_from_player(second)
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if first_peer_id == runtime_local_peer_id and second_peer_id != runtime_local_peer_id:
		return first
	if second_peer_id == runtime_local_peer_id and first_peer_id != runtime_local_peer_id:
		return second
	var first_live: bool = _is_peer_id_live_for_session(first_peer_id)
	var second_live: bool = _is_peer_id_live_for_session(second_peer_id)
	if first_live != second_live:
		return first if first_live else second
	if first_peer_id == 1 and second_peer_id != 1:
		return first
	if second_peer_id == 1 and first_peer_id != 1:
		return second
	return first if first_peer_id <= second_peer_id else second


func _update_network_transport_badge(message: String) -> void:
	if _network_loading_transport_badge == null:
		return
	var lower_message: String = message.strip_edges().to_lower()
	if lower_message.find("websocket") >= 0 or lower_message.find("dedicated") >= 0 or lower_message.find("room") >= 0 or lower_message.find("socket") >= 0 or lower_message.find("connecting") >= 0:
		_network_loading_transport_badge.text = "Transport: Dedicated WebSocket"
	else:
		_network_loading_transport_badge.text = ""

# This function toggles the lightweight gameplay freeze used during host migration without pausing network processing.
func _set_gameplay_frozen(is_frozen: bool) -> void:
	GameState.network_gameplay_frozen = is_frozen

func _ensure_mode_music_player() -> void:
	if _mode_music_player != null:
		return
	_mode_music_player = AudioStreamPlayer.new()
	_mode_music_player.name = "ModeMusicPlayer"
	_mode_music_player.bus = "Master"
	_mode_music_player.finished.connect(_on_mode_music_finished)
	add_child(_mode_music_player)

func _get_local_player() -> CharacterBody3D:
	if players == null:
		return null
	if not _is_runtime_multiplayer_query_safe():
		var cached_local_peer_id: int = int(NetworkManager.get_cached_migration_local_peer_id()) if NetworkManager != null and NetworkManager.has_method("get_cached_migration_local_peer_id") else 0
		if cached_local_peer_id > 0:
			var cached_by_id: CharacterBody3D = players.get_node_or_null(str(cached_local_peer_id)) as CharacterBody3D
			if cached_by_id != null:
				return cached_by_id
		if NetworkManager != null and NetworkManager.is_host():
			return players.get_node_or_null("1") as CharacterBody3D
		return null
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0:
		var local_by_id: CharacterBody3D = players.get_node_or_null(str(runtime_local_peer_id)) as CharacterBody3D
		if local_by_id != null:
			return local_by_id
	for child in players.get_children():
		if child is CharacterBody3D and child.is_multiplayer_authority():
			return child as CharacterBody3D
	return null

func _is_runtime_multiplayer_query_safe() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return false
	var status: MultiplayerPeer.ConnectionStatus = peer.get_connection_status()
	return status == MultiplayerPeer.CONNECTION_CONNECTED

func _get_runtime_local_peer_id() -> int:
	var cached_peer_id: int = int(NetworkManager.get_cached_migration_local_peer_id()) if NetworkManager != null and NetworkManager.has_method("get_cached_migration_local_peer_id") else 0
	if NetworkManager != null and NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return cached_peer_id
	if not _is_runtime_multiplayer_query_safe():
		return cached_peer_id
	if multiplayer.multiplayer_peer == null:
		return cached_peer_id
	var runtime_peer_id: int = multiplayer.get_unique_id()
	if runtime_peer_id > 0:
		return runtime_peer_id
	if cached_peer_id > 0:
		return cached_peer_id
	if NetworkManager != null and NetworkManager.has_method("get_cached_migration_local_peer_id"):
		return int(NetworkManager.get_cached_migration_local_peer_id())
	return 0

func _update_local_player_hud() -> void:
	if _health_bar == null or _respawn_button == null:
		return
	var local_player := _get_local_player()
	if local_player == null:
		_health_bar.value = 0.0
		_respawn_button.disabled = true
		return
	_respawn_button.disabled = false
	var health := int(local_player.call("get_health")) if local_player.has_method("get_health") else 100
	var max_health := int(local_player.call("get_max_health")) if local_player.has_method("get_max_health") else 100
	_health_bar.max_value = max_health
	_health_bar.value = clampi(health, 0, max_health)

func _update_ping_indicator() -> void:
	if _ping_label == null:
		return
	if multiplayer.multiplayer_peer == null:
		_ping_label.text = "Ping: --"
		return
	if NetworkManager != null and NetworkManager.is_host():
		_ping_label.text = "Ping: Host"
		return
	if _last_ping_rtt_msec >= 0:
		_ping_label.text = "Ping: %d ms" % _last_ping_rtt_msec
	elif _host_last_pong_msec > 0 and (Time.get_ticks_msec() - _host_last_pong_msec) < int(HOST_KEEPALIVE_TIMEOUT_SECONDS * 1000.0):
		_ping_label.text = "Ping: Live"
	else:
		_ping_label.text = "Ping: ..."

func _on_respawn_pressed() -> void:
	var local_player := _get_local_player()
	if is_instance_valid(local_player) and local_player.has_method("force_respawn"):
		local_player.force_respawn()
	else:
		request_authoritative_respawn_for_local_player()
	close_game_menu()

func request_authoritative_respawn_for_local_player() -> void:
	var local_peer_id: int = _get_runtime_local_peer_id()
	if local_peer_id <= 0 or multiplayer.multiplayer_peer == null:
		var local_player := _get_local_player()
		if is_instance_valid(local_player) and local_player.has_method("respawn_at_checkpoint"):
			local_player.respawn_at_checkpoint()
		return
	if multiplayer.is_server():
		_perform_authoritative_respawn_for_peer(local_peer_id)
		return
	rpc_id(1, "_request_player_respawn", local_peer_id)

@rpc("any_peer", "call_local", "reliable")
func _request_player_respawn(requested_peer_id: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if requested_peer_id > 0 and requested_peer_id != sender_id:
		push_warning("[RoomHub] Rejecting respawn request spoof from peer %d for peer %d." % [sender_id, requested_peer_id])
		return
	# AUDIT FIX VULN-1: Verify the sender is in the same room before respawning.
	if NetworkManager != null and NetworkManager.has_method("get_peer_room_id"):
		var sender_room_id: String = str(NetworkManager.get_peer_room_id(sender_id)).strip_edges()
		if sender_room_id.is_empty():
			push_warning("[RoomHub] Rejecting respawn for peer %d with no room assignment." % sender_id)
			return
	_perform_authoritative_respawn_for_peer(sender_id)

func _perform_authoritative_respawn_for_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	var payload: Dictionary = _build_authoritative_respawn_payload(peer_id)
	if payload.is_empty():
		return
	if peer_id == _get_runtime_local_peer_id():
		_apply_authoritative_respawn(payload)
		return
	_apply_authoritative_respawn.rpc_id(peer_id, payload)

func _build_authoritative_respawn_payload(peer_id: int) -> Dictionary:
	if peer_id <= 0:
		return {}
	var has_checkpoint: bool = _peer_checkpoint_positions.has(peer_id)
	var respawn_position: Vector3 = _peer_checkpoint_positions[peer_id] if has_checkpoint else _get_spawn_info_for_peer(peer_id).get("position", Vector3.ZERO)
	return {
		"peer_id": peer_id,
		"position": respawn_position,
		"has_checkpoint": has_checkpoint
	}

@rpc("authority", "call_local", "reliable")
func _apply_authoritative_respawn(payload: Dictionary) -> void:
	var peer_id: int = int(payload.get("peer_id", _get_runtime_local_peer_id()))
	if peer_id <= 0:
		return
	var player_node: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if player_node == null and peer_id == _get_runtime_local_peer_id():
		player_node = _get_local_player()
	if player_node == null or not player_node.has_method("apply_authoritative_respawn_position"):
		return
	var respawn_position: Vector3 = payload.get("position", player_node.global_position)
	var has_checkpoint: bool = bool(payload.get("has_checkpoint", false))
	if has_checkpoint:
		_peer_checkpoint_positions[peer_id] = respawn_position
	else:
		_peer_checkpoint_positions.erase(peer_id)
	var room_id := _get_peer_room_id(peer_id)
	player_node.call("apply_authoritative_respawn_position", _server_to_local_room_position(respawn_position, room_id), has_checkpoint)

func _on_game_menu_button_pressed() -> void:
	if _game_menu_panel == null:
		return
	var next_visible := not _game_menu_panel.visible
	if next_visible:
		var local_player := _get_local_player()
		if is_instance_valid(local_player): local_player.set_meta("bobux_system_menu_open", true)
		if is_instance_valid(_runtime_inventory_controller):
			_runtime_inventory_controller.call("set_system_menu_open", true)
		var chat_box := get_node_or_null("ChatBox")
		if chat_box and chat_box.has_method("close_chat_panel"):
			chat_box.call("close_chat_panel")
		_set_runtime_top_hud_visible(false)
		_next_friend_status_refresh_msec = 0
		_refresh_escape_menu_player_rows()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_game_menu_panel.visible = true
		_game_menu_panel.position.y = -get_viewport().get_visible_rect().size.y
		var mobile_runtime = get_node_or_null("/root/MobileRuntime")
		if mobile_runtime != null:
			mobile_runtime.call("set_gameplay_touch_controls_enabled", false)
		if is_instance_valid(_game_menu_tween): _game_menu_tween.kill()
		_game_menu_tween = create_tween()
		_game_menu_tween.set_trans(Tween.TRANS_QUART)
		_game_menu_tween.set_ease(Tween.EASE_OUT)
		_game_menu_tween.tween_property(_game_menu_panel, "position:y", 0.0, 0.22)
	else:
		close_game_menu()

func close_game_menu() -> void:
	if not is_instance_valid(_game_menu_panel):
		return
	if is_instance_valid(_game_menu_tween): _game_menu_tween.kill()
	var tween := create_tween()
	_game_menu_tween = tween
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_game_menu_panel, "position:y", -get_viewport().get_visible_rect().size.y, 0.16)
	tween.tween_callback(func():
		if is_instance_valid(_game_menu_panel):
			_game_menu_panel.visible = false
			_game_menu_panel.position.y = 0.0
			var local_player := _get_local_player()
			if is_instance_valid(local_player): local_player.set_meta("bobux_system_menu_open", false)
			if is_instance_valid(_runtime_inventory_controller):
				_runtime_inventory_controller.call("set_system_menu_open", false)
			_set_runtime_top_hud_visible(true)
			var mobile_runtime = get_node_or_null("/root/MobileRuntime")
			if mobile_runtime != null and bool(mobile_runtime.call("is_mobile_beta")):
				mobile_runtime.call("set_gameplay_touch_controls_enabled", true)
	)

func _make_escape_menu_tab_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(130.0, 54.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.28, 0.31, 0.38, 0.94)
	normal.corner_radius_top_left = 5
	normal.corner_radius_top_right = 5
	normal.corner_radius_bottom_right = 5
	normal.corner_radius_bottom_left = 5
	var hover := normal.duplicate()
	hover.bg_color = Color(0.36, 0.4, 0.48, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _set_escape_menu_page(page_name: String) -> void:
	if _escape_menu_players_page != null:
		_escape_menu_players_page.visible = page_name == "players"
	if _escape_menu_settings_page != null:
		_escape_menu_settings_page.visible = page_name == "settings"

func _refresh_escape_menu_player_rows() -> void:
	if _escape_menu_player_rows == null:
		return
	for child in _escape_menu_player_rows.get_children():
		child.queue_free()
	for peer_id in _get_sorted_leaderboard_peer_ids():
		_escape_menu_player_rows.add_child(_build_escape_menu_player_row(peer_id))

func _build_escape_menu_player_row(peer_id: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 64.0)
	row.add_theme_constant_override("separation", 14)
	var username: String = str(peer_usernames.get(peer_id, UserSession.username if _is_local_leaderboard_peer(peer_id) and UserSession.is_logged_in else "Player")).strip_edges()
	var name_label := Label.new()
	name_label.text = username
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(name_label)
	_attach_runtime_account_badges(name_label, peer_id)
	var view_button := Button.new()
	view_button.text = "View"
	view_button.custom_minimum_size = Vector2(120.0, 40.0)
	view_button.focus_mode = Control.FOCUS_NONE
	row.add_child(view_button)
	var user_id: String = _get_user_id_for_leaderboard_peer(peer_id)
	if _is_local_leaderboard_peer(peer_id):
		var self_label := Label.new()
		self_label.text = "You"
		self_label.custom_minimum_size = Vector2(150.0, 40.0)
		self_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		self_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		self_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.9))
		row.add_child(self_label)
	elif _is_friend_user_id(user_id):
		var friends_label := Label.new()
		friends_label.text = "Friends"
		friends_label.custom_minimum_size = Vector2(150.0, 40.0)
		friends_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		friends_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		friends_label.add_theme_color_override("font_color", Color(0.42, 0.95, 0.58, 1.0))
		row.add_child(friends_label)
	else:
		var friend_button := Button.new()
		friend_button.text = "Add Friend"
		friend_button.custom_minimum_size = Vector2(150.0, 40.0)
		friend_button.focus_mode = Control.FOCUS_NONE
		friend_button.pressed.connect(func(): _on_leaderboard_player_pressed(peer_id))
		row.add_child(friend_button)
	return row

func _sync_master_volume_slider() -> void:
	if _master_volume_slider == null:
		return
	var master_bus := AudioServer.get_bus_index("Master")
	var current_db := AudioServer.get_bus_volume_db(master_bus)
	var current_linear := db_to_linear(current_db)
	_master_volume_slider.set_value_no_signal(roundf(current_linear * 100.0))

func _on_master_volume_changed(value: float) -> void:
	ClientPreferences.update("volume", clampf(value / 100.0, 0.0, 1.0))

func _add_mobile_controls_settings_if_needed(parent: VBoxContainer) -> void:
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	if parent == null or mobile_runtime == null or not mobile_runtime.has_method("is_mobile_beta") or not bool(mobile_runtime.call("is_mobile_beta")):
		return
	if not mobile_runtime.has_method("get_control_settings") or not mobile_runtime.has_method("update_control_settings"):
		return
	var settings: Dictionary = mobile_runtime.call("get_control_settings")
	var section_label := Label.new()
	section_label.text = "Mobile controls"
	section_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	section_label.add_theme_font_size_override("font_size", 18)
	parent.add_child(section_label)
	_add_mobile_control_option(
		parent,
		mobile_runtime,
		settings,
		"Joystick mode",
		"joystick_mode",
		["Fixed", "Dynamic", "Following"]
	)
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Joystick deadzone", "joystick_deadzone", 0.0, 45.0, 100.0, "%")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Joystick size", "joystick_scale", 72.0, 165.0, 100.0, "%")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Joystick from left", "joystick_margin_x", 24.0, 160.0, 1.0, "px")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Joystick from bottom", "joystick_margin_bottom", 32.0, 160.0, 1.0, "px")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Jump size", "jump_scale", 72.0, 155.0, 100.0, "%")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Jump from right", "jump_margin_x", 28.0, 180.0, 1.0, "px")
	_add_mobile_control_slider(parent, mobile_runtime, settings, "Jump from bottom", "jump_margin_bottom", 36.0, 180.0, 1.0, "px")

func _add_mobile_control_option(parent: VBoxContainer, mobile_runtime: Node, settings: Dictionary, label_text: String, key: String, options: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86, 0.95))
	row.add_child(label)
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(148.0, 36.0)
	selector.focus_mode = Control.FOCUS_NONE
	for option in options:
		selector.add_item(option)
	var current_value := str(settings.get(key, options[0] if not options.is_empty() else ""))
	var selected_index := options.find(current_value)
	selector.select(maxi(selected_index, 0))
	selector.item_selected.connect(func(index: int) -> void:
		if index < 0 or index >= options.size():
			return
		var next_settings := mobile_runtime.call("get_control_settings") as Dictionary
		next_settings[key] = options[index]
		mobile_runtime.call("update_control_settings", next_settings)
	)
	row.add_child(selector)

func _add_mobile_control_slider(parent: VBoxContainer, mobile_runtime: Node, settings: Dictionary, label_text: String, key: String, min_value: float, max_value: float, display_multiplier: float, suffix: String) -> void:
	var label := Label.new()
	var raw_value: float = float(settings.get(key, 1.0))
	var shown_value: float = raw_value * display_multiplier if display_multiplier > 1.0 else raw_value
	label.text = "%s: %d%s" % [label_text, int(roundf(shown_value)), suffix]
	label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86, 0.95))
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 1.0
	slider.value = raw_value * display_multiplier if display_multiplier > 1.0 else raw_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void:
		var next_settings := mobile_runtime.call("get_control_settings") as Dictionary
		next_settings[key] = value / display_multiplier if display_multiplier > 1.0 else value
		mobile_runtime.call("update_control_settings", next_settings)
		label.text = "%s: %d%s" % [label_text, int(roundf(value)), suffix]
	)
	parent.add_child(slider)

func _load_template_scene_async(shape_type: String) -> PackedScene:
	var clean_shape: String = shape_type.strip_edges().to_lower()
	if clean_shape.is_empty():
		return null
	var scene_path: String = "res://maps/templates/%s/%s.tscn" % [clean_shape, clean_shape]
	if _threaded_scene_cache.has(scene_path):
		return _threaded_scene_cache[scene_path] as PackedScene
	if not ResourceLoader.exists(scene_path):
		return null
	var cache_mode := ResourceLoader.CACHE_MODE_IGNORE if clean_shape == "obby1" or clean_shape == "obby2" else ResourceLoader.CACHE_MODE_REUSE
	var request_error: Error = ResourceLoader.load_threaded_request(scene_path, "PackedScene", true, cache_mode)
	if request_error != OK and request_error != ERR_BUSY:
		var fallback_resource := ResourceLoader.load(scene_path, "PackedScene", cache_mode)
		var fallback_scene := fallback_resource as PackedScene
		if fallback_scene != null:
			_threaded_scene_cache[scene_path] = fallback_scene
		return fallback_scene
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded_resource := ResourceLoader.load_threaded_get(scene_path)
			var loaded_scene := loaded_resource as PackedScene
			if loaded_scene != null:
				_threaded_scene_cache[scene_path] = loaded_scene
			return loaded_scene
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return null
		await get_tree().process_frame
	return null

func _instantiate_template_block_async(shape_type: String, block_data: Dictionary, position: Vector3, map_target: Node3D, room_id: String = "") -> Node3D:
	var scene: PackedScene = await _load_template_scene_async(shape_type)
	if scene == null or map_target == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	inst.position = position
	inst.rotation_degrees = Vector3(
		block_data.get("rx", 0.0),
		block_data.get("ry", 0.0),
		block_data.get("rz", 0.0)
	)
	inst.scale = Vector3(
		block_data.get("sx", 1.0),
		block_data.get("sy", 1.0),
		block_data.get("sz", 1.0)
	)
	if not room_id.strip_edges().is_empty():
		inst.set_meta("room_id", room_id.strip_edges())
	map_target.add_child(inst)
	return inst

func _load_selected_map() -> void:
	_teleport_blocks_by_color.clear()
	_fallback_spawn_positions.clear()
	_pending_map_asset_downloads.clear()
	_failed_map_asset_downloads.clear()
	_map_player_settings = _get_default_player_settings()
	_map_mode_settings = _get_default_mode_settings()
	_map_roblox_manifest = {}
	_clear_runtime_roblox_ui()
	# FIX Eye Strain Bug: Reset WorldEnvironment glow and Sun rotation to
	# defaults BEFORE loading the new map. Without this, glow from a Neon
	# map persists into a non-Neon map, and the sun angle from a previous
	# time_of_day leaks into the next session causing shadow instability.
	var env_node_pre: WorldEnvironment = $World/WorldEnvironment
	if env_node_pre and env_node_pre.environment:
		env_node_pre.environment.glow_enabled = false
		env_node_pre.environment.glow_intensity = 0.0
	var sun_pre: DirectionalLight3D = $World/Sun
	if sun_pre:
		sun_pre.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
	_configure_runtime_visual_stability()
	var local_room_id: String = _get_effective_local_room_id()
	var room_origin: Vector3 = _get_room_visual_origin(local_room_id)
	if GameState.selected_map_folder.is_empty():
		_map_asset_urls.clear()
		_apply_mode_settings(_map_mode_settings)
		_generate_default_ground()
		return
	var data: Dictionary = await _read_map_data_dictionary_async(GameState.selected_map_folder)
	if data.is_empty():
		print("[Main] Failed to parse map data.")
		_map_asset_urls.clear()
		_apply_mode_settings(_map_mode_settings)
		_generate_default_ground()
		return
	_map_player_settings = data.get("player_settings", _get_default_player_settings())
	_map_mode_settings = data.get("mode_settings", _get_default_mode_settings())
	_map_roblox_manifest = data.get("roblox_manifest", {}) if data.get("roblox_manifest", {}) is Dictionary else {}
	_map_asset_urls = data.get("mode_asset_urls", {}) if data.get("mode_asset_urls", {}) is Dictionary else {}

	# Set time of day
	if data.has("time_of_day"):
		var sun: DirectionalLight3D = $World/Sun
		if sun:
			var time_ratio: float = float(data["time_of_day"]) / 24.0
			var angle: float = (time_ratio * 360.0) - 90.0
			sun.rotation_degrees.x = -angle
	_apply_mode_settings(_map_mode_settings)

	# Spawn blocks
	var blocks: Array = data.get("blocks", [])
	var has_neon := false
	var blocks_loaded: int = 0
	# FIX A (Death Loop): Use the @onready member 'world' instead of a
	# local variable that shadows it, which caused spawn targets to desync.
	var map_target: Node3D = self.world

	for block_data in blocks:
		var pos := Vector3(
			block_data.get("px", 0.0),
			block_data.get("py", 0.0),
			block_data.get("pz", 0.0)
		) + room_origin
		var col := _color_from_block_data(block_data, Color.WHITE)
		var shape_type: String = block_data.get("shape", "Box")
		var mat_type: String = block_data.get("material", "Plastic")
		var transparency: float = block_data.get("transparency", 0.0)
		var can_collide: bool = block_data.get("can_collide", true)
		var is_water_volume := mat_type.strip_edges().to_lower() == "water"
		if is_water_volume:
			can_collide = false
		var deals_damage: bool = block_data.get("deals_damage", false)
		var damage_amount: float = float(block_data.get("damage_amount", 25.0))
		if shape_type == "KillPart":
			shape_type = "Box"
			deals_damage = true
			damage_amount = maxf(damage_amount, 100.0)

		if mat_type == "Neon":
			has_neon = true

		if shape_type == "Obby1" or shape_type == "Obby2":
			await _instantiate_template_block_async(shape_type, block_data, pos, map_target, local_room_id)
			blocks_loaded += 1
			if blocks_loaded % MAP_LOAD_BLOCKS_PER_FRAME == 0:
				await get_tree().process_frame
			continue

		# Create mesh
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = _make_runtime_node_name(str(block_data.get("name", "")), "%s_block" % shape_type)
		var mesh_resource: Mesh = _create_mesh_for_shape(shape_type)
		var mat := _create_material(col, mat_type, transparency)
		if _should_apply_saved_roblox_block_material(block_data):
			var roblox_props: Dictionary = (block_data.get("roblox_properties", {}) as Dictionary).duplicate(true)
			mat = _runtime_rbxl_material_cache.get_part_material_with_color(roblox_props, col)
		mesh_resource.surface_set_material(0, mat)
		mesh_inst.mesh = mesh_resource
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
		mesh_inst.set_meta("shape_type", shape_type)
		mesh_inst.set_meta("can_collide", can_collide)
		mesh_inst.set_meta("deals_damage", deals_damage)
		mesh_inst.set_meta("damage_amount", damage_amount)
		mesh_inst.set_meta("room_id", local_room_id)
		_restore_runtime_roblox_block_metadata(mesh_inst, block_data)
		mesh_inst.set_meta("material_type", mat_type)
		mesh_inst.set_meta("surface_type", mat_type)
		_apply_saved_bobux_mesh_resource(mesh_inst, block_data)
		_apply_saved_roblox_mesh_asset(mesh_inst, block_data)
		mesh_inst.set_meta("bobux_color", col)
		if block_data.has("vehicle_color"):
			mesh_inst.set_meta("vehicle_color", block_data.get("vehicle_color"))
		if block_data.has("vehicle_kind"):
			mesh_inst.set_meta("vehicle_kind", block_data.get("vehicle_kind"))
		if bool(block_data.get("breakable", shape_type == "Destructible")):
			mesh_inst.set_meta("breakable", true)
			mesh_inst.set_meta("health", int(block_data.get("health", 35)))
			mesh_inst.add_to_group("destructible_blocks")

		var is_spawn_block: bool = shape_type == "Spawn" or bool(block_data.get("is_spawn", false))
		if is_spawn_block:
			mesh_inst.add_to_group(_get_room_spawn_group_name(local_room_id))
			mesh_inst.add_child(_create_spawn_decal_node(mesh_inst.scale))

		map_target.add_child(mesh_inst)
		var coll_shape := _attach_runtime_block_physics(mesh_inst, block_data, shape_type, mat_type, can_collide, map_target)
		if is_water_volume:
			_attach_runtime_water_volume(mesh_inst, coll_shape)
		_configure_runtime_special_object(mesh_inst, shape_type, col, local_room_id)
		_configure_runtime_damage_block(mesh_inst, deals_damage, damage_amount)
		if bool(mesh_inst.get_meta("breakable", false)):
			_register_destructible_block(mesh_inst, local_room_id)
		if can_collide and not deals_damage and shape_type != "Teleport" and not _block_uses_dynamic_physics(block_data):
			_register_fallback_spawn_surface(mesh_inst)
		_configure_runtime_ai_components(mesh_inst, block_data)
		blocks_loaded += 1
		if blocks_loaded % MAP_LOAD_BLOCKS_PER_FRAME == 0:
			await get_tree().process_frame

	var loaded_runtime_refs := await _load_runtime_objects_into_map(data.get("runtime_objects", []), map_target, room_origin, local_room_id)
	await _apply_roblox_manifest_to_runtime_root(map_target, _map_roblox_manifest, loaded_runtime_refs, room_origin, local_room_id)
	print("[Main] Loaded %d blocks from user map" % blocks.size())

	# Enable glow if any block uses Neon material
	if has_neon:
		var env_node: WorldEnvironment = $World/WorldEnvironment
		if env_node and env_node.environment:
			env_node.environment.glow_enabled = true
			env_node.environment.glow_intensity = 0.5
			print("[Main] Neon detected - glow enabled")

func _restore_runtime_roblox_block_metadata(block: Node, block_data: Dictionary) -> void:
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
	if block_data.get("roblox_special_mesh", {}) is Dictionary:
		block.set_meta("roblox_special_mesh", (block_data.get("roblox_special_mesh", {}) as Dictionary).duplicate(true))


func _configure_runtime_ai_components(block: MeshInstance3D, block_data: Dictionary) -> void:
	if block == null or not is_instance_valid(block):
		return
	for child in block.get_children():
		if bool(child.get_meta("bobux_ai_component", false)):
			child.queue_free()
	var effects: Array = block_data.get("bobux_ai_effects", []) if block_data.get("bobux_ai_effects", []) is Array else []
	block.set_meta("bobux_ai_effects", effects.duplicate(true))
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
		_configure_runtime_ai_effect_node(effect_node, effect_spec)
		block.add_child(effect_node)
	var interaction: Dictionary = block_data.get("bobux_ai_interaction", {}) if block_data.get("bobux_ai_interaction", {}) is Dictionary else {}
	block.set_meta("bobux_ai_interaction", interaction.duplicate(true))
	if interaction.is_empty():
		return
	var mode := str(interaction.get("mode", "click"))
	var interaction_node: Node
	if mode == "touch":
		var area := Area3D.new()
		area.name = "TouchInterest"
		area.collision_layer = 0
		area.collision_mask = PLAYER_TRIGGER_COLLISION_MASK
		area.monitoring = true
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		shape_node.shape = box
		area.add_child(shape_node)
		area.body_entered.connect(_on_bobux_ai_touch_interaction.bind(area))
		area.add_to_group("roblox_touch_interests")
		interaction_node = area
	else:
		interaction_node = Node.new()
		interaction_node.name = "ProximityPrompt" if mode == "proximity" else "ClickDetector"
		if mode == "proximity":
			interaction_node.add_to_group("roblox_proximity_prompts")
		else:
			interaction_node.add_to_group("roblox_click_detectors")
	interaction_node.set_meta("roblox_class", interaction_node.name)
	interaction_node.set_meta("bobux_ai_component", true)
	interaction_node.set_meta("bobux_runtime_generated", true)
	interaction_node.set_meta("bobux_ai_interaction", interaction.duplicate(true))
	interaction_node.set_meta("roblox_properties", {
		"Enabled": true,
		"ActionText": str(interaction.get("prompt", "Use")),
		"MaxActivationDistance": float(interaction.get("max_distance", 16.0))
	})
	block.add_child(interaction_node)


func _configure_runtime_ai_effect_node(effect_node: Node, effect_spec: Dictionary) -> void:
	var effect_type := str(effect_spec.get("type", effect_node.name))
	var primary := Color.from_string(str(effect_spec.get("color", "#FF7814")), Color("#FF7814"))
	effect_node.name = effect_type
	effect_node.set_meta("roblox_class", effect_type)
	effect_node.set_meta("bobux_ai_component", true)
	effect_node.set_meta("bobux_runtime_generated", true)
	effect_node.set_meta("bobux_ai_effect", effect_spec.duplicate(true))
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

func _apply_saved_bobux_mesh_resource(mesh_inst: MeshInstance3D, block_data: Dictionary, map_folder: String = "") -> void:
	if mesh_inst == null:
		return
	var file_name := str(block_data.get("bobux_mesh_resource_asset", "")).strip_edges()
	if file_name.is_empty():
		return
	var resolved := file_name
	if not map_folder.is_empty() and not (file_name.begins_with("res://") or file_name.begins_with("user://") or file_name.is_absolute_path()):
		resolved = map_folder.path_join(file_name)
	else:
		resolved = _resolve_map_asset_path(file_name)
	if not FileAccess.file_exists(resolved):
		return
	var loaded := ResourceLoader.load(_runtime_resource_loader_path(resolved))
	if not (loaded is Mesh):
		return
	var fallback_material := mesh_inst.get_active_material(0)
	mesh_inst.mesh = (loaded as Mesh).duplicate(true)
	_apply_material_to_missing_mesh_surfaces(mesh_inst, fallback_material)
	RbxlMaterialCache.enable_embedded_vertex_colors(mesh_inst)
	mesh_inst.set_meta("shape_type", "MeshPart")
	mesh_inst.set_meta("bobux_mesh_resource_asset", file_name)
	_ensure_mesh_materials_double_sided(mesh_inst)

func _runtime_resource_loader_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var normalized := path.replace("\\", "/")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if normalized.begins_with(user_root + "/"):
		return "user://" + normalized.substr(user_root.length() + 1)
	return ProjectSettings.localize_path(path)

func _apply_saved_roblox_mesh_asset(mesh_inst: MeshInstance3D, block_data: Dictionary, map_folder: String = "") -> void:
	if mesh_inst == null:
		return
	var mesh_path := _saved_block_mesh_asset_path(block_data, map_folder)
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
	_apply_saved_roblox_block_texture(mesh_inst, block_data, true, map_folder)
	RbxlMaterialCache.enable_embedded_vertex_colors(mesh_inst)
	_ensure_mesh_materials_double_sided(mesh_inst)

func _saved_block_mesh_asset_path(block_data: Dictionary, map_folder: String = "") -> String:
	var file_name := str(block_data.get("roblox_mesh_json_asset", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := map_folder.path_join(file_name) if not map_folder.is_empty() and not file_name.is_absolute_path() and not file_name.begins_with("res://") and not file_name.begins_with("user://") else _resolve_map_asset_path(file_name)
		if FileAccess.file_exists(resolved):
			return resolved
		if FileAccess.file_exists(file_name):
			return file_name
	var mesh_id := _block_mesh_asset_id(block_data)
	if not mesh_id.is_empty():
		var cache_path := ProjectSettings.globalize_path("user://rbxl_assets/%s.mesh.json" % mesh_id)
		if FileAccess.file_exists(cache_path):
			return cache_path
	return ""

func _apply_saved_roblox_block_texture(mesh_inst: MeshInstance3D, block_data: Dictionary, use_mesh_uvs: bool, map_folder: String = "") -> void:
	var texture_path := _saved_block_texture_asset_path(block_data, map_folder)
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

func _saved_block_texture_asset_path(block_data: Dictionary, map_folder: String = "") -> String:
	var file_name := str(block_data.get("roblox_texture_asset_file", "")).strip_edges()
	if not file_name.is_empty():
		var resolved := map_folder.path_join(file_name) if not map_folder.is_empty() and not file_name.is_absolute_path() and not file_name.begins_with("res://") and not file_name.begins_with("user://") else _resolve_map_asset_path(file_name)
		if FileAccess.file_exists(resolved):
			return resolved
		if FileAccess.file_exists(file_name):
			return file_name
	var texture_id := _block_texture_asset_id(block_data)
	if texture_id.is_empty():
		return ""
	for ext in ["asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp", "png", "jpg", "jpeg", "webp"]:
		var cache_texture := ProjectSettings.globalize_path("user://rbxl_assets/%s.%s" % [texture_id, ext])
		if _texture_file_has_supported_magic(cache_texture):
			return cache_texture
	return ""

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

func reload_runtime_map_from_game_state() -> Dictionary:
	# Initial joins prepare files in MapManager, then build once on the server's
	# world confirmation. Building here as well duplicated every map and script.
	if not _runtime_world_ready and not multiplayer.is_server():
		return {"ok": true, "deferred": true, "map_folder": GameState.selected_map_folder}
	if world == null:
		return {
			"ok": false,
			"error": "World root is unavailable."
		}
	for child in world.get_children():
		if PERSISTENT_WORLD_CHILDREN.has(child.name):
			continue
		child.queue_free()
	await get_tree().process_frame
	await _load_selected_map()
	return {
		"ok": true,
		"map_folder": GameState.selected_map_folder
	}

func request_map_change(map_id: String, map_name: String = "", cloud_version_id: String = "") -> Dictionary:
	if not multiplayer.is_server():
		return {
			"ok": false,
			"error": "Only the dedicated server can change the active map."
		}
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return {
			"ok": false,
			"error": "Map id is empty."
		}
	var requested_map_name: String = map_name.strip_edges()
	var load_result: Dictionary = await MapManager.load_map(clean_map_id, requested_map_name, cloud_version_id)
	if not bool(load_result.get("ok", false)):
		return load_result
	var payload: Dictionary = {
		"map_id": str(load_result.get("map_id", clean_map_id)).strip_edges(),
		"map_name": str(load_result.get("map_name", requested_map_name if not requested_map_name.is_empty() else clean_map_id)).strip_edges(),
		"cloud_version_id": str(load_result.get("cloud_version_id", cloud_version_id)).strip_edges()
	}
	_teleport_blocks_by_color.clear()
	_peer_checkpoint_positions.clear()
	_peer_spawn_infos.clear()
	if NetworkManager != null and NetworkManager.has_method("update_all_rooms_map_state"):
		NetworkManager.update_all_rooms_map_state(
			str(payload.get("map_id", clean_map_id)).strip_edges(),
			str(payload.get("map_name", requested_map_name)).strip_edges(),
			str(payload.get("cloud_version_id", cloud_version_id)).strip_edges()
		)
	_apply_authoritative_map_change.rpc(payload)
	for peer_id_variant in _get_live_session_peer_ids():
		_perform_authoritative_respawn_for_peer(int(peer_id_variant))
	return {
		"ok": true,
		"map_id": str(payload.get("map_id", clean_map_id)).strip_edges(),
		"map_name": str(payload.get("map_name", requested_map_name)).strip_edges(),
		"cloud_version_id": str(payload.get("cloud_version_id", cloud_version_id)).strip_edges()
	}

@rpc("authority", "call_local", "reliable")
func _apply_authoritative_map_change(payload: Dictionary) -> void:
	var clean_map_id: String = str(payload.get("map_id", "")).strip_edges()
	if clean_map_id.is_empty():
		return
	var clean_map_name: String = str(payload.get("map_name", "")).strip_edges()
	var clean_cloud_version_id: String = str(payload.get("cloud_version_id", "")).strip_edges()
	var load_result: Dictionary = await MapManager.load_map(clean_map_id, clean_map_name, clean_cloud_version_id)
	if not bool(load_result.get("ok", false)):
		push_warning("[RoomHub] Could not apply authoritative map change to '%s': %s" % [clean_map_id, str(load_result.get("error", "unknown error"))])
		return
	_teleport_blocks_by_color.clear()
	_peer_checkpoint_positions.clear()
	_peer_spawn_infos.clear()

func _get_live_session_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for peer_id_variant in peer_user_ids.keys():
		var peer_id: int = int(peer_id_variant)
		if peer_id > 0 and not peer_ids.has(peer_id):
			peer_ids.append(peer_id)
	var local_peer_id: int = _get_runtime_local_peer_id()
	if local_peer_id > 0 and not peer_ids.has(local_peer_id):
		peer_ids.append(local_peer_id)
	return peer_ids

func _generate_default_ground() -> void:
	# FIX A (Death Loop): Use the @onready member 'world' directly.
	# The old 'current_world' local variable shadowed the class member.
	var room_origin: Vector3 = _get_room_visual_origin(_get_effective_local_room_id())
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource := BoxMesh.new()
	mesh_resource.size = Vector3(40, 1, 40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.55, 0.45, 1.0)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource
	mesh_inst.position = room_origin + Vector3(0, -0.5, 0)
	var static_body := StaticBody3D.new()
	var coll_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(40, 1, 40)
	coll_shape.shape = box_shape
	static_body.add_child(coll_shape)
	mesh_inst.add_child(static_body)
	self.world.add_child(mesh_inst)
	_fallback_spawn_positions.append(room_origin + Vector3(0.0, CHECKPOINT_RESPAWN_HEIGHT, 0.0))

func _create_mesh_for_shape(shape_name: String) -> Mesh:
	if shape_name == "Spawn" or shape_name == "Checkpoint" or shape_name == "Teleport" or shape_name == "VehicleSpawner" or shape_name == "Destructible":
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereMesh.new()
		"Cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.cap_top = true
			cylinder.cap_bottom = true
			return cylinder
		"Cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.cap_top = true
			cone.cap_bottom = true
			return cone
		"Wedge", "WedgePart":
			return RbxlWedgeMeshBuilder.build_wedge(Vector3.ONE)
		"CornerWedge", "CornerWedgePart":
			return RbxlWedgeMeshBuilder.build_corner_wedge(Vector3.ONE)
		"Truss", "TrussPart":
			return RbxlWedgeMeshBuilder.build_truss(Vector3.ONE)
		_:
			return BoxMesh.new()

func _create_collision_for_shape(shape_name: String) -> Shape3D:
	if shape_name == "Spawn" or shape_name == "Checkpoint" or shape_name == "Teleport" or shape_name == "VehicleSpawner" or shape_name == "Destructible":
		shape_name = "Box"
	match shape_name:
		"Sphere":
			return SphereShape3D.new()
		"Cylinder", "Cone":
			return CylinderShape3D.new()
		"Wedge", "WedgePart", "CornerWedge", "CornerWedgePart":
			var custom_mesh := _create_mesh_for_shape(shape_name)
			return custom_mesh.create_convex_shape(true, false) if custom_mesh != null else BoxShape3D.new()
		_:
			return BoxShape3D.new()

func _create_material(color: Color, mat_type: String, transparency: float = 0.0) -> StandardMaterial3D:
	var mat := _runtime_rbxl_material_cache.get_named_material(color, mat_type, transparency)
	if mat != null:
		return mat
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(color.r, color.g, color.b, 1.0 - transparency)
	fallback.roughness = 0.8
	if transparency > 0.0:
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return fallback


func _block_uses_dynamic_physics(block_data: Dictionary) -> bool:
	var physics_mode := str(block_data.get("bobux_physics_mode", block_data.get("physics_mode", ""))).strip_edges().to_lower()
	if physics_mode == "dynamic":
		return true
	return block_data.has("anchored") and not bool(block_data.get("anchored", true))


func _attach_runtime_block_physics(
	mesh_inst: MeshInstance3D,
	block_data: Dictionary,
	shape_type: String,
	mat_type: String,
	can_collide: bool,
	map_parent: Node
) -> CollisionShape3D:
	if mesh_inst == null or map_parent == null:
		return null
	if shape_type in ["Cone", "Wedge", "WedgePart", "CornerWedge", "CornerWedgePart", "Truss", "TrussPart"]:
		_ensure_mesh_materials_double_sided(mesh_inst)
	if not _block_uses_dynamic_physics(block_data):
		var static_body := StaticBody3D.new()
		var static_shape := CollisionShape3D.new()
		static_shape.shape = _create_collision_for_shape(shape_type)
		_apply_collision_shape_size(static_shape, shape_type, mesh_inst.scale)
		static_shape.disabled = not can_collide
		static_body.add_child(static_shape)
		static_body.set_meta("material_type", mat_type)
		static_body.set_meta("surface_type", mat_type)
		mesh_inst.add_child(static_body)
		return static_shape
	var rigid_body := RigidBody3D.new()
	rigid_body.name = "%s_PhysicsBody" % mesh_inst.name
	rigid_body.set_meta("bobux_runtime_generated", true)
	rigid_body.set_meta("bobux_visual_instance_id", mesh_inst.get_instance_id())
	rigid_body.set_meta("material_type", mat_type)
	rigid_body.set_meta("surface_type", mat_type)
	rigid_body.set_meta("room_id", mesh_inst.get_meta("room_id", ""))
	rigid_body.collision_layer = 1
	rigid_body.collision_mask = PLAYER_TRIGGER_COLLISION_MASK | 1
	rigid_body.mass = maxf(0.05, float(block_data.get("bobux_physics_mass", block_data.get("mass", 1.0))))
	rigid_body.gravity_scale = maxf(0.0, float(block_data.get("bobux_physics_gravity_scale", block_data.get("gravity_scale", 1.0))))
	rigid_body.linear_damp = maxf(0.0, float(block_data.get("bobux_physics_linear_damp", block_data.get("linear_damp", 0.1))))
	rigid_body.angular_damp = maxf(0.0, float(block_data.get("bobux_physics_angular_damp", block_data.get("angular_damp", 0.1))))
	rigid_body.continuous_cd = true
	rigid_body.contact_monitor = true
	rigid_body.max_contacts_reported = 8
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = clampf(float(block_data.get("bobux_physics_friction", block_data.get("friction", 0.5))), 0.0, 1.0)
	physics_material.bounce = clampf(float(block_data.get("bobux_physics_bounce", block_data.get("bounce", 0.0))), 0.0, 1.0)
	rigid_body.physics_material_override = physics_material
	map_parent.add_child(rigid_body, true)
	var visual_scale := mesh_inst.global_basis.get_scale().abs()
	rigid_body.global_transform = Transform3D(mesh_inst.global_basis.orthonormalized(), mesh_inst.global_position)
	var dynamic_shape := CollisionShape3D.new()
	dynamic_shape.name = "CollisionShape3D"
	if bool(mesh_inst.get_meta("roblox_mesh_applied", false)) and mesh_inst.mesh != null:
		dynamic_shape.shape = mesh_inst.mesh.create_convex_shape(true, false)
	else:
		dynamic_shape.shape = _create_collision_for_shape(shape_type)
		_apply_collision_shape_size(dynamic_shape, shape_type, visual_scale)
	dynamic_shape.scale = visual_scale
	dynamic_shape.disabled = not can_collide
	rigid_body.add_child(dynamic_shape)
	var remote := RemoteTransform3D.new()
	remote.name = "VisualFollower"
	remote.update_position = true
	remote.update_rotation = true
	remote.update_scale = false
	rigid_body.add_child(remote)
	remote.remote_path = remote.get_path_to(mesh_inst)
	mesh_inst.set_meta("_bobux_physics_body_instance_id", rigid_body.get_instance_id())
	mesh_inst.set_meta("anchored", false)
	return dynamic_shape

func _attach_runtime_water_volume(block: MeshInstance3D, source_collision: CollisionShape3D) -> void:
	if block == null or source_collision == null or source_collision.shape == null:
		return
	block.add_to_group("roblox_water")
	block.set_meta("roblox_material_name", "Water")
	block.set_meta("material_type", "Water")
	var area := Area3D.new()
	area.name = "WaterVolume"
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = true
	area.monitorable = true
	area.add_to_group("roblox_water")
	area.set_meta("roblox_class", "TerrainWater")
	var water_shape := CollisionShape3D.new()
	water_shape.name = "WaterShape"
	water_shape.shape = source_collision.shape.duplicate(true)
	water_shape.position = source_collision.position
	area.add_child(water_shape)
	block.add_child(area)

func _apply_collision_shape_size(collision_shape: CollisionShape3D, shape_name: String, _block_scale: Vector3) -> void:
	if collision_shape == null or collision_shape.shape == null:
		return
	var normalized_shape := shape_name
	if normalized_shape == "Spawn" or normalized_shape == "Checkpoint" or normalized_shape == "Teleport" or normalized_shape == "VehicleSpawner" or normalized_shape == "Destructible":
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

func _configure_runtime_special_object(block: MeshInstance3D, shape_type: String, block_color: Color, room_id: String = "") -> void:
	match shape_type:
		"Checkpoint":
			_add_checkpoint_marker(block, block_color)
			if _should_attach_room_runtime_interactions():
				_add_checkpoint_trigger(block, func(body: Node3D): _on_checkpoint_entered(block, body))
		"Teleport":
			_add_teleport_marker(block, block_color)
			if _should_attach_room_runtime_interactions():
				_register_teleport_block(block, block_color, room_id)
				_add_teleport_trigger(block, func(body: Node3D): _on_teleport_entered(block, body))
		"VehicleSpawner":
			_add_vehicle_spawner_marker(block, block_color)
			if _should_attach_room_runtime_interactions():
				_add_vehicle_spawner_trigger(block, func(body: Node3D): _on_vehicle_spawner_entered(block, body))
		"Destructible":
			_add_destructible_marker(block, block_color)

func _configure_runtime_damage_block(block: MeshInstance3D, deals_damage: bool, damage_amount: float) -> void:
	if not deals_damage or damage_amount <= 0.0 or not _should_attach_room_runtime_interactions():
		return
	_add_damage_trigger(block, damage_amount, func(body: Node3D): _on_damage_block_entered(block, body, damage_amount))

func _add_checkpoint_marker(block: MeshInstance3D, block_color: Color) -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 2.2
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, (block.scale.y * 0.5) + 1.1, 0.0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.95, 0.95, 0.95)
	pole.mesh.surface_set_material(0, pole_mat)
	block.add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.9, 0.45, 0.08)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.45, (block.scale.y * 0.5) + 1.65, 0.0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = block_color.lightened(0.2)
	flag_mat.emission_enabled = true
	flag_mat.emission = block_color
	flag_mat.emission_energy_multiplier = 0.6
	flag.mesh.surface_set_material(0, flag_mat)
	block.add_child(flag)

func _add_teleport_marker(block: MeshInstance3D, block_color: Color) -> void:
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.35
	beam_mesh.bottom_radius = 0.6
	beam_mesh.height = 3.2
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, (block.scale.y * 0.5) + 1.6, 0.0)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(block_color.r, block_color.g, block_color.b, 0.35)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.emission_enabled = true
	beam_mat.emission = block_color
	beam_mat.emission_energy_multiplier = 1.2
	beam.mesh.surface_set_material(0, beam_mat)
	block.add_child(beam)

func _add_vehicle_spawner_marker(block: MeshInstance3D, block_color: Color) -> void:
	block.add_to_group("vehicle_spawner_blocks")
	var beacon := MeshInstance3D.new()
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.22
	beacon_mesh.bottom_radius = 0.48
	beacon_mesh.height = 2.4
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, (block.scale.y * 0.5) + 1.2, 0.0)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(block_color.r, block_color.g, block_color.b, 0.42)
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.emission_enabled = true
	beacon_mat.emission = block_color
	beacon_mat.emission_energy_multiplier = 1.5
	beacon.mesh.surface_set_material(0, beacon_mat)
	block.add_child(beacon)

	var label := Label3D.new()
	label.text = "[E]\nSpawn Car"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.WHITE
	label.position = Vector3(0.0, (block.scale.y * 0.5) + 3.0, 0.0)
	label.font_size = 28
	label.pixel_size = 0.014
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set("no_depth_test", true)
	label.set("shaded", false)
	block.add_child(label)

func _add_destructible_marker(block: MeshInstance3D, block_color: Color) -> void:
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(1.08, 1.08, 1.08)
	rim.mesh = rim_mesh
	rim.scale = Vector3.ONE
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(block_color.r, block_color.g, block_color.b, 0.16)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.emission_enabled = true
	rim_mat.emission = block_color.lightened(0.1)
	rim_mat.emission_energy_multiplier = 0.35
	rim.mesh.surface_set_material(0, rim_mat)
	block.add_child(rim)

func _add_checkpoint_trigger(block: MeshInstance3D, body_handler: Callable) -> void:
	var area := Area3D.new()
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 0
	area.collision_mask = PLAYER_TRIGGER_COLLISION_MASK
	var area_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(
		maxf(1.0, block.scale.x + 0.25),
		maxf(1.5, block.scale.y + CHECKPOINT_TRIGGER_EXTRA_HEIGHT),
		maxf(1.0, block.scale.z + 0.25)
	)
	area_shape.shape = trigger_box
	area_shape.position = Vector3(0.0, (trigger_box.size.y * 0.5) - (block.scale.y * 0.5), 0.0)
	area.add_child(area_shape)
	area.body_entered.connect(body_handler)
	block.add_child(area)

func _add_teleport_trigger(block: MeshInstance3D, body_handler: Callable) -> void:
	var area := Area3D.new()
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 0
	area.collision_mask = PLAYER_TRIGGER_COLLISION_MASK
	var area_shape := CollisionShape3D.new()
	var trigger_cylinder := CylinderShape3D.new()
	trigger_cylinder.radius = maxf(0.8, minf(block.scale.x, block.scale.z) * 0.46)
	trigger_cylinder.height = maxf(TELEPORT_TRIGGER_HEIGHT, block.scale.y + 1.6)
	area_shape.shape = trigger_cylinder
	area_shape.position = Vector3(0.0, (trigger_cylinder.height * 0.5) - (block.scale.y * 0.5) + 0.15, 0.0)
	area.add_child(area_shape)
	area.body_entered.connect(body_handler)
	block.add_child(area)

func _add_vehicle_spawner_trigger(block: MeshInstance3D, _body_handler: Callable) -> void:
	block.add_to_group("vehicle_spawner_blocks")
	var old_auto_spawner := block.get_node_or_null("MasterCarSpawner")
	if old_auto_spawner != null:
		old_auto_spawner.queue_free()

func _poll_vehicle_spawners_if_needed() -> void:
	if _is_dedicated_server_runtime():
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_vehicle_spawner_poll_msec:
		return
	_next_vehicle_spawner_poll_msec = now_msec + VEHICLE_SPAWNER_POLL_INTERVAL_MSEC
	_update_vehicle_spawn_prompt()

func _update_vehicle_spawn_prompt() -> void:
	if _vehicle_spawn_prompt_panel == null:
		return
	var local_player := _get_local_player()
	if local_player == null:
		_vehicle_spawn_prompt_panel.visible = false
		return
	var spawner_block := _find_vehicle_spawner_for_player(local_player)
	if spawner_block == null:
		_vehicle_spawn_prompt_panel.visible = false
		return
	var peer_id: int = _get_trigger_peer_id_from_body(local_player)
	var existing_car_id: String = str(_chaos_car_id_by_owner.get(peer_id, "")).strip_edges()
	if not existing_car_id.is_empty() and _chaos_cars_by_id.has(existing_car_id):
		_vehicle_spawn_prompt_label.text = "[E] Respawn Car"
	else:
		_vehicle_spawn_prompt_label.text = "[E] Spawn Car"
	_vehicle_spawn_prompt_panel.visible = true

func _request_local_vehicle_spawn_from_pad() -> bool:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		return false
	var local_player := _get_local_player()
	if local_player == null:
		return false
	var spawner_block := _find_vehicle_spawner_for_player(local_player)
	if spawner_block == null:
		return false
	var room_id: String = str(spawner_block.get_meta("room_id", "")).strip_edges()
	if multiplayer.multiplayer_peer != null:
		_request_vehicle_spawn_at_spawner_rpc.rpc_id(1, spawner_block.name, room_id)
	else:
		_on_vehicle_spawner_entered(spawner_block, local_player)
	return true

func _find_vehicle_spawner_for_player(player_body: CharacterBody3D) -> MeshInstance3D:
	for spawner_variant in get_tree().get_nodes_in_group("vehicle_spawner_blocks"):
		if not (spawner_variant is MeshInstance3D):
			continue
		var spawner_block := spawner_variant as MeshInstance3D
		if is_instance_valid(spawner_block) and _is_player_on_vehicle_spawner(spawner_block, player_body):
			return spawner_block
	return null

func _find_vehicle_spawner_by_name(spawner_name: String, room_id: String) -> MeshInstance3D:
	var clean_name: String = spawner_name.strip_edges()
	var clean_room_id: String = room_id.strip_edges()
	if clean_name.is_empty():
		return null
	for spawner_variant in get_tree().get_nodes_in_group("vehicle_spawner_blocks"):
		if not (spawner_variant is MeshInstance3D):
			continue
		var spawner_block := spawner_variant as MeshInstance3D
		if not is_instance_valid(spawner_block) or spawner_block.name != clean_name:
			continue
		var spawner_room_id: String = str(spawner_block.get_meta("room_id", "")).strip_edges()
		if clean_room_id.is_empty() or spawner_room_id == clean_room_id:
			return spawner_block
	return null

@rpc("any_peer", "reliable")
func _request_vehicle_spawn_at_spawner_rpc(spawner_name: String, room_id: String) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	var player_body := _find_player_node_by_peer_id(sender_id)
	if player_body == null:
		return
	var spawner_block := _find_vehicle_spawner_by_name(spawner_name, room_id)
	if spawner_block == null or not _is_player_on_vehicle_spawner(spawner_block, player_body):
		return
	_on_vehicle_spawner_entered(spawner_block, player_body)

func _is_player_on_vehicle_spawner(spawner_block: MeshInstance3D, player_body: CharacterBody3D) -> bool:
	if spawner_block == null or player_body == null:
		return false
	var peer_id: int = _get_trigger_peer_id_from_body(player_body)
	if peer_id <= 0:
		return false
	var room_id: String = str(spawner_block.get_meta("room_id", "")).strip_edges()
	if not room_id.is_empty() and room_id != _get_peer_room_id(peer_id):
		return false
	var local_position: Vector3 = spawner_block.global_transform.affine_inverse() * player_body.global_position
	var half_x: float = maxf(1.2, spawner_block.scale.x * 0.52)
	var half_z: float = maxf(1.2, spawner_block.scale.z * 0.52)
	var top_y: float = spawner_block.scale.y * 0.5
	var min_y: float = top_y - 0.9
	var max_y: float = top_y + 2.8
	return absf(local_position.x) <= half_x and absf(local_position.z) <= half_z and local_position.y >= min_y and local_position.y <= max_y

func _add_damage_trigger(block: MeshInstance3D, damage_amount: float, body_handler: Callable) -> void:
	var area := Area3D.new()
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 0
	area.collision_mask = PLAYER_TRIGGER_COLLISION_MASK
	var area_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(
		maxf(1.0, block.scale.x + 0.2),
		maxf(1.4, block.scale.y + DAMAGE_TRIGGER_EXTRA_HEIGHT),
		maxf(1.0, block.scale.z + 0.2)
	)
	area_shape.shape = trigger_box
	area_shape.position = Vector3(0.0, (trigger_box.size.y * 0.5) - (block.scale.y * 0.5), 0.0)
	area.set_meta("damage_amount", damage_amount)
	area.add_child(area_shape)
	area.body_entered.connect(body_handler)
	block.add_child(area)

func _register_teleport_block(block: MeshInstance3D, block_color: Color, room_id: String = "") -> void:
	var color_key := _make_color_key(block_color)
	block.set_meta("teleport_color_key", color_key)
	var registry: Dictionary = _get_room_teleport_registry(room_id)
	var teleports: Array = registry.get(color_key, [])
	teleports.append(block)
	registry[color_key] = teleports
	if room_id.strip_edges().is_empty():
		_teleport_blocks_by_color = registry
	else:
		_room_runtime_teleports[room_id.strip_edges()] = registry

func _make_color_key(color: Color) -> String:
	return "%d_%d_%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]

func _make_runtime_node_name(raw_name: String, fallback_name: String) -> String:
	var clean_name: String = raw_name.strip_edges()
	if clean_name.is_empty():
		clean_name = fallback_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "RuntimeBlock"
	for token in [":", "/", "\\", "@", "%", ".", " "]:
		clean_name = clean_name.replace(token, "_")
	return clean_name

func _should_attach_room_runtime_interactions() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

func _get_trigger_peer_id_from_body(body: CharacterBody3D) -> int:
	if body == null:
		return 0
	var peer_id: int = body.get_multiplayer_authority()
	if peer_id <= 0:
		return 0
	if not _should_attach_room_runtime_interactions() and not body.is_multiplayer_authority():
		return 0
	return peer_id

func _on_checkpoint_entered(checkpoint_block: MeshInstance3D, body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var checkpoint_owner_id: int = _get_trigger_peer_id_from_body(body as CharacterBody3D)
	if checkpoint_owner_id <= 0:
		return
	var room_id: String = str(checkpoint_block.get_meta("room_id", "")).strip_edges()
	if not room_id.is_empty() and room_id != _get_peer_room_id(checkpoint_owner_id):
		return
	var respawn_pos := checkpoint_block.global_position + Vector3.UP * ((checkpoint_block.scale.y * 0.5) + CHECKPOINT_RESPAWN_HEIGHT)
	_set_checkpoint_for_peer(checkpoint_owner_id, respawn_pos)

func _set_checkpoint_for_peer(peer_id: int, checkpoint_position: Vector3) -> void:
	if peer_id <= 0:
		return
	_peer_checkpoint_positions[peer_id] = checkpoint_position
	var player_node: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if player_node != null and player_node.has_method("restore_checkpoint_state"):
		player_node.call("restore_checkpoint_state", _server_to_local_room_position(checkpoint_position, _get_peer_room_id(peer_id)))
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_apply_checkpoint_to_local_player.rpc_id(peer_id, checkpoint_position)
	elif peer_id == _get_runtime_local_peer_id():
		_apply_checkpoint_to_local_player(checkpoint_position)

@rpc("authority", "reliable")
func _apply_checkpoint_to_local_player(checkpoint_position: Vector3) -> void:
	var local_peer_id := _get_runtime_local_peer_id()
	var local_room_id := _get_peer_room_id(local_peer_id)
	var local_checkpoint_position := _server_to_local_room_position(checkpoint_position, local_room_id)
	if local_peer_id > 0:
		_peer_checkpoint_positions[local_peer_id] = checkpoint_position
	var local_player := _get_local_player()
	if local_player != null and local_player.has_method("restore_checkpoint_state"):
		local_player.call("restore_checkpoint_state", local_checkpoint_position)

func _on_teleport_entered(source_block: MeshInstance3D, body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var teleport_peer_id: int = _get_trigger_peer_id_from_body(body as CharacterBody3D)
	if teleport_peer_id <= 0:
		return
	var room_id: String = str(source_block.get_meta("room_id", "")).strip_edges()
	if not room_id.is_empty() and room_id != _get_peer_room_id(teleport_peer_id):
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < int(_peer_teleport_ready_at_msec.get(teleport_peer_id, 0)):
		return

	var color_key := str(source_block.get_meta("teleport_color_key", "")).strip_edges()
	if color_key.is_empty():
		var block_material := source_block.get_active_material(0) as StandardMaterial3D
		var block_color := block_material.albedo_color if block_material else Color.WHITE
		color_key = _make_color_key(block_color)
	var teleports: Array = _get_room_teleport_registry(room_id).get(color_key, [])
	var valid_teleports: Array[MeshInstance3D] = []
	for entry in teleports:
		if entry is MeshInstance3D and is_instance_valid(entry):
			valid_teleports.append(entry)
	if valid_teleports.size() < 2:
		return

	var source_index := valid_teleports.find(source_block)
	var destination := valid_teleports[(source_index + 1) % valid_teleports.size()]
	if destination == source_block:
		return
	var exit_pos := destination.global_position + Vector3.UP * ((destination.scale.y * 0.5) + TELEPORT_EXIT_HEIGHT)
	_peer_teleport_ready_at_msec[teleport_peer_id] = now_msec + TELEPORT_COOLDOWN_MSEC
	_teleport_peer_to_position(teleport_peer_id, exit_pos)

func _on_damage_block_entered(_source_block: MeshInstance3D, body: Node3D, damage_amount: float) -> void:
	if not (body is CharacterBody3D):
		return
	var damaged_peer_id: int = _get_trigger_peer_id_from_body(body as CharacterBody3D)
	if damaged_peer_id <= 0:
		return
	_apply_damage_to_peer(damaged_peer_id, damage_amount)

func _teleport_peer_to_position(peer_id: int, target_position: Vector3) -> void:
	if peer_id <= 0:
		return
	var player_node := _find_player_node_by_peer_id(peer_id)
	if player_node != null:
		player_node.global_position = target_position
		player_node.velocity = Vector3.ZERO
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_apply_teleport_to_local_player.rpc_id(peer_id, target_position)
	elif player_node != null and player_node.has_method("teleport_to_position"):
		player_node.call("teleport_to_position", target_position)

@rpc("authority", "reliable")
func _apply_teleport_to_local_player(target_position: Vector3) -> void:
	var local_player := _get_local_player()
	if local_player != null and local_player.has_method("teleport_to_position"):
		var local_room_id := _get_peer_room_id(_get_runtime_local_peer_id())
		local_player.call("teleport_to_position", _server_to_local_room_position(target_position, local_room_id))

func _apply_damage_to_peer(peer_id: int, damage_amount: float) -> void:
	if peer_id <= 0:
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_apply_damage_to_local_player.rpc_id(peer_id, damage_amount)
		return
	var local_player := _get_local_player()
	if local_player != null:
		_apply_damage_to_player_node(local_player, damage_amount)

@rpc("authority", "reliable")
func _apply_damage_to_local_player(damage_amount: float) -> void:
	var local_player := _get_local_player()
	if local_player != null:
		_apply_damage_to_player_node(local_player, damage_amount)

func _apply_damage_to_player_node(player_node: CharacterBody3D, damage_amount: float) -> void:
	if damage_amount >= 100.0 and player_node.has_method("kill_now"):
		player_node.call("kill_now")
	elif player_node.has_method("take_damage"):
		player_node.call("take_damage", damage_amount)

func request_lua_tool_damage(target_body: CharacterBody3D, damage_amount: float, source_body: CharacterBody3D = null) -> bool:
	if target_body == null or not is_instance_valid(target_body):
		return false
	var target_peer_id := _get_trigger_peer_id_from_body(target_body)
	if target_peer_id <= 0:
		# Studio/local play tests do not own multiplayer peer ids.
		_apply_damage_to_player_node(target_body, clampf(damage_amount, 0.0, 100.0))
		return true
	var source_peer_id := _get_trigger_peer_id_from_body(source_body) if source_body != null else _get_runtime_local_peer_id()
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		if not _server_supports_tool_damage or not is_instance_valid(_tool_damage_protocol): return false
		_tool_damage_protocol.rpc_id(1, "request_damage", target_peer_id, clampf(damage_amount, 0.0, 100.0))
		return true
	return _validate_and_apply_lua_tool_damage(source_peer_id, target_peer_id, damage_amount)

func _request_lua_tool_damage(target_peer_id: int, damage_amount: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_validate_and_apply_lua_tool_damage(multiplayer.get_remote_sender_id(), target_peer_id, damage_amount)

func _validate_and_apply_lua_tool_damage(source_peer_id: int, target_peer_id: int, damage_amount: float) -> bool:
	if source_peer_id <= 0 or target_peer_id <= 0 or source_peer_id == target_peer_id:
		return false
	if _get_peer_room_id(source_peer_id) != _get_peer_room_id(target_peer_id):
		return false
	var source_player := _find_player_node_by_peer_id(source_peer_id)
	var target_player := _find_player_node_by_peer_id(target_peer_id)
	if source_player == null or target_player == null:
		return false
	var max_distance := 8.0 * maxf(float(source_player.get_meta("roblox_stud_scale", 1.0)), 0.25)
	if source_player.global_position.distance_to(target_player.global_position) > max_distance:
		return false
	var now_msec := Time.get_ticks_msec()
	if now_msec < int(_peer_tool_damage_ready_at_msec.get(source_peer_id, 0)):
		return false
	_peer_tool_damage_ready_at_msec[source_peer_id] = now_msec + 180
	_apply_damage_to_peer(target_peer_id, clampf(damage_amount, 1.0, 100.0))
	return true

func _on_vehicle_spawner_entered(spawner_block: MeshInstance3D, body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var peer_id: int = _get_trigger_peer_id_from_body(body as CharacterBody3D)
	if peer_id <= 0:
		return
	var room_id: String = str(spawner_block.get_meta("room_id", "")).strip_edges()
	if not room_id.is_empty() and room_id != _get_peer_room_id(peer_id):
		return
	var existing_car_id: String = str(_chaos_car_id_by_owner.get(peer_id, "")).strip_edges()
	if not existing_car_id.is_empty() and _chaos_cars_by_id.has(existing_car_id):
		var existing_car: Node = _chaos_cars_by_id[existing_car_id]
		if existing_car != null and is_instance_valid(existing_car):
			existing_car.queue_free()
		_chaos_cars_by_id.erase(existing_car_id)
		_chaos_car_id_by_owner.erase(peer_id)
	var cooldown_key := "%s:%d" % [room_id, peer_id]
	var now_msec := Time.get_ticks_msec()
	if now_msec - int(_vehicle_spawn_cooldowns.get(cooldown_key, 0)) < VEHICLE_SPAWN_COOLDOWN_MSEC:
		return

	var spawn_forward: Vector3 = spawner_block.global_transform.basis.z.normalized()
	var local_spawn_position: Vector3 = spawner_block.global_position + spawn_forward * 11.0 + Vector3.UP * ((spawner_block.scale.y * 0.5) + 1.35)
	var spawn_candidate: Variant = _find_clear_vehicle_spawn_position(local_spawn_position, room_id, spawner_block.global_transform.basis)
	if not (spawn_candidate is Vector3):
		return
	local_spawn_position = spawn_candidate as Vector3
	_vehicle_spawn_cooldowns[cooldown_key] = now_msec
	if not room_id.is_empty():
		local_spawn_position -= _get_room_world_origin(room_id)
	var color_payload := _extract_vehicle_color_payload(spawner_block)
	var car_id := "chaos_car_%d" % peer_id
	var payload := {
		"car_id": car_id,
		"owner_peer_id": peer_id,
		"room_id": room_id,
		"position": local_spawn_position,
		"rotation_y": wrapf(spawner_block.global_rotation.y + PI, -PI, PI),
		"velocity": Vector3.ZERO,
		"color": color_payload
	}
	_dispatch_chaos_car_spawn(payload)

func _find_clear_vehicle_spawn_position(base_position: Vector3, room_id: String, spawner_basis: Basis) -> Variant:
	if _is_vehicle_spawn_zone_clear(base_position, room_id):
		return base_position
	var right := spawner_basis.x.normalized()
	var forward := spawner_basis.z.normalized()
	var offsets: Array[Vector3] = [
		right * 14.0,
		-right * 14.0,
		forward * 15.0,
		-forward * 15.0,
		right * 22.0 + forward * 8.0,
		-right * 22.0 + forward * 8.0,
		right * 30.0,
		-right * 30.0
	]
	for offset in offsets:
		var candidate := base_position + offset
		if _is_vehicle_spawn_zone_clear(candidate, room_id):
			return candidate
	return null

func _is_vehicle_spawn_zone_clear(global_spawn_position: Vector3, room_id: String = "") -> bool:
	var clean_room_id: String = room_id.strip_edges()
	for node in get_tree().get_nodes_in_group("chaos_cars"):
		if not (node is Node3D):
			continue
		var car := node as Node3D
		if not is_instance_valid(car):
			continue
		var car_room: String = str(car.get("room_id")).strip_edges()
		if not clean_room_id.is_empty() and not car_room.is_empty() and car_room != clean_room_id:
			continue
		if car.global_position.distance_to(global_spawn_position) <= VEHICLE_SPAWN_ZONE_RADIUS:
			return false
	return true

func _extract_vehicle_color_payload(spawner_block: MeshInstance3D) -> Dictionary:
	var meta_color: Variant = spawner_block.get_meta("vehicle_color", {})
	if meta_color is Dictionary:
		return {
			"r": float((meta_color as Dictionary).get("r", 0.9)),
			"g": float((meta_color as Dictionary).get("g", 0.18)),
			"b": float((meta_color as Dictionary).get("b", 0.1))
		}
	var material := spawner_block.get_active_material(0) as StandardMaterial3D
	var color := material.albedo_color if material != null else Color(0.9, 0.18, 0.1)
	return {"r": color.r, "g": color.g, "b": color.b}

func _dispatch_chaos_car_spawn(payload: Dictionary) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_spawn_chaos_car_from_payload(payload)
		var room_id: String = str(payload.get("room_id", "")).strip_edges()
		for peer_id in _get_room_broadcast_peer_ids(room_id):
			_spawn_chaos_car_rpc.rpc_id(peer_id, payload)
	else:
		_spawn_chaos_car_from_payload(payload)

@rpc("authority", "call_local", "reliable")
func _spawn_chaos_car_rpc(payload: Dictionary) -> void:
	_spawn_chaos_car_from_payload(payload)

func _spawn_chaos_car_from_payload(payload: Dictionary) -> void:
	var car_id: String = str(payload.get("car_id", "")).strip_edges()
	var owner_peer_id: int = int(payload.get("owner_peer_id", 0))
	if car_id.is_empty() or owner_peer_id <= 0 or world == null:
		return
	var previous_car_id: String = str(_chaos_car_id_by_owner.get(owner_peer_id, "")).strip_edges()
	if not previous_car_id.is_empty() and _chaos_cars_by_id.has(previous_car_id):
		var previous: Node = _chaos_cars_by_id[previous_car_id]
		if previous != null and is_instance_valid(previous):
			previous.queue_free()
		_chaos_cars_by_id.erase(previous_car_id)
	if _chaos_cars_by_id.has(car_id):
		var existing: Node = _chaos_cars_by_id[car_id]
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
	var car := CharacterBody3D.new()
	car.set_script(CHAOS_CAR_SCRIPT)
	if car.has_method("configure"):
		car.call("configure", payload)
	var spawn_position: Vector3 = payload.get("position", Vector3.ZERO)
	var room_id: String = str(payload.get("room_id", "")).strip_edges()
	if not room_id.is_empty():
		spawn_position += _get_room_visual_origin(room_id)
	car.position = spawn_position
	car.rotation.y = float(payload.get("rotation_y", 0.0))
	car.add_to_group("chaos_cars")
	car.set_multiplayer_authority(owner_peer_id, true)
	world.add_child(car)
	_chaos_cars_by_id[car_id] = car
	_chaos_car_id_by_owner[owner_peer_id] = car_id

func _get_room_broadcast_peer_ids(room_id: String) -> Array[int]:
	var clean_room_id := room_id.strip_edges()
	var peer_ids: Array[int] = []
	var seen: Dictionary = {}
	if not clean_room_id.is_empty() and NetworkManager != null and NetworkManager.has_method("get_room_member_peer_ids"):
		for peer_variant in NetworkManager.get_room_member_peer_ids(clean_room_id):
			var peer_id := int(peer_variant)
			if peer_id > 0 and not seen.has(peer_id):
				peer_ids.append(peer_id)
				seen[peer_id] = true
	if not clean_room_id.is_empty():
		return peer_ids
	if peer_ids.is_empty() and multiplayer.multiplayer_peer != null and multiplayer.has_method("get_peers"):
		for peer_variant in multiplayer.get_peers():
			var peer_id := int(peer_variant)
			if peer_id > 0 and not seen.has(peer_id):
				peer_ids.append(peer_id)
				seen[peer_id] = true
	return peer_ids

func _get_chaos_car_room_id(car_id: String) -> String:
	var car: Node = _chaos_cars_by_id.get(car_id, null) as Node
	if car != null and is_instance_valid(car):
		return str(car.get("room_id")).strip_edges()
	for owner_variant in _chaos_car_id_by_owner.keys():
		if str(_chaos_car_id_by_owner[owner_variant]) == car_id:
			var owner_peer_id := int(owner_variant)
			if NetworkManager != null and NetworkManager.has_method("get_peer_room_id"):
				return str(NetworkManager.get_peer_room_id(owner_peer_id)).strip_edges()
	return ""

func submit_chaos_car_state(car_id: String, car_position: Vector3, car_rotation_y: float, car_velocity: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		var room_id := _get_chaos_car_room_id(car_id)
		_submit_chaos_car_state_rpc.rpc_id(1, car_id, _local_to_server_room_position(car_position, room_id), car_rotation_y, car_velocity)
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_chaos_car_state_to_room(car_id, car_position, car_rotation_y, car_velocity)
		return
	_apply_chaos_car_state_rpc(car_id, car_position, car_rotation_y, car_velocity)

@rpc("any_peer", "unreliable")
func _submit_chaos_car_state_rpc(car_id: String, car_position: Vector3, car_rotation_y: float, car_velocity: Vector3) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	var expected_car_id: String = str(_chaos_car_id_by_owner.get(sender_id, "")).strip_edges()
	if expected_car_id != car_id:
		return
	# AUDIT FIX VULN-4: Verify sender is in the same room as the car.
	var car_room_id: String = _get_chaos_car_room_id(car_id)
	if not car_room_id.is_empty() and NetworkManager != null and NetworkManager.has_method("get_peer_room_id"):
		var sender_room: String = str(NetworkManager.get_peer_room_id(sender_id)).strip_edges()
		if sender_room != car_room_id:
			return
	_broadcast_chaos_car_state_to_room(car_id, car_position, car_rotation_y, car_velocity, sender_id)

func _broadcast_chaos_car_state_to_room(car_id: String, car_position: Vector3, car_rotation_y: float, car_velocity: Vector3, exclude_peer_id: int = 0) -> void:
	_apply_chaos_car_state_rpc(car_id, car_position, car_rotation_y, car_velocity)
	var room_id := _get_chaos_car_room_id(car_id)
	for peer_id in _get_room_broadcast_peer_ids(room_id):
		if peer_id == exclude_peer_id:
			continue
		_apply_chaos_car_state_rpc.rpc_id(peer_id, car_id, car_position, car_rotation_y, car_velocity)

@rpc("authority", "call_local", "unreliable")
func _apply_chaos_car_state_rpc(car_id: String, car_position: Vector3, car_rotation_y: float, car_velocity: Vector3) -> void:
	var room_id := _get_chaos_car_room_id(car_id)
	var local_car_position := _server_to_local_room_position(car_position, room_id)
	var car: Node = _chaos_cars_by_id.get(car_id, null) as Node
	if car != null and is_instance_valid(car) and car.has_method("apply_remote_state"):
		car.call("apply_remote_state", local_car_position, car_rotation_y, car_velocity)
	var owner_peer_id: int = _get_chaos_car_owner_peer_id(car_id)
	if owner_peer_id > 0:
		_set_player_vehicle_mode(owner_peer_id, true, _get_chaos_car_driver_seat_position(local_car_position, car_rotation_y))

func request_enter_chaos_car(car_id: String, car_position: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_request_enter_chaos_car_rpc.rpc_id(1, car_id, _local_to_server_room_position(car_position, _get_chaos_car_room_id(car_id)))
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_enter_chaos_car_to_room(car_id, car_position)
		return
	_enter_chaos_car_rpc(car_id, car_position)

@rpc("any_peer", "reliable")
func _request_enter_chaos_car_rpc(car_id: String, car_position: Vector3) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0 or str(_chaos_car_id_by_owner.get(sender_id, "")) != car_id:
		return
	_broadcast_enter_chaos_car_to_room(car_id, car_position)

func _broadcast_enter_chaos_car_to_room(car_id: String, car_position: Vector3) -> void:
	var room_id := _get_chaos_car_room_id(car_id)
	_enter_chaos_car_rpc(car_id, car_position)
	for peer_id in _get_room_broadcast_peer_ids(room_id):
		_enter_chaos_car_rpc.rpc_id(peer_id, car_id, car_position)

@rpc("authority", "call_local", "reliable")
func _enter_chaos_car_rpc(car_id: String, car_position: Vector3) -> void:
	var owner_peer_id: int = _get_chaos_car_owner_peer_id(car_id)
	if owner_peer_id > 0:
		var seat_position: Vector3 = _server_to_local_room_position(car_position, _get_chaos_car_room_id(car_id))
		var car: Node3D = _chaos_cars_by_id.get(car_id, null) as Node3D
		if car != null and is_instance_valid(car):
			seat_position = _get_chaos_car_driver_seat_position(car.global_position, car.rotation.y)
		_set_player_vehicle_mode(owner_peer_id, true, seat_position)

func request_exit_chaos_car(car_id: String, exit_position: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_request_exit_chaos_car_rpc.rpc_id(1, car_id, _local_to_server_room_position(exit_position, _get_chaos_car_room_id(car_id)))
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_exit_chaos_car_to_room(car_id, exit_position)
		return
	_exit_chaos_car_rpc(car_id, exit_position)

@rpc("any_peer", "reliable")
func _request_exit_chaos_car_rpc(car_id: String, exit_position: Vector3) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0 or str(_chaos_car_id_by_owner.get(sender_id, "")) != car_id:
		return
	_broadcast_exit_chaos_car_to_room(car_id, exit_position)

func _broadcast_exit_chaos_car_to_room(car_id: String, exit_position: Vector3) -> void:
	var room_id := _get_chaos_car_room_id(car_id)
	_exit_chaos_car_rpc(car_id, exit_position)
	for peer_id in _get_room_broadcast_peer_ids(room_id):
		_exit_chaos_car_rpc.rpc_id(peer_id, car_id, exit_position)

@rpc("authority", "call_local", "reliable")
func _exit_chaos_car_rpc(car_id: String, exit_position: Vector3) -> void:
	var owner_peer_id: int = _get_chaos_car_owner_peer_id(car_id)
	if owner_peer_id > 0:
		_set_player_vehicle_mode(owner_peer_id, false, _server_to_local_room_position(exit_position, _get_chaos_car_room_id(car_id)))
		_chaos_car_id_by_owner.erase(owner_peer_id)
	var car: Node = _chaos_cars_by_id.get(car_id, null) as Node
	if car != null and is_instance_valid(car):
		car.queue_free()
	_chaos_cars_by_id.erase(car_id)

func _set_player_vehicle_mode(peer_id: int, in_vehicle: bool, exit_position: Vector3) -> void:
	var player_node: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if player_node == null:
		return
	player_node.visible = true
	player_node.global_position = exit_position
	player_node.scale = Vector3(0.58, 0.58, 0.58) if in_vehicle else Vector3.ONE
	if not in_vehicle:
		player_node.rotation = Vector3.ZERO
		var visuals := player_node.get_node_or_null("Visuals") as Node3D
		if visuals != null:
			visuals.rotation.x = 0.0
			visuals.rotation.z = 0.0
	var should_restore_physics_collision: bool = player_node.is_multiplayer_authority() or _is_dedicated_server_runtime()
	if in_vehicle:
		player_node.collision_layer = 0
		player_node.collision_mask = 0
	elif should_restore_physics_collision:
		player_node.collision_layer = 2
		player_node.collision_mask = 1
	player_node.set_physics_process(not in_vehicle)
	player_node.set_process_unhandled_input(true)
	if not in_vehicle:
		_refresh_player_camera_authority_mode(player_node)
	var player_camera := player_node.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if player_camera != null and player_node.is_multiplayer_authority() and not in_vehicle:
		player_camera.current = true
	if player_node.is_multiplayer_authority() and not in_vehicle and player_node.has_method("restore_mouse_mode_after_network_handover"):
		player_node.call("restore_mouse_mode_after_network_handover")

func _get_chaos_car_owner_peer_id(car_id: String) -> int:
	for peer_variant in _chaos_car_id_by_owner.keys():
		if str(_chaos_car_id_by_owner[peer_variant]) == car_id:
			return int(peer_variant)
	return 0

func _get_chaos_car_driver_seat_position(car_position: Vector3, car_rotation_y: float) -> Vector3:
	var basis := Basis(Vector3.UP, car_rotation_y)
	return car_position + (basis * Vector3(0.0, 1.32, -0.38))

func request_break_destructible(car_id: String, block_name: String, room_id: String, hit_position: Vector3, impact_speed: float) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_request_break_destructible_rpc.rpc_id(1, car_id, block_name, room_id, _local_to_server_room_position(hit_position, room_id), impact_speed)
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_break_destructible_to_room(block_name, room_id, hit_position, impact_speed)
		return
	_break_destructible_rpc(block_name, room_id, hit_position, impact_speed)

@rpc("any_peer", "reliable")
func _request_break_destructible_rpc(car_id: String, block_name: String, room_id: String, hit_position: Vector3, impact_speed: float) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0 or str(_chaos_car_id_by_owner.get(sender_id, "")) != car_id:
		return
	_broadcast_break_destructible_to_room(block_name, room_id, hit_position, impact_speed)

func _broadcast_break_destructible_to_room(block_name: String, room_id: String, hit_position: Vector3, impact_speed: float) -> void:
	_break_destructible_rpc(block_name, room_id, hit_position, impact_speed)
	for peer_id in _get_room_broadcast_peer_ids(room_id):
		_break_destructible_rpc.rpc_id(peer_id, block_name, room_id, hit_position, impact_speed)

@rpc("authority", "call_local", "reliable")
func _break_destructible_rpc(block_name: String, room_id: String, hit_position: Vector3, impact_speed: float) -> void:
	var block := _find_destructible_block(block_name, room_id)
	if block == null:
		return
	_spawn_destructible_debris(block, _server_to_local_room_position(hit_position, room_id), impact_speed)
	_unregister_destructible_block(block, room_id)
	block.queue_free()

func _register_destructible_block(block: MeshInstance3D, room_id: String = "") -> void:
	if block == null:
		return
	var key := _make_destructible_key(room_id, block.name)
	_destructible_blocks_by_key[key] = block

func _unregister_destructible_block(block: MeshInstance3D, room_id: String = "") -> void:
	if block == null:
		return
	_destructible_blocks_by_key.erase(_make_destructible_key(room_id, block.name))

func _make_destructible_key(room_id: String, block_name: String) -> String:
	return "%s::%s" % [room_id.strip_edges(), block_name.strip_edges()]

func _find_destructible_block(block_name: String, room_id: String = "") -> MeshInstance3D:
	var key := _make_destructible_key(room_id, block_name)
	var stored: MeshInstance3D = _destructible_blocks_by_key.get(key, null) as MeshInstance3D
	if stored != null and is_instance_valid(stored):
		return stored
	for node in get_tree().get_nodes_in_group("destructible_blocks"):
		if node is MeshInstance3D and (node as MeshInstance3D).name == block_name:
			var candidate_room: String = str((node as MeshInstance3D).get_meta("room_id", "")).strip_edges()
			if candidate_room == room_id.strip_edges():
				return node as MeshInstance3D
	return null

func _spawn_destructible_debris(block: MeshInstance3D, hit_position: Vector3, impact_speed: float) -> void:
	if block == null or block.get_parent() == null or not is_instance_valid(block) or not block.is_inside_tree():
		return
	var parent := block.get_parent() as Node
	var block_transform: Transform3D = block.global_transform
	var block_rotation: Vector3 = block.rotation
	var block_scale: Vector3 = block.scale
	var base_color := Color(0.9, 0.25, 0.1)
	var material := block.get_active_material(0) as StandardMaterial3D
	if material != null:
		base_color = material.albedo_color
	var pieces_x := 4
	var pieces_y := 2
	var pieces_z := 2
	var piece_size := Vector3(
		maxf(0.5, block_scale.x / float(pieces_x)),
		maxf(0.45, block_scale.y / float(pieces_y)),
		maxf(0.45, block_scale.z / float(pieces_z))
	)
	for x in range(pieces_x):
		for y in range(pieces_y):
			for z in range(pieces_z):
				var local_offset := Vector3(
					(float(x) - 1.5) * piece_size.x,
					(float(y) - 0.5) * piece_size.y,
					(float(z) - 0.5) * piece_size.z
				)
				var debris := RigidBody3D.new()
				debris.global_position = block_transform.origin + block_transform.basis * local_offset
				debris.rotation = block_rotation
				debris.mass = 0.35
				var mesh_instance := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = piece_size
				mesh_instance.mesh = mesh
				var debris_mat := StandardMaterial3D.new()
				debris_mat.albedo_color = base_color.lightened(randf() * 0.12)
				mesh_instance.set_surface_override_material(0, debris_mat)
				debris.add_child(mesh_instance)
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = piece_size
				shape.shape = box
				debris.add_child(shape)
				parent.add_child(debris)
				var impulse_dir := (debris.global_position - hit_position + Vector3.UP * 1.8).normalized()
				debris.apply_impulse(impulse_dir * clampf(impact_speed * 0.22, 6.0, 22.0))
				var timer := get_tree().create_timer(DESTRUCTIBLE_DEBRIS_LIFETIME)
				timer.timeout.connect(func():
					if is_instance_valid(debris):
						debris.queue_free()
				)

func _is_body_centered_in_teleport(source_block: MeshInstance3D, body: CharacterBody3D) -> bool:
	var local_position := source_block.to_local(body.global_position)
	var half_width := maxf(0.9, source_block.scale.x * 0.62)
	var half_depth := maxf(0.9, source_block.scale.z * 0.62)
	return absf(local_position.x) <= half_width and absf(local_position.z) <= half_depth

func _start_session_from_game_state() -> void:
	_set_gameplay_frozen(not _runtime_world_ready)
	_stop_host_keepalive()
	if GameState.launch_mode == GameState.LaunchMode.TARGET_JOIN:
		_show_network_loading("Joining...", "Connecting to the selected room.", 0.2)
		_start_targeted_client(GameState.target_server_info)
		return
	if GameState.launch_mode == GameState.LaunchMode.JOIN:
		_show_network_loading("Joining...", "Connecting to the room host.", 0.2)
		_start_client(GameState.address, GameState.port)
		return
	if GameState.launch_mode == GameState.LaunchMode.HOST:
		_show_network_loading("Starting Server...", "Creating your room.", 0.22)
		_start_host(GameState.port)
		return
	if GameState.launch_mode == GameState.LaunchMode.SMART_PLAY:
		_smart_play_failed = false
		_reset_network_state()
		_show_network_loading("Loading...", "Finding or creating the best room.", 0.28)
		await NetworkManager.connect_or_host()
		return
	_show_network_loading("Loading...", "Launching a local room.", 0.16)
	_start_host(GameState.DEFAULT_PORT)

func _start_host(chosen_port: int) -> void:
	var host_world_was_ready := _map_loaded or _runtime_world_ready
	_reset_network_state()
	_map_loaded = host_world_was_ready
	_runtime_world_ready = host_world_was_ready
	_show_network_loading("Starting Server...", "Opening room on port %d." % chosen_port, 0.36)
	var error_code: Error = NetworkManager.host_game(chosen_port)
	if error_code != OK:
		print("[Host] Failed: " + error_string(error_code))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	print("[Host] Hosting on port " + str(NetworkManager.current_port if NetworkManager.current_port > 0 else chosen_port))

func _start_client(chosen_address: String, chosen_port: int) -> void:
	_reset_network_state()
	_show_network_loading("Joining...", "Contacting %s:%d." % [chosen_address, chosen_port], 0.42)
	var error_code: Error = NetworkManager.join_game(chosen_address, chosen_port)
	if error_code != OK:
		print("[Client] Join failed: " + error_string(error_code))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	print("[Client] Connecting to " + chosen_address + ":" + str(chosen_port) + "...")

func _start_targeted_client(server_info: Dictionary) -> void:
	_reset_network_state()
	var map_name: String = str(server_info.get("map_name", "the room host")).strip_edges()
	_show_network_loading("Joining...", "Contacting %s." % map_name, 0.42)
	var server_url: String = str(server_info.get("server_url", "")).strip_edges()
	var room_id: String = str(server_info.get("room_id", "")).strip_edges()
	var error_code: Error = NetworkManager.connect_to_dedicated_server(server_url, room_id, server_info) if not server_url.is_empty() and not room_id.is_empty() and NetworkManager.has_method("connect_to_dedicated_server") else NetworkManager.join_targeted_room(server_info)
	if error_code != OK:
		print("[Client] Targeted join failed: " + error_string(error_code))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	print("[Client] Joining targeted room " + str(server_info.get("room_id", "")))

func _on_hosting_started(_port: int, _external_ip: String, _upnp_mapped: bool) -> void:
	_stop_host_keepalive()
	if _is_dedicated_server_runtime():
		print("[DedicatedServer] Gameplay scene attached to authoritative WebSocket host.")
		return
	# During migration, resume_game_after_migration() handles everything.
	# Do NOT show "Loading World" or spawn a new player - we already have one.
	if NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return
	if not _map_loaded:
		_set_gameplay_frozen(true)
		_show_network_loading("Preparing World...", "Building the map before your character joins.", 0.62)
		await _load_selected_map()
		_map_loaded = true
		_runtime_world_ready = true
	_show_network_loading("Loading World...", "Spawning your character.", 0.82)
	var local_peer_id: int = _get_runtime_local_peer_id()
	if local_peer_id <= 0:
		return
	print("[Host] Session transport: %s" % NetworkManager.get_active_transport_label())
	peer_colors[local_peer_id] = _get_current_colors()
	peer_usernames[local_peer_id] = UserSession.username if UserSession.is_logged_in else "Player"
	peer_user_ids[local_peer_id] = SupabaseClient.get_user_id()
	peer_avatar_visuals[local_peer_id] = _get_current_avatar_visuals()
	_runtime_world_ready = _map_loaded
	_spawn_player_for_peer(local_peer_id)

func _on_peer_connected(peer_id: int) -> void:
	if not NetworkManager.is_host() and peer_id != 1 and NetworkManager.has_method("is_peer_in_same_room") and not NetworkManager.is_peer_in_same_room(peer_id):
		return
	if NetworkManager.is_host():
		print("[Host] Peer " + str(peer_id) + " connected, waiting for color sync...")
		return
	print("[Client] Peer " + str(peer_id) + " connected.")

func _on_room_peer_profiles_updated(profiles_by_peer: Dictionary) -> void:
	peer_profiles.clear()
	for peer_id_variant in profiles_by_peer.keys():
		var peer_id: int = int(peer_id_variant)
		if peer_id <= 0:
			continue
		var profile_entry: Dictionary = profiles_by_peer.get(peer_id_variant, {}) if profiles_by_peer.get(peer_id_variant, {}) is Dictionary else {}
		var profile_payload: Dictionary = profile_entry.get("profile", {}) if profile_entry.get("profile", {}) is Dictionary else {}
		var authoritative_username: String = str(profile_payload.get("username", profile_entry.get("username", ""))).strip_edges()
		if not authoritative_username.is_empty():
			peer_usernames[peer_id] = authoritative_username
		var authoritative_user_id: String = str(profile_payload.get("id", profile_entry.get("user_id", ""))).strip_edges()
		if not authoritative_user_id.is_empty():
			peer_user_ids[peer_id] = authoritative_user_id
		if not profile_payload.is_empty():
			peer_avatar_visuals[peer_id] = _get_avatar_visuals_from_profile(profile_payload)
		elif peer_id == _get_runtime_local_peer_id():
			peer_avatar_visuals[peer_id] = _get_current_avatar_visuals()
		peer_profiles[peer_id] = profile_payload.duplicate(true) if not profile_payload.is_empty() else {
			"id": authoritative_user_id,
			"username": authoritative_username
		}

func _on_room_emptied(_server_key: String, room_id: String) -> void:
	if not multiplayer.is_server():
		return
	if _room_runtime_preparations.has(room_id):
		var pending: Dictionary = _room_runtime_preparations[room_id]
		while bool(pending.loading):
			await get_tree().process_frame
	if NetworkManager != null and not NetworkManager.get_room_member_peer_ids(room_id).is_empty():
		return
	_free_room_runtime(room_id)

func _get_peer_room_id(peer_id: int) -> String:
	if NetworkManager != null and NetworkManager.has_method("get_peer_room_id"):
		return str(NetworkManager.get_peer_room_id(peer_id)).strip_edges()
	return ""

func _snapshot_matches_effective_local_room(peer_id: int, snapshot: Dictionary) -> bool:
	var snapshot_room_id: String = str(snapshot.get("room_id", "")).strip_edges()
	return _peer_matches_effective_local_room(peer_id, snapshot_room_id)

func _peer_matches_effective_local_room(peer_id: int, known_peer_room_id: String = "") -> bool:
	if peer_id <= 0:
		return false
	# A dedicated server hosts multiple room runtimes inside one process. Room
	# filtering here is a client-side visibility guard; applying it to the
	# authoritative server prevents legitimate players from spawning.
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		return true
	if _is_local_leaderboard_peer(peer_id):
		return true
	var local_room_id: String = _get_effective_local_room_id()
	if local_room_id.is_empty():
		return true
	var peer_room_id: String = known_peer_room_id.strip_edges()
	if peer_room_id.is_empty():
		peer_room_id = _get_peer_room_id(peer_id)
	if peer_room_id.is_empty():
		return true
	return peer_room_id == local_room_id

func _get_effective_local_room_id() -> String:
	if NetworkManager != null and NetworkManager.has_method("get_current_room_id"):
		var current_room_id: String = str(NetworkManager.get_current_room_id()).strip_edges()
		if not current_room_id.is_empty():
			return current_room_id
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0:
		var peer_room_id: String = _get_peer_room_id(runtime_local_peer_id)
		if not peer_room_id.is_empty():
			return peer_room_id
	return ""

func _get_room_spawn_group_name(room_id: String) -> String:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return "spawn_locations"
	return "%s%d" % [ROOM_SPAWN_GROUP_PREFIX, abs(clean_room_id.hash())]

func _get_room_world_origin(room_id: String) -> Vector3:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return Vector3.ZERO
	if _room_runtime_origins.has(clean_room_id):
		return _room_runtime_origins[clean_room_id]
	var column_hash: int = abs((clean_room_id + ":x").hash())
	var row_hash: int = abs((clean_room_id + ":z").hash())
	var column: int = column_hash % ROOM_RUNTIME_GRID_COLUMNS
	var row: int = row_hash % ROOM_RUNTIME_GRID_COLUMNS
	var origin := Vector3(float(column) * ROOM_RUNTIME_SPACING, 0.0, float(row) * ROOM_RUNTIME_SPACING)
	_room_runtime_origins[clean_room_id] = origin
	return origin

func _should_rebase_room_origin_for_client() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null and not multiplayer.is_server()

func _get_room_visual_origin(room_id: String) -> Vector3:
	if _should_rebase_room_origin_for_client() and not room_id.strip_edges().is_empty():
		return Vector3.ZERO
	return _get_room_world_origin(room_id)

func _get_room_network_position_origin(room_id: String) -> Vector3:
	return _get_room_world_origin(room_id) - _get_room_visual_origin(room_id)

func _server_to_local_room_position(position: Vector3, room_id: String) -> Vector3:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id.is_empty():
		return position
	return position - _get_room_network_position_origin(clean_room_id)

func _local_to_server_room_position(position: Vector3, room_id: String) -> Vector3:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id.is_empty():
		return position
	return position + _get_room_network_position_origin(clean_room_id)

func _server_to_local_room_points(points: Array, room_id: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points:
		if point is Vector3:
			result.append(_server_to_local_room_position(point as Vector3, room_id))
	return result

func _ensure_room_runtime_root(room_id: String) -> Dictionary:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty() or world == null:
		return {}
	var room_root: Node3D = _room_runtime_roots.get(clean_room_id, null) as Node3D
	var map_root: Node3D = _room_runtime_map_roots.get(clean_room_id, null) as Node3D
	if room_root != null and is_instance_valid(room_root) and map_root != null and is_instance_valid(map_root):
		return {"root": room_root, "map_root": map_root}
	var runtime_name_index: int = _next_room_runtime_index
	_next_room_runtime_index += 1
	room_root = Node3D.new()
	room_root.name = "RoomRuntime_%d" % runtime_name_index
	room_root.position = _get_room_world_origin(clean_room_id)
	room_root.set_meta("room_id", clean_room_id)
	world.add_child(room_root)
	map_root = Node3D.new()
	map_root.name = "MapRoot"
	map_root.set_meta("roblox_class", "Workspace")
	map_root.set_meta("room_id", clean_room_id)
	room_root.add_child(map_root)
	_room_runtime_roots[clean_room_id] = room_root
	_room_runtime_map_roots[clean_room_id] = map_root
	if not _room_runtime_fallback_spawns.has(clean_room_id):
		_room_runtime_fallback_spawns[clean_room_id] = []
	if not _room_runtime_teleports.has(clean_room_id):
		_room_runtime_teleports[clean_room_id] = {}
	return {"root": room_root, "map_root": map_root}

func _get_room_player_settings(room_id: String) -> Dictionary:
	var clean_room_id: String = room_id.strip_edges()
	var stored_settings: Variant = _room_runtime_player_settings.get(clean_room_id, _map_player_settings)
	if stored_settings is Dictionary and not (stored_settings as Dictionary).is_empty():
		return (stored_settings as Dictionary).duplicate(true)
	return _get_default_player_settings()

func _get_room_fallback_spawns(room_id: String) -> Array[Vector3]:
	var clean_room_id: String = room_id.strip_edges()
	var stored_spawns: Variant = _room_runtime_fallback_spawns.get(clean_room_id, [])
	var normalized: Array[Vector3] = []
	if stored_spawns is Array:
		for entry in stored_spawns:
			if entry is Vector3:
				normalized.append(entry)
	return normalized

func _get_room_teleport_registry(room_id: String) -> Dictionary:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return _teleport_blocks_by_color
	var registry: Dictionary = _room_runtime_teleports.get(clean_room_id, {}) if _room_runtime_teleports.get(clean_room_id, {}) is Dictionary else {}
	if not _room_runtime_teleports.has(clean_room_id):
		_room_runtime_teleports[clean_room_id] = registry
	return registry

func _resolve_room_map_folder_async(map_id: String, map_name: String, cloud_version_id: String) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	var clean_map_name: String = map_name.strip_edges()
	var clean_cloud_version_id: String = cloud_version_id.strip_edges()
	var is_builtin_map: bool = clean_map_id.is_empty() or clean_map_id == "classic" or clean_map_id == "untitled"
	if is_builtin_map:
		return {
			"ok": true,
			"folder": "",
			"map_id": clean_map_id,
			"map_name": clean_map_name,
			"cloud_version_id": clean_cloud_version_id
		}
	var selected_folder: String = CloudAPI.get_cached_map_folder(clean_map_id, clean_cloud_version_id) if CloudAPI != null and CloudAPI.has_method("get_cached_map_folder") else ""
	if selected_folder.is_empty():
		if CloudAPI == null or not CloudAPI.is_configured():
			return {
				"ok": false,
				"error": "Cloud API is unavailable on the dedicated server, so map '%s' cannot be prepared." % clean_map_id,
				"map_id": clean_map_id,
				"map_name": clean_map_name,
				"cloud_version_id": clean_cloud_version_id
			}
		var use_service_role: bool = CloudAPI != null and CloudAPI.has_method("has_server_service_role") and bool(CloudAPI.call("has_server_service_role"))
		var download_result: Dictionary = {}
		for attempt in range(4):
			download_result = await CloudAPI.download_map_with_cache(
				clean_map_id,
				clean_cloud_version_id,
				clean_map_name if not clean_map_name.is_empty() else "Cloud Map",
				use_service_role
			)
			if bool(download_result.get("ok", false)):
				break
			if attempt < 3:
				await get_tree().create_timer(0.45).timeout
		if not bool(download_result.get("ok", false)):
			return {
				"ok": false,
				"error": "Failed to cache cloud map '%s': %s" % [clean_map_id, str(download_result.get("error", "unknown error"))],
				"map_id": clean_map_id,
				"map_name": clean_map_name,
				"cloud_version_id": clean_cloud_version_id
			}
		selected_folder = str(download_result.get("folder", "")).strip_edges()
		if clean_cloud_version_id.is_empty():
			clean_cloud_version_id = str(download_result.get("cloud_version_id", "")).strip_edges()
	return {
		"ok": true,
		"folder": selected_folder,
		"map_id": clean_map_id,
		"map_name": clean_map_name,
		"cloud_version_id": clean_cloud_version_id
	}

func _read_map_data_dictionary(map_folder: String) -> Dictionary:
	var clean_folder: String = map_folder.strip_edges()
	if clean_folder.is_empty():
		return {}
	var path := clean_folder.path_join("map_data.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var json_text := file.get_as_text()
	file.close()
	if json.parse(json_text) != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _read_map_data_dictionary_async(map_folder: String) -> Dictionary:
	var clean_folder := map_folder.strip_edges()
	if clean_folder.is_empty():
		return {}
	var path := clean_folder.path_join("map_data.json")
	if not FileAccess.file_exists(path):
		return {}
	var worker := Thread.new()
	var start_error := worker.start(_read_map_data_path_worker.bind(path))
	if start_error != OK:
		return _read_map_data_dictionary(clean_folder)
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is Dictionary else {}

static func _read_map_data_path_worker(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _clear_room_runtime_map(room_id: String) -> void:
	var clean_room_id: String = room_id.strip_edges()
	_clear_room_chaos_runtime(clean_room_id)
	var map_root: Node3D = _room_runtime_map_roots.get(clean_room_id, null) as Node3D
	if map_root != null and is_instance_valid(map_root):
		for child in map_root.get_children():
			child.free()
	_room_runtime_fallback_spawns[clean_room_id] = []
	_room_runtime_teleports[clean_room_id] = {}
	_room_runtime_player_settings[clean_room_id] = _get_default_player_settings()
	_room_runtime_mode_settings[clean_room_id] = _get_default_mode_settings()
	_room_runtime_roblox_manifests[clean_room_id] = {}
	if clean_room_id == _get_effective_local_room_id():
		_clear_runtime_roblox_ui()

func _clear_room_chaos_runtime(room_id: String) -> void:
	var clean_room_id: String = room_id.strip_edges()
	var car_ids_to_remove: Array[String] = []
	for car_id_variant in _chaos_cars_by_id.keys():
		var car_id := str(car_id_variant)
		var car_node: Node = _chaos_cars_by_id[car_id_variant]
		if car_node != null and is_instance_valid(car_node) and str(car_node.get("room_id")).strip_edges() == clean_room_id:
			car_node.queue_free()
			car_ids_to_remove.append(car_id)
	for car_id in car_ids_to_remove:
		_chaos_cars_by_id.erase(car_id)
	var owner_keys_to_remove: Array = []
	for peer_variant in _chaos_car_id_by_owner.keys():
		if car_ids_to_remove.has(str(_chaos_car_id_by_owner[peer_variant])):
			owner_keys_to_remove.append(peer_variant)
	for peer_variant in owner_keys_to_remove:
		_chaos_car_id_by_owner.erase(peer_variant)
	var destructible_keys: Array[String] = []
	for key_variant in _destructible_blocks_by_key.keys():
		var key := str(key_variant)
		if key.begins_with("%s::" % clean_room_id):
			destructible_keys.append(key)
	for key in destructible_keys:
		_destructible_blocks_by_key.erase(key)

func _free_room_runtime(room_id: String) -> void:
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return
	_clear_room_chaos_runtime(clean_room_id)
	var room_root: Node3D = _room_runtime_roots.get(clean_room_id, null) as Node3D
	if room_root != null and is_instance_valid(room_root) and not room_root.is_queued_for_deletion():
		room_root.queue_free()
	_room_runtime_roots.erase(clean_room_id)
	_room_runtime_map_roots.erase(clean_room_id)
	_room_runtime_fallback_spawns.erase(clean_room_id)
	_room_runtime_teleports.erase(clean_room_id)
	_room_runtime_player_settings.erase(clean_room_id)
	_room_runtime_mode_settings.erase(clean_room_id)
	_room_runtime_roblox_manifests.erase(clean_room_id)
	_room_runtime_map_folders.erase(clean_room_id)
	_room_runtime_map_ids.erase(clean_room_id)
	_room_runtime_cloud_versions.erase(clean_room_id)
	if clean_room_id == _get_effective_local_room_id():
		_clear_runtime_roblox_ui()

func _generate_default_ground_for_room(room_id: String, map_target: Node3D) -> void:
	if map_target == null:
		return
	var mesh_inst := MeshInstance3D.new()
	var mesh_resource := BoxMesh.new()
	mesh_resource.size = Vector3(40, 1, 40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.55, 0.45, 1.0)
	mesh_resource.surface_set_material(0, mat)
	mesh_inst.mesh = mesh_resource
	mesh_inst.position = Vector3(0, -0.5, 0)
	mesh_inst.set_meta("room_id", room_id)
	mesh_inst.set_meta("material_type", "Grass")
	mesh_inst.set_meta("surface_type", "Grass")
	mesh_inst.set_meta("bobux_color", mat.albedo_color)
	var static_body := StaticBody3D.new()
	static_body.set_meta("material_type", "Grass")
	static_body.set_meta("surface_type", "Grass")
	var coll_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(40, 1, 40)
	coll_shape.shape = box_shape
	static_body.add_child(coll_shape)
	mesh_inst.add_child(static_body)
	map_target.add_child(mesh_inst)
	_register_fallback_spawn_surface(mesh_inst, room_id)

func _load_map_into_room_runtime(room_id: String, map_folder: String, map_target: Node3D) -> Dictionary:
	map_target.set_meta("bobux_map_asset_folder", map_folder)
	var clean_room_id: String = room_id.strip_edges()
	var clean_map_folder: String = map_folder.strip_edges()
	_room_runtime_player_settings[clean_room_id] = _get_default_player_settings()
	_room_runtime_mode_settings[clean_room_id] = _get_default_mode_settings()
	_room_runtime_roblox_manifests[clean_room_id] = {}
	_room_runtime_fallback_spawns[clean_room_id] = []
	_room_runtime_teleports[clean_room_id] = {}
	if clean_map_folder.is_empty():
		_generate_default_ground_for_room(clean_room_id, map_target)
		return {"ok": true, "room_id": clean_room_id, "map_folder": ""}
	var data: Dictionary = await _read_map_data_dictionary_async(clean_map_folder)
	if data.is_empty():
		return {
			"ok": false,
			"error": "Cached room map data is empty or unreadable.",
			"room_id": clean_room_id,
			"map_folder": clean_map_folder
		}
	_room_runtime_player_settings[clean_room_id] = data.get("player_settings", _get_default_player_settings())
	_room_runtime_mode_settings[clean_room_id] = data.get("mode_settings", _get_default_mode_settings())
	_room_runtime_roblox_manifests[clean_room_id] = data.get("roblox_manifest", {}) if data.get("roblox_manifest", {}) is Dictionary else {}
	var blocks: Array = data.get("blocks", [])
	var blocks_loaded: int = 0
	for block_data in blocks:
		var pos := Vector3(
			block_data.get("px", 0.0),
			block_data.get("py", 0.0),
			block_data.get("pz", 0.0)
		)
		var col := _color_from_block_data(block_data, Color.WHITE)
		var shape_type: String = block_data.get("shape", "Box")
		var mat_type: String = block_data.get("material", "Plastic")
		var transparency: float = block_data.get("transparency", 0.0)
		var can_collide: bool = block_data.get("can_collide", true)
		var is_water_volume := mat_type.strip_edges().to_lower() == "water"
		if is_water_volume:
			can_collide = false
		var deals_damage: bool = block_data.get("deals_damage", false)
		var damage_amount: float = float(block_data.get("damage_amount", 25.0))
		if shape_type == "KillPart":
			shape_type = "Box"
			deals_damage = true
			damage_amount = maxf(damage_amount, 100.0)
		if shape_type == "Obby1" or shape_type == "Obby2":
			await _instantiate_template_block_async(shape_type, block_data, pos, map_target, clean_room_id)
			blocks_loaded += 1
			if blocks_loaded % MAP_LOAD_BLOCKS_PER_FRAME == 0:
				await get_tree().process_frame
			continue
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = _make_runtime_node_name(str(block_data.get("name", "")), "%s_block" % shape_type)
		var mesh_resource: Mesh = _create_mesh_for_shape(shape_type)
		var mat := _create_material(col, mat_type, transparency)
		if _should_apply_saved_roblox_block_material(block_data):
			var roblox_props: Dictionary = (block_data.get("roblox_properties", {}) as Dictionary).duplicate(true)
			mat = _runtime_rbxl_material_cache.get_part_material_with_color(roblox_props, col)
		mesh_resource.surface_set_material(0, mat)
		mesh_inst.mesh = mesh_resource
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
		mesh_inst.set_meta("shape_type", shape_type)
		mesh_inst.set_meta("can_collide", can_collide)
		mesh_inst.set_meta("deals_damage", deals_damage)
		mesh_inst.set_meta("damage_amount", damage_amount)
		mesh_inst.set_meta("room_id", clean_room_id)
		_restore_runtime_roblox_block_metadata(mesh_inst, block_data)
		mesh_inst.set_meta("material_type", mat_type)
		mesh_inst.set_meta("surface_type", mat_type)
		_apply_saved_bobux_mesh_resource(mesh_inst, block_data, clean_map_folder)
		_apply_saved_roblox_mesh_asset(mesh_inst, block_data, clean_map_folder)
		mesh_inst.set_meta("bobux_color", col)
		if block_data.has("vehicle_color"):
			mesh_inst.set_meta("vehicle_color", block_data.get("vehicle_color"))
		if block_data.has("vehicle_kind"):
			mesh_inst.set_meta("vehicle_kind", block_data.get("vehicle_kind"))
		if bool(block_data.get("breakable", shape_type == "Destructible")):
			mesh_inst.set_meta("breakable", true)
			mesh_inst.set_meta("health", int(block_data.get("health", 35)))
			mesh_inst.add_to_group("destructible_blocks")
		var is_spawn_block: bool = shape_type == "Spawn" or bool(block_data.get("is_spawn", false))
		if is_spawn_block:
			mesh_inst.add_to_group(_get_room_spawn_group_name(clean_room_id))
			mesh_inst.add_child(_create_spawn_decal_node(mesh_inst.scale))
		map_target.add_child(mesh_inst)
		var coll_shape := _attach_runtime_block_physics(mesh_inst, block_data, shape_type, mat_type, can_collide, map_target)
		if is_water_volume:
			_attach_runtime_water_volume(mesh_inst, coll_shape)
		_configure_runtime_special_object(mesh_inst, shape_type, col, clean_room_id)
		_configure_runtime_damage_block(mesh_inst, deals_damage, damage_amount)
		_configure_runtime_ai_components(mesh_inst, block_data)
		if bool(mesh_inst.get_meta("breakable", false)):
			_register_destructible_block(mesh_inst, clean_room_id)
		if can_collide and not deals_damage and shape_type != "Teleport" and not _block_uses_dynamic_physics(block_data):
			_register_fallback_spawn_surface(mesh_inst, clean_room_id)
		blocks_loaded += 1
		if blocks_loaded % MAP_LOAD_BLOCKS_PER_FRAME == 0:
			await get_tree().process_frame
	var loaded_runtime_refs := await _load_runtime_objects_into_map(data.get("runtime_objects", []), map_target, Vector3.ZERO, clean_room_id)
	await _apply_roblox_manifest_to_runtime_root(map_target, _room_runtime_roblox_manifests.get(clean_room_id, {}), loaded_runtime_refs, Vector3.ZERO, clean_room_id)
	return {
		"ok": true,
		"room_id": clean_room_id,
		"map_folder": clean_map_folder
	}

func _ensure_server_room_runtime(room_id: String, room_state: Dictionary) -> Dictionary:
	var key := room_id.strip_edges()
	if _room_runtime_preparations.has(key):
		var pending: Dictionary = _room_runtime_preparations[key]
		while bool(pending.loading):
			await get_tree().process_frame
		if pending.state == room_state:
			return pending.result
		return await _ensure_server_room_runtime(room_id, room_state)
	var job := {"loading": true, "state": room_state.duplicate(true), "result": {}}
	_room_runtime_preparations[key] = job
	var result: Dictionary = await _prepare_server_room_runtime(room_id, room_state)
	job.result = result
	job.loading = false
	_room_runtime_preparations.erase(key)
	return result

func _prepare_server_room_runtime(room_id: String, room_state: Dictionary) -> Dictionary:
	if not _is_dedicated_server_runtime() or not multiplayer.is_server():
		return {"ok": true, "room_id": room_id.strip_edges()}
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		return {"ok": false, "error": "Room id is empty."}
	var desired_map_id: String = str(room_state.get("map_id", "classic")).strip_edges()
	var desired_map_name: String = str(room_state.get("map_name", "Classic")).strip_edges()
	var desired_cloud_version_id: String = str(room_state.get("cloud_version_id", "")).strip_edges()
	var runtime_nodes: Dictionary = _ensure_room_runtime_root(clean_room_id)
	var map_root: Node3D = runtime_nodes.get("map_root", null) as Node3D
	if map_root == null:
		return {"ok": false, "error": "Room map root is unavailable."}
	var existing_map_id: String = str(_room_runtime_map_ids.get(clean_room_id, "")).strip_edges()
	var existing_cloud_version_id: String = str(_room_runtime_cloud_versions.get(clean_room_id, "")).strip_edges()
	if existing_map_id == desired_map_id and existing_cloud_version_id == desired_cloud_version_id and map_root.get_child_count() > 0:
		return {"ok": true, "room_id": clean_room_id}
	_clear_room_runtime_map(clean_room_id)
	var folder_result: Dictionary = await _resolve_room_map_folder_async(desired_map_id, desired_map_name, desired_cloud_version_id)
	if not bool(folder_result.get("ok", false)):
		return folder_result
	var clean_map_folder: String = str(folder_result.get("folder", "")).strip_edges()
	_room_runtime_map_ids[clean_room_id] = desired_map_id
	_room_runtime_cloud_versions[clean_room_id] = str(folder_result.get("cloud_version_id", desired_cloud_version_id)).strip_edges()
	_room_runtime_map_folders[clean_room_id] = clean_map_folder
	var load_result: Dictionary = await _load_map_into_room_runtime(clean_room_id, clean_map_folder, map_root)
	if not bool(load_result.get("ok", false)):
		return load_result
	print("[RoomHub] Loaded room runtime '%s' map=%s origin=%s." % [clean_room_id, desired_map_id if not desired_map_id.is_empty() else "classic", str(_get_room_world_origin(clean_room_id))])
	return {
		"ok": true,
		"room_id": clean_room_id,
		"map_id": desired_map_id,
		"map_name": desired_map_name,
		"cloud_version_id": _room_runtime_cloud_versions[clean_room_id],
		"map_folder": clean_map_folder
	}

func _clear_peer_runtime_state(peer_id: int, remove_player: bool = true, preserve_local_player: bool = true) -> void:
	if peer_id <= 0:
		return
	var existing_player: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	var local_player: CharacterBody3D = _get_local_player()
	var should_remove_player: bool = remove_player and existing_player != null and (not preserve_local_player or existing_player != local_player)
	if should_remove_player:
		if multiplayer.is_server():
			_despawn_player_for_peer(peer_id)
		elif existing_player != null and existing_player != local_player and not existing_player.is_queued_for_deletion():
			existing_player.queue_free()
	peer_colors.erase(peer_id)
	peer_usernames.erase(peer_id)
	peer_profiles.erase(peer_id)
	peer_avatar_visuals.erase(peer_id)
	_peer_checkpoint_positions.erase(peer_id)
	_peer_spawn_infos.erase(peer_id)
	_peer_teleport_ready_at_msec.erase(peer_id)
	_peer_tool_damage_ready_at_msec.erase(peer_id)
	peer_user_ids.erase(peer_id)
	_peer_registered.erase(peer_id)
	_pending_existing_peer_snapshots.erase(str(peer_id))
	_pending_existing_peer_snapshot_jobs.erase(str(peer_id))

func _disconnect_scene_peer(peer_id: int) -> bool:
	if peer_id <= 0:
		return false
	if multiplayer != null and multiplayer.has_method("disconnect_peer"):
		multiplayer.call("disconnect_peer", peer_id)
		return true
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null and peer.has_method("disconnect_peer"):
		peer.call("disconnect_peer", peer_id, true)
		return true
	return false

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == 1 and NetworkManager != null and NetworkManager.is_host():
		print("[Session] Ignoring stale host-disconnect callback on promoted host.")
		return
	if _should_preserve_nodes_during_disconnect():
		print("[Session] Peer " + str(peer_id) + " disconnected during migration; preserving nodes.")
		return
	_clear_peer_runtime_state(peer_id, multiplayer.is_server(), true)
	call_deferred("_dedupe_player_nodes")
	print("[Session] Peer " + str(peer_id) + " disconnected.")

func _on_connected_to_server(_peer_id: int) -> void:
	_show_network_loading("Syncing...", "Registering your avatar and waiting for spawn.", 0.72)
	print("[Client] Connected as peer %s via %s. Sending avatar..." % [str(_get_runtime_local_peer_id()), NetworkManager.get_active_transport_label()])
	_host_last_pong_msec = Time.get_ticks_msec()
	_start_host_keepalive()
	_register_local_color_with_server()

func _on_connection_failed(_message: String) -> void:
	if NetworkManager.is_host() or NetworkManager.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_stop_host_keepalive()
	_set_gameplay_frozen(false)
	_smart_play_failed = GameState.launch_mode == GameState.LaunchMode.SMART_PLAY
	_reset_network_state()
	_hide_network_loading()
	var resolved_message: String = _message.strip_edges()
	print("[Client] Connection failed%s" % (": " + resolved_message if not resolved_message.is_empty() else "."))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Always return to lobby with the error message so the user is never stranded
	GameState.set_network_error(resolved_message if not resolved_message.is_empty() else "Could not connect to this room.")
	GameState.clear_launch_mode()
	call_deferred("_return_to_lobby_after_connection_failure")

func _return_to_lobby_after_connection_failure() -> void:
	if get_tree() == null:
		return
	if NetworkManager != null and NetworkManager.has_method("prepare_for_lobby"):
		NetworkManager.prepare_for_lobby()
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

# AUDIT FIX VULN-2: Server-side chat bubble relay. Clients call
# _relay_chat_bubble_to_server() which validates rate-limit + content
# length, then broadcasts the chat bubble authoritatively to all room peers.
func _relay_chat_bubble_to_server(target_peer_id: int, text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if clean_text.length() > CHAT_BUBBLE_MAX_LENGTH:
		clean_text = clean_text.left(CHAT_BUBBLE_MAX_LENGTH)
	if multiplayer.multiplayer_peer == null:
		# Offline: display locally
		var player_node: CharacterBody3D = _find_player_node_by_peer_id(target_peer_id)
		if player_node != null and player_node.has_method("show_chat_bubble"):
			player_node.call("show_chat_bubble", clean_text)
		return
	if multiplayer.is_server():
		_process_chat_bubble_on_server(target_peer_id, clean_text)
	else:
		_request_chat_bubble_relay.rpc_id(1, clean_text)

@rpc("any_peer", "reliable")
func _request_chat_bubble_relay(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if clean_text.length() > CHAT_BUBBLE_MAX_LENGTH:
		clean_text = clean_text.left(CHAT_BUBBLE_MAX_LENGTH)
	_process_chat_bubble_on_server(sender_id, clean_text)

func _process_chat_bubble_on_server(peer_id: int, text: String) -> void:
	if peer_id <= 0 or text.strip_edges().is_empty():
		return
	# Rate-limit per peer
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_peer_last_chat_bubble_msec.get(peer_id, 0))
	if now_msec - last_msec < CHAT_BUBBLE_SERVER_RATE_LIMIT_MS:
		return
	_peer_last_chat_bubble_msec[peer_id] = now_msec
	var player_node: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if player_node == null or not player_node.has_method("show_chat_bubble"):
		return
	# Display locally on the server (for dedicated server rendering, if any)
	player_node.show_chat_bubble(text)
	# Broadcast to all peers in the SAME ROOM only — not all connected peers.
	# Using rpc_id() per peer instead of .rpc() because .rpc() would send
	# to peers in OTHER rooms on a multi-room dedicated server.
	var room_id: String = _get_peer_room_id(peer_id)
	for broadcast_peer_id in _get_room_broadcast_peer_ids(room_id):
		player_node.show_chat_bubble.rpc_id(broadcast_peer_id, text)

func _on_server_disconnected() -> void:
	if NetworkManager != null and NetworkManager.is_host():
		# Ignore stale disconnect callbacks from the pre-migration client transport.
		print("[Main][Migration] Ignored stale server_disconnected callback after host promotion.")
		return
	if NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		# During migration: only freeze + corner badge. NEVER show the big loading overlay.
		_set_gameplay_frozen(true)
		_show_migration_corner_badge()
		return
	_stop_host_keepalive()
	_set_gameplay_frozen(false)
	_reset_network_state()
	_hide_network_loading()
	print("[Client] Server disconnected.")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

@rpc("any_peer", "reliable")
func _register_player_color(chosen_colors: Dictionary, chosen_username: String = "Player", chosen_user_id: String = "") -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var sender_room_id: String = NetworkManager.get_peer_room_id(sender_id) if NetworkManager != null and NetworkManager.has_method("get_peer_room_id") else ""
	if sender_room_id.is_empty():
		push_warning("[RoomHub] Rejecting peer %d color registration because no room assignment exists." % sender_id)
		_disconnect_scene_peer(sender_id)
		return
	# AUDIT FIX HIGH-2: Prevent repeated _register_player_color calls from
	# overwriting peer names or triggering redundant spawn + snapshot work.
	if _peer_registered.has(sender_id):
		push_warning("[RoomHub] Ignoring duplicate color registration from peer %d." % sender_id)
		return
	# AUDIT FIX VULN-3: Validate payload BEFORE marking peer as registered.
	# Previously _peer_registered was set first, and if the size check failed
	# and erased it, a second call could bypass the duplicate guard.
	if JSON.stringify(chosen_colors).length() > 4096:
		push_warning("[RoomHub] Rejecting oversized color payload from peer %d." % sender_id)
		return
	_peer_registered[sender_id] = true
	var clean_user_id: String = chosen_user_id.strip_edges()
	var replaced_peer_id: int = 0
	if not clean_user_id.is_empty():
		replaced_peer_id = _find_peer_by_user_id(clean_user_id)
		if replaced_peer_id > 0 and replaced_peer_id != sender_id:
			push_warning("[RoomHub] Rejecting duplicate login for user %s on peer %d (already active on peer %d)." % [clean_user_id, sender_id, replaced_peer_id])
			_peer_registered.erase(sender_id)
			rpc_id(sender_id, "_reject_duplicate_session", DUPLICATE_SESSION_ERROR_MESSAGE)
			if NetworkManager != null and NetworkManager.has_method("server_evict_peer"):
				NetworkManager.server_evict_peer(sender_id)
			_disconnect_scene_peer(sender_id)
			return
		peer_user_ids[sender_id] = clean_user_id
	call_deferred("_finalize_player_registration_async", sender_id, chosen_colors.duplicate(true), chosen_username, clean_user_id, replaced_peer_id, sender_room_id)

func _finalize_player_registration_async(sender_id: int, chosen_colors: Dictionary, chosen_username: String, clean_user_id: String, replaced_peer_id: int, sender_room_id: String) -> void:
	if not _is_peer_id_live_for_session(sender_id):
		_peer_registered.erase(sender_id)
		return
	var conflicting_peer_id: int = replaced_peer_id
	if conflicting_peer_id <= 0 and not clean_user_id.is_empty():
		conflicting_peer_id = _find_peer_by_user_id(clean_user_id)
	if conflicting_peer_id > 0 and conflicting_peer_id != sender_id:
		push_warning("[RoomHub] Rejecting late duplicate registration for user %s on peer %d (already active on peer %d)." % [clean_user_id, sender_id, conflicting_peer_id])
		_peer_registered.erase(sender_id)
		rpc_id(sender_id, "_reject_duplicate_session", DUPLICATE_SESSION_ERROR_MESSAGE)
		if NetworkManager != null and NetworkManager.has_method("server_evict_peer"):
			NetworkManager.server_evict_peer(sender_id)
		_disconnect_scene_peer(sender_id)
		return
	var confirmed_room_id: String = NetworkManager.get_peer_room_id(sender_id) if NetworkManager != null and NetworkManager.has_method("get_peer_room_id") else sender_room_id
	if confirmed_room_id.is_empty():
		_peer_registered.erase(sender_id)
		return
	var authoritative_profile: Dictionary = {}
	var authoritative_username: String = chosen_username.strip_edges()
	if not clean_user_id.is_empty() and CloudAPI != null and CloudAPI.has_method("load_player_profile") and CloudAPI.has_server_service_role():
		var profile_result: Dictionary = await CloudAPI.load_player_profile(clean_user_id, true)
		if bool(profile_result.get("ok", false)):
			authoritative_profile = profile_result.get("data", {}) if profile_result.get("data", {}) is Dictionary else {}
		else:
			push_warning("[RoomHub] Could not load authoritative profile for %s: %s" % [clean_user_id, str(profile_result.get("error", "unknown error"))])
	if authoritative_profile.is_empty() and not clean_user_id.is_empty():
		authoritative_profile = {
			"id": clean_user_id,
			"username": authoritative_username
		}
	var profile_username: String = str(authoritative_profile.get("username", "")).strip_edges()
	if not profile_username.is_empty():
		authoritative_username = profile_username
	peer_colors[sender_id] = chosen_colors
	peer_usernames[sender_id] = authoritative_username if not authoritative_username.is_empty() else "Player"
	if not authoritative_profile.is_empty():
		peer_profiles[sender_id] = authoritative_profile.duplicate(true)
		peer_avatar_visuals[sender_id] = _get_avatar_visuals_from_profile(authoritative_profile)
	else:
		peer_avatar_visuals[sender_id] = {
			"face_texture_path": GameState.DEFAULT_FACE_TEXTURE_PATH,
			"chest_badge_texture_path": GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH,
			"shirt_texture_path": "",
			"pants_texture_path": "",
			"equipped_avatar_items": []
		}
	if NetworkManager != null and NetworkManager.has_method("update_peer_room_profile"):
		NetworkManager.update_peer_room_profile(sender_id, clean_user_id, peer_usernames[sender_id], authoritative_profile)
	var room_state: Dictionary = NetworkManager.get_server_room_state(confirmed_room_id) if NetworkManager != null and NetworkManager.has_method("get_server_room_state") else {}
	var runtime_result: Dictionary = await _ensure_server_room_runtime(confirmed_room_id, room_state)
	if not bool(runtime_result.get("ok", false)):
		push_warning("[RoomHub] Could not prepare room runtime '%s': %s" % [confirmed_room_id, str(runtime_result.get("error", "unknown error"))])
		_reject_duplicate_session.rpc_id(sender_id, "Could not prepare the selected room.")
		if NetworkManager != null and NetworkManager.has_method("_disconnect_peer_after_reject"):
			NetworkManager.call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	if not multiplayer.get_peers().has(sender_id):
		return
	_spawn_player_for_peer(sender_id)
	if _find_player_node_by_peer_id(sender_id) == null:
		_reject_duplicate_session.rpc_id(sender_id, "Could not create your character. Please reconnect.")
		if NetworkManager != null and NetworkManager.has_method("_disconnect_peer_after_reject"):
			NetworkManager.call_deferred("_disconnect_peer_after_reject", sender_id)
		return
	# FIX B (Death Loop): After spawning the peer, tell the client which map to load.
	# The client does NOT load any map until it receives this RPC.
	var confirm_payload: Dictionary = {
		"tool_damage_protocol": 1,
		"map_id": str(room_state.get("map_id", GameState.get_selected_map_identifier())),
		"map_name": str(room_state.get("map_name", GameState.get_selected_map_display_name())),
		"cloud_version_id": str(room_state.get("cloud_version_id", "")),
		"map_folder": GameState.selected_map_folder if str(room_state.get("map_id", "")) == GameState.get_selected_map_identifier() else ""
	}
	_confirm_room_join.rpc_id(sender_id, confirm_payload)
	if _should_send_existing_snapshot_fallback():
		call_deferred("_send_existing_players_snapshots_to_peer_async", sender_id)
	print("[Host] Spawned peer %d in room %s" % [sender_id, confirmed_room_id])

func _send_existing_players_snapshots_to_peer_async(target_peer_id: int) -> void:
	# Give MultiplayerSpawner enough time to replay authoritative spawns first.
	# Snapshots are then used for correction instead of racing with base spawn.
	await get_tree().create_timer(0.65).timeout
	_send_existing_players_snapshots_to_peer(target_peer_id)

# This function sends the current runtime snapshots of already-present players to a newly joined peer.
# It prevents "invisible host" cases after migration where old preserved nodes are not replayed by MultiplayerSpawner.
func _send_existing_players_snapshots_to_peer(target_peer_id: int) -> void:
	if not multiplayer.is_server() or target_peer_id <= 0 or players == null:
		return
	for child in players.get_children():
		if not (child is CharacterBody3D):
			continue
		var character: CharacterBody3D = child as CharacterBody3D
		var peer_id: int = _extract_peer_id_from_player(character)
		if peer_id <= 0 or peer_id == target_peer_id:
			continue
		if NetworkManager != null and NetworkManager.has_method("are_peers_in_same_room") and not NetworkManager.are_peers_in_same_room(peer_id, target_peer_id):
			continue
		rpc_id(target_peer_id, "_sync_existing_peer_snapshot", _build_existing_peer_snapshot(peer_id, character))

# This function builds one compact spawn + runtime snapshot for syncing existing peers to a late joiner.
func _build_existing_peer_snapshot(peer_id: int, character: CharacterBody3D) -> Dictionary:
	var spawn_info := _get_spawn_info_for_peer(peer_id)
	var room_id: String = NetworkManager.get_peer_room_id(peer_id) if NetworkManager != null and NetworkManager.has_method("get_peer_room_id") else ""
	# AUDIT FIX HIGH-1: Do not include raw Bobux user_id in peer snapshots
	# sent over the network. The user_id is a privacy-sensitive UUID that
	# should never be transmitted to other clients.
	var snapshot: Dictionary = {
		"peer_id": peer_id,
		"room_id": room_id,
		"colors": peer_colors.get(peer_id, _get_current_colors()),
		"username": peer_usernames.get(peer_id, "Player"),
		"user_id": "",
		"avatar_visuals": peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals()),
		"player_settings": _get_room_player_settings(room_id),
		"spawn_position": character.position if character != null else spawn_info.get("position", Vector3.ZERO),
		"spawn_points": spawn_info.get("points", []),
		"spawn_index": spawn_info.get("index", -1),
		"state": _build_character_runtime_state(character)
	}
	if _peer_checkpoint_positions.has(peer_id):
		snapshot["has_checkpoint"] = true
		snapshot["checkpoint_position"] = _peer_checkpoint_positions[peer_id]
	return snapshot

# This function converts one snapshot payload back into spawn_data that _spawn_custom understands.
func _build_spawn_data_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var peer_id: int = int(snapshot.get("peer_id", 0))
	var room_id: String = str(snapshot.get("room_id", "")).strip_edges()
	var spawn_data: Dictionary = {
		"peer_id": peer_id,
		"room_id": room_id,
		"colors": snapshot.get("colors", _get_current_colors()),
		"username": snapshot.get("username", "Player"),
		"avatar_visuals": snapshot.get("avatar_visuals", peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals())),
		"player_settings": snapshot.get("player_settings", _get_room_player_settings(room_id)),
		"spawn_position": snapshot.get("spawn_position", _get_spawn_position_for_peer(peer_id)),
		"spawn_points": snapshot.get("spawn_points", []),
		"spawn_index": int(snapshot.get("spawn_index", -1))
	}
	if bool(snapshot.get("has_checkpoint", false)):
		spawn_data["has_checkpoint"] = true
		spawn_data["checkpoint_position"] = snapshot.get("checkpoint_position", spawn_data["spawn_position"])
	_set_spawn_info_for_peer(peer_id, {
		"position": spawn_data.get("spawn_position", Vector3.ZERO),
		"points": spawn_data.get("spawn_points", []),
		"index": spawn_data.get("spawn_index", -1)
	})
	return spawn_data

# This function performs a safe fallback spawn for one snapshot when the node is still missing on a late-joining client.
func _spawn_player_from_snapshot_if_missing(snapshot: Dictionary) -> CharacterBody3D:
	if players == null:
		return null
	if not _should_send_existing_snapshot_fallback():
		return null
	var peer_id: int = int(snapshot.get("peer_id", 0))
	if peer_id <= 0:
		return null
	var existing: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if existing != null:
		return existing
	var state: Dictionary = snapshot.get("state", {}) if snapshot.get("state", {}) is Dictionary else {}
	var spawned: CharacterBody3D = _spawn_local_player_direct(peer_id, state)
	if spawned == null:
		return null
	var spawn_data: Dictionary = _build_spawn_data_from_snapshot(snapshot)
	if spawned.has_method("assign_network_room"):
		spawned.call("assign_network_room", str(spawn_data.get("room_id", "")).strip_edges())
	if spawned.has_method("apply_movement_settings"):
		spawned.call("apply_movement_settings", spawn_data.get("player_settings", _get_default_player_settings()))
	var spawn_room_id := str(spawn_data.get("room_id", "")).strip_edges()
	if spawned.has_method("set_network_position_origin"):
		spawned.call("set_network_position_origin", _get_room_network_position_origin(spawn_room_id))
	spawned.position = _server_to_local_room_position(spawn_data.get("spawn_position", spawned.position), spawn_room_id)
	spawned.set("network_position", _local_to_server_room_position(spawned.position, spawn_room_id))
	if spawned.has_method("configure_spawn_points"):
		spawned.call("configure_spawn_points", _server_to_local_room_points(spawn_data.get("spawn_points", []), spawn_room_id), int(spawn_data.get("spawn_index", -1)))
	if spawned.has_method("set_initial_spawn_position"):
		spawned.call("set_initial_spawn_position", _server_to_local_room_position(spawn_data.get("spawn_position", spawned.position), spawn_room_id))
	if bool(spawn_data.get("has_checkpoint", false)) and spawned.has_method("restore_checkpoint_state"):
		spawned.call("restore_checkpoint_state", _server_to_local_room_position(spawn_data.get("checkpoint_position", spawned.position), spawn_room_id))
	_apply_peer_visual_identity_to_player(spawned, peer_id)
	return spawned

func _should_send_existing_snapshot_fallback() -> bool:
	if NetworkManager != null and NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return true
	if _handover_payload_cache.size() > 0:
		return true
	if _migration_peer_states.size() > 0:
		return true
	return _post_migration_guard_until_msec > Time.get_ticks_msec()

func _resolve_pending_existing_peer_snapshot_async(peer_id: int) -> void:
	var string_id: String = str(peer_id)
	if players == null:
		_pending_existing_peer_snapshot_jobs.erase(string_id)
		return
	var wait_frames: int = SNAPSHOT_SPAWN_WAIT_FRAMES
	while wait_frames > 0:
		if _find_player_node_by_peer_id(peer_id) != null:
			break
		if not _pending_existing_peer_snapshots.has(string_id):
			_pending_existing_peer_snapshot_jobs.erase(string_id)
			return
		wait_frames -= 1
		await get_tree().process_frame
	if not _pending_existing_peer_snapshots.has(string_id):
		_pending_existing_peer_snapshot_jobs.erase(string_id)
		return
	var snapshot: Dictionary = _pending_existing_peer_snapshots[string_id] if _pending_existing_peer_snapshots[string_id] is Dictionary else {}
	if snapshot.is_empty():
		_pending_existing_peer_snapshots.erase(string_id)
		_pending_existing_peer_snapshot_jobs.erase(string_id)
		return
	var existing_player: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if existing_player == null:
		existing_player = _spawn_player_from_snapshot_if_missing(snapshot)
	if existing_player != null:
		var state: Dictionary = snapshot.get("state", {}) if snapshot.get("state", {}) is Dictionary else {}
		_apply_character_runtime_state(existing_player, state)
		_apply_peer_visual_identity_to_player(existing_player, peer_id)
	_pending_existing_peer_snapshots.erase(string_id)
	_pending_existing_peer_snapshot_jobs.erase(string_id)
	call_deferred("_dedupe_player_nodes")

# This function recreates or updates an already-existing remote peer on the joining client.
@rpc("authority", "reliable")
func _sync_existing_peer_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or players == null:
		return
	var peer_id: int = int(snapshot.get("peer_id", 0))
	if peer_id <= 0:
		return
	if not _snapshot_matches_effective_local_room(peer_id, snapshot):
		return
	var incoming_colors: Dictionary = snapshot.get("colors", {}) if snapshot.get("colors", {}) is Dictionary else {}
	if not incoming_colors.is_empty():
		peer_colors[peer_id] = incoming_colors
	var incoming_username: String = str(snapshot.get("username", "")).strip_edges()
	if not incoming_username.is_empty():
		peer_usernames[peer_id] = incoming_username
	var incoming_avatar_visuals: Variant = snapshot.get("avatar_visuals", {})
	if incoming_avatar_visuals is Dictionary:
		peer_avatar_visuals[peer_id] = (incoming_avatar_visuals as Dictionary).duplicate(true)
	var incoming_user_id: String = str(snapshot.get("user_id", "")).strip_edges()
	if not incoming_user_id.is_empty():
		var existing_peer_id_for_user: int = _find_peer_by_user_id(incoming_user_id)
		if existing_peer_id_for_user > 0 and existing_peer_id_for_user != peer_id:
			var existing_is_live: bool = _is_peer_id_live_for_session(existing_peer_id_for_user)
			var incoming_is_live: bool = _is_peer_id_live_for_session(peer_id)
			if existing_is_live and not incoming_is_live:
				# Drop stale replay rows that would create a ghost clone for a user
				# already represented by the active runtime peer.
				return
			if incoming_is_live and not existing_is_live:
				peer_colors.erase(existing_peer_id_for_user)
				peer_usernames.erase(existing_peer_id_for_user)
				peer_user_ids.erase(existing_peer_id_for_user)
				peer_avatar_visuals.erase(existing_peer_id_for_user)
				_peer_checkpoint_positions.erase(existing_peer_id_for_user)
				var stale_player: CharacterBody3D = _find_player_node_by_peer_id(existing_peer_id_for_user)
				if stale_player != null:
					stale_player.queue_free()
		peer_user_ids[peer_id] = incoming_user_id
	if bool(snapshot.get("has_checkpoint", false)):
		_peer_checkpoint_positions[peer_id] = snapshot.get("checkpoint_position", Vector3.ZERO)
	_pending_existing_peer_snapshots[str(peer_id)] = snapshot.duplicate(true)
	var string_id: String = str(peer_id)
	if not _pending_existing_peer_snapshot_jobs.has(string_id):
		_pending_existing_peer_snapshot_jobs[string_id] = true
		call_deferred("_resolve_pending_existing_peer_snapshot_async", peer_id)

@rpc("any_peer", "call_local", "reliable")
func _sync_checkpoint_for_peer(peer_id: int, checkpoint_position: Vector3) -> void:
	if peer_id <= 0:
		return
	# AUDIT FIX CRITICAL-2: Verify the RPC sender belongs to the same room as
	# the target peer. Without this, a malicious client in Room A could
	# manipulate checkpoint positions for players in Room B.
	if multiplayer.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id > 0 and NetworkManager != null and NetworkManager.has_method("are_peers_in_same_room"):
			if not NetworkManager.are_peers_in_same_room(sender_id, peer_id):
				push_warning("[RoomHub] Rejecting cross-room checkpoint sync from peer %d targeting peer %d." % [sender_id, peer_id])
				return
	_peer_checkpoint_positions[peer_id] = checkpoint_position
	var player_node: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if player_node != null and player_node.has_method("restore_checkpoint_state"):
		player_node.call("restore_checkpoint_state", checkpoint_position)

func _register_local_color_with_server(retry_count: int = 0) -> void:
	var uname: String = UserSession.username if UserSession.is_logged_in else "Player"
	var current_user_id: String = SupabaseClient.get_user_id()
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_register_player_color(_get_current_colors(), uname, current_user_id)
		return
	if not multiplayer.get_peers().has(1):
		if retry_count < 30:
			call_deferred("_register_local_color_with_server", retry_count + 1)
		return
	rpc_id(1, "_register_player_color", _get_current_colors(), uname, current_user_id)

# FIX B (Death Loop): Server-to-client RPC that confirms room join and tells
# the client which map to load. The client does NOT load any map until this
# arrives, preventing the premature local map load that caused the state desync.
@rpc("authority", "call_local", "reliable")
func _confirm_room_join(payload: Dictionary) -> void:
	_server_supports_tool_damage = int(payload.get("tool_damage_protocol", 0)) >= 1
	if _map_loaded or _map_load_in_progress:
		return
	_map_load_in_progress = true
	_runtime_world_ready = false
	_set_gameplay_frozen(true)
	_hide_legacy_runtime_hud_controls()
	if fallback_camera != null:
		fallback_camera.current = true
	var map_folder: String = str(payload.get("map_folder", "")).strip_edges()
	var map_id: String = str(payload.get("map_id", "")).strip_edges()
	var map_name: String = str(payload.get("map_name", "")).strip_edges()
	print("[Client] Room join confirmed by server. map_id=%s map_name=%s" % [map_id, map_name])
	# A server's user:// cache lives on another machine. MapManager has already
	# resolved the agreed version into this client's own cache during room auth.
	if GameState.selected_map_folder.is_empty() and not map_folder.is_empty() and FileAccess.file_exists(map_folder.path_join("map_data.json")):
		GameState.selected_map_folder = map_folder
	elif not map_id.is_empty():
		GameState.selected_map = map_id
	_show_network_loading("Preparing World...", "Downloading and building the map.", 0.86)
	await _load_selected_map()
	for _settle_frame in range(2):
		await get_tree().process_frame
	for _physics_frame in range(2):
		await get_tree().physics_frame
	_map_loaded = true
	_map_load_in_progress = false
	_runtime_world_ready = true
	_show_network_loading("Loading World...", "Finalizing collisions and your character.", 0.97)
	call_deferred("_hide_network_loading_after_spawn_ready")
	# Start the keepalive watchdog only AFTER the server confirmed room join.
	# Previously this ran in _on_connected_to_server, but the server's async
	# profile load could delay _confirm_room_join, causing premature timeouts.
	_host_last_pong_msec = Time.get_ticks_msec()
	_start_host_keepalive()

func _hide_network_loading_after_spawn_ready() -> void:
	var deadline_msec := Time.get_ticks_msec() + CHARACTER_SPAWN_TIMEOUT_MSEC
	while is_inside_tree() and Time.get_ticks_msec() < deadline_msec:
		var local_player: CharacterBody3D = _get_local_player()
		if local_player != null and _runtime_world_ready:
			local_player.visible = true
			if local_player.has_method("_set_collision_enabled"):
				local_player.call("_set_collision_enabled", true)
			_set_gameplay_frozen(false)
			local_player.velocity = Vector3.ZERO
			local_player.call_deferred("reset_physics_interpolation")
			_refresh_player_camera_authority_mode(local_player)
			var camera: Camera3D = local_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
			if camera != null:
				camera.current = true
			if fallback_camera != null:
				fallback_camera.current = false
			_hide_network_loading()
			return
		await get_tree().process_frame
	if fallback_camera != null:
		fallback_camera.current = true
	_show_network_loading("Could Not Spawn", "The server did not spawn your character. Returning to the menu instead of leaving a black screen.", 1.0)
	await get_tree().create_timer(1.8).timeout
	NetworkManager.last_connection_error = "The server did not spawn your character in time."
	GameState.set_network_error(NetworkManager.last_connection_error)
	call_deferred("_return_to_lobby_after_connection_failure")

# This function rejects a second login from the same account so one user cannot drive the room from two windows at once.
@rpc("authority", "call_local", "reliable")
func _reject_duplicate_session(reason: String) -> void:
	_stop_host_keepalive()
	_set_gameplay_frozen(false)
	NetworkManager.last_connection_error = reason
	GameState.set_network_error(reason)
	GameState.clear_launch_mode()
	if NetworkManager != null and NetworkManager.has_method("disconnect_from_session"):
		NetworkManager.disconnect_from_session()
	call_deferred("_return_to_lobby_after_connection_failure")

func _get_current_colors() -> Dictionary:
	return {
		"head": GameState.head_color,
		"torso": GameState.torso_color,
		"left_arm": GameState.left_arm_color,
		"right_arm": GameState.right_arm_color,
		"left_leg": GameState.left_leg_color,
		"right_leg": GameState.right_leg_color
	}

func _get_current_avatar_visuals() -> Dictionary:
	return {
		"face_texture_path": GameState.avatar_face_texture_path,
		"chest_badge_texture_path": GameState.avatar_chest_badge_texture_path,
		"shirt_texture_path": GameState.avatar_shirt_texture_path,
		"pants_texture_path": GameState.avatar_pants_texture_path,
		"equipped_avatar_items": GameState.avatar_equipped_items.duplicate(true)
	}

func _get_avatar_visuals_from_profile(profile_data: Dictionary) -> Dictionary:
	var avatar_data: Dictionary = profile_data.get("avatar_data", {}) if profile_data.get("avatar_data", {}) is Dictionary else {}
	var avatar_outfit: Dictionary = profile_data.get("avatar_outfit", {}) if profile_data.get("avatar_outfit", {}) is Dictionary else {}
	var source := avatar_data.duplicate(true)
	for key in ["face_texture_path", "chest_badge_texture_path", "shirt_texture_path", "pants_texture_path", "equipped_avatar_item_payloads"]:
		if avatar_outfit.has(key):
			source[key] = avatar_outfit.get(key)
	var equipped_items: Array = []
	for key in ["equipped_avatar_item_payloads", "equipped_avatar_items", "avatar_items"]:
		var raw_items: Variant = source.get(key, [])
		if raw_items is Array:
			for raw_item in (raw_items as Array):
				if raw_item is Dictionary:
					equipped_items.append((raw_item as Dictionary).duplicate(true))
			if not equipped_items.is_empty():
				break
	return {
		"face_texture_path": str(source.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)).strip_edges(),
		"chest_badge_texture_path": str(source.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)).strip_edges(),
		"shirt_texture_path": str(source.get("shirt_texture_path", "")).strip_edges(),
		"pants_texture_path": str(source.get("pants_texture_path", "")).strip_edges(),
		"equipped_avatar_items": equipped_items
	}

func _spawn_player_for_peer(peer_id: int) -> void:
	if _find_player_node_by_peer_id(peer_id) != null:
		return
	var room_id: String = NetworkManager.get_peer_room_id(peer_id) if NetworkManager != null and NetworkManager.has_method("get_peer_room_id") else ""
	if not _peer_matches_effective_local_room(peer_id, room_id):
		return
	var spawn_info := _get_spawn_info_for_peer(peer_id)
	_set_spawn_info_for_peer(peer_id, spawn_info)
	var spawn_data: Dictionary = {}
	spawn_data["peer_id"] = peer_id
	spawn_data["room_id"] = room_id
	spawn_data["colors"] = peer_colors.get(peer_id, _get_current_colors())
	spawn_data["username"] = peer_usernames.get(peer_id, "Player")
	spawn_data["avatar_visuals"] = peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals())
	spawn_data["player_settings"] = _get_room_player_settings(room_id)
	spawn_data["spawn_position"] = spawn_info.get("position", Vector3.ZERO)
	spawn_data["spawn_points"] = spawn_info.get("points", [])
	spawn_data["spawn_index"] = spawn_info.get("index", -1)
	if _peer_checkpoint_positions.has(peer_id):
		spawn_data["checkpoint_position"] = _peer_checkpoint_positions[peer_id]
		spawn_data["has_checkpoint"] = true
	if not is_instance_valid(player_spawner) or not is_instance_valid(players):
		push_error("[RoomHub] Player replication containers are unavailable")
		return
	player_spawner.spawn_path = player_spawner.get_path_to(players)
	if player_spawner.spawn(spawn_data) == null:
		push_error("[RoomHub] Failed to create player for peer %d" % peer_id)

func _despawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1 and NetworkManager != null and NetworkManager.is_host():
		return
	var existing_player: CharacterBody3D = _find_player_node_by_peer_id(peer_id)
	if existing_player == null:
		return
	if existing_player == _get_local_player():
		return
	existing_player.queue_free()

func _spawn_custom(spawn_data: Dictionary) -> Node:
	var peer_id: int = int(spawn_data.get("peer_id", 1))
	var spawn_room_id: String = str(spawn_data.get("room_id", "")).strip_edges()
	if not _peer_matches_effective_local_room(peer_id, spawn_room_id):
		return null
	var string_id: String = str(peer_id)
	var chosen_colors: Dictionary = spawn_data.get("colors", _get_current_colors())
	var player_instance: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	player_instance.name = string_id
	player_instance.set_multiplayer_authority(peer_id, true)
	var state_synchronizer: MultiplayerSynchronizer = player_instance.get_node_or_null("StateSynchronizer") as MultiplayerSynchronizer
	if state_synchronizer != null:
		state_synchronizer.root_path = NodePath("..")
		if player_instance.has_method("_configure_state_synchronizer_for"):
			player_instance.call("_configure_state_synchronizer_for", state_synchronizer)
	var spawn_position: Vector3 = spawn_data.get("spawn_position", _get_spawn_position_for_peer(peer_id))
	spawn_position = _server_to_local_room_position(spawn_position, spawn_room_id)
	player_instance.position = spawn_position
	player_instance.set("network_position", _local_to_server_room_position(spawn_position, spawn_room_id))
	if player_instance.has_method("assign_network_room"):
		player_instance.call("assign_network_room", str(spawn_data.get("room_id", "")).strip_edges())
	if player_instance.has_method("set_network_position_origin"):
		player_instance.call("set_network_position_origin", _get_room_network_position_origin(spawn_room_id))

	player_instance.set("head_color", chosen_colors.get("head", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("torso_color", chosen_colors.get("torso", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("left_arm_color", chosen_colors.get("left_arm", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("right_arm_color", chosen_colors.get("right_arm", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("left_leg_color", chosen_colors.get("left_leg", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("right_leg_color", chosen_colors.get("right_leg", GameState.DEFAULT_AVATAR_COLOR))
	player_instance.set("display_name", spawn_data.get("username", "Player"))
	_apply_avatar_visuals_to_player(player_instance, spawn_data.get("avatar_visuals", peer_avatar_visuals.get(peer_id, _get_current_avatar_visuals())))
	if player_instance.has_method("apply_movement_settings"):
		player_instance.call("apply_movement_settings", spawn_data.get("player_settings", _get_default_player_settings()))
	if player_instance.has_method("configure_spawn_points"):
		player_instance.call("configure_spawn_points", _server_to_local_room_points(spawn_data.get("spawn_points", []), spawn_room_id), int(spawn_data.get("spawn_index", -1)))
	if player_instance.has_method("set_initial_spawn_position"):
		player_instance.call("set_initial_spawn_position", player_instance.position)
	if bool(spawn_data.get("has_checkpoint", false)) and player_instance.has_method("restore_checkpoint_state"):
		player_instance.call("restore_checkpoint_state", _server_to_local_room_position(spawn_data.get("checkpoint_position", player_instance.position), spawn_room_id))
	_apply_network_sync_rate(player_instance)
	
	# Restore state if migrating
	if _migration_peer_states.has(string_id):
		var state: Dictionary = _migration_peer_states[string_id]
		_apply_character_runtime_state(player_instance, state)
		call_deferred("_apply_character_runtime_state_late", player_instance.get_instance_id(), state.duplicate(true))
		_migration_peer_states.erase(string_id)
	if _pending_existing_peer_snapshots.has(string_id):
		var pending_snapshot: Dictionary = _pending_existing_peer_snapshots[string_id] if _pending_existing_peer_snapshots[string_id] is Dictionary else {}
		var pending_state: Dictionary = pending_snapshot.get("state", {}) if pending_snapshot.get("state", {}) is Dictionary else {}
		_apply_character_runtime_state(player_instance, pending_state)
		call_deferred("_apply_character_runtime_state_late", player_instance.get_instance_id(), pending_state.duplicate(true))
		_pending_existing_peer_snapshots.erase(string_id)
		
	var runtime_local_peer_id: int = _get_runtime_local_peer_id()
	if runtime_local_peer_id > 0 and peer_id == runtime_local_peer_id:
		if not _runtime_world_ready:
			player_instance.visible = false
			if player_instance.has_method("_set_collision_enabled"):
				player_instance.call("_set_collision_enabled", false)
		call_deferred("_bind_runtime_local_character", player_instance.get_instance_id())
		if _runtime_world_ready:
			call_deferred("_hide_network_loading_after_spawn_ready")
	# FIX Eye Strain Bug (ARCH-4): Reset physics interpolation on the newly
	# spawned player so Godot doesn't interpolate from Vector3.ZERO to the
	# actual spawn position, causing shadow flicker and camera jitter.
	player_instance.call_deferred("reset_physics_interpolation")
	if player_instance.has_method("refresh_camera_authority_mode"):
		player_instance.call_deferred("refresh_camera_authority_mode")
	call_deferred("_dedupe_player_nodes")
	return player_instance

func _spawn_player(spawn_data: Dictionary) -> Node:
	return _spawn_custom(spawn_data)


func _bind_runtime_local_character(character_instance_id: int) -> void:
	var character_variant := instance_from_id(character_instance_id)
	if not (character_variant is Node) or not is_instance_valid(character_variant):
		return
	var character := character_variant as Node
	if LuaScriptEngine != null and LuaScriptEngine.has_method("bind_local_player_character"):
		LuaScriptEngine.bind_local_player_character(character)
	_refresh_runtime_inventory()
	_start_live_player_scripts(character)


func _start_live_player_scripts(character: Node = null) -> void:
	if _is_dedicated_server_runtime():
		return
	for script_node in LuaScriptEngine.collect_live_player_scripts(self, character):
		if script_node.has_meta("bobux_script_runtime_id"):
			continue
		var source := str(script_node.get_meta("lua_source", script_node.get_meta("code", "")))
		if not source.strip_edges().is_empty():
			_queue_runtime_lua_script(script_node, source)

func _get_default_player_settings() -> Dictionary:
	return {
		"move_speed": DEFAULT_PLAYER_MOVE_SPEED,
		"sprint_multiplier": DEFAULT_PLAYER_SPRINT_MULTIPLIER,
		"jump_velocity": DEFAULT_PLAYER_JUMP_VELOCITY
	}

func _get_default_mode_settings() -> Dictionary:
	return {
		"music_playlist": [],
		"music_volume": DEFAULT_MODE_MUSIC_VOLUME,
		"skybox_file": "",
		"roblox_sound_assets": [],
		"roblox_environment": {}
	}

func _apply_mode_settings(mode_settings: Dictionary) -> void:
	var merged_settings := _get_default_mode_settings()
	for key in mode_settings.keys():
		merged_settings[key] = mode_settings[key]
	_map_mode_settings = merged_settings
	_apply_map_music()
	_apply_map_sky()

func _apply_map_music() -> void:
	if _mode_music_player == null:
		return
	_playlist_files.clear()
	var playlist_data: Array = _map_mode_settings.get("music_playlist", [])
	if playlist_data.is_empty():
		var legacy_music_file := str(_map_mode_settings.get("music_file", "")).strip_edges()
		if not legacy_music_file.is_empty():
			playlist_data = [legacy_music_file]
	for file_variant in playlist_data:
		var file_name := str(file_variant).strip_edges()
		if not file_name.is_empty():
			_playlist_files.append(file_name)
	if _playlist_files.is_empty():
		_mode_music_player.stop()
		_mode_music_player.stream = null
		return
	var volume_linear := clampf(float(_map_mode_settings.get("music_volume", DEFAULT_MODE_MUSIC_VOLUME)), 0.0, 1.0)
	_mode_music_player.volume_db = linear_to_db(maxf(volume_linear, 0.0001)) if volume_linear > 0.0 else -80.0
	_play_playlist_track(0)

func _play_playlist_track(track_index: int, attempts: int = 0) -> void:
	if _mode_music_player == null or _playlist_files.is_empty():
		return
	if attempts >= _playlist_files.size():
		return
	_current_playlist_index = posmod(track_index, _playlist_files.size())
	var current_file: String = _playlist_files[_current_playlist_index]
	var download_key: String = _sanitize_map_asset_file_name(current_file)
	if _failed_map_asset_downloads.has(download_key):
		_play_playlist_track(_current_playlist_index + 1, attempts + 1)
		return
	var music_path := _resolve_map_asset_path(current_file)
	var stream := _load_audio_stream_from_path(music_path)
	if stream == null:
		if _start_map_asset_download_if_needed(current_file):
			return
		_play_playlist_track(_current_playlist_index + 1, attempts + 1)
		return
	_mode_music_player.stop()
	_mode_music_player.stream = stream
	_mode_music_player.play()

func _on_mode_music_finished() -> void:
	if _playlist_files.is_empty():
		return
	_play_playlist_track(_current_playlist_index + 1)

func _start_map_asset_download_if_needed(file_name: String) -> bool:
	if CloudAPI == null or not CloudAPI.has_method("download_map_asset_file"):
		return false
	var asset_url: String = _get_map_asset_url(file_name)
	if asset_url.is_empty():
		return false
	var target_path: String = _get_cached_map_asset_path(file_name)
	if target_path.is_empty() or FileAccess.file_exists(target_path):
		return false
	var download_key: String = _sanitize_map_asset_file_name(file_name)
	if _failed_map_asset_downloads.has(download_key):
		return false
	if _pending_map_asset_downloads.has(download_key):
		return true
	_pending_map_asset_downloads[download_key] = true
	call_deferred("_download_map_asset_async", file_name, asset_url, target_path)
	return true

func _download_map_asset_async(file_name: String, asset_url: String, target_path: String) -> void:
	var download_key: String = _sanitize_map_asset_file_name(file_name)
	var result: Dictionary = await CloudAPI.download_map_asset_file(asset_url, target_path)
	_pending_map_asset_downloads.erase(download_key)
	if not bool(result.get("ok", false)):
		_failed_map_asset_downloads[download_key] = Time.get_ticks_msec()
		push_warning("[Main] Failed to download map asset '%s': %s" % [file_name, str(result.get("error", "unknown error"))])
		if _mode_music_player != null and not _mode_music_player.playing and not _playlist_files.is_empty():
			_play_playlist_track(_current_playlist_index + 1)
		return
	if _mode_music_player != null and not _mode_music_player.playing and not _playlist_files.is_empty():
		var downloaded_index: int = _find_playlist_index_for_download_key(download_key)
		if downloaded_index >= 0:
			_play_playlist_track(downloaded_index)

func _find_playlist_index_for_download_key(download_key: String) -> int:
	for index in range(_playlist_files.size()):
		if _sanitize_map_asset_file_name(_playlist_files[index]) == download_key:
			return index
	return -1

func _get_map_asset_url(file_name: String) -> String:
	var candidates: Array[String] = [
		file_name,
		file_name.get_file(),
		_sanitize_map_asset_file_name(file_name)
	]
	for candidate in candidates:
		if _map_asset_urls.has(candidate):
			var asset_url: String = str(_map_asset_urls.get(candidate, "")).strip_edges()
			if not asset_url.is_empty():
				return asset_url
	return ""

func _get_cached_map_asset_path(file_name: String) -> String:
	if GameState.selected_map_folder.is_empty():
		return ""
	return GameState.selected_map_folder.path_join(_sanitize_map_asset_file_name(file_name))

func _sanitize_map_asset_file_name(file_name: String) -> String:
	var sanitized: String = file_name.strip_edges().get_file()
	sanitized = sanitized.replace("\\", "_").replace("/", "_").replace("..", "_")
	return sanitized

func resolve_runtime_tool_texture_path(texture_reference: Variant) -> String:
	var reference := _runtime_asset_reference_to_string(texture_reference)
	if reference.is_empty():
		return ""
	var asset_id := ""
	for index in range(reference.length()):
		var character := reference.substr(index, 1)
		if character >= "0" and character <= "9":
			asset_id += character
	var candidates: Array[String] = [reference, _resolve_map_asset_path(reference)]
	if not asset_id.is_empty():
		for extension in ["asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp", "png", "jpg", "jpeg", "webp"]:
			var file_name := "%s.%s" % [asset_id, extension]
			candidates.append("user://rbxl_assets/" + file_name)
			candidates.append(_resolve_map_asset_path(file_name))
	for candidate in candidates:
		if not candidate.is_empty() and FileAccess.file_exists(candidate):
			return candidate
	# Imported cloud maps publish asset URLs by filename. Queue the first matching
	# texture without blocking inventory refresh or the gameplay frame.
	for candidate in candidates:
		var file_name := candidate.get_file()
		if not file_name.is_empty() and _start_map_asset_download_if_needed(file_name):
			break
	return ""

func _runtime_asset_reference_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		var data := value as Dictionary
		for key in ["value", "url", "path", "asset_id", "id"]:
			var candidate := str(data.get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
		return ""
	if value is Array and not (value as Array).is_empty():
		return _runtime_asset_reference_to_string((value as Array)[0])
	return str(value).strip_edges()

func _apply_map_sky() -> void:
	var env_node: WorldEnvironment = $World/WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var skybox_file := str(_map_mode_settings.get("skybox_file", "")).strip_edges()
	if skybox_file.is_empty():
		var roblox_environment: Dictionary = _map_mode_settings.get("roblox_environment", {}) if _map_mode_settings.get("roblox_environment", {}) is Dictionary else {}
		_apply_roblox_environment_to_runtime_environment(env_node.environment, roblox_environment)
		return
	var image := _load_image_from_path(_resolve_map_asset_path(skybox_file))
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

func _apply_roblox_environment_to_runtime_environment(env: Environment, settings: Dictionary) -> void:
	var sky_color := _color_from_array(settings.get("background_color", [0.52, 0.76, 0.96]), Color(0.52, 0.76, 0.96))
	if settings.has("lighting") and settings["lighting"] is Dictionary and not bool(settings.get("custom_sky_color", false)):
		var lighting: Dictionary = settings["lighting"]
		sky_color = _roblox_sky_color_for_hour(_hour_from_lighting_props(lighting))
	if settings.has("atmosphere") and settings["atmosphere"] is Dictionary:
		var atmosphere: Dictionary = settings["atmosphere"]
		var density := clampf(float(atmosphere.get("Density", 0.0)), 0.0, 1.0)
		sky_color = sky_color.lerp(_color_from_array(atmosphere.get("Color", [0.78, 0.78, 0.78]), Color(0.78, 0.78, 0.78)), density * 0.25)
	if not (settings.has("sky") and settings["sky"] is Dictionary and RobloxSkyMaterial.apply_skybox_from_properties(env, settings["sky"], sky_color)):
		_apply_roblox_procedural_sky(env, sky_color)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _color_from_array(settings.get("ambient_color", [0.56, 0.66, 0.78]), Color(0.56, 0.66, 0.78))
	env.ambient_light_energy = clampf(float(settings.get("ambient_energy", 0.58)), 0.0, 2.0)
	env.glow_enabled = bool(settings.get("glow_enabled", env.glow_enabled))
	env.glow_intensity = clampf(float(settings.get("glow_intensity", env.glow_intensity)), 0.0, 2.0)
	env.glow_bloom = clampf(float(settings.get("glow_bloom", env.glow_bloom)), 0.0, 1.0)
	env.set("fog_enabled", bool(settings.get("fog_enabled", false)))
	env.set("fog_light_color", _color_from_array(settings.get("fog_color", [0.78, 0.78, 0.78]), Color(0.78, 0.78, 0.78)))
	env.set("fog_density", clampf(float(settings.get("fog_density", 0.0)), 0.0, 0.05))

func _apply_roblox_procedural_sky(env: Environment, sky_color: Color) -> void:
	RobloxSkyMaterial.apply_to_environment(env, sky_color)

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

func _should_apply_saved_roblox_block_material(block_data: Dictionary) -> bool:
	if not (block_data.get("roblox_properties", {}) is Dictionary):
		return false
	# A Bobux-authored part has a Roblox class for DataModel compatibility but
	# no imported Roblox material properties. An empty property bag resolves to
	# medium gray, so applying it here would erase the canonical saved color.
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

func _resolve_map_asset_path(file_name: String) -> String:
	if file_name.begins_with("res://") or file_name.begins_with("user://") or file_name.begins_with("/") or file_name.find(":") == 1:
		return file_name
	if GameState.selected_map_folder.is_empty():
		return file_name
	var direct_path: String = GameState.selected_map_folder.path_join(file_name)
	if FileAccess.file_exists(direct_path):
		return direct_path
	return _get_cached_map_asset_path(file_name)

func _load_runtime_objects_into_map(raw_objects: Variant, map_target: Node3D, origin_offset: Vector3 = Vector3.ZERO, room_id: String = "") -> Dictionary:
	var loaded_refs: Dictionary = {}
	if map_target == null or not (raw_objects is Array):
		return loaded_refs
	var created_count := 0
	for object_variant in raw_objects:
		if not (object_variant is Dictionary):
			continue
		var data: Dictionary = object_variant
		var runtime_node := _create_runtime_object_from_map_data(data)
		if runtime_node == null:
			continue
		runtime_node.position += origin_offset
		runtime_node.set_meta("room_id", room_id)
		runtime_node.add_to_group(RBXL_RUNTIME_OBJECT_GROUP)
		map_target.add_child(runtime_node)
		var roblox_ref := str(data.get("roblox_ref", "")).strip_edges()
		if not roblox_ref.is_empty():
			loaded_refs[roblox_ref] = true
		_start_runtime_lua_script_if_needed(runtime_node, data)
		created_count += 1
		if created_count % MAP_LOAD_RUNTIME_OBJECTS_PER_FRAME == 0:
			await get_tree().process_frame
	return loaded_refs

func _apply_roblox_manifest_to_runtime_root(map_target: Node3D, manifest_variant: Variant, loaded_runtime_refs: Dictionary,
		origin_offset: Vector3, room_id: String) -> void:
	if map_target == null or not (manifest_variant is Dictionary):
		return
	var manifest: Dictionary = manifest_variant
	# The manifest can be tens of megabytes. A deep duplicate here used to double
	# peak memory just before DataModel/GUI construction and was enough to crash
	# large published places. The importer and runtime treat it as immutable.
	map_target.set_meta("roblox_class", "Workspace")
	map_target.set_meta("roblox_manifest", manifest.duplicate(false))
	map_target.set_meta("roblox_asset_refs_count", (manifest.get("assets", []) as Array).size() if manifest.get("assets", []) is Array else 0)
	map_target.set_meta("roblox_script_refs_count", (manifest.get("scripts", []) as Array).size() if manifest.get("scripts", []) is Array else 0)
	map_target.set_meta("roblox_constraint_refs_count", (manifest.get("constraints", []) as Array).size() if manifest.get("constraints", []) is Array else 0)
	await _install_roblox_manifest_data_model(manifest, map_target)
	await _load_manifest_scripts_into_map(manifest, loaded_runtime_refs, map_target, origin_offset, room_id)
	await _refresh_runtime_roblox_ui(manifest, room_id)
	var local_character := _get_local_player()
	if is_instance_valid(local_character):
		_bind_runtime_local_character(local_character.get_instance_id())

func _install_roblox_manifest_data_model(manifest: Dictionary, context_node: Node) -> void:
	if LuaScriptEngine == null:
		return
	manifest = preload("res://addons/roblox_runtime/roblox_manifest_assets.gd").resolve(manifest, str(context_node.get_meta("bobux_map_asset_folder", GameState.selected_map_folder)))
	var result: Dictionary = {}
	if LuaScriptEngine.has_method("install_roblox_manifest_async"):
		result = await LuaScriptEngine.install_roblox_manifest_async(manifest, context_node, MAP_LOAD_MANIFEST_NODES_PER_FRAME)
	elif LuaScriptEngine.has_method("install_roblox_manifest"):
		result = LuaScriptEngine.install_roblox_manifest(manifest, context_node)
	else:
		return
	if not bool(result.get("ok", false)):
		push_warning("[Main] Roblox manifest DataModel install failed: %s" % str(result.get("error", "unknown error")))
	else:
		if context_node is Node3D:
			var terrain_restorer = RobloxTerrainEditorClass.new()
			terrain_restorer.restore(null, context_node as Node3D)
		call_deferred("_refresh_runtime_inventory")

func _refresh_runtime_roblox_ui(manifest: Dictionary, room_id: String) -> void:
	if _is_dedicated_server_runtime():
		return
	var clean_room_id := room_id.strip_edges()
	var local_room_id := _get_effective_local_room_id()
	if not clean_room_id.is_empty() and not local_room_id.is_empty() and clean_room_id != local_room_id:
		return
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null and leave_button != null:
		hud = leave_button.get_parent() as CanvasLayer
	if hud == null:
		return
	var gui_host := _ensure_runtime_roblox_gui_host(hud)
	if gui_host == null:
		return
	var gui_options := {
		"root_name": "RobloxRuntimeGui",
		"replace": true,
		"ignore_mouse": false,
		"editor_preview": false,
		"fit_to_viewport": true,
		"design_size": [1366.0, 768.0],
		"suppress_fullscreen_blockers": true,
		"suppress_neutral_fullscreen_frames": true,
		"draw_gui": true,
		# Tools are rendered from the live Backpack/Character DataModel by the
		# inventory controller. The manifest hotbar is preview-only.
		"draw_tools": false,
		"z_index": 80
	}
	var gui_root: Control = await RobloxGuiRuntime.apply_manifest_async(
		gui_host,
		manifest,
		gui_options,
		MAP_LOAD_GUI_CONTROLS_PER_FRAME
	)
	if gui_root != null and LuaScriptEngine != null:
		var map_context: Node = get_node_or_null("MapRoot")
		if map_context == null:
			map_context = self
		if LuaScriptEngine.has_method("bind_gui_controls_async"):
			await LuaScriptEngine.bind_gui_controls_async(gui_root, map_context, MAP_LOAD_GUI_CONTROLS_PER_FRAME)
		elif LuaScriptEngine.has_method("bind_gui_controls"):
			LuaScriptEngine.bind_gui_controls(gui_root, map_context)
	_raise_game_menu_hud_to_front()

func _clear_runtime_roblox_ui() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null and leave_button != null:
		hud = leave_button.get_parent() as CanvasLayer
	if hud == null:
		return
	var gui_host := hud.get_node_or_null("RobloxRuntimeGuiHost") as Control
	if gui_host != null:
		RobloxGuiRuntime.clear_from(gui_host, "RobloxRuntimeGui")
		gui_host.queue_free()
	else:
		RobloxGuiRuntime.clear_from(hud, "RobloxRuntimeGui")

func _ensure_runtime_roblox_gui_host(hud: CanvasLayer) -> Control:
	if hud == null:
		return null
	var host := hud.get_node_or_null("RobloxRuntimeGuiHost") as Control
	if host == null:
		host = Control.new()
		host.name = "RobloxRuntimeGuiHost"
		host.mouse_filter = Control.MOUSE_FILTER_PASS
		host.clip_contents = true
		host.z_index = 78
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		hud.add_child(host)
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.offset_left = 0.0
	host.offset_top = 0.0
	host.offset_right = 0.0
	host.offset_bottom = 0.0
	host.clip_contents = true
	host.size = get_viewport().get_visible_rect().size
	return host

func _load_manifest_scripts_into_map(manifest: Dictionary, loaded_runtime_refs: Dictionary, map_target: Node3D,
		origin_offset: Vector3, room_id: String) -> void:
	var scripts: Array = manifest.get("scripts", []) if manifest.get("scripts", []) is Array else []
	var processed_count := 0
	for script_variant in scripts:
		if not (script_variant is Dictionary):
			continue
		var script_data: Dictionary = script_variant
		var ref := str(script_data.get("ref", "")).strip_edges()
		if not ref.is_empty() and loaded_runtime_refs.has(ref):
			continue
		var roblox_class := str(script_data.get("class", "Script"))
		if roblox_class != "Script" and roblox_class != "LocalScript":
			continue
		if bool(script_data.get("disabled", false)):
			continue
		if not _manifest_script_runs_in_current_runtime(script_data, roblox_class):
			continue
		var lua_source := str(script_data.get("source", "")).strip_edges()
		if lua_source.is_empty():
			continue
		var runtime_node: Node = null
		if LuaScriptEngine != null and LuaScriptEngine.has_method("find_instance_by_ref") and not ref.is_empty():
			runtime_node = LuaScriptEngine.find_instance_by_ref(map_target, ref)
		if runtime_node == null:
			runtime_node = Node.new()
			runtime_node.name = _make_runtime_node_name(str(script_data.get("name", "")), roblox_class)
			map_target.add_child(runtime_node)
		runtime_node.set_meta("room_id", room_id)
		runtime_node.set_meta("roblox_class", roblox_class)
		runtime_node.set_meta("roblox_ref", ref)
		runtime_node.set_meta("lua_source", lua_source)
		runtime_node.set_meta("code", lua_source)
		runtime_node.set_meta("runtime_object_data", {
			"class": roblox_class,
			"name": runtime_node.name,
			"roblox_ref": ref,
			"lua_source": lua_source,
		})
		runtime_node.add_to_group(RBXL_RUNTIME_OBJECT_GROUP)
		if not ref.is_empty():
			loaded_runtime_refs[ref] = true
		_start_runtime_lua_script_if_needed(runtime_node, {"class": roblox_class, "lua_source": lua_source})
		processed_count += 1
		if processed_count % MAP_LOAD_MANIFEST_SCRIPTS_PER_FRAME == 0:
			await get_tree().process_frame


func _manifest_script_runs_in_current_runtime(script_data: Dictionary, roblox_class: String) -> bool:
	var service_name := str(script_data.get("service_name", "")).strip_edges()
	if service_name.is_empty():
		# Older Bobux manifests did not record their owning Roblox service.
		return true
	if roblox_class == "Script":
		# ServerStorage and ReplicatedStorage are inert libraries in Roblox. Scripts
		# begin executing only after they are moved into a live server container.
		return service_name in ["Workspace", "ServerScriptService", "Players"]
	if roblox_class == "LocalScript":
		return service_name in ["ReplicatedFirst", "Players"]
	return false

func _create_runtime_object_from_map_data(data: Dictionary) -> Node3D:
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
			player.name = "AudioStreamPlayer3D"
			player.volume_db = linear_to_db(maxf(float(data.get("volume", 1.0)), 0.0001))
			player.autoplay = bool(data.get("playing", true))
			var sound_file := _runtime_sound_file_name(data)
			var sound_path := _runtime_sound_path(data)
			if not sound_path.is_empty():
				var stream := _load_audio_stream_from_path(sound_path)
				if stream != null:
					player.stream = stream
			elif not sound_file.is_empty():
				_queue_runtime_sound_download(player, sound_file)
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
			var texture := _runtime_object_texture(data)
			if texture != null:
				decal.texture_albedo = texture
				decal.modulate.a = clampf(1.0 - float(data.get("transparency", 0.0)), 0.0, 1.0)
			runtime_node = decal
		_:
			runtime_node = Node3D.new()
	runtime_node.name = _make_runtime_node_name(str(data.get("name", "")), roblox_class)
	runtime_node.position = Vector3(float(data.get("px", 0.0)), float(data.get("py", 0.0)), float(data.get("pz", 0.0)))
	runtime_node.rotation_degrees = Vector3(float(data.get("rx", 0.0)), float(data.get("ry", 0.0)), float(data.get("rz", 0.0)))
	runtime_node.set_meta("roblox_class", roblox_class)
	runtime_node.set_meta("runtime_object_data", data.duplicate(true))
	if data.has("lua_source"):
		runtime_node.set_meta("lua_source", str(data.get("lua_source", "")))
	return runtime_node

func _start_runtime_lua_script_if_needed(runtime_node: Node, data: Dictionary) -> void:
	var roblox_class := str(data.get("class", ""))
	if roblox_class != "Script" and roblox_class != "LocalScript":
		return
	var lua_source := str(data.get("lua_source", "")).strip_edges()
	if lua_source.is_empty():
		return
	if LuaScriptEngine == null or not LuaScriptEngine.has_method("start_script"):
		return
	_queue_runtime_lua_script(runtime_node, lua_source)

func _queue_runtime_lua_script(runtime_node: Node, lua_source: String) -> void:
	if not is_instance_valid(runtime_node):
		return
	# Starter containers hold templates. Their live clones run after the character
	# is bound; running the template gives script.Parent the wrong identity.
	var ancestor := runtime_node.get_parent()
	while ancestor != null:
		if str(ancestor.get_meta("roblox_class", "")) in ["StarterPlayer", "StarterGui", "StarterPack", "ServerStorage", "ReplicatedStorage"]:
			return
		ancestor = ancestor.get_parent()
	if runtime_node.has_meta("bobux_script_runtime_id"):
		return
	var roblox_class := str(runtime_node.get_meta("roblox_class", "Script"))
	var realm := "client" if roblox_class == "LocalScript" else "server"
	var result: Dictionary = LuaScriptEngine.start_script(lua_source, runtime_node, {
		"realm": realm,
		"is_server": roblox_class == "Script",
		"source_name": runtime_node.name,
		"retain": true,
		# Complex imported places can contain more than a thousand scripts. Queue
		# compilation and the first resume so they consume the Lua scheduler's
		# per-frame budgets instead of constructing every VM in one frozen frame.
		"defer_compilation": true,
		"defer_initial_resume": true,
	})
	if not bool(result.get("ok", true)):
		push_warning("[Main] Imported Lua script failed on '%s': %s" % [runtime_node.name, str(result.get("error", "unknown error"))])

func _runtime_sound_path(data: Dictionary) -> String:
	for key in ["file", "resolved_path", "path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if candidate.is_empty():
			continue
		var resolved := _resolve_map_asset_path(candidate)
		if FileAccess.file_exists(resolved):
			return resolved
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

func _runtime_sound_file_name(data: Dictionary) -> String:
	for key in ["file", "resolved_path", "path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if candidate.is_empty():
			continue
		if candidate.begins_with("res://") or candidate.begins_with("user://") or candidate.find(":") == 1:
			candidate = candidate.get_file()
		candidate = candidate.replace("\\", "/").get_file()
		if not candidate.is_empty():
			return candidate
	return ""

func _runtime_object_texture(data: Dictionary) -> Texture2D:
	var paths: Array[String] = []
	for key in ["file", "resolved_path", "path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if not candidate.is_empty():
			paths.append(_resolve_map_asset_path(candidate))
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
	var checked_paths: Dictionary = {}
	for path in paths:
		var clean_path := path.strip_edges()
		if clean_path.is_empty() or checked_paths.has(clean_path):
			continue
		checked_paths[clean_path] = true
		var cached: Variant = _runtime_object_texture_cache.get(clean_path, null)
		if cached is Texture2D:
			return cached as Texture2D
		if not FileAccess.file_exists(clean_path):
			continue
		# Cloud map assets are written into user:// at runtime and therefore have
		# no Godot import metadata. ResourceLoader reports those existing files as
		# missing; decode their bytes directly through the shared image loader.
		var texture := _load_texture_from_file_path(clean_path)
		if texture != null:
			_runtime_object_texture_cache[clean_path] = texture
			return texture
	return null

func _runtime_decal_size(data: Dictionary) -> Vector3:
	var parent_scale := _vector3_from_array(data.get("parent_scale", []), Vector3(4.0, 4.0, 4.0))
	return Vector3(
		maxf(absf(parent_scale.x), 0.5),
		maxf(absf(parent_scale.y), 0.5),
		maxf(absf(parent_scale.z), 0.5)
	) + Vector3(0.08, 0.08, 0.08)

func _vector3_from_array(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array:
		var arr := raw as Array
		return Vector3(
			float(arr[0]) if arr.size() > 0 else fallback.x,
			float(arr[1]) if arr.size() > 1 else fallback.y,
			float(arr[2]) if arr.size() > 2 else fallback.z
		)
	if raw is Dictionary:
		var dict := raw as Dictionary
		return Vector3(float(dict.get("x", fallback.x)), float(dict.get("y", fallback.y)), float(dict.get("z", fallback.z)))
	return fallback

func _queue_runtime_sound_download(player: AudioStreamPlayer3D, file_name: String) -> void:
	if player == null or CloudAPI == null or not CloudAPI.has_method("download_map_asset_file"):
		return
	var asset_url := _get_map_asset_url(file_name)
	if asset_url.is_empty():
		return
	var target_path := _get_cached_map_asset_path(file_name)
	if target_path.is_empty():
		return
	call_deferred("_download_runtime_sound_async", player, file_name, asset_url, target_path)

func _download_runtime_sound_async(player: AudioStreamPlayer3D, file_name: String, asset_url: String, target_path: String) -> void:
	if FileAccess.file_exists(target_path):
		var cached_stream := _load_audio_stream_from_path(target_path)
		if cached_stream != null and is_instance_valid(player):
			player.stream = cached_stream
			if player.autoplay and not player.playing:
				player.play()
		return
	var result: Dictionary = await CloudAPI.download_map_asset_file(asset_url, target_path)
	if not bool(result.get("ok", false)):
		push_warning("[Main] Failed to download runtime sound '%s': %s" % [file_name, str(result.get("error", "unknown error"))])
		return
	if not is_instance_valid(player):
		return
	var stream := _load_audio_stream_from_path(target_path)
	if stream == null:
		return
	player.stream = stream
	if player.autoplay and not player.playing:
		player.play()

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

func _get_spawn_position_for_peer(peer_id: int) -> Vector3:
	return _get_spawn_info_for_peer(peer_id).get("position", Vector3.ZERO)

func _get_spawn_info_for_peer(peer_id: int) -> Dictionary:
	if _peer_spawn_infos.has(peer_id) and _peer_spawn_infos[peer_id] is Dictionary:
		return (_peer_spawn_infos[peer_id] as Dictionary).duplicate(true)
	var spawn_points := _get_spawn_position_candidates_for_peer(peer_id)
	if spawn_points.is_empty():
		var emergency_spawn := Vector3(0.0, CHECKPOINT_RESPAWN_HEIGHT, 0.0)
		var emergency_info := {"position": emergency_spawn, "points": [emergency_spawn], "index": 0}
		_set_spawn_info_for_peer(peer_id, emergency_info)
		return emergency_info
	var spawn_index := _rng.randi_range(0, spawn_points.size() - 1)
	var spawn_info := {
		"position": spawn_points[spawn_index],
		"points": spawn_points,
		"index": spawn_index
	}
	_set_spawn_info_for_peer(peer_id, spawn_info)
	return spawn_info
	
func _set_spawn_info_for_peer(peer_id: int, spawn_info: Dictionary) -> void:
	if peer_id <= 0 or spawn_info.is_empty():
		return
	var normalized_points: Array[Vector3] = []
	for point_variant in spawn_info.get("points", []):
		if point_variant is Vector3:
			normalized_points.append(point_variant)
	_peer_spawn_infos[peer_id] = {
		"position": spawn_info.get("position", Vector3.ZERO),
		"points": normalized_points,
		"index": int(spawn_info.get("index", -1))
	}

func _get_spawn_position_candidates_for_peer(peer_id: int) -> Array[Vector3]:
	var room_id: String = _get_peer_room_id(peer_id)
	var spawns = get_tree().get_nodes_in_group(_get_room_spawn_group_name(room_id))
	var zero_based_index: int = _get_spawn_slot_index_for_peer(peer_id)
	var peer_offset := Vector3.ZERO
	if zero_based_index == 0:
		peer_offset = Vector3.ZERO
	else:
		var ring_index: int = zero_based_index - 1
		var slots_per_ring: int = 6
		var slot_on_ring: int = ring_index % slots_per_ring
		var ring_number: int = floori(float(ring_index) / float(slots_per_ring)) + 1
		var angle: float = float(slot_on_ring) / float(slots_per_ring) * TAU
		var radius: float = float(ring_number) * 2.2
		peer_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var candidates: Array[Vector3] = []
	if spawns.is_empty():
		var fallback_spawns: Array[Vector3] = _get_room_fallback_spawns(room_id) if not room_id.is_empty() else _fallback_spawn_positions
		for fallback_spawn in fallback_spawns:
			# These points may sit on narrow imported platforms; an arbitrary ring
			# offset can put every player after the first beyond the collision edge.
			candidates.append(fallback_spawn)
			if candidates.size() >= MAX_REPLICATED_SPAWN_POINTS:
				break
		if candidates.is_empty():
			var room_origin: Vector3 = _get_room_visual_origin(room_id) if not room_id.is_empty() else Vector3.ZERO
			candidates.append(room_origin + Vector3(0.0, CHECKPOINT_RESPAWN_HEIGHT, 0.0) + peer_offset)
		return candidates
	for spawn_block in spawns:
		if not spawn_block is Node3D or not is_instance_valid(spawn_block) or spawn_block.is_queued_for_deletion():
			continue
		var props: Dictionary = spawn_block.get_meta("roblox_properties", {})
		if not bool(spawn_block.get_meta("Enabled", props.get("Enabled", true))):
			continue
		candidates.append(_spawn_position_above_surface(spawn_block, peer_offset))
		if candidates.size() >= MAX_REPLICATED_SPAWN_POINTS:
			break
	return candidates

func _spawn_position_above_surface(surface: Node3D, peer_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var bounds := AABB(-Vector3.ONE * 0.5, Vector3.ONE)
	if surface is MeshInstance3D and surface.mesh != null:
		bounds = surface.mesh.get_aabb()
	var surface_transform := surface.global_transform if surface.is_inside_tree() else surface.transform
	var local_offset := surface_transform.basis.inverse() * peer_offset
	var center := bounds.get_center()
	var inset_x := minf(0.6 / maxf(surface_transform.basis.x.length(), 0.001), bounds.size.x * 0.5)
	var inset_z := minf(0.6 / maxf(surface_transform.basis.z.length(), 0.001), bounds.size.z * 0.5)
	var local_top := Vector3(
		clampf(center.x + local_offset.x, bounds.position.x + inset_x, bounds.end.x - inset_x),
		bounds.end.y,
		clampf(center.z + local_offset.z, bounds.position.z + inset_z, bounds.end.z - inset_z)
	)
	return surface_transform * local_top + Vector3.UP * CHECKPOINT_RESPAWN_HEIGHT

func _get_spawn_slot_index_for_peer(peer_id: int) -> int:
	var peer_room_id: String = _get_peer_room_id(peer_id)
	var peer_ids: Array[int] = []
	var seen_ids: Dictionary = {}
	for peer_key in peer_colors.keys():
		var known_peer_id: int = int(peer_key)
		if not peer_room_id.is_empty() and _get_peer_room_id(known_peer_id) != peer_room_id:
			continue
		if seen_ids.has(known_peer_id):
			continue
		seen_ids[known_peer_id] = true
		peer_ids.append(known_peer_id)
	if not seen_ids.has(peer_id):
		peer_ids.append(peer_id)
	if peer_ids.is_empty():
		return 0
	peer_ids.sort()
	var slot_index: int = peer_ids.find(peer_id)
	return maxi(slot_index, 0)

func _register_fallback_spawn_surface(block: MeshInstance3D, room_id: String = "") -> void:
	if block == null:
		return
	if block.scale.x < 0.75 or block.scale.z < 0.75:
		return
	var surface_basis := block.global_basis if block.is_inside_tree() else block.basis
	if surface_basis.y.normalized().dot(Vector3.UP) < 0.74:
		return
	var fallback_spawn := _spawn_position_above_surface(block)
	var clean_room_id: String = room_id.strip_edges()
	if clean_room_id.is_empty():
		if _fallback_spawn_positions.size() < MAX_REPLICATED_SPAWN_POINTS:
			_fallback_spawn_positions.append(fallback_spawn)
		return
	var room_spawns: Array = _room_runtime_fallback_spawns.get(clean_room_id, [])
	if room_spawns.size() < MAX_REPLICATED_SPAWN_POINTS:
		room_spawns.append(fallback_spawn)
	_room_runtime_fallback_spawns[clean_room_id] = room_spawns

func _reset_network_state() -> void:
	_stop_host_keepalive()
	_set_gameplay_frozen(true)
	_runtime_world_ready = false
	_map_load_in_progress = false
	_handover_payload_cache.clear()
	_handover_target_peer_id = 0
	_handover_ready_peer_id = 0
	_migration_locked_local_state = {}
	_pending_existing_peer_snapshots.clear()
	_pending_existing_peer_snapshot_jobs.clear()
	_peer_spawn_infos.clear()
	_map_loaded = false
	# AUDIT FIX LEAK-1: Clear cached template scenes so they don't
	# accumulate across multiple map loads.
	_threaded_scene_cache.clear()
	# AUDIT FIX LEAK-3: Clear migration peer states that were never
	# consumed by _spawn_custom (e.g. peer disconnected before respawn).
	_migration_peer_states.clear()
	# AUDIT FIX LEAK-5: Clear room origin cache.
	_room_runtime_origins.clear()
	# AUDIT FIX: Clear chat bubble rate-limit state.
	_peer_last_chat_bubble_msec.clear()
	_clear_session_entities_for_migration()

# This function removes runtime player entities and peer caches without touching the migration freeze flag.
func _clear_session_entities_for_migration() -> void:
	# Persistent migration: do NOT delete our players or connection states!
	# for child in players.get_children():
	# 	child.free()
	# peer_colors.clear()
	# peer_usernames.clear()
	# peer_user_ids.clear()
	peer_profiles.clear()
	_peer_checkpoint_positions.clear()
	var local_player: CharacterBody3D = _get_local_player()
	if local_player == null:
		fallback_camera.current = true
	elif NetworkManager != null and NetworkManager.is_host():
		fallback_camera.current = false

func _apply_network_sync_rate(root: Node) -> void:
	for child in root.get_children():
		_apply_network_sync_rate(child)
	if root is MultiplayerSynchronizer:
		var synchronizer: MultiplayerSynchronizer = root as MultiplayerSynchronizer
		var owner_node: Node = synchronizer.get_parent()
		if owner_node != null and owner_node.has_method("_configure_state_synchronizer_for"):
			return
		synchronizer.delta_interval = 1.0 / NETWORK_SYNC_RATE_HZ
		synchronizer.replication_interval = 1.0 / NETWORK_SYNC_RATE_HZ

func _refresh_player_camera_authority_mode(player_node: CharacterBody3D) -> void:
	if player_node == null:
		return
	if player_node.has_method("refresh_camera_authority_mode"):
		player_node.call("refresh_camera_authority_mode")

func leave_game() -> void:
	if _leave_in_progress:
		return
	_leave_in_progress = true
	_stop_scene_scripts()
	get_tree().paused = false
	_set_gameplay_frozen(false)
	if _game_menu_panel != null:
		_game_menu_panel.visible = false
	_stop_host_keepalive()
	if multiplayer.is_server():
		await _run_graceful_handover_before_leave()
	if NetworkManager != null and NetworkManager.has_method("disconnect_from_session_async"):
		await NetworkManager.disconnect_from_session_async()
	elif NetworkManager != null and NetworkManager.has_method("disconnect_from_session"):
		NetworkManager.disconnect_from_session()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	# AUDIT FIX ARCH-2: Explicitly free all player nodes ONLY on the
	# leave path. This prevents stale CharacterBody3D nodes from the
	# previous session surviving into the next scene load. We do NOT
	# do this in _reset_network_state() to preserve migration flow.
	if players != null:
		for child in players.get_children():
			if child is CharacterBody3D:
				child.queue_free()
	peer_colors.clear()
	peer_usernames.clear()
	peer_user_ids.clear()
	peer_avatar_visuals.clear()
	_reset_network_state()
	_hide_network_loading()
	_hide_migration_corner_badge()
	GameState.clear_launch_mode()
	GameState.selected_map_folder = "" # Clear selected map
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leave_in_progress = false
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _stop_scene_scripts() -> void:
	if is_instance_valid(_runtime_inventory_controller):
		_runtime_inventory_controller.set_process(false)
		_runtime_inventory_controller.set_process_unhandled_input(false)
	LuaScriptEngine.stop_all_scripts(self)

func _exit_tree() -> void:
	# Also cover scene changes caused by a failed connection or editor Stop.
	_stop_scene_scripts()

func _on_leave_pressed() -> void:
	await leave_game()

func _should_preserve_nodes_during_disconnect() -> bool:
	if _leave_in_progress:
		return false
	if _is_dedicated_server_runtime():
		return false
	if not _handover_payload_cache.is_empty():
		return true
	if NetworkManager == null or not NetworkManager.has_method("is_host_migration_in_progress"):
		return false
	return bool(NetworkManager.is_host_migration_in_progress())

func _select_handover_successor_peer_id() -> int:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return 0
	var candidates: Array[int] = []
	for peer_id_variant in multiplayer.get_peers():
		var peer_id: int = int(peer_id_variant)
		if peer_id > 0:
			candidates.append(peer_id)
	if candidates.is_empty():
		return 0
	candidates.sort()
	return candidates[0]

func _build_handover_world_state(successor_peer_id: int) -> Dictionary:
	var state_by_peer: Dictionary = {}
	if players != null:
		for child in players.get_children():
			if not (child is CharacterBody3D):
				continue
			var character: CharacterBody3D = child as CharacterBody3D
			var peer_id: int = _extract_peer_id_from_player(character)
			if peer_id <= 0:
				continue
			var state: Dictionary = _build_character_runtime_state(character)
			state_by_peer[str(peer_id)] = state
	return {
		"successor_peer_id": successor_peer_id,
		"sent_at_msec": Time.get_ticks_msec(),
		"peer_colors": peer_colors.duplicate(true),
		"peer_usernames": peer_usernames.duplicate(true),
		"peer_user_ids": peer_user_ids.duplicate(true),
		"peer_checkpoint_positions": _peer_checkpoint_positions.duplicate(true),
		"peer_spawn_infos": _peer_spawn_infos.duplicate(true),
		"player_states": state_by_peer
	}

func _apply_handover_world_state(world_state_data: Dictionary) -> void:
	var incoming_colors: Variant = world_state_data.get("peer_colors", {})
	if incoming_colors is Dictionary:
		for key_variant in (incoming_colors as Dictionary).keys():
			peer_colors[int(key_variant)] = (incoming_colors as Dictionary)[key_variant]
	var incoming_names: Variant = world_state_data.get("peer_usernames", {})
	if incoming_names is Dictionary:
		for key_variant in (incoming_names as Dictionary).keys():
			peer_usernames[int(key_variant)] = (incoming_names as Dictionary)[key_variant]
	var incoming_ids: Variant = world_state_data.get("peer_user_ids", {})
	if incoming_ids is Dictionary:
		for key_variant in (incoming_ids as Dictionary).keys():
			peer_user_ids[int(key_variant)] = (incoming_ids as Dictionary)[key_variant]
	var incoming_checkpoints: Variant = world_state_data.get("peer_checkpoint_positions", {})
	if incoming_checkpoints is Dictionary:
		for key_variant in (incoming_checkpoints as Dictionary).keys():
			_peer_checkpoint_positions[int(key_variant)] = (incoming_checkpoints as Dictionary)[key_variant]
	var incoming_spawn_infos: Variant = world_state_data.get("peer_spawn_infos", {})
	if incoming_spawn_infos is Dictionary:
		for key_variant in (incoming_spawn_infos as Dictionary).keys():
			var peer_id: int = int(key_variant)
			var spawn_info: Variant = (incoming_spawn_infos as Dictionary)[key_variant]
			if spawn_info is Dictionary:
				_set_spawn_info_for_peer(peer_id, spawn_info)
	var incoming_player_states: Variant = world_state_data.get("player_states", {})
	if incoming_player_states is Dictionary:
		for key_variant in (incoming_player_states as Dictionary).keys():
			_migration_peer_states[str(key_variant)] = (incoming_player_states as Dictionary)[key_variant]

func _run_graceful_handover_before_leave() -> void:
	var successor_peer_id: int = _select_handover_successor_peer_id()
	if successor_peer_id <= 0:
		return
	_handover_target_peer_id = successor_peer_id
	_handover_ready_peer_id = 0
	var handover_payload: Dictionary = _build_handover_world_state(successor_peer_id)
	_handover_payload_cache = handover_payload.duplicate(true)
	if _migration_corner_label != null:
		_migration_corner_label.text = "Saving & Leaving..."
	_show_migration_corner_badge()
	_set_gameplay_frozen(true)
	if NetworkManager.has_method("set_manual_handover_target_peer_id"):
		NetworkManager.set_manual_handover_target_peer_id(successor_peer_id)
	for peer_id_variant in multiplayer.get_peers():
		var peer_id: int = int(peer_id_variant)
		if peer_id > 0:
			rpc_id(peer_id, "_prepare_handover", handover_payload)
	var deadline_msec: int = Time.get_ticks_msec() + int(HANDOVER_READY_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_msec and _handover_ready_peer_id != successor_peer_id:
		await get_tree().process_frame
	if _handover_ready_peer_id != successor_peer_id:
		push_warning("[Main] Graceful handover ack timed out; leaving anyway.")

@rpc("authority", "reliable")
func _prepare_handover(full_world_state_data: Dictionary) -> void:
	_handover_payload_cache = full_world_state_data.duplicate(true)
	_apply_handover_world_state(_handover_payload_cache)
	var successor_peer_id: int = int(full_world_state_data.get("successor_peer_id", 0))
	if successor_peer_id > 0 and NetworkManager.has_method("set_manual_handover_target_peer_id"):
		NetworkManager.set_manual_handover_target_peer_id(successor_peer_id)
	if _get_runtime_local_peer_id() == successor_peer_id:
		_migration_local_authority_before_handover = successor_peer_id
	_set_gameplay_frozen(true)
	if _migration_corner_label != null:
		_migration_corner_label.text = "Reconnecting..."
	_show_migration_corner_badge()
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().has(1):
		rpc_id(1, "_handover_ready", successor_peer_id)

@rpc("any_peer", "reliable")
func _handover_ready(successor_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if sender_id == successor_peer_id and successor_peer_id == _handover_target_peer_id:
		_handover_ready_peer_id = sender_id

# This function returns the connected peer id that already owns the supplied cloud user id.
func _find_peer_by_user_id(user_id: String) -> int:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return 0
	var stale_peer_ids: Array[int] = []
	for peer_id_variant in peer_user_ids.keys():
		var peer_id: int = int(peer_id_variant)
		if str(peer_user_ids.get(peer_id, "")).strip_edges() != clean_user_id:
			continue
		if not _is_peer_id_live_for_session(peer_id):
			stale_peer_ids.append(peer_id)
			continue
		return peer_id
	for stale_peer_id in stale_peer_ids:
		print("[RoomHub] Clearing stale session state for user %s on peer %d." % [clean_user_id, stale_peer_id])
		_clear_peer_runtime_state(stale_peer_id, true, false)
	return 0

# This function starts the host heartbeat watchdog for joined clients.
func _start_host_keepalive() -> void:
	if _host_keepalive_timer == null or NetworkManager.is_host():
		return
	_host_last_pong_msec = Time.get_ticks_msec()
	_last_ping_rtt_msec = -1
	_soft_keepalive_timeout_count = 0
	_host_keepalive_timer.start()
	_dispatch_host_keepalive_probe(true)

# This function stops the host heartbeat watchdog when hosting, leaving, or migrating.
func _stop_host_keepalive() -> void:
	if _host_keepalive_timer != null:
		_host_keepalive_timer.stop()
	_last_ping_rtt_msec = -1
	_soft_keepalive_timeout_count = 0

# This function pings the authoritative dedicated server and returns to the lobby if the heartbeat times out.
func _on_host_keepalive_timeout() -> void:
	if _host_keepalive_timer == null:
		return
	if multiplayer.multiplayer_peer == null or NetworkManager.is_host():
		_stop_host_keepalive()
		return
	if NetworkManager.has_method("is_host_migration_in_progress") and NetworkManager.is_host_migration_in_progress():
		return
	if _network_loading_overlay != null and _network_loading_overlay.visible:
		_host_last_pong_msec = Time.get_ticks_msec()
		_dispatch_host_keepalive_probe(false)
		return
	# Drain the transport so a pong queued on the wire is applied before we
	# measure silence (WebSocket can otherwise miss a window and false-timeout).
	var transport_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if transport_peer != null:
		transport_peer.poll()
	var elapsed_msec: int = Time.get_ticks_msec() - _host_last_pong_msec
	if elapsed_msec >= int(HOST_KEEPALIVE_TIMEOUT_SECONDS * 1000.0):
		var connection_status: MultiplayerPeer.ConnectionStatus = transport_peer.get_connection_status() if transport_peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
		var still_has_host_peer: bool = multiplayer.get_peers().has(1)
		if connection_status == MultiplayerPeer.CONNECTION_CONNECTED and still_has_host_peer:
			_soft_keepalive_timeout_count += 1
			_host_last_pong_msec = Time.get_ticks_msec()
			print("[Client] Heartbeat stalled but socket still reports CONNECTED; suppressing timeout (%d)." % _soft_keepalive_timeout_count)
			return
		_stop_host_keepalive()
		_set_gameplay_frozen(false)
		_reset_network_state()
		_hide_network_loading()
		print("[Client] Dedicated server heartbeat timed out.")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if NetworkManager != null and NetworkManager.has_method("disconnect_from_session"):
			NetworkManager.disconnect_from_session()
		GameState.set_network_error("Lost contact with the dedicated server.")
		GameState.clear_launch_mode()
		call_deferred("_return_to_lobby_after_connection_failure")
		return
	_dispatch_host_keepalive_probe(false)

func _dispatch_host_keepalive_probe(immediate: bool) -> void:
	var dispatched: bool = false
	var keepalive_peer_id: int = _get_runtime_local_peer_id()
	if keepalive_peer_id <= 0 and NetworkManager.has_method("get_unique_id"):
		keepalive_peer_id = int(NetworkManager.get_unique_id())
	var transport_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if multiplayer.get_peers().has(1):
		var sent_msec: int = Time.get_ticks_msec()
		rpc_id(1, "_request_host_keepalive", sent_msec, keepalive_peer_id)
		if transport_peer != null:
			transport_peer.poll()
		dispatched = true
	if dispatched:
		if immediate:
			_log_keepalive("[Tick] Client sent immediate keepalive ping to host")
		else:
			_log_keepalive("[Tick] Client sent keepalive ping to host")

func _accept_host_keepalive_pong(sent_msec: int) -> void:
	var now_msec: int = Time.get_ticks_msec()
	_host_last_pong_msec = now_msec
	_soft_keepalive_timeout_count = 0
	if sent_msec > 0:
		_last_ping_rtt_msec = maxi(now_msec - sent_msec, 0)
		_log_keepalive("[Tick] Client received keepalive pong from host")
	else:
		_log_keepalive("[Tick] Client received keepalive tick from host")

@rpc("any_peer", "reliable")
func _request_host_keepalive(sent_msec: int, requested_peer_id: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if NetworkManager != null and NetworkManager.has_method("record_server_peer_keepalive"):
		NetworkManager.call("record_server_peer_keepalive", sender_id)
	if requested_peer_id > 0 and requested_peer_id != sender_id:
		push_warning("[RoomHub] Keepalive peer mismatch: sender %d claimed %d." % [sender_id, requested_peer_id])
	_log_keepalive("[Tick] Host received keepalive ping from peer %s" % sender_id)
	_receive_host_keepalive_pong.rpc_id(sender_id, sent_msec)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.poll()

@rpc("authority", "reliable")
func _receive_host_keepalive_pong(sent_msec: int) -> void:
	if multiplayer.is_server():
		return
	_accept_host_keepalive_pong(sent_msec)

func _load_audio_stream_from_path(path: String) -> AudioStream:
	return AudioFileLoader.load_stream(path, true)

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

func _create_spawn_decal_node(block_scale: Vector3) -> Sprite3D:
	var decal := Sprite3D.new()
	decal.texture = _load_spawn_decal_texture()
	decal.position = Vector3(0.0, (block_scale.y * 0.5) + 0.26, 0.0)
	decal.axis = Vector3.AXIS_Y
	if block_scale.x > 0.0:
		decal.scale.x = 1.0 / block_scale.x
	if block_scale.z > 0.0:
		decal.scale.z = 1.0 / block_scale.z
	decal.pixel_size = 0.0035
	return decal

func _load_spawn_decal_texture() -> Texture2D:
	var imported_texture := load(SPAWN_DECAL_PATH) as Texture2D
	if imported_texture:
		return imported_texture
	var img := _load_image_from_path(SPAWN_DECAL_PATH)
	if img:
		return ImageTexture.create_from_image(img)
	return _create_placeholder_spawn_decal()

func _attach_runtime_account_badges(label: Label, peer_id: int) -> void:
	var profile: Dictionary = peer_profiles.get(peer_id, {})
	if profile.has("club_tier") or profile.has("verified_badge"):
		load("res://scripts/lobby/account_badges.gd").attach(label, profile)
		return
	var user_id := _get_user_id_for_leaderboard_peer(peer_id)
	if user_id.is_empty(): return
	if _account_badge_cache.has(user_id):
		load("res://scripts/lobby/account_badges.gd").attach(label, _account_badge_cache[user_id])
	elif not _account_badge_requests.has(user_id):
		_account_badge_requests[user_id] = true
		_fetch_runtime_account_badges.call_deferred(user_id)

func _fetch_runtime_account_badges(user_id: String) -> void:
	var result: Dictionary = await CloudAPI.load_player_profile(user_id)
	if not is_inside_tree(): return
	if bool(result.get("ok", false)):
		_account_badge_cache[user_id] = result.get("data", {})
		_refresh_mobile_player_list()
		_refresh_leaderboard_rows()
