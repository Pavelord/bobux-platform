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
	print("[validate_avatar_equipped_persistence] ok=%s equipped=%s payloads=%d" % [
		str(ok),
		str(equipped),
		payloads.size()
	])
	session.free()
	quit(0 if ok else 1)
