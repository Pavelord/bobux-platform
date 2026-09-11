extends RefCounted

const Gameplay = preload("res://addons/roblox_studio/studio_gameplay_library.gd")
const Assets = preload("res://addons/roblox_studio/toolbox_asset_library.gd")

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in [
		["sword", "Меч", "Оружие", "Взмах, проверка дистанции и препятствий, урон Humanoid. Damage, Range, Cooldown."],
		["hammer", "Молоток", "Оружие", "Ближний удар по Humanoid; скрипт и детали доступны для редактирования."],
		["revolver", "Револьвер", "Оружие", "Шесть выстрелов; R перезаряжает. Damage, Cooldown, ReloadTime."],
		["apple", "Яблоко", "Еда", "Activated восстанавливает Health и расходует предмет. HealAmount."],
		["burger", "Бургер", "Еда", "Еда с моделью из CC0-библиотеки и восстановлением здоровья."],
		["health_potion", "Зелье здоровья", "Еда", "Восстанавливает 60 HP; количество лечения настраивается."],
		["flying_carpet", "Ковёр-самолёт", "Транспорт", "Экипировать: полёт. WASD — движение, Space — вверх, LeftControl — вниз; убрать — приземление."],
		["airplane", "Самолёт", "Транспорт", "Физический корпус, тяга и подъёмная сила. E сесть, W/S тяга, A/D поворот, стрелки вверх/вниз — тангаж, Space выйти."],
		["seat", "Сиденье", "Взаимодействия", "E посадить персонажа, Space встать."],
		["lucky_block", "Лаки-блок", "Предметы", "Предмет в инвентаре. Использовать один раз — получить случайный предмет из редактируемого пула."],
		["lucky_spawner", "Спавнер лаки-блоков", "Спавнеры", "Плоский цилиндр, вращающийся куб, повторный подбор по E. Бесплатные награды: оружие и еда."],
		["item_spawner", "Спавнер предметов", "Спавнеры", "Повторно выдаёт копии выбранного предмета: sword, hammer, revolver, apple, burger. Cooldown, InventoryLimit."],
		["teams", "Две команды и точки появления", "Режим", "Красная и синяя команды, равномерное назначение, отдельные точки появления. Названия редактируются в Teams."],
		["npc_citizen", "NPC · горожанин", "NPC", "Риг пропорций персонажа Bobux; стоит, показывает здоровье и получает урон."],
		["npc_guard", "NPC · охранник", "NPC", "Защищает область: преследует ближайшего игрока в радиусе DetectionRange."],
		["npc_follower", "NPC · спутник", "NPC", "Идёт за ближайшим игроком без нанесения урона."],
		["npc_patrol", "NPC · патруль", "NPC", "Обходит четыре точки вокруг места появления. PatrolRadius, WalkSpeed."],
		["npc_dialogue", "NPC · диалог", "NPC", "Подойти и нажать E: реплика появляется на экране. DialogueText."],
		["npc_boss", "NPC · большой противник", "NPC", "Увеличенный риг, 500 HP, ближняя атака. Размер и характеристики редактируются."],
	]:
		result.append({"id": row[0], "name": row[1], "category": row[2], "description": row[3]})
	return result

static func parameters(id: String) -> Dictionary:
	if id in ["npc_citizen", "npc_guard", "npc_follower", "npc_patrol", "npc_dialogue", "npc_boss"]: return {"Health": 500 if id == "npc_boss" else 100, "WalkSpeed": 12, "Damage": 25 if id == "npc_boss" else 10, "DetectionRange": 40, "PatrolRadius": 12, "DialogueText": "Привет! Добро пожаловать в Bobux."}
	match id:
		"sword", "hammer": return {"Damage": 30, "Range": 6, "Cooldown": 0.6}
		"revolver": return {"Damage": 45, "Cooldown": 0.5, "ReloadTime": 1.5}
		"apple", "burger", "health_potion": return {"HealAmount": 60 if id == "health_potion" else 35}
		"flying_carpet": return {"Speed": 35}
		"airplane": return {"MaxSpeed": 90}
		"lucky_spawner": return {"Cooldown": 0.5, "InventoryLimit": 64}
		"item_spawner": return {"Item": "sword", "Cooldown": 1, "InventoryLimit": 64}
	return {}

