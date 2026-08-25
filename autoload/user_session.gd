extends Node

const SESSION_BACKEND_ID: String = "bobux-vps-pocketbase-2026-05-28"
const SESSION_ROOT_PATH: String = "user://session"
const SESSION_PROFILE_PATH: String = "user://session/current_profile.json"
const RUNTIME_SESSION_ROOT_PATH: String = "user://session/runtime"
const USER_CACHE_ROOT_PATH: String = "user://cache/users"
const MAPS_ROOT_PATH: String = "user://maps"
const LEGACY_PROFILE_PATH: String = "user://profile.json"
const LEGACY_PROFILES_ROOT: String = "user://profiles"
const PROFILE_FILE_NAME: String = "profile.json"
const MAPS_DIR_NAME: String = "maps"
const DEFAULT_HEAD_COLOR: Color = Color(0.96, 0.8, 0.2)
const DEFAULT_TORSO_COLOR: Color = Color(0.05, 0.4, 0.7)
const DEFAULT_ARM_COLOR: Color = Color(0.96, 0.8, 0.2)
const DEFAULT_LEG_COLOR: Color = Color(0.65, 0.8, 0.2)
const ILLEGAL_PATH_CHARS: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
const MAX_AVATAR_EQUIPPED_ITEMS: int = 32
const MAX_AVATAR_OWNED_ITEM_PAYLOADS: int = 96
const MAX_AVATAR_SAVED_TEXTURES: int = 128
const MAX_AVATAR_STRING_VALUE_LENGTH: int = 4096
const MAX_AVATAR_PAYLOAD_KEYS: int = 48
const MAX_AVATAR_PAYLOAD_ARRAY_ITEMS: int = 48
const MAX_INVENTORY_ITEMS: int = 512

var user_id: String = ""
var username: String = ""
var join_date: String = ""
var friends_list: Array = []
var inventory_items: Array = []
var avatar_data: Dictionary = {}
var recent_games: Array = []
var deleted_map_ids: Array[String] = []
var deleted_map_names: Array[String] = []
var is_logged_in: bool = false
var explicitly_logged_out: bool = false

func begin_cloud_session(cloud_user_id: String, cloud_username: String) -> void:
	var clean_user_id: String = cloud_user_id.strip_edges()
	var clean_username: String = cloud_username.strip_edges()
	if clean_user_id.is_empty() or clean_username.is_empty():
		return
	if is_logged_in and user_id == clean_user_id and username == clean_username:
		_remember_current_session()
		apply_avatar_to_game_state()
		return
	var cached_data: Dictionary = _read_profile_dictionary(_get_user_cache_path(clean_user_id))
	if not _is_current_backend_record(cached_data):
		cached_data = {}
	if cached_data.is_empty():
		cached_data = {
			"user_id": clean_user_id,
			"username": clean_username,
			"join_date": Time.get_date_string_from_system(),
			"friends_list": [],
			"inventory_items": [],
			"recent_games": [],
			"deleted_map_ids": [],
			"deleted_map_names": [],
			"avatar_data": _serialize_colors(_get_default_avatar_data()),
			"backend_id": SESSION_BACKEND_ID
		}
	cached_data["user_id"] = clean_user_id
	cached_data["username"] = clean_username
	_load_from_dict(cached_data)
	is_logged_in = true
	explicitly_logged_out = false
	save_profile()
	apply_avatar_to_game_state()

