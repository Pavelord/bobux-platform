extends SceneTree

# Diagnostic only: original cached published world and Luau are never modified.
# --audit-only skips the actual player walk. Graphics captures require a renderer.
const MAP_FOLDER := "C:/robloxclone/.codex-tmp/performance-server/Godot/app_userdata/Bobux/cache/maps/akx0oto939gi501_dolina_semi_vetrov"
const SOURCE_PATH := "res://.codex-tmp/performance/map-audit/valley-original.luau"
const OUTPUT := "res://.codex-tmp/performance/valley-visual-motion"
var failures: Array[String] = []
var report: Dictionary = {}
var trace: Array[Dictionary] = []
var main: Node
var character: CharacterBody3D
var authored: Node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_FOLDER.path_join("map_data.json")))
	if not (parsed is Dictionary) or not FileAccess.file_exists(SOURCE_PATH):
		push_error("Published Valley cache/original Luau is required.")
		quit(2)
		return
	var data: Dictionary = parsed
	report["source_sha256"] = FileAccess.get_sha256(SOURCE_PATH)
	report["map_sha256"] = FileAccess.get_sha256(MAP_FOLDER.path_join("map_data.json"))
	report["renderer"] = DisplayServer.get_name()
	report["blocks"] = data.blocks.size()
	report["manifest_scale"] = data.roblox_manifest.get("stud_scale", "legacy authored world: root 1:1")
	await audit_assets(data)
	if not OS.get_cmdline_user_args().has("--audit-only"):
		await walk_world()
	report["failures"] = failures
	write_json("report.json", report)
	write_json("trace.json", trace)
	print("[valley-visual-motion] completed assets=", report.get("unique_assets", 0), " phases=", report.get("walk_phases", []), " failures=", failures, " output=", OUTPUT)
	var engine := root.get_node("LuaScriptEngine")
	if is_instance_valid(main):
		engine.stop_all_scripts(main)
		main.queue_free()
		await process_frame
	engine.release_stopped_script_states()
	quit(0 if failures.is_empty() else 1)

func audit_assets(data: Dictionary) -> void:
	var meshes: Dictionary = {}
	var shaders: Dictionary = {}
	var references: Dictionary = {}
	for raw: Dictionary in data.blocks:
		var file := str(raw.get("bobux_mesh_resource_asset", ""))
		if not file.is_empty(): references[file] = int(references.get(file, 0)) + 1
	var started := Time.get_ticks_msec()
	for file: String in references:
		var mesh := ResourceLoader.load(MAP_FOLDER.path_join(file)) as Mesh
		if mesh == null:
			failures.append("Unreadable mesh " + file)
			continue
		var materials: Array = []
		var vertices := 0
		var invalid_vertices := 0
		for i in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(i)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertices += points.size()
			for point: Vector3 in points:
				if not point.is_finite(): invalid_vertices += 1
			var material := mesh.surface_get_material(i)
			var mat_info := {"class": material.get_class() if material != null else "none"}
			if material is ShaderMaterial and material.shader != null:
				var code: String = material.shader.code
				var hash := code.sha256_text()
				mat_info["shader_hash"] = hash
				if not shaders.has(hash):
					shaders[hash] = {"files": [], "code": code}
				if not file in shaders[hash].files: shaders[hash].files.append(file)
			elif material is BaseMaterial3D:
				mat_info["alpha"] = material.albedo_color.a
				mat_info["transparency"] = material.transparency
			materials.append(mat_info)
		var box := mesh.get_aabb()
		var custom := (mesh as ArrayMesh).custom_aabb if mesh is ArrayMesh else AABB()
		meshes[file] = {"references": references[file], "vertices": vertices, "invalid_vertices": invalid_vertices, "aabb_position": vec(box.position), "aabb_size": vec(box.size), "resource_custom_aabb_position": vec(custom.position), "resource_custom_aabb_size": vec(custom.size), "materials": materials}
		if invalid_vertices > 0 or not box.position.is_finite() or not box.size.is_finite(): failures.append("Nonfinite mesh " + file)
		if meshes.size() % 16 == 0: await process_frame
	write_json("assets.json", meshes)
	write_json("shaders.json", shaders)
	report["unique_assets"] = meshes.size()
	report["unique_shader_programs"] = shaders.size()
	report["asset_audit_ms"] = Time.get_ticks_msec() - started
	print("[valley-visual-motion] mesh audit done assets=", meshes.size(), " shaders=", shaders.size())