static func _script(parent: String, source: String, local_: bool = false, name_: String = "Controller") -> Dictionary:
	return {"type": "create_script", "parent": parent, "source": source, "script_type": "LocalScript" if local_ else "Script", "name": name_}

static func _prompt(parent: String, text_: String) -> Dictionary:
	return {"type": "create_instance", "class": "ProximityPrompt", "name": "ProximityPrompt", "parent": parent, "properties": {"ActionText": text_, "MaxActivationDistance": 10}}

static func _options(id: String, options: Dictionary) -> Dictionary:
	var result := parameters(id)
	for key in result:
		if not options.has(key): continue
		var value: Variant = options[key]
		if result[key] is String: result[key] = str(value).left(250)
		elif (value is int or value is float) and is_finite(float(value)): result[key] = clampf(float(value), 0.1, 10000)
	result["PrefabId"] = id
	return result

static func plan(id: String, options: Dictionary = {}) -> Dictionary:
	var actions: Array = []
	var attrs := _options(id, options)
	if id in ["sword", "hammer", "apple", "burger", "health_potion", "flying_carpet"]:
		actions = tool_plan(id, attrs)
	elif id == "revolver":
		actions = Gameplay.weapon_plan().actions
		actions[0].name = "Revolver"
		actions[0].properties["Attributes"] = attrs
		var source: String = actions[-1].source
		source = source.replace("local lastShot = -100", "local lastShot = -100\nlocal ammo, reloading = 6, false\nlocal input = game:GetService('UserInputService')\ninput.InputBegan:Connect(function(key, processed)\n if processed or key.KeyCode ~= Enum.KeyCode.R or tool.Parent ~= player.Character or reloading or ammo == 6 then return end\n reloading = true\n task.wait(tool:GetAttribute('ReloadTime') or 1.5)\n ammo = 6; reloading = false\n tool:SetAttribute('Ammo', ammo)\nend)\ntool:SetAttribute('Ammo', ammo)")
		source = source.replace("if now - lastShot < cooldown then return end", "if reloading or ammo <= 0 or now - lastShot < cooldown then return end")
		source = source.replace("lastShot = now", "lastShot = now\n    ammo = ammo - 1\n    tool:SetAttribute('Ammo', ammo)")
		actions[-1].source = source
	elif id in ["npc_citizen", "npc_guard", "npc_follower", "npc_patrol", "npc_dialogue", "npc_boss"]:
		actions = npc_plan(id, attrs)
	elif id == "seat":
		actions = [{"type": "create_part", "id": "seat", "shape": "Seat", "name": "Seat", "size": [2, 0.5, 2], "position": [0, 1, 0], "color": "#4874A5"}, _prompt("action:seat", "Сесть"), _script("action:seat", "script.Parent.ProximityPrompt.Triggered:Connect(function(player)\n local character = player.Character\n if character then script.Parent:Sit(character:WaitForChild('Humanoid')) end\nend)")]
	elif id == "airplane":
		actions = airplane_plan(attrs)
	elif id in ["lucky_block", "lucky_spawner", "item_spawner"]:
		actions = spawner_plan(id, attrs)
	elif id == "teams":
		actions = [{"type": "create_part", "id": "redspawn", "name": "RedTeamSpawn", "shape": "Spawn", "size": [8, 0.5, 8], "position": [-24, 0.25, 0], "color": "#D95252"}, {"type": "create_part", "id": "bluespawn", "name": "BlueTeamSpawn", "shape": "Spawn", "size": [8, 0.5, 8], "position": [24, 0.25, 0], "color": "#438BE0"}, _script("ServerScriptService", TEAMS)]
	else: return {"ok": false, "actions": [], "error": "Неизвестная заготовка: " + id}
	return {"ok": true, "actions": actions, "message": "Создана заготовка «%s». Настройки — Properties → Attributes, код — в Explorer." % id}

