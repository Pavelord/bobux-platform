extends SceneTree
var bridge: Node
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func make_case(kind: String) -> Node3D:
	var branch := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = "shader_type spatial; instance uniform vec4 tint : source_color = vec4(1.0); void fragment() { ALBEDO=tint.rgb; }"
	if kind.contains("pass"): material.next_pass = shader_material
	var mesh: Mesh = BoxMesh.new()
	if kind.contains("array"):
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
		if kind.contains("multi"):
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	if kind.contains("embedded"): mesh.surface_set_material(0, material)
	for _index in 8:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		if kind.contains("override"): part.material_override = material
		if kind.contains("surface"): part.set_surface_override_material(0, material)
		if kind.contains("multi"):
			part.set_surface_override_material(0, material.duplicate(true))
			part.set_surface_override_material(1, shader_material.duplicate(true))
		if kind.contains("overlay"): part.material_overlay = shader_material
		branch.add_child(part)
	return branch

func run() -> void:
	bridge = root.get_node("ImportedPlaceNetwork")
	for kind in ["embedded", "override", "surface", "embedded-pass", "override-pass", "surface-pass", "embedded-overlay", "override-overlay", "embedded-pass-overlay", "override-pass-overlay", "surface-pass-overlay", "array-embedded", "array-embedded-pass", "array-embedded-pass-overlay", "array-surface-pass", "array-override-pass", "array-multi", "array-multi-pass"]:
		print("[retire-probe] kind=", kind)
		for _index in 3:
			var branch := make_case(kind)
			root.add_child(branch)
			await process_frame
			bridge.retire_tree(branch)
			while not bridge._retired.is_empty(): await process_frame
		await process_frame
	var folder := "res://.codex-tmp/performance-server/Godot/app_userdata/Bobux/cache/maps/akx0oto939gi501_bobux_park_krut"
	for filename in ["bobux_model_mesh_001.res", "bobux_model_mesh_006.res", "bobux_model_mesh_013.res", "bobux_model_mesh_016.res"]:
		print("[retire-probe] native=", filename)
		var branch := Node3D.new()
		var part := MeshInstance3D.new()
		part.mesh = ResourceLoader.load(folder.path_join(filename), "Mesh", ResourceLoader.CACHE_MODE_IGNORE)
		for index in part.mesh.get_surface_count(): print("[retire-probe] material=", part.mesh.surface_get_material(index))
		branch.add_child(part)
		root.add_child(branch)
		await process_frame
		bridge.retire_tree(branch)
		while not bridge._retired.is_empty(): await process_frame
		await process_frame
	# Freeing one instance must leave a shared mesh/material and survivor intact.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	var shader := ShaderMaterial.new()
	shader.shader = Shader.new()
	shader.shader.code = "shader_type spatial; void fragment(){ ALBEDO=vec3(1.0); }"
	material.next_pass = shader
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	mesh.surface_set_material(0, material)
	var survivor := MeshInstance3D.new()
	survivor.mesh = mesh
	survivor.material_overlay = shader
	root.add_child(survivor)
	var branch := Node3D.new()
	var retired := MeshInstance3D.new()
	retired.mesh = mesh
	retired.material_overlay = shader
	retired.set_surface_override_material(0, material)
	branch.add_child(retired)
	root.add_child(branch)
	var retired_ref: WeakRef = weakref(retired)
	bridge.retire_tree(branch)
	while not bridge._retired.is_empty(): await process_frame
	if retired_ref.get_ref() != null: failures.append("Retired mesh instance leaked")
	if survivor.mesh != mesh or mesh.surface_get_material(0) != material or material.next_pass != shader or survivor.material_overlay != shader:
		failures.append("Shared render resources changed")
	var resources: Array[WeakRef] = [weakref(mesh), weakref(material), weakref(shader)]
	bridge.retire_tree(survivor)
	while not bridge._retired.is_empty(): await process_frame
	mesh = null
	material = null
	shader = null
	for index in 3: await process_frame
	for resource: WeakRef in resources:
		if resource.get_ref() != null: failures.append("Retirement held render resource after free")
	# Avatar previews use direct queue_free, outside the room retirement queue.
	# NameLabel also has renderer-owned font/outline materials.
	var avatar := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
	avatar.set("is_ui_preview", true)
	avatar.set("use_local_avatar_fallback", false)
	root.add_child(avatar)
	await process_frame
	var label := Label3D.new()
	label.text = "Preview teardown"
	avatar.add_child(label)
	var avatar_ref: WeakRef = weakref(avatar)
	var head := avatar.get_node("Visuals/Head") as MeshInstance3D
	var shared_head: Mesh = head.mesh
	var survivor_head := MeshInstance3D.new()
	survivor_head.mesh = shared_head
	root.add_child(survivor_head)
	avatar.queue_free()
	for index in 3: await process_frame
	if avatar_ref.get_ref() != null: failures.append("Direct preview deletion leaked avatar")
	if survivor_head.mesh != shared_head or shared_head.get_surface_count() == 0:
		failures.append("Preview deletion altered shared character mesh")
	bridge.retire_tree(survivor_head)
	while not bridge._retired.is_empty(): await process_frame
	shared_head = null
	print("[retire-probe] complete failures=", failures)
	quit(0 if failures.is_empty() else 1)
