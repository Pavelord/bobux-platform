extends "res://tools/fixtures/replication_test_auth.gd"
signal checked(result: Dictionary)
signal finished(peer: int, ok: bool)
var check_actor: Callable

@rpc("any_peer", "call_remote", "reliable")
func check(stage: String) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	result.rpc_id(peer, check_actor.call(peer, stage))

@rpc("authority", "call_remote", "reliable")
func result(value: Dictionary) -> void: checked.emit(value)

@rpc("any_peer", "call_remote", "reliable")
func complete(ok: bool) -> void:
	if multiplayer.is_server(): finished.emit(multiplayer.get_remote_sender_id(), ok)
