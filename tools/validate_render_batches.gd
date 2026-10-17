extends SceneTree
const Batches = preload("res://addons/roblox_runtime/roblox_render_batches.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var model := Node3D.new()
	world.add_child(model)
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	mesh.material = material
	var parts: Array[MeshInstance3D] = []
	for index in 4:
		var part := MeshInstance3D.new()
		part.mesh = mesh.duplicate(false) if index % 2 else mesh
		part.material_override = material.duplicate(false)
		part.position = Vector3(index * 2, 0, 0)
		part.set_meta("roblox_class", "Part")
		part.set_meta("bobux_lua_created_part", true)
		part.material_override.set_meta("bobux_material_owner_id", part.get_instance_id())
		model.add_child(part)
		parts.append(part)
	var result := Batches.build(world)
	print("[render-batches] initial=", result)
	var ok: bool = result.instances == 4 and result.batches == 1 and result.draws_saved == 3
	if not ok:
		world.free()
		quit(1)
		return
	model.visible = false
	ok = ok and parts.all(func(part): return not part.has_meta(Batches.ENTRY) and part.layers == 1)
	model.visible = true
	Batches.build(world)
	var engine := root.get_node("LuaScriptEngine")
	var wrapper = engine.BobuxInstance.wrap(parts[0])
	ok = ok and parts[0].layers == 0 and wrapper._get("layers") == 1 and wrapper.Position == Vector3.ZERO
	print("[render-batches] layers=", parts[0].layers, " lua=", wrapper._get("layers"), " pos=", wrapper.Position)
	var entry: Array = parts[0].get_meta(Batches.ENTRY)
	var batch: MultiMeshInstance3D = entry[0].get_ref()
	wrapper.CFrame = engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(7, 8, 9)))
	ok = ok and not parts[0].has_meta(Batches.ENTRY) and parts[0].layers == 1 and wrapper.CFrame.Position == Vector3(7, 8, 9)
	ok = ok and batch.multimesh.visible_instance_count == 3
	wrapper.Color = Color.BLUE
	ok = ok and batch.material_override.albedo_color == Color.WHITE and parts[0].material_override.albedo_color == Color.BLUE
	print("[render-batches] move=", parts[0].layers, " pose=", wrapper.CFrame.Position, " det=", batch.multimesh.get_instance_transform(0).basis.determinant())
	engine.BobuxInstance.wrap(parts[1]).Color = Color.RED
	ok = ok and parts[1].layers == 1 and parts[2].get_active_material(0).albedo_color == Color.WHITE
	ok = ok and batch.material_override.albedo_color == Color.WHITE
	print("[render-batches] color=", parts[1].layers, " sibling=", parts[2].get_active_material(0).albedo_color)
	parts[2].visible = false
	ok = ok and not parts[2].has_meta(Batches.ENTRY) and parts[2].layers == 1
	print("[render-batches] hidden=", parts[2].layers, " batched=", parts[2].has_meta(Batches.ENTRY))
	parts[3].queue_free()
	await process_frame
	ok = ok and batch.multimesh.visible_instance_count == 0
	print("[render-batches] delete det=", batch.multimesh.get_instance_transform(3).basis.determinant())
	var movable := Node3D.new()
	movable.name = "MovableModel"
	movable.set_meta("roblox_class", "Model")
	world.add_child(movable)
	var moving_parts: Array[MeshInstance3D] = []
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	for index in 4:
		var part := MeshInstance3D.new()
		part.name = "Member%d" % index
		part.mesh = mesh
		part.material_override = blue
		part.position = Vector3(index, 0, 0)
		part.set_meta("roblox_class", "Part")
		movable.add_child(part)
		moving_parts.append(part)
	var model_wrapper = engine.BobuxInstance.wrap(movable)
	Batches.build(world)
	var identities := moving_parts.map(func(part): return part.get_instance_id())
	model_wrapper.PivotTo(engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(5, 6, 7))))
	ok = ok and moving_parts.all(func(part): return not part.has_meta(Batches.ENTRY) and part.layers == 1)
	ok = ok and model_wrapper.GetPivot().Position == Vector3(5, 6, 7) and moving_parts.map(func(part): return part.get_instance_id()) == identities
	Batches.build(world)
	model_wrapper.MoveTo(Vector3(10, 11, 12))
	ok = ok and moving_parts.all(func(part): return not part.has_meta(Batches.ENTRY) and part.layers == 1) and model_wrapper.GetPivot().Position == Vector3(10, 11, 12)
	Batches.build(world)
	model_wrapper.SetProperty("PrimaryPart", engine.BobuxInstance.wrap(moving_parts[1]))
	model_wrapper.SetPrimaryPartCFrame(engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(15, 16, 17))))
	ok = ok and moving_parts.all(func(part): return not part.has_meta(Batches.ENTRY) and part.layers == 1) and engine.BobuxInstance.wrap(moving_parts[1]).Position == Vector3(15, 16, 17)
	Batches.build(world)
	var clone = model_wrapper.Clone()
	ok = ok and moving_parts.all(func(part): return not part.has_meta(Batches.ENTRY) and part.layers == 1)
	ok = ok and clone != null and clone.node.get_children().all(func(part): return part.layers == 1 and not part.has_meta(Batches.ENTRY))
	if clone != null: clone.node.free()
	Batches.build(world)
	model_wrapper.BulkMoveTo([moving_parts[0]], [engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(20, 21, 22)))])
	ok = ok and not moving_parts[0].has_meta(Batches.ENTRY) and moving_parts[0].layers == 1 and engine.BobuxInstance.wrap(moving_parts[0]).Position == Vector3(20, 21, 22)
	print("[render-batches] model operations=", ok, " PivotTo, MoveTo, PrimaryPart, Clone, native BulkMoveTo")
	world.free()
	print("[render-batches] PASS=", ok, " equivalent owned resources, identity, coordinates, edits, visibility, deletion")
	quit(0 if ok else 1)
