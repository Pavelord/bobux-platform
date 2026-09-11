extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[movement_scripts] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func jump() -> void:
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(2)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(2)
	studio.studio_ai_prompt_edit.text = "Сделай тройной прыжок"
	await studio._request_and_apply_studio_ai()
	await studio._start_studio_playtest()
	var character: CharacterBody3D = studio.studio_playtest_player
	await frames(90)
	await jump()
	await frames(12)
	var previous := character.velocity.y
	await jump()
	check(character.velocity.y > previous + 1, "second jump")
	await frames(12)
	previous = character.velocity.y
	await jump()
	check(character.velocity.y > previous + 1, "third jump")
	await frames(8)
	previous = character.velocity.y
	await jump()
	check(character.velocity.y < previous, "fourth jump blocked")
	await frames(180)
	await jump()
	await frames(12)
	await jump()
	await frames(12)
	previous = character.velocity.y
	await jump()
	check(character.velocity.y > previous + 1, "three jumps restored after landing")
	await studio._stop_studio_playtest()
	studio.studio_ai_prompt_edit.text = "когда я зажал кнопку прыжок я могу летать"
	await studio._request_and_apply_studio_ai()
	await studio._start_studio_playtest()
	character = studio.studio_playtest_player
	await frames(90)
	var original_y := character.global_position.y
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	var focus := root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	root.push_input(key, true)
	await frames(45)
	check(character.global_position.y > original_y + 5, "held Space continuously raises physical character")
	key = key.duplicate()
	key.pressed = false
	root.push_input(key, true)
	await frames(80)
	check(character.velocity.y <= 0, "release ends flight and restores gravity")
	var diagnostics: Dictionary = root.get_node("LuaScriptEngine").get_runtime_diagnostics()
	check(int(diagnostics.failed) == 0, "no Lua errors")
	await studio._stop_studio_playtest()
	studio.queue_free()
	await frames(2)
	print("[movement_scripts] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
