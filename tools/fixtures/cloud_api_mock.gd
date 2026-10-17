extends "res://autoload/cloud_api.gd"
var auth_reply: Dictionary = {"ok":false,"status":503}
var friend_reply: Dictionary = {"ok":true,"data":[{"id":"friend-a"}]}
var refresh_calls := 0
var friend_calls := 0
var cleared := 0
func _ready() -> void: pass
func is_configured() -> bool: return true
func _save_auth_session() -> void: pass
func _clear_auth_session(_remove_file: bool = true) -> void:
	cleared += 1
	_auth_access_token = ""
	_auth_refresh_token = ""
	_auth_user_id = ""
func _validate_session_binding_for_current_user() -> bool: return true
func _request_auth_json(_endpoint: String, _method: HTTPClient.Method, _body: Variant, _request_name: String, _timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	refresh_calls += 1
	var reply := auth_reply.duplicate(true)
	await get_tree().create_timer(0.04).timeout
	return reply
func _fetch_friends_list() -> Dictionary:
	friend_calls += 1
	var reply := friend_reply.duplicate(true)
	await get_tree().create_timer(0.04).timeout
	return reply


