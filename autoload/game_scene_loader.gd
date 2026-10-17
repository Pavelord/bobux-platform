extends Node
## Keep the first game's resource/script loading off the interactive UI thread.
const MAIN_PATH := "res://scenes/main/main.tscn"
const LOBBY_PATH := "res://scenes/lobby/lobby.tscn"
var _main: PackedScene
var _requested := false
var _lobby: PackedScene
var _lobby_requested := false
var _meshes: Dictionary = {}
var _mesh_queue: Dictionary = {}
var _mesh_jobs: Dictionary = {}
var _mesh_bytes := 0
const MESH_CACHE_BYTES := 48 * 1024 * 1024
const MESH_WORKERS := 3

func _ready() -> void:
	# Headless tools/servers never enter the app shell; loading its whole UI
	# tree during a short validation can otherwise outlive the SceneTree.
	if DisplayServer.get_name() != "headless": prepare_lobby.call_deferred()

func prepare_lobby() -> void:
	if _lobby != null or _lobby_requested: return
	_lobby_requested = ResourceLoader.load_threaded_request(LOBBY_PATH, "PackedScene", true) == OK

func get_lobby() -> PackedScene:
	if _lobby != null: return _lobby
	prepare_lobby()
	if not _lobby_requested: return null
	while ResourceLoader.load_threaded_get_status(LOBBY_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if _lobby != null: return _lobby
	if ResourceLoader.load_threaded_get_status(LOBBY_PATH) != ResourceLoader.THREAD_LOAD_LOADED:
		_lobby_requested = false
		return null
	_lobby = ResourceLoader.load_threaded_get(LOBBY_PATH) as PackedScene
	return _lobby

func open_lobby() -> Error:
	var scene := await get_lobby()
	return get_tree().change_scene_to_packed(scene) if scene != null else ERR_CANT_OPEN

func _mesh_key(path: String) -> String:
	return "%s:%d:%d" % [path, FileAccess.get_modified_time(path), _file_size(path)]

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else 0

func cached_mesh(path: String) -> Mesh:
	var key := _mesh_key(path)
	if not _meshes.has(key): return null
	var entry: Dictionary = _meshes[key]
	_meshes.erase(key)
	_meshes[key] = entry
	return entry.mesh

func prepare_meshes(paths: Array[String]) -> void:
	# The dummy renderer used by dedicated servers does not initialize mesh
	# RIDs safely across loader workers. Keep resource creation on its main
	# thread, with the same cache and frame budget as the graphical client.
	if DisplayServer.get_name() == "headless":
		var slice_started := Time.get_ticks_usec()
		for path in paths:
			var key := _mesh_key(path)
			if _meshes.has(key): continue
			var mesh := ResourceLoader.load(path, "Mesh", ResourceLoader.CACHE_MODE_IGNORE) as Mesh
			if mesh != null: _store_mesh(key, path, mesh)
			if Time.get_ticks_usec() - slice_started >= 3000:
				await get_tree().process_frame
				slice_started = Time.get_ticks_usec()
		return
	var waiting: Array[String] = []
	for path in paths:
		var key := _mesh_key(path)
		if _meshes.has(key): continue
		waiting.append(key)
		if not _mesh_jobs.has(key): _mesh_queue[key] = path
	while not waiting.is_empty():
		await get_tree().process_frame
		for key in waiting.duplicate():
			if not _mesh_jobs.has(key) and not _mesh_queue.has(key): waiting.erase(key)

func _process(_delta: float) -> void:
	if _lobby_requested and _lobby == null:
		var status := ResourceLoader.load_threaded_get_status(LOBBY_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_lobby = ResourceLoader.load_threaded_get(LOBBY_PATH) as PackedScene
			_lobby_requested = false
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_lobby_requested = false
	for key in _mesh_jobs.keys():
		var path: String = _mesh_jobs[key]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		_mesh_jobs.erase(key)
		if status != ResourceLoader.THREAD_LOAD_LOADED: continue
		var mesh := ResourceLoader.load_threaded_get(path) as Mesh
		if mesh == null: continue
		_store_mesh(key, path, mesh)
	while _mesh_jobs.size() < MESH_WORKERS and not _mesh_queue.is_empty():
		var key: String = _mesh_queue.keys()[0]
		var path: String = _mesh_queue[key]
		_mesh_queue.erase(key)
		if ResourceLoader.load_threaded_request(path, "Mesh", false, ResourceLoader.CACHE_MODE_IGNORE) == OK:
			_mesh_jobs[key] = path

func _store_mesh(key: String, path: String, mesh: Mesh) -> void:
	preload("res://addons/roblox_runtime/roblox_shader_cache.gd").share_mesh_programs(mesh)
	var size := _file_size(path)
	if size > MESH_CACHE_BYTES: return
	if _meshes.has(key):
		_mesh_bytes -= int(_meshes[key].bytes)
		_meshes.erase(key)
	while _mesh_bytes + size > MESH_CACHE_BYTES and not _meshes.is_empty():
		var oldest: String = _meshes.keys()[0]
		_mesh_bytes -= int(_meshes[oldest].bytes)
		_meshes.erase(oldest)
	_meshes[key] = {"mesh": mesh, "bytes": size}
	_mesh_bytes += size

func prepare_main() -> void:
	if _main != null or _requested: return
	_requested = ResourceLoader.load_threaded_request(MAIN_PATH, "PackedScene", true) == OK

func get_main() -> PackedScene:
	if _main != null: return _main
	prepare_main()
	if not _requested: return null
	while ResourceLoader.load_threaded_get_status(MAIN_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(MAIN_PATH) != ResourceLoader.THREAD_LOAD_LOADED:
		_requested = false
		return null
	_main = ResourceLoader.load_threaded_get(MAIN_PATH) as PackedScene
	return _main

func open_main() -> Error:
	var scene := await get_main()
	return get_tree().change_scene_to_packed(scene) if scene != null else ERR_CANT_OPEN