static func tool_plan(id: String, attrs: Dictionary) -> Array:
	var actions: Array = [{"type": "create_instance", "id": "tool", "class": "Tool", "name": id.to_pascal_case(), "parent": "StarterPack", "properties": {"RequiresHandle": true, "Attributes": attrs}}, {"type": "create_part", "id": "handle", "name": "Handle", "parent": "action:tool", "size": [0.35, 1.4, 0.35] if id in ["sword", "hammer"] else [1, 1, 1], "color": "#885C38", "can_collide": false}]
	if id in ["sword", "hammer"]:
		actions.append({"type": "create_part", "name": "Blade" if id == "sword" else "HammerHead", "parent": "action:tool", "size": [0.6, 3.5, 0.2] if id == "sword" else [2.2, 1, 1], "position": [0, 2, 0], "color": "#BCD0DE", "can_collide": false})
		actions.append(_script("action:tool", MELEE, true))
	elif id == "flying_carpet":
		actions[1].size = [0.3, 0.3, 0.3]
		actions[1]["transparency"] = 1
		actions.append(_script("action:tool", CARPET, true))
	else:
		var query := "apple" if id == "apple" else ("burger" if id == "burger" else "bottle")
		var models := Assets.search_assets(query, "model", "Food", 1)
		if not models.is_empty():
			var entry: Dictionary = models[0]
			var size_: Array = entry.bounds.size
			var factor := 1.5 / maxf(float(size_[1]) * float(entry.get("units_to_studs", 3)), 0.1)
			actions[1]["transparency"] = 1
			actions.append({"type": "spawn_asset", "asset_id": entry.id, "parent": "action:tool", "scale": [factor, factor, factor]})
		actions.append(_script("action:tool", "local tool = script.Parent\nlocal used = false\ntool.Activated:Connect(function()\n if used then return end\n local humanoid = tool.Parent:FindFirstChildOfClass('Humanoid')\n if not humanoid or humanoid.Health <= 0 then return end\n used = true\n humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (tool:GetAttribute('HealAmount') or 35))\n tool:Destroy()\nend)", true))
	return actions

static func npc_plan(id: String, attrs: Dictionary) -> Array:
	var actions: Array = Gameplay.npc_plan().actions
	var colors := ["#F1CF99", "#497BA6", "#33445B"]
	if id == "npc_guard": colors = ["#DFB991", "#343A4D", "#252C3B"]
	if id == "npc_boss": colors = ["#92AF68", "#773D48", "#292D40"]
	actions[0].name = id.to_pascal_case()
	for part in actions[0].parts:
		if part.name == "Head": part["shape"] = "Cylinder"; part.size = [1.2, 1.2, 1.2]; part.position = [0, 4.6, 0]
		if part.name in ["Head", "LeftArm", "RightArm"]: part.color = colors[0]
		elif part.name == "HumanoidRootPart": part.color = colors[1]
		elif "Leg" in str(part.name): part.color = colors[2]
		if part.name == "LeftArm": part.position[0] = 1.5
		if part.name == "RightArm": part.position[0] = -1.5
		if part.name == "LeftLeg": part.position[0] = 0.5
		if part.name == "RightLeg": part.position[0] = -0.5
		if "Eye" in str(part.name): part.position[0] *= 0.65; part.position[2] = 0.55
		actions[1].properties = {"Health": attrs.Health, "MaxHealth": attrs.Health, "WalkSpeed": attrs.WalkSpeed}
	if id == "npc_follower": attrs.Damage = 0
	actions.append({"type": "update_instance", "target": "action:npc", "properties": {"Attributes": attrs}})
	if id in ["npc_citizen", "npc_dialogue"]: actions[2].source = "script.Parent.Humanoid:TakeDamage(0)"
	elif id == "npc_patrol": actions[2].source = "local npc = script.Parent\nlocal h = npc.Humanoid\nlocal start = npc.HumanoidRootPart.Position\nlocal index = 0\nwhile h.Health > 0 do\n local angle = index * math.pi / 2\n local radius = npc:GetAttribute('PatrolRadius') or 12\n h:MoveTo(start + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))\n task.wait(3)\n index = (index + 1) % 4\nend"
	if id == "npc_boss": actions.append({"type": "modify_object", "target": "action:npc", "scale": [1.5, 1.5, 1.5]})
	if id == "npc_dialogue":
		actions.append(_prompt("action:npc", "Поговорить"))
		actions.append(_script("action:npc", DIALOGUE, false, "Dialogue"))
	return actions

