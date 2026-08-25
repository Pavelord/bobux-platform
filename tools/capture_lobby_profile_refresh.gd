extends SceneTree

const CAPTURE_PATH := "user://lobby_profile_refresh.png"


func _initialize() -> void:
	root.size = Vector2i(1440, 900)
	var packed := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lobby := packed.instantiate() as Control
	root.add_child(lobby)
	await create_timer(1.0).timeout
	var loading_overlay: Control = lobby.get("_loading_overlay") as Control
	if loading_overlay != null:
		loading_overlay.hide()
	lobby.set("_discover_refresh_token", int(lobby.get("_discover_refresh_token")) + 1000)

	var tabs := lobby.get_node_or_null("%MainTabs") as TabContainer
	if tabs == null:
		push_error("[capture_lobby_profile_refresh] MainTabs is missing")
		quit(1)
		return
	tabs.current_tab = 1

	var outfit := {
		"head_color": "#f4c542",
		"torso_color": "#246fbd",
		"left_arm_color": "#f4c542",
		"right_arm_color": "#f4c542",
		"left_leg_color": "#263238",
		"right_leg_color": "#263238",
		"face_texture_path": "res://assets/avatar/default_face.png",
		"shirt_texture_path": "res://assets/avatar/shirt_template_reference.jpg",
		"pants_texture_path": "res://assets/avatar/pants_template_reference.jpg",
		"equipped_avatar_item_payloads": [
			{
				"id": "profile-hat-preview",
				"name": "Builder Hat",
				"category": "Accessory",
				"thumbnail": "res://assets/branding/bobux_app_icon.png"
			}
		]
	}
	var profile := {
		"id": "profile-preview-user",
		"username": "BuilderMax",
		"join_date": "2026-04-17T10:00:00Z",
		"friends_count": 23,
		"followers_count": 14,
		"following_count": 8,
		"avatar_data": {
			"head": "#f4c542",
			"torso": "#246fbd",
			"left_arm": "#f4c542",
			"right_arm": "#f4c542",
			"left_leg": "#263238",
			"right_leg": "#263238"
		},
		"avatar_outfit": outfit
	}
	lobby.set("selected_profile_user_id", "profile-preview-user")
	lobby.set("selected_profile_username", "BuilderMax")
	lobby.set("selected_profile_snapshot", profile.duplicate(true))
	lobby.call("_apply_profile_snapshot_to_ui", profile, {"status": "online"})
	lobby.call("_update_profile_social_counts", profile, 23)
	lobby.call("_refresh_profile_currently_wearing", profile, outfit)
	await create_timer(3.0).timeout

	var preview_player: Node = lobby.get("profile_preview_player") as Node
	if preview_player == null:
		push_error("[capture_lobby_profile_refresh] Live avatar preview is missing")
		quit(1)
		return
	var wearing_grid: Container = lobby.get("profile_wearing_items_container") as Container
	if wearing_grid == null or wearing_grid.get_child_count() < 3:
		push_error("[capture_lobby_profile_refresh] Currently Wearing cards are incomplete")
		quit(1)
		return
	var header_holder: Control = lobby.get("profile_header_avatar_holder") as Control
	if header_holder == null or header_holder.get_child_count() != 1:
		push_error("[capture_lobby_profile_refresh] Header avatar snapshot is missing")
		quit(1)
		return

	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(CAPTURE_PATH) != OK:
		push_error("[capture_lobby_profile_refresh] Failed to save capture")
		quit(1)
		return
	print("[capture_lobby_profile_refresh] Capture saved")
	quit(0)
