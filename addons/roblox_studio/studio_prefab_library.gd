extends RefCounted

# The Toolbox and AI expand exactly the same editable, versioned plans.
# Parameters become ordinary Attributes/properties in Explorer, not hidden code.
const Gameplay = preload("res://addons/roblox_studio/studio_gameplay_library.gd")
const Recipes = preload("res://addons/roblox_studio/studio_script_recipes.gd")
const Assets = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
const Extras = preload("res://addons/roblox_studio/studio_extra_prefabs.gd")

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_item("pistol", "Пистолет · инвентарь", "Оружие", "Пули, урон, прицел. Damage, Cooldown, EquipOnSpawn."),
		_item("rpg", "RPG · инвентарь", "Оружие", "Ракеты и взрыв. Damage, Cooldown, EquipOnSpawn."),
		_item("pistol_pickup", "Пистолет · подобрать E", "Оружие", "Мировой предмет с ProximityPrompt. После подбора появляется в Backpack."),
		_item("rpg_pickup", "RPG · подобрать E", "Оружие", "Подбор ракетницы с клавиатуры или экранной кнопкой."),
		_item("pistol_dispenser", "Плита выдачи пистолета", "Взаимодействия", "E выдаёт копию Tool. Повторное нажатие не дублирует имеющийся предмет."),
		_item("rpg_dispenser", "Плита выдачи RPG", "Взаимодействия", "Шаблон в ServerStorage; скрипт клонирует его в Backpack."),
		_item("buff_coin", "Монета усиления · инвентарь", "Предметы", "Equipped усиливает персонажа; Unequipped восстанавливает параметры. Speed, JumpPower, FallSpeed."),
		_item("coin_pickup", "Монета усиления · подобрать E", "Предметы", "E подбирает, слот экипирует. Усиление действует только в руке."),
		_item("coin_dispenser", "Плита выдачи монеты", "Взаимодействия", "Повторно используемая плита с шаблоном монеты."),
		_item("zombie", "NPC · зомби", "NPC", "Humanoid, тело, здоровье над головой, преследование, урон. Health, WalkSpeed, Damage, DetectionRange."),
		_item("fast_zombie", "NPC · быстрый зомби", "NPC", "Более быстрый противник с меньшим здоровьем."),
		_item("target_dummy", "NPC · тренировочная мишень", "NPC", "Неподвижная модель с Humanoid и видимым здоровьем; принимает урон."),
		_item("car", "Машина · физика и E", "Транспорт", "VehicleSeat, четыре колеса с подвеской. E сесть, WASD ехать, Space выйти."),
		_item("points_button", "GUI · кнопка очков", "GUI", "Кнопка, leaderstats, надпись. PointsPerClick настраивает прибавку."),
		_item("health_gui", "GUI · здоровье", "GUI", "Надпись следит за Health персонажа, включая возрождение."),
		_item("timer_gui", "GUI · таймер", "GUI", "Показывает время с начала локальной сессии."),
		_item("sprint_button", "GUI · переключатель бега", "GUI", "Кнопка включает и выключает усиление скорости. Speed."),
		_item("door", "Дверь · переключение E", "Взаимодействия", "E открывает и закрывает проход, меняет коллизию и прозрачность."),
		_item("heal_pad", "Плита лечения", "Взаимодействия", "Касание восстанавливает Health до MaxHealth."),
		_item("damage_pad", "Опасная плита", "Взаимодействия", "Урон с отдельной задержкой для каждого Humanoid. Damage, Cooldown."),
		_item("jump_pad", "Пружинная плита", "Взаимодействия", "При касании подбрасывает HumanoidRootPart. LaunchSpeed."),
		_item("moving_platform", "Движущаяся платформа", "Механизмы", "Tween туда и обратно. Travel, Duration."),
		_item("rotating_platform", "Вращающаяся платформа", "Механизмы", "Вращение по Heartbeat. AngularSpeed в градусах/сек."),
		_item("multi_jump", "Персонаж · несколько прыжков", "Персонаж", "Число прыжков Jumps до приземления."),
		_item("hold_to_fly", "Персонаж · полёт при удержании", "Персонаж", "Space удерживать для подъёма, отпустить для падения."),
		_item("city", "Город · кварталы из библиотеки", "Карты", "Настоящие модели зданий, деревья, дороги. Blocks, BuildingSize, Spacing."),
	]
	result.append_array(Extras.entries())
	return result

static func _item(id: String, title: String, category: String, description: String) -> Dictionary:
	return {"id": id, "name": title, "category": category, "description": description}

