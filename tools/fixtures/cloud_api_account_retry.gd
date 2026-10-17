extends "res://autoload/cloud_api.gd"
var replies: Array = []
var request_calls := 0
var refresh_calls := 0
var cleared := 0
func _ready() -> void: pass
func _has_valid_access_session() -> bool: return true
func _request_json(_endpoint: String, _method: HTTPClient.Method, _body: Variant, _request_name: String, _headers: PackedStringArray = PackedStringArray(), _auth: bool = true, _timeout: float = HTTP_REQUEST_TIMEOUT_SECONDS) -> Dictionary:
	request_calls += 1
	var response := replies.pop_front() as Dictionary
	await get_tree().create_timer(0.04).timeout
	return response
func _refresh_authenticated_session() -> Dictionary:
	refresh_calls += 1
	await get_tree().create_timer(0.04).timeout
	return {"ok": true}
func _clear_auth_session(_remove_saved: bool = false) -> void:
	cleared += 1
	_auth_access_token = ""
	_auth_refresh_token = ""
func _exit_tree() -> void: pass
