extends Node

# A shared ImageTexture survives material/GUI cloning. Decode off the scene
# thread, then replace its pixels once; every consumer sees the finished image.
signal texture_ready(path: String)
var _textures: Dictionary = {}
var _expected: Dictionary = {}
var _queued: Dictionary = {}
var _worker: Thread
var _working_path := ""

static func service() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("MapMediaStream")

func expect_file(path: String) -> void:
	_expected[_key(path)] = true

func can_stream(path: String) -> bool:
	return _expected.has(_key(path)) or FileAccess.file_exists(path)

func request_texture(path: String, placeholder := Color.WHITE) -> Texture2D:
	var key := _key(path)
	if _textures.has(key):
		var existing: Variant = _textures[key]
		if existing is WeakRef: existing = existing.get_ref()
		if existing != null: return existing
		_textures.erase(key)
	if not can_stream(path): return null
	var pixels := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixels.fill(placeholder)
	var texture := ImageTexture.create_from_image(pixels)
	_textures[key] = texture
	if FileAccess.file_exists(key): _queued[key] = true
	return texture

func file_available(path: String) -> void:
	var key := _key(path)
	_expected.erase(key)
	if _textures.has(key): _queued[key] = true

func _process(_delta: float) -> void:
	if _worker != null:
		if _worker.is_alive(): return
		var decoded: Variant = _worker.wait_to_finish()
		_worker = null
		var texture: Variant = _textures.get(_working_path)
		if texture is WeakRef: texture = texture.get_ref()
		if texture != null and decoded is Image and not decoded.is_empty():
			(texture as ImageTexture).set_image(decoded)
			texture_ready.emit(_working_path)
		# Completed textures are owned by their materials, not a permanent map
		# cache. Leaving a large place can reclaim its images immediately.
		if texture != null: _textures[_working_path] = weakref(texture)
		_working_path = ""
	# At most one image upload per frame. IO/decompression run on a worker;
	# the render resource itself is changed only on the main thread.
	if _queued.is_empty(): return
	_working_path = str(_queued.keys()[0])
	_queued.erase(_working_path)
	_worker = Thread.new()
	if _worker.start(_decode.bind(_working_path)) != OK:
		_worker = null

static func _decode(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		error = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 255 and bytes[1] == 216:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	else:
		error = image.load(path)
	if error != OK: return null
	image.generate_mipmaps()
	return image

static func _key(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()

func _exit_tree() -> void:
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
