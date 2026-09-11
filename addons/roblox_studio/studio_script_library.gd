extends RefCounted

const Recipes = preload("res://addons/roblox_studio/studio_script_recipes.gd")
const Gameplay = preload("res://addons/roblox_studio/studio_gameplay_library.gd")

static func entries() -> Array[Dictionary]:
	return [
		_entry("Персонаж · Двойной прыжок", "StarterPlayer > StarterCharacterScripts > LocalScript", "Считает запросы прыжка и сбрасывает счётчик при приземлении.", Recipes.plan_for_request("двойной прыжок", {})),
		_entry("Персонаж · Тройной прыжок", "StarterPlayer > StarterCharacterScripts > LocalScript", "maxJumps задаёт число прыжков до приземления. Меняйте существующий контроллер, чтобы не складывать обработчики.", Recipes.plan_for_request("тройной прыжок", {})),
		_entry("Персонаж · Полёт при удержании Space", "StarterPlayer > StarterCharacterScripts > LocalScript", "InputBegan/InputEnded управляют удержанием; Heartbeat меняет скорость HumanoidRootPart.", Recipes.plan_for_request("летать при удержании Space", {})),
		_entry("Инвентарь · Монета с баффами", "Workspace > BuffCoin (Tool) > BuffCoinController (Script)", "Нажмите монету, затем выберите слот. Equipped усиливает скорость и прыжок, ограничивает скорость падения; Unequipped возвращает параметры. Humanoid находится у персонажа, который держит Tool.", Recipes.buff_coin_plan()),
		_entry("Инвентарь · Монета сразу в руке", "StarterPack > BuffCoin (Tool) > Script", "StarterPack хранит шаблон. При Play копия попадает в Backpack и Humanoid:EquipTool берёт её в руку.", Recipes.plan_for_request("монетка с баффами сразу в руках", {})),
		_entry("Оружие · Пистолет с прицелом", "StarterPack > Pistol > WeaponController (LocalScript)", "Прицел следует мыши. Raycast проверяет путь видимой пули, TakeDamage меняет здоровье Humanoid. Локальный пример; сетевой урон требует серверной проверки.", Gameplay.weapon_plan()),
		_entry("Оружие · РПГ", "StarterPack > RPG > WeaponController (LocalScript)", "Ракета вызывает Explosion. Чтобы деталь постройки могла разлетаться, установите ей атрибут Destructible=true. Статичные детали без атрибута сохраняют Anchored.", Gameplay.weapon_plan(true)),
		_entry("NPC · Зомби", "Workspace > Zombie (Model) > Chase (Script)", "Модель содержит Humanoid и HumanoidRootPart. Контроллер выбирает ближайшего игрока, идёт через MoveTo и атакует вблизи. Обход препятствий этим примером не реализован.", Gameplay.npc_plan()),
		_entry("GUI · Кнопка и очки", "StarterGui > ScoreGui > AddPoint > LocalScript", "Activated увеличивает IntValue в leaderstats и меняет надпись. Очки существуют в локальной сессии и отображаются в Tab.", Recipes.points_button_plan()),
		_part("События · Счётчик кликов", "ClickDetector передаёт Player. Атрибут Clicks хранит число нажатий.", "local part = script.Parent\nlocal detector = part:WaitForChild('ClickDetector')\npart:SetAttribute('Clicks', 0)\ndetector.MouseClick:Connect(function(player)\n    part:SetAttribute('Clicks', part:GetAttribute('Clicks') + 1)\n    print(player.Name, part:GetAttribute('Clicks'))\nend)", true),
		_part("События · Переключение двери", "Клик переключает столкновение и прозрачность детали.", "local door = script.Parent\nlocal open = false\ndoor.ClickDetector.MouseClick:Connect(function()\n    open = not open\n    door.CanCollide = not open\n    door.Transparency = open and 0.7 or 0\nend)", true),
		_part("События · Лечение при касании", "Touched получает деталь персонажа. Health изменяется у найденного Humanoid.", "script.Parent.Touched:Connect(function(hit)\n    local character = hit.Parent\n    local humanoid = character and character:FindFirstChildOfClass('Humanoid')\n    if humanoid then humanoid.Health = humanoid.MaxHealth end\nend)"),
		_part("События · Опасный блок с задержкой", "Флаг debounce исключает многократный урон в одном касании.", "local busy = false\nscript.Parent.Touched:Connect(function(hit)\n    if busy then return end\n    local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass('Humanoid')\n    if not humanoid then return end\n    busy = true\n    humanoid:TakeDamage(10)\n    task.wait(1)\n    busy = false\nend)"),
		_part("Движение · Вращение", "Heartbeat передаёт длительность кадра. CFrame.Angles задаёт угол в радианах.", "local part = script.Parent\ngame:GetService('RunService').Heartbeat:Connect(function(dt)\n    part.CFrame = part.CFrame * CFrame.Angles(0, dt, 0)\nend)"),
		_part("Движение · Tween платформы", "TweenService плавно изменяет Position; повторение -1 и Reverses=true двигают платформу туда и обратно.", "local part = script.Parent\nlocal info = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)\nlocal tween = game:GetService('TweenService'):Create(part, info, {Position = part.Position + Vector3.new(0, 5, 0)})\ntween:Play()"),
		_part("Планировщик · Мигающий блок", "task.wait приостанавливает только этот скрипт. Цикл останавливается вместе с Play.", "local part = script.Parent\nwhile true do\n    part.Transparency = 0.7\n    task.wait(0.5)\n    part.Transparency = 0\n    task.wait(0.5)\nend"),
	]