static func parameters(id: String) -> Dictionary:
	if "pistol" in id or "rpg" in id: return {"Damage": 70 if "rpg" in id else 25, "Cooldown": 1 if "rpg" in id else 0.25, "EquipOnSpawn": false}
	if "coin" in id: return {"Speed": 30, "JumpPower": 70, "FallSpeed": 22, "EquipOnSpawn": false}
	if id in ["zombie", "fast_zombie", "target_dummy"]: return {"Health": 60 if id == "fast_zombie" else 100, "WalkSpeed": 22 if id == "fast_zombie" else 10, "Damage": 10, "DetectionRange": 80}
	match id:
		"car": return {"MaxSpeed": 65}
		"points_button": return {"PointsPerClick": 1}
		"sprint_button": return {"Speed": 30}
		"damage_pad": return {"Damage": 10, "Cooldown": 1}
		"jump_pad": return {"LaunchSpeed": 65}
		"moving_platform": return {"Travel": 10, "Duration": 3}
		"rotating_platform": return {"AngularSpeed": 45}
		"multi_jump": return {"Jumps": 3}
		"city": return {"Blocks": 4, "BuildingSize": 22, "Spacing": 34}
	return Extras.parameters(id)

static func _script(parent: String, source: String, local_: bool = false, name_: String = "Controller") -> Dictionary:
	return {"type": "create_script", "name": name_, "parent": parent, "script_type": "LocalScript" if local_ else "Script", "source": source}

static func _prompt(parent: String, text_: String) -> Dictionary:
	return {"type": "create_instance", "class": "ProximityPrompt", "name": "ProximityPrompt", "parent": parent, "properties": {"ActionText": text_, "MaxActivationDistance": 10, "Enabled": true}}

static func _number(options: Dictionary, key: String, default_: float, minimum: float, maximum: float) -> float:
	var value: Variant = options.get(key, default_)
	if not (value is float or value is int) or not is_finite(float(value)): return default_
	return clampf(float(value), minimum, maximum)

