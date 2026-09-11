extends SceneTree

const RobloxDataModelClass = preload("res://addons/roblox_studio/roblox_data_model.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine := root.get_node_or_null("LuaScriptEngine")
	if engine == null:
		push_error("LuaScriptEngine autoload is missing")
		quit(1)
		return
	var part := MeshInstance3D.new()
	part.name = "FirePart"
	part.set_meta("roblox_class", "Part")
	root.add_child(part)
	var fire := RobloxDataModelClass.create_instance("Fire", "Fire") as GPUParticles3D
	part.add_child(fire)
	var script_node: Node = RobloxDataModelClass.create_instance("Script", "FireScript")
	part.add_child(script_node)
	var source := """local part = script.Parent
local fire = part:FindFirstChildOfClass("Fire")
if fire then
   fire.Enabled = true
   fire.Color = Color3.fromRGB(255, 120, 20)
end
"""
	var result: Dictionary = engine.run_script(source, script_node)
	for _frame in range(3):
		await process_frame
		engine._process(0.016)
	var material := fire.process_material as ParticleProcessMaterial
	var expected := Color8(255, 120, 20)
	var color_ok := material != null and material.color.is_equal_approx(expected)
	var ok := bool(result.get("ok", false)) and fire.emitting and color_ok
	print("[validate_lua_fire_runtime] ok=%s result=%s color=%s" % [str(ok), JSON.stringify(result), str(material.color if material != null else Color.TRANSPARENT)])
	engine.stop_all_scripts(part)
	part.queue_free()
	quit(0 if ok else 1)
