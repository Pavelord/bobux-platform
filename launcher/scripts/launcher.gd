extends Control

const DEFAULT_MANIFEST_URL: String = "http://109.71.245.162/launcher/latest.json"
const LOCAL_VERSION_FILE: String = "version.json"
const TEMP_DIR_NAME: String = "_download"
const STAGING_DIR_NAME: String = "_staging_game"
const GAME_BACKUP_DIR_NAME: String = "_backup_game"
const LAUNCHER_STAGING_DIR_NAME: String = "_staging_launcher"
const HTTP_TIMEOUT_SECONDS: float = 60.0
const DOWNLOAD_IDLE_TIMEOUT_SECONDS: float = 45.0
const HTTP_ATTEMPTS_PER_URL: int = 3
const DOWNLOAD_ATTEMPTS_PER_URL: int = 8
const DOWNLOAD_CHUNK_BYTES: int = 8 * 1024 * 1024
const LAUNCHER_VERSION: String = "0.1.22"
const LAUNCHER_BUILD: int = 24
const MIN_GAME_EXECUTABLE_BYTES: int = 10 * 1024 * 1024
const InstanceGuard = preload("res://scripts/update_instance_guard.gd")

var _title_label: Label = null
var _status_label: Label = null
var _detail_label: Label = null
var _progress_bar: ProgressBar = null
var _action_button: Button = null
var _active_download_request: HTTPRequest = null
var _current_manifest: Dictionary = {}
var _install_root: String = ""
var _game_dir: String = ""
var _temp_dir: String = ""
var _staging_dir: String = ""
var _game_backup_dir: String = ""
var _launcher_staging_dir: String = ""
var _download_base_bytes: int = 0
var _download_total_size: int = -1
var _download_label: String = "update"
var _cancel_requested: bool = false
var _update_flow_running: bool = false
var _retry_available: bool = false
var _force_reinstall: bool = false
var _recovery_menu: MenuButton = null
var _cancel_button: Button = null
var _download_started_at: int = 0
var _download_speed_bytes: float = 0.0
var _download_speed_sample_at: int = 0
var _download_speed_sample_bytes: int = 0
var _download_response: Array = []
var _instance_guard: RefCounted = null
var _download_busy: bool = false

func _ready() -> void:
	_install_root = _get_install_root()
	_game_dir = _install_root.path_join(_get_project_setting_string("launcher/game_folder_name", "Game"))
	_temp_dir = _install_root.path_join(TEMP_DIR_NAME)
	_staging_dir = _install_root.path_join(STAGING_DIR_NAME)
	_game_backup_dir = _install_root.path_join(GAME_BACKUP_DIR_NAME)
	_launcher_staging_dir = _install_root.path_join(LAUNCHER_STAGING_DIR_NAME)
	_build_ui()
	call_deferred("_restore_launcher_window")
	call_deferred("_run_update_flow")

func _restore_launcher_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	# Build 23 supplies SW_HIDE to its replacement. The native display API
	# issues another ShowWindow(SW_NORMAL); the root Window cannot be hidden.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window.get_window_id())
	window.grab_focus()

func _process(_delta: float) -> void:
	if _instance_guard != null:
		_instance_guard.pump(get_window())
	if _active_download_request == null:
		return
	var downloaded: int = _download_base_bytes + _active_download_request.get_downloaded_bytes()
	if _download_base_bytes > 0 and _download_total_size > 0 and _active_download_request.get_body_size() == _download_total_size:
		# A mirror may answer a resumed Range with HTTP 200 and the whole file.
		downloaded = _active_download_request.get_downloaded_bytes()
	_render_download_progress(downloaded, _download_total_size, _download_label)

func _exit_tree() -> void:
	if _instance_guard != null:
		_instance_guard.release()

func _acquire_instance_guard() -> Dictionary:
	if _instance_guard == null:
		_instance_guard = InstanceGuard.new()
	return await _instance_guard.acquire(_install_root, get_tree())

func _acknowledge_self_update() -> void:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--launcher-handoff="):
			continue
		var nonce: String = argument.trim_prefix("--launcher-handoff=")
		if nonce.length() != 32 or not nonce.is_valid_hex_number(false):
			continue
		var ready_path: String = _install_root.path_join("_launcher_handoff_%s.ready" % nonce)
		if not FileAccess.file_exists(ready_path) or FileAccess.get_file_as_string(ready_path) != nonce:
			continue
		var ack := FileAccess.open(_install_root.path_join("_launcher_handoff_%s.ack" % nonce), FileAccess.WRITE)
		if ack != null:
			ack.store_string(JSON.stringify({"nonce": nonce, "pid": OS.get_process_id(), "build": _get_local_launcher_build(), "ready": true}))
			ack.close()
			_log_update("self_update_ready", "build=%d" % _get_local_launcher_build())

func _log_update(phase: String, detail: String = "") -> void:
	if _install_root.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_install_root)
	var path: String = _install_root.path_join("launcher-update.log")
	# Limit diagnostics without deleting download or installation artifacts.
	if _get_file_size(path) > 1024 * 1024:
		DirAccess.remove_absolute(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line("%s %s %s" % [Time.get_datetime_string_from_system(true), phase, detail.get_slice("\n", 0).left(400)])
		file.close()

func _build_ui() -> void:
	if _is_halloween_theme_enabled():
		_build_halloween_ui()
	else:
		_build_classic_ui()
	_detail_label.max_lines_visible = 3
	_action_button.pressed.disconnect(_launch_game)
	_action_button.pressed.connect(_on_action_pressed)
	_build_recovery_menu()

func _build_recovery_menu() -> void:
	var buttons := _action_button.get_parent() as HBoxContainer
	if buttons == null:
		var previous_parent := _action_button.get_parent()
		previous_parent.remove_child(_action_button)
		buttons = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 12)
		previous_parent.add_child(buttons)
		buttons.add_child(_action_button)
		_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recovery_menu = MenuButton.new()
	_recovery_menu.name = "RecoveryOptions"
	_recovery_menu.text = "Варианты"
	_recovery_menu.custom_minimum_size = Vector2(112, 44)
	_recovery_menu.focus_mode = Control.FOCUS_NONE
	_recovery_menu.visible = false
	if _is_halloween_theme_enabled():
		_style_seasonal_button(_recovery_menu, false)
	buttons.add_child(_recovery_menu)
	var popup := _recovery_menu.get_popup()
	popup.add_item("Переустановить игру", 1)
	popup.add_item("Начать загрузку заново", 2)
	popup.add_separator()
	popup.add_item("Открыть папку установки", 3)
	popup.id_pressed.connect(_on_recovery_selected)
	if _is_halloween_theme_enabled():
		popup.add_theme_stylebox_override("panel", _rounded_style(Color("252128"), 8, Color("ed8b4555")))
		popup.add_theme_color_override("font_color", Color("ffc28a"))
		popup.add_theme_color_override("font_hover_color", Color("ffffff"))

func _on_recovery_selected(option: int) -> void:
	if _update_flow_running:
		return
	if option == 3:
		OS.shell_open(_install_root)
		return
	if option not in [1, 2]:
		return
	# Installation is still staged and validated before replacing the current
	# game. Neither option removes the profile or the game's user:// data.
	_force_reinstall = true
	if option == 2:
		_delete_recursive_absolute(_temp_dir)
		_delete_recursive_absolute(_staging_dir)
		_delete_recursive_absolute(_launcher_staging_dir)
	_run_update_flow()

func _is_halloween_theme_enabled() -> bool:
	var selection: String = str(ProjectSettings.get_setting("launcher/theme", "auto")).strip_edges().to_lower()
	var environment_selection: String = OS.get_environment("BOBUX_LAUNCHER_THEME").strip_edges().to_lower()
	if not environment_selection.is_empty():
		selection = environment_selection
	if selection == "classic":
		return false
	if selection == "halloween":
		return true
	var moscow_date: Dictionary = Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + 3 * 3600)
	return int(moscow_date.get("month", 0)) == 10

