extends SceneTree
func _initialize() -> void:
	var launcher = load("res://scripts/launcher.gd").new()
	var folder := OS.get_user_data_dir().path_join("launcher_contract_test_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder.path_join("Game"))
	launcher._install_root = folder
	launcher._game_dir = folder.path_join("Game")
	var bytes := PackedByteArray()
	bytes.resize(11 * 1024 * 1024)
	bytes.fill(42)
	var file := FileAccess.open(folder.path_join("Game/Bobux.exe"), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var manifest := {"version": "0.1.99", "build": 99, "embedded_pck": true, "executable_size": bytes.size(), "executable_sha256": launcher._sha256_file(folder.path_join("Game/Bobux.exe"))}
	launcher._current_manifest = manifest
	assert(launcher._is_game_install_usable(manifest)) # Lost marker, same complete build.
	assert(launcher._get_local_game_build() == 99)
	assert(launcher._is_game_install_usable(manifest)) # Second launch must not download.
	manifest["executable_sha256"] = "bad-hash"
	assert(not launcher._is_game_install_usable(manifest))
	for path in ["Game/Bobux.exe", "Game/version.json", "version.json"]:
		DirAccess.remove_absolute(folder.path_join(path))
	DirAccess.remove_absolute(folder.path_join("Game"))
	DirAccess.remove_absolute(folder)
	launcher.free()
	print("LAUNCHER_INSTALL_CONTRACT_OK: missing marker, repeated launch, changed binary")
	quit(0)
