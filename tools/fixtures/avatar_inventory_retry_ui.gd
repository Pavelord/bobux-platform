extends "res://scripts/lobby/avatar_ui.gd"
var fixture_api: Node
func _get_cloud_api() -> Node: return fixture_api
func _get_current_user_id() -> String: return "retry_owner"
func _refresh_ui() -> void: pass
func _group_catalog() -> void: pass
func _apply_visuals_to_preview_player() -> void: pass
func _queue_avatar_sync() -> void: pass
