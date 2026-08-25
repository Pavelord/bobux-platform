extends SceneTree


func _initialize() -> void:
	ProjectSettings.set_setting("bobux/prefetch_remote_rbxl_assets", false)
	var source_path := "C:/Users/Pavel/Downloads/Ronaldinho2k20 - Escape Memes Obby.rbxl"
	var scene: PackedScene = load("res://scenes/place_editor/studio.tscn")
	var studio := scene.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	await studio._on_rbxl_file_selected(source_path)
	await process_frame
	var target := _find_mesh_asset(studio.get("placement_parent"), "151778863")
	var ok := target != null and target.mesh != null
	var visual_size := Vector3.ZERO
	var expected_size := Vector3.ZERO
	if ok:
		visual_size = target.mesh.get_aabb().size * target.scale.abs()
		# Roblox FileMesh Scale is relative to the uploaded source mesh bounds,
		# unlike primitive SpecialMesh types which scale from the parent Part.Size.
		# The fixture uses Scale=(10,10,10) and Bobux maps one stud to 0.5 units.
		expected_size = Vector3(1.757005, 1.64372, 1.94692) * 5.0
		ok = visual_size.distance_to(expected_size) < 0.25
	print("[validate_rbxl_special_mesh_scale] ok=", ok, " visual_size=", visual_size, " expected=", expected_size)
	studio.free()
	quit(0 if ok else 1)


func _find_mesh_asset(node: Node, asset_id: String) -> MeshInstance3D:
	if node is MeshInstance3D and str(node.get_meta("roblox_mesh_id", "")).contains(asset_id):
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_asset(child, asset_id)
		if found != null:
			return found
	return null
