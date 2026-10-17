extends SceneTree
var _failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func _check(ok: bool, detail: String) -> void:
	if not ok: _failures.append(detail)

func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(480, 800)
	var prefs: Node = root.get_node("ClientPreferences")
	prefs.values.app_theme = "halloween"
	var packed: PackedScene = load("res://scenes/lobby/lobby.tscn")
	var lobby: Control = packed.instantiate()
	var fixture: Script = load("res://tools/fixtures/seasonal_lobby.gd")
	if not fixture.can_instantiate():
		quit(1)
		return
	lobby.set_script(fixture)
	lobby.set_meta("bobux_mobile_layout_override", true)
	root.add_child(lobby)
	current_scene = lobby
	await create_timer(0.5).timeout
	lobby.call("_switch_tab", 2)
	await create_timer(0.5).timeout
	var view: Control = lobby.get_node("%MainTabs/AvatarView")
	var row := view.get_node("Content/MainRow")
	var grid := view.find_child("WardrobeGrid", true, false) as GridContainer
	var wardrobe_scroll := view.find_child("WardrobeScroll", true, false) as ScrollContainer
	_check(row is VBoxContainer, "portrait avatar does not stack")
	_check(grid != null and grid.columns >= 1 and grid.columns <= 3, "portrait wardrobe columns overflow")
	_check(wardrobe_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "nested portrait wardrobe traps page gestures")
	_check(grid.get_combined_minimum_size().x <= view.size.x + 1, "portrait wardrobe wider than visible viewport")
	var portrait_preview := view.find_child("PreviewPanel", true, false) as Control
	_check(portrait_preview.size.y <= 290, "mobile preview consumes excessive vertical space")
	var palette := view.find_child("ColorGrid", true, false) as GridContainer
	_check(palette.columns == 3, "mobile palette does not fit compact rows")
	var torso := view.find_child("BtnTorso", true, false) as Button
	_check(torso.has_meta("seasonal_preserve_color"), "body part selection lost actual avatar color")
	_check((torso.get_theme_stylebox("normal") as StyleBoxFlat).bg_color != preload("res://scripts/ui/seasonal_theme.gd").SURFACE, "theme painted avatar body diagram dark")
	var overlay := view.find_child("AvatarPreviewInputOverlay", true, false) as Control
	var mobile: Node = root.get_node("MobileRuntime")
	_check(mobile.call("_find_scroll_container_at", lobby, overlay.get_global_rect().get_center()) == null, "avatar orbit drag is mistaken for a page swipe")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/halloween")
		root.get_texture().get_image().save_png("user://validation/halloween/avatar_portrait.png")
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout
	row = view.get_node("Content/MainRow")
	_check(row is HBoxContainer, "landscape avatar stays incorrectly stacked after resize")
	_check(grid.columns >= 3 and grid.columns <= 5, "landscape wardrobe not fitted to available width")
	_check(grid.get_combined_minimum_size().x <= wardrobe_scroll.size.x + 2, "landscape wardrobe overflows horizontally")
	var preview := view.find_child("PreviewPanel", true, false) as Control
	var viewport := preview.find_child("SubViewport", true, false) as SubViewport
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "hidden preview keeps rendering")
	_check(lobby.get_node_or_null("MobileBetaBanner") == null and not _has_beta_label(lobby), "visible mobile beta branding remains")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://validation/halloween/avatar_landscape.png")
	print("AVATAR_RESPONSIVE_RESULT=" + JSON.stringify({"ok": _failures.is_empty(), "failures": _failures, "columns": grid.columns}))
	lobby.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _has_beta_label(node: Node) -> bool:
	if node is Label and "mobile beta" in (node as Label).text.to_lower(): return true
	for child in node.get_children():
		if _has_beta_label(child): return true
	return false
