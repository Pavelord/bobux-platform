extends Node
## A room owns one imported DataModel. Clients receive its live instances, not
## another invocation of the place's server scripts. Native avatars keep their
## existing movement channel; authored teleports/forces originate here.

signal replica_ready(workspace: Node)

const DataModel = preload("res://addons/roblox_studio/roblox_data_model.gd")
const Physics = preload("res://addons/roblox_runtime/roblox_part_physics.gd")
const SERVICES = ["Workspace", "Players", "Lighting", "ReplicatedStorage", "Teams"]
const CHUNK_BYTES = 12000
const MAX_TRANSFER_BYTES = 32 * 1024 * 1024
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

func networked() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

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
			var waiting: Dictionary = _client.get("character_commands", {})
			_client.erase("character_commands")
			for method in waiting: _character_command(_client.room, method, waiting[method])

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
		return str(state.workspace.get_meta("bobux_map_asset_folder", "")).path_join(value.trim_prefix("$asset:"))
	return value

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
	for existing_peer in _subscriptions:
		if _subscriptions[existing_peer].room == room and existing_peer != peer:
			var visible := _for_peer(changes, existing_peer)
			if not visible.is_empty(): _send_transaction(existing_peer, int(_subscriptions[existing_peer].token), {"ops": visible})
	var ops: Array = []
	for entry in state.records.values(): ops.append(["put", entry])
	_subscriptions[peer] = {"room": room, "token": token}
	var initial_character := {}
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if character.get_multiplayer_authority() == peer and workspace_for(character) == state.workspace:
			initial_character = {"position": character.global_position - state.workspace.global_position, "health": character.get("current_health")}
	_send_transaction(peer, token, {"snapshot": true, "ops": _for_peer(ops, peer), "character": initial_character})

func _send_transaction(peer: int, token: int, data: Dictionary) -> void:
	var raw := var_to_bytes(data)
	if raw.size() > MAX_TRANSFER_BYTES:
		push_error("Imported place snapshot exceeds the supported transfer size")
		return
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var transfer := Time.get_ticks_usec()
	var total := ceili(float(compressed.size()) / CHUNK_BYTES)
	for index in total:
		_outgoing.append([peer, token, transfer, index, total, raw.size(), compressed.slice(index * CHUNK_BYTES, (index + 1) * CHUNK_BYTES)])

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

func _process(delta: float) -> void:
	var cleanup_start := Time.get_ticks_usec()
	while not _retired.is_empty() and Time.get_ticks_usec() - cleanup_start < 2000:
		var retired: Node = _retired.pop_back()
		if is_instance_valid(retired): retired.free()
	# A cold room may still be building when the client finishes its local
	# geometry. Retry that initial request, without restarting the connection.
	if not _client.is_empty() and not bool(_client.ready) and not _applying and _incoming.is_empty() and _pending.is_empty() and networked():
		if Time.get_ticks_msec() - int(_client.get("snapshot_requested_msec", 0)) >= 2000:
			_client.snapshot_requested_msec = Time.get_ticks_msec()
			_request_snapshot.rpc_id(1, int(_client.token))
	for index in mini(8, _outgoing.size()):
		var packet: Array = _outgoing.pop_front()
		var peer := int(packet[0])
		if multiplayer.get_peers().has(peer) and _subscriptions.has(peer) and _room_for_peer(peer) == _subscriptions[peer].room:
			_receive_chunk.rpc_id(peer, packet[1], packet[2], packet[3], packet[4], packet[5], packet[6])
	if not _applying and not _pending.is_empty() and not _client.is_empty():
		_apply_transaction(_pending.pop_front())
	_elapsed += delta
	if _elapsed < 0.1: return
	_elapsed = 0.0
	if not networked() or not multiplayer.is_server(): return
	for room in _rooms.keys():
		var state: Dictionary = _rooms[room]
		if not is_instance_valid(state.workspace):
			_rooms.erase(room)
			continue
		var changes := _capture(state)
		for character in get_tree().get_nodes_in_group("roblox_live_characters"):
			if workspace_for(character) != state.workspace: continue
			var health := int(character.get("current_health"))
			var previous := int(character.get_meta("_bobux_replication_health", 100))
			character.set_meta("_bobux_replication_health", health)
			if health <= 0 and previous > 0:
				get_node("/root/LuaScriptEngine").fire_roblox_instance_event(character.get_node_or_null("Humanoid"), "Died", [])
		if changes.is_empty(): continue
		for peer in _subscriptions.keys():
			var sub: Dictionary = _subscriptions[peer]
			if not multiplayer.get_peers().has(peer) or _room_for_peer(peer) != sub.room:
				_subscriptions.erase(peer)
				continue
			if sub.room == room:
				var visible := _for_peer(changes, peer)
				if not visible.is_empty(): _send_transaction(peer, int(sub.token), {"ops": visible})

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
		var engine := get_node("/root/LuaScriptEngine")
		var importer: RefCounted = engine.template_importer_for(state.workspace)
		for value in changed_parts.values():
			if state != _client or not is_instance_valid(state.get("workspace")): break
			if not is_instance_valid(value) or value.is_queued_for_deletion(): continue
			var part := value as MeshInstance3D
			if part.mesh == null: importer.materialize_template_part(part)
			else: importer.restore_part_children(part)
			if part.mesh != null:
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
			if initial.has("position"): _character_command(state.room, "set_lua_position", initial.position)
			if initial.has("health"): _character_command(state.room, "set_health", initial.health)
		else:
			for op in data.get("ops", []):
				if op[0] == "put" and str(op[1].get("class", "")) == "LocalScript":
					var script_node: Variant = state.nodes.get(str(op[1].ref))
					if is_instance_valid(script_node): engine._refresh_authored_scripts_by_id(script_node.get_instance_id())
	_applying = false

