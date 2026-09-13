class_name FriendsBuilder
extends RefCounted

const AVATAR_PREVIEW_CACHE_DIR: String = "user://cache/friend_avatar_previews"
const AVATAR_PREVIEW_RENDER_SIZE: int = 320
const AVATAR_PREVIEW_RENDER_SETTLE_SECONDS: float = 0.45
const AVATAR_PREVIEW_RENDER_BATCH_SIZE: int = 4
const AVATAR_PREVIEW_RENDER_REVISION: String = "portrait_v15_right_bust"

static var _avatar_preview_queue: Array = []
static var _avatar_preview_pending: Dictionary = {}
static var _avatar_preview_texture_cache: Dictionary = {}
static var _avatar_preview_worker_active: bool = false


static func _get_cloud_api() -> Variant:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	return (main_loop as SceneTree).root.get_node_or_null("CloudAPI")


static func _extract_array_payload(payload: Variant) -> Array:
	if payload is Array:
		return payload
	if payload is Dictionary:
		var payload_dict: Dictionary = payload
		if payload_dict.has("data") and payload_dict["data"] is Array:
			return payload_dict["data"]
		return [payload_dict]
	return []


static func build(lobby, force_refresh: bool = false) -> void:
	var tabs = lobby.get_node_or_null("%MainTabs")
	if not tabs:
		_finish_lobby_refresh(lobby, false)
		return

	var friends_view = tabs.get_node_or_null("FriendsView")
	if not friends_view:
		_finish_lobby_refresh(lobby, false)
		return
	var build_token: int = Time.get_ticks_msec()
	friends_view.set_meta("friends_build_token", build_token)
	friends_view.set_meta("friends_view_ready", false)
	var mobile_beta: bool = _is_mobile_lobby(lobby)
	var viewport_width: float = lobby.get_viewport_rect().size.x if lobby is Control else 960.0
	var mobile_friend_columns: int = 2 if viewport_width < 760.0 else 3

	for child in friends_view.get_children():
		child.queue_free()

	var scroll_host: ScrollContainer = friends_view as ScrollContainer
	if scroll_host == null:
		scroll_host = ScrollContainer.new()
		scroll_host.set_anchors_preset(Control.PRESET_FULL_RECT)
		friends_view.add_child(scroll_host)
	scroll_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12 if mobile_beta else 28)
	margin.add_theme_constant_override("margin_top", 10 if mobile_beta else 14)
	margin.add_theme_constant_override("margin_right", 12 if mobile_beta else 28)
	margin.add_theme_constant_override("margin_bottom", 18 if mobile_beta else 28)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_host.add_child(margin)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(0, 0)
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var title := Label.new()
	title.text = "My Friends"
	title.add_theme_font_size_override("font_size", 22 if mobile_beta else 28)
	title.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(92, 34) if mobile_beta else Vector2(110, 34)
	refresh_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	refresh_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	refresh_btn.pressed.connect(func(): _request_lobby_refresh(lobby))
	header.add_child(refresh_btn)

	var add_btn := Button.new()
	add_btn.text = "Add Friend"
	add_btn.custom_minimum_size = Vector2(108, 34) if mobile_beta else Vector2(130, 34)
	add_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
	add_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	add_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
	add_btn.add_theme_color_override("font_color", Color.WHITE)
	add_btn.pressed.connect(func(): lobby.call("_show_social_friend_search_popup", add_btn))
	header.add_child(add_btn)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 0)
	root.add_child(tab_bar)

	var content_title := Label.new()
	content_title.add_theme_font_size_override("font_size", 22)
	content_title.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
	root.add_child(content_title)

	var content := GridContainer.new()
	content.columns = mobile_friend_columns if mobile_beta else 4
	content.add_theme_constant_override("separation", 10)
	content.add_theme_constant_override("h_separation", 14)
	content.add_theme_constant_override("v_separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	var state: Dictionary = {
		"active_tab": "Friends",
		"friends": [],
		"following": [],
		"followers": [],
		"incoming": [],
		"outgoing": [],
		"active_lookup": {},
		"loaded_tabs": {
			"Friends": false,
			"Following": false,
			"Followers": false,
			"Requests": false
		},
		"loading_tabs": {}
	}
	if not force_refresh and bool(lobby.get("_home_friends_cache_loaded")):
		var cached_friends_variant: Variant = lobby.get("_home_friends_cache")
		var cached_lookup_variant: Variant = lobby.get("_home_friends_active_lookup_cache")
		if cached_friends_variant is Array:
			state["friends"] = (cached_friends_variant as Array).duplicate(true)
			(state["loaded_tabs"] as Dictionary)["Friends"] = true
		if cached_lookup_variant is Dictionary:
			state["active_lookup"] = (cached_lookup_variant as Dictionary).duplicate(true)
	var tab_buttons: Dictionary = {}
	var render_tabs := func() -> void:
		for tab_name in tab_buttons.keys():
			var tab_button: Button = tab_buttons[tab_name] as Button
			if tab_button == null:
				continue
			tab_button.add_theme_stylebox_override("normal", _make_tab_style(str(tab_name) == str(state.get("active_tab", "Friends"))))
			tab_button.add_theme_stylebox_override("hover", _make_tab_style(true))
		_clear_children(content)
		var active_tab: String = str(state.get("active_tab", "Friends"))
		var friends: Array = state.get("friends", []) if state.get("friends", []) is Array else []
		var following: Array = state.get("following", []) if state.get("following", []) is Array else []
		var followers: Array = state.get("followers", []) if state.get("followers", []) is Array else []
		var incoming: Array = state.get("incoming", []) if state.get("incoming", []) is Array else []
		var outgoing: Array = state.get("outgoing", []) if state.get("outgoing", []) is Array else []
		var active_lookup: Dictionary = state.get("active_lookup", {}) if state.get("active_lookup", {}) is Dictionary else {}
		var loaded_tabs: Dictionary = state.get("loaded_tabs", {}) if state.get("loaded_tabs", {}) is Dictionary else {}
		if not bool(loaded_tabs.get(active_tab, false)):
			content_title.text = "%s" % active_tab
			_add_results_bar(content, "Loading...")
			return
		match active_tab:
			"Friends":
				content.columns = mobile_friend_columns if mobile_beta else 5
				content_title.text = "Friends (%d)" % friends.size()
				if friends.is_empty():
					_add_results_bar(content, "No Results Found")
				else:
					var friend_render_index := 0
					for friend_variant in friends:
						if friend_variant is Dictionary:
							var friend_profile: Dictionary = friend_variant as Dictionary
							content.add_child(_create_friend_tile(lobby, friend_profile, _resolve_active_server_for_profile(friend_profile, active_lookup), friend_render_index))
							friend_render_index += 1
			"Following":
				content.columns = 1 if mobile_beta else 2
				content_title.text = "Following (%d)" % following.size()
				if following.is_empty():
					_add_results_bar(content, "No Results Found")
				else:
					for profile_variant in following:
						if profile_variant is Dictionary:
							var following_profile: Dictionary = profile_variant as Dictionary
							content.add_child(_create_follow_card(lobby, following_profile, _resolve_active_server_for_profile(following_profile, active_lookup), true))
			"Followers":
				content.columns = 1 if mobile_beta else 2
				content_title.text = "Followers (%d)" % followers.size()
				if followers.is_empty():
					_add_results_bar(content, "No Results Found")
				else:
					for profile_variant in followers:
						if profile_variant is Dictionary:
							var follower_profile: Dictionary = profile_variant as Dictionary
							content.add_child(_create_follow_card(lobby, follower_profile, _resolve_active_server_for_profile(follower_profile, active_lookup), false))
			"Requests":
				content.columns = 1 if mobile_beta else 2
				content_title.text = "Requests (%d)" % incoming.size()
				if incoming.is_empty() and outgoing.is_empty():
					_add_results_bar(content, "No Results Found")
				else:
					for request_variant in incoming:
						if request_variant is Dictionary:
							var request_row: Dictionary = request_variant as Dictionary
							var sender_profile: Dictionary = request_row.get("sender_profile", {}) if request_row.get("sender_profile", {}) is Dictionary else {}
							content.add_child(_create_request_card(lobby, sender_profile, request_row))
					for request_variant in outgoing:
						if request_variant is Dictionary:
							var outgoing_row: Dictionary = request_variant as Dictionary
							var target_profile: Dictionary = outgoing_row.get("target_profile", {}) if outgoing_row.get("target_profile", {}) is Dictionary else {}
							content.add_child(_create_outgoing_request_card(lobby, target_profile))

	for tab_name in ["Friends", "Following", "Followers", "Requests"]:
		var tab_button := Button.new()
		tab_button.text = tab_name
		tab_button.custom_minimum_size = Vector2(0, 44)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.add_theme_font_size_override("font_size", 15)
		tab_button.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
		tab_button.set_meta("social_tab_name", tab_name)
		tab_button.pressed.connect(func():
			state["active_tab"] = str(tab_button.get_meta("social_tab_name", "Friends"))
			render_tabs.call()
			_load_selected_tab_async(lobby, friends_view, build_token, state, render_tabs)
		)
		tab_buttons[tab_name] = tab_button
		tab_bar.add_child(tab_button)

	render_tabs.call()
	_populate_tabbed_async(lobby, friends_view, build_token, state, render_tabs)

