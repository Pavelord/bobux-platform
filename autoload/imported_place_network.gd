extends Node
## A room owns one imported DataModel. Clients receive its live instances, not
## another invocation of the place's server scripts. Native avatars keep their
## existing movement channel; authored teleports/forces originate here.

signal replica_ready(workspace: Node)

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
const Physics = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
const SeatAuthority = preload("res://addons/roblox_runtime/roblox_seat_authority.gd")
const RenderResourceLifecycle = preload("res://addons/roblox_runtime/roblox_render_resource_lifecycle.gd")
const HumanoidStates = preload("res://scripts/player/humanoid/state_machine.gd")
const HumanoidConfigData = preload("res://scripts/player/humanoid/humanoid_config.tres")
const HUMANOID_COMMANDS := ["move_to", "move_to_part", "set_humanoid_move", "request_humanoid_state", "set_humanoid_property", "set_humanoid_state_enabled"]
const SERVICES = ["Workspace", "Players", "Lighting", "ReplicatedStorage", "Teams"]
const CHUNK_BYTES = 12000
const MAX_TRANSFER_BYTES = 32 * 1024 * 1024
const WEBSOCKET_CONTROL_RESERVE_BYTES = 8192
var _rooms: Dictionary = {}
var _subscriptions: Dictionary = {}
var _client: Dictionary = {}
var _incoming: Dictionary = {}
var _pending: Array = []
var _outgoing: Array = []
var _elapsed := 0.0
var _generation := 0
var _applying := false
var _serializer := DataModel.new()
var _request_id := 0
var _remote_requests := {}
var _remote_rate := {}
var _retired: Array[Node] = []
var _replica_asset_downloads: Dictionary = {}
var _seat_drivers: Dictionary = {}
var _humanoid_command_sequence := 0
var _humanoid_moves: Dictionary = {}
var _pending_humanoid_commands: Dictionary = {}
var _humanoid_actor_sequence := 0

func _humanoid_actor_token(character: Node) -> int:
	var token := int(character.get_meta("_bobux_humanoid_actor_token", 0))
	if token <= 0:
		_humanoid_actor_sequence += 1
		token = _humanoid_actor_sequence
		character.set_meta("_bobux_humanoid_actor_token", token)
	return token

func retire_tree(branch: Node) -> void:
	# Call after stopping this branch's scripts. Free leaves in small batches;
	# destroying thousands of render/physics resources in one frame stalls Leave.
	if not is_instance_valid(branch): return
	branch.process_mode = Node.PROCESS_MODE_DISABLED
	if branch.get_parent() != null: branch.get_parent().remove_child(branch)
	var queue: Array[Node] = [branch]
	var index := 0
	while index < queue.size():
		queue.append_array(queue[index].get_children())
		index += 1
	_retired.append_array(queue)

func _free_retired_node(node: Node) -> void:
	# Godot frees MeshInstance surface overrides before its rendering instance.
	# With several overrides the remaining renderer entries can then query a
	# material RID already freed by an earlier slot (godotengine/godot#85817).
	# Detach this instance while holding its resources, then destroy the node.
	# Never clear a shared Mesh's embedded materials or mutate Material resources.
	var held: Array[Resource] = RenderResourceLifecycle.detach_render_instance(node)
	node.free()
	# `held` is released after the rendering instance no longer exists.

func networked() -> bool:
	if not multiplayer.has_multiplayer_peer(): return false
	var transport := multiplayer.multiplayer_peer
	return is_instance_valid(transport) and not transport is OfflineMultiplayerPeer and transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func workspace_for(context: Node) -> Node:
	return get_node("/root/LuaScriptEngine")._resolve_workspace_node(get_tree().root, context)

func role(context: Node) -> String:
	if not is_instance_valid(context): return ""
	var workspace := workspace_for(context)
	return str(workspace.get_meta("bobux_network_role", "")) if is_instance_valid(workspace) else ""

func script_allowed(context: Node, realm: String) -> bool:
	var mode := role(context)
	if mode.is_empty(): return true # Studio/offline Play still runs both realms.
	if mode == "server": return realm != "client"
	return realm == "client" and bool(workspace_for(context).get_meta("bobux_replica_ready", false))

func prepare(workspace: Node, room: String) -> void:
	if not networked() or room.is_empty(): return
	workspace.set_meta("bobux_network_role", "server" if multiplayer.is_server() else "client")
	workspace.set_meta("bobux_replica_ready", false)
	workspace.set_meta("room_id", room)
	# Physics/GUI setup in older builders could create an offline LocalPlayer
	# before the network role was known. It is not a real room participant.
	var services: Dictionary = get_node("/root/LuaScriptEngine")._ensure_roblox_service_nodes(get_tree().root, workspace)
	var offline: Node = services.Players.get_node_or_null("LocalPlayer")
	if offline != null and int(offline.get_meta("bobux_peer_id", 0)) == 0 and bool(offline.get_meta("bobux_runtime_generated", false)):
		services.Players.remove_child(offline)
		offline.queue_free()

func register_workspace(workspace: Node, room: String) -> void:
	if role(workspace).is_empty(): return
	var engine := get_node("/root/LuaScriptEngine")
	var services: Dictionary = engine._ensure_roblox_service_nodes(get_tree().root, workspace)
	var roots := {}
	for service in SERVICES:
		if is_instance_valid(services.get(service)): roots["$" + service] = services[service]
	if multiplayer.is_server():
		_rooms[room] = {"workspace": workspace, "roots": roots, "records": {}, "nodes": {}}
	else:
		_generation += 1
		_client = {"room": room, "workspace": workspace, "roots": roots, "nodes": roots.duplicate(), "token": _generation, "seen": {}, "ready": false}
		_client["snapshot_requested_msec"] = Time.get_ticks_msec()
		_incoming.clear()
		_pending.clear()
		_index_existing(_client, roots)
		_request_snapshot.rpc_id(1, _generation)

func unregister_workspace(workspace: Node) -> void:
	for peer in _pending_humanoid_commands.keys():
		_pending_humanoid_commands[peer] = (_pending_humanoid_commands[peer] as Array).filter(func(command): return command.workspace != workspace)
		if _pending_humanoid_commands[peer].is_empty(): _pending_humanoid_commands.erase(peer)
	for peer in _humanoid_moves.keys():
		if _humanoid_moves[peer].get("workspace") == workspace:
			_humanoid_moves.erase(peer)
	for room in _rooms.keys():
		if _rooms[room].workspace != workspace: continue
		_rooms.erase(room)
		for peer in _subscriptions.keys():
			if _subscriptions[peer].room == room:
				_subscriptions.erase(peer)
				_remote_rate.erase(peer)
		_outgoing = _outgoing.filter(func(packet): return _subscriptions.has(int(packet[0])))
	if _client.get("workspace") == workspace:
		_client = {}
		_generation += 1
		_pending.clear()
		_incoming.clear()

func mark_changed(node: Node, property_name: String = "") -> void:
	if _applying or not is_instance_valid(node): return
	# Poses are sampled separately. Rebuilding a part, its mesh children and
	# collision shapes for every CFrame assignment made moving disasters stall.
	if node is Node3D and property_name in ["CFrame", "Position", "Rotation", "Orientation"]: return
	node.set_meta("_bobux_replication_revision", int(node.get_meta("_bobux_replication_revision", 0)) + 1)

func _room_for_peer(peer: int) -> String:
	return str(get_node("/root/NetworkManager").get_peer_room_id(peer))

func _id(node: Node, roots: Dictionary) -> String:
	for key in roots:
		if roots[key] == node: return key
	var ref := str(node.get_meta("roblox_ref", ""))
	if ref.is_empty():
		ref = "net:%d" % node.get_instance_id()
		node.set_meta("roblox_ref", ref)
	return ref

