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
	var ok := position_ok and rotation_ok and scale_ok and color_ok
	if attachment != null and not ok:
		print("[validate_avatar_attachment_transform] actual position=%s rotation=%s scale=%s expected_position=%s" % [
			attachment.position,
			attachment.rotation_degrees,
			attachment.scale,
			expected_position
		])
	print("[validate_avatar_attachment_transform] ok=%s position=%s rotation=%s scale=%s color=%s" % [
		ok,
		position_ok,
		rotation_ok,
		scale_ok,
		color_ok
	])
	if attachment != null:
		attachment.free()
	player.free()
	quit(0 if ok else 1)
