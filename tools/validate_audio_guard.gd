extends SceneTree

const AudioFileLoader := preload("res://addons/roblox_runtime/audio_file_loader.gd")


func _initialize() -> void:
	var invalid_path := "user://invalid_cached_map_music.mp3"
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_buffer("<html><body>401 Unauthorized</body></html>".to_utf8_buffer())
	invalid_file.close()
	var tagged_only_path := "user://truncated_tagged_map_music.mp3"
	var tagged_file := FileAccess.open(tagged_only_path, FileAccess.WRITE)
	var tagged_only := PackedByteArray()
	tagged_only.resize(64)
	tagged_only[0] = 0x49
	tagged_only[1] = 0x44
	tagged_only[2] = 0x33
	tagged_file.store_buffer(tagged_only)
	tagged_file.close()

	var invalid_main: AudioStream = AudioFileLoader.load_stream(invalid_path, true)
	var truncated_main: AudioStream = AudioFileLoader.load_stream(tagged_only_path, true)
	var valid_main: AudioStream = AudioFileLoader.load_stream("res://robloxdeathsound.mp3", true)
	var invalid_player: AudioStream = AudioFileLoader.load_stream(invalid_path)
	var valid_player: AudioStream = AudioFileLoader.load_stream("res://robloxdeathsound.mp3")
	var ok := (
		invalid_main == null
		and truncated_main == null
		and valid_main is AudioStreamMP3
		and invalid_player == null
		and valid_player is AudioStreamMP3
	)
	print("[validate_audio_guard] ok=%s invalid=%s truncated=%s valid_main=%s valid_player=%s" % [
		str(ok), str(invalid_main != null), str(truncated_main != null),
		str(valid_main != null), str(valid_player != null),
	])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tagged_only_path))
	quit(0 if ok else 1)
