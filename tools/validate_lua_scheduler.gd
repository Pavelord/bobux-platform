extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine := root.get_node_or_null("LuaScriptEngine")
	if engine == null:
		push_error("LuaScriptEngine autoload is missing")
		quit(1)
		return
	var host := Node.new()
	host.name = "Workspace"
	host.set_meta("roblox_class", "Workspace")
	root.add_child(host)
	var remote := Node.new()
	remote.name = "Remote"
	remote.set_meta("roblox_class", "RemoteEvent")
	host.add_child(remote)
	var server_script := Node.new()
	server_script.name = "ServerScript"
	server_script.set_meta("roblox_class", "Script")
	host.add_child(server_script)
	var client_script := Node.new()
	client_script.name = "ClientScript"
	client_script.set_meta("roblox_class", "LocalScript")
	host.add_child(client_script)

	var server_result: Dictionary = engine.start_script(
		"print(script.Parent.Remote.OnServerEvent)\nlocal connection = script.Parent.Remote.OnServerEvent:Connect(function(value) print(value); script.Parent.Value = value end)\nprint(connection)\nwait(0.02)\nscript.Parent.Ready = true",
		server_script,
		{"realm": "server", "is_server": true}
	)
	var client_result: Dictionary = engine.start_script(
		"wait(0.01)\nscript.Parent.Remote:FireServer(7)",
		client_script,
		{"realm": "client", "is_server": false}
	)
	print("server_result=", server_result, " client_result=", client_result)
	var registry: Dictionary = remote.get_meta("_bobux_event_registry", {})
	print("remote events=", registry.keys(), " server_connections=", (registry.get("OnServerEvent") as Object).connections.size() if registry.get("OnServerEvent") != null else -1)
	for _frame in range(8):
		await process_frame
		await create_timer(0.015).timeout
		engine._process(0.015)
	var ok := bool(server_result.get("ok", false)) and bool(client_result.get("ok", false))
	ok = ok and int(host.get_meta("value", 0)) == 7 and bool(host.get_meta("Ready", false))
	print("[validate_lua_scheduler] ok=", ok, " value=", host.get_meta("value") if host.has_meta("value") else null, " ready=", host.get_meta("Ready") if host.has_meta("Ready") else null, " runtimes=", engine._script_runtimes.size())
	engine.stop_all_scripts(host)
	quit(0 if ok else 1)
