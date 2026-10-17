extends "res://tools/fixtures/download_launcher.gd"

var manifest_routes: Array[String] = []
var self_update_builds: Array[int] = []
var install_builds: Array[int] = []
var last_failure: String = ""

func _get_manifest_urls() -> Array[String]:
	var urls: Array[String] = []
	for route in manifest_routes:
		urls.append(OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL") + route)
	return urls

func _maybe_self_update_launcher(manifest: Dictionary) -> Dictionary:
	# Observe the real manifest selection boundary. Never run a fixture EXE.
	self_update_builds.append(int(manifest.get("build", 0)))
	return {"ok": true}

func _download_and_install(manifest: Dictionary) -> Dictionary:
	install_builds.append(int(manifest.get("build", 0)))
	return await super._download_and_install(manifest)

func _fail(message: String) -> void:
	last_failure = message
	super._fail(message)
