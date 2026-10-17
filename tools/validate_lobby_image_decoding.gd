extends SceneTree

const Decoder = preload("res://scripts/ui/image_byte_decoder.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.75, 0.25, 0.1))
	var formats := {
		"png": image.save_png_to_buffer(),
		"jpeg": image.save_jpg_to_buffer(),
		"webp": image.save_webp_to_buffer()
	}
	var lobby = load("res://scripts/lobby/lobby.gd").new()
	var target := TextureRect.new()
	var urls: Array[String] = []
	for format in formats:
		var bytes: PackedByteArray = formats[format]
		assert(Decoder.detect_format(bytes) == format)
		var decoded: Image = Decoder.decode(bytes)
		assert(decoded != null and decoded.get_size() == Vector2i(8, 8))
		var url: String = "https://thumbnail.invalid/contract-%s-%d.png" % [format, OS.get_process_id()]
		urls.append(url)
		var path: String = lobby._get_remote_game_icon_cache_path(url)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		assert(lobby._try_apply_cached_remote_game_icon(url, target), "Decode cached %s despite .png name" % format)
		assert(target.texture != null)
		# Both the returned HTML error page and an interrupted body are removed
		# so a later successful bounded network request can repair the thumbnail.
		for invalid in ["<html>404 Not Found</html>".to_utf8_buffer(), bytes.slice(0, maxi(2, bytes.size() / 2))]:
			assert(Decoder.decode(invalid) == null)
			file = FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(invalid)
			file.close()
			assert(not lobby._try_apply_cached_remote_game_icon(url, target))
			assert(not FileAccess.file_exists(path), "Discard corrupt known thumbnail cache")
			file = FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(bytes)
			file.close()
			assert(lobby._try_apply_cached_remote_game_icon(url, target), "Repaired cache is usable")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	target.free()
	lobby.free()
	print("LOBBY_IMAGE_DECODING_OK: PNG/JPEG/WebP signatures; mislabeled cache; HTML/truncation removal; repair")
	quit(0)