func save_profile() -> void:
	if user_id.strip_edges().is_empty() or username.strip_edges().is_empty():
		return
	ensure_current_storage()
	inventory_items = _sanitize_inventory_items(inventory_items)
	avatar_data = _sanitize_avatar_data_for_runtime(avatar_data if avatar_data is Dictionary else {})
	var data: Dictionary = {
		"user_id": user_id,
		"username": username,
		"join_date": join_date,
		"friends_list": friends_list,
		"inventory_items": inventory_items,
		"recent_games": recent_games,
		"deleted_map_ids": deleted_map_ids,
		"deleted_map_names": deleted_map_names,
		"avatar_data": _serialize_colors(avatar_data),
		"backend_id": SESSION_BACKEND_ID
	}
	var file := FileAccess.open(_get_user_cache_path(user_id), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	_remember_current_session()

func load_profile() -> bool:
	for session_path in _get_session_profile_candidates():
		var session_data: Dictionary = _read_profile_dictionary(session_path)
		if session_data.is_empty():
			continue
		if not _is_current_backend_record(session_data):
			_remove_file_if_exists(session_path)
			continue
		var cached_user_id: String = str(session_data.get("user_id", "")).strip_edges()
		var cached_username: String = str(session_data.get("username", "")).strip_edges()
		if cached_user_id.is_empty() or cached_username.is_empty():
			continue
		var cached_profile: Dictionary = _read_profile_dictionary(_get_user_cache_path(cached_user_id))
		if not _is_current_backend_record(cached_profile):
			cached_profile = {}
		if cached_profile.is_empty():
			cached_profile = session_data
		cached_profile["user_id"] = cached_user_id
		cached_profile["username"] = cached_username
		_load_from_dict(cached_profile)
		is_logged_in = true
		explicitly_logged_out = false
		apply_avatar_to_game_state()
		_remember_current_session()
		save_profile()
		return true
	return false

func apply_avatar_to_game_state() -> void:
	var default_avatar: Dictionary = _get_default_avatar_data()
	var resolved_avatar: Dictionary = avatar_data if not avatar_data.is_empty() else default_avatar
	resolved_avatar = _sanitize_avatar_data_for_runtime(resolved_avatar)
	avatar_data = resolved_avatar.duplicate(true)
	GameState.apply_avatar_data(resolved_avatar)
	GameState.head_color = _resolve_avatar_color_value(resolved_avatar.get("head", default_avatar["head"]), default_avatar["head"])
	GameState.torso_color = _resolve_avatar_color_value(resolved_avatar.get("torso", default_avatar["torso"]), default_avatar["torso"])
	GameState.left_arm_color = _resolve_avatar_color_value(resolved_avatar.get("left_arm", default_avatar["left_arm"]), default_avatar["left_arm"])
	GameState.right_arm_color = _resolve_avatar_color_value(resolved_avatar.get("right_arm", default_avatar["right_arm"]), default_avatar["right_arm"])
	GameState.left_leg_color = _resolve_avatar_color_value(resolved_avatar.get("left_leg", default_avatar["left_leg"]), default_avatar["left_leg"])
	GameState.right_leg_color = _resolve_avatar_color_value(resolved_avatar.get("right_leg", default_avatar["right_leg"]), default_avatar["right_leg"])

func apply_cloud_profile_payload(next_avatar_data: Variant, next_inventory_items: Variant) -> void:
	if next_avatar_data is Dictionary:
		var incoming_avatar := _sanitize_avatar_data_for_runtime(_deserialize_colors(next_avatar_data as Dictionary))
		# Profile rows can lag one outfit write behind avatar_outfits. Keep the
		# complete local/model payloads until the authoritative outfit refresh has
		# resolved the same IDs, otherwise returning from a place makes accessories
		# disappear for one lobby session.
		for list_key in ["equipped", "equipped_avatar_item_payloads", "equipped_avatar_items", "avatar_items", "owned_avatar_item_payloads"]:
			var incoming_list: Variant = incoming_avatar.get(list_key, [])
			var current_list: Variant = avatar_data.get(list_key, []) if avatar_data is Dictionary else []
			if incoming_list is Array and (incoming_list as Array).is_empty() and current_list is Array and not (current_list as Array).is_empty():
				incoming_avatar[list_key] = (current_list as Array).duplicate(true)
		avatar_data = incoming_avatar
	if next_inventory_items is Array:
		inventory_items = _sanitize_inventory_items(next_inventory_items)

func get_last_profile_username() -> String:
	for session_path in _get_session_profile_candidates():
		var session_data: Dictionary = _read_profile_dictionary(session_path)
		if not _is_current_backend_record(session_data):
			continue
		var stored_username: String = str(session_data.get("username", "")).strip_edges()
		if not stored_username.is_empty():
			return stored_username
	return ""

func get_maps_root_path(_unused_username: String = "") -> String:
	var root_path: String = _get_current_maps_root_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	return root_path

func ensure_current_storage() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SESSION_ROOT_PATH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_get_runtime_session_root_path()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_CACHE_ROOT_PATH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_get_current_maps_root_path()))
	if not user_id.strip_edges().is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_get_user_cache_path(user_id).get_base_dir()))