static func plan(id: String, options: Dictionary = {}) -> Dictionary:
	var actions: Array = []
	var root_id := "prefab"
	if id in ["pistol", "rpg", "pistol_pickup", "rpg_pickup", "pistol_dispenser", "rpg_dispenser", "buff_coin", "coin_pickup", "coin_dispenser"]:
		var coin := "coin" in id
		var rocket := "rpg" in id
		if coin:
			actions = Recipes.buff_coin_plan().actions
			actions[0].parent = "StarterPack"
			actions.remove_at(2) # This controller uses Equipped, independent of pickup.
			actions[-1].source = BUFF
			actions[-1].script_type = "LocalScript"
			actions[1].position = [0, 0, 0]
			root_id = "buff_coin"
		else:
			actions = Gameplay.weapon_plan(rocket).actions
			root_id = "weapon"
		var attrs := {"PrefabId": id, "EquipOnSpawn": bool(options.get("EquipOnSpawn", false)), "Damage": _number(options, "Damage", 70 if rocket else 25, 0, 10000), "Cooldown": _number(options, "Cooldown", 1 if rocket else 0.25, 0.05, 60), "Speed": _number(options, "Speed", 30, 0, 200), "JumpPower": _number(options, "JumpPower", 70, 0, 300), "FallSpeed": _number(options, "FallSpeed", 22, 1, 300)}
		actions[0].properties["Attributes"] = attrs
		if id.ends_with("_pickup"):
			actions[0].parent = "Workspace"
			actions.insert(1, {"type": "modify_object", "target": "action:" + root_id, "position": [0, 3, 0]})
			actions.append(_prompt("action:" + root_id, "Подобрать"))
			actions.append(_script("action:" + root_id, PICKUP, false, "PickupController"))
		elif id.ends_with("_dispenser"):
			actions[0].parent = "ServerStorage"
			# Reference the actual child rather than a global name: multiple dispensers coexist.
			var storage_name := "ItemTemplates_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
			actions.insert(0, {"type": "create_instance", "id": "storage", "class": "Folder", "name": storage_name, "parent": "ServerStorage"})
			actions[1].parent = "action:storage"
			actions.append({"type": "create_part", "id": "pad", "name": "ItemDispenser", "size": [6, 0.5, 6], "color": "#4388F4"})
			actions.append(_prompt("action:pad", "Получить " + str(actions[1].name)))
			# Parent-relative template is saved with the pad; it remains inert outside Backpack.
			actions.append({"type": "create_instance", "id": "link", "class": "StringValue", "name": "TemplateName", "parent": "action:pad", "properties": {"Value": str(actions[1].name)}})
			actions.append(_script("action:pad", DISPENSER.replace("__STORAGE__", storage_name)))
	elif id in ["zombie", "fast_zombie", "target_dummy"]:
		actions = Gameplay.npc_plan().actions
		root_id = "npc"
		actions[0].name = "TargetDummy" if id == "target_dummy" else ("FastZombie" if id == "fast_zombie" else "Zombie")
		var health := _number(options, "Health", 60 if id == "fast_zombie" else 100, 1, 100000)
		actions[1].properties = {"MaxHealth": health, "Health": health, "WalkSpeed": _number(options, "WalkSpeed", 22 if id == "fast_zombie" else 10, 0, 100)}
		actions.append({"type": "update_instance", "target": "action:npc", "properties": {"Attributes": {"PrefabId": id, "Damage": _number(options, "Damage", 10, 0, 10000), "DetectionRange": _number(options, "DetectionRange", 80, 1, 1000)}}})
		if id == "target_dummy": actions[2].source = "script.Parent.Humanoid:TakeDamage(0)"
	elif id == "car":
		actions = car_plan(options)
	elif id == "points_button":
		actions = Recipes.points_button_plan().actions
		actions[1].properties["Attributes"] = {"PrefabId": id, "PointsPerClick": _number(options, "PointsPerClick", 1, -10000, 10000)}
		actions[2].source = Recipes.POINT_BUTTON.replace("points.Value + 1", "points.Value + (button:GetAttribute('PointsPerClick') or 1)").replace('"  (+1)"', '""')
	elif id in ["health_gui", "timer_gui", "sprint_button"]:
		actions = gui_plan(id, options)
	elif id == "multi_jump":
		actions = [{"type": "create_script", "name": "MultiJump", "parent": "StarterCharacterScripts", "script_type": "LocalScript", "source": Recipes.DOUBLE_JUMP.replace("local maxJumps = 2", "local maxJumps = %d" % int(_number(options, "Jumps", 3, 1, 20)))}]
	elif id == "hold_to_fly":
		actions = [_script("StarterCharacterScripts", Recipes.HOLD_TO_FLY, true, "HoldToFly")]
	elif id == "city":
		actions = city_plan(options)
	elif PART_SOURCES.has(id):
		actions = [{"type": "create_part", "id": "part", "name": id.to_pascal_case(), "size": [4, 8, 0.5] if id == "door" else [6, 0.5, 6], "position": [0, 4, 0] if id == "door" else [0, 0.5, 0], "color": "#D65757" if id == "damage_pad" else "#4388F4"}]
		actions.append({"type": "update_instance", "target": "action:part", "properties": {"Attributes": {"PrefabId": id, "Damage": _number(options, "Damage", 10, 0, 10000), "Cooldown": _number(options, "Cooldown", 1, 0.05, 60), "LaunchSpeed": _number(options, "LaunchSpeed", 65, 1, 300), "Travel": _number(options, "Travel", 10, 0.1, 200), "Duration": _number(options, "Duration", 3, 0.1, 120), "AngularSpeed": _number(options, "AngularSpeed", 45, -360, 360)}}})
		if id == "door": actions.append(_prompt("action:part", "Открыть / закрыть"))
		actions.append(_script("action:part", PART_SOURCES[id]))
	else:
		return Extras.plan(id, options)
	return {"ok": true, "message": "Добавлена настраиваемая заготовка: %s. Скрипты доступны у объектов в Explorer; запуск — Play." % id, "actions": actions}

const PICKUP := """local tool = script.Parent
local prompt = tool:WaitForChild("ProximityPrompt")
prompt.Triggered:Connect(function(player)
    if not prompt.Enabled then return end
    prompt.Enabled = false
    tool.Parent = player:WaitForChild("Backpack")
end)
"""

const DISPENSER := """local pad = script.Parent
local name = pad.TemplateName.Value
local template = game:GetService("ServerStorage"):WaitForChild("__STORAGE__"):WaitForChild(name)
assert(template, "Dispenser Tool template missing")
pad.ProximityPrompt.Triggered:Connect(function(player)
    local backpack = player:WaitForChild("Backpack")
    local character = player.Character
    if backpack:FindFirstChild(name) or (character and character:FindFirstChild(name)) then return end
    local copy = template:Clone()
    copy.Parent = backpack
end)
"""

