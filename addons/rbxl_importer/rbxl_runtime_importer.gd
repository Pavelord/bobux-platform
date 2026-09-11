@tool
class_name RbxlRuntimeImporter
extends RefCounted

## Runtime bridge used by Bobux Studio. It imports .rbxl/.rbxlx directly into
## the live place editor using Bobux-native map primitives wherever possible:
## parts become studio_parts, SpawnLocation becomes a Spawn block, and important
## non-part instances become serializable runtime_objects.

const _Converter := preload("res://addons/rbxl_importer/rbxl_converter_bridge.gd")
const _Materials := preload("res://addons/rbxl_importer/material_cache.gd")
const _WedgeBuilder := preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")
const _RobloxSky := preload("res://addons/rbxl_importer/roblox_sky_material.gd")
const _MeshProxy := preload("res://addons/rbxl_importer/roblox_mesh_proxy.gd")
const _MeshJsonLoader := preload("res://addons/rbxl_importer/roblox_mesh_json_loader.gd")
const _CsgPhysicsLoader := preload("res://addons/rbxl_importer/roblox_csg_physics_loader.gd")
const _TerrainBuilder := preload("res://addons/rbxl_importer/terrain_builder.gd")

const RUNTIME_OBJECT_GROUP := "studio_runtime_objects"
const SOUND_CACHE_DIR := "user://rbxl_assets"
const SOUND_CACHE_EXTENSIONS_CSV := "ogg,mp3,wav"
const MAX_IMPORT_POSITION_ABS := 1000000.0
const MAX_IMPORT_BASIS_ABS := 8.0
const MAX_IMPORT_SCALE_ABS := 10000.0
const MAX_EAGER_STORAGE_PARTS := 4096

signal import_started()
signal import_progress(done: int, total: int, message: String)
signal import_finished(report: Dictionary)
signal import_failed(reason: String)

var target_parent_override: Node = null
var scale_factor: float = 0.5
var import_lighting: bool = true
var replace_existing: bool = false
var parts_per_frame: int = 96
var meta_per_frame: int = 192
var max_runtime_preview_nodes: int = 12000
var max_texture_preview_nodes: int = 5000
var apply_standard_mesh_children: bool = true
## Studio performs one authoritative Explorer rebuild after the Roblox
## DataModel has been installed. Skipping the intermediate rebuild avoids
## walking a large imported world twice while the import overlay is active.
var defer_studio_explorer_refresh: bool = false

var _runtime_objects: Array[Dictionary] = []
var _sound_assets: Array[Dictionary] = []
var _runtime_warnings: Array[String] = []
var _material_cache := _Materials.new()
var _runtime_preview_nodes_created: int = 0
var _texture_preview_nodes_created: int = 0
var _runtime_preview_nodes_skipped: int = 0
var _mesh_proxy_nodes_improved: int = 0
var _exact_mesh_nodes_applied: int = 0
var _standard_mesh_nodes_applied: int = 0
var _csg_fallback_nodes_preserved: int = 0
var _terrain_nodes_created: int = 0
var _mesh_asset_cache: Dictionary = {}


func import_file(path: String, studio: Node) -> Dictionary:
	if not is_instance_valid(studio):
		return _fail("studio node is not valid")

	var placement_parent: Node3D = null
	if is_instance_valid(target_parent_override) and target_parent_override is Node3D:
		placement_parent = target_parent_override as Node3D
	elif studio.get("placement_parent") is Node3D:
		placement_parent = studio.get("placement_parent") as Node3D
	if placement_parent == null:
		placement_parent = studio as Node3D
	if placement_parent == null:
		return _fail("placement parent is not available")

	import_started.emit()
	var cache_dir := ProjectSettings.globalize_path("user://rbxl_import_cache")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var json_path := _unique_intermediate_json_path(cache_dir, path)
	var bridge := _Converter.new()
	var conv_err: int = bridge.convert_file(path, json_path)
	if conv_err != OK:
		return _fail("RBXL converter failed: %s" % bridge.last_error, {"converter_error": conv_err})

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return _fail("cannot open intermediate JSON: %s" % json_path)
	var json_text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(json_path)

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("intermediate JSON is malformed")
	return import_json(parsed as Dictionary, placement_parent, studio)


func import_file_async(path: String, studio: Node) -> Dictionary:
	if not is_instance_valid(studio):
		return _fail("studio node is not valid")

	var placement_parent: Node3D = null
	if is_instance_valid(target_parent_override) and target_parent_override is Node3D:
		placement_parent = target_parent_override as Node3D
	elif studio.get("placement_parent") is Node3D:
		placement_parent = studio.get("placement_parent") as Node3D
	if placement_parent == null:
		placement_parent = studio as Node3D
	if placement_parent == null:
		return _fail("placement parent is not available")

	import_started.emit()
	var cache_dir := ProjectSettings.globalize_path("user://rbxl_import_cache")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var json_path := _unique_intermediate_json_path(cache_dir, path)

	import_progress.emit(0, 1, "Converting RBXL")
	var convert_result_variant: Variant = await _run_threaded(
		Callable(self, "_thread_convert_file").bind(path, json_path),
		studio,
		"Converting RBXL"
	)
	if not (convert_result_variant is Dictionary):
		return _fail("RBXL converter thread returned an invalid result")
	var convert_result: Dictionary = convert_result_variant
	var conv_err := int(convert_result.get("error", ERR_BUG))
	if conv_err != OK:
		return _fail("RBXL converter failed: %s" % str(convert_result.get("last_error", "")), {"converter_error": conv_err})

	import_progress.emit(0, 1, "Reading converted JSON")
	var load_result_variant: Variant = await _run_threaded(
		Callable(self, "_thread_load_json").bind(json_path),
		studio,
		"Reading converted JSON"
	)
	if not (load_result_variant is Dictionary):
		return _fail("intermediate JSON loader returned an invalid result")
	var load_result: Dictionary = load_result_variant
	if not bool(load_result.get("ok", false)):
		return _fail(str(load_result.get("error", "intermediate JSON is malformed")))
	var parsed: Variant = load_result.get("json", {})
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("intermediate JSON is malformed")
	return await import_json_async(parsed as Dictionary, placement_parent, studio)


func _thread_convert_file(source_path: String, output_path: String) -> Dictionary:
	var bridge := _Converter.new()
	var conv_err: int = bridge.convert_file(source_path, output_path)
	return {"error": conv_err, "last_error": bridge.last_error}


func _thread_load_json(json_path: String) -> Dictionary:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open intermediate JSON: %s" % json_path}
	var json_text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(json_path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "intermediate JSON is malformed"}
	return {"ok": true, "json": parsed}


func _unique_intermediate_json_path(cache_dir: String, source_path: String) -> String:
	# Multiple editor/test processes may import the same file concurrently.
	# A filename-only key allowed one converter to truncate another job's JSON.
	var base_name := source_path.get_file().get_basename().validate_filename()
	if base_name.is_empty():
		base_name = "place"
	var token := "%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), get_instance_id()]
	return cache_dir.path_join("%s.%s.intermediate.json" % [base_name, token])


func _run_threaded(callable: Callable, studio: Node, message: String) -> Variant:
	var thread := Thread.new()
	var start_err := thread.start(callable)
	if start_err != OK:
		return {"ok": false, "error": "cannot start worker thread", "code": start_err}
	var pulse := 0
	while thread.is_alive():
		pulse += 1
		import_progress.emit(0, 1, "%s%s" % [message, ".".repeat(pulse % 4)])
		await _process_frame_signal(studio)
	return thread.wait_to_finish()


func _process_frame_signal(studio: Node) -> Signal:
	if is_instance_valid(studio) and studio.is_inside_tree():
		return studio.get_tree().process_frame
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		return tree.process_frame
	return RenderingServer.frame_post_draw


func import_json(json: Dictionary, placement_parent: Node3D, studio: Node) -> Dictionary:
	_runtime_objects.clear()
	_sound_assets.clear()
	_runtime_warnings.clear()
	_material_cache.clear()
	_runtime_preview_nodes_created = 0
	_texture_preview_nodes_created = 0
	_runtime_preview_nodes_skipped = 0
	_mesh_proxy_nodes_improved = 0
	_exact_mesh_nodes_applied = 0
	_standard_mesh_nodes_applied = 0
	_csg_fallback_nodes_preserved = 0
	_terrain_nodes_created = 0
	_mesh_asset_cache.clear()

	var instances: Dictionary = json.get("instances", {})
	var hierarchy: Array = json.get("hierarchy", [])
	var parent_map := _build_parent_map(hierarchy)
	var import_scope := _build_import_scope(instances, hierarchy, parent_map)
	var roblox_manifest := _build_roblox_place_manifest(json, instances, hierarchy, parent_map)
	if is_instance_valid(placement_parent):
		placement_parent.set_meta("roblox_stud_scale", scale_factor)
	if is_instance_valid(studio):
		# The manifest can contain tens of thousands of immutable entries. A deep
		# copy here multiplied peak memory before Studio had created the first part.
		studio.set_meta("roblox_place_manifest", roblox_manifest.duplicate(false))

	if replace_existing:
		_clear_existing_editor_content(placement_parent, studio)

	var part_refs: Array[String] = []
	for ref_id in instances:
		var inst: Dictionary = instances[ref_id]
		if _is_part_class(str(inst.get("class", ""))) and _should_import_world_ref(str(ref_id), import_scope):
			part_refs.append(str(ref_id))

	var block_map: Dictionary = {}
	var part_count := 0
	var errors := 0
	var done := 0
	for ref_id in part_refs:
		var inst: Dictionary = instances[ref_id]
		var block := _spawn_part_block(ref_id, str(inst.get("class", "")), inst.get("properties", {}), placement_parent, studio)
		if block != null:
			block_map[ref_id] = block
			part_count += 1
		else:
			errors += 1
		done += 1
		import_progress.emit(done, part_refs.size(), str(inst.get("class", "")))

	var meta_count := 0
	var skipped := 0
	var skipped_classes: Dictionary = {}
	for ref_id in instances:
		if block_map.has(str(ref_id)):
			continue
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", ""))
		if _is_part_class(roblox_class) and not _should_import_world_ref(str(ref_id), import_scope):
			continue
		var props: Dictionary = inst.get("properties", {})
		if _spawn_meta_instance(str(ref_id), roblox_class, props, placement_parent, studio, parent_map, block_map, instances, import_scope):
			meta_count += 1
		elif not _is_structural_class(roblox_class):
			skipped += 1
			skipped_classes[roblox_class] = int(skipped_classes.get(roblox_class, 0)) + 1

	if not defer_studio_explorer_refresh and studio.has_method("_refresh_explorer"):
		studio._refresh_explorer()
	if studio.has_method("_clear_selection"):
		studio._clear_selection()
	if studio.has_method("_commit_editor_history"):
		studio._commit_editor_history("Import RBXL")
	if studio.has_method("_refresh_music_source_ui"):
		studio._refresh_music_source_ui()

	var warnings: Array = []
	var json_warnings: Variant = json.get("warnings", [])
	if json_warnings is Array:
		warnings = (json_warnings as Array).duplicate()
	for warning in _runtime_warnings:
		warnings.append(warning)
	if _runtime_preview_nodes_skipped > 0:
		warnings.append("%d runtime preview node(s) were preserved as metadata only to keep the editor responsive." % _runtime_preview_nodes_skipped)
	if _exact_mesh_nodes_applied > 0:
		warnings.append("%d imported Roblox mesh asset(s) were applied exactly from cached .mesh data." % _exact_mesh_nodes_applied)
	if _standard_mesh_nodes_applied > 0:
		warnings.append("%d Roblox standard mesh child node(s) were materialized procedurally." % _standard_mesh_nodes_applied)
	if _mesh_proxy_nodes_improved > 0:
		warnings.append("%d Roblox mesh asset(s) were unavailable and used fallback geometry." % _mesh_proxy_nodes_improved)
	if _csg_fallback_nodes_preserved > 0:
		warnings.append("%d Roblox CSG operation(s) kept exact AssetId metadata and received editable fallback bodies." % _csg_fallback_nodes_preserved)
	if _terrain_nodes_created > 0:
		warnings.append("%d Roblox Terrain node(s) were imported as voxel GridMap previews." % _terrain_nodes_created)

	var report := {
		"ok": true,
		"parts": part_count,
		"runtime_objects": _runtime_objects.size(),
		"sounds": _sound_assets.size(),
		"nodes": part_count + meta_count,
		"skipped": skipped,
		"skipped_classes": skipped_classes,
		"errors": errors,
		"total_instances": instances.size(),
		"hidden_parts": int(import_scope.get("hidden_part_count", 0)),
		"workspace_parts": int(import_scope.get("world_part_count", part_count)),
		"workspace_filter": bool(import_scope.get("use_workspace_filter", false)),
		"workspace_ref_count": int((import_scope.get("workspace_refs", []) as Array).size()) if import_scope.get("workspace_refs", []) is Array else 0,
		"world_ref_count": int((import_scope.get("world_refs", {}) as Dictionary).size()) if import_scope.get("world_refs", {}) is Dictionary else 0,
		"asset_refs": int((roblox_manifest.get("assets", []) as Array).size()) if roblox_manifest.get("assets", []) is Array else 0,
		"script_refs": int((roblox_manifest.get("scripts", []) as Array).size()) if roblox_manifest.get("scripts", []) is Array else 0,
		"constraint_refs": int((roblox_manifest.get("constraints", []) as Array).size()) if roblox_manifest.get("constraints", []) is Array else 0,
		"tool_refs": int((roblox_manifest.get("tools", []) as Array).size()) if roblox_manifest.get("tools", []) is Array else 0,
		"gui_refs": int((roblox_manifest.get("gui", []) as Array).size()) if roblox_manifest.get("gui", []) is Array else 0,
		"storage_libraries": int((roblox_manifest.get("storage_libraries", []) as Array).size()) if roblox_manifest.get("storage_libraries", []) is Array else 0,
		"preview_nodes": _runtime_preview_nodes_created,
		"preview_skipped": _runtime_preview_nodes_skipped,
		"warnings": warnings,
	}
	import_finished.emit(report)
	print("[RBXL Runtime] Imported %d parts, %d runtime objects, %d sound asset(s). Skipped %d, errors %d." %
		[part_count, _runtime_objects.size(), _sound_assets.size(), skipped, errors])
	return report


