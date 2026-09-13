extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(390, 844)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		var reward = load("res://scripts/lobby/founder_reward.gd").new()
		reward.preview_only = true
		root.add_child(reward)
		await create_timer(0.5).timeout
		var card: PanelContainer = reward.get("_card")
		var button: Button = reward.get("_button")
		if card.size.x > root.get_visible_rect().size.x: failures.append("card overflows %s" % dimensions)
		if button.text != "Получить": failures.append("claim button missing")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.codex-tmp/urgent-release/reward_%dx%d.png" % [dimensions.x, dimensions.y])
		reward.queue_free()
		await process_frame
	print("[founder_reward_ui] failures=", failures)
	quit(0 if failures.is_empty() else 1)
