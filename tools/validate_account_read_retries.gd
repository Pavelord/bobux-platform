extends SceneTree
var failures: Array[String] = []
var completed: Array[Dictionary] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	print("[account_read_retries] ", label_, "=", ok)
	if not ok: failures.append(label_)
func request(cloud: Node) -> void:
	completed.append(await cloud._request_json_with_retries("/rpc/get_friends_list", HTTPClient.METHOD_POST, {}, "probe", PackedStringArray(), true, 1.0, 2))
func run() -> void:
	var cloud: Node = load("res://tools/fixtures/cloud_api_account_retry.gd").new()
	root.add_child(cloud)
	cloud._auth_user_id = "test-a"
	cloud._auth_access_token = "test-access-a"
	cloud._auth_refresh_token = "test-refresh-a"
	cloud.replies = [{"ok": false, "status": 401}]
	request(cloud)
	cloud._auth_operation_epoch += 1
	cloud._auth_user_id = "test-b"
	cloud._auth_access_token = "test-access-b"
	cloud._auth_refresh_token = ""
	while completed.is_empty(): await process_frame
	check(not completed[0].get("ok", false) and int(completed[0].get("status", 0)) != 401, "stale rejection is classified as an account change")
	check(cloud.cleared == 0 and cloud.refresh_calls == 0 and cloud._auth_access_token == "test-access-b", "old-account 401 cannot erase or refresh the replacement session")
	completed.clear()
	cloud.replies = [{"ok": false, "status": 503}, {"ok": true, "status": 200, "data": ["old-a"]}]
	request(cloud)
	await create_timer(0.12).timeout
	cloud._auth_operation_epoch += 1
	cloud._auth_user_id = "test-c"
	cloud._auth_access_token = "test-access-c"
	while completed.is_empty(): await process_frame
	check(cloud.request_calls == 2 and not completed[0].get("ok", false), "retry backoff never sends the old request under a different account")
	completed.clear()
	cloud.replies = [{"ok": false, "status": 503}, {"ok": true, "status": 200, "data": ["friend-c"]}]
	request(cloud)
	while completed.is_empty(): await process_frame
	check(completed[0].get("ok", false) and completed[0].data == ["friend-c"], "same-account transient reads still recover normally")
	cloud.queue_free()
	await process_frame
	print("ACCOUNT_READ_RETRY_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
