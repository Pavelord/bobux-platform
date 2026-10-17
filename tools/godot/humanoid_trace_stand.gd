extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HUMANOID_CONFIG = preload("res://scripts/player/humanoid/humanoid_config.tres")
const CHARACTER_COLLIDER = preload("res://scripts/player/humanoid/character_collider.gd")
const SCENARIO_PATH: String = "res://tools/scenarios.json"

var _scenario_data: Dictionary = {}
var _player: CharacterBody3D
var _trace_rows: Array[PackedStringArray] = []
var _scenario_index: int = -1
var _command_index: int = 0
var _ticks_in_command: int = 0
var _scenario_tick: int = 0
var _scenario_active: bool = false
var _reset_tick_pending: bool = false
var _trace_directory: String = ""
var _hrp_height_above_body_origin: float = 0.0
var _last_support_body: Node3D
var _last_move_direction: Vector3 = Vector3.ZERO
var _pending_edge_overhang: String = ""


func _ready() -> void:
	process_physics_priority = -100
	_trace_directory = ProjectSettings.globalize_path("user://roblox_humanoid_traces/godot")
	_hrp_height_above_body_origin = CHARACTER_COLLIDER.resolve_hrp_height(HUMANOID_CONFIG)
	DirAccess.make_dir_recursive_absolute(_trace_directory)
	var file := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read " + SCENARIO_PATH)
		get_tree().quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid scenario JSON")
		get_tree().quit(1)
		return
	_scenario_data = parsed
	_build_course()
	_spawn_player()
	call_deferred("_begin_scenario", 0)


func _build_course() -> void:
	var course_root := Node3D.new()
	course_root.name = "R6TraceCourse"
	add_child(course_root)
	for fixture_variant in _scenario_data.get("course", {}).get("parts", []):
		var fixture: Dictionary = fixture_variant
		var body := StaticBody3D.new()
		body.name = str(fixture.get("name", "Fixture"))
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("roblox_class", "TrussPart" if str(fixture.get("kind", "Part")) == "TrussPart" else "Part")
		if str(fixture.get("kind", "Part")) == "TrussPart":
			body.set_meta("shape_type", "Truss")
		var position := _vector3(fixture.get("position", [0.0, 0.0, 0.0]))
		var dimensions := _vector3(fixture.get("size", [1.0, 1.0, 1.0]))
		body.set_meta("trace_fixture_size", dimensions)
		var rotation := _vector3(fixture.get("rotation_deg", [0.0, 0.0, 0.0]))
		body.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z))), position)
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = dimensions
		collider.shape = box
		body.add_child(collider)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = dimensions
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.48, 0.56, 0.68) if str(fixture.get("kind", "Part")) != "TrussPart" else Color(0.78, 0.52, 0.18)
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
		course_root.add_child(body)


func _spawn_player() -> void:
	var first_spawn := _vector3(_scenario_data["scenarios"][0]["spawn"])
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	_player.set_meta("bobux_studio_playtest", true)
	_player.set_meta("bobux_trace_stand", true)
	_player.set_meta("bobux_world_collision_mask", 1)
	_player.position = first_spawn - Vector3.UP * _hrp_height_above_body_origin
	_player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	_player.set_meta("bobux_trace_climb_axis", 0.0)
	_player.set_meta("bobux_trace_jump", false)
	add_child(_player)


func _begin_scenario(index: int) -> void:
	if index >= _scenario_data.get("scenarios", []).size():
		print("R6 Godot traces: " + _trace_directory)
		get_tree().quit()
		return
	_scenario_index = index
	var scenario: Dictionary = _scenario_data["scenarios"][index]
	var hrp_spawn := _vector3(scenario["spawn"])
	_player.global_position = hrp_spawn - Vector3.UP * _hrp_height_above_body_origin
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	(_player.get_node("CameraPivot") as Node3D).rotation = Vector3.ZERO
	_player.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	_player.set_meta("bobux_trace_climb_axis", 0.0)
	_player.set_meta("bobux_trace_jump", false)
	_player.reset_physics_interpolation()
	_player.call("reset_trace_state")
	_trace_rows.clear()
	_command_index = 0
	_ticks_in_command = 0
	_scenario_tick = 0
	_scenario_active = false
	_reset_tick_pending = true
	_last_support_body = null
	_last_move_direction = Vector3.ZERO
	_pending_edge_overhang = ""
	print("R6 Godot scenario: " + str(scenario.get("name", "")))


