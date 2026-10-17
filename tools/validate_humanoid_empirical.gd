extends SceneTree

## Runs the real player controller and collision world against signed-off Studio
## evidence. No expected constants replace absent or failed Roblox experiments.
const DOCUMENT := "res://docs/ROBLOX_HUMANOID_EMPIRICAL_RU.md"
const REPORT := "res://.codex-tmp/performance/humanoid-empirical-calibration.json"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const STATE_MACHINE = preload("res://scripts/player/humanoid/state_machine.gd")
const STEP := 1.0 / 60.0
var evidence: Dictionary = {}
var results: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var manifest: Dictionary = {}
var tolerance := 0.1
var world: Node3D
var player: CharacterBody3D
var humanoid: Node
var clock_sim := 0.0
var frame_index := 0
var state_previous := ""
var state_events: Array[Dictionary] = []
var case_name := ""


func _initialize() -> void:
	run.call_deferred()


func _block(reason: String) -> void:
	results.append({"case": case_name, "metric": "evidence_or_fixture", "status": "blocked", "required": true, "reason": reason})
	print("[humanoid-calibration] BLOCKED ", reason)


func _load_evidence() -> bool:
	if not FileAccess.file_exists(DOCUMENT):
		_block("Empirical Markdown is absent; Roblox data must be harvested first.")
		return false
	var pattern := RegEx.new()
	pattern.compile("```json\\s*(\\{[\\s\\S]*?\\})\\s*```")
	for match_ in pattern.search_all(FileAccess.get_file_as_string(DOCUMENT)):
		var decoded: Variant = JSON.parse_string(match_.get_string(1))
		if decoded is Dictionary and decoded.get("schema") == 1 and decoded.has("evidence"):
			manifest = decoded
			break
	if manifest.is_empty():
		_block("Markdown lacks a schema 1 evidence/hash JSON block.")
		return false
	var path := str(manifest.get("evidence", ""))
	var wanted_sha := str(manifest.get("sha256", "")).to_lower()
	if not path.begins_with("res://") or wanted_sha.length() != 64 or not FileAccess.file_exists(path):
		_block("Evidence path/hash is absent or invalid.")
		return false
	if FileAccess.get_sha256(path).to_lower() != wanted_sha:
		_block("Evidence SHA-256 differs from the reviewed Markdown manifest.")
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not decoded is Dictionary or decoded.get("source") != "roblox_studio_black_box" or decoded.get("schema") != 1:
		_block("Input is not a structured Roblox Studio black-box result.")
		return false
	evidence = decoded
	tolerance = float(manifest.get("tolerance", 0.1))
	if tolerance <= 0.0 or tolerance > 0.1:
		_block("Calibration tolerance must be greater than zero and at most 10%.")
		return false
	if evidence.get("cases", []).is_empty():
		_block("Evidence has no measured cases; truncated or unfinished logs are insufficient.")
		return false
	return true


