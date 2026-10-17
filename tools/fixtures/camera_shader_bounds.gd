extends Node
## Diagnostic prototype only; production does not install this adapter.
## Camera-relative vertex geometry needs camera-relative CPU culling bounds.
## Fragment-only fog, camera-distance fades and ordinary billboards are excluded.
static var _shader_kinds: Dictionary = {}
var _mesh: MeshInstance3D
var _kind: Dictionary = {}
var _last_transform := Transform3D.IDENTITY
var _last_camera := Vector3.INF
var _last_radius := -1.0
var _owned_aabb := AABB()

static func attach(mesh: MeshInstance3D) -> Node:
	if mesh == null or mesh.mesh == null or mesh.custom_aabb != AABB(): return null
	if mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).custom_aabb != AABB(): return null
	if mesh.has_node("CameraShaderBounds"): return mesh.get_node("CameraShaderBounds")
	var descriptor: Dictionary = {}
	for index in range(mesh.mesh.get_surface_count()):
		var material := mesh.get_active_material(index) as ShaderMaterial
		if material == null or material.shader == null: continue
		var kind := classify(material.shader.code)
		if str(kind.get("kind", "")) == "sky": descriptor = kind; break
		if not kind.is_empty(): descriptor = kind
	if descriptor.is_empty(): return null
	var controller: Node = load("res://tools/fixtures/camera_shader_bounds.gd").new()
	controller.name = "CameraShaderBounds"
	controller.set("_mesh", mesh)
	controller.set("_kind", descriptor)
	mesh.add_child(controller)
	return controller

static func classify(code: String) -> Dictionary:
	var hash := code.sha256_text()
	if _shader_kinds.has(hash): return _shader_kinds[hash]
	# Ignore comments, including examples of camera-relative expressions in an
	# ordinary material. Only the actual vertex entry point determines bounds.
	var comments := RegEx.new()
	comments.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
	var source := comments.sub(code, "", true)
	var entry := RegEx.new()
	entry.compile("void\\s+vertex\\s*\\(\\s*\\)\\s*\\{")
	var match := entry.search(source)
	var start := match.get_start() if match != null else -1
	var vertex := ""
	if start >= 0:
		var brace := source.find("{", start)
		if brace >= 0:
			var depth := 1
			var end := brace + 1
			while end < source.length() and depth > 0:
				if source[end] == "{": depth += 1
				elif source[end] == "}": depth -= 1
				end += 1
			vertex = source.substr(brace + 1, end - brace - 2)
	var normalized := vertex.replace(" ", "").replace("\t", "").replace("\n", "").replace("\r", "")
	var kind: Dictionary = {}
	# Perspective sky domes project camera-centred vertices directly into clip
	# space. This pattern excludes fragment fog and local camera-facing quads.
	if "CAMERA_POSITION_WORLD" in normalized and "POSITION=" in normalized and "INV_PROJECTION_MATRIX" in normalized and "VIEW_MATRIX*vec4" in normalized:
		kind = {"kind": "sky"}
	# Camera-centred rain fields wrap seeds around the camera, then transform
	# world vertices back to model space. The declared B bounds the field.
	elif "CAMERA_POSITION_WORLD" in normalized and "VERTEX=" in normalized and "inverse(MODEL_MATRIX)" in normalized and "fract(" in normalized:
		var regex := RegEx.new()
		regex.compile("const\\s+float\\s+B\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)\\s*;")
		var declared := regex.search(source)
		if declared != null:
			var field := float(declared.get_string(1))
			if field > 0 and is_finite(field): kind = {"kind": "rain", "field": field}
	_shader_kinds[hash] = kind
	return kind

func _ready() -> void:
	# Headless room servers do not render or update camera-dependent bounds.
	# Run after the ordinary player camera update, before the frame is rendered.
	process_priority = 100
	set_process(DisplayServer.get_name() != "headless")
	if is_processing(): _process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(_mesh) or not _mesh.is_inside_tree() or not _mesh.is_visible_in_tree(): return
	var viewport := _mesh.get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null: refresh_bounds(camera)

func refresh_bounds(camera: Camera3D) -> void:
	if not is_instance_valid(_mesh) or not is_instance_valid(camera): return
	# Authored/API custom bounds set after load supersede this automatic adapter.
	if _mesh.custom_aabb != AABB() and _mesh.custom_aabb != _owned_aabb:
		set_process(false)
		return
	var radius := maxf(camera.far * 1.05 + 32.0, 64.0) if _kind.get("kind") == "sky" else maxf(float(_kind.get("field", 34.0)) * 1.5 + 32.0, 82.0)
	var transform := _mesh.global_transform
	var center := camera.global_position
	if not center.is_finite() or not is_finite(radius) or is_zero_approx(transform.basis.determinant()): return
	if transform == _last_transform and center == _last_camera and radius == _last_radius: return
	# MeshInstance.custom_aabb is local, including arbitrary room origins and
	# nonuniform model transforms. Only these affected instances are changed;
	# shared immutable meshes, materials, vertex animation and collision stay intact.
	_owned_aabb = transform.affine_inverse() * AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	_mesh.custom_aabb = _owned_aabb
	_last_transform = transform
	_last_camera = center
	_last_radius = radius
