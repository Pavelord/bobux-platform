extends SceneTree


func _initialize() -> void:
	var user_session := root.get_node_or_null("UserSession")
	if user_session == null:
		push_error("[validate_avatar_inventory_ownership] UserSession autoload is missing")
		quit(1)
		return
	var previous_user_id := str(user_session.get("user_id"))
	var current_inventory: Variant = user_session.get("inventory_items")
	var previous_inventory: Array = current_inventory.duplicate(true) if current_inventory is Array else []
	user_session.set("user_id", "owner_1")
	user_session.set("inventory_items", ["owned_by_inventory"])

	var avatar_ui_script := load("res://scripts/lobby/avatar_ui.gd") as Script
	if avatar_ui_script == null:
		push_error("[validate_avatar_inventory_ownership] AvatarUI script is missing")
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return
	var ui = avatar_ui_script.new()
	ui._cloud_inventory_loaded = true
	ui._user_inventory_ids = ["owned_by_inventory"]
	ui._cloud_catalog = [
		{
			"id": "owned_by_inventory",
			"owner_id": "owner_2",
			"data": {"item_kind": "hat"}
		},
		{
			"id": "owned_by_owner",
			"owner_id": "owner_1",
			"data": {"item_kind": "hat"}
		},
		{
			"id": "foreign_hat",
			"owner_id": "owner_2",
			"data": {"item_kind": "hat"}
		},
		{
			"id": "foreign_shirt",
			"owner_id": "owner_2",
			"data": {
				"item_kind": "shirt",
				"template_url": "res://assets/avatar/shirt_template_reference.jpg"
			}
		},
		{
			"id": "owned_shirt",
			"owner_id": "owner_1",
			"data": {
				"item_kind": "shirt",
				"template_url": "res://assets/avatar/shirt_template_reference.jpg"
			}
		}
	]
	ui._user_avatar_data = {
		"equipped": ["owned_by_inventory", "foreign_hat", "owned_by_owner", "foreign_hat"],
		"shirt_texture_path": "res://assets/avatar/shirt_template_reference.jpg"
	}

	var payloads: Array = ui._get_equipped_avatar_item_payloads()
	var equipped: Array = ui._user_avatar_data.get("equipped", [])
	if payloads.size() != 2 or equipped != ["owned_by_inventory", "owned_by_owner"]:
		push_error("[validate_avatar_inventory_ownership] Foreign equipped items were not sanitized: payloads=%d equipped=%s" % [payloads.size(), str(equipped)])
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return
	if ui._is_item_wearing(ui._cloud_catalog[2]):
		push_error("[validate_avatar_inventory_ownership] Foreign accessory is considered worn")
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return
	if ui._is_item_wearing(ui._cloud_catalog[3]):
		push_error("[validate_avatar_inventory_ownership] Foreign shirt is considered worn by matching texture path")
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return

	ui._user_avatar_data["saved_shirt_texture_paths"] = [
		"user://avatar_templates/local_old.png",
		"res://assets/avatar/shirt_template_reference.jpg"
	]
	var saved_paths: Array = ui._get_saved_visual_paths("saved_shirt_texture_paths", "res://assets/avatar/shirt_template_reference.jpg")
	if "res://assets/avatar/shirt_template_reference.jpg" in saved_paths:
		push_error("[validate_avatar_inventory_ownership] Owned cloud shirt texture still appears as a duplicate local saved shirt")
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return

	ui._categorized_items = {"Accessories": []}
	ui._local_visual_item_payloads.clear()
	ui._register_local_visual_item("Accessories", "bobux_chest_badge", "Bobux Chest Badge", "chest_badge_texture_path", GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH, GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH)
	ui._user_avatar_data["chest_badge_texture_path"] = GameState.DEFAULT_CHEST_BADGE_TEXTURE_PATH
	ui._toggle_item("bobux_chest_badge")
	if str(ui._user_avatar_data.get("chest_badge_texture_path", "missing")) != "":
		push_error("[validate_avatar_inventory_ownership] Default chest badge did not unequip")
		_restore_session(user_session, previous_user_id, previous_inventory)
		quit(1)
		return

	var cloud_api := root.get_node_or_null("CloudAPI")
	if cloud_api != null and cloud_api.has_method("_merge_avatar_outfit_into_session_avatar_data"):
		var merged_avatar: Dictionary = cloud_api.call("_merge_avatar_outfit_into_session_avatar_data", {}, {"chest_badge_texture_path": ""})
		if str(merged_avatar.get("chest_badge_texture_path", "missing")) != "":
			push_error("[validate_avatar_inventory_ownership] Empty cloud chest badge was restored to default")
			_restore_session(user_session, previous_user_id, previous_inventory)
			quit(1)
			return

	_restore_session(user_session, previous_user_id, previous_inventory)
	print("[validate_avatar_inventory_ownership] Avatar ownership filtering OK")
	quit(0)


func _restore_session(user_session: Node, previous_user_id: String, previous_inventory: Array) -> void:
	user_session.set("user_id", previous_user_id)
	user_session.set("inventory_items", previous_inventory)
