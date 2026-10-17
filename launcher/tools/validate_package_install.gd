extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Provide the manifest JSON and its local game ZIP after --.")
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not manifest is Dictionary:
		quit(1)
		return
	var launcher = load("res://tools/fixtures/download_launcher.gd").new()
	root.add_child(launcher)
	var folder: String = OS.get_user_data_dir().path_join("release_package_contract_%d" % OS.get_process_id())
	launcher._install_root = folder
	launcher._game_dir = folder.path_join("Game")
	launcher._temp_dir = folder.path_join("_download")
	launcher._staging_dir = folder.path_join("_staging_game")
	launcher._game_backup_dir = folder.path_join("_backup_game")
	DirAccess.make_dir_recursive_absolute(launcher._temp_dir)
	var archive: String = launcher._temp_dir.path_join("game_%s.zip" % launcher._hash_suffix(str(manifest.sha256)))
	var copied: Error = DirAccess.copy_absolute(args[1], archive)
	assert(copied == OK, "copy staged package")
	var first_result: Dictionary = await launcher._download_and_install(manifest)
	print("RELEASE_PACKAGE_INSTALL " + JSON.stringify(first_result))
	assert(bool(first_result.get("ok", false)), "real release ZIP must install")
	launcher._write_local_version(manifest)
	assert(launcher._is_game_install_usable(manifest), "repeated launch uses the exact installed build")
	assert(launcher._get_local_game_build() == int(manifest.build), "actual build marker")
	# Recover a marker that antivirus, an older launcher or the user removed.
	DirAccess.remove_absolute(folder.path_join("version.json"))
	DirAccess.remove_absolute(launcher._game_dir.path_join("version.json"))
	assert(launcher._is_game_install_usable(manifest), "lost marker adopts matching executable and required runtime")
	print("LAUNCHER_RELEASE_PACKAGE_OK: actual ZIP, executable + required runtime SHA-256, repeated launch, missing marker")
	launcher._delete_recursive_absolute(folder)
	launcher.queue_free()
	quit(0)
