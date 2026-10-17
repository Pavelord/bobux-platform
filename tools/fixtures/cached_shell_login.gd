extends "res://scripts/login/login.gd"
var fixture_opened_lobby := false
func _go_to_lobby() -> void: fixture_opened_lobby = true
func _try_restore_saved_session(_remembered_username: String) -> void: pass

