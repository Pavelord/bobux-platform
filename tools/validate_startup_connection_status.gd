extends SceneTree
const BANNER := preload("res://scripts/ui/startup_connection_banner.gd")
var failures: Array[String] = []
var clicks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	await process_frame
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(960, 640)
	root.get_node("ClientPreferences").values.app_theme = "halloween"
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(load("res://tools/fixtures/seasonal_lobby.gd"))
	root.add_child(lobby)
	current_scene = lobby
	BANNER.begin(self)
	await create_timer(0.25).timeout
	var banner: Node = root.get_node_or_null("StartupConnectionBanner")
	check(banner != null, "initial connection status is missing")
	var label := banner.find_child("ConnectionLabel", true, false) as Label
	check(label != null and label.text == "Подключение к Бобукс…" and label.get_theme_color("font_color") == Color("ffc18a"), "connection state does not use Halloween text")
	# Only this initial splash covers input, never later menu/return transitions.
	var beneath := Button.new()
	beneath.position = Vector2(400, 15)
	beneath.size = Vector2(160, 45)
	lobby.add_child(beneath)
	beneath.pressed.connect(func(): clicks += 1)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = beneath.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	check(clicks == 0, "initial splash does not cover the lobby input")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/halloween")
		root.get_texture().get_image().save_png("user://validation/halloween/startup_connection.png")
		root.get_texture().get_image().save_png("res://.codex-tmp/startup_connection_final.png")
	BANNER.finish(self)
	var deadline := Time.get_ticks_msec() + 3000
	while root.get_node_or_null("StartupConnectionBanner") != null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(root.get_node_or_null("StartupConnectionBanner") == null, "connection state is not released when authentication finishes")
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	check(clicks == 1, "splash left an invisible input blocker behind")
	beneath.queue_free()
	BANNER.begin(self)
	check(root.get_node_or_null("StartupConnectionBanner") == null, "connection state reappears when returning from a mode")
	lobby.queue_free()
	await process_frame
	print("STARTUP_CONNECTION_STATUS_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures, "clicks": clicks}))
	quit(0 if failures.is_empty() else 1)
