extends SceneTree

const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
const PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, detail: String):
	if not ok: failures.append(detail)
func part(parent: Node, at: Vector3, size_: Vector3, anchored: bool = true) -> MeshInstance3D:
	var mesh := DATA.create_instance("Part", "Part") as MeshInstance3D
	mesh.position = at
	mesh.scale = size_
	mesh.set_meta("anchored", anchored)
	mesh.set_meta("roblox_properties", {"Anchored":anchored,"TopSurface":3,"BottomSurface":4})
	parent.add_child(mesh)
	return mesh
func run():
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "Workspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	# Old saved parts have Anchored in properties but no lowercase metadata.
	var island := part(world, Vector3(0,-1,0), Vector3(40,2,40))
	island.remove_meta("anchored")
	var island_body := PHYSICS.body_for(island, true)
	var brick := part(world, Vector3(0,0.5,0), Vector3.ONE, false)
	PHYSICS.body_for(brick, true)
	var explosion := DATA.create_instance("Explosion", "Lightning")
	explosion.position = Vector3(-1,0.2,0)
	explosion.set_meta("BlastRadius", 12.0)
	explosion.set_meta("BlastPressure", 2000000.0)
	world.add_child(explosion)
	explosion.add_child(preload("res://addons/roblox_runtime/roblox_explosion.gd").new())
	await create_timer(0.3).timeout
	check(island_body.freeze and island.position.is_equal_approx(Vector3(0,-1,0)), "lightning unanchors permanent island")
	check(brick.position.distance_to(Vector3(0,0.5,0)) > 0.05, "blast fails to move dynamic debris")

	var wall := part(world, Vector3(15,3,0), Vector3(1,4,4))
	var static_body := StaticBody3D.new()
	wall.add_child(static_body)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	static_body.add_child(collision)
	var wall_api = engine.BobuxInstance.wrap(wall)
	wall_api._set(&"CanCollide", false)
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(12,3,0),Vector3(18,3,0),1)
	check(world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "CanCollide=false static Part still blocks player")
	ray.collision_mask = 16
	check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "non-solid Part lost query shape")
	wall_api._set(&"CanCollide", true)
	await physics_frame
	await physics_frame
	ray.collision_mask = 1
	check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "CanCollide=true fails to restore collision")

	var vehicle := Node3D.new()
	world.add_child(vehicle)
	var chassis := part(vehicle, Vector3(-10,3,0), Vector3(4,1,3))
	var seat := part(vehicle, Vector3(-10,4,0), Vector3.ONE)
	seat.set_meta("roblox_class", "VehicleSeat")
	var wheel := part(vehicle, Vector3(-12.75,3,0), Vector3(1.5,1.5,1.5))
	wheel.set_meta("RightSurface", 6)
	engine.BobuxInstance.wrap(vehicle).MakeJoints()
	check(PHYSICS.body_for(seat)==PHYSICS.body_for(chassis), "seat not welded into compound chassis")
	check(int(seat.get_meta("AreHingesDetected", 0)) > 0, "VehicleSeat does not detect connected wheel hinge")
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.set("is_ui_preview", true)
	world.add_child(player)
	player.set_physics_process(false)
	player.apply_world_stud_scale(0.5)
	player.ensure_roblox_character_contract()
	player._set_collision_enabled(true)
	player.position = Vector3(-10,4.6,0)
	await physics_frame
	await physics_frame
	check(player._find_seat_below()==seat, "compound collider hides Seat")
	var events := []
	engine.BobuxInstance.wrap(player.get_node("Humanoid"))._shared_event("Seated").Connect(func(active, _seat): events.append(active))
	# Exercise the movement controller: landing on a Seat must sit without E.
	player.position = Vector3(-10, 5.5, 0)
	for frame in range(60):
		player._run_local_movement(1.0 / 60.0)
		await physics_frame
		if player.get("_seated_part") == seat: break
	check(player.get("_seated_part") == seat, "standing on Seat does not automatically sit")
	check((seat.get_meta("Occupant") if seat.has_meta("Occupant") else null)==player.get_node("Humanoid"), "seat occupancy not assigned")
	check(seat.get_node_or_null("SeatWeld")!=null, "legacy SeatWeld missing")
	player._update_seated_movement(false, Vector2(0.5,-1))
	check(seat.get_meta("ThrottleFloat",0)==1 and seat.get_meta("SteerFloat",0)==0.5, "vehicle input not passed to Lua")
	await physics_frame
	await physics_frame
	var motor_started := false
	for hinge in vehicle.find_children("*", "HingeJoint3D", true, false):
		motor_started = motor_started or absf(hinge.get_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY)) > 0.01
	check(motor_started, "VehicleSeat input does not drive native hinges")
	player._leave_seat(true)
	check(not seat.has_meta("Occupant") and seat.get_meta("ThrottleFloat",1)==0, "seat input/occupancy persists after jump")
	check(events==[true,false], "Humanoid.Seated events missing")
	print("[imported_physics] failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