func walk_world() -> void:
	root.get_node("GameState").selected_map_folder = MAP_FOLDER
	main = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/nds_network_runtime.gd"))
	root.add_child(main)
	current_scene = main
	await main._load_selected_map()
	character = main.add_probe_player(1)
	main._apply_character_map_scale(character, main._map_roblox_manifest)
	root.get_node("LuaScriptEngine").bind_local_player_character(character)
	# Character-ready watchers may start the archived LocalScript. Stop them
	# before measuring the no-script baseline, then restart exactly one copy.
	await wait_seconds(0.5)
	report["automatic_contexts_before_isolation"] = script_contexts()
	# The reused disaster fixture creates an offline server Peer_1 as well as
	# LocalPlayer. Service script clones can live outside the Main ancestry.
	# They are fixture setup, not evidence of duplicate execution on a client.
	for node: Node in root.find_children("*", "Node", true, false):
		if str(node.get_meta("roblox_class", "")) in ["Script", "LocalScript"]: node.set_meta("disabled", true)
	root.get_node("LuaScriptEngine").stop_all_scripts()
	root.get_node("LuaScriptEngine").release_stopped_script_states()
	character.set_lua_position(Vector3(46, 24, 26))
	character.set_initial_spawn_position(character.global_position)
	character._reset_all_physics_interpolation()
	character.set_physics_process(true)
	character.set_process(true)
	character.player_camera.current = true
	await process_frame
	report["shader_bounds_at_spawn"] = shader_bounds_at_spawn()
	var meshes: Array[Dictionary] = []
	for node: Node in main.world.get_children():
		if node is MeshInstance3D and node.global_position.distance_to(Vector3(46, 18.609, 26)) < 110:
			var box: AABB = node.global_transform * node.get_aabb()
			meshes.append({"name": str(node.name), "position": vec(node.global_position), "asset": node.get_meta("bobux_mesh_resource_asset", ""), "world_aabb_position": vec(box.position), "world_aabb_size": vec(box.size), "scale": node.get_meta("roblox_stud_scale", "inherited"), "lua_scale": root.get_node("LuaScriptEngine").BobuxInstance.wrap(node)._stud_scale(), "collidable": node.get_meta("can_collide", true)})
	write_json("spawn_geometry.json", meshes)
	report["player_scale"] = character.world_stud_scale
	report["camera_near"] = character.player_camera.near
	report["camera_far"] = character.player_camera.far
	report["camera_pivot_top_level"] = character.camera_pivot.top_level
	var phases: Array[Dictionary] = []
	check_context_count(0, "without_author_script_before")
	phases.append(await walk_phase("without_author_script"))
	check_context_count(0, "without_author_script_after")
	var engine := root.get_node("LuaScriptEngine")
	engine.script_message.connect(func(context: Node, message: String, error: bool):
		if error: failures.append(str(context.name) + ": " + message))
	authored = Node.new()
	authored.name = "OriginalValleyClient"
	authored.set_meta("bobux_map_asset_folder", MAP_FOLDER)
	authored.set_meta("lua_source", FileAccess.get_file_as_string(SOURCE_PATH))
	main.world.add_child(authored)
	engine.reset_runtime_diagnostics()
	engine.start_script(FileAccess.get_file_as_string(SOURCE_PATH), authored, {"realm": "client", "retain": true})
	await wait_seconds(1.5)
	for button: Node in main.find_children("*", "BaseButton", true, false):
		if button.name == "StartButton": button.pressed.emit()
	phases.append(await walk_phase("original_author_script"))
	check_context_count(1, "original_author_script_after")
	report["walk_phases"] = phases
	report["runtime_diagnostics"] = engine.get_runtime_diagnostics()

