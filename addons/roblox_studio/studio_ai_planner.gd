extends RefCounted

const Prefabs = preload("res://addons/roblox_studio/studio_prefab_library.gd")
const Recipes = preload("res://addons/roblox_studio/studio_script_recipes.gd")
const Assets = preload("res://addons/roblox_studio/studio_asset_planner.gd")

static func _matches(text_: String, pattern: String) -> bool:
	var regex := RegEx.new()
	regex.compile("(?i)" + pattern)
	return regex.search(text_) != null

static func plan_for_request(prompt: String, context: Dictionary) -> Dictionary:
	var text_ := prompt.to_lower()
	var settings := _settings_plan(text_)
	if not settings.is_empty(): return settings
	var editing := _matches(text_, "исправ|почин|передел|измени|изменить|редакт|настрой|увелич|уменьш|fix|repair|edit|update|change")
	var id := ""
	if _matches(text_, "лаки|lucky"): id = "lucky_spawner" if _matches(text_, "спавн|spawner") else "lucky_block"
	elif _matches(text_, "спавнер|spawner") and not _matches(text_, "npc|нпс|зомби"): id = "item_spawner"
	elif _matches(text_, "ков[её]р|carpet"): id = "flying_carpet"
	elif _matches(text_, "самол[её]т|airplane|aircraft"): id = "airplane"
	elif _matches(text_, "револьвер|revolver"): id = "revolver"
	elif _matches(text_, "молот|hammer"): id = "hammer"
	elif _matches(text_, "меч|sword"): id = "sword"
	elif _matches(text_, "яблок|apple"): id = "apple"
	elif _matches(text_, "бургер|burger"): id = "burger"
	elif _matches(text_, "зель|potion"): id = "health_potion"
	elif _matches(text_, "команд|teams") and _matches(text_, "раздел|две|2|красн|син|team"): id = "teams"
	elif _matches(text_, "сидень|сидени|seat"): id = "seat"
	elif _matches(text_, "нпс|npc|охранник|горожанин|спутник|босс|патруль") and not _matches(text_, "зомби|zombie"):
		id = "npc_citizen"
		for pair in [["диалог|говор|dialogue", "npc_dialogue"], ["охран|guard", "npc_guard"], ["спутник|следова|follower", "npc_follower"], ["патрул|patrol", "npc_patrol"], ["босс|boss", "npc_boss"]]:
			if _matches(text_, pair[0]): id = pair[1]; break
	elif _matches(text_, "пистолет|pistol"): id = "pistol"
	elif _matches(text_, "рпг|\\brpg\\b|ракетниц|rocket launcher"): id = "rpg"
	elif _matches(text_, "монет|coin") and _matches(text_, "буст|бафф|скорост|прыж|buff|boost|speed"): id = "buff_coin"
	elif _matches(text_, "зомби|zombie|\\bnpc\\b|нпс"): id = "fast_zombie" if "быстр" in text_ else "zombie"
	elif _matches(text_, "мишен|манекен|dummy"): id = "target_dummy"
	elif _matches(text_, "машин|автомобил|\\bcar\\b") and not _matches(text_, "стиральн|игруш|washing"): id = "car"
	elif _matches(text_, "кнопк|button|gui") and _matches(text_, "очк|point"): id = "points_button"
	elif _matches(text_, "gui|интерфейс|экран") and _matches(text_, "здоров|\\bhp\\b|health"): id = "health_gui"
	elif _matches(text_, "gui|интерфейс|экран") and _matches(text_, "таймер|timer"): id = "timer_gui"
	elif _matches(text_, "кнопк|button") and _matches(text_, "бег|спринт|sprint"): id = "sprint_button"
	elif _matches(text_, "двер|door") and _matches(text_, "кноп|\\be\\b|откры|open|взаимод"): id = "door"
	elif _matches(text_, "плит|блок|pad") and _matches(text_, "леч|heal"): id = "heal_pad"
	elif _matches(text_, "плит|блок|pad") and _matches(text_, "урон|опасн|damage"): id = "damage_pad"
	elif _matches(text_, "плит|блок|pad") and _matches(text_, "подбрасы|пружин|launch"): id = "jump_pad"
	elif _matches(text_, "платформ|platform") and _matches(text_, "движ|moving"): id = "moving_platform"
	elif _matches(text_, "платформ|platform") and _matches(text_, "вращ|rotat"): id = "rotating_platform"
	elif _matches(text_, "город|\\bcity\\b") and not editing: id = "city"
	var options := _options(text_)
	if id in ["pistol", "rpg", "buff_coin"]:
		if _matches(text_, "плит|выдающ|выдает|выдаёт|dispenser"):
			id = "coin_dispenser" if id == "buff_coin" else id + "_dispenser"
		elif _matches(text_, "подобр|подним|подход|pickup|\\be\\b"):
			id = "coin_pickup" if id == "buff_coin" else id + "_pickup"
	# Additional behaviors require composition by the provider. Do not quietly
	# replace a requested quest, reload system, shop, or complex GUI with a sample.
	if _matches(text_, "квест|магазин|сохранен|анимац|quest|shop|persist|animation") or (id != "revolver" and _matches(text_, "перезаряд|патрон|reload|ammo")) or prompt.length() > 500:
		return {}
	if not id.is_empty():
		if editing:
			var target := _prefab_target(id, context)
			if not target.is_empty() and not options.is_empty():
				var actions: Array = [{"type": "update_instance", "target": target.ref, "properties": {"Attributes": options}}]
				if id in ["zombie", "fast_zombie", "target_dummy"] or id.begins_with("npc_"):
					for child in context.get("scene", []):
						if child.get("parent") == target.ref and child.get("class") == "Humanoid":
							var properties := {}
							if options.has("Health"): properties["MaxHealth"] = options.Health; properties["Health"] = options.Health
							if options.has("WalkSpeed"): properties["WalkSpeed"] = options.WalkSpeed
							if not properties.is_empty(): actions.append({"type": "update_instance", "target": child.ref, "properties": properties})
				return {"ok": true, "message": "Обновлены параметры существующей заготовки; её объекты и скрипты сохранены.", "actions": actions}
			return {}
		return {"ok": true, "message": "Использую готовую механику «%s» и параметры запроса. Объекты и Lua остаются редактируемыми." % id, "actions": [{"type": "create_prefab", "prefab_id": id, "options": options}]}
	var recipe := Recipes.plan_for_request(prompt, context)
	return recipe if not recipe.is_empty() else Assets.plan_for_request(prompt, context)

