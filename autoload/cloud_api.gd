extends Node

signal map_uploaded(result: Dictionary)
signal map_downloaded(map_id: String, result: Dictionary)
signal active_server_registered(result: Dictionary)
signal active_servers_fetched(servers: Array)
signal friend_request_sent(result: Dictionary)
signal friend_search_completed(profiles: Array)
signal friends_list_received(friends: Array)
signal friend_requests_received(requests: Array)
signal presence_updated(result: Dictionary)
signal published_maps_fetched(maps: Array)
signal request_failed(endpoint: String, error_message: String)
signal profile_authenticated(profile: Dictionary)
signal auth_session_ready(session: Dictionary)
signal auth_session_failed(error_message: String)

# PRACTICE SCREENSHOT: Cloud API configuration - base URLs, PocketBase-compatible endpoints, auth paths, timeouts and retry limits.
const ENV_BASE_URL: String = "ROBLOXCLONE_CLOUD_BASE_URL"
const ENV_API_KEY: String = "ROBLOXCLONE_CLOUD_API_KEY"
const ENV_BEARER_TOKEN: String = "ROBLOXCLONE_CLOUD_BEARER"
const ENV_BOBUX_SERVICE_KEY: String = "BOBUX_SERVICE_KEY"
const CLOUD_BACKEND_ID: String = "bobux-vps-pocketbase-2026-05-28"
const DEFAULT_PROJECT_URL: String = "http://109.71.245.162/api"
const DEFAULT_REST_BASE_URL: String = "http://109.71.245.162/api/rest/v1"
const DEFAULT_PUBLISHABLE_KEY: String = "bobux-public-vps"
const DEFAULT_ANON_KEY: String = "bobux-public-vps"

const DEFAULT_MAPS_ENDPOINT: String = "/maps"
const DEFAULT_SERVERS_ENDPOINT: String = "/active_servers"
const DEFAULT_PROFILES_ENDPOINT: String = "/profiles"
const DEFAULT_CATALOG_ENDPOINT: String = "/catalog_items"
const DEFAULT_MODEL_ASSETS_ENDPOINT: String = "/model_assets"
const DEFAULT_AVATAR_ITEMS_ENDPOINT: String = "/avatar_items"
const DEFAULT_AVATAR_OUTFITS_ENDPOINT: String = "/avatar_outfits"
const DEFAULT_FRIENDSHIPS_ENDPOINT: String = "/friendships"
const DEFAULT_FRIEND_REQUESTS_ENDPOINT: String = "/friend_requests"
const DEFAULT_FOLLOWS_ENDPOINT: String = "/follows"
const MAP_ASSET_BUCKET: String = "map-assets"
const MODEL_ASSET_BUCKET: String = "model-assets"
const AVATAR_ITEM_BUCKET: String = "avatar-items"
const CACHE_ROOT_PATH: String = "user://cache/maps"
const ACTIVE_SERVER_TTL_SECONDS: float = 180.0
const LEGACY_AUTH_SESSION_PATH: String = "user://cache/supabase_auth_session.json"
const LEGACY_CURRENT_AUTH_SESSION_PATH: String = "user://session/supabase_auth_session.json"
const CURRENT_AUTH_SESSION_PATH: String = "user://session/bobux_auth_session.json"
const RUNTIME_AUTH_SESSION_ROOT_PATH: String = "user://session/runtime"
const USER_AUTH_SESSION_ROOT_PATH: String = "user://session/users"
const AUTH_REFRESH_MARGIN_SECONDS: int = 60
const AUTH_BOOTSTRAP_WAIT_TIMEOUT_MSEC: int = 8000
const HTTP_REQUEST_TIMEOUT_SECONDS: float = 12.0
const HTTP_UPLOAD_TIMEOUT_SECONDS: float = 90.0
const HTTP_MEDIA_UPLOAD_TIMEOUT_SECONDS: float = 8.0
const HTTP_MAP_ASSET_DOWNLOAD_TIMEOUT_SECONDS: float = 24.0
const MAP_VISUAL_ASSET_PREFETCH_CONCURRENCY: int = 4
const MAP_VISUAL_ASSET_PREFETCH_SCHEMA: String = "2"
const HTTP_AVATAR_PROFILE_TIMEOUT_SECONDS: float = 5.0
const HTTP_SOCIAL_TIMEOUT_SECONDS: float = 2.5
const HTTP_PRESENCE_TIMEOUT_SECONDS: float = 2.5
const HTTP_READ_RETRY_ATTEMPTS: int = 2
const STORAGE_ASSET_UPLOAD_MAX_ATTEMPTS: int = 4
const STORAGE_ASSET_RETRY_BASE_SECONDS: float = 0.75
# Complex imported places routinely exceed 18 MB. Rejecting those cache files
# forced a full cloud download and JSON parse on every join, which looked like
# a frozen client and was especially expensive on Android.
const MAX_CACHED_MAP_JSON_BYTES: int = 128 * 1024 * 1024
const MAX_INLINE_CLOUD_MAP_DATA_BYTES: int = 768 * 1024
const EXTERNAL_MAP_DATA_URL_KEY: String = "__bobux_external_map_data_url"
const EXTERNAL_MAP_DATA_SIZE_KEY: String = "__bobux_external_map_data_size"
const EXTERNAL_MAP_DATA_SHA256_KEY: String = "__bobux_external_map_data_sha256"
const MAX_RESTORED_INLINE_ASSET_BYTES: int = 2 * 1024 * 1024
const MAX_RESTORED_INLINE_ASSET_TOTAL_BYTES: int = 4 * 1024 * 1024
const AUTH_SIGNUP_ENDPOINT: String = "/auth/v1/signup"
const AUTH_TOKEN_ENDPOINT: String = "/auth/v1/token"
const AUTH_USER_ENDPOINT: String = "/auth/v1/user"
const USERNAME_AUTH_EMAIL_DOMAIN: String = "gmail.com"
const ANONYMOUS_PROVIDER_DISABLED_CODE: String = "anonymous_provider_disabled"
const EMAIL_CONFIRMATION_HINT: String = "Bobux account service is not accepting this sign-in request yet. Check the VPS API health and auth settings."
const PASSWORD_MIN_LENGTH: int = 6
const AVATAR_OUTFIT_TO_SESSION_KEY_MAP: Dictionary = {
	"head_color": "head",
	"torso_color": "torso",
	"left_arm_color": "left_arm",
	"right_arm_color": "right_arm",
	"left_leg_color": "left_leg",
	"right_leg_color": "right_leg"
}
const AVATAR_OUTFIT_TEXTURE_KEYS := [
	"face_texture_path",
	"chest_badge_texture_path",
	"shirt_texture_path",
	"pants_texture_path"
]
const AVATAR_OUTFIT_SAVED_TEXTURE_LIST_KEYS := [
	"saved_shirt_texture_paths",
	"saved_pants_texture_paths"
]

var base_url: String = ""
var api_key: String = ""
var bearer_token: String = ""
var maps_endpoint: String = DEFAULT_MAPS_ENDPOINT
var servers_endpoint: String = DEFAULT_SERVERS_ENDPOINT
var profiles_endpoint: String = DEFAULT_PROFILES_ENDPOINT
var catalog_endpoint: String = DEFAULT_CATALOG_ENDPOINT
var model_assets_endpoint: String = DEFAULT_MODEL_ASSETS_ENDPOINT
var avatar_items_endpoint: String = DEFAULT_AVATAR_ITEMS_ENDPOINT
var avatar_outfits_endpoint: String = DEFAULT_AVATAR_OUTFITS_ENDPOINT
var friendships_endpoint: String = DEFAULT_FRIENDSHIPS_ENDPOINT
var friend_requests_endpoint: String = DEFAULT_FRIEND_REQUESTS_ENDPOINT
var follows_endpoint: String = DEFAULT_FOLLOWS_ENDPOINT
var project_url: String = DEFAULT_PROJECT_URL
var _auth_access_token: String = ""
var _auth_refresh_token: String = ""
var _auth_user_id: String = ""
var _auth_expires_at: int = 0
var _auth_is_anonymous: bool = false
var _auth_email: String = ""
var _current_profile_username: String = ""
var _auth_bootstrap_in_progress: bool = false
var _auth_bootstrap_result: Dictionary = {}
var _last_auth_error_message: String = ""
var _active_http_requests: Array[HTTPRequest] = []
var _is_shutting_down: bool = false
var _reported_cache_refresh_reasons: Dictionary = {}
var _auth_operation_epoch: int = 0
var _avatar_outfit_refresh_in_flight: bool = false
var _avatar_outfit_refresh_user_id: String = ""

func _ready() -> void:
	_is_shutting_down = false
	project_url = _get_config_value("cloud/project_url", "", DEFAULT_PROJECT_URL)
	base_url = _get_config_value("cloud/base_url", ENV_BASE_URL, DEFAULT_REST_BASE_URL)
	api_key = _get_config_value("cloud/api_key", ENV_API_KEY, DEFAULT_PUBLISHABLE_KEY)
	if api_key.strip_edges().is_empty():
		api_key = DEFAULT_ANON_KEY
	bearer_token = _get_config_value("cloud/bearer_token", ENV_BEARER_TOKEN, "")
	maps_endpoint = _normalize_endpoint(_get_config_value("cloud/maps_endpoint", "", DEFAULT_MAPS_ENDPOINT))
	servers_endpoint = _normalize_endpoint(_get_config_value("cloud/servers_endpoint", "", DEFAULT_SERVERS_ENDPOINT))
	profiles_endpoint = _normalize_endpoint(_get_config_value("cloud/profiles_endpoint", "", DEFAULT_PROFILES_ENDPOINT))
	catalog_endpoint = _normalize_endpoint(_get_config_value("cloud/catalog_endpoint", "", DEFAULT_CATALOG_ENDPOINT))
	model_assets_endpoint = _normalize_endpoint(_get_config_value("cloud/model_assets_endpoint", "", DEFAULT_MODEL_ASSETS_ENDPOINT))
	avatar_items_endpoint = _normalize_endpoint(_get_config_value("cloud/avatar_items_endpoint", "", DEFAULT_AVATAR_ITEMS_ENDPOINT))
	avatar_outfits_endpoint = _normalize_endpoint(_get_config_value("cloud/avatar_outfits_endpoint", "", DEFAULT_AVATAR_OUTFITS_ENDPOINT))
	friendships_endpoint = _normalize_endpoint(_get_config_value("cloud/friendships_endpoint", "", DEFAULT_FRIENDSHIPS_ENDPOINT))
	friend_requests_endpoint = _normalize_endpoint(_get_config_value("cloud/friend_requests_endpoint", "", DEFAULT_FRIEND_REQUESTS_ENDPOINT))
	follows_endpoint = _normalize_endpoint(_get_config_value("cloud/follows_endpoint", "", DEFAULT_FOLLOWS_ENDPOINT))
	_prune_obsolete_auth_artifacts()
	_load_saved_auth_session()
	if _should_autobootstrap_auth_session():
		call_deferred("_bootstrap_auth_session")

func _exit_tree() -> void:
	_cleanup_active_http_requests()

func _cleanup_active_http_requests() -> void:
	_is_shutting_down = true
	_auth_bootstrap_in_progress = false
	for request in _active_http_requests.duplicate():
		if request == null or not is_instance_valid(request):
			continue
		request.cancel_request()
		request.queue_free()
	_active_http_requests.clear()

func _should_autobootstrap_auth_session() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return true

func _bootstrap_auth_session() -> void:
	if not is_configured():
		return
	if _has_valid_access_session():
		auth_session_ready.emit(get_current_auth_session())
		return
	if _auth_refresh_token.is_empty():
		return
	var bootstrap_epoch: int = _auth_operation_epoch
	var bootstrap_refresh_token: String = _auth_refresh_token
	var auth_result: Dictionary = await _refresh_authenticated_session()
	if bootstrap_epoch != _auth_operation_epoch or bootstrap_refresh_token != _auth_refresh_token:
		return
	if bool(auth_result.get("ok", false)):
		auth_session_ready.emit(get_current_auth_session())
	else:
		_clear_auth_session(true)
		push_warning("[CloudAPI] %s" % str(auth_result.get("error", "Could not restore saved cloud session.")))

func get_current_user_id() -> String:
	return _auth_user_id.strip_edges()

func get_current_username() -> String:
	if not _current_profile_username.strip_edges().is_empty():
		return _current_profile_username.strip_edges()
	if UserSession.is_logged_in and not UserSession.username.strip_edges().is_empty():
		return UserSession.username.strip_edges()
	return "Player"

func has_server_service_role() -> bool:
	return not _get_server_service_role_key().is_empty() and not _get_server_rest_base_url().is_empty()

func has_authenticated_session() -> bool:
	return not _auth_user_id.is_empty() and not _auth_access_token.is_empty()

# This function clears the in-memory cloud auth and reloads the saved global session cache.
func reload_saved_auth_session_for_current_user() -> void:
	_auth_operation_epoch += 1
	_clear_auth_session(false)
	_load_saved_auth_session()
	_auth_bootstrap_in_progress = false
	_auth_bootstrap_result = {}
	_last_auth_error_message = ""

# This function clears the current cloud auth from memory and optionally removes its saved file.
func reset_authenticated_session(remove_saved_session: bool = false) -> void:
	_auth_operation_epoch += 1
	_clear_auth_session(remove_saved_session)
	_auth_bootstrap_in_progress = false
	_auth_bootstrap_result = {}
	_last_auth_error_message = ""

func ensure_authenticated_session() -> Dictionary:
	if not is_configured():
		var config_error: Dictionary = _make_error_result("ensure_authenticated_session", "Cloud API configuration is incomplete.")
		auth_session_failed.emit(str(config_error.get("error", "")))
		return config_error

	if _auth_bootstrap_in_progress:
		var bootstrap_deadline_msec: int = Time.get_ticks_msec() + AUTH_BOOTSTRAP_WAIT_TIMEOUT_MSEC
		while _auth_bootstrap_in_progress and Time.get_ticks_msec() < bootstrap_deadline_msec:
			await get_tree().process_frame
		if _auth_bootstrap_in_progress:
			_auth_bootstrap_in_progress = false
			if _auth_bootstrap_result.is_empty():
				_auth_bootstrap_result = _make_error_result("ensure_authenticated_session", "Cloud authentication bootstrap timed out.")
			_last_auth_error_message = str(_auth_bootstrap_result.get("error", "Cloud authentication bootstrap timed out."))
			auth_session_failed.emit(_last_auth_error_message)
		return _auth_bootstrap_result

	_auth_bootstrap_in_progress = true
	var ensure_epoch: int = _auth_operation_epoch
	var result: Dictionary = {}
	if _has_valid_access_session():
		result = {
			"ok": true,
			"endpoint": "ensure_authenticated_session",
			"status": 200,
			"data": get_current_auth_session()
		}
	elif not _auth_refresh_token.is_empty():
		result = await _refresh_authenticated_session()
		if ensure_epoch != _auth_operation_epoch:
			_auth_bootstrap_in_progress = false
			_auth_bootstrap_result = {}
			if _has_valid_access_session():
				return {
					"ok": true,
					"endpoint": "ensure_authenticated_session",
					"status": 200,
					"data": get_current_auth_session()
				}
			return _make_error_result("ensure_authenticated_session", "Cloud authentication request was superseded.")
		if not bool(result.get("ok", false)):
			_clear_auth_session(true)
	if bool(result.get("ok", false)) and not await _validate_session_binding_for_current_user():
		_clear_auth_session(true)
		result = _make_error_result("ensure_authenticated_session", "Saved cloud session does not match the selected player profile.")
	if result.is_empty():
		result = _make_error_result("ensure_authenticated_session", "No authenticated cloud session is available.")

	_auth_bootstrap_result = result
	_auth_bootstrap_in_progress = false
	if bool(result.get("ok", false)):
		auth_session_ready.emit(get_current_auth_session())
	else:
		_last_auth_error_message = str(result.get("error", "Authentication failed."))
		auth_session_failed.emit(_last_auth_error_message)
	return result

# PRACTICE SCREENSHOT: Client registration flow - sends username/password to the server and stores the returned cloud session.
func sign_up_with_credentials(preferred_username: String, password: String) -> Dictionary:
	var clean_username: String = preferred_username.strip_edges()
	var clean_password: String = password.strip_edges()
	if clean_username.length() < 3:
		return _make_error_result("sign_up_with_credentials", "Username must be at least 3 characters long.")
	if clean_password.length() < PASSWORD_MIN_LENGTH:
		return _make_error_result("sign_up_with_credentials", "Password must be at least %d characters long." % PASSWORD_MIN_LENGTH)
	var response: Dictionary = await _request_auth_json(
		AUTH_SIGNUP_ENDPOINT,
		HTTPClient.METHOD_POST,
		{
			"email": _build_auth_email_from_username(clean_username),
			"password": clean_password,
			"data": {
				"username": clean_username,
				"source": "godot",
				"platform": OS.get_name()
			}
		},
		"sign_up_with_credentials"
	)
	if not bool(response.get("ok", false)):
		return _map_auth_error_result(response, clean_username, true)
	if not _auth_payload_contains_session(response.get("data", {})):
		return _make_error_result(
			"sign_up_with_credentials",
			"Bobux account service did not return a session. %s" % EMAIL_CONFIRMATION_HINT
		)
	var session_result: Dictionary = _apply_auth_response_payload(response, "sign_up_with_credentials")
	if not bool(session_result.get("ok", false)):
		return session_result
	var profile_result: Dictionary = await authenticate_or_create_profile(clean_username, false)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	UserSession.begin_cloud_session(_auth_user_id, str(profile_result.get("username", clean_username)).strip_edges())
	return {
		"ok": true,
		"endpoint": "sign_up_with_credentials",
		"status": int(session_result.get("status", 200)),
		"data": get_current_auth_session()
	}

# PRACTICE SCREENSHOT: Client login flow - authenticates the player and opens the UserSession used by the game.
func sign_in_with_credentials(preferred_username: String, password: String) -> Dictionary:
	var clean_username: String = preferred_username.strip_edges()
	var clean_password: String = password.strip_edges()
	if clean_username.length() < 3:
		return _make_error_result("sign_in_with_credentials", "Username must be at least 3 characters long.")
	if clean_password.length() < PASSWORD_MIN_LENGTH:
		return _make_error_result("sign_in_with_credentials", "Password must be at least %d characters long." % PASSWORD_MIN_LENGTH)
	var response: Dictionary = await _perform_password_sign_in_request(clean_username, clean_password, "sign_in_with_credentials")
	if not bool(response.get("ok", false)):
		return _map_auth_error_result(response, clean_username, false)
	var session_result: Dictionary = _apply_auth_response_payload(response, "sign_in_with_credentials")
	if not bool(session_result.get("ok", false)):
		return session_result
	var profile_result: Dictionary = await authenticate_or_create_profile(clean_username, false)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	UserSession.begin_cloud_session(_auth_user_id, str(profile_result.get("username", clean_username)).strip_edges())
	return {
		"ok": true,
		"endpoint": "sign_in_with_credentials",
		"status": int(session_result.get("status", 200)),
		"data": get_current_auth_session()
	}

func get_current_auth_session() -> Dictionary:
	return {
		"user_id": _auth_user_id,
		"access_token": _auth_access_token,
		"refresh_token": _auth_refresh_token,
		"expires_at": _auth_expires_at,
		"is_anonymous": _auth_is_anonymous,
		"email": _auth_email,
		"username": get_current_username()
	}

