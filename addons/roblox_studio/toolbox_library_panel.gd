extends VBoxContainer

const Library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
signal asset_requested(asset_id: String)
signal prefab_requested(prefab_id: String)
signal legacy_requested
var items: ItemList
var _search: LineEdit
var _kind: OptionButton
var _category: OptionButton
var _info: Label
var _page_label: Label
var _previous: Button
var _next: Button
var _preview: Button
var _audio: AudioStreamPlayer
var _timer: Timer
var _offset := 0
var _page_generation := 0
const PAGE_SIZE := 24

static func library_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 13
	for type_ in ["Button", "OptionButton", "LineEdit", "Label", "ItemList", "TabContainer"]:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_selected_color"]:
			result.set_color(key, type_, Color("#263238"))
		result.set_color("font_unselected_color", type_, Color("#596579"))
		result.set_color("font_placeholder_color", type_, Color("#778397"))
		result.set_color("font_disabled_color", type_, Color("#929cac"))
	for type_ in ["Button", "OptionButton", "LineEdit", "ItemList"]:
		result.set_stylebox("normal" if type_ != "ItemList" else "panel", type_, _surface("#ffffff", "#d5dde8", 7))
		result.set_stylebox("focus", type_, _surface("#00000000", "#3985eb", 7))
		if type_ in ["Button", "OptionButton"]:
			result.set_stylebox("hover", type_, _surface("#edf4ff", "#b1cff4", 7))
			result.set_stylebox("pressed", type_, _surface("#dceaff", "#8db8ef", 7))
			result.set_stylebox("disabled", type_, _surface("#f2f4f7", "#e2e7ee", 7))
	result.set_stylebox("selected", "ItemList", _surface("#e6f0ff", "#b1cff4", 3))
	result.set_stylebox("selected_focus", "ItemList", _surface("#dceaff", "#8db8ef", 3))
	result.set_stylebox("panel", "TabContainer", _surface("#f5f7fa", "#d5dde8", 6))
	result.set_stylebox("tab_selected", "TabContainer", _surface("#ffffff", "#d5dde8", 9))
	result.set_stylebox("tab_unselected", "TabContainer", _surface("#edf0f5", "#d5dde8", 9))
	result.set_stylebox("tab_hovered", "TabContainer", _surface("#e6f0ff", "#b1cff4", 9))
	return result

static func _surface(fill: String, border: String, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск моделей и звуков…"
	add_child(_search)
	var filters := HBoxContainer.new()
	add_child(filters)
	_kind = OptionButton.new()
	_kind.add_item("Models")
	_kind.add_item("Sounds")
	_kind.add_item("Готовые механики")
	filters.add_child(_kind)
	_category = OptionButton.new()
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(_category)
	items = ItemList.new()
	items.name = "LibraryItems"
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.max_columns = 2
	items.fixed_column_width = 116
	items.fixed_icon_size = Vector2i(96, 96)
	items.icon_mode = ItemList.ICON_MODE_TOP
	items.max_text_lines = 2
	items.add_theme_font_size_override("font_size", 11)
	add_child(items)
	var pages := HBoxContainer.new()
	add_child(pages)
	_previous = Button.new()
	_previous.text = "‹"
	pages.add_child(_previous)
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	pages.add_child(_next)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 11)
	add_child(_info)
	var actions := HBoxContainer.new()
	add_child(actions)
	_preview = Button.new()
	_preview.text = "▶ / ■"
	_preview.tooltip_text = "Прослушать / остановить звук"
	actions.add_child(_preview)
	var insert := Button.new()
	insert.text = "Добавить"
	insert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(insert)
	var legacy := Button.new()
	legacy.text = "Примитивы и мои модели…"
	legacy.pressed.connect(func(): legacy_requested.emit())
	add_child(legacy)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.18
	add_child(_timer)
	_timer.timeout.connect(refresh)
	_search.text_changed.connect(func(_text): _offset = 0; _timer.start())
	_kind.item_selected.connect(func(_index): _offset = 0; _update_categories(); refresh())
	_category.item_selected.connect(func(_index): _offset = 0; refresh())
	_previous.pressed.connect(func(): _offset = maxi(0, _offset - PAGE_SIZE); refresh())
	_next.pressed.connect(func(): _offset += PAGE_SIZE; refresh())
	items.item_selected.connect(_select)
	items.item_activated.connect(_insert_item)
	insert.pressed.connect(func():
		if not items.get_selected_items().is_empty(): _insert_item(items.get_selected_items()[0])
	)
	_preview.pressed.connect(func():
		if _audio.playing: _audio.stop(); return
		if items.get_selected_items().is_empty(): return
		var asset_id := str(items.get_item_metadata(items.get_selected_items()[0]))
		if not await ToolboxAssetService.ensure_asset(asset_id):
			_info.text = ToolboxAssetService.last_error
			return
		var entry := Library.get_asset(asset_id)
		if entry.get("type") != "sound": return
		_audio.stream = Library.load_sound(entry.file)
		if _audio.stream != null: _audio.play()
	)
	visibility_changed.connect(func():
		if not is_visible_in_tree() and is_instance_valid(_audio): _audio.stop()
	)
	_update_categories()
	refresh()
	if DisplayServer.get_name() != "headless":
		_refresh_server_catalog.call_deferred()

