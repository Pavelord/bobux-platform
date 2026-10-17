extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var desktop := OS.get_cmdline_user_args().has("--desktop")
	root.size = Vector2i(1280, 720) if desktop else Vector2i(480, 800)
	root.content_scale_size = root.size
	await process_frame
	root.get_node("ClientPreferences").values.app_theme = "halloween"
	var lobby := (load("res://scenes/lobby/lobby.tscn") as PackedScene).instantiate() as Control
	lobby.set_script(load("res://tools/fixtures/seasonal_lobby.gd"))
	lobby.set_meta("bobux_compact_layout_override", not desktop)
	lobby.set_meta("boblox_preview", true)
	lobby.set_meta("catalog_preview_items", [])
	lobby.set_meta("halloween_preview_state", {"can_claim_gift": true, "gift_owned": false, "pumpkin_owned": false, "items": [
		{"id":"event_halloween_2026_gift","name":"Coffin Gift Box - Halloween","owner_name":"Bobux","category":"accessory","source_url":"res://assets/events/halloween2026/gift.glb","data":{"art_version":4},"owned":false},
		{"id":"event_halloween_2026_pumpkin","name":"Pumpkin","owner_name":"Bobux","category":"accessory","source_url":"res://assets/events/halloween2026/pumpkin.glb","data":{"art_version":4},"owned":false}
	]})
	root.add_child(lobby)
	current_scene = lobby
	await create_timer(1).timeout
	var builder: Script = load("res://scripts/lobby/catalog_builder.gd")
	if builder == null or not builder.can_instantiate(): quit(1); return
	var tabs := lobby.get_node("%MainTabs") as TabContainer
	var view := tabs.get_node("CatalogView") as ScrollContainer
	var banner_action := lobby.find_child("HalloweenCatalogOpen", true, false) as Button
	if banner_action == null: failures.append("Home Halloween banner catalog button missing")
	else: banner_action.pressed.emit()
	await process_frame
	if tabs.current_tab != view.get_index(): failures.append("Home banner did not select Catalog")
	var event_button := view.find_child("HalloweenTab", true, false) as Button
	if event_button == null: failures.append("missing Halloween tab")
	await create_timer(1).timeout
	var event_view := view.find_child("HalloweenCatalog", true, false) as VBoxContainer
	if event_view == null or not event_view.visible: failures.append("Halloween page hidden")
	else:
		var claim_count := 0
		var locked_count := 0
		for button in event_view.find_children("*", "Button", true, false):
			if button.text == "Забрать подарок" and not button.disabled: claim_count += 1
			if button.text == "31 октября" and button.disabled: locked_count += 1
		if claim_count != 1 or locked_count != 0: failures.append("event must contain only the claimable gift")
		for label in event_view.find_children("*", "Label", true, false):
			if "тыкв" in label.text.to_lower() or "pumpkin" in label.text.to_lower(): failures.append("gift page reveals the surprise reward")
		if event_view.find_children("HalloweenBadge", "PanelContainer", true, false).size() != 1: failures.append("missing Halloween 2026 badge")
		var badge := event_view.find_child("HalloweenBadge", true, false) as Control
		if badge != null and (badge.get_child(0) as Label).text != "Halloween 2026": failures.append("wrong seasonal badge text")
		if badge != null and not (badge.get_parent() as Control).get_global_rect().encloses(badge.get_global_rect()): failures.append("Halloween badge outside preview")
		if event_view.get_global_rect().size.x > root.get_visible_rect().size.x: failures.append("mobile page overflow")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/halloween")
		root.get_texture().get_image().save_png("user://validation/halloween/catalog.png")
		root.get_texture().get_image().save_png("res://.codex-tmp/final_event_catalog_desktop.png" if desktop else "res://.codex-tmp/final_event_catalog_mobile.png")
		if not desktop:
			view.scroll_vertical = int(view.get_v_scroll_bar().max_value)
			await process_frame
			await RenderingServer.frame_post_draw
			var claim := event_view.find_child("ClaimHalloweenGift", true, false) as Button
			if claim == null or not view.get_global_rect().encloses(claim.get_global_rect()): failures.append("mobile gift claim is not reachable by scrolling")
			root.get_texture().get_image().save_png("res://.codex-tmp/final_event_catalog_mobile_scrolled.png")
		# Preview coroutines finish their current draw before the fixture exits.
		for _frame in range(4): await process_frame
	print("HALLOWEEN_CATALOG_RESULT=",JSON.stringify({"ok":failures.is_empty(),"failures":failures}))
	lobby.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
