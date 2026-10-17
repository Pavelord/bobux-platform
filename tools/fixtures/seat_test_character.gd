extends "res://scripts/player/player.gd"
## Uses the production avatar, seat methods and Humanoid contract. Movement
## and account UI are suppressed so the fixture can control test positions.
var fixture_input := Vector2.ZERO

func _ready() -> void:
	ensure_roblox_character_contract()
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)

func _process(_delta: float) -> void: pass

func _physics_process(_delta: float) -> void:
	if get_node("/root/ImportedPlaceNetwork").networked() and is_multiplayer_authority() and is_instance_valid(_seated_part):
		_update_seated_movement(false, fixture_input)

func _exit_tree() -> void: pass
