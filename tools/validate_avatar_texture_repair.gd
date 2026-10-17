extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("[avatar-texture] ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func write_image(path: String, color: Color, size_y: int, webp: bool = false) -> void:
	var source := Image.create(64, size_y, false, Image.FORMAT_RGB8)
	source.fill(color)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(source.save_webp_to_buffer(true) if webp else source.save_png_to_buffer())
	file.close()

func run() -> void:
	await process_frame
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.set_script(load("res://tools/fixtures/avatar_attachment_player.gd"))
	root.add_child(player)
	var folder := "user://validation/avatar_texture_repair"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("shirt.png")
	write_image(path, Color.RED, 32)
	var original: Texture2D = player._load_texture_from_any_path(path, true)
	check(original != null and original.get_image().get_pixel(10, 10).r > 0.95, "initial prepared clothing texture is red")
	var decoded: Image = player._decode_avatar_texture_file(path)
	for region in range(12):
		check(player._decode_avatar_texture_file(path) == decoded, "all clothing regions share one source-image decode")
	# Keep the URL/path and vary bytes, format and dimensions, just like a
	# repaired or replaced remote shirt. The old prepared decal must not win.
	write_image(path, Color.BLUE, 31, true)
	var replacement: Texture2D = player._load_texture_from_any_path(path, true)
	check(replacement != null and replacement != original and replacement.get_image().get_pixel(10, 10).b > 0.95, "same-path replacement invalidates prepared texture cache, including WebP in a .png file")
	check(player._load_texture_from_any_path(path, true) == replacement, "unchanged repaired clothing keeps its shared prepared texture")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("<html>A temporary proxy error</html>")
	file.close()
	check(player._load_texture_from_any_path(path, true) == null, "HTTP error content cannot become a clothing texture")
	write_image(path, Color.GREEN, 30)
	var repaired: Texture2D = player._load_texture_from_any_path(path, true)
	check(repaired != null and repaired.get_image().get_pixel(10, 10).g > 0.95, "valid repaired file becomes visible without waiting for the failure cooldown")
	# Let the scheduled recovery settle before freeing its scene owner.
	await create_timer(5.2).timeout
	check(not player._avatar_texture_retry_scheduled, "background texture retry completes instead of remaining stuck")
	player.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("AVATAR_TEXTURE_REPAIR_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