# PRACTICE SCREENSHOT: Profile synchronization - creates or updates the player profile after authentication.
func authenticate_or_create_profile(preferred_username: String = "", allow_generated_username: bool = true) -> Dictionary:
	var auth_result: Dictionary = await ensure_authenticated_session()
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var username: String = _resolve_username(preferred_username)
	var payload: Dictionary = _build_profile_payload(username)
	var response: Dictionary = await _upsert_profile_payload(payload, "authenticate_or_create_profile")
	if _is_unique_username_conflict(response):
		if not allow_generated_username:
			return _make_error_result("authenticate_or_create_profile", "That username is already claimed. Sign in to the original account or choose another username.", ERR_ALREADY_EXISTS)
		payload["username"] = _make_unique_username_variant(username, _auth_user_id)
		response = await _upsert_profile_payload(payload, "authenticate_or_create_profile_retry")
	if bool(response.get("ok", false)):
		var resolved_profile: Dictionary = _normalize_profile_record(response.get("data", {}))
		_current_profile_username = str(resolved_profile.get("username", payload.get("username", username))).strip_edges()
		_save_auth_session()
		if not _auth_user_id.is_empty() and not _current_profile_username.is_empty():
			UserSession.begin_cloud_session(_auth_user_id, _current_profile_username)
			UserSession.apply_cloud_profile_payload(resolved_profile.get("avatar_data", {}), resolved_profile.get("inventory_items", []))
			UserSession.apply_avatar_to_game_state()
			UserSession.save_profile()
			_schedule_current_avatar_outfit_refresh(_auth_user_id)
		response["profile_id"] = _auth_user_id
		response["user_id"] = _auth_user_id
		response["username"] = _current_profile_username
		profile_authenticated.emit({
			"id": _auth_user_id,
			"username": _current_profile_username,
			"is_anonymous": _auth_is_anonymous
		})
	return response

func _schedule_current_avatar_outfit_refresh(user_id: String) -> void:
	var clean_user_id := user_id.strip_edges()
	if clean_user_id.is_empty() or _avatar_outfit_refresh_in_flight:
		return
	_avatar_outfit_refresh_in_flight = true
	_avatar_outfit_refresh_user_id = clean_user_id
	call_deferred("_refresh_current_avatar_outfit_async", clean_user_id)

func _refresh_current_avatar_outfit_async(user_id: String) -> void:
	var clean_user_id := user_id.strip_edges()
	if clean_user_id.is_empty():
		_avatar_outfit_refresh_in_flight = false
		_avatar_outfit_refresh_user_id = ""
		return
	if is_inside_tree():
		await get_tree().process_frame
	if _is_shutting_down or clean_user_id != _auth_user_id:
		_avatar_outfit_refresh_in_flight = false
		_avatar_outfit_refresh_user_id = ""
		return
	var avatar_outfit_result: Dictionary = await load_avatar_outfit(clean_user_id)
	if bool(avatar_outfit_result.get("ok", false)) and avatar_outfit_result.get("data", {}) is Dictionary and clean_user_id == _auth_user_id:
		var resolved_avatar_outfit: Dictionary = avatar_outfit_result.get("data", {})
		if not resolved_avatar_outfit.is_empty():
			UserSession.avatar_data = _merge_avatar_outfit_into_session_avatar_data(UserSession.avatar_data, resolved_avatar_outfit)
			UserSession.apply_avatar_to_game_state()
			UserSession.save_profile()
	_avatar_outfit_refresh_in_flight = false
	_avatar_outfit_refresh_user_id = ""

# PRACTICE SCREENSHOT: Map publishing flow - uploads a user-created experience and metadata to the cloud database.
func upload_map_to_cloud(map_data: Dictionary, map_name: String, map_metadata: Dictionary = {}) -> Dictionary:
	if map_data.is_empty():
		var empty_error: Dictionary = _make_error_result("upload_map_to_cloud", "Map data is empty.")
		request_failed.emit("upload_map_to_cloud", str(empty_error.get("error", "")))
		return empty_error

	var ensured_profile: Dictionary = await authenticate_or_create_profile(str(map_metadata.get("owner_name", get_current_username())))
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var map_id: String = _resolve_cloud_map_id(map_name, map_metadata)
	var clean_map_name: String = map_name.strip_edges()
	if clean_map_name.is_empty():
		clean_map_name = "Untitled Experience"
	var version_id: String = _generate_cloud_version_id()
	var cloud_map_data: Dictionary = map_data
	var encoded_map_data: PackedByteArray = await _encode_json_dictionary_async(map_data)
	if encoded_map_data.is_empty():
		return _make_error_result("upload_map_to_cloud", "Map data could not be encoded as JSON.", ERR_CANT_CREATE)
	if encoded_map_data.size() > MAX_INLINE_CLOUD_MAP_DATA_BYTES:
		var map_data_upload: Dictionary = await _upload_map_data_payload(map_id, version_id, encoded_map_data)
		if not bool(map_data_upload.get("ok", false)):
			return map_data_upload
		var uploaded_asset: Dictionary = map_data_upload.get("asset", {}) if map_data_upload.get("asset", {}) is Dictionary else {}
		var external_url: String = str(uploaded_asset.get("public_url", "")).strip_edges()
		if external_url.is_empty():
			return _make_error_result("upload_map_to_cloud", "Map data storage upload did not return a public URL.")
		cloud_map_data = {
			EXTERNAL_MAP_DATA_URL_KEY: external_url,
			EXTERNAL_MAP_DATA_SIZE_KEY: encoded_map_data.size(),
			EXTERNAL_MAP_DATA_SHA256_KEY: _sha256_bytes(encoded_map_data),
			"__bobux_external_map_data_version": 1
		}
	var payload: Dictionary = {
		"id": map_id,
		"name": clean_map_name,
		"owner_id": _auth_user_id,
		"owner_name": str(ensured_profile.get("username", get_current_username())).strip_edges(),
		"data": cloud_map_data,
		"updated_at": Time.get_datetime_string_from_system(true, true),
		"cloud_version_id": version_id,
		"description": map_metadata.get("description", ""),
		"thumbnail": map_metadata.get("thumbnail", ""),
		"is_published": bool(map_metadata.get("is_published", true))
	}

	var response: Dictionary = {}
	for upload_attempt in range(3):
		response = await _request_json(
			"%s?on_conflict=id" % maps_endpoint,
			HTTPClient.METHOD_POST,
			payload,
			"upload_map_to_cloud",
			PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
			true,
			HTTP_UPLOAD_TIMEOUT_SECONDS
		)
		if bool(response.get("ok", false)):
			break
		if _is_recoverable_transport_error(response):
			var recovered_after_transport: Dictionary = await _recover_uploaded_map_after_timeout(map_id)
			if bool(recovered_after_transport.get("ok", false)):
				response = recovered_after_transport
				break
		if upload_attempt < 2:
			await get_tree().create_timer(0.6 + float(upload_attempt) * 0.45).timeout
	if bool(response.get("ok", false)):
		map_uploaded.emit(response)
		return response
	if _is_http_timeout_error(response):
		var recovered_response: Dictionary = await _recover_uploaded_map_after_timeout(map_id)
		if bool(recovered_response.get("ok", false)):
			map_uploaded.emit(recovered_response)
			return recovered_response
	return response

func _upload_map_data_payload(map_id: String, version_id: String, bytes: PackedByteArray) -> Dictionary:
	if map_id.strip_edges().is_empty() or bytes.is_empty():
		return _make_error_result("upload_map_data_payload", "Map id or map data is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("upload_map_data_payload")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var safe_version: String = _sanitize_storage_segment(version_id)
	if safe_version.is_empty():
		safe_version = str(Time.get_unix_time_from_system())
	var relative_name := "map_data/%s.json" % safe_version
	var object_path: String = "%s/%s/%s" % [
		_sanitize_storage_segment(_auth_user_id),
		_sanitize_storage_segment(map_id),
		relative_name
	]
	var upload_url: String = "%s/storage/v1/object/%s/%s" % [
		project_url.trim_suffix("/"),
		MAP_ASSET_BUCKET.uri_encode(),
		object_path
	]
	var public_url: String = "%s/storage/v1/object/public/%s/%s" % [
		project_url.trim_suffix("/"),
		MAP_ASSET_BUCKET.uri_encode(),
		object_path
	]
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"apikey: %s" % _get_storage_api_key(),
		"Authorization: Bearer %s" % _auth_access_token,
		"cache-control: no-cache",
		"x-upsert: true"
	])
	var result: Dictionary = await _request_http_bytes(
		upload_url,
		HTTPClient.METHOD_POST,
		bytes,
		"upload_map_data_payload",
		headers,
		HTTP_UPLOAD_TIMEOUT_SECONDS
	)
	if not bool(result.get("ok", false)):
		return result
	result["asset"] = {
		"relative_file": relative_name,
		"storage_path": object_path,
		"public_url": public_url,
		"mime_type": "application/json",
		"size": bytes.size()
	}
	return result

# PRACTICE SCREENSHOT: Map asset upload flow - stores external files such as thumbnails and map media in server storage.
func upload_map_asset_file(map_id: String, relative_file_name: String, absolute_path: String, mime_type: String = "", timeout_seconds: float = HTTP_UPLOAD_TIMEOUT_SECONDS, max_attempts: int = STORAGE_ASSET_UPLOAD_MAX_ATTEMPTS) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	var clean_relative_name: String = _sanitize_storage_relative_path(relative_file_name)
	if clean_map_id.is_empty() or clean_relative_name.is_empty():
		return _make_error_result("upload_map_asset_file", "Map id or asset path is empty.")
	if not FileAccess.file_exists(absolute_path):
		return _make_error_result("upload_map_asset_file", "Asset file does not exist: %s" % absolute_path)
	var auth_result: Dictionary = await _ensure_data_api_session("upload_map_asset_file")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return _make_error_result("upload_map_asset_file", "Could not open asset file: %s" % absolute_path)
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return _make_error_result("upload_map_asset_file", "Asset file is empty: %s" % absolute_path)
	var object_path: String = "%s/%s/%s" % [
		_sanitize_storage_segment(_auth_user_id),
		_sanitize_storage_segment(clean_map_id),
		clean_relative_name
	]
	var upload_url: String = "%s/storage/v1/object/%s/%s" % [
		project_url.trim_suffix("/"),
		MAP_ASSET_BUCKET.uri_encode(),
		object_path
	]
	var public_url: String = "%s/storage/v1/object/public/%s/%s" % [
		project_url.trim_suffix("/"),
		MAP_ASSET_BUCKET.uri_encode(),
		object_path
	]
	var content_type: String = mime_type.strip_edges()
	if content_type.is_empty():
		content_type = _guess_mime_type(clean_relative_name)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: %s" % content_type,
		"apikey: %s" % _get_storage_api_key(),
		"Authorization: Bearer %s" % _auth_access_token,
		"cache-control: 3600",
		"x-upsert: true"
	])
	var result: Dictionary = {}
	for attempt in range(maxi(max_attempts, 1)):
		result = await _request_http_bytes(upload_url, HTTPClient.METHOD_POST, bytes, "upload_map_asset_file", headers, maxf(timeout_seconds, 1.0))
		if bool(result.get("ok", false)):
			break
		if _is_recoverable_transport_error(result):
			await get_tree().create_timer(STORAGE_ASSET_RETRY_BASE_SECONDS + float(attempt) * 0.65).timeout
			var verify_result: Dictionary = await _verify_uploaded_asset(public_url)
			if bool(verify_result.get("ok", false)):
				result = verify_result
				break
			continue
		break
	if not bool(result.get("ok", false)):
		return result
	result["asset"] = {
		"relative_file": clean_relative_name,
		"storage_path": object_path,
		"public_url": public_url,
		"mime_type": content_type,
		"size": bytes.size()
	}
	return result

func upload_model_asset_file(model_id: String, relative_file_name: String, absolute_path: String, mime_type: String = "", timeout_seconds: float = HTTP_UPLOAD_TIMEOUT_SECONDS, max_attempts: int = STORAGE_ASSET_UPLOAD_MAX_ATTEMPTS) -> Dictionary:
	return await _upload_storage_asset_file(MODEL_ASSET_BUCKET, model_id, relative_file_name, absolute_path, mime_type, "upload_model_asset_file", timeout_seconds, max_attempts)

func upload_avatar_item_file(item_id: String, relative_file_name: String, absolute_path: String, mime_type: String = "", timeout_seconds: float = HTTP_UPLOAD_TIMEOUT_SECONDS, max_attempts: int = STORAGE_ASSET_UPLOAD_MAX_ATTEMPTS) -> Dictionary:
	return await _upload_storage_asset_file(AVATAR_ITEM_BUCKET, item_id, relative_file_name, absolute_path, mime_type, "upload_avatar_item_file", timeout_seconds, max_attempts)

func _upload_storage_asset_file(bucket: String, owner_object_id: String, relative_file_name: String, absolute_path: String, mime_type: String, request_name: String, timeout_seconds: float, max_attempts: int) -> Dictionary:
	var clean_object_id: String = owner_object_id.strip_edges()
	var clean_relative_name: String = _sanitize_storage_relative_path(relative_file_name)
	if clean_object_id.is_empty() or clean_relative_name.is_empty():
		return _make_error_result(request_name, "Object id or asset path is empty.")
	if not FileAccess.file_exists(absolute_path):
		return _make_error_result(request_name, "Asset file does not exist: %s" % absolute_path)
	var auth_result: Dictionary = await _ensure_data_api_session(request_name)
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return _make_error_result(request_name, "Could not open asset file: %s" % absolute_path)
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return _make_error_result(request_name, "Asset file is empty: %s" % absolute_path)
	var object_path: String = "%s/%s/%s" % [
		_sanitize_storage_segment(_auth_user_id),
		_sanitize_storage_segment(clean_object_id),
		clean_relative_name
	]
	var upload_url: String = "%s/storage/v1/object/%s/%s" % [
		project_url.trim_suffix("/"),
		bucket.uri_encode(),
		object_path
	]
	var public_url: String = "%s/storage/v1/object/public/%s/%s" % [
		project_url.trim_suffix("/"),
		bucket.uri_encode(),
		object_path
	]
	var content_type: String = mime_type.strip_edges()
	if content_type.is_empty():
		content_type = _guess_mime_type(clean_relative_name)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: %s" % content_type,
		"apikey: %s" % _get_storage_api_key(),
		"Authorization: Bearer %s" % _auth_access_token,
		"cache-control: 3600",
		"x-upsert: true"
	])
	var result: Dictionary = {}
	for attempt in range(maxi(max_attempts, 1)):
		result = await _request_http_bytes(upload_url, HTTPClient.METHOD_POST, bytes, request_name, headers, maxf(timeout_seconds, 1.0))
		if bool(result.get("ok", false)):
			break
		if _is_recoverable_transport_error(result):
			await get_tree().create_timer(STORAGE_ASSET_RETRY_BASE_SECONDS + float(attempt) * 0.65).timeout
			var verify_result: Dictionary = await _verify_uploaded_asset(public_url)
			if bool(verify_result.get("ok", false)):
				result = verify_result
				break
			continue
		break
	if not bool(result.get("ok", false)):
		return result
	result["asset"] = {
		"relative_file": clean_relative_name,
		"storage_path": object_path,
		"public_url": public_url,
		"mime_type": content_type,
		"size_bytes": bytes.size()
	}
	return result

func _verify_uploaded_asset(public_url: String) -> Dictionary:
	if public_url.strip_edges().is_empty():
		return _make_error_result("verify_map_asset_file", "Asset URL is empty.")
	var headers: PackedStringArray = PackedStringArray(["Accept: */*"])
	var result: Dictionary = await _request_http_bytes(public_url, HTTPClient.METHOD_HEAD, PackedByteArray(), "verify_map_asset_file", headers, 12.0)
	if bool(result.get("ok", false)):
		return result
	if int(result.get("status", 0)) == 405:
		headers.append("Range: bytes=0-0")
		return await _request_http_bytes(public_url, HTTPClient.METHOD_GET, PackedByteArray(), "verify_map_asset_file", headers, 12.0)
	return result

func download_map_asset_file(asset_url: String, target_path: String) -> Dictionary:
	return await _download_file_to_path(asset_url, target_path)

func download_map_from_cloud(map_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		var empty_error: Dictionary = _make_error_result("download_map_from_cloud", "Map id is empty.")
		request_failed.emit("download_map_from_cloud", str(empty_error.get("error", "")))
		return empty_error

	var endpoint: String = "%s?select=id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,data&id=eq.%s&limit=1" % [
		maps_endpoint,
		clean_map_id.uri_encode()
	]
	var response: Dictionary = {}
	if use_service_role:
		response = await _request_server_json(endpoint, HTTPClient.METHOD_GET, null, "download_map_from_cloud", PackedStringArray(), true)
	else:
		response = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "download_map_from_cloud", PackedStringArray(), false)
	if bool(response.get("ok", false)):
		response = await _hydrate_external_map_data_response(response)
	if bool(response.get("ok", false)):
		map_downloaded.emit(clean_map_id, response)
	return response

func _hydrate_external_map_data_response(response: Dictionary) -> Dictionary:
	var rows: Array = _extract_array_payload(response.get("data", []))
	if rows.is_empty():
		return response
	var hydrated_rows: Array = []
	for row_variant in rows:
		if not (row_variant is Dictionary):
			hydrated_rows.append(row_variant)
			continue
		var row: Dictionary = (row_variant as Dictionary).duplicate(false)
		var descriptor: Dictionary = row.get("data", {}) if row.get("data", {}) is Dictionary else {}
		var external_url: String = str(descriptor.get(EXTERNAL_MAP_DATA_URL_KEY, "")).strip_edges()
		if external_url.is_empty():
			hydrated_rows.append(row)
			continue
		var headers := PackedStringArray(["Accept: application/json", "Cache-Control: no-cache"])
		var download_result: Dictionary = await _request_http_bytes(
			external_url,
			HTTPClient.METHOD_GET,
			PackedByteArray(),
			"download_external_map_data",
			headers,
			HTTP_UPLOAD_TIMEOUT_SECONDS
		)
		if not bool(download_result.get("ok", false)):
			return download_result
		var map_bytes: PackedByteArray = download_result.get("bytes", PackedByteArray())
		var expected_size: int = int(descriptor.get(EXTERNAL_MAP_DATA_SIZE_KEY, 0))
		if expected_size > 0 and map_bytes.size() != expected_size:
			return _make_error_result("download_external_map_data", "Downloaded map data size does not match the published version.", ERR_FILE_CORRUPT)
		var expected_hash: String = str(descriptor.get(EXTERNAL_MAP_DATA_SHA256_KEY, "")).strip_edges()
		var decoded_map := await _decode_json_dictionary_async(map_bytes)
		if not bool(decoded_map.get("ok", false)):
			return _make_error_result("download_external_map_data", "Published map data is not valid JSON.", ERR_PARSE_ERROR)
		if not expected_hash.is_empty() and str(decoded_map.get("sha256", "")) != expected_hash:
			return _make_error_result("download_external_map_data", "Downloaded map data checksum is invalid.", ERR_FILE_CORRUPT)
		row["data"] = decoded_map.get("data", {})
		hydrated_rows.append(row)
	response["data"] = hydrated_rows
	return response

func _encode_json_dictionary_async(data: Dictionary) -> PackedByteArray:
	var worker := Thread.new()
	var start_error := worker.start(_encode_json_dictionary_worker.bind(data))
	if start_error != OK:
		return JSON.stringify(data).to_utf8_buffer()
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is PackedByteArray else PackedByteArray()

