extends SceneTree

const IMPORTER = preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")
const DATA = preload("res://addons/roblox_studio/roblox_data_model.gd")
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, detail: String):
	print("[published_visuals] ", detail, "=", ok)
	if not ok: failures.append(detail)

func run():
	var world := Node3D.new()
	root.add_child(world)
	var water := DATA.create_instance("Part", "Water") as MeshInstance3D
	water.scale = Vector3(5,0.5,5)
	water.set_meta("roblox_ref", "water")
	world.add_child(water)
	var mesh := Node.new()
	mesh.set_meta("roblox_class", "BlockMesh")
	mesh.set_meta("roblox_ref", "water_mesh")
	mesh.set_meta("roblox_properties", {"Scale":[1000,0.1,1000]})
	water.add_child(mesh)
	var importer := IMPORTER.new()
	importer.restore_part_children(water)
	check((water.transform * water.get_aabb()).size.is_equal_approx(Vector3(5000,0.05,5000)), "ocean retains authored BlockMesh scale")
	importer.restore_part_children(water)
	check((water.transform * water.get_aabb()).size.is_equal_approx(Vector3(5000,0.05,5000)), "restoring appearance twice never compounds scale")
	var path := "user://validation/streamed_poster.png"
	var pixels := Image.create(16,16,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.CORNFLOWER_BLUE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	pixels.save_png(path)
	var poster := Node.new()
	poster.set_meta("roblox_class", "Decal")
	poster.set_meta("roblox_ref", "poster")
	poster.set_meta("roblox_properties", {"Texture":path, "Face":5})
	water.add_child(poster)
	importer.restore_part_children(water)
	var faces := []
	for child in water.get_children():
		if child.get_meta("roblox_face_decal",false): faces.append(child)
	check(faces.size()==1 and faces[0].mesh is QuadMesh, "poster uses a renderer-compatible face quad")
	check(not preload("res://addons/roblox_runtime/roblox_spatial_query.gd").is_part(faces[0]), "poster is never a physical building brick")
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("bobux_studio_playtest",true)
	world.add_child(player)
	player.set_physics_process(false)
	var seat := DATA.create_instance("VehicleSeat", "Seat") as MeshInstance3D
	seat.rotation.y = 1.3
	world.add_child(seat)
	player._enter_seat(seat)
	player._update_seated_movement(false,Vector2(0,-1))
	var look: Basis = player.camera_pivot.global_basis
	player._leave_seat(true)
	check(player.rotation.is_equal_approx(Vector3.ZERO) and player.camera_pivot.global_basis.is_equal_approx(look), "seat exit restores world movement without turning camera")
	check(seat.get_meta("Throttle")==0 and not seat.has_meta("Occupant"), "seat exit clears throttle and occupant")
	var loading_script = load("res://scripts/ui/experience_loading.gd")
	var first = loading_script.new()
	root.add_child(first)
	await first.set_experience("Test Island", {"thumbnail":path})
	var cover: Texture2D = first.preview.texture
	first.free()
	var next = loading_script.new()
	root.add_child(next)
	next.set_experience("Test Island", {})
	check(next.preview.texture == cover and next.preview.visible and not next.subtitle.visible and not next.transport.visible, "scene transition keeps the same cover and hides transport details")
	next.queue_free()
	world.queue_free()
	await process_frame
	print("[published_visuals] failures=", failures)
	quit(0 if failures.is_empty() else 1)
