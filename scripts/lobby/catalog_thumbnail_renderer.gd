extends Node
## Renders the asset itself, not its old screenshot or clothing atlas.
const PLAYER_PATH := "res://scenes/player/player.tscn"
const CACHE := "user://catalog_previews/v4/"
var _queue: Array[Dictionary] = []
var _running := false
var _viewport: SubViewport
var _world: Node3D
var _helper: Node3D
var _camera: Camera3D
var failures: Array[Dictionary] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(384, 384)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	_world = Node3D.new()
	_world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.WHITE
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	_world.add_child(environment)
	for rotation in [Vector3(-35, -35, 0), Vector3(-15, 145, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 0.75 if rotation.y < 0 else 0.3
		_world.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 100000
	_world.add_child(_camera)
	_camera.current = true
	_helper = _mannequin()
	_world.add_child(_helper)
	_helper.hide()

func request_preview(item: Dictionary, target: TextureRect) -> void:
	_queue.append({"item": item, "target": weakref(target)})
	if not _running:
		_running = true
		call_deferred("_drain")

func _drain() -> void:
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var target: Variant = job.target.get_ref()
		if not is_instance_valid(target): continue
		var texture := await render_item(job.item)
		target = job.target.get_ref()
		if is_instance_valid(target):
			target.texture = texture
			target.tooltip_text = "Исходная модель или текстура недоступна" if texture == null else ""
			if texture == null and not target.has_node("Unavailable"):
				var note := Label.new()
				note.name = "Unavailable"
				note.text = "Превью недоступно"
				note.add_theme_color_override("font_color", Color("#777777"))
				note.add_theme_font_size_override("font_size", 13)
				note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				note.mouse_filter = Control.MOUSE_FILTER_IGNORE
				target.add_child(note)
	_running = false

static func cache_key(item: Dictionary) -> String:
	var data: Variant = item.get("data", {})
	if data is String: data = JSON.parse_string(data)
	if not data is Dictionary: data = {}
	var kind := str(item.get("item_kind", item.get("category", data.get("item_kind", "model")))).to_lower()
	if kind == "shirts": kind = "shirt"
	var identity := {"kind": kind, "data": data.duplicate(true)}
	for key in ["source_url", "source_path", "template_url", "texture_path", "atlas_path", "parts"]:
		if item.has(key): identity[key] = item[key]
	if kind == "boblox_promo": identity["art_version"] = 2
	_remove_previews(identity)
	return JSON.stringify(identity).sha256_text()

static func _remove_previews(value: Variant) -> void:
	if value is Dictionary:
		for key in value.keys():
			if "thumbnail" in str(key) or key in ["owned", "likes_count", "_pb_id", "uses_count"]:
				value.erase(key)
			else: _remove_previews(value[key])
	elif value is Array:
		for child in value: _remove_previews(child)

func render_item(item: Dictionary, force := false) -> Texture2D:
	var path := CACHE + cache_key(item) + ".png"
	if not force and FileAccess.file_exists(path):
		return ImageTexture.create_from_image(Image.load_from_file(path))
	if DisplayServer.get_name() == "headless": return null
	var data: Dictionary = _helper.call("_avatar_attachment_item_data", item)
	var kind := str(item.get("item_kind", item.get("category", data.get("item_kind", "")))).to_lower()
	_viewport.transparent_bg = kind == "boblox_promo"
	var subject: Node3D
	if kind == "boblox_promo":
		subject = _mannequin()
		subject.set("torso_color", Color("#00ae3c"))
		subject.set("head_color", Color("#ffd43a"))
		subject.set("left_arm_color", Color("#ffd43a"))
		subject.set("right_arm_color", Color("#ffd43a"))
		subject.set("left_leg_color", Color("#0b743b"))
		subject.set("right_leg_color", Color("#0b743b"))
		subject.set("chest_badge_texture_path", "res://assets/currency/boblox.png")
	elif kind in ["face", "chest_badge"]:
		var source := str(item.get("texture_path", data.get("texture_path", "")))
		var local_path := await _texture_source(source)
		if local_path.is_empty(): return _fail(item, "Texture unavailable")
		if kind == "face":
			subject = Node3D.new()
			var head := MeshInstance3D.new()
			head.mesh = BoxMesh.new()
			head.mesh.size = Vector3.ONE
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("d5d5d5")
			head.material_override = material
			subject.add_child(head)
			var face := MeshInstance3D.new()
			face.mesh = QuadMesh.new()
			face.mesh.size = Vector2(0.86, 0.86)
			face.position.z = 0.502
			var face_material := StandardMaterial3D.new()
			face_material.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(local_path))
			face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			face.material_override = face_material
			subject.add_child(face)
		else:
			subject = _mannequin()
			subject.set("chest_badge_texture_path", local_path)
	elif kind in ["shirt", "shirts", "pants", "tshirt", "t-shirt"]:
		var source := ""
		for candidate in [item, data]:
			for key in ["template_url", "atlas_path", "texture_path", "source_url"]:
				if source.is_empty(): source = str(candidate.get(key, ""))
		var local_path := await _texture_source(source)
		if local_path.is_empty():
			return _fail(item, "Clothing template unavailable")
		subject = _mannequin()
		subject.set("pants_texture_path" if kind == "pants" else "shirt_texture_path", local_path)
	else:
		var source: String = _helper.call("_avatar_attachment_source_path", item, data)
		if not source.is_empty() and source.get_slice("?", 0).get_extension().to_lower() in ["glb", "gltf", "fbx", "obj", "tscn", "res", "tres"]:
			var loaded: Variant = await _helper.call("_instantiate_avatar_attachment_source", source)
			if loaded is Node3D: subject = loaded
			elif loaded is Node: loaded.queue_free()
			var parts: Array = _helper.call("_avatar_attachment_extract_parts", data)
			if subject != null: _helper.call("_apply_avatar_attachment_source_fallback_colors", subject, parts)
		if subject == null:
			var parts: Array = _helper.call("_avatar_attachment_extract_parts", data)
			if parts.is_empty(): return _fail(item, "No model geometry")
			subject = Node3D.new()
			for part in parts:
				if part is Dictionary:
					if str(part.get("kind", "")) in ["ImportedMeshPart", "ImportedPlaceholder"]:
						subject.free()
						return _fail(item, "Original mesh file unavailable; bounds are not geometry")
					subject.add_child(_helper.call("_create_avatar_attachment_part", part))
	_world.add_child(subject)
	# Player previews opt in to interpolation in _ready; static snapshots must
	# override that, including children loaded from animated model scenes.
	_disable_snapshot_interpolation(subject)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bounds: Array[AABB] = []
	_collect_bounds(subject, bounds)
	if bounds.is_empty():
		subject.queue_free()
		return _fail(item, "No visible mesh")
	var box := bounds[0]
	for part_box in bounds: box = box.merge(part_box)
	var center := box.get_center()
	var direction := Vector3(0.85, 0.48, 1.6).normalized()
	var distance := maxf(box.size.length() * 3, 5)
	_camera.position = center + direction * distance
	_camera.look_at(center, Vector3.UP)
	_camera.far = maxf(distance * 3, 100)
	var projected := AABB()
	for corner in range(8):
		var point := _camera.global_transform.affine_inverse() * box.get_endpoint(corner)
		if corner == 0: projected = AABB(point, Vector3.ZERO)
		else: projected = projected.expand(point)
	_camera.size = maxf(maxf(projected.size.x, projected.size.y) * 1.18, 0.05)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_world.remove_child(subject)
	subject.queue_free()
	if image == null or image.is_empty(): return _fail(item, "Renderer produced no image")
	image.save_png(path)
	return ImageTexture.create_from_image(image)

func _disable_snapshot_interpolation(node: Node) -> void:
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if node is AnimationPlayer: node.stop(true)
	if node is AnimationTree: node.active = false
	for child in node.get_children():
		_disable_snapshot_interpolation(child)

func _mannequin() -> Node3D:
	var actor := (load(PLAYER_PATH) as PackedScene).instantiate() as Node3D
	actor.set("is_ui_preview", true)
	actor.set("use_local_avatar_fallback", false)
	actor.set("render_avatar_visual_decals", true)
	actor.set("render_avatar_clothing_decals", true)
	actor.set("chest_badge_texture_path", "")
	actor.set("face_texture_path", GameState.DEFAULT_FACE_TEXTURE_PATH)
	actor.set("equipped_avatar_items", [])
	for key in ["head_color", "torso_color", "left_arm_color", "right_arm_color", "left_leg_color", "right_leg_color"]:
		actor.set(key, Color("#c6c6c6"))
	return actor

func _texture_source(source: String) -> String:
	if source.is_empty(): return ""
	if FileAccess.file_exists(source): return source
	var path := CACHE + source.sha256_text() + "_template.png"
	if FileAccess.file_exists(path): return path
	if not source.begins_with("http://") and not source.begins_with("https://"):
		if source.begins_with("data:image/"):
			var image := Image.new()
			var bytes := Marshalls.base64_to_raw(source.get_slice(",", 1))
			if image.load_png_from_buffer(bytes) == OK or image.load_jpg_from_buffer(bytes) == OK:
				if image.save_png(path) == OK: return path
		return ""
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 12
	request.body_size_limit = 16 * 1024 * 1024
	add_child(request)
	if request.request(source) != OK:
		request.queue_free()
		return ""
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200: return ""
	var image := Image.new()
	if image.load_png_from_buffer(response[3]) == OK or image.load_jpg_from_buffer(response[3]) == OK or image.load_webp_from_buffer(response[3]) == OK:
		if image.save_png(path) == OK: return path
	return ""

static func _collect_bounds(node: Node, bounds: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
		var local_bounds: AABB = node.get_aabb()
		if node.mesh is ArrayMesh and node.get_skin_reference() != null:
			# Imported bind poses may be translated far from the visible skeleton.
			# Frame the posed vertices, not the unskinned source mesh's box.
			var posed: ArrayMesh = node.bake_mesh_from_current_skeleton_pose()
			if posed != null: local_bounds = posed.get_aabb()
		bounds.append(node.global_transform * local_bounds)
	for child in node.get_children(): _collect_bounds(child, bounds)

func _fail(item: Dictionary, reason: String) -> Texture2D:
	failures.append({"id": item.get("id", ""), "name": item.get("name", ""), "reason": reason})
	return null