static func _encode_json_dictionary_worker(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()

func _decode_json_dictionary_async(bytes: PackedByteArray) -> Dictionary:
	var worker := Thread.new()
	var start_error := worker.start(_decode_json_dictionary_worker.bind(bytes))
	if start_error != OK:
		return _decode_json_dictionary_worker(bytes)
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is Dictionary else {"ok": false}

static func _decode_json_dictionary_worker(bytes: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false}
	return {
		"ok": true,
		"data": parsed,
		"sha256": _sha256_bytes(bytes)
	}

static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func _is_http_timeout_error(response: Dictionary) -> bool:
	return not bool(response.get("ok", false)) \
		and int(response.get("error_code", -1)) == HTTPRequest.RESULT_TIMEOUT \
		and int(response.get("status", -1)) == 0

func _is_recoverable_transport_error(response: Dictionary) -> bool:
	if bool(response.get("ok", false)):
		return false
	var status_code: int = int(response.get("status", -1))
	if status_code != 0:
		return false
	var transport_code: int = int(response.get("error_code", -1))
	return transport_code == HTTPRequest.RESULT_TIMEOUT \
		or transport_code == HTTPRequest.RESULT_CANT_CONNECT \
		or transport_code == HTTPRequest.RESULT_CANT_RESOLVE \
		or transport_code == HTTPRequest.RESULT_CONNECTION_ERROR \
		or transport_code == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR

func _is_retryable_http_error(response: Dictionary) -> bool:
	if _is_recoverable_transport_error(response):
		return true
	var status_code: int = int(response.get("status", 0))
	return status_code == 408 or status_code == 425 or status_code == 429 or status_code == 500 or status_code == 502 or status_code == 503 or status_code == 504

func _recover_uploaded_map_after_timeout(map_id: String) -> Dictionary:
	if map_id.strip_edges().is_empty():
		return _make_error_result("upload_map_to_cloud", "Upload timed out and no map id was available for verification.", HTTPRequest.RESULT_TIMEOUT)
	await get_tree().create_timer(0.75).timeout
	var endpoint: String = "%s?select=id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,data&id=eq.%s&limit=1" % [
		maps_endpoint,
		map_id.strip_edges().uri_encode()
	]
	var verify_response: Dictionary = await _request_json(
		endpoint,
		HTTPClient.METHOD_GET,
		null,
		"upload_map_to_cloud_verify",
		PackedStringArray(),
		true,
		HTTP_UPLOAD_TIMEOUT_SECONDS
	)
	if bool(verify_response.get("ok", false)):
		var rows: Array = _extract_array_payload(verify_response.get("data", []))
		if not rows.is_empty():
			verify_response["endpoint"] = "upload_map_to_cloud"
			verify_response["recovered_from_timeout"] = true
			return verify_response
	return _make_error_result(
		"upload_map_to_cloud",
		"Cloud upload timed out and the map record could not be verified yet. Please try again.",
		HTTPRequest.RESULT_TIMEOUT,
		0,
		verify_response.get("data", null)
	)

func download_map_with_cache(map_id: String, cloud_version_id: String = "", fallback_name: String = "Cloud Map", use_service_role: bool = false) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("download_map_with_cache", "Map id is empty.")
	if clean_map_id.to_lower() == "classic":
		return {
			"ok": true,
			"folder": "res://maps/classic",
			"from_cache": true,
			"cloud_version_id": ""
		}

	var cached_folder: String = get_cached_map_folder(clean_map_id, cloud_version_id)
	if not cached_folder.is_empty():
		var cached_prefetch: Dictionary = await _ensure_cached_map_visual_assets(cached_folder, cloud_version_id)
		return {
			"ok": true,
			"folder": cached_folder,
			"from_cache": true,
			"cloud_version_id": cloud_version_id,
			"asset_prefetch": cached_prefetch
		}

	var response: Dictionary = await download_map_from_cloud(clean_map_id, use_service_role)
	if not bool(response.get("ok", false)):
		return response

	var record: Dictionary = _normalize_cloud_map_record(response.get("data", {}))
	if record.is_empty():
		return _make_error_result("download_map_with_cache", "Cloud map response did not include a usable record.")

	var resolved_version: String = _extract_cloud_version_id(record, cloud_version_id)
	var folder: String = await _store_cached_map_record(clean_map_id, resolved_version, fallback_name, record)
	if folder.is_empty():
		return _make_error_result("download_map_with_cache", "Could not cache map locally.")

	var visual_prefetch: Dictionary = await _ensure_cached_map_visual_assets(folder, resolved_version, record.get("data", {}))
	return {
		"ok": true,
		"folder": folder,
		"from_cache": false,
		"data": record,
		"cloud_version_id": resolved_version,
		"asset_prefetch": visual_prefetch
	}

func get_cached_map_folder(map_id: String, cloud_version_id: String = "") -> String:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return ""
	var folder: String = CACHE_ROOT_PATH.path_join(_sanitize_cache_key(clean_map_id))
	var map_path: String = folder.path_join("map_data.json")
	var meta_path: String = folder.path_join("meta.json")
	var version_path: String = folder.path_join("version.txt")
	if not FileAccess.file_exists(map_path) or not FileAccess.file_exists(meta_path):
		return ""
	if _get_file_size_bytes(map_path) > MAX_CACHED_MAP_JSON_BYTES:
		_print_cache_refresh_once(clean_map_id, "too_large", "is too large; refreshing cloud cache without inline heavy assets.")
		return ""
	# Do not parse every cached map on lobby startup just to detect legacy inline
	# blobs. That check walks large map JSON files and was freezing accounts with
	# many cached experiences after login. Heavy maps are still rejected by the
	# size guard above; older inline caches are cleaned lazily when a map is
	# explicitly refreshed or re-downloaded.
	if cloud_version_id.strip_edges().is_empty():
		return folder
	if not FileAccess.file_exists(version_path):
		return ""
	var version_file: FileAccess = FileAccess.open(version_path, FileAccess.READ)
	if version_file == null:
		return ""
	var stored_version: String = version_file.get_as_text().strip_edges()
	version_file.close()
	return folder if stored_version == cloud_version_id.strip_edges() else ""

func _print_cache_refresh_once(map_id: String, reason_key: String, message: String) -> void:
	var dedupe_key := "%s|%s" % [map_id, reason_key]
	if _reported_cache_refresh_reasons.has(dedupe_key):
		return
	_reported_cache_refresh_reasons[dedupe_key] = true
	print("[CloudAPI] Cached map '%s' %s" % [map_id, message])

func fetch_published_maps(limit: int = 20) -> Dictionary:
	var query: String = "%s?select=id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,likes_count,visits_count&is_published=eq.true&order=updated_at.desc&limit=%d" % [maps_endpoint, maxi(limit, 1)]
	var response: Dictionary = await _request_json_with_retries(query, HTTPClient.METHOD_GET, null, "fetch_published_maps", PackedStringArray(), false, HTTP_REQUEST_TIMEOUT_SECONDS, HTTP_READ_RETRY_ATTEMPTS)
	if bool(response.get("ok", false)):
		var maps: Array = _dedupe_published_maps_by_owner_and_name(_extract_array_payload(response.get("data", [])))
		response["data"] = maps
		published_maps_fetched.emit(maps)
	return response

func fetch_published_maps_for_owner(owner_user_id: String, limit: int = 20) -> Dictionary:
	var clean_owner_user_id: String = owner_user_id.strip_edges()
	if clean_owner_user_id.is_empty():
		return {
			"ok": true,
			"endpoint": "fetch_published_maps_for_owner",
			"status": 200,
			"data": []
		}
	var query: String = "%s?select=id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,likes_count,visits_count&is_published=eq.true&owner_id=eq.%s&order=updated_at.desc&limit=%d" % [maps_endpoint, clean_owner_user_id.uri_encode(), maxi(limit, 1)]
	var response: Dictionary = await _request_json_with_retries(query, HTTPClient.METHOD_GET, null, "fetch_published_maps_for_owner", PackedStringArray(), false, HTTP_REQUEST_TIMEOUT_SECONDS, HTTP_READ_RETRY_ATTEMPTS)
	if bool(response.get("ok", false)):
		response["data"] = _dedupe_published_maps_by_owner_and_name(_extract_array_payload(response.get("data", [])))
	return response

func fetch_published_map_metadata(map_id: String) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("fetch_published_map_metadata", "Map id is empty.")
	var query: String = "%s?select=id,name,owner_id,owner_name,thumbnail,cloud_version_id,updated_at,likes_count,visits_count,is_published&id=eq.%s&is_published=eq.true&limit=1" % [
		maps_endpoint,
		clean_map_id.uri_encode()
	]
	return await _request_json_with_retries(query, HTTPClient.METHOD_GET, null, "fetch_published_map_metadata", PackedStringArray(), false, HTTP_REQUEST_TIMEOUT_SECONDS, 1)

func increment_map_visits(map_id: String, current_visits: int = 0) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("increment_map_visits", "Map id is empty.")
	var rpc_response: Dictionary = await _request_json_with_retries(
		"/rpc/increment_map_visit",
		HTTPClient.METHOD_POST,
		{"target_id": clean_map_id},
		"increment_map_visits",
		PackedStringArray(),
		false
	)
	# The server owns counters. A client-side PATCH based on a stale card value
	# could overwrite newer visits and made the number appear to go backwards.
	return rpc_response

func like_map(map_id: String, current_likes: int = 0) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("like_map", "Map id is empty.")
	var rpc_response: Dictionary = await like_catalog_asset("map", clean_map_id)
	# Likes are idempotent per authenticated user and authoritative on the API.
	# Never fall back to an unaudited absolute counter write from the client.
	return rpc_response

func delete_map(map_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("delete_map", "Map id is empty.")
	var endpoint: String = "%s?id=eq.%s" % [maps_endpoint, clean_map_id.uri_encode()]
	var headers := PackedStringArray(["Prefer: return=minimal"])
	if use_service_role:
		return await _request_server_json(endpoint, HTTPClient.METHOD_DELETE, null, "delete_map", headers, true)
	var auth_result: Dictionary = await _ensure_data_api_session("delete_map")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json(endpoint, HTTPClient.METHOD_DELETE, null, "delete_map", headers, true)

func resolve_cloud_map_id_for_name(map_name: String, map_metadata: Dictionary = {}) -> String:
	return _resolve_cloud_map_id(map_name, map_metadata)

func find_own_published_map_by_name(map_name: String) -> Dictionary:
	var clean_map_name: String = map_name.strip_edges()
	if clean_map_name.is_empty():
		return _make_error_result("find_own_published_map_by_name", "Map name is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("find_own_published_map_by_name")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var query: String = "%s?select=id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,likes_count,visits_count&owner_id=eq.%s&name=eq.%s&is_published=eq.true&order=updated_at.desc&limit=1" % [
		maps_endpoint,
		_auth_user_id.uri_encode(),
		clean_map_name.uri_encode()
	]
	var response: Dictionary = await _request_json_with_retries(
		query,
		HTTPClient.METHOD_GET,
		null,
		"find_own_published_map_by_name",
		PackedStringArray(),
		true,
		HTTP_REQUEST_TIMEOUT_SECONDS,
		HTTP_READ_RETRY_ATTEMPTS
	)
	if not bool(response.get("ok", false)):
		return response
	var maps: Array = _extract_array_payload(response.get("data", []))
	if maps.is_empty() or not (maps[0] is Dictionary):
		return {
			"ok": false,
			"not_found": true,
			"error": "No published map found for this account and name."
		}
	return {
		"ok": true,
		"data": maps[0]
	}

func delete_own_maps_by_name(map_name: String) -> Dictionary:
	var clean_map_name: String = map_name.strip_edges()
	if clean_map_name.is_empty():
		return _make_error_result("delete_own_maps_by_name", "Map name is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("delete_own_maps_by_name")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var endpoint: String = "%s?owner_id=eq.%s&name=eq.%s" % [
		maps_endpoint,
		_auth_user_id.uri_encode(),
		clean_map_name.uri_encode()
	]
	return await _request_json(
		endpoint,
		HTTPClient.METHOD_DELETE,
		null,
		"delete_own_maps_by_name",
		PackedStringArray(["Prefer: return=minimal"]),
		true
	)

func delete_own_maps_by_name_and_cleanup(map_name: String) -> Dictionary:
	var clean_map_name: String = map_name.strip_edges()
	if clean_map_name.is_empty():
		return _make_error_result("delete_own_maps_by_name_and_cleanup", "Map name is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("delete_own_maps_by_name_and_cleanup")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var rpc_result: Dictionary = await _request_json(
		"/rpc/delete_own_maps_by_name_and_cleanup",
		HTTPClient.METHOD_POST,
		{"target_map_name": clean_map_name},
		"delete_own_maps_by_name_and_cleanup",
		PackedStringArray(),
		true
	)
	if bool(rpc_result.get("ok", false)):
		return rpc_result
	return await delete_own_maps_by_name(clean_map_name)

func delete_map_and_cleanup(map_id: String) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("delete_map_and_cleanup", "Map id is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("delete_map_and_cleanup")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var rpc_result: Dictionary = await _request_json(
		"/rpc/delete_own_map_and_cleanup",
		HTTPClient.METHOD_POST,
		{"target_map_id": clean_map_id},
		"delete_map_and_cleanup",
		PackedStringArray(),
		true
	)
	if bool(rpc_result.get("ok", false)):
		return rpc_result
	# Older databases may not have the RPC yet. Keep the client safe by falling
	# back to the old two-step path, but callers should prefer the RPC because it
	# removes active server ghosts atomically with the map row.
	var delete_result: Dictionary = await delete_map(clean_map_id)
	if bool(delete_result.get("ok", false)):
		return delete_result
	var unpublish_result: Dictionary = await unpublish_map(clean_map_id)
	if bool(unpublish_result.get("ok", false)):
		var delete_after_unpublish: Dictionary = await delete_map(clean_map_id)
		if bool(delete_after_unpublish.get("ok", false)):
			return delete_after_unpublish
	return rpc_result

func unpublish_map(map_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_map_id: String = map_id.strip_edges()
	if clean_map_id.is_empty():
		return _make_error_result("unpublish_map", "Map id is empty.")
	var payload: Dictionary = {
		"is_published": false,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	var endpoint: String = "%s?id=eq.%s" % [maps_endpoint, clean_map_id.uri_encode()]
	var headers := PackedStringArray(["Prefer: return=minimal"])
	if use_service_role:
		return await _request_server_json(endpoint, HTTPClient.METHOD_PATCH, payload, "unpublish_map", headers, true)
	var auth_result: Dictionary = await _ensure_data_api_session("unpublish_map")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json(endpoint, HTTPClient.METHOD_PATCH, payload, "unpublish_map", headers, true)

func register_active_server(server_info: Dictionary, use_service_role: bool = false) -> Dictionary:
	if server_info.is_empty():
		var empty_error: Dictionary = _make_error_result("register_active_server", "Server info is empty.")
		request_failed.emit("register_active_server", str(empty_error.get("error", "")))
		return empty_error
	if use_service_role:
		var server_payload: Dictionary = _pick_dictionary_fields(server_info, [
			"server_key",
			"room_id",
			"player_id",
			"is_host",
			"transport",
			"server_url",
			"ip",
			"port",
			"map_id",
			"map_name",
			"cloud_version_id",
			"host_user_id",
			"host_username",
			"member_user_ids",
			"players_count",
			"max_players",
			"status",
			"last_seen",
			"last_heartbeat",
			"started_at",
			"last_seen_at"
		])
		if not server_payload.has("last_seen_at"):
			server_payload["last_seen_at"] = Time.get_datetime_string_from_system(true, true)
		if not server_payload.has("last_heartbeat"):
			server_payload["last_heartbeat"] = Time.get_datetime_string_from_system(true, true)
		if not server_payload.has("status"):
			server_payload["status"] = "active"
		var server_response: Dictionary = await _request_server_json(
			"%s?on_conflict=server_key" % servers_endpoint,
			HTTPClient.METHOD_POST,
			server_payload,
			"register_active_server",
			PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"])
		)
		if bool(server_response.get("ok", false)):
			active_server_registered.emit(server_response)
		return server_response

	var ensured_profile: Dictionary = await authenticate_or_create_profile(str(server_info.get("host_username", get_current_username())))
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var payload: Dictionary = _pick_dictionary_fields(server_info, [
		"server_key",
		"room_id",
		"player_id",
		"is_host",
		"transport",
		"server_url",
		"ip",
		"port",
		"map_id",
		"map_name",
		"cloud_version_id",
		"host_user_id",
		"host_username",
		"member_user_ids",
		"players_count",
		"max_players",
		"status",
		"last_seen",
		"last_heartbeat",
		"started_at",
		"last_seen_at"
	])
	payload["host_user_id"] = _auth_user_id
	payload["host_username"] = str(ensured_profile.get("username", get_current_username())).strip_edges()
	payload["last_seen_at"] = Time.get_datetime_string_from_system(true, true)
	payload["last_heartbeat"] = Time.get_datetime_string_from_system(true, true)
	payload["status"] = str(payload.get("status", "active")).strip_edges()
	if not payload.has("players_count"):
		payload["players_count"] = int(payload.get("player_count", 0))
	if not payload.has("server_key"):
		payload["server_key"] = "%s:%d:%s" % [
			str(payload.get("ip", "")),
			int(payload.get("port", 0)),
			_auth_user_id
		]

	var response: Dictionary = await _request_json(
		"%s?on_conflict=server_key" % servers_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		"register_active_server",
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)
	if bool(response.get("ok", false)):
		active_server_registered.emit(response)
	return response

func delete_active_server(server_key: String, use_service_role: bool = false) -> Dictionary:
	var clean_key: String = server_key.strip_edges()
	if clean_key.is_empty():
		return _make_error_result("delete_active_server", "Server key is empty.")
	if use_service_role:
		return await _request_server_json(
			"%s?server_key=eq.%s" % [servers_endpoint, clean_key.uri_encode()],
			HTTPClient.METHOD_DELETE,
			null,
			"delete_active_server",
			PackedStringArray(["Prefer: return=minimal"]),
			true
		)
	var auth_result: Dictionary = await _ensure_data_api_session("delete_active_server")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json(
		"%s?server_key=eq.%s" % [servers_endpoint, clean_key.uri_encode()],
		HTTPClient.METHOD_DELETE,
		null,
		"delete_active_server",
		PackedStringArray(["Prefer: return=minimal"]),
		true
	)

func fetch_active_servers(map_filter: String = "", limit: int = 64, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS, attempts: int = HTTP_READ_RETRY_ATTEMPTS) -> Dictionary:
	var endpoint: String = "%s?select=server_key,room_id,server_url,ip,port,transport,map_id,map_name,cloud_version_id,host_user_id,host_username,member_user_ids,players_count,max_players,last_seen,last_seen_at,status,is_host&status=eq.active&is_host=eq.true&order=players_count.desc.nullslast,last_seen_at.desc&limit=%d" % [servers_endpoint, maxi(limit, 1)]
	var clean_filter: String = map_filter.strip_edges()
	if not clean_filter.is_empty():
		var encoded_filter: String = clean_filter.uri_encode()
		endpoint += "&or=(map_id.eq.%s,map_name.eq.%s)" % [encoded_filter, encoded_filter]

	var response: Dictionary = await _request_json_with_retries(endpoint, HTTPClient.METHOD_GET, null, "fetch_active_servers", PackedStringArray(), false, timeout_seconds, attempts)
	if bool(response.get("ok", false)):
		var servers: Array = _filter_fresh_active_servers(_extract_array_payload(response.get("data", [])))
		response["data"] = servers
		active_servers_fetched.emit(servers)
	return response

func find_active_server_for_member_user(user_id: String, freshness_window_seconds: int = 15, use_service_role: bool = false) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return {
			"ok": true,
			"endpoint": "find_active_server_for_member_user",
			"status": 200,
			"data": {},
			"rows": []
		}
	var safe_window_seconds: int = maxi(freshness_window_seconds, 1)
	var endpoint: String = "%s?select=server_key,room_id,server_url,host_user_id,host_username,member_user_ids,last_seen,last_seen_at,status&status=eq.active&is_host=eq.true&member_user_ids=cs.%s&order=last_seen.desc.nullslast,last_seen_at.desc&limit=8" % [
		servers_endpoint,
		("{%s}" % clean_user_id).uri_encode()
	]
	var min_last_seen: int = int(Time.get_unix_time_from_system()) - safe_window_seconds
	endpoint += "&last_seen=gte.%d" % min_last_seen
	var response: Dictionary = {}
	if use_service_role:
		response = await _request_server_json(endpoint, HTTPClient.METHOD_GET, null, "find_active_server_for_member_user", PackedStringArray(), true)
	else:
		var auth_result: Dictionary = await _ensure_data_api_session("find_active_server_for_member_user")
		if not bool(auth_result.get("ok", false)):
			return auth_result
		response = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "find_active_server_for_member_user", PackedStringArray(), true)
	if not bool(response.get("ok", false)):
		return response
	var matched_rows: Array = []
	for row_variant in _extract_array_payload(response.get("data", [])):
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant
		if not _is_server_record_fresh_within_window(row, safe_window_seconds):
			continue
		matched_rows.append(row.duplicate(true))
	return {
		"ok": true,
		"endpoint": "find_active_server_for_member_user",
		"status": 200,
		"data": matched_rows[0] if not matched_rows.is_empty() else {},
		"rows": matched_rows
	}

func fetch_catalog_items() -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("fetch_catalog_items")
	if not bool(auth_result.get("ok", false)): return auth_result
	var endpoint: String = "%s?select=id,item_id,name,category,asset_type,thumbnail,color&order=category.asc,name.asc&limit=200" % catalog_endpoint
	return await _request_json(endpoint, HTTPClient.METHOD_GET, null, "fetch_catalog_items", PackedStringArray(), true)

func publish_model_asset(model_data: Dictionary, model_name: String, metadata: Dictionary = {}) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("publish_model_asset")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var payload: Dictionary = metadata.duplicate(true)
	payload["name"] = model_name.strip_edges()
	payload["data"] = _json_safe_value(model_data)
	if not payload.has("id"):
		payload["id"] = str(model_data.get("cloud_model_id", model_data.get("draft_id", ""))).strip_edges()
	return await _request_json_with_retries(
		"/rpc/publish_model_asset",
		HTTPClient.METHOD_POST,
		payload,
		"publish_model_asset",
		PackedStringArray(),
		true,
		HTTP_UPLOAD_TIMEOUT_SECONDS,
		HTTP_READ_RETRY_ATTEMPTS
	)

# PRACTICE SCREENSHOT: Avatar catalog publishing flow - sends clothes/accessories to the backend catalog.
func publish_avatar_item(item_data: Dictionary, item_name: String, metadata: Dictionary = {}) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("publish_avatar_item")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var payload: Dictionary = metadata.duplicate(true)
	payload["name"] = item_name.strip_edges()
	for key in item_data.keys():
		if not payload.has(key):
			payload[key] = _json_safe_value(item_data[key])
	if str(payload.get("id", "")).is_empty():
		payload["id"] = Crypto.new().generate_random_bytes(16).hex_encode()
		item_data["id"] = payload["id"]
		metadata["id"] = payload["id"]
	var permission: Dictionary = await _confirm_catalog_publication(payload)
	if not bool(permission.get("ok", false)): return permission
	payload["publication_fee"] = int(permission.get("fee", 0))
	return await _request_json_with_retries(
		"/rpc/publish_avatar_item",
		HTTPClient.METHOD_POST,
		payload,
		"publish_avatar_item",
		PackedStringArray(),
		true,
		HTTP_UPLOAD_TIMEOUT_SECONDS,
		HTTP_READ_RETRY_ATTEMPTS
	)

func fetch_marketplace_models(limit: int = 96, include_private: bool = true, owner_only: bool = false) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("fetch_marketplace_models")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/fetch_marketplace_models",
		HTTPClient.METHOD_POST,
		{"limit": limit, "include_private": include_private, "owner_only": owner_only},
		"fetch_marketplace_models",
		PackedStringArray(),
		true,
		HTTP_REQUEST_TIMEOUT_SECONDS,
		HTTP_READ_RETRY_ATTEMPTS
	)

# PRACTICE SCREENSHOT: Avatar marketplace loading flow - downloads public and owner-visible catalog items.
func fetch_avatar_marketplace_items(limit: int = 96, include_private: bool = true, owner_only: bool = false) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("fetch_avatar_marketplace_items")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/fetch_avatar_marketplace_items",
		HTTPClient.METHOD_POST,
		{"limit": limit, "include_private": include_private, "owner_only": owner_only},
		"fetch_avatar_marketplace_items",
		PackedStringArray(),
		true,
		HTTP_REQUEST_TIMEOUT_SECONDS,
		HTTP_READ_RETRY_ATTEMPTS
	)

# PRACTICE SCREENSHOT: My creations loading flow - requests maps, models and avatar items created by the signed-in user.
func fetch_my_creations() -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("fetch_my_creations")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries("/rpc/fetch_my_creations", HTTPClient.METHOD_POST, {}, "fetch_my_creations", PackedStringArray(), true)

func request_studio_ai(prompt: String, context: Dictionary = {}) -> Dictionary:
	var clean_prompt := prompt.strip_edges()
	if clean_prompt.length() < 3:
		return _make_error_result("studio_ai", "Describe what Bobux AI should create.")
	if clean_prompt.length() > 4000:
		return _make_error_result("studio_ai", "The Studio AI request is too long (maximum 4000 characters).")
	var auth_result: Dictionary = await _ensure_data_api_session("studio_ai")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var response: Dictionary = await _request_authenticated_auth_json(
		"/studio/assistant",
		HTTPClient.METHOD_POST,
		{"prompt": clean_prompt, "context": _json_safe_value(context)},
		"studio_ai",
		55.0
	)
	return _normalize_studio_ai_response(response)


func fetch_boblox_wallet() -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("boblox_wallet")
	if not bool(auth_result.get("ok", false)): return auth_result
	return await _request_authenticated_auth_json("/boblox/wallet", HTTPClient.METHOD_GET, null, "boblox_wallet", 12.0)

func claim_founder_reward() -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("founder_reward")
	if not bool(auth_result.get("ok", false)): return auth_result
	return await _request_authenticated_auth_json("/boblox/founder-reward/claim", HTTPClient.METHOD_POST, {}, "founder_reward", 12.0)

func fetch_boblox_catalog() -> Dictionary:
	return await _request_auth_json("/boblox/catalog", HTTPClient.METHOD_GET, null, "boblox_catalog", 12.0)

func create_boblox_checkout(product_id: String, request_key: String, receipt_email: String) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("boblox_checkout")
	if not bool(auth_result.get("ok", false)): return auth_result
	return await _request_authenticated_auth_json("/boblox/checkout", HTTPClient.METHOD_POST,
		{"product_id": product_id, "request_key": request_key, "email": receipt_email}, "boblox_checkout", 25.0)

func refresh_boblox_order(order_id: String) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("boblox_order")
	if not bool(auth_result.get("ok", false)): return auth_result
	return await _request_authenticated_auth_json("/boblox/orders/%s/refresh" % order_id.uri_encode(), HTTPClient.METHOD_POST, {}, "boblox_order", 25.0)

func _normalize_studio_ai_response(response: Dictionary) -> Dictionary:
	if not bool(response.get("ok", false)):
		return response
	var normalized: Dictionary = response.duplicate(true)
	var payload: Variant = response.get("data", response)
	for _depth in range(4):
		if payload is String:
			var parsed_payload: Variant = JSON.parse_string((payload as String).strip_edges())
			if parsed_payload == null:
				break
			payload = parsed_payload
		if not payload is Dictionary:
			break
		var payload_dictionary := payload as Dictionary
		if payload_dictionary.has("actions") or payload_dictionary.has("message"):
			break
		var nested_payload: Variant = null
		for key in ["data", "body", "result"]:
			if payload_dictionary.has(key):
				nested_payload = payload_dictionary.get(key)
				break
		if nested_payload == null or nested_payload == payload:
			break
		payload = nested_payload
	if not payload is Dictionary:
		return normalized
	var studio_payload := payload as Dictionary
	for key_variant in studio_payload.keys():
		normalized[key_variant] = studio_payload[key_variant]
	normalized["ok"] = bool(response.get("ok", false)) and bool(studio_payload.get("ok", true))
	return normalized

func like_catalog_asset(target_type: String, target_id: String) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("like_catalog_asset")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/like_catalog_asset",
		HTTPClient.METHOD_POST,
		{"target_type": target_type, "target_id": target_id},
		"like_catalog_asset",
		PackedStringArray(),
		true
	)

