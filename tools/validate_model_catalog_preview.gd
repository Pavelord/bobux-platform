extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var editor := (load("res://scenes/model_editor/model_editor.tscn") as PackedScene).instantiate() as Control
	root.add_child(editor)
	await process_frame
	editor.set_process(false)
	var data := {"parts": [{"name": "Wide Model", "kind": "Block", "position": [120, 8, -90], "scale": [28, 3, 4], "color": "0088ff"}]}
	var camera := editor.get("_camera") as Camera3D
	var before := camera.transform
	var uri: String = await editor.call("_capture_model_preview_data_uri", data)
	assert(uri.begins_with("data:image/png;base64,"))
	assert(camera.transform == before)
	var image := Image.new()
	assert(image.load_png_from_buffer(Marshalls.base64_to_raw(uri.get_slice(",", 1))) == OK)
	assert(image.get_size() == Vector2i(384, 384))
	image.save_png("res://.codex-tmp/model_publish_preview.png")
	var visible_pixels := 0
	for y in range(384):
		for x in range(384):
			if image.get_pixel(x, y).r < 0.8: visible_pixels += 1
	print("visible_pixels=", visible_pixels)
	if visible_pixels <= 500:
		push_error("Model is not visible in the preview")
		quit(1)
		return
	for corner in [Vector2i(0, 0), Vector2i(383, 0), Vector2i(0, 383), Vector2i(383, 383)]:
		assert(image.get_pixelv(corner).r > 0.95)
	image.save_png("res://.codex-tmp/model_publish_preview.png")
	var renderer := load("res://scripts/lobby/catalog_thumbnail_renderer.gd")
	var item := {"id": "one", "category": "model", "data": data}
	var key: String = renderer.cache_key(item)
	item["owned"] = true
	item["likes_count"] = 999
	assert(renderer.cache_key(item) == key)
	item.data.parts[0].color = "ff0000"
	assert(renderer.cache_key(item) != key)
	editor.queue_free()
	await process_frame
	print("[model_catalog_preview] PASS: off-centre wide model fits, camera unchanged, visual cache invalidation")
	quit(0)
