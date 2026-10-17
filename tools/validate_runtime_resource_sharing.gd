extends SceneTree

const ShaderCache = preload("res://addons/roblox_runtime/roblox_shader_cache.gd")
const MaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")
var failures: Array[String] = []
var listener := TCPServer.new()
var clients: Array = []
var requests := 0
var outcomes: Array = []
var frames := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("[resource-sharing] ", message, "=", ok)
	if not ok: failures.append(message)

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
				requests += 1
		if client.received > 0 and not client.get("sent", false) and Time.get_ticks_msec() - client.received > 150:
			var body := "second!" if "GET /second " in client.request else "fixture"
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\n" + body).to_utf8_buffer())
			client.sent = true

func download(url: String, path: String) -> void:
	outcomes.append(await root.get_node("CloudAPI").download_map_asset_file(url, path))

func run() -> void:
	var meshes: Array[ArrayMesh] = []
	var materials: Array[ShaderMaterial] = []
	for index in 2:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = "shader_type spatial; uniform float tint; void fragment() { ALBEDO = vec3(tint); }"
		material.set_shader_parameter("tint", 0.2 + index * 0.5)
		mesh.surface_set_material(0, material)
		ShaderCache.share_mesh_programs(mesh)
		meshes.append(mesh)
		materials.append(material)
	check(materials[0].shader == materials[1].shader, "identical programs share a shader")
	check(materials[0].get_shader_parameter("tint") != materials[1].get_shader_parameter("tint"), "material uniforms stay independent")
	var engine := root.get_node("LuaScriptEngine")
	var folder := "user://validation/resource_sharing"
	DirAccess.make_dir_recursive_absolute(folder)
	var mesh_path := folder.path_join("mesh.res")
	check(ResourceSaver.save(meshes[0], mesh_path) == OK, "native mesh fixture saves")
	var parts: Array[MeshInstance3D] = []
	for index in 2:
		var part := MeshInstance3D.new()
		root.add_child(part)
		engine._apply_manifest_properties_to_node(part, {"BobuxMeshResource": mesh_path})
		parts.append(part)
	check(parts[0].mesh == parts[1].mesh, "network metadata preserves shared mesh")
	parts[0].set_surface_override_material(0, StandardMaterial3D.new())
	check(parts[1].get_active_material(0) is ShaderMaterial, "one part cannot overwrite its sibling material")
	var cache := MaterialCache.new()
	var first := cache.get_shared_named_material(Color.RED, "Plastic")
	check(first == cache.get_shared_named_material(Color.RED, "Plastic"), "runtime named materials are pooled")
	check(cache.get_named_material(Color.RED, "Plastic") != cache.get_named_material(Color.RED, "Plastic"), "Studio named materials remain editable copies")
	var main: Node = load("res://scripts/main/main.gd").new()
	check(main._get_runtime_primitive_mesh("Box", first) == main._get_runtime_primitive_mesh("Spawn", first), "equivalent primitive geometry is pooled")
	var textured := StandardMaterial3D.new()
	textured.uv1_triplanar = true
	textured.set_meta("bobux_texture_tile_studs", 4.0)
	for part in parts:
		part.mesh = BoxMesh.new()
		part.material_override = textured
		part.scale = Vector3(8, 4, 2)
		MaterialCache.sync_texture_scale(part, 1.0)
	check(parts[0].material_override == parts[1].material_override and parts[0].material_override.uv1_scale == Vector3(2, 1, 0.5), "texture scale variants share exact repeats")
	var shared_before: Material = parts[1].material_override
	var wrapper = engine.BobuxInstance.wrap(parts[0])
	wrapper.Color = Color.BLUE
	var editable: Material = parts[0].material_override
	wrapper.Color = Color.RED
	check(parts[0].material_override == editable and editable.albedo_color == Color.RED, "animated colour reuses the detached material")
	check(parts[1].material_override == shared_before and shared_before.albedo_color == Color.WHITE, "animated colour preserves shared assets and sibling appearance")
	parts[1].material_override = editable
	engine.BobuxInstance.wrap(parts[1]).Color = Color.GREEN
	check(parts[0].material_override.albedo_color == Color.RED and parts[1].material_override != editable, "rebinding an owned material still detaches another part")
	check(listener.listen(0, "127.0.0.1") == OK, "HTTP fixture listens")
	process_frame.connect(serve)
	var asset_path := folder.path_join("same.bin")
	var url := "http://127.0.0.1:%d/asset" % listener.get_local_port()
	for index in 8: download(url, asset_path)
	var deadline := Time.get_ticks_msec() + 5000
	while outcomes.size() < 8 and Time.get_ticks_msec() < deadline: await process_frame
	check(outcomes.size() == 8 and outcomes.all(func(result): return result.get("ok", false)), "all concurrent download callers succeed")
	check(requests == 1 and FileAccess.get_file_as_string(asset_path) == "fixture", "one HTTP request owns the shared output file")
	outcomes.clear()
	download(url, asset_path)
	download(url.replace("/asset", "/second"), asset_path)
	deadline = Time.get_ticks_msec() + 5000
	while outcomes.size() < 2 and Time.get_ticks_msec() < deadline: await process_frame
	check(outcomes.size() == 2 and outcomes.all(func(result): return result.get("ok", false)), "different URLs sharing one destination both finish")
	check(requests == 3 and FileAccess.get_file_as_string(asset_path) == "second!", "different URLs serialize writes without reusing the wrong asset")
	check(root.get_node("CloudAPI")._asset_download_jobs.is_empty() and frames > 3, "download jobs clear while the main loop stays responsive")
	listener.stop()
	for client in clients: client.peer.disconnect_from_host()
	for part in parts: part.free()
	main.free()
	for file in [mesh_path, asset_path]: DirAccess.remove_absolute(file)
	print("[resource-sharing] failures=", failures)
	quit(0 if failures.is_empty() else 1)
