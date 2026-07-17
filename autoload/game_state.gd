extends Node # This makes the script act like a global singleton node that stays alive while scenes change.

func _ready() -> void:
	_ensure_input_actions()

func _ensure_input_actions() -> void:
	_ensure_input_action("move_left", KEY_A)
	_ensure_input_action("move_right", KEY_D)
	_ensure_input_action("move_forward", KEY_W)
	_ensure_input_action("move_back", KEY_S)
	_ensure_input_action("jump", KEY_SPACE)
	_ensure_input_action("sprint", KEY_SHIFT)
	_ensure_input_action("interact", KEY_E)

func _ensure_input_action(action_name: StringName, key_code: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = key_code
	key_event.physical_keycode = key_code
	InputMap.action_add_event(action_name, key_event)

enum LaunchMode { NONE, HOST, JOIN, TARGET_JOIN, SMART_PLAY } # This enumeration stores the allowed launch states as small integers so menu code and game code share the same vocabulary.

const DEFAULT_PORT: int = 7777 # This integer stores the fallback network port so the lobby and game scene use the same default value.
const DEFAULT_AVATAR_COLOR: Color = Color(0.901961, 0.768627, 0.611765, 1.0) # Restored for compatibility.
const DEFAULT_FACE_TEXTURE_PATH: String = "res://assets/avatar/default_face.png"
const DEFAULT_CHEST_BADGE_TEXTURE_PATH: String = "res://assets/avatar/bobux_chest_badge.png"

var launch_mode: int = LaunchMode.NONE
var address: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var selected_map: String = ""
var selected_map_folder: String = "" # Path to user://maps/[map_name]/ for user-created maps
var last_network_error: String = ""
var target_server_info: Dictionary = {}
var network_gameplay_frozen: bool = false
var dedicated_server_mode: bool = false


var head_color: Color = Color(0.96, 0.8, 0.2) # Classic Yellow Head
var torso_color: Color = Color(0.05, 0.4, 0.7) # Classic Blue Torso
var left_arm_color: Color = Color(0.96, 0.8, 0.2) # Yellow Arm
var right_arm_color: Color = Color(0.96, 0.8, 0.2) # Yellow Arm
var left_leg_color: Color = Color(0.65, 0.8, 0.2) # Yellow-Green Leg
var right_leg_color: Color = Color(0.65, 0.8, 0.2) # Yellow-Green Leg
var avatar_face_texture_path: String = DEFAULT_FACE_TEXTURE_PATH
var avatar_chest_badge_texture_path: String = DEFAULT_CHEST_BADGE_TEXTURE_PATH
var avatar_shirt_texture_path: String = ""
var avatar_pants_texture_path: String = ""
var avatar_equipped_items: Array = []

func configure_host(next_port: int, colors: Dictionary) -> void: # This function records the values needed to start the main scene in host mode.
	launch_mode = LaunchMode.HOST
	address = "127.0.0.1"
	port = next_port
	target_server_info = {}
	dedicated_server_mode = false
	_apply_colors(colors)

func configure_join(next_address: String, next_port: int, colors: Dictionary) -> void: # This function records the values needed to start the main scene in join mode.
	launch_mode = LaunchMode.JOIN
	address = next_address
	port = next_port
	target_server_info = {}
	dedicated_server_mode = false
	_apply_colors(colors)

func configure_target_join(server_info: Dictionary, colors: Dictionary) -> void:
	launch_mode = LaunchMode.TARGET_JOIN
	target_server_info = server_info.duplicate(true)
	address = str(server_info.get("server_url", server_info.get("ip", "127.0.0.1"))).strip_edges()
	port = int(server_info.get("port", DEFAULT_PORT))
	dedicated_server_mode = false
	_apply_colors(colors)

func configure_smart_play(colors: Dictionary, map_info: Dictionary = {}) -> void:
	launch_mode = LaunchMode.SMART_PLAY
	address = "127.0.0.1"
	port = DEFAULT_PORT
	# Propagate cloud map identity so the network layer uses the correct UUID
	# instead of falling back to local folder names.
	target_server_info = {}
	var info_map_id: String = str(map_info.get("map_id", "")).strip_edges()
	if not info_map_id.is_empty():
		target_server_info["map_id"] = info_map_id
	var info_map_name: String = str(map_info.get("map_name", map_info.get("name", ""))).strip_edges()
	if not info_map_name.is_empty():
		target_server_info["map_name"] = info_map_name
	var info_cloud_version_id: String = str(map_info.get("cloud_version_id", "")).strip_edges()
	if not info_cloud_version_id.is_empty():
		target_server_info["cloud_version_id"] = info_cloud_version_id
	dedicated_server_mode = false
	_apply_colors(colors)

func configure_dedicated_server(next_port: int = 7860, map_name: String = "") -> void:
	launch_mode = LaunchMode.HOST
	address = "127.0.0.1"
	port = next_port
	var clean_map_name: String = map_name.strip_edges()
	selected_map = clean_map_name if not clean_map_name.is_empty() else "classic"
	selected_map_folder = ""
	target_server_info = {}
	dedicated_server_mode = true

func clear_launch_mode() -> void: # This function resets the launch state after leaving a session or returning to the lobby.
	launch_mode = LaunchMode.NONE
	target_server_info = {}
	network_gameplay_frozen = false
	dedicated_server_mode = false

func set_network_error(message: String) -> void:
	last_network_error = message.strip_edges()

func pop_network_error() -> String:
	var message: String = last_network_error
	last_network_error = ""
	return message

# FIX Issue-2: Full session wipe for account switching. Resets ALL mutable
# state so no data from the previous account leaks to the next login.
func clear_session() -> void:
	clear_launch_mode()
	selected_map = ""
	selected_map_folder = ""
	last_network_error = ""
	target_server_info = {}
	network_gameplay_frozen = false
	dedicated_server_mode = false
	head_color = Color(0.96, 0.8, 0.2)
	torso_color = Color(0.05, 0.4, 0.7)
	left_arm_color = Color(0.96, 0.8, 0.2)
	right_arm_color = Color(0.96, 0.8, 0.2)
	left_leg_color = Color(0.65, 0.8, 0.2)
	right_leg_color = Color(0.65, 0.8, 0.2)
	avatar_face_texture_path = DEFAULT_FACE_TEXTURE_PATH
	avatar_chest_badge_texture_path = DEFAULT_CHEST_BADGE_TEXTURE_PATH
	avatar_shirt_texture_path = ""
	avatar_pants_texture_path = ""
	avatar_equipped_items = []

func is_dedicated_server_runtime() -> bool:
	return dedicated_server_mode

func get_selected_map_metadata() -> Dictionary:
	if selected_map_folder.strip_edges().is_empty():
		return {}
	var meta_path: String = selected_map_folder.path_join("meta.json")
	if not FileAccess.file_exists(meta_path):
		return {}
	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func get_selected_map_display_name() -> String:
	var metadata: Dictionary = get_selected_map_metadata()
	var meta_name: String = str(metadata.get("name", "")).strip_edges()
	if not meta_name.is_empty():
		return meta_name
	var folder_name: String = selected_map_folder.get_file().strip_edges()
	if not folder_name.is_empty() and not _looks_like_generated_map_identifier(folder_name):
		return folder_name
	var clean_selected_map: String = selected_map.strip_edges()
	if clean_selected_map.to_lower() == "classic":
		return "Classic"
	if not clean_selected_map.is_empty() and not _looks_like_generated_map_identifier(clean_selected_map):
		return clean_selected_map
	return "Untitled Experience"

func get_selected_map_identifier() -> String:
	var metadata: Dictionary = get_selected_map_metadata()
	for key in ["cloud_map_id", "map_id", "id"]:
		var meta_id: String = str(metadata.get(key, "")).strip_edges()
		if not meta_id.is_empty():
			return meta_id
	var folder_name: String = selected_map_folder.get_file().strip_edges()
	if not folder_name.is_empty():
		return folder_name.to_lower()
	var clean_selected_map: String = selected_map.strip_edges()
	if not clean_selected_map.is_empty():
		return clean_selected_map.to_lower()
	if dedicated_server_mode:
		return "classic"
	return "untitled"

func _looks_like_generated_map_identifier(value: String) -> bool:
	var clean_value: String = value.strip_edges().to_lower()
	if clean_value.is_empty() or clean_value == "classic":
		return false
	var pattern: String = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}([:_].+)?$"
	var matcher := RegEx.new()
	if matcher.compile(pattern) != OK:
		return false
	return matcher.search(clean_value) != null