static func _is_mobile_lobby(lobby) -> bool:
	if lobby == null or not is_instance_valid(lobby):
		return false
	if lobby.has_method("_is_mobile_beta"):
		return bool(lobby.call("_is_mobile_beta"))
	var mobile_runtime: Node = lobby.get_node_or_null("/root/MobileRuntime")
	return mobile_runtime != null and mobile_runtime.has_method("is_mobile_beta") and bool(mobile_runtime.call("is_mobile_beta"))


static func _populate_tabbed_async(lobby, friends_view: Control, build_token: int, state: Dictionary, render_tabs: Callable) -> void:
	var cloud_api: Variant = _get_cloud_api()
	if cloud_api == null or not cloud_api.has_method("is_configured") or not bool(cloud_api.call("is_configured")):
		(state["loaded_tabs"] as Dictionary)["Friends"] = true
		render_tabs.call()
		friends_view.set_meta("friends_view_ready", true)
		_finish_lobby_refresh(lobby, false)
		return

	var loaded_tabs: Dictionary = state.get("loaded_tabs", {}) if state.get("loaded_tabs", {}) is Dictionary else {}
	var friends_result: Dictionary = {"ok": true, "data": state.get("friends", [])}
	if not bool(loaded_tabs.get("Friends", false)):
		friends_result = await cloud_api.call("get_friends_list")
	var active_servers_result: Dictionary = await cloud_api.call("fetch_active_servers", "", 24, 3.0, 1)
	if not is_instance_valid(lobby) or not is_instance_valid(friends_view):
		_finish_lobby_refresh(lobby, false)
		return
	if int(friends_view.get_meta("friends_build_token", -1)) != build_token:
		_finish_lobby_refresh(lobby, false)
		return
	var active_servers: Array = _extract_array_payload(active_servers_result.get("data", [])) if bool(active_servers_result.get("ok", false)) else []
	var active_lookup: Dictionary = _build_member_server_lookup(active_servers)
	var friends: Array = _extract_array_payload(friends_result.get("data", [])) if bool(friends_result.get("ok", false)) else []
	friends.sort_custom(func(a: Dictionary, b: Dictionary):
		var rank_a: int = _profile_presence_rank(a, active_lookup)
		var rank_b: int = _profile_presence_rank(b, active_lookup)
		if rank_a == rank_b:
			return str(a.get("username", "")).to_lower() < str(b.get("username", "")).to_lower()
		return rank_a < rank_b
	)
	state["friends"] = friends
	state["active_lookup"] = active_lookup
	loaded_tabs["Friends"] = true
	state["loaded_tabs"] = loaded_tabs
	lobby.set("_home_friends_cache", friends.duplicate(true))
	lobby.set("_home_friends_active_lookup_cache", active_lookup.duplicate(true))
	lobby.set("_home_friends_cache_loaded", true)
	render_tabs.call()
	friends_view.set_meta("friends_view_ready", true)
	_finish_lobby_refresh(lobby, bool(friends_result.get("ok", false)))


static func _load_selected_tab_async(lobby, friends_view: Control, build_token: int, state: Dictionary, render_tabs: Callable) -> void:
	if not is_instance_valid(lobby) or not is_instance_valid(friends_view):
		return
	var cloud_api: Variant = _get_cloud_api()
	if cloud_api == null:
		return
	var active_tab: String = str(state.get("active_tab", "Friends"))
	var loaded_tabs: Dictionary = state.get("loaded_tabs", {}) if state.get("loaded_tabs", {}) is Dictionary else {}
	var loading_tabs: Dictionary = state.get("loading_tabs", {}) if state.get("loading_tabs", {}) is Dictionary else {}
	if bool(loaded_tabs.get(active_tab, false)) or bool(loading_tabs.get(active_tab, false)):
		return
	loading_tabs[active_tab] = true
	state["loading_tabs"] = loading_tabs

	match active_tab:
		"Following":
			var following_result: Dictionary = {"ok": false, "data": []}
			if cloud_api.has_method("get_following_list"):
				following_result = await cloud_api.call("get_following_list")
			state["following"] = _extract_array_payload(following_result.get("data", [])) if bool(following_result.get("ok", false)) else []
		"Followers":
			var followers_result: Dictionary = {"ok": false, "data": []}
			if cloud_api.has_method("get_followers_list"):
				followers_result = await cloud_api.call("get_followers_list")
			state["followers"] = _extract_array_payload(followers_result.get("data", [])) if bool(followers_result.get("ok", false)) else []
		"Requests":
			var incoming_result: Dictionary = await cloud_api.call("get_incoming_friend_requests")
			var outgoing_result: Dictionary = await cloud_api.call("get_outgoing_friend_requests")
			state["incoming"] = _extract_array_payload(incoming_result.get("data", [])) if bool(incoming_result.get("ok", false)) else []
			state["outgoing"] = _extract_array_payload(outgoing_result.get("data", [])) if bool(outgoing_result.get("ok", false)) else []
		_:
			return

	if not is_instance_valid(lobby) or not is_instance_valid(friends_view):
		return
	if int(friends_view.get_meta("friends_build_token", -1)) != build_token:
		return
	loaded_tabs = state.get("loaded_tabs", {}) if state.get("loaded_tabs", {}) is Dictionary else {}
	loading_tabs = state.get("loading_tabs", {}) if state.get("loading_tabs", {}) is Dictionary else {}
	loaded_tabs[active_tab] = true
	loading_tabs.erase(active_tab)
	state["loaded_tabs"] = loaded_tabs
	state["loading_tabs"] = loading_tabs
	if str(state.get("active_tab", "")) == active_tab:
		render_tabs.call()


