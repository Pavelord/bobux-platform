extends SceneTree


func _initialize() -> void:
	var user_session := root.get_node_or_null("UserSession")
	var cloud_api := root.get_node_or_null("CloudAPI")
	if user_session == null:
		push_error("[validate_catalog_ownership] UserSession autoload is missing")
		quit(1)
		return
	var previous_user_id := str(user_session.get("user_id"))
	var current_inventory: Variant = user_session.get("inventory_items")
	var previous_inventory: Array = current_inventory.duplicate(true) if current_inventory is Array else []
	user_session.set("user_id", "owner_1")
	user_session.set("inventory_items", ["inventory_item"])

	var catalog_script := load("res://scripts/lobby/catalog_builder.gd") as Script
	if catalog_script == null:
		_restore_session(user_session, previous_user_id, previous_inventory)
		push_error("[validate_catalog_ownership] CatalogBuilder script is missing")
		quit(1)
		return
	var owned_by_flag: bool = catalog_script._is_catalog_item_owned({"id": "flag_item", "owned": true}, cloud_api)
	var owned_by_inventory: bool = catalog_script._is_catalog_item_owned({"id": "inventory_item"}, cloud_api)
	var owned_by_creator: bool = catalog_script._is_catalog_item_owned({"id": "creator_item", "owner_id": "owner_1"}, cloud_api)
	var foreign: bool = catalog_script._is_catalog_item_owned({"id": "foreign_item", "owner_id": "owner_2"}, cloud_api)
	var section_shirt: String = catalog_script._catalog_section_for_item({"category": "shirt"})
	var section_pants: String = catalog_script._catalog_section_for_item({"data": {"item_kind": "pants"}})
	var section_accessory: String = catalog_script._catalog_section_for_item({"category": "model"})
	_restore_session(user_session, previous_user_id, previous_inventory)
	if not owned_by_flag or not owned_by_inventory or not owned_by_creator or foreign:
		push_error("[validate_catalog_ownership] Catalog ownership detection failed")
		quit(1)
		return
	if section_shirt != "Shirts" or section_pants != "Pants" or section_accessory != "Accessories":
		push_error("[validate_catalog_ownership] Catalog section detection failed: %s / %s / %s" % [section_shirt, section_pants, section_accessory])
		quit(1)
		return
	print("[validate_catalog_ownership] Catalog ownership and sections OK")
	quit(0)


func _restore_session(user_session: Node, previous_user_id: String, previous_inventory: Array) -> void:
	user_session.set("user_id", previous_user_id)
	user_session.set("inventory_items", previous_inventory)
