extends SceneTree

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var source := """
local input = game:GetService("UserInputService")
local character = script.Parent
input.InputBegan:Connect(function(key, processed)
    if key.KeyCode == Enum.KeyCode.E then
        assert(key.UserInputType == Enum.UserInputType.Keyboard)
        assert(key.UserInputState == Enum.UserInputState.Begin)
        assert(input:IsKeyDown(Enum.KeyCode.E))
        character:SetAttribute(processed and "TypingInput" or "GameplayInput", true)
    end
    if key.UserInputType == Enum.UserInputType.MouseButton1 then
        character:SetAttribute("MouseInput", true)
    end
end)
input.InputEnded:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.E then
        assert(not input:IsKeyDown(Enum.KeyCode.E))
        character:SetAttribute("Released", true)
    end
end)
input.InputChanged:Connect(function(key)
    if key.UserInputType == Enum.UserInputType.MouseMovement then
        assert(key.Delta.X == 8)
        character:SetAttribute("Motion", true)
    end
end)
"""
	var applied: int = studio._apply_studio_ai_actions([{"type": "create_script", "name": "InputTest", "parent": "StarterCharacterScripts", "script_type": "LocalScript", "source": source}])
	print("[lua_input] applied=%s errors=%s" % [applied, studio.studio_ai_last_errors])
	await studio._start_studio_playtest()
	var character: Node = studio.studio_playtest_player
	print("[lua_input] processing=%s disabled=%s diag=%s" % [root.get_node("LuaScriptEngine").is_processing_input(), root.is_input_disabled(), root.get_node("LuaScriptEngine").get_runtime_diagnostics()])
	var focus := root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	root.push_input(key)
	await create_timer(0.1).timeout
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)
	await create_timer(0.1).timeout
	var text_box := LineEdit.new()
	root.add_child(text_box)
	text_box.grab_focus()
	key = key.duplicate()
	key.pressed = true
	root.push_input(key)
	await create_timer(0.1).timeout
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)
	await create_timer(0.1).timeout
	text_box.queue_free()
	await process_frame
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse)
	await create_timer(0.1).timeout
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(8, 0)
	root.push_input(motion, true)
	await create_timer(0.1).timeout
	var ok := true
	for attr in ["GameplayInput", "TypingInput", "Released", "MouseInput", "Motion"]:
		var passed := bool(character.get_meta("attribute_" + attr, false))
		print("[lua_input] %s=%s" % [attr, passed])
		ok = ok and passed
	var diagnostics: Dictionary = root.get_node("LuaScriptEngine").get_runtime_diagnostics()
	ok = ok and int(diagnostics.get("failed", 0)) == 0
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)
