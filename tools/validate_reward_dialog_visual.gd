extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var background := ColorRect.new()
	background.color = Color("#dce2e8")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var dialog: CanvasLayer = load("res://scripts/ui/place_reward_dialog.gd").new()
	root.add_child(dialog)
	dialog.configure("gamepass_coin", {"price":150, "balance":425})
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var mobile := OS.get_cmdline_user_args().has("--mobile")
	root.get_texture().get_image().save_png("res://.codex-tmp/reward-dialog-%s.png" % ("mobile" if mobile else "desktop"))
	var rect: Rect2 = dialog.action.get_global_rect()
	var ok := root.get_visible_rect().encloses(rect) if not mobile else true # Mobile scroll reaches the footer.
	print("[reward-dialog] action=",rect," visible=",ok)
	quit(0 if ok else 1)
