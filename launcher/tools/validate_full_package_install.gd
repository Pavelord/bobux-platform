extends SceneTree

var failures: Array[String] = []
var install_root: String
var base_url: String
func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	print("[full-package] ", "PASS " if ok else "FAIL ", detail)
	if not ok: failures.append(detail)

func create_launcher() -> Control:
	var launcher: Control = load("res://tools/fixtures/full_package_launcher.gd").new()
	launcher._install_root = install_root
	launcher._game_dir = install_root.path_join("Game")
	launcher._temp_dir = install_root.path_join("_download")
	launcher._staging_dir = install_root.path_join("_staging_game")
	launcher._game_backup_dir = install_root.path_join("_backup_game")
	launcher._launcher_staging_dir = install_root.path_join("_staging_launcher")
	root.add_child(launcher)
	return launcher

func counts(launcher: Control) -> Dictionary:
	var result: Dictionary = await launcher._http_get_json(base_url + "/counts", "fixture counts")
	return result.get("data", {})

func run() -> void:
	install_root = OS.get_environment("BOBUX_FULL_PACKAGE_INSTALL_ROOT")
	base_url = OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL")
	if not install_root.replace("\\", "/").contains(".codex-tmp/") or not base_url.begins_with("http://127.0.0.1:"):
		push_error("Full-package contract requires isolated .codex-tmp and loopback HTTP")
		quit(2)
		return
	ProjectSettings.set_setting("launcher/build", 99999) # This contract exercises game installation only.
	ProjectSettings.set_setting("launcher/file_retry_seconds", 0.5)
	var launcher := create_launcher()
	if OS.get_cmdline_user_args().has("--secondary"):
		if not launcher.has_method("_acquire_instance_guard"):
			check(false, "cross-process instance guard is available")
		else:
			var guard: Dictionary = await launcher._acquire_instance_guard()
			check(bool(guard.get("secondary", false)), "a second launcher process delegates to the current updater")
		print("FULL_PACKAGE_SECONDARY_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
		launcher.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	var reply: Dictionary = await launcher._http_get_json(base_url + "/manifest", "fixture metadata")
	var manifest: Dictionary = reply.get("data", {})
	check(int(manifest.get("build", 0)) == 58 and int(manifest.get("package_size", 0)) > 250 * 1000 * 1000, "actual complete release 58 manifest is used")
	var previous_build: int = launcher._get_local_game_build()
	launcher.inject_commit_lock = true
	launcher._force_reinstall = true
	await launcher._run_update_flow()
	check(launcher.lock_acquired, "real Windows file handle blocks the final Game-directory rename")
	check(launcher.launches == 0 and launcher._retry_available, "locked final installation offers retry and never launches a partial game")
	var zip_path: String = launcher._temp_dir.path_join("game_%s.zip" % launcher._hash_suffix(str(manifest.sha256)))
	check(FileAccess.file_exists(zip_path) and launcher._file_size(zip_path) == int(manifest.package_size), "failed final installation retains the complete verified ZIP")
	check(launcher._sha256_file(zip_path).to_lower() == str(manifest.sha256).to_lower(), "retained 262-MB download has the real release SHA-256")
	check(launcher._get_local_game_build() == previous_build and FileAccess.file_exists(launcher._game_dir.path_join("Bobux.exe")), "failed rename preserves the previous executable and build marker")
	var before := await counts(launcher)
	check(int(before.get("package_bytes", -1)) == int(manifest.package_size), "the complete package crosses loopback exactly once")
	check(bool(launcher.fixture_control("/unlock").get("ok", false)), "transient install lock can be released")
	launcher.queue_free()
	await process_frame
	await process_frame
	var restarted := create_launcher()
	restarted._force_reinstall = true
	await restarted._run_update_flow()
	check(restarted.launches == 1 and restarted._get_local_game_build() == 58, "a restarted launcher completes extraction, verification and stage commit")
	var after := await counts(restarted)
	check(int(after.get("package_bytes", -1)) == int(before.get("package_bytes", -2)), "restart reuses the verified download instead of fetching another full ZIP")
	check(bool(restarted._validate_game_install_directory(restarted._game_dir, manifest, true).get("ok", false)), "installed executable and every required Luau/runtime file match release hashes")
	await restarted._run_update_flow()
	check(restarted.launches == 2 and int((await counts(restarted)).get("package_bytes", -1)) == int(before.get("package_bytes", -2)), "subsequent ordinary launch uses installed build without downloading")
	for progress in restarted.extraction_progress:
		check(is_equal_approx(progress, 1), "completed download remains at 100% during extraction and installation")
	# Simulate closing immediately after the last downloaded byte, while a
	# scanner still holds the complete .part without delete sharing.
	DirAccess.make_dir_recursive_absolute(restarted._temp_dir)
	var complete_part: String = restarted._temp_dir.path_join("game_%s.zip.part" % restarted._hash_suffix(str(manifest.sha256)))
	var final_zip := complete_part.trim_suffix(".part")
	check(DirAccess.remove_absolute(final_zip) == OK, "isolated completed ZIP is removed to exercise interrupted .part promotion")
	check(DirAccess.copy_absolute(OS.get_environment("BOBUX_FULL_PACKAGE_SOURCE"), complete_part) == OK, "real complete .part fixture is copied")
	check(bool(restarted.fixture_control("/lock-part").get("ok", false)), "real complete .part is readable but locked against rename")
	var urls: Array[String] = [base_url + "/full.zip"]
	var part_result: Dictionary = await restarted._download_file_from_urls(urls, final_zip, "complete-part fixture", str(manifest.sha256), int(manifest.package_size))
	check(not bool(part_result.get("ok", false)) and not bool(part_result.get("retryable", true)) and FileAccess.file_exists(complete_part), "locked 100% .part returns a terminal recoverable failure and is retained")
	check(int((await counts(restarted)).get("package_bytes", -1)) == int(before.get("package_bytes", -2)), "locked complete .part sends no EOF Range or full download")
	restarted.fixture_control("/unlock")
	var promoted: Dictionary = await restarted._download_file_from_urls(urls, final_zip, "complete-part fixture", str(manifest.sha256), int(manifest.package_size))
	check(bool(promoted.get("ok", false)) and bool(promoted.get("cached", false)) and not FileAccess.file_exists(complete_part), "released complete .part promotes and verifies without HTTP")
	check(bool(restarted.fixture_control("/lock-zip").get("ok", false)), "real complete ZIP is unreadable during a transient sharing lock")
	var zip_result: Dictionary = await restarted._download_file_from_urls(urls, final_zip, "locked-ZIP fixture", str(manifest.sha256), int(manifest.package_size))
	check(not bool(zip_result.get("ok", false)) and not bool(zip_result.get("retryable", true)) and FileAccess.file_exists(final_zip), "unreadable verified ZIP is preserved instead of being classified as corrupt")
	check(int((await counts(restarted)).get("package_bytes", -1)) == int(before.get("package_bytes", -2)), "temporary ZIP sharing lock cannot restart the full transfer")
	restarted.fixture_control("/unlock")
	var recovered: Dictionary = await restarted._download_file_from_urls(urls, final_zip, "locked-ZIP fixture", str(manifest.sha256), int(manifest.package_size))
	check(bool(recovered.get("ok", false)) and bool(recovered.get("cached", false)), "unlocking the ZIP makes Retry reuse the same full verified file")
	print("FULL_PACKAGE_INSTALL_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "requests": await counts(restarted), "build": restarted._get_local_game_build()}))
	restarted.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
