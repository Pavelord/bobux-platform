extends RefCounted

# Older imports incorrectly copied idle SoundService effects into background
# music. Match the actual bytes, since publishing renames them music_01.ogg.
static func imported_music_playlist(settings: Dictionary, folder: String) -> Array:
	var playlist: Array = settings.get("music_playlist", []).duplicate()
	if playlist.is_empty() and not str(settings.get("music_file", "")).is_empty(): playlist.append(settings.music_file)
	if int(settings.get("roblox_sound_playlist_policy", 0)) >= 2: return playlist
	var hashes := {}
	for sound in settings.get("roblox_sound_assets", []):
		if not sound is Dictionary or not bool(sound.get("as_music", false)) or bool(sound.get("looped", false)) or bool(sound.get("playing", false)): continue
		var path := str(sound.get("resolved_path", ""))
		if not FileAccess.file_exists(path): path = folder.path_join(path.get_file())
		if FileAccess.file_exists(path): hashes[FileAccess.get_sha256(path)] = true
	var result: Array = []
	for track in playlist:
		var path := str(track)
		if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path(): path = folder.path_join(path)
		if FileAccess.file_exists(path) and hashes.has(FileAccess.get_sha256(path)): continue
		result.append(track)
	return result


static func has_audio_header(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var bytes := file.get_buffer(mini(file.get_length(), 65536))
	if bytes.size() < 12: return false
	return (bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE") or bytes.slice(0, 4).get_string_from_ascii() == "OggS" or is_probably_valid_mp3_data(bytes)


static func load_stream(path: String, disable_loop: bool = false) -> AudioStream:
	# Imported res:// audio is packed under Godot's generated .mp3str/.oggstr
	# resource path. FileAccess cannot open the original source file in an export,
	# so ask ResourceLoader first; retain the byte loader for downloaded/user files.
	var stream: AudioStream = _load_imported_stream(path)
	if stream == null:
		var resolved_path := resolve_existing_path(path)
		if resolved_path.is_empty():
			return null
		match resolved_path.get_extension().to_lower():
			"wav":
				stream = AudioStreamWAV.load_from_file(resolved_path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(resolved_path)
			"mp3":
				var file := FileAccess.open(resolved_path, FileAccess.READ)
				if file == null:
					return null
				var data := file.get_buffer(file.get_length())
				file.close()
				if not is_probably_valid_mp3_data(data):
					return null
				var mp3 := AudioStreamMP3.new()
				mp3.data = data
				stream = mp3
	if stream != null and disable_loop:
		# ResourceLoader caches imported resources; duplicate before changing a
		# playback property so one caller cannot change another caller's stream.
		stream = stream.duplicate() as AudioStream
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		for property_info in stream.get_property_list():
			if str(property_info.get("name", "")) == "loop":
				stream.set("loop", false)
				break
	return stream


static func _load_imported_stream(path: String) -> AudioStream:
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AudioStream


static func is_probably_valid_mp3_data(data: PackedByteArray) -> bool:
	if data.size() < 32:
		return false
	var scan_start := 0
	var scan_span := 8192
	if data[0] == 0x49 and data[1] == 0x44 and data[2] == 0x33:
		if data.size() < 10:
			return false
		for size_byte in range(6, 10):
			if int(data[size_byte]) >= 0x80:
				return false
		var tag_size := (
			(int(data[6]) << 21) | (int(data[7]) << 14)
			| (int(data[8]) << 7) | int(data[9])
		)
		scan_start = 10 + tag_size
		if (int(data[5]) & 0x10) != 0:
			scan_start += 10
		scan_span = 65536
	if scan_start >= data.size() - 1:
		return false
	var scan_limit := mini(data.size() - 1, scan_start + scan_span)
	for index in range(scan_start, scan_limit):
		if data[index] != 0xFF:
			continue
		var second := int(data[index + 1])
		if (second & 0xE0) == 0xE0 and (second & 0x18) != 0x08 and (second & 0x06) != 0:
			return true
	return false


static func resolve_existing_path(path: String) -> String:
	if path.is_empty():
		return ""
	var global_path := ProjectSettings.globalize_path(path)
	if global_path != path and FileAccess.file_exists(global_path):
		return global_path
	return path if FileAccess.file_exists(path) else ""
