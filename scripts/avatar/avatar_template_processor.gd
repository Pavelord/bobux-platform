class_name AvatarTemplateProcessor
extends RefCounted

const OUTPUT_SIZE: int = 1280
const PREVIEW_SIZE: int = 768
const MAX_SOURCE_IMAGE_BYTES: int = 64 * 1024 * 1024

const REGION_TORSO_FRONT: Rect2 = Rect2(0.395, 0.151, 0.219, 0.219)
const REGION_RIGHT_LIMB_FRONT: Rect2 = Rect2(0.373, 0.628, 0.109, 0.219)
const REGION_LEFT_LIMB_FRONT: Rect2 = Rect2(0.528, 0.628, 0.109, 0.219)


static func import_template_to_user_storage(source_path: String, template_kind: String, owner_hint: String = "") -> Dictionary:
	var clean_kind := _normalize_kind(template_kind)
	if clean_kind.is_empty():
		return {"ok": false, "error": "Template kind must be shirt or pants."}
	var source_image := _load_source_image(source_path)
	if source_image == null or source_image.is_empty():
		return {"ok": false, "error": "Could not load template image."}
	source_image.convert(Image.FORMAT_RGBA8)
	var atlas := _normalize_to_reference_square(source_image)
	var user_dir := "user://avatar_templates"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
	var owner_prefix := _sanitize_file_segment(owner_hint)
	if owner_prefix.is_empty():
		owner_prefix = "local"
	var stamp := Time.get_ticks_msec()
	var atlas_path := "%s/%s_%s_%d.png" % [user_dir, clean_kind, owner_prefix, stamp]
	var save_error: Error = atlas.save_png(atlas_path)
	if save_error != OK:
		return {"ok": false, "error": "Could not save normalized template."}
	var preview := make_template_preview_image(atlas, clean_kind)
	var preview_path := "%s/%s_%s_%d_preview.png" % [user_dir, clean_kind, owner_prefix, stamp]
	var preview_error: Error = preview.save_png(preview_path)
	if preview_error != OK:
		preview_path = atlas_path
	return {
		"ok": true,
		"kind": clean_kind,
		"path": atlas_path,
		"atlas_path": atlas_path,
		"preview_path": preview_path,
		"source_path": source_path,
		"template_version": "bobux_r6_square_v1"
	}


static func make_template_preview_image(atlas: Image, template_kind: String) -> Image:
	var preview := Image.create(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGBA8)
	preview.fill(Color(0.94, 0.96, 0.98, 1.0))
	var torso := _extract_region(atlas, REGION_TORSO_FRONT)
	var right_limb := _extract_region(atlas, REGION_RIGHT_LIMB_FRONT)
	var left_limb := _extract_region(atlas, REGION_LEFT_LIMB_FRONT)
	var head_color := Color(0.96, 0.8, 0.2, 1.0)
	var torso_placeholder := Color(0.12, 0.38, 0.72, 1.0)
	var leg_placeholder := Color(0.42, 0.58, 0.18, 1.0)
	_draw_block(preview, _scaled_rect(216, 18, 80, 80), head_color)
	if _normalize_kind(template_kind) == "pants":
		_draw_block(preview, _scaled_rect(156, 112, 200, 180), torso_placeholder)
		_blit_scaled(preview, right_limb, _scaled_rect(166, 306, 88, 194))
		_blit_scaled(preview, left_limb, _scaled_rect(258, 306, 88, 194))
	else:
		_blit_scaled(preview, torso, _scaled_rect(154, 112, 204, 214))
		_blit_scaled(preview, right_limb, _scaled_rect(52, 124, 88, 230))
		_blit_scaled(preview, left_limb, _scaled_rect(372, 124, 88, 230))
		_draw_block(preview, _scaled_rect(176, 340, 78, 150), leg_placeholder)
		_draw_block(preview, _scaled_rect(258, 340, 78, 150), leg_placeholder)
	return preview


static func _scaled_rect(x: int, y: int, width: int, height: int) -> Rect2i:
	var scale := float(PREVIEW_SIZE) / 512.0
	return Rect2i(
		roundi(float(x) * scale),
		roundi(float(y) * scale),
		maxi(1, roundi(float(width) * scale)),
		maxi(1, roundi(float(height) * scale))
	)


