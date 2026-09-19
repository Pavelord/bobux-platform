extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var overlay = load("res://scripts/ui/experience_loading.gd").new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(overlay)
	overlay.set_experience("Bobux PARK", {"thumbnail": "res://icon.svg"})
	overlay.title.text = "Подключение..."
	overlay.subtitle.text = "Подготавливаем остров и вашего персонажа."
	overlay.bar.value = 65
	# Use a real existing map cover when available; an empty cover stays hidden.
	var source := Image.new()
	source.create_empty(320,180,false,Image.FORMAT_RGB8)
	var texture := GradientTexture2D.new()
	texture.width = 320
	texture.height = 180
	texture.gradient = Gradient.new()
	texture.gradient.colors = PackedColorArray([Color("459ec7"), Color("91cb70")])
	overlay.preview.texture = texture
	overlay.preview.visible = true
	for resolution in [Vector2i(1280,720), Vector2i(960,540), Vector2i(390,844)]:
		viewport.size = resolution
		await process_frame
		await process_frame
		assert(overlay.card.size.x <= resolution.x)
		assert(overlay.bar.get_global_rect().end.y < resolution.y)
		for corner in [Vector2.ZERO, Vector2(overlay.spinner.size.x, 0), overlay.spinner.size, Vector2(0, overlay.spinner.size.y)]:
			var point: Vector2 = overlay.spinner.get_global_transform() * corner
			assert(point.x >= 0 and point.x <= resolution.x and point.y >= 0 and point.y <= resolution.y)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("user://loading_%dx%d.png" % [resolution.x,resolution.y])
	overlay.queue_free()
	await process_frame
	print("Loading UI PASS: desktop, landscape, portrait")
	quit()
