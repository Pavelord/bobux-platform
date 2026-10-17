extends SceneTree


func _initialize() -> void:
	var session: Node = load("res://autoload/user_session.gd").new()
	var raw := {
		"equipped": ["hat-one", {"id": "shoulder-two"}, "hat-one", {"item_id": "back-three"}],
		"equipped_avatar_item_payloads": [
			{"id": "hat-one", "name": "Hat One", "slot": "Head"},
			{"id": "shoulder-two", "name": "Shoulder Two", "slot": "Shoulder"}
		]
	}
	var clean: Dictionary = session.call("_sanitize_avatar_data_for_runtime", raw)
	var equipped: Array = clean.get("equipped", [])
	var payloads: Array = clean.get("equipped_avatar_item_payloads", [])
	var ids_ok := equipped == ["hat-one", "shoulder-two", "back-three"]
	var payloads_ok := payloads.size() == 2 \
		and payloads[0] is Dictionary \
		and str((payloads[0] as Dictionary).get("id", "")) == "hat-one"
	var ok := ids_ok and payloads_ok
	var large_outfit := {"equipped": [], "equipped_avatar_item_payloads": [], "owned_avatar_item_payloads": []}
	for index in range(140):
		var item := {"id": "persistence_accessory_%03d" % index, "name": "Accessory %d" % index, "data": {"slot": "Head", "attachment_scale": 0.3}}
		large_outfit.owned_avatar_item_payloads.append(item)
		if index < 72:
			large_outfit.equipped.append(item.id)
			large_outfit.equipped_avatar_item_payloads.append(item)
	# Exercise the same serialization/cache reload used when leaving a mode and
	# restarting the app, not only a direct call to the sanitizer.
	session.user_id = "validation-many-accessories"
	session.username = "Validation many accessories"
	session.avatar_data = large_outfit
	session.save_profile()
	session.avatar_data = {}
	var reloaded: bool = session.load_profile()
	var persisted: Dictionary = session.avatar_data
	var large_ok: bool = reloaded and persisted.equipped.size() == 72 and persisted.equipped_avatar_item_payloads.size() == 72 and persisted.owned_avatar_item_payloads.size() == 140
	large_ok = large_ok and persisted.equipped[71] == "persistence_accessory_071" and persisted.equipped_avatar_item_payloads[71].data.slot == "Head"
	ok = ok and large_ok
	print("[validate_avatar_equipped_persistence] saved_loaded_72=%s owned=%d" % [large_ok, persisted.get("owned_avatar_item_payloads", []).size()])
	print("[validate_avatar_equipped_persistence] ok=%s equipped=%s payloads=%d" % [
		str(ok),
		str(equipped),
		payloads.size()
	])
	session.free()
	quit(0 if ok else 1)