func record_recent_game(game_entry: Dictionary) -> void:
	if game_entry.is_empty():
		return
	var clean_entry: Dictionary = _normalize_recent_game_entry({
		"map_id": str(game_entry.get("map_id", "")).strip_edges(),
		"name": str(game_entry.get("name", "")).strip_edges(),
		"folder": str(game_entry.get("folder", "")).strip_edges(),
		"icon_path": str(game_entry.get("icon_path", "")).strip_edges(),
		"cloud_version_id": str(game_entry.get("cloud_version_id", "")).strip_edges(),
		"last_played_at": Time.get_datetime_string_from_system(true, true)
	})
	if clean_entry.is_empty():
		return
	if str(clean_entry.get("map_id", "")).strip_edges().is_empty() and str(clean_entry.get("folder", "")).strip_edges().is_empty():
		return
	if str(clean_entry.get("name", "")).is_empty():
		clean_entry["name"] = "Untitled Game"
	var dedupe_key: String = str(clean_entry.get("map_id", "")).strip_edges()
	if dedupe_key.is_empty():
		dedupe_key = str(clean_entry.get("folder", "")).strip_edges()
	var filtered: Array = []
	for existing_variant in recent_games:
		if not (existing_variant is Dictionary):
			continue
		var existing: Dictionary = existing_variant
		var existing_key: String = str(existing.get("map_id", "")).strip_edges()
		if existing_key.is_empty():
			existing_key = str(existing.get("folder", "")).strip_edges()
		if not dedupe_key.is_empty() and existing_key == dedupe_key:
			continue
		filtered.append(existing)
	recent_games = [clean_entry]
	recent_games.append_array(filtered)
	while recent_games.size() > 8:
		recent_games.pop_back()
	save_profile()

func remove_recent_game(map_id: String = "", folder: String = "", game_name: String = "") -> void:
	var clean_map_id: String = map_id.strip_edges()
	var clean_folder: String = folder.strip_edges()
	var clean_name: String = game_name.strip_edges().to_lower()
	var filtered: Array = []
	var changed: bool = false
	for existing_variant in recent_games:
		if not (existing_variant is Dictionary):
			continue
		var existing: Dictionary = existing_variant
		var existing_map_id: String = str(existing.get("map_id", "")).strip_edges()
		var existing_folder: String = str(existing.get("folder", "")).strip_edges()
		var existing_name: String = str(existing.get("name", "")).strip_edges().to_lower()
		var matches: bool = false
		if not clean_map_id.is_empty() and existing_map_id == clean_map_id:
			matches = true
		elif not clean_folder.is_empty() and existing_folder == clean_folder:
			matches = true
		elif not clean_name.is_empty() and existing_name == clean_name:
			matches = true
		if matches:
			changed = true
			continue
		filtered.append(existing)
	if changed:
		recent_games = filtered
		save_profile()

func mark_deleted_game(map_id: String = "", game_name: String = "") -> void:
	var clean_map_id: String = map_id.strip_edges()
	var clean_name: String = game_name.strip_edges().to_lower()
	var changed: bool = false
	if not clean_map_id.is_empty() and not deleted_map_ids.has(clean_map_id):
		deleted_map_ids.append(clean_map_id)
		changed = true
	if not clean_name.is_empty() and not deleted_map_names.has(clean_name):
		deleted_map_names.append(clean_name)
		changed = true
	if changed:
		save_profile()

func unmark_deleted_game(map_id: String = "", game_name: String = "") -> void:
	var clean_map_id: String = map_id.strip_edges()
	var clean_name: String = game_name.strip_edges().to_lower()
	var changed: bool = false
	if not clean_map_id.is_empty() and deleted_map_ids.has(clean_map_id):
		deleted_map_ids.erase(clean_map_id)
		changed = true
	if not clean_name.is_empty() and deleted_map_names.has(clean_name):
		deleted_map_names.erase(clean_name)
		changed = true
	if changed:
		save_profile()

