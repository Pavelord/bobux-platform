extends SceneTree


func _initialize() -> void:
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	if lua_engine == null:
		push_error("LuaScriptEngine autoload is unavailable")
		quit(1)
		return
	var part := Node3D.new()
	part.name = "EscalatorBrick"
	part.set_meta("roblox_stud_scale", 0.5)
	part.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)), Vector3(4.0, 2.0, -3.0))
	get_root().add_child(part)
	var script_node := Node.new()
	script_node.name = "Script"
	part.add_child(script_node)
	lua_engine.reset_runtime_diagnostics()
	var result: Dictionary = lua_engine.start_script(
		"local direction = script.Parent.CFrame.lookVector\n" +
		"script.Parent.Velocity = direction * 13\n" +
		"script.Parent.CFrame = script.Parent.CFrame * CFrame.new(1, 2, 3)\n",
		script_node,
		{"source_name": "CFrameRuntimeTest", "retain": true}
	)
	await process_frame
	var diagnostics: Dictionary = lua_engine.get_runtime_diagnostics()
	var velocity: Variant = part.get_meta("velocity", null)
	# Lua exposes Roblox studs while the Godot world stores half-unit studs.
	# Roblox and Godot use opposite Z handedness. After converting the Roblox
	# LookVector back to Godot, it aligns with the stored basis Z axis here.
	var expected_velocity := part.transform.basis.z.normalized() * 13.0 * 0.5
	var ok := bool(result.get("ok", false))
	ok = ok and int(diagnostics.get("failed", 0)) == 0
	ok = ok and velocity is Vector3 and (velocity as Vector3).is_equal_approx(expected_velocity)
	ok = ok and part.position.is_finite()
	print("[validate_lua_cframe_runtime] ok=%s velocity=%s position=%s diagnostics=%s" % [ok, velocity, part.position, diagnostics])
	lua_engine.stop_all_scripts()
	part.queue_free()
	await process_frame
	lua_engine.release_stopped_script_states()
	quit(0 if ok else 1)
