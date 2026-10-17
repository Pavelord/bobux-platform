extends SceneTree
const EXPIRY := preload("res://autoload/auth_token_expiry.gd")
const FIXTURE_PATH := "res://tools/fixtures/cloud_api_expiry_fixture.gd"
const SAVED_PATH := "user://validation/auth_expiry/synthetic_session.json"
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	print("[auth-expiry] ", "PASS " if ok else "FAIL ", detail)
	if not ok: failures.append(detail)
func jwt(claims: Dictionary) -> String:
	return "header." + Marshalls.utf8_to_base64(JSON.stringify(claims)).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=") + ".signature"
func payload(token: String, expiry: int) -> Dictionary:
	return {"access_token": token, "refresh_token": token, "expires_at": expiry, "user": {"id": "test-expiry-account"}}
func run() -> void:
	await process_frame
	var now := int(Time.get_unix_time_from_system())
	var future := jwt({"exp": now + 900, "extra": "игрок"})
	check(EXPIRY.token_expires_at(future) == now + 900, "numeric JWT expiration is decoded without using identity claims")
	check(EXPIRY.clamp_expiry(now + 30 * 86400, future) == now + 900, "fixed 30-day metadata cannot outlive the token")
	check(EXPIRY.clamp_expiry(now + 120, future) == now + 120, "shorter existing metadata is not extended")
	check(EXPIRY.clamp_expiry(0, future) == now + 900, "missing expiry uses the token's expiration hint")
	check(EXPIRY.clamp_expiry(now + 120, "opaque-test-token") == now + 120, "opaque tokens keep their existing expiry behavior")
	for expiry in [0, -1, 1.5, "1791800000", null, true, 253402300800, 1.0e100]:
		check(EXPIRY.token_expires_at(jwt({"exp": expiry})) == 0, "invalid claim type/range is ignored")
	for token in ["", "header.!.signature", "header.a.signature", "header.bm90LWpzb24.signature", "header.eyJleHAiOjEy.signature", ".payload.signature", "header.payload."]:
		check(EXPIRY.token_expires_at(token) == 0, "malformed payload is ignored safely")
	var cloud: Node = load(FIXTURE_PATH).new()
	root.add_child(cloud)
	var response: Dictionary = cloud._apply_auth_response_payload({"ok": true, "data": payload(future, now + 30 * 86400)}, "expiry-fixture")
	check(response.ok and cloud._auth_expires_at == now + 900 and cloud._has_valid_access_session() and cloud.cleared == 0, "received valid session is clamped and retained")
	DirAccess.make_dir_recursive_absolute(SAVED_PATH.get_base_dir())
	var expired := jwt({"exp": now - 120})
	var saved := {"backend_id": cloud.CLOUD_BACKEND_ID, "access_token": expired, "refresh_token": expired, "user_id": "test-expiry-account", "expires_at": now + 30 * 86400}
	var file := FileAccess.open(SAVED_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	cloud._load_saved_auth_session()
	check(cloud._auth_expires_at == now - 120 and cloud.has_authenticated_session() and not cloud._has_valid_access_session() and cloud.cleared == 0, "saved legacy expiry schedules refresh without deleting credentials or forcing login")
	cloud.auth_reply = {"ok": true, "data": payload(future, now + 30 * 86400)}
	var refreshed: Dictionary = await cloud.ensure_authenticated_session()
	check(refreshed.ok and cloud.refresh_calls == 1 and cloud._auth_expires_at == now + 900 and cloud.cleared == 0, "ordinary refresh recovers the expired scheduling hint")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED_PATH))
	cloud.queue_free()
	await process_frame
	print("AUTH_TOKEN_EXPIRY_RESULT=", JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
