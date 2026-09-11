extends SceneTree
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[obstacles] ",label_,"=",ok)
	if not ok: failures.append(label_)
func frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame
func block(pos: Vector3, dimensions: Vector3, concave := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var collider := CollisionShape3D.new()
	if concave:
		var mesh := BoxMesh.new()
		mesh.size = dimensions
		collider.shape = mesh.create_trimesh_shape()
	else:
		collider.shape = BoxShape3D.new()
		collider.shape.size = dimensions
	body.add_child(collider)
	world.add_child(body)
	return body
func place(pos: Vector3) -> void:
	player.set_lua_position(pos)
	player.velocity = Vector3.ZERO
	await frames(12)
func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	block(Vector3(0,-0.5,0),Vector3(160,1,160))
	player = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest",true)
	world.add_child(player)
	await frames(12)
	# A 1.6 stud corridor should fit the rounded body without arm colliders.
	var left := block(Vector3(-1.3,4,-5),Vector3(1,8,10))
	var right := block(Vector3(1.3,4,-5),Vector3(1,8,10))
	Input.action_press("move_forward")
	await frames(55)
	Input.action_release("move_forward")
	check(player.position.z < -10 and not player._is_body_overlapping_world(), "crosses narrow passage without shoulder snagging")
	left.queue_free(); right.queue_free()
	await place(Vector3(20,0,0))
	var mesh_wall := block(Vector3(20,5,-3),Vector3(12,10,1),true)
	mesh_wall.rotation.y = 0.32
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	var wall_position := player.position
	Input.action_press("move_back")
	await frames(25)
	Input.action_release("move_back")
	check(player.position.z > wall_position.z + 3 and not player._is_body_overlapping_world(), "backs out of rotated concave model")
	mesh_wall.queue_free()
	await place(Vector3(40,0,0))
	# Do not invoke recovery directly: exercise its timer with real movement.
	var engulfing := block(Vector3(40,3,0),Vector3(8,6,8))
	player._has_safe_position = false
	Input.action_press("move_right")
	for i in range(80):
		# Small solver-like jitter used to reset the overlap timer indefinitely.
		if i < 30 and player._is_body_overlapping_world():
			player.position.z += 0.08 if i%2==0 else -0.08
		await frames(1)
	Input.action_release("move_right")
	check(not player._is_body_overlapping_world(), "automatic recovery survives jitter inside a newly added block")
	engulfing.queue_free()
	await place(Vector3(-30,0,0))
	var ceiling := block(Vector3(-30,5.7,0),Vector3(10,0.6,10))
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(35)
	check(player.is_on_floor() and not player._is_body_overlapping_world(), "ceiling collision releases the character")
	ceiling.queue_free()
	world.queue_free()
	await frames(3)
	print("[obstacles] failures=",failures)
	quit(0 if failures.is_empty() else 1)
