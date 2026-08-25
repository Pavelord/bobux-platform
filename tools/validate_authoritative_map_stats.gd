extends SceneTree


func _initialize() -> void:
	var cloud_script := load("res://autoload/cloud_api.gd") as Script
	var lobby_script := load("res://scripts/lobby/lobby.gd") as Script
	if cloud_script == null or lobby_script == null:
		push_error("[validate_authoritative_map_stats] Required scripts did not load")
		quit(1)
		return
	var cloud := cloud_script.new() as Node
	var lobby := lobby_script.new() as Control
	var duplicate_records: Array = [
		{"id": "old", "owner_id": "owner", "name": "Map", "likes_count": 12, "visits_count": 40},
		{"id": "new", "owner_id": "owner", "name": "map", "likes_count": 9, "visits_count": 83},
	]
	var deduped: Array = cloud.call("_dedupe_published_maps_by_owner_and_name", duplicate_records)
	var stabilized: Array = lobby.call(
		"_stabilize_published_map_stats",
		[{"id": "map-1", "name": "Map", "likes_count": 2, "visits_count": 10}],
		[{"id": "map-1", "name": "Map", "likes_count": 7, "visits_count": 51}]
	)
	var fallback_stabilized: Array = lobby.call(
		"_stabilize_published_map_stats",
		[{"id": "map-2", "name": "Fallback Map"}],
		[{"id": "map-2", "name": "Fallback Map", "likes_count": 4, "visits_count": 18}]
	)
	var server_source := _read_text("res://services/bobux_api/server.js")
	var client_source := _read_text("res://autoload/cloud_api.gd")
	var deduped_record: Dictionary = deduped[0] if deduped.size() == 1 and deduped[0] is Dictionary else {}
	var stable_record: Dictionary = stabilized[0] if stabilized.size() == 1 and stabilized[0] is Dictionary else {}
	var fallback_record: Dictionary = fallback_stabilized[0] if fallback_stabilized.size() == 1 and fallback_stabilized[0] is Dictionary else {}
	var ok := (
		deduped.size() == 1
		and int(deduped_record.get("likes_count", 0)) == 12
		and int(deduped_record.get("visits_count", 0)) == 83
		and int(stable_record.get("likes_count", 0)) == 2
		and int(stable_record.get("visits_count", 0)) == 10
		and int(fallback_record.get("likes_count", 0)) == 4
		and int(fallback_record.get("visits_count", 0)) == 18
		and server_source.contains("withMutationLock(`like:${targetType}:${targetId}`")
		and server_source.contains("withMutationLock(`visit:map:${cleanTargetId}`")
		and client_source.contains("The server owns counters")
		and client_source.contains("Likes are idempotent")
	)
	print("[validate_authoritative_map_stats] ok=%s deduped=%s stabilized=%s" % [str(ok), JSON.stringify(deduped), JSON.stringify(stabilized)])
	cloud.free()
	lobby.free()
	quit(0 if ok else 1)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var value := file.get_as_text()
	file.close()
	return value
