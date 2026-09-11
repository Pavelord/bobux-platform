extends SceneTree


func _initialize() -> void:
	var packed := load("res://scenes/place_editor/studio.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var actions := [
		{
			"type": "create_model",
			"name": "AI House",
			"parts": [
				{"name": "Floor", "shape": "Box", "size": [10, 1, 8], "position": [0, 0, 0], "rotation": [0, 0, 0], "color": "#8B5A2B", "material": "Wood", "anchored": true, "can_collide": true},
				{"name": "Roof", "shape": "Wedge", "size": [10, 3, 8], "position": [0, 3, 0], "rotation": [0, 0, 0], "color": "#C0392B", "material": "Plastic", "anchored": true, "can_collide": true},
			]
		},
		{
			"type": "create_part", "name": "Lamp", "shape": "Sphere", "size": [1, 1, 1], "position": [0, 5, 0], "rotation": [0, 0, 0],
			"color": "#FFFF55", "material": "Neon", "anchored": true, "can_collide": false,
			"effects": [{"type": "Fire", "color": "#FF7814", "enabled": true, "rate": 32}],
			"interaction": {"mode": "click", "action": "toggle_effect", "prompt": "Switch fire", "max_distance": 16}
		},
		{"type": "create_script", "name": "HouseLogic", "script_type": "Script", "parent": "ServerScriptService", "source": "print('AI house ready')"},
	]
	var applied := int(studio.call("_apply_studio_ai_actions", actions))
	var parts: Array = studio.call("_get_editor_parts")
	var generated_parts := parts.filter(func(part: Node) -> bool: return bool(part.get_meta("bobux_ai_generated", false)))
	var data_model: Node = studio.get("data_model")
	var scripts: Array = data_model.find_all_of_class("Script") if data_model != null else []
	var generated_script := scripts.any(func(script: Node) -> bool:
		return str(script.name) == "HouseLogic" and str(script.get_meta("lua_source", "")) == "print('AI house ready')"
	)
	var house := studio.get("placement_parent").get_node_or_null("AI House") as Node3D
	var lamp := studio.get("placement_parent").get_node_or_null("Lamp") as MeshInstance3D
	var fire := lamp.get_node_or_null("Fire") as GPUParticles3D if lamp != null else null
	var detector := lamp.get_node_or_null("ClickDetector") if lamp != null else null
	var interaction_script := lamp.get_node_or_null("InteractionScript") if lamp != null else null
	studio.call("_set_selection", [lamp])
	var modified := int(studio.call("_apply_studio_ai_actions", [{"type": "modify_selected", "color": "#3366CC", "material": "Metal"}]))
	var lamp_color: Color = lamp.get_meta("bobux_color", Color.WHITE) if lamp != null else Color.WHITE
	var serialized: Dictionary = studio.call("_serialize_block_for_clipboard", lamp) if lamp != null else {}
	var copied := studio.call("_create_block_from_clipboard", serialized, Vector3.ZERO, true) as MeshInstance3D
	var copied_effect := copied.get_node_or_null("Fire") if copied != null else null
	var ok := applied == 4 and modified == 1 and generated_parts.size() == 3 and generated_script \
		and house != null and house.get_child_count() == 2 and fire != null and fire.emitting \
		and detector != null and detector.is_in_group("roblox_click_detectors") \
		and interaction_script != null and str(interaction_script.get_meta("lua_source", "")).contains("effect.Enabled") \
		and lamp_color.is_equal_approx(Color("#3366CC")) and copied_effect is GPUParticles3D
	print("[validate_studio_ai_builder] ok=%s applied=%d modified=%d parts=%d script=%s" % [str(ok), applied, modified, generated_parts.size(), str(generated_script)])
	if copied != null:
		copied.free()
	studio.free()
	quit(0 if ok else 1)
