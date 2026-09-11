extends SceneTree

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var index := int(args[0]) if not args.is_empty() else 0
	var path := "res://.codex-tmp/roblox_compat/%d.json" % index
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var importer := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
	importer.scale_factor = 1.0
	var parents: Dictionary = importer._build_parent_map(parsed.hierarchy)
	var started := Time.get_ticks_msec()
	var manifest: Dictionary = importer._build_roblox_place_manifest(parsed, parsed.instances, parsed.hierarchy, parents)
	FileAccess.open("res://.codex-tmp/roblox_compat/%d_manifest.json" % index, FileAccess.WRITE).store_string(JSON.stringify(manifest))
	var failures: Array = []
	var compiled := {}
	var engine := root.get_node("LuaScriptEngine")
	for script in manifest.scripts:
		var source := str(script.source)
		var key := source.sha256_text()
		if not compiled.has(key):
			compiled[key] = engine.validate_script_source(source)
		if not compiled[key].get("ok", false):
			failures.append({"ref": script.ref, "name": script.name, "class": script.class, "error": compiled[key].get("error", "")})
		if compiled.size() % 24 == 0: await process_frame
	var refs := {}
	for section in ["instances", "tools", "scripts", "gui", "services"]:
		for entry in manifest[section]: refs[str(entry.ref)] = true
	var missing_storage_parts: Array = []
	for ref in parsed.instances:
		var item: Dictionary = parsed.instances[ref]
		if importer._is_part_class(item.class) and importer._service_name_for_ref(ref, parents, parsed.instances) != "Workspace" and not refs.has(ref): missing_storage_parts.append(ref)
	var report := {"index": index, "source_instances": parsed.instances.size(), "scripts": manifest.scripts.size(), "unique_sources": compiled.size(), "compile_failures": failures, "missing_storage_parts": missing_storage_parts.size(), "seconds": (Time.get_ticks_msec() - started) / 1000.0}
	FileAccess.open("res://.codex-tmp/roblox_compat/%d_runtime_audit.json" % index, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[rbxl_audit] index=%d instances=%d scripts=%d unique=%d compile_errors=%d missing_parts=%d seconds=%.1f" % [index, report.source_instances, report.scripts, report.unique_sources, failures.size(), missing_storage_parts.size(), report.seconds])
	quit()
