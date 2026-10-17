extends SceneTree
const SENSOR = preload("res://scripts/player/humanoid/climb_sensor.gd")
const CONTROLLER = preload("res://scripts/player/humanoid/climb_controller.gd")
const CONFIG = preload("res://scripts/player/humanoid/humanoid_config.tres")

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ok := true
	for scale_ in [0.5, 1.0]:
		var world := Node3D.new()
		root.add_child(world)
		var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
		player.world_stud_scale = scale_
		player.set_meta("bobux_studio_playtest", true)
		world.add_child(player)
		player.set_process(false)
		player.set_physics_process(false)
		var visual := MeshInstance3D.new()
		visual.set_meta("roblox_class", "TrussPart")
		world.add_child(visual)
		var collider := StaticBody3D.new()
		collider.set_meta("_bobux_shape_parts", {0: visual.get_instance_id()})
		world.add_child(collider)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# The centre ray goes through an opening; a side rail still supports climbing.
		box.size = Vector3(0.25, 8, 0.2) * scale_
		shape.shape = box
		collider.add_child(shape)
		collider.position = Vector3(0.6, 3, -0.8) * scale_
		for upside_down in [false, true]:
			visual.rotation.x = PI if upside_down else 0.0
			await physics_frame
			await physics_frame
			var hit := SENSOR.probe(player, Vector3.FORWARD, CONFIG)
			var velocity := CONTROLLER.velocity_for(Vector3.ZERO, visual, Vector3.BACK, 1.0, 16.0, 1.0, CONFIG)
			var pass_: bool = not hit.is_empty() and velocity.y > 0.0
			print("[climb] scale=", scale_, " inverted=", upside_down, " PASS=", pass_)
			ok = ok and pass_
		box.size = Vector3(2,8,2) * scale_
		collider.position = Vector3(0,3,0) * scale_
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var clearance := 2.05 if absf(direction.x)>0.5 else 1.55
			player.position = -direction * clearance * scale_
			await physics_frame
			await physics_frame
			var hit := SENSOR.probe(player,direction,CONFIG)
			print("[climb] four-sided scale=",scale_," direction=",direction," PASS=",not hit.is_empty())
			ok = ok and not hit.is_empty()
		visual.set_meta("roblox_class", "Part")
		ok = ok and SENSOR.probe(player, Vector3.FORWARD, CONFIG).is_empty()
		world.queue_free()
		await process_frame
	quit(0 if ok else 1)
