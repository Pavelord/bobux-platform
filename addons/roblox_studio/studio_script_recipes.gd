extends RefCounted

# Tested building blocks available even when the remote provider is unavailable.
const DOUBLE_JUMP := """-- LocalScript in StarterPlayer > StarterCharacterScripts
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local input = game:GetService("UserInputService")
local jumps = 0
local maxJumps = 2

input.JumpRequest:Connect(function()
    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Dead then return end
    -- Walking off a ledge consumes the ground jump.
    if state == Enum.HumanoidStateType.Freefall and jumps == 0 then
        jumps = 1
    end
    if jumps < maxJumps then
        jumps = jumps + 1
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

humanoid.StateChanged:Connect(function(_, state)
    if state == Enum.HumanoidStateType.Landed then
        jumps = 0
    end
end)
"""

static func plan_for_request(prompt: String, context: Dictionary) -> Dictionary:
	var lower := prompt.to_lower()
	# Recipes cover small, well-defined requests. Editing arbitrary authored
	# objects, extra constraints and compound tasks need the contextual planner.
	if prompt.length() > 180:
		return {}
	var exclusions := RegEx.new()
	exclusions.compile("(?i)(удал|убер|отключ|без |remove|disable|анимац|animation|частиц|particle)")
	if exclusions.search(prompt) != null:
		return {}
	var editing := RegEx.new()
	editing.compile("(?i)(исправ|почин|передел|измени|редакт|fix|repair|edit|update)")
	var starts_held := "сразу в рук" in lower or "изначально в рук" in lower or "сразу в руках" in lower or "equipped" in lower
	if editing.search(prompt) == null:
		var library = preload("res://addons/roblox_studio/studio_gameplay_library.gd")
		if ("зомби" in lower or "zombie" in lower or "npc" in lower or "нпс" in lower):
			return library.npc_plan()
		if ("пистолет" in lower or "pistol" in lower):
			return library.weapon_plan(false, starts_held)
		if ("рпг" in lower or "rpg" in lower or "ракетниц" in lower or "rocket launcher" in lower):
			return library.weapon_plan(true, starts_held)
	if ("кнопк" in lower or "button" in lower or "gui" in lower) and ("очк" in lower or "point" in lower):
		if editing.search(prompt) != null or _has_named_instance(context, "ScoreGui"):
			return {}
		var quantities := RegEx.new()
		quantities.compile("[2-9]|[0-9]{2}|пять|десять|два|три")
		if quantities.search(prompt) != null:
			return {}
		return points_button_plan()
	if ("монет" in lower or "coin" in lower) and ("бафф" in lower or "buff" in lower or "усил" in lower or "буст" in lower or "скорост" in lower):
		if editing.search(prompt) != null or _has_named_instance(context, "BuffCoin"):
			return {}
		var plan := buff_coin_plan()
		if starts_held:
			plan.actions[0].parent = "StarterPack"
			plan.actions[3].source += "\nlocal player = game:GetService('Players').LocalPlayer\nlocal character = player.Character or player.CharacterAdded:Wait()\ncharacter:WaitForChild('Humanoid'):EquipTool(tool)\n"
		return plan
	if ("летат" in lower or "полёт" in lower or "полет" in lower or "fly" in lower) and ("заж" in lower or "удерж" in lower or "hold" in lower):
		return _character_recipe("HoldToFly", HOLD_TO_FLY, context, "Полёт работает при удержании Space; отпускание возвращает обычное падение.")
	var pattern := RegEx.new()
	pattern.compile("(?i)((двойн|тройн|четверн)[а-яё]*[ \\t]+прыж|(double|triple)[ \\t-]*jump|[2-9][ \\t]+прыж)")
	# Longer requests can combine custom mechanics; let the provider plan those.
	if prompt.length() > 180 or pattern.search(prompt) == null:
		return {}
	var jump_count := 3 if "тройн" in lower or "triple" in lower else (4 if "четверн" in lower else 2)
	var number := RegEx.new()
	number.compile("([2-9])[ \\t]+прыж")
	var count_match := number.search(lower)
	if count_match != null: jump_count = int(count_match.get_string(1))
	var target := ""
	if str(context.get("selected_class", "")) in ["Script", "LocalScript"]:
		for entry in context.get("scene", []):
			if str(entry.get("ref", "")) != str(context.get("selected_ref", "")):
				continue
			var source := str(entry.get("source", ""))
			if editing.search(prompt) != null or source.contains("JumpRequested") or (source.contains("JumpRequest") and source.contains("maxJumps")):
				target = str(context.get("selected_ref", ""))
			break
	if target.is_empty():
		for entry in context.get("scene", []):
			if str(entry.get("name", "")) in ["DoubleJump", "TripleJump", "MultiJump"] and str(entry.get("class", "")) in ["Script", "LocalScript"] and str(entry.get("source", "")).contains("maxJumps"):
				target = str(entry.get("ref", ""))
				break
	var recipe_name := "DoubleJump" if jump_count == 2 else ("TripleJump" if jump_count == 3 else "MultiJump")
	var action := {"type": "create_script", "name": recipe_name, "script_type": "LocalScript", "parent": "StarterCharacterScripts", "source": DOUBLE_JUMP.replace("local maxJumps = 2", "local maxJumps = %d" % jump_count)}
	if not target.is_empty():
		action["type"] = "update_script"
		action["target"] = target
		action["disabled"] = false
	return {"ok": true, "message": "Настроено прыжков до приземления: %d. LocalScript находится в StarterCharacterScripts и запускается через Play." % jump_count, "actions": [action]}

