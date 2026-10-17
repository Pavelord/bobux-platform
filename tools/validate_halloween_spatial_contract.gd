extends SceneTree
const QUERY := preload("res://addons/roblox_runtime/roblox_spatial_query.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func reference_overlap(frame: Transform3D, size_: Vector3, part: MeshInstance3D) -> bool:
	var box := QUERY.bounds(part)
	var query_basis := frame.basis.orthonormalized()
	var part_basis := part.global_basis.orthonormalized()
	var half := size_.abs() * 0.5
	var query_bounds := Transform3D(query_basis, frame.origin) * AABB(-half, half * 2)
	if not query_bounds.grow(0.00001).intersects(part.global_transform * box): return false
	var extent := box.size * part.global_basis.get_scale().abs() * 0.5
	var offset := part.to_global(box.get_center()) - frame.origin
	var axes: Array[Vector3] = [query_basis.x, query_basis.y, query_basis.z, part_basis.x, part_basis.y, part_basis.z]
	for a in [query_basis.x, query_basis.y, query_basis.z]:
		for b in [part_basis.x, part_basis.y, part_basis.z]: axes.append(a.cross(b))
	for axis in axes:
		if axis.length_squared() < 0.00000001: continue
		var a := absf(axis.dot(query_basis.x))*half.x + absf(axis.dot(query_basis.y))*half.y + absf(axis.dot(query_basis.z))*half.z
		var b := absf(axis.dot(part_basis.x))*extent.x + absf(axis.dot(part_basis.y))*extent.y + absf(axis.dot(part_basis.z))*extent.z
		if absf(axis.dot(offset)) > a+b+0.00001: return false
	return true

func run() -> void:
	var world := Node3D.new()
	world.position = Vector3(600000,0,630000)
	root.add_child(world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var parts: Array[MeshInstance3D] = []
	for i in range(240):
		var part := MeshInstance3D.new()
		part.mesh = BoxMesh.new()
		part.set_meta("roblox_class", "Part")
		world.add_child(part)
		part.position = Vector3(rng.randf_range(-40,40),rng.randf_range(-8,8),rng.randf_range(-40,40))
		part.scale = Vector3(rng.randf_range(.1,20),rng.randf_range(.1,10),rng.randf_range(.1,20))
		if i % 3 == 1: part.rotation.y = PI * .5
		elif i % 3 == 2: part.rotation = Vector3(.3,.7,.2)
		parts.append(part)
	for iteration in range(150):
		var moved := parts[iteration % parts.size()]
		moved.position += Vector3(1.2,0,-.7)
		QUERY.invalidate(moved)
		var center := world.global_position + Vector3(rng.randf_range(-35,35),rng.randf_range(-4,4),rng.randf_range(-35,35))
		var basis := Basis.IDENTITY if iteration % 2 == 0 else Basis.from_euler(Vector3(.13,.31,.2))
		var frame := Transform3D(basis,center)
		var size_ := Vector3(rng.randf_range(1,20),rng.randf_range(1,12),rng.randf_range(1,20))
		var actual := QUERY.in_box(world,frame,size_,[],false,0,false)
		for part in parts:
			if actual.has(part) != reference_overlap(frame,size_,part): failures.append("overlap/dirty cell mismatch at query %d" % iteration); break
	var before := QUERY.full_builds
	var hidden := parts[0]
	hidden.hide()
	var full := QUERY.in_box(world,Transform3D(Basis.IDENTITY,world.global_position),Vector3.ONE*200,[],false,0,false)
	if full.has(hidden): failures.append("hidden Part remains indexed")
	hidden.show()
	full = QUERY.in_box(world,Transform3D(Basis.IDENTITY,world.global_position),Vector3.ONE*200,[],false,0,false)
	if not full.has(hidden): failures.append("visible Part not reindexed")
	if QUERY.full_builds != before: failures.append("dirty cells rebuild the full world")
	world.queue_free()
	await process_frame
	QUERY.invalidate()
	print("[halloween-spatial-contract] PASS=",failures.is_empty()," exact comparisons=36000 failures=",failures)
	quit(0 if failures.is_empty() else 1)
