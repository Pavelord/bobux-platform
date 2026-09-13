extends RefCounted

static func icon(name_: String, pixels: int) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load("res://assets/account_badges/%s.png" % name_)
	image.custom_minimum_size = Vector2(pixels, pixels)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_PASS
	return image

static func attach(label: Control, account: Dictionary) -> void:
	if not is_instance_valid(label): return
	var row := label.get_parent() as HBoxContainer
	if row == null or not bool(row.get_meta("account_badge_row", false)):
		var parent := label.get_parent()
		var index := label.get_index()
		row = HBoxContainer.new()
		row.clip_contents = true
		row.set_meta("account_badge_row", true)
		row.size_flags_horizontal = label.size_flags_horizontal
		row.custom_minimum_size = label.custom_minimum_size
		row.add_theme_constant_override("separation", 5)
		parent.add_child(row)
		parent.move_child(row, index)
		if not parent is Container:
			row.position = label.position
			row.size = label.size
		label.reparent(row)
		label.custom_minimum_size.x = 0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if label is Button else Control.SIZE_SHRINK_BEGIN
	for child in row.get_children():
		if child != label:
			row.remove_child(child)
			child.queue_free()
	var pixels := clampi(label.get_theme_font_size("font_size") + 3, 18, 38)
	var tier := str(account.get("club_tier", account.get("membership", {}).get("tier", ""))).to_lower()
	if tier in ["bc", "bbc", "pbc", "tbc"]:
		var badge := icon(tier, pixels)
		badge.tooltip_text = "%s · %s" % [tier.to_upper(), "Пожизненный Bricks Club" if account.get("club_lifetime", account.get("membership", {}).get("lifetime", false)) else "Bricks Club"]
		row.add_child(badge)
	if bool(account.get("verified_badge", false)):
		var badge := icon("verified", pixels)
		badge.tooltip_text = "Подтверждённый участник Bobux"
		row.add_child(badge)
