extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine := root.get_node_or_null("LuaScriptEngine")
	if engine == null:
		push_error("LuaScriptEngine autoload is missing")
		quit(1)
		return
	var workspace := Node.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	root.add_child(workspace)
	var script_node := Node.new()
	script_node.name = "LuauCompatibility"
	script_node.set_meta("roblox_class", "Script")
	workspace.add_child(script_node)
	var source := """
--!strict
type Entry = {
    value: any,
    next: Entry?
}
local current: { [number]: any }?
local runContext: "server" | "client" = "server"
local typedCallback = function(listener: (number, string) -> ()): () -> ()
    return function (): ()
        listener(1, "ok")
    end
end
local total: number = 1
local function add(value: number): number
    total += value
    return total
end
for _, value in {2, 3} do
    total += value
end
local label = if total > 5 then "ok" else "bad"
local casted = total :: number
local template = `Total {total}`
local inline = string.format("%s", if total > 5 then (" %s"):format("ok") else "")
local color = Color3.fromHSV(0.0, 1.0, 1.0)
local params = RaycastParams.new()
local enumValue = Enum.BulkMoveMode.FireAllEvents
local optional = {Value = if total > 5 then nil else total, Occupies = 1}
script.Parent:SetAttribute("Literal", "asset_123_456; text")
local part = Instance.new("Part")
part.Name = "Multi_123_456"; part.Anchored = true; part.CanCollide = false
part.Parent = script.Parent
script.Parent.Value = (label == "ok" and casted == 6 and template == "Total 6" and inline == " ok" and color ~= nil and params ~= nil and enumValue == 0 and current == nil and runContext == "server" and typedCallback ~= nil and optional.Value == nil and optional.Occupies == 1) and add(4) or -1;
"""
	var result: Dictionary = engine.start_script(
		source,
		script_node,
		{"realm": "server", "is_server": true}
	)
	for _frame in range(4):
		await process_frame
		engine._process(0.016)
	var ok := bool(result.get("ok", false))
	ok = ok and int(workspace.get_meta("value", -1)) == 10
	ok = ok and workspace.get_meta("attribute_Literal", "") == "asset_123_456; text"
	var multi: Node = workspace.get_node_or_null("Multi_123_456")
	ok = ok and multi != null and not bool(engine.BobuxInstance.new(multi).GetProperty("CanCollide"))
	if not ok:
		var prepared: String = engine.call("_prepare_scheduled_lua_source", source)
		for line_number in range(prepared.split("\n").size()):
			print("%04d: %s" % [line_number + 1, prepared.split("\n")[line_number]])
	print(
		"[validate_luau_compatibility] ok=", ok,
		" value=", workspace.get_meta("value") if workspace.has_meta("value") else null,
		" result=", result
	)
	engine.stop_all_scripts(workspace)
	quit(0 if ok else 1)