func _walk(roots: Dictionary) -> Array:
	var result: Array = []
	for key in roots:
		var root: Node = roots[key]
		var queue: Array = [root]
		var index := 0
		while index < queue.size():
			var node: Node = queue[index]
			index += 1
			if node.is_queued_for_deletion(): continue
			result.append(node)
			# Legacy places use Lighting as a server-side model library. Clients
			# already have its authored templates; only live Workspace clones and
			# Lighting's own properties belong in the room stream.
			if key == "$Lighting": continue
			for child in node.get_children():
				# Native colliders, render helpers and avatars use other channels.
				if child is CharacterBody3D or bool(child.get_meta("roblox_face_decal", false)): continue
				if str(child.get_meta("roblox_class", "")).is_empty(): continue
				queue.append(child)
	return result

func _index_existing(state: Dictionary, roots: Dictionary) -> void:
	for node in _walk(roots): state.nodes[_id(node, roots)] = node
	_index_characters(state)

func track_character(character: Node, workspace: Node) -> void:
	if not is_instance_valid(character) or not is_instance_valid(workspace): return
	character.set_meta("bobux_workspace_instance_id", workspace.get_instance_id())
	character.add_to_group("roblox_live_characters")
	if not _client.is_empty() and _client.workspace == workspace:
		_index_characters(_client)
		if character.is_multiplayer_authority():
			var previous_id := int(_client.get("command_actor_id", 0))
			if previous_id > 0 and previous_id != character.get_instance_id():
				_client["actor_waiting"] = true
				_client.erase("humanoid_command_queue")
			_client["command_actor_id"] = character.get_instance_id()
			_flush_character_commands()
		_refresh_seat_views()
		_apply_waiting_seat_command()

func _index_characters(state: Dictionary) -> void:
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if workspace_for(character) != state.workspace: continue
		var peer := character.get_multiplayer_authority()
		var ref := "character:%d" % peer
		character.set_meta("roblox_ref", ref)
		state.nodes[ref] = character
		for child in character.get_children():
			if child.has_meta("bobux_character_part_proxy") or str(child.get_meta("roblox_class", "")) == "Humanoid":
				var child_ref := ref + ":" + str(child.name)
				child.set_meta("roblox_ref", child_ref)
				state.nodes[child_ref] = child
		var player: Variant = state.nodes.get("player:%d" % peer)
		if not is_instance_valid(player): continue
		var previous := int(player.get_meta("bobux_character_instance_id", 0))
		player.set_meta("bobux_character_instance_id", character.get_instance_id())
		character.set_meta("bobux_player_instance_id", player.get_instance_id())
		if previous != character.get_instance_id() and not multiplayer.is_server():
			var instance = LuaScriptEngine.BobuxInstance.wrap(player)
			instance._shared_event("CharacterAdded").Fire(LuaScriptEngine.BobuxInstance.wrap(character))
			instance.Changed.Fire("Character")

func _private_owner(node: Node) -> int:
	var cursor := node
	var private_branch := false
	while cursor != null:
		var cls := str(cursor.get_meta("roblox_class", ""))
		if cls in ["PlayerGui", "PlayerScripts", "Backpack"]: private_branch = true
		if cls == "Player": return int(cursor.get_meta("bobux_peer_id", 0)) if private_branch else 0
		cursor = cursor.get_parent()
	return 0

func _pack_value(value: Variant, state: Dictionary, depth: int = 0) -> Variant:
	if depth > 20: return null
	if value is Object:
		var target: Node = value if value is Node else (value.node if value is LuaScriptEngine.BobuxInstance else null)
		return {"$instance": _id(target, state.roots)} if is_instance_valid(target) else null
	if value is Callable or value is Signal or value is RID: return null
	if value is Dictionary:
		var out := {}
		for key in value:
			if key is String or key is StringName or key is int or key is float: out[str(key) if key is StringName else key] = _pack_value(value[key], state, depth + 1)
		return out
	if value is Array:
		var out := []
		for item in value: out.append(_pack_value(item, state, depth + 1))
		return out
	if value is String:
		var folder := str(state.workspace.get_meta("bobux_map_asset_folder", ""))
		if not folder.is_empty() and value.begins_with(folder + "/"): return "$asset:" + value.substr(folder.length() + 1)
	return value

func _unpack_value(value: Variant, state: Dictionary) -> Variant:
	if value is Dictionary:
		if value.has("$instance"):
			var target: Variant = state.nodes.get(str(value["$instance"]))
			return LuaScriptEngine.BobuxInstance.wrap(target) if is_instance_valid(target) else null
		var out := {}
		for key in value: out[key] = _unpack_value(value[key], state)
		return out
	if value is Array:
		var out := []
		for item in value: out.append(_unpack_value(item, state))
		return out
	if value is String and value.begins_with("$asset:"):
		var relative_path := _safe_replica_asset_path(value.trim_prefix("$asset:"))
		var folder := str(state.workspace.get_meta("bobux_map_asset_folder", "")).strip_edges()
		if relative_path.is_empty(): return value
		if folder.is_empty(): return value
		var local_path := folder.path_join(relative_path)
		_ensure_replica_asset_download(state.workspace, relative_path, local_path)
		return local_path
	return value

func _safe_replica_asset_path(value: String) -> String:
	var clean := value.strip_edges().replace("\\", "/")
	if clean.is_empty() or clean.begins_with("/") or clean.contains(":"):
		return ""
	for segment in clean.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return ""
	return clean

func _ensure_replica_asset_download(workspace: Node, relative_path: String, local_path: String) -> void:
	if FileAccess.file_exists(local_path) or _replica_asset_downloads.has(local_path):
		return
	var urls: Dictionary = workspace.get_meta("bobux_map_asset_urls", {})
	var asset_url := str(urls.get(relative_path, urls.get(relative_path.get_file(), ""))).strip_edges()
	if asset_url.is_empty():
		return
	var cloud := get_node_or_null("/root/CloudAPI")
	if cloud == null or not cloud.has_method("download_map_asset_file"):
		return
	_replica_asset_downloads[local_path] = true
	if relative_path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "wav", "ogg", "mp3", "oga"]:
		var media := get_node_or_null("/root/MapMediaStream")
		if media != null:
			media.expect_file(local_path)
	_download_replica_asset(local_path, asset_url)

func _download_replica_asset(local_path: String, asset_url: String) -> void:
	var cloud := get_node_or_null("/root/CloudAPI")
	var result: Dictionary = {}
	for attempt in range(3):
		if cloud == null or not is_instance_valid(cloud):
			break
		result = await cloud.download_map_asset_file(asset_url, local_path)
		if bool(result.get("ok", false)):
			break
		if attempt < 2:
			await get_tree().create_timer(0.5 * float(attempt + 1)).timeout
	_replica_asset_downloads.erase(local_path)
	if bool(result.get("ok", false)):
		var media := get_node_or_null("/root/MapMediaStream")
		if media != null:
			media.file_available(local_path)
	else:
		var media := get_node_or_null("/root/MapMediaStream")
		if media != null:
			media.file_failed(local_path)
		push_warning("[ImportedPlaceNetwork] Could not fetch replica map asset '%s': %s" % [local_path.get_file(), str(result.get("error", "download failed"))])

func _record(node: Node, state: Dictionary) -> Dictionary:
	var cls := str(node.get_meta("roblox_class", "Instance"))
	var props: Dictionary = _serializer._serialize_node_properties(node, cls)
	# Luau scalar properties and instance references may be newer than the
	# original import manifest. Never serialize callbacks or native object IDs.
	for key in node.get_meta_list():
		var label := str(key)
		if not label.is_empty() and label.left(1) == label.left(1).to_upper() and label.left(1) != "_" and label not in ["OnServerInvoke", "OnClientInvoke", "OnInvoke"]:
			props[label] = node.get_meta(key)
	if node is Node3D:
		props["BobuxTemplateOnly"] = not node.visible
		if node is MeshInstance3D and node.mesh != null: props["BobuxDeferredGeometry"] = false
	var entry := {"ref": _id(node, state.roots), "class": cls, "name": str(node.get_meta("Name", node.get_meta("block_name", node.name))), "parent_ref": _id(node.get_parent(), state.roots) if node.get_parent() != null else "", "properties": _pack_value(props, state), "owner": _private_owner(node), "revision": int(node.get_meta("_bobux_replication_revision", 0))}
	if cls == "Player": entry["peer"] = int(node.get_meta("bobux_peer_id", 0))
	if cls in ["LocalScript", "ModuleScript"]:
		entry["source"] = str(node.get_meta("code", node.get_meta("lua_source", "")))
		entry["disabled"] = bool(node.get_meta("disabled", false))
	if node is Node3D: entry["pose"] = node.transform
	return entry

