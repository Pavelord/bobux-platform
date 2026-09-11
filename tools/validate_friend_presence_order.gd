extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/lobby/friends_builder.gd").new()
	var now_iso := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()), true)
	var playing := {"id": "playing", "username": "Playing", "status": "offline"}
	var online := {"id": "online", "username": "Online", "status": "online", "updated_at": now_iso}
	var offline := {"id": "offline", "username": "Offline", "status": "offline"}
	var lookup := {"playing": {"map_id": "map-1"}}
	var entries := [offline, online, playing]
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var rank_a: int = builder.call("_profile_presence_rank", a, lookup)
		var rank_b: int = builder.call("_profile_presence_rank", b, lookup)
		return rank_a < rank_b
	)
	if str(entries[0].get("id", "")) != "playing" or str(entries[1].get("id", "")) != "online":
		push_error("[validate_friend_presence_order] wrong order: %s" % [entries])
		quit(1)
		return
	print("[validate_friend_presence_order] playing -> online -> offline OK")
	quit(0)