static func _request_lobby_refresh(lobby) -> void:
	if lobby != null and is_instance_valid(lobby) and lobby.has_method("_refresh_friends_view"):
		lobby.call("_refresh_friends_view", true)
	else:
		build(lobby, true)


static func _finish_lobby_refresh(lobby, success: bool) -> void:
	if lobby != null and is_instance_valid(lobby) and lobby.has_method("_on_friends_view_refresh_finished"):
		lobby.call_deferred("_on_friends_view_refresh_finished", success)


static func _populate_async(lobby, friends_view: Control, build_token: int, summary_label: Label, requests_parts: Dictionary, friends_parts: Dictionary, outgoing_parts: Dictionary) -> void:
	var requests_status: Label = requests_parts.get("status_label", null)
	var requests_container: VBoxContainer = requests_parts.get("content", null)
	var friends_status: Label = friends_parts.get("status_label", null)
	var friends_container: VBoxContainer = friends_parts.get("content", null)
	var outgoing_status: Label = outgoing_parts.get("status_label", null)
	var outgoing_container: VBoxContainer = outgoing_parts.get("content", null)
	if requests_status:
		requests_status.text = "Loading requests..."
	if friends_status:
		friends_status.text = "Loading friends..."
	if outgoing_status:
		outgoing_status.text = "Loading pending requests..."
	if summary_label:
		summary_label.text = "Syncing social data..."

	var cloud_api: Variant = _get_cloud_api()
	if cloud_api == null or not cloud_api.has_method("is_configured") or not bool(cloud_api.call("is_configured")):
		if summary_label:
			summary_label.text = "Cloud social is disconnected."
		if requests_status:
			requests_status.text = "Cloud social is disconnected."
		if friends_status:
			friends_status.text = "Cloud social is disconnected."
		if outgoing_status:
			outgoing_status.text = "Cloud social is disconnected."
		return

	var friends_result: Dictionary = await cloud_api.call("get_friends_list")
	var incoming_result: Dictionary = await cloud_api.call("get_incoming_friend_requests")
	var outgoing_result: Dictionary = await cloud_api.call("get_outgoing_friend_requests")
	var active_servers_result: Dictionary = await cloud_api.call("fetch_active_servers", "", 24, 3.0, 1)

	if not is_instance_valid(lobby) or not is_instance_valid(friends_view):
		return
	if int(friends_view.get_meta("friends_build_token", -1)) != build_token:
		return
	if requests_container == null or friends_container == null or outgoing_container == null:
		return

	var active_servers: Array = _extract_array_payload(active_servers_result.get("data", [])) if bool(active_servers_result.get("ok", false)) else []
	var active_server_lookup: Dictionary = _build_member_server_lookup(active_servers)

	var friends: Array = _extract_array_payload(friends_result.get("data", [])) if bool(friends_result.get("ok", false)) else []
	var incoming_requests: Array = _extract_array_payload(incoming_result.get("data", [])) if bool(incoming_result.get("ok", false)) else []
	var outgoing_requests: Array = _extract_array_payload(outgoing_result.get("data", [])) if bool(outgoing_result.get("ok", false)) else []
	var friends_load_error := "" if bool(friends_result.get("ok", false)) else str(friends_result.get("error", "Could not load friends."))
	var incoming_load_error := "" if bool(incoming_result.get("ok", false)) else str(incoming_result.get("error", "Could not load incoming requests."))
	var outgoing_load_error := "" if bool(outgoing_result.get("ok", false)) else str(outgoing_result.get("error", "Could not load pending requests."))

	_clear_children(requests_container)
	_clear_children(friends_container)
	_clear_children(outgoing_container)

	var active_friends_count: int = 0
	for friend_variant in friends:
		if not (friend_variant is Dictionary):
			continue
		var friend_profile: Dictionary = (friend_variant as Dictionary).duplicate(true)
		var active_server: Dictionary = _resolve_active_server_for_profile(friend_profile, active_server_lookup)
		if not active_server.is_empty():
			active_friends_count += 1
	for request_variant in incoming_requests:
		if not (request_variant is Dictionary):
			continue
		var request_row: Dictionary = (request_variant as Dictionary).duplicate(true)
		var sender_profile: Dictionary = request_row.get("sender_profile", {}) if request_row.get("sender_profile", {}) is Dictionary else {}
		requests_container.add_child(_create_request_card(lobby, sender_profile, request_row))

	if not incoming_load_error.is_empty():
		_add_placeholder(requests_container, incoming_load_error)
	elif incoming_requests.is_empty():
		_add_placeholder(requests_container, "No incoming requests right now.")
	if requests_status:
		requests_status.text = incoming_load_error if not incoming_load_error.is_empty() else "%d incoming request(s)" % incoming_requests.size()

	friends.sort_custom(func(a: Dictionary, b: Dictionary):
		var rank_a: int = _profile_presence_rank(a, active_server_lookup)
		var rank_b: int = _profile_presence_rank(b, active_server_lookup)
		if rank_a == rank_b:
			return str(a.get("username", "")).to_lower() < str(b.get("username", "")).to_lower()
		return rank_a < rank_b
	)
	for friend_variant in friends:
		if not (friend_variant is Dictionary):
			continue
		var friend_profile: Dictionary = (friend_variant as Dictionary).duplicate(true)
		var active_server: Dictionary = _resolve_active_server_for_profile(friend_profile, active_server_lookup)
		friends_container.add_child(_create_friend_card(lobby, friend_profile, active_server))

	if not friends_load_error.is_empty():
		_add_placeholder(friends_container, friends_load_error)
	elif friends.is_empty():
		_add_placeholder(friends_container, "No friends yet. Use Add Friend to search for players.")
	if friends_status:
		friends_status.text = friends_load_error if not friends_load_error.is_empty() else "%d friend(s), %d playing right now" % [friends.size(), active_friends_count]

	for request_variant in outgoing_requests:
		if not (request_variant is Dictionary):
			continue
		var request_row: Dictionary = (request_variant as Dictionary).duplicate(true)
		var target_profile: Dictionary = request_row.get("target_profile", {}) if request_row.get("target_profile", {}) is Dictionary else {}
		outgoing_container.add_child(_create_outgoing_request_card(lobby, target_profile))

	if not outgoing_load_error.is_empty():
		_add_placeholder(outgoing_container, outgoing_load_error)
	elif outgoing_requests.is_empty():
		_add_placeholder(outgoing_container, "No pending requests.")
	if outgoing_status:
		outgoing_status.text = outgoing_load_error if not outgoing_load_error.is_empty() else "%d pending request(s)" % outgoing_requests.size()

	if summary_label:
		if not friends_load_error.is_empty() or not incoming_load_error.is_empty() or not outgoing_load_error.is_empty():
			summary_label.text = "Some social data could not load. Please refresh."
		else:
			summary_label.text = "%d friends, %d live, %d incoming requests" % [friends.size(), active_friends_count, incoming_requests.size()]


static func _create_section(parent: VBoxContainer, title_text: String, subtitle_text: String, min_height: float) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, min_height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var status_label := Label.new()
	status_label.text = "Loading..."
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.48, 0.49, 0.53, 1))
	root.add_child(status_label)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	return {
		"panel": panel,
		"status_label": status_label,
		"content": content
	}