func import_json_async(json: Dictionary, placement_parent: Node3D, studio: Node) -> Dictionary:
	_runtime_objects.clear()
	_sound_assets.clear()
	_runtime_warnings.clear()
	_material_cache.clear()
	_runtime_preview_nodes_created = 0
	_texture_preview_nodes_created = 0
	_runtime_preview_nodes_skipped = 0
	_mesh_proxy_nodes_improved = 0
	_exact_mesh_nodes_applied = 0
	_standard_mesh_nodes_applied = 0
	_csg_fallback_nodes_preserved = 0
	_terrain_nodes_created = 0
	_mesh_asset_cache.clear()

	var instances: Dictionary = json.get("instances", {})
	var hierarchy: Array = json.get("hierarchy", [])
	var parent_map := _build_parent_map(hierarchy)
	var import_scope := _build_import_scope(instances, hierarchy, parent_map)
	var roblox_manifest := _build_roblox_place_manifest(json, instances, hierarchy, parent_map)
	if is_instance_valid(placement_parent):
		placement_parent.set_meta("roblox_stud_scale", scale_factor)
	if is_instance_valid(studio):
		studio.set_meta("roblox_place_manifest", roblox_manifest.duplicate(false))

	if replace_existing:
		_clear_existing_editor_content(placement_parent, studio)
		await _process_frame_signal(studio)

	var part_refs: Array[String] = []
	for ref_id in instances:
		var inst: Dictionary = instances[ref_id]
		if _is_part_class(str(inst.get("class", ""))) and _should_import_world_ref(str(ref_id), import_scope):
			part_refs.append(str(ref_id))

	var block_map: Dictionary = {}
	var part_count := 0
	var errors := 0
	var done := 0
	var batch_size: int = maxi(parts_per_frame, 1)
	for ref_id in part_refs:
		var inst: Dictionary = instances[ref_id]
		var block := _spawn_part_block(ref_id, str(inst.get("class", "")), inst.get("properties", {}), placement_parent, studio)
		if block != null:
			block_map[ref_id] = block
			part_count += 1
		else:
			errors += 1
		done += 1
		import_progress.emit(done, part_refs.size(), str(inst.get("class", "")))
		if done % batch_size == 0:
			await _process_frame_signal(studio)

	var meta_count := 0
	var skipped := 0
	var skipped_classes: Dictionary = {}
	var meta_done := 0
	var meta_batch_size: int = maxi(meta_per_frame, 1)
	for ref_id in instances:
		if block_map.has(str(ref_id)):
			continue
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", ""))
		if _is_part_class(roblox_class) and not _should_import_world_ref(str(ref_id), import_scope):
			continue
		var props: Dictionary = inst.get("properties", {})
		if _spawn_meta_instance(str(ref_id), roblox_class, props, placement_parent, studio, parent_map, block_map, instances, import_scope):
			meta_count += 1
		elif not _is_structural_class(roblox_class):
			skipped += 1
			skipped_classes[roblox_class] = int(skipped_classes.get(roblox_class, 0)) + 1
		meta_done += 1
		if meta_done % meta_batch_size == 0:
			import_progress.emit(part_refs.size(), part_refs.size(), "Importing metadata")
			await _process_frame_signal(studio)

	if not defer_studio_explorer_refresh and studio.has_method("_refresh_explorer"):
		studio._refresh_explorer()
	if studio.has_method("_clear_selection"):
		studio._clear_selection()
	if studio.has_method("_commit_editor_history"):
		studio._commit_editor_history("Import RBXL")
	if studio.has_method("_refresh_music_source_ui"):
		studio._refresh_music_source_ui()

	var warnings: Array = []
	var json_warnings: Variant = json.get("warnings", [])
	if json_warnings is Array:
		warnings = (json_warnings as Array).duplicate()
	for warning in _runtime_warnings:
		warnings.append(warning)
	if _runtime_preview_nodes_skipped > 0:
		warnings.append("%d runtime preview node(s) were preserved as metadata only to keep the editor responsive." % _runtime_preview_nodes_skipped)
	if _exact_mesh_nodes_applied > 0:
		warnings.append("%d imported Roblox mesh asset(s) were applied exactly from cached .mesh data." % _exact_mesh_nodes_applied)
	if _standard_mesh_nodes_applied > 0:
		warnings.append("%d Roblox standard mesh child node(s) were materialized procedurally." % _standard_mesh_nodes_applied)
	if _mesh_proxy_nodes_improved > 0:
		warnings.append("%d Roblox mesh asset(s) were unavailable and used fallback geometry." % _mesh_proxy_nodes_improved)
	if _csg_fallback_nodes_preserved > 0:
		warnings.append("%d Roblox CSG operation(s) kept exact AssetId metadata and received editable fallback bodies." % _csg_fallback_nodes_preserved)
	if _terrain_nodes_created > 0:
		warnings.append("%d Roblox Terrain node(s) were imported as voxel GridMap previews." % _terrain_nodes_created)

	var report := {
		"ok": true,
		"parts": part_count,
		"runtime_objects": _runtime_objects.size(),
		"sounds": _sound_assets.size(),
		"nodes": part_count + meta_count,
		"skipped": skipped,
		"skipped_classes": skipped_classes,
		"errors": errors,
		"total_instances": instances.size(),
		"hidden_parts": int(import_scope.get("hidden_part_count", 0)),
		"workspace_parts": int(import_scope.get("world_part_count", part_count)),
		"workspace_filter": bool(import_scope.get("use_workspace_filter", false)),
		"workspace_ref_count": int((import_scope.get("workspace_refs", []) as Array).size()) if import_scope.get("workspace_refs", []) is Array else 0,
		"world_ref_count": int((import_scope.get("world_refs", {}) as Dictionary).size()) if import_scope.get("world_refs", {}) is Dictionary else 0,
		"asset_refs": int((roblox_manifest.get("assets", []) as Array).size()) if roblox_manifest.get("assets", []) is Array else 0,
		"script_refs": int((roblox_manifest.get("scripts", []) as Array).size()) if roblox_manifest.get("scripts", []) is Array else 0,
		"constraint_refs": int((roblox_manifest.get("constraints", []) as Array).size()) if roblox_manifest.get("constraints", []) is Array else 0,
		"tool_refs": int((roblox_manifest.get("tools", []) as Array).size()) if roblox_manifest.get("tools", []) is Array else 0,
		"gui_refs": int((roblox_manifest.get("gui", []) as Array).size()) if roblox_manifest.get("gui", []) is Array else 0,
		"storage_libraries": int((roblox_manifest.get("storage_libraries", []) as Array).size()) if roblox_manifest.get("storage_libraries", []) is Array else 0,
		"preview_nodes": _runtime_preview_nodes_created,
		"preview_skipped": _runtime_preview_nodes_skipped,
		"warnings": warnings,
	}
	import_finished.emit(report)
	print("[RBXL Runtime] Imported %d parts, %d runtime objects, %d sound asset(s). Skipped %d, errors %d." %
		[part_count, _runtime_objects.size(), _sound_assets.size(), skipped, errors])
	return report


func _fail(reason: String, extra: Dictionary = {}) -> Dictionary:
	push_error("[RBXL Runtime] " + reason)
	import_failed.emit(reason)
	var report := {"ok": false, "error": reason}
	for key in extra:
		report[key] = extra[key]
	return report


func _clear_existing_editor_content(placement_parent: Node3D, studio: Node) -> void:
	if studio.has_method("_get_editor_parts"):
		for block in studio._get_editor_parts():
			if is_instance_valid(block):
				block.queue_free()
	for child in placement_parent.get_children():
		if child.is_in_group(RUNTIME_OBJECT_GROUP):
			child.queue_free()


func _build_parent_map(hierarchy: Array) -> Dictionary:
	var parent_map := {}
	for edge_variant in hierarchy:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var child_id := _normalize_ref_id(edge.get("child", ""))
		if child_id.is_empty():
			continue
		parent_map[child_id] = _normalize_ref_id(edge.get("parent", ""))
	return parent_map


func _build_children_map(hierarchy: Array) -> Dictionary:
	var children_map := {}
	for edge_variant in hierarchy:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var child_id := _normalize_ref_id(edge.get("child", ""))
		var parent_id := _normalize_ref_id(edge.get("parent", ""))
		if child_id.is_empty():
			continue
		if not children_map.has(parent_id):
			children_map[parent_id] = []
		(children_map[parent_id] as Array).append(child_id)
	return children_map


