extends SceneTree
const RENDERER := preload("res://scripts/lobby/catalog_thumbnail_renderer.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var renderer := RENDERER.new()
	root.add_child(renderer)
	var items: Array = []
	for source in ["avatar_items", "model_assets"]:
		var file := "res://.codex-tmp/%s_preview_audit.json" % source
		if not FileAccess.file_exists(file): push_error("Missing audit file: " + file); quit(1); return
		var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if rows is Array: items.append_array(rows)
	var limit := items.size()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int(): limit = mini(limit, int(args[0]))
	DirAccess.make_dir_recursive_absolute("res://.codex-tmp/rebuilt_catalog_previews")
	var results: Array = []
	# Resume successful renders without downloading/rendering the whole catalog again.
	var previous: Dictionary = {}
	var report_path := "res://.codex-tmp/rebuilt_catalog_previews/results.json"
	if FileAccess.file_exists(report_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if saved is Dictionary:
			for entry in saved.get("items", []): previous[str(entry.id)] = entry
	for idx in range(limit):
		var item: Dictionary = items[idx]
		var id := str(item.get("id", str(idx))).validate_filename()
		var path := "res://.codex-tmp/rebuilt_catalog_previews/" + id + ".png"
		var texture: Texture2D
		if not "--force" in args and previous.get(id, {}).get("ok", false) and FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			image.save_png(RENDERER.CACHE + RENDERER.cache_key(item) + ".png")
			texture = ImageTexture.create_from_image(image)
		else:
			texture = await renderer.render_item(item, true)
		if texture != null: texture.get_image().save_png(path)
		var result := {"id": id, "name": item.get("name"), "ok": texture != null, "cache_key": RENDERER.cache_key(item)}
		results.append(result)
		print("[%d/%d] %s ok=%s" % [idx + 1, limit, id, texture != null])
		var report := FileAccess.open("res://.codex-tmp/rebuilt_catalog_previews/results.json", FileAccess.WRITE)
		report.store_string(JSON.stringify({"items": results, "failures": renderer.failures}, "\t"))
	renderer.queue_free()
	await process_frame
	quit(0)
