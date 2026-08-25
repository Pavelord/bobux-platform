class_name CatalogBuilder
extends RefCounted

const CATALOG_CARD_WIDTH := 144
const CATALOG_CARD_HEIGHT := 228
const CATALOG_THUMBNAIL_SIZE := 132

static func build(lobby: Control) -> void:
	var tabs = lobby.get_node_or_null("%MainTabs")
	if not tabs: return
	
	var catalog_view = tabs.get_node_or_null("CatalogView")
	if not catalog_view:
		catalog_view = ScrollContainer.new()
		catalog_view.name = "CatalogView"
		tabs.add_child(catalog_view)
	catalog_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	catalog_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
	# Clear existing
	for child in catalog_view.get_children():
		child.queue_free()
		
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_view.add_child(margin)
	
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	

	
	# Header Row (Title + Search)
	var header_hbox := HBoxContainer.new()
	root.add_child(header_hbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "Catalog"
	title_lbl.add_theme_color_override("font_color", Color("#333333"))
	title_lbl.add_theme_font_size_override("font_size", 28)
	header_hbox.add_child(title_lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var search_box := LineEdit.new()
	search_box.custom_minimum_size.x = 250
	search_box.placeholder_text = ""
	var _s_style = StyleBoxFlat.new()
	_s_style.border_width_left = 1; _s_style.border_width_top = 1
	_s_style.border_width_right = 1; _s_style.border_width_bottom = 1
	_s_style.border_color = Color("#DDDDDD")
	_s_style.bg_color = Color.WHITE
	search_box.add_theme_stylebox_override("normal", _s_style)
	header_hbox.add_child(search_box)
	
	var cat_opt := OptionButton.new()
	for option_name in ["All", "Shirts", "Pants", "Accessories"]:
		cat_opt.add_item(option_name)
	cat_opt.select(0)
	header_hbox.add_child(cat_opt)
	
	var btn_search := Button.new()
	btn_search.text = "Search"
	header_hbox.add_child(btn_search)
	
	# Main Content Area
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	root.add_child(content_hbox)
	
	# Left Sidebar
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = 180
	content_hbox.add_child(left_col)
	
	var nav_title_bg := ColorRect.new()
	nav_title_bg.color = Color("#666666")
	nav_title_bg.custom_minimum_size.y = 30
	left_col.add_child(nav_title_bg)
	
	var nav_title := Label.new()
	nav_title.text = " Browse by\n Category"
	nav_title.add_theme_color_override("font_color", Color.WHITE)
	nav_title.add_theme_font_size_override("font_size", 12)
	nav_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_title_bg.add_child(nav_title)
	
	var sub_panel := PanelContainer.new()
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color("#F8F8F8")
	sp_style.border_color = Color("#DDDDDD")
	sp_style.border_width_left = 1; sp_style.border_width_top = 0
	sp_style.border_width_right = 1; sp_style.border_width_bottom = 1
	sub_panel.add_theme_stylebox_override("panel", sp_style)
	left_col.add_child(sub_panel)
	
	var sub_vbox := VBoxContainer.new()
	sub_panel.add_child(sub_vbox)
	
	var section_buttons: Dictionary = {}
	for cat in ["Shirts", "Pants", "Accessories"]:
		var btn := Button.new()
		btn.text = cat
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var b_st := StyleBoxEmpty.new()
		b_st.content_margin_left = 8; b_st.content_margin_top = 6; b_st.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", b_st)
		btn.add_theme_stylebox_override("hover", b_st)
		btn.add_theme_color_override("font_color", Color("#0074BD"))
		sub_vbox.add_child(btn)
		section_buttons[cat] = btn
		
		if cat != "Items":
			var sep = ColorRect.new()
			sep.custom_minimum_size.y = 1
			sep.color = Color("#DDDDDD")
			sub_vbox.add_child(sep)
			
	var legend_lbl = Label.new()
	legend_lbl.text = "▼ Legend"
	legend_lbl.add_theme_color_override("font_color", Color("#333333"))
	legend_lbl.add_theme_font_size_override("font_size", 12)
	left_col.add_child(legend_lbl)
	legend_lbl.text = "Player-created avatar items"
	legend_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_lbl.add_theme_color_override("font_color", Color("#666666"))
	
	# Right Content (Featured Items on Bobux)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 20)
	content_hbox.add_child(right_col)
	
	var top_hdr := HBoxContainer.new()
	right_col.add_child(top_hdr)
	
	var rh_title = Label.new()
	rh_title.text = "Items on BOBUX"
	rh_title.add_theme_color_override("font_color", Color("#333333"))
	rh_title.add_theme_font_size_override("font_size", 22)
	top_hdr.add_child(rh_title)
	
	var sp_2 = Control.new()
	sp_2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hdr.add_child(sp_2)
	
	var hint := Label.new()
	hint.text = "Get items to add them to your wardrobe."
	hint.add_theme_color_override("font_color", Color("#777777"))
	hint.add_theme_font_size_override("font_size", 12)
	top_hdr.add_child(hint)
	
	var content_area := VBoxContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_child(content_area)
	
	_load_catalog(lobby, content_area, cat_opt, search_box, btn_search, section_buttons)

static func _load_catalog(lobby: Node, container: Node, cat_opt: OptionButton, search_box: LineEdit, btn_search: Button, section_buttons: Dictionary) -> void:
	# Show loading
	var loading_lbl := Label.new()
	loading_lbl.text = "Loading Catalog..."
	loading_lbl.add_theme_color_override("font_color", Color("#888888"))
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(loading_lbl)
	
	var cloud_api = lobby.get_node_or_null("/root/CloudAPI")
	if cloud_api == null or not cloud_api.is_configured():
		loading_lbl.text = "Cloud not connected."
		return
		
	var result: Dictionary = await cloud_api.fetch_catalog_items()
	var avatar_items_result: Dictionary = {"ok": false, "data": []}
	if cloud_api.has_method("fetch_avatar_marketplace_items"):
		avatar_items_result = await cloud_api.fetch_avatar_marketplace_items(96, true, false)
	
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
		
	if not result.get("ok", false):
		var err_lbl := Label.new()
		err_lbl.text = "Failed to load catalog: " + str(result.get("error", "Unknown error"))
		container.add_child(err_lbl)
		return
		
	var items: Array = []
	for legacy_variant in result.get("data", []):
		if not (legacy_variant is Dictionary):
			continue
		var legacy_item: Dictionary = legacy_variant
		var legacy_id := str(legacy_item.get("item_id", legacy_item.get("id", ""))).strip_edges()
		var legacy_type := str(legacy_item.get("asset_type", "")).strip_edges()
		if legacy_id in ["classic_head", "blue_torso", "green_legs"] or legacy_type == "part":
			continue
		items.append(legacy_item)
	if bool(avatar_items_result.get("ok", false)):
		for avatar_item_variant in _extract_array_payload(avatar_items_result):
			if not (avatar_item_variant is Dictionary):
				continue
			var avatar_item: Dictionary = avatar_item_variant
			items.append({
				"id": str(avatar_item.get("id", "")),
				"item_id": str(avatar_item.get("id", "")),
				"name": str(avatar_item.get("name", "Avatar Item")),
				"category": str(avatar_item.get("category", avatar_item.get("item_kind", "Avatar Items"))),
				"item_kind": str(avatar_item.get("item_kind", avatar_item.get("category", ""))),
				"asset_type": "avatar_item",
				"thumbnail": str(avatar_item.get("thumbnail", "")),
				"owned": bool(avatar_item.get("owned", false)),
				"owner_id": str(avatar_item.get("owner_id", "")),
				"data": avatar_item.get("data", {}),
				"attachment_slot": str(avatar_item.get("attachment_slot", "Head")),
				"attachment_transform": avatar_item.get("attachment_transform", {}),
				"price_robux": int(avatar_item.get("price_robux", 0)),
				"likes_count": int(avatar_item.get("likes_count", 0)),
				"owner_name": str(avatar_item.get("owner_name", ""))
			})
	var known_avatar_item_ids: Dictionary = {}
	for item_variant in items:
		if item_variant is Dictionary:
			var known_id := str((item_variant as Dictionary).get("item_id", (item_variant as Dictionary).get("id", ""))).strip_edges()
			if not known_id.is_empty():
				known_avatar_item_ids[known_id] = true
	for local_avatar_item in _extract_session_avatar_item_payloads():
		var local_id := str(local_avatar_item.get("id", local_avatar_item.get("item_id", ""))).strip_edges()
		if local_id.is_empty() or bool(known_avatar_item_ids.get(local_id, false)):
			continue
		local_avatar_item["id"] = local_id
		local_avatar_item["item_id"] = local_id
		local_avatar_item["asset_type"] = str(local_avatar_item.get("asset_type", "avatar_item"))
		local_avatar_item["owned"] = true
		items.append(local_avatar_item)
		known_avatar_item_ids[local_id] = true
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No catalog items found in the database."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(empty_lbl)
		return
		
	var state := {"section": "All"}
	var render_catalog := func() -> void:
		if container == null or not is_instance_valid(container):
			return
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
		var query := search_box.text.strip_edges().to_lower() if search_box != null else ""
		var selected_section := str(state.get("section", "All"))
		var grouped := {
			"Shirts": [],
			"Pants": [],
			"Accessories": []
		}
		for item_variant in items:
			if not (item_variant is Dictionary):
				continue
			var item: Dictionary = item_variant as Dictionary
			var section := _catalog_section_for_item(item)
			if selected_section != "All" and section != selected_section:
				continue
			if not query.is_empty():
				var searchable := "%s %s %s" % [
					str(item.get("name", item.get("title", ""))).to_lower(),
					str(item.get("owner_name", "")).to_lower(),
					str(item.get("item_kind", item.get("category", ""))).to_lower()
				]
				if searchable.find(query) < 0:
					continue
			(grouped[section] as Array).append(item)
		var rendered_any := false
		for section_name in ["Shirts", "Pants", "Accessories"]:
			var section_items: Array = grouped[section_name]
			if section_items.is_empty():
				continue
			rendered_any = true
			var section_title := Label.new()
			section_title.text = section_name
			section_title.add_theme_color_override("font_color", Color("#333333"))
			section_title.add_theme_font_size_override("font_size", 22)
			container.add_child(section_title)
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 12)
			flow.add_theme_constant_override("v_separation", 18)
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			container.add_child(flow)
			for section_item_variant in section_items:
				if section_item_variant is Dictionary:
					_add_catalog_card(lobby, flow, cloud_api, (section_item_variant as Dictionary).duplicate(true))
		if not rendered_any:
			var empty_filtered := Label.new()
			empty_filtered.text = "No items found for this section."
			empty_filtered.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_filtered.add_theme_color_override("font_color", Color("#777777"))
			container.add_child(empty_filtered)
	var set_section := func(section_name: String) -> void:
		state["section"] = section_name
		if cat_opt != null:
			for i in range(cat_opt.get_item_count()):
				if cat_opt.get_item_text(i) == section_name:
					cat_opt.select(i)
					break
		render_catalog.call()
	if cat_opt != null:
		cat_opt.item_selected.connect(func(index: int) -> void:
			state["section"] = cat_opt.get_item_text(index)
			render_catalog.call()
		)
	if btn_search != null:
		btn_search.pressed.connect(render_catalog)
	if search_box != null:
		search_box.text_submitted.connect(func(_text: String) -> void:
			render_catalog.call()
		)
	for section_key in section_buttons.keys():
		var section_button := section_buttons[section_key] as Button
		if section_button != null:
			section_button.pressed.connect(set_section.bind(str(section_key)))
	render_catalog.call()

static func _add_catalog_card(lobby: Node, grid: Container, cloud_api: Node, item: Dictionary) -> void:
	var item_name = item.get("name", "Unknown Item")
	var item_price = item.get("price_robux", 0)
	var price_str = "R$ " + str(item_price) if item_price > 0 else "Free"
	
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(CATALOG_CARD_WIDTH, CATALOG_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var img_box := Panel.new()
	var ib_st = StyleBoxFlat.new()
	ib_st.bg_color = Color.WHITE
	ib_st.border_width_left = 1; ib_st.border_width_top = 1
	ib_st.border_width_right = 1; ib_st.border_width_bottom = 1
	ib_st.border_color = Color("#DDDDDD")
	img_box.add_theme_stylebox_override("panel", ib_st)
	img_box.custom_minimum_size = Vector2(CATALOG_THUMBNAIL_SIZE, CATALOG_THUMBNAIL_SIZE)
	card.add_child(img_box)
	_apply_item_thumbnail_async(lobby, _resolve_catalog_thumbnail(item), img_box)
	
	var lbl_name := Label.new()
	lbl_name.text = item_name
	lbl_name.add_theme_color_override("font_color", Color("#0074BD"))
	lbl_name.add_theme_font_size_override("font_size", 12)
	lbl_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_name.clip_text = true
	lbl_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_name.custom_minimum_size = Vector2(CATALOG_CARD_WIDTH - 4, 32)
	card.add_child(lbl_name)

	var creator_label := Label.new()
	creator_label.text = "by %s" % _resolve_catalog_creator_name(item)
	creator_label.add_theme_color_override("font_color", Color("#777777"))
	creator_label.add_theme_font_size_override("font_size", 11)
	creator_label.clip_text = true
	creator_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	creator_label.custom_minimum_size = Vector2(CATALOG_CARD_WIDTH - 4, 20)
	card.add_child(creator_label)
	
	var lbl_price := Label.new()
	lbl_price.text = price_str
	lbl_price.add_theme_color_override("font_color", Color("#555555") if int(item_price) == 0 else Color("#118811"))
	lbl_price.add_theme_font_size_override("font_size", 11)
	card.add_child(lbl_price)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	card.add_child(actions)
	var get_btn := Button.new()
	get_btn.custom_minimum_size = Vector2(68, 30)
	var get_style := StyleBoxFlat.new()
	get_style.bg_color = Color("#169B32")
	get_style.corner_radius_top_left = 4
	get_style.corner_radius_top_right = 4
	get_style.corner_radius_bottom_left = 4
	get_style.corner_radius_bottom_right = 4
	get_btn.add_theme_stylebox_override("normal", get_style)
	get_btn.add_theme_stylebox_override("hover", get_style)
	get_btn.add_theme_color_override("font_color", Color.WHITE)
	var owned_id := str(item.get("item_id", item.get("id", ""))).strip_edges()
	var owned_type := str(item.get("asset_type", "avatar_item")).strip_edges()
	var is_owned := _is_catalog_item_owned(item, cloud_api)
	get_btn.text = "Owned" if is_owned else "Get"
	get_btn.disabled = is_owned
	get_btn.pressed.connect(func() -> void:
		if cloud_api.has_method("get_catalog_item"):
			get_btn.disabled = true
			get_btn.text = "Getting..."
			var get_result: Dictionary = await cloud_api.get_catalog_item(owned_id, owned_type)
			if bool(get_result.get("ok", false)):
				item["owned"] = true
				get_btn.text = "Owned"
				if UserSession.inventory_items is Array and not UserSession.inventory_items.has(owned_id):
					UserSession.inventory_items.append(owned_id)
				var avatar_ui_variant: Variant = lobby.get("avatar_ui") if lobby != null else null
				if avatar_ui_variant != null and avatar_ui_variant.has_method("reload_cloud_inventory"):
					avatar_ui_variant.call_deferred("reload_cloud_inventory")
			else:
				get_btn.disabled = false
				get_btn.text = "Retry"
	)
	actions.add_child(get_btn)
	var like_btn := Button.new()
	like_btn.text = "Like"
	like_btn.custom_minimum_size = Vector2(68, 30)
	var like_style := StyleBoxFlat.new()
	like_style.bg_color = Color("#666666")
	like_style.corner_radius_top_left = 4
	like_style.corner_radius_top_right = 4
	like_style.corner_radius_bottom_left = 4
	like_style.corner_radius_bottom_right = 4
	like_btn.add_theme_stylebox_override("normal", like_style)
	like_btn.add_theme_stylebox_override("hover", like_style)
	like_btn.add_theme_color_override("font_color", Color.WHITE)
	like_btn.pressed.connect(func() -> void:
		if cloud_api.has_method("like_catalog_asset"):
			like_btn.disabled = true
			var like_result: Dictionary = await cloud_api.like_catalog_asset(str(item.get("asset_type", "avatar_item")), owned_id)
			like_btn.text = "Liked" if bool(like_result.get("ok", false)) else "Retry"
			like_btn.disabled = bool(like_result.get("ok", false))
	)
	actions.add_child(like_btn)
	
	grid.add_child(card)


static func _catalog_section_for_item(item: Dictionary) -> String:
	var data: Dictionary = item.get("data", {}) if item.get("data", {}) is Dictionary else {}
	var kind := str(item.get("item_kind", item.get("category", item.get("type", "")))).strip_edges().to_lower()
	if kind.is_empty() or kind in ["avatar_item", "avatar items", "avatar_items", "item"]:
		kind = str(data.get("item_kind", data.get("category", data.get("kind", "")))).strip_edges().to_lower()
	if kind in ["shirt", "shirts", "tshirt", "t-shirt", "tee", "clothes", "clothing"]:
		return "Shirts"
	if kind in ["pants", "pant", "trousers", "legs"]:
		return "Pants"
	return "Accessories"


static func _is_catalog_item_owned(item: Dictionary, cloud_api: Node) -> bool:
	var item_id := str(item.get("item_id", item.get("id", ""))).strip_edges()
	if item_id.is_empty():
		return false
	if bool(item.get("owned", false)):
		return true
	if UserSession.inventory_items is Array and item_id in UserSession.inventory_items:
		return true
	var current_user_id := ""
	if UserSession.user_id.strip_edges() != "":
		current_user_id = UserSession.user_id.strip_edges()
	elif cloud_api != null and cloud_api.has_method("get_current_user_id"):
		current_user_id = str(cloud_api.get_current_user_id()).strip_edges()
	return not current_user_id.is_empty() and str(item.get("owner_id", "")).strip_edges() == current_user_id

static func _resolve_catalog_thumbnail(item: Dictionary) -> String:
	for key in ["thumbnail", "thumbnail_url", "thumbnail_path", "texture_path", "template_url", "atlas_path", "source_url", "image_path", "icon_path"]:
		var candidate := str(item.get(key, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	var data: Dictionary = item.get("data", {}) if item.get("data", {}) is Dictionary else {}
	for key in ["thumbnail", "thumbnail_url", "thumbnail_path", "texture_path", "template_url", "atlas_path", "source_url", "image_path", "icon_path"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return ""

static func _resolve_catalog_creator_name(item: Dictionary) -> String:
	for key in ["owner_name", "creator", "creator_name", "username", "author", "publisher_name"]:
		var candidate := str(item.get(key, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	var data: Dictionary = item.get("data", {}) if item.get("data", {}) is Dictionary else {}
	for key in ["owner_name", "creator", "creator_name", "username", "author", "publisher_name"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return "Unknown"

static func _extract_array_payload(response: Dictionary) -> Array:
	var data: Variant = response.get("data", [])
	if data is Array:
		return data
	if data is Dictionary:
		for key in ["items", "avatar_items", "data"]:
			var nested: Variant = (data as Dictionary).get(key, [])
			if nested is Array:
				return nested
	return []

static func _extract_session_avatar_item_payloads() -> Array:
	if typeof(UserSession) == TYPE_NIL or not (UserSession.avatar_data is Dictionary):
		return []
	var result: Array = []
	var seen: Dictionary = {}
	for list_key in ["owned_avatar_item_payloads", "equipped_avatar_item_payloads"]:
		var raw_list: Variant = UserSession.avatar_data.get(list_key, [])
		if not (raw_list is Array):
			continue
		for raw_payload in (raw_list as Array):
			if not (raw_payload is Dictionary):
				continue
			var payload := (raw_payload as Dictionary).duplicate(true)
			var payload_id := str(payload.get("id", payload.get("item_id", ""))).strip_edges()
			if payload_id.is_empty() or bool(seen.get(payload_id, false)):
				continue
			result.append(payload)
			seen[payload_id] = true
	return result

static func _apply_item_thumbnail_async(lobby: Node, thumbnail: String, target: Panel) -> void:
	var clean := thumbnail.strip_edges()
	if clean.is_empty() or target == null:
		return
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	target.add_child(texture_rect)

	var image := Image.new()
	var loaded := false
	if clean.begins_with("data:image/") or clean.begins_with("base64:"):
		var bytes := _decode_inline_image_bytes(clean)
		if not bytes.is_empty():
			loaded = image.load_png_from_buffer(bytes) == OK or image.load_jpg_from_buffer(bytes) == OK or image.load_webp_from_buffer(bytes) == OK
	elif FileAccess.file_exists(clean):
		loaded = image.load(clean) == OK
	elif clean.begins_with("http://") or clean.begins_with("https://"):
		if lobby == null:
			texture_rect.queue_free()
			return
		var request := HTTPRequest.new()
		request.use_threads = true
		request.timeout = 8.0
		request.body_size_limit = 4 * 1024 * 1024
		lobby.add_child(request)
		var start_error := request.request(clean, PackedStringArray(["Accept: image/png,image/jpeg,image/webp,*/*"]), HTTPClient.METHOD_GET)
		if start_error != OK:
			request.queue_free()
			texture_rect.queue_free()
			return
		var result: Array = await request.request_completed
		request.queue_free()
		if result.size() >= 4 and int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) >= 200 and int(result[1]) < 300 and result[3] is PackedByteArray:
			var body: PackedByteArray = result[3]
			loaded = image.load_png_from_buffer(body) == OK or image.load_jpg_from_buffer(body) == OK or image.load_webp_from_buffer(body) == OK
	if not loaded:
		texture_rect.queue_free()
		return
	image = _prepare_catalog_thumbnail_image(image, CATALOG_THUMBNAIL_SIZE * 4)
	texture_rect.texture = ImageTexture.create_from_image(image)

static func _prepare_catalog_thumbnail_image(source: Image, final_size: int) -> Image:
	if source == null or source.is_empty():
		return source
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var longest_side: int = maxi(image.get_width(), image.get_height())
	if longest_side > 1024:
		var ratio: float = 1024.0 / float(longest_side)
		image.resize(maxi(1, roundi(float(image.get_width()) * ratio)), maxi(1, roundi(float(image.get_height()) * ratio)), Image.INTERPOLATE_LANCZOS)
	image = _crop_thumbnail_to_subject(image)
	image.resize(final_size, final_size, Image.INTERPOLATE_LANCZOS)
	return image

static func _crop_thumbnail_to_subject(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var width := image.get_width()
	var height := image.get_height()
	if width <= 8 or height <= 8:
		return image
	var bg := image.get_pixel(0, 0)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(height):
		for x in range(width):
			var c := image.get_pixel(x, y)
			if c.a <= 0.04:
				continue
			var delta: float = absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			if delta < 0.12 and c.a >= 0.98:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return image
	var subject_width := max_x - min_x + 1
	var subject_height := max_y - min_y + 1
	if subject_width <= 4 or subject_height <= 4:
		return image
	var padding := maxi(8, roundi(float(maxi(subject_width, subject_height)) * 0.12))
	var crop_x := maxi(0, min_x - padding)
	var crop_y := maxi(0, min_y - padding)
	var crop_w := mini(width - crop_x, subject_width + padding * 2)
	var crop_h := mini(height - crop_y, subject_height + padding * 2)
	var square := maxi(crop_w, crop_h)
	var extra_x := int(maxi(0, square - crop_w) / 2)
	var extra_y := int(maxi(0, square - crop_h) / 2)
	crop_x = clampi(crop_x - extra_x, 0, maxi(0, width - square))
	crop_y = clampi(crop_y - extra_y, 0, maxi(0, height - square))
	square = mini(square, mini(width - crop_x, height - crop_y))
	if square <= 0:
		return image
	if square >= mini(width, height) - 2:
		return image
	return image.get_region(Rect2i(crop_x, crop_y, square, square))

static func _decode_inline_image_bytes(value: String) -> PackedByteArray:
	var encoded_value := value.strip_edges()
	if encoded_value.begins_with("data:image/"):
		var comma_index := encoded_value.find(",")
		if comma_index >= 0:
			encoded_value = encoded_value.substr(comma_index + 1)
	elif encoded_value.begins_with("base64:"):
		encoded_value = encoded_value.substr(7)
	return Marshalls.base64_to_raw(encoded_value)
