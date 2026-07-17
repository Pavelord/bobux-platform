extends Node

# Legacy compatibility shim.
#
# Bobux no longer talks to Supabase directly. This autoload is still named
# SupabaseClient because older scenes/scripts call it, but every meaningful
# operation is delegated to CloudAPI, which points at the VPS Bobux API.
# Do not add new Supabase-specific behavior here.

var compat_base_url: String = ""
var compat_api_key: String = ""

func _ready() -> void:
	_refresh_from_cloud_api()
	if CloudAPI != null:
		if CloudAPI.has_signal("auth_session_ready") and not CloudAPI.auth_session_ready.is_connected(_on_auth_session_changed):
			CloudAPI.auth_session_ready.connect(_on_auth_session_changed)
		if CloudAPI.has_signal("auth_session_failed") and not CloudAPI.auth_session_failed.is_connected(_on_auth_session_failed):
			CloudAPI.auth_session_failed.connect(_on_auth_session_failed)

func _refresh_from_cloud_api() -> void:
	if CloudAPI == null:
		compat_base_url = ""
		compat_api_key = ""
		return
	compat_base_url = str(CloudAPI.project_url).strip_edges().trim_suffix("/")
	compat_api_key = str(CloudAPI.api_key).strip_edges()

func _on_auth_session_changed(_session: Dictionary) -> void:
	_refresh_from_cloud_api()

func _on_auth_session_failed(_message: String) -> void:
	_refresh_from_cloud_api()

func ensure_authenticated_session() -> Dictionary:
	_refresh_from_cloud_api()
	if CloudAPI == null:
		return {"ok": false, "error": "CloudAPI is unavailable."}
	return await CloudAPI.ensure_authenticated_session()

func get_user_id() -> String:
	if CloudAPI == null:
		return ""
	return str(CloudAPI.get_current_user_id()).strip_edges()

func get_access_token() -> String:
	if CloudAPI == null:
		return ""
	var session: Dictionary = CloudAPI.get_current_auth_session()
	return str(session.get("access_token", "")).strip_edges()

func get_refresh_token() -> String:
	if CloudAPI == null:
		return ""
	var session: Dictionary = CloudAPI.get_current_auth_session()
	return str(session.get("refresh_token", "")).strip_edges()

func get_access_token_expiry_unix() -> int:
	if CloudAPI == null:
		return 0
	var session: Dictionary = CloudAPI.get_current_auth_session()
	return int(session.get("expires_at", 0))

func get_rest_url() -> String:
	_refresh_from_cloud_api()
	if compat_base_url.is_empty():
		return ""
	return "%s/rest/v1" % compat_base_url

func get_realtime_url() -> String:
	_refresh_from_cloud_api()
	if compat_base_url.is_empty() or compat_api_key.is_empty():
		return ""
	var ws_base: String = compat_base_url
	if ws_base.begins_with("https://"):
		ws_base = "wss://%s" % ws_base.trim_prefix("https://")
	elif ws_base.begins_with("http://"):
		ws_base = "ws://%s" % ws_base.trim_prefix("http://")
	return "%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [ws_base, compat_api_key.uri_encode()]

func build_rest_headers() -> PackedStringArray:
	_refresh_from_cloud_api()
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json"
	])
	if not compat_api_key.is_empty():
		headers.append("apikey: %s" % compat_api_key)
	var access_token: String = get_access_token()
	if not access_token.is_empty():
		headers.append("Authorization: Bearer %s" % access_token)
	elif not compat_api_key.is_empty():
		headers.append("Authorization: Bearer %s" % compat_api_key)
	return headers

func is_configured() -> bool:
	_refresh_from_cloud_api()
	return not compat_base_url.is_empty() and not compat_api_key.is_empty()
