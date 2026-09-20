extends SceneTree

const CAPTURE_PATH := "user://avatar_editor_layout.png"

func _initialize() -> void:
	root.size = Vector2i(1440, 900)
	var packed := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lobby := packed.instantiate() as Control
	root.add_child(lobby)
	await process_frame
	lobby.call("_switch_tab", 2)
	await create_timer(1.5).timeout
	var overlay := lobby.get("_loading_overlay") as Control
	if overlay != null:
		overlay.hide()
	var avatar_view := lobby.get_node_or_null("%MainTabs/AvatarView") as Control
	var main_row := avatar_view.get_node_or_null("Content/MainRow") if avatar_view != null else null
	var preview := avatar_view.find_child("PreviewPanel", true, false) if avatar_view != null else null
	var grid := avatar_view.find_child("WardrobeGrid", true, false) if avatar_view != null else null
	var breadcrumb := avatar_view.find_child("AvatarBreadcrumb", true, false) if avatar_view != null else null
	var room_background := preview.get_node_or_null("BobuxAvatarRoomBg") as TextureRect if preview != null else null
	var ok := main_row is HBoxContainer and preview != null and grid != null and breadcrumb is Label
	ok = ok and room_background != null and room_background.texture != null
	if not ok:
		push_error("[validate_avatar_editor_layout] Incomplete row=%s preview=%s grid=%s breadcrumb=%s room=%s avatar_ui=%s" % [main_row, preview, grid, breadcrumb, room_background, lobby.get("avatar_ui")])
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(CAPTURE_PATH) != OK:
		push_error("[validate_avatar_editor_layout] Could not save capture")
		quit(1)
		return
	print("[validate_avatar_editor_layout] ok=true capture=%s" % ProjectSettings.globalize_path(CAPTURE_PATH))
	quit(0)
