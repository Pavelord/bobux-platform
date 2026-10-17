extends SceneTree
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var prefs: Node = root.get_node("ClientPreferences")
	prefs.values.app_theme = "halloween"
	prefs.apply()
	if DisplayServer.get_name() != "headless" and prefs.get("_applied_window_icon_path") != "res://assets/branding/halloween/bobux_app_icon.png":
		_failures.append("Halloween running-window icon was not applied")
	root.get_node("UserSession").set("username", "Pavelord")
	var page := "lobby"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--page="): page = argument.trim_prefix("--page=")
	var scene: PackedScene = load("res://scenes/login/login.tscn" if page == "login" else "res://scenes/lobby/lobby.tscn")
	var surface: Control = scene.instantiate()
	var fixture: Script = load("res://tools/fixtures/seasonal_login.gd" if page == "login" else "res://tools/fixtures/seasonal_lobby.gd")
	if fixture == null or not fixture.can_instantiate():
		push_error("Seasonal visual fixture failed to compile")
		quit(1)
		return
	surface.set_script(fixture)
	root.add_child(surface)
	current_scene = surface
	await create_timer(2.5).timeout
	if page == "settings":
		var settings: Control = load("res://scripts/lobby/client_settings.gd").new()
		settings.name = "ClientSettings"
		surface.add_child(settings)
		await create_timer(0.5).timeout
		var tabs := settings.get("_tabs") as TabContainer
		tabs.current_tab = 3
		await process_frame
	await RenderingServer.frame_post_draw
	var folder := "user://validation/halloween"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(page + ".png"))
	prefs.values.app_theme = "classic"
	prefs.apply()
	prefs.emit_signal("changed", "app_theme", "classic")
	if prefs.get("_applied_window_icon_path") != "res://icon.svg": _failures.append("Classic running-window icon was not restored")
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("classic_" + page + ".png"))
	prefs.values.app_theme = "halloween"
	prefs.apply()
	prefs.emit_signal("changed", "app_theme", "halloween")
	await process_frame
	root.get_node("CloudAPI").call("_cleanup_active_http_requests")
	surface.queue_free()
	await process_frame
	await process_frame
	print("SEASONAL_UI_RESULT=" + JSON.stringify({"ok": _failures.is_empty(), "page": page, "image": ProjectSettings.globalize_path(folder.path_join(page + ".png")), "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
