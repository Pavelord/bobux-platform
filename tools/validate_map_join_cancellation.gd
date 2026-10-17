extends SceneTree
## Delay a real MapManager reload and replace its session before it completes.
class DelayedMapScene extends Node:
	signal finish_reload
	var reloading := false
	func reload_runtime_map_from_game_state() -> Dictionary:
		reloading = true
		await finish_reload
		return {"ok": true}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var network := root.get_node("NetworkManager")
	var state := root.get_node("GameState")
	var maps := root.get_node("MapManager")
	var failures: Array[String] = []
	var helper := root.get_node("EditorTestServer")
	for endpoint in ["ws://127.0.0.1:17860/ws", "ws://localhost:17860"]:
		if helper._validated_debug_endpoint(endpoint) != endpoint: failures.append("Valid loopback endpoint rejected")
	for endpoint in ["ws://127.0.0.1:123@public.example/ws", "ws://localhost:123@public.example/ws", "ws://127.0.0.1:65536", "ws://public.example:17860", "wss://localhost:17860"]:
		if not helper._validated_debug_endpoint(endpoint).is_empty(): failures.append("Non-loopback debug authority accepted")
	var map_events: Array = []
	maps.map_loaded.connect(func(id, result): map_events.append({"id": id, "result": result}))
	var scene := DelayedMapScene.new()
	root.add_child(scene)
	current_scene = scene
	var api: MultiplayerAPI = network._multiplayer_api()
	var old_peer := OfflineMultiplayerPeer.new()
	api.multiplayer_peer = old_peer
	network._client_attempt_serial += 1
	network._confirm_room_join({"room_id": "cancel-old", "map_id": "classic", "map_name": "Classic"})
	if not scene.reloading: failures.append("Real map reload did not wait")
	network.disconnect_from_session()
	var next_peer := OfflineMultiplayerPeer.new()
	api.multiplayer_peer = next_peer
	network._client_attempt_serial += 1
	network._active_room_id = "next-room"
	state.selected_map = "next-map"
	scene.finish_reload.emit()
	for frame in 3: await process_frame
	if api.multiplayer_peer != next_peer: failures.append("Old map join replaced the new peer")
	if network._active_room_id != "next-room" or state.selected_map != "next-map": failures.append("Old completion overwrote the newer map")
	if not network._connect_timeout_timer.is_stopped(): failures.append("Old map join rearmed an authentication timeout")
	if not map_events.is_empty(): failures.append("Canceled map emitted successful completion")
	var rejected: Dictionary = await maps.load_map("classic", "Classic", "", func(): return false)
	if not rejected.get("cancelled", false) or state.selected_map != "next-map": failures.append("Canceled load modified GameState")
	# Independent preload remains supported without the optional join callback.
	scene.reloading = false
	var completed: Array = []
	preload_independently(maps, completed)
	if not scene.reloading: failures.append("Independent preload was cancelled")
	scene.finish_reload.emit()
	for frame in 2: await process_frame
	if completed.is_empty() or not completed[0].get("ok", false) or state.selected_map != "classic": failures.append("Independent preload failed")
	network.disconnect_from_session()
	scene.queue_free()
	await process_frame
	print("[map-join-cancellation] failures=", failures)
	quit(0 if failures.is_empty() else 1)

func preload_independently(maps: Node, completed: Array) -> void:
	completed.append(await maps.load_map("classic", "Classic"))
