extends SceneTree


func _initialize() -> void:
	var runtime_script := load("res://autoload/mobile_runtime.gd") as Script
	if runtime_script == null:
		push_error("[validate_mobile_runtime_modes] MobileRuntime script did not load")
		quit(1)
		return
	var runtime := runtime_script.new() as Node
	if runtime == null:
		push_error("[validate_mobile_runtime_modes] MobileRuntime did not instantiate")
		quit(1)
		return
	var inside: Vector2 = runtime.call("_apply_joystick_deadzone", Vector2(0.08, 0.0), 0.12)
	var edge: Vector2 = runtime.call("_apply_joystick_deadzone", Vector2(1.0, 0.0), 0.12)
	var remapped: Vector2 = runtime.call("_apply_joystick_deadzone", Vector2(0.56, 0.0), 0.12)
	var ok := (
		inside.is_zero_approx()
		and edge.is_equal_approx(Vector2.RIGHT)
		and remapped.x > 0.0
		and remapped.x < 0.56
	)
	print("[validate_mobile_runtime_modes] ok=%s inside=%s edge=%s remapped=%s" % [str(ok), str(inside), str(edge), str(remapped)])
	runtime.free()
	quit(0 if ok else 1)
