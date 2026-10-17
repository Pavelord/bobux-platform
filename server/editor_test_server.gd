extends SceneTree
## Deliberately separate from production's registry/heartbeat bootstrap.
## Real main scene, map loading and Luau execute with the current checkout.
var _parent_pid := 0
var _ready_path := ""
var _server_port := 0
var _watchdog: Timer

func _initialize() -> void: _boot.call_deferred()

func _option(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return ""

func _boot() -> void:
	if not OS.has_feature("editor") or not OS.get_cmdline_user_args().has("--bobux-editor-test-server"):
		push_error("Editor test server requires the explicit development flag and Godot project executable.")
		quit(2)
		return
	_server_port = int(_option("--dev-port="))
	_parent_pid = int(_option("--dev-parent="))
	_ready_path = _option("--dev-ready=")
	if _server_port < 1024 or _server_port > 65535 or _parent_pid <= 0 or _ready_path.is_empty():
		push_error("Invalid editor server launch arguments.")
		quit(2)
		return
	# Service credentials are never used by this development process, even if
	# the parent's environment contains deployment variables.
	for key in ["BOBUX_SERVICE_KEY", "BOBUX_SERVER_HEARTBEAT_TOKEN", "ROBLOXCLONE_CLOUD_API_KEY", "ROBLOXCLONE_CLOUD_BEARER"]:
		OS.set_environment(key, "")
	# Autoloads share the editor's cache directory and may have read its saved
	# login before this script's deferred boot. Forget credentials in memory
	# only; never delete or overwrite the parent's account files.
	var cloud := root.get_node("CloudAPI")
	cloud._clear_auth_session(false)
	cloud.bearer_token = ""
	cloud.api_key = cloud.DEFAULT_PUBLISHABLE_KEY
	root.get_node("UserSession").is_logged_in = false
	root.get_node("GameState").configure_dedicated_server(_server_port, "classic")
	var network := root.get_node("NetworkManager")
	network.hosting_started.connect(_on_listening)
	network.connection_failed.connect(func(message): push_error(message); quit(1))
	_watchdog = Timer.new()
	_watchdog.wait_time = 1.0
	root.add_child(_watchdog)
	_watchdog.timeout.connect(func():
		# Windows OS.is_process_running tracks owned child handles and cannot
		# reliably inspect an unowned parent PID. A private lease also covers
		# abrupt F8/editor termination, without trusting a recycled PID.
		if not OS.get_cmdline_user_args().has("--dev-standalone") and (not FileAccess.file_exists(_ready_path + ".lease") or Time.get_unix_time_from_system() - FileAccess.get_modified_time(_ready_path + ".lease") > 12):
			network.disconnect_from_session()
			quit())
	_watchdog.start()
	change_scene_to_file("res://scenes/main/main.tscn")

func _on_listening(_port: int, _ip: String, _upnp: bool) -> void:
	var ready := FileAccess.open(_ready_path, FileAccess.WRITE)
	if ready == null: quit(1); return
	var cloud := root.get_node("CloudAPI")
	ready.store_string(JSON.stringify({
		"pid": OS.get_process_id(),
		"bind_address": "127.0.0.1",
		"protocol_version": root.get_node("NetworkManager").NETWORK_PROTOCOL_VERSION,
		"service_credentials": cloud.has_server_service_role(),
		"account_credentials": cloud.has_authenticated_session() or not cloud.bearer_token.is_empty() or not cloud._auth_refresh_token.is_empty(),
		"runtime_name": root.get_node("LuaScriptEngine")._lua.get_runtime_name(),
	}))
	ready.close()
	print("[EditorTestServer] Current-project authoritative runtime on 127.0.0.1:", _server_port, "; no production registry or heartbeat")
