extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine := root.get_node_or_null("LuaScriptEngine")
	if engine == null:
		push_error("LuaScriptEngine autoload is missing")
		quit(1)
		return
	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	root.add_child(workspace)
	var model := Node3D.new()
	model.name = "Model"
	model.set_meta("roblox_class", "Model")
	workspace.add_child(model)
	var target := Node3D.new()
	target.name = "Target"
	target.set_meta("roblox_class", "Part")
	model.add_child(target)
	var script_node := Node.new()
	script_node.name = "ServiceCompatibility"
	script_node.set_meta("roblox_class", "Script")
	model.add_child(script_node)

	var source := """
local dataStores = game:GetService("DataStoreService")
local scores = dataStores:GetDataStore("Compatibility")
scores:SetAsync("score", 4)
local updated = scores:UpdateAsync("score", function(value)
    return (value or 0) + 3
end)
local ordered = dataStores:GetOrderedDataStore("Leaderboard")
ordered:SetAsync("player", 12)
local page = ordered:GetSortedAsync(false, 10):GetCurrentPage()

local collection = game:GetService("CollectionService")
collection:AddTag(script.Parent.Target, "Enemy")
local tagged = collection:GetTagged("Enemy")
local ancestor = script:FindFirstAncestor("Workspace")
local pivot = script.Parent:GetPivot()

local starterGui = game:GetService("StarterGui")
starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
local coreDisabled = not starterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)

local random = Random.new(1234)
local randomValue = random:NextInteger(5, 5)
debug.setmemorycategory("Compatibility")
local now = os.time()
local purchaseEvent = game:GetService("MarketplaceService").PromptGamePassPurchaseFinished
local promptEvent = game:GetService("ProximityPromptService").PromptButtonHoldBegan

script.Parent.Parent.Value = (
    updated == 7 and page[1].value == 12 and #tagged == 1 and
    collection:HasTag(script.Parent.Target, "Enemy") and ancestor ~= nil and
    pivot ~= nil and coreDisabled and randomValue == 5 and now > 0 and
    purchaseEvent ~= nil and promptEvent ~= nil
)
"""
	engine.reset_runtime_diagnostics()
	var result: Dictionary = engine.start_script(source, script_node, {"realm": "server", "is_server": true})
	for _frame in range(12):
		await process_frame
		engine._process(0.016)
	var diagnostics: Dictionary = engine.get_runtime_diagnostics()
	var ok := bool(result.get("ok", false)) and bool(workspace.get_meta("value", false))
	ok = ok and int(diagnostics.get("failed", 0)) == 0
	print("[validate_lua_service_compatibility] ok=", ok, " result=", result, " diagnostics=", diagnostics)
	engine.stop_all_scripts(workspace)
	workspace.queue_free()
	await process_frame
	quit(0 if ok else 1)
