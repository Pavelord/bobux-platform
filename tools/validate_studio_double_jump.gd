extends SceneTree

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
	print("[double_jump] %s: %s" % [message, value])

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func press_jump() -> void:
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(2)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(2)
	var broken := Node.new()
	broken.name = "BrokenJump"
	broken.set_meta("roblox_class", "Script")
	broken.set_meta("script_type", "Script")
	broken.set_meta("roblox_ref", "double-jump-regression")
	broken.set_meta("code", "local humanoid = script.Parent.Parent:FindFirstChildOfClass('Humanoid')\nhumanoid.JumpRequested:Connect(function()\n&#x20; humanoid:ChangeState(Enum.HumanoidStateType.Jumping)\nend)")
	studio.placement_parent.add_child(broken)
	studio.explorer_selected_node = broken
	# Exercise the same AI submit handler the user invokes, then the editor Save.
	studio.studio_ai_prompt_edit.text = "сделай скрипт на двойной прыжок"
	await studio._request_and_apply_studio_ai()
	var scripts: Node = studio.data_model.ensure_service("StarterPlayer").get_node("StarterCharacterScripts")
	var authored := scripts.get_node_or_null("DoubleJump")
	check(authored != null, "AI created character LocalScript")
	check(authored == broken and str(broken.get_meta("roblox_class")) == "LocalScript", "wrong Script repaired and relocated in place")
	if authored == null:
		studio.queue_free()
		await process_frame
		quit(1)
		return
	var tab: Control = studio.open_scripts[authored.get_instance_id()]
	var save_button: Button
	for button in tab.get_child(0).get_children():
		if button is Button:
			check(button.text not in ["Run", "Stop"], "script toolbar has no separate execution")
			if button.text == "Save": save_button = button
	check(save_button != null, "Save exists")
	if save_button != null: save_button.pressed.emit()
	# Repeating the request must update the existing script, not stack jump handlers.
	studio.studio_ai_prompt_edit.text = "исправь двойной прыжок"
	await studio._request_and_apply_studio_ai()
	check(scripts.get_child_count() == 1, "repeat request edits existing script")
	var editor: CodeEdit = studio._find_code_edit(tab)
	editor.text += '\nprint("DoubleJumpReady", 2, nil, true)\n'
	save_button.pressed.emit()
	var engine := root.get_node("LuaScriptEngine")
	var encoded := "local s = [[\n&#x20;literal]]\n-- &#x20;comment\n&#x20;local x = 1"
	check(engine.normalize_script_source(encoded) == "local s = [[\n&#x20;literal]]\n-- &#x20;comment\n local x = 1", "HTML indentation corrected without altering literals")
	for cycle in range(2):
		await studio._start_studio_playtest()
		var player: CharacterBody3D = studio.studio_playtest_player
		await frames(90)
		if cycle == 0:
			var output: RichTextLabel = studio._find_output_log(tab)
			check(output.get_parsed_text().contains("DoubleJumpReady\t2\tnil\ttrue"), "Play output reaches script tab with all print arguments")
		check(player.is_on_floor(), "Play %d grounded" % cycle)
		var ground_y := player.global_position.y
		await press_jump()
		check(player.velocity.y > 0 and player.global_position.y > ground_y, "first jump moves character")
		await frames(12)
		var before_second := player.velocity.y
		await press_jump()
		check(player.velocity.y > before_second + 1.0, "Lua second jump applies physical impulse")
		await frames(6)
		var before_third := player.velocity.y
		await press_jump()
		check(player.velocity.y < before_third, "third jump rejected")
		await frames(180)
		check(player.is_on_floor(), "character landed")
		await press_jump()
		await frames(12)
		before_second = player.velocity.y
		await press_jump()
		check(player.velocity.y > before_second + 1.0, "Landed resets jump counter")
		var diagnostics: Dictionary = engine.get_runtime_diagnostics()
		check(int(diagnostics.get("failed", 0)) == 0, "no Lua runtime failures")
		await studio._stop_studio_playtest()
		await frames(2)
	studio.queue_free()
	await frames(2)
	print("[double_jump] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
