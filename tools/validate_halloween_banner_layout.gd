extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	print("[halloween-layout] ", "PASS " if ok else "FAIL ", detail)
	if not ok: failures.append(detail)

func settle(frames: int = 15) -> void:
	for _frame in range(frames): await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.codex-tmp/final_event_" + name + ".png")

func run() -> void:
	await process_frame
	root.get_node("ClientPreferences").values.app_theme = "halloween"
	root.get_node("MobileRuntime").set("_is_mobile_beta", true)
	# Real Huawei physical dimensions and the release project's canvas scale.
	root.size = Vector2i(2000, 1200)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await settle()
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(load("res://tools/fixtures/seasonal_lobby.gd"))
	lobby.set_meta("boblox_preview", true)
	lobby.set_meta("catalog_preview_items", [])
	lobby.set_meta("halloween_preview_state", {"can_claim_gift": true, "items": []})
	# The premiere covers and suspends the lobby before its first layout. This
	# reproduces the physical-device failure that tab re-entry used to repair.
	lobby.hide()
	lobby.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(lobby)
	current_scene = lobby
	await create_timer(0.5).timeout
	lobby.process_mode = Node.PROCESS_MODE_INHERIT
	lobby.show()
	await settle()
	var banner := lobby.find_child("HalloweenWelcome", true, false) as Control
	var home := lobby.get_node("%MainTabs/HomeView") as ScrollContainer
	check(banner is PanelContainer, "banner uses native container measurement")
	check(banner.size.y >= 108 and banner.size.y <= 170, "first Huawei Home banner remains compact: " + str(banner.size.y))
	check(banner.get_global_rect().size.x <= home.size.x + 1, "banner stays inside the Home width")
	check(home.scroll_vertical == 0 and lobby.home_friends_clip.global_position.y < home.get_global_rect().end.y, "greeting and Friends are visible without swiping past the premiere banner")
	check(banner.find_child("HalloweenCatalogOpen", true, false) != null and banner.find_child("HalloweenTrailerReplay", true, false) != null, "catalog and replay actions remain available")
	print("HUAWEI_UI_DIMS=", JSON.stringify({"window": str(root.size), "logical": str(root.get_visible_rect().size), "banner": str(banner.size)}))
	await capture("home_huawei_canvas")
	lobby.call("_switch_tab", 2)
	await settle()
	var avatar := lobby.get_node("%MainTabs/AvatarView") as Control
	check(avatar.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "Huawei Avatar remains within the logical screen")
	lobby.call("_switch_tab", 0)
	await settle()
	check(banner.size.y <= 170, "returning from Avatar does not alter first-visit banner height")
	# Also validate narrow portrait layout, including its two touch actions.
	root.size = Vector2i(480, 800)
	root.content_scale_size = root.size
	await settle(25)
	check(banner.size.y <= 270, "narrow portrait banner does not retain a transient wrapped height: " + str(banner.size.y))
	check(banner.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "portrait banner does not overflow horizontally")
	var replay := banner.find_child("HalloweenTrailerReplay", true, false) as Control
	check(banner.get_global_rect().encloses(replay.get_global_rect()), "portrait replay remains inside banner bounds")
	await capture("home_portrait_banner")
	# Wider 19.5:9 phone viewport with the same release base resolution.
	root.size = Vector2i(2340, 1080)
	root.content_scale_size = Vector2i(1280, 720)
	await settle(25)
	check(banner.size.y <= 170, "wide phone canvas does not stretch banner height")
	await capture("home_phone_canvas")
	print("HALLOWEEN_BANNER_LAYOUT_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	lobby.queue_free()
	await settle(5)
	quit(0 if failures.is_empty() else 1)
