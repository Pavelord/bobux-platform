extends SceneTree

const Prefabs = preload("res://addons/roblox_studio/studio_prefab_library.gd")
const Planner = preload("res://addons/roblox_studio/studio_ai_planner.gd")
var errors: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[prefabs] %s=%s" % [label_, ok])
	if not ok: errors.append(label_)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	for entry in Prefabs.entries():
		var plan := Prefabs.plan(entry.id)
		check(plan.ok and not plan.actions.is_empty(), entry.id + " complete plan")
		var count: int = studio._apply_studio_ai_actions(plan.actions)
		check(count > 0 and studio.studio_ai_last_errors.is_empty(), entry.id + " applies and compiles " + str(studio.studio_ai_last_errors))
	check(Prefabs.entries().size() == 45, "45 editable templates")
	for request in ["сделай RPG в инвентарь", "создай пистолет с прицелом и уроном 40", "создай нпс", "сделай монетку с бустом чтобы подбирать по E", "создай плиту которая выдает рпг", "сделай машину на которой можно ездить", "сделай GUI кнопку добавляющую по 5 очков", "построй город"]:
		var plan := Planner.plan_for_request(request, studio._build_studio_ai_context(request))
		check(plan.get("ok", false) and plan.actions[0].type == "create_prefab", request)
	check(Planner.plan_for_request("сделай пистолет с магазином и перезарядкой", {}).is_empty(), "custom reload request retains provider planning")
	var expanded := Planner.expand_actions([{"type": "create_prefab", "prefab_id": "pistol"}, {"type": "create_prefab", "prefab_id": "rpg"}])
	var ids := {}
	for action in expanded.actions:
		if action.has("id"):
			check(not ids.has(action.id), "independent prefab aliases " + action.id)
			ids[action.id] = true
	check(not Planner.expand_actions([{"type": "create_prefab", "prefab_id": "unknown"}]).ok, "unknown prefab rejected")
	studio._apply_studio_ai_actions(Planner.plan_for_request("сделай небо #CC4477", {}).actions)
	check(studio.current_roblox_environment_settings.custom_sky_color, "sky override persisted")
	check(studio.current_roblox_environment_settings.background_color == [0.8, 68.0 / 255, 119.0 / 255] or Color(studio.current_roblox_environment_settings.background_color[0], studio.current_roblox_environment_settings.background_color[1], studio.current_roblox_environment_settings.background_color[2]).is_equal_approx(Color("#CC4477")), "requested sky RGB")
	studio._apply_studio_ai_actions(Planner.plan_for_request("настройки игрока скорость 27 прыжок 19", {}).actions)
	check(studio._get_current_player_settings().move_speed == 27 and studio._get_current_player_settings().jump_velocity == 19, "settings survive closed panel")
	var car: Node3D = studio.placement_parent.get_node("Car")
	studio.explorer_selected_node = car
	studio._scale_selection_uniformly(2)
	check(car.scale.is_equal_approx(Vector3.ONE * 2), "whole model scale")
	check(car.get_node("VehicleSeat").get_meta("roblox_class") == "VehicleSeat", "real VehicleSeat class")
	var engine := root.get_node("LuaScriptEngine")
	var pistol: Node = studio.data_model.ensure_service("StarterPack").get_node("Pistol")
	check(engine.BobuxInstance.new(pistol).GetAttribute("Damage") == 25, "template options become attributes")
	var manifest: Dictionary = studio.data_model.build_manifest()
	var persisted := false
	for item in manifest.tools:
		if item.name == "Pistol" and item.properties.get("Attributes", {}).get("Damage") == 25: persisted = true
	check(persisted, "configurable attributes included in saved manifest")
	studio.queue_free()
	await process_frame
	await process_frame
	print("[prefabs] errors=%s" % [errors])
	quit(0 if errors.is_empty() else 1)
