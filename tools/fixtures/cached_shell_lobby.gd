extends "res://scripts/lobby/lobby.gd"
func _schedule_home_dashboard_refresh(_force: bool = false) -> void: pass
func _poll_home_network_retries() -> void: pass
func _poll_lobby_presence_heartbeat_if_needed() -> void: pass
func _poll_lobby_friend_requests_if_needed() -> void: pass
func _request_avatar_inventory_load() -> void: pass
func _get_cached_published_map_records() -> Array:
	return [{"id": "fixture_cached_place", "name": "Cached experience", "creator_username": "Cached Player"}]

