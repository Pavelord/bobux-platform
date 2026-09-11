extends RefCounted

static func weapon_source(damage: float, cooldown: float, rocket: bool = false, equipped_on_spawn: bool = false) -> String:
	return WEAPON.replace("__DAMAGE__", str(damage)).replace("__COOLDOWN__", str(cooldown)).replace("__ROCKET__", "true" if rocket else "false").replace("__EQUIP__", "true" if equipped_on_spawn else "false")

static func weapon_plan(rocket: bool = false, equipped_on_spawn: bool = false) -> Dictionary:
	var actions: Array = [{"type": "create_instance", "id": "weapon", "class": "Tool", "name": "RPG" if rocket else "Pistol", "parent": "StarterPack", "properties": {"RequiresHandle": true, "ToolTip": "Click to fire"}}]
	var parts: Array = [
		{"name": "Handle", "size": [0.4, 1, 0.5], "position": [0, 0, 0], "color": "#242832"},
		{"name": "Barrel", "size": [0.6, 0.6, 2.4] if rocket else [0.45, 0.45, 1.6], "position": [0, 0.55, -0.5], "color": "#657048" if rocket else "#697380"},
		{"name": "Sight", "size": [0.15, 0.2, 0.2], "position": [0, 0.95, -1], "color": "#111820"}]
	for part in parts:
		part.merge({"type": "create_part", "parent": "action:weapon", "anchored": true, "can_collide": false})
		actions.append(part)
	var library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
	var models := library.search_assets("blaster" if not rocket else "blaster r", "model", "Weapons", 1)
	if not models.is_empty():
		# The Handle remains the stable grip/script target; visual geometry is
		# selected by the same library resolver used by the Toolbox browser.
		actions = actions.slice(0, 2)
		actions[1]["transparency"] = 1.0
		actions.append({"type": "spawn_asset", "asset_id": models[0].id, "parent": "action:weapon", "scale": [0.7, 0.7, 0.7], "position": [0, -0.2, 0]})
	var shot_sounds := library.search_assets("laser", "sound", "", 1)
	if not shot_sounds.is_empty():
		actions.append({"type": "attach_sound", "asset_id": shot_sounds[0].id, "parent": "action:weapon"})
	actions.append({"type": "create_script", "name": "WeaponController", "script_type": "LocalScript", "parent": "action:weapon", "source": weapon_source(70 if rocket else 25, 1.0 if rocket else 0.25, rocket, equipped_on_spawn)})
	return {"ok": true, "message": "Создан Tool в StarterPack с прицелом и снарядами. Постройки разрушаются при атрибуте Destructible=true. Урон проверяется локально в Play; сетевая серверная проверка выстрела требует отдельного контроллера.", "actions": actions}

const WEAPON := """-- LocalScript inside a Tool with a Handle.
local tool = script.Parent
local players = game:GetService("Players")
local run = game:GetService("RunService")
local player = players.LocalPlayer
local mouse = player:GetMouse()
local damage, cooldown = tool:GetAttribute("Damage") or __DAMAGE__, tool:GetAttribute("Cooldown") or __COOLDOWN__
local rocket = __ROCKET__
local lastShot = -100
local sight = Instance.new("ScreenGui")
sight.Name = tool.Name .. "Sight"
sight.Enabled = false
sight.Parent = player.PlayerGui
local crosshair = Instance.new("TextLabel")
crosshair.Name = "Crosshair"
crosshair.Text = "+"
crosshair.TextSize = 28
crosshair.TextColor3 = Color3.new(1, 1, 1)
crosshair.BackgroundTransparency = 1
crosshair.BorderSizePixel = 0
crosshair.Size = UDim2.new(0, 32, 0, 32)
crosshair.Position = UDim2.new(0.5, -16, 0.5, -16)
crosshair.Parent = sight
tool.Equipped:Connect(function() sight.Enabled = true end)
tool.Unequipped:Connect(function() sight.Enabled = false end)
tool.Destroying:Connect(function() sight:Destroy() end)
run.RenderStepped:Connect(function()
    if sight.Enabled then crosshair.Position = UDim2.new(0, mouse.X - 16, 0, mouse.Y - 16) end
end)
tool.Activated:Connect(function()
    damage = tool:GetAttribute("Damage") or damage
    cooldown = tool:GetAttribute("Cooldown") or cooldown
    local now = os.clock()
    if now - lastShot < cooldown then return end
    local character = player.Character
    if not character or tool.Parent ~= character then return end
    local origin = tool.Handle.Position
    local offset = mouse.Hit.Position - origin
    if offset.Magnitude < 0.01 then return end
    lastShot = now
    local shotSound = tool:FindFirstChildOfClass("Sound")
    if shotSound then shotSound:Play() end
    local direction = offset.Unit
    local bullet = Instance.new("Part")
    bullet.Name = rocket and "Rocket" or "Bullet"
    bullet.Size = rocket and Vector3.new(0.5, 0.5, 1.8) or Vector3.new(0.15, 0.15, 0.8)
    bullet.Color = rocket and Color3.new(1, 0.35, 0.05) or Color3.new(1, 0.9, 0.3)
    bullet.Anchored = true
    bullet.CanCollide = false
    bullet.CanQuery = false
    bullet.Position = origin
    bullet.Parent = workspace
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {character, bullet}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local traveled = 0
    local position = origin
    local connection
    connection = run.Heartbeat:Connect(function(dt)
        local step = direction * (rocket and 75 or 240) * dt
        local hit = workspace:Raycast(position, step, params)
        position = hit and hit.Position or position + step
        bullet.CFrame = CFrame.lookAt(position, position + direction)
        traveled = traveled + step.Magnitude
        if hit then
            local target = hit.Instance:FindFirstAncestorOfClass("Model")
            local humanoid = target and target:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:TakeDamage(damage) end
            if rocket then
                local blast = Instance.new("Explosion")
                blast.Position = hit.Position
                blast.BlastRadius = 12
                blast.BlastPressure = 300000
                blast.DestroyJointRadiusPercent = 0
                blast.Hit:Connect(function(part)
                    -- Only explicitly marked construction is destructible.
                    if part:GetAttribute("Destructible") then part.Anchored = false end
                end)
                blast.Parent = workspace
            end
        end
        if hit or traveled >= 600 then
            connection:Disconnect()
            bullet:Destroy()
        end
    end)
end)
if tool:GetAttribute("EquipOnSpawn") or __EQUIP__ then
    local character = player.Character or player.CharacterAdded:Wait()
    character:WaitForChild("Humanoid"):EquipTool(tool)
end
"""

