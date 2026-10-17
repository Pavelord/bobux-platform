extends SceneTree

var _launcher: Control
var _base_url: String
var _folder: String
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_base_url = OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL")
	if _base_url.is_empty():
		push_error("Start launcher/tools/run_download_contract.py to provide the local HTTP fixture.")
		quit(1)
		return
	_folder = OS.get_user_data_dir().path_join("download_contract_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_folder)
	_launcher = load("res://scripts/launcher.gd").new()
	# Do not enter _ready or fetch the live release manifest.
	_launcher.set_script(load("res://tools/fixtures/download_launcher.gd"))
	root.add_child(_launcher)
	await process_frame
	var metadata: Dictionary = await _launcher._http_get_json(_base_url + "/metadata", "fixture")
	var info: Dictionary = metadata.get("data", {})
	ProjectSettings.set_setting("launcher/download_idle_timeout_seconds", 0.3)
	# Reproduce the original whole-transfer deadline: both attempts restart
	# a progressing HTTP 200 transfer from byte zero rather than finishing it.
	for attempt in range(2):
		var legacy := HTTPRequest.new()
		legacy.use_threads = true
		legacy.timeout = 0.25
		root.add_child(legacy)
		legacy.request(_base_url + "/legacy-slow")
		var legacy_result: Array = await legacy.request_completed
		_check(int(legacy_result[0]) == HTTPRequest.RESULT_TIMEOUT, "legacy total deadline must reproduce timeout")
		legacy.queue_free()
	var slow_result: Dictionary = await _download("/slow", "slow.zip", info.slow_size, info.slow_hash)
	_check(bool(slow_result.get("ok", false)), "slow but progressing HTTP 200 must finish")
	var requests_before: Dictionary = await _counts()
	var slow_again: Dictionary = await _download("/slow", "slow.zip", info.slow_size, info.slow_hash)
	var requests_after: Dictionary = await _counts()
	_check(bool(slow_again.get("cached", false)), "completed file must be reused")
	_check(int(requests_before.get("/slow", 0)) == int(requests_after.get("/slow", 0)), "valid first download must not fetch again")
	var range_result: Dictionary = await _download("/range", "range.zip", info.range_size, info.range_hash)
	_check(bool(range_result.get("ok", false)), "multiple ranges must join byte exactly")
	var resumed_path: String = _folder.path_join("resume.zip")
	var prefix := PackedByteArray()
	prefix.resize(12345)
	prefix.fill(37)
	_launcher._write_bytes_to_file(resumed_path + ".part", prefix)
	var resume_result: Dictionary = await _download("/range", "resume.zip", info.range_size, info.range_hash)
	_check(bool(resume_result.get("ok", false)), "partial file must continue at its exact byte")
	_launcher._write_bytes_to_file(_folder.path_join("ignored.zip.part"), prefix)
	var ignored_result: Dictionary = await _download("/ignore", "ignored.zip", info.range_size, info.range_hash)
	_check(bool(ignored_result.get("ok", false)), "HTTP 200 after Range must replace the old partial")
	var corrupt_result: Dictionary = await _download("/corrupt", "corrupt.zip", info.range_size, info.range_hash)
	_check(not bool(corrupt_result.get("ok", false)), "incorrect hash must fail")
	var corrupt_counts: Dictionary = await _counts()
	_check(int(corrupt_counts.get("/corrupt", 0)) == 1, "bad integrity must not repeat eight full transfers")
	var wrong_range: Dictionary = await _download("/wrong-range", "wrong.zip", info.range_size, info.range_hash)
	_check(not bool(wrong_range.get("ok", false)), "incorrect Content-Range must fail")
	_check(int((await _counts()).get("/wrong-range", 0)) == 1, "invalid range must fail without retry loop")
	# Interrupted responses may not contaminate a verified prefix.
	_launcher._write_bytes_to_file(_folder.path_join("interrupted.zip.part"), prefix)
	var interrupted: Dictionary = await _download("/interrupt", "interrupted.zip", info.range_size, info.range_hash)
	_check(bool(interrupted.get("ok", false)), "network interruption must resume from preserved prefix")
	_check(_launcher._sha256_file(_folder.path_join("interrupted.zip")) == str(info.range_hash), "resumed interruption SHA-256")
	var cancel_timer := create_timer(0.18)
	cancel_timer.timeout.connect(func(): _launcher._cancel_requested = true)
	var cancelled: Dictionary = await _download("/slow", "cancel.zip", info.slow_size, info.slow_hash)
	_check(not bool(cancelled.get("ok", false)), "cancel must end transfer")
	_check(not FileAccess.file_exists(_folder.path_join("cancel.zip")), "cancel must not promote incomplete response")
	_launcher._cancel_requested = false
	var retry_result: Dictionary = await _download("/slow", "cancel.zip", info.slow_size, info.slow_hash)
	_check(bool(retry_result.get("ok", false)), "explicit retry must recover cancelled download")
	_launcher._install_root = _folder.path_join("installed")
	_launcher._game_dir = _launcher._install_root.path_join("Game")
	_launcher._temp_dir = _launcher._install_root.path_join("_download")
	_launcher._staging_dir = _launcher._install_root.path_join("_staging_game")
	_launcher._game_backup_dir = _launcher._install_root.path_join("_backup_game")
	_launcher._launcher_staging_dir = _launcher._install_root.path_join("_staging_launcher")
	_launcher._run_update_flow()
	_launcher._run_update_flow() # Must not start a second overlapping operation.
	while _launcher._update_flow_running:
		await process_frame
	_check(_launcher.launches == 1, "verified install must launch once")
	_check(_launcher._get_local_game_build() == 99, "install marker must persist")
	var first_install_counts: Dictionary = await _counts()
	_check(int(first_install_counts.get("/manifest", 0)) == 1, "reentrant flow must fetch one manifest")
	_check(int(first_install_counts.get("/install.zip", 0)) == 1, "first install must fetch one package")
	for value in _launcher.extraction_progress:
		_check(is_equal_approx(value, 1.0), "completed download must not reset to 82% during extraction")
	await _launcher._run_update_flow()
	_check(_launcher.launches == 2, "repeated launch must use installed build")
	_check(int((await _counts()).get("/install.zip", 0)) == 1, "second launch must not repeat full package download")
	print("LAUNCHER_DOWNLOAD_CONTRACT: " + JSON.stringify({"failures": _failures, "requests": await _counts()}))
	_launcher._delete_recursive_absolute(_folder)
	_launcher.queue_free()
	quit(0 if _failures.is_empty() else 1)

func _download(endpoint: String, filename: String, size: int, checksum: String) -> Dictionary:
	var urls: Array[String] = [_base_url + endpoint]
	var result: Dictionary = await _launcher._download_file_from_urls(urls, _folder.path_join(filename), "fixture", checksum, size)
	print("FIXTURE_RESULT " + endpoint + " " + JSON.stringify(result))
	return result

func _counts() -> Dictionary:
	var result: Dictionary = await _launcher._http_get_json(_base_url + "/counts", "fixture counts")
	return result.get("data", {})

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error(label)