func _normalize_ref_id(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text.ends_with(".0") and text.is_valid_float():
		return str(int(round(text.to_float())))
	return text


func _build_import_scope(instances: Dictionary, hierarchy: Array, parent_map: Dictionary) -> Dictionary:
	var children_map := _build_children_map(hierarchy)
	var workspace_refs: Array[String] = []
	for ref_id_variant in instances:
		var ref_id := str(ref_id_variant)
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", ""))
		var name := str(_prop(inst.get("properties", {}), "Name", "")).strip_edges()
		if roblox_class == "Workspace" or name == "Workspace":
			workspace_refs.append(ref_id)

	var world_refs: Dictionary = {}
	for workspace_ref in workspace_refs:
		_collect_descendant_refs(workspace_ref, children_map, world_refs)

	var total_part_count := 0
	var world_part_count := 0
	for ref_id_variant in instances:
		var ref_id := str(ref_id_variant)
		var inst: Dictionary = instances[ref_id]
		if not _is_part_class(str(inst.get("class", ""))):
			continue
		total_part_count += 1
		if world_refs.has(ref_id):
			world_part_count += 1

	var use_workspace_filter := not workspace_refs.is_empty() and world_part_count > 0
	return {
		"use_workspace_filter": use_workspace_filter,
		"workspace_refs": workspace_refs,
		"world_refs": world_refs,
		"world_part_count": world_part_count if use_workspace_filter else total_part_count,
		"total_part_count": total_part_count,
		"hidden_part_count": maxi(total_part_count - world_part_count, 0) if use_workspace_filter else 0,
		"children_map": children_map,
	}


func _collect_descendant_refs(root_ref: String, children_map: Dictionary, out_refs: Dictionary) -> void:
	var stack: Array[String] = [root_ref]
	var guard := 0
	while not stack.is_empty() and guard < 1000000:
		var ref_id := stack.pop_back()
		if out_refs.has(ref_id):
			guard += 1
			continue
		out_refs[ref_id] = true
		var children: Array = children_map.get(ref_id, [])
		for child_variant in children:
			stack.append(str(child_variant))
		guard += 1


func _should_import_world_ref(ref_id: String, import_scope: Dictionary) -> bool:
	if not bool(import_scope.get("use_workspace_filter", false)):
		return true
	var world_refs: Dictionary = import_scope.get("world_refs", {})
	return world_refs.has(ref_id)


func _build_roblox_place_manifest(json: Dictionary, instances: Dictionary, hierarchy: Array, parent_map: Dictionary) -> Dictionary:
	var class_counts: Dictionary = {}
	var services: Array[Dictionary] = []
	var scripts: Array[Dictionary] = []
	var assets: Array[Dictionary] = []
	var constraints: Array[Dictionary] = []
	var motion: Array[Dictionary] = []
	var tools: Array[Dictionary] = []
	var gui: Array[Dictionary] = []
	var runtime_instances: Array[Dictionary] = []
	var hierarchy_edges: Array[Dictionary] = []
	var children_map := _build_children_map(hierarchy)
	var eager_template_selection := _select_eager_template_part_refs(instances, parent_map)
	var eager_template_refs: Dictionary = eager_template_selection.get("refs", {})

	for edge_variant in hierarchy:
		if edge_variant is Dictionary:
			var edge: Dictionary = edge_variant
			hierarchy_edges.append({
				"child": _normalize_ref_id(edge.get("child", "")),
				"parent": _normalize_ref_id(edge.get("parent", "")),
			})

	for ref_id_variant in instances:
		var ref_id := str(ref_id_variant)
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", "Instance"))
		var props: Dictionary = inst.get("properties", {})
		var name := _safe_name(_prop(props, "Name", roblox_class))
		class_counts[roblox_class] = int(class_counts.get(roblox_class, 0)) + 1

		var base := {
			"ref": ref_id,
			"class": roblox_class,
			"name": name,
			"parent_ref": str(parent_map.get(ref_id, "")),
			"parent_class": _class_of_ref(str(parent_map.get(ref_id, "")), instances),
			"root_ref": _root_ref_for_ref(ref_id, parent_map, instances),
			"service_name": _service_name_for_ref(ref_id, parent_map, instances),
		}
		base["root_class"] = _class_of_ref(str(base.get("root_ref", "")), instances)
		base["root_name"] = _name_of_ref(str(base.get("root_ref", "")), instances)

		if _is_manifest_service_class(roblox_class):
			var service_data := base.duplicate(true)
			service_data["properties"] = _runtime_manifest_properties(roblox_class, props, roblox_class)
			services.append(service_data)

		if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
			var script_data := base.duplicate(true)
			var source := str(_prop(props, "Source", ""))
			script_data["source"] = source
			script_data["source_length"] = source.length()
			script_data["disabled"] = bool(_prop(props, "Disabled", false))
			scripts.append(script_data)

		if roblox_class in ["Tool", "HopperBin"]:
			var tool_data := base.duplicate(true)
			tool_data["properties"] = _pick_manifest_properties(props, [
				"ToolTip", "TextureId", "RequiresHandle", "CanBeDropped",
				"Enabled", "Grip", "GripForward", "GripPos", "GripRight", "GripUp"
			])
			tool_data.merge(_summarize_descendants(ref_id, children_map, instances), true)
			tools.append(tool_data)

		if _is_gui_class(roblox_class):
			var gui_data := base.duplicate(true)
			gui_data["properties"] = _pick_manifest_properties(props, [
				"Text", "Image", "HoverImage", "PressedImage", "Visible", "Enabled",
				"Size", "Position", "AnchorPoint", "Rotation",
				"BackgroundColor3", "TextColor3", "ImageColor3", "BackgroundTransparency",
				"TextTransparency", "ImageTransparency", "Transparency",
				"TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment",
				"TextStrokeColor3", "TextStrokeTransparency", "RichText", "LineHeight",
				"Font", "FontFace", "ZIndex", "DisplayOrder", "IgnoreGuiInset",
				"ZIndexBehavior", "ResetOnSpawn", "ScreenInsets", "ClipToDeviceSafeArea",
				"BorderSizePixel", "ClipsDescendants", "LayoutOrder",
				"ScaleType", "SliceCenter", "AutomaticSize", "ImageRectOffset",
				"ImageRectSize", "TileSize", "SizeConstraint", "CanvasSize",
				"ScrollingEnabled", "ScrollingDirection", "ScrollBarThickness",
				"CornerRadius", "Thickness", "MinSize", "MaxSize",
				"TextMinimumSize", "TextMaximumSize",
				"Color", "StrokeColor3", "ApplyStrokeMode", "Scale",
				"Padding", "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
				"FillDirection", "HorizontalAlignment", "VerticalAlignment",
				"SortOrder", "CellSize", "CellPadding", "AspectRatio",
				"DominantAxis", "AspectType"
			])
			var image_content := _content_to_string(_prop(props, "Image", ""))
			if not image_content.is_empty():
				gui_data["properties"]["ImageAssetId"] = _sanitize_asset_id(image_content)
				var resolved_image_path := _resolve_texture_content_to_local_path(image_content)
				if not resolved_image_path.is_empty():
					gui_data["properties"]["ResolvedImagePath"] = resolved_image_path
			gui.append(gui_data)

		if _should_emit_runtime_manifest_instance(
			ref_id,
			roblox_class,
			str(base.get("service_name", "")),
			eager_template_refs
		):
			var runtime_data := base.duplicate(true)
			runtime_data["properties"] = _runtime_manifest_properties(
				roblox_class,
				props,
				str(base.get("service_name", ""))
			)
			if _is_part_class(roblox_class):
				runtime_data["properties"]["BobuxDeferredGeometry"] = not eager_template_refs.has(ref_id)
			runtime_instances.append(runtime_data)

		_collect_manifest_assets(ref_id, roblox_class, name, props, parent_map, instances, assets)

		if _is_manifest_constraint_class(roblox_class):
			var constraint_data := base.duplicate(true)
			constraint_data["properties"] = _pick_manifest_properties(props, [
				"Part0", "Part1", "Attachment0", "Attachment1", "C0", "C1",
				"Transform", "Enabled", "LimitsEnabled", "ActuatorType",
				"TargetAngle", "AngularVelocity", "MotorMaxTorque",
				"TargetPosition", "Speed", "ServoMaxForce", "DesiredAngle",
				"MaxVelocity", "BaseAngle"
			])
			constraints.append(constraint_data)

		if _is_manifest_motion_class(roblox_class):
			var motion_data := base.duplicate(true)
			motion_data["properties"] = _pick_manifest_properties(props, [
				"Velocity", "MaxForce", "P", "D", "Position", "CFrame",
				"AngularVelocity", "MaxTorque", "Force", "Torque",
				"Attachment0", "Attachment1", "RelativeTo", "Enabled"
			])
			motion.append(motion_data)

	return {
		"schema": "bobux.roblox_manifest.v1",
		"format": str(json.get("format", "")),
		"version": int(json.get("version", 0)),
		"total_instances": instances.size(),
		"class_counts": class_counts,
		"hierarchy": hierarchy_edges,
		"services": services,
		"scripts": scripts,
		"assets": assets,
		"constraints": constraints,
		"motion": motion,
		"tools": tools,
		"gui": gui,
		"instances": runtime_instances,
		"eager_template_parts": eager_template_refs.size(),
		"lazy_template_parts": int(eager_template_selection.get("total", 0)) - eager_template_refs.size(),
		"storage_libraries": _build_storage_libraries(instances, children_map, parent_map),
	}


func _service_name_for_ref(ref_id: String, parent_map: Dictionary, instances: Dictionary) -> String:
	var cursor := ref_id
	var guard := 0
	while not cursor.is_empty() and cursor != "-1" and instances.has(cursor) and guard < 256:
		var inst: Dictionary = instances[cursor]
		var roblox_class := str(inst.get("class", ""))
		var instance_name := _name_of_ref(cursor, instances)
		if _is_manifest_service_class(roblox_class):
			return roblox_class
		cursor = str(parent_map.get(cursor, "")).strip_edges()
		guard += 1
	return ""


func _should_emit_runtime_manifest_instance(ref_id: String, roblox_class: String, service_name: String,
		eager_template_refs: Dictionary) -> bool:
	if roblox_class.is_empty() or roblox_class == "DataModel":
		return false
	if _is_manifest_service_class(roblox_class):
		return false
	if roblox_class in ["Script", "LocalScript", "ModuleScript", "Tool", "HopperBin"]:
		return false
	if _is_gui_class(roblox_class):
		return false
	# Workspace parts are already materialized by the geometry importer. Parts in
	# storage services stay as lightweight templates so Clone()/WaitForChild()
	# can resolve them without spilling hidden map libraries into the world.
	if _is_part_class(roblox_class) and service_name == "Workspace":
		return false
	if _is_part_class(roblox_class):
		return true
	return true


func _select_eager_template_part_refs(instances: Dictionary, parent_map: Dictionary) -> Dictionary:
	var priority: Array[String] = []
	var regular: Array[String] = []
	for ref_variant in instances:
		var ref_id := str(ref_variant)
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", ""))
		if not _is_part_class(roblox_class):
			continue
		if _service_name_for_ref(ref_id, parent_map, instances) == "Workspace":
			continue
		if _has_manifest_ancestor_class(ref_id, parent_map, instances, ["Tool", "HopperBin", "Accessory"]):
			priority.append(ref_id)
		else:
			regular.append(ref_id)
	var selected: Dictionary = {}
	for ref_id in priority:
		selected[ref_id] = true
	var remaining := maxi(MAX_EAGER_STORAGE_PARTS - selected.size(), 0)
	for index in range(mini(remaining, regular.size())):
		selected[regular[index]] = true
	return {"refs": selected, "total": priority.size() + regular.size()}


func _has_manifest_ancestor_class(ref_id: String, parent_map: Dictionary, instances: Dictionary,
		class_names: Array[String]) -> bool:
	var cursor := str(parent_map.get(ref_id, "")).strip_edges()
	var guard := 0
	while not cursor.is_empty() and cursor != "-1" and instances.has(cursor) and guard < 256:
		var inst: Dictionary = instances[cursor]
		if class_names.has(str(inst.get("class", ""))):
			return true
		cursor = str(parent_map.get(cursor, "")).strip_edges()
		guard += 1
	return false


func _runtime_manifest_properties(roblox_class: String, props: Dictionary, service_name: String) -> Dictionary:
	var keys: Array[String] = [
		"Name", "Archivable", "Value", "Enabled", "Visible", "Disabled",
		"PrimaryPart", "WorldPivot", "ModelStreamingMode",
		"Size", "CFrame", "Position", "Orientation", "Rotation",
		"Color", "Color3", "Color3uint8", "BrickColor", "Material", "MaterialVariant",
		"Transparency", "Reflectance", "Anchored", "CanCollide", "CanTouch",
		"CanQuery", "CollisionGroup", "Massless", "CastShadow", "Shape",
		"MeshId", "MeshID", "TextureId", "TextureID", "MeshType", "Scale", "Offset",
		"Part0", "Part1", "Attachment0", "Attachment1", "C0", "C1",
		"Transform", "LimitsEnabled", "ActuatorType", "TargetAngle",
		"AngularVelocity", "MotorMaxTorque", "TargetPosition", "Speed",
		"SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "TimePosition",
		"Brightness", "Range", "Shadows", "Angle", "Face",
		"Texture", "StudsPerTileU", "StudsPerTileV", "Face",
		"RequiresHandle", "CanBeDropped", "ToolTip", "Grip", "GripForward",
		"GripPos", "GripRight", "GripUp", "Graphic", "BinType", "Active",
		"DesiredAngle", "MaxVelocity", "BaseAngle", "TonemapperPreset",
		"Attributes", "Tags", "TeamColor", "AutoAssignable", "Neutral", "AllowTeamChangeOnTouch",
		"Health", "Health_XML", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "HipHeight",
		"MaxActivationDistance", "KeyboardKeyCode", "ActionText", "ObjectText", "HoldDuration",
		"UsePartColor", "VertexColor", "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface",
	]
	var picked := _pick_manifest_properties(props, keys)
	# Retain new/less common Roblox properties too. A rendering whitelist must
	# not erase script-visible data or CSG geometry from storage templates.
	for key in props:
		if not picked.has(key): picked[key] = _prop(props, str(key), null)
	if _is_part_class(roblox_class):
		var import_transform := _cframe_to_transform(_prop(props, "CFrame", null), scale_factor)
		if _is_transform_import_safe(import_transform):
			picked["BobuxPosition"] = [import_transform.origin.x, import_transform.origin.y, import_transform.origin.z]
			var rotation := import_transform.basis.get_euler()
			picked["BobuxRotation"] = [rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z)]
		var part_size := _get_part_size_vector3(props).abs() * scale_factor
		if _is_vector3_finite_and_limited(part_size, MAX_IMPORT_SCALE_ABS):
			picked["BobuxSize"] = [maxf(part_size.x, 0.02), maxf(part_size.y, 0.02), maxf(part_size.z, 0.02)]
		picked["BobuxTemplateOnly"] = service_name != "Workspace"
	return picked


func materialize_template_part(part: MeshInstance3D) -> void:
	var props: Dictionary = part.get_meta("roblox_properties", {})
	var roblox_class := str(part.get_meta("roblox_class", "Part"))
	var shape := _roblox_class_to_shape(roblox_class, props)
	part.mesh = _create_import_mesh_for_shape(shape)
	part.set_meta("shape_type", shape)
	var exact := _apply_exact_import_mesh_if_needed(part, roblox_class, props)
	if not exact and _is_csg_operation_class(roblox_class): exact = _apply_embedded_csg_hull_if_needed(part, props)
	_apply_material_to_mesh_surfaces(part, _material_cache.get_part_material(props))
	_apply_mesh_texture_to_parent(part, _content_to_string(_prop(props, "TextureID", _prop(props, "TextureId", ""))), exact)
	for child in part.get_children():
		var child_class := str(child.get_meta("roblox_class", ""))
		var child_props: Dictionary = child.get_meta("roblox_properties", {})
		var ref := str(child.get_meta("roblox_ref", ""))
		var parent_ref := str(part.get_meta("roblox_ref", ""))
		if child_class in ["SpecialMesh", "BlockMesh", "CylinderMesh"]:
			_build_mesh_runtime_object(ref, child_class, child_props, {ref: parent_ref}, {parent_ref: part}, {}, null)
		elif child_class in ["Decal", "Texture"]:
			_build_decal_runtime_object(ref, child_class, child_props, {ref: parent_ref}, {parent_ref: part}, {})
	part.set_meta("bobux_deferred_geometry", false)


func _collect_manifest_assets(ref_id: String, roblox_class: String, name: String, props: Dictionary,
		parent_map: Dictionary, instances: Dictionary, out_assets: Array[Dictionary]) -> void:
	var asset_props := _manifest_asset_properties_for_class(roblox_class)
	for prop_name in asset_props:
		var raw_value: Variant = _prop(props, prop_name, "")
		var content := _content_to_string(raw_value).strip_edges()
		if content.is_empty():
			continue
		out_assets.append({
			"ref": ref_id,
			"class": roblox_class,
			"name": name,
			"parent_ref": str(parent_map.get(ref_id, "")),
			"parent_class": _class_of_ref(str(parent_map.get(ref_id, "")), instances),
			"property": prop_name,
			"kind": _manifest_asset_kind(prop_name, roblox_class),
			"content": content,
			"asset_id": _sanitize_asset_id(content),
		})


func _build_storage_libraries(instances: Dictionary, children_map: Dictionary, parent_map: Dictionary) -> Array[Dictionary]:
	var libraries: Array[Dictionary] = []
	for ref_id_variant in instances:
		var ref_id := str(ref_id_variant)
		var inst: Dictionary = instances[ref_id]
		var roblox_class := str(inst.get("class", ""))
		var name := _name_of_ref(ref_id, instances)
		if not _is_storage_service_class(roblox_class, name):
			continue
		var children: Array = children_map.get(ref_id, [])
		for child_variant in children:
			var child_ref := str(child_variant)
			if not instances.has(child_ref):
				continue
			var child_inst: Dictionary = instances[child_ref]
			var child_class := str(child_inst.get("class", ""))
			var child_name := _name_of_ref(child_ref, instances)
			var entry := {
				"ref": child_ref,
				"class": child_class,
				"name": child_name,
				"service_ref": ref_id,
				"service_class": roblox_class,
				"service_name": name,
			}
			entry.merge(_summarize_descendants(child_ref, children_map, instances), true)
			libraries.append(entry)
	return libraries


