extends SceneTree

const AVATAR_TEMPLATE_PROCESSOR: Script = preload("res://scripts/avatar/avatar_template_processor.gd")

func _initialize() -> void:
	var shirt_result: Dictionary = AVATAR_TEMPLATE_PROCESSOR.import_template_to_user_storage(
		"res://assets/avatar/shirt_template_reference.jpg",
		"shirt",
		"codex_validation"
	)
	if not bool(shirt_result.get("ok", false)):
		push_error("[validate_avatar_clothing_pipeline] Shirt import failed: %s" % str(shirt_result.get("error", "unknown")))
		quit(1)
		return
	var pants_result: Dictionary = AVATAR_TEMPLATE_PROCESSOR.import_template_to_user_storage(
		"res://assets/avatar/pants_template_reference.jpg",
		"pants",
		"codex_validation"
	)
	if not bool(pants_result.get("ok", false)):
		push_error("[validate_avatar_clothing_pipeline] Pants import failed: %s" % str(pants_result.get("error", "unknown")))
		quit(1)
		return
	for result in [shirt_result, pants_result]:
		var atlas_path := str(result.get("path", ""))
		var preview_path := str(result.get("preview_path", ""))
		if not FileAccess.file_exists(atlas_path) or not FileAccess.file_exists(preview_path):
			push_error("[validate_avatar_clothing_pipeline] Imported files are missing for %s" % str(result.get("kind", "")))
			quit(1)
			return
		var atlas := Image.new()
		if atlas.load(atlas_path) != OK or atlas.get_width() != 1280 or atlas.get_height() != 1280:
			push_error("[validate_avatar_clothing_pipeline] Atlas is not normalized: %s" % atlas_path)
			quit(1)
			return
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_avatar_clothing_pipeline] Could not load player scene")
		quit(1)
		return
	var player := player_scene.instantiate()
	root.add_child(player)
	player.set("is_ui_preview", true)
	player.set("use_local_avatar_fallback", false)
	player.set("shirt_texture_path", str(shirt_result.get("path", "")))
	player.set("pants_texture_path", str(pants_result.get("path", "")))
	player.set("equipped_avatar_items", [{
		"id": "validation_hat",
		"name": "Validation Hat",
		"category": "model",
		"attachment_slot": "Head",
		"attachment_transform": {
			"position": [0.0, 0.35, 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [1.0, 1.0, 1.0]
		},
		"data": {
			"parts": [{
				"name": "HatBlock",
				"kind": "Block",
				"position": [0.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.9, 0.22, 0.9],
				"color": "222222"
			}]
		}
	}])
	await process_frame
	if player.has_method("force_avatar_visual_refresh"):
		player.force_avatar_visual_refresh()
	await process_frame
	var shirt_decal := player.get_node_or_null("Visuals/Torso/ShirtFrontDecal") as MeshInstance3D
	var shirt_up_decal := player.get_node_or_null("Visuals/Torso/ShirtUpDecal") as MeshInstance3D
	var arm_decal := player.get_node_or_null("Visuals/LeftArmPivot/LeftArm/LeftArmShirtDecal") as MeshInstance3D
	var arm_up_decal := player.get_node_or_null("Visuals/LeftArmPivot/LeftArm/LeftArmShirtUpDecal") as MeshInstance3D
	var arm_down_decal := player.get_node_or_null("Visuals/LeftArmPivot/LeftArm/LeftArmShirtDownDecal") as MeshInstance3D
	var pants_decal := player.get_node_or_null("Visuals/LeftLegPivot/LeftLeg/LeftPantsFrontDecal") as MeshInstance3D
	var pants_up_decal := player.get_node_or_null("Visuals/LeftLegPivot/LeftLeg/LeftPantsUpDecal") as MeshInstance3D
	var pants_down_decal := player.get_node_or_null("Visuals/LeftLegPivot/LeftLeg/LeftPantsDownDecal") as MeshInstance3D
	if shirt_decal == null or not shirt_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Shirt front decal is not visible")
		quit(1)
		return
	if shirt_up_decal == null or not shirt_up_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Shirt shoulder/top decal is not visible")
		quit(1)
		return
	if arm_decal == null or not arm_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Arm shirt decal is not visible")
		quit(1)
		return
	if arm_up_decal == null or not arm_up_decal.visible or arm_down_decal == null or not arm_down_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Arm shirt top/bottom decals are not visible")
		quit(1)
		return
	if pants_decal == null or not pants_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Pants front decal is not visible")
		quit(1)
		return
	if pants_up_decal == null or not pants_up_decal.visible or pants_down_decal == null or not pants_down_decal.visible:
		push_error("[validate_avatar_clothing_pipeline] Pants top/bottom decals are not visible")
		quit(1)
		return
	var shirt_quad := shirt_decal.mesh as QuadMesh
	var shirt_up_quad := shirt_up_decal.mesh as QuadMesh
	var arm_quad := arm_decal.mesh as QuadMesh
	var arm_up_quad := arm_up_decal.mesh as QuadMesh
	var pants_quad := pants_decal.mesh as QuadMesh
	var pants_up_quad := pants_up_decal.mesh as QuadMesh
	if shirt_quad == null or shirt_quad.size.x < 1.9 or shirt_quad.size.y < 1.9:
		push_error("[validate_avatar_clothing_pipeline] Torso shirt decal does not cover the full body face")
		quit(1)
		return
	if shirt_up_quad == null or shirt_up_quad.size.x < 1.9 or shirt_up_quad.size.y < 0.9:
		push_error("[validate_avatar_clothing_pipeline] Torso shirt top decal does not cover the full shoulder face")
		quit(1)
		return
	if arm_quad == null or arm_quad.size.x < 0.9 or arm_quad.size.y < 1.9:
		push_error("[validate_avatar_clothing_pipeline] Arm shirt decal does not cover the full limb face")
		quit(1)
		return
	if arm_up_quad == null or arm_up_quad.size.x < 0.9 or arm_up_quad.size.y < 0.9:
		push_error("[validate_avatar_clothing_pipeline] Arm shirt top decal does not cover the full limb cap")
		quit(1)
		return
	if pants_quad == null or pants_quad.size.x < 0.9 or pants_quad.size.y < 1.9:
		push_error("[validate_avatar_clothing_pipeline] Pants decal does not cover the full limb face")
		quit(1)
		return
	if pants_up_quad == null or pants_up_quad.size.x < 0.9 or pants_up_quad.size.y < 0.9:
		push_error("[validate_avatar_clothing_pipeline] Pants top decal does not cover the full limb cap")
		quit(1)
		return
	var attachment_root := player.get_node_or_null("Visuals/AvatarAttachments") as Node3D
	if attachment_root == null or attachment_root.get_child_count() == 0:
		push_error("[validate_avatar_clothing_pipeline] Avatar attachment item did not render")
		quit(1)
		return
	var pants_only_player := player_scene.instantiate()
	root.add_child(pants_only_player)
	pants_only_player.set("is_ui_preview", true)
	pants_only_player.set("use_local_avatar_fallback", false)
	pants_only_player.set("shirt_texture_path", "")
	pants_only_player.set("pants_texture_path", str(pants_result.get("path", "")))
	await process_frame
	if pants_only_player.has_method("force_avatar_visual_refresh"):
		pants_only_player.force_avatar_visual_refresh()
	await process_frame
	var pants_only_torso := pants_only_player.get_node_or_null("Visuals/Torso/ShirtFrontDecal") as MeshInstance3D
	var pants_only_arm := pants_only_player.get_node_or_null("Visuals/LeftArmPivot/LeftArm/LeftArmShirtDecal") as MeshInstance3D
	var pants_only_leg := pants_only_player.get_node_or_null("Visuals/LeftLegPivot/LeftLeg/LeftPantsFrontDecal") as MeshInstance3D
	if pants_only_torso == null or not pants_only_torso.visible:
		push_error("[validate_avatar_clothing_pipeline] Pants-only outfit did not render the pants torso template area")
		quit(1)
		return
	if pants_only_arm != null and pants_only_arm.visible:
		push_error("[validate_avatar_clothing_pipeline] Pants-only outfit incorrectly rendered shirt arm regions")
		quit(1)
		return
	if pants_only_leg == null or not pants_only_leg.visible:
		push_error("[validate_avatar_clothing_pipeline] Pants-only outfit did not render leg regions")
		quit(1)
		return
	print("[validate_avatar_clothing_pipeline] Avatar clothing pipeline OK")
	quit(0)
