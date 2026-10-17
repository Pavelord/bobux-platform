extends SceneTree

const ASSETS = preload("res://addons/roblox_runtime/roblox_manifest_assets.gd")
const IMPORTER = preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
var failed: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	print("[asset-roundtrip] ",label,"=",ok)
	if not ok: failed.append(label)

func run():
	var source := "user://validation/nds_performance"
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("map_data.json")))
	var original: Dictionary = payload.roblox_manifest
	var manifest := ASSETS.bind_runtime_assets(original,payload.runtime_objects)
	var poster: Dictionary
	var cloud: Dictionary
	var mesh: Dictionary
	for e in manifest.instances:
		if e.ref=="25": poster=e
		if e.name=="Cloud": cloud=e
		if e.ref=="10243": mesh=e
	check(poster.properties.Texture=="rbxl_texture_01.png", "legacy photo maps to its published local file")
	check(original.instances.filter(func(e): return e.ref=="25")[0].properties.Texture.begins_with("http"), "localization does not mutate imported source")
	var studio = load("res://scripts/place_editor/studio.gd").new()
	studio.current_map_folder=source
	var folder := "user://validation/portable_nds_assets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	studio._store_manifest_asset_files(manifest,folder)
	check(not mesh.properties.MeshId.contains(":") and FileAccess.file_exists(folder.path_join(mesh.properties.MeshId)), "cloud mesh is bundled from Lighting storage")
	check(not poster.properties.Texture.contains(":") and FileAccess.file_exists(folder.path_join(poster.properties.Texture)), "photo is bundled independently of Studio texture cache")
	var exported: Array = studio._collect_publish_asset_file_names({"roblox_manifest":manifest},[],folder)
	check(exported.has(mesh.properties.MeshId) and exported.has(poster.properties.Texture), "both assets enter upload manifest")
	var second := "user://validation/portable_nds_assets_resave"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(second))
	studio.current_map_folder=folder
	studio._store_manifest_asset_files(manifest,second)
	var resolved := ASSETS.resolve(manifest,second)
	var engine := root.get_node("LuaScriptEngine")
	var world := Node3D.new()
	world.set_meta("roblox_class","Workspace")
	world.set_meta("roblox_stud_scale",0.5)
	root.add_child(world)
	for e in resolved.instances:
		if e.ref=="10242": cloud=e
		if e.ref=="10243": mesh=e
		if e.ref=="25": poster=e
	var cloud_node: Node = engine._ensure_manifest_entry_node(world,cloud)
	engine._ensure_manifest_entry_node(cloud_node,mesh)
	var importer := IMPORTER.new()
	importer.materialize_template_part(cloud_node)
	var extent: Vector3 = (cloud_node.transform * cloud_node.get_aabb()).size
	print("[asset-roundtrip] cloud extent=",extent)
	check(extent.x>1000 and extent.z>1000, "cloud keeps authored mesh scale after save/reopen")
	var board = preload("res://addons/roblox_studio/roblox_data_model.gd").create_instance("Part","Board")
	world.add_child(board)
	board.scale=Vector3(8,4,0.5)
	engine._ensure_manifest_entry_node(board,poster)
	importer.restore_part_children(board)
	var faces := board.get_children().filter(func(n): return n.get_meta("roblox_face_decal",false))
	check(faces.size()==1 and faces[0].get_active_material(0).albedo_texture!=null, "photo face restored after second save")
	var model = preload("res://addons/roblox_studio/roblox_data_model.gd").new()
	check(faces.size()==1 and model._should_skip_serialized_node(faces[0]), "rendered decal helper never becomes a duplicate authored object")
	model.free()
	studio.free()
	world.queue_free()
	await process_frame
	print("[asset-roundtrip] failures=",failed)
	quit(0 if failed.is_empty() else 1)
