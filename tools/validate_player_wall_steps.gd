extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[wall_steps] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func box(parent: Node, pos: Vector3, size_: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size_
	body.add_child(shape)
	parent.add_child(body)
	return body

func _initialize() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest", true)
	world.add_child(player)
	player.position = Vector3.ZERO
	await frames(15)
	var wall := box(world, Vector3(0, 5, -3), Vector3(12, 10, 1))
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	check(player.global_position.z > -2.6 and not player._is_body_overlapping_world(), "wall blocks without embedding capsule")
	var start := player.global_position
	Input.action_press("move_back")
	await frames(25)
	Input.action_release("move_back")
	check(player.global_position.z > start.z + 2, "can back away after pushing against wall")
	wall.queue_free()
	await frames(3)
	player.position = Vector3.ZERO
	player._previous_physics_position = player.position
	player.velocity = Vector3.ZERO
	box(world, Vector3(0, 0.5, -4), Vector3(6, 1, 4))
	await frames(10)
	Input.action_press("move_forward")
	var peak := 0.0
	for _i in range(45):
		await frames(1)
		peak = maxf(peak, player.position.y)
	Input.action_release("move_forward")
	check(peak > 0.9 and player.position.z < -2.5, "walks onto one stud step without jump")
	# Emulate an edited part appearing around a stationary character.
	player.position = Vector3(10, 0, 0)
	player._previous_physics_position = player.position
	player.velocity = Vector3.ZERO
	await frames(8)
	box(world, Vector3(10, 1, 0), Vector3(2, 2, 2))
	await frames(5)
	player._has_safe_position = false
	var escaped: bool = player._recover_world_overlap()
	check(escaped and not player._is_body_overlapping_world(), "recovers when new part engulfs player with no safe history")
	world.queue_free()
	await frames(2)
	print("[wall_steps] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