func update_catalog_asset_visibility(target_type: String, target_id: String, visibility: String) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("update_catalog_asset_visibility")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var payload := {"target_type": target_type, "target_id": target_id, "visibility": visibility}
	if target_type == "avatar_item" and visibility == "public":
		var permission: Dictionary = await _confirm_catalog_publication({"id": target_id, "visibility": visibility})
		if not bool(permission.get("ok", false)): return permission
		payload["publication_fee"] = int(permission.get("fee", 0))
	return await _request_json_with_retries(
		"/rpc/update_catalog_asset_visibility",
		HTTPClient.METHOD_POST,
		payload,
		"update_catalog_asset_visibility",
		PackedStringArray(),
		true
	)

func delete_avatar_item(item_id: String) -> Dictionary:
	var clean_item_id := item_id.strip_edges()
	if clean_item_id.is_empty():
		return _make_error_result("delete_avatar_item", "Avatar item id is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("delete_avatar_item")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/delete_avatar_item",
		HTTPClient.METHOD_POST,
		{"item_id": clean_item_id},
		"delete_avatar_item",
		PackedStringArray(),
		true
	)

func delete_model_asset(model_id: String) -> Dictionary:
	var clean_model_id := model_id.strip_edges()
	if clean_model_id.is_empty():
		return _make_error_result("delete_model_asset", "Model id is empty.")
	var auth_result: Dictionary = await _ensure_data_api_session("delete_model_asset")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/delete_model_asset",
		HTTPClient.METHOD_POST,
		{"model_id": clean_model_id},
		"delete_model_asset",
		PackedStringArray(),
		true
	)

func get_catalog_item(item_id: String, item_type: String = "avatar_item") -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("get_catalog_item")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	return await _request_json_with_retries(
		"/rpc/get_catalog_item",
		HTTPClient.METHOD_POST,
		{"item_id": item_id, "item_type": item_type},
		"get_catalog_item",
		PackedStringArray(),
		true
	)

func update_profile_avatar(avatar_data: Dictionary, inventory: Array) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("update_profile_avatar")
	if not bool(auth_result.get("ok", false)): return auth_result
	var current_username = get_current_username()
	if current_username.strip_edges().is_empty(): return _make_error_result("update_profile_avatar", "Must be logged in to save avatar data.")
	var payload: Dictionary = {
		"id": _auth_user_id,
		"username": current_username,
		"avatar_data": _json_safe_value(avatar_data),
		"inventory_items": inventory,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	return await _request_json_with_retries("%s?on_conflict=id" % profiles_endpoint, HTTPClient.METHOD_POST, payload, "update_profile_avatar", PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]), true)

