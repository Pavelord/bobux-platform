extends SceneTree
var failures: Array[String] = []
var concurrent_result: Dictionary = {}
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	await process_frame
	var api: Node = root.get_node("CloudAPI")
	api.set_script(load("res://tools/fixtures/published_map_pagination_api.gd"))
	var full: Dictionary = await api.fetch_published_maps(-1)
	check(full.get("ok", false) and full.get("data", []).size() == 205, "full Games list drops pages after the first 100")
	check(api.fixture_queries.size() == 3 and api.fixture_queries[1].contains("offset=100") and api.fixture_queries[2].contains("offset=200"), "metadata pages do not advance")
	for query in api.fixture_queries:
		check(query.contains("limit=100") and not query.contains("updated_at,data"), "full scene data leaked into the mobile Games request")
	api.fixture_queries.clear()
	concurrent_fetch(api)
	var shared: Dictionary = await api.fetch_published_maps(-1)
	check(shared.get("data", []).size() == 205 and concurrent_result.get("data", []).size() == 205 and api.fixture_queries.size() == 3, "simultaneous Home/Games requests duplicate all metadata pages")
	api.fixture_queries.clear()
	var preview: Dictionary = await api.fetch_published_maps(12)
	check(preview.get("data", []).size() == 12 and api.fixture_queries.size() == 1 and api.fixture_queries[0].contains("limit=12"), "bounded recommendation request expanded unexpectedly")
	api.fixture_queries.clear()
	var owned: Dictionary = await api.fetch_published_maps_for_owner("owner with spaces", -1)
	check(owned.get("data", []).size() == 205 and api.fixture_queries[0].contains("owner_id=eq.owner%20with%20spaces"), "owner filter was lost between pages")
	api.fixture_queries.clear()
	api.fixture_fail_offset = 100
	var failed: Dictionary = await api.fetch_published_maps(-1)
	check(not failed.get("ok", false) and failed.get("status", 0) == 503, "incomplete refresh masquerades as a full list")
	api.fixture_fail_offset = -1
	api.fixture_ignore_offset = true
	var ignored: Dictionary = await api.fetch_published_maps(-1)
	check(not ignored.get("ok", false), "server ignoring offset creates an infinite page loop")
	print("PUBLISHED_MAP_PAGINATION_RESULT=" + JSON.stringify({"ok": failures.is_empty(), "failures": failures, "all_maps": full.get("data", []).size()}))
	quit(0 if failures.is_empty() else 1)

func concurrent_fetch(api: Node) -> void:
	concurrent_result = await api.fetch_published_maps(-1)
