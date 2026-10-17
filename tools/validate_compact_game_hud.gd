extends SceneTree

class HudPlayer:
	extends CharacterBody3D
	var health: float = 72.75
	var maximum: float = 120.5
	func get_health() -> float: return health
	func get_max_health() -> float: return maximum

var failures: Array[String] = []
var activations: Dictionary = {"MenuButton": 0, "ChatButton": 0, "InventoryButton": 0, "AuthorButton": 0}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("[runtime-hud] ", "PASS " if ok else "FAIL ", message)

func touch(position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func mouse(position: Vector2, pressed: bool, emulated: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event, true)

func drag(position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = relative
	root.push_input(event, true)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var preferences: Node = root.get_node("ClientPreferences")
	var previous_preferences: Dictionary = preferences.values.duplicate(true)
	preferences.values["hud_style"] = "classic"
	preferences.values["app_theme"] = "halloween"
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/compact_hud_main.gd"))
	var player := HudPlayer.new()
	player.name = "HudTestPlayer"
	main.add_child(player)
	root.add_child(main)
	current_scene = main
	main._ensure_runtime_inventory_controller()
	main._update_local_player_hud()
	await process_frame
	await process_frame
	var curtain: Panel = main._mobile_top_bar
	var health: ProgressBar = main._health_bar
	var menu: Button = curtain.get_node("MenuButton")
	check(menu.icon != null and menu.icon.resource_path == "res://assets/ui/halloween/menu.svg", "classic Halloween menu uses three lines instead of the B logo")
	check(curtain.size.x == 1280 and curtain.size.y <= 50 and curtain.mouse_filter == Control.MOUSE_FILTER_IGNORE, "classic PC curtain is thin and spans the viewport")
	check(curtain.get_theme_stylebox("panel").bg_color.a > 0.34 and curtain.get_theme_stylebox("panel").bg_color.a < 0.55, "classic PC curtain is easier to see and remains translucent")
	check(health.value == player.health and health.max_value == player.maximum and health.step == 0.0 and not health.show_percentage, "HP preserves fractional damage and dynamic MaxHealth")
	check(health.size.y == 8 and health.mouse_filter == Control.MOUSE_FILTER_IGNORE, "classic HP is a plain green bar")
	check(not main._runtime_inventory_controller.get_node("InventoryRoot/OpenBackpack").visible, "there is one inventory button")
	await capture("hud_pc_classic")
	for button in main._runtime_hud_buttons:
		button.pressed.connect(func(): activations[str(button.name)] += 1)
	var router: Node = main._runtime_hud_touch_router
	# The real engine input path is used, never a manual button signal.
	var chat: Button = curtain.get_node("ChatButton")
	var point := chat.get_global_rect().get_center()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse(point, true, true)
	touch(point, true)
	mouse(point, false, true)
	touch(point, false)
	await process_frame
	check(activations.ChatButton == 1 and main.get_node("ChatBox").chat_visible, "touch with mouse emulation opens chat once while the game captures the pointer")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	touch(point, true)
	mouse(point, true, true)
	drag(point + Vector2(50, 0), Vector2(50, 0))
	touch(point + Vector2(50, 0), false)
	mouse(point + Vector2(50, 0), false, true)
	touch(point, true)
	touch(point, false, true)
	await process_frame
	check(activations.ChatButton == 1, "dragged and cancelled touches never activate a core button")
	mouse(point, true)
	mouse(point, false)
	await process_frame
	check(activations.ChatButton == 2, "ordinary desktop mouse still works")
	var inventory: Button = curtain.get_node("InventoryButton")
	point = inventory.get_global_rect().get_center()
	touch(point, true)
	touch(point, false)
	check(activations.InventoryButton == 1, "real touch activates inventory")
	main._set_runtime_top_hud_visible(false)
	touch(point, true)
	touch(point, false)
	check(activations.InventoryButton == 1, "hidden core HUD does not intercept modal/menu input")
	main._set_runtime_top_hud_visible(true)
	# An authored GUI outside our hit regions retains its native mouse route.
	var author_layer := CanvasLayer.new()
	author_layer.layer = 15
	main.add_child(author_layer)
	var author := Button.new()
	author.name = "AuthorButton"
	author.position = Vector2(200, 250)
	author.size = Vector2(120, 44)
	author.text = "Authored GUI"
	author_layer.add_child(author)
	author.pressed.connect(func(): activations.AuthorButton += 1)
	point = author.get_global_rect().get_center()
	touch(point, true)
	mouse(point, true, true)
	touch(point, false)
	mouse(point, false, true)
	await process_frame
	check(activations.AuthorButton == 1, "authored GUI input is unchanged")
	point = curtain.get_node("MenuButton").get_global_rect().get_center()
	touch(point, true)
	touch(point, false)
	check(activations.MenuButton == 1 and main._game_menu_panel.visible and not router.enabled, "real touch opens the game menu and suspends core HUD routing")
	await create_timer(0.24).timeout
	main.close_game_menu()
	await create_timer(0.18).timeout
	check(not main._game_menu_panel.visible and router.enabled, "closing the menu restores the HUD touch route")
	preferences.values["hud_style"] = "compact"
	preferences.changed.emit("hud_style", "compact")
	await process_frame
	check(curtain.size.x < 150 and main._runtime_player_status.visible and main._runtime_player_name.text.length() > 0, "compact style switches in place and displays the player name")
	check(health.size.y == 10 and curtain.get_node("MenuButton").pressed.is_connected(main._on_game_menu_button_pressed), "compact menu and green HP keep their game callbacks")
	await capture("hud_pc_compact")
	main.simulate_mobile = true
	main.safe_insets = Vector3(28, 20, 24)
	for window_size in [Vector2i(640, 360), Vector2i(360, 640), Vector2i(320, 568)]:
		root.size = window_size
		await process_frame
		main._layout_runtime_corner_hud()
		for style in ["classic", "compact"]:
			preferences.values["hud_style"] = style
			preferences.changed.emit("hud_style", style)
			await process_frame
			var last_button: Button = main._runtime_hud_buttons.back()
			print("[runtime-hud] layout viewport=", root.get_visible_rect(), " window=", root.size, " buttons=", last_button.get_global_rect(), " health=", health.get_global_rect())
			check(last_button.size.x >= 48 and last_button.size.y >= 48, "%s %s has reachable mobile buttons" % [window_size, style])
			check(last_button.get_global_rect().end.x <= health.get_global_rect().position.x and health.get_global_rect().end.x <= window_size.x - 24.0, "%s %s respects safe area without overlapping HP" % [window_size, style])
			check(main._runtime_hud_buttons[0].get_global_rect().position.x >= 28.0, "%s %s respects the left display cutout" % [window_size, style])
	preferences.values = previous_preferences
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/compact_hud")
		root.get_texture().get_image().save_png("user://validation/compact_hud/hud.png")
	print("RUNTIME_HUD_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "activations": activations}))
	main.free()
	check(not router.enabled and not router.is_processing_input(), "scene exit immediately disables the global touch route")
	# process_frame is emitted before queued deletes are flushed; a rendered
	# frame can resume this coroutine while the freed scene's router is queued.
	await process_frame
	await process_frame
	check(not is_instance_valid(router), "scene exit releases the touch router")
	if DisplayServer.get_name() != "headless":
		# The app autoload prefetches Lobby in a background resource worker. A
		# standalone HUD tool must let that worker finish before engine shutdown.
		await root.get_node("GameSceneLoader").get_lobby()
	quit(0 if failures.is_empty() else 1)

func capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://validation/compact_hud")
	root.get_texture().get_image().save_png("user://validation/compact_hud/%s.png" % file_name)