func _build_classic_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.045, 0.08, 0.105, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var accent := ColorRect.new()
	accent.color = Color(0.0, 0.48, 0.74, 1.0)
	accent.anchor_right = 1.0
	accent.offset_bottom = 8.0
	background.add_child(accent)

	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -310.0
	card.offset_top = -190.0
	card.offset_right = 310.0
	card.offset_bottom = 190.0
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.96, 0.97, 0.98, 1.0)
	card_style.corner_radius_top_left = 18
	card_style.corner_radius_top_right = 18
	card_style.corner_radius_bottom_right = 18
	card_style.corner_radius_bottom_left = 18
	card_style.shadow_color = Color(0, 0, 0, 0.26)
	card_style.shadow_size = 18
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var logo_texture := _load_image_texture("res://assets/branding/bobux_logo_ui.png")
	if logo_texture != null:
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(0.0, 100.0)
		root.add_child(logo)

	_title_label = Label.new()
	_title_label.text = "Bobux"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.08, 0.13, 0.17, 1.0))
	root.add_child(_title_label)

	_status_label = Label.new()
	_status_label.text = "Checking for updates..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", Color(0.16, 0.18, 0.21, 1.0))
	root.add_child(_status_label)

	_detail_label = Label.new()
	_detail_label.text = "Preparing launcher."
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52, 1.0))
	root.add_child(_detail_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 20.0)
	root.add_child(_progress_bar)

	_action_button = Button.new()
	_action_button.text = "Launch"
	_action_button.disabled = true
	_action_button.custom_minimum_size = Vector2(0.0, 44.0)
	_action_button.focus_mode = Control.FOCUS_NONE
	_action_button.pressed.connect(_launch_game)
	root.add_child(_action_button)

func _build_halloween_ui() -> void:
	var seasonal_icon: Texture2D = load("res://assets/branding/halloween/bobux_app_icon.png") as Texture2D
	if seasonal_icon != null:
		DisplayServer.set_icon(seasonal_icon.get_image())
	var backdrop: Control = load("res://scripts/seasonal_background.gd").new()
	backdrop.name = "HalloweenBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var card := PanelContainer.new()
	card.name = "HalloweenUpdateCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -322.0
	card.offset_right = 322.0
	card.offset_top = -209.0
	card.offset_bottom = 209.0
	var card_style := _rounded_style(Color("17191ff5"), 22, Color("f78c3340"))
	card_style.shadow_color = Color("00000080")
	card_style.shadow_size = 24
	card_style.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	card.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var badge := Label.new()
	badge.text = "BOBUX / HALLOWEEN"
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color("ff993c"))
	header.add_child(badge)
	var version := Label.new()
	version.text = "LAUNCHER %s" % LAUNCHER_VERSION
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color("8e8990"))
	header.add_child(version)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 22)
	layout.add_child(hero)
	var logo := TextureRect.new()
	logo.name = "SeasonalLogo"
	var logo_path: String = "res://assets/branding/halloween/bobux_logo_ui.png"
	var logo_texture: Texture2D = _load_image_texture(logo_path if FileAccess.file_exists(logo_path) else "res://assets/branding/bobux_logo_ui.png")
	if FileAccess.file_exists(logo_path) and logo_texture != null:
		var wordmark := AtlasTexture.new()
		wordmark.atlas = logo_texture
		wordmark.region = Rect2(0, 490, 2048, 850)
		logo.texture = wordmark
	else:
		logo.texture = logo_texture
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(254, 126)
	hero.add_child(logo)
	var introduction := VBoxContainer.new()
	introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	introduction.alignment = BoxContainer.ALIGNMENT_CENTER
	introduction.add_theme_constant_override("separation", 7)
	hero.add_child(introduction)
	_title_label = Label.new()
	_title_label.text = "Ночь в Bobux"
	_title_label.add_theme_font_size_override("font_size", 25)
	_title_label.add_theme_color_override("font_color", Color("ffaa51"))
	introduction.add_child(_title_label)
	var subtitle := Label.new()
	subtitle.text = "Зажги свою историю.\nИгры, друзья и немного магии."
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("b4a79e"))
	introduction.add_child(subtitle)
	var divider := ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color("ff983b25")
	layout.add_child(divider)
	_status_label = Label.new()
	_status_label.text = "Проверяем обновления…"
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("ffb061"))
	layout.add_child(_status_label)
	_detail_label = Label.new()
	_detail_label.text = "Готовим всё для игры."
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size.y = 38
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", Color("bda99b"))
	layout.add_child(_detail_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "DownloadProgress"
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 9
	_progress_bar.add_theme_stylebox_override("background", _rounded_style(Color("323039"), 5))
	_progress_bar.add_theme_stylebox_override("fill", _rounded_style(Color("ff8a2b"), 5))
	layout.add_child(_progress_bar)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	layout.add_child(buttons)
	_action_button = Button.new()
	_action_button.name = "LaunchOrRetry"
	_action_button.text = "Играть"
	_action_button.disabled = true
	_action_button.custom_minimum_size.y = 46
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.focus_mode = Control.FOCUS_NONE
	_style_seasonal_button(_action_button, true)
	_action_button.pressed.connect(_launch_game)
	buttons.add_child(_action_button)
	_cancel_button = Button.new()
	_cancel_button.name = "PauseUpdate"
	_cancel_button.text = "Пауза"
	_cancel_button.disabled = true
	_cancel_button.custom_minimum_size = Vector2(104, 46)
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_style_seasonal_button(_cancel_button, false)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	buttons.add_child(_cancel_button)
	var footer := Label.new()
	footer.text = "Загрузка сохраняется при паузе · Файлы проверяются перед запуском"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color("857c7b"))
	layout.add_child(footer)
	card.modulate.a = 0.0
	var entrance: Tween = create_tween()
	entrance.tween_property(card, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)

