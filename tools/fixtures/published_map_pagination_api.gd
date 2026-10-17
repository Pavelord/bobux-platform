extends "res://autoload/cloud_api.gd"
var fixture_queries: Array[String] = []
var fixture_fail_offset := -1
var fixture_ignore_offset := false

func _ready() -> void: pass

func _request_json_with_retries(endpoint: String, _method: HTTPClient.Method, _body: Variant, request_name: String, _extra_headers: PackedStringArray = PackedStringArray(), _use_auth_session: bool = true, _timeout_seconds: float = HTTP_REQUEST_TIMEOUT_SECONDS, _attempts: int = HTTP_READ_RETRY_ATTEMPTS) -> Dictionary:
	fixture_queries.append(endpoint)
	var query: Dictionary = {}
	for pair in endpoint.get_slice("?", 1).split("&"):
		query[pair.get_slice("=", 0)] = pair.get_slice("=", 1)
	var offset := int(query.get("offset", 0))
	if offset == fixture_fail_offset: return {"ok": false, "status": 503, "error": "fixture disconnected", "endpoint": request_name}
	if fixture_ignore_offset: offset = 0
	var page: Array = []
	for index in range(offset, mini(offset + int(query.get("limit", 100)), 205)):
		page.append({"id": "page_map_%03d" % index, "name": "Page Map %03d" % index, "owner_id": "page_owner", "is_published": true})
	await get_tree().process_frame
	return {"ok": true, "status": 200, "data": page}
