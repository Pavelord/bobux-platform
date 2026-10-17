extends SceneTree

var player_fixture: Script
const BEHAVIOR = preload("res://tools/fixtures/avatar_attachment_behavior.gd")
var failures: Array[String] = []
var listener := TCPServer.new()
var clients: Array[Dictionary] = []
var requests: Dictionary = {}
var outcomes: Array[Dictionary] = []
var glb_bytes: PackedByteArray
var frames: int = 0
var cache_paths: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	print("[avatar-attachment] ", "PASS " if ok else "FAIL ", detail)
	if not ok: failures.append(detail)

func serve() -> void:
	frames += 1
	if listener.is_connection_available():
		clients.append({"peer": listener.take_connection(), "request": "", "received": 0})
	for client in clients:
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
		if peer.get_available_bytes() > 0:
			client.request += peer.get_utf8_string(peer.get_available_bytes())
			if client.received == 0 and "\r\n\r\n" in client.request:
				client.received = Time.get_ticks_msec()
				client.route = str(client.request).split(" ")[1]
				requests[client.route] = int(requests.get(client.route, 0)) + 1
		if client.received > 0 and not client.get("sent", false) and Time.get_ticks_msec() - client.received >= 180:
			var body: PackedByteArray = glb_bytes
			if client.route == "/repair.glb" and requests[client.route] == 1:
				body = "<html>This was a proxy error instead of the avatar asset.</html>".to_utf8_buffer()
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer())
			peer.put_data(body)
			client.sent = true

func new_player() -> Node:
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.set_script(player_fixture)
	root.add_child(player)
	return player

func download_model(player: Node, url: String, label: String) -> void:
	var model: Node = await player._instantiate_avatar_attachment_source(url)
	outcomes.append({"model": model, "label": label})

