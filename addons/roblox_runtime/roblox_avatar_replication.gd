extends RefCounted
## Spawn visibility belongs to the server, while movement belongs to the player.
## A filter on an owner-authority synchronizer cannot restrict server spawns.

static func configure_spawn_visibility(player: Node) -> MultiplayerSynchronizer:
	var visibility := player.get_node_or_null("SpawnVisibility") as MultiplayerSynchronizer
	if visibility == null:
		visibility = MultiplayerSynchronizer.new()
		visibility.name = "SpawnVisibility"
		visibility.root_path = NodePath("..")
		visibility.replication_config = SceneReplicationConfig.new()
		visibility.set_multiplayer_authority(1)
		player.add_child(visibility)
	# set_multiplayer_authority(..., true) is also used during host migration.
	visibility.set_multiplayer_authority(1)
	var filtering := player.multiplayer != null and player.multiplayer.has_multiplayer_peer() and not player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer and player.multiplayer.is_server()
	# Filters restrict the public set; public=false would hide every peer even
	# when its filter returns true (unless explicitly enabled one by one).
	visibility.public_visibility = true
	if filtering and not visibility.has_meta("bobux_room_filter"):
		visibility.add_visibility_filter(player._is_peer_visible_for_room)
		visibility.set_meta("bobux_room_filter", true)
	elif not filtering and visibility.has_meta("bobux_room_filter"):
		visibility.remove_visibility_filter(player._is_peer_visible_for_room)
		visibility.remove_meta("bobux_room_filter")
	if visibility.is_inside_tree(): visibility.update_visibility()
	return visibility