static func _create_friend_card(lobby, profile: Dictionary, active_server: Dictionary) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 158 if not active_server.is_empty() else 112)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_subpanel_style())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var avatar := _create_round_avatar_preview(profile, 72, 0.0, lobby)
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	_set_mouse_pass_recursive(avatar)
	var press_pos := Vector2.ZERO
	avatar.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
			else:
				if press_pos.distance_to(event.position) < 15.0:
					var mobile_runtime = lobby.get_node_or_null("/root/MobileRuntime")
					if mobile_runtime == null or not mobile_runtime.get("_ui_scroll_dragged"):
						lobby.call("_show_home_friend_popup", avatar, profile, active_server)
	)
	root.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	root.add_child(info)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	info.add_child(top_row)

	var username_btn := Button.new()
	username_btn.flat = true
	username_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	username_btn.text = str(profile.get("username", "Unknown")).strip_edges()
	username_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_btn.clip_text = true
	username_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	username_btn.add_theme_font_size_override("font_size", 16)
	username_btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	username_btn.pressed.connect(func():
		lobby.call("_show_home_friend_popup", username_btn, profile, active_server)
	)
	top_row.add_child(username_btn)

	var status_chip := Label.new()
	var status_text: String = str(lobby.call("_get_profile_status_text", profile, active_server))
	status_chip.text = status_text
	status_chip.add_theme_font_size_override("font_size", 11)
	status_chip.add_theme_color_override("font_color", Color(0.09, 0.54, 0.24, 1) if not active_server.is_empty() else Color(0.48, 0.49, 0.53, 1))
	status_chip.add_theme_stylebox_override("normal", _make_status_chip_style(not active_server.is_empty()))
	top_row.add_child(status_chip)

	if not active_server.is_empty():
		var game_info := _game_info_from_server(active_server)
		var game_row := HBoxContainer.new()
		game_row.add_theme_constant_override("separation", 10)
		info.add_child(game_row)

		var icon: Control = lobby.call("_create_game_icon_widget", game_info)
		icon.custom_minimum_size = Vector2(100, 60)
		game_row.add_child(icon)

		var game_meta := VBoxContainer.new()
		game_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_meta.add_theme_constant_override("separation", 4)
		game_row.add_child(game_meta)

		var game_name := Label.new()
		game_name.text = str(game_info.get("name", "Friend's Game"))
		game_name.add_theme_font_size_override("font_size", 14)
		game_name.add_theme_color_override("font_color", Color(0.16, 0.17, 0.2, 1))
		game_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game_meta.add_child(game_name)

		var game_presence := Label.new()
		game_presence.text = "%d/%d players online" % [int(active_server.get("players_count", 0)), int(active_server.get("max_players", 10))]
		game_presence.add_theme_font_size_override("font_size", 11)
		game_presence.add_theme_color_override("font_color", Color(0.47, 0.48, 0.52, 1))
		game_meta.add_child(game_presence)
	else:
		var offline_hint := Label.new()
		offline_hint.text = "Open profile or wait until this friend joins a live experience."
		offline_hint.add_theme_font_size_override("font_size", 11)
		offline_hint.add_theme_color_override("font_color", Color(0.47, 0.48, 0.52, 1))
		offline_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(offline_hint)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(120, 0)
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	if not active_server.is_empty():
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(0, 34)
		join_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)))
		join_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
		join_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)))
		join_btn.add_theme_color_override("font_color", Color.WHITE)
		join_btn.pressed.connect(func():
			lobby.call("_join_server_flow", _game_info_from_server(active_server), active_server)
		)
		actions.add_child(join_btn)

	var profile_btn := Button.new()
	profile_btn.text = "Profile"
	profile_btn.custom_minimum_size = Vector2(0, 34)
	profile_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	profile_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	profile_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(profile.get("id", "")).strip_edges(), str(profile.get("username", "")).strip_edges(), profile, active_server)
	)
	actions.add_child(profile_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.custom_minimum_size = Vector2(0, 34)
	remove_btn.add_theme_stylebox_override("normal", _make_danger_button_style(false))
	remove_btn.add_theme_stylebox_override("hover", _make_danger_button_style(true))
	remove_btn.pressed.connect(func():
		var cloud_api: Variant = _get_cloud_api()
		if cloud_api == null or not cloud_api.has_method("remove_friend"):
			return
		await cloud_api.call("remove_friend", str(profile.get("id", "")).strip_edges())
		_request_lobby_refresh(lobby)
	)
	actions.add_child(remove_btn)

	return panel


static func _create_friend_tile(lobby, profile: Dictionary, active_server: Dictionary, render_index: int = 0) -> Panel:
	var panel := Panel.new()
	var mobile_beta: bool = _is_mobile_lobby(lobby)
	panel.custom_minimum_size = Vector2(150, 184) if mobile_beta else Vector2(164, 194)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _make_friend_tile_style())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)

	var avatar_delay: float = minf(1.6, maxf(0.08, float(render_index) * 0.07))
	var avatar := _create_round_avatar_preview(profile, 98 if mobile_beta else 112, avatar_delay, lobby)
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	_set_mouse_pass_recursive(avatar)
	root.add_child(avatar)

	var username_btn := Button.new()
	username_btn.flat = true
	username_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	username_btn.text = str(profile.get("username", "Unknown")).strip_edges()
	username_btn.custom_minimum_size = Vector2(0, 26)
	username_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_btn.clip_text = true
	username_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	username_btn.add_theme_font_size_override("font_size", 15)
	username_btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	username_btn.pressed.connect(func():
		lobby.call("_show_home_friend_popup", username_btn, profile, active_server)
	)
	root.add_child(username_btn)

	var status_chip := Label.new()
	status_chip.text = str(lobby.call("_get_profile_status_text", profile, active_server))
	status_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.custom_minimum_size = Vector2(0, 24)
	status_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_chip.clip_text = true
	status_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_chip.add_theme_font_size_override("font_size", 11)
	status_chip.add_theme_color_override("font_color", Color(0.09, 0.54, 0.24, 1) if not active_server.is_empty() else Color(0.48, 0.49, 0.53, 1))
	status_chip.add_theme_stylebox_override("normal", _make_status_chip_style(not active_server.is_empty()))
	root.add_child(status_chip)

	var press_pos := Vector2.ZERO
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
			else:
				if press_pos.distance_to(event.position) < 15.0:
					var mobile_runtime = lobby.get_node_or_null("/root/MobileRuntime")
					if mobile_runtime == null or not mobile_runtime.get("_ui_scroll_dragged"):
						lobby.call("_show_home_friend_popup", panel, profile, active_server)
	)
	return panel


