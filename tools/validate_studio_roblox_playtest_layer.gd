extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame

	var workspace: Node3D = studio.get("placement_parent") as Node3D
	if workspace == null:
		push_error("Studio Workspace is missing")
		quit(1)
		return
	workspace.set_meta("roblox_stud_scale", 0.5)

	var snapshot_part := MeshInstance3D.new()
	snapshot_part.name = "SnapshotExactMesh"
	snapshot_part.mesh = _build_triangle_mesh()
	snapshot_part.position = Vector3(3.0, 4.0, 5.0)
	snapshot_part.set_meta("roblox_class", "MeshPart")
	snapshot_part.set_meta("shape_type", "ExactMesh")
	snapshot_part.set_meta("payload", {"colors": [1, 2, 3], "label": "preserve"})
	var nested := Node3D.new()
	nested.name = "NestedAttachment"
	nested.position = Vector3(0.25, 0.5, 0.75)
	nested.set_meta("roblox_class", "Attachment")
	snapshot_part.add_child(nested)
	workspace.add_child(snapshot_part)

	var water: MeshInstance3D = studio._build_block_instance(
		"Water", Color(0.12, 0.55, 0.92, 0.72), "Water", 0.28, false, "Water"
	)
	water.name = "Water"
	water.position = Vector3(20.0, 1.0, 0.0)
	workspace.add_child(water)
	var truss: MeshInstance3D = studio._build_block_instance(
		"Truss", Color(0.55, 0.55, 0.58), "Metal", 0.0, true, "Truss"
	)
	truss.name = "Truss"
	truss.position = Vector3(-20.0, 4.0, 0.0)
	workspace.add_child(truss)

	await studio._start_studio_playtest()
	var player: CharacterBody3D = studio.get("studio_playtest_player") as CharacterBody3D
	var scale_ok := (
		player != null
		and is_equal_approx(player.scale.x, 0.5)
		and is_equal_approx(float(player.call("get_humanoid_walk_speed")), 16.0)
		and is_equal_approx(float(player.call("get_humanoid_jump_power")), 50.0)
		and is_equal_approx(float(player.get("move_speed")), 8.0)
	)
	var spawn_position: Vector3 = player.global_position if player != null else Vector3.ZERO
	if player != null:
		player.global_position = Vector3(100.0, 100.0, 100.0)
		studio._reset_studio_playtest_character()
		for _frame in range(4):
			await physics_frame
			await process_frame
	var reset_ok := player != null and player.global_position.distance_to(spawn_position) < 2.0

	var water_area := water.get_node_or_null("WaterVolume") as Area3D
	var water_body := water.get_node_or_null("CollisionBody") as StaticBody3D
	var water_shape := water_body.get_node_or_null("CollisionShape3D") as CollisionShape3D if water_body != null else null
	var water_ok := (
		water.is_in_group("roblox_water")
		and water_area != null
		and water_shape != null
		and water_shape.disabled
		and not bool(water.get_meta("can_collide", true))
	)
	var truss_ok := (
		str(truss.get_meta("roblox_class", "")) == "TrussPart"
		and str(truss.get_meta("shape_type", "")) == "Truss"
		and truss.mesh != null
	)

	snapshot_part.position = Vector3(99.0, 99.0, 99.0)
	snapshot_part.mesh = BoxMesh.new()
	nested.queue_free()
	await process_frame
	await studio._stop_studio_playtest()
	await process_frame

	var restored := workspace.get_node_or_null("SnapshotExactMesh") as MeshInstance3D
	var restored_nested := restored.get_node_or_null("NestedAttachment") as Node3D if restored != null else null
	var payload: Dictionary = restored.get_meta("payload", {}) if restored != null and restored.get_meta("payload", {}) is Dictionary else {}
	var snapshot_ok := (
		restored != null
		and restored.mesh is ArrayMesh
		and restored.position.is_equal_approx(Vector3(3.0, 4.0, 5.0))
		and restored_nested != null
		and restored_nested.position.is_equal_approx(Vector3(0.25, 0.5, 0.75))
		and str(payload.get("label", "")) == "preserve"
		and (payload.get("colors", []) as Array).size() == 3
	)

	var ok := scale_ok and reset_ok and water_ok and truss_ok and snapshot_ok
	print("[validate_studio_roblox_playtest_layer] ok=%s scale=%s reset=%s water=%s truss=%s snapshot=%s" % [
		str(ok), str(scale_ok), str(reset_ok), str(water_ok), str(truss_ok), str(snapshot_ok),
	])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _build_triangle_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.7, 0.4)
	mesh.surface_set_material(0, material)
	return mesh
