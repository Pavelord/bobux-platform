extends "res://scripts/main/main.gd"

var simulate_mobile: bool = false
var safe_insets := Vector3(12, 12, 12)
func _ready() -> void: _build_runtime_hud()
func _process(_delta: float) -> void: pass
func _exit_tree() -> void:
	super._exit_tree()
func _get_local_player() -> CharacterBody3D:
	return get_node_or_null("HudTestPlayer") as CharacterBody3D
func _is_mobile_runtime_platform() -> bool: return simulate_mobile
func _runtime_hud_safe_insets(_viewport_size: Vector2) -> Vector3: return safe_insets
