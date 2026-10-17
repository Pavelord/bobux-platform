extends SceneTree
## Build seasonal materials on the supplied geometry; source FBX files stay intact.
var source_dir := "res://assets/events/halloween2026/source"
var output_dir := "res://assets/events/halloween2026"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source-dir="): source_dir = arg.trim_prefix("--source-dir=")
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	for key in ["gift", "pumpkin"]:
		var packed := load(source_dir.path_join(key + ".fbx")) as PackedScene
		if packed == null: quit(1); return
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		var texture_image := Image.load_from_file(output_dir.path_join(key + "_texture.png"))
		if texture_image == null or texture_image.is_empty(): quit(3); return
		var texture := ImageTexture.create_from_image(texture_image)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.mesh = seasonal_mesh(mesh.mesh, key, texture)
		if key == "pumpkin":
			var light := OmniLight3D.new()
			light.name = "PumpkinGlow"
			light.light_color = Color("ffad32")
			light.light_energy = 0.65
			light.omni_range = 2.8
			light.shadow_enabled = false
			model.add_child(light)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var error := doc.append_from_scene(model, state)
		if error == OK: error = doc.write_to_filesystem(state, output_dir.path_join(key + ".glb"))
		print("[halloween-asset] ", key, " export=", error)
		model.free()
		if error != OK: quit(2); return
	quit(0)

func seasonal_mesh(mesh: Mesh, key: String, texture: Texture2D) -> ArrayMesh:
	var output := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var parent: PackedInt32Array = []
		var positions: Dictionary = {}
		for i in vertices.size():
			parent.append(i)
			var position_key := "%d,%d,%d" % [roundi(vertices[i].x*100000),roundi(vertices[i].y*100000),roundi(vertices[i].z*100000)]
			if positions.has(position_key): parent[i] = int(positions[position_key])
			else: positions[position_key] = i
		for i in range(0, indices.size(), 3):
			parent[find_root(parent, indices[i])] = find_root(parent, indices[i+1])
			parent[find_root(parent, indices[i])] = find_root(parent, indices[i+2])
		var groups: Dictionary = {}
		var counts: Dictionary = {}
		for i in vertices.size():
			var group := find_root(parent, i)
			counts[group] = int(counts.get(group,0)) + 1
		for i in range(0,indices.size(),3):
			var group := find_root(parent, indices[i])
			if not groups.has(group): groups[group] = []
			for j in 3: groups[group].append(indices[i+j])
		for group in groups:
			var count := int(counts[group])
			var material := StandardMaterial3D.new()
			material.roughness = 0.6
			material.albedo_color = Color.WHITE
			material.albedo_texture = texture
			if key == "gift":
				material.metallic = 0.12 if count != 60 else 0.0
			elif count >= 100 and count < 1000:
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_texture = texture
				material.emission_energy_multiplier = 2.2
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(material)
			for index in groups[group]:
				if not normals.is_empty(): tool.set_normal(normals[index])
				if not uv.is_empty(): tool.set_uv(uv[index])
				tool.add_vertex(vertices[index])
			tool.index()
			tool.commit(output)
			print("[halloween-asset] ",key," component_vertices=",count," color=",material.albedo_color," emission=",material.emission_enabled)
	return output

func find_root(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index: index = parent[index]
	return index
