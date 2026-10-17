extends SceneTree
var failures := []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print("[lobby-retry] ", message, "=", value)
	if not value: failures.append(message)
func run() -> void:
	var lobby: Node = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(load("res://tools/fixtures/lobby_network_retry.gd"))
	root.add_child(lobby)
	lobby.home_friends_container = HBoxContainer.new()
	lobby.add_child(lobby.home_friends_container)
	lobby.home_friends_status = Label.new()
	lobby.add_child(lobby.home_friends_status)
	lobby._lobby_bootstrap_active = false
	await lobby._refresh_home_friends_section()
	check(lobby.requests == 1 and lobby._next_home_friends_refresh_allowed_msec > 0, "first failure schedules retry")
	check(lobby.presence_requests == 0, "room presence does not delay friend list")
	lobby.reply = {"ok": true, "data": [{"id": "test", "username": "Friend"}]}
	lobby._next_home_friends_refresh_allowed_msec = Time.get_ticks_msec() - 1
	lobby._poll_home_network_retries()
	while lobby._home_friends_refresh_in_flight: await process_frame
	await process_frame
	check(lobby.requests == 2 and lobby.home_friends_container.get_child_count() == 1, "recovers without reopening lobby")
	lobby._home_friends_cache_expires_msec = 0
	lobby.reply = {"ok": false, "status": 503}
	await lobby._refresh_home_friends_section()
	check(lobby.home_friends_container.get_child_count() == 1, "refresh failure keeps visible friends")
	lobby._next_home_friends_refresh_allowed_msec = 0
	lobby.reply = {"ok": true, "stale": true, "data": [{"id": "test", "username": "Friend"}]}
	await lobby._refresh_home_friends_section()
	check(lobby._next_home_friends_refresh_allowed_msec > 0, "stale cache still retries")
	lobby.queue_free()
	await process_frame
	print("[lobby-retry] failures=", failures)
	quit(0 if failures.is_empty() else 1)
