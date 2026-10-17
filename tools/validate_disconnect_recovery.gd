extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main_scene)
	current_scene = main_scene
	await process_frame
	main_scene._on_server_disconnected()
	var error_queued: bool = not str(root.get_node("GameState").last_network_error).is_empty()
	for _frame in range(20):
		await process_frame
	var lobby: Node = current_scene
	var returned_to_lobby: bool = lobby != main_scene and lobby != null
	var network_error_consumed: bool = str(root.get_node("GameState").last_network_error).is_empty()
	var ok: bool = returned_to_lobby and error_queued and network_error_consumed
	print("[disconnect_recovery] returned_to_lobby=", returned_to_lobby, " error_queued=", error_queued, " network_error_consumed=", network_error_consumed, " PASS=", ok)
	quit(0 if ok else 1)
