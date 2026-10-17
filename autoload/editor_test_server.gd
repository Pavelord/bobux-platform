extends Node
## F5 uses this checkout's authoritative runtime instead of impersonating an
## older production protocol. Exported clients keep their normal live routing.
const SERVER_SCRIPT := "res://server/editor_test_server.gd"
const START_TIMEOUT_MSEC := 15000
var _child_pid := -1
var _port := 0
var _ready_path := ""
var _launching := false
var _generation := 0
var _lease_written_at := 0
var _status: Label
var session_active := false
var last_error := ""

func is_local_server_process() -> bool:
	return OS.has_feature("editor") and OS.get_cmdline_user_args().has("--bobux-editor-test-server")

func external_debug_endpoint() -> String:
	if not OS.is_debug_build(): return ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bobux-dev-server="):
			var endpoint := argument.trim_prefix("--bobux-dev-server=").strip_edges()
			# adb reverse exposes only loopback. A debug switch cannot silently
			# redirect accounts to a third-party public endpoint.
			return _validated_debug_endpoint(endpoint)
	return ""

func _validated_debug_endpoint(endpoint: String) -> String:
	if not endpoint.begins_with("ws://"): return ""
	# Check the authority, not a prefix: 127.0.0.1:123@remote.example is
	# user information for a remote host, not a loopback address.
	var authority := endpoint.trim_prefix("ws://").get_slice("/", 0)
	var host_port := authority.split(":")
	if host_port.size() != 2 or host_port[0] not in ["127.0.0.1", "localhost"]: return ""
	if not host_port[1].is_valid_int(): return ""
	var port := int(host_port[1])
	if port < 1 or port > 65535: return ""
	return endpoint

func should_route(url: String = "") -> bool:
	if is_local_server_process() or GameState.is_dedicated_server_runtime(): return false
	if not external_debug_endpoint().is_empty(): return true
	if not OS.has_feature("editor"): return false
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--bobux-live-server"): return false
	if DisplayServer.get_name() == "headless" and not arguments.has("--bobux-editor-test-client"): return false
	# Explicit loopback fixtures already select their own compatible server.
	return not url.begins_with("ws://127.0.0.1:") and not url.begins_with("ws://localhost:")

func _ready() -> void:
	if is_local_server_process(): return
	var layer := CanvasLayer.new()
	layer.layer = 145
	add_child(layer)
	_status = Label.new()
	_status.text = "Локальный тестовый сервер"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.position = Vector2(16, 74)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("ffab64"))
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_status)
	_status.hide()

func _process(_delta: float) -> void:
	if _child_pid > 0 and Time.get_ticks_msec() - _lease_written_at >= 1000:
		_write_parent_lease()
	if _status != null:
		_status.visible = session_active and is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == "res://scenes/main/main.tscn"

func ensure_endpoint() -> String:
	last_error = ""
	var endpoint := external_debug_endpoint()
	if not endpoint.is_empty(): return endpoint
	if not OS.has_feature("editor"):
		last_error = "Тестовый сервер доступен только из проекта Godot."
		return ""
	while _launching:
		await get_tree().process_frame
	if _child_pid > 0 and OS.is_process_running(_child_pid) and FileAccess.file_exists(_ready_path):
		return "ws://127.0.0.1:%d/ws" % _port
	_shutdown_child()
	_launching = true
	_generation += 1
	var token := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var base_port := 19000 + OS.get_process_id() % 10000
	for offset in 64:
		var socket := TCPServer.new()
		if socket.listen(base_port + offset, "127.0.0.1") == OK:
			_port = base_port + offset
			socket.stop()
			break
	if _port == 0:
		last_error = "Не удалось найти свободный порт локального сервера."
		_launching = false
		return ""
	var directory := "user://editor_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_ready_path = ProjectSettings.globalize_path(directory.path_join(token + ".ready"))
	_write_parent_lease()
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(directory.path_join(token + ".log")), "--script", SERVER_SCRIPT, "--", "--bobux-editor-test-server", "--dev-port=%d" % _port, "--dev-parent=%d" % OS.get_process_id(), "--dev-ready=" + _ready_path])
	# Godot open_console=false keeps the child hidden on Windows.
	_child_pid = OS.create_process(OS.get_executable_path(), arguments, false)
	var deadline := Time.get_ticks_msec() + START_TIMEOUT_MSEC
	while _child_pid > 0 and OS.is_process_running(_child_pid) and not FileAccess.file_exists(_ready_path) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	_launching = false
	if _child_pid <= 0 or not OS.is_process_running(_child_pid) or not FileAccess.file_exists(_ready_path):
		last_error = "Локальный сервер не запустился. Журнал: user://editor_test/" + token + ".log"
		_shutdown_child()
		return ""
	return "ws://127.0.0.1:%d/ws" % _port

func _shutdown_child() -> void:
	# Only a PID returned by this instance's create_process is ever terminated.
	if _child_pid > 0 and OS.is_process_running(_child_pid): OS.kill(_child_pid)
	_child_pid = -1
	_port = 0
	if not _ready_path.is_empty() and FileAccess.file_exists(_ready_path): DirAccess.remove_absolute(_ready_path)
	if not _ready_path.is_empty() and FileAccess.file_exists(_ready_path + ".lease"): DirAccess.remove_absolute(_ready_path + ".lease")
	_ready_path = ""

func _write_parent_lease() -> void:
	if _ready_path.is_empty(): return
	var lease := FileAccess.open(_ready_path + ".lease", FileAccess.WRITE)
	if lease != null: lease.store_string(str(Time.get_unix_time_from_system()))
	_lease_written_at = Time.get_ticks_msec()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_child()
