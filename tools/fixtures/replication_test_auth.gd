extends Node
signal accepted
signal peer_joined(peer: int, room: String)

@rpc("any_peer", "call_remote", "reliable")
func join(room: String) -> void:
	if not multiplayer.is_server() or room not in ["a", "b"]: return
	var peer := multiplayer.get_remote_sender_id()
	get_node("/root/NetworkManager")._peer_room_ids[peer] = room
	peer_joined.emit(peer, room)
	confirm.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func confirm() -> void:
	accepted.emit()
