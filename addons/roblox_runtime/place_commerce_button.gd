extends Node
## Authored Toolbox commerce buttons use the platform wallet, never a Lua balance.
var target: Button
var view: Button
var kind := ""
var owned := false
var _busy := false
var _elapsed := 0.0
var _map_id := ""
var _preview := false
var _popup: CanvasLayer

func _ready() -> void:
	kind = str(target.get_meta("attribute_PrefabId", ""))
	view.icon = load("res://assets/ui/daily_gift.svg" if kind == "daily_boblox" else "res://assets/ui/pass_shop.svg")
	view.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.expand_icon = false
	view.tooltip_text = "Ежедневная награда · 10 Boblox" if kind == "daily_boblox" else "Магазин · монета усиления"
	_preview = ImportedPlaceNetwork.role(target).is_empty()
	_map_id = GameState.get_selected_map_identifier()
	view.pressed.connect(_open)
	if not _preview: _load_status()

func _load_status() -> void:
	var result: Dictionary = await CloudAPI.place_commerce("status", _map_id)
	if not is_instance_valid(target): return
	if bool(result.get("ok", false)):
		owned = bool(result.get("owned", false))
		if kind == "gamepass_coin" and owned:
			view.tooltip_text = "Монета усиления уже в инвентаре"
			_grant_coin()

func _open() -> void:
	if _busy or not is_instance_valid(target): return
	if is_instance_valid(_popup): _popup.queue_free()
	_popup = preload("res://scripts/ui/place_reward_dialog.gd").new()
	view.add_child(_popup)
	_popup.confirmed.connect(_claim)
	if _preview:
		_popup.configure(kind, {}, true)
	else:
		_popup.configure(kind, {})
		_popup.busy()
		_busy = true
		var status: Dictionary = await CloudAPI.place_commerce("status", _map_id)
		_busy = false
		if not is_instance_valid(_popup): return
		if not bool(status.get("ok", false)):
			_popup.failure(str(status.get("error", "Сервер недоступен. Попробуйте ещё раз.")))
			_popup.confirmed.disconnect(_claim)
			_popup.confirmed.connect(_open)
		else:
			owned = bool(status.get("owned", false))
			_popup.configure(kind, status)

func _claim() -> void:
	if _busy: return
	_busy = true
	if is_instance_valid(_popup): _popup.busy()
	var result := {"ok":true,"owned":true}
	if not _preview:
		result = await CloudAPI.place_commerce("daily" if kind == "daily_boblox" else "purchase", _map_id, _popup.price)
	_busy = false
	if not is_instance_valid(target): return
	if bool(result.get("ok", false)):
		if kind == "gamepass_coin":
			owned = true
			_grant_coin()
			view.tooltip_text = "Монета усиления уже в инвентаре"
		if is_instance_valid(_popup): _popup.complete("Монета добавлена в инвентарь. Выберите её, чтобы усилить персонажа." if kind == "gamepass_coin" else "Предпросмотр награды: 10 Boblox." if _preview else "На ваш счёт зачислено 10 Boblox. Возвращайтесь завтра!")
	else:
		if is_instance_valid(_popup): _popup.failure(str(result.get("error", "Не удалось получить награду. Повторите попытку.")))

func _process(delta: float) -> void:
	if not owned or kind != "gamepass_coin": return
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	_grant_coin()

func _grant_coin() -> void:
	if not is_instance_valid(target): return
	var workspace := ImportedPlaceNetwork.workspace_for(target)
	var services: Dictionary = LuaScriptEngine._ensure_roblox_service_nodes(get_tree().root, workspace)
	var player: Node = services.Players.get_node_or_null("LocalPlayer")
	if player == null: return
	var backpack: Node = player.get_node_or_null("Backpack")
	var character: Node = LuaScriptEngine._bound_character_for_player(player)
	var template: Node = services.ReplicatedStorage.get_node_or_null("GamepassBoostCoin")
	if backpack == null or template == null or not is_instance_valid(character): return
	if backpack.get_node_or_null("GamepassBoostCoin") != null or character.get_node_or_null("GamepassBoostCoin") != null: return
	var copy = LuaScriptEngine.BobuxInstance.wrap(template).Clone()
	copy._set("Parent", LuaScriptEngine.BobuxInstance.wrap(backpack))
