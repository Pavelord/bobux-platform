extends "res://scripts/lobby/lobby.gd"
var reply: Dictionary = {"ok": false, "status": 503}
var requests := 0
var presence_requests := 0
func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func _fetch_home_friends_list() -> Dictionary:
	requests += 1
	var result := reply.duplicate(true)
	await get_tree().process_frame
	return result
func _refresh_home_friend_active_statuses_async() -> void:
	presence_requests += 1
func _create_home_friend_avatar(profile: Dictionary, _servers: Dictionary) -> Control:
	var label := Label.new()
	label.text = str(profile.get("username", ""))
	return label
func _queue_home_friends_clip_layout() -> void: pass