const NPC_CHASE := """-- Script inside a Model with Humanoid and HumanoidRootPart.
local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
local root = npc:WaitForChild("HumanoidRootPart")
local players = game:GetService("Players")
local lastAttack = -100
humanoid:TakeDamage(0) -- initialize collision and health display even outside detection range
while humanoid.Health > 0 do
    local nearest, distance = nil, npc:GetAttribute("DetectionRange") or 80
    for _, player in ipairs(players:GetPlayers()) do
        local character = player.Character
        local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
            local candidate = (targetRoot.Position - root.Position).Magnitude
            if candidate < distance then nearest, distance = character, candidate end
        end
    end
    if nearest then
        humanoid:MoveTo(nearest.HumanoidRootPart.Position)
        if distance < 4 and os.clock() - lastAttack >= 1 then
            lastAttack = os.clock()
            nearest.Humanoid:TakeDamage(npc:GetAttribute("Damage") or 10)
        end
    end
    task.wait(0.2)
end
"""

static func npc_plan() -> Dictionary:
	return {"ok": true, "message": "Создан NPC с Humanoid: идёт к ближайшему игроку и атакует вблизи. Этот контроллер не строит маршрут вокруг препятствий.", "actions": [
		{"type": "create_model", "id": "npc", "name": "Zombie", "parts": [
			{"name": "HumanoidRootPart", "size": [2, 2, 1], "position": [0, 3, 0], "color": "#4C7040", "anchored": true},
			{"name": "Head", "size": [2, 1, 1], "position": [0, 4.5, 0], "color": "#77A65C", "anchored": true},
			{"name": "LeftArm", "size": [1, 2, 1], "position": [-1.5, 3, 0], "color": "#77A65C", "anchored": true},
			{"name": "RightArm", "size": [1, 2, 1], "position": [1.5, 3, 0], "color": "#77A65C", "anchored": true},
			{"name": "LeftLeg", "size": [1, 2, 1], "position": [-0.5, 1, 0], "color": "#33405C", "anchored": true},
			{"name": "RightLeg", "size": [1, 2, 1], "position": [0.5, 1, 0], "color": "#33405C", "anchored": true},
			{"name": "LeftEye", "size": [0.22, 0.18, 0.06], "position": [-0.4, 4.65, 0.52], "color": "#182C15", "anchored": true, "can_collide": false},
			{"name": "RightEye", "size": [0.22, 0.18, 0.06], "position": [0.4, 4.65, 0.52], "color": "#182C15", "anchored": true, "can_collide": false},
			{"name": "Mouth", "size": [0.7, 0.12, 0.06], "position": [0, 4.3, 0.52], "color": "#182C15", "anchored": true, "can_collide": false}]},
		{"type": "create_instance", "class": "Humanoid", "name": "Humanoid", "parent": "action:npc", "properties": {"Health": 100, "WalkSpeed": 10}},
		{"type": "create_script", "name": "Chase", "script_type": "Script", "parent": "action:npc", "source": NPC_CHASE}
	]}
