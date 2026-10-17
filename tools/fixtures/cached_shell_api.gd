extends "res://autoload/cloud_api.gd"
signal fixture_auth_completed(result: Dictionary)
var fixture_authenticated := true
var fixture_user_id := "ui_cached_shell_user"
var fixture_attempts := 0

func has_authenticated_session() -> bool: return fixture_authenticated
func get_current_user_id() -> String: return fixture_user_id
func get_current_username() -> String: return "Cached Player"
func is_configured() -> bool: return true
func authenticate_or_create_profile(_preferred_username: String = "", _allow_generated_username: bool = true) -> Dictionary:
	fixture_attempts += 1
	return await fixture_auth_completed
func fetch_legends() -> Dictionary: return {"ok": true, "games": []}
func update_profile_presence(_status: String, _current_game: String = "", _extra_fields: Dictionary = {}) -> Dictionary: return {"ok": true}

