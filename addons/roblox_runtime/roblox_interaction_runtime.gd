extends RefCounted

static func prompt_position(prompt: Node) -> Vector3:
	var anchor := prompt.get_parent()
	while anchor != null and not anchor is Node3D: anchor = anchor.get_parent()
	if anchor == null: return Vector3.ZERO
	for name_ in ["Handle", "Display", "HumanoidRootPart"]:
		var part := anchor.get_node_or_null(name_) as Node3D
		if part != null: return part.global_position
	return anchor.global_position

static func activate_nearest_prompt(boundary: Node, character: CharacterBody3D, engine: Node, native_action: Callable = Callable(), room_filter: Callable = Callable()) -> bool:
	var nearest := nearest_prompt(boundary, character, room_filter)
	if nearest == null: return false
	var player_id := int(character.get_meta("bobux_player_instance_id", 0))
	var player: Variant = instance_from_id(player_id) if player_id > 0 else null
	if not is_instance_valid(player): return false
	var handled := bool(native_action.call(nearest, character)) if native_action.is_valid() else false
	return bool(engine.fire_roblox_instance_event(nearest, "Triggered", [player])) or handled

static func nearest_prompt(boundary: Node, character: CharacterBody3D, room_filter: Callable = Callable()) -> Node:
	if not is_instance_valid(boundary) or not is_instance_valid(character): return null
	var nearest: Node = null
	var nearest_distance := INF
	for candidate in boundary.get_tree().get_nodes_in_group("roblox_proximity_prompts"):
		if not is_instance_valid(candidate) or not boundary.is_ancestor_of(candidate): continue
		if room_filter.is_valid() and not bool(room_filter.call(candidate)): continue
		var props: Dictionary = candidate.get_meta("roblox_properties", {})
		if not bool(candidate.get_meta("Enabled", props.get("Enabled", true))): continue
		var owner := candidate.get_parent()
		var in_inventory := false
		while owner != null and owner != boundary:
			if str(owner.get_meta("roblox_class", "")) in ["Backpack", "StarterPack"] or owner == character: in_inventory = true; break
			owner = owner.get_parent()
		if in_inventory: continue
		var anchor: Node = candidate.get_parent()
		while anchor != null and not anchor is Node3D: anchor = anchor.get_parent()
		if anchor == null: continue
		var distance := character.global_position.distance_to(prompt_position(candidate))
		var max_distance := float(candidate.get_meta("MaxActivationDistance", props.get("MaxActivationDistance", 10.0))) * float(character.get_meta("roblox_stud_scale", 1.0))
		if distance <= max_distance and distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest

static func detector_for_hit(hit: Node, boundary: Node) -> Node:
	var cursor := hit
	while is_instance_valid(cursor) and cursor != boundary:
		if str(cursor.get_meta("roblox_class", "")) == "ClickDetector" or cursor.is_in_group("roblox_click_detectors"):
			return cursor
		for child in cursor.get_children():
			if str(child.get_meta("roblox_class", "")) == "ClickDetector" or child.is_in_group("roblox_click_detectors"):
				return child
		cursor = cursor.get_parent()
	return null

static func activate_click(camera: Camera3D, position: Vector2, boundary: Node, character: CharacterBody3D, engine: Node, native_action: Callable = Callable(), room_filter: Callable = Callable()) -> bool:
	if not is_instance_valid(camera) or not is_instance_valid(character) or not is_instance_valid(boundary):
		return false
	var origin := camera.project_ray_origin(position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(position) * 4096.0)
	query.collide_with_areas = true
	query.exclude = [character.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	if not is_instance_valid(collider) or not collider is Node or not boundary.is_ancestor_of(collider):
		return false
	var detector := detector_for_hit(collider, boundary)
	return activate_detector(detector, character, engine, native_action, room_filter)

static func activate_detector(detector: Node, character: CharacterBody3D, engine: Node, native_action: Callable = Callable(), room_filter: Callable = Callable()) -> bool:
	if not is_instance_valid(detector) or not is_instance_valid(character):
		return false
	if room_filter.is_valid() and not bool(room_filter.call(detector)):
		return false
	var anchor := detector.get_parent()
	while anchor != null and not anchor is Node3D:
		anchor = anchor.get_parent()
	var properties: Dictionary = detector.get_meta("roblox_properties", {})
	var distance := float(detector.get_meta("MaxActivationDistance", properties.get("MaxActivationDistance", 32.0)))
	var stud_scale := float(character.get_meta("roblox_stud_scale", 1.0))
	if anchor == null or character.global_position.distance_to((anchor as Node3D).global_position) > distance * stud_scale:
		return false
	var player_id := int(character.get_meta("bobux_player_instance_id", 0))
	var actor: Variant = instance_from_id(player_id) if player_id != 0 else null
	if not is_instance_valid(actor):
		return false
	var handled := bool(native_action.call(detector, character)) if native_action.is_valid() else false
	return bool(engine.fire_roblox_instance_event(detector, "MouseClick", [actor])) or handled