func _apply_colors(c: Dictionary) -> void:
	if c.has("head"): head_color = _avatar_color_from_variant(c["head"], head_color)
	if c.has("torso"): torso_color = _avatar_color_from_variant(c["torso"], torso_color)
	if c.has("left_arm"): left_arm_color = _avatar_color_from_variant(c["left_arm"], left_arm_color)
	if c.has("right_arm"): right_arm_color = _avatar_color_from_variant(c["right_arm"], right_arm_color)
	if c.has("left_leg"): left_leg_color = _avatar_color_from_variant(c["left_leg"], left_leg_color)
	if c.has("right_leg"): right_leg_color = _avatar_color_from_variant(c["right_leg"], right_leg_color)

func _avatar_color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is Dictionary:
		var dict := value as Dictionary
		return Color(
			float(dict.get("r", fallback.r)),
			float(dict.get("g", fallback.g)),
			float(dict.get("b", fallback.b)),
			float(dict.get("a", fallback.a))
		)
	if value is Array and (value as Array).size() >= 3:
		var array_value := value as Array
		return Color(float(array_value[0]), float(array_value[1]), float(array_value[2]), float(array_value[3]) if array_value.size() > 3 else fallback.a)
	if value is String:
		var text := (value as String).strip_edges()
		if text.begins_with("#"):
			text = text.substr(1)
		if text.length() == 6 or text.length() == 8:
			return Color.html(text)
	return fallback

