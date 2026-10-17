extends SceneTree
var clicks := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var camera: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	var engine := root.get_node("LuaScriptEngine")
	var wrapper = engine.BobuxInstance.wrap(camera)
	wrapper._set("CFrame", engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(40, 60, 30))))
	var cinematic := camera.global_position
	var write_time: int = camera.get_meta("bobux_camera_written_msec", -1)
	wrapper._get("CFrame")
	assert(camera.get_meta("bobux_camera_written_msec", -2) == write_time, "Reading a camera must not keep the cutscene alive")
	player._restore_camera_after_script()
	var ok := camera.global_position.is_equal_approx(cinematic)
	camera.set_meta("bobux_camera_written_msec", Time.get_ticks_msec()-300)
	wrapper._set("CameraType", 6.0)
	player._restore_camera_after_script()
	ok = ok and camera.global_position.is_equal_approx(cinematic)
	wrapper._set("CameraType", 5.0)
	player._restore_camera_after_script()
	ok = ok and camera.position.x == 0 and camera.position.y == 0 and camera.basis.is_equal_approx(Basis.IDENTITY)
	var model := Node.new()
	root.add_child(model)
	var host := Control.new()
	host.size = Vector2(1280,720)
	root.add_child(host)
	var sync: Node = load("res://addons/roblox_runtime/roblox_live_gui.gd").new()
	sync.host = host
	sync.player_gui = model
	sync.engine = engine
	host.add_child(sync)
	sync.set_process(false)
	var button := Button.new()
	button.position = Vector2(80,600)
	button.size = Vector2(180,80)
	host.add_child(button)
	button.pressed.connect(func(): clicks += 1)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for pressed in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = Vector2(140,640)
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	ok = ok and clicks == 1
	var press := InputEventScreenTouch.new()
	press.position=Vector2(140,640);press.pressed=true
	root.push_input(press, true)
	var drag := InputEventScreenDrag.new()
	drag.position=Vector2(180,640)
	root.push_input(drag, true)
	press.pressed=false
	root.push_input(press, true)
	ok = ok and clicks == 1
	print("[park-camera-touch] PASS=",ok," clicks=",clicks," camera_local=",camera.position)
	quit(0 if ok else 1)

