extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var cloud := root.get_node("CloudAPI")
	var result: Dictionary = await cloud.download_map_with_cache("z9ovqynlv860sgw_coller", "", "coller")
	if not result.get("ok",false): print(result); quit(1); return
	root.get_node("GameState").selected_map_folder = result.folder
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.set_script(load("res://tools/fixtures/published_runtime_fixture.gd"))
	root.add_child(main)
	current_scene = main
	await main._load_selected_map()
	var board: Node = main._find_runtime_part_by_roblox_ref(main.world,"24")
	var decal: Node = board.get_node_or_null("Decal")
	var window: Node = main._find_runtime_part_by_roblox_ref(main.world,"1014")
	var faces: Array = board.get_children().filter(func(n): return n.get_meta("roblox_face_decal", false))
	var path: String = decal.get_meta("roblox_properties",{}).get("Texture","") if decal else ""
	var ok := decal != null and FileAccess.file_exists(path) and faces.size()==1 and faces[0].get_active_material(0).albedo_texture != null
	ok = ok and is_equal_approx(float(window.get_meta("roblox_properties",{}).get("Transparency",0)),0.75)
	var engine := root.get_node("LuaScriptEngine")
	var services: Dictionary = engine._ensure_roblox_service_nodes(root,main.world)
	var cloud_part: Node = services.Lighting.get_node_or_null("Cloud")
	if cloud_part:
		var importer: RefCounted = engine.template_importer_for(main.world)
		importer.materialize_template_part(cloud_part)
		ok = ok and cloud_part.mesh is ArrayMesh
	print("[published-media] PASS=",ok," decal=",path," faces=",faces.size()," cloud_mesh=",cloud_part.mesh.get_class() if cloud_part and cloud_part.mesh else "missing")
	# Parse the new collection and test the request-complete UI state.
	var collection = load("res://scripts/lobby/roblox_legends_panel.gd")
	var dialog: CanvasLayer = load("res://scripts/ui/place_reward_dialog.gd").new()
	root.add_child(dialog)
	dialog.busy()
	dialog.configure("gamepass_coin",{"price":150,"balance":200})
	ok = ok and not dialog.action.disabled and collection != null
	quit(0 if ok else 1)
