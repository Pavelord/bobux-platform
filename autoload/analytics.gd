extends Node

const LOG_PATH: String = "user://logs.txt"

var session_start_time: int = 0
var events: Array = []

func _ready() -> void:
	session_start_time = Time.get_ticks_msec()
	log_event("session_started")

func log_event(event_name: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system()
	var entry: String = "[%s] %s" % [timestamp, event_name]
	events.append(entry)
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(entry)
		file.close()

func log_button_click(button_name: String) -> void:
	log_event("button_click: " + button_name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var duration_sec: float = (Time.get_ticks_msec() - session_start_time) / 1000.0
		log_event("session_ended (duration: %.1fs)" % duration_sec)
		get_tree().quit()