func is_deleted_game(map_id: String = "", game_name: String = "") -> bool:
	var clean_map_id: String = map_id.strip_edges()
	var clean_name: String = game_name.strip_edges().to_lower()
	return (not clean_map_id.is_empty() and deleted_map_ids.has(clean_map_id)) \
		or (not clean_name.is_empty() and deleted_map_names.has(clean_name))

func clear() -> void:
	user_id = ""
	username = ""
	join_date = ""
	friends_list.clear()
	inventory_items.clear()
	avatar_data.clear()
	recent_games.clear()
	deleted_map_ids.clear()
	deleted_map_names.clear()
	is_logged_in = false
	explicitly_logged_out = true
	_forget_current_session()
	_apply_default_avatar_to_game_state()

func _load_from_dict(data: Dictionary) -> void:
	if not _is_current_backend_record(data):
		data = {
			"user_id": str(data.get("user_id", "")).strip_edges(),
			"username": str(data.get("username", "Player")).strip_edges(),
			"join_date": Time.get_date_string_from_system(),
			"friends_list": [],
			"inventory_items": [],
			"recent_games": [],
			"deleted_map_ids": [],
			"deleted_map_names": [],
			"avatar_data": _serialize_colors(_get_default_avatar_data()),
			"backend_id": SESSION_BACKEND_ID
		}
	user_id = str(data.get("user_id", "")).strip_edges()
	username = str(data.get("username", "Player")).strip_edges()
	join_date = str(data.get("join_date", Time.get_date_string_from_system())).strip_edges()
	friends_list = data.get("friends_list", []) if data.get("friends_list", []) is Array else []
	inventory_items = _sanitize_inventory_items(data.get("inventory_items", []))
	recent_games = _normalize_recent_games_paths(data.get("recent_games", []))
	deleted_map_ids = _normalize_string_array(data.get("deleted_map_ids", []), false)
	deleted_map_names = _normalize_string_array(data.get("deleted_map_names", []), true)
	var raw_avatar: Dictionary = data.get("avatar_data", {}) if data.get("avatar_data", {}) is Dictionary else {}
	avatar_data = _sanitize_avatar_data_for_runtime(_deserialize_colors(raw_avatar))
	if avatar_data.is_empty():
		avatar_data = _get_default_avatar_data()

func _read_profile_dictionary(profile_path: String) -> Dictionary:
	if not FileAccess.file_exists(profile_path):
		return {}
	var file := FileAccess.open(profile_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _is_current_backend_record(data: Dictionary) -> bool:
	return not data.is_empty() and str(data.get("backend_id", "")).strip_edges() == SESSION_BACKEND_ID

func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _get_user_cache_path(cloud_user_id: String) -> String:
	var clean_user_id: String = cloud_user_id.strip_edges().replace("-", "")
	if clean_user_id.is_empty():
		clean_user_id = "player"
	return USER_CACHE_ROOT_PATH.path_join(clean_user_id).path_join(PROFILE_FILE_NAME)

func _get_current_maps_root_path() -> String:
	if not user_id.strip_edges().is_empty():
		return _get_user_maps_root_path_for_id(user_id)
	if not username.strip_edges().is_empty():
		return MAPS_ROOT_PATH.path_join(_sanitize_path_component(username))
	return MAPS_ROOT_PATH.path_join("guest")

func _get_user_maps_root_path_for_id(cloud_user_id: String) -> String:
	return _get_user_cache_path(cloud_user_id).get_base_dir().path_join(MAPS_DIR_NAME)

func _get_runtime_session_root_path() -> String:
	return RUNTIME_SESSION_ROOT_PATH.path_join(str(OS.get_process_id()))

func _get_runtime_session_profile_path() -> String:
	return _get_runtime_session_root_path().path_join("current_profile.json")

func _get_session_profile_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var runtime_path: String = _get_runtime_session_profile_path()
	if not runtime_path.is_empty():
		candidates.append(runtime_path)
	if not SESSION_PROFILE_PATH.is_empty() and not candidates.has(SESSION_PROFILE_PATH):
		candidates.append(SESSION_PROFILE_PATH)
	return candidates

func _remember_current_session() -> void:
	if user_id.strip_edges().is_empty() or username.strip_edges().is_empty():
		return
	ensure_current_storage()
	var session_payload: Dictionary = {
		"user_id": user_id,
		"username": username,
		"join_date": join_date,
		"backend_id": SESSION_BACKEND_ID
	}
	_write_session_profile(_get_runtime_session_profile_path(), session_payload)
	_write_session_profile(SESSION_PROFILE_PATH, session_payload)

func _forget_current_session() -> void:
	for session_path in _get_session_profile_candidates():
		if FileAccess.file_exists(session_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))

