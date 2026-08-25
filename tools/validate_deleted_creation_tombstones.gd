extends SceneTree


func _initialize() -> void:
	var session_script := load("res://autoload/user_session.gd") as Script
	if session_script == null:
		push_error("[validate_deleted_creation_tombstones] UserSession script is missing")
		quit(1)
		return
	var session := session_script.new() as Node
	session.call("mark_deleted_game", "", "Test Escape Meme Obby")
	var hidden_by_name: bool = bool(session.call("is_deleted_game", "", "test escape meme obby"))
	session.call("mark_deleted_game", "map-42", "Created Place")
	var hidden_by_id: bool = bool(session.call("is_deleted_game", "map-42", ""))
	var hidden_by_second_name: bool = bool(session.call("is_deleted_game", "", "CREATED PLACE"))
	session.call("unmark_deleted_game", "map-42", "created place")
	var restored: bool = not bool(session.call("is_deleted_game", "map-42", "created place"))
	var ok := hidden_by_name and hidden_by_id and hidden_by_second_name and restored
	print("[validate_deleted_creation_tombstones] ok=%s name=%s id=%s restored=%s" % [
		str(ok), str(hidden_by_name), str(hidden_by_id), str(restored)
	])
	session.free()
	quit(0 if ok else 1)
