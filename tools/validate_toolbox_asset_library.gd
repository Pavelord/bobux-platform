extends SceneTree

const Library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[toolbox_library] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	for query in ["Create a house", "Create a small modern house", "Create a forest", "Create a city street", "Add a chair inside the house", "Create a pistol", "Add a gunshot sound to the pistol", "Create a car and add engine sounds", "Create a medieval village", "Create a sci-fi room", "Add an explosion sound", "Create an office with desks and chairs"]:
		var start := Time.get_ticks_usec()
		var bundle := Library.get_asset_bundle_for_concept(query)
		var primary: Dictionary = bundle.primary_model
		var sound_results: Array = bundle.sounds
		print("[asset_search] " + JSON.stringify({"query": query, "terms": bundle.search_terms, "model": primary.get("id", ""), "score": primary.get("score", 0), "sounds": sound_results.map(func(x): return {"id": x.id, "score": x.score}), "ms": (Time.get_ticks_usec() - start) / 1000.0}))
	check(Library.search_assets("qzxj nevermatchingasset", "model").is_empty(), "unrelated query returns no random model")
	check(not Library.search_assets("дерево", "model").is_empty(), "Russian synonyms find models")
	check(not Library.search_assets("chiar", "model").is_empty(), "typo tolerant model search")
	check(Library.get_asset_bundle_for_concept("small modern house").primary_model.get("role") == "building", "house ranks above walls and windows")
	check("chair" in str(Library.get_asset_bundle_for_concept("chair inside the house").primary_model.get("name")).to_lower(), "requested chair ranks above surrounding house")
	check(Library.get_asset_bundle_for_concept("sci-fi room").primary_model.is_empty(), "room requires assembly rather than one bed")
	check(Library.get_asset_bundle_for_concept("small modern house").sounds.is_empty(), "adjectives do not select unrelated sounds")
	var planner = preload("res://addons/roblox_studio/studio_asset_planner.gd")
	check(planner.plan_for_request("Create a house", {}).get("actions", [{}])[0].get("type") == "spawn_asset", "AI automatically resolves model from library")
	check(planner.plan_for_request("Add a gunshot sound", {"selected_ref": "node:123"}).get("actions", [{}])[0].get("parent") == "node:123", "AI sound edit targets selected object")
	check(planner.plan_for_request("Create a car with a working engine", {}).is_empty(), "compound behavior keeps full contextual planner")
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var selected := Library.search_assets("chair", "model", "", 1)
	if selected.is_empty():
		failures.append("chair missing")
	else:
		var actions := [{"type": "spawn_asset", "id": "chair", "asset_id": selected[0].id}]
		check(studio._apply_studio_ai_actions(actions) == 1, "AI spawns library model by ID")
		var authored: Array = studio.placement_parent.find_children("*", "MeshInstance3D", true, false)
		check(not authored.is_empty() and authored.any(func(x): return x.get_meta("roblox_mesh_applied", false)), "library has real geometry and mesh collision")
		var sound := Library.search_assets("impact", "sound", "", 1)
		if not sound.is_empty():
			var target: Node = authored[0]
			check(studio._apply_studio_ai_actions([{"type": "attach_sound", "asset_id": sound[0].id, "parent": studio._studio_ai_node_reference(target)}]) == 1, "AI attaches playable sound to existing object")
	studio._show_studio_ai_window()
	await process_frame
	check(studio.toolbox_content_tabs.current_tab == 1 and studio.studio_ai_dock.is_visible_in_tree(), "AI button selects AI tab")
	studio._show_studio_ai_window()
	check(studio.toolbox_dock_panel.visible and studio.toolbox_content_tabs.current_tab == 1, "repeated AI click stays open")
	studio._toggle_tool_window("toolbox")
	await process_frame
	check(studio.toolbox_content_tabs.current_tab == 0 and not studio.studio_ai_dock.is_visible_in_tree(), "Toolbox tab does not overlap AI")
	var browser: Node = studio.toolbox_content_tabs.get_child(0)
	check(browser.items.item_count <= 24, "Toolbox renders only one page")
	studio.queue_free()
	await process_frame
	await process_frame
	print("[toolbox_library] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
