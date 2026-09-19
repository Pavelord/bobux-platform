extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var lobby = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_meta("boblox_preview", true)
	root.add_child(lobby)
	await create_timer(0.3).timeout
	var account := {"balance": 38, "verified_badge": true, "club_tier": "TBC", "club_lifetime": true,
		"membership": {"tier": "TBC", "lifetime": true, "daily": 38}, "founder_reward": {"pending": false}}
	lobby.call("_on_boblox_account_updated", account)
	lobby.call("_on_boblox_account_updated", account)
	var label: Label = lobby.get("sidebar_username")
	var row := label.get_parent()
	assert(row.get_child_count() == 3, "One label and two badges; no duplicates")
	assert(row.get_meta("account_badge_row", false))
	var before := label.text
	load("res://scripts/lobby/account_badges.gd").attach(label, {"club_tier": "BC"})
	assert(row.get_child_count() == 1, "Free BC is hidden outside profiles")
	load("res://scripts/lobby/account_badges.gd").attach(label, {"club_tier": "BC"}, true)
	assert(row.get_child_count() == 2, "Profiles may show free BC")
	label.text = "pavelord"
	await process_frame
	await process_frame
	assert(label.size.x > 50, "Nickname must receive usable width")
	label.text = before
	assert(label.text == before)
	print("[account_badges] PASS lobby compiles, server fields render, refresh deduplicates, badges clear")
	lobby.queue_free()
	await process_frame
	quit()