func _summarize_descendants(root_ref: String, children_map: Dictionary, instances: Dictionary) -> Dictionary:
	var stack: Array[String] = [root_ref]
	var visited: Dictionary = {}
	var class_counts: Dictionary = {}
	var part_count := 0
	var script_count := 0
	var tool_count := 0
	var gui_count := 0
	while not stack.is_empty() and visited.size() < 1000000:
		var ref_id := stack.pop_back()
		if visited.has(ref_id):
			continue
		visited[ref_id] = true
		if instances.has(ref_id):
			var inst: Dictionary = instances[ref_id]
			var roblox_class := str(inst.get("class", ""))
			class_counts[roblox_class] = int(class_counts.get(roblox_class, 0)) + 1
			if _is_part_class(roblox_class):
				part_count += 1
			if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
				script_count += 1
			if roblox_class == "Tool":
				tool_count += 1
			if _is_gui_class(roblox_class):
				gui_count += 1
		var children: Array = children_map.get(ref_id, [])
		for child_variant in children:
			stack.append(str(child_variant))
	return {
		"descendant_count": visited.size(),
		"part_count": part_count,
		"script_count": script_count,
		"tool_count": tool_count,
		"gui_count": gui_count,
		"class_counts": class_counts,
	}


func _root_ref_for_ref(ref_id: String, parent_map: Dictionary, instances: Dictionary) -> String:
	var cursor := ref_id
	var guard := 0
	while parent_map.has(cursor) and guard < 256:
		var parent_ref := str(parent_map.get(cursor, "")).strip_edges()
		if parent_ref.is_empty() or parent_ref == "-1" or not instances.has(parent_ref):
			return cursor
		cursor = parent_ref
		guard += 1
	return cursor


func _name_of_ref(ref_id: String, instances: Dictionary) -> String:
	if not instances.has(ref_id):
		return ""
	var inst: Dictionary = instances[ref_id]
	return _safe_name(_prop(inst.get("properties", {}), "Name", str(inst.get("class", "Instance"))))


func _is_storage_service_class(roblox_class: String, name: String) -> bool:
	return roblox_class in [
		"ReplicatedStorage", "ServerStorage", "StarterGui", "StarterPack",
		"StarterPlayer", "ServerScriptService", "ReplicatedFirst",
		"Teams", "SoundService"
	] or name in [
		"ReplicatedStorage", "ServerStorage", "StarterGui", "StarterPack",
		"StarterPlayer", "ServerScriptService", "ReplicatedFirst",
		"Teams", "SoundService"
	]


func _is_gui_class(roblox_class: String) -> bool:
	return roblox_class in [
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel",
		"TextButton", "TextBox", "ImageLabel", "ImageButton",
		"ScrollingFrame", "ViewportFrame", "CanvasGroup", "UIListLayout",
		"UIGridLayout", "UIPadding", "UICorner", "UIGradient",
		"UIAspectRatioConstraint", "UIScale", "UIStroke", "UISizeConstraint",
		"UITextSizeConstraint"
	]


func _manifest_asset_properties_for_class(roblox_class: String) -> Array[String]:
	match roblox_class:
		"Sound":
			return ["SoundId"]
		"Decal", "Texture":
			return ["Texture", "NormalMap", "MetalnessMap", "RoughnessMap", "TexturePack"]
		"SpecialMesh", "MeshPart", "FileMesh":
			return ["MeshId", "TextureId", "TextureID"]
		"Animation":
			return ["AnimationId"]
		"Sky":
			return ["SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "MoonTextureId", "SunTextureId"]
		"Shirt":
			return ["ShirtTemplate"]
		"Pants":
			return ["PantsTemplate"]
		"ShirtGraphic":
			return ["Graphic"]
		"ImageLabel", "ImageButton":
			return ["Image", "HoverImage", "PressedImage"]
		"Tool", "HopperBin":
			return ["TextureId"]
		"ParticleEmitter", "Trail", "Beam":
			return ["Texture"]
		_:
			return []


func _manifest_asset_kind(prop_name: String, roblox_class: String) -> String:
	var lower := prop_name.to_lower()
	if lower.find("sound") >= 0:
		return "sound"
	if lower.find("mesh") >= 0:
		return "mesh"
	if lower.find("animation") >= 0:
		return "animation"
	if roblox_class in ["Shirt", "Pants", "ShirtGraphic"]:
		return "clothing_texture"
	return "texture"


func _pick_manifest_properties(props: Dictionary, keys: Array[String]) -> Dictionary:
	var picked: Dictionary = {}
	for key in keys:
		var value: Variant = _prop(props, key, null)
		if value != null:
			picked[key] = value
	return picked


func _is_manifest_service_class(roblox_class: String) -> bool:
	return roblox_class.ends_with("Service") or roblox_class in [
		"Workspace", "Lighting", "Players", "Teams", "ReplicatedStorage",
		"ReplicatedFirst", "ServerStorage", "ServerScriptService",
		"StarterGui", "StarterPack", "StarterPlayer", "SoundService",
		"TextChatService", "Chat", "Debris", "Selection", "VirtualInputManager"
	]


func _is_manifest_constraint_class(roblox_class: String) -> bool:
	return roblox_class in [
		"Weld", "ManualWeld", "WeldConstraint", "Motor6D", "Snap", "Motor",
		"HingeConstraint", "BallSocketConstraint", "SpringConstraint",
		"PrismaticConstraint", "CylindricalConstraint", "RodConstraint",
		"RopeConstraint", "NoCollisionConstraint", "AlignPosition",
		"AlignOrientation", "LinearVelocity", "AngularVelocity",
		"VectorForce", "Torque"
	]


func _is_manifest_motion_class(roblox_class: String) -> bool:
	return roblox_class in [
		"BodyVelocity", "BodyPosition", "BodyGyro", "BodyAngularVelocity",
		"BodyForce", "BodyThrust", "AlignPosition", "AlignOrientation",
		"LinearVelocity", "AngularVelocity", "VectorForce", "Torque",
		"HingeConstraint", "PrismaticConstraint", "RotateP", "RotateV"
	]


func _spawn_part_block(ref_id: String, roblox_class: String, props: Dictionary, placement_parent: Node3D, studio: Node) -> Node:
	if not studio.has_method("_build_block_instance"):
		return null

	var shape := _roblox_class_to_shape(roblox_class, props)
	var color := _Materials.part_color_from_properties(props)
	var material_id: Variant = _prop(props, "Material", 256)
	var material_type := _Materials.roblox_material_to_bobux(material_id)
	var transparency := clampf(float(_prop(props, "Transparency", 0.0)), 0.0, 1.0)
	var can_collide := bool(_prop(props, "CanCollide", true))
	var is_water_volume := material_type.strip_edges().to_lower() == "water"
	if is_water_volume:
		can_collide = false
	var name := str(_prop(props, "Name", roblox_class)).strip_edges()
	if name.is_empty():
		name = roblox_class

	var block: Node = null
	if studio.has_method("_build_imported_block_instance"):
		block = studio._build_imported_block_instance(shape, color, material_type, transparency, can_collide, name)
	else:
		block = studio._build_block_instance(shape, color, material_type, transparency, can_collide, name)
	if block == null or not is_instance_valid(block):
		return null

	var cf: Variant = _prop(props, "CFrame", null)
	if cf != null:
		var import_transform := _cframe_to_transform(cf, scale_factor)
		if not _is_transform_import_safe(import_transform):
			_runtime_warnings.append("Skipped %s '%s': invalid or far-away CFrame for ref %s." % [roblox_class, name, ref_id])
			block.queue_free()
			return null
		block.transform = import_transform

	var size := _get_part_size_vector3(props)
	if size != Vector3.ZERO:
		if not _is_vector3_finite_and_limited(size, MAX_IMPORT_SCALE_ABS / maxf(scale_factor, 0.001)):
			_runtime_warnings.append("Skipped %s '%s': invalid Size for ref %s." % [roblox_class, name, ref_id])
			block.queue_free()
			return null
		block.scale = Vector3(
			clampf(absf(size.x) * scale_factor, 0.02, MAX_IMPORT_SCALE_ABS),
			clampf(absf(size.y) * scale_factor, 0.02, MAX_IMPORT_SCALE_ABS),
			clampf(absf(size.z) * scale_factor, 0.02, MAX_IMPORT_SCALE_ABS)
		)

	block.set_meta("roblox_ref", ref_id)
	block.set_meta("roblox_class", roblox_class)
	block.set_meta("roblox_properties", props.duplicate(true))
	block.set_meta("roblox_material_id", int(material_id))
	block.set_meta("roblox_material_name", material_type)
	block.set_meta("can_collide", can_collide)
	block.set_meta("is_spawn", shape == "Spawn")
	if roblox_class in ["MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"]:
		block.set_meta("roblox_mesh_id", _resolve_part_mesh_content(roblox_class, props))
		block.set_meta("roblox_texture_id", _content_to_string(_prop(props, "TextureID", _prop(props, "TextureId", ""))))
	if bool(_prop(props, "Anchored", true)) == false:
		block.set_meta("anchored", false)
	if roblox_class == "TrussPart":
		block.add_to_group("roblox_climbable")
		block.set_meta("climbable", true)
	if roblox_class in ["Seat", "VehicleSeat"]:
		block.add_to_group("roblox_seat")
		block.set_meta("Disabled", bool(_prop(props, "Disabled", false)))
	if is_water_volume:
		block.add_to_group("roblox_water")
		if studio.has_method("_configure_studio_water_volume"):
			studio.call_deferred("_configure_studio_water_volume", block)
	if block is MeshInstance3D:
		var mesh_block := block as MeshInstance3D
		var exact_mesh_applied := _apply_exact_import_mesh_if_needed(mesh_block, roblox_class, props)
		if not exact_mesh_applied and _is_csg_operation_class(roblox_class):
			exact_mesh_applied = _apply_embedded_csg_hull_if_needed(mesh_block, props)
		var part_material := _material_cache.get_part_material(props)
		if exact_mesh_applied:
			part_material = part_material.duplicate(true) as StandardMaterial3D
			part_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_apply_material_to_mesh_surfaces(mesh_block, part_material)
		if roblox_class in ["MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"]:
			_apply_mesh_texture_to_parent(mesh_block, _content_to_string(_prop(props, "TextureID", _prop(props, "TextureId", ""))), exact_mesh_applied)
			# Roblox mesh files can carry per-vertex colors even when they do not
			# declare a material. Re-enable COLOR_0 after the Part material/texture
			# is installed so imported models do not collapse to gray.
			_Materials.enable_embedded_vertex_colors(mesh_block)
			if not exact_mesh_applied:
				_apply_import_meshpart_proxy_if_needed(mesh_block, roblox_class, props, shape)
		if studio.has_method("_update_block_collision"):
			studio._update_block_collision(block)

	placement_parent.add_child(block, false)
	return block


func _spawn_meta_instance(ref_id: String, roblox_class: String, props: Dictionary, placement_parent: Node3D,
		studio: Node, parent_map: Dictionary, block_map: Dictionary, instances: Dictionary, import_scope: Dictionary) -> bool:
	if not _should_register_runtime_scene_object(ref_id, roblox_class, parent_map, instances, import_scope):
		return true
	match roblox_class:
		"Lighting":
			if import_lighting:
				_apply_lighting(studio, props)
			return true
		"Sky":
			if import_lighting:
				_apply_sky(studio, props)
			return true
		"Atmosphere":
			if import_lighting:
				_apply_atmosphere(studio, props)
			return true
		"Terrain":
			return _register_terrain_runtime_object(ref_id, props, placement_parent)
		"BloomEffect", "SunRaysEffect", "ColorCorrectionEffect", "ColorGradingEffect":
			if import_lighting:
				_apply_lighting_effect(studio, roblox_class, props)
			return true
		"PointLight", "SpotLight", "SurfaceLight":
			return _register_runtime_object(
				_build_light_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances),
				placement_parent
			)
		"Sound":
			var sound_data := _build_sound_runtime_object(ref_id, props, parent_map, block_map, instances)
			if sound_data.is_empty():
				return false
			_sound_assets.append(sound_data.duplicate(true))
			if studio.has_method("_register_imported_sound_asset"):
				studio._register_imported_sound_asset(sound_data.duplicate(true))
			if bool(sound_data.get("as_music", false)):
				return true
			return _register_runtime_object(sound_data, placement_parent)
		"ParticleEmitter", "Fire", "Smoke", "Sparkles":
			return _register_runtime_object(
				_build_particle_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances),
				placement_parent
			)
		"Camera":
			return _register_runtime_object(
				_build_camera_runtime_object(ref_id, props, parent_map, block_map, instances),
				placement_parent
			)
		"Decal", "Texture":
			return _register_runtime_object(
				_build_decal_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances),
				placement_parent
			)
		"Script", "LocalScript", "ModuleScript":
			return _register_runtime_object(
				_build_script_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances),
				placement_parent
			)
		"SpecialMesh", "BlockMesh", "CylinderMesh":
			return _register_runtime_object(
				_build_mesh_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances, studio),
				placement_parent
			)
		_:
			return _is_structural_class(roblox_class)


