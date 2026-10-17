extends RefCounted
## Only for nodes about to be destroyed. Keep shared resource data untouched;
## remove renderer dependencies before native destructors release materials.

static func detach_render_instance(node: Node) -> Array[Resource]:
	var held: Array[Resource] = []
	if not node is GeometryInstance3D: return held
	if node.material_override != null: held.append(node.material_override)
	if node.material_overlay != null: held.append(node.material_overlay)
	if node is MeshInstance3D:
		if node.mesh != null: held.append(node.mesh)
		for index in node.get_surface_override_material_count():
			var material: Material = node.get_surface_override_material(index)
			if material != null: held.append(material)
		# Preserve native surface-array sizes while clearing the overrides.
		for index in node.get_surface_override_material_count(): node.set_surface_override_material(index, null)
		node.mesh = null
	elif node is MultiMeshInstance3D:
		if node.multimesh != null: held.append(node.multimesh)
		node.multimesh = null
	node.material_override = null
	node.material_overlay = null
	# Label3D and particles own native mesh/material data that is not exposed
	# through MeshInstance3D. Their dependencies also stop before destruction.
	var instance: RID = node.get_instance()
	if instance.is_valid(): RenderingServer.instance_set_base(instance, RID())
	return held

static func detach_render_tree(root: Node) -> void:
	if not is_instance_valid(root): return
	var pending: Array[Node] = [root]
	var held: Array[Resource] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		held.append_array(detach_render_instance(node))