func update_avatar_outfit(outfit_data: Dictionary) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("update_avatar_outfit")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	if _auth_user_id.strip_edges().is_empty():
		return _make_error_result("update_avatar_outfit", "Must be logged in to save avatar outfit data.")
	var payload: Dictionary = {
		"user_id": _auth_user_id,
		"head_color": str(outfit_data.get("head_color", "#F5CC33")).strip_edges(),
		"torso_color": str(outfit_data.get("torso_color", "#0D66B3")).strip_edges(),
		"left_arm_color": str(outfit_data.get("left_arm_color", "#F5CC33")).strip_edges(),
		"right_arm_color": str(outfit_data.get("right_arm_color", "#F5CC33")).strip_edges(),
		"left_leg_color": str(outfit_data.get("left_leg_color", "#A6CC33")).strip_edges(),
		"right_leg_color": str(outfit_data.get("right_leg_color", "#A6CC33")).strip_edges(),
		"equipped_items": outfit_data.get("equipped_items", []),
		"body_type": str(outfit_data.get("body_type", "R6")).strip_edges(),
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	for texture_key in AVATAR_OUTFIT_TEXTURE_KEYS:
		var fallback_texture := ""
		if texture_key == "face_texture_path":
			fallback_texture = GameState.DEFAULT_FACE_TEXTURE_PATH
		elif texture_key == "chest_badge_texture_path":
			fallback_texture = GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH
		payload[texture_key] = str(outfit_data.get(texture_key, fallback_texture)).strip_edges()
	for list_key in AVATAR_OUTFIT_SAVED_TEXTURE_LIST_KEYS:
		var saved_paths: Array = []
		var raw_saved_paths: Variant = outfit_data.get(list_key, [])
		if raw_saved_paths is Array:
			saved_paths = (raw_saved_paths as Array).duplicate(true)
		payload[list_key] = saved_paths
	return await _request_json_with_retries(
		"%s?on_conflict=user_id" % avatar_outfits_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		"update_avatar_outfit",
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)

# FIX Issue-4: Create a new map entry in the database so locally created
# places are also visible in the cloud game list.
func create_new_world(map_name: String, description: String = "") -> Dictionary:
	var ensured_profile: Dictionary = await _ensure_light_profile_context("create_new_world")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var clean_name: String = map_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Untitled Place"
	var map_id: String = clean_name.to_lower().replace(" ", "_") + "_" + _auth_user_id.left(8) + "_" + str(int(Time.get_unix_time_from_system()))
	var payload: Dictionary = {
		"id": map_id,
		"name": clean_name,
		"owner_id": _auth_user_id,
		"owner_name": str(ensured_profile.get("username", get_current_username())).strip_edges(),
		"description": description.strip_edges(),
		"data": {},
		"is_published": false,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	return await _request_json(
		"%s?on_conflict=id" % maps_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		"create_new_world",
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)

func load_avatar_outfit(user_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("load_avatar_outfit", "Avatar outfit user id is empty.")
	var endpoint: String = "%s?select=*&user_id=eq.%s&limit=1" % [avatar_outfits_endpoint, clean_user_id.uri_encode()]
	var response: Dictionary = {}
	if use_service_role:
		response = await _request_server_json(endpoint, HTTPClient.METHOD_GET, null, "load_avatar_outfit", PackedStringArray(), true, HTTP_AVATAR_PROFILE_TIMEOUT_SECONDS)
	else:
		var auth_result: Dictionary = await _ensure_data_api_session("load_avatar_outfit")
		if not bool(auth_result.get("ok", false)):
			return auth_result
		response = await _request_json_with_retries(endpoint, HTTPClient.METHOD_GET, null, "load_avatar_outfit", PackedStringArray(), true, HTTP_AVATAR_PROFILE_TIMEOUT_SECONDS, 3)
	if not bool(response.get("ok", false)):
		return response
	var rows: Array = _extract_array_payload(response.get("data", []))
	response["data"] = rows[0] if not rows.is_empty() and rows[0] is Dictionary else {}
	return response

func load_player_profile(user_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("load_player_profile", "Player user id is empty.")
	var endpoint: String = "%s?select=*&id=eq.%s&limit=1" % [profiles_endpoint, clean_user_id.uri_encode()]
	var response: Dictionary = {}
	if use_service_role:
		response = await _request_server_json(endpoint, HTTPClient.METHOD_GET, null, "load_player_profile", PackedStringArray(), true, HTTP_AVATAR_PROFILE_TIMEOUT_SECONDS)
	else:
		var auth_result: Dictionary = await _ensure_data_api_session("load_player_profile")
		if not bool(auth_result.get("ok", false)):
			return auth_result
		response = await _request_json_with_retries(endpoint, HTTPClient.METHOD_GET, null, "load_player_profile", PackedStringArray(), true, HTTP_AVATAR_PROFILE_TIMEOUT_SECONDS, 3)
	if not bool(response.get("ok", false)):
		return response
	var rows: Array = _extract_array_payload(response.get("data", []))
	var profile_data: Dictionary = (rows[0] as Dictionary).duplicate(true) if not rows.is_empty() and rows[0] is Dictionary else {}
	if not profile_data.is_empty():
		var outfit_result: Dictionary = await load_avatar_outfit(clean_user_id, use_service_role)
		if bool(outfit_result.get("ok", false)) and outfit_result.get("data", {}) is Dictionary:
			var outfit: Dictionary = (outfit_result.get("data", {}) as Dictionary).duplicate(true)
			profile_data["avatar_outfit"] = outfit
			profile_data["avatar_data"] = _merge_avatar_outfit_into_session_avatar_data(
				profile_data.get("avatar_data", {}) if profile_data.get("avatar_data", {}) is Dictionary else {},
				outfit
			)
	response["data"] = profile_data
	return response

func search_profiles(partial_username: String, limit: int = 10) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session("search_profiles")
	if not bool(auth_result.get("ok", false)):
		return auth_result
	var clean_query: String = partial_username.strip_edges()
	if clean_query.is_empty():
		var empty_result := {
			"ok": true,
			"endpoint": "search_profiles",
			"status": 200,
			"data": []
		}
		friend_search_completed.emit([])
		return empty_result

	var endpoint: String = "%s?select=id,username,status,current_game,current_server_host,current_server_ip,current_server_port,updated_at&username=ilike.*%s*&limit=%d" % [
		profiles_endpoint,
		clean_query.uri_encode(),
		maxi(limit, 1)
	]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "search_profiles", PackedStringArray(), true)
	if bool(response.get("ok", false)):
		var profiles: Array = _extract_array_payload(response.get("data", []))
		friend_search_completed.emit(profiles)
	return response

func add_friend(user_id: String) -> Dictionary:
	return await send_friend_request(user_id)

func send_friend_request(user_id: String, username: String = "") -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		var empty_error: Dictionary = _make_error_result("send_friend_request", "Friend user id is empty.")
		request_failed.emit("send_friend_request", str(empty_error.get("error", "")))
		return empty_error
	if clean_user_id == _auth_user_id:
		return _make_error_result("send_friend_request", "You cannot add yourself as a friend.")

	var ensured_profile: Dictionary = await _ensure_light_profile_context("send_friend_request")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var payload: Dictionary = {"target_user": clean_user_id}
	var clean_username: String = username.strip_edges()
	if not clean_username.is_empty():
		payload["target_username"] = clean_username
	var response: Dictionary = await _request_json_with_retries(
		"/rpc/send_friend_request",
		HTTPClient.METHOD_POST,
		payload,
		"send_friend_request",
		PackedStringArray(),
		true
	)
	if bool(response.get("ok", false)):
		friend_request_sent.emit(response)
	return response

func get_incoming_friend_requests() -> Dictionary:
	var ensured_profile: Dictionary = await _ensure_light_profile_context("get_incoming_friend_requests")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var requests_response: Dictionary = await _request_json_with_retries(
		"/rpc/get_incoming_friend_requests",
		HTTPClient.METHOD_POST,
		{},
		"get_incoming_friend_requests",
		PackedStringArray(),
		true,
		HTTP_SOCIAL_TIMEOUT_SECONDS,
		1
	)
	if not bool(requests_response.get("ok", false)):
		return requests_response
	var requests: Array = _dedupe_friend_requests_by_sender(_extract_array_payload(requests_response.get("data", [])))
	requests = _dedupe_friend_requests_by_sender(requests)
	friend_requests_received.emit(requests)
	return {
		"ok": true,
		"endpoint": "get_incoming_friend_requests",
		"status": 200,
		"data": requests
	}

func accept_friend_request(from_user_id: String) -> Dictionary:
	var clean_from_user_id: String = from_user_id.strip_edges()
	if clean_from_user_id.is_empty():
		return _make_error_result("accept_friend_request", "Request sender id is empty.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("accept_friend_request")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	return await _request_json_with_retries(
		"/rpc/accept_friend_request",
		HTTPClient.METHOD_POST,
		{"from_user": clean_from_user_id},
		"accept_friend_request",
		PackedStringArray(),
		true
	)

func decline_friend_request(from_user_id: String) -> Dictionary:
	var clean_from_user_id: String = from_user_id.strip_edges()
	if clean_from_user_id.is_empty():
		return _make_error_result("decline_friend_request", "Request sender id is empty.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("decline_friend_request")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	return await _request_json_with_retries(
		"/rpc/decline_friend_request",
		HTTPClient.METHOD_POST,
		{"from_user": clean_from_user_id},
		"decline_friend_request",
		PackedStringArray(),
		true
	)

func cancel_friend_request(to_user_id: String) -> Dictionary:
	var clean_to_user_id: String = to_user_id.strip_edges()
	if clean_to_user_id.is_empty():
		return _make_error_result("cancel_friend_request", "Request target id is empty.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("cancel_friend_request")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	return await _request_json_with_retries(
		"/rpc/cancel_friend_request",
		HTTPClient.METHOD_POST,
		{"to_user": clean_to_user_id},
		"cancel_friend_request",
		PackedStringArray(),
		true
	)

func get_outgoing_friend_requests() -> Dictionary:
	var ensured_profile: Dictionary = await _ensure_light_profile_context("get_outgoing_friend_requests")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var requests_response: Dictionary = await _request_json_with_retries(
		"/rpc/get_outgoing_friend_requests",
		HTTPClient.METHOD_POST,
		{},
		"get_outgoing_friend_requests",
		PackedStringArray(),
		true,
		HTTP_SOCIAL_TIMEOUT_SECONDS,
		1
	)
	if not bool(requests_response.get("ok", false)):
		return requests_response
	var requests: Array = _dedupe_friend_requests_by_target(_extract_array_payload(requests_response.get("data", [])))
	return {
		"ok": true,
		"endpoint": "get_outgoing_friend_requests",
		"status": 200,
		"data": requests
	}

func get_friends_list() -> Dictionary:
	var ensured_profile: Dictionary = await _ensure_light_profile_context("get_friends_list")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var friends_response: Dictionary = await _request_json_with_retries(
		"/rpc/get_friends_list",
		HTTPClient.METHOD_POST,
		{},
		"get_friends_list",
		PackedStringArray(),
		true,
		HTTP_SOCIAL_TIMEOUT_SECONDS,
		1
	)
	if not bool(friends_response.get("ok", false)):
		return friends_response
	var profiles: Array = _extract_array_payload(friends_response.get("data", []))
	profiles = _dedupe_profiles_by_username(profiles)
	friends_list_received.emit(profiles)
	return {
		"ok": true,
		"endpoint": "get_friends_list",
		"status": 200,
		"data": profiles
	}

func follow_user(user_id: String) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("follow_user", "Target user id is empty.")
	if clean_user_id == _auth_user_id:
		return _make_error_result("follow_user", "You cannot follow yourself.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("follow_user")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var payload: Dictionary = {
		"follower_id": _auth_user_id,
		"following_id": clean_user_id,
		"created_at": Time.get_datetime_string_from_system(true, true)
	}
	return await _request_json(
		"%s?on_conflict=follower_id,following_id" % follows_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		"follow_user",
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)

func unfollow_user(user_id: String) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("unfollow_user", "Target user id is empty.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("unfollow_user")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	return await _request_json(
		"%s?follower_id=eq.%s&following_id=eq.%s" % [follows_endpoint, _auth_user_id.uri_encode(), clean_user_id.uri_encode()],
		HTTPClient.METHOD_DELETE,
		null,
		"unfollow_user",
		PackedStringArray(["Prefer: return=minimal"]),
		true
	)

func get_following_list(user_id: String = "") -> Dictionary:
	var target_user_id: String = user_id.strip_edges()
	var ensured_profile: Dictionary = await _ensure_light_profile_context("get_following_list")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	if target_user_id.is_empty():
		target_user_id = _auth_user_id
	var endpoint: String = "%s?select=follower_id,following_id,created_at&follower_id=eq.%s&order=created_at.desc" % [
		follows_endpoint,
		target_user_id.uri_encode()
	]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "get_following_list", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	if not bool(response.get("ok", false)):
		return response
	var rows: Array = _extract_array_payload(response.get("data", []))
	var profile_ids: Array[String] = []
	for row_variant in rows:
		if not (row_variant is Dictionary):
			continue
		var following_id: String = str((row_variant as Dictionary).get("following_id", "")).strip_edges()
		if not following_id.is_empty() and not profile_ids.has(following_id):
			profile_ids.append(following_id)
	return await _profiles_result_from_ids(profile_ids, "get_following_profiles")

func get_followers_list(user_id: String = "") -> Dictionary:
	var target_user_id: String = user_id.strip_edges()
	var ensured_profile: Dictionary = await _ensure_light_profile_context("get_followers_list")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	if target_user_id.is_empty():
		target_user_id = _auth_user_id
	var endpoint: String = "%s?select=follower_id,following_id,created_at&following_id=eq.%s&order=created_at.desc" % [
		follows_endpoint,
		target_user_id.uri_encode()
	]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "get_followers_list", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	if not bool(response.get("ok", false)):
		return response
	var rows: Array = _extract_array_payload(response.get("data", []))
	var profile_ids: Array[String] = []
	for row_variant in rows:
		if not (row_variant is Dictionary):
			continue
		var follower_id: String = str((row_variant as Dictionary).get("follower_id", "")).strip_edges()
		if not follower_id.is_empty() and not profile_ids.has(follower_id):
			profile_ids.append(follower_id)
	return await _profiles_result_from_ids(profile_ids, "get_followers_profiles")

func get_follow_counts_for_user(user_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("get_follow_counts_for_user", "User id is empty.")
	if not use_service_role:
		var auth_result: Dictionary = await _ensure_data_api_session("get_follow_counts_for_user")
		if not bool(auth_result.get("ok", false)):
			return auth_result
	var rpc_payload: Dictionary = {"target_user": clean_user_id}
	var rpc_response: Dictionary = {}
	if use_service_role:
		rpc_response = await _request_server_json("/rpc/get_follow_counts", HTTPClient.METHOD_POST, rpc_payload, "get_follow_counts_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	else:
		rpc_response = await _request_json("/rpc/get_follow_counts", HTTPClient.METHOD_POST, rpc_payload, "get_follow_counts_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	if bool(rpc_response.get("ok", false)):
		if rpc_response.get("data", {}) is Dictionary:
			return rpc_response
		if rpc_response.get("data", []) is Array and not _extract_array_payload(rpc_response.get("data", [])).is_empty():
			rpc_response["data"] = _extract_array_payload(rpc_response.get("data", []))[0]
			return rpc_response

	var followers_result: Dictionary = await get_followers_list(clean_user_id)
	var following_result: Dictionary = await get_following_list(clean_user_id)
	return {
		"ok": true,
		"endpoint": "get_follow_counts_for_user",
		"status": 200,
		"data": {
			"followers_count": _extract_array_payload(followers_result.get("data", [])).size() if bool(followers_result.get("ok", false)) else 0,
			"following_count": _extract_array_payload(following_result.get("data", [])).size() if bool(following_result.get("ok", false)) else 0
		}
	}

func count_friends_for_user(user_id: String, use_service_role: bool = false) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("count_friends_for_user", "User id is empty.")
	if not use_service_role:
		var auth_result: Dictionary = await _ensure_data_api_session("count_friends_for_user")
		if not bool(auth_result.get("ok", false)):
			return auth_result
	var rpc_payload: Dictionary = {"target_user": clean_user_id}
	var rpc_response: Dictionary = {}
	if use_service_role:
		rpc_response = await _request_server_json("/rpc/get_friend_count", HTTPClient.METHOD_POST, rpc_payload, "count_friends_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	else:
		rpc_response = await _request_json("/rpc/get_friend_count", HTTPClient.METHOD_POST, rpc_payload, "count_friends_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	if bool(rpc_response.get("ok", false)):
		rpc_response["count"] = int(rpc_response.get("data", 0))
		return rpc_response

	# Backward-compatible fallback for older Bobux API builds. Server RPC is the
	# release-safe path because it can count any profile, not only the caller.
	var endpoint: String = "%s?select=user1,user2,status&status=eq.accepted&or=(user1.eq.%s,user2.eq.%s)" % [
		friendships_endpoint,
		clean_user_id.uri_encode(),
		clean_user_id.uri_encode()
	]
	var response: Dictionary = {}
	if use_service_role:
		response = await _request_server_json(endpoint, HTTPClient.METHOD_GET, null, "count_friends_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	else:
		response = await _request_json(endpoint, HTTPClient.METHOD_GET, null, "count_friends_for_user", PackedStringArray(), true, HTTP_SOCIAL_TIMEOUT_SECONDS)
	if bool(response.get("ok", false)):
		response["count"] = _extract_array_payload(response.get("data", [])).size()
	return response

func remove_friend(user_id: String) -> Dictionary:
	var clean_user_id: String = user_id.strip_edges()
	if clean_user_id.is_empty():
		return _make_error_result("remove_friend", "Friend user id is empty.")
	var ensured_profile: Dictionary = await _ensure_light_profile_context("remove_friend")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var delete_result: Dictionary = await _delete_friendship_rows_between_users(_auth_user_id, clean_user_id, "remove_friend")
	await _delete_friend_request_rows_between_users(_auth_user_id, clean_user_id, "remove_friend_cleanup_requests")
	if bool(delete_result.get("ok", false)):
		return delete_result
	if int(delete_result.get("status", 0)) == 404:
		return {
			"ok": true,
			"endpoint": "remove_friend",
			"status": 200,
			"data": []
		}
	return delete_result

func update_profile_presence(status: String, current_game: String = "", server_info: Dictionary = {}) -> Dictionary:
	var ensured_profile: Dictionary = await _ensure_light_profile_context("update_profile_presence")
	if not bool(ensured_profile.get("ok", false)):
		return ensured_profile
	var payload: Dictionary = {
		"id": _auth_user_id,
		"username": str(ensured_profile.get("username", get_current_username())),
		"status": status.strip_edges(),
		"current_game": current_game.strip_edges(),
		"current_server_host": str(server_info.get("host_username", "")).strip_edges(),
		"current_server_ip": str(server_info.get("server_url", server_info.get("ip", ""))).strip_edges(),
		"current_server_port": int(server_info.get("port", 0)),
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	var response: Dictionary = await _request_json(
		"%s?on_conflict=id" % profiles_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		"update_profile_presence",
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true,
		HTTP_PRESENCE_TIMEOUT_SECONDS
	)
	if bool(response.get("ok", false)):
		presence_updated.emit(response)
	return response

func is_configured() -> bool:
	return not base_url.strip_edges().is_empty() and not project_url.strip_edges().is_empty() and not api_key.strip_edges().is_empty()

func _ensure_data_api_session(request_name: String) -> Dictionary:
	var auth_result: Dictionary = await ensure_authenticated_session()
	if bool(auth_result.get("ok", false)):
		return auth_result
	request_failed.emit(request_name, str(auth_result.get("error", "Authentication failed.")))
	return auth_result

func _ensure_light_profile_context(request_name: String) -> Dictionary:
	var auth_result: Dictionary = await _ensure_data_api_session(request_name)
	if not bool(auth_result.get("ok", false)):
		return auth_result
	if _auth_user_id.strip_edges().is_empty():
		return _make_error_result(request_name, "Must be logged in to use this feature.")
	var username := get_current_username().strip_edges()
	if username.is_empty():
		username = "Player"
	return {
		"ok": true,
		"endpoint": request_name,
		"status": 200,
		"user_id": _auth_user_id,
		"username": username
	}

func _sign_in_anonymously() -> Dictionary:
	var response: Dictionary = await _request_auth_json(
		AUTH_SIGNUP_ENDPOINT,
		HTTPClient.METHOD_POST,
		{
			"data": {
				"source": "godot",
				"platform": OS.get_name()
			}
		},
		"sign_in_anonymously"
	)
	if not bool(response.get("ok", false)):
		if _extract_auth_error_code(response.get("data", null)) == ANONYMOUS_PROVIDER_DISABLED_CODE:
			response["error"] = "Bobux account service rejected anonymous sign-in for this build."
		return response
	return _apply_auth_response_payload(response, "sign_in_anonymously")

func _refresh_authenticated_session() -> Dictionary:
	if _auth_refresh_token.strip_edges().is_empty():
		return _make_error_result("refresh_authenticated_session", "No refresh token is stored.")
	var response: Dictionary = await _request_auth_json(
		"%s?grant_type=refresh_token" % AUTH_TOKEN_ENDPOINT,
		HTTPClient.METHOD_POST,
		{
			"refresh_token": _auth_refresh_token
		},
		"refresh_authenticated_session"
	)
	if not bool(response.get("ok", false)):
		return response
	return _apply_auth_response_payload(response, "refresh_authenticated_session")

func _apply_auth_response_payload(response: Dictionary, request_name: String) -> Dictionary:
	var payload: Dictionary = _normalize_auth_payload(response.get("data", {}))
	var access_token: String = str(payload.get("access_token", "")).strip_edges()
	var refresh_token: String = str(payload.get("refresh_token", _auth_refresh_token)).strip_edges()
	var user: Dictionary = payload.get("user", {}) if payload.get("user", {}) is Dictionary else {}
	var user_id: String = str(user.get("id", payload.get("user_id", ""))).strip_edges()
	var expires_at: int = int(payload.get("expires_at", 0))
	var previous_user_id := _auth_user_id
	if expires_at <= 0:
		var expires_in: int = int(payload.get("expires_in", 0))
		if expires_in > 0:
			expires_at = int(Time.get_unix_time_from_system()) + expires_in
	if access_token.is_empty() or refresh_token.is_empty() or user_id.is_empty():
		return _make_error_result(request_name, "Bobux auth response did not contain a complete session.", ERR_PARSE_ERROR, int(response.get("status", 0)), payload)

	_auth_access_token = access_token
	_auth_refresh_token = refresh_token
	_auth_user_id = user_id
	_auth_expires_at = expires_at
	_auth_is_anonymous = bool(user.get("is_anonymous", payload.get("is_anonymous", false)))
	_auth_email = str(user.get("email", "")).strip_edges()
	if previous_user_id != user_id:
		_current_profile_username = ""
	if user.has("user_metadata") and user["user_metadata"] is Dictionary:
		var user_metadata: Dictionary = user["user_metadata"]
		var metadata_username: String = str(user_metadata.get("username", "")).strip_edges()
		if not metadata_username.is_empty():
			_current_profile_username = metadata_username
	_save_auth_session()
	return {
		"ok": true,
		"endpoint": request_name,
		"status": int(response.get("status", 200)),
		"data": get_current_auth_session()
	}

func _upsert_profile_payload(payload: Dictionary, request_name: String) -> Dictionary:
	return await _request_json(
		"%s?on_conflict=id" % profiles_endpoint,
		HTTPClient.METHOD_POST,
		payload,
		request_name,
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)

func _build_profile_payload(username: String) -> Dictionary:
	return {
		"id": _auth_user_id,
		"username": username,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}

func _get_default_session_avatar_data() -> Dictionary:
	return {
		"head": Color(0.96, 0.8, 0.2),
		"torso": Color(0.05, 0.4, 0.7),
		"left_arm": Color(0.96, 0.8, 0.2),
		"right_arm": Color(0.96, 0.8, 0.2),
		"left_leg": Color(0.65, 0.8, 0.2),
		"right_leg": Color(0.65, 0.8, 0.2),
		"face_texture_path": GameState.DEFAULT_FACE_TEXTURE_PATH,
		"chest_badge_texture_path": GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH,
		"shirt_texture_path": "",
		"pants_texture_path": "",
		"saved_shirt_texture_paths": [],
		"saved_pants_texture_paths": [],
		"equipped": []
	}

func _merge_avatar_outfit_into_session_avatar_data(base_avatar_data: Dictionary, avatar_outfit: Dictionary) -> Dictionary:
	var merged_avatar_data: Dictionary = _get_default_session_avatar_data()
	var default_avatar_data: Dictionary = _get_default_session_avatar_data()
	# Step 1: Copy non-color keys from base_avatar_data (equipped list, etc.)
	if base_avatar_data is Dictionary:
		for key_variant in base_avatar_data.keys():
			var avatar_key: String = str(key_variant)
			if AVATAR_OUTFIT_TO_SESSION_KEY_MAP.values().has(avatar_key):
				var default_color: Color = default_avatar_data.get(avatar_key, Color.WHITE) if default_avatar_data.get(avatar_key, Color.WHITE) is Color else Color.WHITE
				merged_avatar_data[avatar_key] = _parse_avatar_color_value(base_avatar_data[key_variant], default_color)
			elif avatar_key == "equipped" and base_avatar_data[key_variant] is Array:
				merged_avatar_data[avatar_key] = (base_avatar_data[key_variant] as Array).duplicate()
			else:
				merged_avatar_data[avatar_key] = base_avatar_data[key_variant]
	# Step 2 (FIX Issue-3b): Avatar outfit colors from the DB now ALWAYS take
	# precedence over profile avatar_data. The avatar_outfits table is the
	# authoritative color source — profile.avatar_data is only a fallback.
	for outfit_key_variant in AVATAR_OUTFIT_TO_SESSION_KEY_MAP.keys():
		var outfit_key: String = str(outfit_key_variant)
		var avatar_key: String = str(AVATAR_OUTFIT_TO_SESSION_KEY_MAP[outfit_key])
		var default_color: Color = default_avatar_data.get(avatar_key, Color.WHITE) if default_avatar_data.get(avatar_key, Color.WHITE) is Color else Color.WHITE
		var fallback_color: Color = _parse_avatar_color_value(merged_avatar_data.get(avatar_key, default_color), default_color)
		if avatar_outfit.has(outfit_key) and not str(avatar_outfit.get(outfit_key, "")).strip_edges().is_empty():
			merged_avatar_data[avatar_key] = _parse_avatar_color_value(avatar_outfit.get(outfit_key, ""), fallback_color)
		else:
			merged_avatar_data[avatar_key] = fallback_color
	for texture_key in AVATAR_OUTFIT_TEXTURE_KEYS:
		if not avatar_outfit.has(texture_key):
			continue
		var texture_value: String = str(avatar_outfit.get(texture_key, "")).strip_edges()
		if texture_value.is_empty() and texture_key == "face_texture_path":
			texture_value = str(default_avatar_data.get(texture_key, ""))
		merged_avatar_data[texture_key] = texture_value
	for list_key in AVATAR_OUTFIT_SAVED_TEXTURE_LIST_KEYS:
		if avatar_outfit.has(list_key) and avatar_outfit.get(list_key, []) is Array:
			merged_avatar_data[list_key] = (avatar_outfit.get(list_key, []) as Array).duplicate(true)
	if avatar_outfit.get("equipped_items", []) is Array:
		var outfit_items := (avatar_outfit.get("equipped_items", []) as Array).duplicate(true)
		merged_avatar_data["equipped"] = outfit_items
		var payloads: Array = []
		for outfit_item in outfit_items:
			if outfit_item is Dictionary:
				payloads.append((outfit_item as Dictionary).duplicate(true))
		if not payloads.is_empty():
			merged_avatar_data["equipped_avatar_item_payloads"] = payloads
	if avatar_outfit.get("equipped_avatar_item_payloads", []) is Array:
		var direct_payloads := (avatar_outfit.get("equipped_avatar_item_payloads", []) as Array).duplicate(true)
		if not direct_payloads.is_empty():
			merged_avatar_data["equipped_avatar_item_payloads"] = direct_payloads
	return merged_avatar_data

func _parse_avatar_color_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var color_dict: Dictionary = value if value is Dictionary else {}
	if color_dict.has("r") and color_dict.has("g") and color_dict.has("b"):
		return Color(
			float(color_dict.get("r", fallback.r)),
			float(color_dict.get("g", fallback.g)),
			float(color_dict.get("b", fallback.b)),
			float(color_dict.get("a", fallback.a))
		)
	var raw_value: String = str(value).strip_edges()
	if raw_value.is_empty():
		return fallback
	var hex_value: String = raw_value.trim_prefix("#")
	if hex_value.length() != 6 and hex_value.length() != 8:
		return fallback
	var matcher := RegEx.new()
	if matcher.compile("^[0-9a-fA-F]+$") != OK or matcher.search(hex_value) == null:
		return fallback
	var red: float = float(hex_value.substr(0, 2).hex_to_int()) / 255.0
	var green: float = float(hex_value.substr(2, 2).hex_to_int()) / 255.0
	var blue: float = float(hex_value.substr(4, 2).hex_to_int()) / 255.0
	var alpha: float = fallback.a
	if hex_value.length() == 8:
		alpha = float(hex_value.substr(6, 2).hex_to_int()) / 255.0
	return Color(red, green, blue, alpha)

func _normalize_profile_record(payload: Variant) -> Dictionary:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		if payload_dict.has("id") or payload_dict.has("username"):
			return payload_dict
		if payload_dict.has("data"):
			return _normalize_profile_record(payload_dict["data"])
	if payload is Array:
		var payload_array: Array = payload
		if not payload_array.is_empty():
			return _normalize_profile_record(payload_array[0])
	return {}

func _has_valid_access_session() -> bool:
	if _auth_access_token.is_empty() or _auth_user_id.is_empty():
		return false
	if _auth_expires_at <= 0:
		return true
	return int(Time.get_unix_time_from_system()) < (_auth_expires_at - AUTH_REFRESH_MARGIN_SECONDS)

func _load_saved_auth_session() -> void:
	for session_path in _get_auth_session_candidates():
		if not FileAccess.file_exists(session_path):
			continue
		var file: FileAccess = FileAccess.open(session_path, FileAccess.READ)
		if file == null:
			continue
		var content: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(content)
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed
		if str(data.get("backend_id", "")).strip_edges() != CLOUD_BACKEND_ID:
			_remove_file_if_exists(session_path)
			continue
		_auth_access_token = str(data.get("access_token", "")).strip_edges()
		_auth_refresh_token = str(data.get("refresh_token", "")).strip_edges()
		_auth_user_id = str(data.get("user_id", "")).strip_edges()
		_auth_expires_at = int(data.get("expires_at", 0))
		_auth_is_anonymous = bool(data.get("is_anonymous", false))
		_auth_email = str(data.get("email", "")).strip_edges()
		_current_profile_username = str(data.get("username", "")).strip_edges()
		_save_auth_session()
		return

func _save_auth_session() -> void:
	var session_payload: Dictionary = {
		"access_token": _auth_access_token,
		"refresh_token": _auth_refresh_token,
		"user_id": _auth_user_id,
		"expires_at": _auth_expires_at,
		"is_anonymous": _auth_is_anonymous,
		"email": _auth_email,
		"username": _current_profile_username,
		"backend_id": CLOUD_BACKEND_ID
	}
	_write_auth_session_file(_get_runtime_auth_session_path(), session_payload)
	_write_auth_session_file(CURRENT_AUTH_SESSION_PATH, session_payload)

func _clear_auth_session(remove_file: bool = true) -> void:
	_auth_access_token = ""
	_auth_refresh_token = ""
	_auth_user_id = ""
	_auth_expires_at = 0
	_auth_is_anonymous = false
	_auth_email = ""
	_current_profile_username = ""
	if remove_file:
		for session_path in _get_auth_session_candidates():
			if FileAccess.file_exists(session_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))

func _get_auth_session_path() -> String:
	return _get_runtime_auth_session_path()

func _get_runtime_auth_session_path() -> String:
	return RUNTIME_AUTH_SESSION_ROOT_PATH.path_join(str(OS.get_process_id())).path_join("bobux_auth_session.json")

func _get_auth_session_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var runtime_path: String = _get_runtime_auth_session_path()
	if not runtime_path.is_empty():
		candidates.append(runtime_path)
	if not CURRENT_AUTH_SESSION_PATH.is_empty() and not candidates.has(CURRENT_AUTH_SESSION_PATH):
		candidates.append(CURRENT_AUTH_SESSION_PATH)
	return candidates

# This function deletes obsolete local auth artifacts so only the active cloud session remains authoritative.
func _prune_obsolete_auth_artifacts() -> void:
	_remove_file_if_exists(LEGACY_AUTH_SESSION_PATH)
	_remove_file_if_exists(LEGACY_CURRENT_AUTH_SESSION_PATH)
	for candidate_path in _get_legacy_auth_session_candidates():
		_remove_file_if_exists(candidate_path)
	_remove_directory_recursive(USER_AUTH_SESSION_ROOT_PATH)
	_prune_runtime_auth_sessions()

# This function removes stale per-process auth sessions left by crashed or force-closed clients.
func _prune_runtime_auth_sessions() -> void:
	var runtime_root := DirAccess.open(RUNTIME_AUTH_SESSION_ROOT_PATH)
	if runtime_root == null:
		return
	var current_process_id: String = str(OS.get_process_id())
	var stale_runtime_dirs: Array[String] = []
	runtime_root.list_dir_begin()
	var entry: String = runtime_root.get_next()
	while not entry.is_empty():
		if runtime_root.current_is_dir() and entry != "." and entry != ".." and entry != current_process_id:
			stale_runtime_dirs.append(RUNTIME_AUTH_SESSION_ROOT_PATH.path_join(entry))
		entry = runtime_root.get_next()
	runtime_root.list_dir_end()
	for stale_path in stale_runtime_dirs:
		_remove_directory_recursive(stale_path)

# This function removes one file path if it still exists in user storage.
func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# This function removes one user:// directory recursively without touching unrelated map caches.
func _remove_directory_recursive(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = path.path_join(entry)
			if directory.current_is_dir():
				_remove_directory_recursive(child_path)
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
			else:
				_remove_file_if_exists(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)

# This function sends one password grant request without falling back to legacy anonymous session recovery.
func _perform_password_sign_in_request(preferred_username: String, password: String, request_name: String) -> Dictionary:
	return await _request_auth_json(
		"%s?grant_type=password" % AUTH_TOKEN_ENDPOINT,
		HTTPClient.METHOD_POST,
		{
			"email": _build_auth_email_from_username(preferred_username),
			"password": password
		},
		request_name
	)

func _validate_session_binding_for_current_user() -> bool:
	if _current_profile_username.is_empty() or _auth_user_id.is_empty() or _auth_access_token.is_empty():
		return true
	var response: Dictionary = await _request_json(
		"%s?select=id,username&id=eq.%s&limit=1" % [profiles_endpoint, _auth_user_id.uri_encode()],
		HTTPClient.METHOD_GET,
		null,
		"validate_session_binding",
		PackedStringArray(),
		true
	)
	if not bool(response.get("ok", false)):
		return true
	var profile_record: Dictionary = _normalize_profile_record(response.get("data", {}))
	if profile_record.is_empty():
		return true
	var bound_username: String = str(profile_record.get("username", "")).strip_edges()
	return bound_username.is_empty() or bound_username == _current_profile_username

func _write_auth_session_file(session_path: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(session_path.get_base_dir()))
	var file: FileAccess = FileAccess.open(session_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

func _json_safe_value(value: Variant) -> Variant:
	if value is Color:
		var color_value: Color = value
		return {
			"r": color_value.r,
			"g": color_value.g,
			"b": color_value.b,
			"a": color_value.a
		}
	if value is Dictionary:
		var safe_dict: Dictionary = {}
		for key_variant in (value as Dictionary).keys():
			safe_dict[key_variant] = _json_safe_value((value as Dictionary)[key_variant])
		return safe_dict
	if value is Array:
		var safe_array: Array = []
		for item_variant in value:
			safe_array.append(_json_safe_value(item_variant))
		return safe_array
	return value

# PRACTICE SCREENSHOT: Retry wrapper - repeats transient HTTP failures and refreshes expired auth sessions.
func _request_json_with_retries(endpoint: String, method: HTTPClient.Method, body: Variant, request_name: String, extra_headers: PackedStringArray = PackedStringArray(), use_auth_session: bool = true, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS, attempts: int = HTTP_READ_RETRY_ATTEMPTS) -> Dictionary:
	var last_response: Dictionary = {}
	var safe_attempts: int = maxi(attempts, 1)
	var auth_retry_used := false
	if use_auth_session and not _has_valid_access_session() and not _auth_refresh_token.strip_edges().is_empty():
		var preflight_refresh_result: Dictionary = await _refresh_authenticated_session()
		if not bool(preflight_refresh_result.get("ok", false)):
			return _handle_expired_auth_session(request_name, preflight_refresh_result)
	for attempt_index in range(safe_attempts):
		last_response = await _request_json(endpoint, method, body, request_name, extra_headers, use_auth_session, timeout_seconds)
		if bool(last_response.get("ok", false)):
			return last_response
		if use_auth_session and not auth_retry_used and _should_refresh_auth_after_response(last_response):
			auth_retry_used = true
			var refresh_result: Dictionary = await _refresh_authenticated_session()
			if bool(refresh_result.get("ok", false)):
				last_response = await _request_json(endpoint, method, body, request_name, extra_headers, use_auth_session, timeout_seconds)
				if bool(last_response.get("ok", false)):
					return last_response
			else:
				return _handle_expired_auth_session(request_name, refresh_result)
		elif use_auth_session and (int(last_response.get("status", 0)) == 401 or (int(last_response.get("status", 0)) == 403 and _auth_refresh_token.strip_edges().is_empty())):
			return _handle_expired_auth_session(request_name, last_response)
		if not _is_retryable_http_error(last_response):
			return last_response
		if attempt_index < safe_attempts - 1 and is_inside_tree() and not _is_shutting_down:
			await get_tree().create_timer(0.35 + float(attempt_index) * 0.75).timeout
	return last_response


func _handle_expired_auth_session(request_name: String, source_response: Dictionary = {}) -> Dictionary:
	_clear_auth_session(true)
	_auth_bootstrap_in_progress = false
	_auth_bootstrap_result = {}
	var message := "Login session expired. Please sign in again."
	_last_auth_error_message = message
	auth_session_failed.emit(message)
	request_failed.emit(request_name, message)
	return _make_error_result(
		request_name,
		message,
		int(source_response.get("error_code", ERR_CANT_CONNECT)),
		int(source_response.get("status", 401)),
		source_response.get("data", null)
	)

func _should_refresh_auth_after_response(response: Dictionary) -> bool:
	var status_code: int = int(response.get("status", 0))
	if status_code != 401 and status_code != 403:
		return false
	return not _auth_refresh_token.strip_edges().is_empty()

# PRACTICE SCREENSHOT: Authenticated REST request builder - attaches JSON headers, API key and bearer token.
func _request_json(endpoint: String, method: HTTPClient.Method, body: Variant, request_name: String, extra_headers: PackedStringArray = PackedStringArray(), use_auth_session: bool = true, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	if not is_configured():
		var config_error: Dictionary = _make_error_result(request_name, "Cloud API base URL is not configured.")
		request_failed.emit(request_name, str(config_error.get("error", "")))
		return config_error

	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json"
	])
	var has_prefer_header: bool = false
	for header_variant in extra_headers:
		var header_string: String = str(header_variant)
		if header_string.to_lower().begins_with("prefer:"):
			has_prefer_header = true
			break
	if not has_prefer_header:
		headers.append("Prefer: return=representation")
	var storage_api_key: String = _get_storage_api_key()
	if not storage_api_key.is_empty():
		headers.append("apikey: %s" % storage_api_key)
	var auth_header_value: String = _auth_access_token if use_auth_session and not _auth_access_token.is_empty() else bearer_token
	if auth_header_value.is_empty():
		var anonymous_auth_key: String = _get_storage_api_key()
		if not anonymous_auth_key.is_empty():
			auth_header_value = anonymous_auth_key
		elif not api_key.is_empty():
			auth_header_value = api_key
	if not auth_header_value.is_empty():
		headers.append("Authorization: Bearer %s" % auth_header_value)
	for header_variant in extra_headers:
		headers.append(str(header_variant))

	var normalized_endpoint: String = _normalize_endpoint(endpoint)
	var url: String = normalized_endpoint if normalized_endpoint.begins_with("http://") or normalized_endpoint.begins_with("https://") else "%s%s" % [base_url.trim_suffix("/"), normalized_endpoint]
	return await _request_http_json(url, method, body, request_name, headers, timeout_seconds)

func _request_server_json(endpoint: String, method: HTTPClient.Method, body: Variant, request_name: String, extra_headers: PackedStringArray = PackedStringArray(), allow_empty_result: bool = false, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	var service_role_key: String = _get_server_service_role_key()
	var rest_base_url: String = _get_server_rest_base_url()
	if service_role_key.is_empty() or rest_base_url.is_empty():
		return _make_error_result(request_name, "Bobux server credentials are not configured for dedicated-server access.")
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"apikey: %s" % service_role_key
	])
	var has_prefer_header: bool = false
	for header_variant in extra_headers:
		var header_string: String = str(header_variant)
		if header_string.to_lower().begins_with("prefer:"):
			has_prefer_header = true
			break
	if not has_prefer_header and not allow_empty_result:
		headers.append("Prefer: return=representation")
	if _should_send_server_authorization_header(service_role_key):
		headers.append("Authorization: Bearer %s" % service_role_key)
	for header_variant in extra_headers:
		headers.append(str(header_variant))
	var normalized_endpoint: String = _normalize_endpoint(endpoint)
	var url: String = normalized_endpoint if normalized_endpoint.begins_with("http://") or normalized_endpoint.begins_with("https://") else "%s%s" % [rest_base_url.trim_suffix("/"), normalized_endpoint]
	return await _request_http_json(url, method, body, request_name, headers, timeout_seconds)

# PRACTICE SCREENSHOT: Auth REST request builder - calls signup/login endpoints with the public client key.
func _request_auth_json(endpoint: String, method: HTTPClient.Method, body: Variant, request_name: String, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json"
	])
	var auth_api_key: String = DEFAULT_ANON_KEY if not DEFAULT_ANON_KEY.is_empty() else api_key
	if not auth_api_key.is_empty():
		headers.append("apikey: %s" % auth_api_key)
		headers.append("Authorization: Bearer %s" % auth_api_key)
	var normalized_endpoint: String = _normalize_endpoint(endpoint)
	var url: String = normalized_endpoint if normalized_endpoint.begins_with("http://") or normalized_endpoint.begins_with("https://") else "%s%s" % [project_url.trim_suffix("/"), normalized_endpoint]
	return await _request_http_json(url, method, body, request_name, headers, timeout_seconds)

# This function calls the Bobux Auth REST API with the current bearer session instead of the public key bearer.
func _request_authenticated_auth_json(endpoint: String, method: HTTPClient.Method, body: Variant, request_name: String, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json"
	])
	var auth_api_key: String = DEFAULT_ANON_KEY if not DEFAULT_ANON_KEY.is_empty() else api_key
	if not auth_api_key.is_empty():
		headers.append("apikey: %s" % auth_api_key)
	var access_token: String = _auth_access_token.strip_edges()
	if access_token.is_empty():
		return _make_error_result(request_name, "No authenticated Bobux access token is available.")
	headers.append("Authorization: Bearer %s" % access_token)
	var normalized_endpoint: String = _normalize_endpoint(endpoint)
	var url: String = normalized_endpoint if normalized_endpoint.begins_with("http://") or normalized_endpoint.begins_with("https://") else "%s%s" % [project_url.trim_suffix("/"), normalized_endpoint]
	return await _request_http_json(url, method, body, request_name, headers, timeout_seconds)

# PRACTICE SCREENSHOT: Low-level HTTP transport - creates HTTPRequest, serializes JSON, waits asynchronously and parses status codes.
func _request_http_json(url: String, method: HTTPClient.Method, body: Variant, request_name: String, headers: PackedStringArray, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	if _is_shutting_down or not is_inside_tree():
		return _make_error_result(request_name, "CloudAPI is shutting down.")
	var request: HTTPRequest = HTTPRequest.new()
	request.use_threads = true
	request.timeout = maxf(timeout_seconds, 1.0)
	add_child(request)
	_active_http_requests.append(request)

	var request_body: String = ""
	if body != null:
		request_body = JSON.stringify(_json_safe_value(body))

	var start_error: Error = request.request(url, headers, method, request_body)
	if start_error != OK:
		_active_http_requests.erase(request)
		request.queue_free()
		var send_error: Dictionary = _make_error_result(request_name, "Could not start HTTP request: %s" % error_string(start_error), start_error)
		request_failed.emit(request_name, str(send_error.get("error", "")))
		return send_error

	var result: Array = await request.request_completed
	_active_http_requests.erase(request)
	if is_instance_valid(request):
		request.queue_free()

	var transport_result: int = int(result[0])
	var response_code: int = int(result[1])
	var body_bytes: PackedByteArray = result[3]
	var body_text: String = body_bytes.get_string_from_utf8()
	var parsed_body: Variant = {}
	var trimmed_body: String = body_text.strip_edges()
	if not trimmed_body.is_empty():
		if _looks_like_json_body(trimmed_body):
			var parsed_variant: Variant = JSON.parse_string(trimmed_body)
			parsed_body = parsed_variant if parsed_variant != null else body_text
		else:
			parsed_body = body_text

	if transport_result != HTTPRequest.RESULT_SUCCESS:
		var transport_error: Dictionary = _make_error_result(
			request_name,
			"HTTP transport failed with result %d and status %d." % [transport_result, response_code],
			transport_result,
			response_code,
			parsed_body
		)
		request_failed.emit(request_name, str(transport_error.get("error", "")))
		return transport_error

	var ok: bool = response_code >= 200 and response_code < 300
	if not ok:
		var body_hint: String = _compact_error_body(parsed_body)
		var status_message: String = "HTTP request returned status %d." % response_code
		if not body_hint.is_empty():
			status_message += " %s" % body_hint
		var status_error: Dictionary = _make_error_result(
			request_name,
			status_message,
			transport_result,
			response_code,
			parsed_body
		)
		request_failed.emit(request_name, str(status_error.get("error", "")))
		return status_error

	return {
		"ok": true,
		"endpoint": request_name,
		"status": response_code,
		"data": parsed_body
	}

func _request_http_bytes(url: String, method: HTTPClient.Method, body_bytes: PackedByteArray, request_name: String, headers: PackedStringArray, timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	if _is_shutting_down or not is_inside_tree():
		return _make_error_result(request_name, "CloudAPI is shutting down.")
	var request: HTTPRequest = HTTPRequest.new()
	request.use_threads = true
	request.timeout = maxf(timeout_seconds, 1.0)
	add_child(request)
	_active_http_requests.append(request)
	var start_error: Error = request.request_raw(url, headers, method, body_bytes)
	if start_error != OK:
		_active_http_requests.erase(request)
		request.queue_free()
		var send_error: Dictionary = _make_error_result(request_name, "Could not start HTTP raw request: %s" % error_string(start_error), start_error)
		request_failed.emit(request_name, str(send_error.get("error", "")))
		return send_error
	var result: Array = await request.request_completed
	_active_http_requests.erase(request)
	if is_instance_valid(request):
		request.queue_free()
	var transport_result: int = int(result[0])
	var response_code: int = int(result[1])
	var response_bytes: PackedByteArray = result[3]
	var parsed_body: Variant = {}
	var response_text: String = ""
	if not response_bytes.is_empty():
		response_text = response_bytes.get_string_from_utf8()
		var trimmed_response: String = response_text.strip_edges()
		if _looks_like_json_body(trimmed_response):
			var parsed_variant: Variant = JSON.parse_string(trimmed_response)
			parsed_body = parsed_variant if parsed_variant != null else response_text
		elif response_code >= 400 and not trimmed_response.is_empty():
			parsed_body = response_text.substr(0, 4096)
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		var transport_error: Dictionary = _make_error_result(
			request_name,
			"HTTP transport failed with result %d and status %d." % [transport_result, response_code],
			transport_result,
			response_code,
			parsed_body
		)
		request_failed.emit(request_name, str(transport_error.get("error", "")))
		return transport_error
	if response_code < 200 or response_code >= 300:
		var body_hint: String = _compact_error_body(parsed_body)
		var status_message: String = "HTTP request returned status %d." % response_code
		if not body_hint.is_empty():
			status_message += " %s" % body_hint
		var status_error: Dictionary = _make_error_result(
			request_name,
			status_message,
			transport_result,
			response_code,
			parsed_body
		)
		request_failed.emit(request_name, str(status_error.get("error", "")))
		return status_error
	return {"ok": true, "endpoint": request_name, "status": response_code, "data": parsed_body, "bytes": response_bytes}

func _looks_like_json_body(text: String) -> bool:
	if text.is_empty():
		return false
	return text.begins_with("{") \
		or text.begins_with("[") \
		or text.begins_with("\"") \
		or text == "true" \
		or text == "false" \
		or text == "null"

func _compact_error_body(data: Variant) -> String:
	if data == null:
		return ""
	var text: String = ""
	if data is Dictionary or data is Array:
		text = JSON.stringify(data)
	else:
		text = str(data)
	text = text.strip_edges()
	if text.length() > 500:
		text = text.substr(0, 500) + "..."
	return text

func _download_file_to_path(url: String, target_path: String) -> Dictionary:
	if url.strip_edges().is_empty() or target_path.strip_edges().is_empty():
		return _make_error_result("download_map_asset_file", "Asset URL or target path is empty.")
	var headers: PackedStringArray = PackedStringArray(["Accept: */*"])
	var storage_api_key: String = _get_storage_api_key()
	if not storage_api_key.is_empty():
		headers.append("apikey: %s" % storage_api_key)
	if not _auth_access_token.is_empty():
		headers.append("Authorization: Bearer %s" % _auth_access_token)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))
	var temp_path: String = "%s.download" % target_path
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var request: HTTPRequest = HTTPRequest.new()
	request.use_threads = true
	request.timeout = HTTP_MAP_ASSET_DOWNLOAD_TIMEOUT_SECONDS
	request.download_file = temp_path
	add_child(request)
	_active_http_requests.append(request)
	var start_error: Error = request.request(url, headers, HTTPClient.METHOD_GET)
	if start_error != OK:
		_active_http_requests.erase(request)
		request.queue_free()
		var start_result: Dictionary = _make_error_result("download_map_asset_file", "Could not start asset download: %s" % error_string(start_error), start_error)
		request_failed.emit("download_map_asset_file", str(start_result.get("error", "")))
		return start_result
	var result: Array = await request.request_completed
	_active_http_requests.erase(request)
	if is_instance_valid(request):
		request.queue_free()
	if result.size() < 4:
		return _make_error_result("download_map_asset_file", "Asset download returned an incomplete response.")
	var transport_result: int = int(result[0])
	var response_code: int = int(result[1])
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		var transport_error: Dictionary = _make_error_result(
			"download_map_asset_file",
			"HTTP transport failed with result %d and status %d." % [transport_result, response_code],
			transport_result,
			response_code
		)
		request_failed.emit("download_map_asset_file", str(transport_error.get("error", "")))
		return transport_error
	if response_code < 200 or response_code >= 300:
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		var status_error: Dictionary = _make_error_result("download_map_asset_file", "HTTP request returned status %d." % response_code, transport_result, response_code)
		request_failed.emit("download_map_asset_file", str(status_error.get("error", "")))
		return status_error
	var downloaded_size: int = _get_file_size_bytes(temp_path)
	if downloaded_size <= 0:
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _make_error_result("download_map_asset_file", "Downloaded asset was empty.")
	if FileAccess.file_exists(target_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(target_path))
	if rename_error != OK:
		return _make_error_result("download_map_asset_file", "Could not finalize downloaded asset: %s" % error_string(rename_error), rename_error)
	return {"ok": true, "path": target_path, "size": downloaded_size}

func _sanitize_storage_relative_path(path: String) -> String:
	var file_name: String = path.strip_edges().get_file()
	file_name = file_name.replace("\\", "_").replace("/", "_").replace("..", "_")
	if file_name.is_empty():
		file_name = "asset.bin"
	return file_name

func _sanitize_storage_segment(value: String) -> String:
	var cleaned: String = value.strip_edges()
	for bad_char in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "%", "#", "&", "=", "+"]:
		cleaned = cleaned.replace(bad_char, "_")
	if cleaned.is_empty():
		cleaned = "asset"
	return cleaned.uri_encode().replace("%", "_")

func _get_storage_api_key() -> String:
	var clean_key: String = api_key.strip_edges()
	if clean_key.is_empty() or clean_key.begins_with("sb_publishable_"):
		return DEFAULT_ANON_KEY
	return clean_key

func _guess_mime_type(path: String) -> String:
	match path.get_extension().to_lower():
		"ogg":
			return "audio/ogg"
		"mp3":
			return "audio/mpeg"
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"webp":
			return "image/webp"
		_:
			return "application/octet-stream"

func _get_server_rest_base_url() -> String:
	if not base_url.strip_edges().is_empty():
		return base_url.trim_suffix("/")
	var env_base_url: String = OS.get_environment(ENV_BASE_URL).strip_edges().trim_suffix("/")
	if not env_base_url.is_empty():
		return env_base_url
	return DEFAULT_REST_BASE_URL

func _get_server_service_role_key() -> String:
	return OS.get_environment(ENV_BOBUX_SERVICE_KEY).strip_edges()

func _should_send_server_authorization_header(service_role_key: String) -> bool:
	var clean_key: String = service_role_key.strip_edges()
	return not clean_key.is_empty() and not clean_key.begins_with("sb_")

func _store_cached_map_record(map_id: String, cloud_version_id: String, fallback_name: String, record: Dictionary) -> String:
	var map_data_variant: Variant = record.get("map_data", record.get("data", {}))
	if not (map_data_variant is Dictionary):
		return ""
	var map_data: Dictionary = _prepare_map_data_for_cache(map_data_variant)
	if map_data.is_empty():
		return ""

	var folder: String = CACHE_ROOT_PATH.path_join(_sanitize_cache_key(map_id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

	var version_file: FileAccess = FileAccess.open(folder.path_join("version.txt"), FileAccess.WRITE)
	if version_file:
		version_file.store_string(cloud_version_id)
		version_file.close()

	var meta: Dictionary = {
		"name": str(record.get("name", fallback_name)).strip_edges(),
		"creator": str(record.get("owner_name", record.get("creator", "Cloud"))).strip_edges(),
		"description": str(record.get("description", "")).strip_edges(),
		"cloud_map_id": map_id,
		"cloud_version_id": cloud_version_id
	}
	if str(meta.get("name", "")).is_empty():
		meta["name"] = fallback_name

	var meta_file: FileAccess = FileAccess.open(folder.path_join("meta.json"), FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta, "\t"))
		meta_file.close()

	# Large imported places used to freeze on this stringify. Encode on a worker
	# and only perform the final buffered write on the main thread.
	var encoded_map_data: PackedByteArray = await _encode_json_dictionary_async(map_data)
	if encoded_map_data.is_empty():
		return ""
	var map_file: FileAccess = FileAccess.open(folder.path_join("map_data.json"), FileAccess.WRITE)
	if map_file == null:
		return ""
	map_file.store_buffer(encoded_map_data)
	map_file.close()

	_restore_cached_inline_map_assets(folder, map_data, record)

	return folder


func _ensure_cached_map_visual_assets(folder: String, cloud_version_id: String, supplied_map_data: Variant = null) -> Dictionary:
	var clean_folder := folder.strip_edges()
	if clean_folder.is_empty():
		return {"ok": false, "error": "Cached map folder is empty."}
	var version_token := cloud_version_id.strip_edges()
	if version_token.is_empty():
		version_token = "unversioned"
	version_token = "%s:%s" % [MAP_VISUAL_ASSET_PREFETCH_SCHEMA, version_token]
	var marker_path := clean_folder.path_join("visual_assets.ready")
	if FileAccess.file_exists(marker_path):
		var marker := FileAccess.get_file_as_string(marker_path).strip_edges()
		if marker == version_token:
			return {"ok": true, "from_cache": true, "downloaded": 0, "failed": 0}
	var map_data: Dictionary = supplied_map_data if supplied_map_data is Dictionary else {}
	if map_data.is_empty():
		map_data = await _read_json_dictionary_file_async(clean_folder.path_join("map_data.json"))
	if map_data.is_empty():
		return {"ok": false, "error": "Cached map data could not be read for asset prefetch."}
	var raw_urls: Variant = map_data.get("mode_asset_urls", {})
	var asset_urls: Dictionary = raw_urls if raw_urls is Dictionary else {}
	var entries: Array[Dictionary] = []
	for file_variant in asset_urls.keys():
		var file_name := _sanitize_storage_relative_path(str(file_variant))
		var asset_url := str(asset_urls.get(file_variant, "")).strip_edges()
		if file_name.is_empty() or asset_url.is_empty() or _is_audio_asset_name(file_name):
			continue
		if not _is_map_visual_asset_name(file_name):
			continue
		var target_path := clean_folder.path_join(file_name)
		if FileAccess.file_exists(target_path) and _get_file_size_bytes(target_path) > 0:
			continue
		entries.append({"file": file_name, "url": asset_url, "target": target_path})
	if entries.is_empty():
		_write_text_file(marker_path, version_token)
		return {"ok": true, "from_cache": true, "downloaded": 0, "failed": 0}
	var downloaded := 0
	var failed := 0
	var cursor := 0
	while cursor < entries.size():
		var batch_end := mini(entries.size(), cursor + MAP_VISUAL_ASSET_PREFETCH_CONCURRENCY)
		var state := {"pending": batch_end - cursor, "downloaded": 0, "failed": 0}
		for index in range(cursor, batch_end):
			var entry: Dictionary = entries[index]
			call_deferred("_download_cached_map_visual_asset_async", entry, state)
		while int(state.get("pending", 0)) > 0:
			await get_tree().process_frame
		downloaded += int(state.get("downloaded", 0))
		failed += int(state.get("failed", 0))
		cursor = batch_end
	if failed == 0:
		_write_text_file(marker_path, version_token)
	return {
		"ok": failed == 0,
		"from_cache": false,
		"downloaded": downloaded,
		"failed": failed,
		"total": entries.size()
	}


func _download_cached_map_visual_asset_async(entry: Dictionary, state: Dictionary) -> void:
	var result: Dictionary = await _download_file_to_path(
		str(entry.get("url", "")),
		str(entry.get("target", ""))
	)
	if bool(result.get("ok", false)):
		state["downloaded"] = int(state.get("downloaded", 0)) + 1
	else:
		state["failed"] = int(state.get("failed", 0)) + 1
	state["pending"] = maxi(0, int(state.get("pending", 1)) - 1)


func _read_json_dictionary_file_async(path: String) -> Dictionary:
	var worker := Thread.new()
	var start_error := worker.start(_read_json_dictionary_file_worker.bind(path))
	if start_error != OK:
		return _read_json_dictionary_file_worker(path)
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result if result is Dictionary else {}


static func _read_json_dictionary_file_worker(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _is_map_visual_asset_name(file_name: String) -> bool:
	var lower := file_name.to_lower()
	var is_mesh_json := lower.ends_with(".mesh.json") \
		or (lower.get_extension() == "json" and (lower.contains("mesh") or lower.begins_with("rbxl_")))
	return is_mesh_json or lower.get_extension() in [
		"png", "jpg", "jpeg", "webp", "bmp", "tga",
		"res", "tres", "mesh", "obj", "glb", "gltf", "bin"
	]


func _write_text_file(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func _restore_cached_inline_map_assets(folder: String, map_data: Dictionary, record: Dictionary) -> void:
	var asset_blobs: Dictionary = map_data.get("mode_asset_blobs", {}) if map_data.get("mode_asset_blobs", {}) is Dictionary else {}
	var restored_total_bytes: int = 0
	for file_name_variant in asset_blobs.keys():
		var file_name: String = str(file_name_variant).strip_edges()
		var encoded_blob: String = str(asset_blobs.get(file_name_variant, "")).strip_edges()
		if file_name.is_empty() or encoded_blob.is_empty():
			continue
		if _is_audio_asset_name(file_name):
			continue
		var estimated_bytes: int = int(float(encoded_blob.length()) * 0.75)
		if estimated_bytes > MAX_RESTORED_INLINE_ASSET_BYTES or restored_total_bytes + estimated_bytes > MAX_RESTORED_INLINE_ASSET_TOTAL_BYTES:
			continue
		var file_bytes: PackedByteArray = Marshalls.base64_to_raw(encoded_blob)
		if file_bytes.is_empty():
			continue
		restored_total_bytes += file_bytes.size()
		var target_file := FileAccess.open(folder.path_join(file_name), FileAccess.WRITE)
		if target_file == null:
			continue
		target_file.store_buffer(file_bytes)
		target_file.close()
	var thumbnail_data: String = str(record.get("thumbnail", "")).strip_edges()
	var image_bytes: PackedByteArray = _decode_inline_image_bytes(thumbnail_data)
	if not image_bytes.is_empty():
		var icon_file := FileAccess.open(folder.path_join("icon.png"), FileAccess.WRITE)
		if icon_file:
			icon_file.store_buffer(image_bytes)
			icon_file.close()

func _prepare_map_data_for_cache(map_data_variant: Variant) -> Dictionary:
	if not (map_data_variant is Dictionary):
		return {}
	# Only root-level asset fields are rewritten below. A deep copy of a large
	# RBXL manifest doubled memory and was a major source of publish/join stalls.
	var map_data: Dictionary = (map_data_variant as Dictionary).duplicate(false)
	var asset_blobs: Dictionary = map_data.get("mode_asset_blobs", {}) if map_data.get("mode_asset_blobs", {}) is Dictionary else {}
	if asset_blobs.is_empty():
		return map_data
	var kept_blobs: Dictionary = {}
	var skipped_count: int = 0
	var kept_total_bytes: int = 0
	for file_name_variant in asset_blobs.keys():
		var file_name: String = str(file_name_variant).strip_edges()
		var encoded_blob: String = str(asset_blobs.get(file_name_variant, "")).strip_edges()
		if file_name.is_empty() or encoded_blob.is_empty():
			continue
		var estimated_bytes: int = int(float(encoded_blob.length()) * 0.75)
		if _is_audio_asset_name(file_name) \
			or estimated_bytes > MAX_RESTORED_INLINE_ASSET_BYTES \
			or kept_total_bytes + estimated_bytes > MAX_RESTORED_INLINE_ASSET_TOTAL_BYTES:
			skipped_count += 1
			continue
		kept_blobs[file_name] = encoded_blob
		kept_total_bytes += estimated_bytes
	if kept_blobs.is_empty():
		map_data.erase("mode_asset_blobs")
	else:
		map_data["mode_asset_blobs"] = kept_blobs
	if skipped_count > 0:
		map_data["mode_asset_warning"] = "Skipped %d heavy inline asset(s) while caching this map. Gameplay can start without blocking on media." % skipped_count
	return map_data

func _is_audio_asset_name(file_name: String) -> bool:
	var extension: String = file_name.get_extension().to_lower()
	return extension == "mp3" or extension == "ogg" or extension == "wav"

func _get_file_size_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = file.get_length()
	file.close()
	return length

func _cached_map_contains_inline_asset_blobs(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var needle := "\"mode_asset_blobs\""
	var overlap := ""
	while file.get_position() < file.get_length():
		var remaining: int = file.get_length() - file.get_position()
		var chunk_size: int = mini(remaining, 64 * 1024)
		var text := overlap + file.get_buffer(chunk_size).get_string_from_utf8()
		if text.find(needle) >= 0:
			file.close()
			return true
		overlap = text.right(mini(text.length(), needle.length()))
	file.close()
	return false

func _normalize_cloud_map_record(payload: Variant) -> Dictionary:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		# Unwrap nested "data" wrapper first (PostgREST-compatible response envelope)
		if payload_dict.has("data") and not (payload_dict.has("map_data") or payload_dict.has("name") or payload_dict.has("cloud_version_id") or payload_dict.has("id")):
			return _normalize_cloud_map_record(payload_dict["data"])
		if payload_dict.has("map_data") or payload_dict.has("data") or payload_dict.has("name") or payload_dict.has("cloud_version_id") or payload_dict.has("id"):
			return payload_dict
	if payload is Array:
		var payload_array: Array = payload
		if not payload_array.is_empty():
			return _normalize_cloud_map_record(payload_array[0])
	return {}

func _extract_cloud_version_id(payload: Variant, fallback: String = "") -> String:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		for key in ["cloud_version_id", "version_id", "updated_at"]:
			var value: String = str(payload_dict.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
		if payload_dict.has("data"):
			return _extract_cloud_version_id(payload_dict["data"], fallback)
	if payload is Array:
		var payload_array: Array = payload
		if not payload_array.is_empty():
			return _extract_cloud_version_id(payload_array[0], fallback)
	return fallback.strip_edges()

func _normalize_auth_payload(payload: Variant) -> Dictionary:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		if payload_dict.has("session") and payload_dict["session"] is Dictionary:
			var session_payload: Dictionary = payload_dict["session"]
			if not session_payload.has("user") and payload_dict.has("user"):
				session_payload["user"] = payload_dict["user"]
			return session_payload
		return payload_dict
	return {}

func _extract_auth_error_code(payload: Variant) -> String:
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		for key in ["error_code", "code"]:
			var value: String = str(payload_dict.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	return ""

func _generate_cloud_version_id() -> String:
	return "%s_%d" % [_get_generated_id_prefix(), Time.get_unix_time_from_system()]

func _resolve_cloud_map_id(map_name: String, map_metadata: Dictionary) -> String:
	for key in ["cloud_map_id", "map_id", "id"]:
		var existing_id: String = str(map_metadata.get(key, "")).strip_edges()
		if not existing_id.is_empty():
			return existing_id
	var clean_name: String = _sanitize_cache_key(map_name.to_lower())
	return "%s_%s" % [_get_generated_id_prefix(), clean_name]

func _get_generated_id_prefix() -> String:
	if not _auth_user_id.is_empty():
		return _auth_user_id
	var fallback_username: String = _sanitize_cache_key(get_current_username().to_lower())
	return fallback_username if not fallback_username.is_empty() else "player"

func _pick_dictionary_fields(source: Dictionary, allowed_keys: Array[String]) -> Dictionary:
	var filtered: Dictionary = {}
	for allowed_key in allowed_keys:
		if source.has(allowed_key):
			filtered[allowed_key] = source[allowed_key]
	return filtered

func _quote_postgrest_value(value: String) -> String:
	var escaped: String = value.replace("\\", "\\\\").replace("\"", "\\\"")
	return "\"%s\"" % escaped

func _filter_fresh_active_servers(servers: Array) -> Array:
	var filtered: Array = []
	for server_variant in servers:
		if not (server_variant is Dictionary):
			continue
		var server: Dictionary = server_variant
		if _is_server_record_fresh(server):
			filtered.append(server)
	return filtered

func _is_server_record_fresh_within_window(server_info: Dictionary, freshness_window_seconds: int) -> bool:
	var safe_window_seconds: int = maxi(freshness_window_seconds, 1)
	var last_seen_epoch: int = int(server_info.get("last_seen", 0))
	if last_seen_epoch > 0:
		return (int(Time.get_unix_time_from_system()) - last_seen_epoch) <= safe_window_seconds
	var last_seen_at: String = str(server_info.get("last_seen_at", "")).strip_edges()
	if last_seen_at.is_empty():
		return true
	var last_seen_unix: int = Time.get_unix_time_from_datetime_string(last_seen_at)
	if last_seen_unix <= 0:
		return true
	return (Time.get_unix_time_from_system() - float(last_seen_unix)) <= safe_window_seconds

func _dedupe_published_maps_by_owner_and_name(maps: Array) -> Array:
	var deduped: Array = []
	var seen: Dictionary = {}
	for map_variant in maps:
		if not (map_variant is Dictionary):
			continue
		var map_record: Dictionary = map_variant
		var owner_id: String = str(map_record.get("owner_id", "")).strip_edges().to_lower()
		var map_name: String = str(map_record.get("name", "")).strip_edges().to_lower()
		var dedupe_key: String = "%s|%s" % [owner_id, map_name]
		if map_name.is_empty():
			dedupe_key = str(map_record.get("id", "")).strip_edges().to_lower()
		if dedupe_key.is_empty():
			continue
		if seen.has(dedupe_key):
			var existing_index: int = int(seen[dedupe_key])
			var existing_record: Dictionary = deduped[existing_index]
			# Old clients sometimes published a second record with the same name.
			# Keep the newest payload but never let legacy duplicates lower stats.
			existing_record["likes_count"] = maxi(int(existing_record.get("likes_count", 0)), int(map_record.get("likes_count", 0)))
			existing_record["visits_count"] = maxi(int(existing_record.get("visits_count", 0)), int(map_record.get("visits_count", 0)))
			deduped[existing_index] = existing_record
			continue
		seen[dedupe_key] = deduped.size()
		deduped.append(map_record.duplicate(true))
	return deduped

func _is_server_record_fresh(server_info: Dictionary) -> bool:
	var last_seen: String = str(server_info.get("last_seen_at", "")).strip_edges()
	if last_seen.is_empty():
		return true
	var last_seen_unix: int = Time.get_unix_time_from_datetime_string(last_seen)
	if last_seen_unix <= 0:
		return true
	return (Time.get_unix_time_from_system() - float(last_seen_unix)) <= ACTIVE_SERVER_TTL_SECONDS

func _sanitize_cache_key(value: String) -> String:
	var safe_value: String = value.strip_edges()
	for bad_char in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe_value = safe_value.replace(bad_char, "_")
	return safe_value if not safe_value.is_empty() else "cloud_map"

func _decode_inline_image_bytes(value: String) -> PackedByteArray:
	var encoded_value: String = value.strip_edges()
	if encoded_value.begins_with("data:image/"):
		var comma_index: int = encoded_value.find(",")
		if comma_index >= 0:
			encoded_value = encoded_value.substr(comma_index + 1)
	elif encoded_value.begins_with("base64:"):
		encoded_value = encoded_value.substr(7)
	else:
		return PackedByteArray()
	return Marshalls.base64_to_raw(encoded_value)

func _get_legacy_auth_session_candidates() -> Array[String]:
	var candidates: Array[String] = []
	if FileAccess.file_exists(LEGACY_AUTH_SESSION_PATH):
		candidates.append(LEGACY_AUTH_SESSION_PATH)
	if FileAccess.file_exists(LEGACY_CURRENT_AUTH_SESSION_PATH) and not candidates.has(LEGACY_CURRENT_AUTH_SESSION_PATH):
		candidates.append(LEGACY_CURRENT_AUTH_SESSION_PATH)
	var old_runtime_root := DirAccess.open(RUNTIME_AUTH_SESSION_ROOT_PATH)
	if old_runtime_root != null:
		old_runtime_root.list_dir_begin()
		var runtime_entry: String = old_runtime_root.get_next()
		while not runtime_entry.is_empty():
			if old_runtime_root.current_is_dir() and runtime_entry != "." and runtime_entry != "..":
				var old_runtime_path: String = RUNTIME_AUTH_SESSION_ROOT_PATH.path_join(runtime_entry).path_join("supabase_auth_session.json")
				if FileAccess.file_exists(old_runtime_path) and not candidates.has(old_runtime_path):
					candidates.append(old_runtime_path)
			runtime_entry = old_runtime_root.get_next()
		old_runtime_root.list_dir_end()
	var legacy_profiles_dir := DirAccess.open("user://profiles")
	if legacy_profiles_dir != null:
		legacy_profiles_dir.list_dir_begin()
		var entry: String = legacy_profiles_dir.get_next()
		while not entry.is_empty():
			if legacy_profiles_dir.current_is_dir() and entry != "." and entry != "..":
				var candidate_path: String = "user://profiles/%s/supabase_auth_session.json" % entry
				if FileAccess.file_exists(candidate_path) and not candidates.has(candidate_path):
					candidates.append(candidate_path)
			entry = legacy_profiles_dir.get_next()
		legacy_profiles_dir.list_dir_end()
	return candidates

func _resolve_username(preferred_username: String) -> String:
	var clean_username: String = preferred_username.strip_edges()
	if clean_username.is_empty():
		clean_username = get_current_username()
	return clean_username

func _make_unique_username_variant(base_username: String, user_id: String) -> String:
	var clean_base: String = base_username.strip_edges()
	if clean_base.is_empty():
		clean_base = "Player"
	var suffix_source: String = user_id.replace("-", "")
	var suffix: String = suffix_source.substr(0, mini(6, suffix_source.length())).to_upper()
	return "%s-%s" % [clean_base, suffix]

func _is_unique_username_conflict(response: Dictionary) -> bool:
	if bool(response.get("ok", false)):
		return false
	var error_blob: String = str(response.get("error", ""))
	var payload: Variant = response.get("data", null)
	if payload != null:
		error_blob += " " + JSON.stringify(payload)
	var lowered: String = error_blob.to_lower()
	return lowered.find("profiles_username_key") >= 0 or (lowered.find("username") >= 0 and lowered.find("duplicate") >= 0)

func _auth_payload_contains_session(payload: Variant) -> bool:
	var normalized_payload: Dictionary = _normalize_auth_payload(payload)
	return not str(normalized_payload.get("access_token", "")).strip_edges().is_empty() and not str(normalized_payload.get("refresh_token", "")).strip_edges().is_empty()

func _map_auth_error_result(response: Dictionary, requested_username: String, during_signup: bool) -> Dictionary:
	var payload_blob: String = JSON.stringify(response.get("data", {})).to_lower()
	var error_blob: String = str(response.get("error", "")).to_lower() + " " + payload_blob
	if during_signup and (
		error_blob.find("already registered") >= 0
		or error_blob.find("user_already_exists") >= 0
		or error_blob.find("username_taken") >= 0
		or error_blob.find("username is already taken") >= 0
	):
		response["error"] = "That username is already taken."
	elif not during_signup and (
		error_blob.find("invalid login credentials") >= 0
		or error_blob.find("invalid_grant") >= 0
		or error_blob.find("failed to authenticate") >= 0
		or error_blob.find("missing bearer token") >= 0
	):
		response["error"] = "Invalid username or password."
	elif error_blob.find("password") >= 0 and (
		error_blob.find("at least 6") >= 0
		or error_blob.find("6 characters") >= 0
		or error_blob.find("too short") >= 0
		or error_blob.find("weak_password") >= 0
	):
		response["error"] = "Password must be at least %d characters long." % PASSWORD_MIN_LENGTH
	elif error_blob.find("email_address_invalid") >= 0:
		response["error"] = "Bobux account service rejected the hidden auth email format for this build."
	elif error_blob.find("email not confirmed") >= 0:
		response["error"] = "Email confirmation is still enabled in the account service. %s" % EMAIL_CONFIRMATION_HINT
	elif error_blob.find("signup is disabled") >= 0:
		response["error"] = "Bobux email/password sign-ups are disabled for this project."
	if during_signup and str(response.get("error", "")).strip_edges().is_empty():
		response["error"] = "Could not create the account for %s." % requested_username
	return response

# This function detects when sign-up really hit an already-existing auth user so the client can recover by signing in immediately.
func _looks_like_existing_auth_account(response: Dictionary) -> bool:
	var payload_blob: String = JSON.stringify(response.get("data", {})).to_lower()
	var error_blob: String = str(response.get("error", "")).to_lower() + " " + payload_blob
	return error_blob.find("already registered") >= 0 or error_blob.find("user_already_exists") >= 0

func _build_auth_email_from_username(preferred_username: String) -> String:
	var canonical_username: String = preferred_username.strip_edges().to_lower()
	var email_slug := ""
	for index in range(canonical_username.length()):
		var char_value: String = canonical_username.substr(index, 1)
		var is_letter: bool = (char_value >= "a" and char_value <= "z")
		var is_digit: bool = (char_value >= "0" and char_value <= "9")
		if is_letter or is_digit:
			email_slug += char_value
		else:
			email_slug += "-"
	while email_slug.find("--") >= 0:
		email_slug = email_slug.replace("--", "-")
	email_slug = email_slug.trim_prefix("-").trim_suffix("-")
	if email_slug.is_empty():
		email_slug = "player"
	var suffix: String = canonical_username.sha256_text().substr(0, 8)
	return "%s-%s@%s" % [email_slug, suffix, USERNAME_AUTH_EMAIL_DOMAIN]

func _profiles_result_from_ids(profile_ids: Array[String], request_name: String) -> Dictionary:
	var profiles_by_id: Dictionary = await _fetch_profiles_by_ids(profile_ids, request_name)
	var profiles: Array = []
	for profile_id in profile_ids:
		if profiles_by_id.has(profile_id):
			profiles.append(profiles_by_id[profile_id])
	return {
		"ok": true,
		"endpoint": request_name,
		"status": 200,
		"data": _dedupe_profiles_by_username(profiles)
	}

func _fetch_profiles_by_ids(profile_ids: Array[String], request_name: String) -> Dictionary:
	var profiles_by_id: Dictionary = {}
	if profile_ids.is_empty():
		return profiles_by_id
	var encoded_ids: Array[String] = []
	for profile_id in profile_ids:
		if profile_id.strip_edges().is_empty():
			continue
		encoded_ids.append(_quote_postgrest_value(profile_id))
	if encoded_ids.is_empty():
		return profiles_by_id
	var profiles_endpoint_query: String = "%s?select=id,username,status,current_game,current_server_host,current_server_ip,current_server_port,updated_at,avatar_data&id=in.(%s)" % [
		profiles_endpoint,
		",".join(encoded_ids)
	]
	var profiles_response: Dictionary = await _request_json(profiles_endpoint_query, HTTPClient.METHOD_GET, null, request_name, PackedStringArray(), true)
	if not bool(profiles_response.get("ok", false)):
		return profiles_by_id
	for profile_variant in _extract_array_payload(profiles_response.get("data", [])):
		if not (profile_variant is Dictionary):
			continue
		var profile: Dictionary = profile_variant
		var profile_id: String = str(profile.get("id", "")).strip_edges()
		if not profile_id.is_empty():
			profiles_by_id[profile_id] = profile
	return profiles_by_id

# This function fetches accepted friendship rows between the current user and one other user.
func _fetch_friendship_rows_with_user(other_user_id: String, request_name: String) -> Array:
	if _auth_user_id.is_empty() or other_user_id.strip_edges().is_empty():
		return []
	var endpoint: String = "%s?select=user1,user2,status,created_at&status=eq.accepted&or=(and(user1.eq.%s,user2.eq.%s),and(user1.eq.%s,user2.eq.%s))" % [
		friendships_endpoint,
		_auth_user_id.uri_encode(),
		other_user_id.uri_encode(),
		other_user_id.uri_encode(),
		_auth_user_id.uri_encode()
	]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, null, request_name, PackedStringArray(), true)
	if not bool(response.get("ok", false)):
		return []
	return _extract_array_payload(response.get("data", []))

# This function fetches pending friend request rows between two concrete users.
func _fetch_friend_request_rows_between_users(from_user_id: String, to_user_id: String, request_name: String) -> Array:
	var clean_from_user_id: String = from_user_id.strip_edges()
	var clean_to_user_id: String = to_user_id.strip_edges()
	if clean_from_user_id.is_empty() or clean_to_user_id.is_empty():
		return []
	var endpoint: String = "%s?select=from_user,to_user,status,created_at&from_user=eq.%s&to_user=eq.%s&status=eq.pending" % [
		friend_requests_endpoint,
		clean_from_user_id.uri_encode(),
		clean_to_user_id.uri_encode()
	]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, null, request_name, PackedStringArray(), true)
	if not bool(response.get("ok", false)):
		return []
	return _extract_array_payload(response.get("data", []))

# This function deletes accepted friendship rows in either direction for one user pair.
func _delete_friendship_rows_between_users(user_a: String, user_b: String, request_name: String) -> Dictionary:
	var clean_user_a: String = user_a.strip_edges()
	var clean_user_b: String = user_b.strip_edges()
	if clean_user_a.is_empty() or clean_user_b.is_empty():
		return _make_error_result(request_name, "Friendship user ids are empty.")
	return await _request_json(
		"%s?or=(and(user1.eq.%s,user2.eq.%s),and(user1.eq.%s,user2.eq.%s))" % [
			friendships_endpoint,
			clean_user_a.uri_encode(),
			clean_user_b.uri_encode(),
			clean_user_b.uri_encode(),
			clean_user_a.uri_encode()
		],
		HTTPClient.METHOD_DELETE,
		null,
		request_name,
		PackedStringArray(["Prefer: return=representation"]),
		true
	)

# This function deletes pending friend request rows in either direction for one user pair.
func _delete_friend_request_rows_between_users(user_a: String, user_b: String, request_name: String) -> Dictionary:
	var clean_user_a: String = user_a.strip_edges()
	var clean_user_b: String = user_b.strip_edges()
	if clean_user_a.is_empty() or clean_user_b.is_empty():
		return _make_error_result(request_name, "Friend request user ids are empty.")
	return await _request_json(
		"%s?or=(and(from_user.eq.%s,to_user.eq.%s),and(from_user.eq.%s,to_user.eq.%s))" % [
			friend_requests_endpoint,
			clean_user_a.uri_encode(),
			clean_user_b.uri_encode(),
			clean_user_b.uri_encode(),
			clean_user_a.uri_encode()
		],
		HTTPClient.METHOD_DELETE,
		null,
		request_name,
		PackedStringArray(["Prefer: return=representation"]),
		true
	)

# This function removes redundant accepted friendship rows left behind by older buggy builds.
func _cleanup_duplicate_friendships(other_user_id: String) -> void:
	var rows: Array = await _fetch_friendship_rows_with_user(other_user_id, "cleanup_duplicate_friendships_fetch")
	await _cleanup_duplicate_friendship_rows(rows)

# This function deletes extra rows when multiple accepted friendships resolve to the same canonical pair.
func _cleanup_duplicate_friendship_rows(friendship_rows: Array) -> void:
	var seen_pairs: Dictionary = {}
	for row_variant in friendship_rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant
		var user1: String = str(row.get("user1", "")).strip_edges()
		var user2: String = str(row.get("user2", "")).strip_edges()
		if user1.is_empty() or user2.is_empty():
			continue
		var pair: Dictionary = _build_friendship_pair(user1, user2)
		var pair_key: String = "%s|%s" % [str(pair.get("user1", "")), str(pair.get("user2", ""))]
		var is_non_canonical_row: bool = user1 != str(pair.get("user1", "")) or user2 != str(pair.get("user2", ""))
		if seen_pairs.has(pair_key) or is_non_canonical_row:
			await _delete_friendship_rows_between_users(user1, user2, "cleanup_duplicate_friendship_rows")
			await _upsert_friendship_pair(str(pair.get("user1", "")), str(pair.get("user2", "")), "cleanup_duplicate_friendship_rows_restore")
			break
		seen_pairs[pair_key] = true

# This function keeps only one visible friend per username so stale duplicate cloud identities do not render twice.
func _dedupe_profiles_by_username(profiles: Array) -> Array:
	var deduped: Array = []
	var seen: Dictionary = {}
	for profile_variant in profiles:
		if not (profile_variant is Dictionary):
			continue
		var profile: Dictionary = profile_variant
		var dedupe_key: String = _profile_dedupe_key(profile)
		if dedupe_key.is_empty():
			continue
		if seen.has(dedupe_key):
			continue
		seen[dedupe_key] = true
		deduped.append(profile)
	return deduped

# This function collapses duplicate incoming requests that belong to the same visible sender name.
func _dedupe_friend_requests_by_sender(requests: Array) -> Array:
	var deduped: Array = []
	var seen: Dictionary = {}
	for request_variant in requests:
		if not (request_variant is Dictionary):
			continue
		var request_row: Dictionary = request_variant
		var sender_profile: Dictionary = request_row.get("sender_profile", {}) if request_row.get("sender_profile", {}) is Dictionary else {}
		var dedupe_key: String = _profile_dedupe_key(sender_profile)
		if dedupe_key.is_empty():
			dedupe_key = str(request_row.get("from_user", "")).strip_edges().to_lower()
		if dedupe_key.is_empty() or seen.has(dedupe_key):
			continue
		seen[dedupe_key] = true
		deduped.append(request_row)
	return deduped

# This function collapses duplicate outgoing requests that target the same visible username.
func _dedupe_friend_requests_by_target(requests: Array) -> Array:
	var deduped: Array = []
	var seen: Dictionary = {}
	for request_variant in requests:
		if not (request_variant is Dictionary):
			continue
		var request_row: Dictionary = request_variant
		var target_profile: Dictionary = request_row.get("target_profile", {}) if request_row.get("target_profile", {}) is Dictionary else {}
		var dedupe_key: String = _profile_dedupe_key(target_profile)
		if dedupe_key.is_empty():
			dedupe_key = str(request_row.get("to_user", "")).strip_edges().to_lower()
		if dedupe_key.is_empty() or seen.has(dedupe_key):
			continue
		seen[dedupe_key] = true
		deduped.append(request_row)
	return deduped

# This function derives one stable dedupe key for profile lists and social cards.
func _profile_dedupe_key(profile: Dictionary) -> String:
	var username: String = str(profile.get("username", "")).strip_edges().to_lower()
	if not username.is_empty():
		return username
	return str(profile.get("id", "")).strip_edges().to_lower()

func _build_friendship_pair(user_a: String, user_b: String) -> Dictionary:
	var clean_user_a: String = user_a.strip_edges()
	var clean_user_b: String = user_b.strip_edges()
	if clean_user_a <= clean_user_b:
		return {"user1": clean_user_a, "user2": clean_user_b}
	return {"user1": clean_user_b, "user2": clean_user_a}

# This function writes one canonical accepted friendship row after duplicate cleanup or acceptance.
func _upsert_friendship_pair(user_a: String, user_b: String, request_name: String) -> Dictionary:
	var pair: Dictionary = _build_friendship_pair(user_a, user_b)
	return await _request_json(
		"%s?on_conflict=user1,user2" % friendships_endpoint,
		HTTPClient.METHOD_POST,
		{
			"user1": str(pair.get("user1", "")).strip_edges(),
			"user2": str(pair.get("user2", "")).strip_edges(),
			"status": "accepted",
			"created_at": Time.get_datetime_string_from_system(true, true)
		},
		request_name,
		PackedStringArray(["Prefer: resolution=merge-duplicates,return=representation"]),
		true
	)

func _get_config_value(setting_suffix: String, env_name: String, fallback: String) -> String:
	var env_value: String = OS.get_environment(env_name).strip_edges() if not env_name.is_empty() else ""
	if not env_value.is_empty():
		return env_value
	var project_setting: String = "application/config/%s" % setting_suffix
	if ProjectSettings.has_setting(project_setting):
		return str(ProjectSettings.get_setting(project_setting, fallback)).strip_edges()
	return fallback

func _normalize_endpoint(endpoint: String) -> String:
	var clean_endpoint: String = endpoint.strip_edges()
	if clean_endpoint.is_empty():
		return "/"
	if clean_endpoint.begins_with("http://") or clean_endpoint.begins_with("https://"):
		return clean_endpoint
	if clean_endpoint.begins_with("/"):
		return clean_endpoint
	return "/" + clean_endpoint

func _make_error_result(endpoint: String, error_message: String, error_code: int = ERR_CANT_CONNECT, status_code: int = 0, data: Variant = null) -> Dictionary:
	return {
		"ok": false,
		"endpoint": endpoint,
		"status": status_code,
		"error_code": error_code,
		"error": error_message,
		"data": data
	}

func _extract_array_payload(payload: Variant) -> Array:
	if payload is Array:
		return payload
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		if payload_dict.has("data") and payload_dict["data"] is Array:
			return payload_dict["data"]
		return [payload_dict]
	return []

func get_direct_messages(peer: String, before := 0, after := 0) -> Dictionary:
	var auth: Dictionary = await _ensure_data_api_session("direct_messages")
	if not auth.get("ok", false): return auth
	return await _request_authenticated_auth_json("/social/messages/%s?before=%d&after=%d" % [peer.uri_encode(), before, after], HTTPClient.METHOD_GET, null, "direct_messages")

func send_direct_message(peer: String, text: String, request_id: String) -> Dictionary:
	var auth: Dictionary = await _ensure_data_api_session("send_direct_message")
	if not auth.get("ok", false): return auth
	return await _request_authenticated_auth_json("/social/messages/" + peer.uri_encode(), HTTPClient.METHOD_POST, {"text": text, "request_id": request_id}, "send_direct_message")

func vote_for_map(map_id: String, value: int) -> Dictionary:
	var auth: Dictionary = await _ensure_data_api_session("vote_for_map")
	if not auth.get("ok", false): return auth
	return await _request_authenticated_auth_json("/social/maps/" + map_id.uri_encode() + "/vote", HTTPClient.METHOD_POST, {"vote": value}, "vote_for_map")

func convert_roblox_place(path: String) -> Dictionary:
	var auth: Dictionary = await _ensure_data_api_session("import_place")
	if not bool(auth.get("ok", false)): return auth
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Не удалось открыть выбранный файл. Скопируйте его в Downloads и выберите снова."}
	if file.get_length() > 32 * 1024 * 1024:
		file.close()
		return {"ok": false, "error": "Мобильный импорт поддерживает файлы до 32 МБ."}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var headers := PackedStringArray(["Content-Type: application/octet-stream", "Authorization: Bearer " + _auth_access_token])
	return await _request_http_bytes(project_url.trim_suffix("/") + "/studio/import-place", HTTPClient.METHOD_POST, bytes, "import_place", headers, 60.0)


func _confirm_catalog_publication(payload: Dictionary) -> Dictionary:
	if str(payload.get("visibility", "public")) == "private": return {"ok": true, "fee": 0}
	var response: Dictionary = await _request_authenticated_auth_json("/creator/quote", HTTPClient.METHOD_POST,
		{"item_id": str(payload.get("id", "")), "category": str(payload.get("category", payload.get("item_kind", "model"))), "visibility": "public", "price_robux": payload.get("price_robux", null)}, "publication_quote")
	if not bool(response.get("ok", false)): return response
	var quote: Dictionary = response.get("data", {})
	if not bool(quote.get("allowed", false)):
		return {"ok": false, "error": str(quote.get("error", "Публикация недоступна."))}
	var fee := int(quote.get("fee", 0))
	if fee <= 0: return {"ok": true, "fee": 0}
	var dialog := ConfirmationDialog.new()
	dialog.title = "Публикация в каталоге"
	dialog.dialog_text = "Бесплатные публикации этого типа на месяц закончились.\nДополнительная публикация: %d Boblox.\nОсталось до общего месячного предела: %d.\nРедактирование этой вещи бесплатно." % [fee, int(quote.get("remaining", 0))]
	dialog.ok_button_text = "Опубликовать · %d Boblox" % fee
	dialog.cancel_button_text = "Отмена"
	var accepted := [false]
	dialog.confirmed.connect(func(): accepted[0] = true)
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 190))
	while is_instance_valid(dialog) and dialog.visible:
		await get_tree().process_frame
	dialog.queue_free()
	return {"ok": accepted[0], "fee": fee, "error": "Публикация отменена." if not accepted[0] else ""}
