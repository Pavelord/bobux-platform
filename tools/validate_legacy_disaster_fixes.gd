extends SceneTree

const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
const QUERY = preload("res://addons/roblox_runtime/roblox_spatial_query.gd")
const PARTICLES = preload("res://addons/roblox_runtime/roblox_particles.gd")
const PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "Workspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	var smoke := DATA.create_instance("Smoke", "Smoke") as GPUParticles3D
	smoke.set_meta("roblox_properties", {"size_xml":60.0, "riseVelocity_xml":25.0, "opacity_xml":0.5, "Color":[0.8,0.8,1.0], "Enabled":true})
	world.add_child(smoke)
	PARTICLES.configure(smoke)
	check(smoke.draw_pass_1 is QuadMesh and smoke.draw_pass_1.size.x == 30.0, "legacy Smoke.Size lost")
	check(smoke.visibility_aabb.size.y >= 100.0, "large smoke incorrectly culled")
	check(smoke.process_material.initial_velocity_min == 10.0, "legacy Smoke.RiseVelocity lost")
	var fire := DATA.create_instance("Fire", "Fire") as GPUParticles3D
	world.add_child(fire)
	engine._apply_manifest_properties_to_node(fire, {"Enabled":false, "heat_xml":25.0, "size_xml":30.0})
	# This function normally receives metadata from the manifest installer.
	fire.set_meta("roblox_properties", {"Enabled":false,"heat_xml":25.0,"size_xml":30.0})
	PARTICLES.configure(fire)
	check(not fire.emitting, "disabled template fire starts before disaster")
	var wrapper = engine.BobuxInstance.new(fire)
	wrapper._set(&"Size", 12.0)
	check(fire.draw_pass_1.size.x == 6.0, "Lua Fire.Size does not update renderer")
	check(not fire.emitting, "resizing disabled fire starts it")

	var model := Node3D.new()
	world.add_child(model)
	var lower := part(model, Vector3(0, 5, 0))
	var upper := part(model, Vector3(0, 6, 0))
	# A tiny decorative mesh is still a full-sized physical Roblox Part.
	upper.mesh = BoxMesh.new()
	upper.mesh.size = Vector3.ONE * 0.05
	engine.BobuxInstance.new(model).MakeJoints()
	check(PHYSICS.body_for(lower) == PHYSICS.body_for(upper), "SpecialMesh changes surface-joint contact size")
	engine.BobuxInstance.new(upper)._set(&"Anchored", false)
	await create_timer(0.3).timeout
	check(upper.global_position.distance_to(Vector3(0,6,0)) < 0.01, "connected part falls before disaster")

	var probe := part(world, Vector3(30,0,0))
	var first := QUERY.in_box(world, Transform3D(Basis.IDENTITY, Vector3(30,0,0)), Vector3.ONE*2, [], false, 100, false)
	check(first.has(probe), "Region3 initial query")
	probe.position = Vector3(90,0,0)
	QUERY.invalidate(probe)
	check(not QUERY.in_box(world, Transform3D(Basis.IDENTITY, Vector3(30,0,0)), Vector3.ONE*2, [],false,100,false).has(probe), "Region3 old cell after movement")
	check(QUERY.in_box(world, Transform3D(Basis.IDENTITY, Vector3(90,0,0)), Vector3.ONE*2, [],false,100,false).has(probe), "Region3 new cell within same frame")
	world.remove_child(probe)
	check(not QUERY.in_box(world, Transform3D(Basis.IDENTITY, Vector3(90,0,0)), Vector3.ONE*2, [],false,100,false).has(probe), "removed Part remains queryable")
	probe.free()

	var studio: Control = load("res://scripts/place_editor/studio.gd").new()
	studio._register_imported_sound_asset({"as_music":true,"sound_id":"FastPing","playing":false,"resolved_path":"res://project.godot"})
	check(studio.current_music_source_paths.is_empty(), "one-shot SoundService sound enters music playlist")
	studio.free()

	var ladder_model := Node3D.new()
	world.add_child(ladder_model)
	var ladder := part(ladder_model, Vector3(0, 2, -0.7))
	ladder.set_meta("roblox_class", "TrussPart")
	ladder.scale = Vector3(1,4,0.5)
	var base := part(ladder_model, Vector3(0,-0.5,-0.7))
	base.scale = Vector3(1,1,0.5)
	engine.BobuxInstance.new(ladder_model).MakeJoints()
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.set("is_ui_preview", true)
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var hit: Dictionary = player._probe_climbable_surface(Vector3.FORWARD)
	check(not hit.is_empty(), "TrussPart lost in compound collision body")
	var climbed: bool = player._update_climbing_movement(1.0/60, Vector2(0,-1), Vector3.FORWARD, Basis.IDENTITY, false)
	check(climbed and player.velocity.y > 0.0, "walking into ladder without jump does not climb")
	print("[legacy_disaster_fixes] failures=", failures)
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func part(parent: Node, at: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = BoxMesh.new()
	result.position = at
	result.set_meta("roblox_class", "Part")
	result.set_meta("anchored", true)
	result.set_meta("roblox_properties", {"TopSurface":3,"BottomSurface":4})
	parent.add_child(result)
	return result
