extends SceneTree

const Library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
const Prefabs = preload("res://addons/roblox_studio/studio_prefab_library.gd")
var errors: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[prefab_persistence] %s=%s" % [label_, ok])
	if not ok: errors.append(label_)

func _initialize() -> void:
	await process_frame
	var packed := load("res://scenes/place_editor/studio.tscn")
	var studio: Node = packed.instantiate()
	root.add_child(studio)
	await process_frame
	var entry: Dictionary = Library.search_assets("chair", "model", "", 1)[0]
	studio._apply_studio_ai_actions([{"type": "spawn_asset", "asset_id": entry.id, "position": [4, 2, 6]}])
	var model: Node3D = null
	for child in studio.placement_parent.get_children():
		if child.get_meta("toolbox_asset_id", "") == entry.id: model = child
	if model == null: check(false, "library model spawned"); studio.queue_free(); await process_frame; quit(1); return
	model.name = "SavedChair"
	studio.explorer_selected_node = model
	studio._scale_selection_uniformly(2)
	var bounds_before: AABB = Library.bounds(model)
	var position_before := model.global_position
	studio._apply_studio_ai_actions(Prefabs.plan("pistol", {"Damage": 39, "EquipOnSpawn": true}).actions)
	studio._apply_studio_ai_actions(Prefabs.plan("car").actions)
	studio._apply_studio_ai_actions(Prefabs.plan("points_button", {"PointsPerClick": 7}).actions)
	studio._apply_studio_ai_actions([{"type": "set_environment", "sky_color": "#CC4477"}, {"type": "set_player_settings", "move_speed": 27, "jump_velocity": 19}])
	var audio: Dictionary = Library.search_assets("laser", "sound", "", 1)[0]
	studio._on_music_browse_pressed()
	studio._on_music_file_selected(audio.file)
	studio._on_music_volume_changed(37)
	studio._play_studio_music(0)
	check(studio.studio_music_player.playing, "music dialog preview plays OGG")
	check(studio.atmosphere_music_list.get_child_count() > 0, "music dialog shows imported track")
	var folder := "user://validation/prefab_persistence_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	check(await studio._save_map(folder), "map saved")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/map_data.json"))
	var files: Array = studio._collect_publish_asset_file_names(payload, payload.mode_settings.music_playlist, folder)
	check(files.any(func(path): return str(path).begins_with("manifest_asset_") and str(path).ends_with(".res")), "published assets include Tool meshes")
	check(files.any(func(path): return str(path).begins_with("manifest_asset_") and str(path).ends_with(".ogg")), "published assets include Tool sounds")
	studio.queue_free()
	await process_frame
	await process_frame
	studio = packed.instantiate()
	root.add_child(studio)
	await process_frame
	await studio._load_map_from_folder(folder)
	await process_frame
	var restored: Node3D = studio.placement_parent.get_node_or_null("SavedChair")
	check(restored != null, "model restored")
	if restored != null:
		var bounds_after: AABB = Library.bounds(restored)
		print("[prefab_persistence] bounds before=%s after=%s" % [bounds_before, bounds_after])
		check(restored.global_position.is_equal_approx(position_before), "model pivot survives load")
		check(bounds_before.size.is_equal_approx(bounds_after.size), "uniform size survives load")
	var pistol: Node = studio.data_model.ensure_service("StarterPack").get_node_or_null("Pistol")
	check(pistol != null and pistol.get_meta("attribute_Damage", 0) == 39, "Tool attributes survive save/load")
	if pistol != null:
		var detailed := false
		for mesh in pistol.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh is ArrayMesh: detailed = true
		check(detailed, "Tool retains real model geometry")
		var sounds: Array = pistol.find_children("*", "AudioStreamPlayer3D", true, false)
		check(not sounds.is_empty() and sounds[0].stream != null, "Tool sound restored from map bundle")
	check(studio._get_current_player_settings().move_speed == 27, "movement settings survive save/load")
	check(is_equal_approx(studio.studio_music_volume, 0.37), "music volume survives save/load")
	check(studio.current_roblox_environment_settings.get("custom_sky_color", false), "custom sky survives save/load")
	await studio._start_studio_playtest()
	await create_timer(0.4).timeout
	check(studio.studio_playtest_player.get_humanoid_walk_speed() == 27, "Play uses saved movement settings")
	check(studio.studio_music_player.playing, "Play starts saved background music")
	check(studio.studio_playtest_player.get_node_or_null("Pistol") != null, "saved weapon auto equips in Play")
	check(int(root.get_node("LuaScriptEngine").get_runtime_diagnostics().failed) == 0, "loaded scripts run without errors")
	await studio._stop_studio_playtest()
	check(not studio.studio_music_player.playing, "Stop stops background music")
	studio.queue_free()
	await process_frame
	await process_frame
	print("[prefab_persistence] errors=%s" % [errors])
	quit(0 if errors.is_empty() else 1)
