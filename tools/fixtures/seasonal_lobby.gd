extends "res://scripts/lobby/lobby.gd"

func _bootstrap_cloud_lobby() -> void:
	_lobby_bootstrap_active = false
	_lobby_bootstrap_finished = true
	_hide_loading_overlay()
	var grid := get_node_or_null("%MainTabs/HomeView/Content/ContinuePanel/Content/ContinueCards")
	if grid == null: grid = continue_cards_container
	if grid != null:
		for child in grid.get_children(): child.queue_free()
		for title in ["Бобукс парк", "Долина семи ветров", "Natural Disaster", "Нормальный лифт"]:
			grid.add_child(_create_smart_play_card({"id": "fixture_" + title, "name": title, "active_players": 12}, true))

func _schedule_home_dashboard_refresh(_force: bool = false) -> void:
	pass

func _poll_lobby_presence_heartbeat_if_needed() -> void:
	pass

func _poll_lobby_friend_requests_if_needed() -> void:
	pass

func _request_avatar_inventory_load() -> void:
	pass
