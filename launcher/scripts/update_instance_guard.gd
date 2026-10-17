extends RefCounted

# The socket is an OS-owned lease: crashes release it without stale lock files.
# Every operation touching the shared download/staging folders holds this lease.
var _server: TCPServer = null
var _clients: Array[Dictionary] = []
var _instance_key: String = ""

func acquire(install_root: String, tree: SceneTree) -> Dictionary:
	if _server != null and _server.is_listening():
		return {"ok": true}
	# The helper bridges the old process exiting and the replacement taking
	# the TCP lease. Only that replacement's nonce may touch shared staging.
	var status_path: String = install_root.path_join("_launcher_self_update_status.json")
	if FileAccess.file_exists(status_path):
		var status: Variant = JSON.parse_string(FileAccess.get_file_as_string(status_path))
		if status is Dictionary and str(status.get("phase", "")) in ["helper_ready", "applying", "starting_visible_launcher"]:
			var nonce: String = str(status.get("nonce", ""))
			var helper_pid: int = int(status.get("helper_pid", 0))
			var age: float = Time.get_unix_time_from_system() - float(Time.get_unix_time_from_datetime_string(str(status.get("time", "")).left(19)))
			var started_ticks: String = str(status.get("helper_started_ticks", ""))
			if nonce.length() == 32 and helper_pid > 0 and age >= -5.0 and age < 240.0 and await _helper_is_alive(helper_pid, started_ticks, tree):
				if not OS.get_cmdline_user_args().has("--launcher-handoff=" + nonce):
					return {"ok": true, "secondary": true, "handoff_pending": true}
	var canonical: String = ProjectSettings.globalize_path(install_root).replace("\\", "/").simplify_path().to_lower()
	_instance_key = canonical.sha256_text()
	var port: int = 40000 + _instance_key.substr(0, 6).hex_to_int() % 12000
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(port, "127.0.0.1")
	if listen_error == OK:
		return {"ok": true}
	_server = null
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var deadline: int = Time.get_ticks_msec() + 6000
	var sent := false
	var response := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				peer.put_data((JSON.stringify({"instance": _instance_key, "activate": true}) + "\n").to_utf8_buffer())
				sent = true
			if peer.get_available_bytes() > 0:
				response += peer.get_utf8_string(peer.get_available_bytes())
				if response.contains("\n"):
					var reply: Variant = JSON.parse_string(response.get_slice("\n", 0))
					peer.disconnect_from_host()
					if reply is Dictionary and str(reply.get("instance", "")) == _instance_key:
						return {"ok": true, "secondary": true}
					break
		elif peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			break
		await tree.process_frame
	peer.disconnect_from_host()
	return {"ok": false, "error": "Другой лаунчер ещё работает. Закройте его окно и повторите. Загрузка сохранена."}

func _helper_is_alive(pid: int, started_ticks: String, tree: SceneTree) -> bool:
	if OS.get_name() != "Windows":
		return OS.is_process_running(pid)
	if not started_ticks.is_valid_int():
		return false
	# Godot's Windows process table only reliably knows children it created.
	# A second launcher must verify the foreign helper and reject reused PIDs.
	var query: String = "try { $p=[Diagnostics.Process]::GetProcessById(%d); if ($p.ProcessName -ieq 'powershell' -and $p.StartTime.ToUniversalTime().Ticks.ToString() -eq '%s' -and -not $p.HasExited) { exit 0 }; exit 1 } catch { exit 1 }" % [pid, started_ticks]
	var worker := Thread.new()
	if worker.start(_query_helper_process.bind(query)) != OK:
		return false
	while worker.is_alive():
		await tree.process_frame
	return int(worker.wait_to_finish()) == 0

func _query_helper_process(query: String) -> int:
	var output: Array = []
	return OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", query]), output, true, false)

func pump(window: Window) -> void:
	if _server == null or not _server.is_listening():
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "text": "", "expires": Time.get_ticks_msec() + 6000})
	for index in range(_clients.size() - 1, -1, -1):
		var entry: Dictionary = _clients[index]
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() > int(entry.expires):
			peer.disconnect_from_host()
			_clients.remove_at(index)
			continue
		var bytes: int = peer.get_available_bytes()
		if bytes <= 0:
			continue
		entry.text = str(entry.text) + peer.get_utf8_string(mini(bytes, 4096))
		if str(entry.text).length() > 4096:
			peer.disconnect_from_host()
			_clients.remove_at(index)
			continue
		if not str(entry.text).contains("\n"):
			continue
		var request: Variant = JSON.parse_string(str(entry.text).get_slice("\n", 0))
		if request is Dictionary and str(request.get("instance", "")) == _instance_key:
			peer.put_data((JSON.stringify({"instance": _instance_key, "pid": OS.get_process_id()}) + "\n").to_utf8_buffer())
			if window != null and DisplayServer.get_name() != "headless":
				if window.mode == Window.MODE_MINIMIZED:
					window.mode = Window.MODE_WINDOWED
				window.grab_focus()
		_clients.remove_at(index)

func release() -> void:
	if _server != null:
		_server.stop()
	_server = null
	for entry in _clients:
		(entry.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