func _write_session_profile(profile_path: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path.get_base_dir()))
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload, "\t"))
		file.close()

func _maybe_migrate_legacy_profile_for_username(target_username: String) -> Dictionary:
	var named_profile: Dictionary = _read_legacy_named_profile(target_username)
	if not named_profile.is_empty():
		return named_profile
	var legacy_profile: Dictionary = _read_profile_dictionary(LEGACY_PROFILE_PATH)
	if legacy_profile.is_empty():
		return {}
	var legacy_username: String = str(legacy_profile.get("username", "")).strip_edges()
	if legacy_username != target_username.strip_edges():
		return {}
	return legacy_profile

func _read_legacy_named_profile(target_username: String) -> Dictionary:
	var legacy_profile_path: String = LEGACY_PROFILES_ROOT.path_join(_sanitize_path_component(target_username)).path_join(PROFILE_FILE_NAME)
	return _read_profile_dictionary(legacy_profile_path)

func _migrate_legacy_maps_if_needed(target_username: String = "", target_user_id: String = "") -> void:
	ensure_current_storage()
	var clean_username: String = target_username.strip_edges()
	var clean_user_id: String = target_user_id.strip_edges()
	if clean_username.is_empty() and not username.strip_edges().is_empty():
		clean_username = username.strip_edges()
	if clean_user_id.is_empty() and not user_id.strip_edges().is_empty():
		clean_user_id = user_id.strip_edges()
	if clean_username.is_empty() or clean_user_id.is_empty():
		return
	var destination_root: String = _get_user_maps_root_path_for_id(clean_user_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_root))
	var legacy_maps_path: String = LEGACY_PROFILES_ROOT.path_join(_sanitize_path_component(clean_username)).path_join(MAPS_DIR_NAME)
	_merge_missing_map_directories(legacy_maps_path, destination_root)
	_merge_owned_global_maps_if_needed(clean_username, destination_root)

func _merge_owned_global_maps_if_needed(target_username: String, destination_root: String) -> void:
	var legacy_root := DirAccess.open(MAPS_ROOT_PATH)
	if legacy_root == null:
		return
	var clean_username: String = target_username.strip_edges().to_lower()
	if clean_username.is_empty():
		return
	legacy_root.list_dir_begin()
	var entry: String = legacy_root.get_next()
	while not entry.is_empty():
		if legacy_root.current_is_dir() and entry != "." and entry != "..":
			var source_path: String = MAPS_ROOT_PATH.path_join(entry)
			var meta: Dictionary = _read_map_metadata_from_folder(source_path)
			var creator: String = str(meta.get("creator", "")).strip_edges().to_lower()
			if creator == clean_username:
				var destination_path: String = destination_root.path_join(entry)
				if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination_path)):
					_copy_directory_recursive(source_path, destination_path)
		entry = legacy_root.get_next()
	legacy_root.list_dir_end()

func _merge_missing_map_directories(source_root: String, destination_root: String) -> void:
	var source_dir := DirAccess.open(source_root)
	if source_dir == null:
		return
	source_dir.list_dir_begin()
	var entry: String = source_dir.get_next()
	while not entry.is_empty():
		if source_dir.current_is_dir() and entry != "." and entry != "..":
			var source_path: String = source_root.path_join(entry)
			var destination_path: String = destination_root.path_join(entry)
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination_path)):
				_copy_directory_recursive(source_path, destination_path)
		entry = source_dir.get_next()
	source_dir.list_dir_end()

