extends SceneTree

var failures: Array[String] = []
var opened: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	print("[support] ", "PASS " if ok else "FAIL ", detail)
	if not ok: failures.append(detail)
func settle(frames: int = 8) -> void:
	for _frame in range(frames): await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.codex-tmp/final_support_" + name + ".png")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("ClientPreferences").values.app_theme = "halloween"
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(load("res://tools/fixtures/seasonal_lobby.gd"))
	lobby.set_meta("boblox_preview", true)
	root.add_child(lobby)
	current_scene = lobby
	await create_timer(1).timeout
	var controller := lobby.get_node_or_null("BobuxSupport")
	check(controller != null, "support controller loads")
	if controller == null: quit(1); return
	controller.external_opener = func(url: String) -> Error: opened.append(url); return OK
	var sidebar := lobby.get_node("Body/HBox/Sidebar")
	var holder := sidebar.get_node("SupportSidebar") as Control
	check(holder.get_index() + 1 == sidebar.get_node("UpgradeBtn").get_index(), "support sits immediately above Bricks Club")
	check(holder.has_meta("seasonal_ignore") and holder.get_child(0).material is ShaderMaterial, "rainbow is not repainted by the seasonal theme")
	var button := holder.find_child("SupportButton", true, false) as Button
	check(button != null and button.text == "Поддержать", "visible support action has the requested label")
	await capture("sidebar")
	button.pressed.emit()
	await settle()
	var popup: CanvasLayer = controller._popup
	check(popup != null and not quit_on_go_back, "dialog opens and Android Back cannot quit underneath it")
	var donate := popup.find_child("OpenDonationAlerts", true, false) as Button
	check(donate.get_meta("external_url") == "https://www.donationalerts.com/r/bobux_ceo", "donation URL is exact")
	donate.pressed.emit()
	check(opened == ["https://www.donationalerts.com/r/bobux_ceo"], "one user action opens the support page, without messages or currency grants")
	var telegram := popup.find_child("OpenSupportTelegram", true, false) as Button
	telegram.pressed.emit()
	check(opened[-1] == "https://t.me/pavelord", "Telegram opens the requested profile link")
	await capture("desktop_dialog")
	root.size = Vector2i(360, 480)
	root.content_scale_size = root.size
	await settle(20)
	var panel: Control = controller._panel
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(panel.get_global_rect()), "mobile dialog stays inside the screen")
	var scroll := popup.find_child("SupportScroll", true, false) as ScrollContainer
	check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "mobile text wraps without horizontal scrolling")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await settle()
	var close := popup.find_child("CloseSupportDialog", true, false) as Button
	check(scroll.get_global_rect().encloses(close.get_global_rect()), "close action remains reachable by scrolling")
	await capture("mobile_dialog")
	controller.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await settle()
	check(controller._popup == null and quit_on_go_back, "Android Back closes the dialog and restores its previous behavior")
	var menu := lobby.find_child("HeaderNavigation", true, false) as MenuButton
	menu.get_popup().id_pressed.emit(100)
	await settle()
	check(controller._popup != null, "compact mobile navigation can open support without a sidebar")
	controller.close_dialog()
	await settle()
	print("SUPPORT_DIALOG_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "external_actions": opened.size()}))
	lobby.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
