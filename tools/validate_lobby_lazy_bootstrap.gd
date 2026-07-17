extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if scene == null:
		push_error("[validate_lobby_lazy_bootstrap] lobby scene missing")
		quit(1)
		return
	var lobby := scene.instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	if lobby.get("avatar_ui") != null:
		push_error("[validate_lobby_lazy_bootstrap] Avatar UI was built during lobby bootstrap")
		quit(1)
		return
	if bool(lobby.get("_catalog_ui_built")):
		push_error("[validate_lobby_lazy_bootstrap] Catalog UI was built during lobby bootstrap")
		quit(1)
		return
	print("[validate_lobby_lazy_bootstrap] Lobby bootstrap stays lightweight")
	quit(0)
