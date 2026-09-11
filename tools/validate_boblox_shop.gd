extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	var packed := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if packed == null: quit(1); return
	var lobby := packed.instantiate() as Control
	lobby.set_meta("boblox_preview", true)
	root.add_child(lobby)
	await process_frame
	lobby.call("_open_boblox_shop", 0)
	await create_timer(1.0).timeout
	var overlay := lobby.get("_loading_overlay") as Control
	if overlay: overlay.hide()
	var shop := lobby.get("_boblox_shop") as Control
	if shop == null: quit(1); return
	var nav := lobby.get_node("TopBar/HBox/Nav4") as Button
	assert(nav.get_signal_connection_list("pressed").size() > 0)
	assert(shop.find_child("BuyBBC", true, false) != null)
	assert(shop.find_child("BuyTBC", true, false) != null)
	for id in ["bc", "bbc", "pbc", "tbc"]:
		var texture := load("res://assets/currency/bricks_club/%s.png" % id) as Texture2D
		assert(texture != null)
		assert(texture.get_image().get_pixel(0, 0).a == 0.0)
	var catalog: Dictionary = shop.get("catalog")
	assert(int(catalog.packs[0].price_kopecks) == 5000)
	shop.call("_show_checkout", catalog.tiers[1])
	await process_frame
	var dialog := shop.get("_dialog") as ConfirmationDialog
	assert(dialog != null and dialog.get_ok_button().disabled)
	await _capture("checkout")
	dialog.hide()
	await _capture("club")
	shop.call("select_section", 1)
	await _capture("boblox")
	shop.call("select_section", 2)
	await _capture("history")
	lobby.queue_free()
	await process_frame
	# Narrow-layout contract uses the same real shop, independently of lobby navigation.
	root.size = Vector2i(420, 900)
	root.content_scale_size = Vector2i(420, 900)
	var narrow := load("res://scripts/lobby/boblox_shop.gd").new() as Control
	narrow.set("preview_only", true)
	root.add_child(narrow)
	narrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	print("narrow_size=%s root=%s minimum=%s" % [narrow.size, root.size, narrow.get_combined_minimum_size()])
	if narrow.size.x > 420:
		push_error("Shop exceeds narrow viewport")
		quit(1)
		return
	assert(narrow.find_child("BuyTBC", true, false) != null)
	await _capture("mobile")
	narrow.queue_free()
	await process_frame
	print("[validate_boblox_shop] PASS: lobby navigation, four tiers, real alpha, preview cannot pay, mobile layout")
	quit(0)

func _capture(label: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	var path := "res://.codex-tmp/boblox_%s.png" % label
	assert(image.save_png(path) == OK)
	print("capture=" + ProjectSettings.globalize_path(path))
