extends SceneTree
var _failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
func _fixture_scene(path: String, script_path: String) -> Control:
	var packed := load(path) as PackedScene
	var control := packed.instantiate() as Control
	var script := load(script_path) as Script
	if script == null or not script.can_instantiate():
		control.free()
		return null
	control.set_script(script)
	return control
func _run() -> void:
	await process_frame
	root.size = Vector2i(960, 640)
	var api: Node = root.get_node("CloudAPI")
	var mock := load("res://tools/fixtures/cached_shell_api.gd") as Script
	if not mock.can_instantiate():
		quit(1)
		return
	api.set_script(mock)
	var session: Node = root.get_node("UserSession")
	session.begin_cloud_session(api.fixture_user_id, "Cached Player")
	var login := _fixture_scene("res://scenes/login/login.tscn", "res://tools/fixtures/cached_shell_login.gd")
	root.add_child(login)
	_check(bool(login.fixture_opened_lobby), "saved session waits for authentication before opening cached lobby")
	_check(int(api.fixture_attempts) == 0, "cached login requested network profile before opening shell")
	_check(login.username_input == null, "remembered player sees a sign-in form flash")
	var connection_banner := root.get_node_or_null("StartupConnectionBanner")
	_check(connection_banner != null, "first saved-session connection has no startup status")
	if connection_banner != null:
		var label := connection_banner.find_child("ConnectionLabel", true, false) as Label
		_check(label != null and label.text == "Подключение к Бобукс…", "startup connection text is missing")
		_check(label != null and label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "startup status blocks input")
	login.free()
	api.fixture_authenticated = false
	login = _fixture_scene("res://scenes/login/login.tscn", "res://tools/fixtures/cached_shell_login.gd")
	root.add_child(login)
	await process_frame
	_check(not bool(login.fixture_opened_lobby), "login bypassed authentication without a saved cloud session")
	_check(login.login_button != null and not login.login_button.disabled, "fresh login is blocked")
	_check(login.get("_session_cover") == null, "fresh login is covered by a blocking startup screen")
	login.free()
	api.fixture_authenticated = true
	var lobby := _fixture_scene("res://scenes/lobby/lobby.tscn", "res://tools/fixtures/cached_shell_lobby.gd")
	root.add_child(lobby)
	current_scene = lobby
	await create_timer(0.25).timeout
	_check(int(api.fixture_attempts) == 1, "background authentication did not start")
	_check(lobby.get("_loading_overlay") == null, "lobby creates a blocking loading screen during background auth")
	var cached_grid := lobby.get("all_cards_grid") as Container
	_check(cached_grid != null and cached_grid.get_child_count() > 0, "cached modes do not render while authentication is pending")
	lobby.get_node("%NavCharacterBtn").emit_signal("pressed")
	await process_frame
	_check((lobby.get("main_tabs") as TabContainer).current_tab == 2, "navigation is blocked by background authentication")
	api.emit_signal("fixture_auth_completed", {"ok": false, "error": "fixture network timeout"})
	await process_frame
	var notice := lobby.get("_lobby_notice") as Control
	_check(notice != null and notice.is_visible_in_tree(), "temporary auth error has no visible inline retry on the active page")
	_check(lobby.get("_loading_overlay") == null, "auth error reintroduced a full-screen blocker")
	lobby.get("_lobby_notice_action").emit_signal("pressed")
	await process_frame
	await process_frame
	_check(int(api.fixture_attempts) == 2, "inline retry does not retry the failed profile sync")
	api.emit_signal("fixture_auth_completed", {"ok": true, "username": "Cached Player"})
	await process_frame
	_check(not notice.visible and bool(lobby.get("_lobby_bootstrap_finished")), "successful retry did not clear inline error")
	_check(root.get_node_or_null("StartupConnectionBanner") == null, "connection status survives authentication result")
	lobby.call("_show_loading_error", "Room connection failed", "Try joining again.")
	_check(lobby.get("_loading_overlay") == null and notice.visible, "room connection failure blocks the returned menu")
	lobby.call("_ensure_experience_loading_overlay")
	lobby.call("_show_loading_overlay", "Loading...", "Joining Cached experience", 0.2)
	_check((lobby.get("_loading_overlay") as Control).visible, "necessary per-mode joining progress was removed")
	lobby.queue_free()
	await process_frame
	print("CACHED_LOBBY_SHELL_RESULT=" + JSON.stringify({"ok": _failures.is_empty(), "failures": _failures, "auth_attempts": api.fixture_attempts}))
	quit(0 if _failures.is_empty() else 1)
