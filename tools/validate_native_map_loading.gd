extends SceneTree


func _initialize() -> void: run.call_deferred()

func run() -> void:
	var folder := "user://native_map_loading_validation"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("mesh.res")
	var original := ArrayMesh.new()
	var primitive := BoxMesh.new()
	original.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, primitive.get_mesh_arrays())
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	original.surface_set_material(0, shader_material)
	assert(ResourceSaver.save(original, path) == OK)
	var cached := load(path) as Mesh
	var main = load("res://scripts/main/main.gd").new()
	var first := MeshInstance3D.new()
	var second := MeshInstance3D.new()
	for instance in [first, second]:
		instance.mesh = BoxMesh.new()
		main._apply_saved_bobux_mesh_resource(instance, {"bobux_mesh_resource_asset": "mesh.res"}, folder)
	assert(first.mesh == cached and second.mesh == cached, "Repeated native assets must share immutable geometry")
	assert(first.get_active_material(0) == cached.surface_get_material(0), "Embedded shader must survive loading")
	first.set_surface_override_material(0, StandardMaterial3D.new())
	assert(second.get_active_material(0) == cached.surface_get_material(0), "Per-part edits must not alter siblings")
	first.free()
	second.free()
	main.free()
	var probe: Node = load("res://tools/native_map_download_probe.gd").new()
	root.add_child(probe)
	var urls := {}
	for i in probe.MAP_VISUAL_ASSET_PREFETCH_CONCURRENCY + 2:
		urls["%d.res" % i] = "https://invalid.example/test"
	var result: Dictionary = await probe._ensure_cached_map_visual_assets(folder, str(Time.get_ticks_usec()), {"mode_asset_urls": urls}, true)
	assert(result.ok and result.downloaded == urls.size())
	assert(probe.peak <= probe.MAP_VISUAL_ASSET_PREFETCH_CONCURRENCY)
	var next := "%d.res" % probe.MAP_VISUAL_ASSET_PREFETCH_CONCURRENCY
	assert(probe.launched[next] < probe.finished["0.res"], "Slow request must not stall free download slots")
	print("[native-map-loading] PASS shared geometry, isolated materials, bounded rolling downloads")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder.path_join("visual_assets.ready"))
	probe.queue_free()
	quit(0)