func _physics_process(_delta: float) -> void:
	if _reset_tick_pending:
		_reset_tick_pending = false
		call_deferred("_activate_scenario")
		return
	if not _scenario_active or _player == null:
		return
	var scenario: Dictionary = _scenario_data["scenarios"][_scenario_index]
	var commands: Array = scenario.get("commands", [])
	if _command_index >= commands.size():
		_scenario_active = false
		call_deferred("_finish_scenario")
		return
	var command: Dictionary = commands[_command_index]
	var move_direction := _vector3(command.get("move", [0.0, 0.0, 0.0]))
	var jump_pressed := bool(command.get("jump", false)) and _ticks_in_command == 0
	var climb_axis := float(command.get("climb_axis", 0.0))
	var capture := {
		"scenario_tick": _scenario_tick,
		"move_direction": Vector3(move_direction.x, climb_axis, move_direction.z),
		"jump": jump_pressed,
	}
	# Roblox RunService.Stepped samples before physics. Capture this Godot tick
	# before the player callback runs, then apply this tick's command.
	_capture_trace_row(capture)
	_player.set_meta("bobux_trace_move_direction", move_direction)
	_player.set_meta("bobux_trace_climb_axis", climb_axis)
	_player.set_meta("bobux_trace_jump", jump_pressed)
	_scenario_tick += 1
	_ticks_in_command += 1
	if _ticks_in_command >= int(command.get("ticks", 0)):
		_command_index += 1
		_ticks_in_command = 0
		if _command_index >= commands.size():
			_scenario_active = false
			call_deferred("_finish_scenario")


func _activate_scenario() -> void:
	_scenario_active = true


func _capture_trace_row(capture: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var hrp_position := _player.global_position + Vector3.UP * _hrp_height_above_body_origin
	var velocity: Vector3 = _player.velocity
	var humanoid := _player.get_node_or_null("Humanoid")
	var floor_material := str(humanoid.get_meta("FloorMaterial", "Air")) if humanoid != null else "Air"
	var state_name := str(_player.call("get_trace_state_name"))
	var move: Vector3 = capture["move_direction"]
	var support_part: Variant = _player.call("get_trace_support_part")
	if floor_material != "Air":
		if support_part is Node3D:
			_last_support_body = support_part as Node3D
		if move.length_squared() > 0.0:
			_last_move_direction = move
		_pending_edge_overhang = ""
	elif _pending_edge_overhang.is_empty() and state_name in ["Freefall", "FallingDown"]:
		_pending_edge_overhang = _edge_overhang_estimate(_last_support_body, _last_move_direction)
	var hz := float(HUMANOID_CONFIG.value("PhysicsFrequencyHz"))
	var row := PackedStringArray([
		_number(float(capture["scenario_tick"]) / hz), _number(1.0 / hz),
		_number(hrp_position.x), _number(hrp_position.y), _number(hrp_position.z),
		_number(velocity.x), _number(velocity.y), _number(velocity.z),
		_csv(state_name), _csv(floor_material), _number(move.x), _number(move.y), _number(move.z),
		"true" if bool(capture["jump"]) else "false",
		_csv(_pending_edge_overhang),
	])
	_trace_rows.append(row)


func _edge_overhang_estimate(support: Node3D, move_direction: Vector3) -> String:
	if not is_instance_valid(support) or move_direction.length_squared() <= 0.0:
		return ""
	var platform_size: Vector3 = support.get_meta("trace_fixture_size", Vector3.ZERO)
	if platform_size == Vector3.ZERO:
		return ""
	var local_direction := support.global_basis.inverse() * move_direction.normalized()
	var maximum := 0.0
	var found := false
	for node_path in ["CollisionLeftLeg", "CollisionRightLeg"]:
		var foot := _player.get_node_or_null(node_path) as CollisionShape3D
		if foot == null or not foot.shape is BoxShape3D:
			continue
		var box := foot.shape as BoxShape3D
		var local_center := support.to_local(foot.global_position)
		var relative_basis := support.global_basis.inverse() * foot.global_basis
		var extent_x := absf(relative_basis.x.x) * box.size.x * 0.5 + absf(relative_basis.y.x) * box.size.y * 0.5 + absf(relative_basis.z.x) * box.size.z * 0.5
		var extent_z := absf(relative_basis.x.z) * box.size.x * 0.5 + absf(relative_basis.y.z) * box.size.y * 0.5 + absf(relative_basis.z.z) * box.size.z * 0.5
		if absf(local_direction.x) > 0.001:
			maximum = maxf(maximum, signf(local_direction.x) * (local_center.x + signf(local_direction.x) * extent_x) - platform_size.x * 0.5)
			found = true
		if absf(local_direction.z) > 0.001:
			maximum = maxf(maximum, signf(local_direction.z) * (local_center.z + signf(local_direction.z) * extent_z) - platform_size.z * 0.5)
			found = true
	return _number(maximum) if found else ""


func _finish_scenario() -> void:
	var scenario: Dictionary = _scenario_data["scenarios"][_scenario_index]
	var filename := str(scenario.get("name", "scenario")) + ".csv"
	var path := _trace_directory.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write trace: " + path)
		get_tree().quit(1)
		return
	file.store_line("t,dt,px,py,pz,vx,vy,vz,state,floor_material,mx,my,mz,jump,edge_overhang_studs")
	for row in _trace_rows:
		file.store_line(",".join(row))
	file.close()
	call_deferred("_begin_scenario", _scenario_index + 1)


func _vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _number(value: float) -> String:
	return "%.9f" % value


func _csv(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\"" if value.contains(",") or value.contains("\"") or value.contains("\n") else value