static func _has_named_instance(context: Dictionary, name_: String) -> bool:
	for entry in context.get("scene", []):
		if str(entry.get("name", "")) == name_:
			return true
	return false

static func _character_recipe(name_: String, source: String, context: Dictionary, message: String) -> Dictionary:
	var action := {"type": "create_script", "name": name_, "script_type": "LocalScript", "parent": "StarterCharacterScripts", "source": source}
	for entry in context.get("scene", []):
		if str(entry.get("name", "")) == name_ and str(entry.get("class", "")) in ["Script", "LocalScript"]:
			action.type = "update_script"
			action.target = entry.ref
			action.disabled = false
			break
	return {"ok": true, "message": message, "actions": [action]}

const HOLD_TO_FLY := """-- LocalScript in StarterCharacterScripts
local input = game:GetService("UserInputService")
local run = game:GetService("RunService")
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local held = false
input.InputBegan:Connect(function(key, processed)
    if key.KeyCode == Enum.KeyCode.Space and not processed then held = true end
end)
input.InputEnded:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.Space then held = false end
end)
run.Heartbeat:Connect(function()
    if held and humanoid.Health > 0 then
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 24, velocity.Z)
    end
end)
"""

static func points_button_plan() -> Dictionary:
	return {"ok": true, "message": "Создан редактируемый GUI со счётчиком и LocalScript. Нажатие добавляет очко текущему игроку в этой сессии.", "actions": [
		{"type": "create_instance", "id": "score_gui", "class": "ScreenGui", "name": "ScoreGui", "parent": "StarterGui"},
		{"type": "create_instance", "id": "score_button", "class": "TextButton", "name": "AddPoint", "parent": "action:score_gui", "properties": {"Text": "Очки: 0  (+1)", "TextSize": 22, "BackgroundColor3": [0.12, 0.32, 0.75], "TextColor3": [1, 1, 1], "Size": {"x": {"scale": 0, "offset": 250}, "y": {"scale": 0, "offset": 60}}, "Position": {"x": {"scale": 0.5, "offset": -125}, "y": {"scale": 0.8, "offset": -30}}}},
		{"type": "create_script", "name": "PointButtonController", "script_type": "LocalScript", "parent": "action:score_button", "source": POINT_BUTTON}
	]}

const POINT_BUTTON := """local player = game:GetService("Players").LocalPlayer
local stats = player:FindFirstChild("leaderstats")
if not stats then
    stats = Instance.new("Folder")
    stats.Name = "leaderstats"
    stats.Parent = player
end
local points = stats:FindFirstChild("Points")
if not points then
    points = Instance.new("IntValue")
    points.Name = "Points"
    points.Value = 0
    points.Parent = stats
end
local button = script.Parent
button.Activated:Connect(function()
    points.Value = points.Value + 1
    button.Text = "Очки: " .. tostring(points.Value) .. "  (+1)"
end)
"""

static func buff_coin_plan() -> Dictionary:
	return {"ok": true, "message": "Создана монета Tool с Handle и ClickDetector. Клик подбирает её в Backpack; экипировка даёт баффы, убирание возвращает прежние параметры.", "actions": [
		{"type": "create_instance", "id": "buff_coin", "class": "Tool", "name": "BuffCoin", "parent": "Workspace", "properties": {"ToolTip": "Speed and jump bonus while equipped", "RequiresHandle": true}},
		{"type": "create_part", "id": "coin_handle", "name": "Handle", "parent": "action:buff_coin", "shape": "Cylinder", "size": [2, 0.3, 2], "rotation": [90, 0, 0], "position": [0, 3, 0], "color": "#F5C542", "anchored": true, "can_collide": false},
		{"type": "create_instance", "class": "ClickDetector", "name": "ClickDetector", "parent": "action:coin_handle", "properties": {"MaxActivationDistance": 32}},
		{"type": "create_script", "name": "BuffCoinController", "script_type": "Script", "parent": "action:buff_coin", "source": BUFF_COIN}
	]}

const BUFF_COIN := """local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local detector = handle:WaitForChild("ClickDetector")
local owner = nil
local activeHumanoid = nil
local previousSpeed, previousJump
detector.MouseClick:Connect(function(player)
    if owner then return end
    owner = player
    tool.Parent = player:WaitForChild("Backpack")
end)
tool.Equipped:Connect(function()
    local humanoid = tool.Parent:FindFirstChildOfClass("Humanoid")
    if not humanoid or activeHumanoid then return end
    activeHumanoid = humanoid
    previousSpeed = humanoid.WalkSpeed
    previousJump = humanoid.JumpPower
    humanoid.WalkSpeed = 30
    humanoid.JumpPower = 70
end)
tool.Unequipped:Connect(function()
    if not activeHumanoid then return end
    activeHumanoid.WalkSpeed = previousSpeed
    activeHumanoid.JumpPower = previousJump
    activeHumanoid = nil
end)
game:GetService("RunService").Heartbeat:Connect(function()
    if not activeHumanoid or activeHumanoid.Health <= 0 then return end
    local root = activeHumanoid.Parent:FindFirstChild("HumanoidRootPart")
    if root then
        local velocity = root.AssemblyLinearVelocity
        if velocity.Y < -22 then
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, -22, velocity.Z)
        end
    end
end)
"""
