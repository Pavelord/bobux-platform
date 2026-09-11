extends Node

func _ready() -> void:
	call_deferred("_explode")

func _explode() -> void:
	# Parts created in the same Lua callback enter the physics broadphase on
	# the next tick. Querying immediately silently missed those constructions.
	await get_tree().physics_frame
	await get_tree().process_frame
	var explosion := get_parent() as Node3D
	if not is_instance_valid(explosion): return
	var engine := get_tree().root.get_node("LuaScriptEngine")
	var instance = engine.BobuxInstance.new(explosion)
	var scale_: float = instance._stud_scale()
	var radius := maxf(0.0, float(explosion.get_meta("BlastRadius", 4.0)))
	var pressure := maxf(0.0, float(explosion.get_meta("BlastPressure", 500000.0)))
	if radius <= 0: return
	var sphere := SphereShape3D.new()
	sphere.radius = radius * scale_
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = explosion.global_position
	query.collision_mask = 1 | 2 | 4 | 16
	query.collide_with_areas = true
	var seen := {}
	var hit_bodies: Array = explosion.get_world_3d().direct_space_state.intersect_shape(query, 1024)
	for hit in hit_bodies:
		var part: Node = instance._part_from_raycast_collider(hit.collider)
		if part == null or seen.has(part.get_instance_id()): continue
		seen[part.get_instance_id()] = true
		var distance := (part as Node3D).global_position.distance_to(explosion.global_position) / scale_
		engine.fire_roblox_instance_event(explosion, "Hit", [part, distance])
		if pressure <= 0: continue
		var part_instance = engine.BobuxInstance.new(part)
		var body: CharacterBody3D = part_instance._character_body()
		if body != null and distance <= radius * float(explosion.get_meta("DestroyJointRadiusPercent", 1.0)):
			if body.has_method("take_damage"):
				body.take_damage(1000.0)
		var direction := (part as Node3D).global_position - explosion.global_position
		if direction.length_squared() < 0.001: direction = Vector3.UP
		var force := minf(pressure / 10000.0, 100.0) * maxf(0.0, 1.0 - distance / radius)
		part_instance.ApplyImpulse(part_instance, instance._godot_velocity_to_roblox(direction.normalized() * force * scale_))
	if bool(explosion.get_meta("Visible", true)):
		var flash := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = radius * scale_
		mesh.height = radius * scale_ * 2
		flash.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 0.45, 0.08, 0.4)
		flash.material_override = material
		explosion.add_child(flash)
		var tween := create_tween()
		tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(explosion): explosion.queue_free()
