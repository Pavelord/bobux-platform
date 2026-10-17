extends RefCounted

# Extensions and response Content-Type are not reliable for imported thumbnails.
# Pick one decoder from the actual container, so a valid JPEG never reaches PNG.
static func decode(bytes: PackedByteArray) -> Image:
	var format := detect_format(bytes)
	if format.is_empty():
		return null
	var image := Image.new()
	var result: Error = ERR_FILE_UNRECOGNIZED
	match format:
		"png": result = image.load_png_from_buffer(bytes)
		"jpeg": result = image.load_jpg_from_buffer(bytes)
		"webp": result = image.load_webp_from_buffer(bytes)
	return image if result == OK and not image.is_empty() else null

static func detect_format(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		# Reject truncated cached/downloaded PNGs before calling the native decoder.
		var offset := 8
		var has_header := false
		var has_pixels := false
		while offset + 12 <= bytes.size():
			var length := (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])
			if length > bytes.size() - offset - 12:
				return ""
			var kind := bytes.slice(offset + 4, offset + 8).get_string_from_ascii()
			if offset == 8:
				if kind != "IHDR" or length != 13:
					return ""
				has_header = true
			if kind == "IDAT": has_pixels = true
			if kind == "IEND":
				return "png" if length == 0 and has_header and has_pixels else ""
			offset += length + 12
		return ""
	if bytes.size() >= 4 and bytes[0] == 255 and bytes[1] == 216:
		return "jpeg" if _complete_jpeg(bytes) else ""
	if bytes.size() >= 20 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		var declared_size := int(bytes.decode_u32(4)) + 8
		return "webp" if declared_size >= 20 and declared_size <= bytes.size() else ""
	return ""

static func _complete_jpeg(bytes: PackedByteArray) -> bool:
	var offset := 2
	var has_frame := false
	var has_scan := false
	while offset + 1 < bytes.size():
		if bytes[offset] != 255: return false
		while offset < bytes.size() and bytes[offset] == 255: offset += 1
		if offset >= bytes.size(): return false
		var marker := int(bytes[offset])
		offset += 1
		if marker == 217: return has_frame and has_scan
		if marker == 0 or marker == 216: return false
		if marker == 1 or (marker >= 208 and marker <= 215): continue
		if offset + 2 > bytes.size(): return false
		var length := (int(bytes[offset]) << 8) | int(bytes[offset + 1])
		if length < 2 or length > bytes.size() - offset: return false
		if marker >= 192 and marker <= 207 and marker not in [196, 200, 204]:
			if length < 8: return false
			has_frame = true
		offset += length
		if marker == 218:
			has_scan = true
			# Native byte search keeps large thumbnails inexpensive. Skip escaped
			# entropy bytes/restart markers; nested EXIF thumbnails were skipped
			# as opaque APP segments and cannot fake a complete main image.
			while offset < bytes.size():
				var next := bytes.find(255, offset)
				if next < 0 or next + 1 >= bytes.size(): return false
				var following := int(bytes[next + 1])
				if following == 0 or (following >= 208 and following <= 215):
					offset = next + 2
				else:
					offset = next
					break
	return false
