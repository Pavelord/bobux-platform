extends RefCounted

const INDEX := "res://toolbox_assets/metadata/index.json"
const SERVER_INDEX := "user://toolbox_cache/index.json"
const MODIFIERS := ["small", "large", "big", "modern", "wide", "tall", "short", "long", "low", "high", "маленький", "большой", "city", "sci", "fi"]
static var _assets: Array = []
static var _by_id: Dictionary = {}
static var _terms: Dictionary = {}
static var _loaded := false

static func reload() -> void:
	_loaded = false
	_assets.clear()
	_by_id.clear()
	_terms.clear()
	_ensure_index()

static func _ensure_index() -> void:
	if _loaded: return
	_loaded = true
	var index_path := SERVER_INDEX if FileAccess.file_exists(SERVER_INDEX) else INDEX
	if not FileAccess.file_exists(index_path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not parsed is Dictionary: return
	for entry in parsed.get("assets", []):
		if not entry is Dictionary or entry.get("license") != "CC0": continue
		var id: String = entry.get("id", "")
		if id.is_empty(): continue
		_assets.append(entry)
		_by_id[id] = entry
		var weighted := {}
		_add_terms(weighted, str(entry.get("name", "")), 12.0)
		_add_terms(weighted, " ".join(entry.get("tags", [])), 7.0)
		_add_terms(weighted, " ".join(entry.get("synonyms", [])), 5.0)
		_add_terms(weighted, str(entry.get("category", "")), 4.0)
		_add_terms(weighted, " ".join(entry.get("ai_use_cases", [])), 2.0)
		_terms[id] = weighted

static func _tokens(value: String) -> PackedStringArray:
	var regex := RegEx.new()
	regex.compile("[a-zа-яё0-9]+")
	var result := PackedStringArray()
	for match_ in regex.search_all(value.to_lower()):
		var token := match_.get_string()
		if token not in ["create", "add", "make", "a", "an", "the", "with", "and", "to", "inside", "some", "сделай", "создай", "создать", "добавь", "поставь", "и", "с", "в", "на", "для", "модель", "model", "звук", "sound", "sounds"]:
			result.append(token)
	return result

static func _add_terms(out: Dictionary, text: String, weight: float) -> void:
	for token in _tokens(text):
		var term_weight := minf(weight, 2.0) if token in MODIFIERS else weight
		out[token] = maxf(float(out.get(token, 0)), term_weight)

static func get_asset(asset_id: String) -> Dictionary:
	_ensure_index()
	var entry: Dictionary = _by_id.get(asset_id, {}).duplicate(true)
	if entry.has("package_sha256"):
		var folder := "user://toolbox_cache/assets/" + str(entry.package_sha256)
		if FileAccess.file_exists(folder + "/.verified"):
			entry["file"] = folder + "/" + str(entry.entrypoint)
	return entry

static func categories(type_: String) -> Array[String]:
	_ensure_index()
	var result: Array[String] = []
	for entry in _assets:
		if entry.type == type_ and str(entry.category) not in result: result.append(str(entry.category))
	result.sort()
	return result

static func search_assets(query: String, type_: String = "", category: String = "", limit: int = 24, offset: int = 0) -> Array[Dictionary]:
	_ensure_index()
	var tokens := _tokens(query)
	var ranked: Array[Dictionary] = []
	for entry in _assets:
		if not type_.is_empty() and entry.type != type_: continue
		if not category.is_empty() and entry.category != category: continue
		var terms: Dictionary = _terms[entry.id]
		var score := 0.0
		var matched := 0
		var token_index := 0
		for token in tokens:
			var best := float(terms.get(token, 0))
			if best == 0 and token.length() >= 4:
				for candidate in terms:
					# Prefixes cover plural/Russian inflections; one typo is only
					# accepted for longer words with the same first letter.
					var prefix := token.left(maxi(4, token.length() - 2))
					if str(candidate).begins_with(prefix): best = maxf(best, float(terms[candidate]) * 0.6)
					elif token.length() >= 5 and str(candidate).left(1) == token.left(1) and _one_typo(token, str(candidate)):
						best = maxf(best, float(terms[candidate]) * 0.4)
			if best > 0: matched += 1
			score += best * maxf(0.5, 1.0 - token_index * 0.1)
			token_index += 1
		if not tokens.is_empty() and matched == 0: continue
		if str(entry.name).to_lower() == query.to_lower(): score += 30
		if entry.get("role") == "component": score *= 0.7
		var result: Dictionary = entry.duplicate()
		result["score"] = score
		result["matched_terms"] = matched
		ranked.append(result)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.score == b.score: return str(a.id) < str(b.id)
		return a.score > b.score)
	var page: Array[Dictionary] = []
	for index in range(maxi(0, offset), mini(ranked.size(), offset + clampi(limit, 1, 96))): page.append(ranked[index])
	return page

