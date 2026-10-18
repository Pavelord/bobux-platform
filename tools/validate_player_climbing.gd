extends SceneTree
const SENSOR = preload("res://scripts/player/humanoid/climb_sensor.gd")
const CONFIG = preload("res://scripts/player/humanoid/humanoid_config.tres")
var _finished := false

func _initialize() -> void:
	# A script error must not leave an unattended headless test running forever.
	create_timer(15.0).timeout.connect(func() -> void:
		if not _finished:
			push_error("[validate_player_climbing] Timed out")
			quit(1)
	)
	run.call_deferred()

func run() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		push_error("[validate_player_climbing] Player scene is missing")
		quit(1)
		return
	var world := Node3D.new()
	world.name = "ClimbingValidation"
	get_root().add_child(world)
	_add_box_body(world, "Floor", Vector3(0.0, -0.5, 0.0), Vector3(12.0, 1.0, 12.0), "Part")
	# Keep the top beyond this short ascent; top-exit parity is a separate test.
	var truss := _add_box_body(world, "Truss", Vector3(0.0, 6.0, -1.2), Vector3(3.0, 12.0, 0.25), "TrussPart")
	truss.add_to_group("roblox_climbable")

	var player := player_scene.instantiate() as CharacterBody3D
	player.name = "Character"
	player.set_meta("bobux_studio_playtest", true)
	player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	if not player.has_method("_set_collision_enabled"):
		push_error("[validate_player_climbing] Player collision setup unavailable")
		player.free()
		world.queue_free()
		quit(1)
		return
	world.add_child(player)
	player.position = Vector3.ZERO
	player.call("_set_collision_enabled", true)
	player.collision_mask = 1

	for _frame in range(4):
		await physics_frame
	var probe: Dictionary = SENSOR.probe(player, Vector3.FORWARD, CONFIG)
	var detected := not probe.is_empty()
	var start_y := player.global_position.y
	# Exercise the real player physics loop with the existing authored trace
	# input seam. Do not directly integrate a second motor tick or force state.
	player.set_meta("bobux_trace_move_direction", Vector3.FORWARD)
	for _frame in range(24):
		await physics_frame
	var humanoid := player.get_node_or_null("Humanoid")
	var climbing := humanoid != null and str(humanoid.get_meta("HumanoidState", "")) == "Climbing"
	var climbed := player.global_position.y > start_y + 0.25

	player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	player.set_meta("bobux_trace_jump", true)
	await physics_frame
	await physics_frame
	var detached := not bool(player.get("_climbing_active")) and player.velocity.y > 0.0
	var ok := detected and climbing and climbed and detached
	print("[validate_player_climbing] ok=%s detected=%s climbing=%s climbed=%s detached=%s delta_y=%.3f" % [
		str(ok), str(detected), str(climbing), str(climbed), str(detached), player.global_position.y - start_y,
	])
	world.queue_free()
	await process_frame
	# The audio mixer releases its playback references asynchronously after
	# the real character (and its movement sounds) leaves the tree.
	await create_timer(0.1).timeout
	_finished = true
	quit(0 if ok else 1)


func _add_box_body(parent: Node3D, node_name: String, position: Vector3, size: Vector3, roblox_class: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("roblox_class", roblox_class)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
