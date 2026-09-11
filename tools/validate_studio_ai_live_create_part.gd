extends SceneTree


func _initialize() -> void:
	await process_frame
	await process_frame
	var cloud_api := get_root().get_node_or_null("CloudAPI")
	if cloud_api == null:
		print("[validate_studio_ai_live_create_part] ok=false reason=CloudAPI_missing")
		quit(1)
		return
	var response: Dictionary = await cloud_api.request_studio_ai(
		"Создай синий горящий Part",
		{"map_name": "AI Live Contract", "selected_name": "", "selected_class": "", "selected_position": []}
	)
	if not bool(response.get("ok", false)):
		print("[validate_studio_ai_live_create_part] ok=false request_error=%s" % str(response.get("error", "unknown")))
		quit(1)
		return
	var actions_value: Variant = response.get("actions", [])
	var actions: Array = actions_value if actions_value is Array else []
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	var studio := packed.instantiate() if packed != null else null
	if studio == null:
		print("[validate_studio_ai_live_create_part] ok=false reason=studio_missing")
		quit(1)
		return
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var applied := int(studio.call("_apply_studio_ai_actions", actions))
	var generated_parts: Array = (studio.call("_get_editor_parts") as Array).filter(
		func(part: Node) -> bool: return bool(part.get_meta("bobux_ai_generated", false))
	)
	var blue_fire_part: MeshInstance3D = null
	for part_variant in generated_parts:
		var part := part_variant as MeshInstance3D
		if part == null or part.get_node_or_null("Fire") == null:
			continue
		var color: Color = part.get_meta("bobux_color", Color.WHITE)
		if color.b > color.r and color.b > color.g:
			blue_fire_part = part
			break
	var ok := actions.size() > 0 and applied > 0 and blue_fire_part != null
	print("[validate_studio_ai_live_create_part] ok=%s actions=%d applied=%d blue_fire=%s" % [str(ok), actions.size(), applied, str(blue_fire_part != null)])
	studio.free()
	quit(0 if ok else 1)
