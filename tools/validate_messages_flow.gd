extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cloud = root.get_node("CloudAPI")
	var session = root.get_node("UserSession")
	var port := int(OS.get_cmdline_user_args()[0])
	cloud.project_url = "http://127.0.0.1:%d/api" % port
	cloud.base_url = cloud.project_url + "/rest/v1"
	cloud.api_key = "local-test"
	cloud.set("_auth_user_id", "alice")
	cloud.set("_auth_access_token", "alice")
	cloud.set("_auth_refresh_token", "")
	cloud.set("_auth_expires_at", 0)
	cloud.set("_current_profile_username", "")
	session.user_id = "alice"
	root.size = Vector2i(1100, 720)
	root.content_scale_size = root.size
	var panel := load("res://scripts/lobby/friends_messages.gd").new() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await panel.refresh_friends()
	assert((panel.get("_friends") as VBoxContainer).get_child_count() == 1)
	panel.call("_select_peer", "bob", "Bob")
	await _idle(panel)
	assert((panel.get("_feed") as VBoxContainer).get_child_count() == 1)
	var input := panel.get("_input") as LineEdit
	input.text = "Привет, Bob! [b]Текст[/b]"
	await panel._send_message()
	await _idle(panel)
	assert(input.text.is_empty())
	assert((panel.get("_feed") as VBoxContainer).get_child_count() == 2)
	var rating: Dictionary = await cloud.vote_for_map("map1", -1)
	assert(rating.get("ok", false))
	assert(int(rating.data.rating_negative) == 1)
	panel.call("_select_peer", "eve", "Eve")
	await _idle(panel)
	assert((panel.get("_feed") as VBoxContainer).get_child_count() == 0)
	input.text = "Must stay unsent"
	await panel._send_message()
	assert(input.text == "Must stay unsent")
	panel.queue_free()
	await process_frame
	print("[messages_flow] PASS: real Godot UI + local HTTP, history, send, literal text, vote, forbidden peer")
	quit(0)

func _idle(panel: Control) -> void:
	for frame in range(1000):
		if not panel.get("_loading") and not panel.get("_sending"): return
		await process_frame
	push_error("Message request timed out")
	quit(1)
