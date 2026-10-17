extends SceneTree

var listener := TCPServer.new()
var connections: Array[Dictionary] = []
var payload: PackedByteArray
var failures: Array[String] = []
var frames := 0

func _initialize(): run.call_deferred()

func check(ok: bool, detail: String):
	print("[streaming] ", detail, "=", ok)
	if not ok: failures.append(detail)

func serve():
	frames += 1
	if listener.is_connection_available():
		connections.append({"peer": listener.take_connection(), "request": "", "received": 0})
	for client in connections:
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
		if peer.get_available_bytes() > 0:
			client.request += peer.get_utf8_string(peer.get_available_bytes())
			if client.received == 0 and "\r\n\r\n" in client.request: client.received = Time.get_ticks_msec()
		if "GET /image " in client.request and client.received > 0 and Time.get_ticks_msec() - client.received > 1400:
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()).to_utf8_buffer())
			peer.put_data(payload)
			client.request = "done"
		# /hang deliberately accepts the connection without sending headers.

func run():
	var cloud := root.get_node("CloudAPI")
	var media := root.get_node("MapMediaStream")
	check(listener.listen(0, "127.0.0.1") == OK, "local stalled HTTP fixture starts")
	var url := "http://127.0.0.1:%d" % listener.get_local_port()
	process_frame.connect(serve)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.8))
	payload = image.save_png_to_buffer()
	var folder := "user://validation/progressive_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var started := Time.get_ticks_msec()
	var result: Dictionary = await cloud._ensure_cached_map_visual_assets(folder, "test", {"mode_asset_urls": {"image.png": url + "/image"}}, true)
	check(result.ok and result.get("streaming",0) == 1 and Time.get_ticks_msec()-started < 500, "join does not wait for delayed image")
	check(not FileAccess.file_exists(folder.path_join("image.png")), "playable cache returned before media arrives")
	var texture: Texture2D = media.request_texture(folder.path_join("image.png"))
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	var clone := material.duplicate(false) as StandardMaterial3D
	var deadline := Time.get_ticks_msec() + 5000
	while texture.get_width() == 1 and Time.get_ticks_msec() < deadline: await process_frame
	var pixels := texture.get_image() if DisplayServer.get_name() != "headless" else Image.load_from_file(folder.path_join("image.png"))
	check(texture.get_width() == 16 and pixels.get_pixel(0,0).is_equal_approx(image.get_pixel(0,0)), "streamed pixels replace shared placeholder")
	check(clone.albedo_texture == texture and clone.albedo_texture.get_width() == 16, "cloned materials update without rebuilding world")
	started = Time.get_ticks_msec()
	frames = 0
	var timeout: Dictionary = await cloud._request_http_json(url + "/hang", HTTPClient.METHOD_GET, null, "timeout_probe", PackedStringArray(), 1.0)
	check(not timeout.ok and timeout.error_code == HTTPRequest.RESULT_TIMEOUT and Time.get_ticks_msec()-started < 2000, "stalled socket times out without joining a blocked worker")
	check(frames > 30, "game loop continues while server is unresponsive")
	for client in connections: (client.peer as StreamPeerTCP).disconnect_from_host()
	listener.stop()
	print("[streaming] failures=",failures)
	quit(0 if failures.is_empty() else 1)