const MELEE := """local tool = script.Parent
local last = -100
local player = game:GetService('Players').LocalPlayer
tool.Activated:Connect(function()
    if os.clock() - last < (tool:GetAttribute('Cooldown') or 0.6) then return end
    local character = player.Character
    if not character or tool.Parent ~= character then return end
    last = os.clock()
    local root = character:WaitForChild('HumanoidRootPart')
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {character}
    local overlap = OverlapParams.new()
    overlap.FilterDescendantsInstances = {character}
    local range = tool:GetAttribute('Range') or 6
    local hitHumanoids = {}
    for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, range, overlap)) do
        local model = part:FindFirstAncestorOfClass('Model')
        local humanoid = model and model:FindFirstChildOfClass('Humanoid')
        local key = model and model:GetFullName()
        if humanoid and humanoid.Health > 0 and not hitHumanoids[key] then
            hitHumanoids[key] = true
            local target = model:FindFirstChild('HumanoidRootPart')
            if target and (target.Position - root.Position).Magnitude <= range then
                local hit = workspace:Raycast(root.Position, target.Position - root.Position, params)
                if hit and hit.Instance:IsDescendantOf(model) then humanoid:TakeDamage(tool:GetAttribute('Damage') or 30) end
            end
        end
    end
    tool.Grip = CFrame.Angles(-1.1, 0, 0)
    task.wait(0.15)
    tool.Grip = CFrame.new()
end)
"""

const CARPET := """local tool = script.Parent
local input = game:GetService('UserInputService')
local active, previousSpeed, carpet
tool.Equipped:Connect(function()
    active = tool.Parent:FindFirstChildOfClass('Humanoid')
    if not active then return end
    previousSpeed = active.WalkSpeed
    active.WalkSpeed = tool:GetAttribute('Speed') or 35
    carpet = Instance.new('Part')
    carpet.Name = 'FlyingCarpetVisual'
    carpet.Size = Vector3.new(5, 0.15, 7)
    carpet.Color = Color3.new(0.65, 0.1, 0.45)
    carpet.Anchored = true; carpet.CanCollide = false; carpet.CanQuery = false
    carpet.Parent = workspace
end)
local function stop()
    if active then active.WalkSpeed = previousSpeed end
    if carpet then carpet:Destroy() end
    active, carpet = nil, nil
end
tool.Unequipped:Connect(stop)
tool.Destroying:Connect(stop)
game:GetService('RunService').Heartbeat:Connect(function()
    if not active or active.Health <= 0 then return end
    local root = active.Parent:FindFirstChild('HumanoidRootPart')
    if not root then return end
    local velocity = root.AssemblyLinearVelocity
    local vertical = input:IsKeyDown(Enum.KeyCode.Space) and 20 or (input:IsKeyDown(Enum.KeyCode.LeftControl) and -15 or 0)
    root.AssemblyLinearVelocity = Vector3.new(velocity.X, vertical, velocity.Z)
    carpet.CFrame = root.CFrame * CFrame.new(0, -2.8, 0)
end)
"""