func _refresh_server_catalog() -> void:
	var ok := await ToolboxAssetService.refresh_catalog()
	if not is_inside_tree(): return
	if ok:
		_update_categories()
		refresh()
	else:
		_info.text = "Сервер библиотеки недоступен. Показан сохранённый каталог."

func _update_categories() -> void:
	_category.clear()
	_category.add_item("Все категории")
	if _kind.selected == 2:
		var seen := {}
		for entry in preload("res://addons/roblox_studio/studio_prefab_library.gd").entries():
			if not seen.has(entry.category): _category.add_item(entry.category); seen[entry.category] = true
		return
	for category in Library.categories("model" if _kind.selected == 0 else "sound"): _category.add_item(category)

func refresh() -> void:
	_page_generation += 1
	items.clear()
	_audio.stop()
	var category := "" if _category.selected == 0 else _category.get_item_text(_category.selected)
	if _kind.selected == 2:
		var results: Array = preload("res://addons/roblox_studio/studio_prefab_library.gd").entries().filter(func(entry): return (category.is_empty() or category == entry.category) and (_search.text.is_empty() or (entry.name + " " + entry.description + " " + entry.id).to_lower().contains(_search.text.to_lower())))
		for entry in results.slice(_offset, _offset + PAGE_SIZE):
			items.add_item(entry.name)
			items.set_item_metadata(items.item_count - 1, "prefab:" + entry.id)
			items.set_item_tooltip(items.item_count - 1, entry.description)
		_next.disabled = results.size() <= _offset + PAGE_SIZE
		_previous.disabled = _offset == 0
		_page_label.text = "%d заготовок · %d" % [results.size(), _offset / PAGE_SIZE + 1]
		_preview.hide()
		_info.text = "Готовые объекты с редактируемыми Lua и параметрами."
		if items.item_count > 0: items.select(0); _select(0)
		return
	var results := Library.search_assets(_search.text, "model" if _kind.selected == 0 else "sound", category, PAGE_SIZE + 1, _offset)
	_next.disabled = results.size() <= PAGE_SIZE
	_previous.disabled = _offset == 0
	for entry in results.slice(0, PAGE_SIZE):
		var icon: Texture2D = null
		if not str(entry.thumbnail).is_empty():
			if ResourceLoader.exists(entry.thumbnail): icon = load(entry.thumbnail) as Texture2D
			elif FileAccess.file_exists(entry.thumbnail): icon = ImageTexture.create_from_image(Image.load_from_file(entry.thumbnail))
		var label: String = entry.name if entry.type == "model" else "♪ " + entry.name + "\n%.2f s" % float(entry.get("duration", 0))
		items.add_item(label, icon)
		items.set_item_metadata(items.item_count - 1, entry.id)
		items.set_item_tooltip(items.item_count - 1, "%s · %s\n%s · CC0\n%s" % [entry.name, entry.category, entry.source, entry.source_url])
	_page_label.text = "Страница %d" % (_offset / PAGE_SIZE + 1)
	_preview.visible = _kind.selected == 1
	if items.item_count > 0:
		items.select(0)
		_select(0)
	else:
		_info.text = "Подходящих ассетов нет."
	if DisplayServer.get_name() != "headless":
		_load_page_thumbnails(results.slice(0, PAGE_SIZE), _page_generation)

func _load_page_thumbnails(entries: Array, generation: int) -> void:
	# At most four requests are active; changing a page cancels pending work.
	for worker in range(mini(4, entries.size())):
		_thumbnail_worker(entries, generation, worker)

func _thumbnail_worker(entries: Array, generation: int, worker: int) -> void:
	for index in range(worker, entries.size(), 4):
		if generation != _page_generation or not is_inside_tree(): return
		var path := await ToolboxAssetService.ensure_thumbnail(entries[index])
		if generation != _page_generation or not is_inside_tree(): return
		if not path.is_empty() and FileAccess.file_exists(path):
			var bitmap := Image.load_from_file(path)
			if bitmap != null and not bitmap.is_empty(): items.set_item_icon(index, ImageTexture.create_from_image(bitmap))

func _select(index: int) -> void:
	_audio.stop()
	var id := str(items.get_item_metadata(index))
	if id.begins_with("prefab:"):
		for entry in preload("res://addons/roblox_studio/studio_prefab_library.gd").entries():
			if entry.id == id.substr(7): _info.text = entry.description; return
	var entry := Library.get_asset(str(items.get_item_metadata(index)))
	_info.text = "%s · %s\n%s · CC0" % [entry.get("name", ""), entry.get("category", ""), entry.get("source", "")]

func _insert_item(index: int) -> void:
	var id := str(items.get_item_metadata(index))
	if id.begins_with("prefab:"): prefab_requested.emit(id.substr(7))
	else: asset_requested.emit(id)