func _rounded_style(color: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(mini(radius, 4))
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	return style

func _style_seasonal_button(button: Button, primary: bool) -> void:
	button.add_theme_font_size_override("font_size", 16 if primary else 13)
	button.add_theme_color_override("font_color", Color("1d130d") if primary else Color("efa970"))
	button.add_theme_color_override("font_hover_color", Color("1d130d") if primary else Color("ffc28a"))
	button.add_theme_color_override("font_disabled_color", Color("8b7565"))
	button.add_theme_stylebox_override("normal", _rounded_style(Color("ff8a2b") if primary else Color("2b2524"), 11))
	button.add_theme_stylebox_override("hover", _rounded_style(Color("ffab57") if primary else Color("3d2c26"), 11))
	button.add_theme_stylebox_override("pressed", _rounded_style(Color("d5681c") if primary else Color("221c1b"), 11))
	button.add_theme_stylebox_override("disabled", _rounded_style(Color("352a23"), 11, Color("593a2730")))

func _on_action_pressed() -> void:
	if _retry_available:
		_run_update_flow()
	else:
		_launch_game()

func _on_cancel_pressed() -> void:
	_cancel_requested = true
	if _cancel_button != null:
		_cancel_button.disabled = true

func _load_image_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture != null:
		return texture
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _run_update_flow() -> void:
	if _update_flow_running:
		return
	_update_flow_running = true
	var lease: Dictionary = await _acquire_instance_guard()
	if not bool(lease.get("ok", false)):
		_update_flow_running = false
		_fail(str(lease.get("error", "Не удалось защитить папку обновления.")))
		_recovery_menu.disabled = true
		return
	if bool(lease.get("secondary", false)):
		get_tree().quit()
		return
	_restore_launcher_window()
	_acknowledge_self_update()
	if OS.get_cmdline_user_args().has("--launcher-self-update-recovered") and _current_manifest.is_empty():
		_current_manifest = {"self_update_recovered": true}
		_update_flow_running = false
		_fail("Самообновление не завершилось. Предыдущий лаунчер восстановлен. Нажмите «Повторить»; файлы загрузки сохранены. Журнал: launcher-update.log")
		return
	_cancel_requested = false
	_retry_available = false
	if _recovery_menu != null:
		_recovery_menu.visible = false
		_recovery_menu.disabled = true
	_action_button.text = "Играть" if _is_halloween_theme_enabled() else "Launch"
	if _cancel_button != null:
		_cancel_button.visible = true
		_cancel_button.disabled = false
	await _run_update_flow_once()
	_update_flow_running = false
	if _cancel_button != null:
		_cancel_button.disabled = true
	if _retry_available and _recovery_menu != null:
		_recovery_menu.disabled = false

func _run_update_flow_once() -> void:
	_action_button.disabled = true
	_set_status("Checking for updates...", "Contacting release manifest.", 0.08)
	var manifest_urls: Array[String] = _get_manifest_urls()
	if manifest_urls.is_empty():
		_fail("Launcher manifest URL is not configured. Set launcher/manifest_url before export.")
		return
	var manifest_result: Dictionary = {}
	var last_manifest_error: String = ""
	for manifest_url in manifest_urls:
		for attempt in range(HTTP_ATTEMPTS_PER_URL):
			if _cancel_requested:
				_fail("Update paused. Your downloaded files are kept; press Retry to continue.")
				return
			_set_status("Checking for updates...", "Contacting %s (attempt %d/%d)" % [_short_url_for_status(manifest_url), attempt + 1, HTTP_ATTEMPTS_PER_URL], 0.08)
			manifest_result = await _http_get_json(manifest_url, "manifest")
			if bool(manifest_result.get("ok", false)):
				var candidate: Variant = manifest_result.get("data", {})
				if candidate is Dictionary and _is_manifest_older_than_installed(candidate):
					_log_update("stale_manifest_rejected", "local=%s/%d remote=%s/%d host=%s" % [_get_local_version(), _get_local_game_build(), str(candidate.get("version", "")), int(candidate.get("build", 0)), _short_url_for_status(manifest_url)])
					manifest_result = {"ok": false, "retryable": false, "error": "Зеркало предлагает устаревшую версию Bobux. Установленная игра и загрузка сохранены; нажмите «Повторить» позднее."}
			if bool(manifest_result.get("ok", false)):
				break
			last_manifest_error = str(manifest_result.get("error", "Could not fetch update manifest."))
			if not bool(manifest_result.get("retryable", true)):
				break
			await get_tree().create_timer(0.45 + float(attempt) * 0.65).timeout
		if bool(manifest_result.get("ok", false)):
			break
	if not bool(manifest_result.get("ok", false)):
		_fail(last_manifest_error if not last_manifest_error.is_empty() else "Could not fetch update manifest.")
		return
	var manifest: Dictionary = manifest_result.get("data", {}) if manifest_result.get("data", {}) is Dictionary else {}
	_current_manifest = manifest
	if _cancel_requested:
		_fail("Update paused. Press Retry to continue.")
		return
	var launcher_update_result: Dictionary = await _maybe_self_update_launcher(manifest)
	if bool(launcher_update_result.get("restarting", false)):
		return
	if not bool(launcher_update_result.get("ok", true)):
		_fail(str(launcher_update_result.get("error", "Launcher self-update failed.")))
		return
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	var zip_url: String = str(manifest.get("zip_url", "")).strip_edges()
	if remote_version.is_empty() or zip_url.is_empty():
		_fail("Manifest is missing version or zip_url.")
		return
	var recovered: Dictionary = await _recover_previous_game_install()
	if not bool(recovered.get("ok", false)):
		_fail(str(recovered.get("error", "Не удалось восстановить предыдущую установку.")))
		return
	if not _force_reinstall and _is_game_install_usable(manifest):
		_set_status("Game is up to date.", "Version %s build %d is ready." % [_get_local_version(), _get_local_game_build()], 1.0)
		_action_button.disabled = false
		_launch_game()
		return
	_set_status("Updating game...", "Installing version %s." % remote_version, 0.14)
	var update_result: Dictionary = await _download_and_install(manifest)
	if not bool(update_result.get("ok", false)):
		_fail(str(update_result.get("error", "Update failed.")))
		return
	_write_local_version(manifest)
	_force_reinstall = false
	_set_status("Update complete.", "Launching version %s." % remote_version, 1.0)
	_action_button.disabled = false
	_launch_game()

func _download_and_install(manifest: Dictionary) -> Dictionary:
	var expected_hash: String = str(manifest.get("sha256", "")).strip_edges().to_lower()
	var urls: Array[String] = _get_download_urls(manifest, "zip_url", PackedStringArray(["mirrors", "zip_mirrors", "download_mirrors"]))
	if urls.is_empty():
		return {"ok": false, "error": "zip_url is empty."}
	_delete_recursive_absolute(_staging_dir)
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	DirAccess.make_dir_recursive_absolute(_staging_dir)
	var zip_name: String = "game_%s.zip" % _hash_suffix(expected_hash)
	var zip_path: String = _temp_dir.path_join(zip_name)
	var package_size: int = int(manifest.get("package_size", -1))
	var download_result: Dictionary = await _download_file_from_urls(urls, zip_path, "game build", expected_hash, package_size)
	if not bool(download_result.get("ok", false)):
		return download_result
	_set_status("Extracting update...", "Download complete. Unpacking game files.", 1.0)
	await get_tree().process_frame
	var extract_result: Dictionary = await _run_file_task(_extract_zip_to_directory.bind(zip_path, _staging_dir))
	if not bool(extract_result.get("ok", false)):
		return extract_result
	if _cancel_requested:
		return {"ok": false, "error": "Update paused. Press Retry to continue.", "retryable": false}
	_set_status("Verifying installed files...", "Checking the game and Luau runtime before installation.", 1.0)
	var validate_result: Dictionary = await _run_file_task(_validate_game_install_directory.bind(_staging_dir, manifest))
	if not bool(validate_result.get("ok", false)):
		return validate_result
	if _cancel_requested:
		return {"ok": false, "error": "Update paused. Press Retry to continue.", "retryable": false}
	_set_status("Installing update...", "Download verified. Replacing local game build.", 1.0)
	var recovered: Dictionary = await _recover_previous_game_install()
	if not bool(recovered.get("ok", false)):
		return recovered
	_delete_recursive_absolute(_game_backup_dir)
	if DirAccess.dir_exists_absolute(_game_backup_dir):
		return {"ok": false, "error": "Предыдущая резервная копия занята другой программой. ZIP сохранён; закройте игру и повторите."}
	var had_previous_install: bool = DirAccess.dir_exists_absolute(_game_dir)
	if had_previous_install:
		var backup_error: Error = await _rename_with_retry(_game_dir, _game_backup_dir, "preserve_previous_game")
		if backup_error != OK:
			return {"ok": false, "error": "Не удалось заменить открытую игру. Закройте Bobux и повторите; проверенный ZIP сохранён (%s)." % error_string(backup_error)}
	var rename_error: Error = await _rename_with_retry(_staging_dir, _game_dir, "install_game")
	if rename_error != OK:
		if had_previous_install:
			var restore_error: Error = await _rename_with_retry(_game_backup_dir, _game_dir, "restore_previous_game")
			if restore_error != OK:
				return {"ok": false, "error": "Установка прервана. Предыдущая игра сохранена в _backup_game; закройте Bobux и повторите восстановление."}
		return {"ok": false, "error": "Could not install update: %s" % error_string(rename_error)}
	var installed_validate_result: Dictionary = _validate_game_install_directory(_game_dir, manifest, false)
	if not bool(installed_validate_result.get("ok", false)):
		_delete_recursive_absolute(_game_dir)
		if had_previous_install:
			await _rename_with_retry(_game_backup_dir, _game_dir, "restore_previous_game")
		return installed_validate_result
	_delete_recursive_absolute(_game_backup_dir)
	# Keep the verified ZIP for recovery/reinstall; success is recorded separately.
	_log_update("game_installed", "build=%d" % int(manifest.get("build", 0)))
	return {"ok": true}

func _recover_previous_game_install() -> Dictionary:
	if not _game_backup_dir.is_empty() and DirAccess.dir_exists_absolute(_game_backup_dir) and not DirAccess.dir_exists_absolute(_game_dir):
		var error: Error = await _rename_with_retry(_game_backup_dir, _game_dir, "recover_interrupted_install")
		if error != OK:
			return {"ok": false, "error": "Предыдущая игра сохранена в _backup_game, но временно недоступна. Закройте Bobux и нажмите «Повторить»."}
		_log_update("previous_game_restored")
	return {"ok": true}

func _maybe_self_update_launcher(manifest: Dictionary) -> Dictionary:
	var launcher_manifest: Dictionary = manifest.get("launcher", {}) if manifest.get("launcher", {}) is Dictionary else {}
	if launcher_manifest.is_empty():
		return {"ok": true}
	var remote_build: int = int(launcher_manifest.get("build", 0))
	var local_build: int = _get_local_launcher_build()
	if remote_build <= local_build:
		return {"ok": true}
	var urls: Array[String] = _get_download_urls(launcher_manifest, "zip_url", PackedStringArray(["mirrors", "zip_mirrors", "download_mirrors"]))
	if urls.is_empty():
		return {"ok": false, "error": "Launcher update is missing zip_url."}
	var expected_hash: String = str(launcher_manifest.get("sha256", "")).strip_edges().to_lower()
	_set_status("Updating launcher...", "A newer launcher build is available.", 0.2)
	_delete_recursive_absolute(_launcher_staging_dir)
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	DirAccess.make_dir_recursive_absolute(_launcher_staging_dir)
	var zip_name: String = "launcher_%s.zip" % _hash_suffix(expected_hash)
	var zip_path: String = _temp_dir.path_join(zip_name)
	var package_size: int = int(launcher_manifest.get("package_size", -1))
	var download_result: Dictionary = await _download_file_from_urls(urls, zip_path, "launcher", expected_hash, package_size)
	if not bool(download_result.get("ok", false)):
		return download_result
	_set_status("Extracting launcher...", "Launcher downloaded. Preparing the new version.", 1.0)
	var extract_result: Dictionary = await _run_file_task(_extract_zip_to_directory.bind(zip_path, _launcher_staging_dir))
	if not bool(extract_result.get("ok", false)):
		return extract_result
	var validate_result: Dictionary = _validate_launcher_install_directory(_launcher_staging_dir)
	if not bool(validate_result.get("ok", false)):
		return validate_result
	var bat_result: Dictionary = await _write_and_run_self_update_script()
	if not bool(bat_result.get("ok", false)):
		return bat_result
	_set_status("Restarting launcher...", "Applying launcher update.", 1.0)
	get_tree().quit()
	return {"ok": true, "restarting": true}

func _write_and_run_self_update_script() -> Dictionary:
	var launcher_exe := OS.get_executable_path()
	var source_exe := _launcher_staging_dir.path_join("BobuxLauncher.exe")
	if not FileAccess.file_exists(launcher_exe) or not FileAccess.file_exists(source_exe):
		return {"ok": false, "error": "Launcher executable is missing."}
	var nonce: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var helper_path := _temp_dir.path_join("apply_launcher_update_%s.ps1" % nonce)
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	var helper := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null:
		return {"ok": false, "error": "Could not save update helper."}
	helper.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF])) # Windows PowerShell 5 needs a UTF-8 BOM.
	helper.store_string(FileAccess.get_file_as_string("res://scripts/self_update.ps1"))
	helper.close()
	var source_hash: String = await _sha256_file_with_retry(source_exe)
	if source_hash.is_empty():
		return {"ok": false, "error": "Не удалось прочитать новый лаунчер. Файлы сохранены; повторите установку."}
	var remote_build: int = int((_current_manifest.get("launcher", {}) as Dictionary).get("build", 0))
	var args := PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", helper_path,
		"-OwnerPid", str(OS.get_process_id()), "-SourceExe", _windows_path(source_exe), "-TargetExe", _windows_path(launcher_exe),
		"-StateRoot", _windows_path(_install_root), "-Nonce", nonce, "-ExpectedHash", source_hash, "-ExpectedBuild", str(remote_build)])
	var pid: int = OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		return {"ok": false, "error": "Could not start update helper."}
	var ready_path: String = _install_root.path_join("_launcher_handoff_%s.ready" % nonce)
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(ready_path) and FileAccess.get_file_as_string(ready_path) == nonce:
			_log_update("self_update_handoff", "helper_ready build=%d" % remote_build)
			return {"ok": true}
		if not OS.is_process_running(pid):
			break
		await get_tree().process_frame
	return {"ok": false, "error": "Помощник обновления не готов. Лаунчер остаётся открыт; загрузка сохранена. Нажмите «Повторить»."}