const DIALOGUE := """local npc = script.Parent
npc.ProximityPrompt.Triggered:Connect(function(player)
    local gui = Instance.new('ScreenGui')
    gui.Name = 'NpcDialogue'
    gui.Parent = player:WaitForChild('PlayerGui')
    local text = Instance.new('TextLabel')
    text.Size = UDim2.new(0.7, 0, 0, 90)
    text.Position = UDim2.new(0.15, 0, 0.7, 0)
    text.BackgroundColor3 = Color3.new(0.08, 0.12, 0.18)
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextSize = 22
    text.TextWrapped = true
    text.Text = npc:GetAttribute('DialogueText') or 'Привет!'
    text.Parent = gui
    game:GetService('Debris'):AddItem(gui, 4)
end)
"""

static func _append_namespaced(actions: Array, addition: Array, prefix: String, parent: String) -> void:
	for raw in addition:
		var action: Dictionary = raw.duplicate(true)
		if action.has("id"): action.id = prefix + action.id
		for key in ["parent", "target"]:
			var ref := str(action.get(key, ""))
			if ref.begins_with("action:"): action[key] = "action:" + prefix + ref.substr(7)
		if action.get("parent") == "StarterPack": action.parent = parent
		actions.append(action)

static func spawner_plan(id: String, attrs: Dictionary) -> Array:
	var folder := "LootPool_%d_%d" % [Time.get_ticks_usec(), randi() % 10000]
	var actions: Array = [{"type": "create_instance", "id": "pool", "class": "Folder", "name": folder, "parent": "ServerStorage"}, {"type": "create_instance", "id": "templates", "class": "Folder", "name": folder + "Templates", "parent": "ServerStorage"}]
	if id != "item_spawner":
		_append_namespaced(actions, tool_plan("apple", _options("apple", {})), "loot1_", "action:pool")
		_append_namespaced(actions, tool_plan("sword", _options("sword", {})), "loot2_", "action:pool")
		_append_namespaced(actions, Gameplay.weapon_plan().actions, "loot3_", "action:pool")
		actions.append({"type": "create_instance", "id": "lucky", "class": "Tool", "name": "LuckyBlock", "parent": "StarterPack" if id == "lucky_block" else "action:templates", "properties": {"Attributes": {"PrefabId": "lucky_block"}}})
		actions.append({"type": "create_part", "id": "lucky_handle", "name": "Handle", "parent": "action:lucky", "size": [2, 2, 2], "color": "#FFD43B", "can_collide": false})
		actions.append(_script("action:lucky", "local tool = script.Parent\nlocal used = false\nlocal pool = game:GetService('ServerStorage'):WaitForChild('" + folder + "')\ntool.Activated:Connect(function()\n if used then return end\n local h = tool.Parent:FindFirstChildOfClass('Humanoid')\n if not h then return end\n used = true\n local choices = pool:GetChildren()\n local reward = choices[math.random(1, #choices)]:Clone()\n local player = game:GetService('Players'):GetPlayerFromCharacter(tool.Parent)\n if not player then used = false; return end\n reward.Parent = player:WaitForChild('Backpack')\n tool:Destroy()\nend)", false))
		if id == "lucky_block": return actions
	else:
		var item := str(attrs.get("Item", "sword"))
		if item not in ["sword", "hammer", "apple", "burger", "health_potion", "revolver"]: item = "sword"
		_append_namespaced(actions, plan(item).actions, "loot_", "action:pool")
	actions.append({"type": "create_model", "id": "spawner", "name": "LuckySpawner" if id == "lucky_spawner" else "ItemSpawner", "parts": [{"name": "Base", "shape": "Cylinder", "size": [6, 0.4, 6], "position": [0, 0.2, 0], "color": "#4A63A8"}, {"name": "Display", "size": [2, 2, 2], "position": [0, 2.2, 0], "color": "#FFD43B", "can_collide": false}]})
	actions.append({"type": "update_instance", "target": "action:spawner", "properties": {"Attributes": attrs}})
	actions.append(_prompt("action:spawner", "Взять лаки-блок" if id == "lucky_spawner" else "Получить предмет"))
	var source := "local spawner = script.Parent\nlocal template = " + ("game:GetService('ServerStorage'):WaitForChild('" + folder + "Templates'):WaitForChild('LuckyBlock')" if id == "lucky_spawner" else "game:GetService('ServerStorage'):WaitForChild('" + folder + "'):GetChildren()[1]") + "\nlocal last = {}\ngame:GetService('RunService').Heartbeat:Connect(function(dt)\n spawner.Display.CFrame = spawner.Display.CFrame * CFrame.Angles(0, dt, 0)\nend)\nspawner.ProximityPrompt.Triggered:Connect(function(player)\n local now = os.clock()\n if now - (last[player] or -100) < (spawner:GetAttribute('Cooldown') or 0.5) then return end\n local backpack = player:WaitForChild('Backpack')\n if #backpack:GetChildren() >= (spawner:GetAttribute('InventoryLimit') or 64) then return end\n last[player] = now\n local item = template:Clone()\n item.Parent = backpack\nend)"
	actions.append(_script("action:spawner", source))
	return actions