func _should_register_runtime_scene_object(ref_id: String, roblox_class: String, parent_map: Dictionary,
		instances: Dictionary, import_scope: Dictionary) -> bool:
	if not bool(import_scope.get("use_workspace_filter", false)):
		return true
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		return true
	if roblox_class in ["Lighting", "Sky", "Atmosphere", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect", "ColorGradingEffect"]:
		return true
	if roblox_class == "Sound":
		return _should_import_world_ref(ref_id, import_scope) or _is_global_sound(ref_id, parent_map, instances)
	if roblox_class in [
		"PointLight", "SpotLight", "SurfaceLight",
		"ParticleEmitter", "Fire", "Smoke", "Sparkles",
		"Camera", "Decal", "Texture",
		"SpecialMesh", "BlockMesh", "CylinderMesh"
	]:
		return _should_import_world_ref(ref_id, import_scope)
	return true


func _register_runtime_object(data: Dictionary, placement_parent: Node3D) -> bool:
	if data.is_empty():
		return false
	_runtime_objects.append(data.duplicate(true))
	if not _should_create_runtime_preview_node(data):
		_runtime_preview_nodes_skipped += 1
		return true
	var runtime_node := _create_runtime_object_preview_node(data)
	if runtime_node == null:
		return true
	placement_parent.add_child(runtime_node, false)
	_runtime_preview_nodes_created += 1
	return true


func _register_terrain_runtime_object(ref_id: String, props: Dictionary, placement_parent: Node3D) -> bool:
	var terrain_node := Node3D.new()
	terrain_node.name = str(_prop(props, "Name", "Terrain"))
	if terrain_node.name.strip_edges().is_empty():
		terrain_node.name = "Terrain"
	terrain_node.set_meta("roblox_ref", ref_id)
	terrain_node.set_meta("roblox_class", "Terrain")
	terrain_node.set_meta("roblox_properties", props.duplicate(true))
	var builder := _TerrainBuilder.new()
	builder.build_into(terrain_node, props, scale_factor)
	placement_parent.add_child(terrain_node, false)
	_runtime_objects.append({
		"ref": ref_id,
		"class": "Terrain",
		"name": terrain_node.name,
		"status": str(terrain_node.get_meta("bobux_terrain_status", "imported")),
	})
	_terrain_nodes_created += 1
	return true


func _should_create_runtime_preview_node(data: Dictionary) -> bool:
	var roblox_class := str(data.get("class", ""))
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		return false
	if roblox_class in ["SpecialMesh", "BlockMesh", "CylinderMesh"]:
		return false
	if roblox_class in ["Decal", "Texture"]:
		if bool(data.get("applied_to_parent", false)):
			return false
		if _texture_preview_nodes_created >= maxi(max_texture_preview_nodes, 0):
			return false
		if _runtime_preview_nodes_created >= maxi(max_runtime_preview_nodes, 0):
			return false
		_texture_preview_nodes_created += 1
		return true
	if _runtime_preview_nodes_created >= maxi(max_runtime_preview_nodes, 0):
		return false
	return true


func _build_light_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var data := _base_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances)
	var color := _Materials._color_from_array(_prop(props, "Color", [1.0, 1.0, 1.0]))
	data["color"] = [color.r, color.g, color.b]
	data["brightness"] = float(_prop(props, "Brightness", 1.0))
	data["range"] = float(_prop(props, "Range", 16.0)) * scale_factor
	data["angle"] = float(_prop(props, "Angle", 45.0))
	return data


func _build_sound_runtime_object(ref_id: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var sound_id := _content_to_string(_prop(props, "SoundId", _prop(props, "soundid", ""))).strip_edges()
	var data := _base_runtime_object(ref_id, "Sound", props, parent_map, block_map, instances)
	data["sound_id"] = sound_id
	data["volume"] = clampf(float(_prop(props, "Volume", 1.0)), 0.0, 10.0)
	data["looped"] = bool(_prop(props, "Looped", _prop(props, "looped", false)))
	data["playing"] = bool(_prop(props, "Playing", _prop(props, "playing", true)))
	data["resolved_path"] = _resolve_sound_content_to_local_path(sound_id)
	data["as_music"] = _is_global_sound(ref_id, parent_map, instances)
	return data


func _build_particle_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var data := _base_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances)
	data["enabled"] = bool(_prop(props, "Enabled", true))
	data["rate"] = float(_prop(props, "Rate", 16.0))
	return data


func _build_camera_runtime_object(ref_id: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var data := _base_runtime_object(ref_id, "Camera", props, parent_map, block_map, instances)
	data["fov"] = float(_prop(props, "FieldOfView", 70.0))
	return data


func _build_decal_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var data := _base_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances)
	data["texture"] = _content_to_string(_prop(props, "Texture", ""))
	data["resolved_path"] = _resolve_texture_content_to_local_path(data["texture"])
	data["face"] = int(_prop(props, "Face", 5))
	data["transparency"] = clampf(float(_prop(props, "Transparency", 0.0)), 0.0, 1.0)
	var decal_color := _Materials._color_from_array(_prop(props, "Color3", [1.0, 1.0, 1.0]))
	data["color"] = [decal_color.r, decal_color.g, decal_color.b]
	data["studs_per_tile_u"] = maxf(float(_prop(props, "StudsPerTileU", 2.0)), 0.001)
	data["studs_per_tile_v"] = maxf(float(_prop(props, "StudsPerTileV", 2.0)), 0.001)
	var parent_ref := str(parent_map.get(ref_id, ""))
	if block_map.has(parent_ref):
		var parent_node: Node = block_map[parent_ref]
		if parent_node is Node3D and is_instance_valid(parent_node):
			var parent_3d := parent_node as Node3D
			data["parent_scale"] = [parent_3d.scale.x, parent_3d.scale.y, parent_3d.scale.z]
			data["parent_rotation_degrees"] = [parent_3d.rotation_degrees.x, parent_3d.rotation_degrees.y, parent_3d.rotation_degrees.z]
			data["applied_to_parent"] = _apply_decal_runtime_to_parent(parent_3d, data)
	return data


func _apply_decal_runtime_to_parent(parent_node: Node3D, data: Dictionary) -> bool:
	if parent_node == null or not is_instance_valid(parent_node):
		return false
	var texture := _load_runtime_texture(data)
	if texture == null:
		return false

	# Roblox decals belong to one NormalId face. A Godot Decal is a volume
	# projector and can bleed through neighbouring parts, so use a thin quad
	# parented to the Part instead. The parent already carries CFrame and Size.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var face_mesh := MeshInstance3D.new()
	face_mesh.name = "%sFace" % _safe_name(data.get("name", "Decal"))
	face_mesh.mesh = quad
	face_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face_mesh.position = _decal_face_position(int(data.get("face", 5)))
	face_mesh.rotation = _decal_face_rotation(int(data.get("face", 5)))

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	var color := _color_from_data(data)
	color.a = clampf(1.0 - float(data.get("transparency", 0.0)), 0.0, 1.0)
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.render_priority = 1
	if str(data.get("class", "Decal")) == "Texture":
		var parent_dimensions := parent_node.scale.abs()
		var face_dimensions := _decal_face_dimensions(int(data.get("face", 5)), parent_dimensions)
		material.uv1_scale = Vector3(
			maxf(face_dimensions.x / float(data.get("studs_per_tile_u", 2.0)), 1.0),
			maxf(face_dimensions.y / float(data.get("studs_per_tile_v", 2.0)), 1.0),
			1.0
		)
	face_mesh.material_override = material
	face_mesh.add_to_group(RUNTIME_OBJECT_GROUP)
	face_mesh.set_meta("runtime_object_data", data.duplicate(true))
	face_mesh.set_meta("roblox_class", str(data.get("class", "Decal")))
	face_mesh.set_meta("roblox_face_decal", true)
	face_mesh.set_meta("roblox_face", int(data.get("face", 5)))
	parent_node.add_child(face_mesh, false)
	return true


func _decal_face_position(face: int) -> Vector3:
	const SURFACE_OFFSET := 0.501
	match face:
		0:
			return Vector3(SURFACE_OFFSET, 0.0, 0.0)
		1:
			return Vector3(0.0, SURFACE_OFFSET, 0.0)
		2:
			# Roblox -> Godot mirrors world Z. NormalId semantic directions must
			# be mirrored as well; otherwise Back/Front decals land inside walls.
			return Vector3(0.0, 0.0, -SURFACE_OFFSET)
		3:
			return Vector3(-SURFACE_OFFSET, 0.0, 0.0)
		4:
			return Vector3(0.0, -SURFACE_OFFSET, 0.0)
		_:
			return Vector3(0.0, 0.0, SURFACE_OFFSET)


func _decal_face_rotation(face: int) -> Vector3:
	match face:
		0:
			return Vector3(0.0, PI * 0.5, 0.0)
		1:
			return Vector3(-PI * 0.5, 0.0, 0.0)
		2:
			return Vector3(0.0, PI, 0.0)
		3:
			return Vector3(0.0, -PI * 0.5, 0.0)
		4:
			return Vector3(PI * 0.5, 0.0, 0.0)
		_:
			return Vector3.ZERO


func _decal_face_dimensions(face: int, parent_dimensions: Vector3) -> Vector2:
	if face in [0, 3]:
		return Vector2(parent_dimensions.z, parent_dimensions.y)
	if face in [1, 4]:
		return Vector2(parent_dimensions.x, parent_dimensions.z)
	return Vector2(parent_dimensions.x, parent_dimensions.y)


func _build_mesh_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary, studio: Node) -> Dictionary:
	var data := _base_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances)
	data["mesh_type"] = int(_prop(props, "MeshType", 0))
	data["mesh_id"] = _content_to_string(_prop(props, "MeshId", _prop(props, "meshid", "")))
	data["texture_id"] = _content_to_string(_prop(props, "TextureId", _prop(props, "textureid", "")))
	var scale := _get_vector3(props, "Scale", Vector3.ONE)
	var offset := _get_vector3(props, "Offset", Vector3.ZERO)
	data["scale"] = [scale.x, scale.y, scale.z]
	# Keep the Roblox-local offset untouched here. It is converted exactly once
	# when the mesh is attached to its Part; pre-converting it caused a second
	# scale and a second Z flip for non-zero SpecialMesh offsets.
	data["offset"] = [offset.x, offset.y, offset.z]
	var vertex_color := _get_vector3(props, "VertexColor", Vector3.ONE)
	data["vertex_color"] = [vertex_color.x, vertex_color.y, vertex_color.z]
	data["preserved_as_metadata"] = true
	var parent_ref := str(parent_map.get(ref_id, ""))
	if block_map.has(parent_ref):
		var parent_node: Node = block_map[parent_ref]
		if is_instance_valid(parent_node):
			var applied := false
			if apply_standard_mesh_children:
				applied = _apply_mesh_runtime_to_parent(parent_node, roblox_class, data, studio)
			data["applied_to_parent"] = applied
			parent_node.set_meta("roblox_special_mesh", data.duplicate(true))
	return data


func _apply_mesh_runtime_to_parent(parent_node: Node, roblox_class: String, data: Dictionary, studio: Node) -> bool:
	if not (parent_node is MeshInstance3D):
		return false
	var mesh_id := str(data.get("mesh_id", "")).strip_edges()
	if roblox_class == "SpecialMesh" and not mesh_id.is_empty():
		var exact_applied := _apply_exact_mesh_asset_to_block(parent_node as MeshInstance3D, mesh_id, str(data.get("texture_id", "")).strip_edges())
		if exact_applied:
			var mesh_block_exact := parent_node as MeshInstance3D
			mesh_block_exact.set_meta("roblox_mesh_id", mesh_id)
			mesh_block_exact.set_meta("roblox_texture_id", str(data.get("texture_id", "")).strip_edges())
			var mesh_scale_exact := _vector3_from_array(data.get("scale", []), Vector3.ONE)
			if _is_vector3_finite_and_limited(mesh_scale_exact, 100.0):
				# FileMesh/SpecialMesh Scale multiplies the original mesh vertices.
				# The JSON loader restores those source vertices and their pivot, so
				# normalizing back to Scale would squash every asset to unit bounds.
				mesh_block_exact.scale = Vector3(
					_signed_scaled_axis(scale_factor, mesh_scale_exact.x),
					_signed_scaled_axis(scale_factor, mesh_scale_exact.y),
					_signed_scaled_axis(scale_factor, mesh_scale_exact.z)
				)
			var offset_exact := _vector3_from_array(data.get("offset", []), Vector3.ZERO)
			if offset_exact != Vector3.ZERO and _is_vector3_finite_and_limited(offset_exact, 10000.0):
				mesh_block_exact.position += mesh_block_exact.transform.basis.orthonormalized() * _roblox_local_vector_to_godot(offset_exact, scale_factor)
			_apply_mesh_vertex_color(mesh_block_exact, data.get("vertex_color", []))
			if studio != null and studio.has_method("_update_block_collision"):
				studio._update_block_collision(mesh_block_exact)
			return true
		if _apply_procedural_special_mesh_fallback(parent_node as MeshInstance3D, data, studio):
			return true
		parent_node.set_meta("roblox_mesh_deferred", true)
		parent_node.set_meta("roblox_mesh_id", mesh_id)
		parent_node.set_meta("roblox_texture_id", str(data.get("texture_id", "")).strip_edges())
		_apply_mesh_texture_to_parent(parent_node as MeshInstance3D, str(data.get("texture_id", "")).strip_edges(), false)
		_mesh_proxy_nodes_improved += 1
		return false
	var mesh_block := parent_node as MeshInstance3D
	var shape_name := _mesh_runtime_shape_name(roblox_class, int(data.get("mesh_type", 0)))
	if shape_name.is_empty():
		_apply_mesh_texture_to_parent(mesh_block, str(data.get("texture_id", "")).strip_edges(), false)
		_mesh_proxy_nodes_improved += 1
		return false
	var previous_material := mesh_block.get_active_material(0)
	mesh_block.mesh = _create_import_mesh_for_shape(shape_name)
	if previous_material != null:
		mesh_block.set_surface_override_material(0, previous_material)
	var mesh_scale := _vector3_from_array(data.get("scale", []), Vector3.ONE)
	if _is_vector3_finite_and_limited(mesh_scale, 100.0):
		mesh_block.scale = Vector3(
			_signed_scaled_axis(mesh_block.scale.x, mesh_scale.x),
			_signed_scaled_axis(mesh_block.scale.y, mesh_scale.y),
			_signed_scaled_axis(mesh_block.scale.z, mesh_scale.z)
		)
	var offset := _vector3_from_array(data.get("offset", []), Vector3.ZERO)
	if offset != Vector3.ZERO and _is_vector3_finite_and_limited(offset, 10000.0):
		mesh_block.position += mesh_block.transform.basis.orthonormalized() * _roblox_local_vector_to_godot(offset, scale_factor)
	_apply_mesh_vertex_color(mesh_block, data.get("vertex_color", []))
	_apply_mesh_texture_to_parent(mesh_block, str(data.get("texture_id", "")).strip_edges(), false)
	mesh_block.set_meta("shape_type", shape_name)
	mesh_block.set_meta("roblox_mesh_applied", true)
	_ensure_imported_mesh_double_sided(mesh_block)
	_standard_mesh_nodes_applied += 1
	if studio != null and studio.has_method("_update_block_collision"):
		studio._update_block_collision(mesh_block)
	return true