func _download_file_from_urls(urls: Array[String], destination_path: String, label: String, expected_hash: String = "", expected_size: int = -1) -> Dictionary:
	if _download_busy:
		return {"ok": false, "retryable": false, "error": "Другая загрузка ещё завершается. Файлы сохранены."}
	_download_busy = true
	var result: Dictionary = await _download_file_from_urls_locked(urls, destination_path, label, expected_hash, expected_size)
	_download_busy = false
	return result

func _verify_downloaded_package(path: String, expected_hash: String, expected_size: int) -> Dictionary:
	if not expected_hash.is_empty():
		var actual_hash: String = await _sha256_file_with_retry(path)
		if actual_hash.is_empty():
			return {"ok": false, "retryable": false, "error": "Не удалось прочитать загруженный ZIP. Файл сохранён; закройте программу, которая его использует, и нажмите «Повторить»."}
		if actual_hash != expected_hash:
			_log_update("package_integrity_failed", path.get_file())
			return {"ok": false, "retryable": false, "corrupt": true, "error": "Downloaded package failed SHA-256 verification. Use Options to download it again."}
	var size: int = _file_size(path)
	if expected_size > 0 and size != expected_size:
		return {"ok": false, "retryable": false, "corrupt": size > 0, "error": "Downloaded package has an unexpected size. The existing files are preserved."}
	return {"ok": true}

func _download_file_from_urls_locked(urls: Array[String], destination_path: String, label: String, expected_hash: String, expected_size: int) -> Dictionary:
	expected_hash = expected_hash.strip_edges().to_lower()
	var last_error: String = ""
	var part_path: String = "%s.part" % destination_path
	if FileAccess.file_exists(destination_path):
		var cached: Dictionary = await _verify_downloaded_package(destination_path, expected_hash, expected_size)
		if bool(cached.get("ok", false)):
			_set_download_progress(_file_size(destination_path), expected_size, label)
			_log_update("package_cached", destination_path.get_file())
			return {"ok": true, "cached": true}
		if not bool(cached.get("corrupt", false)):
			return cached
		if DirAccess.remove_absolute(destination_path) != OK:
			return {"ok": false, "retryable": false, "error": "Повреждённый ZIP занят другой программой. Закройте её и повторите."}
	if FileAccess.file_exists(part_path) and expected_size > 0:
		var part_size: int = await _read_file_size_with_retry(part_path)
		if part_size < 0:
			return {"ok": false, "retryable": false, "error": "Файл загрузки временно недоступен. Он сохранён; нажмите «Повторить»."}
		if part_size > expected_size:
			return {"ok": false, "retryable": false, "error": "Размер частичной загрузки превышает размер обновления. В «Вариантах» выберите загрузку заново."}
		if part_size == expected_size:
			var complete: Dictionary = await _verify_downloaded_package(part_path, expected_hash, expected_size)
			if not bool(complete.get("ok", false)):
				return complete
			return await _finalize_download(part_path, destination_path, label, expected_size, true)
	for url in urls:
		for attempt in range(DOWNLOAD_ATTEMPTS_PER_URL):
			if _cancel_requested:
				return {"ok": false, "error": "Update paused. Press Retry to continue.", "retryable": false}
			_set_status("Downloading update...", "Downloading %s from %s (attempt %d/%d, resumable)" % [label, _short_url_for_status(url), attempt + 1, DOWNLOAD_ATTEMPTS_PER_URL], -1.0)
			var result: Dictionary = await _download_file_resumable(url, destination_path, label, expected_size)
			if bool(result.get("ok", false)):
				_set_status("Verifying update...", "Download complete. Checking SHA-256.", 1.0)
				await get_tree().process_frame
				var verified: Dictionary = await _verify_downloaded_package(part_path, expected_hash, expected_size)
				if not bool(verified.get("ok", false)):
					if bool(verified.get("corrupt", false)):
						DirAccess.remove_absolute(part_path)
					return verified
				return await _finalize_download(part_path, destination_path, label, expected_size, false)
			last_error = str(result.get("error", "Download failed."))
			_log_update("download_paused", last_error)
			if not bool(result.get("retryable", true)):
				# A missing endpoint may exist on a configured mirror. File/integrity
				# failures terminate the operation and never repeat whole transfers.
				if int(result.get("status", 0)) in [400, 401, 403, 404, 410]:
					break
				return result
			await get_tree().create_timer(0.7 + float(attempt) * 0.8).timeout
	return {"ok": false, "error": last_error if not last_error.is_empty() else "All download mirrors failed."}

func _finalize_download(part_path: String, destination_path: String, label: String, expected_size: int, cached: bool) -> Dictionary:
	var rename_error: Error = await _rename_with_retry(part_path, destination_path, "finalize_download")
	if rename_error != OK:
		return {"ok": false, "retryable": false, "error": "ZIP полностью загружен и проверен, но временно занят. Он сохранён; нажмите «Повторить» без повторной загрузки."}
	_set_download_progress(_file_size(destination_path), expected_size, label)
	_log_update("package_verified", destination_path.get_file())
	return {"ok": true, "cached": cached}

func _rename_with_retry(source: String, destination: String, phase: String) -> Error:
	var deadline: int = Time.get_ticks_msec() + int(float(ProjectSettings.get_setting("launcher/file_retry_seconds", 10.0)) * 1000.0)
	var error: Error = ERR_CANT_CREATE
	while true:
		error = DirAccess.rename_absolute(source, destination)
		if error == OK:
			return OK
		if Time.get_ticks_msec() >= deadline:
			_log_update(phase + "_failed", error_string(error))
			return error
		await get_tree().create_timer(0.25).timeout
	return error

