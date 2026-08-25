extends SceneTree

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "LuaShimScene"
	var world := Node3D.new()
	world.name = "World"
	scene.add_child(world)
	get_root().add_child(scene)
	current_scene = scene
	var script_context := Node.new()
	script_context.name = "ShimScript"
	world.add_child(script_context)
	var code := """
local part = Instance.new("Part")
part.Name = "LuaCreatedPart"
part.Parent = workspace
local players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")
local folder = Instance.new("Folder")
folder.Name = "LuaFolder"
folder.Parent = storage
print(players.LocalPlayer.Name)
"""
	var lua_engine_script := load("res://autoload/lua_script_engine.gd")
	var lua_engine := lua_engine_script.new() as Node
	lua_engine.name = "LuaScriptEngineTest"
	get_root().add_child(lua_engine)
	if lua_engine.has_method("_init_lua_engine"):
		lua_engine.call("_init_lua_engine")
	var result: Dictionary = lua_engine.run_script(code, script_context)
	var created_part := world.get_node_or_null("LuaCreatedPart")
	var storage_root := scene.get_node_or_null("RobloxDataModel/ReplicatedStorage/LuaFolder")
	if storage_root == null:
		storage_root = lua_engine.get_node_or_null("RobloxDataModel/ReplicatedStorage/LuaFolder")
	var manifest := {
		"services": [
			{"ref": "1", "class": "StarterGui", "name": "StarterGui"},
			{"ref": "2", "class": "StarterPack", "name": "StarterPack"},
			{"ref": "3", "class": "ReplicatedStorage", "name": "ReplicatedStorage"}
		],
		"gui": [
			{"ref": "10", "parent_ref": "1", "class": "ScreenGui", "name": "MainGui", "properties": {}},
			{"ref": "11", "parent_ref": "10", "class": "TextButton", "name": "PlayButton", "properties": {"Text": "Play"}}
		],
		"tools": [
			{"ref": "20", "parent_ref": "2", "class": "Tool", "name": "Hammer", "properties": {}}
		],
		"storage_libraries": [
			{"ref": "30", "service_name": "ReplicatedStorage", "class": "Folder", "name": "BoatParts"}
		]
	}
	var manifest_result: Dictionary = lua_engine.call("install_roblox_manifest", manifest, script_context)
	var manifest_gui := lua_engine.get_node_or_null("RobloxDataModel/StarterGui/MainGui/PlayButton")
	var manifest_tool := lua_engine.get_node_or_null("RobloxDataModel/StarterPack/Hammer")
	var manifest_storage := lua_engine.get_node_or_null("RobloxDataModel/ReplicatedStorage/BoatParts")
	var ok := bool(result.get("ok", false)) and created_part != null and storage_root != null and bool(manifest_result.get("ok", false)) and manifest_gui != null and manifest_tool != null and manifest_storage != null
	print("[validate_lua_roblox_shim] ok=%s setter_calls=%s setter_type=%s result=%s" % [
		str(ok),
		str(lua_engine.get("_last_property_setter_calls")),
		"%s/%s/hasSet=%s" % [
			str(lua_engine.get("_last_property_setter_target_type")),
			str(lua_engine.get("_last_property_setter_target_class")),
			str(lua_engine.get("_last_property_setter_has_set_property"))
		],
		JSON.stringify(result)
	])
	lua_engine.free()
	scene.free()
	quit(0 if ok else 1)
