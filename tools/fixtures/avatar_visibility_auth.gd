extends Node
signal accepted
signal peer_joined(peer: int, room: String)
signal observed(peer: int, phase: int, passed: bool)
signal check_requested(phase: int, assignments: Dictionary)
signal finished(passed: bool)

@rpc("any_peer", "call_remote", "reliable")
func join(room: String) -> void:
	if not multiplayer.is_server() or room not in ["a", "b"]: return
	var peer := multiplayer.get_remote_sender_id()
	get_node("/root/NetworkManager")._peer_room_ids[peer] = room
	peer_joined.emit(peer, room)
	confirm.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func confirm() -> void: accepted.emit()

@rpc("authority", "call_remote", "reliable")
func check(phase: int, assignments: Dictionary) -> void:
	get_node("/root/NetworkManager")._peer_room_ids = assignments.duplicate()
	get_node("/root/NetworkManager").room_summaries_updated.emit([])
	check_requested.emit(phase, assignments)

@rpc("any_peer", "call_remote", "reliable")
func report(phase: int, passed: bool) -> void:
	if multiplayer.is_server(): observed.emit(multiplayer.get_remote_sender_id(), phase, passed)

@rpc("authority", "call_remote", "reliable")
func finish(passed: bool) -> void: finished.emit(passed)