func await_outcomes(count: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 7000
	while outcomes.size() < count and Time.get_ticks_msec() < deadline: await process_frame

func fixture_model(with_script: bool = false, emissive: bool = true) -> Node3D:
	var model := Node3D.new()
	model.name = "OriginalSource"
	model.set_meta("source_marker", "original-geometry")
	var mesh := MeshInstance3D.new()
	mesh.name = "SourceMesh"
	var source_mesh := ArrayMesh.new()
	source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	mesh.mesh = source_mesh
	mesh.position = Vector3(1.5, 2.0, 3.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.emission_enabled = emissive
	material.emission = Color(1, 0.5, 0.1)
	material.emission_energy_multiplier = 0.4
	mesh.mesh.surface_set_material(0, material)
	model.add_child(mesh)
	mesh.owner = model
	if with_script:
		var behavior := Node3D.new()
		behavior.name = "Behavior"
		behavior.set_script(BEHAVIOR)
		model.add_child(behavior)
		behavior.owner = model
	return model

func mesh_of(model: Node) -> MeshInstance3D:
	return model.find_child("SourceMesh", true, false) as MeshInstance3D if model != null else null

func run() -> void:
	player_fixture = load("res://tools/fixtures/avatar_attachment_player.gd")
	var folder := "user://validation/avatar_attachment_cache"
	DirAccess.make_dir_recursive_absolute(folder)
	var original := fixture_model()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var glb_path := folder.path_join("fixture.glb")
	check(document.append_from_scene(original, state) == OK and document.write_to_filesystem(state, glb_path) == OK, "real textured-format GLB fixture exports")
	glb_bytes = FileAccess.get_file_as_bytes(glb_path)
	original.free()
	check(listener.listen(0, "127.0.0.1") == OK, "asset HTTP fixture listens")
	process_frame.connect(serve)
	var base := "http://127.0.0.1:%d" % listener.get_local_port()
	var player := new_player()
	for route in ["/shared.glb", "/survive.glb", "/repair.glb"]:
		var local_path: String = player._avatar_attachment_cache_path(base + route)
		cache_paths.append(local_path)
		if FileAccess.file_exists(local_path): DirAccess.remove_absolute(local_path)
	for index in 8: download_model(player, base + "/shared.glb", str(index))
	await await_outcomes(8)
	check(outcomes.size() == 8 and outcomes.all(func(result: Dictionary): return result.model is Node3D), "all eight avatars load their accessory")
	check(requests.get("/shared.glb", 0) == 1 and player_fixture.source_import_count == 1, "concurrent avatars share one download and one GLB parse")
	if outcomes.size() >= 2:
		var first: Node = outcomes[0].model
		var second: Node = outcomes[1].model
		root.add_child(first)
		root.add_child(second)
		var first_mesh := mesh_of(first)
		var second_mesh := mesh_of(second)
		check(first != second and first_mesh != second_mesh and first_mesh.mesh == second_mesh.mesh, "every avatar gets independent nodes while geometry is reused")
		check(first_mesh.position.is_equal_approx(Vector3(1.5, 2.0, 3.0)) and first_mesh.get_active_material(0).emission_enabled, "original transform and emissive material survive cached import")
		player._apply_avatar_attachment_source_fallback_colors(first, [{"name": "SourceMesh", "color": "ff0000"}])
		player._apply_avatar_attachment_source_fallback_colors(second, [{"name": "SourceMesh", "color": "0000ff"}])
		check(first_mesh.get_active_material(0).emission_enabled and first_mesh.get_active_material(0).albedo_color == Color.WHITE and second_mesh.get_active_material(0).emission_enabled, "fallback colours preserve an authored emissive material")
	for result in outcomes: if result.model != null: result.model.free()
	outcomes.clear()
	var disappearing := new_player()
	disappearing._resolve_avatar_attachment_source_path(base + "/survive.glb")
	while not requests.has("/survive.glb"): await process_frame
	download_model(player, base + "/survive.glb", "survivor")
	disappearing.free()
	await await_outcomes(1)
	check(outcomes.size() == 1 and outcomes[0].model != null and requests.get("/survive.glb", 0) == 1, "freeing the first preview cannot cancel a shared download")
	for result in outcomes: if result.model != null: result.model.free()
	outcomes.clear()
	download_model(player, base + "/repair.glb", "repair")
	await await_outcomes(1)
	check(outcomes.size() == 1 and outcomes[0].model != null and requests.get("/repair.glb", 0) == 2, "an HTTP 200 error page is rejected and repaired instead of becoming a permanent missing model")
	for result in outcomes: if result.model != null: result.model.free()
	outcomes.clear()
	var header_path := folder.path_join("truncated.glb")
	var file := FileAccess.open(header_path, FileAccess.WRITE)
	file.store_buffer(glb_bytes.slice(0, glb_bytes.size() - 20))
	file.close()
	check(not player._avatar_attachment_cached_file_valid(header_path), "a truncated GLB is rejected even when larger than 32 bytes")
	var packed_source := fixture_model(true, false)
	var packed := PackedScene.new()
	packed.pack(packed_source)
	var packed_path := folder.path_join("behavior.tscn")
	check(ResourceSaver.save(packed, packed_path) == OK, "scripted PackedScene fixture saves")
	packed_source.free()
	var scripted_first: Node = await player._instantiate_avatar_attachment_source(packed_path)
	var scripted_second: Node = await player._instantiate_avatar_attachment_source(packed_path)
	if scripted_first != null and scripted_second != null:
		root.add_child(scripted_first)
		root.add_child(scripted_second)
		player._apply_avatar_attachment_source_fallback_colors(scripted_first, [{"name": "SourceMesh", "color": "ff0000"}])
		player._apply_avatar_attachment_source_fallback_colors(scripted_second, [{"name": "SourceMesh", "color": "0000ff"}])
		check(mesh_of(scripted_first).get_active_material(0).albedo_color == Color.RED and mesh_of(scripted_second).get_active_material(0).albedo_color == Color.BLUE, "per-avatar fallback colours do not leak through the cache")
		check(scripted_first.get_meta("source_marker") == "original-geometry" and scripted_first.get_node("Behavior").increment() == 8 and scripted_second.get_node("Behavior").counter == 7, "PackedScene metadata and per-instance script state retain their full behaviour")
	else: check(false, "scripted PackedScene loads")
	# Allow the material's deferred RenderingServer update to settle, matching
	# the live avatar's queue_free lifecycle rather than destroying it mid-setter.
	await process_frame
	var material_keepalive: Array[Material] = []
	for model in [scripted_first, scripted_second]:
		if model != null: material_keepalive.append(mesh_of(model).get_active_material(0))
	if scripted_first != null: scripted_first.free()
	if scripted_second != null: scripted_second.free()
	var vertex_source := fixture_model(false, false)
	var vertex_mesh := mesh_of(vertex_source)
	var arrays: Array = vertex_mesh.mesh.surface_get_arrays(0)
	var vertex_colors := PackedColorArray()
	vertex_colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	vertex_colors.fill(Color(0.2, 0.4, 0.8))
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	var coloured_mesh := ArrayMesh.new()
	coloured_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	coloured_mesh.surface_set_material(0, vertex_mesh.get_active_material(0))
	vertex_mesh.mesh = coloured_mesh
	var vertex_packed := PackedScene.new()
	vertex_packed.pack(vertex_source)
	var vertex_path := folder.path_join("vertex_color.tscn")
	ResourceSaver.save(vertex_packed, vertex_path)
	vertex_source.free()
	var vertex_model: Node = await player._instantiate_avatar_attachment_source(vertex_path)
	if vertex_model != null:
		root.add_child(vertex_model)
		material_keepalive.append(mesh_of(vertex_model).get_active_material(0))
		player._apply_avatar_attachment_source_fallback_colors(vertex_model, [{"name": "SourceMesh", "color": "ff0000"}])
		check(mesh_of(vertex_model).get_active_material(0).vertex_color_use_as_albedo and mesh_of(vertex_model).get_active_material(0).albedo_color == Color.WHITE, "PackedScene vertex colours survive loading, caching and fallback tint")
		vertex_model.free()
	else: check(false, "vertex-coloured PackedScene loads")
	check(root.get_node("CloudAPI")._asset_download_jobs.is_empty() and frames > 5, "shared jobs finish while the main loop remains responsive")
	listener.stop()
	for client in clients: client.peer.disconnect_from_host()
	player.free()
	for path in cache_paths + [glb_path, header_path, packed_path, vertex_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("AVATAR_ATTACHMENT_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "requests": requests, "imports": player_fixture.source_import_count}))
	quit(0 if failures.is_empty() else 1)
