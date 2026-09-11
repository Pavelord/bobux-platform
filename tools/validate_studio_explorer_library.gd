extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[studio_library] %s=%s" % [label_, ok])
	if not ok: failures.append(label_)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var library = load("res://addons/roblox_studio/studio_script_library.gd")
	var engine := root.get_node("LuaScriptEngine")
	var contract = load("res://addons/roblox_studio/roblox_script_contract.gd")
	for entry in library.entries():
		for action in entry.plan.get("actions", []):
			if action.get("type") != "create_script": continue
			var validation: Dictionary = engine.validate_script_source(action.source)
			check(bool(validation.ok) and contract.errors(action.source).is_empty(), "compiles: " + entry.title)
	check(contract.errors("local h = character:WaitForChild('Humanoid')\nh.Gravity = 0.5").size() == 1, "invalid Humanoid API rejected")
	check(contract.errors("local h = character:WaitForChild('Humanoid')\n-- h.Gravity = 0.5\nprint('h.Gravity')").is_empty(), "comments and literals never trigger API rejection")
	studio._apply_studio_ai_actions(library.entries()[3].plan.actions)
	var coin: Node = studio.placement_parent.get_node("BuffCoin")
	var script_node: Node = coin.get_node("BuffCoinController")
	var item: TreeItem = studio.roblox_explorer.find_item_for_node(studio.explorer_tree, script_node)
	var parent_item: TreeItem = studio.roblox_explorer.find_item_for_node(studio.explorer_tree, coin)
	check(item != null and item.get_parent() == parent_item, "Explorer shows item script below its Tool")
	check(item.get_text(1) == "Script", "Explorer shows script class")
	var original_id := script_node.get_instance_id()
	var edits := [{"type": "update_script", "target": studio._studio_ai_node_reference(script_node), "source": "script.Parent:SetAttribute('Edited', true)"}]
	check(studio._apply_studio_ai_actions(edits) == 1 and coin.get_node("BuffCoinController").get_instance_id() == original_id, "AI edits existing script in place")
	var target: Node = studio.data_model.ensure_service("StarterPlayer").get_node("StarterCharacterScripts")
	studio._add_script_to_node(target)
	check(str(target.get_child(target.get_child_count() - 1).get_meta("roblox_class")) == "LocalScript", "character scripts insert in selected service with correct class")
	var dialog: AcceptDialog = library.open(studio, studio._apply_studio_ai_actions)
	await process_frame
	check(dialog.visible and dialog.find_children("*", "CodeEdit", true, false).size() == 1, "Learn opens searchable code library")
	dialog.queue_free()
	studio.queue_free()
	await process_frame
	await process_frame
	print("[studio_library] failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