func _apply_entry(entry: Dictionary, state: Dictionary, changed_parts: Dictionary) -> void:
	var ref := str(entry.ref)
	var node: Node = state.nodes.get(ref) if is_instance_valid(state.nodes.get(ref)) else null
	var engine := get_node("/root/LuaScriptEngine")
	var created := node == null
	if not state.roots.has(ref):
		var parent: Node = state.nodes.get(str(entry.parent_ref)) if is_instance_valid(state.nodes.get(str(entry.parent_ref))) else null
		if parent == null: return
		if node == null:
			node = DataModel.create_instance(str(entry.class), str(entry.name))
			parent.add_child(node)
			state.nodes[ref] = node
		elif node.get_parent() != parent:
			node.reparent(parent, false)
	var props: Dictionary = _unpack_value(entry.properties, state)
	var previous: Dictionary = node.get_meta("roblox_properties", {})
	var geometry_changed := created
	for key in ["BobuxSize", "Size", "size", "shape", "Shape", "BobuxMeshResource", "BobuxDeferredGeometry", "BobuxTemplateOnly"]:
		if props.get(key) != previous.get(key): geometry_changed = true
	var adapted := entry.duplicate(false)
	adapted.properties = props
	engine._apply_manifest_entry_metadata(node, adapted)
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
		if bool(props.get("Playing", false)): preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").play(node)
		else: preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").stop(node)

func _apply_pose(value: Variant, pose: Transform3D) -> void:
	if not is_instance_valid(value) or not value is Node3D: return
	if not pose.origin.is_finite() or not pose.basis.is_finite(): return
	var node := value as Node3D
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
	if value is Vector3 and method == "set_lua_position": value -= (workspace_for(character) as Node3D).global_position
	_character_command.rpc_id(peer, room, method, value)
	return true

@rpc("authority", "call_remote", "reliable")
func _character_command(room: String, method: String, value: Variant) -> void:
	if _client.is_empty() or room != _client.room: return
	if method not in ["set_lua_position", "set_lua_linear_velocity", "set_health", "apply_external_impulse"]: return
	for character in get_tree().get_nodes_in_group("roblox_live_characters"):
		if character.get_multiplayer_authority() != multiplayer.get_unique_id(): continue
		if method == "set_lua_position": value += (_client.workspace as Node3D).global_position
		character.call(method, value)
		return
	var waiting: Dictionary = _client.get("character_commands", {})
	waiting[method] = value
	_client["character_commands"] = waiting

func forward_gui_click(target: Node) -> void:
	if role(target) != "client" or not _client.get("ready", false): return
	_gui_click.rpc_id(1, str(target.get_meta("roblox_ref", "")))

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
