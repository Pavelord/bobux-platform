extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[lobby_rows] ",label_,"=",ok)
	if not ok: failures.append(label_)
func settle() -> void:
	for i in range(10): await process_frame
func _run() -> void:
	var probe := GDScript.new()
	probe.source_code = "extends 'res://scripts/lobby/lobby.gd'\nfunc _ready():\n\tLOBBY_STYLER_SCRIPT.apply_2016_theme(self)\n\t_apply_bobux_branding()\n\tpreload('res://scripts/lobby/lobby_chrome.gd').apply(self)\n\t_build_home_dashboard()\nfunc _process(_delta): pass\nfunc _refresh_bobux_creator_section(_entries,_token): pass\n"
	check(probe.reload()==OK,"lobby harness compiles")
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.set_script(probe)
	root.add_child(lobby)
	current_scene = lobby
	lobby._loading_overlay.hide()
	var entries: Array = []
	for i in range(25):
		entries.append({"map_id":"test-%d"%i,"name":"Adventure %d with a long title"%i,"icon_path":"res://assets/branding/login_background.png","active_players":i,"likes_count":85,"dislikes_count":15,"visits":100})
	entries.append(entries[0].duplicate())
	var alias: Dictionary = entries[1].duplicate()
	alias.id = alias.map_id
	alias.erase("map_id")
	entries.append(alias)
	for i in range(24):
		var friend: Control = lobby._create_home_friend_avatar({"id":"friend-%d"%i,"username":"Friend %d"%i}, {})
		lobby.home_friends_container.add_child(friend)
	var counts: Array[int] = []
	for width in [1280,1920,480,1920]:
		root.size = Vector2i(width,900)
		root.content_scale_size = root.size
		await settle()
		await lobby._render_home_game_sections(entries,lobby._discover_refresh_token)
		await settle()
		var grid: GridContainer = lobby.recommended_cards_grid
		var ids := {}
		var first_y := 0.0
		var one_row := true
		var square := true
		var padded := true
		for child: Control in grid.get_children():
			if ids.is_empty(): first_y=child.position.y
			one_row = one_row and is_equal_approx(child.position.y,first_y)
			var key: String = child.get_meta("bobux_game_name","")
			check(not ids.has(key),"unique %s at %d"%[key,width])
			ids[key]=true
			var media: Control = child.find_child("MediaHost",true,false)
			var title: Control = child.find_child("GameTitle",true,false)
			square = square and absf(child.size.x-148)<0.1 and media.size.is_equal_approx(Vector2(146,146))
			padded = padded and title.global_position.x-child.global_position.x >=7 and title.get_global_rect().end.x<=child.get_global_rect().end.x-6
		check(one_row and grid.get_child_count()==lobby._get_home_game_grid_columns(),"one full recommended row at %d"%width)
		check(square and padded,"square covers and aligned inset text at %d"%width)
		counts.append(grid.get_child_count())
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.codex-tmp/home_rows_%d.png"%width)
	check(counts[1]>counts[0] and counts[2]<counts[0] and counts[3]==counts[1],"resizing changes number of cards instead of stretching")
	# Reproduce a thumbnail retry whose owning lobby is removed during await.
	var target := TextureRect.new()
	lobby.add_child(target)
	lobby._retry_remote_game_icon_load("http://127.0.0.1:1/unused",target,0)
	root.remove_child(lobby)
	lobby._retry_remote_game_icon_load("http://127.0.0.1:1/unused",target,0)
	await create_timer(1.0).timeout
	check(lobby._remote_game_icon_active_downloads==0,"detached lobby cancels thumbnail retries")
	lobby.free()
	print("[lobby_rows] counts=",counts," failures=",failures)
	quit(0 if failures.is_empty() else 1)
