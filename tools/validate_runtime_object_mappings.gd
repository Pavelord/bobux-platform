extends SceneTree


class ImportHost:
	extends Node3D

	func _build_block_instance(_shape: String, _color: Color, _material_type: String,
			_transparency: float, _can_collide: bool, block_name: String) -> Node:
		var part := MeshInstance3D.new()
		part.name = block_name
		part.mesh = BoxMesh.new()
		return part

	func _build_imported_block_instance(_shape: String, _color: Color, _material_type: String,
			_transparency: float, _can_collide: bool, block_name: String) -> Node:
		var part := MeshInstance3D.new()
		part.name = block_name
		part.mesh = BoxMesh.new()
		return part


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var placement := Node3D.new()
	placement.name = "Placement"
	root.add_child(placement)
	var host := ImportHost.new()
	host.name = "ImportHost"
	placement.add_child(host)
	var importer = load("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
	importer.scale_factor = 1.0
	var probe_texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	var probe_material := StandardMaterial3D.new()
	importer._apply_surface_textures_to_material(probe_material, probe_texture, probe_texture, probe_texture, probe_texture)
	var pbr_mapping_ok := probe_material.albedo_texture == probe_texture
	pbr_mapping_ok = pbr_mapping_ok and probe_material.normal_enabled and probe_material.normal_texture == probe_texture
	pbr_mapping_ok = pbr_mapping_ok and probe_material.roughness_texture == probe_texture
	pbr_mapping_ok = pbr_mapping_ok and is_equal_approx(probe_material.metallic, 1.0) and probe_material.metallic_texture == probe_texture
	var source := {
		"format": "synthetic",
		"version": 1,
		"instances": {
			"0": {"class": "Workspace", "properties": {"Name": "Workspace"}},
			"1": {"class": "MeshPart", "properties": {"Name": "SyntheticMesh", "Size": [4.0, 4.0, 4.0]}},
			"2": {"class": "SurfaceAppearance", "properties": {
				"Name": "SyntheticPBR", "ColorMap": "rbxassetid://1001", "NormalMap": "rbxassetid://1002",
				"RoughnessMap": "rbxassetid://1003", "MetalnessMap": "rbxassetid://1004"
			}},
			"3": {"class": "Attachment", "properties": {"Name": "Start", "Position": [0.0, 0.0, 0.0]}},
			"4": {"class": "Attachment", "properties": {"Name": "End", "Position": [4.0, 0.0, 0.0]}},
			"5": {"class": "Bone", "properties": {"Name": "Root", "CFrame": null}},
			"6": {"class": "Beam", "properties": {
				"Name": "SyntheticBeam", "Attachment0": {"__rbxdom_ref_target_id": 3}, "Attachment1": {"__rbxdom_ref_target_id": 4}, "Width0": 0.5, "Width1": 0.25,
				"Segments": 4, "Texture": "rbxassetid://2001", "Enabled": true
			}},
			"7": {"class": "Trail", "properties": {
				"Name": "SyntheticTrail", "Attachment0": {"__rbxdom_ref_target_id": 3}, "Attachment1": {"__rbxdom_ref_target_id": 4}, "Lifetime": 1.0,
				"Texture": "rbxassetid://2002", "Enabled": true
			}}
		},
		"hierarchy": [
			{"child": "1", "parent": "0"},
			{"child": "2", "parent": "1"},
			{"child": "3", "parent": "1"},
			{"child": "4", "parent": "1"},
			{"child": "5", "parent": "1"},
			{"child": "6", "parent": "0"},
			{"child": "7", "parent": "0"}
		]
	}
	var report: Dictionary = importer.import_json(source, placement, host)
	await process_frame
	var beam := placement.get_node_or_null("SyntheticBeam") as MeshInstance3D
	var trail := placement.get_node_or_null("SyntheticTrail") as MeshInstance3D
	var part := placement.get_node_or_null("SyntheticMesh") as MeshInstance3D
	var skeleton := part.get_node_or_null("RobloxSkeleton_SyntheticMesh") as Skeleton3D if part != null else null
	var surface_appearance := part.get_node_or_null("SyntheticPBR") if part != null else null
	var attachment0 := part.get_node_or_null("Start") as Node3D if part != null else null
	var ok := pbr_mapping_ok and bool(report.get("ok", false)) and int(report.get("skipped", -1)) == 0
	ok = ok and beam != null and beam.get_script() != null and beam.get_meta("roblox_class", "") == "Beam"
	ok = ok and trail != null and trail.get_script() != null and trail.get_meta("roblox_class", "") == "Trail"
	ok = ok and skeleton != null and skeleton.get_bone_count() == 1
	ok = ok and part != null and part.skeleton == part.get_path_to(skeleton)
	ok = ok and surface_appearance != null and surface_appearance.get_meta("roblox_properties", {}).get("NormalMap", "") == "rbxassetid://1002"
	ok = ok and attachment0 != null and attachment0.get_meta("roblox_class", "") == "Attachment"
	if attachment0 != null:
		attachment0.position += Vector3(0.0, 0.0, 1.0)
	await create_timer(0.08).timeout
	if beam != null and beam.mesh is ImmediateMesh:
		ok = ok and (beam.mesh as ImmediateMesh).get_surface_count() > 0
	if trail != null and trail.mesh is ImmediateMesh:
		ok = ok and (trail.mesh as ImmediateMesh).get_surface_count() > 0
	print("[validate_runtime_object_mappings] ok=", ok, " report=", report,
		" skeleton_bones=", skeleton.get_bone_count() if skeleton != null else -1,
		" beam_surfaces=", (beam.mesh as ImmediateMesh).get_surface_count() if beam != null and beam.mesh is ImmediateMesh else -1,
		" trail_surfaces=", (trail.mesh as ImmediateMesh).get_surface_count() if trail != null and trail.mesh is ImmediateMesh else -1)
	placement.queue_free()
	await process_frame
	quit(0 if ok else 1)
