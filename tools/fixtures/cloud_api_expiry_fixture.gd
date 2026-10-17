extends "res://tools/fixtures/cloud_api_mock.gd"
const SAVED_PATH := "user://validation/auth_expiry/synthetic_session.json"
func _get_auth_session_candidates() -> Array[String]: return [SAVED_PATH]
