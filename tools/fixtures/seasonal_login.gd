extends "res://scripts/login/login.gd"

func _try_restore_saved_session(_remembered_username: String) -> void:
	if is_instance_valid(_session_cover): _session_cover.queue_free()
	status_label.text = "Sign in to continue."