func _copy_directory_recursive(source_path: String, destination_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_path))
	var source_dir := DirAccess.open(source_path)
	if source_dir == null:
		return
	source_dir.list_dir_begin()
	var entry: String = source_dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var source_entry_path: String = source_path.path_join(entry)
			var destination_entry_path: String = destination_path.path_join(entry)
			if source_dir.current_is_dir():
				_copy_directory_recursive(source_entry_path, destination_entry_path)
			else:
				_copy_file(source_entry_path, destination_entry_path)
		entry = source_dir.get_next()
	source_dir.list_dir_end()

func _copy_file(source_path: String, destination_path: String) -> void:
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_path.get_base_dir()))
	var destination_file := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		source_file.close()
		return
	destination_file.store_buffer(source_file.get_buffer(source_file.get_length()))
	destination_file.close()
	source_file.close()

func _normalize_recent_games_paths(raw_recent_games: Variant) -> Array:
	var normalized: Array = []
	if not (raw_recent_games is Array):
		return normalized
	var seen: Dictionary = {}
	for entry_variant in raw_recent_games:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = _normalize_recent_game_entry((entry_variant as Dictionary).duplicate(true))
		if entry.is_empty():
			continue
		var dedupe_key: String = str(entry.get("map_id", "")).strip_edges()
		if dedupe_key.is_empty():
			dedupe_key = str(entry.get("folder", "")).strip_edges()
		if dedupe_key.is_empty():
			dedupe_key = str(entry.get("name", "")).strip_edges().to_lower()
		if dedupe_key.is_empty() or seen.has(dedupe_key):
			continue
		seen[dedupe_key] = true
		normalized.append(entry)
	return normalized

func _normalize_string_array(raw_values: Variant, lowercase: bool = false) -> Array[String]:
	var normalized: Array[String] = []
	if not (raw_values is Array):
		return normalized
	for value_variant in raw_values:
		var value := str(value_variant).strip_edges()
		if lowercase:
			value = value.to_lower()
		if value.is_empty() or normalized.has(value):
			continue
		normalized.append(value)
	return normalized

func _normalize_recent_game_entry(entry: Dictionary) -> Dictionary:
	var normalized_entry: Dictionary = entry.duplicate(true)
	var explicit_map_id: String = str(normalized_entry.get("map_id", "")).strip_edges()
	var folder_path: String = str(normalized_entry.get("folder", "")).strip_edges()
	if folder_path.begins_with("user://maps") or folder_path.find("/user/maps/") >= 0:
		normalized_entry["folder"] = ""
		folder_path = ""
	if folder_path.find("/profiles/") >= 0 and folder_path.find("/maps/") >= 0:
		normalized_entry["folder"] = ""
		folder_path = ""
	elif folder_path.begins_with(MAPS_ROOT_PATH.path_join("")) and folder_path.get_base_dir() == MAPS_ROOT_PATH:
		normalized_entry["folder"] = ""
		folder_path = ""
	if explicit_map_id.is_empty() and folder_path.is_empty():
		return {}
	var metadata: Dictionary = _read_map_metadata_from_folder(folder_path)
	var meta_name: String = str(metadata.get("name", "")).strip_edges()
	var meta_map_id: String = str(metadata.get("cloud_map_id", metadata.get("map_id", ""))).strip_edges()
	var meta_cloud_version_id: String = str(metadata.get("cloud_version_id", "")).strip_edges()
	var current_name: String = str(normalized_entry.get("name", "")).strip_edges()
	var current_map_id: String = str(normalized_entry.get("map_id", "")).strip_edges()
	if not meta_name.is_empty() and (current_name.is_empty() or _looks_like_generated_game_name(current_name)):
		normalized_entry["name"] = meta_name
		current_name = meta_name
	if not meta_map_id.is_empty() and (current_map_id.is_empty() or _looks_like_generated_game_name(current_map_id)):
		normalized_entry["map_id"] = meta_map_id
		current_map_id = meta_map_id
	if not meta_cloud_version_id.is_empty() and str(normalized_entry.get("cloud_version_id", "")).strip_edges().is_empty():
		normalized_entry["cloud_version_id"] = meta_cloud_version_id
	if folder_path.find("/cache/maps/") >= 0 and _looks_like_generated_game_name(current_name):
		return {}
	if str(normalized_entry.get("name", "")).strip_edges().is_empty():
		var folder_name: String = folder_path.get_file().strip_edges()
		if not folder_name.is_empty() and not _looks_like_generated_game_name(folder_name):
			normalized_entry["name"] = folder_name
	return normalized_entry

