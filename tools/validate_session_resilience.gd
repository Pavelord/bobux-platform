extends SceneTree
## Isolated transport doubles: never reads, writes or deletes real credentials.

var failures: Array[String] = []
var completions: Array[Dictionary] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func refresh(cloud: Node) -> void:
	completions.append(await cloud.ensure_authenticated_session())
func friends(cloud: Node) -> void:
	completions.append(await cloud.get_friends_list())
func direct_refresh(cloud: Node) -> void:
	completions.append(await cloud._refresh_authenticated_session())
func run() -> void:
	var cloud: Node = load("res://tools/fixtures/cloud_api_mock.gd").new()
	root.add_child(cloud)
	cloud._auth_refresh_token = "test-only"
	cloud._auth_user_id = "user-a"
	refresh(cloud)
	refresh(cloud)
	while completions.size() < 2: await process_frame
	check(cloud.refresh_calls == 1, "concurrent login refresh was not coalesced")
	check(cloud.cleared == 0 and cloud._auth_refresh_token == "test-only", "503 erased saved session")
	cloud.auth_reply = {"ok":false,"status":401}
	await cloud.ensure_authenticated_session()
	check(cloud.cleared == 1 and cloud._auth_refresh_token.is_empty(), "revoked session was retained")
	cloud._auth_refresh_token = "test-old-account"
	completions.clear()
	direct_refresh(cloud)
	cloud._auth_operation_epoch += 1
	cloud._auth_user_id = "user-b"
	cloud._auth_refresh_token = "test-new-account"
	while completions.is_empty(): await process_frame
	check(not cloud._is_rejected_auth_session(completions[0]) and cloud._auth_refresh_token == "test-new-account", "stale rejection can erase a new account session")
	cloud._auth_user_id = "user-a"
	completions.clear()
	friends(cloud)
	friends(cloud)
	while completions.size() < 2: await process_frame
	check(cloud.friend_calls == 1, "concurrent friend requests were not coalesced")
	cloud.friend_reply = {"ok":false,"status":503}
	var cached: Dictionary = await cloud.get_friends_list()
	check(cached.get("stale",false) and cached.get("data",[]).size() == 1, "temporary failure lost friends")
	cloud._auth_user_id = "user-b"
	var other: Dictionary = await cloud.get_friends_list()
	check(not other.get("ok",false), "another account received cached friends")
	completions.clear()
	cloud._auth_user_id = "user-a"
	friends(cloud)
	friends(cloud)
	cloud._auth_user_id = "user-b"
	cloud.friend_reply = {"ok":true,"data":[{"id":"friend-b"}]}
	var switched: Dictionary = await cloud.get_friends_list()
	while completions.size() < 2: await process_frame
	check(switched.get("ok",false) and switched.data[0].id == "friend-b", "account change mixed pending requests")
	check(not completions[0].get("ok",false) and not completions[1].get("ok",false), "old-account waiter received new-account friends")
	print("[session_resilience] failures=", failures)
	cloud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

