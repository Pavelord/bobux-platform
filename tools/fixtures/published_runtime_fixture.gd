extends "res://scripts/main/main.gd"

# Exercise the real published map builder without a production room or login.
# The disaster probe starts only the selected archived controller afterwards.
func _ready() -> void:
	_rng.randomize()
	_build_runtime_hud()
	_ensure_runtime_inventory_controller()
	_ensure_mode_music_player()
	set_process(false)

func _get_runtime_local_peer_id() -> int: return 1
func _peer_matches_effective_local_room(_peer_id: int, _known_peer_room_id: String = "") -> bool: return true
func _load_manifest_scripts_into_map(_manifest: Dictionary, _refs: Dictionary, _target: Node3D, _origin: Vector3, _room: String) -> void: pass
