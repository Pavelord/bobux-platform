extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine := root.get_node_or_null("LuaScriptEngine")
	if engine == null:
		push_error("[validate_lua_click_detector_runtime] LuaScriptEngine autoload is missing")
		quit(1)
		return

	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	workspace.set_meta("roblox_stud_scale", 1.0)
	root.add_child(workspace)
	var door := MeshInstance3D.new()
	door.name = "Door"
	door.set_meta("roblox_class", "Part")
	workspace.add_child(door)
	var script_node := Node.new()
	script_node.name = "DoorScript"
	script_node.set_meta("roblox_class", "Script")
	door.add_child(script_node)

	var source := """local object = script.Parent
local isOpen = false
local closedPosition = object.Position
local openPosition = closedPosition + Vector3.new(0, 5, 0)
local clickDetector = object:FindFirstChild("ClickDetector")
if clickDetector == nil then
   clickDetector = Instance.new("ClickDetector")
   clickDetector.Parent = object
end
clickDetector.MouseClick:Connect(function()
   if isOpen == true then
       object.Position = closedPosition
       isOpen = false
       print("Door closed")
   else
       object.Position = openPosition
       isOpen = true
       print("Door opened")
   end
end)
"""
	var result: Dictionary = engine.start_script(source, script_node, {"realm": "server", "is_server": true})
	await process_frame
	var detector := door.get_node_or_null("ClickDetector")
	var detector_ready := detector != null and detector.is_in_group("roblox_click_detectors")
	var first_fired := detector_ready and bool(engine.fire_roblox_instance_event(detector, "MouseClick"))
	await process_frame
	var opened := is_equal_approx(door.position.y, 5.0)
	var second_fired := detector_ready and bool(engine.fire_roblox_instance_event(detector, "MouseClick"))
	await process_frame
	var closed := door.position.is_equal_approx(Vector3.ZERO)
	var ok := bool(result.get("ok", false)) and detector_ready and first_fired and opened and second_fired and closed
	print("[validate_lua_click_detector_runtime] ok=%s result=%s detector=%s opened=%s closed=%s" % [ok, JSON.stringify(result), detector_ready, opened, closed])
	engine.stop_all_scripts(workspace)
	workspace.queue_free()
	quit(0 if ok else 1)
