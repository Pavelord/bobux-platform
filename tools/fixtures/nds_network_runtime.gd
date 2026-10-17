extends "res://tools/fixtures/published_runtime_fixture.gd"

func _get_effective_local_room_id() -> String: return "a"
func _get_runtime_local_peer_id() -> int: return multiplayer.get_unique_id()
func _get_room_visual_origin(_room: String) -> Vector3: return Vector3.ZERO
func _get_room_world_origin(_room: String) -> Vector3: return Vector3.ZERO

func _get_room_network_position_origin(_room: String) -> Vector3:
	# The nonzero-origin regression offsets the existing World container, not
	# a production room root. Native respawn/checkpoint RPCs still need the same
	# server-to-client translation as ImportedPlaceNetwork's authored teleports.
	# Keeping the old all-zero stub sent a killed survivor back to server space
	# even when the actual imported transport was translating it correctly.
	if OS.get_cmdline_user_args().has("--nonzero-origin") and not multiplayer.is_server():
		return Vector3(600000, 0, 630000)
	return Vector3.ZERO

func add_probe_player(peer: int) -> CharacterBody3D:
	var character: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	character.set_script(load("res://tools/fixtures/nds_network_character.gd"))
	character.name = str(peer)
	character.set_multiplayer_authority(peer)
	character.world_stud_scale = 0.5
	character.set_meta("bobux_studio_playtest", true)
	character.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	# The authored game controls teleport/damage, the fixture holds movement
	# still so physics input does not affect assertions across processes.
	players.add_child(character)
	for synchronizer in character.find_children("*", "MultiplayerSynchronizer", true, false):
		synchronizer.public_visibility = false
		synchronizer.replication_config = null
	character.set_physics_process(false)
	character.set_process(false)
	ImportedPlaceNetwork.track_character(character, world)
	if multiplayer.is_server():
		LuaScriptEngine.bind_network_player_character(character, world, peer, "Probe%d" % peer, str(peer))
	return character
