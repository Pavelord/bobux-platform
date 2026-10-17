extends RefCounted
## Keep legacy orthographic-only POSITION guards well defined on GLES too.
## Authored files and valid shader branches remain unchanged.

static func perspective_position_fallback(source: String) -> String:
	var masked := _mask_comments(source)
	if not masked.contains("shader_type spatial") or masked.contains("world_vertex_coords") or masked.contains("skip_vertex_transform"):
		return source
	var vertex := RegEx.new()
	vertex.compile("\\bvoid\\s+vertex\\s*\\(\\s*\\)\\s*\\{")
	var declaration := vertex.search(masked)
	if declaration == null: return source
	var body_start := declaration.get_end()
	var body_end := body_start
	var depth := 1
	while body_end < masked.length() and depth > 0:
		if masked[body_end] == "{": depth += 1
		elif masked[body_end] == "}": depth -= 1
		body_end += 1
	if depth != 0: return source
	var assignment := RegEx.new()
	assignment.compile("\\bPOSITION\\s*=(?!=)")
	if assignment.search_all(masked).size() != 1: return source
	var guard := RegEx.new()
	guard.compile("\\bif\\s*\\(\\s*PROJECTION_MATRIX\\s*\\[\\s*3\\s*\\]\\s*\\[\\s*3\\s*\\]\\s*>\\s*(?:0\\.5|\\.5)\\s*\\)\\s*\\{[^{}]*\\bPOSITION\\s*=[^;]+;\\s*\\}")
	var match_guard := guard.search(masked, body_start, body_end - 1)
	if match_guard == null: return source
	var insert_at := match_guard.get_end()
	var remainder := masked.substr(insert_at, body_end - 1 - insert_at).strip_edges()
	# A following else, an early return, or additional vertex operations require
	# full control-flow analysis. This adapter deliberately leaves those alone.
	if not remainder.is_empty(): return source
	var fallback := " else { POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); }"
	return source.substr(0, insert_at) + fallback + source.substr(insert_at)

static func _mask_comments(source: String) -> String:
	var expression := RegEx.new()
	expression.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
	var masked := source
	for found: RegExMatch in expression.search_all(source):
		var blank := ""
		for character: String in found.get_string(): blank += "\n" if character == "\n" else " "
		masked = masked.substr(0, found.get_start()) + blank + masked.substr(found.get_end())
	return masked
