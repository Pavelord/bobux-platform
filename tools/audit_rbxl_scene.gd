extends SceneTree

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var index := int(args[0]) if not args.is_empty() else 2
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex-tmp/roblox_compat/%d.json" % index))
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var workspace: Node3D = studio.placement_parent
	var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
	importer.scale_factor = 0.5
	importer.defer_studio_explorer_refresh = true
	var started := Time.get_ticks_msec()
	var report: Dictionary = await importer.import_json_async(parsed, workspace, studio)
	print("[scene_audit] geometry=", report.parts, " elapsed=", (Time.get_ticks_msec() - started) / 1000.0)
	var engine := root.get_node("LuaScriptEngine")
	var manifest: Dictionary = studio.get_meta("roblox_place_manifest")
	var installed: Dictionary = await engine.install_roblox_manifest_async(manifest, workspace)
	print("[scene_audit] installed=", installed)
	var refs := {}
	engine._index_nodes_by_roblox_ref(studio.data_model, refs)
	engine._index_nodes_by_roblox_ref(workspace, refs)
	var missing: Array = []
	var wrong_parent: Array = []
	var geometry_missing: Array = []
	var parents: Dictionary = importer._build_parent_map(parsed.hierarchy)
	for ref in parsed.instances:
		if not refs.has(ref):
			missing.append({"ref": ref, "class": parsed.instances[ref].class})
			continue
		var node: Node = refs[ref]
		var parent_ref := str(parents.get(ref, ""))
		if refs.has(parent_ref) and node.get_parent() != refs[parent_ref]:
			# PlayerGui/Backpack clones have the same source refs; inspect authored nodes instead.
			wrong_parent.append(ref)
		if node is MeshInstance3D and node.mesh == null and not bool(node.get_meta("bobux_deferred_geometry", false)): geometry_missing.append(ref)
	var errors: Array = []
	if args.has("play"):
		await studio._start_studio_playtest()
		for frame in range(150): await create_timer(0.02).timeout
		report["play_diagnostics"] = engine.get_runtime_diagnostics()
		await studio._stop_studio_playtest()
	report["installed"] = installed
	report["missing_instances"] = missing
	report["wrong_parent_refs"] = wrong_parent
	report["missing_geometry_refs"] = geometry_missing
	report["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	FileAccess.open("res://.codex-tmp/roblox_compat/%d_scene_audit.json" % index, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[scene_audit] index=", index, " missing=", missing.size(), " parents=", wrong_parent.size(), " geometry=", geometry_missing.size(), " seconds=", report.seconds)
	engine.stop_all_scripts()
	studio.queue_free()
	await process_frame
	quit()