static func get_asset_bundle_for_concept(query: String) -> Dictionary:
	var models := search_assets(query, "model", "", 4)
	var sounds := search_assets(query, "sound", "", 4)
	var primary: Dictionary = {}
	if not models.is_empty() and models[0].get("role") != "component" and _has_subject_match(models[0], query): primary = models.pop_front()
	sounds = sounds.filter(func(entry): return _has_subject_match(entry, query))
	return {"query": query, "search_terms": _tokens(query), "primary_model": primary, "optional_models": models, "sounds": sounds, "assembly_required": primary.is_empty() and not models.is_empty()}

static func _has_subject_match(entry: Dictionary, query: String) -> bool:
	for token in _tokens(query):
		if token not in MODIFIERS and float(_terms[entry.id].get(token, 0)) >= 5:
			return true
	return false

static func _one_typo(a: String, b: String) -> bool:
	if absi(a.length() - b.length()) > 1: return false
	for index in range(mini(a.length(), b.length())):
		if a[index] == b[index]: continue
		if a.length() == b.length():
			return a.substr(index + 1) == b.substr(index + 1) or (index + 1 < a.length() and a[index] == b[index + 1] and a[index + 1] == b[index] and a.substr(index + 2) == b.substr(index + 2))
		return a.substr(index + 1) == b.substr(index) if a.length() > b.length() else a.substr(index) == b.substr(index + 1)
	return true

static func ai_candidates(query: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for type_ in ["model", "sound"]:
		for entry in search_assets(query, type_, "", 8):
			result.append({"id": entry.id, "name": entry.name, "type": entry.type, "category": entry.category, "role": entry.get("role", "prop"), "tags": entry.tags, "score": entry.score})
	return result

static func load_model(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var resource := ResourceLoader.load(path)
		if resource is PackedScene: return resource.instantiate() as Node3D
	if not FileAccess.file_exists(path): return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK: return null
	return document.generate_scene(state) as Node3D

static func bounds(root: Node3D) -> AABB:
	return _bounds_recursive(root, Transform3D.IDENTITY, AABB())

static func _bounds_recursive(node: Node, transform_: Transform3D, result: AABB) -> AABB:
	if node is Node3D: transform_ = transform_ * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = transform_ * node.mesh.get_aabb()
		result = box if result.size == Vector3.ZERO else result.merge(box)
	for child in node.get_children(): result = _bounds_recursive(child, transform_, result)
	return result

static func spawn_asset(asset_id: String, parent: Node3D, transform_: Transform3D = Transform3D.IDENTITY) -> Node3D:
	var entry := get_asset(asset_id)
	if entry.is_empty() or entry.type != "model" or not is_instance_valid(parent): return null
	var model := load_model(entry.file)
	if model == null: return null
	var box := bounds(model)
	var wrapper := Node3D.new()
	wrapper.name = entry.name
	wrapper.set_meta("roblox_class", "Model")
	wrapper.set_meta("toolbox_asset_id", asset_id)
	wrapper.set_meta("source_asset_path", entry.file)
	parent.add_child(wrapper, true)
	wrapper.transform = transform_
	wrapper.add_child(model)
	var scale_: float = float(entry.get("units_to_studs", 3.0))
	model.scale *= scale_
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z) * scale_
	_tag_model(model, entry.file)
	return wrapper

static func _tag_model(node: Node, source: String) -> void:
	if node is Camera3D or node is Light3D:
		node.queue_free()
		return
	if node is MeshInstance3D and node.mesh != null:
		node.set_meta("roblox_class", "MeshPart")
		node.set_meta("shape_type", "MeshPart")
		node.set_meta("roblox_mesh_applied", true)
		node.set_meta("source_asset_path", source)
		node.set_meta("can_collide", true)
		node.set_meta("anchored", true)
		node.add_to_group("studio_parts")
	elif node is Node3D and not node is Skeleton3D:
		node.set_meta("roblox_class", "Model")
	for child in node.get_children(): _tag_model(child, source)

static func load_sound(path: String) -> AudioStream:
	if ResourceLoader.exists(path): return ResourceLoader.load(path) as AudioStream
	return AudioStreamOggVorbis.load_from_file(path)

static func attach_sound(asset_id: String, target: Node) -> AudioStreamPlayer3D:
	var entry := get_asset(asset_id)
	if entry.is_empty() or entry.type != "sound" or not is_instance_valid(target): return null
	var stream := load_sound(entry.file)
	if stream == null: return null
	var sound := AudioStreamPlayer3D.new()
	sound.name = entry.name
	sound.stream = stream
	sound.max_distance = 80
	sound.set_meta("roblox_class", "Sound")
	sound.set_meta("SoundId", entry.file)
	sound.set_meta("toolbox_asset_id", asset_id)
	sound.set_meta("roblox_properties", {"SoundId": entry.file, "Volume": 1.0, "RollOffMaxDistance": 80.0})
	target.add_child(sound, true)
	return sound