static func _entry(title: String, location: String, description: String, plan: Dictionary) -> Dictionary:
	var sources: Array[String] = []
	for action in plan.get("actions", []):
		if action.get("type") == "create_script": sources.append(str(action.get("source", "")))
	return {"title": title, "location": location, "description": description, "source": "\n\n".join(sources), "plan": plan}

static func _part(title: String, description: String, source: String, detector: bool = false) -> Dictionary:
	var actions: Array = [{"type": "create_part", "id": "example", "name": "ExamplePart", "size": [6, 1, 6], "anchored": true, "color": "#448AD4"}]
	if detector: actions.append({"type": "create_instance", "class": "ClickDetector", "parent": "action:example", "name": "ClickDetector"})
	actions.append({"type": "create_script", "name": "Controller", "parent": "action:example", "script_type": "Script", "source": source})
	return _entry(title, "Workspace > ExamplePart > Controller (Script)", description, {"actions": actions})

static func open(owner: Node, insert_example: Callable = Callable()) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = "Learn · Библиотека Lua"
	dialog.size = Vector2i(960, 650)
	dialog.min_size = Vector2i(500, 400)
	owner.add_child(dialog)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(layout)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск: Tool, GUI, прыжок, события…"
	layout.add_child(search)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	var list := ItemList.new()
	list.custom_minimum_size.x = 275
	split.add_child(list)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(details)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(help)
	var code := CodeEdit.new()
	code.editable = false
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(code)
	var buttons := HBoxContainer.new()
	details.add_child(buttons)
	var copy := Button.new()
	copy.text = "Копировать Lua"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(code.text))
	buttons.add_child(copy)
	var insert := Button.new()
	insert.text = "Добавить пример в Studio"
	insert.visible = insert_example.is_valid()
	buttons.add_child(insert)
	var items := entries()
	var select := func(index: int):
		var entry: Dictionary = items[int(list.get_item_metadata(index))]
		help.text = entry.location + "\n\n" + entry.description + "\n\nSave сохраняет код. Play запускает его; ошибки отображаются в Output."
		code.text = entry.source
	list.item_selected.connect(select)
	var filter := func(query: String):
		list.clear()
		for index in range(items.size()):
			var entry: Dictionary = items[index]
			if query.is_empty() or (entry.title + " " + entry.location + " " + entry.description).to_lower().contains(query.to_lower()):
				list.add_item(entry.title)
				list.set_item_metadata(list.item_count - 1, index)
		insert.disabled = list.item_count == 0
		if list.item_count > 0:
			list.select(0)
			select.call(0)
	search.text_changed.connect(filter)
	insert.pressed.connect(func():
		if list.get_selected_items().is_empty(): return
		var entry: Dictionary = items[int(list.get_item_metadata(list.get_selected_items()[0]))]
		insert_example.call(entry.plan.actions.duplicate(true))
	)
	filter.call("")
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.85)
	return dialog
