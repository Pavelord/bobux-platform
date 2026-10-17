extends RefCounted
## Static opaque geometry shares draw calls; authored Nodes and physics remain
## intact. Any runtime edit immediately returns that Node to normal rendering.

const CELL_SIZE := 64.0
const ENTRY := &"_bobux_render_batch"
const CONTAINS := &"_bobux_contains_render_batches"

static func detach(node: Node) -> void:
	if not is_instance_valid(node) or not node.has_meta(ENTRY): return
	var entry: Array = node.get_meta(ENTRY)
	node.remove_meta(ENTRY)
	var batch: MultiMeshInstance3D = entry[0].get_ref()
	if is_instance_valid(batch) and batch.multimesh != null:
		var slots: Array = batch.get_meta("slots")
		var transforms: Array = batch.get_meta("transforms")
		var index := int(entry[1])
		var last := slots.size() - 1
		if index != last:
			var moved: MeshInstance3D = slots[last].get_ref()
			batch.multimesh.set_instance_transform(index, transforms[last])
			slots[index] = slots[last]
			transforms[index] = transforms[last]
			if is_instance_valid(moved): moved.get_meta(ENTRY)[1] = index
		slots.pop_back()
		transforms.pop_back()
		batch.multimesh.visible_instance_count = slots.size()
		if slots.is_empty(): batch.visible = false
	if node is MeshInstance3D: node.layers = int(entry[2])

static func detach_tree(node: Node) -> void:
	if not is_instance_valid(node): return
	detach(node)
	if not bool(node.get_meta(CONTAINS, false)): return
	for child in node.get_children(): detach_tree(child)
	node.remove_meta(CONTAINS)

static func _resource_key(resource: Resource, cache: Dictionary, excluded: Array[String]) -> String:
	var id := resource.get_instance_id()
	if cache.has(id): return cache[id]
	var values: Array = [resource.get_class()]
	for property in resource.get_property_list():
		var name_: String = property.name
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or name_ in excluded or name_.begins_with("metadata/"): continue
		var value: Variant = resource.get(name_)
		if value is Object: value = value.get_instance_id() if is_instance_valid(value) else 0
		values.append([name_, value])
	var key := var_to_bytes(values).hex_encode().sha256_text()
	cache[id] = key
	return key

static func _on_exit(id: int) -> void:
	var node: Variant = instance_from_id(id)
	if is_instance_valid(node): detach(node)

static func build(workspace: Node3D) -> Dictionary:
	var groups := {}
	var signatures := {}
	var defaults := MeshInstance3D.new()
	for node in workspace.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.has_meta(ENTRY) or not part.is_visible_in_tree() or part.mesh == null or part.mesh.get_surface_count() != 1: continue
		if bool(part.get_meta("bobux_character_part_proxy", false)): continue
		if part.has_meta("_bobux_surface_assembly") or part.material_overlay != null or part.skeleton != NodePath(""): continue
		var props: Dictionary = part.get_meta("roblox_properties", {})
		if not bool(part.get_meta("anchored", props.get("Anchored", true))): continue
		var body_id := int(part.get_meta("_bobux_physics_body_instance_id", 0))
		var body: Variant = instance_from_id(body_id) if body_id else null
		if is_instance_valid(body) and not body.freeze: continue
		var material := part.get_active_material(0) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass != null: continue
		if part.layers == 0 or part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: continue
		var special_rendering := false
		for property in ["gi_mode", "lod_bias", "extra_cull_margin", "ignore_occlusion_culling", "visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin", "visibility_range_fade_mode", "transparency"]:
			if part.get(property) != defaults.get(property): special_rendering = true; break
		if special_rendering: continue
		var cell := Vector3i((part.global_position / CELL_SIZE).floor())
		# Replication preserves per-part material ownership. Equivalent immutable
		# primitive geometry and material settings can still share one draw call.
		var mesh_key := _resource_key(part.mesh, signatures, ["material", "resource_name", "resource_local_to_scene"]) if part.mesh is PrimitiveMesh else str(part.mesh.get_instance_id())
		var material_key := _resource_key(material, signatures, ["resource_name", "resource_local_to_scene"])
		var key := "%s:%s:%d:%s" % [mesh_key, material_key, part.layers, cell]
		if not groups.has(key): groups[key] = {"mesh": part.mesh, "material": material, "layers": part.layers, "parts": []}
		groups[key].parts.append(part)
	defaults.free()
	var holder := Node3D.new()
	holder.name = "RobloxRenderBatches"
	holder.set_meta("bobux_runtime_generated", true)
	workspace.add_child(holder)
	var saved := 0
	var instances := 0
	for group in groups.values():
		if group.parts.size() < 3: continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		# A part may already own a mutable material/primitive. Freeze the batch's
		# own resources so editing its former first member cannot recolour peers.
		multi.mesh = group.mesh.duplicate(false)
		multi.instance_count = group.parts.size()
		var batch := MultiMeshInstance3D.new()
		batch.set_meta("bobux_runtime_generated", true)
		batch.multimesh = multi
		batch.material_override = group.material.duplicate(false)
		batch.layers = group.layers
		var slots: Array = []
		var transforms: Array = []
		batch.set_meta("slots", slots)
		batch.set_meta("transforms", transforms)
		holder.add_child(batch)
		for index in group.parts.size():
			var part: MeshInstance3D = group.parts[index]
			var transform := holder.global_transform.affine_inverse() * part.global_transform
			multi.set_instance_transform(index, transform)
			slots.append(weakref(part))
			transforms.append(transform)
			part.set_meta(ENTRY, [weakref(batch), index, part.layers])
			var ancestor := part.get_parent()
			while is_instance_valid(ancestor):
				ancestor.set_meta(CONTAINS, true)
				if ancestor == workspace: break
				ancestor = ancestor.get_parent()
			part.layers = 0
			var callback := _on_exit.bind(part.get_instance_id())
			if not part.tree_exiting.is_connected(callback): part.tree_exiting.connect(callback)
			if not part.visibility_changed.is_connected(callback): part.visibility_changed.connect(callback)
		saved += group.parts.size() - 1
		instances += group.parts.size()
	return {"instances": instances, "batches": holder.get_child_count(), "draws_saved": saved}
