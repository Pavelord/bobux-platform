extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("[legacy_media_physics] ", "PASS " if ok else "FAIL ", message)

func _run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var scene := Node3D.new()
	root.add_child(scene)
	var gui := Control.new()
	scene.add_child(gui)
	var sound := preload("res://addons/roblox_studio/roblox_data_model.gd").create_instance("Sound")
	gui.add_child(sound)
	var sound_api := preload("res://addons/roblox_runtime/roblox_sound_runtime.gd")
	var wrapper = engine.BobuxInstance.wrap(sound)
	for id in ["12221990", "12222152", "26723422"]:
		wrapper._set(&"SoundId", "http://novetus.mygamesonline.org/asset?id=" + id)
		wrapper._set(&"Looped", true)
		wrapper.Play()
		await process_frame
		var player := sound_api.player_for(sound)
		check(player is AudioStreamPlayer and player.stream != null and player.playing, "global Sound.Play " + id)
		wrapper.Stop()
		check(not player.playing, "Sound.Stop " + id)
	var ground := StaticBody3D.new()
	scene.add_child(ground)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, 1, 60)
	floor_shape.shape = floor_box
	ground.add_child(floor_shape)
	ground.position.y = -0.5
	var body := RigidBody3D.new()
	body.mass = 1000.0
	body.position = Vector3(0, 2, 0)
	scene.add_child(body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	collision.shape = box
	body.add_child(collision)
	preload("res://addons/roblox_runtime/roblox_heavy_body.gd").configure(body, 0.5)
	var character := CharacterBody3D.new()
	character.collision_layer = 2
	character.collision_mask = 1 | 32
	scene.add_child(character)
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	character.add_child(capsule)
	character.position = Vector3(-3, 1.1, 0)
	for frame in range(120):
		await physics_frame
		character.velocity = Vector3(12, -2, 0)
		character.move_and_slide()
	check(absf(body.global_position.x) < 0.05, "walking cannot push a heavy assembly")
	check(character.global_position.x < -2.3, "heavy assembly still blocks the character")
	body.apply_central_impulse(Vector3(6000, 0, 0))
	await create_timer(0.3).timeout
	check(body.global_position.x > 0.3, "external impulse still moves heavy assembly")
	var mat := preload("res://addons/rbxl_importer/material_cache.gd").new().get_part_material({"Color": [0.6, 0.25, 0.12], "TopSurface": 3, "BottomSurface": 4, "BobuxStudScale": 0.5})
	check(mat.next_pass is ShaderMaterial, "separate stud and inlet face material")
	check(mat.next_pass.get_shader_parameter("face_types") == Vector4(3, 4, 0, 0), "surface types preserved per face")
	check(mat.next_pass.get_shader_parameter("studs_texture").get_width() == 2048, "original user texture retained")
	scene.queue_free()
	await process_frame
	print("[legacy_media_physics] failures=", failures)
	quit(0 if failures.is_empty() else 1)