func _read_map_metadata_from_folder(folder_path: String) -> Dictionary:
	if folder_path.is_empty():
		return {}
	var meta_path: String = folder_path.path_join("meta.json")
	if not FileAccess.file_exists(meta_path):
		return {}
	return _read_profile_dictionary(meta_path)

func _looks_like_generated_game_name(value: String) -> bool:
	var clean_value: String = value.strip_edges().to_lower()
	if clean_value.is_empty() or clean_value == "classic":
		return false
	var matcher := RegEx.new()
	if matcher.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}([:_].+)?$") != OK:
		return false
	return matcher.search(clean_value) != null

func _get_default_avatar_data() -> Dictionary:
	return {
		"head": DEFAULT_HEAD_COLOR,
		"torso": DEFAULT_TORSO_COLOR,
		"left_arm": DEFAULT_ARM_COLOR,
		"right_arm": DEFAULT_ARM_COLOR,
		"left_leg": DEFAULT_LEG_COLOR,
		"right_leg": DEFAULT_LEG_COLOR,
		"face_texture_path": GameState.DEFAULT_FACE_TEXTURE_PATH,
		"chest_badge_texture_path": GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH,
		"shirt_texture_path": "",
		"pants_texture_path": "",
		"saved_shirt_texture_paths": [],
		"saved_pants_texture_paths": [],
		"equipped": []
	}

func _apply_default_avatar_to_game_state() -> void:
	var defaults: Dictionary = _get_default_avatar_data()
	GameState.apply_avatar_data(defaults)
	GameState.head_color = defaults["head"]
	GameState.torso_color = defaults["torso"]
	GameState.left_arm_color = defaults["left_arm"]
	GameState.right_arm_color = defaults["right_arm"]
	GameState.left_leg_color = defaults["left_leg"]
	GameState.right_leg_color = defaults["right_leg"]

func _sanitize_path_component(value: String) -> String:
	var clean_value: String = value.strip_edges()
	for illegal_char in ILLEGAL_PATH_CHARS:
		clean_value = clean_value.replace(illegal_char, "_")
	return clean_value if not clean_value.is_empty() else "player"