func _download_file_resumable(url: String, destination_path: String, label: String, expected_size: int = -1) -> Dictionary:
	var part_path: String = "%s.part" % destination_path
	var response_path: String = "%s.response" % destination_path
	DirAccess.make_dir_recursive_absolute(destination_path.get_base_dir())
	var downloaded: int = _file_size(part_path)
	var total_size: int = expected_size
	var range_supported: bool = true
	if total_size > 0 and downloaded == total_size:
		return {"ok": true}
	while true:
		if _cancel_requested:
			return {"ok": false, "error": "Update paused. Press Retry to continue.", "retryable": false}
		var chunk_end: int = downloaded + DOWNLOAD_CHUNK_BYTES - 1
		if total_size > 0:
			chunk_end = mini(chunk_end, total_size - 1)
		var headers := PackedStringArray([
			"Accept: application/octet-stream",
			"Accept-Encoding: identity",
			"Range: bytes=%d-%d" % [downloaded, chunk_end]
		])
		_set_download_progress(downloaded, total_size, label)
		var result: Dictionary = await _http_get_response_to_file(url, headers, response_path, "download chunk")
		if not bool(result.get("ok", false)):
			return result
		var status: int = int(result.get("status", 0))
		var body_size: int = await _read_file_size_with_retry(response_path)
		if body_size < 0:
			return {"ok": false, "retryable": false, "error": "Загруженный диапазон временно занят другой программой. Основная загрузка сохранена."}
		var response_headers: PackedStringArray = result.get("headers", PackedStringArray())
		if status == 206:
			var range_start := _extract_start_from_content_range(response_headers, -1)
			if range_start != downloaded:
				DirAccess.remove_absolute(response_path)
				return {"ok": false, "error": "Server resumed at byte %d; expected byte %d." % [range_start, downloaded], "retryable": false}
			var range_end: int = _extract_end_from_content_range(response_headers, -1)
			if range_end < range_start or body_size != range_end - range_start + 1 or range_end > chunk_end:
				DirAccess.remove_absolute(response_path)
				return {"ok": false, "error": "Server returned an invalid or incomplete byte range.", "retryable": false}
			var server_total := _extract_total_size_from_content_range(response_headers, -1)
			if server_total > 0 and expected_size > 0 and server_total != expected_size:
				return {"ok": false, "error": "Manifest size (%d) does not match server size (%d)." % [expected_size, server_total], "retryable": false}
			if server_total > 0:
				total_size = server_total
		elif status == 200 and downloaded == 0:
			range_supported = false
			var response_total := _extract_content_length(response_headers, body_size)
			if expected_size > 0 and response_total > 0 and response_total != expected_size:
				return {"ok": false, "error": "Manifest size (%d) does not match server size (%d)." % [expected_size, response_total], "retryable": false}
			total_size = expected_size if expected_size > 0 else response_total
		elif status == 200 and downloaded > 0:
			# The server ignored Range. This response is a whole-file body, so
			# replace the old partial instead of appending and corrupting the ZIP.
			range_supported = false
			var response_total := _extract_content_length(response_headers, body_size)
			if expected_size > 0 and response_total > 0 and response_total != expected_size:
				return {"ok": false, "error": "Manifest size (%d) does not match server size (%d)." % [expected_size, response_total], "retryable": false}
			total_size = expected_size if expected_size > 0 else response_total
		else:
			return {"ok": false, "error": "Server did not continue resumable download: status=%d" % status}
		if body_size <= 0:
			return {"ok": false, "error": "Download returned an empty chunk."}
		if status == 206:
			var write_result: Dictionary = _append_response_file(part_path, response_path)
			if not bool(write_result.get("ok", false)):
				return write_result
			downloaded += body_size
		else:
			if total_size > 0 and body_size != total_size:
				return {"ok": false, "error": "Full download has the wrong size.", "retryable": false}
			if FileAccess.file_exists(part_path):
				DirAccess.remove_absolute(part_path)
			var replace_error: Error = await _rename_with_retry(response_path, part_path, "save_full_download")
			if replace_error != OK:
				return {"ok": false, "error": "Could not save downloaded package: %s" % error_string(replace_error), "retryable": false}
			downloaded = body_size
		_download_base_bytes = downloaded
		_download_total_size = total_size
		_set_download_progress(downloaded, total_size, label)
		if not range_supported:
			break
		if total_size > 0 and downloaded >= total_size:
			break
		if body_size < DOWNLOAD_CHUNK_BYTES and total_size <= 0:
			break
	if total_size > 0 and downloaded != total_size:
		return {"ok": false, "error": "Download ended at %d of %d bytes." % [downloaded, total_size]}
	# Verification and file promotion are separate from network retry. A blocked
	# final rename must never issue another HTTP Range starting after EOF.
	return {"ok": true}

