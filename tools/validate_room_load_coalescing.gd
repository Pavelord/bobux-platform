extends SceneTree
var results: Array = []
func _initialize() -> void: call_deferred("_run")
func collect(host: Node, room: String, state: Dictionary) -> void:
	results.append(await host._ensure_server_room_runtime(room, state))
func _run() -> void:
	var host: Node = load("res://scenes/main/main.tscn").instantiate()
	var fixture := GDScript.new()
	fixture.source_code = """extends "res://scripts/main/main.gd"
var loads := 0
func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func _exit_tree() -> void: pass
func _prepare_server_room_runtime(room_id: String, room_state: Dictionary) -> Dictionary:
	loads += 1
	await get_tree().process_frame
	await get_tree().process_frame
	return {"ok": room_state.get("ok", true), "room_id": room_id}
"""
	assert(fixture.reload() == OK)
	host.set_script(fixture)
	root.add_child(host)
	collect(host, "one", {})
	collect(host, "one", {})
	collect(host, "two", {"ok": false})
	assert(host.loads == 2)
	while results.size() < 3: await process_frame
	assert(results.filter(func(row): return row.ok).size() == 2)
	assert(host._room_runtime_preparations.is_empty())
	assert((await host._ensure_server_room_runtime("two", {})).ok)
	assert(host.loads == 3)
	host.queue_free()
	await process_frame
	print("ROOM_LOAD_COALESCING_OK: shared load, independent rooms, failed load retry")
	quit(0)