func walk_phase(label: String) -> Dictionary:
	character.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	character.set_lua_position(Vector3(46, 24, 26))
	character.velocity = Vector3.ZERO
	character.set_initial_spawn_position(character.global_position)
	character._reset_all_physics_interpolation()
	await wait_seconds(2.0)
	var summary := {"phase": label, "samples": 0, "vertical_jumps_over_1": 0, "max_vertical_step": 0.0, "max_camera_step": 0.0, "minimum_spring": 100.0, "spring_hits": {}, "camera_inside_character_visuals": 0, "start": vec(character.global_position)}
	if OS.get_cmdline_user_args().has("--angle-sweep") or OS.get_cmdline_user_args().has("--angles-only"):
		report[label + "_angle_sweep"] = await angle_sweep(label)
		if OS.get_cmdline_user_args().has("--angles-only"): return summary
	await capture(label + "_start")
	var previous: Vector3 = character.global_position
	var previous_camera: Vector3 = character.player_camera.global_position
	var segments := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for direction: Vector3 in segments:
		character.set_meta("bobux_trace_move_direction", direction)
		var until := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < until:
			await physics_frame
			var position: Vector3 = character.global_position
			var camera: Vector3 = character.player_camera.global_position
			var dy := absf(position.y - previous.y)
			var dc := camera.distance_to(previous_camera)
			var spring: float = character.spring_arm.spring_length
			var hit := camera_collision()
			var enclosing := character_camera_overlap()
			summary.samples += 1
			summary.max_vertical_step = maxf(summary.max_vertical_step, dy)
			summary.max_camera_step = maxf(summary.max_camera_step, dc)
			summary.minimum_spring = minf(summary.minimum_spring, spring)
			if dy > 1.0: summary.vertical_jumps_over_1 += 1
			if not enclosing.is_empty(): summary.camera_inside_character_visuals += 1
			if not hit.is_empty(): summary.spring_hits[hit.name] = int(summary.spring_hits.get(hit.name, 0)) + 1
			trace.append({"phase": label, "ticks": Engine.get_physics_frames(), "position": vec(position), "camera": vec(camera), "spring_length": spring, "vertical_step": dy, "camera_step": dc, "hit": hit, "camera_inside_mesh_aabbs": enclosing, "grounded": character.is_on_floor()})
			previous = position
			previous_camera = camera
		await capture(label + "_segment_" + str(segments.find(direction)))
	character.set_meta("bobux_trace_move_direction", Vector3.ZERO)
	await wait_seconds(1.0)
	summary["end"] = vec(character.global_position)
	print("[valley-visual-motion] phase=", summary)
	return summary

func angle_sweep(label: String) -> Array[Dictionary]:
	var observations: Array[Dictionary] = []
	var sky := main.world.find_child("SkyDome", true, false) as MeshInstance3D
	if sky == null:
		failures.append("Published sky node is missing")
		return observations
	character.set_physics_process(false)
	var original_rotation: Vector3 = character.camera_pivot.rotation
	for pitch: float in [-0.2, 0.35, 0.9]:
		for yaw in range(0, 360, 15):
			character.camera_pivot.rotation = Vector3(pitch, deg_to_rad(float(yaw)), 0)
			character._update_local_camera_rig_render_phase(0.016)
			await physics_frame
			var box: AABB = sky.global_transform * sky.get_aabb()
			var effective_box: AABB = sky.global_transform * effective_bounds(sky)
			var visible_corners := 0
			for i in range(8):
				var point := box.position + box.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
				if character.player_camera.is_position_in_frustum(point): visible_corners += 1
			var expected_vertex: Vector3 = character.player_camera.global_position - character.player_camera.global_basis.z * character.player_camera.far * 0.9
			observations.append({"pitch_radians": pitch, "yaw_degrees": yaw, "camera": vec(character.player_camera.global_position), "spring_length": character.spring_arm.spring_length, "camera_collision": camera_collision(), "sky_vertex_aabb_corners_in_frustum": visible_corners, "sky_effective_bounds_intersect_frustum": box_intersects_frustum(effective_box, character.player_camera), "sky_effective_bounds_contain_camera": effective_box.has_point(character.player_camera.global_position), "sky_effective_bounds_contain_forward_shader_vertex": effective_box.has_point(expected_vertex), "camera_inside_mesh_aabbs": character_camera_overlap()})
			if DisplayServer.get_name() != "headless" and yaw % 45 == 0:
				await capture(label + "_pitch_" + str(pitch) + "_yaw_" + str(yaw))
	character.camera_pivot.rotation = original_rotation
	character._update_local_camera_rig_render_phase(0.016)
	character.set_physics_process(true)
	return observations

func script_contexts() -> Array[Dictionary]:
	var engine := root.get_node("LuaScriptEngine")
	var contexts: Array[Dictionary] = []
	var seen: Dictionary = {}
	for collection: Dictionary in [engine._script_runtimes, engine._retained_lua_states]:
		for runtime: Dictionary in collection.values():
			var context: Node = runtime.get("context")
			if not is_instance_valid(context) or seen.has(context.get_instance_id()): continue
			seen[context.get_instance_id()] = true
			var code := str(context.get_meta("lua_source", context.get_meta("code", "")))
			contexts.append({"path": str(context.get_path()), "class": context.get_meta("roblox_class", "diagnostic context"), "source_sha256": code.sha256_text(), "source_name": runtime.get("source_name", ""), "realm": runtime.get("realm", "")})
	return contexts

