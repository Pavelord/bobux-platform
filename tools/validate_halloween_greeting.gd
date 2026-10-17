extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(400, 740)
	root.content_scale_size = root.size
	var ui: Node = root.get_node("HalloweenEventUI")
	if ui.get("_timer") != null: (ui.get("_timer") as Timer).stop()
	ui.set("_seen", {})
	var early := {"event_id":"halloween_2026", "server_time":"2026-10-30T20:59:59.000Z", "reward_at":"2026-10-30T21:00:00.000Z", "pumpkin_owned":false, "items":[]}
	ui.consume_state(early, "greeting-contract-a")
	if is_instance_valid(ui.get("_dialog")): failures.append("early client reward greeting")
	var state: Dictionary = early.duplicate(true)
	state.server_time = "2026-10-30T21:00:00.000Z"
	ui.consume_state(state, "greeting-contract-a")
	await process_frame
	var dialog: CanvasLayer = ui.get("_dialog")
	if dialog == null: failures.append("missing greeting at Moscow midnight")
	elif dialog.find_child("PumpkinPreview", true, false) != null: failures.append("unearned item promised")
	ui._acknowledge()
	ui.consume_state(state, "greeting-contract-a")
	if is_instance_valid(ui.get("_dialog")): failures.append("duplicate greeting for same account")
	state.pumpkin_owned = true
	state.items = [{"id":"event_halloween_2026_pumpkin","name":"Pumpkin","source_url":"res://assets/events/halloween2026/pumpkin.glb","category":"accessory","attachment_transform":{"rotation_degrees":[0,-90,0]},"data":{"limited":true,"art_version":4}}]
	ui.consume_state(state, "greeting-contract-b")
	await process_frame
	dialog = ui.get("_dialog")
	if dialog == null or dialog.find_child("PumpkinPreview", true, false) == null or dialog.find_child("HalloweenBadge", true, false) == null: failures.append("eligible reward preview / Halloween 2026 missing")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://validation/halloween")
		root.get_texture().get_image().save_png("user://validation/halloween/greeting.png")
	ui._acknowledge()
	print("HALLOWEEN_GREETING_RESULT=",JSON.stringify({"ok":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
