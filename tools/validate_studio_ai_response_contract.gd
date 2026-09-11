extends SceneTree


func _initialize() -> void:
	var cloud_api: Node = load("res://autoload/cloud_api.gd").new()
	var action := {
		"type": "create_part",
		"name": "Blue Fire Part",
		"shape": "Box",
		"size": [4, 4, 4],
		"position": [0, 2, 0],
		"color": "#2584D8",
		"effects": [{"type": "Fire", "enabled": true}]
	}
	var nested_response := {
		"ok": true,
		"status": 200,
		"data": {"ok": true, "message": "Created a blue burning Part.", "actions": [action]}
	}
	var normalized: Dictionary = cloud_api.call("_normalize_studio_ai_response", nested_response)
	var actions: Array = normalized.get("actions", []) if normalized.get("actions", []) is Array else []
	var direct_response := {"ok": true, "message": "Direct", "actions": [action]}
	var direct: Dictionary = cloud_api.call("_normalize_studio_ai_response", direct_response)
	var direct_actions: Array = direct.get("actions", []) if direct.get("actions", []) is Array else []
	var ok := bool(normalized.get("ok", false)) \
		and str(normalized.get("message", "")) == "Created a blue burning Part." \
		and actions.size() == 1 \
		and str((actions[0] as Dictionary).get("type", "")) == "create_part" \
		and direct_actions.size() == 1
	print("[validate_studio_ai_response_contract] ok=%s nested_actions=%d direct_actions=%d" % [str(ok), actions.size(), direct_actions.size()])
	cloud_api.free()
	quit(0 if ok else 1)
