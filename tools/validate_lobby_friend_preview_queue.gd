extends SceneTree

const FRIENDS_BUILDER := preload("res://scripts/lobby/friends_builder.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Control.new()
	host.name = "FriendPreviewQueueTest"
	root.add_child(host)

	var holders: Array[Control] = []
	var cache_paths: Array[String] = []
	for index in range(6):
		var profile := {
			"id": "preview-test-%d-%d" % [Time.get_ticks_msec(), index],
			"username": "PreviewTest%d" % index,
			"avatar_data": {
				"head": Color(0.96, 0.8, 0.2).to_html(),
				"torso": Color.from_hsv(float(index) / 6.0, 0.72, 0.72).to_html()
			}
		}
		var holder := FRIENDS_BUILDER._create_round_avatar_preview(profile, 84, 0.0, host)
		host.add_child(holder)
		holders.append(holder)
		cache_paths.append(FRIENDS_BUILDER._avatar_preview_cache_path(FRIENDS_BUILDER._avatar_preview_cache_key(profile)))

	var max_live_viewports := 0
	var max_frame_gap_msec := 0.0
	var last_frame_usec := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		max_frame_gap_msec = maxf(max_frame_gap_msec, float(now_usec - last_frame_usec) / 1000.0)
		last_frame_usec = now_usec
		max_live_viewports = maxi(max_live_viewports, _count_subviewports(host))
		var ready_count := 0
		for holder in holders:
			if holder == null or not is_instance_valid(holder):
				continue
			for child in holder.get_children():
				if child is TextureRect:
					ready_count += 1
					break
		if ready_count == holders.size():
			break
		if DisplayServer.get_name() == "headless" and FRIENDS_BUILDER._avatar_preview_queue.is_empty() and not FRIENDS_BUILDER._avatar_preview_worker_active:
			break

	var texture_count := 0
	for holder in holders:
		if holder == null or not is_instance_valid(holder):
			continue
		for child in holder.get_children():
			if child is TextureRect and (child as TextureRect).texture != null:
				texture_count += 1
				break

	var no_lingering_viewports := _count_subviewports(host) == 0
	var serialized_rendering := max_live_viewports <= 1
	var queue_drained: bool = FRIENDS_BUILDER._avatar_preview_queue.is_empty() and not FRIENDS_BUILDER._avatar_preview_worker_active
	var textures_ready: bool = texture_count == holders.size() or DisplayServer.get_name() == "headless"
	var frame_budget_ok := max_frame_gap_msec < 250.0
	var ok := textures_ready and queue_drained and no_lingering_viewports and serialized_rendering and frame_budget_ok
	print(
		"[validate_lobby_friend_preview_queue] ok=%s textures=%d max_viewports=%d max_frame_ms=%.2f queue_drained=%s lingering=%s"
		% [str(ok), texture_count, max_live_viewports, max_frame_gap_msec, str(queue_drained), str(not no_lingering_viewports)]
	)

	for cache_path in cache_paths:
		if FileAccess.file_exists(cache_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	host.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _count_subviewports(node: Node) -> int:
	var count := 1 if node is SubViewport else 0
	for child in node.get_children():
		count += _count_subviewports(child)
	return count
