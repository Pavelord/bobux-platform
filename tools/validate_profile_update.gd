extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func profile(id: String, username: String, bio := "", color := "#246fbd") -> Dictionary:
	return {"id": id, "username": username, "bio": bio, "join_date": "2026-04-17T10:00:00Z", "visited_modes_count": 12,
		"avatar_data": {"torso": color}, "avatar_outfit": {"equipped_avatar_item_payloads": []}}
func complete(api: Node, id: String, data: Dictionary) -> void:
	api.emit_signal("fixture_profile_completed", id, data)
	await process_frame
	await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation/profile_update"))
	root.get_texture().get_image().save_png("user://validation/profile_update/" + name + ".png")
func _run() -> void:
	await process_frame
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	check((load("res://scripts/main/main.gd") as Script).can_instantiate(), "successful spawn visit hook does not compile")
	var api := root.get_node("CloudAPI")
	api.set_script(load("res://tools/fixtures/profile_update_api.gd"))
	var session := root.get_node("UserSession")
	session.begin_cloud_session(api.fixture_user_id, "SelfPlayer")
	session.recent_games = [{"map_id": "old_park"}, {"map_id": "old_valley"}, {"map_id": "old_park"}]
	ProfileBuilder.remember(profile(api.fixture_user_id, "SelfPlayer", "Own description"))
	var lobby := (load("res://scenes/lobby/lobby.tscn") as PackedScene).instantiate() as Control
	lobby.set_script(load("res://tools/fixtures/profile_update_lobby.gd"))
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	lobby.call("_switch_tab", 1)
	await process_frame
	check(api.fixture_requested.has(api.fixture_user_id), "own profile refresh was not requested")
	var alice := profile("profile_update_alice", "Alice", "Alice description", "#20aa50")
	var bob := profile("profile_update_bob", "Bob", "Bob description", "#ee5500")
	lobby.call("_open_profile_for_user", alice.id, alice.username, alice, {})
	check(lobby.profile_username_label.text == "Alice", "opening Alice flashes the own username")
	check(lobby.profile_about_label.text == "Alice description", "opening Alice flashes own bio")
	check(lobby.profile_preview_player.torso_color.is_equal_approx(Color("#20aa50")), "opening Alice retains own avatar color")
	check(not lobby.profile_about_edit_button.visible, "description editing is offered for another player")
	await process_frame
	lobby.call("_open_profile_for_user", bob.id, bob.username, bob, {})
	await process_frame
	await complete(api, bob.id, bob)
	await complete(api, alice.id, alice)
	await complete(api, api.fixture_user_id, profile(api.fixture_user_id, "SelfPlayer", "Stale own result"))
	check(lobby.profile_username_label.text == "Bob" and lobby.selected_profile_user_id == bob.id, "out-of-order profile response changes selected identity")
	check(lobby.profile_about_label.text == "Bob description", "late own/Alice response leaks its description into Bob")
	check(lobby.join_date_label.text == "Join Date: 17.04.2026", "registration date is absent or made up")
	check(lobby.profile_visited_count_label.text == "12", "recorded visited mode count is absent")
	check(not lobby.has_node("ProfileGamesPanel"), "About has a duplicate My Games section")
	var orbit: Control = lobby.profile_preview_orbit
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	orbit.call("_gui_input", button)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(25, 0)
	orbit.call("_gui_input", motion)
	check(absf(lobby.profile_preview_player.rotation.y - 0.3) < 0.001, "PC drag does not rotate the profile character")
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	orbit.call("_gui_input", touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.relative = Vector2(25, 0)
	orbit.call("_gui_input", drag)
	check(absf(lobby.profile_preview_player.rotation.y - 0.6) < 0.001, "touch drag does not rotate the profile character")
	orbit.call("_gui_input", motion)
	check(absf(lobby.profile_preview_player.rotation.y - 0.6) < 0.001, "touch emulated mouse rotates twice")
	lobby.get_node("%NavProfileBtn").emit_signal("pressed")
	await process_frame
	await complete(api, api.fixture_user_id, profile(api.fixture_user_id, "SelfPlayer", "Own description"))
	check(lobby.profile_about_edit_button.visible and lobby.profile_about_label.text == "Own description", "own description edit or own identity reset failed")
	check(api.fixture_imported.is_empty(), "legacy recent attempts were incorrectly imported as successful visits")
	lobby.profile_about_edit_button.emit_signal("pressed")
	lobby.profile_about_input.text = "Persistent new description 🎃"
	lobby.call("_save_profile_about_async")
	check(lobby.profile_about_save_button.disabled and api.fixture_saved_bio == "Persistent new description 🎃", "save request is not guarded or contains different text")
	lobby.call("_open_profile_for_user", bob.id, bob.username, bob, {})
	await process_frame
	api.emit_signal("fixture_about_completed", {"ok": true, "data": {"id": api.fixture_user_id, "bio": "Persistent new description 🎃"}})
	await process_frame
	check(lobby.profile_about_label.text == "Bob description", "description save response overwrites another player")
	check(ProfileBuilder.cached_profile(api.fixture_user_id).get("bio", "") == "Persistent new description 🎃", "successful description was not cached for the correct account")
	await complete(api, bob.id, bob)
	lobby.get_node("%NavProfileBtn").emit_signal("pressed")
	await process_frame
	lobby.profile_about_edit_button.emit_signal("pressed")
	check(not lobby.profile_about_save_button.disabled, "save stays disabled after switching identity during a previous save")
	lobby.profile_about_input.text = "Acknowledged new description"
	lobby.call("_save_profile_about_async")
	api.emit_signal("fixture_about_completed", {"ok": true, "data": {"id": api.fixture_user_id, "bio": "Acknowledged new description"}})
	await process_frame
	await complete(api, api.fixture_user_id, profile(api.fixture_user_id, "SelfPlayer", "Old GET description"))
	check(lobby.profile_about_label.text == "Acknowledged new description", "old profile GET overwrites an acknowledged description save")
	check(not lobby.profile_about_editor.visible, "successful own description save leaves editor open")
	lobby.call("_open_profile_for_user", bob.id, bob.username, bob, {})
	await process_frame
	await complete(api, bob.id, bob)
	var gift := {"id": "event_halloween_2026_gift", "name": "Coffin Gift Box - Halloween", "category": "Accessory", "source_model_path": "res://assets/events/halloween2026/gift.glb", "data": {"source_model_path": "res://assets/events/halloween2026/gift.glb", "limited": true}}
	var outfit := {"shirt_texture_path": "res://assets/avatar/shirt_template_reference.jpg", "pants_texture_path": "res://assets/avatar/pants_template_reference.jpg", "equipped_avatar_item_payloads": [gift]}
	bob.avatar_outfit = outfit
	lobby.call("_apply_profile_snapshot_to_ui", bob, {})
	await process_frame
	check(lobby.profile_wearing_items_container.get_child_count() == 3, "wearing cards are incomplete")
	check(lobby.profile_wearing_items_container.get_child(0).find_child("HalloweenBadge", true, false) != null, "Halloween 2026 accessory badge is missing")
	check(lobby.profile_wearing_items_container.get_child(1).find_child("ProfileItemPreview", true, false) != null, "shirt card displays a raw texture instead of a model preview")
	await capture("desktop")
	var view := lobby.get_node("%MainTabs/ProfileView") as Control
	var items: GridContainer = lobby.profile_wearing_items_container
	for width in [360, 540]:
		root.size = Vector2i(width, 960)
		root.content_scale_size = root.size
		for frame in range(10): await process_frame
		check(view.get_global_rect().position.x >= -1 and view.get_global_rect().end.x <= root.size.x + 1, "phone profile extends outside the screen at %d" % width)
		check(view.get_child(0).get_combined_minimum_size().x <= view.size.x + 1, "phone profile content overflows at %d" % width)
		check(items.columns >= 1 and items.get_combined_minimum_size().x <= items.get_parent().size.x + 1, "phone wearing grid overflows at %d" % width)
	await capture("mobile")
	var creations_button := view.find_child("ProfileCreationsButton", true, false) as Button
	check(creations_button != null, "profile Creations navigation is missing")
	if creations_button != null: creations_button.emit_signal("pressed")
	for frame in range(5): await process_frame
	var creations_grid := view.find_child("ProfileCreationsGrid", true, false) as GridContainer
	check(creations_grid != null and creations_grid.get_child_count() == 3, "Creations does not show all three author maps")
	for width in [1440, 360, 540]:
		root.size = Vector2i(width, 960)
		root.content_scale_size = root.size
		for frame in range(10): await process_frame
		check(view.get_global_rect().position.x >= -1 and view.get_global_rect().end.x <= root.size.x + 1, "Creations extends outside the screen at %d" % width)
		check(view.get_child(0).get_combined_minimum_size().x <= view.size.x + 1, "Creations content overflows at %d" % width)
		if creations_grid != null:
			check(creations_grid.get_combined_minimum_size().x <= creations_grid.get_parent().size.x + 1, "Creations card grid overflows at %d" % width)
			check(creations_grid.columns == (3 if width == 1440 else 1), "Creations columns do not adapt at %d" % width)
	await capture("mobile-creations")
	print("PROFILE_UPDATE_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures}))
	lobby.free()
	# Let deferred preview/card frees and cancelled draw awaits finish before
	# closing this standalone fixture process.
	for frame in range(5): await process_frame
	quit(0 if failures.is_empty() else 1)
