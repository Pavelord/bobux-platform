extends "res://scripts/player/player.gd"

static var source_import_count: int = 0
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
func _exit_tree() -> void: pass
func _import_avatar_attachment_source(local_path: String) -> Node:
	source_import_count += 1
	return super._import_avatar_attachment_source(local_path)
