extends SceneTree
const SEASONAL := preload("res://scripts/ui/seasonal_theme.gd")
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, detail: String) -> void:
	if not ok: _failures.append(detail)

func _run() -> void:
	await process_frame
	var prefs: Node = root.get_node("ClientPreferences")
	var old: Dictionary = prefs.values.duplicate(true)
	prefs.values.app_theme = "halloween"
	var surface := Panel.new()
	surface.name = "AppSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var original_theme := Theme.new()
	original_theme.default_font_size = 18
	surface.theme = original_theme
	root.add_child(surface)
	var label := Label.new()
	label.name = "OriginalLabel"
	label.text = "Bobux Halloween"
	label.add_theme_color_override("font_color", Color("123456"))
	surface.add_child(label)
	var panel := Panel.new()
	var original_style := StyleBoxFlat.new()
	original_style.bg_color = Color.WHITE
	original_style.content_margin_left = 21
	panel.add_theme_stylebox_override("panel", original_style)
	surface.add_child(panel)
	var portrait := Panel.new()
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color.WHITE
	portrait_style.set_corner_radius_all(48)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	surface.add_child(portrait)
	var swatch := Button.new()
	swatch.set_meta("seasonal_preserve_color", true)
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = Color.GREEN
	swatch.add_theme_stylebox_override("normal", swatch_style)
	surface.add_child(swatch)
	var nav := Button.new()
	nav.name = "NavHomeBtn"
	nav.text = "Home"
	var original_icon: Texture2D = load("res://assets/textures/icons/home.svg")
	nav.icon = original_icon
	surface.add_child(nav)
	var viewport := SubViewport.new()
	surface.add_child(viewport)
	var author_label := Label.new()
	author_label.add_theme_color_override("font_color", Color.BLUE)
	viewport.add_child(author_label)
	var controller := SEASONAL.mount(surface)
	_check(panel.get_theme_stylebox("panel") != original_style, "initial page was white before the first frame")
	_check((portrait.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left == 48, "Home/Friends portrait circle was replaced by a square")
	var games := Button.new()
	games.name = "Nav1"
	games.icon = original_icon
	surface.add_child(games)
	var catalog := Button.new()
	catalog.name = "Nav2"
	catalog.icon = original_icon
	surface.add_child(catalog)
	_check(games.icon == null and catalog.icon == null, "Games/Catalog still contain seasonal icons")
	var limited: PanelContainer = load("res://scripts/lobby/catalog_builder.gd").limited_badge()
	surface.add_child(limited)
	_check((limited.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Color("399341"), "Limited green badge was recolored")
	_check((limited.get_child(0) as Label).get_theme_color("font_color") == Color.WHITE, "Limited white text was recolored")
	var hidden_page := Panel.new()
	hidden_page.visible = false
	surface.add_child(hidden_page)
	for i in range(150):
		var hidden_panel := Panel.new()
		hidden_panel.add_theme_stylebox_override("panel", original_style)
		hidden_page.add_child(hidden_panel)
	controller.prepare_page(hidden_page)
	for hidden_panel: Panel in hidden_page.get_children():
		_check((hidden_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == SEASONAL.SURFACE, "selected subtree was not dark before visibility")
	hidden_page.visible = true
	await process_frame
	_check(label.get_theme_color("font_color") == SEASONAL.TEXT, "app label did not adopt seasonal orange")
	_check(panel.get_theme_stylebox("panel") != original_style, "panel still has light background")
	_check((panel.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left == 21, "panel spacing changed")
	_check((panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left == original_style.corner_radius_top_left and (panel.get_theme_stylebox("panel") as StyleBoxFlat).border_width_left == 1, "seasonal panel changed authored framing")
	_check(swatch.get_theme_stylebox("normal") == swatch_style, "avatar swatch was recolored")
	_check(author_label.get_theme_color("font_color") == Color.BLUE, "author preview interface was changed")
	_check(nav.icon != original_icon, "seasonal navigation icon missing")
	var late := Label.new()
	late.add_theme_color_override("font_color", Color("456789"))
	surface.add_child(late)
	await process_frame
	await process_frame
	_check(late.get_theme_color("font_color") == SEASONAL.TEXT, "late app control not themed")
	late.add_theme_color_override("font_color", Color("654321"))
	await process_frame
	await process_frame
	_check(late.get_theme_color("font_color") == SEASONAL.TEXT, "async style update escaped season")
	late.reparent(panel)
	await process_frame
	await process_frame
	_check(late.get_theme_color("font_color") == SEASONAL.TEXT, "responsive reparenting lost seasonal style")
	prefs.values.app_theme = "classic"
	controller.refresh()
	_check(surface.theme == original_theme, "root theme not restored")
	_check(label.get_theme_color("font_color") == Color("123456"), "original label color not restored")
	_check(panel.get_theme_stylebox("panel") == original_style, "original StyleBox not restored")
	_check(nav.icon == original_icon, "original navigation icon not restored")
	_check(games.icon == original_icon and catalog.icon == original_icon, "classic header icons were not restored")
	_check(late.get_theme_color("font_color") == Color("654321"), "latest async app style not retained for rollback")
	_check(not swatch.has_theme_color_override("font_color"), "inherited classic color became a permanent override")
	prefs.values = old
	surface.queue_free()
	await process_frame
	print("SEASONAL_THEME_RESULT=" + JSON.stringify({"ok": _failures.is_empty(), "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