func _capture(state: Dictionary) -> Array:
	var changes: Array = []
	var records := {}
	var nodes := {}
	for node in _walk(state.roots):
		var ref := _id(node, state.roots)
		nodes[ref] = node
		var old: Dictionary = state.records.get(ref, {})
		var parent_ref := _id(node.get_parent(), state.roots) if node.get_parent() != null else ""
		var dirty: bool = old.is_empty() or int(old.get("revision", -1)) != int(node.get_meta("_bobux_replication_revision", 0)) or old.get("parent_ref") != parent_ref
		if dirty:
			var entry := _record(node, state)
			records[ref] = entry
			changes.append(["put", entry])
		else:
			records[ref] = old
			if node is Node3D and not node.transform.is_equal_approx(old.get("pose", Transform3D.IDENTITY)):
				var updated := old.duplicate(false)
				updated.pose = node.transform
				records[ref] = updated
				changes.append(["pose", ref, node.transform, int(old.get("owner", 0))])
	for ref in state.records:
		if not records.has(ref): changes.append(["remove", ref, int(state.records[ref].get("owner", 0))])
	state.records = records
	state.nodes = nodes
	_index_characters(state)
	return changes

func _for_peer(operations: Array, peer: int) -> Array:
	var result := []
	for op in operations:
		var owner := int(op[1].get("owner", 0)) if op[0] == "put" else int(op[-1])
		if owner == 0 or owner == peer: result.append(op)
	return result

@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot(token: int) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var room := _room_for_peer(peer)
	if not _rooms.has(room): return
	# A reliable snapshot already queued for this generation needs no resend.
	if _subscriptions.has(peer) and _subscriptions[peer].token == token: return
	var state: Dictionary = _rooms[room]
	var changes := _capture(state)
	# A late join must not consume changes that existing subscribers have not
	# received yet. Commit the same revision to them before taking its snapshot.
	_broadcast_room_changes(room, changes, peer)
	var ops: Array = []
	for entry in state.records.values(): ops.append(["put", entry])
	_subscriptions[peer] = {"room": room, "token": token}
	var initial_character := {}
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if character.get_multiplayer_authority() == peer and workspace_for(character) == state.workspace:
			initial_character = {"position": character.global_position - state.workspace.global_position, "health": character.get("current_health"), "actor_token": _humanoid_actor_token(character)}
			var seat := SeatAuthority.assigned_seat(character)
			initial_character["seat"] = _id(seat, state.roots) if seat != null else ""
	_send_transaction(peer, token, {"snapshot": true, "ops": _for_peer(ops, peer), "character": initial_character})
	_flush_server_humanoid_commands(peer, room)

func _send_transaction(peer: int, token: int, data: Dictionary) -> void:
	_queue_encoded_transaction(peer, token, _encode_transaction(data))

func _encode_transaction(data: Dictionary) -> Dictionary:
	var raw := var_to_bytes(data)
	if raw.size() > MAX_TRANSFER_BYTES:
		push_error("Imported place snapshot exceeds the supported transfer size")
		return {}
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	return {"raw_size": raw.size(), "compressed": compressed}

func _queue_encoded_transaction(peer: int, token: int, encoded: Dictionary) -> void:
	if encoded.is_empty(): return
	var compressed: PackedByteArray = encoded.compressed
	var transfer := Time.get_ticks_usec()
	var total := ceili(float(compressed.size()) / CHUNK_BYTES)
	for index in total:
		_outgoing.append([peer, token, transfer, index, total, encoded.raw_size, compressed.slice(index * CHUNK_BYTES, (index + 1) * CHUNK_BYTES)])

func _broadcast_room_changes(room: String, changes: Array, except_peer: int = 0) -> void:
	if changes.is_empty(): return
	var public_ops: Array = []
	var private_owners := {}
	for op in changes:
		var owner := int(op[1].get("owner", 0)) if op[0] == "put" else int(op[-1])
		if owner == 0: public_ops.append(op)
		else: private_owners[owner] = true
	# Every observer without a private update receives exactly the same bytes.
	# Serialize/compress that view once, including moving disaster geometry.
	var encoded_views := {}
	var connected := multiplayer.get_peers()
	for peer in _subscriptions.keys():
		var sub: Dictionary = _subscriptions[peer]
		if not connected.has(peer) or _room_for_peer(peer) != sub.room:
			_subscriptions.erase(peer)
			continue
		if sub.room != room or peer == except_peer: continue
		var view := int(peer) if private_owners.has(peer) else 0
		if not encoded_views.has(view):
			var visible: Array = _for_peer(changes, peer) if view != 0 else public_ops
			encoded_views[view] = _encode_transaction({"ops": visible}) if not visible.is_empty() else {}
		_queue_encoded_transaction(peer, int(sub.token), encoded_views[view])

