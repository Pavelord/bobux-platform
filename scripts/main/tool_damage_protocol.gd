extends Node
## Optional gameplay RPCs must not renumber Main's join/respawn protocol.
@rpc("any_peer", "reliable")
func request_damage(target_peer_id: int, damage_amount: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server(): return
	get_parent()._validate_and_apply_lua_tool_damage(multiplayer.get_remote_sender_id(), target_peer_id, damage_amount)