static func _create_follow_card(lobby, profile: Dictionary, active_server: Dictionary, is_following_tab: bool) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 104)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_subpanel_style())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var avatar := _create_round_avatar_preview(profile, 64, 0.0, lobby)
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	_set_mouse_pass_recursive(avatar)
	var press_pos := Vector2.ZERO
	avatar.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
			else:
				if press_pos.distance_to(event.position) < 15.0:
					var mobile_runtime = lobby.get_node_or_null("/root/MobileRuntime")
					if mobile_runtime == null or not mobile_runtime.get("_ui_scroll_dragged"):
						lobby.call("_show_home_friend_popup", avatar, profile, active_server)
	)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)

	var username_btn := Button.new()
	username_btn.flat = true
	username_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	username_btn.text = str(profile.get("username", "Unknown")).strip_edges()
	username_btn.clip_text = true
	username_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	username_btn.add_theme_font_size_override("font_size", 16)
	username_btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	username_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(profile.get("id", "")).strip_edges(), str(profile.get("username", "")).strip_edges(), profile, active_server)
	)
	info.add_child(username_btn)
	preload("res://scripts/lobby/account_badges.gd").attach(username_btn, profile)

	var status := Label.new()
	status.text = str(lobby.call("_get_profile_status_text", profile, active_server))
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.09, 0.54, 0.24, 1) if not active_server.is_empty() else Color(0.48, 0.49, 0.53, 1))
	info.add_child(status)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(120, 0)
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	var profile_btn := Button.new()
	profile_btn.text = "Profile"
	profile_btn.custom_minimum_size = Vector2(0, 34)
	profile_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	profile_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	profile_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(profile.get("id", "")).strip_edges(), str(profile.get("username", "")).strip_edges(), profile, active_server)
	)
	actions.add_child(profile_btn)

	var follow_btn := Button.new()
	follow_btn.text = "Unfollow" if is_following_tab else "Follow"
	follow_btn.custom_minimum_size = Vector2(0, 34)
	follow_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.12, 0.6, 0.88, 1.0)) if not is_following_tab else _make_secondary_button_style())
	follow_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.16, 0.68, 0.96, 1.0)) if not is_following_tab else _make_secondary_hover_style())
	follow_btn.add_theme_color_override("font_color", Color.WHITE if not is_following_tab else Color(0.18, 0.19, 0.22, 1))
	follow_btn.pressed.connect(func():
		var target_id: String = str(profile.get("id", "")).strip_edges()
		if target_id.is_empty():
			return
		var cloud_api: Variant = _get_cloud_api()
		if cloud_api == null:
			return
		if is_following_tab and cloud_api.has_method("unfollow_user"):
			await cloud_api.call("unfollow_user", target_id)
		elif cloud_api.has_method("follow_user"):
			await cloud_api.call("follow_user", target_id)
		_request_lobby_refresh(lobby)
	)
	actions.add_child(follow_btn)

	return panel


static func _create_request_card(lobby, sender_profile: Dictionary, request_row: Dictionary) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 108)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_subpanel_style())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var avatar := _create_round_avatar_preview(sender_profile, 64, 0.0, lobby)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)

	var username_btn := Button.new()
	username_btn.flat = true
	username_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	username_btn.text = str(sender_profile.get("username", "Unknown")).strip_edges()
	username_btn.add_theme_font_size_override("font_size", 16)
	username_btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	username_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(sender_profile.get("id", "")).strip_edges(), str(sender_profile.get("username", "")).strip_edges(), sender_profile, {})
	)
	info.add_child(username_btn)

	var hint := Label.new()
	hint.text = "Wants to add you as a friend."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.47, 0.48, 0.52, 1))
	info.add_child(hint)

	var created_at: String = str(request_row.get("created_at", "")).strip_edges()
	if not created_at.is_empty():
		var created_lbl := Label.new()
		created_lbl.text = "Requested %s" % created_at.substr(0, 10)
		created_lbl.add_theme_font_size_override("font_size", 11)
		created_lbl.add_theme_color_override("font_color", Color(0.57, 0.58, 0.61, 1))
		info.add_child(created_lbl)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(120, 0)
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(0, 34)
	accept_btn.add_theme_stylebox_override("normal", _make_primary_button_style(Color(0.18, 0.67, 0.33, 1.0)))
	accept_btn.add_theme_stylebox_override("hover", _make_primary_button_style(Color(0.22, 0.74, 0.37, 1.0)))
	accept_btn.add_theme_stylebox_override("pressed", _make_primary_button_style(Color(0.22, 0.74, 0.37, 1.0)))
	accept_btn.add_theme_color_override("font_color", Color.WHITE)
	accept_btn.pressed.connect(func():
		var cloud_api: Variant = _get_cloud_api()
		if cloud_api == null or not cloud_api.has_method("accept_friend_request"):
			return
		await cloud_api.call("accept_friend_request", str(request_row.get("from_user", "")).strip_edges())
		_request_lobby_refresh(lobby)
	)
	actions.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(0, 34)
	decline_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	decline_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	decline_btn.pressed.connect(func():
		var cloud_api: Variant = _get_cloud_api()
		if cloud_api == null or not cloud_api.has_method("decline_friend_request"):
			return
		await cloud_api.call("decline_friend_request", str(request_row.get("from_user", "")).strip_edges())
		_request_lobby_refresh(lobby)
	)
	actions.add_child(decline_btn)

	return panel


static func _create_outgoing_request_card(lobby, target_profile: Dictionary) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 96)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _make_subpanel_style())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	row.add_child(_create_round_avatar_preview(target_profile, 56, 0.0, lobby))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var username_btn := Button.new()
	username_btn.flat = true
	username_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	username_btn.text = str(target_profile.get("username", "Unknown")).strip_edges()
	username_btn.add_theme_font_size_override("font_size", 15)
	username_btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16, 1))
	username_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(target_profile.get("id", "")).strip_edges(), str(target_profile.get("username", "")).strip_edges(), target_profile, {})
	)
	info.add_child(username_btn)

	var hint := Label.new()
	hint.text = "Friend request pending."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.47, 0.48, 0.52, 1))
	info.add_child(hint)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(120, 0)
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	var profile_btn := Button.new()
	profile_btn.text = "Profile"
	profile_btn.custom_minimum_size = Vector2(0, 34)
	profile_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	profile_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	profile_btn.pressed.connect(func():
		lobby.call("_open_profile_for_user", str(target_profile.get("id", "")).strip_edges(), str(target_profile.get("username", "")).strip_edges(), target_profile, {})
	)
	actions.add_child(profile_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 34)
	cancel_btn.add_theme_stylebox_override("normal", _make_secondary_button_style())
	cancel_btn.add_theme_stylebox_override("hover", _make_secondary_hover_style())
	cancel_btn.pressed.connect(func():
		var cloud_api: Variant = _get_cloud_api()
		if cloud_api == null or not cloud_api.has_method("cancel_friend_request"):
			return
		await cloud_api.call("cancel_friend_request", str(target_profile.get("id", "")).strip_edges())
		_request_lobby_refresh(lobby)
	)
	actions.add_child(cancel_btn)

	return panel


