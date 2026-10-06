extends RefCounted

# Legacy avatar URLs refer to the Player.UserId of this session. Render that
# player's Bobux outfit locally, never request an unrelated Roblox account.
static func user_id(source: String) -> String:
	var clean := source.strip_edges().to_lower()
	if clean.begins_with("rbxthumb://"):
		if not ("type=avatar" in clean): return ""
	elif not (clean.begins_with("www.roblox.com/thumbs/avatar.ashx?") or clean.begins_with("https://www.roblox.com/thumbs/avatar.ashx?") or clean.begins_with("http://www.roblox.com/thumbs/avatar.ashx?")):
		return ""
	for field in source.replace("?", "&").split("&"):
		if field.get_slice("=", 0).to_lower() == "id": return field.get_slice("=", 1).uri_decode()
	return ""

static func profile_for(target: Node, identity: String) -> Dictionary:
	var node := target
	while node != null and str(node.get_meta("roblox_class", "")) != "Player": node = node.get_parent()
	if node == null or not node.is_inside_tree(): return {}
	var engine := node.get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine == null: return {}
	for player in node.get_parent().get_children():
		if str(player.get_meta("UserId", "")) != identity: continue
		var character: Node = engine._bound_character_for_player(player)
		var data := {}
		if is_instance_valid(character):
			for key in ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
				data[key] = character.get(key + "_color")
			for key in ["face_texture_path", "chest_badge_texture_path", "shirt_texture_path", "pants_texture_path", "equipped_avatar_items"]:
				data[key] = character.get(key)
		else:
			var session := node.get_tree().root.get_node_or_null("UserSession")
			if session == null or str(session.user_id) != identity: return {}
			data = session.avatar_data.duplicate(true)
		return {"id": identity, "username": player.get_meta("Name", player.name), "avatar_data": data}
	return {}

static var cache: Dictionary = {}

static func render(target: TextureRect, profile: Dictionary, headshot: bool) -> void:
	var key := JSON.stringify([profile, headshot]).sha256_text()
	if cache.has(key):
		target.texture = cache[key]
		return
	if not target.is_inside_tree() or DisplayServer.get_name() == "headless": return
	var target_ref := weakref(target)
	var viewport := preload("res://scripts/lobby/friends_builder.gd")._create_avatar_render_viewport(target, profile)
	if viewport == null: return
	if not headshot:
		var camera := viewport.get_child(0) as Camera3D
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 5.6
		camera.position = Vector3(0, 2.45, 9)
		camera.look_at(Vector3(0, 2.45, 0))
	var tree := target.get_tree()
	await tree.create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var live: Variant = target_ref.get_ref()
	if not is_instance_valid(live) or not is_instance_valid(viewport): return
	var captured := viewport.get_texture().get_image()
	if captured != null and not captured.is_empty():
		var texture := ImageTexture.create_from_image(captured)
		if cache.size() >= 64: cache.erase(cache.keys()[0])
		cache[key] = texture
		live.texture = texture
	viewport.queue_free()
