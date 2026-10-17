extends SceneTree

const STATES = preload("res://scripts/player/humanoid/state_machine.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("[humanoid-player] ", "PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)

func step(player: CharacterBody3D, frames: int) -> void:
	for _frame in frames:
		await physics_frame
		player.call("_run_local_movement", 1.0 / 60.0)
		player.call("_sync_humanoid_runtime_properties", player.call("_sample_ground_sensor"))

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.name = "HumanoidPlayerContract"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 1.0)
	world.set_meta("Gravity", 196.2)
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(500, 1, 500)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.set_meta("bobux_studio_playtest", true)
	player.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	world.add_child(player)
	player.set_physics_process(false)
	engine.bind_local_player_character(player)
	var h := player.get_node("Humanoid")
	var head: Mesh = player.get_node("Visuals/Head").mesh
	var probe := Node.new()
	probe.name = "HumanoidProbe"
	world.add_child(probe)
	var result: Dictionary = engine.start_script("""
local h=game.Players.LocalPlayer.Character.Humanoid
h.AutoRotate=false
h.HipHeight=2.25
local seated=0
h.Seated:Connect(function(active,seat)
    seated+=1
    script:SetAttribute('SeatedCount',seated)
    script:SetAttribute('SeatedActive',active)
    script:SetAttribute('SeatedHasPart',seat~=nil)
end)
local running=0
h.Running:Connect(function(speed)
    running+=1
    script:SetAttribute('RunningCount',running)
    script:SetAttribute('RunningSpeed',speed)
end)
local moveFinished=0
h.MoveToFinished:Connect(function(reached)
    moveFinished+=1
    script:SetAttribute('MoveToCount',moveFinished)
    script:SetAttribute('MoveToReached',reached)
end)
script:SetAttribute('Ready',true)
""", probe, {"retain": true})
	await create_timer(0.05).timeout
	check(result.get("ok", false) and probe.get_meta("attribute_Ready", false), "actual Luau listeners and property writes")
	await step(player, 12)
	check(not bool(h.get_meta("AutoRotate", true)) and is_equal_approx(float(h.get_meta("HipHeight", 0)), 2.25), "AutoRotate and HipHeight survive runtime synchronization")
	check(STATES.STATES.size() == 17 and STATES.STATES.Physics == 16 and STATES.STATES.None == 18 and STATES.STATES.FallingDown == 0, "all public Humanoid state IDs")

	var initial_angle: float = player.visuals.rotation.y
	player.set_meta("bobux_trace_move_direction", Vector3.RIGHT)
	await step(player, 15)
	check(absf(player.velocity.x - 16.0) < 0.01 and is_equal_approx(player.visuals.rotation.y, initial_angle), "AutoRotate false preserves facing while walking")
	player.is_shift_lock = true
	player._apply_camera_rotation_delta(0.35, 0.12)
	await step(player, 3)
	check(is_equal_approx(player.visuals.rotation.y, initial_angle), "AutoRotate false also covers shift lock and camera input")
	h.set_meta("AutoRotate", true)
	await step(player, 2)
	check(not is_equal_approx(player.visuals.rotation.y, initial_angle), "AutoRotate true resumes camera facing")
	player.is_shift_lock = false
	player.remove_meta("bobux_trace_move_direction")
	player.set_humanoid_move(Vector3.RIGHT * 0.5)
	await step(player, 15)
	check(absf(player.velocity.x - 8.0) < 0.01 and player.get_humanoid_move_direction().is_equal_approx(Vector3.RIGHT), "Humanoid Move keeps analog speed and reports unit direction")
	player.set_humanoid_move(Vector3.ZERO)
	await step(player, 15)
	check(player.get_humanoid_move_direction() == Vector3.ZERO and absf(float(probe.get_meta("attribute_RunningSpeed", -1))) < 0.01, "Running reports stopping and MoveDirection follows intent")

	player.set_lua_position(Vector3(0, 8, 0))
	player.velocity = Vector3(0, 20, 0)
	player.request_humanoid_state(5)
	check(is_equal_approx(player.velocity.y, 20.0) and player.get_runtime_humanoid_state() == 5, "ChangeState Freefall preserves an ascending impulse")
	await step(player, 1)
	check(player.get_runtime_humanoid_state() == 5 and player.velocity.y > 0, "ascending Freefall persists through automatic state resolution")
	world.set_meta("Gravity", 98.1)
	player.velocity.y = 20
	await step(player, 1)
	check(absf(player.velocity.y - (20 - 98.1 / 60.0)) < 0.001, "air movement follows live Workspace Gravity")
	h.set_meta("UseJumpPower", false)
	h.set_meta("JumpHeight", 10.0)
	player.request_humanoid_state(3)
	check(absf(player.velocity.y - sqrt(2.0 * 98.1 * 10.0)) < 0.001, "JumpHeight uses the same live gravity as freefall")
	world.set_meta("Gravity", 196.2)
	h.set_meta("UseJumpPower", true)
	var landed_visible := false
	for _frame in 120:
		await step(player, 1)
		if player.get_runtime_humanoid_state() == 7:
			landed_visible = true
			break
	check(landed_visible, "Landed remains observable after a physical landing")
	await step(player, 5)
	check(player.get_runtime_humanoid_state() == 8, "Landed resolves to Running after its configured transient")

	h.set_meta("bobux_state_enabled_3", false)
	player.request_humanoid_state(3)
	player.set_meta("bobux_trace_jump", true)
	await step(player, 2)
	check(player.get_runtime_humanoid_state() != 3 and absf(player.velocity.y) < 1, "disabled Jumping blocks both script and input jumps")
	h.set_meta("bobux_state_enabled_3", true)
	h.set_meta("PlatformStand", true)
	player.set_meta("bobux_trace_move_direction", Vector3.RIGHT)
	await step(player, 1)
	check(player.get_runtime_humanoid_state() == 14 and player.get_humanoid_move_direction() == Vector3.ZERO, "PlatformStand publishes PlatformStanding and suppresses control")
	h.set_meta("PlatformStand", false)
	player.request_humanoid_state(16)
	await step(player, 5)
	check(player.get_runtime_humanoid_state() == 16, "explicit Physics stays active until a script changes state")
	player.request_humanoid_state(8)
	player.remove_meta("bobux_trace_move_direction")
	player.set_lua_position(Vector3.ZERO)
	player.velocity = Vector3.ZERO
	await step(player, 12)
	check(player.get_runtime_humanoid_state() == 8, "ChangeState Running exits passive physics")

	var target := Node3D.new()
	world.add_child(target)
	target.position = Vector3(3, 0, 0)
	player.move_to_part(target.global_position, target)
	target.position.x = 12
	check(player._get_lua_move_target().distance_to(target.global_position) < 0.001, "MoveTo follows the target part local point")
	await step(player, 65)
	check(bool(probe.get_meta("attribute_MoveToReached", false)) and int(probe.get_meta("attribute_MoveToCount", 0)) == 1, "moving MoveTo target completes once")
	player.move_to(Vector3(70, 0, 0))
	player._lua_move_deadline = Time.get_ticks_msec() - 1
	await step(player, 1)
	check(not bool(probe.get_meta("attribute_MoveToReached", true)) and int(probe.get_meta("attribute_MoveToCount", 0)) == 2, "MoveTo timeout reports false once")
	player.move_to(Vector3(70, 0, 0))
	player.set_lua_position(Vector3(0, 0, 0))
	check(player._lua_move_deadline == 0, "root teleport cancels MoveTo")

	h.set_meta("AutoRotate", false)
	player.set_humanoid_walk_speed(32)
	player.velocity = Vector3.ZERO
	var swim_angle: float = player.visuals.rotation.y
	for _frame in 55:
		await physics_frame
		player._run_swimming_movement(1.0 / 60.0, Vector2(0, -1), false)
	check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 28.0) < 0.01, "swimming horizontal speed is 87.5 percent of WalkSpeed")
	check(is_equal_approx(player.visuals.rotation.y, swim_angle), "swimming respects AutoRotate false")
	player.set_humanoid_walk_speed(16)
	player.set_lua_position(Vector3.ZERO)
	player.velocity = Vector3.ZERO
	await step(player, 8)
	var truss := Node3D.new()
	truss.set_meta("roblox_class", "TrussPart")
	world.add_child(truss)
	var truss_body := StaticBody3D.new()
	truss_body.set_meta("_bobux_shape_parts", {0: truss.get_instance_id()})
	var truss_shape := CollisionShape3D.new()
	var truss_box := BoxShape3D.new()
	truss_box.size = Vector3(2, 100, 2)
	truss_shape.shape = truss_box
	truss_body.add_child(truss_shape)
	truss_body.position = Vector3(40, 50, 4)
	world.add_child(truss_body)
	for yaw in [0.0, PI]:
		player._stop_climbing()
		player.set_lua_position(Vector3(40, 0, 2))
		player.camera_pivot.rotation.y = yaw
		player.velocity = Vector3.ZERO
		player.set_humanoid_move(Vector3.BACK)
		await step(player, 30)
		check(player.get_runtime_humanoid_state() == 12 and player.position.y > 3.0 and absf(player.velocity.y - 11.2) < 0.01, "world-space Move climbs at 70 percent independently of camera yaw=" + str(yaw))
	h.set_meta("bobux_state_enabled_12", false)
	player._stop_climbing()
	player.set_lua_position(Vector3(40, 0, 2))
	player.velocity = Vector3.ZERO
	await step(player, 10)
	check(player.get_runtime_humanoid_state() != 12 and player.position.y < 0.1, "disabled Climbing blocks the automatic truss motor")
	h.set_meta("bobux_state_enabled_12", true)
	player.set_humanoid_move(Vector3.ZERO)
	player._stop_climbing()
	var water := Area3D.new()
	water.set_meta("roblox_class", "TerrainWater")
	water.add_to_group("roblox_water")
	water.collision_layer = 4
	water.collision_mask = 0
	var water_shape := CollisionShape3D.new()
	var water_box := BoxShape3D.new()
	water_box.size = Vector3(15, 15, 15)
	water_shape.shape = water_box
	water.add_child(water_shape)
	water.position = Vector3(-40, 5, 0)
	world.add_child(water)
	player.set_lua_position(Vector3(-40, 0, 0))
	player.velocity = Vector3.ZERO
	await step(player, 4)
	check(player.get_runtime_humanoid_state() == 4, "automatic water contact enters Swimming")
	h.set_meta("bobux_state_enabled_4", false)
	await step(player, 4)
	check(player.get_runtime_humanoid_state() != 4 and not player._swimming_active, "disabled Swimming stops the automatic water motor")
	h.set_meta("bobux_state_enabled_4", true)
	water.queue_free()
	await physics_frame
	player.set_lua_position(Vector3.ZERO)
	player.velocity = Vector3.ZERO
	await step(player, 8)

	var seat := Node3D.new()
	seat.set_meta("roblox_class", "Seat")
	world.add_child(seat)
	h.set_meta("bobux_state_enabled_13", false)
	player._enter_seat(seat)
	check(player._seated_part == null, "disabled Seated prevents automatic attachment")
	h.set_meta("bobux_state_enabled_13", true)
	player._enter_seat(seat)
	await create_timer(0.05).timeout
	check(player.get_runtime_humanoid_state() == 13 and int(probe.get_meta("attribute_SeatedCount", 0)) == 1 and bool(probe.get_meta("attribute_SeatedHasPart", false)), "seat enters and emits Seated true with the part once")
	player._leave_seat(false)
	await create_timer(0.05).timeout
	check(int(probe.get_meta("attribute_SeatedCount", 0)) == 2 and not bool(probe.get_meta("attribute_SeatedActive", true)) and not bool(probe.get_meta("attribute_SeatedHasPart", true)), "seat exit emits Seated false nil once")

	h.set_meta("BreakJointsOnDeath", false)
	player._spawn_death_fragments()
	check(player._death_fragment_root == null and player.visuals.visible, "BreakJointsOnDeath false preserves the visual rig")
	h.set_meta("BreakJointsOnDeath", true)
	player._spawn_death_fragments()
	check(is_instance_valid(player._death_fragment_root) and player._death_fragment_root.get_child_count() >= 6, "BreakJointsOnDeath true retains existing fragments")
	player._restore_after_respawn()
	h.set_meta("MaxHealth", 175.25)
	player.apply_authoritative_respawn_position(Vector3.ZERO)
	check(is_equal_approx(player.get_health(), 175.25), "respawn respects a fractional custom MaxHealth")
	var health_proxy = engine.BobuxInstance.wrap(h)
	health_proxy._set(&"MaxHealth", INF)
	health_proxy._set(&"Health", INF)
	await step(player, 4)
	player.take_damage(100.0)
	check(is_inf(float(health_proxy._get(&"Health"))) and is_inf(float(health_proxy._get(&"MaxHealth"))), "infinite logical health survives finite damage and frame synchronization")
	check(is_finite(player.get_health()) and is_finite(player.get_max_health()), "existing HUD getters keep infinite health presentation finite")
	health_proxy._set(&"MaxHealth", 175.25)
	check(is_equal_approx(float(health_proxy._get(&"Health")), 175.25), "reducing MaxHealth clamps an infinite current health")
	check(player.get_node("Visuals/Head").mesh == head, "original Bobux head mesh remains in use")
	check(engine.get_runtime_diagnostics().failed == 0, "no Luau script failures")
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	await process_frame
	engine.release_stopped_script_states()
	print("[humanoid-player] checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
