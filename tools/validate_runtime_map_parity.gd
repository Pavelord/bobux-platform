extends SceneTree

const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
const QUERY = preload("res://addons/roblox_runtime/roblox_spatial_query.gd")
const PHYSICS = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
const ENVIRONMENT = preload("res://addons/roblox_runtime/roblox_environment_snapshot.gd")
var failures: Array[String] = []

func _initialize(): run.call_deferred()
func check(ok: bool, detail: String):
	print("[runtime_parity] ", detail, "=", ok)
	if not ok: failures.append(detail)

func part(parent: Node, at: Vector3) -> MeshInstance3D:
	var node := DATA.create_instance("Part", "Part") as MeshInstance3D
	node.position = at
	node.scale = Vector3(4, 1, 4)
	node.set_meta("anchored", true)
	node.set_meta("roblox_properties", {"Anchored":true, "TopSurface":3, "BottomSurface":4})
	parent.add_child(node)
	return node

func run():
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "Workspace"
	world.position = Vector3(100, 20, 30)
	world.set_meta("bobux_authored_origin", Vector3(50, 0, 0))
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 0.5)
	root.add_child(world)
	var model := Node3D.new()
	world.add_child(model)
	var first := part(model, Vector3(0, 0, 0))
	var second := part(model, Vector3(0, 1, 0))
	var a = engine.BobuxInstance.wrap(first)
	var b = engine.BobuxInstance.wrap(second)
	a._set(&"Position", Vector3(12, 8, 10))
	b._set(&"Position", Vector3(12, 10, 10))
	check(first.global_position.is_equal_approx(Vector3(156,24,25)), "room origin applied to authored position")
	check(a._get(&"Position").is_equal_approx(Vector3(12,8,10)), "position round trip")
	check(a._godot_velocity_to_roblox(Vector3(3,4,-5)).is_equal_approx(Vector3(6,8,10)), "velocity excludes room translation")
	engine.BobuxInstance.wrap(model).MakeJoints()
	var body := PHYSICS.body_for(first)
	check(body == PHYSICS.body_for(second), "connected anchored wave shares body")
	var offset := second.global_position - first.global_position
	for step in range(24):
		a._set(&"Position", Vector3(12 + step, 8, 10))
		b._set(&"Position", Vector3(12 + step, 10, 10))
		await physics_frame
	check((second.global_position-first.global_position).is_equal_approx(offset), "anchored wave segments stay aligned")
	var size_before: Vector3 = first.global_basis.get_scale()
	for i in 60:
		var pose: Transform3D = a._get(&"CFrame").transform
		pose.basis = Basis(Vector3.UP,0.073) * pose.basis
		a._set(&"CFrame",engine.BobuxCFrame.new(pose))
	check(first.global_basis.get_scale().is_equal_approx(size_before), "rotating nonuniform parts preserves Size")
	check(absf(first.global_basis.x.normalized().dot(first.global_basis.z.normalized()))<0.0001, "repeated CFrame writes never shear a wave part")
	var shape: CollisionShape3D = body.get_child(0)
	var proxy: Variant = instance_from_id(int(shape.get_meta("bobux_player_shape_id",0)))
	check(is_instance_valid(proxy) and proxy.transform.is_equal_approx(shape.transform), "wave player collision follows visual")
	QUERY.in_radius(world, first.global_position, 10, [], false, 0, false)
	var builds := QUERY.full_builds
	for i in range(12):
		await process_frame
		QUERY.in_radius(world, first.global_position, 10, [], false, 0, false)
	check(QUERY.full_builds == builds, "stationary queries reuse spatial index across frames")
	first.hide()
	check(not QUERY.in_radius(world, first.global_position, 1, [], false, 0, false).has(first), "hidden part leaves index")
	first.show()
	check(QUERY.in_radius(world, first.global_position, 1, [], false, 0, false).has(first), "shown part returns to index")
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.set("is_ui_preview",true)
	root.add_child(player)
	player.apply_world_stud_scale(0.5)
	player.ensure_roblox_character_contract()
	player.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	engine.bind_local_player_character(player)
	var state: Dictionary = engine.get_local_inventory_state(world)
	var added := []
	engine.BobuxInstance.wrap(state.local_player).CharacterAdded.Connect(func(_character): added.append(true))
	player.global_position = Vector3(160,80,25)
	engine.bind_local_player_character(player)
	check(added.is_empty() and player.global_position.is_equal_approx(Vector3(160,80,25)), "GUI rebind does not respawn character")
	var torso = engine.BobuxInstance.wrap(player.get_node("Torso"))
	check(torso._coordinate_origin() == Vector3(150,20,30), "sibling character uses bound room coordinate system")

	var gui := Control.new()
	root.add_child(gui)
	var target := DATA.create_instance("TextButton", "Menu") as BaseButton
	target.set_meta("roblox_ref", "menu-test")
	world.add_child(target)
	var button := Button.new()
	button.set_meta("roblox_ref", "menu-test")
	gui.add_child(button)
	await engine.bind_gui_controls_async(gui, world)
	check(button.focus_mode == Control.FOCUS_NONE, "async imported menu cannot capture jump key")
	var clicks := []
	button.pressed.connect(func(): clicks.append(true))
	button.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(clicks.is_empty(), "Space does not activate imported Menu")

	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.13
	sun.rotation_degrees = Vector3(-32,-45,0)
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(ENVIRONMENT.capture(env,sun)))
	var replay := Environment.new()
	var replay_sun := DirectionalLight3D.new()
	ENVIRONMENT.apply(replay, replay_sun, {"render_snapshot":json_copy})
	check(replay.tonemap_mode == env.tonemap_mode and is_equal_approx(replay.tonemap_exposure,env.tonemap_exposure) and replay.adjustment_saturation == env.adjustment_saturation, "published exposure and color grading equal Studio")
	check(is_equal_approx(sun.light_energy,replay_sun.light_energy) and sun.rotation.is_equal_approx(replay_sun.rotation), "published sun equals Studio")
	sun.free(); replay_sun.free()
	engine.stop_all_scripts(world)
	world.queue_free(); player.queue_free(); gui.queue_free()
	await process_frame
	print("[runtime_parity] failures=",failures)
	quit(0 if failures.is_empty() else 1)
