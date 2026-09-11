extends SceneTree

func _initialize() -> void:
	root.size = Vector2i(480, 800)
	var packed := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lobby := packed.instantiate() as Control
	lobby.set_meta("bobux_compact_layout_override", true)
	root.add_child(lobby)
	await process_frame
	lobby.call("_switch_tab", 2)
	await create_timer(1.0).timeout
	var avatar_view := lobby.get_node_or_null("%MainTabs/AvatarView") as Control
	var main_row := avatar_view.get_node_or_null("Content/MainRow") if avatar_view != null else null
	var grid := avatar_view.find_child("WardrobeGrid", true, false) as GridContainer if avatar_view != null else null
	if not (main_row is VBoxContainer) or grid == null or grid.columns != 2:
		push_error("[validate_avatar_editor_mobile_layout] row=%s grid=%s columns=%s" % [main_row, grid, grid.columns if grid != null else -1])
		quit(1)
		return
	print("[validate_avatar_editor_mobile_layout] compact avatar editor OK")
	quit(0)