func _apply_procedural_special_mesh_fallback(mesh_block: MeshInstance3D, data: Dictionary, studio: Node) -> bool:
	var mesh_id := str(data.get("mesh_id", "")).strip_edges()
	if mesh_id.is_empty():
		return false
	var props: Dictionary = {}
	if mesh_block.has_meta("roblox_properties") and mesh_block.get_meta("roblox_properties") is Dictionary:
		props = (mesh_block.get_meta("roblox_properties") as Dictionary).duplicate(true)
	props["Name"] = str(mesh_block.get_meta("block_name", mesh_block.name))
	props["MeshId"] = mesh_id
	var fallback_mesh: Mesh = _MeshProxy.proxy_mesh_for_part("SpecialMesh", props, str(mesh_block.get_meta("shape_type", "Box")))
	if fallback_mesh == null:
		return false
	var previous_material := mesh_block.get_active_material(0)
	mesh_block.mesh = fallback_mesh
	if previous_material != null:
		mesh_block.set_surface_override_material(0, previous_material)
	var mesh_scale := _vector3_from_array(data.get("scale", []), Vector3.ONE)
	if _is_vector3_finite_and_limited(mesh_scale, 100.0):
		_set_mesh_target_dimensions(mesh_block, mesh_scale.abs() * scale_factor)
	var offset := _vector3_from_array(data.get("offset", []), Vector3.ZERO)
	if offset != Vector3.ZERO and _is_vector3_finite_and_limited(offset, 10000.0):
		mesh_block.position += mesh_block.transform.basis.orthonormalized() * _roblox_local_vector_to_godot(offset, scale_factor)
	_apply_mesh_vertex_color(mesh_block, data.get("vertex_color", []))
	_apply_mesh_texture_to_parent(mesh_block, str(data.get("texture_id", "")).strip_edges(), false)
	mesh_block.set_meta("roblox_mesh_applied", true)
	mesh_block.set_meta("roblox_mesh_procedural_fallback", true)
	mesh_block.set_meta("roblox_mesh_deferred", false)
	mesh_block.set_meta("roblox_mesh_id", mesh_id)
	mesh_block.set_meta("roblox_texture_id", str(data.get("texture_id", "")).strip_edges())
	_ensure_imported_mesh_double_sided(mesh_block)
	if studio != null and studio.has_method("_update_block_collision"):
		studio._update_block_collision(mesh_block)
	return true


func _apply_exact_import_mesh_if_needed(mesh_block: MeshInstance3D, roblox_class: String, props: Dictionary) -> bool:
	if not roblox_class in ["MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"]:
		return false
	var mesh_id := _resolve_part_mesh_content(roblox_class, props).strip_edges()
	var texture_id := _content_to_string(_prop(props, "TextureID", _prop(props, "TextureId", ""))).strip_edges()
	return _apply_exact_mesh_asset_to_block(mesh_block, mesh_id, texture_id)


func _apply_embedded_csg_hull_if_needed(mesh_block: MeshInstance3D, props: Dictionary) -> bool:
	var physical_data: Variant = _prop(props, "PhysicalConfigData", null)
	if physical_data == null:
		return false
	var mesh: ArrayMesh = _CsgPhysicsLoader.load_from_property(physical_data)
	if mesh == null:
		return false
	var target_dimensions := mesh_block.scale.abs()
	mesh_block.mesh = mesh
	_set_mesh_target_dimensions(mesh_block, target_dimensions)
	mesh_block.set_meta("shape_type", "UnionOperation")
	mesh_block.set_meta("roblox_mesh_applied", true)
	mesh_block.set_meta("roblox_csg_embedded_hull", true)
	mesh_block.set_meta("roblox_proxy_geometry", false)
	mesh_block.set_meta("roblox_missing_exact_mesh", false)
	_ensure_imported_mesh_double_sided(mesh_block)
	_csg_fallback_nodes_preserved += 1
	return true


func _resolve_part_mesh_content(roblox_class: String, props: Dictionary) -> String:
	var mesh_id := _content_to_string(_prop(props, "MeshId", _prop(props, "MeshID", ""))).strip_edges()
	if not mesh_id.is_empty():
		return mesh_id
	if roblox_class in ["UnionOperation", "NegateOperation", "IntersectOperation"]:
		mesh_id = _content_to_string(_prop(props, "AssetId", _prop(props, "SourceAssetId", ""))).strip_edges()
	return mesh_id


func _apply_exact_mesh_asset_to_block(mesh_block: MeshInstance3D, mesh_content: String, texture_content: String = "") -> bool:
	var asset_id := _sanitize_asset_id(mesh_content)
	if asset_id.is_empty():
		return false
	var mesh_path := _find_cached_mesh_json_asset(asset_id)
	if mesh_path.is_empty():
		return false
	var mesh: Mesh = null
	if _mesh_asset_cache.has(mesh_path):
		mesh = _mesh_asset_cache[mesh_path]
	else:
		mesh = _MeshJsonLoader.load_mesh(mesh_path)
		if mesh != null:
			_mesh_asset_cache[mesh_path] = mesh
	if mesh == null:
		return false
	# The editor block starts as a unit primitive whose scale already equals
	# the requested Roblox Part.Size. Imported meshes can have arbitrary source
	# bounds, so normalize the instance transform to that target size.
	var target_dimensions := mesh_block.scale.abs()
	mesh_block.mesh = mesh
	_set_mesh_target_dimensions(mesh_block, target_dimensions)
	mesh_block.set_meta("shape_type", "MeshPart")
	mesh_block.set_meta("roblox_mesh_applied", true)
	mesh_block.set_meta("roblox_mesh_exact_asset", asset_id)
	mesh_block.set_meta("roblox_mesh_json_asset", _cache_file_name_from_path(mesh_path))
	mesh_block.set_meta("roblox_proxy_geometry", false)
	_apply_mesh_texture_to_parent(mesh_block, texture_content, true)
	_ensure_imported_mesh_double_sided(mesh_block)
	_exact_mesh_nodes_applied += 1
	return true


func _ensure_imported_mesh_double_sided(mesh_block: MeshInstance3D) -> void:
	if mesh_block == null or mesh_block.mesh == null:
		return
	var surface_count := maxi(1, mesh_block.mesh.get_surface_count())
	for surface_index in range(surface_count):
		var material := mesh_block.get_active_material(surface_index) as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()
		else:
			material = material.duplicate(true) as StandardMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		mesh_block.set_surface_override_material(surface_index, material)


func _apply_material_to_mesh_surfaces(mesh_block: MeshInstance3D, material: Material) -> void:
	if mesh_block == null or material == null:
		return
	var surface_count := maxi(1, mesh_block.mesh.get_surface_count() if mesh_block.mesh != null else 1)
	for surface_index in range(surface_count):
		mesh_block.set_surface_override_material(surface_index, material)


func _set_mesh_target_dimensions(mesh_block: MeshInstance3D, target_dimensions: Vector3) -> void:
	if mesh_block == null or mesh_block.mesh == null:
		return
	var bounds := mesh_block.mesh.get_aabb().size.abs()
	mesh_block.scale = Vector3(
		target_dimensions.x / maxf(bounds.x, 0.0001),
		target_dimensions.y / maxf(bounds.y, 0.0001),
		target_dimensions.z / maxf(bounds.z, 0.0001)
	)


func _roblox_local_vector_to_godot(value: Vector3, scale: float) -> Vector3:
	return Vector3(value.x * scale, value.y * scale, -value.z * scale)


func _apply_import_meshpart_proxy_if_needed(mesh_block: MeshInstance3D, roblox_class: String, props: Dictionary, shape_name: String) -> void:
	if not roblox_class in ["MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"]:
		return
	var mesh_content := _resolve_part_mesh_content(roblox_class, props).strip_edges()
	var asset_id := _sanitize_asset_id(mesh_content)
	mesh_block.set_meta("roblox_mesh_id", mesh_content)
	if not asset_id.is_empty():
		mesh_block.set_meta("roblox_asset_id", asset_id)
	if _is_csg_operation_class(roblox_class):
		# Roblox CSG operations keep their AssetId as the source of truth. If
		# the private solid mesh cannot be downloaded, keep a clean editable
		# fallback body instead of flagging the object as a broken mesh.
		mesh_block.set_meta("roblox_csg_asset_id", asset_id)
		mesh_block.set_meta("roblox_csg_fallback", true)
		mesh_block.set_meta("roblox_missing_exact_mesh", false)
		mesh_block.set_meta("roblox_proxy_geometry", false)
		mesh_block.set_meta("shape_type", shape_name if not shape_name.is_empty() else "Box")
		_csg_fallback_nodes_preserved += 1
		return
	mesh_block.set_meta("roblox_missing_exact_mesh", true)
	mesh_block.set_meta("roblox_proxy_geometry", true)
	mesh_block.set_meta("roblox_asset_unavailable", true)
	_mesh_proxy_nodes_improved += 1


func _is_csg_operation_class(roblox_class: String) -> bool:
	return roblox_class in ["UnionOperation", "NegateOperation", "IntersectOperation"]


func _apply_mesh_texture_to_parent(mesh_block: MeshInstance3D, texture_content: String, use_mesh_uvs: bool = false) -> void:
	if mesh_block == null or texture_content.strip_edges().is_empty():
		return
	var texture_path := _resolve_exact_texture_content_to_local_path(texture_content)
	if texture_path.is_empty():
		return
	var texture := _load_texture_from_path(texture_path)
	if texture == null:
		return
	var surface_count := maxi(1, mesh_block.mesh.get_surface_count() if mesh_block.mesh != null else 1)
	for surface_index in range(surface_count):
		var material := mesh_block.get_active_material(surface_index) as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()
		else:
			material = material.duplicate(true) as StandardMaterial3D
		material.albedo_texture = texture
		material.uv1_triplanar = not use_mesh_uvs
		if not use_mesh_uvs:
			material.uv1_scale = Vector3(1.0, 1.0, 1.0)
		if material.albedo_color.a >= 0.99:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		mesh_block.set_surface_override_material(surface_index, material)


func _apply_mesh_vertex_color(mesh_block: MeshInstance3D, raw_vertex_color: Variant) -> void:
	var vertex_color := _vector3_from_array(raw_vertex_color, Vector3.ONE)
	if vertex_color == Vector3.ONE:
		return
	var surface_count := maxi(1, mesh_block.mesh.get_surface_count() if mesh_block.mesh != null else 1)
	for surface_index in range(surface_count):
		var material := mesh_block.get_active_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		material = material.duplicate(true) as StandardMaterial3D
		material.albedo_color = Color(
			clampf(material.albedo_color.r * vertex_color.x, 0.0, 1.0),
			clampf(material.albedo_color.g * vertex_color.y, 0.0, 1.0),
			clampf(material.albedo_color.b * vertex_color.z, 0.0, 1.0),
			material.albedo_color.a
		)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_block.set_surface_override_material(surface_index, material)


func _signed_scaled_axis(base_value: float, multiplier: float) -> float:
	var value := base_value * multiplier
	var sign_value := -1.0 if value < 0.0 else 1.0
	var magnitude := clampf(absf(value), 0.02, MAX_IMPORT_SCALE_ABS)
	return magnitude * sign_value


func _mesh_runtime_shape_name(roblox_class: String, mesh_type: int) -> String:
	match roblox_class:
		"BlockMesh":
			return "Box"
		"CylinderMesh":
			return "Cylinder"
		"SpecialMesh":
			match mesh_type:
				0, 1, 5, 6:
					return "Box"
				2, 7, 9, 10:
					return "Wedge"
				8:
					return "Pyramid"
				11:
					return "CornerWedge"
				3:
					return "Sphere"
				4:
					return "Cylinder"
				_:
					return ""
	return ""


func _create_import_mesh_for_shape(shape_name: String) -> Mesh:
	match shape_name:
		"Sphere":
			return SphereMesh.new()
		"Cylinder":
			return CylinderMesh.new()
		"Wedge":
			return _WedgeBuilder.build_wedge(Vector3.ONE)
		"CornerWedge":
			return _WedgeBuilder.build_corner_wedge(Vector3.ONE)
		"Pyramid":
			return _WedgeBuilder.build_pyramid(Vector3.ONE)
		"Truss":
			return _WedgeBuilder.build_truss(Vector3.ONE)
		_:
			return BoxMesh.new()


func _build_script_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var data := _base_runtime_object(ref_id, roblox_class, props, parent_map, block_map, instances)
	data["lua_source"] = str(_prop(props, "Source", ""))
	return data


func _base_runtime_object(ref_id: String, roblox_class: String, props: Dictionary, parent_map: Dictionary,
		block_map: Dictionary, instances: Dictionary) -> Dictionary:
	var transform := _infer_instance_transform(ref_id, props, parent_map, block_map)
	var rot := transform.basis.get_euler()
	return {
		"class": roblox_class,
		"name": _safe_name(_prop(props, "Name", roblox_class)),
		"roblox_ref": ref_id,
		"parent_ref": str(parent_map.get(ref_id, "")),
		"parent_class": _class_of_ref(str(parent_map.get(ref_id, "")), instances),
		"px": snappedf(transform.origin.x, 0.001),
		"py": snappedf(transform.origin.y, 0.001),
		"pz": snappedf(transform.origin.z, 0.001),
		"rx": snappedf(rad_to_deg(rot.x), 0.001),
		"ry": snappedf(rad_to_deg(rot.y), 0.001),
		"rz": snappedf(rad_to_deg(rot.z), 0.001),
	}


func _infer_instance_transform(ref_id: String, props: Dictionary, parent_map: Dictionary, block_map: Dictionary) -> Transform3D:
	var cf: Variant = _prop(props, "CFrame", null)
	if cf != null:
		return _cframe_to_transform(cf, scale_factor)
	var parent_ref := str(parent_map.get(ref_id, ""))
	if block_map.has(parent_ref):
		var parent_node: Node3D = block_map[parent_ref]
		if parent_node != null and is_instance_valid(parent_node):
			return parent_node.transform
	return Transform3D.IDENTITY


