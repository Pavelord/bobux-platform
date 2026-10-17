extends "res://tools/fixtures/download_launcher.gd"

var inject_commit_lock := false
var lock_acquired := false
var status_phases: Array[String] = []

func _set_status(title: String, detail: String, progress: float) -> void:
	status_phases.append(title)
	super._set_status(title, detail, progress)
	if title == "Installing update..." and inject_commit_lock and not lock_acquired:
		var reply := fixture_control("/lock")
		lock_acquired = bool(reply.get("ok", false))
		if not lock_acquired: push_error("Could not acquire the real Windows fixture file lock")

func fixture_control(route: String) -> Dictionary:
	var base := OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL")
	if not base.begins_with("http://127.0.0.1:"): return {"ok": false}
	var client := HTTPClient.new()
	if client.connect_to_host("127.0.0.1", base.get_slice(":", 2).to_int()) != OK: return {"ok": false}
	var deadline := Time.get_ticks_msec() + 10000
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING] and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(2)
	if client.get_status() != HTTPClient.STATUS_CONNECTED: return {"ok": false}
	if client.request(HTTPClient.METHOD_GET, route, PackedStringArray(["Connection: close"])) != OK: return {"ok": false}
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(2)
	var bytes := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		client.poll()
		bytes.append_array(client.read_response_body_chunk())
		OS.delay_msec(2)
	client.close()
	var json := JSON.new()
	return json.data if json.parse(bytes.get_string_from_utf8()) == OK and json.data is Dictionary else {"ok": false}
