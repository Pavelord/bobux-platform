extends ColorRect

var card := Panel.new()
var experience := Label.new()
var title := Label.new()
var subtitle := Label.new()
var transport := Label.new()
var transport_badge := Label.new()
var bar := ProgressBar.new()
var spinner := TextureRect.new()
var preview := TextureRect.new()
var box := VBoxContainer.new()
var logo := TextureRect.new()
var _preview_key := ""
var _preview_generation := 0
var rotate_spinner := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("252525")
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := TextureRect.new()
	background.texture = load("res://assets/loading/background.jpg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(card)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	logo.texture = load("res://assets/branding/bobux_logo_ui.png")
	for image in [logo, preview, spinner]:
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(logo)
	experience.text = "Bobux"
	for label in [experience, title, subtitle]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("eeeeee"))
		experience.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(experience)
	preview.visible = false
	box.add_child(preview)
	bar.show_percentage = false
	bar.max_value = 100
	bar.custom_minimum_size.y = 16
	for kind in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("505050") if kind == "background" else Color("b7b7b7")
		style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override(kind, style)
	box.add_child(bar)
	box.add_child(title)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("b5b5b5"))
	box.add_child(subtitle)
	for label in [transport, transport_badge]:
		label.visible = false
		add_child(label)
	spinner.texture = load("res://assets/loading/spinner.png")
	add_child(spinner)
	resized.connect(_layout)
	visibility_changed.connect(_refresh_selected)
	_layout()
	_refresh_selected()

func _layout() -> void:
	if not is_inside_tree(): return
	var compact := size.y < 620
	var width := minf(size.x - 48, 620)
	card.position = Vector2((size.x - width) * 0.5, 14)
	card.size = Vector2(width, maxf(size.y - 28, 250))
	card.pivot_offset = card.size * 0.5
	logo.custom_minimum_size = Vector2(0, 78 if compact else 112)
	experience.add_theme_font_size_override("font_size", 24 if compact else 32)
	title.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_font_size_override("font_size", 13)
	preview.custom_minimum_size.y = minf(width * 0.5625, size.y * 0.37)
	spinner.size = Vector2(44, 44) if compact else Vector2(64, 64)
	spinner.position = size - spinner.size - Vector2(24, 24)
	spinner.pivot_offset = spinner.size * 0.5

func _process(delta: float) -> void:
	if visible and rotate_spinner: spinner.rotation += delta * 2.2

func _refresh_selected() -> void:
	if not visible: return
	var state := get_node_or_null("/root/GameState")
	if state == null: return
	set_experience(state.get_selected_map_display_name(), state.get_selected_map_metadata(), str(state.selected_map_folder))

func set_experience(display_name: String, metadata: Dictionary, folder := "") -> void:
	experience.text = display_name if not display_name.is_empty() else "Bobux"
	var reference := ""
	for key in ["thumbnail", "icon_path", "thumbnail_url", "thumbnail_path"]:
		reference = str(metadata.get(key, "")).strip_edges()
		if not reference.is_empty(): break
	if reference.is_empty() and not folder.is_empty() and FileAccess.file_exists(folder.path_join("icon.png")):
		reference = folder.path_join("icon.png")
	if reference == _preview_key: return
	_preview_key = reference
	_preview_generation += 1
	var generation := _preview_generation
	preview.texture = null
	preview.visible = false
	if reference.is_empty(): return
	var bytes := PackedByteArray()
	if reference.begins_with("http://") or reference.begins_with("https://"):
		var request := HTTPRequest.new()
		request.timeout = 15
		request.body_size_limit = 8 * 1024 * 1024
		add_child(request)
		if request.request(reference) != OK:
			request.queue_free()
			return
		var result: Array = await request.request_completed
		request.queue_free()
		if generation != _preview_generation or int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200: return
		bytes = result[3]
	elif reference.begins_with("data:image/"):
		bytes = Marshalls.base64_to_raw(reference.get_slice(",", 1))
	elif reference.begins_with("res://") and ResourceLoader.exists(reference):
		var resource = load(reference)
		if resource is Texture2D:
			preview.texture = resource
			preview.visible = true
		return
	elif FileAccess.file_exists(reference):
		bytes = FileAccess.get_file_as_bytes(reference)
	if bytes.size() < 12: return
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 137 and bytes[1] == 80:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 255 and bytes[1] == 216:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		error = image.load_webp_from_buffer(bytes)
	if error == OK and generation == _preview_generation:
		preview.texture = ImageTexture.create_from_image(image)
		preview.visible = true