const BUFF := """local tool = script.Parent
local active, speed, jump, usePower
tool.Equipped:Connect(function()
    if active then return end
    active = tool.Parent:FindFirstChildOfClass("Humanoid")
    if not active then return end
    speed, jump, usePower = active.WalkSpeed, active.JumpPower, active.UseJumpPower
    active.WalkSpeed = tool:GetAttribute("Speed") or 30
    active.UseJumpPower = true
    active.JumpPower = tool:GetAttribute("JumpPower") or 70
end)
local function restore()
    if active then active.WalkSpeed = speed; active.JumpPower = jump; active.UseJumpPower = usePower end
    active = nil
end
tool.Unequipped:Connect(restore)
tool.Destroying:Connect(restore)
game:GetService("RunService").Heartbeat:Connect(function()
    if not active or active.Health <= 0 then return end
    local root = active.Parent:FindFirstChild("HumanoidRootPart")
    if root then
        local velocity = root.AssemblyLinearVelocity
        local limit = tool:GetAttribute("FallSpeed") or 22
        if velocity.Y < -limit then root.AssemblyLinearVelocity = Vector3.new(velocity.X, -limit, velocity.Z) end
    end
end)
if tool:GetAttribute("EquipOnSpawn") then
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    character:WaitForChild("Humanoid"):EquipTool(tool)
end
"""

const PART_SOURCES := {
	"door": "local part = script.Parent\nlocal open = false\npart.ProximityPrompt.Triggered:Connect(function()\n open = not open\n part.CanCollide = not open\n part.Transparency = open and 0.75 or 0\nend)",
	"heal_pad": "script.Parent.Touched:Connect(function(hit)\n local h = hit.Parent and hit.Parent:FindFirstChildOfClass('Humanoid')\n if h then h.Health = h.MaxHealth end\nend)",
	"damage_pad": "local part = script.Parent\nlocal last = {}\npart.Touched:Connect(function(hit)\n local h = hit.Parent and hit.Parent:FindFirstChildOfClass('Humanoid')\n if not h or os.clock() - (last[h] or -100) < (part:GetAttribute('Cooldown') or 1) then return end\n last[h] = os.clock()\n h:TakeDamage(part:GetAttribute('Damage') or 10)\nend)",
	"jump_pad": "local part = script.Parent\npart.Touched:Connect(function(hit)\n local c = hit.Parent\n if not c or not c:FindFirstChildOfClass('Humanoid') then return end\n local root = c:FindFirstChild('HumanoidRootPart')\n if root then\n local v = root.AssemblyLinearVelocity\n root.AssemblyLinearVelocity = Vector3.new(v.X, part:GetAttribute('LaunchSpeed') or 65, v.Z)\n end\nend)",
	"moving_platform": "local part = script.Parent\nlocal info = TweenInfo.new(part:GetAttribute('Duration') or 3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)\ngame:GetService('TweenService'):Create(part, info, {Position = part.Position + Vector3.new(0, part:GetAttribute('Travel') or 10, 0)}):Play()",
	"rotating_platform": "local part = script.Parent\ngame:GetService('RunService').Heartbeat:Connect(function(dt)\n part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(part:GetAttribute('AngularSpeed') or 45) * dt, 0)\nend)",
}

static func gui_plan(id: String, options: Dictionary) -> Array:
	var is_button := id == "sprint_button"
	var source := "local label = script.Parent\nlocal player = game:GetService('Players').LocalPlayer\ngame:GetService('RunService').Heartbeat:Connect(function()\n local c = player.Character\n local h = c and c:FindFirstChildOfClass('Humanoid')\n if h then label.Text = 'HP: ' .. tostring(math.floor(h.Health)) .. ' / ' .. tostring(h.MaxHealth) end\nend)"
	if id == "timer_gui": source = "local label = script.Parent\nlocal start = os.clock()\nwhile true do\n local seconds = math.floor(os.clock() - start)\n label.Text = string.format('%02d:%02d', math.floor(seconds / 60), seconds % 60)\n task.wait(0.2)\nend)".trim_suffix(")")
	if is_button: source = "local button = script.Parent\nlocal player = game:GetService('Players').LocalPlayer\nlocal active, previous\nbutton.Activated:Connect(function()\n local c = player.Character\n local h = c and c:FindFirstChildOfClass('Humanoid')\n if not h then return end\n if active == h then h.WalkSpeed = previous; active = nil\n else previous = h.WalkSpeed; active = h; h.WalkSpeed = button:GetAttribute('Speed') or 30 end\n button.Text = active and 'Бег: ВКЛ' or 'Бег: ВЫКЛ'\nend)"
	return [{"type": "create_instance", "id": "gui", "class": "ScreenGui", "name": id.to_pascal_case(), "parent": "StarterGui"}, {"type": "create_instance", "id": "label", "class": "TextButton" if is_button else "TextLabel", "name": "Display", "parent": "action:gui", "properties": {"Text": "Бег: ВЫКЛ" if is_button else "…", "TextSize": 22, "TextColor3": [1, 1, 1], "BackgroundColor3": [0.08, 0.13, 0.23], "BorderSizePixel": 0, "Size": {"x": {"scale": 0, "offset": 220}, "y": {"scale": 0, "offset": 48}}, "Position": {"x": {"scale": 0, "offset": 20}, "y": {"scale": 0, "offset": 80}}, "Attributes": {"PrefabId": id, "Speed": _number(options, "Speed", 30, 0, 200)}}}, _script("action:label", source, true)]