static func _prefab_target(id: String, context: Dictionary) -> Dictionary:
	var by_ref := {}
	var matches: Array = []
	for entry in context.get("scene", []):
		by_ref[str(entry.ref)] = entry
		if entry.get("attributes", {}).get("PrefabId", "") == id: matches.append(entry)
	var cursor := str(context.get("selected_ref", ""))
	var visited := {}
	while by_ref.has(cursor) and not visited.has(cursor):
		visited[cursor] = true
		var entry: Dictionary = by_ref[cursor]
		if entry in matches: return entry
		cursor = str(entry.get("parent", ""))
	return matches[0] if matches.size() == 1 else {}

static func _options(text_: String) -> Dictionary:
	var result := {}
	for spec in [["Range", "дистанци[яию]|range"], ["ReloadTime", "перезарядк[аиу]|reload"], ["HealAmount", "лечени[ея]|heal"], ["DetectionRange", "радиус обнаружения"], ["PatrolRadius", "радиус патруля"], ["InventoryLimit", "лимит|limit"], ["Damage", "урон(?:ом|а)?|damage"], ["Cooldown", "задержк(?:а|ой|у)|cooldown"], ["Health", "здоровь(?:е|ем|я)|health|hp"], ["Speed", "скорост(?:ь|ью|и)|speed"], ["JumpPower", "сил(?:а|ой) прыжка|jump.?power"], ["FallSpeed", "падени[ея]|fall.?speed"], ["PointsPerClick", "по|на|добавля(?:ет|ла)|прибавля(?:ет|ла)"], ["Blocks", "квартал(?:ов|а|ы)?|blocks"], ["BuildingSize", "размер(?:ом)? зданий|building.?size"]]:
		var regex := RegEx.new()
		regex.compile("(?:" + spec[1] + ")\\s*[:=]?\\s*(-?[0-9]+(?:[.,][0-9]+)?)")
		var found := regex.search(text_)
		if found != null: result[spec[0]] = float(found.get_string(1).replace(",", "."))
	for pair in [["молот|hammer", "hammer"], ["револьвер|revolver", "revolver"], ["яблок|apple", "apple"], ["бургер|burger", "burger"], ["зель|potion", "health_potion"]]:
		if _matches(text_, pair[0]): result["Item"] = pair[1]
	var dialogue := RegEx.new()
	dialogue.compile('[«"]([^»"]+)[»"]')
	var quoted := dialogue.search(text_)
	if quoted != null: result["DialogueText"] = quoted.get_string(1)
	if _matches(text_, "сразу в рук|изначально в рук|equipped"): result["EquipOnSpawn"] = true
	if result.has("Speed"):
		result["WalkSpeed"] = result.Speed
		result["MaxSpeed"] = result.Speed
	return result

