extends SceneTree

const SHIRT_REFERENCE := "res://assets/avatar/shirt_template_reference.jpg"
const PANTS_REFERENCE := "res://assets/avatar/pants_template_reference.jpg"

func _initialize() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_avatar_preview_render_modes] Could not load player scene")
		quit(1)
		return

	var light_preview := player_scene.instantiate()
	root.add_child(light_preview)
	light_preview.set("is_ui_preview", true)
	light_preview.set("use_local_avatar_fallback", false)
	light_preview.set("render_avatar_clothing_decals", false)
	light_preview.set("shirt_texture_path", SHIRT_REFERENCE)
	light_preview.set("pants_texture_path", PANTS_REFERENCE)
	await process_frame
	light_preview.force_avatar_visual_refresh()
	await process_frame

	var face_decal := light_preview.get_node_or_null("Visuals/Head/FaceDecal") as MeshInstance3D
	if face_decal == null or not face_decal.visible:
		push_error("[validate_avatar_preview_render_modes] Lightweight preview lost face decal")
		quit(1)
		return
	var face_bounds := face_decal.get_aabb()
	if face_bounds.size.x > 0.85 or face_bounds.size.y > 0.65 or face_bounds.position.z < 0.45 or face_bounds.end.z > 0.64:
		push_error("[validate_avatar_preview_render_modes] Face decal curved bounds are outside expected head surface")
		quit(1)
		return
	var light_shirt := light_preview.get_node_or_null("Visuals/Torso/ShirtFrontDecal") as MeshInstance3D
	if light_shirt != null and light_shirt.visible:
		push_error("[validate_avatar_preview_render_modes] Lightweight preview rendered shirt clothing decal")
		quit(1)
		return

	var full_preview := player_scene.instantiate()
	root.add_child(full_preview)
	full_preview.set("is_ui_preview", true)
	full_preview.set("use_local_avatar_fallback", false)
	full_preview.set("render_avatar_clothing_decals", true)
	full_preview.set("shirt_texture_path", SHIRT_REFERENCE)
	full_preview.set("pants_texture_path", PANTS_REFERENCE)
	await process_frame
	full_preview.force_avatar_visual_refresh()
	await process_frame

	var full_shirt := full_preview.get_node_or_null("Visuals/Torso/ShirtFrontDecal") as MeshInstance3D
	var full_pants := full_preview.get_node_or_null("Visuals/LeftLegPivot/LeftLeg/LeftPantsFrontDecal") as MeshInstance3D
	if full_shirt == null or not full_shirt.visible:
		push_error("[validate_avatar_preview_render_modes] Full preview did not render shirt decal")
		quit(1)
		return
	if full_pants == null or not full_pants.visible:
		push_error("[validate_avatar_preview_render_modes] Full preview did not render pants decal")
		quit(1)
		return

	print("[validate_avatar_preview_render_modes] Avatar preview render modes OK")
	quit(0)
