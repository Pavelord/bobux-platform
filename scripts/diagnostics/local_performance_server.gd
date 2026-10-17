extends SceneTree
## Local benchmark server: no registry heartbeat, credentials or deployment.
func _initialize() -> void:
	var port := 17860
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="): port = argument.trim_prefix("--port=").to_int()
	root.get_node("GameState").configure_dedicated_server(port, "")
	change_scene_to_file("res://scenes/main/main.tscn")