static func _settings_plan(text_: String) -> Dictionary:
	var actions: Array = []
	if _matches(text_, "неб[оа]|sky|освещен|lighting") and not _matches(text_, "gui|кнопк|button|пистолет|npc|нпс"):
		var action := {"type": "set_environment"}
		var hex := RegEx.new()
		hex.compile("#[0-9a-f]{6}")
		var found := hex.search(text_)
		if found != null: action["sky_color"] = found.get_string()
		else:
			for color in [["красн|red", "#DD4545"], ["син|blue", "#307CDD"], ["розов|pink", "#F59DCC"], ["фиолет|purple", "#7954BE"], ["черн|чёрн|black", "#080A15"], ["оранж|orange", "#EE9D53"], ["зелён|зелен|green", "#68BA85"]]:
				if _matches(text_, color[0]): action["sky_color"] = color[1]; break
		if _matches(text_, "ноч|night"): action["clock_time"] = 0; action["brightness"] = 0.35
		elif _matches(text_, "закат|sunset"): action["clock_time"] = 18; action["brightness"] = 1
		if action.size() > 1: actions.append(action)
	if _matches(text_, "настройк|игрок|персонаж|player|character") and not _matches(text_, "пистолет|монет|npc|нпс|зомби"):
		var action := {"type": "set_player_settings"}
		for pair in [["move_speed", "скорост(?:ь|ью)|speed"], ["jump_velocity", "прыж(?:ок|ка)|jump"], ["sprint_multiplier", "спринт|sprint"]]:
			var regex := RegEx.new()
			regex.compile("(?:" + pair[1] + ")\\s*[:=]?\\s*([0-9]+(?:[.,][0-9]+)?)")
			var found := regex.search(text_)
			if found != null: action[pair[0]] = float(found.get_string(1).replace(",", "."))
		if action.size() > 1: actions.append(action)
	return {} if actions.is_empty() else {"ok": true, "message": "Изменены настройки карты; они сохраняются с картой и применяются в Play.", "actions": actions}

static func expand_actions(actions: Array) -> Dictionary:
	var expanded: Array = []
	var errors: Array[String] = []
	for index in range(actions.size()):
		var action: Variant = actions[index]
		if not action is Dictionary: errors.append("План содержит некорректное действие."); continue
		if action.get("type") != "create_prefab": expanded.append(action); continue
		var options: Variant = action.get("options", {})
		var prefab := Prefabs.plan(str(action.get("prefab_id", "")), options if options is Dictionary else {})
		if not prefab.get("ok", false): errors.append(prefab.error); continue
		var aliases := {}
		for item in prefab.actions:
			if item.has("id"): aliases[str(item.id)] = "p%d_%s" % [index, item.id]
		for item in prefab.actions:
			item = item.duplicate(true)
			if item.has("id"): item.id = aliases[str(item.id)]
			for key in ["parent", "target"]:
				var ref := str(item.get(key, ""))
				if ref.begins_with("action:") and aliases.has(ref.substr(7)): item[key] = "action:" + aliases[ref.substr(7)]
			expanded.append(item)
	if expanded.size() > 256: errors.append("План превышает 256 действий. Разбейте карту на несколько запросов.")
	return {"ok": errors.is_empty(), "actions": expanded if errors.is_empty() else [], "error": "\n".join(errors)}
