extends RefCounted


static func load_stream(path: String, disable_loop: bool = false) -> AudioStream:
	var resolved_path := resolve_existing_path(path)
	if resolved_path.is_empty():
		return null
	var stream: AudioStream = null
	match resolved_path.get_extension().to_lower():
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
		for property_info in stream.get_property_list():
			if str(property_info.get("name", "")) == "loop":
				stream.set("loop", false)
				break
	return stream


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
