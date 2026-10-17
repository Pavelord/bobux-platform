extends "res://scripts/launcher.gd"

var launches: int = 0
var extraction_progress: Array[float] = []

func _ready() -> void:
	_build_ui()

func _launch_game() -> void:
	launches += 1

func _get_manifest_urls() -> Array[String]:
	return [OS.get_environment("BOBUX_DOWNLOAD_FIXTURE_URL") + "/manifest"]

func _set_status(title: String, detail: String, progress: float) -> void:
	if title in ["Extracting update...", "Installing update..."]:
		extraction_progress.append(progress)
	super._set_status(title, detail, progress)
