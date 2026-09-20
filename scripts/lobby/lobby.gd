extends Control

const AVATAR_UI_SCRIPT: Script = preload("res://scripts/lobby/avatar_ui.gd")
const LOBBY_STYLER_SCRIPT: Script = preload("res://scripts/lobby/lobby_styler.gd")
const AVATAR_TEMPLATE_PROCESSOR: Script = preload("res://scripts/avatar/avatar_template_processor.gd")
const AVATAR_PREVIEW_INPUT_OVERLAY_SCRIPT: Script = preload("res://scripts/ui/avatar_preview_input_overlay.gd")
const CREATION_HUB_SCENE: PackedScene = preload("res://scenes/creation_hub/creation_hub.tscn")
const MODEL_EDITOR_SCENE: PackedScene = preload("res://scenes/model_editor/model_editor.tscn")
const RbxlMaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
const BOBLOX_SHOP_SCRIPT := preload("res://scripts/lobby/boblox_shop.gd")
var _boblox_shop: Control
var _founder_reward_dialog: CanvasLayer
const ACCOUNT_BADGES = preload("res://scripts/lobby/account_badges.gd")
var _bricks_club_button: Button

# --- Tab Navigation ---
@onready var main_tabs: TabContainer = %MainTabs
@onready var sidebar_username: Label = %SidebarUsername

# Sidebar nav buttons
@onready var nav_home_btn: Button = %NavHomeBtn
@onready var nav_profile_btn: Button = %NavProfileBtn
@onready var nav_messages_btn: Button = %NavMessagesBtn
@onready var nav_friends_btn: Button = %NavFriendsBtn
@onready var nav_character_btn: Button = %NavCharacterBtn
@onready var nav_inventory_btn: Button = %NavInventoryBtn
@onready var nav_trade_btn: Button = $Body/HBox/Sidebar/NavTradeBtn
@onready var nav_groups_btn: Button = $Body/HBox/Sidebar/NavGroupsBtn
@onready var nav_blog_btn: Button = $Body/HBox/Sidebar/NavBlogBtn
@onready var nav_promocodes_btn: Button = $Body/HBox/Sidebar/NavPromocodesBtn
@onready var logout_btn: Button = %LogoutBtn

# Profile
@onready var profile_username_label: Label = %ProfileUsernameLabel
@onready var join_date_label: Label = %JoinDateLabel
var profile_status_label: Label = null
var profile_friends_count_label: Label = null
var profile_followers_count_label: Label = null
var profile_following_count_label: Label = null

# Avatar Editor
@onready var btn_head: Button = %BtnHead
@onready var btn_torso: Button = %BtnTorso
@onready var btn_left_arm: Button = %BtnLeftArm
@onready var btn_right_arm: Button = %BtnRightArm
@onready var btn_left_leg: Button = %BtnLeftLeg
@onready var btn_right_leg: Button = %BtnRightLeg

@onready var color_buttons: Array[Button] = []

var selected_part: String = "head"
var preview_player: Node = null
var profile_preview_player: Node = null
var profile_header_preview_player: Node = null
var profile_header_avatar_holder: Control = null
var profile_wearing_items_container: Container = null
var profile_wearing_empty_label: Label = null
var live_servers_panel: Panel = null
var live_servers_list: VBoxContainer = null
var live_servers_status: Label = null
var continue_cards_container: Container = null
var continue_status_label: Label = null
var recommended_cards_grid: GridContainer = null
var recommended_status_label: Label = null
var discover_cards_grid: GridContainer = null
var discover_status_label: Label = null
var new_cards_grid: GridContainer = null
var new_status_label: Label = null
var all_cards_grid: GridContainer = null
var all_status_label: Label = null
var bobux_creator_cards_grid: Control = null
var bobux_creator_status_label: Label = null
var _loading_overlay: ColorRect = null
var _loading_progress_bar: ProgressBar = null
var _loading_title_label: Label = null
var _loading_subtitle_label: Label = null
var _loading_transport_badge_label: Label = null
var _profile_games_panel: Panel = null
var _discover_refresh_token: int = 0
var _discover_refresh_in_flight: bool = false
var _discover_refresh_pending: bool = false
var _next_discover_refresh_allowed_msec: int = 0
var _home_friends_refresh_in_flight: bool = false
var _home_friends_refresh_pending: bool = false
var _next_home_friends_refresh_allowed_msec: int = 0
var _home_friends_cache: Array = []
var _home_friends_active_lookup_cache: Dictionary = {}
var _home_friends_cache_loaded: bool = false
var _friends_view_last_refresh_msec: int = -100000
var _friends_view_refresh_in_flight: bool = false
var _home_friend_status_refresh_in_flight: bool = false
var _next_home_friend_status_refresh_msec: int = 0
var _home_dashboard_refresh_scheduled: bool = false
var _home_dashboard_refresh_force_pending: bool = false
var _last_home_dashboard_refresh_msec: int = -100000
var _lobby_bootstrap_active: bool = true
var _lobby_bootstrap_finished: bool = false
var _avatar_cloud_sync_in_flight: bool = false
var _avatar_cloud_sync_pending: bool = false
var _avatar_inventory_load_requested: bool = false
var _catalog_ui_built: bool = false
var _scene_change_in_progress: bool = false
var _presence_heartbeat_in_flight: bool = false
var _next_lobby_presence_heartbeat_msec: int = 0
var _lobby_friend_request_poll_in_flight: bool = false
var _next_lobby_friend_request_poll_msec: int = 0
var _lobby_pending_friend_request_ids: Dictionary = {}
var _lobby_friend_request_popup: Panel = null
var _lobby_friend_request_sender_id: String = ""
var _model_publish_dialog: ConfirmationDialog = null
var _studio_overlay: Control = null
var _creator_page_generation: int = 0
var _inventory_ui_built: bool = false
var _inventory_refresh_generation: int = 0
var _inventory_active_category: String = "All"
var _inventory_items_cache: Array = []
var _inventory_cache_expires_at_msec: int = 0
var _inventory_grid: GridContainer = null
var _inventory_status_label: Label = null
var _inventory_category_buttons: Dictionary = {}
var _inventory_render_generation: int = 0
var home_friends_container: Container = null
var home_friends_clip: Control = null
var home_friends_status: Label = null
var home_friend_popup: Panel = null
var home_avatar_player: Node = null
var avatar_ui: RefCounted = null
var selected_profile_user_id: String = ""
var selected_profile_username: String = ""
var selected_profile_snapshot: Dictionary = {}
var selected_profile_active_server: Dictionary = {}
var _local_map_entries_cache: Array = []
var _local_map_entries_cache_expires_at_msec: int = 0
var _local_game_icon_path_cache: Dictionary = {}
var _remote_game_icon_texture_cache: Dictionary = {}
var _remote_game_icon_loading: Dictionary = {}
var _remote_game_icon_waiters: Dictionary = {}
var _remote_game_icon_active_downloads: int = 0
var _lobby_exiting: bool = false
var _home_layout_columns: int = 0
var _home_layout_entries: Array = []
var _home_render_generation: int = 0
var _published_map_ids_cache: Dictionary = {}
var _published_game_records_cache: Dictionary = {}
var _home_friends_scroll_offset: float = 0.0
var _home_friends_drag_active: bool = false
var _home_friends_drag_pointer: int = -1
var _home_friends_drag_start_position: Vector2 = Vector2.ZERO
var _home_friends_drag_start_offset: float = 0.0
var _home_friends_dragged: bool = false
var _published_map_names_cache: Dictionary = {}
var _published_game_cache_expires_at_msec: int = 0
var _published_game_cache_loaded: bool = false
var _smart_play_hover_cards: Array[Dictionary] = []
var _smart_play_hover_sweep_accumulator: float = 0.0
const PROFILE_PRESENCE_TTL_SECONDS: int = 90
const LOCAL_MAP_ENTRY_CACHE_TTL_MS: int = 5000
const PUBLISHED_GAME_CACHE_TTL_MS: int = 30000
const HOME_REFRESH_MIN_INTERVAL_MS: int = 2500
const HOME_FRIENDS_FAILURE_RETRY_MS: int = 30000
const FRIENDS_VIEW_REFRESH_TTL_MS: int = 30000
const DISCOVER_FAILURE_RETRY_MS: int = 20000
const LOBBY_PRESENCE_HEARTBEAT_MSEC: int = 30000
const LOBBY_FRIEND_REQUEST_POLL_MSEC: int = 4000
const HOME_FRIENDS_ACTIVE_SERVER_LIMIT: int = 16
const HOME_FRIENDS_RENDER_LIMIT: int = 16
const HOME_CONTINUE_RENDER_LIMIT: int = 6
const DISCOVER_ACTIVE_SERVER_LIMIT: int = 64
const DISCOVER_PUBLISHED_MAP_LIMIT: int = 1000
const HOME_DISCOVER_RENDER_LIMIT: int = 12
const HOME_RECOMMENDED_RENDER_LIMIT: int = 6
const HOME_NEW_RENDER_LIMIT: int = 4
const HOME_ALL_RENDER_LIMIT: int = 16
const BOBUX_CREATOR_RENDER_LIMIT: int = 8
const LOBBY_PUBLISHED_MAP_CACHE_PATH: String = "user://cache/lobby_published_maps.json"
const LOBBY_PUBLISHED_MAP_CACHE_TTL_MS: int = 15 * 60 * 1000
const REMOTE_GAME_ICON_MAX_CONCURRENT_DOWNLOADS: int = 3
const REMOTE_GAME_ICON_TIMEOUT_SECONDS: float = 5.0
const REMOTE_GAME_ICON_BODY_LIMIT_BYTES: int = 768 * 1024
const REMOTE_GAME_ICON_CACHE_DIR: String = "user://game_icon_cache"
const LOCAL_GAME_ICON_BODY_LIMIT_BYTES: int = 768 * 1024
const LOCAL_GAME_ICON_INLINE_CHAR_LIMIT: int = 1100 * 1024
const BOBUX_CREATOR_USERNAME: String = "pavelord"
const BOBUX_CREATOR_USER_IDS: Array[String] = ["5g1wpd52ldqc2h4", "z9ovqynlv860sgw"]
const CLOUD_INLINE_ASSET_MAX_BYTES: int = 24 * 1024 * 1024
const CLOUD_INLINE_ASSET_TOTAL_MAX_BYTES: int = 96 * 1024 * 1024
const CLOUD_INLINE_ASSET_MAX_TRACKS: int = 32
const CLOUD_THUMBNAIL_MAX_DIMENSION: int = 1024
const CLOUD_THUMBNAIL_FALLBACK_MAX_BYTES: int = 512 * 1024

const COLOR_MAP: Dictionary = {
	"BtnColorYellow": Color(0.96, 0.8, 0.2),
	"BtnColorBlue": Color(0.05, 0.4, 0.7),
	"BtnColorLightGreen": Color(0.65, 0.8, 0.2),
	"BtnColorDarkGreen": Color(0.15, 0.5, 0.15),
	"BtnColorRed": Color(0.85, 0.1, 0.1),
	"BtnColorTan": Color(0.9, 0.77, 0.61),
	"BtnColorWhite": Color(0.95, 0.95, 0.95),
	"BtnColorGrey": Color(0.63, 0.65, 0.64),
	"BtnColorDarkGrey": Color(0.39, 0.37, 0.39),
	"BtnColorBlack": Color(0.1, 0.1, 0.1),
	"BtnColorBrown": Color(0.4, 0.25, 0.15),
	"BtnColorOrange": Color(0.85, 0.52, 0.1),
}
const CONTINUE_PANEL_MIN_HEIGHT: float = 330.0
const DISCOVER_PANEL_MIN_HEIGHT: float = 520.0
const CONTINUE_SCROLL_MIN_HEIGHT: float = 236.0
const DISCOVER_SCROLL_MIN_HEIGHT: float = 560.0

# Tab index map (must match order of children in MainTabs)
enum Tab { HOME = 0, PROFILE = 1, AVATAR = 2, FRIENDS = 3, INVENTORY = 4, MESSAGES = 5, DEVELOP = 6, TRADE = 7, GROUPS = 8, BLOG = 9, PROMOCODES = 10, CATALOG = 11, GAMES = 12, GAME_DETAILS = 13 }

var _game_details_return_tab: int = Tab.HOME

func _exit_tree() -> void:
	_lobby_exiting = true
	_discover_refresh_token += 1
	_home_render_generation += 1
	for child in get_children():
		if child is HTTPRequest:
			child.cancel_request()
	_remote_game_icon_waiters.clear()
	_remote_game_icon_loading.clear()
	_remote_game_icon_active_downloads = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_lobby_bootstrap_active = true
	_lobby_bootstrap_finished = false
	_ensure_all_tabs_exist()
	_disable_mobile_gameplay_controls()
	var mobile_beta: bool = _is_mobile_beta()
	
	LOBBY_STYLER_SCRIPT.apply_2016_theme(self)
	_apply_bobux_branding()
	_install_boblox_shop()
	preload("res://scripts/lobby/lobby_chrome.gd").apply(self)
	if Engine.has_singleton("ProfileBuilder") or true:
		var pb = load("res://scripts/lobby/profile_builder.gd")
		if pb: pb.build(self)

	if NetworkManager != null and NetworkManager.has_method("prepare_for_lobby"):
		NetworkManager.prepare_for_lobby()

	# Set user info
	var uname: String = UserSession.username if UserSession.is_logged_in else "Player"
	sidebar_username.text = uname

	var greeting_label: Label = get_node_or_null("%GreetingLabel")
	if greeting_label:
		greeting_label.text = "Hello, %s!" % uname

	profile_username_label.text = uname
	join_date_label.text = "Join Date: %s" % UserSession.join_date

	# Nav signals
	nav_home_btn.pressed.connect(func(): _switch_tab(Tab.HOME); Analytics.log_button_click("nav_home"))
	nav_profile_btn.pressed.connect(func(): selected_profile_user_id = ""; selected_profile_username = ""; _switch_tab(Tab.PROFILE); Analytics.log_button_click("nav_profile"))
	nav_messages_btn.pressed.connect(func(): _switch_tab(Tab.MESSAGES); Analytics.log_button_click("nav_messages"))
	nav_friends_btn.pressed.connect(func(): _switch_tab(Tab.FRIENDS); Analytics.log_button_click("nav_friends"))
	nav_character_btn.pressed.connect(func(): _switch_tab(Tab.AVATAR); Analytics.log_button_click("nav_character"))
	nav_inventory_btn.pressed.connect(func(): _switch_tab(Tab.INVENTORY); Analytics.log_button_click("nav_inventory"))
	nav_trade_btn.pressed.connect(func(): _switch_tab(Tab.TRADE); Analytics.log_button_click("nav_trade"))
	nav_groups_btn.pressed.connect(func(): _switch_tab(Tab.GROUPS); Analytics.log_button_click("nav_groups"))
	nav_blog_btn.pressed.connect(func(): _switch_tab(Tab.BLOG); Analytics.log_button_click("nav_blog"))
	nav_promocodes_btn.pressed.connect(func(): _switch_tab(Tab.PROMOCODES); Analytics.log_button_click("nav_promocodes"))
	logout_btn.pressed.connect(_on_logout)

	# Play button - safe lookup
	var play_btn: Button = get_node_or_null("%PlayButton")
	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)

	# Game mode buttons - safe connect (may be removed later by grid)
	var btn_classic: Button = get_node_or_null("%BtnModeClassic")
	var btn_chaos: Button = get_node_or_null("%BtnModeChaos")
	var btn_sfoth: Button = get_node_or_null("%BtnModeSfoth")
	if btn_classic:
		btn_classic.pressed.connect(func(): _select_mode("classic", btn_classic, [btn_classic, btn_chaos, btn_sfoth]))
	if btn_chaos:
		btn_chaos.pressed.connect(func(): _select_mode("chaos", btn_chaos, [btn_classic, btn_chaos, btn_sfoth]))
	if btn_sfoth:
		btn_sfoth.pressed.connect(func(): _select_mode("sfoth", btn_sfoth, [btn_classic, btn_chaos, btn_sfoth]))
	var legacy_modes_panel: Control = get_node_or_null("Body/HBox/MainTabs/HomeView/Content/ModesPanel")
	if legacy_modes_panel != null:
		legacy_modes_panel.visible = false

	# Part selection signals
	btn_head.pressed.connect(func(): _select_part("head"))
	btn_torso.pressed.connect(func(): _select_part("torso"))
	btn_left_arm.pressed.connect(func(): _select_part("left_arm"))
	btn_right_arm.pressed.connect(func(): _select_part("right_arm"))
	btn_left_leg.pressed.connect(func(): _select_part("left_leg"))
	btn_right_leg.pressed.connect(func(): _select_part("right_leg"))

	# Color button signals + fallback palette rebuild for scenes where
	# the color nodes are missing, gray-themed, or not wired.
	_rebind_avatar_color_palette()

	# Get preview player references
	preview_player = get_node_or_null("%PreviewPlayer")
	# ProfileBuilder creates this preview dynamically. Keep its direct reference;
	# resolving the old scene's queued node here made the live profile avatar
	# disappear one frame later.
	if profile_preview_player == null or not is_instance_valid(profile_preview_player):
		profile_preview_player = get_node_or_null("%ProfilePreviewPlayer")
	if preview_player:
		preview_player.set("is_ui_preview", true)
		preview_player.set("use_local_avatar_fallback", false)
		preview_player.set("render_avatar_visual_decals", true)
		preview_player.set("render_avatar_clothing_decals", true)
		preview_player.position.y = 0.22
		var label = preview_player.get_node_or_null("Visuals/NameLabel")
		if label: label.visible = false
	if profile_preview_player:
		profile_preview_player.set("is_ui_preview", true)
		profile_preview_player.set("use_local_avatar_fallback", false)
		profile_preview_player.set("render_avatar_clothing_decals", true)
		profile_preview_player.position.y = 0.28
		var label = profile_preview_player.get_node_or_null("Visuals/NameLabel")
		if label: label.visible = false

	# Develop (Studio) hook
	var nav_develop: Button = get_node_or_null("TopBar/HBox/Nav3") as Button
	if nav_develop:
		nav_develop.pressed.connect(_open_creation_hub)
		
	var nav_catalog: Button = get_node_or_null("TopBar/HBox/Nav2") as Button
	if nav_catalog:
		nav_catalog.pressed.connect(func(): _switch_tab(Tab.CATALOG))
		
	var nav_games: Button = get_node_or_null("TopBar/HBox/Nav1") as Button
	if nav_games:
		nav_games.pressed.connect(func(): _switch_tab(Tab.GAMES))

	var btn_create_new: Button = get_node_or_null("%BtnCreateNew")
	if btn_create_new and not mobile_beta:
		btn_create_new.pressed.connect(_open_create_game_choice_dialog)

	# Default tab
	_switch_tab(Tab.HOME)
	_update_preview_colors()

	# Ensure maps directory exists and build game discovery
	_ensure_maps_dir()
	_build_home_dashboard()
	_show_loading_overlay("Loading Bobux", "Preparing cached lobby data...", 0.08)
	_render_home_startup_skeletons()
	if mobile_beta:
		_apply_mobile_beta_lobby_mode()
	call_deferred("_install_button_micro_interactions")
	call_deferred("_bootstrap_cloud_lobby")
	var pending_network_error: String = GameState.pop_network_error()
	if not pending_network_error.is_empty():
		call_deferred("_show_loading_error", "Connection Failed", pending_network_error)


func _is_mobile_beta() -> bool:
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))


func _apply_mobile_beta_lobby_mode() -> void:
	if not _is_mobile_beta():
		return
	_configure_mobile_scroll_containers(self)
	for tab_index in range(main_tabs.get_tab_count()):
		main_tabs.set_tab_hidden(tab_index, false)
	_add_mobile_beta_home_banner()


func _disable_mobile_gameplay_controls() -> void:
	var mobile_runtime: Node = get_node_or_null("/root/MobileRuntime")
	if mobile_runtime != null and mobile_runtime.has_method("disable_gameplay_touch_controls"):
		mobile_runtime.call("disable_gameplay_touch_controls")


func _configure_mobile_scroll_containers(root: Node) -> void:
	if root is ScrollContainer:
		var scroll := root as ScrollContainer
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.follow_focus = true
		scroll.scroll_deadzone = 8
	for child in root.get_children():
		_configure_mobile_scroll_containers(child)


func _add_mobile_beta_home_banner() -> void:
	var home_content: VBoxContainer = get_node_or_null("Body/HBox/MainTabs/HomeView/Content") as VBoxContainer
	if home_content == null or home_content.get_node_or_null("MobileBetaBanner") != null:
		return
	var banner := PanelContainer.new()
	banner.name = "MobileBetaBanner"
	banner.custom_minimum_size = Vector2(0, 54)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.33, 0.58, 0.92)
	style.border_color = Color(0.0, 0.16, 0.28, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	banner.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "Bobux Mobile Beta: play places, edit your avatar, browse catalog, open profiles, friends, and develop tools."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 15)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_child(label)
	banner.add_child(margin)
	home_content.add_child(banner)
	home_content.move_child(banner, 1)

func _process(delta: float) -> void:
	_poll_lobby_presence_heartbeat_if_needed()
	_poll_lobby_friend_requests_if_needed()
	_sweep_smart_play_hover_cards(delta)


func _sweep_smart_play_hover_cards(delta: float) -> void:
	_smart_play_hover_sweep_accumulator += delta
	if _smart_play_hover_sweep_accumulator < 0.04:
		return
	_smart_play_hover_sweep_accumulator = 0.0
	for index in range(_smart_play_hover_cards.size() - 1, -1, -1):
		var entry: Dictionary = _smart_play_hover_cards[index]
		# Validate the weak scene references before casting them. A card can be
		# queued for deletion while a tab is rebuilding; casting that freed object
		# generated an error every frame and could effectively lock the lobby.
		var panel_value: Variant = entry.get("panel", null)
		var overlay_value: Variant = entry.get("overlay", null)
		if not is_instance_valid(panel_value) or not is_instance_valid(overlay_value):
			_smart_play_hover_cards.remove_at(index)
			continue
		var panel: Panel = panel_value as Panel
		var overlay: Panel = overlay_value as Panel
		if panel == null or overlay == null:
			_smart_play_hover_cards.remove_at(index)
			continue
		if not panel.is_visible_in_tree():
			overlay.modulate.a = 0.0
			continue
		var pointer_inside := Rect2(Vector2.ZERO, panel.size).grow(2.0).has_point(panel.get_local_mouse_position())
		overlay.modulate.a = 1.0 if pointer_inside else 0.0
		var normal_style: StyleBoxFlat = entry.get("normal_style", null) as StyleBoxFlat
		var hover_style: StyleBoxFlat = entry.get("hover_style", null) as StyleBoxFlat
		if normal_style != null and hover_style != null:
			panel.add_theme_stylebox_override("panel", hover_style if pointer_inside else normal_style)

func _poll_lobby_presence_heartbeat_if_needed() -> void:
	if _scene_change_in_progress or _presence_heartbeat_in_flight or _lobby_bootstrap_active:
		return
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_lobby_presence_heartbeat_msec:
		return
	_presence_heartbeat_in_flight = true
	_next_lobby_presence_heartbeat_msec = now_msec + LOBBY_PRESENCE_HEARTBEAT_MSEC
	var response: Dictionary = await CloudAPI.update_profile_presence("online", "")
	_presence_heartbeat_in_flight = false
	if not bool(response.get("ok", false)):
		_next_lobby_presence_heartbeat_msec = Time.get_ticks_msec() + LOBBY_PRESENCE_HEARTBEAT_MSEC

func _poll_lobby_friend_requests_if_needed() -> void:
	if _scene_change_in_progress or _lobby_friend_request_poll_in_flight or _lobby_bootstrap_active:
		return
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_lobby_friend_request_poll_msec:
		return
	_lobby_friend_request_poll_in_flight = true
	_next_lobby_friend_request_poll_msec = now_msec + LOBBY_FRIEND_REQUEST_POLL_MSEC
	var response: Dictionary = await CloudAPI.get_incoming_friend_requests()
	_lobby_friend_request_poll_in_flight = false
	if not bool(response.get("ok", false)):
		_next_lobby_friend_request_poll_msec = Time.get_ticks_msec() + HOME_FRIENDS_FAILURE_RETRY_MS
		return
	var requests: Array = CloudAPI._extract_array_payload(response.get("data", []))
	var active_ids: Dictionary = {}
	for request_variant in requests:
		if not (request_variant is Dictionary):
			continue
		var request: Dictionary = request_variant
		var sender_id: String = str(request.get("from_user", "")).strip_edges()
		if sender_id.is_empty():
			continue
		active_ids[sender_id] = true
		if not _lobby_pending_friend_request_ids.has(sender_id):
			_lobby_pending_friend_request_ids[sender_id] = true
			_show_lobby_friend_request_popup(request)
	for known_id in _lobby_pending_friend_request_ids.keys():
		if not active_ids.has(str(known_id)):
			_lobby_pending_friend_request_ids.erase(known_id)

func _show_lobby_friend_request_popup(request: Dictionary) -> void:
	var sender_id: String = str(request.get("from_user", "")).strip_edges()
	if sender_id.is_empty():
		return
	var sender_profile: Dictionary = request.get("sender_profile", {}) if request.get("sender_profile", {}) is Dictionary else {}
	var sender_name: String = str(sender_profile.get("username", "Player")).strip_edges()
	if sender_name.is_empty():
		sender_name = "Player"
	_lobby_friend_request_sender_id = sender_id
	if _lobby_friend_request_popup == null or not is_instance_valid(_lobby_friend_request_popup):
		_lobby_friend_request_popup = Panel.new()
		_lobby_friend_request_popup.z_index = 350
		_lobby_friend_request_popup.custom_minimum_size = Vector2(360, 132)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.13, 0.15, 0.94)
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.shadow_color = Color(0, 0, 0, 0.24)
		style.shadow_size = 12
		_lobby_friend_request_popup.add_theme_stylebox_override("panel", style)
		add_child(_lobby_friend_request_popup)
	else:
		_clear_container(_lobby_friend_request_popup)
	_lobby_friend_request_popup.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lobby_friend_request_popup.offset_left = -382
	_lobby_friend_request_popup.offset_top = -154
	_lobby_friend_request_popup.offset_right = -22
	_lobby_friend_request_popup.offset_bottom = -22
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_lobby_friend_request_popup.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var title := Label.new()
	title.text = "%s sent you a friend request." % sender_name
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.18, 0.72, 0.35, 1.0)))
	accept_btn.add_theme_color_override("font_color", Color.WHITE)
	accept_btn.pressed.connect(func():
		await CloudAPI.accept_friend_request(sender_id)
		_lobby_pending_friend_request_ids.erase(sender_id)
		if is_instance_valid(_lobby_friend_request_popup):
			_lobby_friend_request_popup.hide()
		_refresh_friends_view()
		_schedule_home_dashboard_refresh(true)
	)
	row.add_child(accept_btn)
	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.74, 0.2, 0.18, 1.0)))
	decline_btn.add_theme_color_override("font_color", Color.WHITE)
	decline_btn.pressed.connect(func():
		await CloudAPI.decline_friend_request(sender_id)
		_lobby_pending_friend_request_ids.erase(sender_id)
		if is_instance_valid(_lobby_friend_request_popup):
			_lobby_friend_request_popup.hide()
		_refresh_friends_view()
	)
	row.add_child(decline_btn)
	_lobby_friend_request_popup.modulate.a = 1.0
	_lobby_friend_request_popup.show()

func _install_button_micro_interactions() -> void:
	_decorate_buttons_recursive(self)

func _decorate_buttons_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			_decorate_lobby_button(child as Button)
		_decorate_buttons_recursive(child)

func _decorate_lobby_button(button: Button) -> void:
	if button == null or button.has_meta("roblox_button_fx") or button.has_meta("classic_flat"):
		return
	if button.name.begins_with("Nav") and ("Btn" in button.name):
		return
	button.set_meta("roblox_button_fx", true)
	button.focus_mode = Control.FOCUS_NONE
	_refresh_button_pivot(button)
	button.resized.connect(_on_button_resized.bind(button))
	button.mouse_entered.connect(_on_button_hover_started.bind(button))
	button.mouse_exited.connect(_on_button_hover_ended.bind(button))
	button.button_down.connect(_on_button_pressed_down.bind(button))
	button.button_up.connect(_on_button_pressed_up.bind(button))
	_enhance_button_shadow_styles(button)

func _refresh_button_pivot(button: Control) -> void:
	if button == null:
		return
	button.pivot_offset = button.size * 0.5

func _on_button_resized(button: Control) -> void:
	_refresh_button_pivot(button)

func _on_button_hover_started(button: Button) -> void:
	_tween_button_scale(button, Vector2(1.02, 1.02))

func _on_button_hover_ended(button: Button) -> void:
	_tween_button_scale(button, Vector2.ONE)

func _on_button_pressed_down(button: Button) -> void:
	_tween_button_scale(button, Vector2(0.97, 0.97))

func _on_button_pressed_up(button: Button) -> void:
	# FIX Bug-1: Guard against viewport-null crash when lobby is being freed
	# during a scene change (button_up fires after change_scene_to_file starts).
	if not is_inside_tree() or button == null or not is_instance_valid(button):
		return
	var target_scale: Vector2 = Vector2(1.02, 1.02) if button.get_global_rect().has_point(get_global_mouse_position()) else Vector2.ONE
	_tween_button_scale(button, target_scale)

func _tween_button_scale(button: Control, target_scale: Vector2) -> void:
	if button == null:
		return
	var tween := create_tween()
	tween.tween_property(button, "scale", target_scale, 0.08)

func _enhance_button_shadow_styles(button: Button) -> void:
	for style_name in ["normal", "hover", "pressed"]:
		var base_style: StyleBox = button.get_theme_stylebox(style_name)
		if not (base_style is StyleBoxFlat):
			continue
		var styled := (base_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		styled.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
		styled.shadow_size = maxi(styled.shadow_size, 6)
		if style_name == "hover":
			styled.bg_color = styled.bg_color.lerp(Color.WHITE, 0.05)
		elif style_name == "pressed":
			styled.bg_color = styled.bg_color.darkened(0.08)
		button.add_theme_stylebox_override(style_name, styled)


func _switch_tab(idx: int) -> void:
	main_tabs.current_tab = idx
	if idx == Tab.HOME:
		_schedule_home_dashboard_refresh()
	elif idx == Tab.PROFILE:
		call_deferred("_refresh_selected_profile_async")
	elif idx == Tab.AVATAR:
		_ensure_avatar_ui_initialized()
		_request_avatar_inventory_load()
	elif idx == Tab.FRIENDS:
		call_deferred("_refresh_friends_view")
	elif idx == Tab.INVENTORY:
		_ensure_inventory_view_initialized()
		call_deferred("_refresh_inventory_async")
	elif idx == Tab.MESSAGES:
		_ensure_messages_initialized()
	elif idx == Tab.GAMES:
		call_deferred("_refresh_games_view")
	elif idx == Tab.CATALOG:
		_ensure_catalog_ui_initialized()
	elif is_instance_valid(_boblox_shop) and idx == _boblox_shop.get_index():
		_boblox_shop.call("refresh")

func _install_boblox_shop() -> void:
	_boblox_shop = BOBLOX_SHOP_SCRIPT.new()
	_boblox_shop.set("preview_only", bool(get_meta("boblox_preview", false)))
	_boblox_shop.name = "BobloxView"
	main_tabs.add_child(_boblox_shop)
	_boblox_shop.connect("account_updated", _on_boblox_account_updated)
	var nav := get_node_or_null("TopBar/HBox/Nav4") as Button
	if nav:
		nav.text = "Boblox"
		nav.pressed.connect(func(): _open_boblox_shop(1))
	var upgrade := get_node_or_null("Body/HBox/Sidebar/UpgradeBtn") as Button
	if upgrade:
		upgrade.text = "Вступить в клуб"
		upgrade.pressed.connect(func(): _open_boblox_shop(0))

func _open_boblox_shop(section: int) -> void:
	_switch_tab(_boblox_shop.get_index())
	_boblox_shop.call("select_section", section)

func _on_boblox_account_updated(account: Dictionary) -> void:
	ACCOUNT_BADGES.attach(sidebar_username, account)
	if selected_profile_user_id == UserSession.user_id:
		ACCOUNT_BADGES.attach(profile_username_label, account, true)
	var reward: Dictionary = account.get("founder_reward", {}) if account.get("founder_reward") is Dictionary else {}
	if reward.get("pending", false) and not is_instance_valid(_founder_reward_dialog):
		_founder_reward_dialog = preload("res://scripts/lobby/founder_reward.gd").new()
		_founder_reward_dialog.claimed.connect(func(updated: Dictionary):
			_boblox_shop.call("_set_account", updated)
			_boblox_shop.call("_render")
			_refresh_selected_profile_async()
		)
		add_child(_founder_reward_dialog)
	var nav := get_node_or_null("TopBar/HBox/Nav4") as Button
	if nav: nav.text = "Boblox"
	var wallet := get_node_or_null("TopBar/HBox/HeaderBobloxBalance") as Button
	if wallet: wallet.text = "B$ %d%s" % [int(account.get("balance", 0)), "*" if account.get("test", false) else ""]
	var tier := str(account.get("membership", {}).get("tier", "BC"))
	if tier not in ["BC", "BBC", "PBC", "TBC"]: tier = "BC"
	var upgrade := get_node_or_null("Body/HBox/Sidebar/UpgradeBtn") as Button
	if upgrade:
		upgrade.text = "Вступить в клуб" if tier == "BC" else "%s · Мой клуб" % tier

func _schedule_home_dashboard_refresh(force_refresh: bool = false) -> void:
	if force_refresh:
		_home_dashboard_refresh_force_pending = true
	if _home_dashboard_refresh_scheduled:
		return
	_home_dashboard_refresh_scheduled = true
	call_deferred("_run_scheduled_home_dashboard_refresh")

func _run_scheduled_home_dashboard_refresh() -> void:
	_home_dashboard_refresh_scheduled = false
	var now_msec := Time.get_ticks_msec()
	var force_refresh: bool = _home_dashboard_refresh_force_pending
	_home_dashboard_refresh_force_pending = false
	if not force_refresh and now_msec - _last_home_dashboard_refresh_msec < HOME_REFRESH_MIN_INTERVAL_MS:
		return
	_last_home_dashboard_refresh_msec = now_msec
	_refresh_home_dashboard()

func _request_avatar_inventory_load() -> void:
	if _avatar_inventory_load_requested:
		return
	_avatar_inventory_load_requested = true
	_ensure_avatar_ui_initialized()
	if avatar_ui != null and avatar_ui.has_method("ensure_cloud_inventory_loaded"):
		avatar_ui.call_deferred("ensure_cloud_inventory_loaded")

func _ensure_avatar_ui_initialized() -> void:
	if avatar_ui != null:
		return
	_build_avatar_view_if_placeholder()
	avatar_ui = AVATAR_UI_SCRIPT.new()
	avatar_ui.init(self)

func _ensure_catalog_ui_initialized() -> void:
	if _catalog_ui_built:
		return
	_catalog_ui_built = true
	var catalog_builder_script = load("res://scripts/lobby/catalog_builder.gd")
	if catalog_builder_script:
		catalog_builder_script.build(self)

func _ensure_inventory_view_initialized() -> void:
	if _inventory_ui_built:
		return
	var inventory_view := main_tabs.get_node_or_null("InventoryView") as Control if main_tabs != null else null
	if inventory_view == null:
		return
	_inventory_ui_built = true
	_clear_children_immediate(inventory_view)
	if inventory_view is Panel:
		(inventory_view as Panel).add_theme_stylebox_override("panel", _make_white_panel_style())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18 if _is_mobile_beta() else 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 18 if _is_mobile_beta() else 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	inventory_view.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	var title := Label.new()
	title.text = "My Inventory"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.12, 0.13, 0.15, 1))
	title_box.add_child(title)
	_inventory_status_label = Label.new()
	_inventory_status_label.text = "Loading your items..."
	_inventory_status_label.add_theme_font_size_override("font_size", 13)
	_inventory_status_label.add_theme_color_override("font_color", Color(0.44, 0.46, 0.50, 1))
	title_box.add_child(_inventory_status_label)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.custom_minimum_size = Vector2(104, 38)
	refresh_button.pressed.connect(func() -> void:
		_inventory_cache_expires_at_msec = 0
		_refresh_inventory_async()
	)
	header.add_child(refresh_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	var category_panel := PanelContainer.new()
	category_panel.custom_minimum_size = Vector2(148 if _is_mobile_beta() else 178, 0)
	var category_style := _make_white_panel_style()
	category_style.bg_color = Color(0.955, 0.96, 0.97, 1)
	category_panel.add_theme_stylebox_override("panel", category_style)
	body.add_child(category_panel)
	var category_margin := MarginContainer.new()
	category_margin.add_theme_constant_override("margin_left", 8)
	category_margin.add_theme_constant_override("margin_top", 10)
	category_margin.add_theme_constant_override("margin_right", 8)
	category_margin.add_theme_constant_override("margin_bottom", 10)
	category_panel.add_child(category_margin)
	var categories := VBoxContainer.new()
	categories.add_theme_constant_override("separation", 4)
	category_margin.add_child(categories)
	_inventory_category_buttons.clear()
	for category_name in ["All", "Clothing", "Accessories", "Faces", "Models"]:
		var category_button := Button.new()
		category_button.text = category_name
		category_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		category_button.toggle_mode = true
		category_button.button_pressed = category_name == _inventory_active_category
		category_button.custom_minimum_size = Vector2(0, 38)
		category_button.pressed.connect(_set_inventory_category.bind(category_name))
		categories.add_child(category_button)
		_inventory_category_buttons[category_name] = category_button

	var item_scroll := ScrollContainer.new()
	item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(item_scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 2 if _is_mobile_beta() else 5
	_inventory_grid.add_theme_constant_override("h_separation", 12)
	_inventory_grid.add_theme_constant_override("v_separation", 12)
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(_inventory_grid)

func _set_inventory_category(category_name: String) -> void:
	_inventory_active_category = category_name
	for key in _inventory_category_buttons.keys():
		var button := _inventory_category_buttons.get(key) as Button
		if button != null:
			button.set_pressed_no_signal(str(key) == category_name)
	_render_inventory_items()

func _refresh_inventory_async() -> void:
	_ensure_inventory_view_initialized()
	if _inventory_grid == null:
		return
	var now_msec := Time.get_ticks_msec()
	if not _inventory_items_cache.is_empty() and now_msec < _inventory_cache_expires_at_msec:
		_render_inventory_items()
		return
	_inventory_refresh_generation += 1
	var generation := _inventory_refresh_generation
	if _inventory_status_label != null:
		_inventory_status_label.text = "Loading owned clothes, accessories and models..."
	var sources: Array = []
	if CloudAPI != null and CloudAPI.is_configured():
		if CloudAPI.has_method("fetch_catalog_items"):
			var catalog_result: Dictionary = await CloudAPI.fetch_catalog_items()
			if bool(catalog_result.get("ok", false)):
				sources.append_array(_extract_response_array(catalog_result))
		if CloudAPI.has_method("fetch_avatar_marketplace_items"):
			var avatar_result: Dictionary = await CloudAPI.fetch_avatar_marketplace_items(240, true, false)
			if bool(avatar_result.get("ok", false)):
				sources.append_array(_extract_response_array(avatar_result))
		if CloudAPI.has_method("fetch_marketplace_models"):
			var model_result: Dictionary = await CloudAPI.fetch_marketplace_models(240, true, false)
			if bool(model_result.get("ok", false)):
				sources.append_array(_extract_response_array(model_result))
	if generation != _inventory_refresh_generation or not is_instance_valid(self):
		return

	var owned_ids: Dictionary = {}
	if UserSession.inventory_items is Array:
		for raw_id in UserSession.inventory_items:
			owned_ids[str(raw_id).strip_edges()] = true
	var own_user_id := str(UserSession.user_id).strip_edges()
	var items: Array = _collect_local_inventory_visual_items()
	var seen: Dictionary = {}
	for local_item in items:
		if local_item is Dictionary:
			seen[_inventory_item_id(local_item)] = true
	for source_variant in sources:
		if not (source_variant is Dictionary):
			continue
		var item := (source_variant as Dictionary).duplicate(true)
		var item_id := _inventory_item_id(item)
		if item_id.is_empty() or seen.has(item_id):
			continue
		var owner_id := str(item.get("owner_id", item.get("creator_id", item.get("user_id", "")))).strip_edges()
		var is_owned := bool(owned_ids.get(item_id, false)) or bool(item.get("owned", false)) or (not own_user_id.is_empty() and owner_id == own_user_id)
		if not is_owned:
			continue
		seen[item_id] = true
		items.append(item)
	_inventory_items_cache = items
	_inventory_cache_expires_at_msec = Time.get_ticks_msec() + 30000
	_render_inventory_items()

func _collect_local_inventory_visual_items() -> Array:
	var result: Array = []
	var avatar_data: Dictionary = UserSession.avatar_data if UserSession.avatar_data is Dictionary else {}
	var shirt_paths: Array = avatar_data.get("saved_shirt_texture_paths", []) if avatar_data.get("saved_shirt_texture_paths", []) is Array else []
	var active_shirt := str(avatar_data.get("shirt_texture_path", "")).strip_edges()
	if not active_shirt.is_empty() and not (active_shirt in shirt_paths):
		shirt_paths.append(active_shirt)
	for index in range(shirt_paths.size()):
		var path := str(shirt_paths[index]).strip_edges()
		if not path.is_empty():
			result.append({"id": "local_shirt_%d" % index, "name": "Shirt %d" % (index + 1), "category": "Shirt", "thumbnail": path})
	var pants_paths: Array = avatar_data.get("saved_pants_texture_paths", []) if avatar_data.get("saved_pants_texture_paths", []) is Array else []
	var active_pants := str(avatar_data.get("pants_texture_path", "")).strip_edges()
	if not active_pants.is_empty() and not (active_pants in pants_paths):
		pants_paths.append(active_pants)
	for index in range(pants_paths.size()):
		var path := str(pants_paths[index]).strip_edges()
		if not path.is_empty():
			result.append({"id": "local_pants_%d" % index, "name": "Pants %d" % (index + 1), "category": "Pants", "thumbnail": path})
	return result

func _inventory_item_id(item: Dictionary) -> String:
	return str(item.get("id", item.get("item_id", item.get("model_id", item.get("name", ""))))).strip_edges()

func _inventory_item_category(item: Dictionary) -> String:
	var nested := _dictionary_from_jsonish_variant(item.get("data", {}))
	var raw := str(item.get("category", item.get("item_kind", item.get("asset_type", nested.get("category", nested.get("item_kind", "")))))).strip_edges().to_lower()
	if raw.find("shirt") >= 0 or raw.find("pants") >= 0 or raw.find("cloth") >= 0:
		return "Clothing"
	if raw.find("face") >= 0:
		return "Faces"
	if raw.find("model") >= 0 or item.has("model_data") or nested.has("parts"):
		return "Models"
	return "Accessories"

func _render_inventory_items() -> void:
	if _inventory_grid == null:
		return
	_inventory_render_generation += 1
	var render_generation := _inventory_render_generation
	_clear_children_immediate(_inventory_grid)
	var visible_items: Array = []
	for item_variant in _inventory_items_cache:
		if not (item_variant is Dictionary):
			continue
		var item := item_variant as Dictionary
		var category := _inventory_item_category(item)
		if _inventory_active_category != "All" and category != _inventory_active_category:
			continue
		visible_items.append({"item": item.duplicate(true), "category": category})
	if visible_items.is_empty():
		var empty := Label.new()
		empty.text = "No owned items in this category."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(0.46, 0.48, 0.52, 1))
		_inventory_grid.add_child(empty)
	else:
		_render_inventory_items_async(visible_items, render_generation)
	if _inventory_status_label != null:
		_inventory_status_label.text = "%d owned item(s)" % _inventory_items_cache.size()

func _render_inventory_items_async(items: Array, render_generation: int) -> void:
	var rendered_in_frame := 0
	for entry_variant in items:
		if render_generation != _inventory_render_generation or _inventory_grid == null or not is_instance_valid(_inventory_grid):
			return
		if entry_variant is Dictionary:
			var entry := entry_variant as Dictionary
			var item: Dictionary = entry.get("item", {}) if entry.get("item", {}) is Dictionary else {}
			_inventory_grid.add_child(_create_inventory_item_card(item, str(entry.get("category", "Accessories"))))
			rendered_in_frame += 1
		if rendered_in_frame >= 8:
			rendered_in_frame = 0
			if is_inside_tree():
				await get_tree().process_frame
			else:
				return

func _create_inventory_item_card(item: Dictionary, category: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(164, 218)
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var preview := _create_profile_wearing_item_preview(item)
	preview.custom_minimum_size = Vector2(150, 142)
	box.add_child(preview)
	var title := Label.new()
	title.text = str(item.get("name", "Item")).strip_edges()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.13, 0.14, 0.16, 1))
	box.add_child(title)
	var kind := Label.new()
	kind.text = category
	kind.add_theme_font_size_override("font_size", 11)
	kind.add_theme_color_override("font_color", Color(0.47, 0.49, 0.53, 1))
	box.add_child(kind)
	return panel

func _select_part(part_name: String) -> void:
	selected_part = part_name
	_highlight_body_part_buttons()
	Analytics.log_button_click("select_part_" + part_name)

func _highlight_body_part_buttons() -> void:
	if _is_live_control(btn_head):
		_style_body_part_button("head", btn_head)
	else:
		btn_head = null
	if _is_live_control(btn_torso):
		_style_body_part_button("torso", btn_torso)
	else:
		btn_torso = null
	if _is_live_control(btn_left_arm):
		_style_body_part_button("left_arm", btn_left_arm)
	else:
		btn_left_arm = null
	if _is_live_control(btn_right_arm):
		_style_body_part_button("right_arm", btn_right_arm)
	else:
		btn_right_arm = null
	if _is_live_control(btn_left_leg):
		_style_body_part_button("left_leg", btn_left_leg)
	else:
		btn_left_leg = null
	if _is_live_control(btn_right_leg):
		_style_body_part_button("right_leg", btn_right_leg)
	else:
		btn_right_leg = null

func _is_live_control(control: Variant) -> bool:
	return control != null and is_instance_valid(control) and not control.is_queued_for_deletion()

func _style_body_part_button(part_name: String, btn: Button) -> void:
	if not _is_live_control(btn):
		return
	var is_selected: bool = part_name == selected_part
	btn.add_theme_color_override("font_color", Color.WHITE if is_selected else Color(0.25, 0.25, 0.25, 1))
	var col: Color = _get_part_color(part_name)
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	if is_selected:
		s.border_width_left = 3
		s.border_width_top = 3
		s.border_width_right = 3
		s.border_width_bottom = 3
		s.border_color = Color(0.086, 0.357, 0.678, 1)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s.duplicate())
	btn.add_theme_stylebox_override("pressed", s.duplicate())

func _get_part_color(part_name: String) -> Color:
	match part_name:
		"head": return GameState.head_color
		"torso": return GameState.torso_color
		"left_arm": return GameState.left_arm_color
		"right_arm": return GameState.right_arm_color
		"left_leg": return GameState.left_leg_color
		"right_leg": return GameState.right_leg_color
	return Color(0.9, 0.9, 0.9, 1)

func _on_color_selected(color: Color) -> void:
	match selected_part:
		"head": GameState.head_color = color
		"torso": GameState.torso_color = color
		"left_arm": GameState.left_arm_color = color
		"right_arm": GameState.right_arm_color = color
		"left_leg": GameState.left_leg_color = color
		"right_leg": GameState.right_leg_color = color
	_update_preview_colors()
	UserSession.avatar_data = _build_avatar_session_payload()
	UserSession.save_profile()
	_queue_avatar_cloud_sync()
	Analytics.log_button_click("color_change")

func _update_preview_colors() -> void:
	_ensure_avatar_preview_player_reference()
	var preview_targets: Array = [preview_player, home_avatar_player]
	if _is_viewing_own_profile():
		preview_targets.append(profile_header_preview_player)
		preview_targets.append(profile_preview_player)
	for p in preview_targets:
		if p == null: continue
		p.head_color = GameState.head_color
		p.torso_color = GameState.torso_color
		p.left_arm_color = GameState.left_arm_color
		p.right_arm_color = GameState.right_arm_color
		p.left_leg_color = GameState.left_leg_color
		p.right_leg_color = GameState.right_leg_color
	_highlight_body_part_buttons()

func _is_viewing_own_profile() -> bool:
	var target_user_id: String = selected_profile_user_id.strip_edges()
	return target_user_id.is_empty() or target_user_id == UserSession.user_id

func _ensure_avatar_preview_player_reference() -> void:
	if preview_player != null:
		return
	var avatar_view: Node = main_tabs.get_node_or_null("AvatarView") if main_tabs else null
	if avatar_view == null:
		return
	preview_player = _find_child_by_name_recursive(avatar_view, "PreviewPlayer")

func _select_mode(mode: String, btn: Button, all_btns: Array) -> void:
	GameState.selected_map = mode
	GameState.selected_map_folder = ""
	# Highlight selected
	for b in all_btns:
		if b != null:
			b.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	btn.add_theme_color_override("font_color", Color(0.1, 0.7, 0.3, 1))
	Analytics.log_button_click("mode_" + mode)

func _on_play_pressed() -> void:
	Analytics.log_button_click("smart_play")
	var local_entries: Array = _get_continue_playing_entries()
	if not local_entries.is_empty():
		_start_smart_play_for_game(local_entries[0])
		return
	var cached_entries: Array = _get_cached_discover_entries()
	if not cached_entries.is_empty():
		_start_smart_play_for_game(cached_entries[0])
		return
	if CloudAPI != null and CloudAPI.is_configured():
		_show_loading_overlay("Loading...", "Finding a playable Bobux experience...", 0.08)
		var maps_result: Dictionary = await CloudAPI.fetch_published_maps(12)
		if bool(maps_result.get("ok", false)):
			for map_variant in CloudAPI._extract_array_payload(maps_result.get("data", [])):
				if not (map_variant is Dictionary):
					continue
				var cloud_entry: Dictionary = _make_game_entry_from_cloud_map(map_variant)
				if str(cloud_entry.get("map_id", "")).strip_edges().is_empty() or _should_hide_discover_entry(cloud_entry):
					continue
				_start_smart_play_for_game(cloud_entry)
				return
	await _show_loading_error("No playable experiences found.", "Open Games or Develop after the lobby finishes refreshing.")

func _on_logout() -> void:
	Analytics.log_button_click("logout")
	await _set_presence_offline_async()
	# FIX Issue-2: Disconnect network FIRST to prevent stale room state,
	# then wipe cloud auth, user session, and game state in order.
	if NetworkManager != null and NetworkManager.has_method("disconnect_from_session"):
		NetworkManager.disconnect_from_session()
	CloudAPI.reset_authenticated_session(true)
	UserSession.clear()
	GameState.clear_session()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	get_tree().call_deferred("change_scene_to_file", "res://scenes/login/login.tscn")

func _gather_colors() -> Dictionary:
	return {
		"head": GameState.head_color,
		"torso": GameState.torso_color,
		"left_arm": GameState.left_arm_color,
		"right_arm": GameState.right_arm_color,
		"left_leg": GameState.left_leg_color,
		"right_leg": GameState.right_leg_color
	}

func _build_avatar_session_payload() -> Dictionary:
	var payload: Dictionary = UserSession.avatar_data.duplicate(true) if UserSession.avatar_data is Dictionary else {}
	var gathered_colors: Dictionary = _gather_colors()
	for color_key in gathered_colors.keys():
		payload[color_key] = gathered_colors[color_key]
	if not payload.has("equipped") or not (payload.get("equipped", []) is Array):
		payload["equipped"] = []
	return payload

func _build_avatar_outfit_payload() -> Dictionary:
	var equipped_items: Array = []
	if UserSession.avatar_data is Dictionary and UserSession.avatar_data.get("equipped", []) is Array:
		equipped_items = (UserSession.avatar_data.get("equipped", []) as Array).duplicate()
	var saved_shirt_paths: Array = []
	if UserSession.avatar_data is Dictionary and UserSession.avatar_data.get("saved_shirt_texture_paths", []) is Array:
		saved_shirt_paths = (UserSession.avatar_data.get("saved_shirt_texture_paths", []) as Array).duplicate(true)
	var saved_pants_paths: Array = []
	if UserSession.avatar_data is Dictionary and UserSession.avatar_data.get("saved_pants_texture_paths", []) is Array:
		saved_pants_paths = (UserSession.avatar_data.get("saved_pants_texture_paths", []) as Array).duplicate(true)
	var avatar_data: Dictionary = UserSession.avatar_data if UserSession.avatar_data is Dictionary else {}
	var payload := {
		"head_color": "#" + GameState.head_color.to_html(false),
		"torso_color": "#" + GameState.torso_color.to_html(false),
		"left_arm_color": "#" + GameState.left_arm_color.to_html(false),
		"right_arm_color": "#" + GameState.right_arm_color.to_html(false),
		"left_leg_color": "#" + GameState.left_leg_color.to_html(false),
		"right_leg_color": "#" + GameState.right_leg_color.to_html(false),
		"equipped_items": equipped_items,
		"body_type": "R6",
		"face_texture_path": str(avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)),
		"chest_badge_texture_path": str(avatar_data.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)),
		"shirt_texture_path": str(avatar_data.get("shirt_texture_path", "")),
		"pants_texture_path": str(avatar_data.get("pants_texture_path", "")),
		"saved_shirt_texture_paths": saved_shirt_paths,
		"saved_pants_texture_paths": saved_pants_paths
	}
	return payload

func _queue_avatar_cloud_sync() -> void:
	_avatar_cloud_sync_pending = true
	if _avatar_cloud_sync_in_flight:
		return
	call_deferred("_flush_avatar_cloud_sync_async")

func _flush_avatar_cloud_sync_async() -> void:
	if _avatar_cloud_sync_in_flight:
		return
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		_avatar_cloud_sync_pending = false
		return
	_avatar_cloud_sync_in_flight = true
	while _avatar_cloud_sync_pending:
		_avatar_cloud_sync_pending = false
		var avatar_payload: Dictionary = _build_avatar_session_payload()
		var inventory_snapshot: Array = UserSession.inventory_items.duplicate() if UserSession.inventory_items is Array else []
		var profile_result: Dictionary = await CloudAPI.update_profile_avatar(avatar_payload, inventory_snapshot)
		if not bool(profile_result.get("ok", false)):
			push_warning("[Lobby] Failed to save avatar_data: %s" % str(profile_result.get("error", "Unknown profile avatar error")))
		var outfit_result: Dictionary = await CloudAPI.update_avatar_outfit(_build_avatar_outfit_payload())
		if not bool(outfit_result.get("ok", false)):
			push_warning("[Lobby] Failed to save avatar_outfit: %s" % str(outfit_result.get("error", "Unknown avatar outfit error")))
	_avatar_cloud_sync_in_flight = false

func _refresh_lobby_presence() -> void:
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	var response: Dictionary = await CloudAPI.update_profile_presence("online", "")
	if bool(response.get("ok", false)):
		_next_lobby_presence_heartbeat_msec = Time.get_ticks_msec() + LOBBY_PRESENCE_HEARTBEAT_MSEC

func _bootstrap_cloud_lobby() -> void:
	_lobby_bootstrap_active = true
	_show_loading_overlay("Loading Bobux", "Opening lobby shell...", 0.12)
	await get_tree().process_frame
	if NetworkManager != null and NetworkManager.has_method("prepare_for_lobby"):
		NetworkManager.prepare_for_lobby()
	GameState.clear_launch_mode()
	if CloudAPI.is_configured():
		_update_loading_overlay("Signing in", "Checking your Bobux session...", 0.32)
		var preferred_username: String = UserSession.username if UserSession.is_logged_in else CloudAPI.get_current_username()
		var auth_result: Dictionary = await CloudAPI.authenticate_or_create_profile(preferred_username)
		if bool(auth_result.get("ok", false)):
			_update_loading_overlay("Loading profile", "Applying your avatar and session cache...", 0.58)
			var display_username: String = str(auth_result.get("username", preferred_username)).strip_edges()
			UserSession.begin_cloud_session(CloudAPI.get_current_user_id(), display_username)
			sidebar_username.text = display_username
			profile_username_label.text = display_username
			join_date_label.text = "Join Date: %s" % UserSession.join_date
			_update_preview_colors()
			call_deferred("_refresh_lobby_presence")
		else:
			push_warning("[Lobby] Bootstrap auth failed softly: %s" % str(auth_result.get("error", "Unknown auth error")))
	_update_loading_overlay("Loading lobby", "Drawing cached pages before network sections...", 0.82)
	await get_tree().process_frame
	_lobby_bootstrap_active = false
	_lobby_bootstrap_finished = true
	_home_friends_refresh_pending = false
	_discover_refresh_pending = false
	_next_lobby_friend_request_poll_msec = Time.get_ticks_msec() + 9000
	_next_lobby_presence_heartbeat_msec = Time.get_ticks_msec() + 2500
	_hide_loading_overlay()
	# Only refresh the data-dependent sections (friends/discover), not the whole
	# dashboard, because _ready() already called _build_home_dashboard +
	# _switch_tab(HOME) which triggers a full _refresh_home_dashboard. Calling
	# it again here was the root cause of the freeze and friend duplication.
	_schedule_home_dashboard_refresh(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		# BUGFIX: desktop starts windowed; F11 is the explicit fullscreen toggle.
		var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		ClientPreferences.update("fullscreen", not fullscreen)
		get_viewport().set_input_as_handled()

func _apply_bobux_branding() -> void:
	var left_padding := get_node_or_null("TopBar/HBox/PaddingL") as Control
	if left_padding != null:
		left_padding.custom_minimum_size = Vector2(2, 0)
	var logo_holder := get_node_or_null("TopBar/HBox/Logo") as Control
	if logo_holder == null:
		return
	if logo_holder is Label:
		(logo_holder as Label).text = ""
	var is_mobile := _is_mobile_beta()
	logo_holder.custom_minimum_size = Vector2(140, 42) if is_mobile else Vector2(230, 42)
	for child in logo_holder.get_children():
		child.queue_free()
	var logo_texture := _load_ui_image_texture("res://assets/branding/bobux_logo_ui.png")
	if logo_texture == null:
		return
	var logo_rect := TextureRect.new()
	logo_rect.name = "BobuxLogoTexture"
	logo_rect.texture = logo_texture
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_holder.add_child(logo_rect)

func _load_ui_image_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture != null:
		return texture
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _set_presence_offline_async() -> void:
	if not CloudAPI.is_configured() or not CloudAPI.has_authenticated_session():
		return
	await CloudAPI.update_profile_presence("offline", "")

func _build_home_dashboard() -> void:
	var home_content := get_node_or_null("Body/HBox/MainTabs/HomeView/Content") as VBoxContainer
	if home_content == null:
		return
	_style_home_scroll_surface()
	_clear_container(home_content)
	home_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_content.custom_minimum_size.x = 0.0
	var home_view := home_content.get_parent() as Control
	if not home_view.resized.is_connected(_queue_home_layout_refresh):
		home_view.resized.connect(_queue_home_layout_refresh)
	if not get_viewport().size_changed.is_connected(_queue_home_layout_refresh):
		get_viewport().size_changed.connect(_queue_home_layout_refresh)

	var uname: String = UserSession.username if UserSession.is_logged_in else "Player"
	
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 18)
	home_content.add_child(header_hbox)

	var home_avatar := _create_home_header_avatar_preview(120)
	home_avatar.custom_minimum_size = Vector2(120, 120)
	header_hbox.add_child(home_avatar)

	var header_name_box := VBoxContainer.new()
	header_name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header_hbox.add_child(header_name_box)

	var greeting_label := Label.new()
	greeting_label.text = "Hello, %s!" % uname
	greeting_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	greeting_label.add_theme_font_size_override("font_size", 28)
	header_name_box.add_child(greeting_label)
	var greeting_subtitle := Label.new()
	greeting_subtitle.text = "See what your friends are building and playing."
	greeting_subtitle.add_theme_color_override("font_color", Color(0.46, 0.47, 0.5, 1))
	greeting_subtitle.add_theme_font_size_override("font_size", 12)
	header_name_box.add_child(greeting_subtitle)
	
	var sep_space := Control.new()
	sep_space.custom_minimum_size = Vector2(0, 2)
	home_content.add_child(sep_space)

	var friends_panel_parts := _create_dashboard_panel(home_content, "Friends", "Online friends appear first.", 198, "See All", Callable(self, "_open_home_see_all_friends"))
	home_friends_status = friends_panel_parts.get("status_label", null)

	home_friends_clip = Control.new()
	home_friends_clip.name = "HomeFriendsScroll"
	home_friends_clip.custom_minimum_size = Vector2(0, 124)
	home_friends_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_friends_clip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	home_friends_clip.clip_contents = true
	home_friends_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	home_friends_clip.gui_input.connect(_on_home_friends_clip_gui_input)
	home_friends_clip.resized.connect(_update_home_friends_clip_layout)
	friends_panel_parts["content"].add_child(home_friends_clip)
	home_friends_container = HBoxContainer.new()
	home_friends_container.add_theme_constant_override("separation", 14)
	home_friends_container.custom_minimum_size = Vector2(0, 0)
	home_friends_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	home_friends_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	home_friends_container.mouse_filter = Control.MOUSE_FILTER_PASS
	home_friends_clip.add_child(home_friends_container)

	if home_friend_popup == null:
		_ensure_home_friend_popup()

	var recommended_panel_parts := _create_dashboard_panel(home_content, "Recommended", "Popular experiences and worlds with players online.", 278.0, "See All", Callable(self, "_open_home_see_all_games"))
	recommended_status_label = recommended_panel_parts.get("status_label", null)
	recommended_cards_grid = _create_home_game_grid(_get_home_game_grid_columns())
	recommended_panel_parts["content"].add_child(recommended_cards_grid)

	var continue_panel_parts := _create_dashboard_panel(home_content, "Continue Playing", "Jump back into your recent experiences.", 278.0, "See All", Callable(self, "_open_home_see_all_games"))
	continue_status_label = continue_panel_parts.get("status_label", null)

	continue_cards_container = HFlowContainer.new()
	continue_cards_container.add_theme_constant_override("h_separation", 12)
	continue_cards_container.add_theme_constant_override("v_separation", 10)
	continue_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_panel_parts["content"].add_child(continue_cards_container)

	var creator_panel_parts := _create_dashboard_panel(home_content, "From Bobux Creators", "Experiences from pavelord and the Bobux team.", 278.0, "See All", Callable(self, "_open_home_see_all_games"))
	bobux_creator_status_label = creator_panel_parts.get("status_label", null)
	var creator_panel_control := creator_panel_parts.get("panel", null) as Control
	if creator_panel_control != null:
		creator_panel_control.custom_minimum_size = Vector2(0, 278)
	var creator_title_label := creator_panel_parts.get("title_label", null) as Label
	if creator_title_label != null:
		creator_title_label.text = "From Bobux Creators"
	var creator_subtitle_label := creator_panel_parts.get("subtitle_label", null) as Label
	if creator_subtitle_label != null:
		creator_subtitle_label.text = "Experiences from pavelord and the Bobux team."

	var creator_scroll := ScrollContainer.new()
	creator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	creator_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	creator_scroll.custom_minimum_size = Vector2(0, 242)
	creator_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_panel_parts["content"].add_child(creator_scroll)

	var creator_row := HBoxContainer.new()
	creator_row.add_theme_constant_override("separation", 12)
	creator_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	creator_scroll.add_child(creator_row)
	bobux_creator_cards_grid = creator_row

	var new_panel_parts := _create_dashboard_panel(home_content, "New Experiences", "Freshly published places.", 278.0, "See All", Callable(self, "_open_home_see_all_games"))
	new_status_label = new_panel_parts.get("status_label", null)
	new_cards_grid = _create_home_game_grid(_get_home_game_grid_columns())
	new_panel_parts["content"].add_child(new_cards_grid)

	var all_panel_parts := _create_dashboard_panel(home_content, "All Experiences", "Everything currently published on Bobux.", 470.0, "See All", Callable(self, "_open_home_see_all_games"))
	all_status_label = all_panel_parts.get("status_label", null)
	all_cards_grid = _create_home_game_grid(_get_home_game_grid_columns())
	all_panel_parts["content"].add_child(all_cards_grid)

	# Backward-compatible aliases for helpers that still refer to Discover.
	discover_cards_grid = all_cards_grid
	discover_status_label = all_status_label

	_ensure_loading_overlay()

func _create_home_game_grid(columns: int = 3) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = maxi(columns, 1)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return grid

func _get_home_game_grid_columns() -> int:
	var home_view := get_node_or_null("Body/HBox/MainTabs/HomeView") as Control
	var available := home_view.size.x - 32.0 if is_instance_valid(home_view) else get_viewport_rect().size.x - 220.0
	if is_instance_valid(home_view):
		# Existing grid minima may still describe the old, wider window. Bound
		# by the viewport so those minima cannot prevent columns from shrinking.
		available = minf(available, get_viewport_rect().size.x - home_view.global_position.x - 40.0)
	return maxi(1, int(floor((available + 12.0) / 160.0)))

func _queue_home_layout_refresh() -> void:
	_refresh_home_layout.call_deferred()

func _refresh_home_layout() -> void:
	if _lobby_exiting or not is_inside_tree(): return
	var columns := _get_home_game_grid_columns()
	if columns == _home_layout_columns: return
	_home_layout_columns = columns
	if not _home_layout_entries.is_empty():
		_render_home_game_sections(_home_layout_entries, _discover_refresh_token)

func _ensure_all_tabs_exist() -> void:
	if main_tabs == null: return
	var desired_names = ["HomeView", "ProfileView", "AvatarView", "FriendsView", "InventoryView", "MessagesView", "DevelopView", "TradeView", "GroupsView", "BlogView", "PromocodesView", "CatalogView", "GamesView", "GameDetailsView"]
	var dict = {}
	for child in main_tabs.get_children():
		dict[child.name] = child
		main_tabs.remove_child(child)
	for d_name in desired_names:
		if dict.has(d_name):
			main_tabs.add_child(dict[d_name])
		else:
			var sc = ScrollContainer.new()
			sc.name = d_name
			var v = VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_constant_override("separation", 50)
			sc.add_child(v)
			var s = Control.new()
			s.custom_minimum_size.y = 50
			v.add_child(s)
			var l = Label.new()
			l.text = d_name.replace("View", "") + " - Coming Soon"
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
			l.add_theme_font_size_override("font_size", 24)
			v.add_child(l)
			main_tabs.add_child(sc)
	# Avatar UI is built lazily on first Avatar tab open. Building it during
	# lobby bootstrap can stall weak networks/large inventories right after login.

func _build_avatar_view_if_placeholder() -> void:
	var avatar_view: Control = main_tabs.get_node_or_null("AvatarView")
	if avatar_view == null:
		return
	# If AvatarView already has a proper UI (e.g. from scene file), skip.
	if avatar_view.get_node_or_null("Content") != null:
		return
	# Clear placeholder content
	for child in avatar_view.get_children():
		child.queue_free()

	# Root layout: Content VBox inside a MarginContainer
	var margin := MarginContainer.new()
	margin.name = "AvatarMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	avatar_view.add_child(margin)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 24)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	# === LEFT: 3D Preview ===
	var left_panel := Panel.new()
	left_panel.custom_minimum_size = Vector2(300, 500)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lp_style := StyleBoxFlat.new()
	lp_style.bg_color = Color(0.92, 0.92, 0.92)
	lp_style.corner_radius_top_left = 8; lp_style.corner_radius_top_right = 8
	lp_style.corner_radius_bottom_left = 8; lp_style.corner_radius_bottom_right = 8
	left_panel.add_theme_stylebox_override("panel", lp_style)
	content.add_child(left_panel)

	var svpc := SubViewportContainer.new()
	svpc.stretch = true
	svpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_panel.add_child(svpc)

	var svp := SubViewport.new()
	svp.transparent_bg = true
	svp.own_world_3d = true
	svpc.add_child(svp)

	var cam := Camera3D.new()
	cam.fov = 30.0
	var cam_pos := Vector3(0.0, 3.0, 10.0)
	var cam_target := Vector3(0.0, 2.8, 0.0)
	cam.transform = Transform3D(Basis.looking_at(cam_target - cam_pos, Vector3.UP), cam_pos)
	svp.add_child(cam)

	var dr_light := DirectionalLight3D.new()
	dr_light.transform = Transform3D(Basis.looking_at(Vector3(0, 3.0, 0) - Vector3(3.0, 8.0, 5.0), Vector3.UP), Vector3(3.0, 8.0, 5.0))
	svp.add_child(dr_light)

	var player_res = load("res://scenes/player/player.tscn")
	if player_res:
		var p_avatar = player_res.instantiate()
		p_avatar.set("is_ui_preview", true)
		p_avatar.set("use_local_avatar_fallback", false)
		p_avatar.set("render_avatar_visual_decals", true)
		p_avatar.set("render_avatar_clothing_decals", true)
		p_avatar.unique_name_in_owner = true
		p_avatar.name = "PreviewPlayer"
		if p_avatar.get_node_or_null("Visuals/NameLabel"):
			p_avatar.get_node("Visuals/NameLabel").visible = false
		svp.add_child(p_avatar)
		preview_player = p_avatar

	# === RIGHT: Controls ===
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 20)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right_col)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = "Avatar Customizer"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	right_col.add_child(title_lbl)

	# --- Body Part Buttons ---
	var part_label := Label.new()
	part_label.text = "Select Body Part"
	part_label.add_theme_font_size_override("font_size", 14)
	part_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	right_col.add_child(part_label)

	var part_grid := GridContainer.new()
	part_grid.columns = 3
	part_grid.add_theme_constant_override("h_separation", 8)
	part_grid.add_theme_constant_override("v_separation", 8)
	right_col.add_child(part_grid)

	var body_parts: Array = [
		["Head", "head"], ["Torso", "torso"],
		["Left Arm", "left_arm"], ["Right Arm", "right_arm"],
		["Left Leg", "left_leg"], ["Right Leg", "right_leg"]
	]
	var part_buttons_map: Dictionary = {}
	for bp in body_parts:
		var bp_btn := Button.new()
		bp_btn.text = bp[0]
		bp_btn.name = "Btn" + bp[0].replace(" ", "")
		bp_btn.unique_name_in_owner = true
		bp_btn.custom_minimum_size = Vector2(110, 36)
		bp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var part_name: String = bp[1]
		bp_btn.pressed.connect(func(): _select_part(part_name))
		part_grid.add_child(bp_btn)
		part_buttons_map[part_name] = bp_btn

	# Assign onready references (they're set in the header as @onready but won't resolve for programmatic nodes)
	btn_head = part_buttons_map.get("head", btn_head)
	btn_torso = part_buttons_map.get("torso", btn_torso)
	btn_left_arm = part_buttons_map.get("left_arm", btn_left_arm)
	btn_right_arm = part_buttons_map.get("right_arm", btn_right_arm)
	btn_left_leg = part_buttons_map.get("left_leg", btn_left_leg)
	btn_right_leg = part_buttons_map.get("right_leg", btn_right_leg)

	# --- Color Palette ---
	var color_label := Label.new()
	color_label.text = "Select Color"
	color_label.add_theme_font_size_override("font_size", 14)
	color_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	right_col.add_child(color_label)

	var color_grid := GridContainer.new()
	color_grid.name = "ColorGrid"
	color_grid.columns = 6
	color_grid.add_theme_constant_override("h_separation", 6)
	color_grid.add_theme_constant_override("v_separation", 6)
	right_col.add_child(color_grid)

	_rebuild_color_grid(color_grid)
		
	# Call highlight at the very end to force the grey buttons to update to the avatar colors immediately.
	call_deferred("_highlight_body_part_buttons")

func _refresh_friends_view(force_refresh: bool = false) -> void:
	var friends_view: Control = null
	if main_tabs != null:
		friends_view = main_tabs.get_node_or_null("FriendsView") as Control
	if friends_view == null:
		return
	if _friends_view_refresh_in_flight:
		return
	var now_msec := Time.get_ticks_msec()
	if (
		not force_refresh
		and bool(friends_view.get_meta("friends_view_ready", false))
		and now_msec - _friends_view_last_refresh_msec < FRIENDS_VIEW_REFRESH_TTL_MS
	):
		return
	var fb = load("res://scripts/lobby/friends_builder.gd")
	if fb:
		_friends_view_refresh_in_flight = true
		_friends_view_last_refresh_msec = now_msec
		fb.build(self, force_refresh)

func _on_friends_view_refresh_finished(success: bool = true) -> void:
	_friends_view_refresh_in_flight = false
	if success:
		_friends_view_last_refresh_msec = Time.get_ticks_msec()

func _refresh_games_view() -> void:
	var gb = load("res://scripts/lobby/games_builder.gd")
	if gb:
		gb.build(self)

func _create_dashboard_panel(parent: Node, title_text: String, subtitle_text: String, min_height: float = 220.0, action_text: String = "Refresh", action_callback: Callable = Callable()) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2.ZERO if title_text != "Friends" else Vector2(0, 164)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color.WHITE if title_text == "Friends" else Color.TRANSPARENT
	band_style.border_width_top = 0
	band_style.border_width_bottom = 0
	band_style.border_color = Color(0.87, 0.875, 0.89, 1)
	panel.add_theme_stylebox_override("panel", band_style)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	if not action_text.strip_edges().is_empty():
		var action_btn := Button.new()
		action_btn.text = action_text
		action_btn.flat = false
		action_btn.set_meta("classic_flat", true)
		var action_style := StyleBoxFlat.new()
		action_style.bg_color = Color("#00a2e8")
		action_style.content_margin_left = 14
		action_style.content_margin_right = 14
		action_style.content_margin_top = 4
		action_style.content_margin_bottom = 4
		action_btn.add_theme_stylebox_override("normal", action_style)
		var hover_style := action_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color("#008fce")
		action_btn.add_theme_stylebox_override("hover", hover_style)
		action_btn.add_theme_stylebox_override("pressed", hover_style)
		action_btn.focus_mode = Control.FOCUS_NONE
		action_btn.add_theme_color_override("font_color", Color.WHITE)
		action_btn.add_theme_font_size_override("font_size", 13)
		if action_callback.is_valid():
			action_btn.pressed.connect(action_callback)
		else:
			action_btn.pressed.connect(func(): _schedule_home_dashboard_refresh(true))
		header.add_child(action_btn)

	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.hide()
	title.tooltip_text = subtitle_text
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var status_label := Label.new()
	status_label.text = "Loading..."
	status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	status_label.add_theme_font_size_override("font_size", 12)
	root.add_child(status_label)

	return {"panel": panel, "content": root, "status_label": status_label, "title_label": title, "subtitle_label": subtitle}

func _open_home_see_all_friends() -> void:
	_switch_tab(Tab.FRIENDS)

func _open_home_see_all_games() -> void:
	_switch_tab(Tab.GAMES)

func _open_creation_hub() -> void:
	_switch_tab(Tab.DEVELOP)
	_show_develop_hub_page()

func _show_develop_hub_page() -> void:
	_clear_studio_overlay()
	var hub := CREATION_HUB_SCENE.instantiate() as Control
	if hub == null:
		push_error("[Lobby] Failed to instantiate Creation Hub.")
		return
	_studio_overlay = Control.new()
	_studio_overlay.name = "CreatorHubFullscreenOverlay"
	_studio_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_studio_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_studio_overlay.z_index = 500
	add_child(_studio_overlay)
	hub.name = "CreationHub"
	hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_studio_overlay.add_child(hub)
	if hub.has_signal("create_game_requested"):
		hub.connect("create_game_requested", Callable(self, "_open_create_game_from_hub"))
	if hub.has_signal("create_model_requested"):
		hub.connect("create_model_requested", Callable(self, "_open_model_editor_page"))
	if hub.has_signal("create_avatar_item_requested"):
		hub.connect("create_avatar_item_requested", Callable(self, "_show_avatar_item_creator_page"))
	if hub.has_signal("catalog_requested"):
		hub.connect("catalog_requested", Callable(self, "_open_creation_catalog_from_hub"))
	if hub.has_signal("legacy_editor_requested"):
		hub.connect("legacy_editor_requested", Callable(self, "_open_old_place_editor_direct"))
	if hub.has_signal("home_requested"):
		hub.connect("home_requested", Callable(self, "_open_home_from_develop_hub"))

func _prepare_develop_page() -> Control:
	var develop_view := _get_develop_view()
	if develop_view == null:
		return null
	if develop_view is ScrollContainer:
		var develop_scroll := develop_view as ScrollContainer
		develop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		develop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		develop_scroll.follow_focus = false
		var vbar := develop_scroll.get_v_scroll_bar()
		if vbar != null:
			vbar.modulate = Color(1, 1, 1, 0.0)
			vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in develop_view.get_children():
		develop_view.remove_child(child)
		child.queue_free()
	return develop_view

func _prepare_creator_fullscreen_page() -> VBoxContainer:
	_clear_studio_overlay()
	_studio_overlay = Control.new()
	_studio_overlay.name = "CreatorPageFullscreenOverlay"
	_studio_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_studio_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_studio_overlay.z_index = 500
	add_child(_studio_overlay)

	var background := ColorRect.new()
	background.color = Color(0.038, 0.043, 0.055, 1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_studio_overlay.add_child(background)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	_studio_overlay.add_child(scroll)

	var root := _create_creator_develop_root(scroll)
	root.set_meta("creator_page_generation", _creator_page_generation)
	return root

func _get_develop_view() -> Control:
	if main_tabs == null:
		return null
	return main_tabs.get_node_or_null("DevelopView") as Control

func _open_create_game_from_hub() -> void:
	_clear_studio_overlay()
	_open_create_game_choice_dialog()

func _open_create_game_choice_dialog() -> void:
	_show_template_picker_page()

func _open_old_place_editor_direct() -> void:
	_show_template_picker_page("res://scenes/place_editor/legacy_studio.tscn")

func _open_creation_catalog_from_hub() -> void:
	_clear_studio_overlay()
	_show_my_creations_page()

func _open_model_editor_page(source_path: String = "") -> void:
	_clear_studio_overlay()
	var editor := MODEL_EDITOR_SCENE.instantiate() as Control
	if editor == null:
		push_error("[Lobby] Failed to instantiate Model Editor.")
		return
	_studio_overlay = Control.new()
	_studio_overlay.name = "StudioFullscreenOverlay"
	_studio_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_studio_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_studio_overlay.z_index = 500
	add_child(_studio_overlay)
	editor.name = "ModelEditor"
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_studio_overlay.add_child(editor)
	if not source_path.strip_edges().is_empty() and editor.has_method("open_source_model"):
		editor.call("open_source_model", source_path)
	if editor.has_signal("back_requested"):
		editor.connect("back_requested", Callable(self, "_close_studio_overlay_and_show_hub"))
	if editor.has_signal("save_requested"):
		editor.connect("save_requested", Callable(self, "_on_model_editor_save_requested"))
	if editor.has_signal("publish_requested"):
		editor.connect("publish_requested", Callable(self, "_on_model_editor_publish_requested"))

func _clear_studio_overlay() -> void:
	_creator_page_generation += 1
	if _studio_overlay != null and is_instance_valid(_studio_overlay):
		_studio_overlay.queue_free()
	_studio_overlay = null

func _close_studio_overlay_and_show_hub() -> void:
	_clear_studio_overlay()
	_show_develop_hub_page()

func _on_model_editor_save_requested(model_data: Dictionary) -> void:
	var draft_root := _get_model_drafts_root_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(draft_root))
	var draft_path := _find_matching_model_draft_path(model_data)
	var draft_id := str(model_data.get("draft_id", "")).strip_edges()
	if draft_path.is_empty():
		if draft_id.is_empty():
			draft_id = "model_%d" % Time.get_ticks_msec()
		draft_path = draft_root.path_join(draft_id + ".json")
	elif draft_id.is_empty():
		draft_id = draft_path.get_file().get_basename()
	var payload := model_data.duplicate(true)
	payload["draft_id"] = draft_id
	payload["owner_user_id"] = UserSession.user_id
	payload["owner_username"] = UserSession.username
	var cloud_model_id := str(payload.get("cloud_model_id", "")).strip_edges()
	payload["local_only"] = cloud_model_id.is_empty()
	payload["publish_state"] = "draft" if cloud_model_id.is_empty() else "published"
	var file := FileAccess.open(draft_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Lobby] Failed to save model draft to %s" % draft_path)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("[Lobby] Model saved to %s with %d parts." % [draft_path, int((payload.get("parts", []) as Array).size())])

func _on_model_editor_publish_requested(model_data: Dictionary) -> void:
	if _model_publish_dialog != null and is_instance_valid(_model_publish_dialog):
		_model_publish_dialog.queue_free()
	_model_publish_dialog = ConfirmationDialog.new()
	_model_publish_dialog.title = "Publish Model"
	_model_publish_dialog.ok_button_text = "Publish"
	_model_publish_dialog.cancel_button_text = "Cancel"
	add_child(_model_publish_dialog)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(440, 260)
	root.add_theme_constant_override("separation", 10)
	_model_publish_dialog.add_child(root)
	var name_edit := LineEdit.new()
	name_edit.name = "NameEdit"
	var source_path: String = str(model_data.get("source_model_path", "")).strip_edges()
	name_edit.text = source_path.get_file().get_basename() if not source_path.is_empty() else "My Model"
	name_edit.placeholder_text = "Model name"
	root.add_child(name_edit)
	var desc_edit := TextEdit.new()
	desc_edit.name = "DescriptionEdit"
	desc_edit.custom_minimum_size = Vector2(0, 96)
	desc_edit.placeholder_text = "Description"
	root.add_child(desc_edit)
	var visibility := OptionButton.new()
	visibility.name = "VisibilityOption"
	visibility.add_item("Public")
	visibility.add_item("Private")
	root.add_child(visibility)
	var hint := Label.new()
	hint.text = "Public models appear in Toolbox and global marketplace. The editor will capture the preview image automatically."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42))
	root.add_child(hint)
	var publish_now_btn := Button.new()
	publish_now_btn.text = "Publish Model"
	publish_now_btn.custom_minimum_size = Vector2(0, 42)
	publish_now_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	publish_now_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.10, 0.56, 0.92, 1.0)))
	publish_now_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.08, 0.48, 0.82, 1.0)))
	publish_now_btn.add_theme_color_override("font_color", Color.WHITE)
	publish_now_btn.pressed.connect(func() -> void:
		publish_now_btn.disabled = true
		publish_now_btn.text = "Publishing..."
		var published: bool = await _publish_model_from_dialog(_model_publish_dialog, model_data)
		if not published and is_instance_valid(publish_now_btn):
			publish_now_btn.disabled = false
			publish_now_btn.text = "Publish Model"
	)
	root.add_child(publish_now_btn)
	_model_publish_dialog.popup_centered(Vector2i(560, 340))

func _publish_model_from_dialog(dialog: ConfirmationDialog, model_data: Dictionary) -> bool:
	if dialog == null or not is_instance_valid(dialog):
		return false
	var model_parts: Array = _avatar_item_extract_parts_from_model_data(model_data)
	if model_parts.is_empty():
		push_warning("[Lobby] Model publish rejected: the model has no serializable parts.")
		return false
	model_data["parts"] = model_parts
	var name_edit := dialog.find_child("NameEdit", true, false) as LineEdit
	var desc_edit := dialog.find_child("DescriptionEdit", true, false) as TextEdit
	var visibility_option := dialog.find_child("VisibilityOption", true, false) as OptionButton
	var model_name := name_edit.text.strip_edges() if name_edit != null else "My Model"
	if model_name.is_empty():
		model_name = "My Model"
	var source_path: String = str(model_data.get("canonical_source_model_path", "")).strip_edges()
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		source_path = str(model_data.get("source_model_path", "")).strip_edges()
	var model_object_id := "model_%d_%s" % [
		Time.get_ticks_msec(),
		str(UserSession.user_id).md5_text().substr(0, 8)
	]
	var metadata: Dictionary = {
		"id": model_object_id,
		"description": desc_edit.text.strip_edges() if desc_edit != null else "",
		"visibility": "private" if visibility_option != null and visibility_option.selected == 1 else "public",
		"asset_type": "model",
		"source_file_name": source_path.get_file() if not source_path.is_empty() else ""
	}
	if not source_path.is_empty() and FileAccess.file_exists(source_path):
		var upload_result: Dictionary = await CloudAPI.upload_model_asset_file(model_object_id, source_path.get_file(), source_path, _guess_model_source_mime(source_path))
		if bool(upload_result.get("ok", false)):
			var asset_info: Dictionary = upload_result.get("asset", {}) if upload_result.get("asset", {}) is Dictionary else {}
			var source_public_url := str(asset_info.get("public_url", "")).strip_edges()
			metadata["source_url"] = source_public_url
			metadata["source_file_url"] = source_public_url
			model_data["source_url"] = source_public_url
			model_data["source_file_url"] = source_public_url
		else:
			push_warning("[Lobby] Model source upload failed: %s" % str(upload_result.get("error", "Unknown error")))
			return false
	var auto_thumbnail := str(model_data.get("preview_thumbnail", "")).strip_edges()
	var thumbnail_path := str(model_data.get("preview_thumbnail_path", "")).strip_edges()
	if thumbnail_path.is_empty() and auto_thumbnail.begins_with("data:image/"):
		thumbnail_path = _write_inline_model_preview_to_cache(auto_thumbnail, model_object_id)
	if not thumbnail_path.is_empty() and FileAccess.file_exists(thumbnail_path):
		var thumbnail_upload: Dictionary = await CloudAPI.upload_model_asset_file(model_object_id, "thumbnail.png", thumbnail_path, "image/png")
		if bool(thumbnail_upload.get("ok", false)):
			var thumbnail_asset: Dictionary = thumbnail_upload.get("asset", {}) if thumbnail_upload.get("asset", {}) is Dictionary else {}
			var thumbnail_url := str(thumbnail_asset.get("public_url", "")).strip_edges()
			if not thumbnail_url.is_empty():
				metadata["thumbnail"] = thumbnail_url
				model_data["preview_thumbnail"] = thumbnail_url
				model_data["preview_thumbnail_path"] = thumbnail_path
	var result: Dictionary = await CloudAPI.publish_model_asset(model_data, model_name, metadata)
	if bool(result.get("ok", false)):
		var response_data: Variant = result.get("data", {})
		var saved_model: Dictionary = response_data if response_data is Dictionary else {}
		_on_model_editor_save_requested(_merge_model_publish_metadata(model_data, saved_model))
		print("[Lobby] Model published: %s" % model_name)
		if dialog != null and is_instance_valid(dialog):
			dialog.queue_free()
		_show_my_creations_page()
		return true
	else:
		push_warning("[Lobby] Model publish failed: %s" % str(result.get("error", "Unknown error")))
	return false

func _write_inline_model_preview_to_cache(data_uri: String, model_id: String) -> String:
	var separator_index := data_uri.find(",")
	if separator_index < 0:
		return ""
	var encoded := data_uri.substr(separator_index + 1).strip_edges()
	if encoded.is_empty():
		return ""
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.is_empty():
		return ""
	var image := Image.new()
	var load_error := image.load_png_from_buffer(bytes)
	if load_error != OK:
		load_error = image.load_jpg_from_buffer(bytes)
	if load_error != OK:
		load_error = image.load_webp_from_buffer(bytes)
	if load_error != OK or image.is_empty():
		return ""
	var preview_dir := "user://studio_drafts/model_previews"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(preview_dir))
	var preview_path := preview_dir.path_join("%s.png" % _sanitize_avatar_item_file_segment(model_id))
	if image.save_png(preview_path) != OK:
		return ""
	return preview_path

func _merge_model_publish_metadata(model_data: Dictionary, saved_model: Dictionary) -> Dictionary:
	var merged := model_data.duplicate(true)
	merged["cloud_model_id"] = str(saved_model.get("id", ""))
	merged["name"] = str(saved_model.get("name", model_data.get("name", ""))).strip_edges()
	merged["visibility"] = str(saved_model.get("visibility", "public"))
	for metadata_key in ["thumbnail", "source_url", "source_file_url", "source_file_name", "description"]:
		if saved_model.has(metadata_key):
			merged[metadata_key] = saved_model.get(metadata_key)
	var saved_metadata := _dictionary_from_jsonish_variant(saved_model.get("metadata", {}))
	for metadata_key in ["thumbnail", "source_url", "source_file_url", "source_file_name", "description"]:
		if saved_metadata.has(metadata_key):
			merged[metadata_key] = saved_metadata.get(metadata_key)
	merged["local_only"] = false
	merged["publish_state"] = "published"
	return merged

func _guess_model_source_mime(source_path: String) -> String:
	var extension := source_path.get_extension().to_lower()
	if extension == "glb":
		return "model/gltf-binary"
	if extension == "gltf":
		return "model/gltf+json"
	if extension == "obj":
		return "model/obj"
	if extension == "fbx":
		return "application/octet-stream"
	return "application/octet-stream"

func _guess_image_mime(image_path: String) -> String:
	var extension := image_path.get_extension().to_lower()
	if extension == "jpg" or extension == "jpeg":
		return "image/jpeg"
	if extension == "webp":
		return "image/webp"
	return "image/png"

func _browse_path_into_line_edit(target: LineEdit, filters: PackedStringArray) -> void:
	if target == null:
		return
	if _show_system_open_file_dialog("Choose file", filters, func(path: String) -> void:
		target.text = path
	):
		return
	var dialog := FileDialog.new()
	_configure_user_file_dialog(dialog, filters)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		target.text = path
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(760, 520))

func _configure_user_file_dialog(dialog: FileDialog, filters: PackedStringArray) -> void:
	if dialog == null:
		return
	dialog.use_native_dialog = true
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	if OS.has_feature("android"):
		_request_android_media_permissions()
		if DirAccess.dir_exists_absolute("/storage/emulated/0/Download"):
			dialog.current_dir = "/storage/emulated/0/Download"
		elif DirAccess.dir_exists_absolute("/storage/emulated/0"):
			dialog.current_dir = "/storage/emulated/0"

func _show_system_open_file_dialog(title: String, filters: PackedStringArray, selected_callback: Callable) -> bool:
	if not selected_callback.is_valid():
		return false
	if OS.has_feature("android"):
		_request_android_media_permissions()
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
		var selected_path := str(selected_paths[0]).strip_edges()
		if not selected_path.is_empty():
			selected_callback.call(selected_path)
	var error: Error = DisplayServer.file_dialog_show(title, start_dir, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, callback)
	return error == OK

func _get_model_drafts_root_path() -> String:
	var owner_key := UserSession.user_id.strip_edges().replace("-", "")
	if owner_key.is_empty():
		owner_key = UserSession.username.strip_edges().to_lower().replace(" ", "_")
	if owner_key.is_empty():
		owner_key = "guest"
	return "user://studio_drafts/models".path_join(owner_key)

func _open_home_from_develop_hub() -> void:
	_clear_studio_overlay()
	_switch_tab(Tab.HOME)

func _show_develop_info_page(title_text: String, body_text: String, bullet_points: Array[String]) -> void:
	var develop_view := _prepare_develop_page()
	if develop_view == null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	develop_view.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	root.add_child(_create_develop_page_header(title_text, body_text, true))
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var panel_margin := MarginContainer.new()
	panel_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_margin.add_theme_constant_override("margin_left", 22)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_right", 22)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(panel_margin)
	panel_margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14))
	box.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.28, 0.29, 0.32))
	box.add_child(body)
	for point in bullet_points:
		var point_label := Label.new()
		point_label.text = "- " + point
		point_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		point_label.add_theme_font_size_override("font_size", 13)
		point_label.add_theme_color_override("font_color", Color(0.34, 0.34, 0.34))
		box.add_child(point_label)

func _show_template_picker_page(editor_scene_path: String = "res://scenes/place_editor/studio.tscn") -> void:
	var root := _prepare_creator_fullscreen_page()
	if root == null:
		return
	var old_editor_mode := editor_scene_path == "res://scenes/place_editor/legacy_studio.tscn"
	root.add_child(_create_develop_page_header(
		"Legacy Templates" if old_editor_mode else "Choose a Template",
		"Compatibility projects for the retired editor." if old_editor_mode else "Start with a complete world foundation, then build, test and publish from Bobux Studio.",
		true,
		true
	))

	var intro := PanelContainer.new()
	intro.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.075, 0.105, 0.15, 1), Color(0.13, 0.42, 0.72, 1), 7))
	root.add_child(intro)
	var intro_margin := MarginContainer.new()
	intro_margin.add_theme_constant_override("margin_left", 18)
	intro_margin.add_theme_constant_override("margin_top", 13)
	intro_margin.add_theme_constant_override("margin_right", 18)
	intro_margin.add_theme_constant_override("margin_bottom", 13)
	intro.add_child(intro_margin)
	var intro_label := Label.new()
	intro_label.text = "Every template opens in the new editor with Workspace, Lighting, StarterGui, scripts, terrain and publishing ready." if not old_editor_mode else "Legacy mode is kept only for opening projects that still depend on the retired editor."
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 1))
	intro_label.add_theme_font_size_override("font_size", 13)
	intro_margin.add_child(intro_label)

	var grid := GridContainer.new()
	var available_width := get_viewport_rect().size.x
	grid.columns = 1 if available_width < 760.0 else (2 if available_width < 1180.0 else 3)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	for template_info in _get_creation_templates():
		grid.add_child(_create_template_picker_card(template_info, editor_scene_path))

func _show_my_creations_page() -> void:
	var root := _prepare_creator_fullscreen_page()
	if root == null:
		return
	var page_generation := _creator_page_generation
	root.add_child(_create_develop_page_header("My Creations", "Manage experiences and reusable assets saved to your account and Bobux Cloud.", true, true))

	var my_creations_response: Dictionary = await CloudAPI.fetch_my_creations() if CloudAPI != null and CloudAPI.is_configured() and CloudAPI.has_method("fetch_my_creations") else {"ok": false, "data": {}}
	var my_creations_payload: Dictionary = my_creations_response.get("data", {}) if my_creations_response.get("data", {}) is Dictionary else {}
	var owner_avatar_items_response: Dictionary = {"ok": false, "data": []}
	var owner_avatar_items_source: Array = []
	if CloudAPI != null and CloudAPI.is_configured() and CloudAPI.has_method("fetch_avatar_marketplace_items"):
		owner_avatar_items_response = await CloudAPI.fetch_avatar_marketplace_items(240, true, true)
		if bool(owner_avatar_items_response.get("ok", false)):
			owner_avatar_items_source = _extract_response_array(owner_avatar_items_response)
	if not is_instance_valid(root) or page_generation != _creator_page_generation:
		return

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	var studio_btn := Button.new()
	studio_btn.text = "Open Bobux Studio"
	studio_btn.custom_minimum_size = Vector2(190, 38)
	_style_creator_button(studio_btn, true)
	studio_btn.pressed.connect(_show_template_picker_page)
	actions.add_child(studio_btn)
	var hub_btn := Button.new()
	hub_btn.text = "Creator Dashboard"
	hub_btn.custom_minimum_size = Vector2(160, 38)
	_style_creator_button(hub_btn)
	hub_btn.pressed.connect(_show_develop_hub_page)
	actions.add_child(hub_btn)

	var catalog_tabs := TabContainer.new()
	catalog_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_tabs.custom_minimum_size = Vector2(0, 470)
	catalog_tabs.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.075, 0.082, 0.10, 1), Color(0.20, 0.22, 0.27, 1), 6))
	catalog_tabs.add_theme_stylebox_override("tab_selected", _make_creator_panel_style(Color(0.12, 0.15, 0.20, 1), Color(0.12, 0.54, 0.92, 1), 5))
	catalog_tabs.add_theme_stylebox_override("tab_unselected", _make_creator_panel_style(Color(0.085, 0.09, 0.11, 1), Color(0.18, 0.19, 0.22, 1), 5))
	catalog_tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	catalog_tabs.add_theme_color_override("font_unselected_color", Color(0.66, 0.69, 0.74, 1))
	root.add_child(catalog_tabs)

	var places_tab := _create_catalog_tab_panel("Places")
	catalog_tabs.add_child(places_tab)
	var grid := GridContainer.new()
	grid.columns = 1 if get_viewport_rect().size.x < 760.0 else (2 if get_viewport_rect().size.x < 1180.0 else 3)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	places_tab.get_node("Margin").add_child(grid)

	var visible_count := 0
	for cloud_map_variant in my_creations_payload.get("maps", []):
		if not (cloud_map_variant is Dictionary):
			continue
		var cloud_map: Dictionary = cloud_map_variant
		if _should_hide_discover_entry(_make_game_entry_from_cloud_map(cloud_map)):
			continue
		grid.add_child(_create_cloud_place_catalog_card(cloud_map))
		visible_count += 1

	if visible_count == 0:
		if bool(my_creations_response.get("ok", false)):
			_add_placeholder_label(grid, "You have not published any places yet.")
		else:
			_add_placeholder_label(grid, "Cloud places could not load: %s" % str(my_creations_response.get("error", "Unknown error")))

	var models_tab := _create_catalog_tab_panel("Models")
	catalog_tabs.add_child(models_tab)
	var models_list := GridContainer.new()
	models_list.columns = 1 if DisplayServer.is_touchscreen_available() else 3
	models_list.add_theme_constant_override("h_separation", 14)
	models_list.add_theme_constant_override("v_separation", 14)
	models_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	models_tab.get_node("Margin").add_child(models_list)
	var model_count := 0
	var seen_model_ids: Dictionary = {}
	for model_entry in _load_local_model_draft_entries():
		var local_identity := _model_entry_identity(model_entry)
		if not local_identity.is_empty():
			seen_model_ids[local_identity] = true
		models_list.add_child(_create_model_draft_row(model_entry))
		model_count += 1
	var cloud_models_source: Array = my_creations_payload.get("models", []) if my_creations_payload.get("models", []) is Array else []
	if bool(my_creations_response.get("ok", false)):
		for model_variant in cloud_models_source:
			if not (model_variant is Dictionary):
				continue
			var model_entry: Dictionary = (model_variant as Dictionary).duplicate(true)
			model_entry["publish_state"] = "cloud"
			var cloud_identity := _model_entry_identity(model_entry)
			if not cloud_identity.is_empty() and seen_model_ids.has(cloud_identity):
				continue
			if not cloud_identity.is_empty():
				seen_model_ids[cloud_identity] = true
			models_list.add_child(_create_model_draft_row(model_entry))
			model_count += 1
	elif CloudAPI.is_configured():
		_add_placeholder_label(models_list, "Cloud models could not load: %s" % str(my_creations_response.get("error", "Unknown error")))
	if model_count == 0:
		_add_placeholder_label(models_list, "No model drafts yet. Open Bobux Studio and use Model or Import.")

	var avatar_items_tab := _create_catalog_tab_panel("Avatar Items")
	catalog_tabs.add_child(avatar_items_tab)
	var avatar_box := VBoxContainer.new()
	avatar_box.add_theme_constant_override("separation", 10)
	avatar_items_tab.get_node("Margin").add_child(avatar_box)
	var avatar_grid := GridContainer.new()
	avatar_grid.columns = 1 if get_viewport_rect().size.x < 620.0 else (2 if get_viewport_rect().size.x < 920.0 else 4)
	avatar_grid.add_theme_constant_override("h_separation", 14)
	avatar_grid.add_theme_constant_override("v_separation", 14)
	avatar_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_box.add_child(avatar_grid)
	var avatar_item_count := 0
	var avatar_items_source: Array = my_creations_payload.get("avatar_items", []) if my_creations_payload.get("avatar_items", []) is Array else []
	var avatar_item_seen_ids: Dictionary = {}
	if bool(my_creations_response.get("ok", false)):
		for item_variant in avatar_items_source:
			if not (item_variant is Dictionary):
				continue
			var item_entry := item_variant as Dictionary
			var item_id := str(item_entry.get("id", item_entry.get("item_id", ""))).strip_edges()
			if not item_id.is_empty():
				avatar_item_seen_ids[item_id] = true
			avatar_grid.add_child(_create_avatar_item_catalog_card(item_entry))
			avatar_item_count += 1
	elif CloudAPI.is_configured():
		_add_placeholder_label(avatar_grid, "Cloud avatar items could not load: %s" % str(my_creations_response.get("error", "Unknown error")))
	if bool(owner_avatar_items_response.get("ok", false)):
		for owner_item_variant in owner_avatar_items_source:
			if not (owner_item_variant is Dictionary):
				continue
			var owner_item_entry := owner_item_variant as Dictionary
			var owner_item_id := str(owner_item_entry.get("id", owner_item_entry.get("item_id", ""))).strip_edges()
			if not owner_item_id.is_empty() and bool(avatar_item_seen_ids.get(owner_item_id, false)):
				continue
			avatar_grid.add_child(_create_avatar_item_catalog_card(owner_item_entry))
			if not owner_item_id.is_empty():
				avatar_item_seen_ids[owner_item_id] = true
			avatar_item_count += 1
	for local_item in _get_session_created_avatar_item_payloads():
		if not (local_item is Dictionary):
			continue
		var local_entry := local_item as Dictionary
		var local_id := str(local_entry.get("id", local_entry.get("item_id", ""))).strip_edges()
		if local_id.is_empty() or bool(avatar_item_seen_ids.get(local_id, false)):
			continue
		avatar_grid.add_child(_create_avatar_item_catalog_card(local_entry))
		avatar_item_seen_ids[local_id] = true
		avatar_item_count += 1
	if avatar_item_count == 0:
		_add_placeholder_label(avatar_grid, "No avatar items yet. Use a published model to create a wearable item in the next editor step.")

func _show_avatar_item_creator_page() -> void:
	_clear_studio_overlay()
	var develop_view := _prepare_develop_page()
	if develop_view == null:
		return
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	develop_view.add_child(root)
	root.add_child(_create_develop_page_header("Создать предмет аватара", "1. Выберите модель или одежду   ·   2. Настройте вид   ·   3. Укажите цену и опубликуйте", true))
	var compact_creator := get_viewport_rect().size.x < 1000
	var content: BoxContainer = VBoxContainer.new() if compact_creator else HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	root.add_child(content)

	var preview_panel := Panel.new()
	preview_panel.custom_minimum_size = Vector2(300 if compact_creator else 390, 440 if compact_creator else 550)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	content.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	preview_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_margin.add_theme_constant_override("margin_left", 18)
	preview_margin.add_theme_constant_override("margin_right", 18)
	preview_margin.add_theme_constant_override("margin_top", 18)
	preview_margin.add_theme_constant_override("margin_bottom", 18)
	preview_panel.add_child(preview_margin)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 10)
	preview_margin.add_child(preview_box)
	var preview_title := Label.new()
	preview_title.text = "Примерка"
	preview_title.add_theme_font_size_override("font_size", 22)
	preview_title.add_theme_color_override("font_color", Color(0.14, 0.14, 0.14))
	preview_box.add_child(preview_title)
	var sub_frame := Control.new()
	sub_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	sub_frame.mouse_force_pass_scroll_events = false
	sub_frame.clip_contents = true
	sub_frame.custom_minimum_size = Vector2(280 if compact_creator else 350, 340 if compact_creator else 430)
	sub_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_box.add_child(sub_frame)
	var sub_container := SubViewportContainer.new()
	sub_container.name = "AvatarItemPreviewViewportContainer"
	sub_container.stretch = true
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_container.mouse_force_pass_scroll_events = false
	sub_frame.add_child(sub_container)
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sub := SubViewport.new()
	sub.name = "AvatarItemPreviewViewport"
	sub.own_world_3d = true
	sub.transparent_bg = true
	sub.gui_disable_input = true
	sub.size = Vector2i(1536, 1536)
	sub_container.add_child(sub)
	var input_overlay: Control = AVATAR_PREVIEW_INPUT_OVERLAY_SCRIPT.new() as Control
	input_overlay.name = "AvatarItemPreviewInputOverlay"
	input_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	input_overlay.mouse_force_pass_scroll_events = false
	input_overlay.focus_mode = Control.FOCUS_ALL
	input_overlay.mouse_default_cursor_shape = Control.CURSOR_DRAG
	input_overlay.z_index = 100
	input_overlay.custom_minimum_size = sub_frame.custom_minimum_size
	input_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_frame.add_child(input_overlay)
	input_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var world_root := Node3D.new()
	sub.add_child(world_root)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, 35, 0)
	world_root.add_child(light)
	var preview_orbit_root := Node3D.new()
	preview_orbit_root.name = "AvatarItemPreviewOrbitRoot"
	world_root.add_child(preview_orbit_root)
	var player_res: PackedScene = load("res://scenes/player/player.tscn")
	var player_preview: Node = null
	if player_res != null:
		player_preview = player_res.instantiate()
		player_preview.name = "AvatarItemPreviewPlayer"
		player_preview.set("is_ui_preview", true)
		player_preview.set("use_local_avatar_fallback", false)
		player_preview.set("render_avatar_visual_decals", true)
		player_preview.set("render_avatar_clothing_decals", true)
		player_preview.set("equipped_avatar_items", [])
		player_preview.set("head_color", Color(0.96, 0.8, 0.2))
		player_preview.set("torso_color", Color(0.05, 0.4, 0.7))
		player_preview.set("left_arm_color", Color(0.96, 0.8, 0.2))
		player_preview.set("right_arm_color", Color(0.96, 0.8, 0.2))
		player_preview.set("left_leg_color", Color(0.65, 0.8, 0.2))
		player_preview.set("right_leg_color", Color(0.65, 0.8, 0.2))
		player_preview.set("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)
		player_preview.set("chest_badge_texture_path", "")
		player_preview.set("shirt_texture_path", "")
		player_preview.set("pants_texture_path", "")
		
		if player_preview is Node3D:
			(player_preview as Node3D).position = Vector3(0, 0, 0)
		preview_orbit_root.add_child(player_preview)
		if player_preview.has_method("_apply_avatar_visuals_if_needed"):
			player_preview.call_deferred("_apply_avatar_visuals_if_needed")
	var attachment_root := Node3D.new()
	attachment_root.name = "AttachmentPreview"
	var attachment_parent: Node3D = preview_orbit_root
	if player_preview != null:
		var preview_visuals := player_preview.get_node_or_null("Visuals") as Node3D
		if preview_visuals != null:
			attachment_parent = preview_visuals
	attachment_parent.add_child(attachment_root)
	var cam := Camera3D.new()
	cam.name = "AvatarItemPreviewCamera"
	cam.fov = 30.0
	cam.current = true
	cam.position = Vector3(0.0, 2.45, 8.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 2.18, 0.0) - cam.position, Vector3.UP), cam.position)
	sub.add_child(cam)
	var camera_state := {
		"yaw": 0.0,
		"pitch": 0.02,
		"distance": 11.5,
		"dragging": false
	}
	var creation_state := {
		"mode": "model",
		"clothing": {}
	}
	var update_preview_camera := func() -> void:
		var target := Vector3(0.0, 2.18, 0.0)
		var pitch := float(camera_state["pitch"])
		var distance := float(camera_state["distance"])
		var offset := Vector3(
			0.0,
			sin(pitch),
			cos(pitch)
		) * distance
		cam.position = target + offset
		cam.look_at(target, Vector3.UP)
	update_preview_camera.call()
	
	# Keep parents pass-through; IGNORE can prevent the overlay from receiving drag input.
	preview_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_box.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var pos_row: HBoxContainer = null
	var rot_row: HBoxContainer = null
	var scale_row: HBoxContainer = null
	var sync_attachment_preview: Callable
	var active_drag_gizmo := ""

	var handle_avatar_item_preview_input := func(event: InputEvent, input_receiver: Control = null) -> void:
		if sub == null or not is_instance_valid(sub):
			return
		var receiver: Control = input_receiver if input_receiver != null else input_overlay
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index == MOUSE_BUTTON_LEFT:
				if mouse_button.pressed:
					receiver.grab_focus()
					if sub.world_3d != null:
						var space_state := sub.world_3d.direct_space_state
						var mouse_pos: Vector2 = mouse_button.position
						var container_size: Vector2 = receiver.size
						var viewport_size := Vector2(sub.size)
						if container_size.x > 0.0 and container_size.y > 0.0:
							mouse_pos = Vector2(
								clampf(mouse_pos.x, 0.0, container_size.x) * viewport_size.x / container_size.x,
								clampf(mouse_pos.y, 0.0, container_size.y) * viewport_size.y / container_size.y
							)
						var from := cam.project_ray_origin(mouse_pos)
						var to := from + cam.project_ray_normal(mouse_pos) * 100.0
						var query := PhysicsRayQueryParameters3D.create(from, to)
						query.collide_with_areas = true
						query.collide_with_bodies = false
						query.collision_mask = 1
						var result := space_state.intersect_ray(query)
						if not result.is_empty():
							var collider = result.get("collider")
							if collider is Area3D and collider.has_meta("is_gizmo"):
								active_drag_gizmo = collider.name
								camera_state["dragging"] = false
								receiver.accept_event()
								return
					camera_state["dragging"] = true
					receiver.accept_event()
				else:
					active_drag_gizmo = ""
					camera_state["dragging"] = false
					receiver.accept_event()
			elif mouse_button.button_index == MOUSE_BUTTON_RIGHT:
				camera_state["dragging"] = mouse_button.pressed
				receiver.accept_event()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
				camera_state["distance"] = maxf(6.0, float(camera_state["distance"]) - 0.35)
				update_preview_camera.call()
				receiver.accept_event()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
				camera_state["distance"] = minf(12.5, float(camera_state["distance"]) + 0.35)
				update_preview_camera.call()
				receiver.accept_event()
		elif event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			if not active_drag_gizmo.is_empty() and pos_row != null and scale_row != null:
				var delta_val := (motion.relative.x - motion.relative.y) * 0.012
				var pos_x = pos_row.get_node_or_null("X") as SpinBox
				var pos_y = pos_row.get_node_or_null("Y") as SpinBox
				var pos_z = pos_row.get_node_or_null("Z") as SpinBox
				var scale_x = scale_row.get_node_or_null("X") as SpinBox
				var scale_y = scale_row.get_node_or_null("Y") as SpinBox
				var scale_z = scale_row.get_node_or_null("Z") as SpinBox
				if pos_x != null and pos_y != null and pos_z != null and scale_x != null and scale_y != null and scale_z != null:
					if active_drag_gizmo == "GizmoX":
						pos_x.value += motion.relative.x * 0.015
					elif active_drag_gizmo == "GizmoY":
						pos_y.value -= motion.relative.y * 0.015
					elif active_drag_gizmo == "GizmoZ":
						pos_z.value += motion.relative.y * 0.015
					elif active_drag_gizmo == "GizmoScale":
						scale_x.value += delta_val
						scale_y.value += delta_val
						scale_z.value += delta_val
					if sync_attachment_preview.is_valid():
						sync_attachment_preview.call(0.0)
				receiver.accept_event()
			else:
				var button_dragging := bool(camera_state["dragging"]) or ((motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0) or ((motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0)
				if not button_dragging:
					return
				preview_orbit_root.rotation.y -= motion.relative.x * 0.008
				camera_state["pitch"] = clampf(float(camera_state["pitch"]) - motion.relative.y * 0.006, -0.85, 0.65)
				update_preview_camera.call()
				receiver.accept_event()
	if input_overlay.has_method("set_input_handler"):
		input_overlay.call("set_input_handler", handle_avatar_item_preview_input)
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_container.mouse_force_pass_scroll_events = false
	sub_container.gui_input.connect(handle_avatar_item_preview_input.bind(sub_container))
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var orbit_controls := HBoxContainer.new()
	orbit_controls.add_theme_constant_override("separation", 8)
	preview_box.add_child(orbit_controls)
	var rotate_left_btn := Button.new()
	rotate_left_btn.text = "Rotate Left"
	rotate_left_btn.custom_minimum_size = Vector2(120, 32)
	rotate_left_btn.pressed.connect(func() -> void:
		preview_orbit_root.rotation.y += 0.35
		update_preview_camera.call()
	)
	orbit_controls.add_child(rotate_left_btn)
	var rotate_right_btn := Button.new()
	rotate_right_btn.text = "Rotate Right"
	rotate_right_btn.custom_minimum_size = Vector2(120, 32)
	rotate_right_btn.pressed.connect(func() -> void:
		preview_orbit_root.rotation.y -= 0.35
		update_preview_camera.call()
	)
	orbit_controls.add_child(rotate_right_btn)
	var reset_orbit_btn := Button.new()
	reset_orbit_btn.text = "Reset"
	reset_orbit_btn.custom_minimum_size = Vector2(84, 32)
	reset_orbit_btn.pressed.connect(func() -> void:
		camera_state["yaw"] = 0.0
		camera_state["pitch"] = 0.02
		camera_state["distance"] = 11.5
		preview_orbit_root.rotation = Vector3.ZERO
		update_preview_camera.call()
	)
	orbit_controls.add_child(reset_orbit_btn)

	var form_panel := PanelContainer.new()
	form_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	content.add_child(form_panel)
	var form_margin := MarginContainer.new()
	form_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	form_margin.add_theme_constant_override("margin_left", 18)
	form_margin.add_theme_constant_override("margin_right", 18)
	form_margin.add_theme_constant_override("margin_top", 18)
	form_margin.add_theme_constant_override("margin_bottom", 18)
	form_panel.add_child(form_margin)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	var form_scroll := ScrollContainer.new()
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.custom_minimum_size.y = 440 if compact_creator else 260
	var form_shell := VBoxContainer.new()
	form_shell.add_theme_constant_override("separation", 12)
	form_margin.add_child(form_shell)
	form_shell.add_child(form_scroll)
	var publication_box := VBoxContainer.new()
	publication_box.add_theme_constant_override("separation", 8)
	form_shell.add_child(publication_box)
	publication_box.add_child(HSeparator.new())
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(form)
	var models_response: Dictionary = await CloudAPI.fetch_marketplace_models(96, true, true)
	var model_entries: Array = []
	var seen_model_ids: Dictionary = {}
	if bool(models_response.get("ok", false)):
		for cloud_model_variant in _extract_response_array(models_response):
			if not (cloud_model_variant is Dictionary):
				continue
			var cloud_model := (cloud_model_variant as Dictionary).duplicate(true)
			var cloud_model_id := str(cloud_model.get("id", cloud_model.get("cloud_model_id", ""))).strip_edges()
			if not cloud_model_id.is_empty():
				seen_model_ids[cloud_model_id] = true
			model_entries.append(cloud_model)
	for local_model in _load_local_model_draft_entries():
		var local_model_id := str(local_model.get("cloud_model_id", local_model.get("id", ""))).strip_edges()
		if not local_model_id.is_empty() and bool(seen_model_ids.get(local_model_id, false)):
			continue
		model_entries.append(local_model)
		if not local_model_id.is_empty():
			seen_model_ids[local_model_id] = true
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Название предмета"
	name_edit.max_length = 80
	name_edit.custom_minimum_size.y = 40
	form.add_child(_avatar_creator_label("Название"))
	form.add_child(name_edit)
	
	var model_option := OptionButton.new()
	model_option.add_item("Select a model...")
	model_option.set_item_metadata(0, {})
	for entry_variant in model_entries:
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			model_option.add_item(str(entry.get("name", "Model")))
			model_option.set_item_metadata(model_option.get_item_count() - 1, entry)
	model_option.disabled = model_entries.is_empty()
	form.add_child(_avatar_creator_label("Модель из ваших работ"))
	model_option.custom_minimum_size.y = 38
	model_option.clip_text = true
	form.add_child(model_option)
	var slot_option: OptionButton = null
	
	var add_model_btn := Button.new()
	add_model_btn.text = "Добавить модель на персонажа"
	add_model_btn.custom_minimum_size = Vector2(0, 36)
	add_model_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_model_btn.disabled = model_option.disabled
	form.add_child(add_model_btn)
	var dev_shirt_btn: Button = null
	var dev_pants_btn: Button = null
	var reset_item_btn: Button = null
	var clear_attachment_preview := func() -> void:
		for child in attachment_root.get_children():
			attachment_root.remove_child(child)
			child.queue_free()
	var set_transform_rows_visible := func(is_visible: bool) -> void:
		for row in creation_state.get("transform_rows", []):
			if is_instance_valid(row): row.visible = is_visible
	var lock_creator_to_single_kind := func(kind: String) -> void:
		var clean_kind := kind.strip_edges().to_lower()
		var clothing_selected := clean_kind in ["shirt", "pants"]
		var model_selected := clean_kind == "model"
		if clothing_selected:
			model_option.disabled = true
			add_model_btn.disabled = true
			if slot_option != null:
				slot_option.disabled = true
			for child in attachment_root.get_children():
				attachment_root.remove_child(child)
				child.queue_free()
			if pos_row != null:
				pos_row.visible = false
			if rot_row != null:
				rot_row.visible = false
			if scale_row != null:
				scale_row.visible = false
		elif model_selected:
			if dev_shirt_btn != null:
				dev_shirt_btn.disabled = true
			if dev_pants_btn != null:
				dev_pants_btn.disabled = true
			if pos_row != null:
				pos_row.visible = true
			if rot_row != null:
				rot_row.visible = true
			if scale_row != null:
				scale_row.visible = true
		if reset_item_btn != null:
			reset_item_btn.disabled = false
	
	model_option.item_selected.connect(func(_index: int) -> void:
		var model_entry: Dictionary = model_option.get_item_metadata(model_option.selected) if model_option.get_item_metadata(model_option.selected) is Dictionary else {}
		if model_entry.is_empty():
			return
		creation_state["mode"] = "model"
		creation_state["clothing"] = {}
		if lock_creator_to_single_kind.is_valid():
			lock_creator_to_single_kind.call("model")
		await _rebuild_avatar_item_attachment_preview(attachment_root, model_entry)
		if sync_attachment_preview.is_valid():
			sync_attachment_preview.call(0.0)
	)
	slot_option = OptionButton.new()
	for slot_name in ["Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Back"]:
		slot_option.add_item(slot_name)
	form.add_child(_avatar_creator_label("Крепление на персонаже"))
	slot_option.custom_minimum_size.y = 38
	form.add_child(slot_option)
	slot_option.item_selected.connect(func(_index: int) -> void:
		if sync_attachment_preview.is_valid():
			sync_attachment_preview.call(0.0)
		else:
			attachment_root.position = _avatar_item_slot_position(slot_option.get_item_text(slot_option.selected))
	)
	var visibility := OptionButton.new()
	visibility.add_item("В каталоге — доступно другим игрокам")
	visibility.add_item("Черновик — видно только вам")
	form.add_child(_avatar_creator_label("Где показывать"))
	visibility.clip_text = true
	visibility.custom_minimum_size.y = 38
	form.add_child(visibility)

	# Outfit creator upload row
	var develop_upload_row := HFlowContainer.new()
	develop_upload_row.add_theme_constant_override("separation", 8)
	form.add_child(develop_upload_row)
	var clothing_status := Label.new()
	clothing_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clothing_status.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	clothing_status.add_theme_font_size_override("font_size", 13)
	var handle_clothing_imported := func(import_result: Dictionary) -> void:
		if not bool(import_result.get("ok", false)):
			clothing_status.text = "Template import failed: %s" % str(import_result.get("error", "Unknown error"))
			return
		var imported_kind := str(import_result.get("kind", "shirt")).strip_edges()
		creation_state["mode"] = imported_kind
		creation_state["clothing"] = import_result.duplicate(true)
		if lock_creator_to_single_kind.is_valid():
			lock_creator_to_single_kind.call(imported_kind)
		if dev_shirt_btn != null:
			dev_shirt_btn.disabled = true
		if dev_pants_btn != null:
			dev_pants_btn.disabled = true
		if name_edit.text.strip_edges().is_empty():
			name_edit.text = "Classic %s" % imported_kind.capitalize()
		clothing_status.text = "%s template ready. This page will publish only that clothing item." % imported_kind.capitalize()
	dev_shirt_btn = Button.new()
	dev_shirt_btn.text = "Загрузить футболку"
	dev_shirt_btn.custom_minimum_size = Vector2(130, 36)
	dev_shirt_btn.pressed.connect(func() -> void:
		_open_avatar_template_picker_from_develop("shirt", player_preview, handle_clothing_imported)
	)
	develop_upload_row.add_child(dev_shirt_btn)
	dev_pants_btn = Button.new()
	dev_pants_btn.text = "Загрузить штаны"
	dev_pants_btn.custom_minimum_size = Vector2(130, 36)
	dev_pants_btn.pressed.connect(func() -> void:
		_open_avatar_template_picker_from_develop("pants", player_preview, handle_clothing_imported)
	)
	develop_upload_row.add_child(dev_pants_btn)
	var dev_templates_btn := Button.new()
	dev_templates_btn.text = "Скачать шаблоны"
	dev_templates_btn.custom_minimum_size = Vector2(170, 36)
	dev_templates_btn.pressed.connect(func() -> void:
		_download_avatar_template_references()
	)
	develop_upload_row.add_child(dev_templates_btn)
	reset_item_btn = Button.new()
	reset_item_btn.text = "Начать заново"
	reset_item_btn.custom_minimum_size = Vector2(120, 36)
	reset_item_btn.disabled = true
	reset_item_btn.pressed.connect(_show_avatar_item_creator_page)
	develop_upload_row.add_child(reset_item_btn)
	form.add_child(clothing_status)

	var transform_header := Label.new()
	transform_header.text = "Точная настройка положения"
	transform_header.add_theme_font_size_override("font_size", 16)
	transform_header.add_theme_color_override("font_color", Color(0.16, 0.16, 0.16))
	form.add_child(transform_header)
	var transform_expand := CheckButton.new()
	transform_expand.text = "Показать координаты и масштаб"
	form.add_child(transform_expand)
	pos_row = _create_avatar_item_vector3_row("Position", Vector3.ZERO, Vector3(-4, -4, -4), Vector3(4, 6, 4), 0.05)
	form.add_child(pos_row)
	rot_row = _create_avatar_item_vector3_row("Rotation", Vector3.ZERO, Vector3(-180, -180, -180), Vector3(180, 180, 180), 1.0)
	form.add_child(rot_row)
	scale_row = _create_avatar_item_vector3_row("Scale", Vector3.ONE, Vector3(0.05, 0.05, 0.05), Vector3(8, 8, 8), 0.05)
	form.add_child(scale_row)
	creation_state["transform_rows"] = [pos_row, rot_row, scale_row]
	set_transform_rows_visible.call(false)
	transform_expand.toggled.connect(func(enabled: bool): set_transform_rows_visible.call(enabled and str(creation_state.get("mode", "model")) == "model"))
	sync_attachment_preview = func(_value: float = 0.0) -> void:
		var slot_pos := _avatar_item_slot_position(slot_option.get_item_text(slot_option.selected))
		attachment_root.position = slot_pos + _read_avatar_item_vector3_row(pos_row, Vector3.ZERO)
		attachment_root.rotation_degrees = _read_avatar_item_vector3_row(rot_row, Vector3.ZERO)
		attachment_root.scale = _read_avatar_item_vector3_row(scale_row, Vector3.ONE)
	add_model_btn.pressed.connect(func() -> void:
		if model_option.disabled:
			return
		var model_entry: Dictionary = model_option.get_item_metadata(model_option.selected) if model_option.get_item_metadata(model_option.selected) is Dictionary else {}
		if model_entry.is_empty():
			return
		creation_state["mode"] = "model"
		creation_state["clothing"] = {}
		if lock_creator_to_single_kind.is_valid():
			lock_creator_to_single_kind.call("model")
		clothing_status.text = "Model attachment selected. Publish will create a wearable model item."
		await _rebuild_avatar_item_attachment_preview(attachment_root, model_entry)
		set_transform_rows_visible.call(transform_expand.button_pressed)
		if sync_attachment_preview.is_valid():
			sync_attachment_preview.call(0.0)
	)
	_connect_vector3_row_changed(pos_row, sync_attachment_preview)
	_connect_vector3_row_changed(rot_row, sync_attachment_preview)
	_connect_vector3_row_changed(scale_row, sync_attachment_preview)
	var price_title := Label.new()
	price_title.text = "Цена в каталоге · Boblox"
	price_title.add_theme_color_override("font_color", Color("202b35"))
	publication_box.add_child(price_title)
	var price_input := SpinBox.new()
	price_input.name = "AvatarItemPrice"
	price_input.min_value = 0
	price_input.max_value = 1000000
	price_input.step = 1
	price_input.value = 20
	price_input.suffix = "Boblox"
	price_input.custom_minimum_size.y = 42
	publication_box.add_child(price_input)
	var price_help := Label.new()
	price_help.text = "Одежда — от 5, модели — от 20 Boblox. Цена 0 использует лимит бесплатных товаров. Сбор за публикацию подтверждается отдельно."
	price_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price_help.add_theme_font_size_override("font_size", 13)
	price_help.add_theme_color_override("font_color", Color("556575"))
	publication_box.add_child(price_help)
	var publish_btn := Button.new()
	publish_btn.text = "Опубликовать предмет"
	publish_btn.name = "PublishAvatarItem"
	publish_btn.custom_minimum_size = Vector2(0, 44)
	publish_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	publish_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.16, 0.63, 0.28, 1.0)))
	publish_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.12, 0.55, 0.23, 1.0)))
	publish_btn.add_theme_color_override("font_color", Color.WHITE)
	publish_btn.pressed.connect(func() -> void:
		var model_entry: Dictionary = model_option.get_item_metadata(model_option.selected) if model_option.get_item_metadata(model_option.selected) is Dictionary else {}
		var selected_mode := str(creation_state.get("mode", "model"))
		var clothing_entry: Dictionary = creation_state.get("clothing", {}) if creation_state.get("clothing", {}) is Dictionary else {}
		if name_edit.text.strip_edges().is_empty():
			clothing_status.text = "Введите название предмета перед публикацией."
			name_edit.grab_focus()
			return
		var minimum_price := 5 if selected_mode in ["shirt", "pants"] else 20
		if visibility.selected == 0 and price_input.value > 0 and price_input.value < minimum_price:
			clothing_status.text = "Минимальная цена: %d Boblox. Для бесплатного предмета укажите 0." % minimum_price
			price_input.get_line_edit().grab_focus()
			return
		if selected_mode in ["shirt", "pants"] and not clothing_entry.is_empty():
			publish_btn.disabled = true
			publish_btn.text = "Publishing..."
			clothing_status.text = "Generating preview and uploading %s..." % selected_mode
			var clothing_thumbnail_path := await _capture_avatar_item_preview_thumbnail(sub, "avatar_%s_%d" % [selected_mode, Time.get_ticks_msec()])
			if clothing_thumbnail_path.is_empty():
				clothing_thumbnail_path = str(clothing_entry.get("preview_path", ""))
			var clothing_result: Dictionary = await _publish_avatar_clothing_item_from_fields(
				name_edit.text.strip_edges(),
				clothing_entry,
				"private" if visibility.selected == 1 else "public",
				clothing_thumbnail_path, int(price_input.value)
			)
			publish_btn.disabled = false
			publish_btn.text = "Опубликовать предмет"
			if not bool(clothing_result.get("ok", false)):
				clothing_status.text = "Publish failed: %s" % _avatar_item_publish_error_text(clothing_result)
			return
		if model_option.disabled or model_entry.is_empty():
			publish_btn.text = "Select a model first!"
			await get_tree().create_timer(1.5).timeout
			publish_btn.text = "Опубликовать предмет"
			return
		publish_btn.disabled = true
		publish_btn.text = "Publishing..."
		clothing_status.text = "Generating model preview and uploading item..."
		var model_thumbnail_path := await _capture_avatar_item_preview_thumbnail(sub, "avatar_model_%d" % Time.get_ticks_msec())
		var selected_slot_name := slot_option.get_item_text(slot_option.selected)
		var selected_slot_position := _avatar_item_slot_position(selected_slot_name)
		var transform_data := {
			"position": _vector3_to_array(attachment_root.position - selected_slot_position),
			"rotation_degrees": _vector3_to_array(attachment_root.rotation_degrees),
			"scale": _vector3_to_array(attachment_root.scale)
		}
		var model_result: Dictionary = await _publish_avatar_item_from_fields(
			name_edit.text.strip_edges(),
			model_entry,
			selected_slot_name,
			"private" if visibility.selected == 1 else "public",
			model_thumbnail_path,
			transform_data, int(price_input.value)
		)
		publish_btn.disabled = false
		publish_btn.text = "Опубликовать предмет"
		if not bool(model_result.get("ok", false)):
			clothing_status.text = "Publish failed: %s" % _avatar_item_publish_error_text(model_result)
	)
	publication_box.add_child(publish_btn)
	_style_avatar_creator_controls(root)

func _open_avatar_template_picker_from_develop(kind: String, preview_player: Node, imported_callback: Callable = Callable()) -> void:
	var filters := PackedStringArray([
		"*.png,*.jpg,*.jpeg,*.webp;Image files;image/png,image/jpeg,image/webp"
	])
	if _show_system_open_file_dialog("Choose %s template" % kind.capitalize(), filters, func(path: String) -> void:
		var import_result := _import_template_to_user_storage_path(path, kind)
		_apply_avatar_template_import_result(kind, preview_player, imported_callback, import_result)
	):
		return
	var dialog := FileDialog.new()
	_configure_user_file_dialog(dialog, filters)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var import_result := _import_template_to_user_storage_path(path, kind)
		_apply_avatar_template_import_result(kind, preview_player, imported_callback, import_result)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(760, 520))

func _apply_avatar_template_import_result(kind: String, preview_player: Node, imported_callback: Callable, import_result: Dictionary) -> void:
	var saved_path := str(import_result.get("path", ""))
	if saved_path.is_empty():
		if imported_callback.is_valid():
			imported_callback.call(import_result)
		return
	if typeof(UserSession) != TYPE_NIL and UserSession.avatar_data is Dictionary:
		UserSession.avatar_data["%s_texture_path" % kind] = saved_path
		var list_key := "saved_shirt_texture_paths" if kind == "shirt" else "saved_pants_texture_paths"
		var saved_paths: Array = UserSession.avatar_data.get(list_key, []) if UserSession.avatar_data.get(list_key, []) is Array else []
		if not (saved_path in saved_paths):
			saved_paths.append(saved_path)
		UserSession.avatar_data[list_key] = saved_paths
		UserSession.apply_avatar_to_game_state()
	if is_instance_valid(preview_player):
		preview_player.set("shirt_texture_path", saved_path if kind == "shirt" else "")
		preview_player.set("pants_texture_path", saved_path if kind == "pants" else "")
		preview_player.set("equipped_avatar_items", [])
		if preview_player.has_method("force_avatar_visual_refresh"):
			preview_player.call_deferred("force_avatar_visual_refresh")
		elif preview_player.has_method("_apply_avatar_visuals_if_needed"):
			preview_player.call_deferred("_apply_avatar_visuals_if_needed")
	if imported_callback.is_valid():
		imported_callback.call(import_result)

func _request_android_media_permissions() -> void:
	if not OS.has_feature("android"):
		return
	if OS.has_method("request_permissions"):
		OS.request_permissions()

func _import_template_to_user_storage_path(source_path: String, template_kind: String) -> Dictionary:
	return AVATAR_TEMPLATE_PROCESSOR.import_template_to_user_storage(source_path, template_kind, _get_avatar_template_owner_hint())

func _copy_template_to_user_storage_path(source_path: String, template_kind: String) -> String:
	var result := _import_template_to_user_storage_path(source_path, template_kind)
	if not bool(result.get("ok", false)):
		push_warning("[Lobby] Template import failed: %s" % str(result.get("error", "Unknown error")))
		return ""
	return str(result.get("path", ""))

func _get_avatar_template_owner_hint() -> String:
	if typeof(UserSession) != TYPE_NIL:
		if UserSession.is_logged_in and not str(UserSession.user_id).strip_edges().is_empty():
			return str(UserSession.user_id)
		return str(UserSession.username)
	return "local"

func _show_avatar_item_creator_dialog() -> void:
	_show_avatar_item_creator_page()

func _publish_avatar_item_from_dialog(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var name_edit := dialog.find_child("ItemNameEdit", true, false) as LineEdit
	var model_option := dialog.find_child("ModelOption", true, false) as OptionButton
	var slot_option := dialog.find_child("AttachmentSlotOption", true, false) as OptionButton
	var visibility_option := dialog.find_child("VisibilityOption", true, false) as OptionButton
	var thumbnail_edit := dialog.find_child("ThumbnailPathEdit", true, false) as LineEdit
	if model_option == null or model_option.disabled:
		push_warning("[Lobby] Cannot publish avatar item without a model.")
		return
	var model_entry: Dictionary = model_option.get_item_metadata(model_option.selected) if model_option.get_item_metadata(model_option.selected) is Dictionary else {}
	var item_name := name_edit.text.strip_edges() if name_edit != null else "Avatar Item"
	var attachment_slot := slot_option.get_item_text(slot_option.selected) if slot_option != null else "Head"
	var visibility_name := "private" if visibility_option != null and visibility_option.selected == 1 else "public"
	var thumbnail_path: String = thumbnail_edit.text.strip_edges() if thumbnail_edit != null else ""
	await _publish_avatar_item_from_fields(item_name, model_entry, attachment_slot, visibility_name, thumbnail_path)

func _publish_avatar_item_from_fields(item_name: String, model_entry: Dictionary, attachment_slot: String, visibility_name: String, thumbnail_path: String, transform_data: Dictionary = {}, price_boblox: int = 20) -> Dictionary:
	var clean_name := item_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Avatar Item"
	var item_id := "avatar_item_%d" % Time.get_ticks_msec()
	var attachment_transform: Dictionary = transform_data.duplicate(true)
	if attachment_transform.is_empty():
		attachment_transform = {
			"position": [0.0, 0.0, 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [1.0, 1.0, 1.0]
		}
	var model_data := _avatar_item_model_data_from_entry(model_entry)
	var model_parts := _avatar_item_extract_parts_from_model_data(model_data)
	var model_data_with_attachment := model_data.duplicate(true)
	model_data_with_attachment["attachment_slot"] = attachment_slot
	model_data_with_attachment["attachment_transform"] = attachment_transform.duplicate(true)
	model_data_with_attachment["item_kind"] = "model"
	model_data_with_attachment["category"] = "model"
	model_data_with_attachment["asset_type"] = "avatar_item"
	var source_file_name_value: Variant = _find_model_entry_value(model_entry, "source_file_name")
	var source_file_name := ""
	if source_file_name_value != null:
		source_file_name = str(source_file_name_value).strip_edges()
	var metadata: Dictionary = {
		"id": item_id,
		"category": "model",
		"asset_type": "avatar_item",
		"item_kind": "model",
		"model_id": str(model_entry.get("id", model_entry.get("cloud_model_id", model_entry.get("draft_id", "")))),
		"attachment_slot": attachment_slot,
		"visibility": visibility_name,
		"price_robux": maxi(0, price_boblox),
		"attachment_transform": attachment_transform,
		"data": model_data_with_attachment,
		"model_data": model_data_with_attachment,
		"model_name": str(model_entry.get("name", "")),
		"source_file_name": source_file_name
	}
	if not model_parts.is_empty():
		metadata["parts"] = model_parts
	for source_key in [
		"source_url",
		"source_file_url",
		"source_model_path",
		"canonical_source_model_path",
		"source_model_transform",
		"canonical_transform_baked"
	]:
		var source_value: Variant = model_data.get(source_key, null)
		if not _model_transport_value_present(source_value):
			source_value = _find_model_entry_value(model_entry, source_key)
		if _model_transport_value_present(source_value):
			metadata[source_key] = source_value
			model_data_with_attachment[source_key] = source_value
	var published_source_url := str(metadata.get("source_url", metadata.get("source_file_url", ""))).strip_edges()
	if published_source_url.is_empty():
		var local_model_source := str(metadata.get("canonical_source_model_path", metadata.get("source_model_path", ""))).strip_edges()
		if not local_model_source.is_empty() and FileAccess.file_exists(local_model_source):
			var model_extension := local_model_source.get_extension().to_lower()
			var model_file_name := "model.%s" % model_extension
			var model_upload: Dictionary = await CloudAPI.upload_avatar_item_file(
				item_id,
				model_file_name,
				local_model_source,
				_guess_model_source_mime(local_model_source)
			)
			if not bool(model_upload.get("ok", false)):
				return _avatar_item_publish_error_result("Model geometry upload failed.", model_upload)
			var model_asset: Dictionary = model_upload.get("asset", {}) if model_upload.get("asset", {}) is Dictionary else {}
			published_source_url = str(model_asset.get("public_url", "")).strip_edges()
			if published_source_url.is_empty():
				return _avatar_item_publish_error_result("Model upload did not return a public URL.", model_upload)
			metadata["source_url"] = published_source_url
			metadata["source_file_url"] = published_source_url
			metadata["source_file_name"] = model_file_name
			model_data_with_attachment["source_url"] = published_source_url
			model_data_with_attachment["source_file_url"] = published_source_url
	if not thumbnail_path.is_empty() and FileAccess.file_exists(thumbnail_path):
		var thumbnail_upload: Dictionary = await CloudAPI.upload_avatar_item_file(item_id, "thumbnail.%s" % thumbnail_path.get_extension().to_lower(), thumbnail_path, _guess_image_mime(thumbnail_path))
		if bool(thumbnail_upload.get("ok", false)):
			var thumbnail_asset: Dictionary = thumbnail_upload.get("asset", {}) if thumbnail_upload.get("asset", {}) is Dictionary else {}
			metadata["thumbnail"] = str(thumbnail_asset.get("public_url", ""))
	var item_data: Dictionary = metadata.duplicate(true)
	var result: Dictionary = await CloudAPI.publish_avatar_item(item_data, clean_name, metadata)
	if bool(result.get("ok", false)):
		_remember_owned_avatar_item(item_id)
		_remember_owned_avatar_item_payload(_avatar_item_payload_from_publish_result(result, metadata, clean_name))
		if avatar_ui != null and avatar_ui.has_method("reload_cloud_inventory"):
			avatar_ui.reload_cloud_inventory()
		_show_my_creations_page()
		result["item_id"] = item_id
		return result
	else:
		push_warning("[Lobby] Avatar item publish failed: %s" % str(result.get("error", "Unknown error")))
		return _avatar_item_publish_error_result("Could not publish avatar model item.", result)

func _publish_avatar_clothing_item_from_fields(item_name: String, clothing_entry: Dictionary, visibility_name: String, thumbnail_path: String = "", price_boblox: int = 5) -> Dictionary:
	var kind := str(clothing_entry.get("kind", "")).strip_edges().to_lower()
	if not (kind in ["shirt", "pants"]):
		var invalid_kind_message := "Cannot publish avatar clothing with invalid kind: %s" % kind
		push_warning("[Lobby] %s" % invalid_kind_message)
		return _avatar_item_publish_error_result(invalid_kind_message)
	var template_path := str(clothing_entry.get("path", clothing_entry.get("atlas_path", ""))).strip_edges()
	if template_path.is_empty() or not FileAccess.file_exists(template_path):
		var missing_template_message := "Cannot publish %s; normalized template file is missing." % kind
		push_warning("[Lobby] %s" % missing_template_message)
		return _avatar_item_publish_error_result(missing_template_message)
	var clean_name := item_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Classic %s" % kind.capitalize()
	var item_id := "avatar_%s_%d" % [kind, Time.get_ticks_msec()]
	var template_upload: Dictionary = await CloudAPI.upload_avatar_item_file(item_id, "%s_template.png" % kind, template_path, "image/png")
	if not bool(template_upload.get("ok", false)):
		push_warning("[Lobby] %s template upload failed: %s" % [kind.capitalize(), str(template_upload.get("error", "Unknown upload error"))])
		return _avatar_item_publish_error_result("%s template upload failed." % kind.capitalize(), template_upload)
	var template_asset: Dictionary = template_upload.get("asset", {}) if template_upload.get("asset", {}) is Dictionary else {}
	var template_url := str(template_asset.get("public_url", "")).strip_edges()
	if template_url.is_empty():
		var missing_template_url_message := "%s template upload did not return a public URL." % kind.capitalize()
		push_warning("[Lobby] %s" % missing_template_url_message)
		return _avatar_item_publish_error_result(missing_template_url_message, template_upload)
	var resolved_thumbnail_path := thumbnail_path.strip_edges()
	if resolved_thumbnail_path.is_empty():
		resolved_thumbnail_path = str(clothing_entry.get("preview_path", "")).strip_edges()
	var thumbnail_url := ""
	if not resolved_thumbnail_path.is_empty() and FileAccess.file_exists(resolved_thumbnail_path):
		var thumbnail_upload: Dictionary = await CloudAPI.upload_avatar_item_file(item_id, "thumbnail.png", resolved_thumbnail_path, _guess_image_mime(resolved_thumbnail_path))
		if bool(thumbnail_upload.get("ok", false)):
			var thumbnail_asset: Dictionary = thumbnail_upload.get("asset", {}) if thumbnail_upload.get("asset", {}) is Dictionary else {}
			thumbnail_url = str(thumbnail_asset.get("public_url", "")).strip_edges()
	if thumbnail_url.is_empty():
		thumbnail_url = template_url
	var clothing_data := {
		"item_kind": kind,
		"category": kind,
		"texture_path": template_url,
		"template_url": template_url,
		"atlas_path": template_url,
		"thumbnail": thumbnail_url,
		"template_version": str(clothing_entry.get("template_version", "bobux_r6_square_v1"))
	}
	var metadata := {
		"id": item_id,
		"category": kind,
		"asset_type": "avatar_item",
		"item_kind": kind,
		"visibility": visibility_name,
		"price_robux": maxi(0, price_boblox),
		"thumbnail": thumbnail_url,
		"template_url": template_url,
		"source_url": template_url,
		"attachment_slot": "Torso" if kind == "shirt" else "LeftLeg",
		"attachment_transform": {},
		"data": clothing_data
	}
	var result: Dictionary = await CloudAPI.publish_avatar_item(clothing_data, clean_name, metadata)
	if bool(result.get("ok", false)):
		_remember_owned_avatar_item(item_id)
		_apply_published_clothing_to_session(kind, template_url, item_id, template_path)
		_remember_owned_avatar_item_payload(_avatar_item_payload_from_publish_result(result, metadata, clean_name))
		if avatar_ui != null and avatar_ui.has_method("reload_cloud_inventory"):
			avatar_ui.reload_cloud_inventory()
		_show_my_creations_page()
		result["item_id"] = item_id
		return result
	else:
		push_warning("[Lobby] Avatar clothing publish failed: %s" % str(result.get("error", "Unknown error")))
		return _avatar_item_publish_error_result("Could not publish avatar clothing.", result)

func _avatar_item_publish_error_result(message: String, source: Dictionary = {}) -> Dictionary:
	var result := source.duplicate(true)
	result["ok"] = false
	if str(result.get("error", "")).strip_edges().is_empty():
		result["error"] = message
	return result

func _avatar_item_publish_error_text(result: Dictionary) -> String:
	for key in ["error", "message", "details"]:
		var value := str(result.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	var data: Variant = result.get("data", null)
	if data is Dictionary:
		var data_dict := data as Dictionary
		for key in ["message", "error", "details"]:
			var value := str(data_dict.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	elif data is String:
		var text := (data as String).strip_edges()
		if not text.is_empty():
			return text
	return "Unknown API error."

func _remember_owned_avatar_item(item_id: String) -> void:
	var clean_id := item_id.strip_edges()
	if clean_id.is_empty() or typeof(UserSession) == TYPE_NIL:
		return
	if not (UserSession.inventory_items is Array):
		UserSession.inventory_items = []
	if not (clean_id in UserSession.inventory_items):
		UserSession.inventory_items.append(clean_id)

func _avatar_item_payload_from_publish_result(result: Dictionary, metadata: Dictionary, item_name: String) -> Dictionary:
	var payload := metadata.duplicate(true)
	for source_variant in [result.get("data", {}), result.get("item", {}), result]:
		if not (source_variant is Dictionary):
			continue
		var source: Dictionary = source_variant
		for key in source.keys():
			if key in ["ok", "error", "message", "details"]:
				continue
			payload[key] = source.get(key)
	for required_metadata_key in ["category", "asset_type", "item_kind", "attachment_slot", "attachment_transform", "data", "model_data", "parts", "source_url", "source_file_url", "source_model_path", "template_url", "thumbnail", "visibility"]:
		if metadata.has(required_metadata_key):
			payload[required_metadata_key] = metadata.get(required_metadata_key)
	var item_id := str(payload.get("id", payload.get("item_id", metadata.get("id", "")))).strip_edges()
	payload["id"] = item_id
	payload["item_id"] = item_id
	payload["name"] = item_name.strip_edges() if not item_name.strip_edges().is_empty() else str(payload.get("name", "Avatar Item"))
	payload["owned"] = true
	if typeof(UserSession) != TYPE_NIL:
		if str(payload.get("owner_id", "")).strip_edges().is_empty():
			payload["owner_id"] = str(UserSession.user_id).strip_edges()
		if str(payload.get("owner_name", "")).strip_edges().is_empty():
			payload["owner_name"] = str(UserSession.username).strip_edges()
	return payload

func _remember_owned_avatar_item_payload(item: Dictionary) -> void:
	if item.is_empty() or typeof(UserSession) == TYPE_NIL:
		return
	if not (UserSession.avatar_data is Dictionary):
		UserSession.avatar_data = {}
	var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
	if item_id.is_empty():
		return
	var normalized := item.duplicate(true)
	normalized["id"] = item_id
	normalized["item_id"] = item_id
	normalized["owned"] = true
	_upsert_avatar_item_payload_in_session_list("owned_avatar_item_payloads", normalized)
	var equipped: Array = UserSession.avatar_data.get("equipped", []) if UserSession.avatar_data.get("equipped", []) is Array else []
	if item_id in equipped:
		_upsert_avatar_item_payload_in_session_list("equipped_avatar_item_payloads", normalized)

func _upsert_avatar_item_payload_in_session_list(list_key: String, item: Dictionary) -> void:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return
	var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
	if item_id.is_empty():
		return
	var raw_list: Variant = UserSession.avatar_data.get(list_key, [])
	var next_list: Array = []
	var replaced := false
	if raw_list is Array:
		for raw_payload in raw_list:
			if not (raw_payload is Dictionary):
				continue
			var payload := (raw_payload as Dictionary).duplicate(true)
			var payload_id := str(payload.get("id", payload.get("item_id", ""))).strip_edges()
			if payload_id == item_id:
				next_list.append(item.duplicate(true))
				replaced = true
			elif not payload_id.is_empty():
				next_list.append(payload)
	if not replaced:
		next_list.append(item.duplicate(true))
	UserSession.avatar_data[list_key] = next_list

func _apply_published_clothing_to_session(kind: String, template_url: String, item_id: String, local_template_path: String = "") -> void:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return
	var texture_key := "shirt_texture_path" if kind == "shirt" else "pants_texture_path"
	var list_key := "saved_shirt_texture_paths" if kind == "shirt" else "saved_pants_texture_paths"
	UserSession.avatar_data[texture_key] = template_url
	var saved_paths: Array = UserSession.avatar_data.get(list_key, []) if UserSession.avatar_data.get(list_key, []) is Array else []
	var cleaned_paths: Array = []
	for raw_path in saved_paths:
		var candidate := str(raw_path).strip_edges()
		if candidate.is_empty() or candidate == template_url or candidate == local_template_path:
			continue
		if not (candidate in cleaned_paths):
			cleaned_paths.append(candidate)
	UserSession.avatar_data[list_key] = cleaned_paths
	var equipped: Array = UserSession.avatar_data.get("equipped", []) if UserSession.avatar_data.get("equipped", []) is Array else []
	if not (item_id in equipped):
		equipped.append(item_id)
	UserSession.avatar_data["equipped"] = equipped
	UserSession.apply_avatar_to_game_state()
	_refresh_all_local_avatar_previews_from_session()
	_queue_avatar_cloud_sync()


func _refresh_all_local_avatar_previews_from_session() -> void:
	var avatar_data: Dictionary = UserSession.avatar_data if UserSession.avatar_data is Dictionary else {}
	var equipped_avatar_items := _get_local_equipped_avatar_item_payloads()
	var targets: Array = [preview_player, home_avatar_player, profile_header_preview_player, profile_preview_player]
	for target in targets:
		if target == null:
			continue
		target.set("use_local_avatar_fallback", false)
		target.set("render_avatar_visual_decals", true)
		target.set("render_avatar_clothing_decals", true)
		target.set("face_texture_path", str(avatar_data.get("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)))
		target.set("chest_badge_texture_path", str(avatar_data.get("chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)))
		target.set("shirt_texture_path", str(avatar_data.get("shirt_texture_path", "")))
		target.set("pants_texture_path", str(avatar_data.get("pants_texture_path", "")))
		target.set("equipped_avatar_items", equipped_avatar_items)
		if target.has_method("force_avatar_visual_refresh"):
			target.call_deferred("force_avatar_visual_refresh")
		elif target.has_method("_apply_avatar_visuals_if_needed"):
			target.call_deferred("_apply_avatar_visuals_if_needed")

func _get_local_equipped_avatar_item_payloads() -> Array:
	var result: Array = []
	if avatar_ui != null and avatar_ui.has_method("_get_equipped_avatar_item_payloads"):
		var payloads: Variant = avatar_ui.call("_get_equipped_avatar_item_payloads")
		if payloads is Array:
			result = _merge_avatar_item_payload_arrays(result, payloads as Array)
	result = _merge_avatar_item_payload_arrays(result, _get_session_equipped_avatar_item_payloads())
	return result

func _get_session_equipped_avatar_item_payloads() -> Array:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return []
	var equipped: Array = UserSession.avatar_data.get("equipped", []) if UserSession.avatar_data.get("equipped", []) is Array else []
	if equipped.is_empty():
		return []
	var result: Array = []
	for payload in _get_session_avatar_item_payloads():
		if not (payload is Dictionary):
			continue
		var item: Dictionary = payload
		var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
		if not item_id.is_empty() and item_id in equipped:
			result.append(item.duplicate(true))
	return result

func _get_session_avatar_item_payloads() -> Array:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return []
	var result: Array = []
	for list_key in ["owned_avatar_item_payloads", "equipped_avatar_item_payloads"]:
		var raw_list: Variant = UserSession.avatar_data.get(list_key, [])
		if not (raw_list is Array):
			continue
		result = _merge_avatar_item_payload_arrays(result, raw_list as Array)
	return result

func _get_session_created_avatar_item_payloads() -> Array:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return []
	var raw_list: Variant = UserSession.avatar_data.get("owned_avatar_item_payloads", [])
	if not (raw_list is Array):
		return []
	var result: Array = []
	var owned_items := raw_list as Array
	var current_user_id := str(UserSession.user_id).strip_edges()
	var current_username := str(UserSession.username).strip_edges().to_lower()
	for raw_item in owned_items:
		if not (raw_item is Dictionary):
			continue
		var item := (raw_item as Dictionary).duplicate(true)
		var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
		if item_id.is_empty() or item_id in ["classic_smile", "bobux_chest_badge"]:
			continue
		var asset_type := str(item.get("asset_type", item.get("type", ""))).strip_edges().to_lower()
		var item_kind := _resolve_avatar_item_catalog_kind(item)
		var owner_id := str(item.get("owner_id", item.get("creator_id", ""))).strip_edges()
		var owner_name := str(item.get("owner_name", item.get("creator_name", ""))).strip_edges().to_lower()
		var created_by_me := false
		if not current_user_id.is_empty() and owner_id == current_user_id:
			created_by_me = true
		if not current_username.is_empty() and owner_name == current_username:
			created_by_me = true
		if item_id.begins_with("avatar_"):
			created_by_me = true
		var recognized_avatar_kind := item_kind in ["shirt", "shirts", "pants", "pant", "model", "accessory", "accessories"]
		var looks_like_avatar_item := asset_type == "avatar_item" or asset_type.is_empty() or recognized_avatar_kind
		if looks_like_avatar_item and created_by_me and recognized_avatar_kind:
			result = _merge_avatar_item_payload_arrays(result, [item])
	return result

func _merge_avatar_item_payload_arrays(base: Array, additions: Array) -> Array:
	var result := base.duplicate(true)
	var seen: Dictionary = {}
	for raw_existing in result:
		if raw_existing is Dictionary:
			var existing_id := str((raw_existing as Dictionary).get("id", (raw_existing as Dictionary).get("item_id", ""))).strip_edges()
			if not existing_id.is_empty():
				seen[existing_id] = true
	for raw_item in additions:
		if not (raw_item is Dictionary):
			continue
		var item := (raw_item as Dictionary).duplicate(true)
		var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
		if item_id.is_empty() or bool(seen.get(item_id, false)):
			continue
		result.append(item)
		seen[item_id] = true
	return result


func _download_avatar_template_references() -> void:
	var copied := _copy_avatar_template_references_to_user_dir()
	if not copied.is_empty():
		OS.shell_open(ProjectSettings.globalize_path("user://avatar_templates"))
	else:
		push_warning("[Lobby] Avatar template download did not copy any files.")

func _copy_avatar_template_references_to_user_dir() -> Array[String]:
	var target_dir := "user://avatar_templates"
	var target_global_dir := ProjectSettings.globalize_path(target_dir)
	DirAccess.make_dir_recursive_absolute(target_global_dir)
	var copied: Array[String] = []
	for entry in [
		{"source": "res://assets/avatar/shirt_template_reference.jpg", "name": "bobux_shirt_template.jpg"},
		{"source": "res://assets/avatar/pants_template_reference.jpg", "name": "bobux_pants_template.jpg"}
	]:
		var source_path := str(entry.get("source", ""))
		var target_path := target_dir.path_join(str(entry.get("name", "")))
		var source_global_path := ProjectSettings.globalize_path(source_path)
		var target_global_path := ProjectSettings.globalize_path(target_path)
		var copy_error := DirAccess.copy_absolute(source_global_path, target_global_path)
		if copy_error != OK:
			var source_file := FileAccess.open(source_path, FileAccess.READ)
			if source_file == null:
				source_file = FileAccess.open(source_global_path, FileAccess.READ)
			if source_file == null:
				push_warning("[Lobby] Could not open avatar template source: %s" % source_path)
				continue
			var bytes := source_file.get_buffer(source_file.get_length())
			source_file.close()
			var target_file := FileAccess.open(target_path, FileAccess.WRITE)
			if target_file == null:
				target_file = FileAccess.open(target_global_path, FileAccess.WRITE)
			if target_file == null:
				push_warning("[Lobby] Could not write avatar template target: %s" % target_global_path)
				continue
			target_file.store_buffer(bytes)
			target_file.close()
		if FileAccess.file_exists(target_path) or FileAccess.file_exists(target_global_path):
			copied.append(target_global_path)
	return copied

func _capture_avatar_item_preview_thumbnail(sub: SubViewport, file_prefix: String) -> String:
	if sub == null:
		return ""
	var camera := sub.get_node_or_null("AvatarItemPreviewCamera") as Camera3D
	var previous_camera_transform := Transform3D.IDENTITY
	var previous_camera_fov := 70.0
	var orbit_root := sub.find_child("AvatarItemPreviewOrbitRoot", true, false) as Node3D
	var previous_orbit_transform := Transform3D.IDENTITY
	if camera != null:
		previous_camera_transform = camera.transform
		previous_camera_fov = camera.fov
		camera.fov = 30.0
		camera.position = Vector3(0.0, 2.45, 8.8)
		camera.look_at(Vector3(0.0, 2.05, 0.0), Vector3.UP)
	if orbit_root != null:
		previous_orbit_transform = orbit_root.transform
		orbit_root.rotation = Vector3.ZERO
	await RenderingServer.frame_post_draw
	var viewport_texture := sub.get_texture()
	if viewport_texture == null:
		if camera != null:
			camera.transform = previous_camera_transform
			camera.fov = previous_camera_fov
		if orbit_root != null:
			orbit_root.transform = previous_orbit_transform
		return ""
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		if camera != null:
			camera.transform = previous_camera_transform
			camera.fov = previous_camera_fov
		if orbit_root != null:
			orbit_root.transform = previous_orbit_transform
		return ""
	if camera != null:
		camera.transform = previous_camera_transform
		camera.fov = previous_camera_fov
	if orbit_root != null:
		orbit_root.transform = previous_orbit_transform
	image.convert(Image.FORMAT_RGBA8)
	image = _crop_avatar_item_thumbnail_to_subject(image)
	var largest_dimension := maxi(image.get_width(), image.get_height())
	if largest_dimension > CLOUD_THUMBNAIL_MAX_DIMENSION:
		var resize_scale := float(CLOUD_THUMBNAIL_MAX_DIMENSION) / float(largest_dimension)
		image.resize(
			maxi(1, roundi(float(image.get_width()) * resize_scale)),
			maxi(1, roundi(float(image.get_height()) * resize_scale)),
			Image.INTERPOLATE_LANCZOS
		)
	var dir := "user://avatar_item_previews"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var clean_prefix := _sanitize_avatar_item_file_segment(file_prefix)
	var path := dir.path_join("%s.png" % clean_prefix)
	if image.save_png(path) != OK:
		return ""
	return path

func _crop_avatar_item_thumbnail_to_subject(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var width := image.get_width()
	var height := image.get_height()
	if width <= 8 or height <= 8:
		return image
	var bg := image.get_pixel(0, 0)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(height):
		for x in range(width):
			var c := image.get_pixel(x, y)
			if c.a <= 0.04:
				continue
			var delta: float = absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			if delta < 0.12 and c.a >= 0.98:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return image
	var subject_width := max_x - min_x + 1
	var subject_height := max_y - min_y + 1
	if subject_width <= 4 or subject_height <= 4:
		return image
	var padding := maxi(28, roundi(float(maxi(subject_width, subject_height)) * 0.18))
	var crop_x := maxi(0, min_x - padding)
	var crop_y := maxi(0, min_y - padding)
	var crop_w := mini(width - crop_x, subject_width + padding * 2)
	var crop_h := mini(height - crop_y, subject_height + padding * 2)
	var square := maxi(crop_w, crop_h)
	var extra_x := int(maxi(0, square - crop_w) / 2)
	var extra_y := int(maxi(0, square - crop_h) / 2)
	crop_x = clampi(crop_x - extra_x, 0, maxi(0, width - square))
	crop_y = clampi(crop_y - extra_y, 0, maxi(0, height - square))
	square = mini(square, mini(width - crop_x, height - crop_y))
	if square <= 0 or square >= mini(width, height) - 2:
		return image
	return image.get_region(Rect2i(crop_x, crop_y, square, square))

func _sanitize_avatar_item_file_segment(value: String) -> String:
	var clean := value.strip_edges().get_file()
	for bad_char in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "%", "#", "&", "=", "+"]:
		clean = clean.replace(bad_char, "_")
	if clean.is_empty():
		clean = "avatar_item"
	return clean

func _rebuild_avatar_item_attachment_preview(attachment_root: Node3D, model_entry: Dictionary) -> void:
	if attachment_root == null:
		return
	for child in attachment_root.get_children():
		attachment_root.remove_child(child)
		child.queue_free()
	if model_entry.is_empty():
		return
	var model_data := _avatar_item_model_data_from_entry(model_entry)
	var source_path := ""
	for path_key in ["canonical_source_model_path", "source_model_path"]:
		var path_candidate := str(model_data.get(path_key, "")).strip_edges()
		if path_candidate.is_empty():
			path_candidate = str(model_entry.get(path_key, "")).strip_edges()
		if not path_candidate.is_empty() and FileAccess.file_exists(path_candidate):
			source_path = path_candidate
			break
	var source_url := str(model_data.get("source_url", model_data.get("source_file_url", ""))).strip_edges()
	if source_url.is_empty():
		var source_url_value: Variant = _find_model_entry_value(model_entry, "source_url")
		if not _model_transport_value_present(source_url_value):
			source_url_value = _find_model_entry_value(model_entry, "source_file_url")
		if _model_transport_value_present(source_url_value):
			source_url = str(source_url_value).strip_edges()
	var path_to_load := source_path if not source_path.is_empty() else source_url
	var parts: Array = _avatar_item_extract_parts_from_model_data(model_data)
	var loaded_model: Node = null
	if not path_to_load.is_empty():
		loaded_model = await _load_mesh_or_scene_from_path(path_to_load)
	if attachment_root == null or not is_instance_valid(attachment_root):
		if loaded_model != null:
			loaded_model.queue_free()
		return
	if loaded_model != null:
		attachment_root.add_child(loaded_model)
		_apply_avatar_item_source_fallback_colors(loaded_model, parts)
		_recenter_avatar_item_attachment_parts(attachment_root)
		_add_attachment_gizmos(attachment_root)
		return

	if parts.is_empty():
		attachment_root.add_child(_create_avatar_item_preview_part({
			"name": str(model_entry.get("name", "Model")),
			"kind": "ImportedPlaceholder",
			"position": [0.0, 0.0, 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [0.9, 0.55, 0.9],
			"color": "ffb347"
		}))
		_recenter_avatar_item_attachment_parts(attachment_root)
		_add_attachment_gizmos(attachment_root)
		return
	for part_variant in parts:
		if part_variant is Dictionary:
			attachment_root.add_child(_create_avatar_item_preview_part(_avatar_item_normalize_part(part_variant as Dictionary)))
	_recenter_avatar_item_attachment_parts(attachment_root)
	_add_attachment_gizmos(attachment_root)

func _load_mesh_or_scene_from_path(path: String) -> Node:
	if path.is_empty():
		return null
	var local_path := path
	if path.begins_with("http://") or path.begins_with("https://"):
		var cache_dir := "user://cache/models"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
		var url_path := path.split("?", false, 1)[0]
		var extension_hint := url_path.get_extension().to_lower()
		if extension_hint not in ["glb", "gltf", "fbx", "obj"]:
			extension_hint = "glb"
		local_path = cache_dir.path_join("%s.%s" % [path.md5_text(), extension_hint])
		var cache_valid := false
		if FileAccess.file_exists(local_path):
			var cached := FileAccess.open(local_path, FileAccess.READ)
			cache_valid = cached != null and cached.get_length() > 32
			if cached != null:
				cached.close()
			if not cache_valid:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
		if not cache_valid:
			var temporary_path := local_path + ".part"
			if FileAccess.file_exists(temporary_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
			var http_client := HTTPRequest.new()
			add_child(http_client)
			http_client.download_file = temporary_path
			http_client.timeout = 20.0
			var err := http_client.request(path)
			var result: Array = []
			if err == OK:
				result = await http_client.request_completed
			http_client.queue_free()
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
					DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(local_path))
			if FileAccess.file_exists(temporary_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		if not FileAccess.file_exists(local_path):
			return null
	
	var extension := local_path.get_extension().to_lower()
	if extension in ["glb", "gltf", "fbx"]:
		var gltf_document: GLTFDocument = FBXDocument.new() if local_path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
		var gltf_state: GLTFState = FBXState.new() if local_path.get_extension().to_lower() == "fbx" else GLTFState.new()
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
	elif local_path.begins_with("res://") or local_path.begins_with("user://"):
		if ResourceLoader.exists(local_path):
			var res := ResourceLoader.load(local_path)
			if res is PackedScene:
				return res.instantiate()
			elif res is Mesh:
				var mesh_instance := MeshInstance3D.new()
				mesh_instance.mesh = res
				return mesh_instance
	return null

func _add_attachment_gizmos(attachment_root: Node3D) -> void:
	var existing = attachment_root.get_node_or_null("AttachmentGizmos")
	if existing != null:
		existing.queue_free()

	var gizmo_root = Node3D.new()
	gizmo_root.name = "AttachmentGizmos"
	attachment_root.add_child(gizmo_root)
	
	var create_handle := func(name: String, color: Color, size: Vector3, pos: Vector3) -> Area3D:
		var area := Area3D.new()
		area.name = name
		area.position = pos
		area.input_ray_pickable = true
		area.collision_layer = 1
		area.collision_mask = 0
		area.set_meta("is_gizmo", true)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size + Vector3(0.2, 0.2, 0.2)
		col.shape = shape
		area.add_child(col)
		var mesh_inst := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_inst.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.set_surface_override_material(0, mat)
		area.add_child(mesh_inst)
		return area
	
	gizmo_root.add_child(create_handle.call("GizmoX", Color.RED, Vector3(0.8, 0.1, 0.1), Vector3(0.8, 0, 0)))
	gizmo_root.add_child(create_handle.call("GizmoY", Color.GREEN, Vector3(0.1, 0.8, 0.1), Vector3(0, 0.8, 0)))
	gizmo_root.add_child(create_handle.call("GizmoZ", Color.BLUE, Vector3(0.1, 0.1, 0.8), Vector3(0, 0, 0.8)))
	gizmo_root.add_child(create_handle.call("GizmoScale", Color.YELLOW, Vector3(0.25, 0.25, 0.25), Vector3(0, 0, 0)))

func _avatar_item_model_data_from_entry(model_entry: Dictionary) -> Dictionary:
	var candidates: Array = [model_entry]
	for key in ["data", "model_data", "asset_data", "metadata", "source", "payload", "model", "asset", "record", "row"]:
		if model_entry.has(key):
			candidates.append(model_entry.get(key))
	var selected: Dictionary = {}
	for candidate in candidates:
		var nested_dict := _dictionary_from_jsonish_variant(candidate)
		if nested_dict.is_empty():
			continue
		if not _avatar_item_extract_parts_from_model_data(nested_dict).is_empty():
			selected = nested_dict.duplicate(true)
			break
		for nested_key in ["data", "model_data", "asset_data", "metadata", "source", "payload", "model", "asset", "record", "row"]:
			if not nested_dict.has(nested_key):
				continue
			var nested_value := _dictionary_from_jsonish_variant(nested_dict.get(nested_key))
			if not _avatar_item_extract_parts_from_model_data(nested_value).is_empty():
				selected = nested_value.duplicate(true)
				break
		if not selected.is_empty():
			break
	if selected.is_empty():
		selected = {
			"parts": [{
				"name": str(model_entry.get("name", "Imported Model")),
				"kind": "ImportedPlaceholder",
				"position": [0.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.0, 0.65, 1.0],
				"color": "ffb347"
			}]
		}
	for transport_key in [
		"source_url",
		"source_file_url",
		"source_model_path",
		"canonical_source_model_path",
		"source_file_name",
		"source_model_transform",
		"canonical_transform_baked",
		"thumbnail",
		"preview_thumbnail",
		"preview_thumbnail_path"
	]:
		if selected.has(transport_key) and not str(selected.get(transport_key, "")).strip_edges().is_empty():
			continue
		var transport_value: Variant = _find_model_entry_value(model_entry, transport_key)
		if transport_value != null and not str(transport_value).strip_edges().is_empty():
			selected[transport_key] = transport_value
	return selected

func _find_model_entry_value(model_entry: Dictionary, key_name: String) -> Variant:
	var queue: Array = [model_entry]
	var visited: Dictionary = {}
	while not queue.is_empty() and visited.size() < 32:
		var value: Variant = queue.pop_front()
		var data := _dictionary_from_jsonish_variant(value)
		if data.is_empty():
			continue
		var signature := JSON.stringify(data)
		if visited.has(signature):
			continue
		visited[signature] = true
		if data.has(key_name):
			var result: Variant = data.get(key_name)
			if result != null and not str(result).strip_edges().is_empty():
				return result
		for nested_key in ["data", "model_data", "asset_data", "metadata", "source", "payload", "model", "asset", "record", "row"]:
			if data.has(nested_key):
				queue.append(data.get(nested_key))
	return null

func _model_transport_value_present(value: Variant) -> bool:
	if value == null:
		return false
	if value is String:
		return not str(value).strip_edges().is_empty()
	if value is Dictionary:
		return not (value as Dictionary).is_empty()
	if value is Array:
		return not (value as Array).is_empty()
	return true

func _avatar_item_extract_parts_from_model_data(model_data: Dictionary) -> Array:
	for key in ["parts", "model_parts", "serialized_parts", "blocks", "objects", "nodes", "children"]:
		var candidate: Variant = model_data.get(key, [])
		if candidate is Array:
			var candidate_array := candidate as Array
			var result: Array = []
			for part_variant in candidate_array:
				if part_variant is Dictionary:
					result.append(part_variant)
				elif part_variant is String:
					var parsed_part := _dictionary_from_jsonish_variant(part_variant)
					if not parsed_part.is_empty():
						result.append(parsed_part)
			if not result.is_empty():
				return result
	for nested_key in ["data", "model_data", "asset_data", "metadata", "model", "asset", "source", "payload", "record", "row"]:
		if not model_data.has(nested_key):
			continue
		var nested_dict := _dictionary_from_jsonish_variant(model_data.get(nested_key))
		if nested_dict.is_empty():
			continue
		var nested_parts := _avatar_item_extract_parts_from_model_data(nested_dict)
		if not nested_parts.is_empty():
			return nested_parts
	return []

func _recenter_avatar_item_attachment_parts(attachment_root: Node3D) -> void:
	if attachment_root == null:
		return
	var bounds := AABB()
	var has_bounds := false
	var meshes: Array[MeshInstance3D] = []
	_collect_avatar_item_preview_meshes(attachment_root, meshes)
	if not meshes.is_empty():
		for mesh_instance in meshes:
			var mesh_bounds := _avatar_item_preview_mesh_aabb_in_space(attachment_root, mesh_instance)
			if mesh_bounds.size.length_squared() <= 0.0001:
				continue
			bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
			has_bounds = true
	else:
		for child in attachment_root.get_children():
			if not (child is Node3D):
				continue
			var part := child as Node3D
			var part_scale := Vector3(absf(part.scale.x), absf(part.scale.y), absf(part.scale.z))
			var part_bounds := AABB(part.position - part_scale * 0.5, part_scale)
			bounds = part_bounds if not has_bounds else bounds.merge(part_bounds)
			has_bounds = true
	if not has_bounds:
		return
	var center := bounds.get_center()
	var max_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var preview_scale := 1.0
	if max_axis > 2.2:
		preview_scale = 2.2 / max_axis
	for child in attachment_root.get_children():
		if child is Node3D:
			var part := child as Node3D
			part.position = (part.position - center) * preview_scale
			part.scale *= preview_scale

func _collect_avatar_item_preview_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_avatar_item_preview_meshes(child, meshes)

func _apply_avatar_item_source_fallback_colors(loaded_model: Node, fallback_parts: Array) -> void:
	if loaded_model == null or fallback_parts.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_avatar_item_preview_meshes(loaded_model, meshes)
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
		if part_data.is_empty() or not _avatar_item_part_has_color(part_data):
			continue
		var surface_count := maxi(1, mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1)
		for surface_index in range(surface_count):
			if not _avatar_item_surface_needs_fallback_color(mesh_instance, surface_index):
				continue
			var fallback_color: Variant = _avatar_item_part_surface_color_value(part_data, surface_index)
			mesh_instance.set_surface_override_material(surface_index, _avatar_item_preview_material(_avatar_item_color_to_html(fallback_color)))

func _avatar_item_mesh_needs_fallback_color(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var surface_count := maxi(1, mesh_instance.mesh.get_surface_count())
	for surface_index in range(surface_count):
		if not _avatar_item_surface_needs_fallback_color(mesh_instance, surface_index):
			return false
	return true

func _avatar_item_surface_needs_fallback_color(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var material: Material = mesh_instance.get_active_material(surface_index)
	if material is BaseMaterial3D:
		var base_material := material as BaseMaterial3D
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
	return material == null

func _avatar_item_part_has_color(part_data: Dictionary) -> bool:
	for key in ["color", "Color", "Color3", "Color3uint8", "BrickColor", "BrickColorId", "brick_color", "colour", "albedo", "albedo_color", "modulate"]:
		if part_data.has(key) and not str(part_data.get(key, "")).strip_edges().is_empty():
			return true
	for surface_variant in part_data.get("surface_materials", []):
		if surface_variant is Dictionary and (surface_variant as Dictionary).has("color"):
			return true
	return false

func _avatar_item_part_surface_color_value(part_data: Dictionary, surface_index: int) -> Variant:
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
	return _avatar_item_part_color_value(part_data)

func _avatar_item_part_color_value(part_data: Dictionary) -> Variant:
	for key in ["color", "Color", "Color3", "Color3uint8", "colour", "albedo", "albedo_color", "modulate"]:
		if part_data.has(key):
			return part_data.get(key)
	for key in ["BrickColor", "BrickColorId", "brick_color"]:
		if part_data.has(key):
			return RbxlMaterialCache.roblox_brick_color_to_color(part_data.get(key))
	return "ffffff"

func _avatar_item_preview_mesh_aabb_in_space(space_root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	if space_root == null or mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var mesh_aabb := mesh_instance.get_aabb()
	var points := [
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
	for local_point in points:
		var point: Vector3 = to_space * (mesh_instance.global_transform * local_point)
		var point_bounds := AABB(point, Vector3.ZERO)
		bounds = point_bounds if not has_point else bounds.merge(point_bounds)
		has_point = true
	return bounds

func _dictionary_from_jsonish_variant(value: Variant) -> Dictionary:
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

func _avatar_item_normalize_part(part_data: Dictionary) -> Dictionary:
	var normalized := part_data.duplicate(true)
	var kind := str(normalized.get("kind", normalized.get("shape", normalized.get("type", "Block"))))
	normalized["kind"] = _avatar_item_shape_to_kind(kind)
	if not normalized.has("position"):
		normalized["position"] = normalized.get("pos", normalized.get("translation", [0.0, 0.0, 0.0]))
	if not normalized.has("rotation_degrees"):
		normalized["rotation_degrees"] = normalized.get("rotation", normalized.get("rotation_deg", [0.0, 0.0, 0.0]))
	if not normalized.has("scale"):
		normalized["scale"] = normalized.get("size", [1.0, 1.0, 1.0])
	normalized["color"] = _avatar_item_color_to_html(_avatar_item_part_color_value(normalized))
	return normalized

func _avatar_item_shape_to_kind(kind: String) -> String:
	var clean := kind.strip_edges().to_lower()
	match clean:
		"sphere", "ball":
			return "Sphere"
		"cylinder", "tube":
			return "Cylinder"
		"ramp", "wedge", "prism":
			return "Ramp"
		"importedmeshpart", "importedmesh", "importedscene", "importedplaceholder":
			return "ImportedMeshPart"
		"box", "part", "block":
			return "Block"
		_:
			return "Block"

func _avatar_item_color_to_html(value: Variant) -> String:
	if value is Color:
		return (value as Color).to_html(false)
	if value is String:
		var clean := (value as String).strip_edges()
		if clean.begins_with("#"):
			clean = clean.substr(1)
		if clean.length() == 6 or clean.length() == 8:
			return clean
	if value is Array:
		var arr := value as Array
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
		return Color(r, g, b, a).to_html(false)
	if value is Dictionary:
		var dict := value as Dictionary
		var r := float(dict.get("r", dict.get("R", dict.get("x", dict.get("X", 1.0)))))
		var g := float(dict.get("g", dict.get("G", dict.get("y", dict.get("Y", 1.0)))))
		var b := float(dict.get("b", dict.get("B", dict.get("z", dict.get("Z", 1.0)))))
		var a := float(dict.get("a", dict.get("A", 1.0)))
		if maxf(r, maxf(g, b)) > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		var color := Color(r, g, b, a)
		return color.to_html(false)
	return "ffffff"

func _create_avatar_item_preview_part(part_data: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = str(part_data.get("name", "AttachmentPart")).strip_edges()
	if node.name.is_empty():
		node.name = "AttachmentPart"
	node.position = _avatar_item_vector3_from_variant(part_data.get("position", []), Vector3.ZERO)
	node.rotation_degrees = _avatar_item_vector3_from_variant(part_data.get("rotation_degrees", []), Vector3.ZERO)
	node.scale = _avatar_item_vector3_from_variant(part_data.get("scale", []), Vector3.ONE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _avatar_item_mesh_for_kind(str(part_data.get("kind", "Block")))
	mesh_instance.set_surface_override_material(0, _avatar_item_preview_material(_avatar_item_color_to_html(_avatar_item_part_color_value(part_data))))
	node.add_child(mesh_instance)
	return node

func _avatar_item_mesh_for_kind(kind: String) -> Mesh:
	match kind:
		"Sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			return sphere
		"Cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			return cylinder
		"Ramp":
			return PrismMesh.new()
		"ImportedMeshPart", "ImportedPlaceholder", "ImportedMesh", "ImportedScene", "Block", "Box", "Part":
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box

func _avatar_item_preview_material(color_html: String) -> StandardMaterial3D:
	var preview_material := StandardMaterial3D.new()
	var clean_color := color_html.strip_edges()
	if clean_color.begins_with("#"):
		clean_color = clean_color.substr(1)
	if clean_color.length() != 6 and clean_color.length() != 8:
		clean_color = "ffffff"
	preview_material.albedo_color = Color.html(clean_color)
	preview_material.emission_enabled = true
	preview_material.emission = Color.html(clean_color).lightened(0.12)
	preview_material.emission_energy_multiplier = 0.18
	preview_material.roughness = 0.72
	return preview_material

func _avatar_item_vector3_from_variant(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var array_value := value as Array
		return Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))
	if value is Dictionary:
		var dict_value := value as Dictionary
		return Vector3(float(dict_value.get("x", fallback.x)), float(dict_value.get("y", fallback.y)), float(dict_value.get("z", fallback.z)))
	return fallback

func _avatar_item_slot_position(slot_name: String) -> Vector3:
	match slot_name:
		"Head":
			return Vector3(0.0, 5.2, 0.0)
		"Torso":
			return Vector3(0.0, 3.0, 0.0)
		"LeftArm":
			return Vector3(-1.5, 3.0, 0.0)
		"RightArm":
			return Vector3(1.5, 3.0, 0.0)
		"LeftLeg":
			return Vector3(-0.5, 1.0, 0.0)
		"RightLeg":
			return Vector3(0.5, 1.0, 0.0)
		"Back":
			return Vector3(0.0, 3.0, 0.72)
		_:
			return Vector3(0.0, 5.2, 0.0)

func _create_avatar_item_vector3_row(label_text: String, value: Vector3, minimum: Vector3, maximum: Vector3, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % label_text
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(86, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18))
	row.add_child(label)
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.name = axis
		spin.custom_minimum_size = Vector2(86, 32)
		spin.step = step
		spin.min_value = _avatar_item_axis_value(minimum, axis)
		spin.max_value = _avatar_item_axis_value(maximum, axis)
		spin.value = _avatar_item_axis_value(value, axis)
		row.add_child(spin)
	return row

func _avatar_item_axis_value(vector: Vector3, axis: String) -> float:
	match axis:
		"X":
			return vector.x
		"Y":
			return vector.y
		"Z":
			return vector.z
		_:
			return 0.0

func _read_avatar_item_vector3_row(row: Node, fallback: Vector3) -> Vector3:
	if row == null:
		return fallback
	var x_spin := row.get_node_or_null("X") as SpinBox
	var y_spin := row.get_node_or_null("Y") as SpinBox
	var z_spin := row.get_node_or_null("Z") as SpinBox
	if x_spin == null or y_spin == null or z_spin == null:
		return fallback
	return Vector3(float(x_spin.value), float(y_spin.value), float(z_spin.value))

func _connect_vector3_row_changed(row: Node, target: Callable) -> void:
	if row == null:
		return
	for axis in ["X", "Y", "Z"]:
		var spin := row.get_node_or_null(axis) as SpinBox
		if spin != null:
			spin.value_changed.connect(target)

func _vector3_to_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]

func _create_catalog_tab_panel(tab_name: String) -> Panel:
	var panel := Panel.new()
	panel.name = tab_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.07, 0.076, 0.092, 1), Color(0.18, 0.19, 0.23, 1), 4))
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	return panel

func _load_local_model_draft_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var draft_root: String = _get_model_drafts_root_path()
	var global_root: String = ProjectSettings.globalize_path(draft_root)
	if not DirAccess.dir_exists_absolute(global_root):
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
		var draft_path := draft_root.path_join(file_name)
		var entry := _read_json_dictionary(draft_path)
		if entry.is_empty():
			continue
		entry["draft_path"] = draft_path
		result.append(entry)
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("created_at", "")) > str(b.get("created_at", ""))
	)
	return result

func _create_cloud_place_catalog_card(map_entry: Dictionary) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(250, 245)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.095, 0.104, 0.126, 1), Color(0.22, 0.235, 0.27, 1), 6))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var game_info := {
		"map_id": str(map_entry.get("id", map_entry.get("map_id", ""))).strip_edges(),
		"name": str(map_entry.get("name", "Untitled Experience")).strip_edges(),
		"description": str(map_entry.get("description", "")).strip_edges(),
		"thumbnail": str(map_entry.get("thumbnail", "")).strip_edges(),
		"cloud_version_id": str(map_entry.get("cloud_version_id", "")).strip_edges(),
		"owner_id": str(map_entry.get("owner_id", "")).strip_edges(),
		"owner_name": str(map_entry.get("owner_name", UserSession.username)).strip_edges(),
		"active_players": int(map_entry.get("active_players", 0))
	}

	var icon_widget := _create_game_icon_widget(game_info)
	icon_widget.custom_minimum_size = Vector2(0, 96)
	root.add_child(icon_widget)

	var title := Label.new()
	title.text = str(game_info.get("name", "Untitled Experience"))
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.965, 0.98, 1))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(title)

	var details := Label.new()
	details.text = "%s · %d visits · %d like(s)" % [
		str(map_entry.get("visibility", "public")).capitalize(),
		int(map_entry.get("visits_count", 0)),
		int(map_entry.get("likes_count", 0))
	]
	details.add_theme_font_size_override("font_size", 12)
	details.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74, 1))
	root.add_child(details)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	root.add_child(actions)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(0, 32)
	_style_creator_button(play_btn, true)
	play_btn.pressed.connect(func() -> void:
		_start_smart_play_for_game(game_info)
	)
	actions.add_child(play_btn)

	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size = Vector2(0, 32)
	_style_creator_button(edit_btn)
	edit_btn.pressed.connect(func() -> void:
		await _open_cloud_place_for_edit(game_info)
	)
	actions.add_child(edit_btn)

	var visibility_btn := Button.new()
	visibility_btn.text = "Private" if str(map_entry.get("visibility", "public")).to_lower() == "private" else "Public"
	visibility_btn.custom_minimum_size = Vector2(0, 32)
	_style_creator_button(visibility_btn)
	visibility_btn.pressed.connect(func() -> void:
		var map_id := str(game_info.get("map_id", "")).strip_edges()
		if map_id.is_empty():
			return
		var next_visibility := "private" if visibility_btn.text == "Public" else "public"
		visibility_btn.disabled = true
		var result: Dictionary = await CloudAPI.update_catalog_asset_visibility("map", map_id, next_visibility)
		if bool(result.get("ok", false)):
			visibility_btn.text = "Private" if next_visibility == "private" else "Public"
		visibility_btn.disabled = false
	)
	actions.add_child(visibility_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.custom_minimum_size = Vector2(0, 32)
	_style_creator_button(delete_btn, false, true)
	delete_btn.pressed.connect(func() -> void:
		await _delete_cloud_place_from_catalog(game_info)
	)
	actions.add_child(delete_btn)

	return card

func _open_cloud_place_for_edit(game_info: Dictionary) -> void:
	var map_id := str(game_info.get("map_id", "")).strip_edges()
	if map_id.is_empty() or CloudAPI == null:
		return
	var cloud_version_id := str(game_info.get("cloud_version_id", "")).strip_edges()
	var map_name := str(game_info.get("name", "Cloud Place")).strip_edges()
	var cache_result: Dictionary = await CloudAPI.download_map_with_cache(map_id, cloud_version_id, map_name)
	if not bool(cache_result.get("ok", false)):
		push_warning("[Lobby] Could not open cloud place for edit: %s" % str(cache_result.get("error", "Unknown error")))
		return
	var folder := str(cache_result.get("folder", "")).strip_edges()
	if folder.is_empty():
		return
	GameState.selected_map_folder = folder
	get_tree().change_scene_to_file("res://scenes/place_editor/studio.tscn")

func _delete_cloud_place_from_catalog(game_info: Dictionary) -> void:
	var map_id := str(game_info.get("map_id", "")).strip_edges()
	var map_name := str(game_info.get("name", "")).strip_edges()
	if map_id.is_empty() or CloudAPI == null:
		return
	var delete_result: Dictionary = await CloudAPI.delete_map_and_cleanup(map_id) if CloudAPI.has_method("delete_map_and_cleanup") else await CloudAPI.delete_map(map_id)
	if not bool(delete_result.get("ok", false)):
		push_warning("[Lobby] Cloud place delete failed for '%s': %s" % [map_id, str(delete_result.get("error", "Unknown error"))])
		return
	UserSession.mark_deleted_game(map_id, map_name)
	_published_map_ids_cache.erase(map_id)
	_local_game_icon_path_cache.erase(map_id)
	_remove_map_from_lobby_cache(map_id, map_name)
	_show_my_creations_page()

func _remove_map_from_lobby_cache(map_id: String, map_name: String) -> void:
	var cache := _read_json_dictionary(LOBBY_PUBLISHED_MAP_CACHE_PATH)
	if cache.is_empty():
		return
	var clean_id := map_id.strip_edges().to_lower()
	var clean_name := _normalize_map_name_key(map_name)
	var filtered: Array = []
	for record_variant in cache.get("maps", []):
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		var record_id := str(record.get("id", record.get("map_id", ""))).strip_edges().to_lower()
		var record_name := _normalize_map_name_key(str(record.get("name", "")))
		if (not clean_id.is_empty() and record_id == clean_id) or (not clean_name.is_empty() and record_name == clean_name):
			continue
		filtered.append(record.duplicate(true))
	cache["maps"] = filtered
	cache["saved_at_unix"] = int(Time.get_unix_time_from_system())
	_write_json_dictionary(LOBBY_PUBLISHED_MAP_CACHE_PATH, cache)

func _create_model_draft_row(model_entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 154)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.095, 0.104, 0.126, 1), Color(0.22, 0.235, 0.27, 1), 6))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var preview_panel := Panel.new()
	preview_panel.custom_minimum_size = Vector2(104, 104)
	preview_panel.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.96, 0.965, 0.975, 1), Color(0.28, 0.30, 0.34, 1), 5))
	row.add_child(preview_panel)
	var thumbnail_path := _resolve_model_catalog_thumbnail(model_entry)
	if not thumbnail_path.is_empty():
		CatalogBuilder._apply_item_thumbnail_async(self, thumbnail_path, preview_panel)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)
	var title := Label.new()
	title.text = str(model_entry.get("name", model_entry.get("draft_id", "Model Draft"))).strip_edges()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.96, 0.965, 0.98, 1))
	title_box.add_child(title)
	var details := Label.new()
	var model_data := _avatar_item_model_data_from_entry(model_entry)
	var part_count := _avatar_item_extract_parts_from_model_data(model_data).size()
	var source_path := str(model_data.get("canonical_source_model_path", model_data.get("source_model_path", ""))).strip_edges()
	var state_text := "Published" if not _model_cloud_id(model_entry).is_empty() else "Local draft"
	details.text = "%s\n%d part(s)%s" % [
		state_text,
		part_count,
		"\n%s" % source_path.get_file() if not source_path.is_empty() else ""
	]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 12)
	details.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74, 1))
	title_box.add_child(details)
	var author := Label.new()
	author.text = "by %s" % str(model_entry.get("owner_username", model_entry.get("owner_name", UserSession.username))).strip_edges()
	author.clip_text = true
	author.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	author.add_theme_font_size_override("font_size", 11)
	author.add_theme_color_override("font_color", Color(0.55, 0.59, 0.66, 1))
	title_box.add_child(author)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("separation", 6)
	title_box.add_child(actions)
	var open_btn := Button.new()
	open_btn.text = "Open"
	open_btn.custom_minimum_size = Vector2(64, 30)
	_style_creator_button(open_btn, true)
	open_btn.disabled = source_path.is_empty() or not FileAccess.file_exists(source_path)
	open_btn.pressed.connect(func() -> void:
		_open_model_editor_page(source_path)
	)
	actions.add_child(open_btn)
	var visibility_btn := Button.new()
	visibility_btn.text = "Private" if str(model_entry.get("visibility", "public")).to_lower() == "private" else "Public"
	visibility_btn.custom_minimum_size = Vector2(70, 30)
	_style_creator_button(visibility_btn)
	visibility_btn.disabled = _model_cloud_id(model_entry).is_empty()
	visibility_btn.pressed.connect(func() -> void:
		var model_id := _model_cloud_id(model_entry)
		if model_id.is_empty():
			return
		var next_visibility := "private" if visibility_btn.text == "Public" else "public"
		visibility_btn.disabled = true
		var result: Dictionary = await CloudAPI.update_catalog_asset_visibility("model", model_id, next_visibility)
		if bool(result.get("ok", false)):
			visibility_btn.text = "Private" if next_visibility == "private" else "Public"
		visibility_btn.disabled = false
	)
	actions.add_child(visibility_btn)
	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.custom_minimum_size = Vector2(64, 30)
	_style_creator_button(delete_btn, false, true)
	delete_btn.pressed.connect(func() -> void:
		delete_btn.disabled = true
		var deleted := await _delete_model_catalog_entry(model_entry)
		if not deleted and is_instance_valid(delete_btn):
			delete_btn.disabled = false
	)
	actions.add_child(delete_btn)
	return panel

func _delete_model_catalog_entry(model_entry: Dictionary) -> bool:
	var cloud_id := _model_cloud_id(model_entry)
	if not cloud_id.is_empty():
		var cloud_result: Dictionary = await CloudAPI.delete_model_asset(cloud_id) if CloudAPI.has_method("delete_model_asset") else {"ok": false, "error": "Delete model API unavailable."}
		if not bool(cloud_result.get("ok", false)):
			push_warning("[Lobby] Model delete failed for '%s': %s" % [cloud_id, str(cloud_result.get("error", "Unknown error"))])
			return false
	_remove_matching_local_model_drafts(model_entry)
	_show_my_creations_page()
	return true

func _model_cloud_id(model_entry: Dictionary) -> String:
	var cloud_id := str(model_entry.get("cloud_model_id", "")).strip_edges()
	if not cloud_id.is_empty():
		return cloud_id
	if str(model_entry.get("publish_state", "")).strip_edges().to_lower() == "cloud":
		return str(model_entry.get("id", "")).strip_edges()
	return ""

func _model_entry_identity(model_entry: Dictionary) -> String:
	var cloud_id := _model_cloud_id(model_entry)
	if not cloud_id.is_empty():
		return "cloud:%s" % cloud_id
	var draft_id := str(model_entry.get("draft_id", model_entry.get("id", ""))).strip_edges()
	if not draft_id.is_empty():
		return "draft:%s" % draft_id
	var name := str(model_entry.get("name", "")).strip_edges().to_lower()
	return "name:%s" % name if not name.is_empty() else ""

func _resolve_model_catalog_thumbnail(model_entry: Dictionary) -> String:
	for key in ["thumbnail", "thumbnail_url", "preview_thumbnail_path", "preview_thumbnail", "thumbnail_path", "preview_path", "icon_path"]:
		var value: Variant = _find_model_entry_value(model_entry, key)
		if _model_transport_value_present(value):
			var candidate := str(value).strip_edges()
			if not candidate.is_empty() and candidate != "<null>":
				return candidate
	return ""

func _find_matching_model_draft_path(model_data: Dictionary) -> String:
	var draft_id := str(model_data.get("draft_id", "")).strip_edges()
	if not draft_id.is_empty():
		var direct_path := _get_model_drafts_root_path().path_join(draft_id + ".json")
		if FileAccess.file_exists(direct_path):
			return direct_path
	var target_cloud_id := str(model_data.get("cloud_model_id", "")).strip_edges()
	var target_source := _model_draft_source_identity(model_data)
	var target_fingerprint := _model_draft_fingerprint(model_data)
	for existing in _load_local_model_draft_entries():
		var existing_path := str(existing.get("draft_path", "")).strip_edges()
		if existing_path.is_empty():
			continue
		var existing_cloud_id := str(existing.get("cloud_model_id", "")).strip_edges()
		if not target_cloud_id.is_empty() and existing_cloud_id == target_cloud_id:
			return existing_path
		if not target_source.is_empty() and _model_draft_source_identity(existing) == target_source:
			return existing_path
		if not target_fingerprint.is_empty() and _model_draft_fingerprint(existing) == target_fingerprint:
			return existing_path
	return ""

func _remove_matching_local_model_drafts(model_entry: Dictionary) -> void:
	var target_path := str(model_entry.get("draft_path", "")).strip_edges()
	var target_cloud_id := _model_cloud_id(model_entry)
	var target_source := _model_draft_source_identity(model_entry)
	var target_fingerprint := _model_draft_fingerprint(model_entry)
	for existing in _load_local_model_draft_entries():
		var existing_path := str(existing.get("draft_path", "")).strip_edges()
		if existing_path.is_empty():
			continue
		var matches := existing_path == target_path and not target_path.is_empty()
		if not matches and not target_cloud_id.is_empty():
			matches = str(existing.get("cloud_model_id", "")).strip_edges() == target_cloud_id
		if not matches and not target_source.is_empty():
			matches = _model_draft_source_identity(existing) == target_source
		if not matches and not target_fingerprint.is_empty():
			matches = _model_draft_fingerprint(existing) == target_fingerprint
		if matches and FileAccess.file_exists(existing_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(existing_path))

func _model_draft_source_identity(model_data: Dictionary) -> String:
	for key in ["original_source_model_path", "canonical_source_model_path", "source_model_path", "source_url", "source_file_url"]:
		var candidate := str(_find_model_entry_value(model_data, key)).strip_edges()
		if candidate.is_empty() or candidate == "<null>":
			continue
		return candidate.replace("\\", "/").to_lower().md5_text()
	return ""

func _model_draft_fingerprint(model_data: Dictionary) -> String:
	var normalized := _avatar_item_model_data_from_entry(model_data)
	var parts: Array = _avatar_item_extract_parts_from_model_data(normalized)
	if parts.is_empty():
		return ""
	return JSON.stringify(parts).md5_text()

func _create_avatar_item_catalog_row(item_entry: Dictionary) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 72)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)
	var title := Label.new()
	title.text = str(item_entry.get("name", "Avatar Item")).strip_edges()
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.14, 0.14, 0.14))
	title_box.add_child(title)
	var details := Label.new()
	details.text = "%s В· %s like(s)" % [str(item_entry.get("visibility", "public")), str(item_entry.get("likes_count", 0))]
	details.add_theme_font_size_override("font_size", 12)
	details.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	title_box.add_child(details)
	var like_btn := Button.new()
	like_btn.text = "Like"
	like_btn.custom_minimum_size = Vector2(80, 34)
	like_btn.pressed.connect(func() -> void:
		CloudAPI.like_catalog_asset("avatar_item", str(item_entry.get("id", "")))
	)
	row.add_child(like_btn)
	var get_btn := Button.new()
	var item_id := str(item_entry.get("id", "")).strip_edges()
	var is_owned := UserSession.inventory_items is Array and UserSession.inventory_items.has(item_id)
	get_btn.text = "Owned" if is_owned else "Get"
	get_btn.disabled = is_owned
	get_btn.custom_minimum_size = Vector2(74, 34)
	get_btn.pressed.connect(func() -> void:
		get_btn.disabled = true
		var result: Dictionary = await CloudAPI.get_catalog_item(item_id, "avatar_item")
		if bool(result.get("ok", false)):
			get_btn.text = "Owned"
			if UserSession.inventory_items is Array and not UserSession.inventory_items.has(item_id):
				UserSession.inventory_items.append(item_id)
				await CloudAPI.update_profile_avatar(UserSession.avatar_data, UserSession.inventory_items)
		else:
			get_btn.text = "Retry"
			get_btn.disabled = false
	)
	row.add_child(get_btn)
	var visibility_btn := Button.new()
	visibility_btn.text = "Private" if str(item_entry.get("visibility", "public")).to_lower() == "private" else "Public"
	visibility_btn.custom_minimum_size = Vector2(92, 34)
	visibility_btn.pressed.connect(func() -> void:
		if item_id.is_empty():
			return
		var next_visibility := "private" if visibility_btn.text == "Public" else "public"
		visibility_btn.disabled = true
		var result: Dictionary = await CloudAPI.update_catalog_asset_visibility("avatar_item", item_id, next_visibility)
		if bool(result.get("ok", false)):
			visibility_btn.text = "Private" if next_visibility == "private" else "Public"
		visibility_btn.disabled = false
	)
	row.add_child(visibility_btn)
	return panel

func _create_avatar_item_catalog_card(item_entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(170, 260)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.095, 0.104, 0.126, 1), Color(0.22, 0.235, 0.27, 1), 6))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var preview_panel := Panel.new()
	preview_panel.custom_minimum_size = Vector2(154, 130)
	preview_panel.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.96, 0.965, 0.975, 1), Color(0.28, 0.30, 0.34, 1), 5))
	box.add_child(preview_panel)
	var thumbnail_path := _resolve_avatar_item_catalog_thumbnail(item_entry)
	if not thumbnail_path.is_empty():
		CatalogBuilder._apply_item_thumbnail_async(self, thumbnail_path, preview_panel)
	var title := Label.new()
	title.text = str(item_entry.get("name", "Avatar Item")).strip_edges()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(154, 28)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.96, 0.965, 0.98, 1))
	box.add_child(title)
	var details := Label.new()
	var item_kind := _resolve_avatar_item_catalog_kind(item_entry)
	details.text = "%s · %s like(s)" % [item_kind.capitalize(), str(item_entry.get("likes_count", 0))]
	details.clip_text = true
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74, 1))
	box.add_child(details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	var item_id := str(item_entry.get("id", item_entry.get("item_id", ""))).strip_edges()
	var visibility_btn := Button.new()
	visibility_btn.text = "Private" if str(item_entry.get("visibility", "public")).to_lower() == "private" else "Public"
	visibility_btn.custom_minimum_size = Vector2(74, 32)
	_style_creator_button(visibility_btn)
	visibility_btn.pressed.connect(func() -> void:
		if item_id.is_empty():
			return
		var next_visibility := "private" if visibility_btn.text == "Public" else "public"
		visibility_btn.disabled = true
		var result: Dictionary = await CloudAPI.update_catalog_asset_visibility("avatar_item", item_id, next_visibility)
		if bool(result.get("ok", false)):
			visibility_btn.text = "Private" if next_visibility == "private" else "Public"
		visibility_btn.disabled = false
	)
	actions.add_child(visibility_btn)
	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.custom_minimum_size = Vector2(74, 32)
	_style_creator_button(delete_btn, false, true)
	delete_btn.pressed.connect(func() -> void:
		if item_id.is_empty() or CloudAPI == null:
			return
		delete_btn.disabled = true
		var result: Dictionary = await CloudAPI.delete_avatar_item(item_id) if CloudAPI.has_method("delete_avatar_item") else {"ok": false, "error": "Delete API unavailable"}
		if bool(result.get("ok", false)):
			_remove_avatar_item_from_local_session(item_id)
			_show_my_creations_page()
		else:
			push_warning("[Lobby] Avatar item delete failed for '%s': %s" % [item_id, str(result.get("error", "Unknown error"))])
			delete_btn.disabled = false
	)
	actions.add_child(delete_btn)
	return panel

func _resolve_avatar_item_catalog_thumbnail(item_entry: Dictionary) -> String:
	for source in [item_entry, _dictionary_from_jsonish_variant(item_entry.get("data", {})), _dictionary_from_jsonish_variant(item_entry.get("metadata", {})), _dictionary_from_jsonish_variant(item_entry.get("model_data", {}))]:
		if not (source is Dictionary):
			continue
		var source_dict := source as Dictionary
		for key in ["thumbnail", "thumbnail_url", "thumbnail_path", "preview_path", "texture_path", "template_url", "atlas_path", "source_url", "image_path", "icon_path"]:
			var candidate := str(source_dict.get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
	return ""

func _resolve_avatar_item_catalog_kind(item_entry: Dictionary) -> String:
	var data := _dictionary_from_jsonish_variant(item_entry.get("data", {}))
	for source in [item_entry, data]:
		if not (source is Dictionary):
			continue
		var source_dict := source as Dictionary
		for key in ["item_kind", "category", "kind", "type"]:
			var candidate := str(source_dict.get(key, "")).strip_edges().to_lower()
			if not candidate.is_empty() and candidate not in ["avatar_item", "avatar_items", "item"]:
				return candidate
	return "model"

func _remove_avatar_item_from_local_session(item_id: String) -> void:
	var clean_id := item_id.strip_edges()
	if clean_id.is_empty() or typeof(UserSession) == TYPE_NIL:
		return
	if UserSession.inventory_items is Array:
		UserSession.inventory_items.erase(clean_id)
	if UserSession.avatar_data is Dictionary:
		var equipped: Array = UserSession.avatar_data.get("equipped", []) if UserSession.avatar_data.get("equipped", []) is Array else []
		equipped.erase(clean_id)
		UserSession.avatar_data["equipped"] = equipped
		for list_key in ["owned_avatar_item_payloads", "equipped_avatar_item_payloads"]:
			var raw_list: Variant = UserSession.avatar_data.get(list_key, [])
			if not (raw_list is Array):
				continue
			var filtered: Array = []
			for payload in (raw_list as Array):
				if not (payload is Dictionary):
					continue
				var payload_id := str((payload as Dictionary).get("id", (payload as Dictionary).get("item_id", ""))).strip_edges()
				if payload_id != clean_id:
					filtered.append(payload)
			UserSession.avatar_data[list_key] = filtered
		UserSession.apply_avatar_to_game_state()
		UserSession.save_profile()

func _extract_response_array(response: Dictionary) -> Array:
	var data: Variant = response.get("data", [])
	if data is Array:
		return data
	if data is Dictionary:
		for key in ["items", "models", "avatar_items", "data"]:
			var nested: Variant = (data as Dictionary).get(key, [])
			if nested is Array:
				return nested
	return []

func _create_creator_develop_root(develop_view: Control) -> VBoxContainer:
	var surface := PanelContainer.new()
	surface.name = "CreatorWorkspaceSurface"
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.custom_minimum_size = Vector2(0, 560)
	surface.add_theme_stylebox_override("panel", _make_creator_panel_style(Color(0.052, 0.058, 0.071, 1), Color(0.12, 0.13, 0.16, 1), 0))
	develop_view.add_child(surface)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16 if get_viewport_rect().size.x < 760.0 else 32)
	margin.add_theme_constant_override("margin_top", 20 if get_viewport_rect().size.x < 760.0 else 28)
	margin.add_theme_constant_override("margin_right", 16 if get_viewport_rect().size.x < 760.0 else 32)
	margin.add_theme_constant_override("margin_bottom", 34)
	surface.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	return root


func _make_creator_panel_style(background: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


func _style_creator_button(button: Button, primary: bool = false, danger: bool = false) -> void:
	var normal_color := Color(0.11, 0.12, 0.145, 1)
	var border_color := Color(0.25, 0.27, 0.32, 1)
	var hover_color := Color(0.15, 0.165, 0.20, 1)
	if primary:
		normal_color = Color(0.10, 0.46, 0.80, 1)
		border_color = Color(0.14, 0.58, 0.96, 1)
		hover_color = Color(0.13, 0.53, 0.90, 1)
	elif danger:
		normal_color = Color(0.30, 0.095, 0.105, 1)
		border_color = Color(0.70, 0.20, 0.22, 1)
		hover_color = Color(0.40, 0.12, 0.13, 1)
	button.add_theme_stylebox_override("normal", _make_creator_panel_style(normal_color, border_color, 5))
	button.add_theme_stylebox_override("hover", _make_creator_panel_style(hover_color, border_color.lightened(0.10), 5))
	button.add_theme_stylebox_override("pressed", _make_creator_panel_style(normal_color.darkened(0.10), border_color, 5))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func _create_develop_page_header(title_text: String, subtitle_text: String, include_back: bool, dark_mode: bool = false) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 3)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.96, 0.965, 0.98, 1) if dark_mode else Color(0.10, 0.10, 0.10))
	title_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74, 1) if dark_mode else Color(0.42, 0.42, 0.42))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(subtitle)
	if include_back:
		var back_btn := Button.new()
		back_btn.text = "Back"
		back_btn.custom_minimum_size = Vector2(92, 34)
		if dark_mode:
			_style_creator_button(back_btn)
		back_btn.pressed.connect(_show_develop_hub_page)
		header.add_child(back_btn)
	return header

func _get_creation_templates() -> Array[Dictionary]:
	return [
		{"name": "Baseplate", "icon": "BP", "color": Color(0.28, 0.52, 0.35), "desc": "Classic flat baseplate to build on"},
		{"name": "Water World", "icon": "WW", "color": Color(0.15, 0.42, 0.82), "desc": "Ocean with a small island"},
		{"name": "Town", "icon": "TN", "color": Color(0.55, 0.5, 0.35), "desc": "Roads, houses and urban scenery"},
		{"name": "Obby 1", "icon": "O1", "color": Color(0.75, 0.25, 0.18), "desc": "Classic stage obby challenge"},
		{"name": "Obby 2", "icon": "O2", "color": Color(0.15, 0.58, 0.68), "desc": "Parkour obby with platforming"},
		{"name": "Беспредел", "icon": "BP", "color": Color(0.86, 0.22, 0.08), "desc": "Vehicle chaos arena"}
	]

func _create_template_picker_card(template_info: Dictionary, editor_scene_path: String = "res://scenes/place_editor/studio.tscn") -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(240, 214)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = template_info.get("color", Color(0.4, 0.4, 0.4))
	var style := _make_creator_panel_style(Color(0.085, 0.093, 0.115, 1), Color(0.22, 0.235, 0.27, 1), 7)
	style.border_width_top = 4
	style.border_color = accent
	card.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(0, 82)
	preview.add_theme_stylebox_override("panel", _make_creator_panel_style(accent.darkened(0.55), accent.darkened(0.12), 5))
	box.add_child(preview)
	var icon := Label.new()
	icon.text = str(template_info.get("icon", ""))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 30)
	icon.add_theme_color_override("font_color", accent.lightened(0.24))
	preview.add_child(icon)
	var title := Label.new()
	title.text = str(template_info.get("name", "Template"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.96, 0.965, 0.98, 1))
	box.add_child(title)
	var desc := Label.new()
	desc.text = str(template_info.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74, 1))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	var button := Button.new()
	button.text = "Create"
	button.custom_minimum_size = Vector2(0, 34)
	_style_creator_button(button, true)
	var template_name := str(template_info.get("name", "Baseplate"))
	button.pressed.connect(func(): _generate_place_from_template(template_name, editor_scene_path))
	box.add_child(button)
	return card

func _style_home_scroll_surface() -> void:
	var home_scroll := get_node_or_null("Body/HBox/MainTabs/HomeView") as ScrollContainer
	if home_scroll == null:
		return
	home_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	home_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	home_scroll.follow_focus = false
	var vbar := home_scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.modulate = Color(1, 1, 1, 0.0)
		vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _make_white_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 3
	style.border_color = Color(0.82, 0.82, 0.82, 1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.shadow_color = Color(0, 0, 0, 0.04)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style

func _refresh_home_dashboard() -> void:
	if continue_cards_container == null or recommended_cards_grid == null or bobux_creator_cards_grid == null or new_cards_grid == null or all_cards_grid == null:
		return
	_refresh_continue_playing_section()
	if _lobby_bootstrap_active:
		_render_home_startup_skeletons()
		return
	if not _home_friends_refresh_in_flight:
		call_deferred("_refresh_home_friends_section")
	if not _discover_refresh_in_flight:
		call_deferred("_refresh_discover_section")

func _render_home_startup_skeletons() -> void:
	if home_friends_status:
		home_friends_status.text = "Friends will load after sign-in..."
	if home_friends_container != null and home_friends_container.get_child_count() == 0:
		var friend_placeholder := Label.new()
		friend_placeholder.text = "Loading friends in the background..."
		friend_placeholder.add_theme_font_size_override("font_size", 13)
		friend_placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		home_friends_container.add_child(friend_placeholder)
		_queue_home_friends_clip_layout()
	if recommended_cards_grid != null and recommended_cards_grid.get_child_count() == 0:
		_add_grid_placeholder(recommended_cards_grid, "Recommended experiences are warming up...")
	if new_cards_grid != null and new_cards_grid.get_child_count() == 0:
		_add_grid_placeholder(new_cards_grid, "New experiences are loading...")
	if all_cards_grid != null and all_cards_grid.get_child_count() == 0:
		var cached_entries := _get_cached_discover_entries()
		if cached_entries.is_empty():
			_add_grid_placeholder(all_cards_grid, "Published experiences will appear here in a moment.")
		else:
			call_deferred("_render_cached_startup_games", cached_entries, _discover_refresh_token)
	if bobux_creator_cards_grid != null and bobux_creator_cards_grid.get_child_count() == 0:
		_add_creator_placeholder(bobux_creator_cards_grid, "Creator picks are loading...")

func _render_cached_startup_games(cached_entries: Array, refresh_token: int) -> void:
	if not _lobby_bootstrap_active:
		return
	await _render_home_game_sections(cached_entries, refresh_token)

func _refresh_home_friends_section() -> void:
	if home_friends_container == null:
		return
	if _lobby_bootstrap_active:
		_home_friends_refresh_pending = true
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_home_friends_refresh_allowed_msec:
		_home_friends_refresh_pending = false
		return
	if _home_friends_cache_loaded:
		if home_friends_container.get_child_count() == 0:
			_render_home_friend_cards_from_cache()
		elif home_friends_status:
			home_friends_status.text = "%d friends" % _home_friends_cache.size()
		call_deferred("_refresh_home_friend_active_statuses_async")
		return
	# Guard: prevent parallel async execution which caused friend duplication
	if _home_friends_refresh_in_flight:
		_home_friends_refresh_pending = true
		return
	_home_friends_refresh_in_flight = true
	_clear_children_immediate(home_friends_container)
	if home_friends_status:
		home_friends_status.text = "Loading friends..."
	if not CloudAPI.is_configured():
		if home_friends_status:
			home_friends_status.text = "Cloud social disconnected."
		_home_friends_refresh_in_flight = false
		_home_friends_refresh_pending = false
		_next_home_friends_refresh_allowed_msec = Time.get_ticks_msec() + HOME_FRIENDS_FAILURE_RETRY_MS
		return
		
	var server_map_by_user: Dictionary = {}
	if CloudAPI != null and CloudAPI.has_method("fetch_active_servers"):
		var active_servers_result: Dictionary = await CloudAPI.fetch_active_servers("", 64, 2.5, 1)
		if bool(active_servers_result.get("ok", false)):
			server_map_by_user = _build_server_lookup_by_user(CloudAPI._extract_array_payload(active_servers_result.get("data", [])))

	var friends_result: Dictionary = await CloudAPI.get_friends_list()
	if not is_instance_valid(self) or not is_inside_tree():
		_home_friends_refresh_in_flight = false
		return
	if not bool(friends_result.get("ok", false)):
		if home_friends_status:
			home_friends_status.text = "Could not load friends."
		_home_friends_refresh_in_flight = false
		_home_friends_refresh_pending = false
		_next_home_friends_refresh_allowed_msec = Time.get_ticks_msec() + HOME_FRIENDS_FAILURE_RETRY_MS
		return

	var friends: Array = CloudAPI._extract_array_payload(friends_result.get("data", []))
	friends.sort_custom(func(a: Dictionary, b: Dictionary):
		var rank_a: int = _get_friend_presence_rank(a, server_map_by_user)
		var rank_b: int = _get_friend_presence_rank(b, server_map_by_user)
		if rank_a == rank_b:
			return str(a.get("username", "")).to_lower() < str(b.get("username", "")).to_lower()
		return rank_a < rank_b
	)
	_home_friends_cache = friends.duplicate(true)
	_home_friends_active_lookup_cache = server_map_by_user.duplicate(true)
	_home_friends_cache_loaded = true
	# Clear again right before populating to remove any stale children
	_clear_children_immediate(home_friends_container)
	if home_friends_status:
		home_friends_status.text = "%d friends" % friends.size()
	
	if friends.is_empty():
		var empty_row := HBoxContainer.new()
		empty_row.add_theme_constant_override("separation", 12)
		empty_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var empty_lbl := Label.new()
		empty_lbl.text = "Add friends to see them here!"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_row.add_child(empty_lbl)
		var add_friend_btn := Button.new()
		add_friend_btn.text = "+ Add Friend"
		add_friend_btn.custom_minimum_size = Vector2(120, 36)
		var af_style := StyleBoxFlat.new()
		af_style.bg_color = Color(0.12, 0.6, 0.88, 1)
		af_style.corner_radius_top_left = 6
		af_style.corner_radius_top_right = 6
		af_style.corner_radius_bottom_right = 6
		af_style.corner_radius_bottom_left = 6
		add_friend_btn.add_theme_stylebox_override("normal", af_style)
		add_friend_btn.add_theme_color_override("font_color", Color.WHITE)
		add_friend_btn.add_theme_font_size_override("font_size", 14)
		add_friend_btn.pressed.connect(func(): _show_social_friend_search_popup(add_friend_btn))
		empty_row.add_child(add_friend_btn)
		home_friends_container.add_child(empty_row)
		_queue_home_friends_clip_layout()
		_home_friends_refresh_in_flight = false
		_home_friends_refresh_pending = false
		return
		
	var rendered_friend_keys: Dictionary = {}
	var rendered_count: int = 0
	for friend_variant in friends:
		if not (friend_variant is Dictionary):
			continue
		var friend_profile: Dictionary = friend_variant
		var friend_key: String = str(friend_profile.get("username", "")).strip_edges().to_lower()
		if friend_key.is_empty():
			friend_key = str(friend_profile.get("id", "")).strip_edges().to_lower()
		if friend_key.is_empty() or rendered_friend_keys.has(friend_key):
			continue
		rendered_friend_keys[friend_key] = true
		home_friends_container.add_child(_create_home_friend_avatar(friend_profile, server_map_by_user))
		rendered_count += 1
		if rendered_count % 2 == 0:
			await get_tree().process_frame
	_queue_home_friends_clip_layout()
	_home_friends_refresh_in_flight = false
	_home_friends_refresh_pending = false
	_next_home_friends_refresh_allowed_msec = 0

func _is_mouse_wheel_button(button_index: int) -> bool:
	return button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

func _on_home_friends_clip_gui_input(event: InputEvent) -> void:
	if home_friends_clip == null or home_friends_container == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if _is_mouse_wheel_button(mouse_event.button_index):
			_route_home_friends_wheel_to_page(home_friends_clip, mouse_event)
			home_friends_clip.accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_home_friends_drag_active = true
				_home_friends_drag_pointer = -1
				_home_friends_drag_start_position = mouse_event.position
				_home_friends_drag_start_offset = _home_friends_scroll_offset
				_home_friends_dragged = false
				home_friends_clip.accept_event()
			elif _home_friends_drag_active and _home_friends_drag_pointer == -1:
				_home_friends_drag_active = false
				if _home_friends_dragged:
					home_friends_clip.accept_event()
			return
	if event is InputEventMouseMotion and _home_friends_drag_active and _home_friends_drag_pointer == -1:
		var motion := event as InputEventMouseMotion
		_apply_home_friends_drag(motion.position, motion.relative)
		home_friends_clip.accept_event()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_home_friends_drag_active = true
			_home_friends_drag_pointer = touch.index
			_home_friends_drag_start_position = touch.position
			_home_friends_drag_start_offset = _home_friends_scroll_offset
			_home_friends_dragged = false
			home_friends_clip.accept_event()
		elif _home_friends_drag_active and touch.index == _home_friends_drag_pointer:
			_home_friends_drag_active = false
			_home_friends_drag_pointer = -1
			if _home_friends_dragged:
				home_friends_clip.accept_event()
		return
	if event is InputEventScreenDrag and _home_friends_drag_active:
		var drag := event as InputEventScreenDrag
		if drag.index != _home_friends_drag_pointer:
			return
		_apply_home_friends_drag(drag.position, drag.relative)
		home_friends_clip.accept_event()

func _apply_home_friends_drag(position: Vector2, relative: Vector2) -> void:
	var delta := position - _home_friends_drag_start_position
	if absf(delta.x) > 8.0:
		_home_friends_dragged = true
	if absf(delta.x) >= absf(delta.y) or _home_friends_dragged:
		_set_home_friends_scroll_offset(_home_friends_drag_start_offset - delta.x)
		return
	var parent_scroll := _find_parent_vertical_scroll_container(home_friends_clip)
	if parent_scroll != null:
		parent_scroll.scroll_vertical = maxi(0, parent_scroll.scroll_vertical - int(round(relative.y)))

func _set_home_friends_scroll_offset(value: float) -> void:
	if home_friends_clip == null or home_friends_container == null:
		return
	var max_offset := maxf(0.0, home_friends_container.size.x - home_friends_clip.size.x)
	_home_friends_scroll_offset = clampf(value, 0.0, max_offset)
	home_friends_container.position = Vector2(-_home_friends_scroll_offset, 0.0)

func _update_home_friends_clip_layout() -> void:
	if home_friends_clip == null or home_friends_container == null:
		return
	var clip_size := home_friends_clip.size
	if clip_size.x <= 1.0:
		clip_size.x = maxf(1.0, home_friends_clip.get_global_rect().size.x)
	if clip_size.y <= 1.0:
		clip_size.y = 172.0
	var content_size := home_friends_container.get_combined_minimum_size()
	var content_width := maxf(content_size.x, clip_size.x)
	var content_height := maxf(content_size.y, clip_size.y)
	home_friends_container.custom_minimum_size = Vector2(content_width, content_height)
	home_friends_container.size = Vector2(content_width, content_height)
	_set_home_friends_scroll_offset(_home_friends_scroll_offset)

func _queue_home_friends_clip_layout() -> void:
	call_deferred("_update_home_friends_clip_layout")

func _restore_scrollbar_value(scrollbar: Range, value: float) -> void:
	if scrollbar != null and is_instance_valid(scrollbar):
		scrollbar.value = value

func _route_home_friends_wheel_to_page(source: Control, event: InputEventMouseButton) -> void:
	if source == null:
		return
	var hbar := (source as ScrollContainer).get_h_scroll_bar() if source is ScrollContainer else null
	var old_horizontal := hbar.value if hbar != null else 0.0
	var parent_scroll := _find_parent_vertical_scroll_container(source)
	if parent_scroll != null:
		var vbar := parent_scroll.get_v_scroll_bar()
		if vbar != null:
			var direction := 0.0
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
					direction = -1.0
				MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
					direction = 1.0
			if direction != 0.0:
				var factor: float = maxf(1.0, event.factor)
				vbar.value = clampf(vbar.value + direction * 72.0 * factor, vbar.min_value, vbar.max_value)
	if hbar != null:
		call_deferred("_restore_scrollbar_value", hbar, old_horizontal)

func _find_parent_vertical_scroll_container(node: Node) -> ScrollContainer:
	var current := node.get_parent()
	while current != null:
		if current is ScrollContainer:
			var scroll := current as ScrollContainer
			if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return scroll
		current = current.get_parent()
	return null

func _render_home_friend_cards_from_cache() -> void:
	if home_friends_container == null:
		return
	_clear_children_immediate(home_friends_container)
	if home_friends_status:
		home_friends_status.text = "%d friends" % _home_friends_cache.size()
	if _home_friends_cache.is_empty():
		var empty_row := HBoxContainer.new()
		empty_row.add_theme_constant_override("separation", 12)
		empty_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var empty_lbl := Label.new()
		empty_lbl.text = "Add friends to see them here!"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_row.add_child(empty_lbl)
		var add_friend_btn := Button.new()
		add_friend_btn.text = "+ Add Friend"
		add_friend_btn.custom_minimum_size = Vector2(120, 36)
		var af_style := StyleBoxFlat.new()
		af_style.bg_color = Color(0.12, 0.6, 0.88, 1)
		af_style.corner_radius_top_left = 6
		af_style.corner_radius_top_right = 6
		af_style.corner_radius_bottom_right = 6
		af_style.corner_radius_bottom_left = 6
		add_friend_btn.add_theme_stylebox_override("normal", af_style)
		add_friend_btn.add_theme_color_override("font_color", Color.WHITE)
		add_friend_btn.add_theme_font_size_override("font_size", 14)
		add_friend_btn.pressed.connect(func(): _show_social_friend_search_popup(add_friend_btn))
		empty_row.add_child(add_friend_btn)
		home_friends_container.add_child(empty_row)
		_queue_home_friends_clip_layout()
		return
	var rendered_friend_keys: Dictionary = {}
	for friend_variant in _home_friends_cache:
		if not (friend_variant is Dictionary):
			continue
		var friend_profile: Dictionary = friend_variant
		var friend_key: String = str(friend_profile.get("username", "")).strip_edges().to_lower()
		if friend_key.is_empty():
			friend_key = str(friend_profile.get("id", friend_profile.get("user_id", ""))).strip_edges().to_lower()
		if friend_key.is_empty() or rendered_friend_keys.has(friend_key):
			continue
		rendered_friend_keys[friend_key] = true
		home_friends_container.add_child(_create_home_friend_avatar(friend_profile, _home_friends_active_lookup_cache))
	_queue_home_friends_clip_layout()

func _refresh_home_friend_active_statuses_async() -> void:
	if _home_friend_status_refresh_in_flight or home_friends_container == null:
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_home_friend_status_refresh_msec:
		return
	_home_friend_status_refresh_in_flight = true
	_next_home_friend_status_refresh_msec = now_msec + 12000
	if CloudAPI != null and CloudAPI.is_configured() and CloudAPI.has_method("fetch_active_servers"):
		var active_servers_result: Dictionary = await CloudAPI.fetch_active_servers("", 64, 2.0, 1)
		if bool(active_servers_result.get("ok", false)):
			_home_friends_active_lookup_cache = _build_server_lookup_by_user(CloudAPI._extract_array_payload(active_servers_result.get("data", [])))
			_update_home_friend_status_cards()
	_home_friend_status_refresh_in_flight = false

func _update_home_friend_status_cards() -> void:
	if home_friends_container == null:
		return
	for child in home_friends_container.get_children():
		if not (child is Control):
			continue
		var card := child as Control
		var profile_variant: Variant = card.get_meta("profile", {})
		if not (profile_variant is Dictionary):
			continue
		var profile: Dictionary = profile_variant
		var active_server := _resolve_active_server_for_profile(profile, _home_friends_active_lookup_cache)
		card.set_meta("active_server", active_server)
		var status_dot := card.find_child("StatusDot", true, false) as Panel
		if status_dot != null:
			status_dot.add_theme_stylebox_override("panel", _make_home_friend_status_dot_style(profile, active_server))

func _make_home_friend_status_dot_style(profile: Dictionary, active_server: Dictionary) -> StyleBoxFlat:
	var status_text: String = _get_profile_status_text(profile, active_server)
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = Color(0.2, 0.72, 0.28, 1) if not active_server.is_empty() else (Color(0.0, 0.62, 0.9, 1) if status_text == "Online" else Color(0.64, 0.66, 0.7, 1))
	dot_style.corner_radius_top_left = 9
	dot_style.corner_radius_top_right = 9
	dot_style.corner_radius_bottom_left = 9
	dot_style.corner_radius_bottom_right = 9
	dot_style.border_width_left = 2
	dot_style.border_width_top = 2
	dot_style.border_width_right = 2
	dot_style.border_width_bottom = 2
	dot_style.border_color = Color.WHITE
	return dot_style

func _create_home_friend_avatar(profile: Dictionary, server_map_by_user: Dictionary) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(112, 136)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(1, 1, 1, 0)
	card.add_theme_stylebox_override("panel", card_style)
	card.set_meta("profile", profile.duplicate(true))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var user_id: String = str(profile.get("id", "")).strip_edges()
	var username_text: String = str(profile.get("username", user_id)).strip_edges()
	var active_server: Dictionary = server_map_by_user.get(user_id, {}) if server_map_by_user.get(user_id, {}) is Dictionary else {}
	if active_server.is_empty():
		active_server = _resolve_active_server_for_profile(profile, server_map_by_user)
	card.set_meta("active_server", active_server)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 2)
	margin.add_child(root)

	var avatar_button := Button.new()
	avatar_button.flat = true
	avatar_button.focus_mode = Control.FOCUS_NONE
	avatar_button.custom_minimum_size = Vector2(86, 86)
	root.add_child(avatar_button)
	var avatar_holder := Control.new()
	avatar_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_button.add_child(avatar_holder)
	var avatar_preview := _create_home_avatar_preview(profile, 82)
	# FIX: Pass mouse events through the avatar preview so the underlying
	# Button actually receives clicks. Without this, the Panel/SubViewport
	# hierarchy consumed all mouse events before they reached the button.
	_set_mouse_filter_pass_recursive(avatar_preview)
	avatar_holder.add_child(avatar_preview)
	var status_dot := Panel.new()
	status_dot.name = "StatusDot"
	status_dot.custom_minimum_size = Vector2(17, 17)
	status_dot.position = Vector2(66, 64)
	status_dot.add_theme_stylebox_override("panel", _make_home_friend_status_dot_style(profile, active_server))
	avatar_holder.add_child(status_dot)

	var name_button := Button.new()
	name_button.text = username_text if not username_text.is_empty() else "Unknown"
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.clip_text = true
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
	name_button.add_theme_font_size_override("font_size", 11)
	root.add_child(name_button)
	ACCOUNT_BADGES.attach(name_button, profile)

	var open_popup := func() -> void:
		var live_active_server: Dictionary = card.get_meta("active_server", {}) if card.get_meta("active_server", {}) is Dictionary else {}
		if live_active_server.is_empty():
			live_active_server = _resolve_active_server_for_profile(profile, _home_friends_active_lookup_cache)
		_show_home_friend_popup(name_button, profile, live_active_server)
	var press_pos := Vector2.ZERO
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and _is_mouse_wheel_button((event as InputEventMouseButton).button_index):
			_route_home_friends_wheel_to_page(card, event as InputEventMouseButton)
			card.accept_event()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
			else:
				if press_pos.distance_to(event.position) < 15.0:
					var mobile_runtime = get_node_or_null("/root/MobileRuntime")
					if mobile_runtime == null or not mobile_runtime.get("_ui_scroll_dragged"):
						open_popup.call()
	)
	avatar_button.pressed.connect(open_popup)
	name_button.pressed.connect(open_popup)
	return card

func _create_home_avatar_preview(profile: Dictionary, size_px: int = 76) -> Control:
	var friends_builder := load("res://scripts/lobby/friends_builder.gd")
	if friends_builder != null:
		return friends_builder._create_round_avatar_preview(profile, size_px, 0.0, self)
	return _create_lightweight_home_avatar_badge(profile, size_px)

func _create_lightweight_home_avatar_badge(profile: Dictionary, size_px: int = 76) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = _get_profile_avatar_color(profile, "torso", Color(0.05, 0.4, 0.7)).lightened(0.22)
	var half_size: int = int(size_px / 2.0)
	style.corner_radius_top_left = half_size
	style.corner_radius_top_right = half_size
	style.corner_radius_bottom_left = half_size
	style.corner_radius_bottom_right = half_size
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color.WHITE
	holder.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = _profile_initials(profile)
	label.add_theme_font_size_override("font_size", maxi(12, int(size_px * 0.36)))
	label.add_theme_color_override("font_color", Color.WHITE)
	holder.add_child(label)
	return holder

func _profile_initials(profile: Dictionary) -> String:
	var username: String = str(profile.get("username", profile.get("name", ""))).strip_edges()
	if username.is_empty():
		return "?"
	var parts: PackedStringArray = username.split("_", false)
	if parts.size() <= 1:
		parts = username.split(" ", false)
	var initials := ""
	for part in parts:
		if initials.length() >= 2:
			break
		var clean_part: String = str(part).strip_edges()
		if not clean_part.is_empty():
			initials += clean_part.substr(0, 1).to_upper()
	return initials if not initials.is_empty() else username.substr(0, 1).to_upper()

func _create_home_header_avatar_preview(size_px: int = 140) -> Control:
	# Home, Friends and Profile use the same cached renderer. This keeps the
	# portrait identical everywhere and includes the complete server outfit.
	home_avatar_player = null
	var profile := {
		"id": UserSession.user_id,
		"user_id": UserSession.user_id,
		"username": UserSession.username,
		"avatar_data": UserSession.avatar_data.duplicate(true),
		"avatar_outfit": UserSession.avatar_data.duplicate(true),
		"equipped_avatar_item_payloads": _get_local_equipped_avatar_item_payloads()
	}
	var friends_builder := load("res://scripts/lobby/friends_builder.gd")
	if friends_builder != null:
		return friends_builder._create_round_avatar_preview(profile, size_px, 0.0, self)
	return _create_lightweight_home_avatar_badge(profile, size_px)

func _create_profile_avatar_snapshot(profile_data: Dictionary, size_px: int = 100) -> Control:
	var resolved_profile := profile_data.duplicate(true)
	if resolved_profile.is_empty() or _is_profile_snapshot_current_user(resolved_profile):
		resolved_profile = _merge_current_session_avatar_into_profile(resolved_profile)
	var friends_builder := load("res://scripts/lobby/friends_builder.gd")
	if friends_builder != null:
		return friends_builder._create_round_avatar_preview(resolved_profile, size_px, 0.0, self)
	return _create_lightweight_home_avatar_badge(resolved_profile, size_px)

func _refresh_profile_header_avatar_snapshot(profile_data: Dictionary) -> void:
	if profile_header_avatar_holder == null or not is_instance_valid(profile_header_avatar_holder):
		return
	_clear_container(profile_header_avatar_holder)
	profile_header_avatar_holder.add_child(_create_profile_avatar_snapshot(profile_data, 100))

func _prepare_home_friend_popup_surface() -> void:
	if home_friend_popup == null:
		return
	home_friend_popup.add_theme_stylebox_override("panel", _make_white_panel_style())
	home_friend_popup.self_modulate = Color(1, 1, 1, 1)
	home_friend_popup.clip_contents = false

func _ensure_home_friend_popup() -> void:
	if home_friend_popup != null:
		return
	home_friend_popup = Panel.new()
	home_friend_popup.visible = false
	home_friend_popup.custom_minimum_size = Vector2(200, 120)
	home_friend_popup.set_as_top_level(true)
	home_friend_popup.add_theme_stylebox_override("panel", _make_white_panel_style())
	add_child(home_friend_popup)

func _show_home_friend_popup(trigger_btn: Control, profile: Dictionary, active_server: Dictionary) -> void:
	_ensure_home_friend_popup()
	if home_friend_popup == null:
		return
	_prepare_home_friend_popup_surface()
	_clear_container(home_friend_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	home_friend_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var user_id: String = str(profile.get("id", ""))
	var username_text: String = str(profile.get("username", user_id)).strip_edges()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vbox.add_child(header)

	header.add_child(_create_home_avatar_preview(profile, 86))

	var header_info := VBoxContainer.new()
	header_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_info.add_theme_constant_override("separation", 8)
	header.add_child(header_info)

	var title := Label.new()
	title.text = username_text if not username_text.is_empty() else "Unknown"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.13, 0.14, 0.16, 1))
	header_info.add_child(title)

	var status_label := Label.new()
	status_label.text = _get_profile_status_text(profile, active_server)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.21, 0.22, 0.25, 1))
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.88, 0.94, 0.9, 1) if not active_server.is_empty() else Color(0.92, 0.94, 0.97, 1)
	status_style.corner_radius_top_left = 10
	status_style.corner_radius_top_right = 10
	status_style.corner_radius_bottom_left = 10
	status_style.corner_radius_bottom_right = 10
	status_style.content_margin_left = 10
	status_style.content_margin_right = 10
	status_style.content_margin_top = 5
	status_style.content_margin_bottom = 5
	status_label.add_theme_stylebox_override("normal", status_style)
	header_info.add_child(status_label)

	if not active_server.is_empty():
		var game_info := {
			"name": _resolve_display_game_name(str(active_server.get("map_name", "")).strip_edges(), str(active_server.get("map_id", "")).strip_edges(), "Friend's Game"),
			"map_id": str(active_server.get("map_id", "")).strip_edges(),
			"cloud_version_id": str(active_server.get("cloud_version_id", "")).strip_edges(),
			"icon_path": "",
			"thumbnail": "",
			"folder": ""
		}
		var game_panel := Panel.new()
		game_panel.custom_minimum_size = Vector2(0, 126)
		game_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
		vbox.add_child(game_panel)

		var game_margin := MarginContainer.new()
		game_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		game_margin.add_theme_constant_override("margin_left", 12)
		game_margin.add_theme_constant_override("margin_top", 12)
		game_margin.add_theme_constant_override("margin_right", 12)
		game_margin.add_theme_constant_override("margin_bottom", 12)
		game_panel.add_child(game_margin)

		var game_row := HBoxContainer.new()
		game_row.add_theme_constant_override("separation", 12)
		game_margin.add_child(game_row)

		var icon := _create_game_icon_widget(game_info)
		icon.custom_minimum_size = Vector2(120, 72)
		game_row.add_child(icon)

		var game_info_box := VBoxContainer.new()
		game_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_info_box.add_theme_constant_override("separation", 6)
		game_row.add_child(game_info_box)

		var game_name_label := Label.new()
		game_name_label.text = str(game_info.get("name", "Friend's Game"))
		game_name_label.add_theme_font_size_override("font_size", 15)
		game_name_label.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
		game_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game_info_box.add_child(game_name_label)

		var game_meta_label := Label.new()
		game_meta_label.text = "%d/%d players" % [int(active_server.get("players_count", 0)), int(active_server.get("max_players", NetworkManager.MAX_CLIENTS if NetworkManager != null else 10))]
		game_meta_label.add_theme_font_size_override("font_size", 11)
		game_meta_label.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
		game_info_box.add_child(game_meta_label)

		var game_hint := Label.new()
		game_hint.text = "You can join this lobby directly."
		game_hint.add_theme_font_size_override("font_size", 11)
		game_hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
		game_info_box.add_child(game_hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	vbox.add_child(actions)

	if not active_server.is_empty():
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(0, 36)
		join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
		join_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.15, 0.67, 0.96, 1.0)))
		join_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.15, 0.67, 0.96, 1.0)))
		join_btn.add_theme_color_override("font_color", Color.WHITE)
		join_btn.pressed.connect(func():
			home_friend_popup.hide()
			_join_server_flow({
				"name": _resolve_display_game_name(str(active_server.get("map_name", "")).strip_edges(), str(active_server.get("map_id", "")).strip_edges(), "Friend's Game"),
				"map_id": str(active_server.get("map_id", "")).strip_edges(),
				"cloud_version_id": str(active_server.get("cloud_version_id", "")).strip_edges(),
				"icon_path": ""
			}, active_server)
		)
		actions.add_child(join_btn)

	var profile_btn := Button.new()
	profile_btn.text = "Profile"
	profile_btn.custom_minimum_size = Vector2(0, 36)
	profile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_btn.pressed.connect(func():
		home_friend_popup.hide()
		_open_profile_for_user(user_id, username_text, profile, active_server)
	)
	actions.add_child(profile_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.custom_minimum_size = Vector2(0, 36)
	remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_btn.pressed.connect(func():
		if user_id.is_empty():
			return
		await CloudAPI.remove_friend(user_id)
		home_friend_popup.hide()
		_refresh_home_dashboard()
		_refresh_friends_view()
	)
	actions.add_child(remove_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.53, 0.55, 0.58, 1))
	close_btn.pressed.connect(func(): home_friend_popup.hide())
	vbox.add_child(close_btn)

	var popup_height: float = 468.0 if not active_server.is_empty() else 320.0
	home_friend_popup.custom_minimum_size = Vector2(460, popup_height)
	home_friend_popup.size = Vector2(460, popup_height)
	var g_pos = trigger_btn.global_position + Vector2(0, trigger_btn.size.y + 10)
	var viewport_size: Vector2 = get_viewport_rect().size
	if g_pos.x + home_friend_popup.size.x > viewport_size.x - 16.0:
		g_pos.x = viewport_size.x - home_friend_popup.size.x - 16.0
	if g_pos.y + popup_height > viewport_size.y - 16.0:
		g_pos.y = maxf(16.0, trigger_btn.global_position.y - popup_height)
	home_friend_popup.global_position = g_pos
	home_friend_popup.show()

func _show_home_add_friend_popup(trigger_btn: Control) -> void:
	_show_social_friend_search_popup(trigger_btn)
	if home_friend_popup != null and home_friend_popup.visible:
		return
	_clear_container(home_friend_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	home_friend_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Add a Friend"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Search for players by username, preview their avatar, and open their full profile."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.46, 0.48, 0.52, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	var search_input := LineEdit.new()
	search_input.placeholder_text = "Search by username..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 42)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.96, 0.97, 0.99, 1)
	input_style.corner_radius_top_left = 8
	input_style.corner_radius_top_right = 8
	input_style.corner_radius_bottom_left = 8
	input_style.corner_radius_bottom_right = 8
	input_style.border_width_left = 1
	input_style.border_width_top = 1
	input_style.border_width_right = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.83, 0.86, 0.91, 1)
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	search_input.add_theme_stylebox_override("normal", input_style)
	search_input.add_theme_stylebox_override("focus", input_style)
	search_input.add_theme_color_override("font_color", Color(0.17, 0.18, 0.22, 1))
	search_input.add_theme_color_override("font_placeholder_color", Color(0.56, 0.58, 0.62, 1))
	row.add_child(search_input)

	var search_btn := Button.new()
	search_btn.text = "Search"
	search_btn.custom_minimum_size = Vector2(116, 42)
	search_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
	search_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	search_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	search_btn.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(search_btn)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", Color(0.43, 0.45, 0.49, 1))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_lbl)

	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(0, 320)
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(results_scroll)
	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 10)
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(results)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 38)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.56, 0.58, 0.61, 1))
	close_btn.pressed.connect(func(): home_friend_popup.hide())
	footer.add_child(close_btn)

	var run_search := func() -> void:
		var query: String = search_input.text.strip_edges()
		for child in results.get_children():
			child.queue_free()
		if query.is_empty():
			status_lbl.text = "Enter a username."
			return
		if not CloudAPI.is_configured():
			status_lbl.text = "Cloud social is disconnected."
			return
		status_lbl.text = "Searching..."
		var search_result: Dictionary = await CloudAPI.search_profiles(query, 8)
		if not bool(search_result.get("ok", false)):
			status_lbl.text = str(search_result.get("error", "Search failed."))
			return
		var profiles: Array = CloudAPI._extract_array_payload(search_result.get("data", []))
		if profiles.is_empty():
			status_lbl.text = "No users found."
			return
		status_lbl.text = "Found %d users" % profiles.size()
		for profile_variant in profiles:
			if not (profile_variant is Dictionary):
				continue
			var profile: Dictionary = profile_variant
			var profile_row := HBoxContainer.new()
			profile_row.add_theme_constant_override("separation", 8)
			var avatar_chip := Panel.new()
			avatar_chip.custom_minimum_size = Vector2(28, 28)
			var avatar_style := StyleBoxFlat.new()
			avatar_style.bg_color = Color(0.92, 0.92, 0.92, 1)
			avatar_style.corner_radius_top_left = 14
			avatar_style.corner_radius_top_right = 14
			avatar_style.corner_radius_bottom_left = 14
			avatar_style.corner_radius_bottom_right = 14
			avatar_chip.add_theme_stylebox_override("panel", avatar_style)
			var avatar_icon := Label.new()
			avatar_icon.text = "👤"
			avatar_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			avatar_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			avatar_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			avatar_chip.add_child(avatar_icon)
			profile_row.add_child(avatar_chip)
			var user_label := Label.new()
			user_label.text = str(profile.get("username", "Unknown")).strip_edges()
			user_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			profile_row.add_child(user_label)
			var add_btn := Button.new()
			add_btn.text = "Add"
			var target_user_id: String = str(profile.get("id", "")).strip_edges()
			add_btn.pressed.connect(func():
				if target_user_id.is_empty():
					status_lbl.text = "Invalid target user."
					return
				add_btn.disabled = true
				status_lbl.text = "Sending request..."
				var send_result: Dictionary = await CloudAPI.send_friend_request(target_user_id)
				status_lbl.text = _format_friend_request_send_status(send_result, str(profile.get("username", "player")))
				_apply_friend_request_button_state(add_btn, send_result)
				if bool(send_result.get("ok", false)):
					_next_lobby_friend_request_poll_msec = 0
					_refresh_friends_view()
					_schedule_home_dashboard_refresh(true)
			)
			profile_row.add_child(add_btn)
			var view_btn := Button.new()
			view_btn.text = "Profile"
			view_btn.pressed.connect(func():
				home_friend_popup.hide()
				_open_profile_for_user(str(profile.get("id", "")).strip_edges(), str(profile.get("username", "Unknown")).strip_edges())
			)
			profile_row.add_child(view_btn)
			results.add_child(profile_row)

	search_btn.pressed.connect(func(): run_search.call())
	search_input.text_submitted.connect(func(_text: String): run_search.call())

	home_friend_popup.size = Vector2(420, 0)
	var g_pos = trigger_btn.global_position
	g_pos.y += trigger_btn.size.y + 10
	home_friend_popup.global_position = g_pos
	home_friend_popup.show()

func _friend_request_response_payload(result: Dictionary) -> Dictionary:
	var data: Variant = result.get("data", {})
	if data is Dictionary:
		return data
	if data is Array and not (data as Array).is_empty() and (data as Array)[0] is Dictionary:
		return (data as Array)[0]
	return result

func _friend_request_response_flag(result: Dictionary, flag_name: String) -> bool:
	var payload := _friend_request_response_payload(result)
	if result.has(flag_name):
		return bool(result.get(flag_name, false))
	return bool(payload.get(flag_name, false))

func _format_friend_request_send_status(result: Dictionary, profile_username: String) -> String:
	var display_name := profile_username.strip_edges()
	if display_name.is_empty():
		display_name = "player"
	if not bool(result.get("ok", false)):
		var status_code := int(result.get("status", 0))
		if status_code == 401 or status_code == 403:
			return "Your login session expired. Please log in again and retry."
		return str(result.get("error", "Could not send friend request."))
	if _friend_request_response_flag(result, "already_friends"):
		return "%s is already your friend." % display_name
	if _friend_request_response_flag(result, "incoming_pending"):
		return "%s already sent you a request. Open Requests to accept it." % display_name
	if _friend_request_response_flag(result, "pending"):
		return "Friend request to %s is pending." % display_name
	return "Friend request sent to %s." % display_name

func _apply_friend_request_button_state(add_btn: Button, result: Dictionary) -> void:
	if add_btn == null:
		return
	if not bool(result.get("ok", false)):
		add_btn.text = "Add"
		add_btn.disabled = false
		return
	if _friend_request_response_flag(result, "already_friends"):
		add_btn.text = "Friends"
		add_btn.disabled = true
	elif _friend_request_response_flag(result, "incoming_pending"):
		add_btn.text = "Requests"
		add_btn.disabled = true
	else:
		add_btn.text = "Pending"
		add_btn.disabled = true

func _show_social_friend_search_popup(trigger_btn: Control) -> void:
	_ensure_home_friend_popup()
	if home_friend_popup == null:
		return
	_prepare_home_friend_popup_surface()
	_clear_container(home_friend_popup)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	home_friend_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Add a Friend"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Search real player profiles, preview their avatar, and open a full profile before sending a friend request."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.46, 0.48, 0.52, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	root.add_child(search_row)

	var search_input := LineEdit.new()
	search_input.placeholder_text = "Search by username..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 42)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.96, 0.97, 0.99, 1)
	input_style.corner_radius_top_left = 8
	input_style.corner_radius_top_right = 8
	input_style.corner_radius_bottom_left = 8
	input_style.corner_radius_bottom_right = 8
	input_style.border_width_left = 1
	input_style.border_width_top = 1
	input_style.border_width_right = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.83, 0.86, 0.91, 1)
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	search_input.add_theme_stylebox_override("normal", input_style)
	search_input.add_theme_stylebox_override("focus", input_style)
	search_input.add_theme_color_override("font_color", Color(0.17, 0.18, 0.22, 1))
	search_input.add_theme_color_override("font_placeholder_color", Color(0.56, 0.58, 0.62, 1))
	search_row.add_child(search_input)

	var search_btn := Button.new()
	search_btn.text = "Search"
	search_btn.custom_minimum_size = Vector2(116, 42)
	search_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
	search_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	search_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	search_btn.add_theme_color_override("font_color", Color.WHITE)
	search_row.add_child(search_btn)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", Color(0.43, 0.45, 0.49, 1))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_lbl)

	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(0, 320)
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(results_scroll)

	var results := VBoxContainer.new()
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_theme_constant_override("separation", 10)
	results_scroll.add_child(results)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 38)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.56, 0.58, 0.61, 1))
	close_btn.pressed.connect(func(): home_friend_popup.hide())
	footer.add_child(close_btn)

	var run_search := func() -> void:
		var query: String = search_input.text.strip_edges()
		_clear_container(results)
		if query.is_empty():
			status_lbl.text = "Enter a username to search."
			return
		if not CloudAPI.is_configured():
			status_lbl.text = "Cloud social is disconnected."
			return
		status_lbl.text = "Searching..."
		var search_result: Dictionary = await CloudAPI.search_profiles(query, 12)
		if not is_instance_valid(results) or not is_instance_valid(status_lbl):
			return
		if not bool(search_result.get("ok", false)):
			status_lbl.text = str(search_result.get("error", "Search failed."))
			return
		var profiles: Array = CloudAPI._extract_array_payload(search_result.get("data", []))
		if profiles.is_empty():
			status_lbl.text = "No users found."
			return
		status_lbl.text = "Found %d matching player(s)." % profiles.size()
		for profile_variant in profiles:
			if not (profile_variant is Dictionary):
				continue
			var profile: Dictionary = (profile_variant as Dictionary).duplicate(true)
			var profile_user_id: String = str(profile.get("id", "")).strip_edges()
			var profile_username: String = str(profile.get("username", "Unknown")).strip_edges()
			var card := Panel.new()
			card.custom_minimum_size = Vector2(0, 96)
			card.add_theme_stylebox_override("panel", _make_white_panel_style())
			results.add_child(card)

			var card_margin := MarginContainer.new()
			card_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
			card_margin.add_theme_constant_override("margin_left", 14)
			card_margin.add_theme_constant_override("margin_right", 14)
			card_margin.add_theme_constant_override("margin_top", 12)
			card_margin.add_theme_constant_override("margin_bottom", 12)
			card.add_child(card_margin)

			var card_row := HBoxContainer.new()
			card_row.add_theme_constant_override("separation", 12)
			card_margin.add_child(card_row)

			card_row.add_child(_create_social_avatar_preview(profile, 56))

			var info_box := VBoxContainer.new()
			info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_box.add_theme_constant_override("separation", 4)
			card_row.add_child(info_box)

			var username_lbl := Label.new()
			username_lbl.text = profile_username if not profile_username.is_empty() else "Unknown"
			username_lbl.add_theme_font_size_override("font_size", 16)
			username_lbl.add_theme_color_override("font_color", Color(0.14, 0.15, 0.19, 1))
			username_lbl.clip_text = true
			username_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			info_box.add_child(username_lbl)

			var status_chip := Label.new()
			status_chip.text = _get_profile_status_text(profile)
			status_chip.add_theme_font_size_override("font_size", 11)
			status_chip.add_theme_color_override("font_color", Color(0.1, 0.55, 0.24, 1) if status_chip.text != "Offline" else Color(0.5, 0.52, 0.56, 1))
			info_box.add_child(status_chip)

			var hint_lbl := Label.new()
			hint_lbl.text = "Preview profile or send a friend request."
			hint_lbl.add_theme_font_size_override("font_size", 11)
			hint_lbl.add_theme_color_override("font_color", Color(0.48, 0.49, 0.53, 1))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_box.add_child(hint_lbl)

			var actions := VBoxContainer.new()
			actions.custom_minimum_size = Vector2(110, 0)
			actions.add_theme_constant_override("separation", 8)
			card_row.add_child(actions)

			var add_btn := Button.new()
			add_btn.text = "Add"
			add_btn.custom_minimum_size = Vector2(0, 34)
			add_btn.disabled = profile_user_id.is_empty() or profile_user_id == UserSession.user_id
			add_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
			add_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
			add_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
			add_btn.add_theme_color_override("font_color", Color.WHITE)
			add_btn.pressed.connect(func():
				if profile_user_id.is_empty():
					status_lbl.text = "Invalid target user."
					return
				add_btn.disabled = true
				status_lbl.text = "Sending request..."
				var send_result: Dictionary = await CloudAPI.send_friend_request(profile_user_id)
				status_lbl.text = _format_friend_request_send_status(send_result, profile_username)
				_apply_friend_request_button_state(add_btn, send_result)
				if bool(send_result.get("ok", false)):
					_next_lobby_friend_request_poll_msec = 0
					_refresh_friends_view()
					_schedule_home_dashboard_refresh(true)
			)
			actions.add_child(add_btn)

			var profile_btn := Button.new()
			profile_btn.text = "Profile"
			profile_btn.custom_minimum_size = Vector2(0, 34)
			profile_btn.pressed.connect(func():
				home_friend_popup.hide()
				_open_profile_for_user(profile_user_id, profile_username, profile, {})
			)
			actions.add_child(profile_btn)

	search_btn.pressed.connect(func(): run_search.call())
	search_input.text_submitted.connect(func(_text: String): run_search.call())

	home_friend_popup.custom_minimum_size = Vector2(720, 520)
	home_friend_popup.size = Vector2(720, 520)
	var popup_position := trigger_btn.global_position + Vector2(0, trigger_btn.size.y + 10)
	var viewport_size: Vector2 = get_viewport_rect().size
	if popup_position.x + home_friend_popup.size.x > viewport_size.x - 16.0:
		popup_position.x = viewport_size.x - home_friend_popup.size.x - 16.0
	if popup_position.y + home_friend_popup.size.y > viewport_size.y - 16.0:
		popup_position.y = maxf(16.0, trigger_btn.global_position.y - home_friend_popup.size.y - 10.0)
	home_friend_popup.global_position = popup_position
	home_friend_popup.show()

func _open_profile_for_user(user_id: String, username: String, profile_snapshot: Dictionary = {}, active_server: Dictionary = {}) -> void:
	selected_profile_user_id = user_id.strip_edges()
	selected_profile_username = username.strip_edges()
	selected_profile_snapshot = profile_snapshot.duplicate(true)
	if selected_profile_user_id.is_empty():
		selected_profile_user_id = str(selected_profile_snapshot.get("id", "")).strip_edges()
	if selected_profile_username.is_empty():
		selected_profile_username = str(selected_profile_snapshot.get("username", "")).strip_edges()
	if not selected_profile_user_id.is_empty():
		selected_profile_snapshot["id"] = selected_profile_user_id
	if not selected_profile_username.is_empty():
		selected_profile_snapshot["username"] = selected_profile_username
	selected_profile_active_server = active_server.duplicate(true)
	if profile_username_label:
		profile_username_label.text = selected_profile_username if not selected_profile_username.is_empty() else (UserSession.username if UserSession.is_logged_in else "Player")
	_apply_profile_snapshot_to_ui(selected_profile_snapshot, selected_profile_active_server)
	_update_profile_social_counts(selected_profile_snapshot)
	_switch_tab(Tab.PROFILE)
	call_deferred("_refresh_selected_profile_async")

func _show_external_profile_popup(profile_data: Dictionary, active_server: Dictionary = {}) -> void:
	_ensure_home_friend_popup()
	if home_friend_popup == null:
		return
	_prepare_home_friend_popup_surface()
	_clear_container(home_friend_popup)
	home_friend_popup.custom_minimum_size = Vector2(760, 520)
	home_friend_popup.size = Vector2(760, 520)
	var viewport_size := get_viewport_rect().size
	home_friend_popup.global_position = Vector2(
		maxf(20.0, (viewport_size.x - home_friend_popup.size.x) * 0.5),
		maxf(20.0, (viewport_size.y - home_friend_popup.size.y) * 0.5)
	)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	home_friend_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)
	root.add_child(top_row)

	top_row.add_child(_create_home_avatar_preview(profile_data, 150))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	top_row.add_child(info)

	var username_label := Label.new()
	username_label.text = str(profile_data.get("username", selected_profile_username if not selected_profile_username.is_empty() else "Player")).strip_edges()
	username_label.add_theme_font_size_override("font_size", 32)
	username_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09, 1))
	info.add_child(username_label)
	ACCOUNT_BADGES.attach(username_label, profile_data, true)

	var status := Label.new()
	status.text = _get_profile_status_text(profile_data, active_server)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.06, 0.58, 0.2, 1) if status.text != "Offline" else Color(0.42, 0.44, 0.48, 1))
	info.add_child(status)

	var join_date := Label.new()
	join_date.text = _format_profile_join_label(profile_data)
	join_date.add_theme_font_size_override("font_size", 12)
	join_date.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	info.add_child(join_date)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	info.add_child(stats)
	for stat in [
		["Friends", int(profile_data.get("friends_count", 0))],
		["Followers", int(profile_data.get("followers_count", 0))],
		["Following", int(profile_data.get("following_count", 0))]
	]:
		var stat_box := VBoxContainer.new()
		var stat_num := Label.new()
		stat_num.text = str(maxi(int(stat[1]), 0))
		stat_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_num.add_theme_font_size_override("font_size", 18)
		stat_num.add_theme_color_override("font_color", Color(0.0, 0.55, 0.8, 1))
		stat_box.add_child(stat_num)
		var stat_name := Label.new()
		stat_name.text = str(stat[0])
		stat_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_name.add_theme_font_size_override("font_size", 11)
		stat_name.add_theme_color_override("font_color", Color(0.48, 0.5, 0.54, 1))
		stat_box.add_child(stat_name)
		stats.add_child(stat_box)

	var divider := ColorRect.new()
	divider.color = Color(0.86, 0.86, 0.86, 1)
	divider.custom_minimum_size = Vector2(0, 1)
	root.add_child(divider)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 14)
	root.add_child(content_row)

	var about_panel := Panel.new()
	about_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about_panel.custom_minimum_size = Vector2(0, 180)
	about_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	content_row.add_child(about_panel)
	var about_margin := MarginContainer.new()
	about_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	about_margin.add_theme_constant_override("margin_left", 16)
	about_margin.add_theme_constant_override("margin_top", 14)
	about_margin.add_theme_constant_override("margin_right", 16)
	about_margin.add_theme_constant_override("margin_bottom", 14)
	about_panel.add_child(about_margin)
	var about_box := VBoxContainer.new()
	about_box.add_theme_constant_override("separation", 8)
	about_margin.add_child(about_box)
	var about_title := Label.new()
	about_title.text = "About"
	about_title.add_theme_font_size_override("font_size", 18)
	about_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.13, 1))
	about_box.add_child(about_title)
	var about_text := Label.new()
	about_text.text = str(profile_data.get("bio", "This player has not written an about section yet.")).strip_edges()
	if about_text.text.is_empty():
		about_text.text = "This player has not written an about section yet."
	about_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about_text.add_theme_font_size_override("font_size", 13)
	about_text.add_theme_color_override("font_color", Color(0.34, 0.35, 0.38, 1))
	about_box.add_child(about_text)

	var activity_panel := Panel.new()
	activity_panel.custom_minimum_size = Vector2(250, 180)
	activity_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	content_row.add_child(activity_panel)
	var activity_margin := MarginContainer.new()
	activity_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	activity_margin.add_theme_constant_override("margin_left", 14)
	activity_margin.add_theme_constant_override("margin_top", 14)
	activity_margin.add_theme_constant_override("margin_right", 14)
	activity_margin.add_theme_constant_override("margin_bottom", 14)
	activity_panel.add_child(activity_margin)
	var activity_box := VBoxContainer.new()
	activity_box.add_theme_constant_override("separation", 10)
	activity_margin.add_child(activity_box)
	var activity_title := Label.new()
	activity_title.text = "Activity"
	activity_title.add_theme_font_size_override("font_size", 18)
	activity_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.13, 1))
	activity_box.add_child(activity_title)
	var activity_text := Label.new()
	activity_text.text = _get_profile_status_text(profile_data, active_server)
	activity_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activity_text.add_theme_font_size_override("font_size", 13)
	activity_text.add_theme_color_override("font_color", Color(0.34, 0.35, 0.38, 1))
	activity_box.add_child(activity_text)
	if not active_server.is_empty():
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(0, 42)
		join_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.23, 0.74, 0.42, 1)))
		join_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.3, 0.82, 0.5, 1)))
		join_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.19, 0.63, 0.36, 1)))
		join_btn.add_theme_color_override("font_color", Color.WHITE)
		join_btn.pressed.connect(func():
			home_friend_popup.hide()
			_join_server_flow({
				"name": _resolve_display_game_name(str(active_server.get("map_name", "")).strip_edges(), str(active_server.get("map_id", "")).strip_edges(), "Friend's Game"),
				"map_id": str(active_server.get("map_id", "")).strip_edges(),
				"cloud_version_id": str(active_server.get("cloud_version_id", "")).strip_edges(),
				"icon_path": ""
			}, active_server)
		)
		activity_box.add_child(join_btn)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 38)
	close_btn.pressed.connect(func(): home_friend_popup.hide())
	footer.add_child(close_btn)
	home_friend_popup.show()

func _refresh_external_profile_popup_async(user_id: String, username: String, active_server: Dictionary = {}) -> void:
	var clean_user_id := user_id.strip_edges()
	if clean_user_id.is_empty() or not CloudAPI.is_configured():
		return
	var profile_data := selected_profile_snapshot.duplicate(true)
	var profile_result: Dictionary = await CloudAPI.load_player_profile(clean_user_id)
	if bool(profile_result.get("ok", false)) and profile_result.get("data", {}) is Dictionary:
		profile_data = (profile_result.get("data", {}) as Dictionary).duplicate(true)
	if not username.strip_edges().is_empty():
		profile_data["username"] = str(profile_data.get("username", username)).strip_edges()
	var outfit_result: Dictionary = await CloudAPI.load_avatar_outfit(clean_user_id)
	if bool(outfit_result.get("ok", false)) and outfit_result.get("data", {}) is Dictionary:
		var outfit: Dictionary = outfit_result.get("data", {})
		outfit["equipped_avatar_item_payloads"] = await _load_profile_equipped_avatar_item_payloads(profile_data, outfit)
		profile_data["avatar_outfit"] = outfit
		var avatar_data: Dictionary = profile_data.get("avatar_data", {}) if profile_data.get("avatar_data", {}) is Dictionary else {}
		for pair in [
			["head_color", "head"],
			["torso_color", "torso"],
			["left_arm_color", "left_arm"],
			["right_arm_color", "right_arm"],
			["left_leg_color", "left_leg"],
			["right_leg_color", "right_leg"]
		]:
			if outfit.has(pair[0]) and not str(outfit.get(pair[0], "")).strip_edges().is_empty():
				avatar_data[pair[1]] = outfit.get(pair[0])
		profile_data["avatar_data"] = avatar_data
	if CloudAPI.has_method("count_friends_for_user"):
		var friend_count_result: Dictionary = await CloudAPI.count_friends_for_user(clean_user_id)
		if bool(friend_count_result.get("ok", false)):
			profile_data["friends_count"] = int(friend_count_result.get("count", CloudAPI._extract_array_payload(friend_count_result.get("data", [])).size()))
	if CloudAPI.has_method("get_follow_counts_for_user"):
		var follow_counts_result: Dictionary = await CloudAPI.get_follow_counts_for_user(clean_user_id)
		if bool(follow_counts_result.get("ok", false)) and follow_counts_result.get("data", {}) is Dictionary:
			var follow_counts: Dictionary = follow_counts_result.get("data", {})
			profile_data["followers_count"] = int(follow_counts.get("followers_count", profile_data.get("followers_count", 0)))
			profile_data["following_count"] = int(follow_counts.get("following_count", profile_data.get("following_count", 0)))
	if home_friend_popup != null and home_friend_popup.visible and selected_profile_user_id == clean_user_id:
		_show_external_profile_popup(profile_data, active_server)

func _apply_profile_snapshot_to_ui(profile_data: Dictionary, active_server: Dictionary = {}) -> void:
	if _is_profile_snapshot_current_user(profile_data):
		profile_data = _merge_current_session_avatar_into_profile(profile_data)
	var resolved_username: String = str(profile_data.get("username", selected_profile_username)).strip_edges()
	if resolved_username.is_empty():
		resolved_username = selected_profile_username if not selected_profile_username.is_empty() else (UserSession.username if UserSession.is_logged_in else "Player")
	if profile_username_label:
		profile_username_label.text = resolved_username
	if join_date_label:
		join_date_label.text = _format_profile_join_label(profile_data)
	if profile_status_label:
		profile_status_label.text = _get_profile_status_text(profile_data, active_server)
		profile_status_label.add_theme_color_override("font_color", Color(0.1, 0.55, 0.24, 1) if profile_status_label.text != "Offline" else Color(0.42, 0.44, 0.48, 1))
	_refresh_profile_header_avatar_snapshot(profile_data)
	var profile_preview_targets: Array = [profile_header_preview_player, profile_preview_player]
	var has_preview_target: bool = false
	for preview_target in profile_preview_targets:
		if preview_target != null:
			has_preview_target = true
			preview_target.head_color = _get_profile_avatar_color(profile_data, "head", Color(0.96, 0.8, 0.2))
			preview_target.torso_color = _get_profile_avatar_color(profile_data, "torso", Color(0.05, 0.4, 0.7))
			preview_target.left_arm_color = _get_profile_avatar_color(profile_data, "left_arm", Color(0.96, 0.8, 0.2))
			preview_target.right_arm_color = _get_profile_avatar_color(profile_data, "right_arm", Color(0.96, 0.8, 0.2))
			preview_target.left_leg_color = _get_profile_avatar_color(profile_data, "left_leg", Color(0.65, 0.8, 0.2))
			preview_target.right_leg_color = _get_profile_avatar_color(profile_data, "right_leg", Color(0.65, 0.8, 0.2))
			var snapshot_outfit: Dictionary = profile_data.get("avatar_outfit", {}) if profile_data.get("avatar_outfit", {}) is Dictionary else {}
			_apply_profile_avatar_visuals_to_preview(preview_target, profile_data, snapshot_outfit)
	if not has_preview_target:
		return

func _refresh_selected_profile_async() -> void:
	if not CloudAPI.is_configured():
		return
	var target_user_id: String = selected_profile_user_id if not selected_profile_user_id.is_empty() else UserSession.user_id
	if target_user_id.is_empty():
		return
	if not CloudAPI.has_authenticated_session():
		var preferred_username: String = UserSession.username if UserSession.is_logged_in else CloudAPI.get_current_username()
		await CloudAPI.authenticate_or_create_profile(preferred_username)
	var profile_data: Dictionary = selected_profile_snapshot.duplicate(true)
	var active_server: Dictionary = selected_profile_active_server.duplicate(true)
	var profile_result: Dictionary = await CloudAPI.load_player_profile(target_user_id)
	if bool(profile_result.get("ok", false)) and profile_result.get("data", {}) is Dictionary:
		profile_data = (profile_result.get("data", {}) as Dictionary).duplicate(true)
	elif profile_data.is_empty():
		return
	var is_own_profile := target_user_id == str(UserSession.user_id).strip_edges()
	if is_own_profile:
		profile_data = _merge_current_session_avatar_into_profile(profile_data)
	var resolved_username: String = str(profile_data.get("username", selected_profile_username)).strip_edges()
	if resolved_username.is_empty():
		resolved_username = UserSession.username if UserSession.is_logged_in else "Player"
	selected_profile_user_id = target_user_id
	selected_profile_username = resolved_username
	selected_profile_snapshot = profile_data.duplicate(true)
	if profile_username_label:
		profile_username_label.text = resolved_username
		ACCOUNT_BADGES.attach(profile_username_label, profile_data, true)
	if sidebar_username and target_user_id == UserSession.user_id:
		sidebar_username.text = resolved_username
		ACCOUNT_BADGES.attach(sidebar_username, profile_data)
	var active_server_lookup: Dictionary = {}
	var active_servers_result: Dictionary = await CloudAPI.fetch_active_servers("", 64, 3.0, 1)
	if bool(active_servers_result.get("ok", false)):
		active_server_lookup = _build_server_lookup_by_user(CloudAPI._extract_array_payload(active_servers_result.get("data", [])))
		var matched_by_id: Variant = active_server_lookup.get(target_user_id, {})
		if matched_by_id is Dictionary:
			active_server = matched_by_id
		else:
			var matched_by_name: Variant = active_server_lookup.get(resolved_username.to_lower(), {})
			if matched_by_name is Dictionary:
				active_server = matched_by_name
	selected_profile_active_server = active_server.duplicate(true)
	var resolved_friend_count: int = int(profile_data.get("friends_count", 0))
	if CloudAPI.has_method("count_friends_for_user"):
		var friend_count_result: Dictionary = await CloudAPI.count_friends_for_user(target_user_id)
		if bool(friend_count_result.get("ok", false)):
			resolved_friend_count = int(friend_count_result.get("count", CloudAPI._extract_array_payload(friend_count_result.get("data", [])).size()))
			profile_data["friends_count"] = resolved_friend_count
	elif target_user_id == UserSession.user_id:
		var own_friends_result: Dictionary = await CloudAPI.get_friends_list()
		if bool(own_friends_result.get("ok", false)):
			resolved_friend_count = CloudAPI._extract_array_payload(own_friends_result.get("data", [])).size()
			profile_data["friends_count"] = resolved_friend_count
	if CloudAPI.has_method("get_follow_counts_for_user"):
		var follow_counts_result: Dictionary = await CloudAPI.get_follow_counts_for_user(target_user_id)
		if bool(follow_counts_result.get("ok", false)) and follow_counts_result.get("data", {}) is Dictionary:
			var follow_counts: Dictionary = follow_counts_result.get("data", {})
			profile_data["followers_count"] = int(follow_counts.get("followers_count", profile_data.get("followers_count", 0)))
			profile_data["following_count"] = int(follow_counts.get("following_count", profile_data.get("following_count", 0)))
	_apply_profile_snapshot_to_ui(profile_data, active_server)
	_update_profile_social_counts(profile_data, resolved_friend_count)
	var avatar_outfit: Dictionary = profile_data.get("avatar_outfit", {}).duplicate(true) if profile_data.get("avatar_outfit", {}) is Dictionary else {}
	var avatar_outfit_result: Dictionary = await CloudAPI.load_avatar_outfit(target_user_id)
	if bool(avatar_outfit_result.get("ok", false)) and avatar_outfit_result.get("data", {}) is Dictionary:
		var refreshed_outfit: Dictionary = (avatar_outfit_result.get("data", {}) as Dictionary).duplicate(true)
		if not refreshed_outfit.is_empty():
			avatar_outfit = refreshed_outfit
	if is_own_profile:
		var local_outfit := _build_avatar_outfit_payload()
		for local_key in local_outfit.keys():
			avatar_outfit[local_key] = local_outfit[local_key]
		avatar_outfit["equipped_avatar_item_payloads"] = _get_local_equipped_avatar_item_payloads()
	else:
		avatar_outfit["equipped_avatar_item_payloads"] = await _load_profile_equipped_avatar_item_payloads(profile_data, avatar_outfit)
	profile_data["avatar_outfit"] = avatar_outfit
	selected_profile_snapshot = profile_data.duplicate(true)
	_refresh_profile_header_avatar_snapshot(profile_data)
	var profile_preview_targets: Array = [profile_header_preview_player, profile_preview_player]
	var has_preview_target: bool = false
	for preview_target in profile_preview_targets:
		if preview_target != null:
			has_preview_target = true
	if not has_preview_target:
		_refresh_profile_games_section()
		return
	for preview_target in profile_preview_targets:
		if preview_target == null:
			continue
		preview_target.head_color = _parse_profile_color(avatar_outfit.get("head_color", _get_profile_avatar_color(profile_data, "head", Color(0.96, 0.8, 0.2))), Color(0.96, 0.8, 0.2))
		preview_target.torso_color = _parse_profile_color(avatar_outfit.get("torso_color", _get_profile_avatar_color(profile_data, "torso", Color(0.05, 0.4, 0.7))), Color(0.05, 0.4, 0.7))
		preview_target.left_arm_color = _parse_profile_color(avatar_outfit.get("left_arm_color", _get_profile_avatar_color(profile_data, "left_arm", Color(0.96, 0.8, 0.2))), Color(0.96, 0.8, 0.2))
		preview_target.right_arm_color = _parse_profile_color(avatar_outfit.get("right_arm_color", _get_profile_avatar_color(profile_data, "right_arm", Color(0.96, 0.8, 0.2))), Color(0.96, 0.8, 0.2))
		preview_target.left_leg_color = _parse_profile_color(avatar_outfit.get("left_leg_color", _get_profile_avatar_color(profile_data, "left_leg", Color(0.65, 0.8, 0.2))), Color(0.65, 0.8, 0.2))
		preview_target.right_leg_color = _parse_profile_color(avatar_outfit.get("right_leg_color", _get_profile_avatar_color(profile_data, "right_leg", Color(0.65, 0.8, 0.2))), Color(0.65, 0.8, 0.2))
		_apply_profile_avatar_visuals_to_preview(preview_target, profile_data, avatar_outfit)
	_refresh_profile_currently_wearing(profile_data, avatar_outfit)
	_refresh_profile_games_section()

func _is_profile_snapshot_current_user(profile_data: Dictionary) -> bool:
	if typeof(UserSession) == TYPE_NIL:
		return false
	var own_id := str(UserSession.user_id).strip_edges()
	var own_name := str(UserSession.username).strip_edges().to_lower()
	var profile_id := str(profile_data.get("id", profile_data.get("user_id", selected_profile_user_id))).strip_edges()
	var profile_name := str(profile_data.get("username", selected_profile_username)).strip_edges().to_lower()
	return (not own_id.is_empty() and profile_id == own_id) or (not own_name.is_empty() and profile_name == own_name)

func _merge_current_session_avatar_into_profile(profile_data: Dictionary) -> Dictionary:
	var merged := profile_data.duplicate(true)
	if typeof(UserSession) == TYPE_NIL:
		return merged
	if UserSession.avatar_data is Dictionary:
		merged["avatar_data"] = UserSession.avatar_data.duplicate(true)
	if UserSession.inventory_items is Array:
		merged["inventory_items"] = UserSession.inventory_items.duplicate(true)
	var outfit := _build_avatar_outfit_payload()
	outfit["equipped_avatar_item_payloads"] = _get_local_equipped_avatar_item_payloads()
	merged["avatar_outfit"] = outfit
	return merged

func _update_profile_social_counts(profile_data: Dictionary, resolved_friend_count: int = -1) -> void:
	if profile_friends_count_label:
		var friend_count: int = resolved_friend_count if resolved_friend_count >= 0 else int(profile_data.get("friends_count", 0))
		profile_friends_count_label.text = str(maxi(friend_count, 0))
	if profile_followers_count_label:
		profile_followers_count_label.text = str(maxi(int(profile_data.get("followers_count", 0)), 0))
	if profile_following_count_label:
		profile_following_count_label.text = str(maxi(int(profile_data.get("following_count", 0)), 0))

func _apply_profile_avatar_visuals_to_preview(preview_target: Node, profile_data: Dictionary, avatar_outfit: Dictionary = {}) -> void:
	if preview_target == null:
		return
	preview_target.set("use_local_avatar_fallback", false)
	preview_target.set("render_avatar_visual_decals", true)
	preview_target.set("render_avatar_clothing_decals", true)
	preview_target.set("face_texture_path", _get_profile_avatar_texture_path(profile_data, avatar_outfit, "face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH, false))
	preview_target.set("chest_badge_texture_path", _get_profile_avatar_texture_path(profile_data, avatar_outfit, "chest_badge_texture_path", "", true))
	preview_target.set("shirt_texture_path", _get_profile_avatar_texture_path(profile_data, avatar_outfit, "shirt_texture_path", "", true))
	preview_target.set("pants_texture_path", _get_profile_avatar_texture_path(profile_data, avatar_outfit, "pants_texture_path", "", true))
	preview_target.set("equipped_avatar_items", avatar_outfit.get("equipped_avatar_item_payloads", []) if avatar_outfit.get("equipped_avatar_item_payloads", []) is Array else [])
	if preview_target.has_method("force_avatar_visual_refresh"):
		preview_target.call_deferred("force_avatar_visual_refresh")
	elif preview_target.has_method("_apply_avatar_visuals_if_needed"):
		preview_target.call_deferred("_apply_avatar_visuals_if_needed")

func _refresh_profile_currently_wearing(profile_data: Dictionary, avatar_outfit: Dictionary = {}) -> void:
	if profile_wearing_items_container == null:
		return
	_clear_children_immediate(profile_wearing_items_container)
	var items: Array = _collect_profile_equipped_avatar_item_payloads(profile_data, avatar_outfit)
	var profile_shirt_texture := str(_get_profile_avatar_texture_path(profile_data, avatar_outfit, "shirt_texture_path", "", true)).strip_edges()
	if not profile_shirt_texture.is_empty():
		items.append({"name": "Shirt", "category": "Shirt", "thumbnail": profile_shirt_texture})
	var profile_pants_texture := str(_get_profile_avatar_texture_path(profile_data, avatar_outfit, "pants_texture_path", "", true)).strip_edges()
	if not profile_pants_texture.is_empty():
		items.append({"name": "Pants", "category": "Pants", "thumbnail": profile_pants_texture})
	var seen: Dictionary = {}
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		var item_id := str(item.get("id", item.get("item_id", item.get("name", "")))).strip_edges()
		if item_id.is_empty() or seen.has(item_id):
			continue
		seen[item_id] = true
		profile_wearing_items_container.add_child(_create_profile_wearing_item_card(item))
	var has_items := seen.size() > 0
	if profile_wearing_empty_label != null:
		profile_wearing_empty_label.visible = not has_items
	profile_wearing_items_container.visible = has_items

func _create_profile_wearing_item_card(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 196)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var preview := _create_profile_wearing_item_preview(item)
	preview.custom_minimum_size = Vector2(134, 112)
	box.add_child(preview)
	var name_label := Label.new()
	name_label.text = str(item.get("name", item.get("id", "Avatar Item"))).strip_edges()
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(134, 24)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
	box.add_child(name_label)
	var kind_label := Label.new()
	kind_label.text = str(item.get("category", item.get("item_kind", item.get("asset_type", "Item")))).capitalize()
	kind_label.clip_text = true
	kind_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kind_label.add_theme_font_size_override("font_size", 12)
	kind_label.add_theme_color_override("font_color", Color(0.48, 0.49, 0.53, 1))
	box.add_child(kind_label)
	return panel

func _create_profile_wearing_item_preview(item: Dictionary) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(134, 112)
	holder.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.95, 0.97, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.82, 0.84, 0.88, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	holder.add_theme_stylebox_override("panel", style)
	var thumbnail_path := _resolve_profile_wearing_item_thumbnail(item)
	if not thumbnail_path.is_empty():
		var rect := TextureRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.offset_left = 4
		rect.offset_top = 4
		rect.offset_right = -4
		rect.offset_bottom = -4
		holder.add_child(rect)
		if _is_http_url(thumbnail_path):
			_load_remote_game_icon_async(thumbnail_path, rect)
			return holder
		if FileAccess.file_exists(thumbnail_path) or _is_inline_image_data(thumbnail_path):
			var image := _load_icon_image(thumbnail_path)
			if image != null:
				image.resize(134, 112, Image.INTERPOLATE_LANCZOS)
				rect.texture = ImageTexture.create_from_image(image)
				return holder
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.text = str(item.get("name", item.get("category", "I"))).left(1).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.48, 0.5, 0.56, 1))
	holder.add_child(label)
	return holder

func _resolve_profile_wearing_item_thumbnail(item: Dictionary) -> String:
	var sources: Array = [item]
	for key in ["data", "metadata", "model_data", "asset_data", "payload", "record", "row"]:
		if item.has(key):
			var nested := _dictionary_from_jsonish_variant(item.get(key))
			if not nested.is_empty():
				sources.append(nested)
	for source_variant in sources:
		if not (source_variant is Dictionary):
			continue
		var source: Dictionary = source_variant
		for key in ["thumbnail", "thumbnail_url", "preview_thumbnail", "preview_path", "template_url", "source_url", "source_file_url", "source_model_path", "icon_path"]:
			var value := str(source.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	return ""

func _load_profile_equipped_avatar_item_payloads(profile_data: Dictionary, avatar_outfit: Dictionary) -> Array:
	var ids := _collect_profile_equipped_avatar_item_ids(profile_data, avatar_outfit)
	var direct_payloads := _collect_profile_equipped_avatar_item_payloads(profile_data, avatar_outfit)
	var result: Array = []
	var resolved_ids: Array = []
	for raw_payload in direct_payloads:
		if not (raw_payload is Dictionary):
			continue
		var payload := (raw_payload as Dictionary).duplicate(true)
		var payload_id := _profile_avatar_item_id(payload)
		if not payload_id.is_empty() and not (payload_id in resolved_ids):
			result.append(payload)
			resolved_ids.append(payload_id)
	var unresolved_ids: Array = []
	for raw_id in ids:
		var clean_id := str(raw_id).strip_edges()
		if not clean_id.is_empty() and not (clean_id in resolved_ids):
			unresolved_ids.append(clean_id)
	if unresolved_ids.is_empty() or CloudAPI == null or not CloudAPI.is_configured():
		return result
	var marketplace_sources: Array = []
	if CloudAPI.has_method("fetch_avatar_marketplace_items"):
		var avatar_result: Dictionary = await CloudAPI.fetch_avatar_marketplace_items(240, true, false)
		if bool(avatar_result.get("ok", false)):
			marketplace_sources.append_array(_extract_response_array(avatar_result))
	if CloudAPI.has_method("fetch_marketplace_models"):
		var model_result: Dictionary = await CloudAPI.fetch_marketplace_models(240, true, false)
		if bool(model_result.get("ok", false)):
			marketplace_sources.append_array(_extract_response_array(model_result))
	for source_variant in marketplace_sources:
		if not (source_variant is Dictionary):
			continue
		var source := source_variant as Dictionary
		var source_id := _profile_avatar_item_id(source)
		if source_id in unresolved_ids and not (source_id in resolved_ids):
			result.append(source.duplicate(true))
			resolved_ids.append(source_id)
	return result

func _collect_profile_equipped_avatar_item_ids(profile_data: Dictionary, avatar_outfit: Dictionary) -> Array:
	var ids: Array = []
	for payload in _collect_profile_equipped_avatar_item_payloads(profile_data, avatar_outfit):
		if payload is Dictionary:
			var payload_id := _profile_avatar_item_id(payload as Dictionary)
			if not payload_id.is_empty() and not (payload_id in ids):
				ids.append(payload_id)
	for source_variant in _profile_avatar_sources(profile_data, avatar_outfit):
		if not (source_variant is Dictionary):
			continue
		var source: Dictionary = source_variant
		for key in ["equipped_items", "equipped", "avatar_items", "equipped_avatar_items"]:
			var raw_entries: Variant = source.get(key, [])
			if not (raw_entries is Array):
				continue
			for raw_entry in raw_entries:
				var item_id := ""
				if raw_entry is Dictionary:
					item_id = _profile_avatar_item_id(raw_entry as Dictionary)
				else:
					item_id = str(raw_entry).strip_edges()
				if not item_id.is_empty() and not (item_id in ids):
					ids.append(item_id)
	return ids

func _collect_profile_equipped_avatar_item_payloads(profile_data: Dictionary, avatar_outfit: Dictionary) -> Array:
	var payloads: Array = []
	for source_variant in _profile_avatar_sources(profile_data, avatar_outfit):
		if not (source_variant is Dictionary):
			continue
		var source: Dictionary = source_variant
		var raw_payloads: Variant = source.get("equipped_avatar_item_payloads", [])
		if raw_payloads is Array:
			for raw_payload in raw_payloads:
				if raw_payload is Dictionary:
					payloads.append(raw_payload)
	return payloads

func _profile_avatar_sources(profile_data: Dictionary, avatar_outfit: Dictionary) -> Array:
	var sources: Array = [avatar_outfit]
	var avatar_data: Dictionary = profile_data.get("avatar_data", {}) if profile_data.get("avatar_data", {}) is Dictionary else {}
	if not avatar_data.is_empty():
		sources.append(avatar_data)
	var nested_outfit: Dictionary = profile_data.get("avatar_outfit", {}) if profile_data.get("avatar_outfit", {}) is Dictionary else {}
	if not nested_outfit.is_empty():
		sources.append(nested_outfit)
	sources.append(profile_data)
	return sources

func _profile_avatar_item_id(item: Dictionary) -> String:
	for key in ["id", "item_id", "avatar_item_id", "catalog_item_id"]:
		var value := str(item.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _get_profile_avatar_texture_path(profile_data: Dictionary, avatar_outfit: Dictionary, texture_key: String, fallback: String, allow_empty: bool) -> String:
	var avatar_data_source: Dictionary = {}
	var raw_avatar_data: Variant = profile_data.get("avatar_data", {})
	if raw_avatar_data is Dictionary:
		avatar_data_source = raw_avatar_data
	var sources: Array = [avatar_outfit, avatar_data_source]
	for source_variant in sources:
		if not (source_variant is Dictionary):
			continue
		var source_dict: Dictionary = source_variant
		if source_dict.has(texture_key):
			var direct_value: String = str(source_dict.get(texture_key, "")).strip_edges()
			if not direct_value.is_empty() or allow_empty:
				return direct_value
		var legacy_key: String = texture_key.replace("_texture_path", "_path")
		if source_dict.has(legacy_key):
			var legacy_value: String = str(source_dict.get(legacy_key, "")).strip_edges()
			if not legacy_value.is_empty() or allow_empty:
				return legacy_value
	if allow_empty:
		return ""
	return fallback

func _get_profile_avatar_color(profile_data: Dictionary, part_key: String, fallback: Color) -> Color:
	var avatar_data: Dictionary = profile_data.get("avatar_data", {}) if profile_data.get("avatar_data", {}) is Dictionary else {}
	var nested_body_colors: Dictionary = avatar_data.get("body_colors", {}) if avatar_data.get("body_colors", {}) is Dictionary else {}
	var direct_color_key: String = "%s_color" % part_key
	if avatar_data.has(part_key):
		return _parse_profile_color(avatar_data.get(part_key), fallback)
	if avatar_data.has(direct_color_key):
		return _parse_profile_color(avatar_data.get(direct_color_key), fallback)
	if nested_body_colors.has(part_key):
		return _parse_profile_color(nested_body_colors.get(part_key), fallback)
	if nested_body_colors.has(direct_color_key):
		return _parse_profile_color(nested_body_colors.get(direct_color_key), fallback)
	return fallback

func _parse_profile_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Dictionary:
		var color_dict: Dictionary = value
		if color_dict.has("r") and color_dict.has("g") and color_dict.has("b"):
			return Color(
				float(color_dict.get("r", fallback.r)),
				float(color_dict.get("g", fallback.g)),
				float(color_dict.get("b", fallback.b)),
				float(color_dict.get("a", fallback.a))
			)
	var raw: String = str(value).strip_edges()
	if raw.begins_with("#") and (raw.length() == 7 or raw.length() == 9):
		return Color(raw)
	return fallback

func _create_social_avatar_preview(profile: Dictionary, size_px: int = 72) -> Control:
	var friends_builder := load("res://scripts/lobby/friends_builder.gd")
	if friends_builder != null:
		return friends_builder._create_round_avatar_preview(profile, size_px)
	var fallback := ColorRect.new()
	fallback.custom_minimum_size = Vector2(size_px, size_px)
	fallback.color = Color(0.88, 0.9, 0.93, 1)
	return fallback

func _format_profile_join_label(profile_data: Dictionary) -> String:
	var raw_join_date: String = str(profile_data.get("join_date", profile_data.get("created_at", ""))).strip_edges()
	if raw_join_date.is_empty():
		return "Joined recently"
	var date_only: String = raw_join_date.substr(0, 10)
	var parts: PackedStringArray = date_only.split("-")
	if parts.size() == 3:
		return "Joined %s.%s.%s" % [parts[2], parts[1], parts[0]]
	return "Joined %s" % date_only

func _refresh_continue_playing_section() -> void:
	if CloudAPI != null and CloudAPI.is_configured() and not _lobby_bootstrap_active:
		await _refresh_published_game_cache(false)
	var entries: Array = _get_continue_playing_entries()
	var fallback_entries: Array = _get_all_home_entries(_get_cached_discover_entries())
	entries = _fill_home_entries_to_limit(entries, fallback_entries, HOME_CONTINUE_RENDER_LIMIT)
	var content_signature := _home_game_entries_signature(entries, HOME_CONTINUE_RENDER_LIMIT, false)
	if _home_game_container_matches_signature(continue_cards_container, content_signature):
		if continue_status_label:
			continue_status_label.text = "Your recent games are ready."
		return
	_clear_container(continue_cards_container)
	_clear_home_game_container_signature(continue_cards_container)
	if continue_status_label:
		continue_status_label.text = "Your recent games are ready."
	if entries.is_empty():
		if continue_status_label:
			continue_status_label.text = "No recent games yet. Create or join a game to see it here."
		var empty_label := Label.new()
		empty_label.text = "No recent games yet."
		empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
		continue_cards_container.add_child(empty_label)
		return
	var rendered_count: int = 0
	for entry_variant in entries:
		if rendered_count >= HOME_CONTINUE_RENDER_LIMIT:
			break
		if entry_variant is Dictionary:
			continue_cards_container.add_child(_create_smart_play_card(entry_variant, false, true))
			rendered_count += 1
	continue_cards_container.set_meta("bobux_content_signature", content_signature)

func _refresh_discover_section() -> void:
	if _lobby_bootstrap_active:
		_discover_refresh_pending = true
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_discover_refresh_allowed_msec:
		_discover_refresh_pending = false
		return
	if _discover_refresh_in_flight:
		_discover_refresh_pending = true
		return
	_discover_refresh_in_flight = true
	_discover_refresh_token += 1
	var refresh_token: int = _discover_refresh_token
	var had_rendered_cards := _home_game_sections_have_rendered_cards()
	if not had_rendered_cards:
		_clear_home_game_sections()
	if recommended_status_label:
		recommended_status_label.text = "Loading recommended experiences..."
	if discover_status_label:
		discover_status_label.text = "Loading all experiences..."
	if new_status_label:
		new_status_label.text = "Loading new experiences..."
	if bobux_creator_status_label:
		bobux_creator_status_label.text = "Loading Bobux creator experiences..."
	if discover_cards_grid == null or discover_cards_grid.get_child_count() == 0:
		_add_discover_loading_placeholders(3)
	var cached_entries: Array = _get_cached_discover_entries()
	if not cached_entries.is_empty():
		if all_status_label:
			all_status_label.text = "Showing cached experiences while refreshing..."
		await _render_home_game_sections(cached_entries, refresh_token)

	var discover_entries: Array = await _build_discover_entries()
	if refresh_token != _discover_refresh_token:
		_discover_refresh_in_flight = false
		_discover_refresh_pending = false
		return
	if discover_entries.is_empty():
		# A transient network/VPN failure must not destroy already rendered cards
		# under the user's pointer. Keep cached content usable and only show an
		# empty state when there truly was nothing to render.
		if had_rendered_cards or not cached_entries.is_empty():
			if recommended_status_label:
				recommended_status_label.text = "Showing cached recommendations."
			if new_status_label:
				new_status_label.text = "Showing cached new experiences."
			if all_status_label:
				all_status_label.text = "Showing cached experiences."
			if bobux_creator_status_label:
				bobux_creator_status_label.text = "Showing cached creator experiences."
			_discover_refresh_in_flight = false
			_discover_refresh_pending = false
			_next_discover_refresh_allowed_msec = Time.get_ticks_msec() + DISCOVER_FAILURE_RETRY_MS
			return
		_clear_home_game_sections()
		if recommended_status_label:
			recommended_status_label.text = "No recommended experiences yet."
		if new_status_label:
			new_status_label.text = "No new experiences yet."
		if all_status_label:
			all_status_label.text = "No published experiences found yet."
		if bobux_creator_status_label:
			bobux_creator_status_label.text = "No Bobux creator experiences yet."
		_add_grid_placeholder(recommended_cards_grid, "No recommended experiences yet.")
		_add_grid_placeholder(new_cards_grid, "No new experiences yet.")
		_add_grid_placeholder(all_cards_grid, "Create or publish a place from the Develop tab!")
		_add_creator_placeholder(bobux_creator_cards_grid, "Creator picks from pavelord will appear here.")
		_discover_refresh_in_flight = false
		_discover_refresh_pending = false
		_next_discover_refresh_allowed_msec = Time.get_ticks_msec() + DISCOVER_FAILURE_RETRY_MS
		return

	await _render_home_game_sections(discover_entries, refresh_token)
	_discover_refresh_in_flight = false
	_discover_refresh_pending = false
	_next_discover_refresh_allowed_msec = 0

func _clear_home_game_sections() -> void:
	for container in [recommended_cards_grid, new_cards_grid, all_cards_grid, bobux_creator_cards_grid]:
		_clear_children_immediate(container)
		_clear_home_game_container_signature(container)

func _home_game_sections_have_rendered_cards() -> bool:
	for container in [recommended_cards_grid, new_cards_grid, all_cards_grid, bobux_creator_cards_grid]:
		if _home_game_container_has_cards(container):
			return true
	return false

func _home_game_container_has_cards(container: Node) -> bool:
	if container == null:
		return false
	for child in container.get_children():
		if child is Control and (child as Control).name == "SmartPlayCard":
			return true
	return false

func _clear_home_game_container_signature(container: Node) -> void:
	if container != null and container.has_meta("bobux_content_signature"):
		container.remove_meta("bobux_content_signature")

func _home_game_container_matches_signature(container: Node, signature: String) -> bool:
	return (
		container != null
		and _home_game_container_has_cards(container)
		and str(container.get_meta("bobux_content_signature", "")) == signature
	)

func _home_game_entries_signature(entries: Array, limit: int, show_active_players: bool) -> String:
	var signature_rows: Array = []
	var target_count: int = entries.size() if limit <= 0 else mini(entries.size(), limit)
	for index in range(target_count):
		var entry_variant: Variant = entries[index]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		signature_rows.append({
			"id": str(entry.get("id", entry.get("map_id", ""))),
			"name": str(entry.get("name", "")),
			"thumbnail": str(entry.get("thumbnail", entry.get("thumbnail_url", entry.get("icon_url", "")))),
			"active": int(entry.get("active_players", 0)) if show_active_players else -1,
			"visits": int(entry.get("visits", entry.get("visits_count", entry.get("plays", 0)))),
			"rating_positive": int(entry.get("rating_positive", -1)),
			"rating_negative": int(entry.get("rating_negative", 0)),
			"likes": int(entry.get("likes", entry.get("likes_count", 0)))
		})
	return JSON.stringify(signature_rows).sha256_text()

func _render_home_game_sections(entries: Array, refresh_token: int) -> void:
	if refresh_token != _discover_refresh_token or _lobby_exiting or not is_inside_tree():
		return
	_home_layout_entries = entries.duplicate()
	_home_layout_columns = _get_home_game_grid_columns()
	_home_render_generation += 1
	var generation := _home_render_generation
	var recommended_entries: Array = _get_recommended_home_entries(entries)
	var new_entries: Array = _get_new_home_entries(entries)
	var all_entries: Array = _get_all_home_entries(entries)
	var compact_columns: int = _get_home_game_grid_columns()
	var recommended_limit: int = compact_columns
	recommended_entries = _fill_home_entries_to_limit(recommended_entries, all_entries, compact_columns)
	new_entries = _fill_home_entries_to_limit(new_entries, all_entries, compact_columns)
	await _populate_home_game_grid(recommended_cards_grid, recommended_entries, recommended_limit, refresh_token, recommended_status_label, "No recommended experiences yet.", true)
	if generation != _home_render_generation or not is_inside_tree(): return
	_refresh_bobux_creator_section(entries, refresh_token)
	await _populate_home_game_grid(new_cards_grid, new_entries, compact_columns, refresh_token, new_status_label, "No new experiences yet.", true)
	if generation != _home_render_generation or not is_inside_tree(): return
	await _populate_home_game_grid(all_cards_grid, all_entries, 0, refresh_token, all_status_label, "No published experiences found yet.", true)

func _populate_home_game_grid(grid: GridContainer, entries: Array, limit: int, refresh_token: int, status_label: Label, empty_text: String, show_active_players: bool) -> void:
	if not is_instance_valid(grid) or refresh_token != _discover_refresh_token or not is_inside_tree():
		return
	var generation := int(grid.get_meta("populate_generation", 0)) + 1
	grid.set_meta("populate_generation", generation)
	entries = _fill_home_entries_to_limit(entries, [], entries.size())
	var content_signature := _home_game_entries_signature(entries, limit, show_active_players)
	if _home_game_container_matches_signature(grid, content_signature):
		grid.columns = _get_home_game_grid_columns()
		if status_label:
			var stable_count: int = entries.size() if limit <= 0 else mini(entries.size(), limit)
			status_label.text = "%d of %d experience(s) shown" % [stable_count, entries.size()]
		return
	_clear_children_immediate(grid)
	_clear_home_game_container_signature(grid)
	grid.columns = _get_home_game_grid_columns()
	if entries.is_empty():
		if status_label:
			status_label.text = empty_text
		_add_grid_placeholder(grid, empty_text)
		return
	var added_count: int = 0
	var target_count: int = entries.size() if limit <= 0 else mini(entries.size(), limit)
	for entry_variant in entries:
		if refresh_token != _discover_refresh_token or not is_instance_valid(grid) or not is_inside_tree() or int(grid.get_meta("populate_generation", 0)) != generation:
			return
		if limit > 0 and added_count >= limit:
			break
		if entry_variant is Dictionary:
			grid.add_child(_create_smart_play_card(entry_variant, show_active_players))
			added_count += 1
			if status_label:
				status_label.text = "Loaded %d/%d experience(s)" % [added_count, target_count]
			if added_count % 2 == 0:
				await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(grid) or int(grid.get_meta("populate_generation", 0)) != generation: return
	if status_label:
		status_label.text = "%d of %d experience(s) shown" % [added_count, entries.size()]
	grid.set_meta("bobux_content_signature", content_signature)

func _get_recommended_home_entries(entries: Array) -> Array:
	var live_entries: Array = []
	var popular_entries: Array = []
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		if _is_bobux_creator_entry(entry):
			continue
		var thumbnail_reference := str(entry.get("thumbnail", entry.get("thumbnail_url", entry.get("icon_url", entry.get("icon_path", ""))))).strip_edges()
		var visits := int(entry.get("visits_count", entry.get("visits", entry.get("plays", 0))))
		var active_players := int(entry.get("active_players", 0))
		if thumbnail_reference.is_empty() or (active_players <= 0 and visits < 10):
			continue
		if active_players > 0:
			live_entries.append(entry)
		else:
			popular_entries.append(entry)
	live_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_players: int = int(a.get("active_players", 0))
		var b_players: int = int(b.get("active_players", 0))
		if a_players == b_players:
			var a_score: int = _get_game_entry_popularity_score(a)
			var b_score: int = _get_game_entry_popularity_score(b)
			if a_score == b_score:
				return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
			return a_score > b_score
		return a_players > b_players
	)
	popular_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_score: int = _get_game_entry_popularity_score(a)
		var b_score: int = _get_game_entry_popularity_score(b)
		if a_score == b_score:
			return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
		return a_score > b_score
	)
	var result: Array = []
	var result_keys: Dictionary = {}
	for entry in live_entries + popular_entries:
		var key := _get_game_entry_recommendation_key(entry)
		if not key.is_empty() and result_keys.has(key):
			continue
		if not key.is_empty():
			result_keys[key] = true
		result.append(entry)
	return result

func _get_new_home_entries(entries: Array) -> Array:
	var result: Array = []
	for entry_variant in entries:
		if entry_variant is Dictionary:
			result.append((entry_variant as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_time: int = _get_game_entry_timestamp(a)
		var b_time: int = _get_game_entry_timestamp(b)
		if a_time == b_time:
			return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
		return a_time > b_time
	)
	return result

func _get_all_home_entries(entries: Array) -> Array:
	var result: Array = []
	for entry_variant in entries:
		if entry_variant is Dictionary:
			result.append((entry_variant as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_has_preview: bool = _game_entry_has_uploaded_preview(a)
		var b_has_preview: bool = _game_entry_has_uploaded_preview(b)
		if a_has_preview != b_has_preview:
			return a_has_preview
		var a_players: int = int(a.get("active_players", 0))
		var b_players: int = int(b.get("active_players", 0))
		if a_players == b_players:
			var a_visits: int = _get_game_entry_visits(a)
			var b_visits: int = _get_game_entry_visits(b)
			if a_visits == b_visits:
				return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
			return a_visits > b_visits
		return a_players > b_players
	)
	return result

func _fill_home_entries_to_limit(primary_entries: Array, fallback_entries: Array, target_count: int) -> Array:
	var result: Array = []
	var used_keys: Dictionary = {}
	for entry_variant in primary_entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var key := _get_game_entry_recommendation_key(entry)
		if not key.is_empty() and used_keys.has(key):
			continue
		if not key.is_empty():
			used_keys[key] = true
		result.append(entry)
		if result.size() >= target_count:
			return result
	for entry_variant in fallback_entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var key := _get_game_entry_recommendation_key(entry)
		if not key.is_empty() and used_keys.has(key):
			continue
		if not key.is_empty():
			used_keys[key] = true
		result.append(entry)
		if result.size() >= target_count:
			return result
	return result

func _get_game_entry_visits(entry: Dictionary) -> int:
	return int(entry.get("visits", entry.get("visits_count", entry.get("plays", 0))))

func _get_game_entry_likes(entry: Dictionary) -> int:
	return int(entry.get("likes", entry.get("likes_count", entry.get("favorites", 0))))

func _get_game_entry_popularity_score(entry: Dictionary) -> int:
	return _get_game_entry_visits(entry) + (_get_game_entry_likes(entry) * 12) + (int(entry.get("active_players", 0)) * 250)

func _get_game_entry_recommendation_key(entry: Dictionary) -> String:
	for key in ["map_id", "id", "cloud_map_id", "cloud_version_id"]:
		var value := str(entry.get(key, "")).strip_edges()
		if not value.is_empty():
			return "map:%s" % value
	return str(entry.get("name", "")).strip_edges().to_lower()

func _game_entry_has_uploaded_preview(entry: Dictionary) -> bool:
	for key in ["icon_path", "thumbnail", "thumbnail_path", "thumbnail_url", "preview_url", "image_url", "cover_url"]:
		var value: String = str(entry.get(key, "")).strip_edges()
		if value.is_empty():
			continue
		if _is_inline_image_data(value) or _is_http_url(value) or FileAccess.file_exists(value):
			return true
	var folder_path: String = str(entry.get("folder", "")).strip_edges()
	if not folder_path.is_empty() and FileAccess.file_exists(folder_path.path_join("icon.png")):
		return true
	return false

func _get_game_entry_timestamp(entry: Dictionary) -> int:
	for key in ["created_at", "updated_at", "cloud_version_id"]:
		var raw_value: String = str(entry.get(key, "")).strip_edges()
		if raw_value.is_empty():
			continue
		var unix_time: int = int(Time.get_unix_time_from_datetime_string(raw_value))
		if unix_time > 0:
			return unix_time
	return 0

func _add_discover_loading_placeholders(count: int) -> void:
	if discover_cards_grid == null:
		return
	for i in range(maxi(count, 0)):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(174.0 if _is_mobile_beta() else 202.0, 252.0)
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.94, 0.94, 0.94, 1)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.84, 0.84, 0.84, 1)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		panel.add_theme_stylebox_override("panel", style)
		discover_cards_grid.add_child(panel)

func _add_discover_cards_progressively(entries: Array, refresh_token: int) -> void:
	var added_count: int = 0
	var target_count: int = mini(entries.size(), HOME_DISCOVER_RENDER_LIMIT)
	if discover_cards_grid != null:
		discover_cards_grid.columns = _get_home_game_grid_columns()
	for entry_variant in entries:
		if refresh_token != _discover_refresh_token or discover_cards_grid == null:
			return
		if added_count >= HOME_DISCOVER_RENDER_LIMIT:
			break
		if entry_variant is Dictionary:
			discover_cards_grid.add_child(_create_smart_play_card(entry_variant, true))
			added_count += 1
			if discover_status_label:
				discover_status_label.text = "Loaded %d/%d experience(s)" % [added_count, target_count]
			if added_count % 2 == 0:
				await get_tree().process_frame
	if discover_status_label:
		discover_status_label.text = "%d of %d experience(s) shown" % [added_count, entries.size()]

func _refresh_bobux_creator_section(entries: Array, refresh_token: int) -> void:
	if refresh_token != _discover_refresh_token or bobux_creator_cards_grid == null:
		return
	var creator_entries: Array = _filter_bobux_creator_entries(entries)
	var content_signature := _home_game_entries_signature(creator_entries, BOBUX_CREATOR_RENDER_LIMIT, true)
	if _home_game_container_matches_signature(bobux_creator_cards_grid, content_signature):
		if bobux_creator_status_label:
			bobux_creator_status_label.text = "%d creator experience(s)" % creator_entries.size()
		return
	_clear_children_immediate(bobux_creator_cards_grid)
	_clear_home_game_container_signature(bobux_creator_cards_grid)
	if creator_entries.is_empty():
		if bobux_creator_status_label:
			bobux_creator_status_label.text = "No creator experiences published yet."
		_add_creator_placeholder(bobux_creator_cards_grid, "Creator picks from pavelord will appear here.")
		return
	if bobux_creator_status_label:
		bobux_creator_status_label.text = "%d creator experience(s)" % creator_entries.size()
	var added_count: int = 0
	for entry_variant in creator_entries:
		if added_count >= BOBUX_CREATOR_RENDER_LIMIT:
			break
		if entry_variant is Dictionary:
			bobux_creator_cards_grid.add_child(_create_smart_play_card(entry_variant, int((entry_variant as Dictionary).get("active_players", 0)) > 0, true))
			added_count += 1
	bobux_creator_cards_grid.set_meta("bobux_content_signature", content_signature)

func _filter_bobux_creator_entries(entries: Array) -> Array:
	var result: Array = []
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		if _is_bobux_creator_entry(entry):
			result.append(entry)
	return result

func _is_bobux_creator_entry(entry: Dictionary) -> bool:
	var creator_name_keys := ["owner_name", "creator", "creator_name", "owner_username", "username", "author", "created_by", "created_by_username"]
	for key in creator_name_keys:
		var creator_name: String = str(entry.get(key, "")).strip_edges().to_lower()
		if creator_name == BOBUX_CREATOR_USERNAME:
			return true
	var creator_id_keys := ["owner_id", "user_id", "creator_id", "host_user_id", "created_by_id"]
	for key in creator_id_keys:
		var owner_id: String = str(entry.get(key, "")).strip_edges().to_lower()
		if owner_id == BOBUX_CREATOR_USERNAME or BOBUX_CREATOR_USER_IDS.has(owner_id):
			return true
	return false

func _add_creator_placeholder(container: Control, text: String) -> void:
	if container == null:
		return
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 56)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(label)
	container.add_child(panel)

func _add_grid_placeholder(grid: GridContainer, text: String) -> void:
	if grid == null:
		return
	grid.columns = 1
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 56)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(label)
	grid.add_child(panel)

func _get_continue_playing_entries() -> Array:
	var entries: Array = []
	for entry_variant in UserSession.recent_games:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant.duplicate(true)
		var entry_map_id: String = str(entry.get("map_id", "")).strip_edges()
		var entry_folder: String = str(entry.get("folder", "")).strip_edges()
		var entry_name: String = str(entry.get("name", "")).strip_edges()
		if entry_map_id.is_empty() and entry_folder.is_empty():
			UserSession.remove_recent_game("", "", entry_name)
			continue
		if not entry_map_id.is_empty() and _published_game_cache_loaded and not _is_published_cloud_game_id(entry_map_id, entry_name):
			UserSession.mark_deleted_game(entry_map_id, entry_name)
			UserSession.remove_recent_game(entry_map_id, entry_folder, entry_name)
			continue
		if _is_deleted_game_entry(entry):
			continue
		if not entry_folder.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(entry_folder)):
			entry["folder"] = ""
		var canonical_record: Dictionary = {}
		if not entry_map_id.is_empty() and _published_game_records_cache.get("id:" + entry_map_id, {}) is Dictionary:
			canonical_record = _published_game_records_cache.get("id:" + entry_map_id, {})
		if canonical_record.is_empty() and not entry_name.is_empty() and _published_game_records_cache.get("name:" + _normalize_map_name_key(entry_name), {}) is Dictionary:
			canonical_record = _published_game_records_cache.get("name:" + _normalize_map_name_key(entry_name), {})
		for canonical_key in ["map_id", "name", "owner_id", "owner_name", "creator", "thumbnail", "icon", "likes", "likes_count", "visits", "visits_count"]:
			if canonical_record.has(canonical_key):
				entry[canonical_key] = canonical_record[canonical_key]
		entry["active_players"] = int(entry.get("active_players", 0))
		entries.append(entry)
	return entries

func _refresh_published_game_cache(force: bool = false) -> void:
	if CloudAPI == null or not CloudAPI.is_configured():
		return
	var now_msec: int = Time.get_ticks_msec()
	if not force and now_msec < _published_game_cache_expires_at_msec and _published_game_cache_loaded:
		return
	var maps_result: Dictionary = await CloudAPI.fetch_published_maps(DISCOVER_PUBLISHED_MAP_LIMIT)
	_published_map_ids_cache.clear()
	_published_map_names_cache.clear()
	_published_game_records_cache.clear()
	_published_game_cache_loaded = false
	_published_game_cache_expires_at_msec = now_msec + 5000
	if not bool(maps_result.get("ok", false)):
		return
	var stable_records: Array = _stabilize_published_map_stats(
		CloudAPI._extract_array_payload(maps_result.get("data", [])),
		_get_cached_published_map_records()
	)
	for map_variant in stable_records:
		if not (map_variant is Dictionary):
			continue
		var map_record: Dictionary = map_variant
		var published_id: String = str(map_record.get("id", map_record.get("map_id", ""))).strip_edges()
		if not published_id.is_empty():
			_published_map_ids_cache[published_id] = true
			_published_game_records_cache["id:" + published_id] = map_record.duplicate(true)
		var published_name_key: String = _normalize_map_name_key(str(map_record.get("name", "")).strip_edges())
		if not published_name_key.is_empty():
			_published_map_names_cache[published_name_key] = true
			_published_game_records_cache["name:" + published_name_key] = map_record.duplicate(true)
	_published_game_cache_loaded = true
	_published_game_cache_expires_at_msec = now_msec + PUBLISHED_GAME_CACHE_TTL_MS

func _is_published_cloud_game_id(map_id: String, game_name: String = "") -> bool:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return false
	if CloudAPI != null and CloudAPI.is_configured() and not _published_game_cache_loaded:
		return false
	if _published_map_ids_cache.is_empty() and _published_map_names_cache.is_empty():
		return false
	if _published_map_ids_cache.has(clean_map_id):
		return true
	var name_key: String = _normalize_map_name_key(game_name.strip_edges())
	return not name_key.is_empty() and _published_map_names_cache.has(name_key)

func _build_discover_entries() -> Array:
	var discover_entries: Array = []
	var active_servers: Array = []
	var active_counts_by_map_id: Dictionary = {}
	var active_counts_by_name: Dictionary = {}
	var sample_server_by_map_id: Dictionary = {}
	var sample_server_by_name: Dictionary = {}
	var published_map_ids: Dictionary = {}
	var published_name_keys: Dictionary = {}

	if CloudAPI.is_configured():
		var servers_result: Dictionary = await CloudAPI.fetch_active_servers("", DISCOVER_ACTIVE_SERVER_LIMIT, 3.0, 1)
		if bool(servers_result.get("ok", false)):
			active_servers = CloudAPI._extract_array_payload(servers_result.get("data", []))
			for server_variant in active_servers:
				if not (server_variant is Dictionary):
					continue
				var server: Dictionary = server_variant
				var players_count: int = int(server.get("players_count", server.get("player_count", 0)))
				var map_id: String = str(server.get("map_id", "")).strip_edges()
				var map_name_key: String = _normalize_map_name_key(_resolve_display_game_name(str(server.get("map_name", "")).strip_edges(), map_id, "Untitled Experience"))
				if not map_id.is_empty():
					active_counts_by_map_id[map_id] = int(active_counts_by_map_id.get(map_id, 0)) + players_count
					if not sample_server_by_map_id.has(map_id):
						sample_server_by_map_id[map_id] = server
				if not map_name_key.is_empty():
					active_counts_by_name[map_name_key] = int(active_counts_by_name.get(map_name_key, 0)) + players_count
					if not sample_server_by_name.has(map_name_key):
						sample_server_by_name[map_name_key] = server
		var maps_result: Dictionary = await CloudAPI.fetch_published_maps(DISCOVER_PUBLISHED_MAP_LIMIT)
		var published_maps: Array = []
		if bool(maps_result.get("ok", false)):
			published_maps = _stabilize_published_map_stats(
				CloudAPI._extract_array_payload(maps_result.get("data", [])),
				_get_cached_published_map_records()
			)
			_save_published_maps_lobby_cache(published_maps)
		else:
			published_maps = _get_cached_published_map_records()
			if not published_maps.is_empty():
				push_warning("[Lobby] Published maps request failed; using cached map list.")
		if not published_maps.is_empty():
			_published_map_ids_cache.clear()
			_published_map_names_cache.clear()
			_published_game_cache_loaded = false
			_published_game_cache_expires_at_msec = Time.get_ticks_msec() + PUBLISHED_GAME_CACHE_TTL_MS
			for map_variant in published_maps:
				if not (map_variant is Dictionary):
					continue
				var map_record: Dictionary = map_variant
				var entry: Dictionary = _make_game_entry_from_cloud_map(map_record)
				if _is_deleted_game_entry(entry):
					continue
				var published_map_id: String = str(entry.get("map_id", "")).strip_edges()
				if not published_map_id.is_empty():
					published_map_ids[published_map_id] = true
					_published_map_ids_cache[published_map_id] = true
				var published_name_key: String = _normalize_map_name_key(str(entry.get("name", "")).strip_edges())
				if not published_name_key.is_empty():
					published_name_keys[published_name_key] = true
					_published_map_names_cache[published_name_key] = true
				entry["active_players"] = _get_active_player_count_for_entry(entry, active_counts_by_map_id, active_counts_by_name)
				var sample_server: Dictionary = _get_sample_server_for_entry(entry, sample_server_by_map_id, sample_server_by_name)
				if not sample_server.is_empty():
					entry["cloud_version_id"] = str(sample_server.get("cloud_version_id", entry.get("cloud_version_id", "")))
				if _is_orphaned_own_cloud_entry(entry):
					continue
				if _should_hide_discover_entry(entry):
					continue
				discover_entries.append(entry)
			_published_game_cache_loaded = true

	for server_variant in active_servers:
		if not (server_variant is Dictionary):
			continue
		var server_entry: Dictionary = server_variant
		var fallback_entry := {
			"name": _resolve_display_game_name(str(server_entry.get("map_name", "Untitled Experience")).strip_edges(), str(server_entry.get("map_id", "")).strip_edges(), "Untitled Experience"),
			"map_id": str(server_entry.get("map_id", "")),
			"cloud_version_id": str(server_entry.get("cloud_version_id", "")),
			"folder": "",
			"icon_path": "",
			"active_players": 0,
			"description": "",
			"source": "cloud"
		}
		if _is_deleted_game_entry(fallback_entry):
			continue
		var fallback_map_id: String = str(fallback_entry.get("map_id", "")).strip_edges()
		var fallback_name_key: String = _normalize_map_name_key(str(fallback_entry.get("name", "")).strip_edges())
		if not fallback_map_id.is_empty() and not published_map_ids.has(fallback_map_id) and not published_name_keys.has(fallback_name_key):
			continue
		if _has_game_entry(discover_entries, _get_game_key(fallback_entry)):
			continue
		fallback_entry["active_players"] = _get_active_player_count_for_entry(fallback_entry, active_counts_by_map_id, active_counts_by_name)
		discover_entries.append(fallback_entry)

	for local_entry_variant in _load_local_map_entries(24):
		if not (local_entry_variant is Dictionary):
			continue
		var local_entry: Dictionary = local_entry_variant
		if _is_local_template_map_entry(local_entry) or not _is_local_entry_owned_by_current_user(local_entry):
			continue
		if _is_deleted_game_entry(local_entry):
			continue
		var merged: bool = false
		for i in range(discover_entries.size()):
			if not (discover_entries[i] is Dictionary):
				continue
			var existing_entry: Dictionary = discover_entries[i]
			if not _game_entries_match(existing_entry, local_entry):
				continue
			var merged_entry: Dictionary = existing_entry.duplicate(true)
			for merge_key in ["folder", "icon_path", "thumbnail", "description"]:
				if str(merged_entry.get(merge_key, "")).strip_edges().is_empty():
					merged_entry[merge_key] = local_entry.get(merge_key, "")
			if str(merged_entry.get("name", "")).strip_edges().is_empty():
				merged_entry["name"] = local_entry.get("name", "")
			discover_entries[i] = merged_entry
			merged = true
			break
		if not merged:
			discover_entries.append(local_entry)

	for cached_entry_variant in _load_cached_cloud_map_entries(128):
		if not (cached_entry_variant is Dictionary):
			continue
		var cached_entry: Dictionary = cached_entry_variant
		if _is_deleted_game_entry(cached_entry) or _should_hide_discover_entry(cached_entry):
			continue
		if _has_game_entry(discover_entries, _get_game_key(cached_entry)):
			continue
		cached_entry["active_players"] = _get_active_player_count_for_entry(cached_entry, active_counts_by_map_id, active_counts_by_name)
		discover_entries.append(cached_entry)

	discover_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_players: int = int(a.get("active_players", 0))
		var b_players: int = int(b.get("active_players", 0))
		if a_players == b_players:
			return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
		return a_players > b_players
	)
	return discover_entries

func _save_published_maps_lobby_cache(published_maps: Array) -> void:
	var cache_records: Array = []
	var stable_records: Array = _stabilize_published_map_stats(published_maps, _get_cached_published_map_records())
	for map_variant in stable_records:
		if map_variant is Dictionary:
			cache_records.append((map_variant as Dictionary).duplicate(true))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOBBY_PUBLISHED_MAP_CACHE_PATH.get_base_dir()))
	_write_json_dictionary(LOBBY_PUBLISHED_MAP_CACHE_PATH, {
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"maps": cache_records
	})

func _stabilize_published_map_stats(current_records: Array, previous_records: Array) -> Array:
	var previous_by_key: Dictionary = {}
	for previous_variant in previous_records:
		if not (previous_variant is Dictionary):
			continue
		var previous: Dictionary = previous_variant
		var previous_id := str(previous.get("id", previous.get("map_id", ""))).strip_edges()
		var previous_name := _normalize_map_name_key(str(previous.get("name", "")))
		if not previous_id.is_empty():
			previous_by_key["id:" + previous_id] = previous
		if not previous_name.is_empty():
			previous_by_key["name:" + previous_name] = previous
	var stabilized: Array = []
	for current_variant in current_records:
		if not (current_variant is Dictionary):
			continue
		var current: Dictionary = (current_variant as Dictionary).duplicate(true)
		var current_id := str(current.get("id", current.get("map_id", ""))).strip_edges()
		var current_name := _normalize_map_name_key(str(current.get("name", "")))
		var previous: Dictionary = {}
		if not current_id.is_empty() and previous_by_key.get("id:" + current_id, {}) is Dictionary:
			previous = previous_by_key.get("id:" + current_id, {})
		if previous.is_empty() and not current_name.is_empty() and previous_by_key.get("name:" + current_name, {}) is Dictionary:
			previous = previous_by_key.get("name:" + current_name, {})
		# A successful map response is authoritative. Reusing the maximum cached
		# value made one bad historical counter permanent and hid valid ordering.
		var likes := int(current.get("likes_count", current.get("likes", previous.get("likes_count", previous.get("likes", 0)))))
		var visits := int(current.get("visits_count", current.get("visits", previous.get("visits_count", previous.get("visits", 0)))))
		current["likes_count"] = likes
		current["visits_count"] = visits
		stabilized.append(current)
	return stabilized

func _get_cached_published_map_records() -> Array:
	var cache: Dictionary = _read_json_dictionary(LOBBY_PUBLISHED_MAP_CACHE_PATH)
	if cache.is_empty():
		return []
	var saved_at_unix: int = int(cache.get("saved_at_unix", 0))
	if saved_at_unix <= 0 or (int(Time.get_unix_time_from_system()) - saved_at_unix) * 1000 > LOBBY_PUBLISHED_MAP_CACHE_TTL_MS:
		return []
	var maps: Array = cache.get("maps", []) if cache.get("maps", []) is Array else []
	var records: Array = []
	for map_variant in maps:
		if map_variant is Dictionary:
			records.append((map_variant as Dictionary).duplicate(true))
	return records

func _get_cached_discover_entries() -> Array:
	var entries: Array = []
	for map_variant in _get_cached_published_map_records():
		if not (map_variant is Dictionary):
			continue
		var entry: Dictionary = _make_game_entry_from_cloud_map(map_variant)
		if _is_deleted_game_entry(entry) or _should_hide_discover_entry(entry):
			continue
		entry["active_players"] = int(entry.get("active_players", 0))
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)
	return entries

func _should_hide_discover_entry(entry: Dictionary) -> bool:
	if _is_deleted_game_entry(entry):
		return true
	var name_key := str(entry.get("name", "")).strip_edges().to_lower()
	var entry_type := str(entry.get("asset_type", entry.get("type", "map"))).strip_edges().to_lower()
	if entry_type not in ["", "map", "place", "experience"]:
		return true
	if name_key.begins_with("_") or name_key.contains("_asset_") or name_key.ends_with("_asset"):
		return true
	return false

func _is_deleted_game_entry(entry: Dictionary) -> bool:
	if UserSession == null:
		return false
	var map_id: String = str(entry.get("map_id", entry.get("cloud_map_id", ""))).strip_edges()
	var game_name: String = str(entry.get("name", "")).strip_edges()
	return UserSession.is_deleted_game(map_id, game_name)

func _is_entry_owned_by_current_user_strict(entry: Dictionary) -> bool:
	if UserSession == null:
		return false
	var current_user_id: String = str(UserSession.user_id).strip_edges().to_lower()
	var current_username: String = str(UserSession.username).strip_edges().to_lower()
	for key in ["owner_id", "user_id", "creator_id", "host_user_id", "created_by_id"]:
		var owner_id := str(entry.get(key, "")).strip_edges().to_lower()
		if not current_user_id.is_empty() and owner_id == current_user_id:
			return true
	for key in ["owner_name", "creator", "creator_name", "owner_username", "username", "author", "created_by", "created_by_username"]:
		var creator_name := str(entry.get(key, "")).strip_edges().to_lower()
		if not current_username.is_empty() and creator_name == current_username:
			return true
	var map_id: String = str(entry.get("map_id", entry.get("cloud_map_id", ""))).strip_edges().to_lower()
	return not current_user_id.is_empty() and map_id.begins_with(current_user_id + "_")

func _is_orphaned_own_cloud_entry(_entry: Dictionary) -> bool:
	return false

func _build_server_lookup_by_user(active_servers: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for server_variant in active_servers:
		if not (server_variant is Dictionary):
			continue
		var server: Dictionary = server_variant
		var server_last_seen: int = int(server.get("last_seen", 0))
		var lookup_keys: Array[String] = []
		var host_user_id: String = str(server.get("host_user_id", "")).strip_edges()
		var host_username: String = str(server.get("host_username", "")).strip_edges()
		if not host_user_id.is_empty():
			lookup_keys.append(host_user_id)
		if not host_username.is_empty():
			lookup_keys.append(host_username.to_lower())
		var member_user_ids: Array = server.get("member_user_ids", []) if server.get("member_user_ids", []) is Array else []
		for member_variant in member_user_ids:
			var member_user_id: String = str(member_variant).strip_edges()
			if not member_user_id.is_empty():
				lookup_keys.append(member_user_id)
		for lookup_key in lookup_keys:
			var existing_entry: Dictionary = lookup.get(lookup_key, {}) if lookup.get(lookup_key, {}) is Dictionary else {}
			if existing_entry.is_empty() or server_last_seen >= int(existing_entry.get("last_seen", 0)):
				lookup[lookup_key] = server
	return lookup

func _resolve_active_server_for_profile(profile: Dictionary, active_server_lookup: Dictionary) -> Dictionary:
	var lookup_keys: Array[String] = []
	var user_id: String = str(profile.get("id", profile.get("user_id", ""))).strip_edges()
	var username: String = str(profile.get("username", profile.get("name", ""))).strip_edges().to_lower()
	if not user_id.is_empty():
		lookup_keys.append(user_id)
	if not username.is_empty():
		lookup_keys.append(username)
	for lookup_key in lookup_keys:
		var server_match: Variant = active_server_lookup.get(lookup_key, {})
		if server_match is Dictionary and not (server_match as Dictionary).is_empty():
			return server_match
	return {}

func _get_profile_status_text(profile: Dictionary, join_server_info: Dictionary = {}) -> String:
	if not join_server_info.is_empty():
		var active_game_name: String = str(join_server_info.get("map_name", profile.get("current_game", ""))).strip_edges()
		if active_game_name.is_empty():
			active_game_name = "a game"
		return "Playing %s" % active_game_name
	if not _is_profile_presence_fresh(profile):
		return "Offline"
	var current_game: String = str(profile.get("current_game", "")).strip_edges()
	if not current_game.is_empty():
		return "Playing %s" % current_game
	return "Online" if str(profile.get("status", "")).strip_edges().to_lower() == "online" else "Offline"

func _get_friend_presence_rank(profile: Dictionary, active_server_lookup: Dictionary) -> int:
	if not _resolve_active_server_for_profile(profile, active_server_lookup).is_empty():
		return 0
	if _is_profile_presence_fresh(profile) and str(profile.get("status", "")).strip_edges().to_lower() == "online":
		return 1
	return 2

func _is_profile_presence_fresh(profile: Dictionary) -> bool:
	var updated_at: String = str(profile.get("updated_at", profile.get("last_seen_at", ""))).strip_edges()
	if updated_at.is_empty():
		return false
	var updated_unix: int = int(Time.get_unix_time_from_datetime_string(updated_at))
	if updated_unix <= 0:
		return false
	return (Time.get_unix_time_from_system() - updated_unix) <= PROFILE_PRESENCE_TTL_SECONDS

func _make_game_entry_from_cloud_map(map_record: Dictionary) -> Dictionary:
	var map_id: String = str(map_record.get("id", map_record.get("map_id", ""))).strip_edges()
	var cloud_version_id: String = str(map_record.get("cloud_version_id", map_record.get("updated_at", ""))).strip_edges()
	var cached_folder: String = CloudAPI.get_cached_map_folder(map_id, cloud_version_id)
	var cached_icon_path: String = ""
	if not cached_folder.is_empty():
		var possible_icon: String = cached_folder.path_join("icon.png")
		if FileAccess.file_exists(possible_icon):
			cached_icon_path = possible_icon
	return {
		"name": _resolve_display_game_name(str(map_record.get("name", "Untitled Experience")).strip_edges(), map_id, "Untitled Experience"),
		"map_id": map_id,
		"cloud_version_id": cloud_version_id,
		"folder": "",
		"icon_path": cached_icon_path,
		"thumbnail": str(map_record.get("thumbnail", "")).strip_edges(),
		"description": str(map_record.get("description", "")).strip_edges(),
		"owner_id": str(map_record.get("owner_id", "")).strip_edges(),
		"owner_name": str(map_record.get("owner_name", "")).strip_edges(),
		"creator": str(map_record.get("owner_name", "")).strip_edges(),
		"likes": int(map_record.get("likes_count", map_record.get("likes", 0))),
		"rating_positive": int(map_record.get("rating_positive", -1)),
		"rating_negative": int(map_record.get("rating_negative", 0)),
		"visits": int(map_record.get("visits_count", map_record.get("visits", 0))),
		"created_at": str(map_record.get("created_at", "")).strip_edges(),
		"updated_at": str(map_record.get("updated_at", "")).strip_edges(),
		"max_players": int(map_record.get("max_players", NetworkManager.MAX_CLIENTS if NetworkManager != null else 10)),
		"genre": str(map_record.get("genre", "All")).strip_edges(),
		"active_players": 0,
		"source": "cloud"
	}

func _scan_local_map_entries() -> Array:
	var entries: Array = []
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir == null:
		return entries
	maps_dir.list_dir_begin()
	var folder_name: String = maps_dir.get_next()
	while folder_name != "":
		if maps_dir.current_is_dir() and not folder_name.begins_with("."):
			var folder_path: String = UserSession.get_maps_root_path() + "/" + folder_name
			var entry: Dictionary = _make_game_entry_from_local_folder(folder_path)
			if not bool(entry.get("draft_unsaved", false)) and not _should_hide_discover_entry(entry):
				entries.append(entry)
		folder_name = maps_dir.get_next()
	maps_dir.list_dir_end()
	return entries

func _load_local_map_entries(limit: int = 8) -> Array:
	var now_msec: int = Time.get_ticks_msec()
	if _local_map_entries_cache.is_empty() or now_msec >= _local_map_entries_cache_expires_at_msec:
		_local_map_entries_cache = _scan_local_map_entries()
		_local_map_entries_cache_expires_at_msec = now_msec + LOCAL_MAP_ENTRY_CACHE_TTL_MS
		_local_game_icon_path_cache.clear()
	var safe_limit: int = maxi(limit, 0)
	var entries: Array = []
	for i in range(mini(safe_limit, _local_map_entries_cache.size())):
		if _local_map_entries_cache[i] is Dictionary:
			entries.append((_local_map_entries_cache[i] as Dictionary).duplicate(true))
	return entries

func _load_cached_cloud_map_entries(limit: int = 64) -> Array:
	var entries: Array = []
	if CloudAPI == null:
		return entries
	var cache_root: String = str(CloudAPI.CACHE_ROOT_PATH)
	var cache_dir := DirAccess.open(cache_root)
	if cache_dir == null:
		return entries
	cache_dir.list_dir_begin()
	var folder_name: String = cache_dir.get_next()
	while not folder_name.is_empty() and entries.size() < limit:
		if cache_dir.current_is_dir() and not folder_name.begins_with("."):
			var folder_path: String = cache_root.path_join(folder_name)
			var meta: Dictionary = _read_json_dictionary(folder_path.path_join("meta.json"))
			if not meta.is_empty() and FileAccess.file_exists(folder_path.path_join("map_data.json")):
				var map_id := str(meta.get("cloud_map_id", meta.get("map_id", folder_name))).strip_edges()
				var icon_path := folder_path.path_join("icon.png")
				var cached_entry: Dictionary = {
					"name": _resolve_display_game_name(str(meta.get("name", "")).strip_edges(), map_id, folder_name),
					"map_id": map_id,
					"cloud_version_id": str(meta.get("cloud_version_id", "")).strip_edges(),
					"folder": folder_path,
					"icon_path": icon_path if FileAccess.file_exists(icon_path) else "",
					"thumbnail": str(meta.get("thumbnail", "")).strip_edges(),
					"description": str(meta.get("description", "")).strip_edges(),
					"creator": str(meta.get("creator", meta.get("owner_name", ""))).strip_edges(),
					"owner_name": str(meta.get("owner_name", meta.get("creator", ""))).strip_edges(),
					"is_template": bool(meta.get("is_template", false)),
					"draft_unsaved": false,
					"active_players": 0,
					"source": "cached_cloud"
				}
				if not _should_hide_discover_entry(cached_entry):
					entries.append(cached_entry)
		folder_name = cache_dir.get_next()
	cache_dir.list_dir_end()
	return entries

func _make_game_entry_from_local_folder(folder_path: String) -> Dictionary:
	var meta: Dictionary = _read_json_dictionary(folder_path + "/meta.json")
	var icon_path: String = folder_path + "/icon.png"
	var resolved_name: String = _resolve_display_game_name(
		str(meta.get("name", "")).strip_edges(),
		str(meta.get("cloud_map_id", meta.get("map_id", ""))).strip_edges(),
		folder_path.get_file().strip_edges()
	)
	return {
		"name": resolved_name,
		"map_id": str(meta.get("cloud_map_id", "")).strip_edges(),
		"cloud_version_id": str(meta.get("cloud_version_id", "")).strip_edges(),
		"folder": folder_path,
		"icon_path": icon_path if FileAccess.file_exists(icon_path) else "",
		"thumbnail": str(meta.get("thumbnail", "")).strip_edges(),
		"description": str(meta.get("description", "")).strip_edges(),
		"creator": str(meta.get("creator", "")).strip_edges(),
		"is_template": bool(meta.get("is_template", false)),
		"draft_unsaved": bool(meta.get("draft_unsaved", false)),
		"active_players": 0,
		"source": "local"
	}

func _is_local_template_map_entry(entry: Dictionary) -> bool:
	if bool(entry.get("is_template", false)):
		return true
	var folder_name: String = str(entry.get("folder", "")).strip_edges().get_file().to_lower()
	var map_id: String = str(entry.get("map_id", "")).strip_edges()
	return folder_name == "classic baseplate" and map_id.is_empty()

func _is_local_entry_owned_by_current_user(entry: Dictionary) -> bool:
	var current_username: String = str(UserSession.username).strip_edges().to_lower()
	var creator_name: String = str(entry.get("creator", "")).strip_edges().to_lower()
	if current_username.is_empty():
		return creator_name.is_empty()
	return creator_name.is_empty() or creator_name == current_username

func _refresh_profile_games_section() -> void:
	# FIX Bug-6: ProfileBuilder builds ProfileView as ScrollContainer > MarginContainer > VBoxContainer.
	# The old lookup "ProfileView/Content" never matched. Now we traverse to find the actual root VBox.
	var profile_view: Control = null
	if main_tabs:
		profile_view = main_tabs.get_node_or_null("ProfileView")
	if profile_view == null:
		return
	var profile_content: VBoxContainer = _find_first_vbox_child(profile_view)
	if profile_content == null:
		return
	if _profile_games_panel != null and is_instance_valid(_profile_games_panel):
		if _profile_games_panel.get_parent() != null:
			_profile_games_panel.get_parent().remove_child(_profile_games_panel)
		_profile_games_panel.queue_free()
		_profile_games_panel = null

	_profile_games_panel = Panel.new()
	_profile_games_panel.name = "ProfileGamesPanel"
	_profile_games_panel.custom_minimum_size = Vector2(0, 320)
	_profile_games_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	profile_content.add_child(_profile_games_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	_profile_games_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	var target_user_id: String = selected_profile_user_id if not selected_profile_user_id.is_empty() else UserSession.user_id
	var target_username: String = selected_profile_username if not selected_profile_username.is_empty() else (UserSession.username if UserSession.is_logged_in else "Player")
	var is_own_profile: bool = target_user_id == UserSession.user_id
	title.text = "My Games" if is_own_profile else "%s's Games" % target_username
	title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Your created experiences. You can jump straight into them or reopen them in Studio." if is_own_profile else "Published experiences created by %s." % target_username
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	_add_placeholder_label(grid, "Loading games...")

	var active_counts_by_map_id: Dictionary = {}
	var active_counts_by_name: Dictionary = {}
	var sample_server_by_map_id: Dictionary = {}
	var sample_server_by_name: Dictionary = {}
	if CloudAPI.is_configured():
		var active_servers_result: Dictionary = await CloudAPI.fetch_active_servers("", 64, 3.0, 1)
		if bool(active_servers_result.get("ok", false)):
			for server_variant in CloudAPI._extract_array_payload(active_servers_result.get("data", [])):
				if not (server_variant is Dictionary):
					continue
				var server: Dictionary = server_variant
				var players_count: int = int(server.get("players_count", server.get("player_count", 0)))
				var map_id: String = str(server.get("map_id", "")).strip_edges()
				var map_name_key: String = _normalize_map_name_key(_resolve_display_game_name(str(server.get("map_name", "")).strip_edges(), map_id, "Untitled Experience"))
				if not map_id.is_empty():
					active_counts_by_map_id[map_id] = int(active_counts_by_map_id.get(map_id, 0)) + players_count
					if not sample_server_by_map_id.has(map_id):
						sample_server_by_map_id[map_id] = server
				if not map_name_key.is_empty():
					active_counts_by_name[map_name_key] = int(active_counts_by_name.get(map_name_key, 0)) + players_count
					if not sample_server_by_name.has(map_name_key):
						sample_server_by_name[map_name_key] = server

	var game_entries: Array = []
	if CloudAPI.is_configured():
		var cloud_maps_result: Dictionary = await CloudAPI.fetch_published_maps_for_owner(target_user_id, 240)
		if bool(cloud_maps_result.get("ok", false)):
			for map_variant in CloudAPI._extract_array_payload(cloud_maps_result.get("data", [])):
				if not (map_variant is Dictionary):
					continue
				var entry: Dictionary = _make_game_entry_from_cloud_map(map_variant)
				if is_own_profile and _is_deleted_game_entry(entry):
					continue
				entry["active_players"] = _get_active_player_count_for_entry(entry, active_counts_by_map_id, active_counts_by_name)
				var sample_server: Dictionary = _get_sample_server_for_entry(entry, sample_server_by_map_id, sample_server_by_name)
				if not sample_server.is_empty():
					entry["cloud_version_id"] = str(sample_server.get("cloud_version_id", entry.get("cloud_version_id", ""))).strip_edges()
				if is_own_profile and _is_orphaned_own_cloud_entry(entry):
					continue
				game_entries.append(entry)

	if is_own_profile:
		for game_entry_variant in _load_local_map_entries(64):
			if not (game_entry_variant is Dictionary):
				continue
			var game_entry: Dictionary = game_entry_variant
			if _is_local_template_map_entry(game_entry) or not _is_local_entry_owned_by_current_user(game_entry):
				continue
			if _is_deleted_game_entry(game_entry):
				continue
			var merged: bool = false
			for i in range(game_entries.size()):
				if not (game_entries[i] is Dictionary):
					continue
				var existing_entry: Dictionary = game_entries[i]
				if not _game_entries_match(existing_entry, game_entry):
					continue
				var merged_entry: Dictionary = existing_entry.duplicate(true)
				for merge_key in ["folder", "icon_path", "thumbnail", "description"]:
					if str(merged_entry.get(merge_key, "")).strip_edges().is_empty():
						merged_entry[merge_key] = game_entry.get(merge_key, "")
				merged_entry["active_players"] = maxi(int(merged_entry.get("active_players", 0)), int(game_entry.get("active_players", 0)))
				game_entries[i] = merged_entry
				merged = true
				break
			if not merged:
				game_entry["active_players"] = _get_active_player_count_for_entry(game_entry, active_counts_by_map_id, active_counts_by_name)
				game_entries.append(game_entry)
		for cached_entry_variant in _load_cached_cloud_map_entries(128):
			if not (cached_entry_variant is Dictionary):
				continue
			var cached_entry: Dictionary = cached_entry_variant
			if _is_local_template_map_entry(cached_entry) or not _is_local_entry_owned_by_current_user(cached_entry):
				continue
			if _is_deleted_game_entry(cached_entry):
				continue
			# A cache entry is never proof that a creation still exists. It may only
			# enrich a row returned by the authoritative API; otherwise deleted maps
			# such as old test imports would reappear forever on this device.
			for entry_index in range(game_entries.size()):
				if not (game_entries[entry_index] is Dictionary):
					continue
				var authoritative_entry: Dictionary = game_entries[entry_index]
				if not _game_entries_match(authoritative_entry, cached_entry):
					continue
				var enriched_entry := authoritative_entry.duplicate(true)
				for cache_key in ["folder", "icon_path", "thumbnail"]:
					if str(enriched_entry.get(cache_key, "")).strip_edges().is_empty():
						enriched_entry[cache_key] = cached_entry.get(cache_key, "")
				game_entries[entry_index] = enriched_entry
				break

	game_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_players: int = int(a.get("active_players", 0))
		var b_players: int = int(b.get("active_players", 0))
		if a_players == b_players:
			return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
		return a_players > b_players
	)
	if not is_instance_valid(grid):
		return
	_clear_container(grid)
	if game_entries.is_empty():
		_add_placeholder_label(grid, "You have not created any games yet." if is_own_profile else "%s has not published any games yet." % target_username)
		return
	for game_entry_variant in game_entries:
		if game_entry_variant is Dictionary:
			grid.add_child(_create_profile_game_card(game_entry_variant))

func _create_profile_game_card(game_info: Dictionary) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 328)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _make_white_panel_style())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	root.add_child(_create_game_icon_widget(game_info))

	var title := Label.new()
	title.text = str(game_info.get("name", "Untitled Experience"))
	title.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	title.add_theme_font_size_override("font_size", 15)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(title)

	var active_players: int = int(game_info.get("active_players", 0))
	var meta := Label.new()
	meta.text = "%d player(s) active" % active_players if active_players > 0 else "Ready to play"
	meta.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	meta.add_theme_font_size_override("font_size", 12)
	root.add_child(meta)

	var description: String = str(game_info.get("description", "")).strip_edges()
	if not description.is_empty():
		var description_label := Label.new()
		description_label.text = description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.max_lines_visible = 2
		description_label.add_theme_color_override("font_color", Color(0.46, 0.46, 0.46, 1))
		description_label.add_theme_font_size_override("font_size", 11)
		root.add_child(description_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.custom_minimum_size = Vector2(0, 36)
	root.add_child(action_row)

	var play_button := Button.new()
	play_button.text = "Join" if active_players > 0 else "Play"
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_button.custom_minimum_size = Vector2(0, 34)
	play_button.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
	play_button.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.15, 0.67, 0.96, 1.0)))
	play_button.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.15, 0.67, 0.96, 1.0)))
	play_button.add_theme_color_override("font_color", Color.WHITE)
	play_button.pressed.connect(func(): _start_smart_play_for_game(game_info))
	action_row.add_child(play_button)

	var studio_button := Button.new()
	studio_button.text = "Studio"
	studio_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	studio_button.custom_minimum_size = Vector2(0, 34)
	var folder_path: String = str(game_info.get("folder", "")).strip_edges()
	studio_button.disabled = folder_path.is_empty()
	studio_button.pressed.connect(func(): _open_local_game_in_studio(folder_path))
	if not folder_path.is_empty():
		action_row.add_child(studio_button)

	return panel

func _open_local_game_in_studio(folder_path: String) -> void:
	if folder_path.is_empty():
		return
	GameState.selected_map_folder = folder_path
	get_tree().change_scene_to_file("res://scenes/place_editor/studio.tscn")

func _record_recent_game_from_entry(game_info: Dictionary, map_result: Dictionary) -> void:
	var recent_map_id: String = str(game_info.get("map_id", map_result.get("map_id", ""))).strip_edges()
	var recent_folder: String = str(map_result.get("folder", game_info.get("folder", ""))).strip_edges()
	if recent_map_id.is_empty() and recent_folder.is_empty():
		return
	UserSession.record_recent_game({
		"map_id": recent_map_id,
		"name": _resolve_game_name_for_recent_entry(game_info, map_result),
		"folder": recent_folder,
		"icon_path": str(game_info.get("icon_path", "")).strip_edges(),
		"cloud_version_id": str(map_result.get("cloud_version_id", game_info.get("cloud_version_id", ""))).strip_edges()
	})

func _resolve_game_name_for_recent_entry(game_info: Dictionary, map_result: Dictionary) -> String:
	var folder_path: String = str(map_result.get("folder", game_info.get("folder", ""))).strip_edges()
	var folder_meta: Dictionary = _read_json_dictionary(folder_path.path_join("meta.json")) if not folder_path.is_empty() else {}
	return _resolve_display_game_name(
		str(game_info.get("name", map_result.get("map_name", ""))).strip_edges(),
		str(game_info.get("map_id", map_result.get("map_id", ""))).strip_edges(),
		str(folder_meta.get("name", "Untitled Experience")).strip_edges()
	)

func _get_game_key(game_info: Dictionary) -> String:
	var map_id: String = str(game_info.get("map_id", "")).strip_edges()
	if not map_id.is_empty():
		return map_id
	return _normalize_map_name_key(str(game_info.get("name", "")))

func _game_entries_match(a: Dictionary, b: Dictionary) -> bool:
	var a_map_id: String = str(a.get("map_id", "")).strip_edges()
	var b_map_id: String = str(b.get("map_id", "")).strip_edges()
	if not a_map_id.is_empty() and not b_map_id.is_empty():
		return a_map_id == b_map_id
	var a_name: String = str(a.get("name", "")).strip_edges().to_lower()
	var b_name: String = str(b.get("name", "")).strip_edges().to_lower()
	return not a_name.is_empty() and a_name == b_name

func _get_game_key_from_server(server_info: Dictionary) -> String:
	var map_id: String = str(server_info.get("map_id", "")).strip_edges()
	if not map_id.is_empty():
		return map_id
	return _normalize_map_name_key(str(server_info.get("map_name", "")))

func _normalize_map_name_key(map_name: String) -> String:
	return _resolve_display_game_name(map_name.strip_edges(), "", "").to_lower()

func _resolve_display_game_name(map_name: String, map_id: String = "", fallback_name: String = "Untitled Experience") -> String:
	var clean_map_name: String = map_name.strip_edges()
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_name.to_lower() == "classic" or clean_map_id.to_lower() == "classic":
		return "Classic"
	if not clean_map_name.is_empty() and not _looks_like_generated_game_name(clean_map_name):
		return clean_map_name
	var clean_fallback_name: String = fallback_name.strip_edges()
	if not clean_fallback_name.is_empty() and not _looks_like_generated_game_name(clean_fallback_name):
		return clean_fallback_name
	return "Untitled Experience"

func _looks_like_generated_game_name(value: String) -> bool:
	var clean_value: String = value.strip_edges().to_lower()
	if clean_value.is_empty() or clean_value == "classic":
		return false
	var matcher := RegEx.new()
	if matcher.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}([:_].+)?$") != OK:
		return false
	return matcher.search(clean_value) != null

func _get_active_player_count_for_entry(entry: Dictionary, active_counts_by_map_id: Dictionary, active_counts_by_name: Dictionary) -> int:
	var map_id: String = str(entry.get("map_id", "")).strip_edges()
	if not map_id.is_empty() and active_counts_by_map_id.has(map_id):
		return int(active_counts_by_map_id.get(map_id, 0))
	var map_name_key: String = _normalize_map_name_key(str(entry.get("name", "")))
	if not map_name_key.is_empty():
		return int(active_counts_by_name.get(map_name_key, 0))
	return 0

func _get_sample_server_for_entry(entry: Dictionary, sample_server_by_map_id: Dictionary, sample_server_by_name: Dictionary) -> Dictionary:
	var map_id: String = str(entry.get("map_id", "")).strip_edges()
	if not map_id.is_empty() and sample_server_by_map_id.has(map_id):
		var mapped_by_id: Variant = sample_server_by_map_id.get(map_id, {})
		return mapped_by_id if mapped_by_id is Dictionary else {}
	var map_name_key: String = _normalize_map_name_key(str(entry.get("name", "")))
	if not map_name_key.is_empty() and sample_server_by_name.has(map_name_key):
		var mapped_by_name: Variant = sample_server_by_name.get(map_name_key, {})
		return mapped_by_name if mapped_by_name is Dictionary else {}
	return {}

func _has_game_entry(entries: Array, game_key: String) -> bool:
	for entry_variant in entries:
		if entry_variant is Dictionary and _get_game_key(entry_variant) == game_key:
			return true
	return false

func _ensure_loading_overlay() -> void:
	if _loading_overlay != null:
		return
	_loading_overlay = ColorRect.new()
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.color = Color(0.89, 0.9, 0.93, 0.96)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	add_child(_loading_overlay)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_top = -96
	panel.offset_right = 240
	panel.offset_bottom = 96
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 0.985)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.12)
	panel_style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	_loading_overlay.add_child(panel)

	var accent_bar := ColorRect.new()
	accent_bar.color = Color(0.11, 0.48, 0.85, 1.0)
	accent_bar.anchor_right = 1.0
	accent_bar.offset_bottom = 10.0
	panel.add_child(accent_bar)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_loading_title_label = Label.new()
	_loading_title_label.text = "Loading..."
	_loading_title_label.add_theme_color_override("font_color", Color(0.14, 0.15, 0.18, 1.0))
	_loading_title_label.add_theme_font_size_override("font_size", 24)
	root.add_child(_loading_title_label)

	_loading_subtitle_label = Label.new()
	_loading_subtitle_label.text = "Preparing your game."
	_loading_subtitle_label.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48, 1.0))
	_loading_subtitle_label.add_theme_font_size_override("font_size", 13)
	_loading_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_loading_subtitle_label)

	_loading_transport_badge_label = Label.new()
	_loading_transport_badge_label.text = "Transport: Dedicated WebSocket"
	_loading_transport_badge_label.add_theme_color_override("font_color", Color(0.11, 0.48, 0.85, 1.0))
	_loading_transport_badge_label.add_theme_font_size_override("font_size", 11)
	root.add_child(_loading_transport_badge_label)

	_loading_progress_bar = ProgressBar.new()
	_loading_progress_bar.min_value = 0.0
	_loading_progress_bar.max_value = 100.0
	_loading_progress_bar.show_percentage = false
	_loading_progress_bar.custom_minimum_size = Vector2(0, 18)
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color(0.84, 0.86, 0.89, 1.0)
	progress_bg.corner_radius_top_left = 7
	progress_bg.corner_radius_top_right = 7
	progress_bg.corner_radius_bottom_right = 7
	progress_bg.corner_radius_bottom_left = 7
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(0.11, 0.48, 0.85, 1.0)
	progress_fill.corner_radius_top_left = 7
	progress_fill.corner_radius_top_right = 7
	progress_fill.corner_radius_bottom_right = 7
	progress_fill.corner_radius_bottom_left = 7
	_loading_progress_bar.add_theme_stylebox_override("background", progress_bg)
	_loading_progress_bar.add_theme_stylebox_override("fill", progress_fill)
	root.add_child(_loading_progress_bar)

func _ensure_experience_loading_overlay() -> void:
	if _loading_overlay != null and _loading_overlay.has_method("set_experience"): return
	if _loading_overlay != null: _loading_overlay.queue_free()
	var overlay = load("res://scripts/ui/experience_loading.gd").new()
	overlay.visible = false
	add_child(overlay)
	_loading_overlay = overlay
	_loading_title_label = overlay.title
	_loading_subtitle_label = overlay.subtitle
	_loading_transport_badge_label = overlay.transport_badge
	_loading_progress_bar = overlay.bar

func _show_loading_overlay(title: String, subtitle: String, progress_ratio: float) -> void:
	_ensure_loading_overlay()
	_loading_overlay.modulate.a = 1.0
	_loading_overlay.visible = true
	_update_loading_overlay(title, subtitle, progress_ratio)

func _hide_loading_overlay() -> void:
	if _loading_overlay == null:
		return
	var overlay := _loading_overlay
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func():
		if is_instance_valid(overlay):
			overlay.visible = false
			overlay.modulate.a = 1.0
	)

func _update_loading_overlay(title: String, subtitle: String, progress_ratio: float) -> void:
	_ensure_loading_overlay()
	_loading_title_label.text = title
	_loading_subtitle_label.text = subtitle
	_update_loading_transport_badge(subtitle)
	_loading_progress_bar.value = clampf(progress_ratio, 0.0, 1.0) * 100.0

func _update_loading_transport_badge(text: String) -> void:
	if _loading_transport_badge_label == null:
		return
	var lower_text: String = text.strip_edges().to_lower()
	if lower_text.find("websocket") >= 0 or lower_text.find("dedicated") >= 0 or lower_text.find("room") >= 0 or lower_text.find("socket") >= 0 or lower_text.find("connecting") >= 0:
		_loading_transport_badge_label.text = "Transport: Dedicated WebSocket"
	else:
		_loading_transport_badge_label.text = ""

func _show_loading_error(title: String, subtitle: String) -> void:
	push_error("[Lobby] %s: %s" % [title, subtitle])
	_show_loading_overlay(title, subtitle, 1.0)
	await get_tree().create_timer(1.6).timeout
	if _loading_overlay:
		_loading_overlay.visible = false

func _make_primary_button_style(color_value: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style

func _add_placeholder_label(container: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	label.add_theme_font_size_override("font_size", 12)
	container.add_child(label)

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

# Immediately remove and free children instead of deferred queue_free.
# This prevents race conditions where a second async call sees the old
# children still present and appends duplicates.
func _clear_children_immediate(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

# Recursively set mouse_filter to PASS on all Control children so that
# mouse events fall through to the parent Button.
func _set_mouse_filter_pass_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_mouse_filter_pass_recursive(child)

# FIX Bug-6: Traverse a node tree to find the first VBoxContainer child.
func _find_first_vbox_child(root: Node) -> VBoxContainer:
	for child in root.get_children():
		if child is VBoxContainer:
			return child as VBoxContainer
		var found: VBoxContainer = _find_first_vbox_child(child)
		if found != null:
			return found
	return null

func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _extract_cloud_array(payload: Variant) -> Array:
	if payload is Array:
		return payload
	if payload is Dictionary and payload.has("data") and payload["data"] is Array:
		return payload["data"]
	return []

# ========== GAME DISCOVERY (RECENTLY PLAYED) ==========
func _ensure_maps_dir() -> void:
	UserSession.ensure_current_storage()

	# Create default "Classic Baseplate" if maps folder is empty
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir == null:
		return
	maps_dir.list_dir_begin()
	var found_any := false
	var fname := maps_dir.get_next()
	while fname != "":
		if maps_dir.current_is_dir() and not fname.begins_with("."):
			found_any = true
			break
		fname = maps_dir.get_next()
	maps_dir.list_dir_end()

	if not found_any:
		var map_dir := DirAccess.open(UserSession.get_maps_root_path())
		if map_dir:
			map_dir.make_dir("Classic Baseplate")
		var meta := {
			"name": "Classic Baseplate",
			"creator": "Bobux",
			"description": "A classic flat baseplate to build on.",
			"is_template": true
		}
		var meta_file := FileAccess.open(UserSession.get_maps_root_path() + "/Classic Baseplate/meta.json", FileAccess.WRITE)
		if meta_file:
			meta_file.store_string(JSON.stringify(meta, "\t"))
			meta_file.close()
		var default_bp = _make_block(-20.0, -1.0, -20.0, 40.0, 1.0, 40.0, Color(0.45, 0.55, 0.45), "Plastic", "Baseplate")
		var map_data := {"blocks": [default_bp], "time_of_day": 12.0}
		var data_file := FileAccess.open(UserSession.get_maps_root_path() + "/Classic Baseplate/map_data.json", FileAccess.WRITE)
		if data_file:
			data_file.store_string(JSON.stringify(map_data, "\t"))
			data_file.close()

func _build_recently_played_section() -> void:
	# Find the ModesPanel in the home view and replace its content
	# with a "RECENTLY PLAYED" game discovery grid - matching 2015 Roblox style
	var modes_panel: Panel = get_node_or_null("Body/HBox/MainTabs/HomeView/Content/ModesPanel")
	if modes_panel == null:
		return

	var modes_vbox = modes_panel.get_node_or_null("Margin/VBox")
	if modes_vbox == null:
		return

	# Clear the old content
	for child in modes_vbox.get_children():
		child.queue_free()

	# Section header row: "RECENTLY PLAYED" + "See All" link
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 0)
	modes_vbox.add_child(header_row)

	var section_title := Label.new()
	section_title.text = "RECENTLY PLAYED"
	section_title.add_theme_font_size_override("font_size", 18)
	section_title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(section_title)

	var see_all_btn := Button.new()
	see_all_btn.text = "See All"
	see_all_btn.flat = true
	see_all_btn.add_theme_font_size_override("font_size", 13)
	see_all_btn.add_theme_color_override("font_color", Color(0.086, 0.357, 0.678, 1))
	var see_all_style := StyleBoxFlat.new()
	see_all_style.bg_color = Color(0.9, 0.94, 0.98, 1)
	see_all_style.corner_radius_top_left = 4
	see_all_style.corner_radius_top_right = 4
	see_all_style.corner_radius_bottom_right = 4
	see_all_style.corner_radius_bottom_left = 4
	see_all_style.content_margin_left = 10
	see_all_style.content_margin_right = 10
	see_all_style.content_margin_top = 4
	see_all_style.content_margin_bottom = 4
	see_all_btn.add_theme_stylebox_override("normal", see_all_style)
	header_row.add_child(see_all_btn)

	# Game cards grid
	var game_scroll := ScrollContainer.new()
	game_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	game_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	game_scroll.custom_minimum_size = Vector2(0, 170)
	modes_vbox.add_child(game_scroll)

	var game_hbox := HBoxContainer.new()
	game_hbox.add_theme_constant_override("separation", 14)
	game_scroll.add_child(game_hbox)

	# Scan user://maps/ for map folders
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir == null:
		var no_maps := Label.new()
		no_maps.text = "No games found. Open Studio to create one!"
		no_maps.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		game_hbox.add_child(no_maps)
		return

	maps_dir.list_dir_begin()
	var folder_name := maps_dir.get_next()
	var map_count: int = 0
	while folder_name != "":
		if maps_dir.current_is_dir() and not folder_name.begins_with("."):
			_create_game_card(game_hbox, folder_name)
			map_count += 1
		folder_name = maps_dir.get_next()
	maps_dir.list_dir_end()

	if map_count == 0:
		var no_maps := Label.new()
		no_maps.text = "No games found. Open Studio to create one!"
		no_maps.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		game_hbox.add_child(no_maps)

	# Adjust panel height
	modes_panel.custom_minimum_size.y = 230

func _build_live_servers_section() -> void:
	var home_content := get_node_or_null("Body/HBox/MainTabs/HomeView/Content") as VBoxContainer
	if home_content == null:
		return

	var existing_panel := home_content.get_node_or_null("LiveServersPanel")
	if existing_panel:
		existing_panel.queue_free()

	live_servers_panel = Panel.new()
	live_servers_panel.name = "LiveServersPanel"
	live_servers_panel.custom_minimum_size = Vector2(0, 190)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 1, 1, 1)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.82, 0.82, 0.82, 1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.04)
	panel_style.shadow_size = 6
	panel_style.shadow_offset = Vector2(0, 3)
	live_servers_panel.add_theme_stylebox_override("panel", panel_style)

	var insert_index := 2
	home_content.add_child(live_servers_panel)
	home_content.move_child(live_servers_panel, mini(insert_index, home_content.get_child_count() - 1))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	live_servers_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "LIVE SERVERS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	header.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.flat = true
	refresh_btn.add_theme_font_size_override("font_size", 13)
	refresh_btn.add_theme_color_override("font_color", Color(0.086, 0.357, 0.678, 1))
	refresh_btn.pressed.connect(func(): call_deferred("_refresh_live_servers_section"))
	header.add_child(refresh_btn)

	live_servers_status = Label.new()
	live_servers_status.text = "Checking cloud servers..."
	live_servers_status.add_theme_font_size_override("font_size", 12)
	live_servers_status.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	vbox.add_child(live_servers_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	live_servers_list = VBoxContainer.new()
	live_servers_list.add_theme_constant_override("separation", 8)
	scroll.add_child(live_servers_list)

func _refresh_live_servers_section() -> void:
	if live_servers_status == null or live_servers_list == null:
		return
	_clear_container(live_servers_list)
	if not CloudAPI.is_configured():
		live_servers_status.text = "Cloud server browser is not configured yet."
		return

	live_servers_status.text = "Loading active servers..."
	var result := await CloudAPI.fetch_active_servers("", 64, 5.0, 1)
	if not bool(result.get("ok", false)):
		live_servers_status.text = "Could not fetch active servers."
		_add_live_server_placeholder(str(result.get("error", "Unknown cloud error")))
		return

	var servers := _extract_cloud_array(result.get("data", []))
	if servers.is_empty():
		live_servers_status.text = "No public servers online right now."
		_add_live_server_placeholder("Host a map to make it appear here.")
		return

	live_servers_status.text = "Found %d active server(s)." % servers.size()
	for server_variant in servers:
		if server_variant is Dictionary:
			_create_live_server_card(server_variant)

func _add_live_server_placeholder(text: String) -> void:
	var placeholder := Label.new()
	placeholder.text = text
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	placeholder.add_theme_font_size_override("font_size", 13)
	live_servers_list.add_child(placeholder)

func _create_live_server_card(server_info: Dictionary) -> void:
	var card := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.98, 1.0, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.85, 0.88, 0.92, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", style)
	live_servers_list.add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	row.add_child(text_column)

	var map_id: String = str(server_info.get("map_id", "")).strip_edges()
	var map_name := _resolve_display_game_name(str(server_info.get("map_name", "Unknown Map")).strip_edges(), map_id, "Untitled Experience")
	var server_name := _resolve_display_game_name(str(server_info.get("server_name", map_name)).strip_edges(), map_id, map_name)
	var host_name := str(server_info.get("host_username", "Unknown Host"))
	var player_count := int(server_info.get("players_count", server_info.get("player_count", server_info.get("players", 0))))
	var max_players := int(server_info.get("max_players", NetworkManager.MAX_CLIENTS))
	var address := str(server_info.get("ip", ""))
	var port := int(server_info.get("port", GameState.DEFAULT_PORT))

	var title := Label.new()
	title.text = server_name
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	text_column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "%s | Host: %s" % [map_name, host_name]
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42, 1))
	text_column.add_child(subtitle)

	var meta := Label.new()
	meta.text = "%s:%d | %d/%d players" % [address, port, player_count, max_players]
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	text_column.add_child(meta)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(84, 34)
	var join_style := StyleBoxFlat.new()
	join_style.bg_color = Color(0.12, 0.6, 0.88, 1)
	join_style.corner_radius_top_left = 6
	join_style.corner_radius_top_right = 6
	join_style.corner_radius_bottom_right = 6
	join_style.corner_radius_bottom_left = 6
	var join_hover := join_style.duplicate()
	join_hover.bg_color = Color(0.15, 0.67, 0.96, 1)
	join_btn.add_theme_stylebox_override("normal", join_style)
	join_btn.add_theme_stylebox_override("hover", join_hover)
	join_btn.add_theme_stylebox_override("pressed", join_hover)
	join_btn.add_theme_color_override("font_color", Color.WHITE)
	join_btn.pressed.connect(func(): call_deferred("_join_live_server", server_info))
	row.add_child(join_btn)

func _join_live_server(server_info: Dictionary) -> void:
	var resolved_server_info: Dictionary = await _resolve_join_server_info(server_info)
	var server_url: String = str(resolved_server_info.get("server_url", "")).strip_edges()
	var ip := str(resolved_server_info.get("ip", "")).strip_edges()
	var room_id: String = str(resolved_server_info.get("room_id", "")).strip_edges()
	if server_url.is_empty() and ip.is_empty():
		push_warning("[Lobby] Cannot join cloud server because it has no dedicated server URL.")
		return
	if room_id.is_empty():
		push_warning("[Lobby] Cannot join cloud server because room metadata is incomplete.")
		return

	var game_info := {
		"name": _resolve_display_game_name(str(resolved_server_info.get("map_name", "Friend's Game")).strip_edges(), str(resolved_server_info.get("map_id", "")).strip_edges(), "Friend's Game"),
		"map_id": str(resolved_server_info.get("map_id", "")),
		"cloud_version_id": str(resolved_server_info.get("cloud_version_id", "")),
		"folder": "",
		"icon_path": ""
	}
	_ensure_experience_loading_overlay()
	_show_loading_overlay("Loading...", "Joining %s" % str(game_info.get("name", "a game")), 0.08)
	_loading_overlay.call("set_experience", str(game_info.get("name", "Bobux")), game_info)
	await _join_server_flow(game_info, resolved_server_info)

func _resolve_join_server_info(server_info: Dictionary) -> Dictionary:
	var resolved: Dictionary = server_info.duplicate(true)
	if _has_complete_join_server_info(resolved):
		return resolved
	var active_servers_result: Dictionary = await CloudAPI.fetch_active_servers("", 64)
	if not bool(active_servers_result.get("ok", false)):
		return resolved
	var active_servers: Array = CloudAPI._extract_array_payload(active_servers_result.get("data", []))
	var matched_host: Dictionary = _match_join_server_to_active_host(resolved, active_servers)
	if matched_host.is_empty():
		await _try_fill_join_map_metadata_from_cloud(resolved)
		return resolved
	for key_variant in matched_host.keys():
		resolved[str(key_variant)] = matched_host.get(key_variant)
	await _try_fill_join_map_metadata_from_cloud(resolved)
	return resolved

func _has_complete_join_server_info(server_info: Dictionary) -> bool:
	var room_id: String = str(server_info.get("room_id", "")).strip_edges()
	var host_player_id: String = str(server_info.get("player_id", "")).strip_edges()
	var host_user_id: String = str(server_info.get("host_user_id", "")).strip_edges()
	var map_id: String = str(server_info.get("map_id", "")).strip_edges()
	var server_url: String = str(server_info.get("server_url", "")).strip_edges()
	if not room_id.is_empty() and not map_id.is_empty() and not server_url.is_empty():
		return true
	return not room_id.is_empty() and not host_player_id.is_empty() and not host_user_id.is_empty() and not map_id.is_empty()

func _match_join_server_to_active_host(server_info: Dictionary, active_servers: Array) -> Dictionary:
	var target_room_id: String = str(server_info.get("room_id", "")).strip_edges()
	var target_host_user_id: String = str(server_info.get("host_user_id", "")).strip_edges()
	var target_host_username: String = str(server_info.get("host_username", "")).strip_edges().to_lower()
	var target_map_id: String = str(server_info.get("map_id", "")).strip_edges()
	var target_map_name: String = str(server_info.get("map_name", "")).strip_edges()
	var target_server_url: String = str(server_info.get("server_url", "")).strip_edges()
	var target_ip: String = str(server_info.get("ip", "")).strip_edges()
	var target_port: int = int(server_info.get("port", 0))
	var best_match: Dictionary = {}
	var best_score: int = 0
	for server_variant in active_servers:
		if not (server_variant is Dictionary):
			continue
		var server: Dictionary = server_variant
		if not bool(server.get("is_host", false)):
			continue
		var score: int = 0
		if not target_room_id.is_empty() and str(server.get("room_id", "")).strip_edges() == target_room_id:
			score += 100
		if not target_host_user_id.is_empty() and str(server.get("host_user_id", "")).strip_edges() == target_host_user_id:
			score += 90
		if not target_host_username.is_empty() and str(server.get("host_username", "")).strip_edges().to_lower() == target_host_username:
			score += 80
		if not target_map_id.is_empty() and str(server.get("map_id", "")).strip_edges() == target_map_id:
			score += 60
		if not target_map_name.is_empty() and str(server.get("map_name", "")).strip_edges() == target_map_name:
			score += 20
		if not target_server_url.is_empty() and str(server.get("server_url", "")).strip_edges() == target_server_url:
			score += 25
		if not target_ip.is_empty() and str(server.get("ip", "")).strip_edges() == target_ip:
			score += 15
		if target_port > 0 and int(server.get("port", 0)) == target_port:
			score += 10
		if score > best_score:
			best_score = score
			best_match = server.duplicate(true)
	return best_match if best_score > 0 else {}

func _try_fill_join_map_metadata_from_cloud(server_info: Dictionary) -> void:
	if not str(server_info.get("map_id", "")).strip_edges().is_empty():
		return
	var target_map_name: String = str(server_info.get("map_name", "")).strip_edges()
	if target_map_name.is_empty():
		return
	var published_maps_result: Dictionary = await CloudAPI.fetch_published_maps(64)
	if not bool(published_maps_result.get("ok", false)):
		return
	for map_variant in CloudAPI._extract_array_payload(published_maps_result.get("data", [])):
		if not (map_variant is Dictionary):
			continue
		var map_record: Dictionary = map_variant
		if str(map_record.get("name", "")).strip_edges() != target_map_name:
			continue
		server_info["map_id"] = str(map_record.get("id", "")).strip_edges()
		server_info["cloud_version_id"] = str(map_record.get("cloud_version_id", "")).strip_edges()
		return

func _create_game_card(parent_container: HBoxContainer, folder_name: String) -> void:
	var map_folder := UserSession.get_maps_root_path() + "/" + folder_name

	# Read meta
	var meta_name := folder_name
	var _meta_desc := ""
	var _meta_creator := ""
	var meta_path := map_folder + "/meta.json"
	if FileAccess.file_exists(meta_path):
		var f := FileAccess.open(meta_path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				var d: Dictionary = json.data
				meta_name = d.get("name", folder_name)
				_meta_desc = d.get("description", "")
				_meta_creator = d.get("creator", "")
			f.close()

	# Card - vertical layout like Roblox 2015 game cards
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(140, 160)
	card.add_theme_constant_override("separation", 4)

	# Thumbnail container (click to play)
	var thumb_btn := Button.new()
	thumb_btn.custom_minimum_size = Vector2(140, 100)
	thumb_btn.clip_text = true

	# Style the thumbnail
	var thumb_style := StyleBoxFlat.new()
	var hash_val: int = folder_name.hash()
	var hue: float = fmod(absf(float(hash_val)) / 100000.0, 1.0)
	thumb_style.bg_color = Color.from_hsv(hue, 0.3, 0.85)
	thumb_style.corner_radius_top_left = 4
	thumb_style.corner_radius_top_right = 4
	thumb_style.border_width_left = 1
	thumb_style.border_width_top = 1
	thumb_style.border_width_right = 1
	thumb_style.border_width_bottom = 1
	thumb_style.border_color = Color(0.82, 0.82, 0.82, 1)
	var thumb_hover := thumb_style.duplicate()
	thumb_hover.border_color = Color(0.4, 0.6, 0.9, 1)
	thumb_btn.add_theme_stylebox_override("normal", thumb_style)
	thumb_btn.add_theme_stylebox_override("hover", thumb_hover)
	thumb_btn.add_theme_stylebox_override("pressed", thumb_hover)
	thumb_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	thumb_btn.add_theme_font_size_override("font_size", 12)
	thumb_btn.text = "Play"

	# Try to load icon (support PNG, JPG, WebP - handles mismatched extensions)
	var icon_path := map_folder + "/icon.png"
	if FileAccess.file_exists(icon_path):
		var img := _load_icon_image(icon_path)
		if img:
			img.resize(140, 100)
			var tex := ImageTexture.create_from_image(img)
			thumb_btn.icon = tex
			thumb_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			thumb_btn.expand_icon = true

	# Connect play action
	var captured_folder := map_folder
	var captured_name := folder_name
	thumb_btn.pressed.connect(func():
		if _scene_change_in_progress:
			return
		Analytics.log_button_click("play_map_" + captured_name)
		var card_meta: Dictionary = _read_json_dictionary(captured_folder.path_join("meta.json"))
		var card_game_info: Dictionary = {
			"folder": captured_folder,
			"map_id": str(card_meta.get("cloud_map_id", "")).strip_edges(),
			"name": str(card_meta.get("name", captured_name)).strip_edges(),
			"cloud_version_id": str(card_meta.get("cloud_version_id", "")).strip_edges(),
			"thumbnail": str(card_meta.get("thumbnail", "")).strip_edges(),
			"description": str(card_meta.get("description", "")).strip_edges()
		}
		_start_smart_play_for_game(card_game_info)
	)
	card.add_child(thumb_btn)

	# Title
	var title_label := Label.new()
	title_label.text = meta_name
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	title_label.clip_text = true
	title_label.custom_minimum_size.x = 140
	card.add_child(title_label)

	# Online count (placeholder)
	var online_label := Label.new()
	online_label.text = "0 Online"
	online_label.add_theme_font_size_override("font_size", 10)
	online_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	card.add_child(online_label)

	parent_container.add_child(card)

# ========== DEVELOP TAB ==========
func _build_develop_grid() -> void:
	_show_develop_hub_page()

func _build_develop_grid_legacy() -> void:
	var develop_grid: GridContainer = get_node_or_null("%DevelopGrid")
	# FIX Issue-4: If DevelopView was auto-generated as a placeholder, the
	# %DevelopGrid and %BtnCreateNew nodes won't exist. Build them now.
	if develop_grid == null:
		var develop_view: Control = null
		if main_tabs:
			develop_view = main_tabs.get_node_or_null("DevelopView")
		if develop_view == null:
			return
		# Clear auto-generated placeholder content
		for child in develop_view.get_children():
			child.queue_free()
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 24)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_right", 24)
		margin.add_theme_constant_override("margin_bottom", 20)
		develop_view.add_child(margin)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 16)
		margin.add_child(vbox)
		# Title row
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 16)
		vbox.add_child(header)
		var title_lbl := Label.new()
		title_lbl.text = "My Creations"
		title_lbl.add_theme_font_size_override("font_size", 22)
		title_lbl.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title_lbl)
		var create_btn := Button.new()
		create_btn.text = "+ Create New"
		create_btn.unique_name_in_owner = true
		create_btn.name = "BtnCreateNew"
		create_btn.custom_minimum_size = Vector2(140, 38)
		var cb_style := StyleBoxFlat.new()
		cb_style.bg_color = Color(0.0, 0.45, 0.73)
		cb_style.corner_radius_top_left = 6; cb_style.corner_radius_top_right = 6
		cb_style.corner_radius_bottom_left = 6; cb_style.corner_radius_bottom_right = 6
		create_btn.add_theme_stylebox_override("normal", cb_style)
		create_btn.add_theme_color_override("font_color", Color.WHITE)
		create_btn.add_theme_font_size_override("font_size", 14)
		create_btn.pressed.connect(_open_create_game_choice_dialog)
		header.add_child(create_btn)
		# Grid
		develop_grid = GridContainer.new()
		develop_grid.name = "DevelopGrid"
		develop_grid.unique_name_in_owner = true
		develop_grid.columns = 3
		develop_grid.add_theme_constant_override("h_separation", 20)
		develop_grid.add_theme_constant_override("v_separation", 20)
		develop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(develop_grid)

	# Clear
	for child in develop_grid.get_children():
		child.queue_free()

	var visible_count: int = 0
	for local_entry_variant in _load_local_map_entries(256):
		if not (local_entry_variant is Dictionary):
			continue
		var local_entry: Dictionary = local_entry_variant
		if _is_local_template_map_entry(local_entry) or not _is_local_entry_owned_by_current_user(local_entry):
			continue
		var folder_name: String = str(local_entry.get("folder", "")).strip_edges().get_file()
		if folder_name.is_empty():
			continue
		_create_develop_card(develop_grid, folder_name)
		visible_count += 1

	if visible_count == 0:
		_add_placeholder_label(develop_grid, "You have not created any places yet.")

func _create_develop_card(parent_container: GridContainer, folder_name: String) -> void:
	var map_folder := UserSession.get_maps_root_path() + "/" + folder_name
	
	# Fetch meta
	var meta_name := folder_name
	var meta_path := map_folder + "/meta.json"
	if FileAccess.file_exists(meta_path):
		var f := FileAccess.open(meta_path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				var d: Dictionary = json.data
				meta_name = d.get("name", folder_name)
			f.close()
			
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(250, 200)
	card.add_theme_constant_override("separation", 8)
	
	var thumb_rect := ColorRect.new()
	thumb_rect.custom_minimum_size = Vector2(250, 140)
	var hash_val: int = folder_name.hash()
	var hue: float = fmod(absf(float(hash_val)) / 100000.0, 1.0)
	thumb_rect.color = Color.from_hsv(hue, 0.3, 0.85)
	
	var icon_path := map_folder + "/icon.png"
	if FileAccess.file_exists(icon_path):
		var img := _load_icon_image(icon_path)
		if img:
			img.resize(250, 140)
			var tex := ImageTexture.create_from_image(img)
			var tex_rect := TextureRect.new()
			tex_rect.texture = tex
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			thumb_rect.add_child(tex_rect)
			
	card.add_child(thumb_rect)
	
	var title_edit := LineEdit.new()
	title_edit.text = meta_name
	title_edit.custom_minimum_size = Vector2(0, 32)
	title_edit.text_submitted.connect(func(new_text): _rename_place(folder_name, new_text))
	card.add_child(title_edit)
	
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	card.add_child(btn_hbox)
	
	var edit_btn := Button.new()
	edit_btn.text = "Edit in Studio"
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap_folder := map_folder
	edit_btn.pressed.connect(func():
		GameState.selected_map_folder = cap_folder
		get_tree().change_scene_to_file("res://scenes/place_editor/studio.tscn")
	)
	btn_hbox.add_child(edit_btn)
	
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	del_btn.pressed.connect(func(): _delete_place(cap_folder))
	btn_hbox.add_child(del_btn)
	
	parent_container.add_child(card)

func _rename_place(folder_name: String, new_name: String) -> void:
	var clean_name: String = new_name.strip_edges()
	if clean_name.is_empty() or clean_name == folder_name:
		return

	var old_map_folder: String = UserSession.get_maps_root_path() + "/" + folder_name
	var new_map_folder: String = UserSession.get_maps_root_path() + "/" + clean_name
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir == null or maps_dir.dir_exists(clean_name):
		return
	if maps_dir.rename(folder_name, clean_name) != OK:
		return
	if GameState.selected_map_folder == old_map_folder:
		GameState.selected_map_folder = new_map_folder

	var meta_path := new_map_folder + "/meta.json"
	var meta := {"name": clean_name, "creator": UserSession.username if UserSession.is_logged_in else "Bobux"}

	if FileAccess.file_exists(meta_path):
		var f := FileAccess.open(meta_path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				meta = json.data
			f.close()
			
	meta["name"] = clean_name
	var wf := FileAccess.open(meta_path, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(meta, "\t"))
		wf.close()
		
	# Refresh views
	_build_recently_played_section()
	_build_develop_grid()
	_refresh_profile_games_section()

func _delete_place(map_folder: String) -> void:
	var meta: Dictionary = _read_json_dictionary(map_folder + "/meta.json")
	var cloud_map_id: String = str(meta.get("cloud_map_id", meta.get("map_id", ""))).strip_edges()
	var cloud_version_id: String = str(meta.get("cloud_version_id", "")).strip_edges()
	var display_name: String = str(meta.get("name", map_folder.get_file())).strip_edges()
	if cloud_map_id.is_empty() and CloudAPI != null and CloudAPI.has_method("resolve_cloud_map_id_for_name"):
		cloud_map_id = str(CloudAPI.resolve_cloud_map_id_for_name(display_name, meta)).strip_edges()
	UserSession.mark_deleted_game(cloud_map_id, display_name)
	if GameState.selected_map_folder == map_folder:
		GameState.selected_map_folder = ""
	if not cloud_map_id.is_empty() and CloudAPI != null and CloudAPI.is_configured():
		var delete_result: Dictionary = {}
		if CloudAPI.has_method("delete_map_and_cleanup"):
			delete_result = await CloudAPI.delete_map_and_cleanup(cloud_map_id)
		else:
			if CloudAPI.has_method("unpublish_map"):
				var unpublish_result: Dictionary = await CloudAPI.unpublish_map(cloud_map_id)
				if not bool(unpublish_result.get("ok", false)):
					push_warning("[Lobby] Cloud map unpublish failed for '%s': %s" % [cloud_map_id, str(unpublish_result.get("error", "Unknown error"))])
			delete_result = await CloudAPI.delete_map(cloud_map_id)
		if not bool(delete_result.get("ok", false)):
			push_warning("[Lobby] Cloud map delete/cleanup failed for '%s': %s" % [cloud_map_id, str(delete_result.get("error", "Unknown error"))])
	if CloudAPI != null and CloudAPI.is_configured() and not display_name.is_empty() and CloudAPI.has_method("delete_own_maps_by_name_and_cleanup"):
		var name_delete_result: Dictionary = await CloudAPI.delete_own_maps_by_name_and_cleanup(display_name)
		if not bool(name_delete_result.get("ok", false)):
			push_warning("[Lobby] Cloud duplicate-name cleanup failed for '%s': %s" % [display_name, str(name_delete_result.get("error", "Unknown error"))])
	var cached_folder: String = ""
	if not cloud_map_id.is_empty() and CloudAPI != null:
		cached_folder = CloudAPI.get_cached_map_folder(cloud_map_id, cloud_version_id)
	_remove_dir_recursive(map_folder)
	if not cached_folder.is_empty() and cached_folder != map_folder:
		_remove_dir_recursive(cached_folder)
	UserSession.remove_recent_game(cloud_map_id, map_folder, display_name)
	if not cloud_map_id.is_empty():
		_published_map_ids_cache.erase(cloud_map_id)
	var deleted_name_key: String = _normalize_map_name_key(display_name)
	if not deleted_name_key.is_empty():
		_published_map_names_cache.erase(deleted_name_key)
	_published_game_cache_expires_at_msec = 0
	_published_game_cache_loaded = false
	_local_map_entries_cache.clear()
	_local_map_entries_cache_expires_at_msec = 0
	_local_game_icon_path_cache.clear()

	_build_recently_played_section()
	_build_develop_grid()
	_refresh_profile_games_section()
	_schedule_home_dashboard_refresh(true)

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
	if parent_dir:
		parent_dir.remove(dir_path.get_file())

func _create_new_place_legacy_popup() -> void:
	# === Dark overlay backdrop ===
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# === Centered modal panel ===
	var modal := Panel.new()
	modal.custom_minimum_size = Vector2(720, 480)
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.offset_left = -360
	modal.offset_top = -240
	modal.offset_right = 360
	modal.offset_bottom = 240
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = Color(0.12, 0.13, 0.16, 1)
	modal_style.corner_radius_top_left = 16
	modal_style.corner_radius_top_right = 16
	modal_style.corner_radius_bottom_right = 16
	modal_style.corner_radius_bottom_left = 16
	modal_style.shadow_color = Color(0, 0, 0, 0.5)
	modal_style.shadow_size = 20
	modal_style.shadow_offset = Vector2(0, 8)
	modal.add_theme_stylebox_override("panel", modal_style)
	overlay.add_child(modal)

	# === Modal margin ===
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	modal.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	# === Header row ===
	var header_row := HBoxContainer.new()
	main_vbox.add_child(header_row)

	var title_label := Label.new()
	title_label.text = "Choose a Template"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(1, 1, 1, 0.05)
	close_style.corner_radius_top_left = 18
	close_style.corner_radius_top_right = 18
	close_style.corner_radius_bottom_right = 18
	close_style.corner_radius_bottom_left = 18
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.9, 0.25, 0.25, 0.8)
	close_hover.corner_radius_top_left = 18
	close_hover.corner_radius_top_right = 18
	close_hover.corner_radius_bottom_right = 18
	close_hover.corner_radius_bottom_left = 18
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.pressed.connect(func(): overlay.queue_free())
	header_row.add_child(close_btn)

	var subtitle := Label.new()
	subtitle.text = "Select a starting template for your new place"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	main_vbox.add_child(subtitle)

	# === Template Grid ===
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var templates = [
		{"name": "Baseplate", "icon": "BP", "color": Color(0.28, 0.52, 0.35), "color2": Color(0.2, 0.4, 0.25), "desc": "Classic flat baseplate to build on"},
		{"name": "Water World", "icon": "WW", "color": Color(0.15, 0.42, 0.82), "color2": Color(0.1, 0.3, 0.65), "desc": "Endless ocean with a small island"},
		{"name": "Town", "icon": "TN", "color": Color(0.55, 0.5, 0.35), "color2": Color(0.4, 0.38, 0.25), "desc": "Roads, houses and urban scenery"},
		{"name": "Obby 1", "icon": "O1", "color": Color(0.75, 0.25, 0.18), "color2": Color(0.6, 0.18, 0.12), "desc": "100 Stage Obby challenge course"},
		{"name": "Obby 2", "icon": "O2", "color": Color(0.15, 0.58, 0.68), "color2": Color(0.1, 0.42, 0.52), "desc": "Parkour Obby with platforming"},
		{"name": "Беспредел", "icon": "BP", "color": Color(0.86, 0.22, 0.08), "color2": Color(0.45, 0.08, 0.04), "desc": "Vehicle chaos arena with ramps, spawners and breakable obstacles"}
	]

	for t in templates:
		# --- Card container ---
		var card := Panel.new()
		card.custom_minimum_size = Vector2(200, 160)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = t["color"]
		card_style.corner_radius_top_left = 12
		card_style.corner_radius_top_right = 12
		card_style.corner_radius_bottom_right = 12
		card_style.corner_radius_bottom_left = 12
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.border_color = Color(1, 1, 1, 0.08)
		card_style.shadow_color = Color(0, 0, 0, 0.3)
		card_style.shadow_size = 6
		card_style.shadow_offset = Vector2(0, 3)
		card.add_theme_stylebox_override("panel", card_style)

		# Card inner layout
		var card_margin := MarginContainer.new()
		card_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_margin.add_theme_constant_override("margin_left", 16)
		card_margin.add_theme_constant_override("margin_top", 14)
		card_margin.add_theme_constant_override("margin_right", 16)
		card_margin.add_theme_constant_override("margin_bottom", 14)
		card.add_child(card_margin)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 8)
		card_margin.add_child(card_vbox)

		# Icon
		var icon_label := Label.new()
		icon_label.text = t["icon"]
		icon_label.add_theme_font_size_override("font_size", 36)
		card_vbox.add_child(icon_label)

		# Spacer
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(spacer)

		# Template name
		var name_lbl := Label.new()
		name_lbl.text = t["name"]
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		card_vbox.add_child(name_lbl)

		# Description
		var desc_lbl := Label.new()
		desc_lbl.text = t["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_vbox.add_child(desc_lbl)

		# Invisible button covering the whole card for click
		var click_btn := Button.new()
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Hover style: brighten border
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(1, 1, 1, 0.08)
		hover_style.corner_radius_top_left = 12
		hover_style.corner_radius_top_right = 12
		hover_style.corner_radius_bottom_right = 12
		hover_style.corner_radius_bottom_left = 12
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(1, 1, 1, 0.15)
		pressed_style.corner_radius_top_left = 12
		pressed_style.corner_radius_top_right = 12
		pressed_style.corner_radius_bottom_right = 12
		pressed_style.corner_radius_bottom_left = 12
		click_btn.add_theme_stylebox_override("hover", hover_style)
		click_btn.add_theme_stylebox_override("pressed", pressed_style)
		var t_name = t["name"]
		click_btn.pressed.connect(func():
			_generate_place_from_template(t_name)
			overlay.queue_free()
		)
		card.add_child(click_btn)

		grid.add_child(card)

func _generate_place_from_template(template_name: String, editor_scene_path: String = "res://scenes/place_editor/studio.tscn") -> void:
	var base_name := template_name
	var number := 1
	var folder_name := base_name + " " + str(number)
	var maps_dir := DirAccess.open(UserSession.get_maps_root_path())
	if maps_dir:
		while maps_dir.dir_exists(folder_name):
			number += 1
			folder_name = base_name + " " + str(number)
		maps_dir.make_dir(folder_name)
		
	var map_folder := UserSession.get_maps_root_path() + "/" + folder_name
	var meta := {
		"name": folder_name,
		"creator": UserSession.username if UserSession.is_logged_in else "Player",
		"description": "A new " + template_name + " place.",
		"is_template": false,
		"draft_unsaved": true,
		"is_published": false,
		"template_source": template_name,
		"cloud_map_id": "",
		"cloud_version_id": ""
	}
	var f := FileAccess.open(map_folder + "/meta.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))
		f.close()
	UserSession.unmark_deleted_game("", folder_name)
		
	var blocks = []
	
	if template_name == "Baseplate":
		blocks.append(_make_block(-20.0, -1.0, -20.0, 40.0, 1.0, 40.0, Color(0.45, 0.55, 0.45), "Plastic", "Baseplate"))
	elif template_name == "Water World":
		blocks.append(_make_block(-256.0, -2.0, -256.0, 512.0, 2.0, 512.0, Color(0.1, 0.4, 0.8), "Glass", "Water", 0.5))
		blocks.append(_make_block(-10.0, 0.0, -10.0, 20.0, 1.0, 20.0, Color(0.8, 0.7, 0.5), "Plastic", "Island"))
	elif template_name == "Town":
		# Green field
		blocks.append(_make_block(-128.0, -1.0, -128.0, 256.0, 1.0, 256.0, Color(0.3, 0.6, 0.3), "Plastic", "Grass"))
		# Roads
		blocks.append(_make_block(-15.0, 0.0, -128.0, 30.0, 0.1, 256.0, Color(0.2, 0.2, 0.2), "Plastic", "MainRoad"))
		blocks.append(_make_block(-128.0, 0.0, -15.0, 256.0, 0.1, 30.0, Color(0.2, 0.2, 0.2), "Plastic", "CrossRoad"))
		# House
		blocks.append(_make_block(20.0, 0.0, 20.0, 20.0, 15.0, 20.0, Color(0.8, 0.2, 0.2), "Plastic", "House"))
		blocks.append(_make_block(-40.0, 0.0, 20.0, 15.0, 10.0, 15.0, Color(0.2, 0.2, 0.8), "Plastic", "BlueHouse"))
	elif template_name == "Obby 1":
		blocks.append({
			"name": "Obby1_Scene", "px": 0.0, "py": 0.0, "pz": 0.0,
			"sx": 1.0, "sy": 1.0, "sz": 1.0, "rx": 0.0, "ry": 0.0, "rz": 0.0,
			"cr": 1.0, "cg": 1.0, "cb": 1.0, "ca": 1.0,
			"material": "Plastic", "shape": "Obby1", "transparency": 0.0,
			"can_collide": false, "is_spawn": false
		})
		var spawn_block = _make_block(0.0, 1.0, 0.0, 4.0, 0.5, 4.0, Color.WHITE, "Plastic", "Spawn")
		spawn_block["is_spawn"] = true
		blocks.append(spawn_block)
	elif template_name == "Obby 2":
		blocks.append({
			"name": "Obby2_Scene", "px": 0.0, "py": 0.0, "pz": 0.0,
			"sx": 50.0, "sy": 50.0, "sz": 50.0, "rx": 0.0, "ry": 0.0, "rz": 0.0,
			"cr": 1.0, "cg": 1.0, "cb": 1.0, "ca": 1.0,
			"material": "Plastic", "shape": "Obby2", "transparency": 0.0,
			"can_collide": false, "is_spawn": false
		})
		var spawn_block = _make_block(0.0, 1.0, 0.0, 4.0, 0.5, 4.0, Color.WHITE, "Plastic", "Spawn")
		spawn_block["is_spawn"] = true
		blocks.append(spawn_block)
	elif template_name == "Беспредел":
		_append_bespredel_template_blocks(blocks)
		
	var data := {"blocks": blocks, "time_of_day": 15.0 if template_name == "Беспредел" else 12.0}
	var df := FileAccess.open(map_folder + "/map_data.json", FileAccess.WRITE)
	if df:
		df.store_string(JSON.stringify(data, "\t"))
		df.close()

	GameState.selected_map_folder = map_folder
	get_tree().change_scene_to_file(editor_scene_path)

func _append_bespredel_template_blocks(blocks: Array) -> void:
	blocks.append(_make_block(-150.0, -1.0, -150.0, 300.0, 1.0, 300.0, Color(0.20, 0.22, 0.24), "Plastic", "Bespredel_Arena"))
	blocks.append(_make_block(-144.0, -0.78, -144.0, 288.0, 0.22, 288.0, Color(0.12, 0.12, 0.125), "Metal", "Bespredel_Asphalt"))
	blocks.append(_make_block(-32.0, 0.0, -126.0, 64.0, 0.44, 28.0, Color(0.07, 0.55, 0.90), "Neon", "Bespredel_PlayerSpawnPlatform"))

	var spawn_block := _make_block(-6.0, 0.52, -116.0, 12.0, 0.45, 12.0, Color(0.96, 0.96, 0.96), "Plastic", "Spawn", 0.0, 0.0, 0.0, 0.0, "Spawn")
	spawn_block["is_spawn"] = true
	blocks.append(spawn_block)

	var pad_color := Color(0.92, 0.08, 0.05)
	var car_pad := _make_block(-18.0, 0.06, -84.0, 36.0, 0.35, 24.0, pad_color, "Neon", "Bespredel_MasterCarPad", 0.0, 0.0, 0.0, 0.0, "VehicleSpawner")
	car_pad["vehicle_color"] = {"r": pad_color.r, "g": pad_color.g, "b": pad_color.b}
	car_pad["vehicle_kind"] = "CrashCar"
	blocks.append(car_pad)
	blocks.append(_make_block(-24.0, 0.46, -50.0, 48.0, 0.2, 34.0, Color(0.38, 0.38, 0.40), "Metal", "Bespredel_LaunchLane"))
	blocks.append(_make_block(-28.0, 0.0, -24.0, 56.0, 2.4, 26.0, Color(0.92, 0.36, 0.08), "Metal", "Bespredel_MainRamp", 0.0, -15.0, 0.0, 0.0, "Wedge"))
	blocks.append(_make_block(-22.0, 7.2, 8.0, 44.0, 1.0, 24.0, Color(0.92, 0.92, 0.96), "Plastic", "Bespredel_JumpPlatform"))

	for i in range(9):
		var angle := float(i) * TAU / 9.0
		var px := cos(angle) * 82.0
		var pz := sin(angle) * 60.0 + 18.0
		blocks.append(_make_block(px - 5.0, 0.0, pz - 5.0, 10.0, 4.0 + float(i % 3) * 1.4, 10.0, Color(0.78, 0.74, 0.64), "Plastic", "Bespredel_CrashPillar_%d" % i))

	for row in range(2):
		for col in range(7):
			var block_col := Color(0.88, 0.16 + 0.10 * float(row), 0.08)
			var piece := _make_block(-63.0 + float(col) * 21.0, 0.0, 76.0 + float(row) * 16.0, 12.0, 4.6, 8.0, block_col, "Plastic", "Bespredel_BreakWall_%d_%d" % [row, col], 0.0, 0.0, 0.0, 0.0, "Destructible")
			piece["breakable"] = true
			piece["health"] = 35
			blocks.append(piece)

	for side in [-1, 1]:
		blocks.append(_make_block(-150.0, 0.0, float(side) * 148.0, 300.0, 14.0, 4.0, Color(0.055, 0.055, 0.06), "Metal", "Bespredel_WallZ_%d" % side))
		blocks.append(_make_block(float(side) * 148.0, 0.0, -150.0, 4.0, 14.0, 300.0, Color(0.055, 0.055, 0.06), "Metal", "Bespredel_WallX_%d" % side))
		blocks.append(_make_block(float(side) * 82.0, 0.0, 6.0, 42.0, 2.2, 22.0, Color(0.12, 0.54, 0.96), "Metal", "Bespredel_SideRamp_%d" % side, 0.0, 0.0, 90.0, 0.0, "Wedge"))

func _make_block(x: float, y: float, z: float, sx: float, sy: float, sz: float, col: Color, mat: String, prefix: String, trans: float = 0.0, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0, shape_name: String = "Box") -> Dictionary:
	return {
		"name": prefix + "_block",
		"px": x + sx/2.0, "py": y + sy/2.0, "pz": z + sz/2.0,
		"sx": sx, "sy": sy, "sz": sz,
		"rx": rx, "ry": ry, "rz": rz,
		"cr": col.r, "cg": col.g, "cb": col.b, "ca": 1.0,
		"material": mat, "shape": shape_name, "transparency": trans,
		"can_collide": true, "is_spawn": false
	}

# Helper: load an icon image that might be mis-named (e.g. JPG saved as .png)
func _load_icon_image(path: String) -> Image:
	var bytes := PackedByteArray()
	if _is_inline_image_data(path):
		if path.length() > LOCAL_GAME_ICON_INLINE_CHAR_LIMIT:
			return null
		bytes = _decode_inline_image_bytes(path)
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			return null
		if file.get_length() > LOCAL_GAME_ICON_BODY_LIMIT_BYTES:
			file.close()
			return null
		bytes = file.get_buffer(file.get_length())
		file.close()
	if bytes.size() < 4:
		return null
	
	var img := Image.new()
	
	# Try PNG first (header: 0x89 0x50 0x4E 0x47)
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		if img.load_png_from_buffer(bytes) == OK:
			return img
	
	# Try JPG (header: 0xFF 0xD8)
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		if img.load_jpg_from_buffer(bytes) == OK:
			return img
	
	# Try WebP (header: RIFF....WEBP)
	if bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
		if img.load_webp_from_buffer(bytes) == OK:
			return img
	
	# Last attempt: try all formats blindly
	if img.load_png_from_buffer(bytes) == OK:
		return img
	if img.load_jpg_from_buffer(bytes) == OK:
		return img
	if img.load_webp_from_buffer(bytes) == OK:
		return img
	
	return null

func _is_inline_image_data(value: String) -> bool:
	return value.begins_with("data:image/") or value.begins_with("base64:")

func _is_http_url(value: String) -> bool:
	var clean_value: String = value.strip_edges().to_lower()
	return clean_value.begins_with("http://") or clean_value.begins_with("https://")

func _ensure_remote_game_icon_cache_dir() -> void:
	var absolute_dir := ProjectSettings.globalize_path(REMOTE_GAME_ICON_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)

func _get_remote_game_icon_cache_path(url: String) -> String:
	return REMOTE_GAME_ICON_CACHE_DIR.path_join("%s.png" % url.strip_edges().sha256_text())

func _get_legacy_remote_game_icon_cache_path(url: String) -> String:
	return REMOTE_GAME_ICON_CACHE_DIR.path_join("%d.png" % abs(hash(url)))

func _try_apply_cached_remote_game_icon(url: String, texture_rect: Variant) -> bool:
	if not is_instance_valid(texture_rect) or not (texture_rect is TextureRect):
		return false
	var cache_path := _get_remote_game_icon_cache_path(url)
	if not FileAccess.file_exists(cache_path):
		var legacy_cache_path := _get_legacy_remote_game_icon_cache_path(url)
		if not FileAccess.file_exists(legacy_cache_path):
			return false
		cache_path = legacy_cache_path
	var cached_image := Image.new()
	if cached_image.load(cache_path) != OK:
		return false
	if cache_path == _get_legacy_remote_game_icon_cache_path(url):
		_ensure_remote_game_icon_cache_dir()
		cached_image.save_png(_get_remote_game_icon_cache_path(url))
	var texture := ImageTexture.create_from_image(cached_image)
	_remote_game_icon_texture_cache[url] = texture
	var rect := texture_rect as TextureRect
	rect.texture = texture
	return true

func _retry_remote_game_icon_load(url: String, texture_rect: Variant, attempt: int) -> void:
	if _lobby_exiting or not is_inside_tree(): return
	if attempt >= 3:
		_remote_game_icon_waiters.erase(url)
		return
	await get_tree().create_timer(0.8 + (0.7 * float(attempt))).timeout
	if _lobby_exiting or not is_inside_tree(): return
	var retry_target := _first_valid_remote_game_icon_waiter(url)
	if retry_target == null and is_instance_valid(texture_rect) and texture_rect is TextureRect:
		retry_target = texture_rect as TextureRect
	if retry_target != null:
		_load_remote_game_icon_async(url, retry_target, attempt + 1)
	else:
		_remote_game_icon_waiters.erase(url)

func _register_remote_game_icon_waiter(url: String, texture_rect: TextureRect) -> void:
	if texture_rect == null or not is_instance_valid(texture_rect):
		return
	var waiters: Array = _remote_game_icon_waiters.get(url, []) if _remote_game_icon_waiters.get(url, []) is Array else []
	var instance_id := texture_rect.get_instance_id()
	for waiter_variant in waiters:
		var waiter_ref := waiter_variant as WeakRef
		var waiter_rect: TextureRect = waiter_ref.get_ref() as TextureRect if waiter_ref != null else null
		if waiter_rect != null and is_instance_valid(waiter_rect) and waiter_rect.get_instance_id() == instance_id:
			return
	waiters.append(weakref(texture_rect))
	_remote_game_icon_waiters[url] = waiters

func _first_valid_remote_game_icon_waiter(url: String) -> TextureRect:
	var waiters: Array = _remote_game_icon_waiters.get(url, []) if _remote_game_icon_waiters.get(url, []) is Array else []
	var retained_waiters: Array = []
	var first_valid: TextureRect = null
	for waiter_variant in waiters:
		var waiter_ref := waiter_variant as WeakRef
		var waiter_rect: TextureRect = waiter_ref.get_ref() as TextureRect if waiter_ref != null else null
		if waiter_rect == null or not is_instance_valid(waiter_rect):
			continue
		retained_waiters.append(waiter_ref)
		if first_valid == null:
			first_valid = waiter_rect
	_remote_game_icon_waiters[url] = retained_waiters
	return first_valid

func _apply_remote_game_icon_to_waiters(url: String, texture: Texture2D) -> void:
	var waiters: Array = _remote_game_icon_waiters.get(url, []) if _remote_game_icon_waiters.get(url, []) is Array else []
	_remote_game_icon_waiters.erase(url)
	for waiter_variant in waiters:
		var waiter_ref := waiter_variant as WeakRef
		var waiter_rect: TextureRect = waiter_ref.get_ref() as TextureRect if waiter_ref != null else null
		if waiter_rect != null and is_instance_valid(waiter_rect):
			waiter_rect.texture = texture

func _load_remote_game_icon_async(url: String, texture_rect: Variant, attempt: int = 0) -> void:
	if _lobby_exiting or not is_inside_tree() or not is_instance_valid(texture_rect): return
	var clean_url: String = url.strip_edges()
	if clean_url.is_empty() or texture_rect == null:
		return
	if _remote_game_icon_texture_cache.has(clean_url):
		texture_rect.texture = _remote_game_icon_texture_cache.get(clean_url, null)
		return
	if _try_apply_cached_remote_game_icon(clean_url, texture_rect):
		return
	_register_remote_game_icon_waiter(clean_url, texture_rect)
	if bool(_remote_game_icon_loading.get(clean_url, false)):
		return
	_remote_game_icon_loading[clean_url] = true
	var wait_started_msec: int = Time.get_ticks_msec()
	while _remote_game_icon_active_downloads >= REMOTE_GAME_ICON_MAX_CONCURRENT_DOWNLOADS:
		var active_target := _first_valid_remote_game_icon_waiter(clean_url)
		if active_target == null:
			_remote_game_icon_loading.erase(clean_url)
			_remote_game_icon_waiters.erase(clean_url)
			return
		if Time.get_ticks_msec() - wait_started_msec > 7000:
			_remote_game_icon_loading.erase(clean_url)
			_retry_remote_game_icon_load(clean_url, texture_rect, attempt)
			return
		await get_tree().create_timer(0.12).timeout
		if _lobby_exiting or not is_inside_tree(): return
	_remote_game_icon_active_downloads += 1
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = REMOTE_GAME_ICON_TIMEOUT_SECONDS
	request.body_size_limit = REMOTE_GAME_ICON_BODY_LIMIT_BYTES
	add_child(request)
	var start_error: Error = request.request(clean_url, PackedStringArray(["Accept: image/png,image/jpeg,image/webp,*/*"]), HTTPClient.METHOD_GET)
	if start_error != OK:
		_remote_game_icon_active_downloads = maxi(0, _remote_game_icon_active_downloads - 1)
		_remote_game_icon_loading.erase(clean_url)
		request.queue_free()
		_retry_remote_game_icon_load(clean_url, texture_rect, attempt)
		return
	var result: Array = await request.request_completed
	if _lobby_exiting or not is_inside_tree(): return
	_remote_game_icon_active_downloads = maxi(0, _remote_game_icon_active_downloads - 1)
	_remote_game_icon_loading.erase(clean_url)
	request.queue_free()
	if result.size() < 4 or int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) < 200 or int(result[1]) >= 300:
		_retry_remote_game_icon_load(clean_url, texture_rect, attempt)
		return
	var body: PackedByteArray = result[3] if result[3] is PackedByteArray else PackedByteArray()
	if body.is_empty():
		_retry_remote_game_icon_load(clean_url, texture_rect, attempt)
		return
	var image := Image.new()
	var load_error: Error = image.load_png_from_buffer(body)
	if load_error != OK:
		load_error = image.load_jpg_from_buffer(body)
	if load_error != OK:
		load_error = image.load_webp_from_buffer(body)
	if load_error != OK:
		_retry_remote_game_icon_load(clean_url, texture_rect, attempt)
		return
	_ensure_remote_game_icon_cache_dir()
	image.save_png(_get_remote_game_icon_cache_path(clean_url))
	var texture := ImageTexture.create_from_image(image)
	_remote_game_icon_texture_cache[clean_url] = texture
	_apply_remote_game_icon_to_waiters(clean_url, texture)

func _decode_inline_image_bytes(value: String) -> PackedByteArray:
	var encoded_value: String = value.strip_edges()
	if encoded_value.begins_with("data:image/"):
		var comma_index: int = encoded_value.find(",")
		if comma_index >= 0:
			encoded_value = encoded_value.substr(comma_index + 1)
	elif encoded_value.begins_with("base64:"):
		encoded_value = encoded_value.substr(7)
	return Marshalls.base64_to_raw(encoded_value)

func _extract_cloud_map_id_from_payload(payload: Variant) -> String:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		for key in ["id", "map_id", "cloud_map_id"]:
			var raw_id: String = str(payload_dict.get(key, "")).strip_edges()
			if not raw_id.is_empty():
				return raw_id
		if payload_dict.has("data"):
			return _extract_cloud_map_id_from_payload(payload_dict["data"])
	if payload is Array:
		var payload_array: Array = payload
		if not payload_array.is_empty():
			return _extract_cloud_map_id_from_payload(payload_array[0])
	return ""

func _extract_cloud_version_id_from_payload(payload: Variant) -> String:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		for key in ["cloud_version_id", "version_id", "updated_at"]:
			var raw_version: String = str(payload_dict.get(key, "")).strip_edges()
			if not raw_version.is_empty():
				return raw_version
		if payload_dict.has("data"):
			return _extract_cloud_version_id_from_payload(payload_dict["data"])
	if payload is Array:
		var payload_array: Array = payload
		if not payload_array.is_empty():
			return _extract_cloud_version_id_from_payload(payload_array[0])
	return ""

func _write_json_dictionary(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _embed_mode_assets_for_cloud(map_payload: Dictionary, folder: String, cloud_map_id: String) -> Dictionary:
	var enriched_payload: Dictionary = map_payload.duplicate(true)
	var mode_settings: Dictionary = enriched_payload.get("mode_settings", {}) if enriched_payload.get("mode_settings", {}) is Dictionary else {}
	var asset_files: Array = mode_settings.get("asset_files", []) if mode_settings.get("asset_files", []) is Array else []
	var playlist_files: Array = mode_settings.get("music_playlist", []) if mode_settings.get("music_playlist", []) is Array else []
	var asset_blobs: Dictionary = {}
	var asset_urls: Dictionary = {}
	var seen_files: Dictionary = {}
	var embedded_bytes: int = 0
	var skipped_assets: int = 0
	var publish_files: Array[String] = []
	for asset_variant in asset_files:
		var asset_name: String = str(asset_variant).strip_edges()
		if asset_name.is_empty() or seen_files.has(asset_name):
			continue
		seen_files[asset_name] = true
		publish_files.append(asset_name)
	for index in range(playlist_files.size()):
		if index >= CLOUD_INLINE_ASSET_MAX_TRACKS:
			skipped_assets += 1
			continue
		var track_name: String = str(playlist_files[index]).strip_edges()
		if track_name.is_empty() or seen_files.has(track_name):
			continue
		seen_files[track_name] = true
		publish_files.append(track_name)
	var total_files: int = publish_files.size()
	for index in range(publish_files.size()):
		var relative_file_name: String = publish_files[index]
		var absolute_path: String = folder.path_join(relative_file_name)
		if not FileAccess.file_exists(absolute_path):
			skipped_assets += 1
			continue
		var file_size: int = _get_file_size_bytes(absolute_path)
		if file_size <= 0:
			skipped_assets += 1
			push_warning("[Lobby] Skipping empty cloud asset '%s' during publish." % relative_file_name)
			continue
		if file_size > 50 * 1024 * 1024:
			skipped_assets += 1
			push_warning("[Lobby] Skipping cloud asset '%s' because it is %.2f MB (Storage safety limit 50 MB)." % [
				relative_file_name,
				float(file_size) / 1048576.0
			])
			continue
		_update_loading_overlay(
			"Preparing world...",
			"Uploading map audio %d/%d: %s" % [index + 1, maxi(total_files, 1), relative_file_name.get_file()],
			0.22 + 0.24 * float(index + 1) / float(maxi(total_files, 1))
		)
		await get_tree().process_frame
		var is_audio_asset: bool = _is_audio_asset_file_name(relative_file_name)
		var storage_result: Dictionary = await CloudAPI.upload_map_asset_file(
			cloud_map_id,
			relative_file_name,
			absolute_path,
			"",
			CloudAPI.HTTP_MEDIA_UPLOAD_TIMEOUT_SECONDS if is_audio_asset else CloudAPI.HTTP_UPLOAD_TIMEOUT_SECONDS,
			1 if is_audio_asset else 2
		)
		if bool(storage_result.get("ok", false)):
			var asset_data: Dictionary = storage_result.get("asset", {}) if storage_result.get("asset", {}) is Dictionary else {}
			var public_url: String = str(asset_data.get("public_url", "")).strip_edges()
			if not public_url.is_empty():
				asset_urls[relative_file_name] = public_url
				embedded_bytes += file_size
				continue
		push_warning("[Lobby] Storage upload failed for asset '%s': %s" % [
			relative_file_name,
			str(storage_result.get("error", "unknown storage error"))
		])
		if is_audio_asset:
			skipped_assets += 1
			continue
		if file_size <= 2 * 1024 * 1024 and embedded_bytes + file_size <= 8 * 1024 * 1024:
			var asset_base64: String = _encode_file_to_base64(absolute_path, 2 * 1024 * 1024)
			if not asset_base64.is_empty():
				asset_blobs[relative_file_name] = asset_base64
				embedded_bytes += file_size
			else:
				skipped_assets += 1
		else:
			skipped_assets += 1
	if not asset_blobs.is_empty():
		enriched_payload["mode_asset_blobs"] = asset_blobs
	if not asset_urls.is_empty():
		enriched_payload["mode_asset_urls"] = asset_urls
	var uploaded_count: int = asset_urls.size() + asset_blobs.size()
	if uploaded_count > 0:
		_update_loading_overlay(
			"Preparing world...",
			"Uploaded %d map asset(s)." % uploaded_count,
			0.48
		)
		await get_tree().process_frame
	var skybox_file: String = str(mode_settings.get("skybox_file", "")).strip_edges()
	if not skybox_file.is_empty():
		var skybox_path: String = folder.path_join(skybox_file)
		if FileAccess.file_exists(skybox_path):
			await get_tree().process_frame
			var skybox_base64: String = _encode_file_to_base64(skybox_path, CLOUD_INLINE_ASSET_MAX_BYTES)
			if not skybox_base64.is_empty():
				asset_blobs[skybox_file] = skybox_base64
	if not asset_blobs.is_empty():
		enriched_payload["mode_asset_blobs"] = asset_blobs
	if not asset_urls.is_empty():
		enriched_payload["mode_asset_urls"] = asset_urls
	if skipped_assets > 0:
		enriched_payload["mode_asset_warning"] = "%d asset(s) were too large or exceeded the publish budget." % skipped_assets
	return enriched_payload

func _get_file_size_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = file.get_length()
	file.close()
	return length

func _is_audio_asset_file_name(file_name: String) -> bool:
	var extension: String = file_name.get_extension().to_lower()
	return extension == "mp3" or extension == "ogg" or extension == "wav"

func _encode_file_to_base64(path: String, max_bytes: int = -1) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var file_length: int = file.get_length()
	if max_bytes > 0 and file_length > max_bytes:
		file.close()
		push_warning("[Lobby] Skipping cloud inline asset '%s' because it is %.2f MB (limit %.2f MB)." % [
			path.get_file(),
			float(file_length) / 1048576.0,
			float(max_bytes) / 1048576.0
		])
		return ""
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Marshalls.raw_to_base64(raw)

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

func _ensure_cloud_map_reference_for_game(game_info: Dictionary) -> Dictionary:
	var resolved_game_info: Dictionary = game_info.duplicate(true)
	var folder: String = str(resolved_game_info.get("folder", "")).strip_edges()
	var map_id: String = str(resolved_game_info.get("map_id", "")).strip_edges()
	var entry_cloud_map_id: String = str(resolved_game_info.get("cloud_map_id", "")).strip_edges()
	var cloud_version_id: String = str(resolved_game_info.get("cloud_version_id", "")).strip_edges()
	if map_id.is_empty() and not entry_cloud_map_id.is_empty():
		map_id = entry_cloud_map_id
		resolved_game_info["map_id"] = map_id
	if not map_id.is_empty():
		resolved_game_info["folder"] = ""
		return {"ok": true, "game_info": resolved_game_info}
	if folder.is_empty():
		return {"ok": true, "game_info": resolved_game_info}
	var meta_path: String = folder.path_join("meta.json")
	var map_data_path: String = folder.path_join("map_data.json")
	if not FileAccess.file_exists(map_data_path):
		return {"ok": false, "error": "Local map data is missing."}
	var meta: Dictionary = _read_json_dictionary(meta_path)
	var existing_cloud_map_id: String = str(meta.get("cloud_map_id", meta.get("map_id", ""))).strip_edges()
	var existing_cloud_version_id: String = str(meta.get("cloud_version_id", "")).strip_edges()
	if not existing_cloud_map_id.is_empty():
		resolved_game_info["map_id"] = existing_cloud_map_id
		cloud_version_id = existing_cloud_version_id if not existing_cloud_version_id.is_empty() else cloud_version_id
		resolved_game_info["cloud_version_id"] = cloud_version_id
		resolved_game_info["name"] = str(meta.get("name", resolved_game_info.get("name", folder.get_file()))).strip_edges()
		resolved_game_info["thumbnail"] = str(meta.get("thumbnail", resolved_game_info.get("thumbnail", ""))).strip_edges()
		resolved_game_info["folder"] = ""
		return {"ok": true, "game_info": resolved_game_info}
	if not CloudAPI.is_configured():
		return {"ok": false, "error": "Cloud API is not configured, so this local map cannot be published for dedicated play."}
	var preferred_username: String = UserSession.username if UserSession.is_logged_in else CloudAPI.get_current_username()
	var auth_result: Dictionary = {}
	for auth_attempt in range(3):
		auth_result = await CloudAPI.authenticate_or_create_profile(preferred_username)
		if bool(auth_result.get("ok", false)):
			break
		if auth_attempt < 2:
			await get_tree().create_timer(0.35).timeout
	if not bool(auth_result.get("ok", false)):
		push_error("[Lobby] Cloud auth failed while preparing map '%s': %s" % [str(resolved_game_info.get("name", folder.get_file())), str(auth_result.get("error", "unknown auth error"))])
		return auth_result
	var map_payload: Dictionary = _read_json_dictionary(map_data_path)
	if map_payload.is_empty():
		return {"ok": false, "error": "Local map payload is empty."}
	var map_name: String = str(meta.get("name", resolved_game_info.get("name", folder.get_file()))).strip_edges()
	if map_name.is_empty():
		map_name = folder.get_file()
	if CloudAPI.has_method("find_own_published_map_by_name"):
		var published_lookup: Dictionary = await CloudAPI.find_own_published_map_by_name(map_name)
		if bool(published_lookup.get("ok", false)):
			var published_map: Dictionary = published_lookup.get("data", {}) if published_lookup.get("data", {}) is Dictionary else {}
			var published_map_id: String = str(published_map.get("id", "")).strip_edges()
			if not published_map_id.is_empty():
				var published_version_id: String = str(published_map.get("cloud_version_id", "")).strip_edges()
				meta["cloud_map_id"] = published_map_id
				meta["map_id"] = published_map_id
				meta["cloud_version_id"] = published_version_id
				meta["name"] = str(published_map.get("name", map_name)).strip_edges()
				meta["thumbnail"] = str(published_map.get("thumbnail", meta.get("thumbnail", ""))).strip_edges()
				_write_json_dictionary(meta_path, meta)
				resolved_game_info["map_id"] = published_map_id
				resolved_game_info["cloud_version_id"] = published_version_id
				resolved_game_info["name"] = str(meta.get("name", map_name)).strip_edges()
				resolved_game_info["thumbnail"] = str(meta.get("thumbnail", resolved_game_info.get("thumbnail", ""))).strip_edges()
				resolved_game_info["folder"] = ""
				return {"ok": true, "game_info": resolved_game_info}
	var resolved_cloud_map_id: String = str(meta.get("cloud_map_id", map_id)).strip_edges()
	if resolved_cloud_map_id.is_empty() and CloudAPI.has_method("resolve_cloud_map_id_for_name"):
		resolved_cloud_map_id = str(CloudAPI.resolve_cloud_map_id_for_name(map_name, meta)).strip_edges()
	if resolved_cloud_map_id.is_empty():
		return {"ok": false, "error": "Could not resolve cloud map id before uploading map assets."}
	map_payload = await _embed_mode_assets_for_cloud(map_payload, folder, resolved_cloud_map_id)
	var thumbnail_payload: String = str(meta.get("thumbnail", "")).strip_edges()
	var icon_file_path: String = folder.path_join("icon.png")
	if FileAccess.file_exists(icon_file_path):
		var thumbnail_upload: Dictionary = await CloudAPI.upload_map_asset_file(resolved_cloud_map_id, "thumbnail.png", icon_file_path, "image/png")
		if bool(thumbnail_upload.get("ok", false)):
			var thumbnail_asset: Dictionary = thumbnail_upload.get("asset", {}) if thumbnail_upload.get("asset", {}) is Dictionary else {}
			thumbnail_payload = str(thumbnail_asset.get("public_url", "")).strip_edges()
		if thumbnail_payload.is_empty():
			thumbnail_payload = _encode_image_file_as_data_uri(icon_file_path)
	var upload_result: Dictionary = {}
	var upload_metadata := {
		"description": str(meta.get("description", resolved_game_info.get("description", ""))).strip_edges(),
		"thumbnail": thumbnail_payload,
		"is_published": true,
		"cloud_map_id": resolved_cloud_map_id,
		"cloud_version_id": str(meta.get("cloud_version_id", ""))
	}
	for upload_attempt in range(3):
		upload_result = await CloudAPI.upload_map_to_cloud(map_payload, map_name, upload_metadata)
		if bool(upload_result.get("ok", false)):
			break
		if upload_attempt < 2:
			await get_tree().create_timer(0.45).timeout
	if not bool(upload_result.get("ok", false)):
		push_error("[Lobby] Cloud upload failed for local map '%s': %s" % [map_name, str(upload_result.get("error", "unknown upload error"))])
		return upload_result
	var upload_payload: Variant = upload_result.get("data", upload_result)
	var cloud_map_id: String = _extract_cloud_map_id_from_payload(upload_payload)
	var resolved_version: String = _extract_cloud_version_id_from_payload(upload_payload)
	if cloud_map_id.is_empty():
		return {"ok": false, "error": "Cloud upload succeeded but did not return a usable map id."}
	meta["cloud_map_id"] = cloud_map_id
	meta["is_published"] = true
	meta["draft_unsaved"] = false
	if not resolved_version.is_empty():
		meta["cloud_version_id"] = resolved_version
	if str(meta.get("name", "")).strip_edges().is_empty():
		meta["name"] = map_name
	if not thumbnail_payload.is_empty():
		meta["thumbnail"] = thumbnail_payload
	_write_json_dictionary(meta_path, meta)
	resolved_game_info["map_id"] = cloud_map_id
	resolved_game_info["cloud_version_id"] = resolved_version if not resolved_version.is_empty() else cloud_version_id
	resolved_game_info["name"] = map_name
	resolved_game_info["thumbnail"] = thumbnail_payload
	resolved_game_info["folder"] = ""
	UserSession.unmark_deleted_game(cloud_map_id, map_name)
	_published_map_ids_cache[cloud_map_id] = true
	_published_game_cache_loaded = true
	var published_name_key: String = _normalize_map_name_key(map_name)
	if not published_name_key.is_empty():
		_published_map_names_cache[published_name_key] = true
	_published_game_cache_expires_at_msec = Time.get_ticks_msec() + PUBLISHED_GAME_CACHE_TTL_MS
	return {"ok": true, "game_info": resolved_game_info}

func _rebind_avatar_color_palette() -> void:
	var avatar_view: Node = main_tabs.get_node_or_null("AvatarView") if main_tabs else null
	if avatar_view == null:
		return
	var color_grid: GridContainer = _find_child_by_name_recursive(avatar_view, "ColorGrid") as GridContainer
	if color_grid == null:
		return
	_rebuild_color_grid(color_grid)
	call_deferred("_highlight_body_part_buttons")

func _rebuild_color_grid(color_grid: GridContainer) -> void:
	if color_grid == null:
		return
	for child in color_grid.get_children():
		child.queue_free()
	color_buttons.clear()
	for btn_name_key in COLOR_MAP.keys():
		var color_val: Color = COLOR_MAP[btn_name_key]
		var c_btn := Button.new()
		c_btn.name = btn_name_key
		c_btn.unique_name_in_owner = true
		c_btn.custom_minimum_size = Vector2(44, 44)
		c_btn.text = ""
		_apply_palette_button_style(c_btn, color_val)
		c_btn.pressed.connect(_on_color_selected.bind(color_val))
		color_grid.add_child(c_btn)
		color_buttons.append(c_btn)

func _apply_palette_button_style(target_button: Button, color_val: Color) -> void:
	if target_button == null:
		return
	var cs := StyleBoxFlat.new()
	cs.bg_color = color_val
	cs.corner_radius_top_left = 6
	cs.corner_radius_top_right = 6
	cs.corner_radius_bottom_left = 6
	cs.corner_radius_bottom_right = 6
	target_button.add_theme_stylebox_override("normal", cs)
	var cs_hover := cs.duplicate() as StyleBoxFlat
	cs_hover.border_width_left = 2
	cs_hover.border_width_top = 2
	cs_hover.border_width_right = 2
	cs_hover.border_width_bottom = 2
	cs_hover.border_color = Color(0.086, 0.357, 0.678)
	target_button.add_theme_stylebox_override("hover", cs_hover)
	target_button.add_theme_stylebox_override("pressed", cs_hover)

func _find_child_by_name_recursive(root: Node, desired_name: String) -> Node:
	if root == null:
		return null
	if root.name == desired_name:
		return root
	for child in root.get_children():
		var found: Node = _find_child_by_name_recursive(child, desired_name)
		if found != null:
			return found
	return null

func _start_smart_play_for_game(game_info: Dictionary) -> void:
	_ensure_experience_loading_overlay()
	_show_loading_overlay("Loading...", "Preparing %s for smart play" % str(game_info.get("name", "this game")), 0.05)
	_loading_overlay.call("set_experience", str(game_info.get("name", "Bobux")), game_info)
	_update_loading_overlay("Preparing world...", "Loading the newest local or cached version.", 0.38)
	var map_result: Dictionary = await _prepare_map_for_game(game_info, {})
	if not bool(map_result.get("ok", false)):
		_show_loading_error("Could not prepare the map.", str(map_result.get("error", "Unknown map error")))
		return
	var resolved_game_info: Dictionary = map_result.get("game_info", game_info) if map_result.get("game_info", game_info) is Dictionary else game_info
	_record_recent_game_from_entry(resolved_game_info, map_result)
	_queue_map_visit_increment(resolved_game_info)
	var map_info: Dictionary = _apply_prepared_map_selection(resolved_game_info, map_result, {})
	# FIX Bug-2: Prevent double scene transitions from rapid clicks.
	if _scene_change_in_progress:
		return
	_scene_change_in_progress = true
	GameState.configure_smart_play(_gather_colors(), map_info)
	if CloudAPI.is_configured() and CloudAPI.has_authenticated_session():
		await CloudAPI.update_profile_presence("online", str(map_info.get("name", resolved_game_info.get("name", ""))).strip_edges(), {})
	_update_loading_overlay("Loading...", "Connecting via dedicated WebSocket...", 0.92)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _queue_map_visit_increment(game_info: Dictionary) -> void:
	if CloudAPI == null or not CloudAPI.is_configured():
		return
	var map_id: String = str(game_info.get("map_id", "")).strip_edges()
	if map_id.is_empty():
		return
	# CloudAPI is an autoload and survives the lobby scene change. Queuing the
	# request on it prevents a visit from being lost when this scene is freed.
	CloudAPI.call_deferred(
		"increment_map_visits",
		map_id,
		int(game_info.get("visits", game_info.get("visits_count", 0)))
	)

func _join_server_flow(game_info: Dictionary, server_info: Dictionary) -> void:
	_update_loading_overlay("Preparing world...", "Loading the latest map version.", 0.52)
	var map_result: Dictionary = await _prepare_map_for_game(game_info, server_info)
	if not bool(map_result.get("ok", false)):
		_show_loading_error("Could not load the map.", str(map_result.get("error", "Unknown map error")))
		return

	var resolved_game_info: Dictionary = map_result.get("game_info", game_info) if map_result.get("game_info", game_info) is Dictionary else game_info
	_record_recent_game_from_entry(resolved_game_info, map_result)
	_queue_map_visit_increment(resolved_game_info)
	_apply_prepared_map_selection(resolved_game_info, map_result, server_info)
	var targeted_server_info: Dictionary = server_info.duplicate(true)
	targeted_server_info["map_name"] = str(targeted_server_info.get("map_name", resolved_game_info.get("name", "Untitled Experience"))).strip_edges()
	targeted_server_info["map_id"] = str(targeted_server_info.get("map_id", resolved_game_info.get("map_id", resolved_game_info.get("id", "")))).strip_edges()
	targeted_server_info["cloud_version_id"] = str(targeted_server_info.get("cloud_version_id", resolved_game_info.get("cloud_version_id", ""))).strip_edges()
	targeted_server_info["port"] = int(targeted_server_info.get("port", GameState.DEFAULT_PORT))
	targeted_server_info["ip"] = str(targeted_server_info.get("ip", "")).strip_edges()
	if _scene_change_in_progress:
		return
	_scene_change_in_progress = true
	GameState.configure_target_join(targeted_server_info, _gather_colors())
	if CloudAPI.is_configured() and CloudAPI.has_authenticated_session():
		await CloudAPI.update_profile_presence("online", str(targeted_server_info.get("map_name", resolved_game_info.get("name", ""))).strip_edges(), targeted_server_info)
	_update_loading_overlay("Joining server...", "Connecting you now.", 0.95)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _host_game_flow(game_info: Dictionary) -> void:
	_update_loading_overlay("Preparing server...", "Creating your world.", 0.46)
	var map_result: Dictionary = await _prepare_map_for_game(game_info, {})
	if not bool(map_result.get("ok", false)):
		_show_loading_error("Could not prepare the map.", str(map_result.get("error", "Unknown map error")))
		return

	var resolved_game_info: Dictionary = map_result.get("game_info", game_info) if map_result.get("game_info", game_info) is Dictionary else game_info
	_record_recent_game_from_entry(resolved_game_info, map_result)
	_queue_map_visit_increment(resolved_game_info)
	_apply_prepared_map_selection(resolved_game_info, map_result, {})
	if _scene_change_in_progress:
		return
	_scene_change_in_progress = true
	GameState.configure_host(GameState.DEFAULT_PORT, _gather_colors())
	if CloudAPI.is_configured() and CloudAPI.has_authenticated_session():
		await CloudAPI.update_profile_presence("online", str(resolved_game_info.get("name", "Untitled Experience")).strip_edges(), {})
	_update_loading_overlay("Starting server...", "Publishing and opening your experience.", 0.95)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _prepare_map_for_game(game_info: Dictionary, server_info: Dictionary) -> Dictionary:
	var resolved_game_info: Dictionary = game_info.duplicate(true)
	if server_info.is_empty():
		var cloud_ready_result: Dictionary = await _ensure_cloud_map_reference_for_game(resolved_game_info)
		if not bool(cloud_ready_result.get("ok", false)):
			push_error("[Lobby] Could not make map cloud-ready for '%s': %s" % [str(resolved_game_info.get("name", "Unknown")), str(cloud_ready_result.get("error", "unknown error"))])
			return cloud_ready_result
		resolved_game_info = cloud_ready_result.get("game_info", resolved_game_info) if cloud_ready_result.get("game_info", resolved_game_info) is Dictionary else resolved_game_info
	var folder: String = str(resolved_game_info.get("folder", "")).strip_edges()
	var map_id: String = str(server_info.get("map_id", resolved_game_info.get("map_id", ""))).strip_edges()
	var cloud_version_id: String = str(server_info.get("cloud_version_id", resolved_game_info.get("cloud_version_id", ""))).strip_edges()
	var game_name: String = str(resolved_game_info.get("name", server_info.get("map_name", "Cloud Map"))).strip_edges()
	var has_local_folder: bool = not folder.is_empty() and FileAccess.file_exists(folder.path_join("map_data.json"))

	if not map_id.is_empty():
		if CloudAPI.is_configured() and CloudAPI.has_method("fetch_published_map_metadata"):
			var metadata_result: Dictionary = await CloudAPI.fetch_published_map_metadata(map_id)
			if not bool(metadata_result.get("ok", false)):
				return {"ok": false, "error": "Could not verify that this experience still exists."}
			var metadata_rows: Array = _extract_response_array(metadata_result)
			if metadata_rows.is_empty():
				return {"ok": false, "error": "This experience was deleted or is no longer published."}
			if metadata_rows[0] is Dictionary:
				var canonical_map := metadata_rows[0] as Dictionary
				for canonical_key in ["name", "owner_id", "owner_name", "thumbnail", "cloud_version_id", "updated_at", "likes_count", "visits_count"]:
					if canonical_map.has(canonical_key):
						resolved_game_info[canonical_key] = canonical_map.get(canonical_key)
				cloud_version_id = str(canonical_map.get("cloud_version_id", cloud_version_id)).strip_edges()
		var cached_folder: String = CloudAPI.get_cached_map_folder(map_id, cloud_version_id)
		if not cached_folder.is_empty():
			return {
				"ok": true,
				"folder": cached_folder,
				"cloud_version_id": cloud_version_id,
				"game_info": resolved_game_info
			}
		if not CloudAPI.is_configured():
			return {
				"ok": false,
				"error": "Cloud API is not configured, so this map cannot be downloaded."
			}
		var download_result: Dictionary = await CloudAPI.download_map_with_cache(map_id, cloud_version_id, game_name)
		if not bool(download_result.get("ok", false)):
			push_error("[Lobby] Cloud map download failed for '%s': %s" % [game_name, str(download_result.get("error", "Unknown cloud error"))])
			return download_result
		return {
			"ok": true,
			"folder": str(download_result.get("folder", "")).strip_edges(),
			"cloud_version_id": str(download_result.get("cloud_version_id", cloud_version_id)).strip_edges(),
			"game_info": resolved_game_info
		}

	if has_local_folder:
		return {
			"ok": false,
			"error": "This experience exists only as a local draft. Publish it to Bobux Cloud before playing."
		}

	if not server_info.is_empty():
		return {
			"ok": false,
			"error": "This room did not expose a valid cloud map id, so the map could not be loaded."
		}

	return {
		"ok": true,
		"folder": "",
		"cloud_version_id": cloud_version_id,
		"game_info": resolved_game_info
	}

func _apply_prepared_map_selection(game_info: Dictionary, map_result: Dictionary, server_info: Dictionary) -> Dictionary:
	var folder_path: String = str(map_result.get("folder", game_info.get("folder", ""))).strip_edges()
	var resolved_map_name: String = str(server_info.get("map_name", game_info.get("name", ""))).strip_edges()
	var resolved_map_id: String = str(server_info.get("map_id", game_info.get("map_id", ""))).strip_edges()
	var resolved_cloud_version_id: String = str(map_result.get("cloud_version_id", game_info.get("cloud_version_id", ""))).strip_edges()
	if not folder_path.is_empty():
		var folder_meta: Dictionary = _read_json_dictionary(folder_path.path_join("meta.json"))
		var meta_name: String = str(folder_meta.get("name", "")).strip_edges()
		if not meta_name.is_empty():
			resolved_map_name = meta_name
		elif resolved_map_name.is_empty():
			resolved_map_name = folder_path.get_file().strip_edges()
		# Prefer cloud_map_id from meta.json for maps that have been published.
		var meta_cloud_map_id: String = str(folder_meta.get("cloud_map_id", "")).strip_edges()
		if not meta_cloud_map_id.is_empty() and resolved_map_id.is_empty():
			resolved_map_id = meta_cloud_map_id
		var meta_cloud_version: String = str(folder_meta.get("cloud_version_id", "")).strip_edges()
		if not meta_cloud_version.is_empty() and resolved_cloud_version_id.is_empty():
			resolved_cloud_version_id = meta_cloud_version
	if resolved_map_name.is_empty():
		resolved_map_name = "Untitled Experience"
	GameState.selected_map_folder = folder_path
	GameState.selected_map = resolved_map_name
	return {
		"map_id": resolved_map_id,
		"name": resolved_map_name,
		"cloud_version_id": resolved_cloud_version_id
	}

func _select_best_server(servers: Array) -> Dictionary:
	var best_server: Dictionary = {}
	var best_ping: float = INF
	for index in range(servers.size()):
		var server_variant: Variant = servers[index]
		if not (server_variant is Dictionary):
			continue
		var server: Dictionary = server_variant
		var ip: String = str(server.get("ip", "")).strip_edges()
		var port: int = int(server.get("port", GameState.DEFAULT_PORT))
		var progress: float = 0.34 + (0.18 * float(index + 1) / float(maxi(servers.size(), 1)))
		_update_loading_overlay("Testing latency...", "Checking %s:%d" % [ip, port], progress)
		var ping_ms: float = await NetworkManager.measure_server_latency(ip, port, 1.1)
		if ping_ms < best_ping:
			best_ping = ping_ms
			best_server = server
			best_server["measured_ping_ms"] = ping_ms
	if best_server.is_empty() and not servers.is_empty() and servers[0] is Dictionary:
		best_server = servers[0]
	return best_server

func _server_matches_game(server_info: Dictionary, game_info: Dictionary) -> bool:
	var desired_map_id: String = str(game_info.get("map_id", "")).strip_edges()
	var desired_name: String = str(game_info.get("name", "")).strip_edges()
	var server_map_id: String = str(server_info.get("map_id", "")).strip_edges()
	var server_name: String = str(server_info.get("map_name", "")).strip_edges()
	if not desired_map_id.is_empty() and server_map_id == desired_map_id:
		return true
	if desired_map_id.is_empty() and not desired_name.is_empty() and server_name == desired_name:
		return true
	return false

func _create_smart_play_card(game_info: Dictionary, show_active_players: bool, keep_compact_width: bool = false) -> Panel:
	var panel := Panel.new()
	panel.name = "SmartPlayCard"
	panel.set_meta("bobux_game_id", str(game_info.get("id", game_info.get("map_id", ""))))
	panel.set_meta("bobux_game_name", str(game_info.get("name", "Untitled Experience")))
	var mobile_card: bool = _is_mobile_beta()
	var card_width: float = 148.0 if mobile_card else 148.0
	var card_height: float = 224.0
	panel.custom_minimum_size = Vector2(card_width, card_height)
	# More room adds columns; it must never turn a square cover into a wide card.
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal_card_style := StyleBoxFlat.new()
	normal_card_style.bg_color = Color.WHITE
	normal_card_style.border_width_left = 1
	normal_card_style.border_width_top = 1
	normal_card_style.border_width_right = 1
	normal_card_style.border_width_bottom = 1
	normal_card_style.border_color = Color(0.79, 0.80, 0.82, 1)
	normal_card_style.shadow_color = Color(0, 0, 0, 0.12)
	normal_card_style.shadow_size = 2
	normal_card_style.shadow_offset = Vector2(0, 1)
	normal_card_style.corner_radius_top_left = 2
	normal_card_style.corner_radius_top_right = 2
	normal_card_style.corner_radius_bottom_left = 2
	normal_card_style.corner_radius_bottom_right = 2
	var hover_card_style := normal_card_style.duplicate() as StyleBoxFlat
	hover_card_style.border_color = Color(0.0, 0.55, 0.88, 1)
	hover_card_style.shadow_color = Color(0, 0, 0, 0.14)
	hover_card_style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", normal_card_style)
	var open_details := func() -> void:
		_show_game_details_page(game_info)
	var press_pos := Vector2.ZERO
	var click_opens_details := func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
			else:
				if press_pos.distance_to(event.position) < 15.0:
					var mobile_runtime = get_node_or_null("/root/MobileRuntime")
					if mobile_runtime == null or not mobile_runtime.get("_ui_scroll_dragged"):
						open_details.call()
	panel.gui_input.connect(click_opens_details)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 1)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_right", 1)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	# Keep the asynchronously populated thumbnail separate from the interactive
	# hover layer.  Remote image completion may rebuild/update the thumbnail,
	# but it must never be able to remove the Play button beneath the pointer.
	var media_host := Control.new()
	media_host.name = "MediaHost"
	media_host.custom_minimum_size = Vector2(0, card_width - 2)
	media_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	media_host.mouse_filter = Control.MOUSE_FILTER_STOP
	media_host.gui_input.connect(click_opens_details)
	root.add_child(media_host)

	var icon_widget := _create_game_icon_widget(game_info, card_width - 2)
	icon_widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	media_host.add_child(icon_widget)

	var play_overlay := Panel.new()
	play_overlay.name = "PlayHoverOverlay"
	play_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# PASS lets the overlay keep its hover state while the child Play button
	# receives the actual click.  IGNORE caused transient parent mouse exits on
	# some scaled/scrolling lobby layouts, making Play flash and disappear.
	play_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	play_overlay.visible = true
	play_overlay.modulate.a = 1.0 if mobile_card else 0.0
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.02, 0.04, 0.06, 0.52)
	play_overlay.add_theme_stylebox_override("panel", overlay_style)
	media_host.add_child(play_overlay)

	var play_button := Button.new()
	play_button.name = "PlayButton"
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(76, 32)
	play_button.set_anchors_preset(Control.PRESET_CENTER)
	play_button.offset_left = -38.0
	play_button.offset_top = -16.0
	play_button.offset_right = 38.0
	play_button.offset_bottom = 16.0
	play_button.mouse_filter = Control.MOUSE_FILTER_STOP
	play_button.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.18, 0.72, 0.38, 1.0)))
	play_button.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.22, 0.79, 0.43, 1.0)))
	play_button.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.14, 0.62, 0.32, 1.0)))
	play_button.add_theme_color_override("font_color", Color.WHITE)
	play_button.pressed.connect(func(): _start_smart_play_for_game(game_info))
	play_overlay.add_child(play_button)
	if not mobile_card:
		_smart_play_hover_cards.append({
			"panel": panel,
			"overlay": play_overlay,
			"normal_style": normal_card_style,
			"hover_style": hover_card_style,
		})
		var show_play_overlay := func() -> void:
			if is_instance_valid(play_overlay) and is_instance_valid(panel):
				play_overlay.modulate.a = 1.0
				panel.add_theme_stylebox_override("panel", hover_card_style)
		panel.mouse_entered.connect(show_play_overlay)
		media_host.mouse_entered.connect(show_play_overlay)
		play_overlay.mouse_entered.connect(show_play_overlay)
		play_button.mouse_entered.connect(show_play_overlay)
		panel.mouse_exited.connect(func() -> void:
			_defer_smart_play_card_hover_exit(panel, play_overlay, normal_card_style, hover_card_style)
		)

	var body_margin := MarginContainer.new()
	body_margin.name = "CardDetails"
	body_margin.add_theme_constant_override("margin_left", 7)
	body_margin.add_theme_constant_override("margin_right", 7)
	root.add_child(body_margin)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 2)
	body_margin.add_child(details)
	var title := Button.new()
	title.name = "GameTitle"
	title.text = str(game_info.get("name", "Untitled Experience"))
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.custom_minimum_size = Vector2(0, 23)
	title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.focus_mode = Control.FOCUS_NONE
	title.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	title.add_theme_font_size_override("font_size", 13)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	var title_style := StyleBoxEmpty.new()
	title.add_theme_stylebox_override("normal", title_style)
	title.add_theme_stylebox_override("hover", title_style)
	title.add_theme_stylebox_override("pressed", title_style)
	title.pressed.connect(open_details)
	details.add_child(title)

	var descriptor := Label.new()
	descriptor.add_theme_color_override("font_color", Color(0.46, 0.46, 0.46, 1))
	descriptor.add_theme_font_size_override("font_size", 11)
	var active_players: int = int(game_info.get("active_players", 0))
	var visits: int = int(game_info.get("visits", game_info.get("visits_count", game_info.get("plays", 0))))
	var likes: int = int(game_info.get("likes", game_info.get("likes_count", 0)))
	descriptor.name = "OnlineCount"
	descriptor.text = "%s Playing" % _compact_count(active_players)
	descriptor.tooltip_text = "%d игроков онлайн · %d посещений" % [active_players, visits]
	descriptor.max_lines_visible = 1
	descriptor.custom_minimum_size = Vector2(0, 16)
	descriptor.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	descriptor.mouse_filter = Control.MOUSE_FILTER_STOP
	descriptor.gui_input.connect(click_opens_details)
	details.add_child(descriptor)

	var rating := preload("res://scripts/lobby/game_rating_bar.gd").new()
	rating.name = "GameRating"
	rating.configure(game_info)
	rating.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(rating)
	rating.gui_input.connect(click_opens_details)
	return panel

func _defer_smart_play_card_hover_exit(panel: Panel, play_overlay: Panel, normal_style: StyleBoxFlat, hover_style: StyleBoxFlat) -> void:
	if _lobby_exiting or not is_inside_tree(): return
	# A child button causes a transient mouse_exited on its parent. Re-check on
	# the next frame so the Play button remains clickable while the pointer is
	# anywhere inside the card.
	await get_tree().create_timer(0.08).timeout
	if _lobby_exiting or not is_inside_tree(): return
	if not is_instance_valid(panel) or not is_instance_valid(play_overlay):
		return
	# Local coordinates remain correct inside scaled roots and ScrollContainers.
	# Comparing viewport coordinates with a transformed global rect made hover
	# collapse while the pointer was visibly still over the Play button.
	var local_pointer := panel.get_local_mouse_position()
	var still_inside := Rect2(Vector2.ZERO, panel.size).grow(3.0).has_point(local_pointer)
	play_overlay.modulate.a = 1.0 if still_inside else 0.0
	panel.add_theme_stylebox_override("panel", hover_style if still_inside else normal_style)

func _show_game_details_popup(_trigger: Control, game_info: Dictionary) -> void:
	_ensure_home_friend_popup()
	if home_friend_popup == null:
		return
	_prepare_home_friend_popup_surface()
	_clear_container(home_friend_popup)

	var popup_size := Vector2(
		maxf(720.0, get_viewport_rect().size.x - 32.0),
		maxf(560.0, get_viewport_rect().size.y - 32.0)
	)
	home_friend_popup.custom_minimum_size = popup_size
	home_friend_popup.size = popup_size

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	home_friend_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)
	root.add_child(top_row)

	var hero := _create_game_icon_widget(game_info)
	hero.custom_minimum_size = Vector2(610, 310)
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(hero)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(250, 0)
	side.add_theme_constant_override("separation", 10)
	top_row.add_child(side)

	var title := Label.new()
	title.text = str(game_info.get("name", "Untitled Experience")).strip_edges()
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 1))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(title)

	var creator := Label.new()
	var creator_name: String = str(game_info.get("owner_name", game_info.get("creator", "Bobux"))).strip_edges()
	creator.text = "By %s" % (creator_name if not creator_name.is_empty() else "Bobux")
	creator.add_theme_font_size_override("font_size", 13)
	creator.add_theme_color_override("font_color", Color(0.08, 0.52, 0.77, 1))
	side.add_child(creator)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 64)
	side.add_child(spacer)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(0, 54)
	play_button.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.24, 0.76, 0.45, 1.0)))
	play_button.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.29, 0.82, 0.5, 1.0)))
	play_button.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.2, 0.66, 0.39, 1.0)))
	play_button.add_theme_color_override("font_color", Color.WHITE)
	play_button.add_theme_font_size_override("font_size", 18)
	play_button.pressed.connect(func():
		home_friend_popup.hide()
		_start_smart_play_for_game(game_info)
	)
	side.add_child(play_button)

	var reactions := HBoxContainer.new()
	reactions.add_theme_constant_override("separation", 14)
	side.add_child(reactions)
	for reaction_text in ["Fav %s" % str(game_info.get("favorites", game_info.get("likes", 0))), "Like %s" % str(game_info.get("likes", "0")), "Dislike %s" % str(game_info.get("dislikes", "0"))]:
		var reaction := Label.new()
		reaction.text = reaction_text
		reaction.add_theme_font_size_override("font_size", 13)
		reaction.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
		reactions.add_child(reaction)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 0)
	root.add_child(tab_bar)
	for tab_name in ["About", "Store", "Leaderboards", "Servers"]:
		var tab_label := Label.new()
		tab_label.text = tab_name
		tab_label.custom_minimum_size = Vector2(0, 42)
		tab_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tab_label.add_theme_font_size_override("font_size", 15)
		tab_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = Color(0.98, 0.98, 0.98, 1)
		tab_style.border_width_bottom = 4 if tab_name == "About" else 1
		tab_style.border_color = Color(0.0, 0.62, 0.86, 1) if tab_name == "About" else Color(0.82, 0.82, 0.82, 1)
		tab_label.add_theme_stylebox_override("normal", tab_style)
		tab_bar.add_child(tab_label)

	var description_panel := Panel.new()
	description_panel.add_theme_stylebox_override("panel", _make_white_panel_style())
	description_panel.custom_minimum_size = Vector2(0, 150)
	root.add_child(description_panel)

	var desc_margin := MarginContainer.new()
	desc_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_margin.add_theme_constant_override("margin_left", 14)
	desc_margin.add_theme_constant_override("margin_top", 12)
	desc_margin.add_theme_constant_override("margin_right", 14)
	desc_margin.add_theme_constant_override("margin_bottom", 12)
	description_panel.add_child(desc_margin)

	var desc_root := VBoxContainer.new()
	desc_root.add_theme_constant_override("separation", 8)
	desc_margin.add_child(desc_root)

	var desc_title := Label.new()
	desc_title.text = "Description"
	desc_title.add_theme_font_size_override("font_size", 20)
	desc_title.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	desc_root.add_child(desc_title)

	var desc_text := Label.new()
	desc_text.text = str(game_info.get("description", "A retro Roblox-style experience.")).strip_edges()
	if desc_text.text.is_empty():
		desc_text.text = "A retro Roblox-style experience."
	desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_text.add_theme_font_size_override("font_size", 13)
	desc_text.add_theme_color_override("font_color", Color(0.31, 0.32, 0.34, 1))
	desc_root.add_child(desc_text)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 18)
	desc_root.add_child(stats_row)
	var stats := {
		"Visits": str(game_info.get("visits", game_info.get("plays", 0))),
		"Max Players": str(game_info.get("max_players", NetworkManager.MAX_CLIENTS if NetworkManager != null else 10)),
		"Genre": str(game_info.get("genre", "All")),
		"Active": str(game_info.get("active_players", 0))
	}
	for stat_name in stats.keys():
		var stat_box := VBoxContainer.new()
		stat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stat_label := Label.new()
		stat_label.text = stat_name
		stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_label.add_theme_font_size_override("font_size", 11)
		stat_label.add_theme_color_override("font_color", Color(0.62, 0.63, 0.66, 1))
		stat_box.add_child(stat_label)
		var stat_value := Label.new()
		stat_value.text = str(stats[stat_name])
		stat_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_value.add_theme_font_size_override("font_size", 13)
		stat_value.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
		stat_box.add_child(stat_value)
		stats_row.add_child(stat_box)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48, 1))
	close_btn.pressed.connect(func(): home_friend_popup.hide())
	root.add_child(close_btn)

	var viewport_size: Vector2 = get_viewport_rect().size
	home_friend_popup.global_position = Vector2(
		maxf(16.0, (viewport_size.x - popup_size.x) * 0.5),
		maxf(16.0, (viewport_size.y - popup_size.y) * 0.5)
	)
	home_friend_popup.show()

func _show_game_details_page(game_info: Dictionary) -> void:
	if main_tabs.current_tab != Tab.GAME_DETAILS:
		_game_details_return_tab = main_tabs.current_tab
	if home_friend_popup != null:
		home_friend_popup.hide()
	preload("res://scripts/lobby/game_details_builder.gd").build(self, game_info, _game_details_return_tab)
	_switch_tab(Tab.GAME_DETAILS)

func _create_game_details_tab_label(tab_name: String, selected: bool) -> Label:
	var tab_label := Label.new()
	tab_label.text = tab_name
	tab_label.custom_minimum_size = Vector2(0, 42)
	tab_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab_label.add_theme_font_size_override("font_size", 15)
	tab_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = Color(0.98, 0.98, 0.98, 1)
	tab_style.border_width_bottom = 4 if selected else 1
	tab_style.border_color = Color(0.0, 0.62, 0.86, 1) if selected else Color(0.82, 0.82, 0.82, 1)
	tab_label.add_theme_stylebox_override("normal", tab_style)
	return tab_label

func _add_game_detail_stat(parent: HBoxContainer, stat_name: String, stat_value: String) -> void:
	var stat_box := VBoxContainer.new()
	stat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stat_label := Label.new()
	stat_label.text = stat_name
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_label.add_theme_font_size_override("font_size", 11)
	stat_label.add_theme_color_override("font_color", Color(0.62, 0.63, 0.66, 1))
	stat_box.add_child(stat_label)
	var value_label := Label.new()
	value_label.text = stat_value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	stat_box.add_child(value_label)
	parent.add_child(stat_box)

func _format_game_date(raw_value: String) -> String:
	var clean_value: String = raw_value.strip_edges()
	if clean_value.is_empty():
		return "-"
	if clean_value.length() >= 10:
		return clean_value.substr(0, 10)
	return clean_value

func _create_game_icon_widget(game_info: Dictionary, preferred_height: float = 112.0) -> Control:
	var wrapper := Panel.new()
	var icon_height: float = maxf(72.0, preferred_height)
	wrapper.custom_minimum_size = Vector2(0, icon_height)
	wrapper.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_hsv(fmod(absf(float(str(game_info.get("name", "Game")).hash())) / 100000.0, 1.0), 0.25, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	wrapper.add_theme_stylebox_override("panel", style)

	var icon_path: String = _resolve_game_icon_path(game_info)
	if not icon_path.is_empty() and (FileAccess.file_exists(icon_path) or _is_inline_image_data(icon_path)):
		var image := _load_icon_image(icon_path)
		if image:
			var texture_rect := TextureRect.new()
			texture_rect.texture = ImageTexture.create_from_image(image)
			texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.add_child(texture_rect)
			return wrapper
	if not icon_path.is_empty() and _is_http_url(icon_path):
		var texture_rect := TextureRect.new()
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(texture_rect)
		_load_remote_game_icon_async(icon_path, texture_rect)
		return wrapper

	var icon_label := Label.new()
	icon_label.set_anchors_preset(Control.PRESET_CENTER)
	icon_label.text = str(game_info.get("name", "G")).left(1).to_upper()
	icon_label.add_theme_font_size_override("font_size", 34)
	icon_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.offset_left = -20.0
	icon_label.offset_top = -24.0
	icon_label.offset_right = 20.0
	icon_label.offset_bottom = 24.0
	wrapper.add_child(icon_label)
	return wrapper

func _resolve_game_icon_path(game_info: Dictionary) -> String:
	var icon_cache_key: String = _get_game_key(game_info)
	if _local_game_icon_path_cache.has(icon_cache_key):
		var cached_icon_path: String = str(_local_game_icon_path_cache.get(icon_cache_key, "")).strip_edges()
		if not cached_icon_path.is_empty():
			return cached_icon_path
	var direct_icon_path: String = str(game_info.get("icon_path", "")).strip_edges()
	if not direct_icon_path.is_empty() and (FileAccess.file_exists(direct_icon_path) or _is_inline_image_data(direct_icon_path) or _is_http_url(direct_icon_path)):
		_local_game_icon_path_cache[icon_cache_key] = direct_icon_path
		return direct_icon_path

	var folder_path: String = str(game_info.get("folder", "")).strip_edges()
	if not folder_path.is_empty():
		var folder_icon_path: String = folder_path.path_join("icon.png")
		if FileAccess.file_exists(folder_icon_path):
			_local_game_icon_path_cache[icon_cache_key] = folder_icon_path
			return folder_icon_path

	for thumbnail_key in ["thumbnail", "thumbnail_path", "thumbnail_url", "preview_url", "image_url", "cover_url"]:
		var thumbnail_path: String = str(game_info.get(thumbnail_key, "")).strip_edges()
		if not thumbnail_path.is_empty() and (FileAccess.file_exists(thumbnail_path) or _is_inline_image_data(thumbnail_path) or _is_http_url(thumbnail_path)):
			_local_game_icon_path_cache[icon_cache_key] = thumbnail_path
			return thumbnail_path

	for local_entry_variant in _load_local_map_entries(128):
		if not (local_entry_variant is Dictionary):
			continue
		var local_entry: Dictionary = local_entry_variant
		if not _game_entries_match(local_entry, game_info):
			continue
		var local_icon_path: String = str(local_entry.get("icon_path", "")).strip_edges()
		if not local_icon_path.is_empty() and (FileAccess.file_exists(local_icon_path) or _is_inline_image_data(local_icon_path) or _is_http_url(local_icon_path)):
			_local_game_icon_path_cache[icon_cache_key] = local_icon_path
			return local_icon_path
		for thumbnail_key in ["thumbnail", "thumbnail_path", "thumbnail_url", "preview_url", "image_url", "cover_url"]:
			var local_thumbnail_path: String = str(local_entry.get(thumbnail_key, "")).strip_edges()
			if not local_thumbnail_path.is_empty() and (FileAccess.file_exists(local_thumbnail_path) or _is_inline_image_data(local_thumbnail_path) or _is_http_url(local_thumbnail_path)):
				_local_game_icon_path_cache[icon_cache_key] = local_thumbnail_path
				return local_thumbnail_path
		var local_folder: String = str(local_entry.get("folder", "")).strip_edges()
		if not local_folder.is_empty():
			var local_folder_icon_path: String = local_folder.path_join("icon.png")
			if FileAccess.file_exists(local_folder_icon_path):
				_local_game_icon_path_cache[icon_cache_key] = local_folder_icon_path
				return local_folder_icon_path
	for cached_entry_variant in _load_cached_cloud_map_entries(128):
		if not (cached_entry_variant is Dictionary):
			continue
		var cached_entry: Dictionary = cached_entry_variant
		if not _game_entries_match(cached_entry, game_info):
			continue
		var cached_icon_path: String = str(cached_entry.get("icon_path", "")).strip_edges()
		if not cached_icon_path.is_empty() and (FileAccess.file_exists(cached_icon_path) or _is_inline_image_data(cached_icon_path) or _is_http_url(cached_icon_path)):
			_local_game_icon_path_cache[icon_cache_key] = cached_icon_path
			return cached_icon_path
		for thumbnail_key in ["thumbnail", "thumbnail_path", "thumbnail_url", "preview_url", "image_url", "cover_url"]:
			var cached_thumbnail_path: String = str(cached_entry.get(thumbnail_key, "")).strip_edges()
			if not cached_thumbnail_path.is_empty() and (FileAccess.file_exists(cached_thumbnail_path) or _is_inline_image_data(cached_thumbnail_path) or _is_http_url(cached_thumbnail_path)):
				_local_game_icon_path_cache[icon_cache_key] = cached_thumbnail_path
				return cached_thumbnail_path
		var cached_folder: String = str(cached_entry.get("folder", "")).strip_edges()
		if not cached_folder.is_empty():
			var cached_folder_icon_path: String = cached_folder.path_join("icon.png")
			if FileAccess.file_exists(cached_folder_icon_path):
				_local_game_icon_path_cache[icon_cache_key] = cached_folder_icon_path
				return cached_folder_icon_path
	return ""

func _ensure_messages_initialized() -> void:
	var view := main_tabs.get_node("MessagesView")
	var messages := view.get_node_or_null("FriendsMessages")
	if messages == null:
		for child in view.get_children():
			view.remove_child(child)
			child.queue_free()
		messages = preload("res://scripts/lobby/friends_messages.gd").new()
		messages.name = "FriendsMessages"
		messages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.add_child(messages)
	messages.call("refresh_friends")

static func _compact_count(value: int) -> String:
	if value >= 1000000: return "%.1fM" % (float(value) / 1000000)
	if value >= 1000: return "%.1fK" % (float(value) / 1000)
	return str(value)

func _avatar_creator_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("334555"))
	return label

func _style_avatar_creator_controls(node: Node) -> void:
	if node is Label: node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if node is Button and get_viewport_rect().size.x < 1000:
		node.clip_text = not (node.get_parent() is HFlowContainer)
		node.custom_minimum_size.y = maxf(node.custom_minimum_size.y, 38)
	if node is SpinBox: _style_avatar_creator_controls(node.get_line_edit())
	if node is LineEdit:
		var input_style := StyleBoxFlat.new()
		input_style.bg_color = Color("f8fafc")
		input_style.border_color = Color("c7d2dc")
		input_style.set_border_width_all(1)
		input_style.set_corner_radius_all(4)
		input_style.content_margin_left = 10
		input_style.content_margin_right = 10
		input_style.content_margin_top = 8
		input_style.content_margin_bottom = 8
		node.add_theme_stylebox_override("normal", input_style)
		node.add_theme_color_override("font_color", Color("243544"))
		node.add_theme_color_override("font_placeholder_color", Color("6b7e8e"))
	if node is Button and not node.text in ["Опубликовать предмет"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.WHITE
		style.border_color = Color("ccd6de")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		node.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color("eef7fc")
		hover.border_color = Color("009cdb")
		node.add_theme_stylebox_override("hover", hover)
		node.add_theme_stylebox_override("pressed", hover)
		node.add_theme_color_override("font_color", Color("263a49"))
		node.add_theme_color_override("font_hover_color", Color("0079b8"))
		node.add_theme_color_override("font_pressed_color", Color("0079b8"))
	for child in node.get_children(): _style_avatar_creator_controls(child)
