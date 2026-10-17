extends "res://tools/fixtures/replication_test_auth.gd"

signal positioned
signal finished(peer: int, ok: bool)
var move_actor: Callable

@rpc("any_peer", "call_remote", "reliable")
func position_actor(index: int, in_range: bool) -> void:
	if not multiplayer.is_server() or not move_actor.is_valid(): return
	move_actor.call(multiplayer.get_remote_sender_id(), index, in_range)
	position_confirmed.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func position_confirmed() -> void:
	positioned.emit()

@rpc("any_peer", "call_remote", "reliable")
func complete(ok: bool) -> void:
	if multiplayer.is_server(): finished.emit(multiplayer.get_remote_sender_id(), ok)