func _create_runtime_object_preview_node(data: Dictionary) -> Node3D:
	var roblox_class := str(data.get("class", "RuntimeObject"))
	var runtime_node: Node3D
	match roblox_class:
		"PointLight", "SurfaceLight":
			var light := OmniLight3D.new()
			light.light_color = _color_from_data(data)
			light.light_energy = float(data.get("brightness", 1.0)) * 2.0
			light.omni_range = float(data.get("range", 8.0))
			runtime_node = light
		"SpotLight":
			var light := SpotLight3D.new()
			light.light_color = _color_from_data(data)
			light.light_energy = float(data.get("brightness", 1.0)) * 2.0
			light.spot_range = float(data.get("range", 8.0))
			light.spot_angle = float(data.get("angle", 45.0))
			runtime_node = light
		"Sound":
			runtime_node = Node3D.new()
			var player := AudioStreamPlayer3D.new()
			player.name = "AudioPreview"
			player.volume_db = linear_to_db(maxf(float(data.get("volume", 1.0)), 0.0001))
			runtime_node.add_child(player, false)
		"ParticleEmitter", "Fire", "Smoke", "Sparkles":
			var particles := GPUParticles3D.new()
			particles.amount = maxi(1, int(data.get("rate", 16.0)))
			particles.emitting = bool(data.get("enabled", true))
			runtime_node = particles
		"Camera":
			var cam := Camera3D.new()
			cam.fov = float(data.get("fov", 70.0))
			runtime_node = cam
		"Decal", "Texture":
			var decal := Decal.new()
			decal.size = _decal_size_from_data(data)
			var decal_texture := _load_runtime_texture(data)
			if decal_texture != null:
				decal.texture_albedo = decal_texture
				decal.modulate.a = clampf(1.0 - float(data.get("transparency", 0.0)), 0.0, 1.0)
			runtime_node = decal
		_:
			runtime_node = Node3D.new()
	runtime_node.name = _safe_name(data.get("name", roblox_class))
	runtime_node.position = Vector3(float(data.get("px", 0.0)), float(data.get("py", 0.0)), float(data.get("pz", 0.0)))
	runtime_node.rotation_degrees = Vector3(float(data.get("rx", 0.0)), float(data.get("ry", 0.0)), float(data.get("rz", 0.0)))
	runtime_node.add_to_group(RUNTIME_OBJECT_GROUP)
	runtime_node.set_meta("runtime_object_data", data.duplicate(true))
	runtime_node.set_meta("roblox_class", roblox_class)
	return runtime_node


func _decal_size_from_data(data: Dictionary) -> Vector3:
	var parent_scale := _vector3_from_array(data.get("parent_scale", []), Vector3(4.0, 4.0, 4.0))
	return Vector3(
		maxf(absf(parent_scale.x), 0.5),
		maxf(absf(parent_scale.y), 0.5),
		maxf(absf(parent_scale.z), 0.5)
	) + Vector3(0.08, 0.08, 0.08)


func _apply_lighting(studio: Node, props: Dictionary) -> void:
	var brightness := float(_prop(props, "Brightness", 2.0))
	var hour := _hour_from_lighting_props(props)
	var ambient := _Materials._color_from_array(_prop(props, "Ambient", [0.45, 0.50, 0.58]))
	var outdoor := _Materials._color_from_array(_prop(props, "OutdoorAmbient", [0.55, 0.65, 0.78]))
	var fog_color := _Materials._color_from_array(_prop(props, "FogColor", [0.62, 0.76, 0.95]))
	var sun: DirectionalLight3D = studio.get("sun_light")
	if sun != null and is_instance_valid(sun):
		sun.light_energy = clampf(0.55 + brightness * 0.58, 0.35, 3.2)
		sun.light_color = Color(1.0, 0.97, 0.90)
		sun.shadow_enabled = bool(_prop(props, "GlobalShadows", true))
		sun.rotation_degrees = Vector3(-((hour / 24.0) * 360.0 - 90.0), -45.0, 0.0)
	var env := _ensure_studio_environment(studio)
	if env != null:
		var fog_start := float(_prop(props, "FogStart", 0.0))
		var fog_end := float(_prop(props, "FogEnd", 100000.0))
		var use_fog := fog_end > fog_start and fog_end < 50000.0
		var sky_color := _roblox_sky_color_for_hour(hour).lerp(fog_color, 0.08 if use_fog else 0.0)
		_apply_roblox_procedural_sky(env, sky_color)
		env.background_color = sky_color
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = ambient.lerp(outdoor, 0.42).lerp(Color(0.56, 0.66, 0.78), 0.18)
		env.ambient_light_energy = clampf(0.32 + brightness * 0.10, 0.32, 0.82)
		env.glow_enabled = false
		env.glow_intensity = 0.0
		env.glow_bloom = 0.0
		env.set("fog_enabled", use_fog)
		env.set("fog_light_color", fog_color)
		env.set("fog_sky_affect", 0.08)
		if use_fog:
			env.set("fog_density", clampf(1.0 / maxf(fog_end - fog_start, 1.0), 0.000005, 0.02))
	if is_instance_valid(studio):
		studio.set_meta("roblox_lighting_properties", props.duplicate(true))
	var slider: HSlider = studio.get("time_slider")
	if slider != null and is_instance_valid(slider):
		slider.set_value_no_signal(hour)


func _apply_sky(studio: Node, props: Dictionary) -> void:
	if is_instance_valid(studio):
		studio.set_meta("roblox_sky_properties", props.duplicate(true))
	var env := _ensure_studio_environment(studio)
	if env == null:
		return
	var fallback_color := env.background_color if env.background_mode == Environment.BG_SKY else Color(0.54, 0.78, 0.98)
	if not _RobloxSky.apply_skybox_from_properties(env, props, fallback_color):
		_apply_roblox_procedural_sky(env, fallback_color)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.66, 0.78)
	env.ambient_light_energy = maxf(env.ambient_light_energy, 0.52)


func _apply_atmosphere(studio: Node, props: Dictionary) -> void:
	if is_instance_valid(studio):
		studio.set_meta("roblox_atmosphere_properties", props.duplicate(true))
	var env := _ensure_studio_environment(studio)
	if env == null:
		return
	var atmosphere_color := _Materials._color_from_array(_prop(props, "Color", [0.78, 0.78, 0.78]))
	var density := clampf(float(_prop(props, "Density", 0.0)), 0.0, 1.0)
	var sky_color := Color(0.54, 0.78, 0.98).lerp(atmosphere_color, density * 0.18)
	var sky_props: Dictionary = studio.get_meta("roblox_sky_properties", {}) if is_instance_valid(studio) and studio.get_meta("roblox_sky_properties", {}) is Dictionary else {}
	if sky_props.is_empty() or not _RobloxSky.apply_skybox_from_properties(env, sky_props, sky_color):
		_apply_roblox_procedural_sky(env, sky_color)
	env.set("fog_light_color", atmosphere_color)
	env.set("fog_sky_affect", clampf(0.05 + density * 0.24, 0.0, 0.38))


func _apply_lighting_effect(studio: Node, roblox_class: String, props: Dictionary) -> void:
	if is_instance_valid(studio):
		studio.set_meta("roblox_%s_properties" % roblox_class.to_lower(), props.duplicate(true))
	var env := _ensure_studio_environment(studio)
	if env == null:
		return
	match roblox_class:
		"BloomEffect":
			env.glow_enabled = bool(_prop(props, "Enabled", true))
			env.glow_intensity = clampf(float(_prop(props, "Intensity", 0.35)), 0.0, 2.0)
			env.glow_bloom = clampf(float(_prop(props, "Size", 24.0)) / 160.0, 0.02, 0.45)
		"SunRaysEffect":
			if bool(_prop(props, "Enabled", true)):
				env.glow_enabled = true
				env.glow_intensity = maxf(env.glow_intensity, clampf(float(_prop(props, "Intensity", 0.02)) * 8.0, 0.02, 0.25))
		"ColorCorrectionEffect":
			if bool(_prop(props, "Enabled", true)):
				var tint := _Materials._color_from_array(_prop(props, "TintColor", [1.0, 1.0, 1.0]))
				env.adjustment_enabled = true
				env.adjustment_brightness = clampf(1.0 + float(_prop(props, "Brightness", 0.0)), 0.1, 3.0)
				env.adjustment_contrast = clampf(1.0 + float(_prop(props, "Contrast", 0.0)), 0.1, 3.0)
				env.adjustment_saturation = clampf(1.0 + float(_prop(props, "Saturation", 0.0)), 0.0, 3.0)
				env.adjustment_color_correction = null
				env.ambient_light_color = env.ambient_light_color.lerp(tint, 0.08)
		"ColorGradingEffect":
			if bool(_prop(props, "Enabled", true)):
				var preset := int(_prop(props, "TonemapperPreset", 0))
				if preset == 1:
					# Roblox Retro deliberately has softer contrast and saturation.
					env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
					env.adjustment_enabled = true
					env.adjustment_contrast = minf(env.adjustment_contrast, 0.94)
					env.adjustment_saturation = minf(env.adjustment_saturation, 0.92)
				else:
					env.tonemap_mode = Environment.TONE_MAPPER_ACES


func _ensure_studio_environment(studio: Node) -> Environment:
	var env_node := _find_studio_world_environment(studio)
	if env_node == null:
		return null
	if env_node.environment == null:
		env_node.environment = Environment.new()
	else:
		var local_env := env_node.environment.duplicate(true) as Environment
		if local_env != null:
			env_node.environment = local_env
	env_node.environment.resource_local_to_scene = true
	return env_node.environment


func _find_studio_world_environment(studio: Node) -> WorldEnvironment:
	if not is_instance_valid(studio):
		return null
	for path in ["SubViewportContainer/SubViewport/World3D/WorldEnvironment", "WorldEnvironment"]:
		var node := studio.get_node_or_null(path)
		if node is WorldEnvironment:
			return node as WorldEnvironment
	return _find_world_environment_recursive(studio)


func _find_world_environment_recursive(root: Node) -> WorldEnvironment:
	for child in root.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var nested := _find_world_environment_recursive(child)
		if nested != null:
			return nested
	return null


func _roblox_sky_color_for_hour(hour: float) -> Color:
	var t := clampf(absf(hour - 12.0) / 12.0, 0.0, 1.0)
	var noon := Color(0.52, 0.76, 0.96)
	var evening := Color(0.38, 0.50, 0.74)
	return noon.lerp(evening, t * 0.55)


func _apply_roblox_procedural_sky(env: Environment, sky_color: Color) -> void:
	if env == null:
		return
	_RobloxSky.apply_to_environment(env, sky_color)


func _hour_from_time_of_day(value: String) -> float:
	var parts := value.split(":")
	if parts.is_empty():
		return 14.0
	return clampf(float(parts[0]), 0.0, 24.0)


func _hour_from_lighting_props(props: Dictionary) -> float:
	if props.has("ClockTime"):
		return clampf(float(_prop(props, "ClockTime", 14.0)), 0.0, 24.0)
	return _hour_from_time_of_day(str(_prop(props, "TimeOfDay", "14:00:00")))


static func _roblox_class_to_shape(roblox_class: String, props: Dictionary) -> String:
	match roblox_class:
		"Part":
			match int(_prop_static(props, "Shape", _prop_static(props, "shape", 1))):
				0:
					return "Sphere"
				2:
					return "Cylinder"
				_:
					return "Box"
		"WedgePart":
			return "Wedge"
		"CornerWedgePart":
			return "CornerWedge"
		"TrussPart":
			return "Truss"
		"SpawnLocation":
			return "Spawn"
		_:
			return "Box"


