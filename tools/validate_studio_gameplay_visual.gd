extends SceneTree

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1440, 900)
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var library = preload("res://addons/roblox_studio/studio_gameplay_library.gd")
	studio._apply_studio_ai_actions(library.weapon_plan(false, true).actions)
	studio._apply_studio_ai_actions(library.npc_plan().actions)
	var npc: Node3D = studio.placement_parent.get_node("Zombie")
	npc.position = Vector3(-5, 0, 0)
	npc.get_node("Chase").set_meta("disabled", true)
	await studio._start_studio_playtest()
	await create_timer(0.4).timeout
	var character: CharacterBody3D = studio.studio_playtest_player
	character.global_position = Vector3(0, 0, 0)
	character.get_node("Visuals").rotation.y = 0
	var motor = preload("res://addons/roblox_runtime/roblox_humanoid_motor.gd").ensure(npc.get_node("Humanoid"))
	motor.set_health(75)
	var observer := Camera3D.new()
	studio.placement_parent.add_child(observer)
	observer.global_position = Vector3(10, 8, 14)
	observer.look_at(Vector3(-1, 2.5, 0))
	observer.make_current()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var capture := "user://studio_gameplay_visual.png"
	root.get_texture().get_image().save_png(capture)
	print("[gameplay_visual] " + ProjectSettings.globalize_path(capture))
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	quit()
