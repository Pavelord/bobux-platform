extends SceneTree

func _initialize() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_avatar_attachment_transform] player scene is unavailable")
		quit(1)
		return
	var player: Node = player_scene.instantiate()
	player.set("is_ui_preview", true)
	var saved_offset := Vector3(0.35, 0.8, -0.2)
	var saved_rotation := Vector3(12.0, 34.0, -7.0)
	var saved_scale := Vector3(1.2, 0.9, 1.1)
	var item := {
		"name": "TransformValidationHat",
		"attachment_slot": "Head",
		"metadata": {
			"data": {
				"parts": [{
					"name": "ColoredHat",
					"kind": "Block",
					"position": [0.0, 0.0, 0.0],
					"rotation_degrees": [0.0, 0.0, 0.0],
					"scale": [1.0, 1.0, 1.0],
					"color": "e53935"
				}],
				"attachment_slot": "Head",
				"attachment_transform": {
					"position": [saved_offset.x, saved_offset.y, saved_offset.z],
					"rotation_degrees": [saved_rotation.x, saved_rotation.y, saved_rotation.z],
					"scale": [saved_scale.x, saved_scale.y, saved_scale.z]
				}
			}
		}
	}
	var attachment: Node3D = player.call("_create_avatar_attachment_node", item)
	var expected_position := Vector3(0.0, 5.2, 0.0) + saved_offset
	var position_ok := attachment != null and attachment.position.is_equal_approx(expected_position)
	var rotation_ok := attachment != null and attachment.rotation_degrees.is_equal_approx(saved_rotation)
	var scale_ok := attachment != null and attachment.scale.is_equal_approx(saved_scale)
	var color_ok := false
	if attachment != null and attachment.get_child_count() > 0:
		var part := attachment.get_child(0) as Node3D
		if part != null and part.get_child_count() > 0:
			var mesh := part.get_child(0) as MeshInstance3D
			if mesh != null:
				var material := mesh.get_active_material(0) as BaseMaterial3D
				color_ok = material != null and material.albedo_color.is_equal_approx(Color("e53935"))
	var surface_fallback_ok := _validate_surface_fallback(player)
	var source_color_preserved := _validate_source_color_preservation(player)
	var ok := position_ok and rotation_ok and scale_ok and color_ok and surface_fallback_ok and source_color_preserved
	if attachment != null and not ok:
		print("[validate_avatar_attachment_transform] actual position=%s rotation=%s scale=%s expected_position=%s" % [
			attachment.position,
			attachment.rotation_degrees,
			attachment.scale,
			expected_position
		])
	print("[validate_avatar_attachment_transform] ok=%s position=%s rotation=%s scale=%s color=%s surface_fallback=%s source_preserved=%s" % [
		ok,
		position_ok,
		rotation_ok,
		scale_ok,
		color_ok,
		surface_fallback_ok,
		source_color_preserved
	])
	if attachment != null:
		attachment.free()
	player.free()
	quit(0 if ok else 1)

func _validate_surface_fallback(player: Node) -> bool:
	var root := Node3D.new()
	var mesh_instance := _mesh_with_color("SurfaceColorModel", Color.WHITE)
	root.add_child(mesh_instance)
	player.call("_apply_avatar_attachment_source_fallback_colors", root, [{
		"name": "SurfaceColorModel",
		"color": "ffffff",
		"surface_materials": [{"surface": 0, "color": "2469d8"}]
	}])
	var material := mesh_instance.get_active_material(0) as BaseMaterial3D
	var ok := material != null and material.albedo_color.is_equal_approx(Color("2469d8"))
	root.free()
	return ok

func _validate_source_color_preservation(player: Node) -> bool:
	var root := Node3D.new()
	var expected := Color("31a85b")
	var mesh_instance := _mesh_with_color("AlreadyColored", expected)
	root.add_child(mesh_instance)
	player.call("_apply_avatar_attachment_source_fallback_colors", root, [{
		"name": "AlreadyColored",
		"color": "ffffff",
		"surface_materials": [{"surface": 0, "color": "d82924"}]
	}])
	var material := mesh_instance.get_active_material(0) as BaseMaterial3D
	var ok := material != null and material.albedo_color.is_equal_approx(expected)
	root.free()
	return ok

func _mesh_with_color(mesh_name: String, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	return mesh_instance