static func _build_member_server_lookup(active_servers: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for server_variant in active_servers:
		if not (server_variant is Dictionary):
			continue
		var server: Dictionary = server_variant
		var last_seen: int = int(server.get("last_seen", 0))
		var member_user_ids: Array = server.get("member_user_ids", []) if server.get("member_user_ids", []) is Array else []
		for user_id_variant in member_user_ids:
			var user_id: String = str(user_id_variant).strip_edges()
			if user_id.is_empty():
				continue
			var existing: Dictionary = lookup.get(user_id, {}) if lookup.get(user_id, {}) is Dictionary else {}
			if existing.is_empty() or last_seen >= int(existing.get("last_seen", 0)):
				lookup[user_id] = server
		var host_user_id: String = str(server.get("host_user_id", "")).strip_edges()
		if not host_user_id.is_empty():
			var existing_by_host: Dictionary = lookup.get(host_user_id, {}) if lookup.get(host_user_id, {}) is Dictionary else {}
			if existing_by_host.is_empty() or last_seen >= int(existing_by_host.get("last_seen", 0)):
				lookup[host_user_id] = server
	return lookup


static func _resolve_active_server_for_profile(profile: Dictionary, active_server_lookup: Dictionary) -> Dictionary:
	var user_id: String = str(profile.get("id", "")).strip_edges()
	var server_match: Variant = active_server_lookup.get(user_id, {})
	return server_match if server_match is Dictionary else {}


static func _profile_presence_rank(profile: Dictionary, active_server_lookup: Dictionary) -> int:
	if not _resolve_active_server_for_profile(profile, active_server_lookup).is_empty():
		return 0
	if str(profile.get("status", "")).strip_edges().to_lower() != "online":
		return 2
	var updated_at: String = str(profile.get("updated_at", profile.get("last_seen_at", ""))).strip_edges()
	if updated_at.is_empty():
		return 2
	var updated_unix: int = int(Time.get_unix_time_from_datetime_string(updated_at))
	if updated_unix <= 0:
		return 2
	return 1 if Time.get_unix_time_from_system() - updated_unix <= 180.0 else 2


static func _game_info_from_server(server: Dictionary) -> Dictionary:
	return {
		"name": str(server.get("map_name", "Friend's Game")).strip_edges(),
		"map_id": str(server.get("map_id", "")).strip_edges(),
		"cloud_version_id": str(server.get("cloud_version_id", "")).strip_edges(),
		"icon_path": "",
		"thumbnail": "",
		"folder": ""
	}


static func _create_round_avatar_preview(profile: Dictionary, size_px: int = 36, delay_seconds: float = 0.0, render_host: Node = null) -> Control:
	var holder := _create_avatar_preview_holder(size_px)
	_install_initials_avatar_label(holder, profile, size_px)
	_queue_avatar_preview(holder, profile, size_px, delay_seconds, render_host)
	return holder


static func _create_lightweight_avatar_badge(profile: Dictionary, size_px: int = 36) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.clip_contents = true
	holder.add_theme_stylebox_override("panel", _make_avatar_circle_style(size_px))
	_install_initials_avatar_label(holder, profile, size_px)
	return holder


static func _create_avatar_preview_holder(size_px: int) -> Panel:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_theme_stylebox_override("panel", _make_avatar_circle_style(size_px))
	return holder


static func _install_initials_avatar_label(holder: Control, profile: Dictionary, size_px: int) -> void:
	for child in holder.get_children():
		child.queue_free()
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = _profile_initials(profile)
	label.add_theme_font_size_override("font_size", maxi(12, int(size_px * 0.36)))
	label.add_theme_color_override("font_color", Color.WHITE)
	holder.add_child(label)


static func _queue_avatar_preview(holder: Control, profile: Dictionary, size_px: int, delay_seconds: float, render_host: Node) -> void:
	var cache_key := _avatar_preview_cache_key(profile)
	var memory_texture: Variant = _avatar_preview_texture_cache.get(cache_key)
	if memory_texture is Texture2D:
		_install_avatar_texture(holder, memory_texture as Texture2D)
		return

	var disk_texture := _load_avatar_preview_texture(cache_key)
	if disk_texture != null:
		_avatar_preview_texture_cache[cache_key] = disk_texture
		_install_avatar_texture(holder, disk_texture)
		return

	var waiter := {
		"holder": weakref(holder),
		"size_px": size_px
	}
	if _avatar_preview_pending.has(cache_key):
		var existing_waiters: Array = _avatar_preview_pending.get(cache_key, [])
		existing_waiters.append(waiter)
		_avatar_preview_pending[cache_key] = existing_waiters
		return

	_avatar_preview_pending[cache_key] = [waiter]
	var effective_host: Node = render_host if render_host != null else holder
	_avatar_preview_queue.append({
		"cache_key": cache_key,
		"profile": profile.duplicate(true),
		"host": weakref(effective_host),
		"delay_seconds": clampf(delay_seconds, 0.0, 0.12)
	})
	_run_avatar_preview_queue()


static func _run_avatar_preview_queue() -> void:
	if _avatar_preview_worker_active:
		return
	_avatar_preview_worker_active = true
	while not _avatar_preview_queue.is_empty():
		var batch: Array[Dictionary] = []
		var batch_tree: SceneTree = null
		var maximum_delay: float = 0.0
		while batch.size() < AVATAR_PREVIEW_RENDER_BATCH_SIZE and not _avatar_preview_queue.is_empty():
			var job_variant: Variant = _avatar_preview_queue.pop_front()
			if not (job_variant is Dictionary):
				continue
			var job: Dictionary = job_variant
			var cache_key: String = str(job.get("cache_key", "")).strip_edges()
			var host_ref: WeakRef = job.get("host") as WeakRef
			var host: Node = host_ref.get_ref() as Node if host_ref != null else null
			if host == null or not is_instance_valid(host) or not host.is_inside_tree():
				_avatar_preview_pending.erase(cache_key)
				continue
			var profile: Dictionary = job.get("profile", {}) if job.get("profile", {}) is Dictionary else {}
			var viewport := _create_avatar_render_viewport(host, profile)
			if viewport == null:
				_finish_avatar_preview_job(cache_key, null, profile)
				continue
			batch_tree = host.get_tree()
			maximum_delay = maxf(maximum_delay, float(job.get("delay_seconds", 0.0)))
			batch.append({
				"cache_key": cache_key,
				"profile": profile,
				"viewport": viewport
			})

		if batch.is_empty() or batch_tree == null:
			continue
		if DisplayServer.get_name() == "headless":
			for batch_job in batch:
				var headless_viewport: SubViewport = batch_job.get("viewport") as SubViewport
				if headless_viewport != null:
					headless_viewport.queue_free()
				_finish_avatar_preview_job(str(batch_job.get("cache_key", "")), null, batch_job.get("profile", {}))
			await batch_tree.process_frame
			continue
		if maximum_delay > 0.0:
			await batch_tree.create_timer(maximum_delay).timeout
		for _frame_index in range(3):
			await batch_tree.process_frame
		await batch_tree.create_timer(AVATAR_PREVIEW_RENDER_SETTLE_SECONDS).timeout
		for _frame_index in range(2):
			await batch_tree.process_frame

		for batch_job in batch:
			var cache_key: String = str(batch_job.get("cache_key", ""))
			var profile: Dictionary = batch_job.get("profile", {}) if batch_job.get("profile", {}) is Dictionary else {}
			var viewport: SubViewport = batch_job.get("viewport") as SubViewport
			var texture: Texture2D = null
			if viewport != null and is_instance_valid(viewport):
				var captured_image := viewport.get_texture().get_image()
				if captured_image != null and not captured_image.is_empty():
					if captured_image.get_width() != AVATAR_PREVIEW_RENDER_SIZE or captured_image.get_height() != AVATAR_PREVIEW_RENDER_SIZE:
						captured_image.resize(AVATAR_PREVIEW_RENDER_SIZE, AVATAR_PREVIEW_RENDER_SIZE, Image.INTERPOLATE_LANCZOS)
					texture = ImageTexture.create_from_image(captured_image)
					_save_avatar_preview_image(cache_key, captured_image)
				viewport.queue_free()
			_finish_avatar_preview_job(cache_key, texture, profile)
		if not _avatar_preview_queue.is_empty():
			await batch_tree.process_frame
	_avatar_preview_worker_active = false


static func _finish_avatar_preview_job(cache_key: String, texture: Texture2D, profile: Dictionary) -> void:
	if texture != null:
		_avatar_preview_texture_cache[cache_key] = texture
	var waiters: Array = _avatar_preview_pending.get(cache_key, [])
	_avatar_preview_pending.erase(cache_key)
	for waiter_variant in waiters:
		if not (waiter_variant is Dictionary):
			continue
		var waiter: Dictionary = waiter_variant
		var holder_ref: WeakRef = waiter.get("holder") as WeakRef
		var holder: Control = null
		if holder_ref != null:
			holder = holder_ref.get_ref() as Control
		if holder == null or not is_instance_valid(holder):
			continue
		if texture != null:
			_install_avatar_texture(holder, texture)
		else:
			_install_initials_avatar_label(holder, profile, int(waiter.get("size_px", 36)))


static func _install_avatar_texture(holder: Control, texture: Texture2D) -> void:
	if holder == null or not is_instance_valid(holder) or texture == null:
		return
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Control.clip_contents is rectangular, even when its StyleBox is round.
	# Mask the portrait itself so shoulders and accessories stay inside the ring.
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec4 c=texture(TEXTURE,UV); float d=length(UV-vec2(0.5)); c.a*=1.0-smoothstep(0.48,0.493,d); COLOR=c; }"
	var mask := ShaderMaterial.new()
	mask.shader = shader
	texture_rect.material = mask
	holder.add_child(texture_rect)