func _serialize_colors(colors: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in colors.keys():
		var value: Variant = colors[key]
		if value is Color:
			out[key] = {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		else:
			out[key] = value
	return out

func _deserialize_colors(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw.keys():
		var value: Variant = raw[key]
		if value is Dictionary and value.has("r") and value.has("g"):
			out[key] = Color(value.get("r", 1.0), value.get("g", 1.0), value.get("b", 1.0), value.get("a", 1.0))
		else:
			out[key] = value
	return out

func _sanitize_avatar_data_for_runtime(raw: Dictionary) -> Dictionary:
	var defaults: Dictionary = _get_default_avatar_data()
	var clean: Dictionary = defaults.duplicate(true)
	for color_key in ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
		clean[color_key] = _resolve_avatar_color_value(raw.get(color_key, defaults[color_key]), defaults[color_key])
	for texture_key in ["face_texture_path", "chest_badge_texture_path", "shirt_texture_path", "pants_texture_path"]:
		clean[texture_key] = _coerce_avatar_string(raw.get(texture_key, defaults.get(texture_key, "")), str(defaults.get(texture_key, "")))
	clean["saved_shirt_texture_paths"] = _sanitize_string_list(raw.get("saved_shirt_texture_paths", []), MAX_AVATAR_SAVED_TEXTURES)
	clean["saved_pants_texture_paths"] = _sanitize_string_list(raw.get("saved_pants_texture_paths", []), MAX_AVATAR_SAVED_TEXTURES)
	clean["equipped"] = _sanitize_avatar_item_payloads(raw.get("equipped", []), MAX_AVATAR_EQUIPPED_ITEMS)
	for list_key in ["equipped_avatar_item_payloads", "equipped_avatar_items", "avatar_items"]:
		if raw.has(list_key):
			clean[list_key] = _sanitize_avatar_item_payloads(raw.get(list_key, []), MAX_AVATAR_EQUIPPED_ITEMS)
	if raw.has("owned_avatar_item_payloads"):
		clean["owned_avatar_item_payloads"] = _sanitize_avatar_item_payloads(raw.get("owned_avatar_item_payloads", []), MAX_AVATAR_OWNED_ITEM_PAYLOADS)
	return clean

func _sanitize_string_list(value: Variant, limit: int) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	var source: Array = value
	for index in range(mini(source.size(), maxi(limit, 0))):
		var clean_value: String = _coerce_avatar_string(source[index], "")
		if not clean_value.is_empty() and not result.has(clean_value):
			result.append(clean_value)
	return result

func _sanitize_inventory_items(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	var source: Array = value
	for index in range(mini(source.size(), MAX_INVENTORY_ITEMS)):
		var clean_id: String = _coerce_avatar_string(source[index], "")
		if not clean_id.is_empty() and not result.has(clean_id):
			result.append(clean_id)
	return result

func _sanitize_avatar_item_payloads(value: Variant, limit: int) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	var source: Array = value
	for index in range(mini(source.size(), maxi(limit, 0))):
		var raw_item: Variant = source[index]
		if raw_item is Dictionary:
			var clean_item: Dictionary = {}
			var key_count: int = 0
			for key_variant in (raw_item as Dictionary).keys():
				if key_count >= MAX_AVATAR_PAYLOAD_KEYS:
					break
				var key: String = str(key_variant).strip_edges()
				if key.is_empty() or key.length() > 80:
					continue
				var clean_value: Variant = _sanitize_avatar_payload_value((raw_item as Dictionary).get(key_variant), 0)
				if clean_value != null:
					clean_item[key] = clean_value
					key_count += 1
			if not clean_item.is_empty():
				result.append(clean_item)
		elif raw_item is String:
			var item_id: String = _coerce_avatar_string(raw_item, "")
			if not item_id.is_empty():
				result.append({"id": item_id})
	return result

func _sanitize_avatar_payload_value(value: Variant, depth: int) -> Variant:
	if depth > 2:
		return null
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _coerce_avatar_string(value, "")
		TYPE_COLOR:
			return value
		TYPE_DICTIONARY:
			var clean_dict: Dictionary = {}
			var source_dict: Dictionary = value
			var key_count: int = 0
			for key_variant in source_dict.keys():
				if key_count >= MAX_AVATAR_PAYLOAD_KEYS:
					break
				var key: String = str(key_variant).strip_edges()
				if key.is_empty() or key.length() > 80:
					continue
				var clean_nested: Variant = _sanitize_avatar_payload_value(source_dict.get(key_variant), depth + 1)
				if clean_nested != null:
					clean_dict[key] = clean_nested
					key_count += 1
			return clean_dict
		TYPE_ARRAY:
			var clean_array: Array = []
			var source_array: Array = value
			for index in range(mini(source_array.size(), MAX_AVATAR_PAYLOAD_ARRAY_ITEMS)):
				var clean_entry: Variant = _sanitize_avatar_payload_value(source_array[index], depth + 1)
				if clean_entry != null:
					clean_array.append(clean_entry)
			return clean_array
	return null

func _coerce_avatar_string(value: Variant, fallback: String) -> String:
	var text: String = str(value).strip_edges()
	if text.is_empty():
		return fallback
	if text.length() > MAX_AVATAR_STRING_VALUE_LENGTH:
		return fallback
	return text

func _resolve_avatar_color_value(value: Variant, fallback: Color) -> Color:
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
	return fallback
