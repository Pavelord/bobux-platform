extends SceneTree
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): Engine.physics_ticks_per_second = int(args[0])
	_run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[player_feel] ", label_, "=", ok)
	if not ok: failures.append(label_)
func frames(count: int) -> void:
	for i in range(maxi(1, roundi(count * Engine.physics_ticks_per_second / 60.0))):
		await physics_frame
		await process_frame
func box(pos: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = dimensions
	body.add_child(shape)
	world.add_child(body)
	return body
func reset(pos := Vector3.ZERO) -> void:
	player._restore_after_respawn()
	player.set_lua_position(pos)
	player.velocity = Vector3.ZERO
	await frames(12)
func jump(hold: bool) -> float:
	await reset()
	Input.action_press("jump")
	await frames(1)
	if not hold: Input.action_release("jump")
	var peak := player.position.y
	for i in range(55):
		await frames(1)
		peak = maxf(peak, player.position.y)
	Input.action_release("jump")
	return peak
func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(0,-0.5,0), Vector3(200,1,200))
	player = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest",true)
	world.add_child(player)
	await frames(10)
	var rest: Vector3 = player.left_arm_pivot.rotation
	var idle_range := 0.0
	for i in range(20):
		await frames(6)
		idle_range = maxf(idle_range, rest.distance_to(player.left_arm_pivot.rotation))
	check(idle_range > 0.02, "idle shoulders breathe")
	Input.action_press("move_forward")
	await frames(1)
	var first_speed := Vector2(player.velocity.x,player.velocity.z).length()
	await frames(15)
	check(first_speed > 0 and first_speed < 8 and absf(player.velocity.z + 16) < 0.2, "progressive acceleration to 16 studs per second")
	Input.action_release("move_forward")
	var stop_start := player.position
	await frames(20)
	var stop_distance := stop_start.distance_to(player.position)
	check(stop_distance > 0.25 and stop_distance < 1.5 and player.velocity.length() < 0.2, "short weighted stop without ice sliding")
	var tap_peak := await jump(false)
	var held_peak := await jump(true)
	print("[player_feel] jump peaks=",tap_peak," / ",held_peak)
	check(absf(tap_peak-held_peak)<0.15 and tap_peak>6.9 and tap_peak<7.5, "same ballistic arc for tapped and held jump")
	await reset()
	player.apply_external_impulse(Vector3(4,0,0))
	await frames(2)
	check(player.get_runtime_humanoid_state() != 0 and player.velocity.x > 2, "small push preserves momentum without knockdown")
	player.apply_external_impulse(Vector3(24,6,0))
	await frames(8)
	check(player.get_runtime_humanoid_state() != 0 and absf(player.visuals.rotation.z)<0.01, "strong push never forces a prone pose")
	var legacy := {"move_speed":24.0,"jump_velocity":31.0,"sprint_multiplier":1.25}
	player.apply_movement_settings(legacy)
	check(is_equal_approx(player.get_humanoid_jump_power(),53.15), "legacy map retains a full height jump")
	var legacy_peak := await jump(false)
	check(legacy_peak>6.9 and legacy_peak<7.5, "legacy map jump clears character height")
	legacy["movement_version"] = 2
	player.apply_movement_settings(legacy)
	check(player.get_humanoid_jump_power()==31, "explicit authored power stays literal")
	player.set_humanoid_jump_power(20)
	check(player.get_humanoid_jump_power()==20, "Lua power remains literal")
	player.apply_movement_settings({})
	var hidden_field := LineEdit.new()
	root.add_child(hidden_field)
	hidden_field.grab_focus()
	hidden_field.hide()
	check(not player._is_text_input_focused(), "hidden text field cannot block movement")
	hidden_field.queue_free()
	# A box corner must permit sliding and backing out.
	await reset(Vector3(20,0,0))
	var wall := box(Vector3(22,3,-3),Vector3(4,6,1))
	var side := box(Vector3(24.5,3,0),Vector3(1,6,7))
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await frames(90)
	Input.action_release("move_forward")
	Input.action_release("move_right")
	check(not player._is_body_overlapping_world(), "diagonal corner does not embed body")
	var corner_pos := player.position
	Input.action_press("move_back")
	Input.action_press("move_left")
	await frames(25)
	Input.action_release("move_back")
	Input.action_release("move_left")
	check(player.position.distance_to(corner_pos)>3, "escapes diagonal corner immediately")
	wall.queue_free(); side.queue_free()
	await reset(Vector3(-20,0,0))
	var cylinder := StaticBody3D.new()
	cylinder.position = Vector3(-20,2.5,-3)
	var shape := CollisionShape3D.new()
	shape.shape = CylinderShape3D.new()
	shape.shape.radius = 1.5
	shape.shape.height = 5
	cylinder.add_child(shape)
	world.add_child(cylinder)
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	var cylinder_pos := player.position
	Input.action_press("move_right")
	await frames(25)
	Input.action_release("move_right")
	check(not player._is_body_overlapping_world() and player.position.x > cylinder_pos.x + 3, "slides around curved imported-style collider")
	cylinder.queue_free()
	player.apply_world_stud_scale(0.5)
	await reset(Vector3(-40,0,0))
	Input.action_press("move_forward")
	await frames(18)
	check(absf(player.velocity.z + 8.0)<0.2, "half-scale imported world retains speed in studs")
	Input.action_release("move_forward")
	player.apply_external_impulse(Vector3(12,2,0))
	await frames(8)
	check(player.get_runtime_humanoid_state()!=0 and not player._is_body_overlapping_world(), "scaled push preserves upright collider")
	world.queue_free()
	await frames(3)
	print("[player_feel] failures=",failures)
	quit(0 if failures.is_empty() else 1)
