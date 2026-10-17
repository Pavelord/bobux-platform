extends SceneTree

const BOUNDS := preload("res://tools/fixtures/camera_shader_bounds.gd")
const CACHE := "user://cache/maps/akx0oto939gi501_dolina_semi_vetrov"
const SHADERS := "res://.codex-tmp/performance/valley-visual-motion/shaders.json"
var failures: Array[String] = []
var checks := 0
var report: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message): failures.append(message)

func run() -> void:
	await process_frame
	var shader_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHADERS))
	if not shader_data is Dictionary:
		push_error("Run the original Valley mesh audit before this validation.")
		quit(2)
		return
	var classified: Dictionary = {}
	for hash: String in shader_data:
		var data: Dictionary = shader_data[hash]
		var code: String = data.code
		var kind: Dictionary = BOUNDS.classify(code)
		classified[",".join(data.files)] = kind
		var expected := "sky" if "skyb.res" in data.files else ("rain" if "rainb.res" in data.files else "")
		check(str(kind.get("kind", "")) == expected, "Classify original " + ",".join(data.files))
		check(BOUNDS.classify(code) == kind, "Cached classification is stable")
	var fog := "shader_type spatial; void vertex() { VERTEX += NORMAL * 0.2; } void fragment() { ALBEDO = vec3(length(CAMERA_POSITION_WORLD)); }"
	check(BOUNDS.classify(fog).is_empty(), "Fragment fog does not change vertex bounds")
	check(BOUNDS.classify("/* void vertex(){ CAMERA_POSITION_WORLD; POSITION=INV_PROJECTION_MATRIX*VIEW_MATRIX*vec4(0.0); } */ " + fog).is_empty(), "Commented example does not cause false positive")
	check(BOUNDS.classify("shader_type spatial; void vertex() { VERTEX = mat3(INV_VIEW_MATRIX) * VERTEX; } void fragment() { ALBEDO=vec3(1.0); }").is_empty(), "Ordinary camera-facing billboard is excluded")
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	camera.current = true
	camera.near = 0.14
	camera.far = 420.0
	await process_frame
	var assets: Dictionary = {}
	for file: String in ["skyb.res", "rainb.res"]:
		var resource := load(CACHE.path_join(file)) as ArrayMesh
		check(resource != null, "Published asset loads: " + file)
		if resource == null: continue
		var original_resource_bounds := resource.custom_aabb
		var original_mesh_bounds := resource.get_aabb()
		print("[camera-shader-bounds] original resource=", file, " custom_aabb=", original_resource_bounds, " aabb=", original_mesh_bounds)
		var original_material := resource.surface_get_material(0)
		var original_shader_code := (original_material as ShaderMaterial).shader.code
		var mesh := MeshInstance3D.new()
		mesh.mesh = resource
		stage.add_child(mesh)
		check(BOUNDS.attach(mesh) == null, "Published authored resource already has conservative custom bounds")
		var prototype_resource := resource.duplicate() as ArrayMesh
		prototype_resource.custom_aabb = AABB()
		mesh.mesh = prototype_resource
		var controller := BOUNDS.attach(mesh)
		check(controller != null, "Attach only to diagnostic copy with bounds cleared: " + file)
		if controller == null: continue
		check(BOUNDS.attach(mesh) == controller, "Repeated attach keeps one controller")
		check(not controller.is_processing(), "Headless server does not process render bounds")
		var count := 0
		var old_excluded := 0
		for origin: Vector3 in [Vector3.ZERO, Vector3(46, 24, 26), Vector3(15000, -200, 27000)]:
			for scale_value: Vector3 in [Vector3.ONE, Vector3(0.5, 2.0, 0.25)]:
				mesh.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.6, -0.2)).scaled(scale_value), origin)
				for far_distance: float in [120.0, 420.0, 1500.0]:
					camera.far = far_distance
					for yaw in range(0, 360, 15):
						for pitch: float in [-0.2, 0.35, 0.9]:
							camera.position = origin + Vector3(46, 24, 26) + Vector3(float(yaw) * 0.03, 0, float(yaw) * -0.02)
							camera.rotation = Vector3(pitch, deg_to_rad(float(yaw)), 0)
							camera.force_update_transform()
							controller.refresh_bounds(camera)
							var local_inverse := mesh.global_transform.affine_inverse()
							var fixed := mesh.custom_aabb
							check(fixed.has_point(local_inverse * camera.global_position), "Camera lies within camera-relative bounds")
							var world_fixed := mesh.global_transform * fixed
							check(camera.is_position_in_frustum(camera.global_position - camera.global_basis.z * camera.far * 0.9), "Expected sky vertex is inside frustum")
							var extent := camera.far * 0.9 if file == "skyb.res" else 18.64
							for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, -camera.global_basis.z]:
								var expected_point := camera.global_position + direction * extent
								check(fixed.has_point(local_inverse * expected_point), "Shader vertex envelope lies within local bounds")
								check(world_fixed.has_point(expected_point), "Shader vertex envelope lies within transformed world bounds")
							if file == "rainb.res": check(fixed.has_point(local_inverse * (camera.global_position + Vector3(0, -50, 0))), "Hidden rain seeds remain inside bounds")
							var forward := camera.global_position - camera.global_basis.z * extent
							if not original_mesh_bounds.has_point(local_inverse * forward): old_excluded += 1
							count += 1
		assets[file] = {"poses": count, "original_bounds_exclude_forward_vertex": old_excluded, "original_aabb": str(original_mesh_bounds), "fixed_aabb": str(mesh.custom_aabb)}
		check(resource.custom_aabb == original_resource_bounds and resource.get_aabb() == original_mesh_bounds, "Shared mesh resource bounds are untouched")
		check(resource.surface_get_material(0) == original_material and (original_material as ShaderMaterial).shader.code == original_shader_code, "Original authored material and shader source are untouched")
		var after_load_authored := AABB(Vector3(-7, -7, -7), Vector3(14, 14, 14))
		mesh.custom_aabb = after_load_authored
		camera.position += Vector3(500, 300, 100)
		controller.refresh_bounds(camera)
		check(mesh.custom_aabb == after_load_authored, "Explicit bounds set through API after load supersede adapter")
		var authored_instance := MeshInstance3D.new()
		authored_instance.mesh = resource
		authored_instance.custom_aabb = after_load_authored
		stage.add_child(authored_instance)
		check(BOUNDS.attach(authored_instance) == null, "Existing authored instance bounds are preserved")
		var authored_resource := resource.duplicate() as ArrayMesh
		authored_resource.custom_aabb = after_load_authored
		var authored_mesh := MeshInstance3D.new()
		authored_mesh.mesh = authored_resource
		stage.add_child(authored_mesh)
		check(BOUNDS.attach(authored_mesh) == null, "Existing authored resource bounds are preserved")
	report = {"renderer": DisplayServer.get_name(), "checks": checks, "classification": classified, "assets": assets, "failures": failures}
	var output := FileAccess.open("res://.codex-tmp/performance/valley-visual-motion/camera-bounds-validation.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report, "\t"))
	print("[camera-shader-bounds] ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " assets=", assets, " failures=", failures)
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
