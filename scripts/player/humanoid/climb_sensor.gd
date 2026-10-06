extends RefCounted
class_name ClimbSensor


static func probe(body: CharacterBody3D, direction: Vector3, config: HumanoidConfig) -> Dictionary:
	if direction.length_squared() <= 0.000001 or body.get_world_3d() == null:
		return {}
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	if flat_direction.length_squared() <= 0.000001:
		return {}
	var scale_: float = body.get("world_stud_scale")
	var root_height := float(body.get_meta("roblox_hrp_height_above_body_origin", config.float_value("Trace.HRPHeightAboveBodyOrigin"))) * scale_
	# Probe the chest's width and height. A single centre ray can pass through
	# a truss opening, dropping Climbing every time the next rung goes past.
	var side := flat_direction.cross(Vector3.UP)
	# Search from the torso's outer face. R6 is wider than it is deep;
	# measuring one stud from its centre made the two wide sides unreachable.
	var torso := body.get_node_or_null("CollisionTorso") as CollisionShape3D
	var support := 0.0
	if torso != null and torso.shape is BoxShape3D:
		var half: Vector3 = torso.shape.size * 0.5
		support = absf(flat_direction.dot(torso.global_basis.x)) * half.x + absf(flat_direction.dot(torso.global_basis.z)) * half.z
	var reach := config.float_value("ClimbSensor.SearchDistance") * scale_ + support
	for height in [0.0, -0.65, 0.65]:
		for lateral in [0.0, -0.6, 0.6]:
			var start: Vector3 = body.global_position + Vector3.UP * (root_height + height * scale_) + side * lateral * scale_
			var hit := _ray(body, start, start + flat_direction * reach)
			if not hit.is_empty(): return hit
	return {}

static func _ray(body: CharacterBody3D, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, body.collision_mask, [body.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = true
	# A rail can already overlap the chest sensor while climbing a seam.
	query.hit_from_inside = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Variant = hit.get("collider")
	var part: Variant = collider
	if is_instance_valid(collider) and collider is Node:
		var shape_parts: Dictionary = collider.get_meta("_bobux_shape_parts", {})
		var part_id := int(shape_parts.get(int(hit.get("shape", -1)), 0))
		if part_id != 0:
			part = instance_from_id(part_id)
		elif collider.has_meta("bobux_visual_instance_id"):
			part = instance_from_id(int(collider.get_meta("bobux_visual_instance_id")))
	if not is_truss(part):
		return {}
	hit["truss_part"] = part
	if Vector3(hit.get("normal", Vector3.ZERO)).length_squared() < 0.00001:
		hit["normal"] = (start - end).normalized()
	return hit


static func is_truss(value: Variant) -> bool:
	var cursor := value as Node if value is Node else null
	while cursor != null:
		if str(cursor.get_meta("roblox_class", "")) == "TrussPart" or str(cursor.get_meta("shape_type", "")) == "Truss":
			return true
		cursor = cursor.get_parent()
	return false