func _body(parent: Node3D, label: String, position_: Vector3, size_: Vector3, class_: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position_
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("roblox_class", class_)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _fixture() -> bool:
	world = Node3D.new()
	world.name = "HumanoidEmpiricalWorkspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("Gravity", 196.2)
	root.add_child(world)
	_body(world, "Baseplate", Vector3(0, -0.5, 0), Vector3(280, 1, 280), "Part")
	var truss := _body(world, "ExperimentTruss", Vector3(40, 24, 0), Vector3(2, 48, 2), "TrussPart")
	truss.add_to_group("roblox_climbable")
	var water := Area3D.new()
	water.name = "TerrainWater"
	water.position = Vector3(-64, 16, 0)
	water.collision_layer = 4
	water.collision_mask = 0
	water.set_meta("roblox_class", "TerrainWater")
	water.add_to_group("roblox_water")
	var water_collision := CollisionShape3D.new()
	var water_shape := BoxShape3D.new()
	water_shape.size = Vector3(64, 32, 64)
	water_collision.shape = water_shape
	water.add_child(water_collision)
	world.add_child(water)
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_block("The real Bobux player scene cannot load.")
		return false
	player = packed.instantiate() as CharacterBody3D
	if player == null:
		_block("Player root is not CharacterBody3D.")
		return false
	player.set("world_stud_scale", 1.0)
	player.set_meta("bobux_studio_playtest", true)
	player.set_meta("bobux_trace_stand", true)
	player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	player.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	world.add_child(player)
	player.set_physics_process(false)
	humanoid = player.get_node_or_null("Humanoid")
	if humanoid == null or not player.has_method("_run_local_movement"):
		_block("Real Humanoid/controller APIs are unavailable.")
		return false
	# A fixed camera is deliberately retained for Move(false) climbing checks.
	# Rotating it to make a flawed world-space controller pass would hide a bug.
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot != null:
		pivot.rotation.y = 0.0
	return true


func _state() -> String:
	# GetState's physical controller ID is authoritative. Legacy animation
	# metadata can be refreshed only when the animation pose changes.
	return STATE_MACHINE.state_name(int(player.call("get_runtime_humanoid_state"))) if is_instance_valid(player) else "Missing"


func _step() -> Dictionary:
	await physics_frame
	player.call("_run_local_movement", STEP)
	frame_index += 1
	clock_sim += STEP
	var current := _state()
	if current != state_previous:
		state_events.append({"frame": frame_index, "sim_s": clock_sim, "old": state_previous, "new": current,
			"position_y": player.position.y, "velocity_y": player.velocity.y})
		state_previous = current
	return {"frame": frame_index, "sim_s": clock_sim, "state": current, "position_y": player.position.y,
		"velocity": [player.velocity.x, player.velocity.y, player.velocity.z], "grounded": player.call("_sample_ground_sensor")}


func _reset(position_: Vector3, gravity_: float) -> void:
	world.set_meta("Gravity", gravity_)
	player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	player.set_meta("bobux_trace_jump", false)
	player.set_meta("bobux_trace_climb_axis", 0.0)
	player.position = position_
	player.velocity = Vector3.ZERO
	player.call("reset_trace_state")
	state_events.clear()
	state_previous = _state()
	await physics_frame


func _settle() -> bool:
	var grounded_count := 0
	var last_sample: Dictionary = {}
	for _index in range(360):
		var sample: Dictionary = await _step()
		last_sample = sample
		if bool(sample.grounded) and absf(player.velocity.y) < 0.15 and sample.state != "Landed":
			grounded_count += 1
		else:
			grounded_count = 0
		if grounded_count >= 24:
			return true
	print("[humanoid-calibration] settle timeout sample=", last_sample, " position=", player.position, " velocity=", player.velocity,
		" ground_distance=", player.get("_ground_hit_distance"), " collision_mask=", player.collision_mask)
	return false


func _compare(metric: String, observed: float, reference: Variant, details: Dictionary = {}, required := true) -> void:
	var record := {"case": case_name, "metric": metric, "observed": observed, "reference": reference,
		"tolerance": tolerance, "required": required, "details": details}
	if not (reference is int or reference is float) or not is_finite(float(reference)):
		record.status = "blocked" if required else "skip"
		record.reason = "No valid measured Roblox number is present."
	elif not is_finite(observed):
		record.status = "fail"
		record.reason = "The Bobux physical measurement is missing/nonfinite."
	else:
		var target := float(reference)
		var relative_error := absf(observed-target) / maxf(absf(target), 0.000001)
		record.relative_error = relative_error
		record.status = "pass" if relative_error <= tolerance else "fail"
	results.append(record)
	print("[humanoid-calibration] ", case_name, " ", metric, " ", record.status, " observed=", observed, " reference=", reference)


func _skip(metric: String, reason: String, required := false) -> void:
	results.append({"case": case_name, "metric": metric, "status": "blocked" if required else "skip", "required": required, "reason": reason})


func _jump(case_: Dictionary) -> void:
	var params: Dictionary = case_.get("parameters", {})
	var gravity_ := float(params.get("gravity", NAN))
	if not is_finite(gravity_) or gravity_ <= 0.0:
		_block("Jump case lacks a positive measured Workspace.Gravity.")
		return
	await _reset(Vector3(0, 1, 0), gravity_)
	if not await _settle():
		_block("Bobux fixture did not settle before jump.")
		return
	humanoid.set_meta("UseJumpPower", bool(params.get("UseJumpPower", true)))
	humanoid.set_meta("JumpHeight", float(params.get("JumpHeight", 0.0)))
	player.call("set_humanoid_jump_power", float(params.get("JumpPower", 0.0)))
	var start_y := player.position.y
	var peak_y := start_y
	var max_velocity := -INF
	var first_post: Dictionary = {}
	var airborne := false
	var returned := false
	state_events.clear()
	player.set_meta("bobux_trace_jump", true)
	for _index in range(600):
		var sample: Dictionary = await _step()
		if first_post.is_empty():
			first_post = sample
		peak_y = maxf(peak_y, player.position.y)
		max_velocity = maxf(max_velocity, player.velocity.y)
		if not bool(sample.grounded) or player.position.y > start_y+0.1:
			airborne = true
		if airborne and bool(sample.grounded) and sample.state != "Landed":
			returned = true
			break
	var observation := {"name": case_name, "type": "jump", "parameters": params, "start_y": start_y,
		"apex_y": peak_y, "observed_apex_height": peak_y-start_y, "max_observed_vy": max_velocity,
		"first_post": first_post, "landed_then_returned": returned, "states": state_events.duplicate(true), "dt_sim_s": STEP}
	observations.append(observation)
	if not airborne or not returned:
		_block("Bobux jump did not leave the floor and return within 10 simulated seconds.")
	_compare("physical_apex_height_studs", peak_y-start_y, case_.get("observed_apex_height"), {"dt_sim_s": STEP})
	_compare("max_observed_vertical_velocity_studs_per_second", max_velocity, case_.get("max_observed_vy"), {
		"sample_kind": "maximum publicly observed velocity, not an exact intra-step impulse", "dt_sim_s": STEP})
	var roblox_first: Dictionary = case_.get("first_post_simulation", {})
	var roblox_v: Array = roblox_first.get("velocity", [])
	if roblox_v.size() >= 2 and float(roblox_v[1]) > 0.1 and first_post.has("velocity"):
		_compare("first_post_vertical_velocity_studs_per_second", float(first_post.velocity[1]), float(roblox_v[1]), {
			"bobux_dt_sim_s": STEP, "roblox_dt_sim_s": roblox_first.get("dt_sim_s"),
			"callback_phase_limitation": "Both are frame samples; the native impulse may happen between callbacks."}, false)
	else:
		_skip("first_post_vertical_velocity_studs_per_second", "Roblox first PostSimulation precedes the jump impulse or is missing; compare apex/max observed velocity instead.")


func _drop(case_: Dictionary) -> void:
	var params: Dictionary = case_.get("parameters", {})
	var gravity_ := float(params.get("gravity", NAN))
	var height := float(params.get("requested_root_height_above_standing", NAN))
	if not is_finite(height) or height <= 0.0 or not is_finite(gravity_) or gravity_ <= 0.0:
		_block("Drop lacks a positive measured height/gravity.")
		return
	await _reset(Vector3(0, 1, 0), gravity_)
	if not await _settle():
		_block("Bobux fixture did not settle before drop.")
		return
	var grounded_y := player.position.y
	await _reset(Vector3(0, grounded_y+height, 0), gravity_)
	var landed_time := -1.0
	var exit_time := -1.0
	var landed_frame := -1
	for _index in range(480):
		var sample: Dictionary = await _step()
		if sample.state == "Landed" and landed_time < 0.0:
			landed_time = clock_sim
			landed_frame = frame_index
		elif landed_time >= 0.0 and sample.state != "Landed":
			exit_time = clock_sim
			break
	var duration := exit_time-landed_time if landed_time >= 0.0 and exit_time >= landed_time else NAN
	observations.append({"name": case_name, "type": "drop", "parameters": params, "grounded_y": grounded_y,
		"landed_sim_duration": duration if is_finite(duration) else null,
		"landed_frame": landed_frame, "states": state_events.duplicate(true), "dt_sim_s": STEP})
	_compare("landed_sim_duration_seconds", duration, case_.get("landed_sim_duration"), {
		"dt_sim_s": STEP, "roblox_wall_duration_s": case_.get("landed_wall_duration"),
		"sampling_limitation": "Frame-quantized observations; wall scheduling is not substituted for simulation time."})


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return NAN
	values.sort()
	var middle := values.size()/2
	return (values[middle-1]+values[middle])*0.5 if values.size()%2 == 0 else values[middle]


func _locomotion(case_: Dictionary) -> void:
	var params: Dictionary = case_.get("parameters", {})
	var kind := str(params.get("type", ""))
	var desired_state := "Climbing" if kind == "climb" else "Swimming"
	var gravity_ := float(params.get("gravity", NAN))
	var speed := float(params.get("WalkSpeed", NAN))
	if not is_finite(gravity_) or not is_finite(speed) or speed <= 0.0:
		_block("Locomotion case lacks measured gravity/WalkSpeed.")
		return
	var direction_array: Array = params.get("input", [])
	if direction_array.size() != 3:
		_block("World-space Move vector missing.")
		return
	var direction := Vector3(float(direction_array[0]), float(direction_array[1]), float(direction_array[2]))
	var position_ := Vector3(40,1,-4) if kind == "climb" else Vector3(-80,13,0)
	await _reset(position_, gravity_)
	if kind == "climb" and not await _settle():
		_block("Bobux fixture did not settle before Truss approach.")
		return
	player.call("set_humanoid_walk_speed", speed)
	player.set_meta("bobux_trace_move_direction", direction)
	var samples: Array[float] = []
	var entry_time := -1.0
	var start_time := clock_sim
	var state_frame_count := 0
	for _index in range(420):
		var sample: Dictionary = await _step()
		if sample.state == desired_state:
			if entry_time < 0.0:
				entry_time = clock_sim
			state_frame_count += 1
			if clock_sim-start_time >= float(params.get("warmup_s",0.5)):
				var observed := absf(player.velocity.y) if str(params.get("component", "magnitude")) == "vertical" else player.velocity.length()
				samples.append(observed)
		if entry_time >= 0.0 and clock_sim-entry_time >= 2.0:
			break
	player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	var measured := _median(samples)
	observations.append({"name": case_name, "type": kind, "parameters": params, "speed_median": measured if is_finite(measured) else null,
		"state_frame_count": state_frame_count, "warm_sample_count": samples.size(), "auto_entered_state": entry_time >= 0.0,
		"states": state_events.duplicate(true), "dt_sim_s": STEP, "camera_yaw": 0.0, "relativeToCamera": false})
	if samples.is_empty():
		_block("Bobux did not naturally enter " + desired_state + " with usable motion samples.")
	_compare("observed_%s_speed_studs_per_second" % str(params.get("component", "magnitude")), measured,
		case_.get("observed_speed_median"), {"component": params.get("component"), "WalkSpeed": speed, "world_move": direction_array})


func run() -> void:
	if not _load_evidence():
		_finish()
		return
	if not _fixture():
		_finish()
		return
	var selected_case := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			selected_case = argument.trim_prefix("--case=")
	for value in evidence.get("cases", []):
		if not value is Dictionary:
			continue
		var case_: Dictionary = value
		case_name = str(case_.get("name", "unnamed"))
		if not selected_case.is_empty() and case_name != selected_case:
			continue
		if case_.get("status") != "measured":
			_skip("native_case", "The genuine Roblox experiment was " + str(case_.get("status", "missing")) + "; no expected value substituted.", true)
			continue
		match str(case_.get("parameters", {}).get("type", "")):
			"jump":
				await _jump(case_)
			"drop":
				await _drop(case_)
			"climb", "swim":
				await _locomotion(case_)
			_:
				_skip("unknown_case_type", "No physical comparison implemented for this case type.", true)
	if is_instance_valid(world):
		world.queue_free()
		for _frame in range(4):
			await process_frame
	_finish()


func _finish() -> void:
	var passed := 0
	var failed := 0
	var skipped := 0
	var blocked := 0
	for result in results:
		match str(result.status):
			"pass": passed += 1
			"fail": failed += 1
			"skip": skipped += 1
			"blocked": blocked += 1
	var status := "blocked" if blocked > 0 else "fail" if failed > 0 else "pass_with_explicit_skips" if skipped > 0 else "pass"
	var report := {"schema": 1, "status": status, "tolerance": tolerance, "document": DOCUMENT, "evidence_manifest": manifest,
		"native_engine_version": evidence.get("engine", {}).get("engine_version"), "native_run_id": evidence.get("run_id"),
		"godot_version": Engine.get_version_info(), "bobux_fixed_dt_seconds": STEP,
		"pass_count": passed, "fail_count": failed, "skip_count": skipped, "blocked_count": blocked,
		"results": results, "bobux_physical_observations": observations,
		"limitations": ["Exact intra-step Roblox jump impulse is unobservable through the public frame callbacks.",
			"Avatar root height is a fixed offset; physical apex compares displacement, not different absolute origins.",
			"No missing/failed native number is replaced with a theoretical value or a permissive expected range.",
			"Landed durations are sampled simulation time; finite frame quantization is explicitly retained."]}
	var output_path := ProjectSettings.globalize_path(REPORT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"\t")+"\n")
		output.close()
	else:
		push_error("Could not save empirical calibration report: " + output_path)
		quit(2)
		return
	print("[humanoid-calibration] RESULT ", status, " pass=", passed, " fail=", failed, " skip=", skipped, " blocked=", blocked)
	quit(2 if blocked > 0 else 1 if failed > 0 else 0)