func _http_get_response_to_file(url: String, headers: PackedStringArray, response_path: String, label: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	# A slow but progressing 245 MB transfer must not restart at 120 seconds.
	# HTTPRequest's timeout is a total deadline, so enforce inactivity separately.
	request.timeout = 0.0
	request.accept_gzip = false
	request.download_file = response_path
	add_child(request)
	_download_response = []
	request.request_completed.connect(_on_download_response_completed)
	_active_download_request = request
	var error: Error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_active_download_request = null
		request.queue_free()
		return {"ok": false, "error": "Could not start %s: %s" % [label, error_string(error)]}
	var last_progress_at: int = Time.get_ticks_msec()
	var last_received: int = 0
	var idle_timeout_ms: int = int(float(ProjectSettings.get_setting("launcher/download_idle_timeout_seconds", DOWNLOAD_IDLE_TIMEOUT_SECONDS)) * 1000.0)
	while _download_response.is_empty():
		await get_tree().process_frame
		var received: int = request.get_downloaded_bytes()
		if received > last_received:
			last_progress_at = Time.get_ticks_msec()
			last_received = received
		if _cancel_requested or Time.get_ticks_msec() - last_progress_at > idle_timeout_ms:
			request.cancel_request()
			_active_download_request = null
			request.queue_free()
			if FileAccess.file_exists(response_path):
				DirAccess.remove_absolute(response_path)
			return {"ok": false, "error": "Update paused. Press Retry to continue." if _cancel_requested else "Download stalled; continuing from the last verified range.", "retryable": not _cancel_requested}
	var result: Array = _download_response
	_download_response = []
	_active_download_request = null
	request.queue_free()
	# Release the HTTPRequest worker and its file handle before moving the body.
	await get_tree().process_frame
	var transport: int = int(result[0])
	var status: int = int(result[1])
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		if FileAccess.file_exists(response_path):
			DirAccess.remove_absolute(response_path)
		return {
			"ok": false,
			"error": "%s failed: result=%d status=%d" % [label, transport, status],
			"status": status,
			"retryable": _is_retryable_http_failure(transport, status)
		}
	return {
		"ok": true,
		"status": status,
		"headers": result[2] as PackedStringArray
	}

func _on_download_response_completed(result: int, status: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_download_response = [result, status, headers, body]

func _append_response_file(destination: String, response_path: String) -> Dictionary:
	var source: FileAccess = FileAccess.open(response_path, FileAccess.READ)
	var output: FileAccess = FileAccess.open(destination, FileAccess.READ_WRITE if FileAccess.file_exists(destination) else FileAccess.WRITE)
	if source == null or output == null:
		return {"ok": false, "error": "Could not save downloaded range.", "retryable": false}
	output.seek_end()
	while source.get_position() < source.get_length():
		var bytes: PackedByteArray = source.get_buffer(64 * 1024)
		if bytes.is_empty() or source.get_error() not in [OK, ERR_FILE_EOF]:
			source.close()
			output.close()
			return {"ok": false, "retryable": false, "error": "Could not read downloaded range."}
		output.store_buffer(bytes)
	var write_error: Error = output.get_error()
	source.close()
	output.close()
	if write_error != OK:
		return {"ok": false, "error": "Could not write downloaded range: %s" % error_string(write_error), "retryable": false}
	DirAccess.remove_absolute(response_path)
	return {"ok": true}

func _set_download_progress(downloaded: int, total_size: int, label: String) -> void:
	if _download_started_at == 0 or _download_label != label:
		_download_started_at = Time.get_ticks_msec()
		_download_speed_sample_at = _download_started_at
		_download_speed_sample_bytes = downloaded
		_download_speed_bytes = 0.0
	_download_base_bytes = downloaded
	_download_total_size = total_size
	_download_label = label
	_render_download_progress(downloaded, total_size, label)

func _render_download_progress(downloaded: int, total_size: int, label: String) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _download_speed_sample_at >= 700:
		var speed: float = maxf(0.0, float(downloaded - _download_speed_sample_bytes) * 1000.0 / float(now - _download_speed_sample_at))
		_download_speed_bytes = speed if _download_speed_bytes <= 0.0 else lerpf(_download_speed_bytes, speed, 0.3)
		_download_speed_sample_at = now
		_download_speed_sample_bytes = downloaded
	var speed_label: String = " · %.1f MB/s" % (_download_speed_bytes / 1048576.0) if _download_speed_bytes > 0 else ""
	if total_size > 0:
		_set_progress(float(downloaded) / float(total_size), "Downloading %s %.1f / %.1f MB%s" % [
			label,
			float(downloaded) / 1048576.0,
			float(total_size) / 1048576.0,
			speed_label
		])
	else:
		_set_progress(-1.0, "Downloading %s %.1f MB" % [label, float(downloaded) / 1048576.0])

func _append_bytes_to_file(path: String, bytes: PackedByteArray) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = null
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open partial download for writing."}
	file.seek_end()
	file.store_buffer(bytes)
	file.close()
	return {"ok": true}

func _write_bytes_to_file(path: String, bytes: PackedByteArray) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not restart partial download from the server response."}
	file.store_buffer(bytes)
	file.close()
	return {"ok": true}

func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = int(file.get_length())
	file.close()
	return size

func _extract_total_size_from_content_range(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-range:"):
			continue
		var slash_index: int = clean_header.find("/")
		if slash_index < 0:
			return fallback
		var total_text: String = clean_header.substr(slash_index + 1).strip_edges()
		if total_text.is_valid_int():
			return int(total_text)
	return fallback

func _extract_start_from_content_range(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-range:"):
			continue
		var range_text: String = clean_header.substr(clean_header.find(":") + 1).strip_edges()
		var space_index := range_text.find(" ")
		if space_index >= 0:
			range_text = range_text.substr(space_index + 1).strip_edges()
		var dash_index := range_text.find("-")
		var start_text := range_text.substr(0, dash_index).strip_edges() if dash_index >= 0 else ""
		if start_text.is_valid_int():
			return int(start_text)
	return fallback

func _extract_end_from_content_range(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-range:"):
			continue
		var range_text: String = clean_header.substr(clean_header.find(":") + 1).strip_edges()
		var dash_index: int = range_text.find("-")
		var slash_index: int = range_text.find("/")
		if dash_index < 0 or slash_index <= dash_index:
			return fallback
		var end_text: String = range_text.substr(dash_index + 1, slash_index - dash_index - 1).strip_edges()
		return int(end_text) if end_text.is_valid_int() else fallback
	return fallback

func _extract_content_length(headers: PackedStringArray, fallback: int = -1) -> int:
	for header in headers:
		var clean_header: String = str(header).strip_edges()
		if not clean_header.to_lower().begins_with("content-length:"):
			continue
		var length_text: String = clean_header.substr(clean_header.find(":") + 1).strip_edges()
		if length_text.is_valid_int():
			return int(length_text)
	return fallback

func _hash_suffix(expected_hash: String) -> String:
	var clean_hash: String = expected_hash.strip_edges().to_lower()
	if clean_hash.length() >= 12:
		return clean_hash.substr(0, 12)
	return "current"

func _http_get_json(url: String, label: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(request)
	var error: Error = request.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "Could not start %s request: %s" % [label, error_string(error)]}
	var result: Array = await request.request_completed
	request.queue_free()
	var transport: int = int(result[0])
	var status: int = int(result[1])
	var body: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if transport != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {
			"ok": false,
			"error": "%s request failed: result=%d status=%d" % [label, transport, status],
			"status": status,
			"retryable": _is_retryable_http_failure(transport, status)
		}
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "%s response was not a JSON object." % label}
	return {"ok": true, "data": parsed}

func _is_retryable_http_failure(transport: int, status: int) -> bool:
	if transport != HTTPRequest.RESULT_SUCCESS:
		return true
	return status == 408 or status == 409 or status == 425 or status == 429 or status >= 500

func _extract_zip_to_directory(zip_path: String, target_dir: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error: Error = reader.open(zip_path)
	if open_error != OK:
		return {"ok": false, "error": "Could not open update zip: %s" % error_string(open_error)}
	# Validate the central directory before native streaming extraction. Never
	# allocate the complete 850 MB embedded executable in the 32-bit launcher.
	for packed_path in reader.get_files():
		var relative: String = str(packed_path).replace("\\", "/")
		if not _is_safe_package_path(relative):
			reader.close()
			return {"ok": false, "error": "Unsafe path in update zip: %s" % relative}
	if OS.get_name() == "Windows":
		reader.close()
		return _extract_zip_to_directory_windows(zip_path, target_dir)
	for packed_path in reader.get_files():
		var clean_path: String = str(packed_path).replace("\\", "/").strip_edges()
		if clean_path.is_empty() or clean_path.ends_with("/"):
			continue
		if not _is_safe_package_path(clean_path):
			reader.close()
			return {"ok": false, "error": "Unsafe path in update zip: %s" % clean_path}
		var output_path: String = target_dir.path_join(clean_path)
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var bytes: PackedByteArray = reader.read_file(clean_path)
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			reader.close()
			return {"ok": false, "error": "Could not write extracted file: %s" % clean_path}
		file.store_buffer(bytes)
		var write_error: Error = file.get_error()
		file.close()
		if write_error != OK:
			reader.close()
			return {"ok": false, "error": "Could not write extracted file: %s" % clean_path}
	reader.close()
	return {"ok": true}

func _is_safe_package_path(path: String) -> bool:
	var clean: String = path.replace("\\", "/")
	if clean.is_empty() or clean.begins_with("/") or clean.contains(":"):
		return false
	for component in clean.split("/"):
		if component == ".." or component.ends_with(".") or component.ends_with(" "):
			return false
	return true

func _run_file_task(task: Callable) -> Dictionary:
	var worker := Thread.new()
	var start_error: Error = worker.start(task)
	if start_error != OK:
		return {"ok": false, "error": "Could not prepare update files: %s" % error_string(start_error)}
	# Unpacking the large embedded PCK runs off the UI thread. A completed
	# download stays at 100%; extraction is an explicit, separate phase.
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	return result as Dictionary if result is Dictionary else {"ok": false, "error": "Update file operation returned no result."}

func _extract_zip_to_directory_windows(zip_path: String, target_dir: String) -> Dictionary:
	_delete_recursive_absolute(target_dir)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var global_zip: String = _windows_path(zip_path)
	var global_target: String = _windows_path(target_dir)
	var ps_script: String = "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force" % [
		global_zip.replace("'", "''"),
		global_target.replace("'", "''")
	]
	var output: Array = []
	var exit_code: int = OS.execute("powershell.exe", PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-Command",
		ps_script
	]), output, true, false)
	if exit_code == 0:
		return {"ok": true}
	# A failed extractor may leave partial files; the alternative starts clean.
	_delete_recursive_absolute(target_dir)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var tar_output: Array = []
	var tar_code: int = OS.execute("tar.exe", PackedStringArray([
		"-xf",
		global_zip,
		"-C",
		global_target
	]), tar_output, true, false)
	if tar_code == 0:
		return {"ok": true}
	return {
		"ok": false,
		"error": "Could not extract update zip with Windows tools.\nPowerShell exit=%d: %s\nTar exit=%d: %s" % [
			exit_code,
			"\n".join(output),
			tar_code,
			"\n".join(tar_output)
		]
	}

func _launch_game() -> void:
	var candidates := _get_game_executable_candidates(_current_manifest)
	var missing: Array[String] = []
	for executable_path in candidates:
		if not FileAccess.file_exists(executable_path):
			missing.append(executable_path)
			continue
		var file_size: int = _get_file_size(executable_path)
		if file_size < MIN_GAME_EXECUTABLE_BYTES:
			missing.append("%s (%d bytes)" % [executable_path, file_size])
			continue
		var pid: int = OS.create_process(executable_path, PackedStringArray(), false)
		if pid > 0:
			get_tree().quit()
			return
		var cmd_pid: int = _launch_game_via_cmd(executable_path)
		if cmd_pid > 0:
			get_tree().quit()
			return
	_fail("Could not launch game executable.\nTried: %s\nInstall folder: %s" % [
		", ".join(candidates) if not candidates.is_empty() else ", ".join(missing),
		_game_dir
	])

func _get_manifest_url() -> String:
	return _get_project_setting_string("launcher/manifest_url", DEFAULT_MANIFEST_URL).strip_edges()

func _get_manifest_urls() -> Array[String]:
	var urls: Array[String] = []
	var primary_url: String = _get_manifest_url()
	if not primary_url.is_empty():
		urls.append(primary_url)
	if ProjectSettings.has_setting("launcher/manifest_fallback_urls"):
		var fallback_urls: Variant = ProjectSettings.get_setting("launcher/manifest_fallback_urls", PackedStringArray())
		if fallback_urls is PackedStringArray or fallback_urls is Array:
			for url_variant in fallback_urls:
				var fallback_url: String = str(url_variant).strip_edges()
				if fallback_url.is_empty() or urls.has(fallback_url):
					continue
				urls.append(fallback_url)
	return urls

func _get_download_urls(manifest: Dictionary, primary_key: String, mirror_keys: PackedStringArray) -> Array[String]:
	var urls: Array[String] = []
	var primary_url: String = str(manifest.get(primary_key, "")).strip_edges()
	if not primary_url.is_empty():
		urls.append(primary_url)
	for mirror_key in mirror_keys:
		var mirrors: Variant = manifest.get(str(mirror_key), [])
		if not (mirrors is Array):
			continue
		for mirror_variant in mirrors:
			var mirror_url: String = str(mirror_variant).strip_edges()
			if mirror_url.is_empty() or urls.has(mirror_url):
				continue
			urls.append(mirror_url)
	return urls

func _get_local_launcher_build() -> int:
	if ProjectSettings.has_setting("launcher/build"):
		return int(ProjectSettings.get_setting("launcher/build", LAUNCHER_BUILD))
	return LAUNCHER_BUILD

func _short_url_for_status(url: String) -> String:
	var clean_url: String = url.strip_edges()
	var scheme_end: int = clean_url.find("://")
	var host_start: int = scheme_end + 3 if scheme_end >= 0 else 0
	var slash_index: int = clean_url.find("/", host_start)
	return clean_url if slash_index < 0 else clean_url.substr(0, slash_index)

func _get_install_root() -> String:
	var local_app_data: String = OS.get_environment("LOCALAPPDATA").strip_edges()
	if local_app_data.is_empty():
		local_app_data = OS.get_user_data_dir().get_base_dir()
	var folder_name: String = _get_project_setting_string("launcher/install_folder_name", "Bobux")
	return local_app_data.path_join(folder_name)

func _get_game_executable_path(manifest: Dictionary) -> String:
	var exe_name: String = str(manifest.get("executable", "")).strip_edges()
	if exe_name.is_empty():
		exe_name = _get_project_setting_string("launcher/game_executable", "Bobux.exe")
	return _game_dir.path_join(exe_name)

func _get_game_executable_candidates(manifest: Dictionary) -> Array[String]:
	return _get_game_executable_candidates_for_directory(_game_dir, manifest)

func _get_game_executable_candidate_names(manifest: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var primary_name: String = str(manifest.get("executable", "")).strip_edges()
	if not primary_name.is_empty():
		names.append(primary_name)
	var compat: Variant = manifest.get("compat_executables", [])
	if compat is Array:
		for raw_name in compat:
			var compat_name: String = str(raw_name).strip_edges()
			if not compat_name.is_empty() and not names.has(compat_name):
				names.append(compat_name)
	var configured_name: String = _get_project_setting_string("launcher/game_executable", "Bobux.exe").strip_edges()
	if not configured_name.is_empty() and not names.has(configured_name):
		names.append(configured_name)
	for fallback_name in ["Bobux.exe", "Game.exe"]:
		if not names.has(fallback_name):
			names.append(fallback_name)
	return names

func _launch_game_via_cmd(executable_path: String) -> int:
	if OS.get_name() != "Windows":
		return 0
	var helper_path := _temp_dir.path_join("launch_game.cmd")
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	var helper := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null:
		return 0
	helper.store_string("@echo off\r\n")
	helper.store_string("cd /d \"%s\"\r\n" % _windows_path(executable_path.get_base_dir()))
	helper.store_string("start \"\" \"%s\"\r\n" % _windows_path(executable_path))
	helper.store_string("exit /b 0\r\n")
	helper.close()
	return OS.create_process("cmd.exe", PackedStringArray(["/C", _windows_path(helper_path)]), false)

func _is_game_install_usable(manifest: Dictionary) -> bool:
	var validate_result: Dictionary = _validate_game_install_directory(_game_dir, manifest, false)
	if not bool(validate_result.get("ok", false)):
		_delete_broken_game_install_if_needed()
		return false
	if _local_install_contract_matches_manifest(manifest) and not _is_remote_manifest_newer(manifest, _get_local_version(), _get_local_game_build()):
		return true
	# A missing/stale marker is not a reason to download an identical package.
	# Adopt it only after checking the executable and every required file hash.
	if str(manifest.get("executable_sha256", "")).is_empty():
		return false
	if not bool(_validate_game_install_directory(_game_dir, manifest, true).get("ok", false)):
		return false
	_write_local_version(manifest)
	return true

func _validate_game_install_directory(directory: String, manifest: Dictionary, verify_hashes: bool = true) -> Dictionary:
	var executable_path: String = _find_usable_game_executable(directory, manifest)
	if executable_path.is_empty():
		return {
			"ok": false,
			"error": "Downloaded build is invalid: game executable is missing or empty after extraction."
		}
	var executable_contract: Dictionary = _validate_install_file_contract(
		executable_path,
		int(manifest.get("executable_size", 0)),
		str(manifest.get("executable_sha256", "")),
		"game executable",
		verify_hashes
	)
	if not bool(executable_contract.get("ok", false)):
		return executable_contract
	var required_contract: Dictionary = _validate_required_install_files(directory, manifest, verify_hashes)
	if not bool(required_contract.get("ok", false)):
		return required_contract
	if bool(manifest.get("embedded_pck", false)):
		return {"ok": true}
	var pck_path: String = "%s.pck" % executable_path.get_basename()
	if FileAccess.file_exists(pck_path) and _get_file_size(pck_path) > MIN_GAME_EXECUTABLE_BYTES:
		return {"ok": true}
	for fallback_name in ["Bobux.pck", "Game.pck"]:
		var fallback_pck: String = directory.path_join(fallback_name)
		if FileAccess.file_exists(fallback_pck) and _get_file_size(fallback_pck) > MIN_GAME_EXECUTABLE_BYTES:
			return {"ok": true}
	return {"ok": false, "error": "Downloaded build is missing its .pck data file."}

func _validate_required_install_files(directory: String, manifest: Dictionary, verify_hashes: bool) -> Dictionary:
	var required_files: Variant = manifest.get("required_files", [])
	if not (required_files is Array):
		return {"ok": true}
	for raw_contract in required_files:
		if not (raw_contract is Dictionary):
			continue
		var contract: Dictionary = raw_contract as Dictionary
		var relative_path: String = str(contract.get("path", "")).replace("\\", "/").strip_edges()
		if relative_path.is_empty():
			continue
		if not _is_safe_package_path(relative_path):
			return {"ok": false, "error": "Update manifest contains an unsafe required file path: %s" % relative_path}
		var result: Dictionary = _validate_install_file_contract(
			directory.path_join(relative_path),
			int(contract.get("size", 0)),
			str(contract.get("sha256", "")),
			"required file %s" % relative_path,
			verify_hashes
		)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true}

func _validate_install_file_contract(path: String, expected_size: int, expected_hash: String, label: String, verify_hash: bool) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Downloaded build is missing %s." % label}
	var actual_size: int = _get_file_size(path)
	if actual_size < MIN_GAME_EXECUTABLE_BYTES and label == "game executable":
		return {"ok": false, "error": "Downloaded %s is too small (%d bytes)." % [label, actual_size]}
	if expected_size > 0 and actual_size != expected_size:
		return {
			"ok": false,
			"error": "Downloaded %s has the wrong size (%d, expected %d bytes)." % [label, actual_size, expected_size]
		}
	var normalized_hash: String = expected_hash.strip_edges().to_lower()
	if verify_hash and not normalized_hash.is_empty():
		var actual_hash: String = _sha256_file(path).to_lower()
		if actual_hash.is_empty() or actual_hash != normalized_hash:
			return {"ok": false, "error": "Downloaded %s failed SHA-256 verification." % label}
	return {"ok": true}

func _local_install_contract_matches_manifest(manifest: Dictionary) -> bool:
	var expected_hash: String = str(manifest.get("executable_sha256", "")).strip_edges().to_lower()
	var expected_size: int = int(manifest.get("executable_size", 0))
	if expected_hash.is_empty() and expected_size <= 0:
		return true
	var local_record: Dictionary = _read_local_version_record()
	if expected_size > 0 and int(local_record.get("executable_size", 0)) != expected_size:
		return false
	if not expected_hash.is_empty() and str(local_record.get("executable_sha256", "")).strip_edges().to_lower() != expected_hash:
		return false
	return true

func _validate_launcher_install_directory(directory: String) -> Dictionary:
	for executable_name in ["BobuxLauncher.exe", OS.get_executable_path().get_file()]:
		var clean_name: String = executable_name.strip_edges()
		if clean_name.is_empty():
			continue
		var executable_path: String = directory.path_join(clean_name)
		if FileAccess.file_exists(executable_path) and _get_file_size(executable_path) >= MIN_GAME_EXECUTABLE_BYTES:
			return {"ok": true}
	return {
		"ok": false,
		"error": "Downloaded launcher update is invalid: BobuxLauncher.exe is missing or empty."
	}

func _find_usable_game_executable(directory: String, manifest: Dictionary) -> String:
	for executable_path in _get_game_executable_candidates_for_directory(directory, manifest):
		if not FileAccess.file_exists(executable_path):
			continue
		if _get_file_size(executable_path) >= MIN_GAME_EXECUTABLE_BYTES:
			return executable_path
	return ""

func _get_game_executable_candidates_for_directory(directory: String, manifest: Dictionary) -> Array[String]:
	var names: Array[String] = _get_game_executable_candidate_names(manifest)
	var paths: Array[String] = []
	for exe_name in names:
		var clean_name: String = exe_name.replace("\\", "/").get_file()
		if clean_name.is_empty():
			continue
		var path: String = directory.path_join(clean_name)
		if not paths.has(path):
			paths.append(path)
	return paths

func _delete_broken_game_install_if_needed() -> void:
	if _game_dir.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(_game_dir):
		return
	var has_broken_executable := false
	for executable_path in _get_game_executable_candidates(_current_manifest):
		if FileAccess.file_exists(executable_path) and _get_file_size(executable_path) < MIN_GAME_EXECUTABLE_BYTES:
			has_broken_executable = true
			break
	if has_broken_executable:
		_delete_recursive_absolute(_game_dir)

func _get_local_version() -> String:
	var parsed := _read_local_version_record()
	if parsed.is_empty():
		return "0.0.0"
	return str(parsed.get("version", "0.0.0")).strip_edges()

func _get_local_game_build() -> int:
	var parsed := _read_local_version_record()
	if parsed.is_empty():
		return 0
	return int(parsed.get("build", 0))

func _read_local_version_record() -> Dictionary:
	for version_path in [_game_dir.path_join(LOCAL_VERSION_FILE), _install_root.path_join(LOCAL_VERSION_FILE)]:
		if not FileAccess.file_exists(version_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(version_path))
		if parsed is Dictionary:
			return parsed as Dictionary
	return {}

func _write_local_version(manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_game_dir)
	var executable_path: String = _find_usable_game_executable(_game_dir, manifest)
	var executable_size: int = _get_file_size(executable_path) if not executable_path.is_empty() else 0
	var executable_hash: String = str(manifest.get("executable_sha256", "")).strip_edges().to_lower()
	if executable_hash.is_empty() and not executable_path.is_empty():
		executable_hash = _sha256_file(executable_path).to_lower()
	var payload := JSON.stringify({
		"version": str(manifest.get("version", "")).strip_edges(),
		"build": int(manifest.get("build", 0)),
		"executable_size": executable_size,
		"executable_sha256": executable_hash,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}, "\t")
	for version_path in [_game_dir.path_join(LOCAL_VERSION_FILE), _install_root.path_join(LOCAL_VERSION_FILE)]:
		DirAccess.make_dir_recursive_absolute(version_path.get_base_dir())
		var file := FileAccess.open(version_path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(payload)
		file.close()
	var written := _read_local_version_record()
	if int(written.get("build", 0)) != int(manifest.get("build", 0)):
		push_warning("[BobuxLauncher] Failed to persist local game build marker.")

func _is_remote_newer(remote_version: String, local_version: String) -> bool:
	var remote_parts: PackedStringArray = remote_version.split(".")
	var local_parts: PackedStringArray = local_version.split(".")
	var count: int = maxi(remote_parts.size(), local_parts.size())
	for i in range(count):
		var remote_num: int = int(remote_parts[i]) if i < remote_parts.size() else 0
		var local_num: int = int(local_parts[i]) if i < local_parts.size() else 0
		if remote_num != local_num:
			return remote_num > local_num
	return false

func _is_remote_manifest_newer(manifest: Dictionary, local_version: String, local_build: int) -> bool:
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	if _is_remote_newer(remote_version, local_version):
		return true
	if _is_remote_newer(local_version, remote_version):
		return false
	return int(manifest.get("build", 0)) > local_build

func _is_manifest_older_than_installed(manifest: Dictionary) -> bool:
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	var local_record: Dictionary = _read_local_version_record()
	if remote_version.is_empty() or local_record.is_empty():
		return false
	return _is_remote_manifest_newer(local_record, remote_version, int(manifest.get("build", 0)))

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var bytes: PackedByteArray = file.get_buffer(65536)
		if bytes.is_empty() or file.get_error() not in [OK, ERR_FILE_EOF]:
			file.close()
			return ""
		context.update(bytes)
	file.close()
	return context.finish().hex_encode()

func _sha256_file_async(path: String) -> String:
	var worker := Thread.new()
	if worker.start(_sha256_file.bind(path)) != OK:
		return ""
	while worker.is_alive():
		await get_tree().process_frame
	return str(worker.wait_to_finish())

func _sha256_file_with_retry(path: String) -> String:
	var deadline: int = Time.get_ticks_msec() + int(float(ProjectSettings.get_setting("launcher/file_retry_seconds", 10.0)) * 1000.0)
	while true:
		var value: String = await _sha256_file_async(path)
		if not value.is_empty():
			return value
		if Time.get_ticks_msec() >= deadline:
			_log_update("hash_read_failed", path.get_file())
			return ""
		await get_tree().create_timer(0.25).timeout
	return ""

func _read_file_size_with_retry(path: String) -> int:
	var deadline: int = Time.get_ticks_msec() + int(float(ProjectSettings.get_setting("launcher/file_retry_seconds", 10.0)) * 1000.0)
	while true:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var size: int = file.get_length()
			file.close()
			return size
		if Time.get_ticks_msec() >= deadline:
			return -1
		await get_tree().create_timer(0.25).timeout
	return -1

func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = int(file.get_length())
	file.close()
	return length

func _delete_recursive_absolute(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	var dir := DirAccess.open(path)
	if dir == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_delete_recursive_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _get_project_setting_string(setting_name: String, fallback: String) -> String:
	if ProjectSettings.has_setting(setting_name):
		return str(ProjectSettings.get_setting(setting_name, fallback))
	return fallback

func _windows_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("/", "\\")

func _set_status(title: String, detail: String, progress: float) -> void:
	if _is_halloween_theme_enabled():
		var titles: Dictionary = {
			"Checking for updates...": "Проверяем обновления…",
			"Updating game...": "Готовим обновление игры…",
			"Downloading update...": "Загружаем обновление…",
			"Verifying update...": "Проверяем загрузку…",
			"Extracting update...": "Распаковываем игру…",
			"Installing update...": "Устанавливаем игру…",
			"Verifying installed files...": "Проверяем файлы игры…",
			"Updating launcher...": "Обновляем лаунчер…",
			"Extracting launcher...": "Распаковываем лаунчер…",
			"Restarting launcher...": "Перезапускаем лаунчер…",
			"Update complete.": "Всё готово. Начинаем!",
			"Game is up to date.": "Ваша версия готова к игре",
			"Launcher error": "Загрузка на паузе" if _cancel_requested else "Не удалось завершить обновление"
		}
		_status_label.text = str(titles.get(title, title))
	else:
		_status_label.text = title
	_detail_label.text = detail
	_set_progress(progress, detail)

func _set_progress(progress: float, detail: String = "") -> void:
	if not detail.is_empty():
		if _is_halloween_theme_enabled():
			detail = detail.replace("Downloading game build ", "Игра · ").replace("Downloading launcher ", "Лаунчер · ").replace("MB/s", "МБ/с").replace("MB", "МБ")
			var details: Dictionary = {
				"Download complete. Checking SHA-256.": "Загрузка завершена. Проверяем целостность файла.",
				"Download complete. Unpacking game files.": "Загрузка завершена. Распаковываем игру на вашем ПК.",
				"Checking the game and Luau runtime before installation.": "Проверяем игру и Luau runtime перед установкой.",
				"Download verified. Replacing local game build.": "Файлы проверены. Устанавливаем новую версию.",
				"Launcher downloaded. Preparing the new version.": "Лаунчер загружен. Подготавливаем новую версию.",
				"A newer launcher build is available.": "Доступна новая версия лаунчера.",
				"Applying launcher update.": "Применяем обновление лаунчера.",
				"Update paused. Press Retry to continue.": "Обновление на паузе. Нажмите «Продолжить».",
				"Update paused. Your downloaded files are kept; press Retry to continue.": "Загруженные файлы сохранены. Нажмите «Продолжить».",
				"Download stalled; continuing from the last verified range.": "Связь прервалась. Продолжим с сохранённого места."
			}
			detail = str(details.get(detail, detail))
		_detail_label.text = detail
	if progress < 0.0:
		_progress_bar.value = fmod(Time.get_ticks_msec() / 18.0, 100.0)
	else:
		_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0

func _fail(message: String) -> void:
	_log_update("update_failed", message)
	var detail := message.get_slice("\n", 0).left(220)
	if not _cancel_requested:
		detail += "\nПовторить — продолжить загрузку. Варианты — переустановить игру или скачать заново."
	_set_status("Launcher error", detail, _progress_bar.value / 100.0)
	_detail_label.tooltip_text = message
	_retry_available = true
	_action_button.text = "Продолжить" if _cancel_requested else "Повторить"
	_action_button.disabled = false
	if _cancel_button != null:
		_cancel_button.visible = _cancel_requested
	if _recovery_menu != null:
		_recovery_menu.visible = not _cancel_requested
		_recovery_menu.disabled = _update_flow_running
