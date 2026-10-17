extends CharacterBody3D
var current_health := 100.0
func get_health() -> float: return current_health
func set_health(value: float) -> void: current_health = value
func set_lua_position(value: Vector3) -> void: global_position = value
func set_initial_spawn_position(value: Vector3) -> void: global_position = value
func get_max_health() -> float: return 100.0
var move_speed := 16.0
func get_humanoid_walk_speed() -> float: return move_speed
func set_humanoid_walk_speed(value: float) -> void: move_speed = value