func _cframe_to_transform(cf: Variant, scale: float) -> Transform3D:
	if cf == null or typeof(cf) != TYPE_DICTIONARY:
		return Transform3D.IDENTITY
	var cfd: Dictionary = cf
	var pos: Array = cfd.get("position", [0.0, 0.0, 0.0])
	var rot: Array = cfd.get("rotation", [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
	var r0: Array = rot[0] if rot.size() > 0 and rot[0] is Array else [1.0, 0.0, 0.0]
	var r1: Array = rot[1] if rot.size() > 1 and rot[1] is Array else [0.0, 1.0, 0.0]
	var r2: Array = rot[2] if rot.size() > 2 and rot[2] is Array else [0.0, 0.0, 1.0]
	var basis := Basis(
		Vector3(_array_float(r0, 0, 1.0), _array_float(r1, 0, 0.0), -_array_float(r2, 0, 0.0)),
		Vector3(_array_float(r0, 1, 0.0), _array_float(r1, 1, 1.0), -_array_float(r2, 1, 0.0)),
		Vector3(-_array_float(r0, 2, 0.0), -_array_float(r1, 2, 0.0), _array_float(r2, 2, 1.0))
	)
	if _is_basis_import_safe(basis) and absf(basis.determinant()) > 0.001:
		basis = basis.orthonormalized()
	var origin := Vector3(
		_array_float(pos, 0, 0.0) * scale,
		_array_float(pos, 1, 0.0) * scale,
		-_array_float(pos, 2, 0.0) * scale
	)
	return Transform3D(basis, origin)


func _is_transform_import_safe(transform: Transform3D) -> bool:
	return _is_basis_import_safe(transform.basis) and _is_vector3_finite_and_limited(transform.origin, MAX_IMPORT_POSITION_ABS)


func _is_basis_import_safe(basis: Basis) -> bool:
	return (
		_is_vector3_finite_and_limited(basis.x, MAX_IMPORT_BASIS_ABS)
		and _is_vector3_finite_and_limited(basis.y, MAX_IMPORT_BASIS_ABS)
		and _is_vector3_finite_and_limited(basis.z, MAX_IMPORT_BASIS_ABS)
	)


func _is_vector3_finite_and_limited(value: Vector3, max_abs_value: float) -> bool:
	return (
		_is_finite_number(value.x)
		and _is_finite_number(value.y)
		and _is_finite_number(value.z)
		and absf(value.x) <= max_abs_value
		and absf(value.y) <= max_abs_value
		and absf(value.z) <= max_abs_value
	)


func _is_finite_number(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


func _array_float(values: Array, index: int, fallback: float) -> float:
	if index < 0 or index >= values.size():
		return fallback
	return _safe_float(values[index], fallback)


func _safe_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(value)
		TYPE_STRING:
			var text := str(value).strip_edges()
			if text.is_valid_float():
				return text.to_float()
			return fallback
		_:
			return fallback


func _get_vector3(props: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var v: Variant = _prop(props, key, null)
	if v == null:
		return fallback
	if v is Array:
		var a := v as Array
		return Vector3(
			_array_float(a, 0, fallback.x),
			_array_float(a, 1, fallback.y),
			_array_float(a, 2, fallback.z)
		)
	if v is Vector3:
		return v
	if v is Dictionary:
		return Vector3(
			_safe_float(v.get("x", fallback.x), fallback.x),
			_safe_float(v.get("y", fallback.y), fallback.y),
			_safe_float(v.get("z", fallback.z), fallback.z)
		)
	return fallback


func _get_part_size_vector3(props: Dictionary) -> Vector3:
	for key in ["Size", "size", "ExtentsSize", "InitialSize"]:
		var value := _get_vector3(props, key, Vector3.ZERO)
		if value != Vector3.ZERO and _is_vector3_finite_and_limited(value, MAX_IMPORT_SCALE_ABS / maxf(scale_factor, 0.001)):
			return value
	return Vector3.ZERO


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		var arr := value as Array
		return Vector3(
			_array_float(arr, 0, fallback.x),
			_array_float(arr, 1, fallback.y),
			_array_float(arr, 2, fallback.z)
		)
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector3(
			_safe_float(dict.get("x", fallback.x), fallback.x),
			_safe_float(dict.get("y", fallback.y), fallback.y),
			_safe_float(dict.get("z", fallback.z), fallback.z)
		)
	return fallback


func _resolve_sound_content_to_local_path(content: Variant) -> String:
	var source := _content_to_string(content).strip_edges()
	if source.is_empty():
		return ""
	if source.begins_with("file://"):
		source = source.substr(7)
	if FileAccess.file_exists(source):
		return source
	var global_source := ProjectSettings.globalize_path(source)
	if global_source != source and FileAccess.file_exists(global_source):
		return global_source
	if source.begins_with("rbxassetid://"):
		var asset_id := _sanitize_asset_id(source.substr("rbxassetid://".length()))
		return _find_cached_sound_asset(asset_id)
	if source.begins_with("rbxasset://"):
		var asset_path := source.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		var builtin_path := "res://addons/rbxl_importer/builtin_assets/%s" % asset_path
		if FileAccess.file_exists(builtin_path):
			return builtin_path
	return ""


func _resolve_texture_content_to_local_path(content: Variant) -> String:
	var source := _content_to_string(content).strip_edges()
	if source.is_empty():
		return ""
	var normalized_source := source.to_lower().replace("\\", "/")
	# Old places commonly reference these Roblox-owned images by URL instead of
	# an asset id. Keep deterministic local equivalents so legacy faces and the
	# default shirt marker do not silently disappear when the place is offline.
	if normalized_source.ends_with("/textures/face.png") or normalized_source.ends_with("/images/face.png"):
		return "res://assets/avatar/default_face.png"
	if normalized_source.ends_with("/images/shirt.png"):
		var legacy_shirt_path := "res://addons/rbxl_importer/builtin_assets/images/shirt.png"
		if FileAccess.file_exists(legacy_shirt_path):
			return legacy_shirt_path
	if source.begins_with("file://"):
		source = source.substr(7)
	if FileAccess.file_exists(source):
		return source
	var global_source := ProjectSettings.globalize_path(source)
	if global_source != source and FileAccess.file_exists(global_source):
		return global_source
	if source.begins_with("rbxasset://"):
		var asset_path := source.substr("rbxasset://".length()).strip_edges()
		while asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		var candidates: Array[String] = [
			"res://addons/rbxl_importer/builtin_assets/%s" % asset_path,
			"res://images/%s" % asset_path.get_file(),
		]
		if asset_path.to_lower() == "textures/face.png":
			candidates.push_front("res://assets/avatar/default_face.png")
		if asset_path.to_lower() == "textures/spawnlocation.png":
			candidates.append("res://images/spawn.png")
		for candidate in candidates:
			if FileAccess.file_exists(candidate):
				return candidate
	if source.begins_with("rbxassetid://"):
		var asset_id := _sanitize_asset_id(source.substr("rbxassetid://".length()))
		return _find_cached_texture_asset(asset_id)
	var asset_id := _sanitize_asset_id(source)
	if not asset_id.is_empty():
		return _find_cached_texture_asset(asset_id)
	return ""


func _resolve_exact_texture_content_to_local_path(content: Variant) -> String:
	var source := _content_to_string(content).strip_edges()
	if source.is_empty():
		return ""
	if source.begins_with("file://"):
		source = source.substr(7)
	if FileAccess.file_exists(source):
		return source
	var global_source := ProjectSettings.globalize_path(source)
	if global_source != source and FileAccess.file_exists(global_source):
		return global_source
	var asset_id := ""
	if source.begins_with("rbxassetid://"):
		asset_id = _sanitize_asset_id(source.substr("rbxassetid://".length()))
	else:
		asset_id = _sanitize_asset_id(source)
	if asset_id.is_empty():
		return ""
	return _find_cached_exact_texture_asset(asset_id)


func _find_cached_sound_asset(asset_id: String) -> String:
	if asset_id.is_empty():
		return ""
	for ext in SOUND_CACHE_EXTENSIONS_CSV.split(","):
		for base in [SOUND_CACHE_DIR, "res://addons/rbxl_importer/builtin_assets"]:
			var candidate := "%s/%s.%s" % [base, asset_id, ext]
			if _texture_file_has_supported_magic(candidate):
				return candidate
	return ""


func _find_cached_mesh_json_asset(asset_id: String) -> String:
	if asset_id.is_empty():
		return ""
	for base in [SOUND_CACHE_DIR, "res://addons/rbxl_importer/builtin_assets"]:
		var candidate := "%s/%s.mesh.json" % [base, asset_id]
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _find_cached_texture_asset(asset_id: String) -> String:
	if asset_id.is_empty():
		return ""
	for ext in ["asset.png", "asset.jpg", "asset.jpeg", "asset.webp", "exact.png", "exact.jpg", "exact.webp", "png", "jpg", "jpeg", "webp"]:
		for base in [SOUND_CACHE_DIR, "res://addons/rbxl_importer/builtin_assets"]:
			var candidate := "%s/%s.%s" % [base, asset_id, ext]
			if _texture_file_has_supported_magic(candidate):
				return candidate
	return ""


func _texture_file_has_supported_magic(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	if path.begins_with("res://"):
		var resource := load(path)
		return resource is Texture2D
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(mini(file.get_length(), 16))
	file.close()
	return (
		bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	) or (
		bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
	) or (
		bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP"
	)


func _find_cached_exact_texture_asset(asset_id: String) -> String:
	if asset_id.is_empty():
		return ""
	for ext in [
		"asset.png", "asset.jpg", "asset.jpeg", "asset.webp",
		"exact.png", "exact.jpg", "exact.webp",
		"png", "jpg", "jpeg", "webp"
	]:
		for base in [SOUND_CACHE_DIR, "res://addons/rbxl_importer/builtin_assets"]:
			var candidate := "%s/%s.%s" % [base, asset_id, ext]
			if _texture_file_has_supported_magic(candidate):
				return candidate
	return ""


func _cache_file_name_from_path(path: String) -> String:
	if path.begins_with(SOUND_CACHE_DIR + "/"):
		return path.substr((SOUND_CACHE_DIR + "/").length())
	return path.get_file()


func _load_runtime_texture(data: Dictionary) -> Texture2D:
	var texture_path := str(data.get("resolved_path", "")).strip_edges()
	if texture_path.is_empty():
		texture_path = _resolve_texture_content_to_local_path(data.get("texture", ""))
	if texture_path.is_empty():
		return null
	return _load_texture_from_path(texture_path)


func _load_texture_from_path(texture_path: String) -> Texture2D:
	if texture_path.strip_edges().is_empty():
		return null
	if texture_path.begins_with("res://"):
		var resource := load(texture_path)
		if resource is Texture2D:
			return resource as Texture2D
	if not FileAccess.file_exists(texture_path):
		return null
	var file := FileAccess.open(texture_path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var err := ERR_UNAVAILABLE
	if bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		err = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		err = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = image.load_webp_from_buffer(bytes)
	if err == OK:
		return ImageTexture.create_from_image(image)
	return null


func _content_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return value
	if value is Dictionary:
		var d: Dictionary = value
		for key in ["value", "url", "path", "asset_id", "id"]:
			var candidate := str(d.get(key, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
	if value is Array:
		var a := value as Array
		if not a.is_empty():
			return _content_to_string(a[0])
	return str(value)


static func _sanitize_asset_id(value: String) -> String:
	var out := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		if ch >= "0" and ch <= "9":
			out += ch
	return out


func _is_global_sound(ref_id: String, parent_map: Dictionary, instances: Dictionary) -> bool:
	if _has_ancestor_class(ref_id, parent_map, instances, ["SoundService"]):
		return true
	var parent_ref := str(parent_map.get(ref_id, ""))
	return parent_ref.is_empty() or parent_ref == "-1"


func _has_ancestor_class(ref_id: String, parent_map: Dictionary, instances: Dictionary, classes: Array[String]) -> bool:
	var cursor := ref_id
	var guard := 0
	while parent_map.has(cursor) and guard < 128:
		cursor = str(parent_map.get(cursor, ""))
		if cursor == "-1" or cursor.is_empty():
			return false
		if classes.has(_class_of_ref(cursor, instances)):
			return true
		guard += 1
	return false


func _class_of_ref(ref_id: String, instances: Dictionary) -> String:
	if instances.has(ref_id):
		var inst: Dictionary = instances[ref_id]
		return str(inst.get("class", ""))
	return ""


func _color_from_data(data: Dictionary) -> Color:
	return _Materials._color_from_array(data.get("color", [1.0, 1.0, 1.0]))


func _prop(props: Dictionary, key: String, fallback: Variant = null) -> Variant:
	return _prop_static(props, key, fallback)


static func _prop_static(props: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if props.has(key):
		return props[key]
	var lower := key.to_lower()
	if props.has(lower):
		return props[lower]
	for candidate in props.keys():
		if str(candidate).to_lower() == lower:
			return props[candidate]
	return fallback


static func _safe_name(raw: Variant) -> String:
	var name := str(raw).strip_edges()
	if name.is_empty():
		name = "Instance"
	return name.replace("/", "_").replace("\\", "_").replace(":", "_")


static func _is_part_class(roblox_class: String) -> bool:
	return roblox_class in [
		"Part", "WedgePart", "CornerWedgePart", "TrussPart",
		"SpawnLocation", "VehicleSeat", "Seat", "MeshPart",
		"UnionOperation", "NegateOperation", "IntersectOperation",
	]


static func _is_structural_class(roblox_class: String) -> bool:
	return roblox_class in [
		"DataModel", "Workspace", "WorldRoot", "Model", "Folder", "Instance",
		"ReplicatedStorage", "ServerStorage", "StarterGui", "StarterPack",
		"StarterPlayer", "Players", "Teams", "Chat", "SoundService",
		"Configuration", "Humanoid", "HumanoidDescription", "Attachment",
		"Accessory", "AccessoryDescription", "Animator", "Animation",
		"AnimationController", "Keyframe", "KeyframeSequence", "Pose",
		"AvatarSettings", "BodyColors", "BodyPartDescription",
		"BubbleChatConfiguration", "ChannelTabsConfiguration",
		"ChatInputBarConfiguration", "ChatWindowConfiguration",
		"AssetService", "CSGDictionaryService", "MaterialService",
		"BindableFunction", "CollectionService", "ContextActionService",
		"CookiesService", "DataStoreService", "Debris", "GamePassService",
		"HttpService", "InsertService", "LocalizationService", "LodDataService",
		"LuaWebService", "NonReplicatedCSGDictionaryService",
		"PermissionsService", "PhysicsService", "PlayerEmulatorService",
		"ProcessInstancePhysicsService", "ProximityPromptService",
		"ReplicatedFirst", "ScriptService", "Selection", "SerializationService",
		"ServerScriptService", "ServiceVisibilityService", "TeleportService",
		"Terrain", "TestService", "TextChatService", "TimerService",
		"TouchInputService", "TweenService", "UGCAvatarService", "VRService",
		"VideoCaptureService", "VideoService", "VirtualInputManager",
		"VoiceChatService",
		"StarterCharacterScripts", "StarterPlayerScripts", "StudioData",
		"DepthOfFieldEffect", "ColorCorrectionEffect", "ColorGradingEffect",
		"ImageLabel", "UICorner", "UIGradient", "UIPadding",
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel",
		"TextButton", "TextBox", "ImageButton", "ScrollingFrame",
		"ViewportFrame", "CanvasGroup", "UIListLayout", "UIGridLayout",
		"UIAspectRatioConstraint", "UIScale", "UIStroke",
		"UISizeConstraint", "UITextSizeConstraint",
		"Shirt", "Pants", "ShirtGraphic", "Tool", "HopperBin", "Backpack",
		"StringValue", "NumberValue", "Vector3Value", "CFrameValue",
		"BoolValue", "IntValue", "ObjectValue", "BrickColorValue", "Color3Value",
		"RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction",
		"ClickDetector", "ProximityPrompt", "PackageLink",
		"Weld", "ManualWeld", "WeldConstraint", "Motor6D", "Snap", "Motor",
		"RotateP", "RotateV",
		"HingeConstraint", "BallSocketConstraint", "SpringConstraint",
		"SpecialMesh", "BlockMesh", "CylinderMesh",
	]
