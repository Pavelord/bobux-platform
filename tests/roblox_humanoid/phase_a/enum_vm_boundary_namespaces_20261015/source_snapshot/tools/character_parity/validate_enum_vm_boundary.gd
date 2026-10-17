extends SceneTree

const REGISTRY = preload("res://addons/roblox_runtime/enums/roblox_enum_registry.gd")
const BOUNDARY = preload("res://addons/roblox_runtime/enums/roblox_enum_vm_boundary.gd")
const SOURCE := "res://tools/character_parity/enum_vm_contract.luau"
const CYCLIC_SOURCE := "res://tools/character_parity/enum_vm_cyclic_contract.luau"
const EDGE_SOURCE := "res://tools/character_parity/enum_vm_humanoid_edges_contract.luau"
var checks: Array[Dictionary] = []
var errors: Array[String] = []

func _initialize() -> void: run.call_deferred()

func record(label: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": label, "status": "PASS" if ok else "FAIL", "detail": detail})
	print("[enum-vm] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])

func lua_check(lua: Variant, label: String, source: String) -> void:
	var problem: Variant = lua.do_string(source)
	record(label, problem == null, str(problem.get_message()) if problem != null else "")

func vm_for(engine: Node, result: Dictionary) -> Variant:
	var id := int(result.get("runtime_id", -1))
	return engine._script_runtimes.get(id, engine._retained_lua_states.get(id, {})).get("lua")

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	engine.script_message.connect(func(context: Node, message: String, is_error: bool):
		if is_error and is_instance_valid(context) and str(context.name).begins_with("EnumVm"):
			errors.append(message)
	)
	var world := Node3D.new()
	world.name = "EnumVmWorkspace"
	world.set_meta("roblox_class", "Workspace")
	world.set_meta("roblox_stud_scale", 1.0)
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.set_meta("bobux_studio_playtest", true)
	player.set_meta("bobux_workspace_instance_id", world.get_instance_id())
	world.add_child(player)
	player.set_physics_process(false)
	engine.bind_local_player_character(player)
	var humanoid := player.get_node("Humanoid")
	player.request_humanoid_state(8)
	var module := Node.new()
	module.name = "RoomModule"
	module.set_meta("roblox_class", "ModuleScript")
	module.set_meta("code", """
local m={count=0}
function m.get(h) return h:GetState() end
function m.connect(h,fn) return h.StateChanged:Connect(fn) end
function m.coroutine(h,fn)
    local c=coroutine.create(function() coroutine.yield();fn(h:GetState()) end)
    assert(coroutine.resume(c));assert(coroutine.resume(c))
end
return m
""")
	world.add_child(module)
	var contexts: Array[Node] = []
	for name_ in ["EnumVmLegacy", "EnumVmParity"]:
		var context := Node.new()
		context.name = name_
		world.add_child(context)
		contexts.append(context)
	var reserved_before: int = engine._next_script_runtime_id
	var pending_before: int = engine._pending_script_starts.size()
	for profile in ["", "TypoParity", null, 77, false]:
		var invalid: Dictionary = engine.start_script("error('must not run')", contexts[0], {"enum_profile": profile, "defer_compilation": true})
		record("reject invalid profile %s before allocation" % str(profile), not invalid.get("ok", true) and engine._next_script_runtime_id == reserved_before and engine._pending_script_starts.size() == pending_before)
	var source := FileAccess.get_file_as_string(SOURCE)
	var legacy: Dictionary
	var parity: Dictionary
	if OS.get_cmdline_user_args().has("--parity-first"):
		parity = engine.run_script(source.replace("PROFILE_PARITY", "true"), contexts[1], {"enum_profile": REGISTRY.ROBLOX_PARITY_ENUM_ITEM})
		legacy = engine.run_script(source.replace("PROFILE_PARITY", "false"), contexts[0])
	else:
		legacy = engine.run_script(source.replace("PROFILE_PARITY", "false"), contexts[0])
		parity = engine.run_script(source.replace("PROFILE_PARITY", "true"), contexts[1], {"enum_profile": REGISTRY.ROBLOX_PARITY_ENUM_ITEM})
	record("actual scheduled legacy VM started", legacy.get("ok", false), str(legacy))
	record("actual scheduled parity VM started", parity.get("ok", false), str(parity))
	for frame in 120:
		if contexts[0].get_meta("attribute_TasksDone", false) and contexts[1].get_meta("attribute_TasksDone", false): break
		await process_frame
	var a: Variant = vm_for(engine, legacy)
	var b: Variant = vm_for(engine, parity)
	record("both scripts reached listeners", contexts[0].get_meta("attribute_Ready", false) and contexts[1].get_meta("attribute_Ready", false))
	if a == null or b == null:
		finish(engine, world)
		return
	var wrapper: Variant = humanoid.get_meta("_bobux_instance_wrapper")
	a.push_variant("shared_actual_humanoid", wrapper)
	b.push_variant("shared_actual_humanoid", wrapper)
	lua_check(a, "legacy uses shared actual BobuxInstance and event", "assert(rawequal(saved.h,shared_actual_humanoid),'wrapper mismatch');assert(rawequal(saved.h.StateChanged,shared_actual_humanoid.StateChanged),'event userdata mismatch')")
	lua_check(b, "parity uses the same actual BobuxInstance and event", "assert(rawequal(saved.h,shared_actual_humanoid),'wrapper mismatch');assert(rawequal(saved.h.StateChanged,shared_actual_humanoid.StateChanged),'event userdata mismatch')")
	lua_check(a, "legacy actual callbacks/modules/coroutines/tasks", "check_tasks()")
	lua_check(b, "parity actual callbacks/modules/coroutines/tasks", "check_tasks()")
	lua_check(b, "cyclic operands keys writes method arguments and ignored extras stay Lua-side", FileAccess.get_file_as_string(CYCLIC_SOURCE))
	record("all 94 cyclic-boundary assertions executed", contexts[1].get_meta("attribute_CyclicChecks", 0) == 94, str(contexts[1].get_meta("attribute_CyclicChecks", 0)))
	lua_check(b, "native enabled-string and extracted-receiver contract", FileAccess.get_file_as_string(EDGE_SOURCE))
	await create_timer(0.08).timeout
	record("native edge contract completes including quiet event window", contexts[1].get_meta("attribute_NativeEdgesDone", false) and contexts[1].get_meta("attribute_NativeEdgeChecks", 0) == 95, str(contexts[1].get_meta("attribute_NativeEdgeChecks", 0)))
	var registry_b: Variant = b.get_meta(REGISTRY.VM_OWNER_META)
	var owner_b: Variant = b.get_meta(BOUNDARY.OWNER_META)
	var registry_weak: WeakRef = weakref(registry_b)
	var owner_weak: WeakRef = weakref(owner_b)
	registry_b = null
	owner_b = null
	lua_check(b, "canonical state setter zero returns and scalar backend", "assert(select('#',saved.h:SetStateEnabled(Enum.HumanoidStateType.Jumping,false))==0);assert(not saved.h:GetStateEnabled(3));assert(select('#',saved.h:SetStateEnabled('Jumping',true))==0)")
	record("internal Humanoid stores bool under scalar state key", humanoid.get_meta("bobux_state_enabled_3", false) == true and not humanoid.has_meta("enum_profile"))
	lua_check(b, "canonical ChangeState calls actual motor and returns no values", "assert(select('#',saved.h:ChangeState(Enum.HumanoidStateType.Freefall))==0)")
	await create_timer(0.04).timeout
	record("both Wait paths receive converted arguments", contexts[0].get_meta("attribute_EnabledWait", false) and contexts[1].get_meta("attribute_EnabledWait", false))
	lua_check(a, "legacy event arguments remain numbers", "check_events(1);check_profile()")
	lua_check(b, "parity Connect extracted lowercase Once Wait module arguments", "check_events(1);check_profile()")
	# A second scalar emission proves Once/Wait are not subscribed twice.
	engine._fire_existing_runtime_event(humanoid, "StateChanged", [8, 5])
	wrapper.Changed.FireArgs([3, false, null])
	await create_timer(0.02).timeout
	record("Connect and Wait preserve raw interior false and trailing nil", contexts[0].get_meta("attribute_TrailingNilConnect", false) and contexts[0].get_meta("attribute_TrailingNilWait", false) and contexts[1].get_meta("attribute_TrailingNilConnect", false) and contexts[1].get_meta("attribute_TrailingNilWait", false))
	lua_check(a, "legacy Once/Wait exactly once", "check_events(2);disconnect_all()")
	lua_check(b, "parity Once/Wait exactly once", "check_events(2)")
	# Cross-VM callbacks re-enter B through A while B's signal callback lives.
	var cross_log: Array[String] = []
	a.push_variant("__cross_to_b", engine._owned_lua_bindings(func() -> Variant:
		var result: Variant = b.do_string("check_profile();cross_returned=true")
		cross_log.append("A to B: " + engine._lua_error_message(result))
		return result
	))
	b.push_variant("__cross_to_a", engine._owned_lua_bindings(func() -> Variant:
		var result: Variant = a.do_string("check_profile();__cross_to_b()")
		cross_log.append("B to A: " + engine._lua_error_message(result))
		return result
	))
	lua_check(b, "install actual nested callback B to A to B", "task.spawn(function() saved.connections[#saved.connections+1]=saved.h.StateChanged:Once(function() __cross_to_a() end) end)")
	engine._fire_existing_runtime_event(humanoid, "StateChanged", [8, 5])
	await create_timer(0.06).timeout
	lua_check(b, "nested callback preserves both VM profiles", "assert(cross_returned==true);check_profile()")
	record("cross callbacks reached both native VM hooks", cross_log.size() == 2 and cross_log[0] == "A to B: " and cross_log[1] == "B to A: ", str(cross_log))
	lua_check(a, "Disconnect prevents subsequent legacy event delivery", "check_events(2)")
	# Remove host hooks so the fixture itself does not hold another VM alive.
	a.push_variant("__cross_to_b", null)
	b.push_variant("__cross_to_a", null)
	lua_check(b, "Once churn starts in actual scheduled coroutine", "task.spawn(function() local count=0;local signal=saved.h.StateEnabledChanged;for i=1,256 do signal:Once(function(item,enabled) assert(typeof(item)=='EnumItem' and enabled==true);count+=1 end);saved.h:SetStateEnabled(Enum.HumanoidStateType.Jumping,true);if i%8==0 then task.wait(0) end end;assert(count==256);collectgarbage('collect');script:SetAttribute('ChurnDone',true) end)")
	for frame in 120:
		if contexts[1].get_meta("attribute_ChurnDone", false): break
		await process_frame
	record("Once churn executes all 256 callbacks", contexts[1].get_meta("attribute_ChurnDone", false))
	var churn_owner: Variant = b.get_meta(BOUNDARY.OWNER_META)
	record("VM owner does not retain unbounded Once history", churn_owner._connections.size() < 80, str(churn_owner._connections.size()))
	churn_owner = null
	lua_check(b, "drop namespace and collect GC retains VM registry", "kept=Enum.HumanoidStateType.Freefall;Enum=nil;collectgarbage('collect');assert(saved.h:GetState()==kept)")
	a = null
	engine.stop_script(int(legacy.runtime_id))
	await process_frame
	engine.release_stopped_script_states()
	lua_check(b, "closing legacy VM leaves parity profile live", "check_profile();assert(saved.h:GetState()==kept)")
	var event: Variant = wrapper._shared_event("StateChanged")
	var connections_before: int = event.connections.size()
	b = null
	engine.stop_script(int(parity.runtime_id))
	record("Stop disconnects parity listeners on sibling Humanoid", connections_before > 0 and event.connections.is_empty())
	await process_frame
	engine.release_stopped_script_states()
	await process_frame
	record("parity VM teardown releases registry and adapter", registry_weak.get_ref() == null and owner_weak.get_ref() == null)
	# Queued profile survives the deferred compile and its source cache path.
	var queued := Node.new()
	queued.name = "EnumVmQueued"
	world.add_child(queued)
	var deferred: Dictionary = engine.start_script("assert(typeof(Enum.HumanoidStateType.Jumping)=='EnumItem');script:SetAttribute('Done',true)", queued, {"enum_profile": REGISTRY.ROBLOX_PARITY_ENUM_ITEM, "defer_compilation": true})
	await create_timer(0.04).timeout
	record("deferred start retains immutable opt-in profile", deferred.get("ok", false) and queued.get_meta("attribute_Done", false))
	finish(engine, world)

func finish(engine: Node, world: Node) -> void:
	record("no Luau runtime errors", errors.is_empty(), str(errors))
	engine.stop_all_scripts(world)
	world.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	var failed := 0
	for check in checks:
		if check.status == "FAIL": failed += 1
	var destination := "res://.codex-tmp/character_parity/enum-vm-boundary-report.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): destination = arg.trim_prefix("--report=")
	if FileAccess.file_exists(destination):
		push_error("Refusing to overwrite report; use --report=<fresh path>")
		quit(2)
		return
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"scope": "opt-in production Humanoid EnumItem VM boundary", "pass": checks.size()-failed, "fail": failed, "checks": checks, "open": ["complete enum namespace", "other enum properties", "native opaque strings and bool/receiver coercion", "tagged wire codec and version negotiation", "Humanoid physical calibration"]}, "\t"))
	print("[enum-vm] PASS=%d FAIL=%d" % [checks.size()-failed, failed])
	quit(0 if failed == 0 else 1)
