extends SubViewportContainer
## Lightweight presentation rig; no player controller, physics or network objects.
var _viewport: SubViewport
var _rig: Node3D
var _wave_arm: Node3D
var _point_arm: Node3D
var _head: Node3D
var _age := 0.0
var _frame_accumulator := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	custom_minimum_size = Vector2(96, 104)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(192, 208)
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var scene := Node3D.new()
	_viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cce5ff")
	environment.environment.ambient_light_energy = 0.45
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -28, 0)
	key.light_energy = 0.85
	scene.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 155, 0)
	fill.light_energy = 0.35
	scene.add_child(fill)
	_rig = Node3D.new()
	_rig.rotation_degrees.y = -12
	scene.add_child(_rig)
	_box(_rig, Vector3(0, 3, 0), Vector3(2, 2, 1), Color("127cdd"))
	_box(_rig, Vector3(-0.51, 1, 0), Vector3(0.98, 2, 1), Color("74ab39"))
	_box(_rig, Vector3(0.51, 1, 0), Vector3(0.98, 2, 1), Color("74ab39"))
	_head = Node3D.new()
	_head.position = Vector3(0, 4.6, 0)
	_rig.add_child(_head)
	var head_mesh := MeshInstance3D.new()
	head_mesh.mesh = _bobux_head()
	head_mesh.material_override = _material(Color("ffce38"))
	_head.add_child(head_mesh)
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.77, 0.8)
	face.mesh = quad
	face.position = Vector3(0, -0.015, 0.623)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D face_texture : source_color; void fragment(){ vec4 ink=texture(face_texture,UV); ALBEDO=vec3(0.035,0.025,0.02); ALPHA=(1.0-ink.r)*ink.a; }"
	var face_material := ShaderMaterial.new()
	face_material.shader = shader
	face_material.set_shader_parameter("face_texture", load("res://assets/avatar/default_face.png"))
	face.material_override = face_material
	_head.add_child(face)
	_wave_arm = _arm(Vector3(-1.5, 3.9, 0))
	_point_arm = _arm(Vector3(1.5, 3.9, 0))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.4
	camera.position = Vector3(1.2, 4.2, 11)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 2.9, 0))
	camera.current = true
	visibility_changed.connect(_update_visibility)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_frame_accumulator += delta
	if _frame_accumulator < 1.0 / 30.0: return
	_age += _frame_accumulator
	var step := _frame_accumulator
	_frame_accumulator = 0
	var wave_angle := -2.5 + sin(_age * 5.5) * 0.24
	_wave_arm.rotation.z = lerp_angle(_wave_arm.rotation.z, wave_angle, minf(step * 8, 1))
	_point_arm.rotation.z = 0.06
	_head.rotation.y = sin(_age * 1.1) * 0.04
	_rig.position.y = sin(_age * 1.8) * 0.055
	_rig.rotation.z = sin(_age * 1.3) * 0.025
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_visibility() -> void:
	if not is_visible_in_tree(): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _arm(at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_rig.add_child(pivot)
	_box(pivot, Vector3(0, -0.85, 0), Vector3(1, 2, 1), Color("ffce38"))
	return pivot

func _box(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = at
	parent.add_child(mesh)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material

static var _cached_head: Mesh
static func _bobux_head() -> Mesh:
	if _cached_head != null: return _cached_head
	# Use the very same rounded head as the game character, with no controller
	# or multiplayer objects instantiated just to render a home-page greeting.
	var source := load("res://files/RolandStudioNoHatsRBLX.obj") as ArrayMesh
	var highest := -INF
	if source != null:
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty(): continue
			var bounds := AABB(vertices[0], Vector3.ZERO)
			for vertex in vertices: bounds = bounds.expand(vertex)
			if bounds.get_center().y <= highest: continue
			highest = bounds.get_center().y
			for index in vertices.size(): vertices[index] -= bounds.get_center()
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_cached_head = mesh
	if _cached_head == null:
		var fallback := CapsuleMesh.new()
		fallback.radius = 0.6
		fallback.height = 1.2
		_cached_head = fallback
	return _cached_head
