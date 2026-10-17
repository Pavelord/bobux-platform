extends SceneTree

var failures: Array[String] = []
var folder: String
var base_url: String
var nonce: String = "0123456789abcdef0123456789abcdef"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	print("[manifest-guard] ", "PASS " if ok else "FAIL ", detail)
	if not ok:
		failures.append(detail)

func create_launcher(case_name: String, routes: Array[String]) -> Control:
	var launcher: Control = load("res://tools/fixtures/manifest_launcher.gd").new()
	launcher._install_root = folder.path_join(case_name)
	launcher._game_dir = launcher._install_root.path_join("Game")
	launcher._temp_dir = launcher._install_root.path_join("_download")
	launcher._staging_dir = launcher._install_root.path_join("_staging_game")
	launcher._game_backup_dir = launcher._install_root.path_join("_backup_game")
	launcher._launcher_staging_dir = launcher._install_root.path_join("_staging_launcher")
	launcher.manifest_routes = routes
	root.add_child(launcher)
	return launcher

func counts(launcher: Control) -> Dictionary:
	var reply: Dictionary = await launcher._http_get_json(base_url + "/counts", "fixture counts")
	return reply.get("data", {})

func fingerprint(launcher: Control) -> Dictionary:
	var hashes: Dictionary = {}
	for path in [launcher._install_root.path_join("version.json"), launcher._game_dir.path_join("version.json"), launcher._game_dir.path_join("Bobux.exe"), launcher._temp_dir.path_join("verified_prior.zip")]:
		hashes[path] = launcher._sha256_file(path)
	return hashes

func free_launcher(launcher: Control) -> void:
	launcher.queue_free()
	await process_frame
	await process_frame

func helper_status(pid: int, ticks: String, age: int = 0) -> Dictionary:
	return {"phase": "applying", "nonce": nonce, "helper_pid": pid, "helper_started_ticks": ticks,
		"owner_pid": OS.get_process_id(), "time": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - age) + "Z"}

func write_helper_status(status: Dictionary) -> void:
	var state_root: String = folder.path_join("handoff")
	DirAccess.make_dir_recursive_absolute(state_root)
	var file := FileAccess.open(state_root.path_join("_launcher_self_update_status.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(status))
	file.close()

func run() -> void:
	folder = OS.get_environment("BOBUX_MANIFEST_FIXTURE_ROOT")
	base_url = OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL")
	if not folder.replace("\\", "/").contains(".codex-tmp/") or not base_url.begins_with("http://127.0.0.1:"):
		push_error("Manifest fixture requires isolated .codex-tmp and loopback HTTP")
		quit(2)
		return
	var helper_pid: int = OS.get_environment("BOBUX_GUARD_HELPER_PID").to_int()
	var helper_ticks: String = OS.get_environment("BOBUX_GUARD_HELPER_TICKS")
	var guard_script = load("res://scripts/update_instance_guard.gd")
	if OS.get_cmdline_user_args().has("--guard-replacement"):
		var replacement = guard_script.new()
		var lease: Dictionary = await replacement.acquire(folder.path_join("handoff"), self)
		check(bool(lease.get("ok", false)) and not bool(lease.get("secondary", false)) and replacement._server != null and replacement._server.is_listening(), "the helper's nonce authorizes its replacement during the handoff gap")
		replacement.release()
		print("MANIFEST_REPLACEMENT_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
		quit(0 if failures.is_empty() else 1)
		return
	var launcher := create_launcher("fallback", ["/old", "/current"])
	await launcher._run_update_flow()
	var first_counts := await counts(launcher)
	check(launcher.launches == 1 and launcher._get_local_game_build() == 58, "old valid manifest is skipped and the current second mirror is accepted")
	check(launcher.self_update_builds == [58] and launcher.install_builds.is_empty(), "old mirror is rejected before self-update, recovery or extraction")
	check(int(first_counts.get("/old", 0)) == 1 and int(first_counts.get("/current", 0)) == 1 and int(first_counts.get("/package.zip", 0)) == 0 and int(first_counts.get("/launcher.zip", 0)) == 0, "stale fallback selection does not download any package")
	await free_launcher(launcher)
	launcher = create_launcher("all_old", ["/old", "/old-build"])
	launcher._force_reinstall = true
	var before := fingerprint(launcher)
	await launcher._run_update_flow()
	var rejected_counts := await counts(launcher)
	check(launcher.launches == 0 and launcher._retry_available and launcher.last_failure.contains("устаревшую"), "all older mirrors return a clear recoverable error")
	check(launcher.self_update_builds.is_empty() and launcher.install_builds.is_empty() and launcher._current_manifest.is_empty(), "all older mirrors stop before any self-update or installation")
	check(fingerprint(launcher) == before and not DirAccess.dir_exists_absolute(launcher._staging_dir) and not DirAccess.dir_exists_absolute(launcher._game_backup_dir), "all older mirrors preserve executable, both version markers and verified cache byte for byte")
	check(int(rejected_counts.get("/package.zip", 0)) == 0 and int(rejected_counts.get("/launcher.zip", 0)) == 0, "all older mirrors cause zero game or launcher package GETs")
	await free_launcher(launcher)
	launcher = create_launcher("equal", ["/current"])
	await launcher._run_update_flow()
	check(launcher.launches == 1 and launcher.self_update_builds == [58] and launcher.install_builds.is_empty(), "equal installed version keeps the normal launch path")
	await free_launcher(launcher)
	launcher = create_launcher("newer", ["/newer"])
	await launcher._run_update_flow()
	check(launcher.launches == 1 and launcher._get_local_game_build() == 59 and launcher.self_update_builds == [59] and launcher.install_builds == [59], "a newer release still downloads, extracts and commits normally")
	check(bool(launcher._validate_game_install_directory(launcher._game_dir, launcher._current_manifest, true).get("ok", false)), "the newer fixture executable and runtime pass real checksum validation")
	check(int((await counts(launcher)).get("/package.zip", 0)) == 1, "only the newer release downloads its package once")
	await free_launcher(launcher)
	write_helper_status(helper_status(helper_pid, helper_ticks))
	var guard = guard_script.new()
	var pending: Dictionary = await guard.acquire(folder.path_join("handoff"), self)
	check(bool(pending.get("secondary", false)) and bool(pending.get("handoff_pending", false)) and guard._server == null, "a real live PowerShell helper prevents a second updater during the TCP gap")
	guard.release()
	for case_value in [
		{"label": "stale helper status", "status": helper_status(helper_pid, helper_ticks, 300)},
		{"label": "dead helper process", "status": helper_status(2147483647, helper_ticks)},
		{"label": "reused helper PID with mismatched start ticks", "status": helper_status(helper_pid, str(helper_ticks.to_int() + 1))},
		{"label": "a non-PowerShell process", "status": helper_status(OS.get_process_id(), helper_ticks)}]:
		write_helper_status(case_value.status)
		guard = guard_script.new()
		var acquired: Dictionary = await guard.acquire(folder.path_join("handoff"), self)
		check(bool(acquired.get("ok", false)) and not bool(acquired.get("secondary", false)) and guard._server != null and guard._server.is_listening(), "%s does not block future launches" % case_value.label)
		guard.release()
	write_helper_status(helper_status(helper_pid, helper_ticks))
	print("MANIFEST_FRESHNESS_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