static func _avatar_preview_cache_key(profile: Dictionary) -> String:
	var identity: String = str(profile.get("id", profile.get("user_id", profile.get("username", "unknown")))).strip_edges()
	var fingerprint_payload := {
		"renderer": AVATAR_PREVIEW_RENDER_REVISION,
		"id": identity,
		"updated": profile.get("updated", profile.get("updated_at", "")),
		"avatar_data": profile.get("avatar_data", {}),
		"avatar_outfit": profile.get("avatar_outfit", {}),
		"equipped_avatar_item_payloads": profile.get("equipped_avatar_item_payloads", []),
		"equipped_avatar_items": profile.get("equipped_avatar_items", [])
	}
	return JSON.stringify(fingerprint_payload).sha256_text()


static func _avatar_preview_cache_path(cache_key: String) -> String:
	return "%s/%s.png" % [AVATAR_PREVIEW_CACHE_DIR, cache_key]


static func _load_avatar_preview_texture(cache_key: String) -> Texture2D:
	var path := _avatar_preview_cache_path(cache_key)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func _save_avatar_preview_image(cache_key: String, image: Image) -> void:
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AVATAR_PREVIEW_CACHE_DIR))
	image.save_png(_avatar_preview_cache_path(cache_key))


static func _create_avatar_render_viewport(render_host: Node, profile: Dictionary) -> SubViewport:
	if render_host == null or not is_instance_valid(render_host):
		return null
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.size = Vector2i(AVATAR_PREVIEW_RENDER_SIZE, AVATAR_PREVIEW_RENDER_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_host.add_child(viewport)

	var camera := Camera3D.new()
	camera.fov = 25.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# UI previews are fitted around y=2.45 by player.gd. Frame the upper body so
	# the face remains visible in small social circles while preserving clothing.
	var camera_position := Vector3(0.0, 3.65, 6.1)
	var camera_target := Vector3(0.0, 3.65, 0.0)
	camera.transform = Transform3D(Basis.looking_at(camera_target - camera_position, Vector3.UP), camera_position)
	viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.45
	light.shadow_enabled = false
	light.transform = Transform3D(Basis.looking_at(Vector3(0, 1.35, 0) - Vector3(3.0, 5.0, 4.0), Vector3.UP), Vector3(3.0, 5.0, 4.0))
	viewport.add_child(light)

	var fill_light := OmniLight3D.new()
	fill_light.light_energy = 0.45
	fill_light.omni_range = 5.0
	fill_light.position = Vector3(-2.0, 2.0, 2.5)
	viewport.add_child(fill_light)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	if player_scene == null:
		viewport.queue_free()
		return null
	var avatar: Node3D = player_scene.instantiate() as Node3D
	if avatar == null:
		viewport.queue_free()
		return null
	avatar.set("is_ui_preview", true)
	avatar.set("use_local_avatar_fallback", false)
	avatar.set("render_avatar_visual_decals", true)
	avatar.set("render_avatar_clothing_decals", true)
	avatar.set("head_color", _resolve_avatar_color_from_profile(profile, "head", Color(0.96, 0.8, 0.2)))
	avatar.set("torso_color", _resolve_avatar_color_from_profile(profile, "torso", Color(0.05, 0.4, 0.7)))
	avatar.set("left_arm_color", _resolve_avatar_color_from_profile(profile, "left_arm", Color(0.96, 0.8, 0.2)))
	avatar.set("right_arm_color", _resolve_avatar_color_from_profile(profile, "right_arm", Color(0.96, 0.8, 0.2)))
	avatar.set("left_leg_color", _resolve_avatar_color_from_profile(profile, "left_leg", Color(0.65, 0.8, 0.2)))
	avatar.set("right_leg_color", _resolve_avatar_color_from_profile(profile, "right_leg", Color(0.65, 0.8, 0.2)))
	avatar.set("face_texture_path", _resolve_avatar_texture_from_profile(profile, "face_texture_path", "res://assets/avatar/default_face.png", false))
	avatar.set("chest_badge_texture_path", _resolve_avatar_texture_from_profile(profile, "chest_badge_texture_path", "res://assets/avatar/bobux_chest_badge.png", false))
	avatar.set("shirt_texture_path", _resolve_avatar_texture_from_profile(profile, "shirt_texture_path", "", true))
	avatar.set("pants_texture_path", _resolve_avatar_texture_from_profile(profile, "pants_texture_path", "", true))
	var equipped_payloads: Array = _resolve_avatar_payloads_from_profile(profile)
	avatar.set("equipped_avatar_items", equipped_payloads)
	avatar.rotation_degrees.y = 18.0
	avatar.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	avatar.position.y = -0.12
	var name_label: Node = avatar.get_node_or_null("Visuals/NameLabel")
	if name_label:
		name_label.visible = false
	viewport.add_child(avatar)
	if avatar.has_method("force_avatar_visual_refresh"):
		avatar.call_deferred("force_avatar_visual_refresh")
	return viewport


static func _resolve_avatar_payloads_from_profile(profile: Dictionary) -> Array:
	var avatar_data: Dictionary = profile.get("avatar_data", {}) if profile.get("avatar_data", {}) is Dictionary else {}
	var outfit: Dictionary = profile.get("avatar_outfit", {}) if profile.get("avatar_outfit", {}) is Dictionary else {}
	var sources: Array = [outfit, avatar_data, profile]
	for source_variant in sources:
		if not (source_variant is Dictionary):
			continue
		var source: Dictionary = source_variant
		for key in ["equipped_avatar_item_payloads", "equipped_avatar_items", "avatar_items", "equipped_items", "equipped"]:
			var raw_items: Variant = source.get(key, [])
			if not (raw_items is Array):
				continue
			var result: Array = []
			for item_variant in raw_items:
				if item_variant is Dictionary:
					result.append((item_variant as Dictionary).duplicate(true))
				if result.size() >= 16:
					break
			if not result.is_empty():
				return result
	return []


static func _build_static_avatar_model(root: Node3D, profile: Dictionary) -> void:
	var head_color: Color = _resolve_avatar_color_from_profile(profile, "head", Color(0.96, 0.8, 0.2))
	var torso_color: Color = _resolve_avatar_color_from_profile(profile, "torso", Color(0.05, 0.4, 0.7))
	var left_arm_color: Color = _resolve_avatar_color_from_profile(profile, "left_arm", Color(0.96, 0.8, 0.2))
	var right_arm_color: Color = _resolve_avatar_color_from_profile(profile, "right_arm", Color(0.96, 0.8, 0.2))
	var left_leg_color: Color = _resolve_avatar_color_from_profile(profile, "left_leg", Color(0.65, 0.8, 0.2))
	var right_leg_color: Color = _resolve_avatar_color_from_profile(profile, "right_leg", Color(0.65, 0.8, 0.2))

	_add_avatar_box(root, Vector3(0.0, 1.2, 0.0), Vector3(0.78, 0.82, 0.34), torso_color)
	_add_avatar_box(root, Vector3(-0.59, 1.2, 0.0), Vector3(0.28, 0.84, 0.32), left_arm_color)
	_add_avatar_box(root, Vector3(0.59, 1.2, 0.0), Vector3(0.28, 0.84, 0.32), right_arm_color)
	_add_avatar_box(root, Vector3(-0.22, 0.42, 0.0), Vector3(0.33, 0.74, 0.33), left_leg_color)
	_add_avatar_box(root, Vector3(0.22, 0.42, 0.0), Vector3(0.33, 0.74, 0.33), right_leg_color)
	_add_avatar_box(root, Vector3(0.0, 1.82, 0.0), Vector3(0.52, 0.52, 0.52), head_color)
	_add_avatar_box(root, Vector3(-0.095, 1.87, 0.266), Vector3(0.042, 0.062, 0.014), Color(0.05, 0.04, 0.03, 1))
	_add_avatar_box(root, Vector3(0.095, 1.87, 0.266), Vector3(0.042, 0.062, 0.014), Color(0.05, 0.04, 0.03, 1))
	_add_avatar_box(root, Vector3(0.0, 1.73, 0.268), Vector3(0.16, 0.028, 0.014), Color(0.05, 0.04, 0.03, 1))


static func _add_avatar_box(root: Node3D, position: Vector3, size: Vector3, color_value: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _make_avatar_material(color_value)
	root.add_child(instance)


static func _make_avatar_material(color_value: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = 0.58
	material.metallic = 0.0
	return material


static func _profile_initials(profile: Dictionary) -> String:
	var username: String = str(profile.get("username", profile.get("name", ""))).strip_edges()
	if username.is_empty():
		return "?"
	var parts: PackedStringArray = username.split("_", false)
	if parts.size() <= 1:
		parts = username.split(" ", false)
	var initials := ""
	for part in parts:
		if initials.length() >= 2:
			break
		var clean_part: String = str(part).strip_edges()
		if not clean_part.is_empty():
			initials += clean_part.substr(0, 1).to_upper()
	return initials if not initials.is_empty() else username.substr(0, 1).to_upper()

static func _resolve_avatar_color_from_profile(profile: Dictionary, part_key: String, fallback: Color) -> Color:
	var avatar_data: Dictionary = profile.get("avatar_data", {}) if profile.get("avatar_data", {}) is Dictionary else {}
	var outfit: Dictionary = profile.get("avatar_outfit", {}) if profile.get("avatar_outfit", {}) is Dictionary else {}
	var nested_body_colors: Dictionary = avatar_data.get("body_colors", {}) if avatar_data.get("body_colors", {}) is Dictionary else {}
	var direct_color_key: String = "%s_color" % part_key
	if outfit.has(direct_color_key):
		return _parse_avatar_color(outfit.get(direct_color_key), fallback)
	if outfit.has(part_key):
		return _parse_avatar_color(outfit.get(part_key), fallback)
	if avatar_data.has(part_key):
		return _parse_avatar_color(avatar_data.get(part_key), fallback)
	if avatar_data.has(direct_color_key):
		return _parse_avatar_color(avatar_data.get(direct_color_key), fallback)
	if nested_body_colors.has(part_key):
		return _parse_avatar_color(nested_body_colors.get(part_key), fallback)
	if nested_body_colors.has(direct_color_key):
		return _parse_avatar_color(nested_body_colors.get(direct_color_key), fallback)
	return fallback


static func _parse_avatar_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Dictionary:
		var color_dict: Dictionary = value
		if color_dict.has("r") and color_dict.has("g") and color_dict.has("b"):
			return Color(
				float(color_dict.get("r", fallback.r)),
				float(color_dict.get("g", fallback.g)),
				float(color_dict.get("b", fallback.b)),
				float(color_dict.get("a", fallback.a))
			)
	var raw: String = str(value).strip_edges()
	if raw.begins_with("#") and (raw.length() == 7 or raw.length() == 9):
		return Color(raw)
	return fallback


static func _resolve_avatar_texture_from_profile(profile: Dictionary, texture_key: String, fallback: String, allow_empty: bool) -> String:
	var avatar_data: Dictionary = profile.get("avatar_data", {}) if profile.get("avatar_data", {}) is Dictionary else {}
	var outfit: Dictionary = profile.get("avatar_outfit", {}) if profile.get("avatar_outfit", {}) is Dictionary else {}
	var sources: Array = [outfit, avatar_data]
	for source_variant in sources:
		if not (source_variant is Dictionary):
			continue
		var source_dict: Dictionary = source_variant
		if source_dict.has(texture_key):
			var direct_value := str(source_dict.get(texture_key, "")).strip_edges()
			if not direct_value.is_empty() or allow_empty:
				return direct_value
		var legacy_key := texture_key.replace("_texture_path", "_path")
		if source_dict.has(legacy_key):
			var legacy_value := str(source_dict.get(legacy_key, "")).strip_edges()
			if not legacy_value.is_empty() or allow_empty:
				return legacy_value
	if allow_empty:
		return ""
	return fallback


static func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.89, 0.9, 0.93, 1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	return style


static func _make_subpanel_style() -> StyleBoxFlat:
	var style := _make_panel_style()
	style.bg_color = Color(0.985, 0.988, 0.995, 1)
	return style

static func _make_friend_tile_style() -> StyleBoxFlat:
	var style := _make_panel_style()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_color = Color(0.82, 0.84, 0.88, 1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.shadow_color = Color(0, 0, 0, 0.12)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


static func _make_primary_button_style(color_value: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style


static func _make_secondary_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.96, 0.98, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.83, 0.86, 0.91, 1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style


static func _make_secondary_hover_style() -> StyleBoxFlat:
	var style := _make_secondary_button_style()
	style.bg_color = Color(0.91, 0.94, 0.98, 1)
	return style


static func _make_danger_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.93, 0.93, 1) if not hovered else Color(0.99, 0.9, 0.9, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.87, 0.54, 0.54, 1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style


static func _make_status_chip_style(is_live: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.95, 0.9, 1) if is_live else Color(0.93, 0.95, 0.98, 1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func _make_tab_style(is_active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 4 if is_active else 1
	style.border_color = Color(0.0, 0.63, 0.86, 1) if is_active else Color(0.82, 0.82, 0.82, 1)
	return style

static func _add_results_bar(container: Container, text: String) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 52)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.72, 0.72, 0.72, 1)
	panel.add_theme_stylebox_override("panel", style)
	container.add_child(panel)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1))
	panel.add_child(label)


static func _make_avatar_circle_style(size_px: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.93, 0.93, 1)
	var half_size: int = int(size_px / 2.0)
	style.corner_radius_top_left = half_size
	style.corner_radius_top_right = half_size
	style.corner_radius_bottom_left = half_size
	style.corner_radius_bottom_right = half_size
	return style


static func _add_placeholder(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	container.add_child(label)


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


static func _set_mouse_pass_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_mouse_pass_recursive(child)