static func _normalize_kind(template_kind: String) -> String:
	var clean := template_kind.strip_edges().to_lower()
	if clean in ["shirt", "shirts", "tshirt", "t-shirt", "tee"]:
		return "shirt"
	if clean in ["pants", "pant", "trousers", "legs"]:
		return "pants"
	return ""


static func _load_source_image(source_path: String) -> Image:
	var clean_path := source_path.strip_edges()
	if clean_path.is_empty():
		return null
	if clean_path.begins_with("res://") and ResourceLoader.exists(clean_path):
		var resource := ResourceLoader.load(clean_path)
		if resource is Texture2D:
			var texture_image := (resource as Texture2D).get_image()
			if texture_image != null and not texture_image.is_empty():
				return texture_image
		if resource is Image:
			return resource as Image
	var source_file := FileAccess.open(clean_path, FileAccess.READ)
	if source_file != null:
		var source_length := source_file.get_length()
		if source_length > 0 and source_length <= MAX_SOURCE_IMAGE_BYTES:
			var source_bytes := source_file.get_buffer(source_length)
			source_file.close()
			var decoded := _decode_source_image_bytes(source_bytes, clean_path)
			if decoded != null and not decoded.is_empty():
				return decoded
		else:
			source_file.close()
	var image := Image.new()
	if image.load(clean_path) != OK:
		return null
	return image


static func _decode_source_image_bytes(source_bytes: PackedByteArray, source_path: String) -> Image:
	if source_bytes.is_empty():
		return null
	var image := Image.new()
	var extension := source_path.split("?", false)[0].get_extension().to_lower()
	var decode_error := ERR_FILE_UNRECOGNIZED
	if extension in ["png"] or _has_png_signature(source_bytes):
		decode_error = image.load_png_from_buffer(source_bytes)
	elif extension in ["jpg", "jpeg"] or _has_jpeg_signature(source_bytes):
		decode_error = image.load_jpg_from_buffer(source_bytes)
	elif extension == "webp" or _has_webp_signature(source_bytes):
		decode_error = image.load_webp_from_buffer(source_bytes)
	if decode_error != OK or image.is_empty():
		return null
	return image


static func _has_png_signature(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 8 \
		and bytes[0] == 0x89 \
		and bytes[1] == 0x50 \
		and bytes[2] == 0x4e \
		and bytes[3] == 0x47 \
		and bytes[4] == 0x0d \
		and bytes[5] == 0x0a \
		and bytes[6] == 0x1a \
		and bytes[7] == 0x0a


static func _has_jpeg_signature(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff


static func _has_webp_signature(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 12 \
		and bytes[0] == 0x52 \
		and bytes[1] == 0x49 \
		and bytes[2] == 0x46 \
		and bytes[3] == 0x46 \
		and bytes[8] == 0x57 \
		and bytes[9] == 0x45 \
		and bytes[10] == 0x42 \
		and bytes[11] == 0x50


static func _normalize_to_reference_square(source_image: Image) -> Image:
	var normalized := source_image.duplicate()
	normalized.convert(Image.FORMAT_RGBA8)
	if normalized.get_width() != OUTPUT_SIZE or normalized.get_height() != OUTPUT_SIZE:
		normalized.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_LANCZOS)
	return normalized


static func _extract_region(image: Image, normalized_region: Rect2) -> Image:
	if image == null or image.is_empty():
		return Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var x := clampi(roundi(normalized_region.position.x * float(width)), 0, width - 1)
	var y := clampi(roundi(normalized_region.position.y * float(height)), 0, height - 1)
	var region_width := clampi(roundi(normalized_region.size.x * float(width)), 1, width - x)
	var region_height := clampi(roundi(normalized_region.size.y * float(height)), 1, height - y)
	return image.get_region(Rect2i(x, y, region_width, region_height))


static func _blit_scaled(target: Image, source: Image, target_rect: Rect2i) -> void:
	if target == null or source == null or source.is_empty():
		return
	var scaled := source.duplicate()
	scaled.convert(Image.FORMAT_RGBA8)
	scaled.resize(maxi(1, target_rect.size.x), maxi(1, target_rect.size.y), Image.INTERPOLATE_LANCZOS)
	target.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), target_rect.position)


static func _draw_block(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


static func _sanitize_file_segment(value: String) -> String:
	var clean := value.strip_edges().get_file()
	for bad_char in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "%", "#", "&", "=", "+"]:
		clean = clean.replace(bad_char, "_")
	return clean
