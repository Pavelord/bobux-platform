extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session := root.get_node("UserSession")
	var original: String = session.user_id
	session.user_id = "outfit-test-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var ui = load("res://scripts/lobby/avatar_ui.gd").new()
	ui._user_avatar_data = {"head": Color.RED, "equipped": ["owned_hat"], "inventory_items": ["must_not_copy"], "saved_outfits": {"must_not_nest": true}}
	var snapshot: Dictionary = ui._appearance_snapshot()
	assert(not snapshot.has("inventory_items") and not snapshot.has("saved_outfits"))
	ui._user_avatar_data.equipped.append("another_hat")
	assert(snapshot.equipped == ["owned_hat"], "Snapshots must not change when the current look changes")
	var looks := {"test": {"name": "Мой образ", "appearance": snapshot, "preview": ""}}
	assert(ui._write_saved_outfits(looks) == OK)
	var reloaded: Dictionary = ui._load_saved_outfits()
	assert(reloaded.test.name == "Мой образ" and reloaded.test.appearance.head == Color.RED)
	var directory: String = ui._outfit_directory()
	session.user_id = "different-test-account"
	assert(ui._load_saved_outfits().is_empty(), "Outfits must be separated by account")
	session.user_id = original
	DirAccess.remove_absolute(directory.path_join("looks.cfg"))
	DirAccess.remove_absolute(directory)
	print("SAVED_OUTFITS_OK")
	quit()