@rpc("authority", "call_remote", "reliable")
func _receive_chunk(token: int, transfer: int, index: int, total: int, raw_size: int, bytes: PackedByteArray) -> void:
	if _client.is_empty() or token != _client.token or multiplayer.is_server(): return
	if raw_size <= 0 or raw_size > MAX_TRANSFER_BYTES or total < 1 or total > 3000 or bytes.size() > CHUNK_BYTES: return
	if index == 0: _incoming[transfer] = {"next": 0, "bytes": PackedByteArray()}
	if not _incoming.has(transfer) or _incoming[transfer].next != index:
		return
	var job: Dictionary = _incoming[transfer]
	job.bytes.append_array(bytes)
	job.next += 1
	if job.bytes.size() > MAX_TRANSFER_BYTES:
		_incoming.erase(transfer)
		return
	if index + 1 != total: return
	var decoded: Variant = bytes_to_var(job.bytes.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	_incoming.erase(transfer)
	if decoded is Dictionary: _pending.append(decoded)

func _transport_accepts_chunk(peer: int, payload_size: int) -> bool:
	var transport := multiplayer.multiplayer_peer
	if not is_instance_valid(transport): return false
	if not transport is WebSocketMultiplayerPeer: return true
	var socket: WebSocketPeer = transport.get_peer(peer)
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	var capacity := socket.outbound_buffer_size
	if capacity <= 0: return true
	# RPC/WebSocket headers and avatar/heartbeat traffic share this buffer.
	var reserve := mini(WEBSOCKET_CONTROL_RESERVE_BYTES, capacity / 4)
	return socket.get_current_outbound_buffered_amount() + payload_size + 1024 <= capacity - reserve

func _flush_outgoing() -> void:
	if _outgoing.is_empty() or not networked(): return
	var connected := multiplayer.get_peers()
	var blocked := {}
	var index := 0
	var sent := 0
	var started := Time.get_ticks_usec()
	while index < _outgoing.size() and sent < 8 and Time.get_ticks_usec() - started < 1500:
		var packet: Array = _outgoing[index]
		var peer := int(packet[0])
		if not connected.has(peer) or not _subscriptions.has(peer) or _room_for_peer(peer) != _subscriptions[peer].room:
			_outgoing.remove_at(index)
			continue
		if blocked.has(peer) or not _transport_accepts_chunk(peer, (packet[6] as PackedByteArray).size()):
			blocked[peer] = true
			index += 1
			continue
		var send_error: Error = rpc_id(peer, "_receive_chunk", packet[1], packet[2], packet[3], packet[4], packet[5], packet[6])
		if send_error != OK:
			# Retain reliable data for a later poll; never discard a chunk on a
			# full transport buffer or rotate later chunks ahead of this one.
			blocked[peer] = true
			index += 1
			continue
		_outgoing.remove_at(index)
		sent += 1

func _process(delta: float) -> void:
	var cleanup_start := Time.get_ticks_usec()
	while not _retired.is_empty() and Time.get_ticks_usec() - cleanup_start < 2000:
		var retired: Variant = _retired.pop_back()
		if is_instance_valid(retired): _free_retired_node(retired)
	# A cold room may still be building when the client finishes its local
	# geometry. Retry that initial request, without restarting the connection.
	if not _client.is_empty() and not bool(_client.ready) and not _applying and _incoming.is_empty() and _pending.is_empty() and networked():
		if Time.get_ticks_msec() - int(_client.get("snapshot_requested_msec", 0)) >= 2000:
			_client.snapshot_requested_msec = Time.get_ticks_msec()
			_request_snapshot.rpc_id(1, int(_client.token))
	_flush_outgoing()
	if not _applying and not _pending.is_empty() and not _client.is_empty():
		_apply_transaction(_pending.pop_front())
	_elapsed += delta
	if _elapsed < 0.1: return
	_elapsed = 0.0
	if not networked() or not multiplayer.is_server(): return
	_maintain_seat_drivers()
	_expire_humanoid_moves()
	for room in _rooms.keys():
		var state: Dictionary = _rooms[room]
		if not is_instance_valid(state.workspace):
			_rooms.erase(room)
			continue
		# A cold room has no observers until its first snapshot request. Capturing
		# and serializing every new clone then wastes time needed by its scripts.
		var observed := false
		for sub in _subscriptions.values():
			if sub.room == room: observed = true; break
		var changes: Array = _capture(state) if observed else []
		for character in get_tree().get_nodes_in_group("roblox_live_characters"):
			if workspace_for(character) != state.workspace: continue
			var health := float(character.get("current_health"))
			var previous := float(character.get_meta("_bobux_replication_health", 100.0))
			character.set_meta("_bobux_replication_health", health)
			if health <= 0 and previous > 0:
				get_node("/root/LuaScriptEngine").fire_roblox_instance_event(character.get_node_or_null("Humanoid"), "Died", [])
		_broadcast_room_changes(room, changes)

func _apply_transaction(data: Dictionary) -> void:
	_applying = true
	var state := _client
	var snapshot := bool(data.get("snapshot", false))
	var seen := {}
	var changed_parts := {}
	var started := Time.get_ticks_usec()
	for op in data.get("ops", []):
		if state != _client or not is_instance_valid(state.workspace): break
		match str(op[0]):
			"put":
				var entry: Dictionary = op[1]
				seen[str(entry.ref)] = true
				_apply_entry(entry, state, changed_parts)
			"pose": _apply_pose(state.nodes.get(str(op[1])), op[2])
			"remove": _remove_instance(state, str(op[1]))
		if Time.get_ticks_usec() - started > 3000:
			await get_tree().process_frame
			started = Time.get_ticks_usec()
	if is_instance_valid(state.get("workspace")) and state == _client:
		if snapshot:
			for ref in state.nodes.keys():
				if not seen.has(ref) and not state.roots.has(ref) and not str(ref).begins_with("character:"): _remove_instance(state, ref)
		_index_characters(state)
		_refresh_seat_views()
		var engine := get_node("/root/LuaScriptEngine")
		var importer: RefCounted = engine.template_importer_for(state.workspace)
		for value in changed_parts.values():
			if state != _client or not is_instance_valid(state.get("workspace")): break
			if not is_instance_valid(value) or value.is_queued_for_deletion(): continue
			var part := value as MeshInstance3D
			if part.mesh == null: importer.materialize_template_part(part)
			else: importer.restore_part_children(part)
			var part_properties: Dictionary = part.get_meta("roblox_properties", {})
			var part_can_collide := bool(part.get_meta("can_collide", part_properties.get("CanCollide", true)))
			var part_can_query := bool(part.get_meta("CanQuery", part_properties.get("CanQuery", true)))
			if part.mesh != null and (part_can_collide or part_can_query) and not bool(part.get_meta("bobux_character_part_proxy", false)):
				Physics.body_for(part, true)
				var adapter := part.get_node_or_null("RobloxPartPhysics")
				if adapter != null: adapter.sync_from_part()
			if Time.get_ticks_usec() - started > 3000:
				await get_tree().process_frame
				started = Time.get_ticks_usec()
		if state != _client or not is_instance_valid(state.get("workspace")):
			_applying = false
			return
		if snapshot:
			state.ready = true
			state.workspace.set_meta("bobux_replica_ready", true)
			replica_ready.emit(state.workspace)
			var initial: Dictionary = data.get("character", {})
			if initial.has("actor_token"):
				_character_actor(str(state.room), int(state.token), int(initial.actor_token))
			if initial.has("position"): _character_command(state.room, "set_lua_position", initial.position)
			if initial.has("health"): _character_command(state.room, "set_health", initial.health)
			if initial.has("seat"): _seat_command(state.room, str(initial.seat))
		else:
			for op in data.get("ops", []):
				if op[0] == "put" and str(op[1].get("class", "")) == "LocalScript":
					var script_node: Variant = state.nodes.get(str(op[1].ref))
					if is_instance_valid(script_node): engine._refresh_authored_scripts_by_id(script_node.get_instance_id())
	_applying = false
	_apply_waiting_seat_command()
	_flush_character_commands()

func _apply_entry(entry: Dictionary, state: Dictionary, changed_parts: Dictionary) -> void:
	var ref := str(entry.ref)
	var node: Node = state.nodes.get(ref) if is_instance_valid(state.nodes.get(ref)) else null
	var engine := get_node("/root/LuaScriptEngine")
	var created := node == null
	if not state.roots.has(ref):
		var parent: Node = state.nodes.get(str(entry.parent_ref)) if is_instance_valid(state.nodes.get(str(entry.parent_ref))) else null
		if parent == null: return
		if node == null and str(entry.class) == "Weld" and str(entry.name) == "SeatWeld":
			var predicted := parent.get_node_or_null("SeatWeld")
			if predicted != null and bool(predicted.get_meta("bobux_seat_weld", false)):
				node = predicted
				state.nodes[ref] = node
		if node == null:
			node = DataModel.create_instance(str(entry.class), str(entry.name))
			parent.add_child(node)
			state.nodes[ref] = node
		elif node.get_parent() != parent:
			node.reparent(parent, false)
	var props: Dictionary = _unpack_value(entry.properties, state)
	if node.has_meta("_bobux_render_batch") or bool(node.get_meta("_bobux_contains_render_batches", false)):
		preload("res://addons/roblox_runtime/roblox_render_batches.gd").detach_tree(node)
	var previous: Dictionary = node.get_meta("roblox_properties", {})
	var geometry_changed := created
	for key in ["BobuxSize", "Size", "size", "shape", "Shape", "BobuxMeshResource", "BobuxDeferredGeometry", "BobuxTemplateOnly"]:
		if props.get(key) != previous.get(key): geometry_changed = true
	var adapted := entry.duplicate(false)
	adapted.properties = props
	# Manifest metadata also contains native BobuxPosition/Rotation/Size. A
	# Workspace entry can arrive through that path before _apply_pose, so the
	# pose guard alone does not protect the client's local room origin.
	var preserve_workspace_pose: bool = node == state.workspace and node is Node3D
	var workspace_pose: Transform3D = (node as Node3D).transform if preserve_workspace_pose else Transform3D.IDENTITY
	engine._apply_manifest_entry_metadata(node, adapted)
	if preserve_workspace_pose:
		(node as Node3D).transform = workspace_pose
	if entry.get("class") == "Player":
		node.set_meta("bobux_peer_id", int(entry.get("peer", 0)))
		node.set_meta("bobux_player_joined", true)
		node.name = "LocalPlayer" if int(entry.get("peer", 0)) == multiplayer.get_unique_id() else "Peer_%d" % int(entry.get("peer", 0))
	if node is Node3D:
		node.visible = not bool(props.get("BobuxTemplateOnly", false))
		if entry.has("pose"): _apply_pose(node, entry.pose)
	if created and node is MeshInstance3D: node.mesh = null
	if node is MeshInstance3D:
		if geometry_changed or node.mesh == null:
			changed_parts[node.get_instance_id()] = node
		else:
			# A burning part changes colour/anchoring repeatedly. Its decals,
			# mesh and collider dimensions are unchanged and need no reconstruction.
			var adapter := node.get_node_or_null("RobloxPartPhysics")
			if adapter != null: adapter.refresh_properties()
	elif str(entry.class) in ["Decal", "Texture", "SpecialMesh", "BlockMesh", "CylinderMesh"] and node.get_parent() is MeshInstance3D:
		changed_parts[node.get_parent().get_instance_id()] = node.get_parent()
	for key in props:
		if key in ["Value", "Team", "TeamColor", "Neutral", "UserId"]:
			node.set_meta(key, props[key])
			engine.BobuxInstance.wrap(node)._shared_event("PropertyChanged_" + key).Fire()
	engine.BobuxInstance.wrap(node).Changed.Fire(props.get("Value") if str(entry.class).ends_with("Value") else "")
	if str(entry.class) == "Sound":
		# Changing volume/position must not restart a playing track at zero.
		# A repeated explicit Play has its own generation and does restart.
		var playback_changed: bool = created or props.get("Playing", false) != previous.get("Playing", false) or props.get("BobuxSoundPlayGeneration", 0) != previous.get("BobuxSoundPlayGeneration", 0) or props.get("SoundId", "") != previous.get("SoundId", "")
		if playback_changed:
			if bool(props.get("Playing", false)): preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").play(node)
			else: preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").stop(node)
	if SeatAuthority.is_seat(node):
		var seats: Dictionary = state.get("seats", {})
		seats[ref] = node
		state["seats"] = seats
		for key in ["ThrottleFloat", "SteerFloat", "Throttle", "Steer"]:
			node.set_meta(key, props.get(key, 0))

func _apply_pose(value: Variant, pose: Transform3D) -> void:
	if not is_instance_valid(value) or not value is Node3D: return
	if not pose.origin.is_finite() or not pose.basis.is_finite(): return
	var node := value as Node3D
	# Server rooms are spaced far apart for physics isolation. Workspace has
	# no authored Roblox transform: that server offset is not a client pose.
	# Keep the client's origin and apply all descendant poses relative to it.
	if not _client.is_empty() and node == _client.get("workspace"):
		return
	if not node.transform.is_equal_approx(pose): preload("res://addons/roblox_runtime/roblox_render_batches.gd").detach_tree(node)
	node.transform = pose
	var body := Physics.body_for(node)
	# Zero-sized hidden mesh templates do not have a usable rotation basis.
	if body != null and absf(node.global_basis.determinant()) > 0.000000000001:
		body.global_transform = Transform3D(node.global_basis.orthonormalized(), node.global_position)

func _remove_instance(state: Dictionary, ref: String) -> void:
	var node: Variant = state.nodes.get(ref)
	state.nodes.erase(ref)
	if is_instance_valid(node) and not state.roots.has(ref):
		if node.get_parent() != null: node.get_parent().remove_child(node)
		node.queue_free()

func send_character_command(character: Node, method: String, value: Variant) -> bool:
	if role(character) != "server" or not networked() or not multiplayer.is_server(): return false
	var peer := character.get_multiplayer_authority()
	if peer == multiplayer.get_unique_id(): return false
	if not multiplayer.get_peers().has(peer): return false
	var room := str(workspace_for(character).get_meta("room_id", ""))
	if _room_for_peer(peer) != room: return false
	if method == "set_lua_position" and OS.get_cmdline_user_args().has("--trace-imported-network"):
		print("[place-net] character send position=", value, " workspace_origin=", (workspace_for(character) as Node3D).global_position, " room=", room)
	if method in ["move_to", "move_to_part"]:
		var point: Variant = value if method == "move_to" else value.get("point") if value is Dictionary else null
		if not point is Vector3 or not point.is_finite(): return false
		_humanoid_command_sequence += 1
		var token := _humanoid_command_sequence
		var packet := {"point": point - (workspace_for(character) as Node3D).global_position, "token": token}
		if method == "move_to_part":
			packet["part_ref"] = value.get("part_ref", "")
			packet["part_local_point"] = value.get("part_local_point")
		value = packet
		if not _valid_character_command(method, value): return false
		_humanoid_moves[peer] = {"token": token, "room": room, "workspace": workspace_for(character), "character": character, "deadline": Time.get_ticks_msec() + roundi((HumanoidConfigData.float_value("MoveTo.TimeoutSeconds") + HumanoidConfigData.float_value("Network.MoveToAckGraceSeconds")) * 1000.0)}
	else:
		if not _valid_character_command(method, value): return false
		if method in ["set_humanoid_move", "set_lua_position"]:
			_cancel_humanoid_move(peer, true)
		if value is Vector3 and method == "set_lua_position": value -= (workspace_for(character) as Node3D).global_position
	if method in HUMANOID_COMMANDS:
		_dispatch_humanoid_command(character, peer, room, method, value)
	else:
		_character_command.rpc_id(peer, room, method, value)
	return true

func _dispatch_humanoid_command(character: Node, peer: int, room: String, method: String, value: Variant) -> void:
	if not _subscriptions.has(peer) or str(_subscriptions[peer].room) != room:
		var pending: Array = _pending_humanoid_commands.get(peer, [])
		if method in ["move_to", "move_to_part", "set_humanoid_move"]:
			pending = pending.filter(func(command): return command.method not in ["move_to", "move_to_part", "set_humanoid_move"])
		pending.append({"character": character, "workspace": workspace_for(character), "room": room, "method": method, "value": value})
		_pending_humanoid_commands[peer] = pending
		return
	var replica_token := int(_subscriptions[peer].token)
	var actor_token := _humanoid_actor_token(character)
	if int(_subscriptions[peer].get("actor_token", 0)) != actor_token:
		_subscriptions[peer]["actor_token"] = actor_token
		_character_actor.rpc_id(peer, room, replica_token, actor_token)
	if method in ["move_to", "move_to_part"] and _humanoid_moves.has(peer): _humanoid_moves[peer]["replica_token"] = replica_token
	_character_command.rpc_id(peer, room, method, {"value": value, "replica_token": replica_token, "actor_token": actor_token})

@rpc("authority", "call_remote", "reliable")
func _character_actor(room: String, replica_token: int, actor_token: int) -> void:
	if _client.is_empty() or room != str(_client.room) or replica_token != int(_client.token) or actor_token <= 0: return
	if multiplayer.get_remote_sender_id() not in [0, 1]: return
	var previous := int(_client.get("actor_token", 0))
	if actor_token < previous or (bool(_client.get("actor_waiting", false)) and actor_token == previous): return
	if previous != actor_token:
		var pending: Array = _client.get("humanoid_command_queue", [])
		_client["humanoid_command_queue"] = pending.filter(func(command): return int(command.value.get("actor_token", -1)) == actor_token)
	_client["actor_token"] = actor_token
	_client["actor_waiting"] = false
	_flush_character_commands()

func _flush_server_humanoid_commands(peer: int, room: String) -> void:
	var pending: Array = _pending_humanoid_commands.get(peer, [])
	_pending_humanoid_commands.erase(peer)
	if not _rooms.has(room): return
	var state: Dictionary = _rooms[room]
	for command in pending:
		var character: Variant = command.character
		if not is_instance_valid(character) or command.workspace != state.workspace or str(command.room) != room or state.nodes.get("character:%d" % peer) != character: continue
		if command.method in ["move_to", "move_to_part"] and (not _humanoid_moves.has(peer) or int(command.value.token) != int(_humanoid_moves[peer].token)): continue
		_dispatch_humanoid_command(character, peer, room, str(command.method), command.value)

func send_character_move_to_part(character: Node, point: Vector3, part: Node3D) -> bool:
	if role(character) != "server" or not networked() or not multiplayer.is_server(): return false
	var workspace := workspace_for(character)
	var room := str(workspace.get_meta("room_id", ""))
	# Existing replicated place references survive across processes. A part
	# outside this room cannot be dereferenced by the target device; keep only
	# the requested world-point snapshot in that case.
	if not is_instance_valid(part) or workspace_for(part) != workspace or not _rooms.has(room):
		return send_character_command(character, "move_to", point)
	return send_character_command(character, "move_to_part", {"point": point, "part_ref": _id(part, _rooms[room].roots), "part_local_point": part.global_transform.affine_inverse() * point})

func _valid_character_command(method: String, value: Variant) -> bool:
	match method:
		"set_lua_position", "set_lua_linear_velocity", "apply_external_impulse", "set_humanoid_move":
			return value is Vector3 and value.is_finite()
		"set_health":
			return (value is int or value is float) and not is_nan(float(value)) and float(value) >= 0.0
		"request_humanoid_state":
			return value is int and HumanoidStates.STATE_NAMES.has(value) and value != 18
		"set_humanoid_property":
			if not value is Dictionary or not value.get("key") is String: return false
			var key: String = value.key
			var property_value: Variant = value.get("value")
			if key in ["AutoRotate", "UseJumpPower", "Sit", "PlatformStand", "BreakJointsOnDeath", "AutoJumpEnabled"]:
				return property_value is bool
			if key in ["WalkSpeed", "JumpPower", "JumpHeight", "HipHeight", "MaxHealth"]:
				return (property_value is int or property_value is float) and (is_finite(float(property_value)) or (key == "MaxHealth" and float(property_value) == INF)) and (key == "HipHeight" or float(property_value) >= 0.0)
			return false
		"set_humanoid_state_enabled":
			return value is Dictionary and value.get("state") is int and HumanoidStates.STATE_NAMES.has(value.state) and value.get("enabled") is bool
		"move_to", "move_to_part":
			if not value is Dictionary or not value.get("point") is Vector3 or not value.point.is_finite() or not value.get("token") is int or int(value.token) <= 0: return false
			return method == "move_to" or (value.get("part_ref") is String and not str(value.part_ref).is_empty() and str(value.part_ref).length() <= 512 and value.get("part_local_point") is Vector3 and value.part_local_point.is_finite())
	return false

@rpc("authority", "call_remote", "reliable")
func _character_command(room: String, method: String, value: Variant) -> void:
	if _client.is_empty() or room != _client.room: return
	if multiplayer.get_remote_sender_id() not in [0, 1]: return
	var wire_value: Variant = value
	if method in HUMANOID_COMMANDS:
		if not value is Dictionary or not value.get("replica_token") is int or int(value.replica_token) != int(_client.token): return
		if not value.get("actor_token") is int or int(value.actor_token) <= 0: return
		value = value.get("value")
	if not _valid_character_command(method, value): return
	if method in HUMANOID_COMMANDS:
		if not bool(_client.get("ready", false)) or int(_client.get("actor_token", 0)) == 0:
			_queue_character_command(method, wire_value)
			return
		if bool(_client.get("actor_waiting", false)) or int(wire_value.actor_token) != int(_client.actor_token): return
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if character.get_multiplayer_authority() != multiplayer.get_unique_id() or workspace_for(character) != _client.workspace: continue
		if method in ["move_to", "move_to_part"]:
			var point: Vector3 = value.point + (_client.workspace as Node3D).global_position
			if method == "move_to_part":
				var part: Variant = _client.nodes.get(str(value.part_ref))
				if not is_instance_valid(part):
					_queue_character_command(method, wire_value)
					return
				if not part is Node3D or workspace_for(part) != _client.workspace: return
				point = part.global_transform * value.part_local_point
				character.call("move_to_part", point, part)
			else:
				character.call("move_to", point)
			character.set_meta("bobux_remote_move_token", int(value.token))
		else:
			if method in ["set_humanoid_move", "set_lua_position"]:
				character.remove_meta("bobux_remote_move_token")
			if method == "set_lua_position": value += (_client.workspace as Node3D).global_position
			if method == "set_lua_position" and OS.get_cmdline_user_args().has("--trace-imported-network"):
				print("[place-net] character receive position=", value, " workspace_origin=", (_client.workspace as Node3D).global_position, " room=", room)
			if method == "set_humanoid_property":
				var humanoid: Node = character.get_node_or_null("Humanoid")
				if humanoid != null: get_node("/root/LuaScriptEngine").BobuxInstance.wrap(humanoid)._set(StringName(value.key), value.value)
			elif method == "set_humanoid_state_enabled":
				var humanoid: Node = character.get_node_or_null("Humanoid")
				if humanoid != null: get_node("/root/LuaScriptEngine").BobuxInstance.wrap(humanoid).SetStateEnabled(int(value.state), bool(value.enabled))
			else:
				character.call(method, value)
		return
	_queue_character_command(method, wire_value)

func _queue_character_command(method: String, value: Variant) -> void:
	if method in HUMANOID_COMMANDS:
		var pending: Array = _client.get("humanoid_command_queue", [])
		if method in ["move_to", "move_to_part", "set_humanoid_move"]:
			pending = pending.filter(func(command): return command.method not in ["move_to", "move_to_part", "set_humanoid_move"])
		var packet: Dictionary = value.duplicate()
		if not packet.has("queued_msec"): packet["queued_msec"] = Time.get_ticks_msec()
		pending.append({"method": method, "value": packet})
		_client["humanoid_command_queue"] = pending
		return
	var waiting: Dictionary = _client.get("character_commands", {})
	if method in ["move_to", "move_to_part", "set_humanoid_move"]:
		for previous in ["move_to", "move_to_part", "set_humanoid_move"]: waiting.erase(previous)
	if method in ["move_to", "move_to_part"] and value is Dictionary:
		value = value.duplicate()
		if not value.has("queued_msec"): value["queued_msec"] = Time.get_ticks_msec()
	# Keep independent property/state writes when the avatar has not arrived.
	var queue_key := method
	if method == "set_humanoid_property": queue_key += ":" + str(value.key)
	elif method == "set_humanoid_state_enabled": queue_key += ":" + str(value.state)
	waiting[queue_key] = value
	_client["character_commands"] = waiting

func _flush_character_commands() -> void:
	if _client.is_empty(): return
	var pending: Array = _client.get("humanoid_command_queue", [])
	_client.erase("humanoid_command_queue")
	for command in pending:
		var method: String = command.method
		var wire: Dictionary = command.value
		if int(wire.get("replica_token", -1)) != int(_client.token): continue
		if method in ["move_to", "move_to_part"] and Time.get_ticks_msec() - int(wire.get("queued_msec", Time.get_ticks_msec())) > roundi(HumanoidConfigData.float_value("MoveTo.TimeoutSeconds") * 1000.0):
			_humanoid_move_finished.rpc_id(1, str(_client.room), int(wire.value.token), false, int(_client.token))
			continue
		_character_command(str(_client.room), method, wire)
	var waiting: Dictionary = _client.get("character_commands", {})
	_client.erase("character_commands")
	for method in waiting:
		_character_command(str(_client.room), method, waiting[method])

func notify_humanoid_move_finished(character: Node, reached: bool) -> void:
	var token := int(character.get_meta("bobux_remote_move_token", 0))
	character.remove_meta("bobux_remote_move_token")
	if token <= 0 or role(character) != "client" or not networked() or not character.is_multiplayer_authority(): return
	if _client.is_empty() or workspace_for(character) != _client.workspace: return
	_humanoid_move_finished.rpc_id(1, str(_client.room), token, reached, int(_client.token))

@rpc("any_peer", "call_remote", "reliable")
func _humanoid_move_finished(room: String, token: Variant, reached: Variant, replica_token: Variant) -> void:
	if not multiplayer.is_server() or not token is int or not reached is bool or not replica_token is int: return
	var peer := multiplayer.get_remote_sender_id()
	if not _humanoid_moves.has(peer): return
	var active: Dictionary = _humanoid_moves[peer]
	if token != int(active.token) or room != str(active.room) or room != _room_for_peer(peer) or replica_token != int(active.get("replica_token", -1)): return
	var character: Variant = active.character
	if not is_instance_valid(character) or character.get_multiplayer_authority() != peer or workspace_for(character) != active.workspace or not _rooms.has(room) or _rooms[room].nodes.get("character:%d" % peer) != character: return
	_humanoid_moves.erase(peer)
	get_node("/root/LuaScriptEngine").fire_roblox_instance_event(character.get_node_or_null("Humanoid"), "MoveToFinished", [reached])

func _expire_humanoid_moves() -> void:
	for peer in _humanoid_moves.keys():
		var active: Dictionary = _humanoid_moves[peer]
		var character: Variant = active.character
		if not is_instance_valid(character) or not multiplayer.get_peers().has(peer) or str(active.room) != _room_for_peer(peer):
			_humanoid_moves.erase(peer)
			continue
		if Time.get_ticks_msec() >= int(active.deadline):
			_cancel_humanoid_move(peer, true)

func _cancel_humanoid_move(peer: int, notify: bool) -> void:
	if not _humanoid_moves.has(peer): return
	var active: Dictionary = _humanoid_moves[peer]
	_humanoid_moves.erase(peer)
	var character: Variant = active.character
	if notify and is_instance_valid(character):
		get_node("/root/LuaScriptEngine").fire_roblox_instance_event(character.get_node_or_null("Humanoid"), "MoveToFinished", [false])

func forward_gui_click(target: Node) -> void:
	if role(target) != "client" or not _client.get("ready", false): return
	_gui_click.rpc_id(1, str(target.get_meta("roblox_ref", "")))

func seat_entry_allowed(character: Node, seat: Node) -> bool:
	var mode := role(character)
	if mode.is_empty(): return true
	if mode == "client":
		if bool(character.get_meta("bobux_seat_command_applying", false)): return true
		if character.is_multiplayer_authority() and _client.get("ready", false) and _client.nodes.get(str(seat.get_meta("roblox_ref", ""))) == seat:
			_seat_action.rpc_id(1, "enter", str(seat.get_meta("roblox_ref", "")))
		return false
	var workspace := workspace_for(character)
	return workspace_for(seat) == workspace and _room_for_peer(character.get_multiplayer_authority()) == str(workspace.get_meta("room_id", "")) and SeatAuthority.can_sit(seat, character, workspace)

func seat_state_changed(character: Node, seat: Node, seated: bool) -> void:
	if role(character) != "server": return
	var peer := character.get_multiplayer_authority()
	if is_instance_valid(seat):
		seat.set_meta("BobuxSeatOccupantPeer", peer if seated else 0)
		mark_changed(seat, "Occupant")
	if seated:
		_seat_drivers[peer] = {"character": character, "seat": seat, "input_msec": Time.get_ticks_msec()}
	else:
		_seat_drivers.erase(peer)
	if multiplayer.get_peers().has(peer):
		var workspace := workspace_for(character)
		var room := str(workspace.get_meta("room_id", ""))
		_seat_command.rpc_id(peer, room, _id(seat, _rooms[room].roots) if seated and _rooms.has(room) else "")

func forward_seat_input(character: Node, seat: Node, input: Vector2) -> void:
	if role(character) != "client" or not character.is_multiplayer_authority() or bool(character.get_meta("bobux_seat_command_applying", false)): return
	if not _client.get("ready", false): return
	var now := Time.get_ticks_msec()
	var changed: bool = character.get_meta("bobux_last_seat_input", Vector2(INF, INF)) != input
	var since := now - int(character.get_meta("bobux_last_seat_input_msec", 0))
	if since < 50 or (not changed and since < 200): return
	character.set_meta("bobux_last_seat_input", input)
	character.set_meta("bobux_last_seat_input_msec", now)
	_seat_input.rpc_id(1, str(seat.get_meta("roblox_ref", "")), input)

func forward_seat_leave(character: Node, seat: Node) -> void:
	if role(character) == "client" and character.is_multiplayer_authority() and not bool(character.get_meta("bobux_seat_command_applying", false)):
		_seat_action.rpc_id(1, "leave", str(seat.get_meta("roblox_ref", "")))

func _seat_actor(peer: int) -> Dictionary:
	var room := _room_for_peer(peer)
	if not _rooms.has(room) or not _subscriptions.has(peer) or _subscriptions[peer].room != room: return {}
	var state: Dictionary = _rooms[room]
	var actor: Variant = state.nodes.get("character:%d" % peer)
	if not is_instance_valid(actor) or actor.get_multiplayer_authority() != peer or workspace_for(actor) != state.workspace: return {}
	return {"state": state, "character": actor}

@rpc("any_peer", "call_remote", "reliable")
func _seat_action(action: String, ref: String) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	if not _accept_remote(peer): return
	var actor := _seat_actor(peer)
	if actor.is_empty(): return
	var seat: Variant = actor.state.nodes.get(ref)
	if action == "enter" and SeatAuthority.can_sit(seat, actor.character, actor.state.workspace, true):
		actor.character.call("_enter_seat", seat)
	elif action == "leave" and SeatAuthority.assigned_seat(actor.character) == seat and seat != null:
		actor.character.call("_leave_seat", false)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _seat_input(ref: String, input: Vector2) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	if not _accept_remote(peer): return
	var actor := _seat_actor(peer)
	if actor.is_empty(): return
	var seat: Variant = actor.state.nodes.get(ref)
	if not SeatAuthority.can_drive(seat, actor.character, actor.state.workspace, input): return
	actor.character.call("_set_seat_input", seat, input)
	if _seat_drivers.has(peer): _seat_drivers[peer].input_msec = Time.get_ticks_msec()

@rpc("authority", "call_remote", "reliable")
func _seat_command(room: String, ref: String) -> void:
	if _client.is_empty() or room != _client.room: return
	_client["seat_command"] = ref
	_apply_waiting_seat_command()

func _apply_waiting_seat_command() -> void:
	if _client.is_empty() or not _client.has("seat_command"): return
	var ref := str(_client.seat_command)
	var seat: Variant = _client.nodes.get(ref)
	if not ref.is_empty() and not is_instance_valid(seat): return
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if not character.is_multiplayer_authority() or workspace_for(character) != _client.workspace: continue
		if not character.has_method("_enter_seat"): continue
		_client.erase("seat_command")
		character.set_meta("bobux_seat_command_applying", true)
		if ref.is_empty(): character.call("_leave_seat", false)
		else: character.call("_enter_seat", seat)
		character.remove_meta("bobux_seat_command_applying")
		return

func _refresh_seat_views() -> void:
	if _client.is_empty(): return
	var seats: Dictionary = _client.get("seats", {})
	for ref in seats.keys():
		if not is_instance_valid(seats[ref]): seats.erase(ref); continue
		SeatAuthority.apply_view(seats[ref], _client, get_node("/root/LuaScriptEngine"))

func _maintain_seat_drivers() -> void:
	for peer in _seat_drivers.keys():
		var driver: Dictionary = _seat_drivers[peer]
		var character: Variant = driver.character
		var seat: Variant = driver.seat
		if not is_instance_valid(character):
			if is_instance_valid(seat):
				seat.set_meta("Occupant", null)
				seat.set_meta("BobuxSeatOccupantPeer", 0)
				for key in ["ThrottleFloat", "SteerFloat", "Throttle", "Steer"]: seat.set_meta(key, 0)
				var weld: Node = seat.get_node_or_null("SeatWeld")
				if weld != null: seat.remove_child(weld); weld.queue_free()
				mark_changed(seat, "Occupant")
			_seat_drivers.erase(peer)
			continue
		if not multiplayer.get_peers().has(peer) or _room_for_peer(peer) != str(workspace_for(character).get_meta("room_id", "")) or not SeatAuthority.can_sit(seat, character, workspace_for(character)):
			_seat_drivers.erase(peer)
			character.call("_leave_seat", false)
		elif Time.get_ticks_msec() - int(driver.input_msec) > 600:
			character.call("_set_seat_input", seat, Vector2.ZERO)

func forward_interaction(target: Node, event_name: String) -> bool:
	if role(target) != "client" or not _client.get("ready", false): return false
	if preload("res://addons/roblox_runtime/roblox_interaction_authority.gd").event_for(target) != event_name: return false
	var ref := str(target.get_meta("roblox_ref", ""))
	if ref.is_empty() or _client.nodes.get(ref) != target: return false
	_interaction_input.rpc_id(1, ref, event_name)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _interaction_input(ref: String, event_name: String) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	if not _accept_remote(peer): return
	_activate_interaction_for_peer(peer, ref, event_name)

func _activate_interaction_for_peer(peer: int, ref: String, event_name: String) -> bool:
	var room := _room_for_peer(peer)
	if not _rooms.has(room) or not _subscriptions.has(peer) or _subscriptions[peer].room != room: return false
	var state: Dictionary = _rooms[room]
	var target: Variant = state.nodes.get(ref)
	var player: Variant = state.nodes.get("player:%d" % peer)
	var character: Variant = state.nodes.get("character:%d" % peer)
	if not is_instance_valid(target) or not is_instance_valid(player) or not is_instance_valid(character): return false
	if int(player.get_meta("bobux_peer_id", 0)) != peer or character.get_multiplayer_authority() != peer: return false
	if workspace_for(character) != state.workspace: return false
	if not preload("res://addons/roblox_runtime/roblox_interaction_authority.gd").can_activate(target, character, state.workspace, event_name): return false
	return bool(get_node("/root/LuaScriptEngine").fire_roblox_instance_event(target, event_name, [player]))

@rpc("any_peer", "call_remote", "reliable")
func _gui_click(ref: String) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var room := _room_for_peer(peer)
	if not _rooms.has(room): return
	var node: Variant = _rooms[room].nodes.get(ref)
	if not is_instance_valid(node) or _private_owner(node) != peer or str(node.get_meta("roblox_class", "")) not in ["TextButton", "ImageButton"]: return
	var wrapper = get_node("/root/LuaScriptEngine").BobuxInstance.wrap(node)
	wrapper.Activated.Fire()
	wrapper.MouseButton1Click.Fire()

func dispatch_remote(target: Node, method: String, arguments: Array) -> Variant:
	if OS.get_cmdline_user_args().has("--trace-imported-network"): print("[place-net] dispatch ", method, " ", target.name)
	var mode := role(target)
	var state: Dictionary = _client if mode == "client" else _rooms.get(str(workspace_for(target).get_meta("room_id", "")), {})
	if state.is_empty(): return null
	var args := arguments.duplicate(false)
	var recipients: Array = []
	if mode == "client":
		if method not in ["FireServer", "InvokeServer"]: return null
		recipients = [1]
	else:
		if method in ["FireClient", "InvokeClient"]:
			if args.is_empty() or not args[0] is LuaScriptEngine.BobuxInstance: return null
			var player: Node = args.pop_front().node
			var peer := int(player.get_meta("bobux_peer_id", 0))
			if _room_for_peer(peer) != str(state.workspace.get_meta("room_id", "")): return null
			recipients = [peer]
		elif method == "FireAllClients":
			for peer in _subscriptions:
				if _subscriptions[peer].room == str(state.workspace.get_meta("room_id", "")): recipients.append(peer)
		else: return null
	var encoded: Variant = _pack_value(args, state)
	if var_to_bytes(encoded).size() > CHUNK_BYTES: return null
	var ticket := 0
	if method.begins_with("Invoke"):
		_request_id += 1
		ticket = _request_id
		_remote_requests[ticket] = {"peer": recipients[0], "room": str(state.workspace.get_meta("room_id", "")), "deadline": Time.get_ticks_msec() + 15000, "done": false}
	for peer in recipients:
		_remote_call.rpc_id(peer, str(state.workspace.get_meta("room_id", "")), _id(target, state.roots), method, encoded, ticket)
	return {"__bobux_remote_ticket": ticket} if ticket > 0 else null

func poll_remote(ticket: int) -> Dictionary:
	if not _remote_requests.has(ticket): return {"done": true, "error": "Remote invocation no longer exists"}
	var request: Dictionary = _remote_requests[ticket]
	if Time.get_ticks_msec() > int(request.deadline):
		_remote_requests.erase(ticket)
		return {"done": true, "error": "Remote invocation timed out"}
	if not request.done: return {"done": false}
	_remote_requests.erase(ticket)
	return {"done": true, "result": request.get("result"), "error": str(request.get("error", ""))}

func _accept_remote(peer: int) -> bool:
	var now := Time.get_ticks_msec()
	var window: Dictionary = _remote_rate.get(peer, {"at": now, "count": 0})
	if now - int(window.at) >= 1000: window = {"at": now, "count": 0}
	window.count += 1
	_remote_rate[peer] = window
	return window.count <= 120

@rpc("any_peer", "call_remote", "reliable")
func _remote_call(room: String, ref: String, method: String, arguments: Array, ticket: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if OS.get_cmdline_user_args().has("--trace-imported-network"): print("[place-net] receive ", room, " ", ref, " ", method, " sender=",sender)
	if not _accept_remote(sender) or var_to_bytes(arguments).size() > CHUNK_BYTES: return
	var state: Dictionary
	if multiplayer.is_server():
		if method not in ["FireServer", "InvokeServer"] or room != _room_for_peer(sender) or not _rooms.has(room): return
		state = _rooms[room]
	else:
		if sender != 1 or _client.is_empty() or room != _client.room or method not in ["FireClient", "FireAllClients", "InvokeClient"]: return
		state = _client
	var target: Variant = state.nodes.get(ref)
	if not is_instance_valid(target): return
	var cls := str(target.get_meta("roblox_class", ""))
	if cls != ("RemoteFunction" if method.begins_with("Invoke") else "RemoteEvent"): return
	var owner := _private_owner(target)
	if multiplayer.is_server() and owner != 0 and owner != sender: return
	var args: Array = _unpack_value(arguments, state)
	if multiplayer.is_server():
		var player: Variant = state.nodes.get("player:%d" % sender)
		if not is_instance_valid(player): return
		args.push_front(LuaScriptEngine.BobuxInstance.wrap(player))
	var instance = LuaScriptEngine.BobuxInstance.wrap(target)
	if not method.begins_with("Invoke"):
		instance._shared_event("OnServerEvent" if multiplayer.is_server() else "OnClientEvent").FireArgs(args)
		return
	var callback_name := "OnServerInvoke" if multiplayer.is_server() else "OnClientInvoke"
	var callback: Variant = target.get_meta(callback_name) if target.has_meta(callback_name) else null
	if not callback is Callable:
		_remote_result.rpc_id(sender, ticket, null, "Remote callback is not installed")
		return
	var result: Variant = _pack_value(callback.callv(args), state)
	if var_to_bytes(result).size() > CHUNK_BYTES:
		_remote_result.rpc_id(sender, ticket, null, "Remote response exceeds the payload limit")
	else: _remote_result.rpc_id(sender, ticket, result, "")

@rpc("any_peer", "call_remote", "reliable")
func _remote_result(ticket: int, result: Variant, error: String) -> void:
	if OS.get_cmdline_user_args().has("--trace-imported-network"): print("[place-net] result ",ticket," ",result," ",error)
	if not _remote_requests.has(ticket): return
	var request: Dictionary = _remote_requests[ticket]
	if multiplayer.get_remote_sender_id() != int(request.peer): return
	var state: Dictionary = _rooms.get(request.room, {}) if multiplayer.is_server() else _client
	if state.is_empty() or str(state.workspace.get_meta("room_id", "")) != request.room: return
	request.result = _unpack_value(result, state)
	request.error = error
	request.done = true

func _exit_tree() -> void:
	_serializer.free()
