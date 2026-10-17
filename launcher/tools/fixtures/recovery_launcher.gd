extends "res://tools/fixtures/download_launcher.gd"

var restart_calls := 0

func _run_update_flow() -> void:
	if not _update_flow_running:
		restart_calls += 1
