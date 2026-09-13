extends RefCounted

# CharacterBody is infinitely massive to the rigid-body solver. Separate the
# player surface of heavy assemblies while retaining their physical simulation.
const PLAYER_SURFACE_LAYER := 32
const MIN_HEAVY_MASS_STUDS := 80.0

static func configure(body: RigidBody3D, stud_scale: float) -> void:
	var old := body.get_node_or_null("PlayerSurface")
	if old != null:
		body.remove_child(old)
		old.queue_free()
	if body.mass < MIN_HEAVY_MASS_STUDS * pow(stud_scale, 3): return
	var surface := AnimatableBody3D.new()
	surface.name = "PlayerSurface"
	surface.set_meta("bobux_runtime_generated", true)
	surface.set_meta("bobux_visual_instance_id", body.get_meta("bobux_visual_instance_id", 0))
	surface.set_meta("_bobux_shape_parts", body.get_meta("_bobux_shape_parts", {}))
	surface.collision_layer = PLAYER_SURFACE_LAYER
	surface.collision_mask = 2
	surface.sync_to_physics = false
	for child in body.get_children():
		if child is CollisionShape3D:
			var copy := CollisionShape3D.new()
			copy.shape = child.shape
			copy.transform = child.transform
			copy.disabled = child.disabled
			surface.add_child(copy)
	body.collision_layer = 64
	body.collision_mask = 1 | 4 | 64
	body.add_child(surface)
