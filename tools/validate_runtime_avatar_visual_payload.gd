extends SceneTree

func _initialize() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("[validate_runtime_avatar_visual_payload] GameState autoload is missing")
		quit(1)
		return
	game_state.apply_avatar_data({
		"face_texture_path": "res://assets/avatar/default_face.png",
		"chest_badge_texture_path": "",
		"shirt_texture_path": "res://assets/avatar/shirt_template_reference.jpg",
		"pants_texture_path": "res://assets/avatar/pants_template_reference.jpg",
		"equipped_avatar_item_payloads": [{
			"id": "runtime_hat_probe",
			"name": "Runtime Hat Probe",
			"category": "model",
			"attachment_slot": "Head",
			"attachment_transform": {
				"position": [0.0, 0.35, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.0, 1.0, 1.0]
			},
			"data": {
				"parts": [{
					"name": "ProbeBlock",
					"kind": "Block",
					"position": [0.0, 0.0, 0.0],
					"rotation_degrees": [0.0, 0.0, 0.0],
					"scale": [0.4, 0.2, 0.4],
					"color": "ffb347"
				}]
			}
		}]
	})
	if game_state.avatar_equipped_items.size() != 1:
		push_error("[validate_runtime_avatar_visual_payload] GameState did not keep equipped avatar item payloads")
		quit(1)
		return
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		push_error("[validate_runtime_avatar_visual_payload] Could not load main scene")
		quit(1)
		return
	var main: Node = main_scene.instantiate()
	if not main.has_method("_get_current_avatar_visuals"):
		push_error("[validate_runtime_avatar_visual_payload] Main is missing avatar visual helper")
		quit(1)
		return
	var visuals: Dictionary = main.call("_get_current_avatar_visuals")
	var equipped: Array = visuals.get("equipped_avatar_items", []) if visuals.get("equipped_avatar_items", []) is Array else []
	if equipped.size() != 1:
		push_error("[validate_runtime_avatar_visual_payload] Main did not expose equipped avatar payloads")
		quit(1)
		return
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	var player: Node = player_scene.instantiate()
	player.set("is_ui_preview", true)
	main.call("_apply_avatar_visuals_to_player", player, visuals)
	if player.get("equipped_avatar_items").size() != 1:
		push_error("[validate_runtime_avatar_visual_payload] Player did not receive equipped avatar payloads")
		quit(1)
		return
	print("[validate_runtime_avatar_visual_payload] Runtime avatar visual payload OK")
	player.free()
	main.free()
	quit(0)