static func airplane_plan(attrs: Dictionary) -> Array:
	return [{"type": "create_model", "id": "plane", "name": "Airplane", "parts": [{"name": "Fuselage", "size": [2.5, 2, 12], "position": [0, 2, 0], "color": "#DFE7EE"}, {"name": "Wings", "size": [20, 0.3, 4], "position": [0, 2, 0], "color": "#4B78C7"}, {"name": "Tail", "size": [7, 0.3, 2], "position": [0, 2, -5], "color": "#4B78C7"}, {"name": "Fin", "size": [0.3, 3, 2], "position": [0, 3.3, -5], "color": "#4B78C7"}]}, {"type": "create_part", "id": "seat", "parent": "action:plane", "shape": "VehicleSeat", "name": "PilotSeat", "size": [1.5, 0.3, 1.5], "position": [0, 3, 2]}, {"type": "update_instance", "target": "action:seat", "properties": {"MaxSpeed": attrs.MaxSpeed, "Attributes": {"BobuxAircraft": true, "PrefabId": "airplane"}}}, _prompt("action:seat", "Пилотировать · WASD и стрелки"), _script("action:seat", "script.Parent.ProximityPrompt.Triggered:Connect(function(player)\n if player.Character then script.Parent:Sit(player.Character:WaitForChild('Humanoid')) end\nend)")]

const TEAMS := """local players = game:GetService('Players')
local teams = game:GetService('Teams')
local red = Instance.new('Team'); red.Name = 'Red'; red.TeamColor = BrickColor.new('Bright red'); red.Parent = teams
local blue = Instance.new('Team'); blue.Name = 'Blue'; blue.TeamColor = BrickColor.new('Bright blue'); blue.Parent = teams
local nextTeam = 0
local function assign(player)
    nextTeam = nextTeam + 1
    player.Team = nextTeam % 2 == 1 and red or blue
    player.Neutral = false
    local function spawn(character)
        local point = workspace:FindFirstChild(player.Team == red and 'RedTeamSpawn' or 'BlueTeamSpawn')
        if point then character:WaitForChild('HumanoidRootPart').CFrame = CFrame.new(point.Position + Vector3.new(0, 4, 0)) end
    end
    player.CharacterAdded:Connect(spawn)
    if player.Character then spawn(player.Character) end
end
for _, player in ipairs(players:GetPlayers()) do assign(player) end
players.PlayerAdded:Connect(assign)
"""