func check_context_count(expected: int, label: String) -> void:
	var contexts := script_contexts()
	report[label + "_contexts"] = contexts
	if contexts.size() != expected: failures.append("%s requires %d contexts, got %d; comparison is invalid" % [label, expected, contexts.size()])

func character_camera_overlap() -> Array[String]:
	var enclosing: Array[String] = []
	for node: Node in character.get_node("Visuals").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.get_aabb().has_point(mesh.global_transform.affine_inverse() * character.player_camera.global_position): enclosing.append(str(mesh.name))
	return enclosing

func shader_bounds_at_spawn() -> Array[Dictionary]:
	var observations: Array[Dictionary] = []
	for node: Node in main.world.get_children():
		if not node is MeshInstance3D or node.mesh == null: continue
		var asset := str(node.get_meta("bobux_mesh_resource_asset", ""))
		if asset not in ["skyb.res", "rainb.res", "birds0b.res", "butter0b.res"]: continue
		var box: AABB = node.global_transform * node.get_aabb()
		var effective_box: AABB = node.global_transform * effective_bounds(node)
		var resource_custom := (node.mesh as ArrayMesh).custom_aabb if node.mesh is ArrayMesh else AABB()
		var visible_corners := 0
		for i in range(8):
			var point := box.position + box.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
			if character.player_camera.is_position_in_frustum(point): visible_corners += 1
		var expected_shader_point: Vector3 = character.player_camera.global_position - character.player_camera.global_basis.z * character.player_camera.far * 0.9
		observations.append({"name": str(node.name), "asset": asset, "vertex_aabb_position": vec(box.position), "vertex_aabb_size": vec(box.size), "extra_cull_margin": node.extra_cull_margin, "instance_custom_aabb_size": vec(node.custom_aabb.size), "resource_custom_aabb_position": vec(resource_custom.position), "resource_custom_aabb_size": vec(resource_custom.size), "effective_world_aabb_position": vec(effective_box.position), "effective_world_aabb_size": vec(effective_box.size), "effective_bounds_intersect_frustum": box_intersects_frustum(effective_box, character.player_camera), "effective_bounds_contain_camera": effective_box.has_point(character.player_camera.global_position), "vertex_aabb_corners_in_frustum": visible_corners, "camera_forward_far_90_percent_in_frustum": character.player_camera.is_position_in_frustum(expected_shader_point), "note": "Vertex positions differ from culling bounds; explicit ArrayMesh.custom_aabb is the actual renderer override and must be considered."})
	return observations

func effective_bounds(mesh: MeshInstance3D) -> AABB:
	if mesh.custom_aabb != AABB(): return mesh.custom_aabb
	if mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).custom_aabb != AABB(): return (mesh.mesh as ArrayMesh).custom_aabb
	return mesh.get_aabb()

func box_intersects_frustum(box: AABB, camera: Camera3D) -> bool:
	# A large enclosing box can intersect the frustum even with all eight
	# corners outside. Reject only when every corner is beyond one plane.
	var inside := camera.global_position - camera.global_basis.z * (camera.near + camera.far) * 0.5
	for plane: Plane in camera.get_frustum():
		var side := signf(plane.distance_to(inside))
		var separated := true
		for i in range(8):
			var point := box.position + box.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
			if plane.distance_to(point) * side >= -0.001:
				separated = false
				break
		if separated: return false
	return true

func camera_collision() -> Dictionary:
	var origin: Vector3 = character.camera_pivot.global_position
	var target: Vector3 = origin + character.camera_pivot.global_basis.z.normalized() * character._world_units(character._camera_desired_spring_length)
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [character.get_rid()]
	query.collision_mask = character._get_world_collision_mask()
	query.collide_with_areas = false
	var hit := character.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var node: Node = hit.collider
	var visual := node.get_parent() if node != null else null
	return {"name": str(visual.name if visual != null else node.name), "distance": origin.distance_to(hit.position), "position": vec(hit.position)}

func wait_seconds(duration: float) -> void:
	var until := Time.get_ticks_msec() + roundi(duration * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func write_json(file: String, value: Variant) -> void:
	var handle := FileAccess.open(OUTPUT.path_join(file), FileAccess.WRITE)
	if handle != null: handle.store_string(JSON.stringify(value, "\t"))
