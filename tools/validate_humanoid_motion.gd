extends SceneTree
var PLAYER: PackedScene
const CONFIG = preload("res://scripts/player/humanoid/humanoid_config.tres")
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	print("[motion] ",label,"=",ok)
	if not ok: failures.append(label)
func run():
	PLAYER = load("res://scenes/player/player.tscn")
	check(CONFIG.validate().is_empty() and CONFIG.float_value("WalkSpeed")==16.0,"config loads all values")
	for scale_ in [1.0,0.5]:
		var world=Node3D.new()
		root.add_child(world)
		var floor_=StaticBody3D.new()
		world.add_child(floor_)
		var shape=CollisionShape3D.new()
		var box=BoxShape3D.new()
		box.size=Vector3(100,1,100)*scale_
		shape.shape=box
		floor_.position.y=-0.5*scale_
		floor_.add_child(shape)
		var p=PLAYER.instantiate()
		p.world_stud_scale=scale_
		p.set_meta("bobux_studio_playtest",true)
		p.set_meta("bobux_trace_stand",true)
		p.set_meta("bobux_trace_move_direction",Vector3.ZERO)
		world.add_child(p)
		p.set_physics_process(false)
		for i in 15:
			await physics_frame
			p._run_local_movement(1.0/60)
		print("[motion] resting ",scale_," pos=",p.position," distance=",p._ground_hit_distance," grounded=",p._sample_ground_sensor())
		check(p._sample_ground_sensor() and absf(p.position.y / scale_) < 0.1,"stable floor scale="+str(scale_))
		p.set_meta("bobux_trace_jump",true)
		var peak=0.0
		for i in 65:
			await physics_frame
			p._run_local_movement(1.0/60)
			peak=maxf(peak,p.position.y/scale_)
		print("[motion] jump peak=",peak," land=",p.position.y/scale_)
		# R6 Studio run02 measured 7.485444 studs for JumpPower50/Gravity196.2.
		check(absf(peak - 7.48544430732727) / 7.48544430732727 <= 0.1 and p._sample_ground_sensor(),"calibrated jump and landing scale="+str(scale_))
		p.set_meta("bobux_trace_move_direction",Vector3.RIGHT)
		for i in 30:
			await physics_frame
			p._run_local_movement(1.0/60)
		check(absf(p.velocity.x/scale_-16)<0.01,"walk speed in studs scale="+str(scale_))
		p.set_meta("bobux_trace_move_direction",Vector3.ZERO)
		for i in 20:
			await physics_frame
			p._run_local_movement(1.0/60)
		check(absf(p.velocity.x)<0.01,"braking scale="+str(scale_))
		var step := StaticBody3D.new()
		var step_shape := CollisionShape3D.new()
		var step_box := BoxShape3D.new()
		step_box.size = Vector3(6,0.6,8)*scale_
		step_shape.shape = step_box
		step.add_child(step_shape)
		world.add_child(step)
		step.position = Vector3(5,0.3,0)*scale_
		p.position = Vector3.ZERO
		p.reset_trace_state()
		p.set_meta("bobux_trace_move_direction",Vector3.RIGHT)
		var minimum_on_step := INF
		for i in 28:
			await physics_frame
			p._run_local_movement(1.0/60)
			if p.position.x/scale_ > 2.5: minimum_on_step = minf(minimum_on_step,p.position.y/scale_)
		check(is_finite(minimum_on_step) and minimum_on_step>0.55,"raised ground never buries feet scale="+str(scale_))
		p._reset_local_camera_anchor(p.global_position)
		p._update_local_camera_rig_render_phase(0.0)
		check(absf((p.camera_pivot.global_position.y-p.global_position.y)/scale_-4.0)<0.01,"camera target follows avatar scale="+str(scale_))
		step.queue_free()
		await physics_frame
		var ledge := StaticBody3D.new()
		var ledge_shape := CollisionShape3D.new()
		var ledge_box := BoxShape3D.new()
		ledge_box.size = Vector3(8, 8, 12) * scale_
		ledge_shape.shape = ledge_box
		ledge.add_child(ledge_shape)
		world.add_child(ledge)
		ledge.position = Vector3(8, 4, 0) * scale_
		p.position = Vector3.ZERO
		p.reset_trace_state()
		p.set_meta("bobux_trace_move_direction", Vector3.RIGHT)
		p.set_meta("bobux_trace_jump", true)
		var buried := false
		for i in 65:
			await physics_frame
			p._run_local_movement(1.0 / 60)
			if p.position.x / scale_ > 3.1 and p.position.y / scale_ < 7.95:
				if not buried: print("[motion] ledge penetration frame=", i, " position=", p.position / scale_, " velocity=", p.velocity / scale_)
				buried = true
		check(not buried, "jumping into a tall ledge cannot bury legs scale="+str(scale_))
		ledge.queue_free()
		await physics_frame
		p.set_meta("bobux_trace_move_direction", Vector3.ZERO)
		p.position = Vector3(0, 2.6, 0) * scale_
		p.velocity = Vector3(0, -240, 0) * scale_
		p._integrate_character_motion(1.0 / 60)
		check(p.position.y / scale_ > -0.02, "continuous full-sole landing at terminal speed scale="+str(scale_))
		box.size=Vector3(1,1,20)*scale_
		p.set_lua_position(Vector3(0, -1.2, 0) * scale_)
		p.velocity = Vector3.ZERO
		for i in 4:
			await physics_frame
			p._run_local_movement(1.0/60)
		check(p.position.y >= -0.01 * scale_, "spawn recovers buried feet scale="+str(scale_))
		p.position=Vector3(0.65,0,0)*scale_
		p.velocity=Vector3.ZERO
		await physics_frame
		await physics_frame
		check(p._sample_ground_sensor(),"full sole supports edge/beam scale="+str(scale_))
		p.position.x=1.6*scale_
		await physics_frame
		check(not p._sample_ground_sensor(),"leaving full sole starts falling scale="+str(scale_))
		world.queue_free()
		await process_frame
	print("[motion] failures=",failures)
	quit(0 if failures.is_empty() else 1)