func apply_avatar_data(data: Dictionary) -> void:
	_apply_colors(data)
	avatar_face_texture_path = _resolve_avatar_texture_path(data, ["face_texture_path", "face_path", "face"], DEFAULT_FACE_TEXTURE_PATH)
	avatar_chest_badge_texture_path = _resolve_avatar_texture_path(data, ["chest_badge_texture_path", "badge_texture_path", "chest_badge"], DEFAULT_CHEST_BADGE_TEXTURE_PATH)
	avatar_shirt_texture_path = _resolve_avatar_texture_path(data, ["shirt_texture_path", "shirt_template_path", "shirt"], "")
	avatar_pants_texture_path = _resolve_avatar_texture_path(data, ["pants_texture_path", "pants_template_path", "pants"], "")
	avatar_equipped_items = _resolve_avatar_equipped_items(data)

func _resolve_avatar_texture_path(data: Dictionary, keys: Array, fallback: String) -> String:
	for key_variant in keys:
		var key := str(key_variant)
		if data.has(key):
			return str(data.get(key, "")).strip_edges()
	return fallback

func _resolve_avatar_equipped_items(data: Dictionary) -> Array:
	for key in ["equipped_avatar_item_payloads", "equipped_avatar_items", "avatar_items"]:
		var raw_items: Variant = data.get(key, [])
		if raw_items is Array:
			var result: Array = []
			for raw_item in (raw_items as Array):
				if raw_item is Dictionary:
					result.append((raw_item as Dictionary).duplicate(true))
			if not result.is_empty():
				return result
	return []
