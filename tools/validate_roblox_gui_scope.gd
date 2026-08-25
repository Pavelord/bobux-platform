extends SceneTree

const RobloxGuiRuntime := preload("res://addons/rbxl_importer/roblox_gui_runtime.gd")


func _initialize() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	get_root().add_child(host)
	var manifest := {
		"services": [
			{"ref": "starter_gui", "class": "StarterGui", "name": "StarterGui"},
			{"ref": "starter_pack", "class": "StarterPack", "name": "StarterPack"},
			{"ref": "server_storage", "class": "ServerStorage", "name": "ServerStorage"},
		],
		"hierarchy": [
			{"child": "visible_gui", "parent": "starter_gui"},
			{"child": "visible_label", "parent": "visible_gui"},
			{"child": "hidden_tool", "parent": "server_storage"},
			{"child": "hidden_script", "parent": "hidden_tool"},
			{"child": "hidden_gui", "parent": "hidden_script"},
			{"child": "hidden_label", "parent": "hidden_gui"},
			{"child": "starter_tool", "parent": "starter_pack"},
		],
		"gui": [
			_gui("visible_gui", "ScreenGui", "VisibleGui", "starter_gui", "StarterGui"),
			_gui("visible_label", "TextLabel", "VisibleLabel", "visible_gui", "StarterGui"),
			_gui("hidden_gui", "ScreenGui", "WeaponHud", "hidden_script", "ServerStorage"),
			_gui("hidden_label", "TextLabel", "Reloading", "hidden_gui", "ServerStorage"),
		],
		"tools": [
			{"ref": "hidden_tool", "class": "Tool", "name": "HiddenTool", "service_name": "ServerStorage", "properties": {}},
			{"ref": "starter_tool", "class": "Tool", "name": "StarterTool", "service_name": "StarterPack", "properties": {}},
		],
	}
	var runtime := RobloxGuiRuntime.apply_manifest(host, manifest, {
		"draw_gui": true,
		"draw_tools": true,
		"editor_preview": true,
		"ignore_mouse": true,
	})
	var visible_label := _find_by_ref(runtime, "visible_label")
	var hidden_label := _find_by_ref(runtime, "hidden_label")
	var visible_tool := _find_by_ref(runtime, "starter_tool")
	var hidden_tool := _find_by_ref(runtime, "hidden_tool")
	var ok := (
		visible_label != null
		and hidden_label == null
		and visible_tool != null
		and hidden_tool == null
		and int(runtime.get_meta("built_gui_controls", -1)) == 2
		and int(runtime.get_meta("built_tool_controls", -1)) == 1
	)
	print("[validate_roblox_gui_scope] ok=%s visible_gui=%d visible_tools=%d hidden_gui=%s hidden_tool=%s" % [
		str(ok),
		int(runtime.get_meta("built_gui_controls", -1)),
		int(runtime.get_meta("built_tool_controls", -1)),
		str(hidden_label != null),
		str(hidden_tool != null),
	])
	quit(0 if ok else 1)


func _gui(ref: String, roblox_class: String, item_name: String,
		parent_ref: String, service_name: String) -> Dictionary:
	return {
		"ref": ref,
		"class": roblox_class,
		"name": item_name,
		"parent_ref": parent_ref,
		"service_name": service_name,
		"properties": {
			"Visible": true,
			"Enabled": true,
			"Text": item_name,
			"Size": [0.0, 180.0, 0.0, 40.0],
			"Position": [0.0, 0.0, 0.0, 0.0],
		},
	}


func _find_by_ref(root: Node, ref: String) -> Node:
	if root == null:
		return null
	if str(root.get_meta("roblox_ref", "")) == ref:
		return root
	for child in root.get_children():
		var found := _find_by_ref(child, ref)
		if found != null:
			return found
	return null
