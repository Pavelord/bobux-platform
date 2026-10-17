extends "res://autoload/cloud_api.gd"
signal fixture_profile_completed(target: String, profile: Dictionary)
signal fixture_about_completed(result: Dictionary)
var fixture_user_id := "profile_update_own"
var fixture_requested: Array[String] = []
var fixture_saved_bio := ""
var fixture_imported: Array[String] = []

func is_configured() -> bool: return true
func has_authenticated_session() -> bool: return true
func get_current_user_id() -> String: return fixture_user_id
func get_current_username() -> String: return "SelfPlayer"
func authenticate_or_create_profile(_name: String = "", _generated := true) -> Dictionary: return {"ok": true, "username": "SelfPlayer"}
func fetch_legends() -> Dictionary: return {"ok": true, "games": []}
func update_profile_presence(_status: String, _game := "", _server: Dictionary = {}) -> Dictionary: return {"ok": true}
func fetch_halloween_event(_claim := "") -> Dictionary: return {"ok": false}
func load_player_profile(user_id: String, _service := false) -> Dictionary:
	fixture_requested.append(user_id)
	while true:
		var reply: Array = await fixture_profile_completed
		if str(reply[0]) == user_id: return {"ok": true, "data": reply[1]}
	return {"ok": false}
func fetch_active_servers(_map := "", _limit := 20, _timeout := 3.0, _retries := 1) -> Dictionary: return {"ok": true, "data": []}
func count_friends_for_user(_user: String, _service := false) -> Dictionary: return {"ok": true, "count": 7}
func get_follow_counts_for_user(_user: String, _service := false) -> Dictionary: return {"ok": true, "data": {"followers_count": 3, "following_count": 4}}
func import_recent_profile_visits(ids: Array[String]) -> Dictionary:
	fixture_imported = ids.duplicate()
	return {"ok": true, "data": {"id": fixture_user_id, "visited_modes_count": ids.size()}}
func update_profile_about(bio: String) -> Dictionary:
	fixture_saved_bio = bio
	return await fixture_about_completed
func fetch_published_maps_for_owner(owner: String, _limit := 20) -> Dictionary:
	var maps: Array = []
	for index in range(3):
		maps.append({"id": "profile_fixture_creation_%d" % index, "name": "Profile Creation %d" % index,
			"owner_id": owner, "owner_name": "Bob", "is_published": true, "is_public": true})
	return {"ok": true, "data": maps}