static func car_plan(options: Dictionary) -> Array:
	var actions: Array = [{"type": "create_model", "id": "car", "name": "Car", "parts": [{"name": "Chassis", "size": [5, 1.1, 8], "position": [0, 1.4, 0], "color": "#336CD4"}]}, {"type": "create_part", "id": "seat", "parent": "action:car", "name": "VehicleSeat", "shape": "VehicleSeat", "size": [1.8, 0.4, 1.8], "position": [0, 2.1, 0]}, {"type": "update_instance", "target": "action:seat", "properties": {"MaxSpeed": _number(options, "MaxSpeed", 65, 1, 150), "Attributes": {"BobuxVehicle": true, "PrefabId": "car"}}}, _prompt("action:seat", "Сесть · WASD, Space — выйти"), _script("action:seat", "local seat = script.Parent\nseat.ProximityPrompt.Triggered:Connect(function(player)\n local c = player.Character\n if c then seat:Sit(c:WaitForChild('Humanoid')) end\nend)")]
	var cars := Assets.search_assets("sedan", "model", "", 1)
	if not cars.is_empty():
		var dimensions: Array = cars[0].get("bounds", {}).get("size", [1, 1, 1])
		var factor := 8.0 / maxf(float(dimensions[2]) * float(cars[0].get("units_to_studs", 3)), 0.1)
		actions[0].parts[0]["transparency"] = 1
		actions.append({"type": "spawn_asset", "asset_id": cars[0].id, "parent": "action:car", "scale": [factor, factor, factor]})
	return actions

static func city_plan(options: Dictionary) -> Array:
	var buildings := Assets.search_assets("building", "model", "", 60).filter(func(entry): return entry.get("role") == "building")
	if buildings.is_empty(): return []
	var count := int(_number(options, "Blocks", 4, 1, 5))
	var size_ := _number(options, "BuildingSize", 22, 8, 40)
	var spacing := maxf(_number(options, "Spacing", 34, 16, 80), size_ + 12)
	var actions: Array = [{"type": "create_model", "id": "city", "name": "City", "parts": [{"name": "Ground", "size": [spacing * (count + 1), 1, spacing * (count + 1)], "position": [0, -0.5, 0], "color": "#7C9B6A"}]}]
	var road_parts: Array = []
	for line in range(count + 1):
		var offset := (line - count * 0.5) * spacing
		road_parts.append({"name": "Road", "size": [8, 0.1, spacing * count + 8], "position": [offset, 0.06, 0], "color": "#424951"})
		road_parts.append({"name": "Road", "size": [spacing * count + 8, 0.1, 8], "position": [0, 0.06, offset], "color": "#424951"})
	var trees := Assets.search_assets("tree", "model", "", 8).filter(func(entry): return entry.get("role") != "component")
	for x in range(count):
		for z in range(count):
			var building: Dictionary = buildings[(x * count + z) % buildings.size()]
			var bounds_: Array = building.bounds.size
			var factor := size_ / maxf(maxf(float(bounds_[0]), float(bounds_[2])) * float(building.get("units_to_studs", 3)), 0.1)
			var position_ := [(x - (count - 1) * 0.5) * spacing, 0, (z - (count - 1) * 0.5) * spacing]
			actions.append({"type": "spawn_asset", "asset_id": building.id, "parent": "action:city", "scale": [factor, factor, factor], "position": position_, "rotation": [0, 180 if z % 2 else 0, 0]})
	if not trees.is_empty():
		for side in [-1, 1]:
			var tree: Dictionary = trees[0]
			var factor := 12.0 / maxf(float(tree.bounds.size[1]) * float(tree.get("units_to_studs", 3)), 0.1)
			actions.append({"type": "spawn_asset", "asset_id": tree.id, "parent": "action:city", "scale": [factor, factor, factor], "position": [side * spacing * (count + 0.6) / 2, 0, 0]})
		actions.append({"type": "create_model", "id": "roads", "name": "Roads", "parent": "action:city", "parts": road_parts})
	return actions
