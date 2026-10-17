extends SceneTree

class RetryAPI:
	extends Node
	var attempts := 0
	func get_current_user_id() -> String: return "retry_owner"
	func fetch_catalog() -> Dictionary: return {"ok": true, "data": []}
	func fetch_avatar_marketplace_items() -> Dictionary: return {"ok": true, "data": []}
	func fetch_owned_avatar_items() -> Dictionary:
		attempts += 1
		if attempts == 1: return {"ok": false, "status": 503, "error": "fixture disconnected"}
		return {"ok": true, "data": [{"id": "pending_hat", "owner_id": "retry_owner", "owned": true, "data": {"slot": "Head"}}]}
	func load_player_profile(_user_id: String) -> Dictionary:
		return {"ok": true, "data": {"inventory_items": ["pending_hat"]}}

var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	await process_frame
	var host := Control.new()
	root.add_child(host)
	var api := RetryAPI.new()
	root.add_child(api)
	var ui: RefCounted = load("res://tools/fixtures/avatar_inventory_retry_ui.gd").new()
	ui.lobby = host
	ui.fixture_api = api
	ui._user_avatar_data = {"equipped": ["pending_hat"]}
	ui._inventory_retry_delay = 0.05
	await ui._load_cloud_inventory()
	check(ui._user_avatar_data.equipped == ["pending_hat"] and not ui._cloud_ownership_snapshot_complete, "temporary owned RPC failure deleted the outfit")
	check(ui._inventory_retry_scheduled and api.attempts == 1, "failed inventory did not schedule a background retry")
	await create_timer(0.15).timeout
	check(api.attempts == 2 and ui._cloud_ownership_snapshot_complete and not ui._inventory_retry_scheduled, "background inventory retry did not recover and stop")
	var payloads: Array = ui._get_equipped_avatar_item_payloads()
	check(payloads.size() == 1 and payloads[0].id == "pending_hat", "recovered accessory did not reach avatar render payload")
	await create_timer(0.1).timeout
	check(api.attempts == 2, "successful inventory keeps requesting again")
	host.queue_free()
	api.queue_free()
	ui = null
	await process_frame
	print("AVATAR_INVENTORY_RETRY_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
