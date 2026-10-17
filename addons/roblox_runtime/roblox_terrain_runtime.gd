@tool
class_name RobloxTerrainRuntime
extends RefCounted

## Runtime terrain backend shared by Luau and the Studio terrain editor.
## Terrain is stored as the same GridMap + Cells metadata that Studio saves.

const TERRAIN_CLASS_META := "roblox_class"
const TERRAIN_NODE_NAME := "Terrain"
const GRID_NODE_NAME := "EditableTerrainGrid"
const DEFAULT_CELL_SIZE := 2.0
const MATERIALS := [
	{"name": "Grass", "color": Color("#5A9B45")},
	{"name": "Ground", "color": Color("#76563B")},
	{"name": "Rock", "color": Color("#74777C")},
	{"name": "Sand", "color": Color("#D9C58B")},
	{"name": "Snow", "color": Color("#E8EEF2")},
	{"name": "Water", "color": Color(0.18, 0.55, 0.88, 0.72)},
	{"name": "Mud", "color": Color("#574334")},
	{"name": "Concrete", "color": Color("#A6A6A6")},
]


static func terrain_for_workspace(workspace: Node) -> Node3D:
	if workspace == null or not is_instance_valid(workspace) or not workspace is Node3D:
		return null
	for child in workspace.get_children():
		if child is Node3D and (str(child.get_meta(TERRAIN_CLASS_META, "")) == "Terrain" or str(child.name) == TERRAIN_NODE_NAME):
			var terrain := child as Node3D
			terrain.set_meta(TERRAIN_CLASS_META, "Terrain")
			_ensure_grid(terrain)
			return terrain
	var terrain := Node3D.new()
	terrain.name = TERRAIN_NODE_NAME
	terrain.set_meta(TERRAIN_CLASS_META, "Terrain")
	terrain.set_meta("block_name", TERRAIN_NODE_NAME)
	terrain.set_meta("is_roblox_service", true)
	workspace.add_child(terrain, true)
	_ensure_grid(terrain)
	return terrain


static func fill_block(terrain: Node, world_transform: Transform3D, size: Vector3, material_value: Variant) -> int:
	var grid := _ensure_grid(terrain)
	if grid == null:
		return 0
	var half := size.abs() * 0.5
	if half.is_zero_approx():
		return 0
	var local_transform := grid.global_transform.affine_inverse() * world_transform
	var extent := local_transform.basis.x.abs() * half.x + local_transform.basis.y.abs() * half.y + local_transform.basis.z.abs() * half.z
	var minimum := grid.local_to_map(local_transform.origin - extent)
	var maximum := grid.local_to_map(local_transform.origin + extent)
	var material_id := _material_index(material_value)
	var changed := 0
	var inverse := local_transform.affine_inverse()
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				var center := inverse * grid.map_to_local(cell)
				if absf(center.x) > half.x or absf(center.y) > half.y or absf(center.z) > half.z:
					continue
				changed += _set_cell(grid, cell, material_id)
	_finish_edit(terrain, grid)
	return changed


static func fill_ball(terrain: Node, world_center: Vector3, radius: float, material_value: Variant) -> int:
	var grid := _ensure_grid(terrain)
	var world_radius := maxf(radius, 0.0)
	if grid == null or world_radius <= 0.0:
		return 0
	var center := grid.to_local(world_center)
	var extent := Vector3.ONE * world_radius
	var minimum := grid.local_to_map(center - extent)
	var maximum := grid.local_to_map(center + extent)
	var radius_squared := world_radius * world_radius
	var material_id := _material_index(material_value)
	var changed := 0
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				if grid.map_to_local(cell).distance_squared_to(center) <= radius_squared:
					changed += _set_cell(grid, cell, material_id)
	_finish_edit(terrain, grid)
	return changed


static func fill_cylinder(terrain: Node, world_transform: Transform3D, height: float, radius: float, material_value: Variant) -> int:
	var grid := _ensure_grid(terrain)
	var half_height := maxf(height, 0.0) * 0.5
	var world_radius := maxf(radius, 0.0)
	if grid == null or half_height <= 0.0 or world_radius <= 0.0:
		return 0
	var local_transform := grid.global_transform.affine_inverse() * world_transform
	var half := Vector3(world_radius, half_height, world_radius)
	var extent := local_transform.basis.x.abs() * half.x + local_transform.basis.y.abs() * half.y + local_transform.basis.z.abs() * half.z
	var minimum := grid.local_to_map(local_transform.origin - extent)
	var maximum := grid.local_to_map(local_transform.origin + extent)
	var inverse := local_transform.affine_inverse()
	var material_id := _material_index(material_value)
	var changed := 0
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				var local := inverse * grid.map_to_local(cell)
				if absf(local.y) > half_height or local.x * local.x + local.z * local.z > world_radius * world_radius:
					continue
				changed += _set_cell(grid, cell, material_id)
	_finish_edit(terrain, grid)
	return changed


static func fill_wedge(terrain: Node, world_transform: Transform3D, size: Vector3, material_value: Variant) -> int:
	var grid := _ensure_grid(terrain)
	var half := size.abs() * 0.5
	if grid == null or half.is_zero_approx():
		return 0
	var local_transform := grid.global_transform.affine_inverse() * world_transform
	var extent := local_transform.basis.x.abs() * half.x + local_transform.basis.y.abs() * half.y + local_transform.basis.z.abs() * half.z
	var minimum := grid.local_to_map(local_transform.origin - extent)
	var maximum := grid.local_to_map(local_transform.origin + extent)
	var inverse := local_transform.affine_inverse()
	var material_id := _material_index(material_value)
	var changed := 0
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				var local := inverse * grid.map_to_local(cell)
				var upper_edge := (local.x / maxf(half.x, 0.0001)) * half.y
				if absf(local.x) > half.x or absf(local.z) > half.z or local.y < -half.y or local.y > upper_edge:
					continue
				changed += _set_cell(grid, cell, material_id)
	_finish_edit(terrain, grid)
	return changed


static func clear(terrain: Node) -> void:
	var grid := _ensure_grid(terrain)
	if grid == null:
		return
	grid.clear()
	_finish_edit(terrain, grid)


static func world_to_cell(terrain: Node, world_position: Vector3) -> Vector3:
	var grid := _ensure_grid(terrain)
	if grid == null:
		return Vector3.ZERO
	var cell := grid.local_to_map(grid.to_local(world_position))
	return Vector3(cell)


static func cell_center_to_world(terrain: Node, x: int, y: int, z: int) -> Vector3:
	var grid := _ensure_grid(terrain)
	if grid == null:
		return Vector3.ZERO
	return grid.to_global(grid.map_to_local(Vector3i(x, y, z)))


static func cell_corner_to_world(terrain: Node, x: int, y: int, z: int) -> Vector3:
	var grid := _ensure_grid(terrain)
	if grid == null:
		return Vector3.ZERO
	var corner_offset := Vector3(-grid.cell_size.x, -grid.cell_size.y, grid.cell_size.z) * 0.5
	return grid.to_global(grid.map_to_local(Vector3i(x, y, z)) + corner_offset)


static func count_cells(terrain: Node) -> int:
	var grid := _ensure_grid(terrain)
	return grid.get_used_cells().size() if grid != null else 0


static func _ensure_grid(terrain: Node) -> GridMap:
	if terrain == null or not is_instance_valid(terrain):
		return null
	var grid := terrain.get_node_or_null(NodePath(GRID_NODE_NAME)) as GridMap
	var properties: Dictionary = terrain.get_meta("roblox_properties", {}) if terrain.get_meta("roblox_properties", {}) is Dictionary else {}
	var cell_size := clampf(float(properties.get("CellSize", DEFAULT_CELL_SIZE)), 0.25, 16.0)
	if grid == null:
		grid = GridMap.new()
		grid.name = GRID_NODE_NAME
		grid.set_meta("bobux_runtime_generated", true)
		terrain.add_child(grid, true)
	grid.cell_size = Vector3.ONE * cell_size
	grid.cell_center_x = true
	grid.cell_center_y = true
	grid.cell_center_z = true
	grid.collision_layer = 1
	grid.collision_mask = 1
	if grid.mesh_library == null:
		grid.mesh_library = _build_mesh_library(cell_size)
	_restore_metadata_cells(terrain, grid, properties)
	return grid


static func _build_mesh_library(cell_size: float) -> MeshLibrary:
	var library := MeshLibrary.new()
	for index in range(MATERIALS.size()):
		var data: Dictionary = MATERIALS[index]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * cell_size
		var material := StandardMaterial3D.new()
		material.albedo_color = data.color
		material.roughness = 0.92
		var texture_path := "res://Roblox-Materials/PartsPre2022/%s/color.png" % str(data.name)
		if ResourceLoader.exists(texture_path):
			material.albedo_texture = load(texture_path) as Texture2D
			material.uv1_triplanar = true
			material.uv1_scale = Vector3.ONE * 0.16
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.texture_repeat = true
		if str(data.name) == "Water":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.metallic = 0.08
		mesh.surface_set_material(0, material)
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * cell_size
		library.create_item(index)
		library.set_item_name(index, str(data.name))
		library.set_item_mesh(index, mesh)
		library.set_item_shapes(index, [shape, Transform3D.IDENTITY])
	return library


static func _restore_metadata_cells(terrain: Node, grid: GridMap, properties: Dictionary) -> void:
	var raw_cells: Variant = properties.get("Cells", [])
	if not raw_cells is Array or not grid.get_used_cells().is_empty():
		return
	for raw_cell in raw_cells:
		if not raw_cell is Array or raw_cell.size() < 4:
			continue
		var values: Array = raw_cell
		grid.set_cell_item(Vector3i(int(values[0]), int(values[1]), int(values[2])), clampi(int(values[3]), 0, MATERIALS.size() - 1))


static func _set_cell(grid: GridMap, cell: Vector3i, material_id: int) -> int:
	var previous := grid.get_cell_item(cell)
	var next := material_id if material_id >= 0 else -1
	if previous == next:
		return 0
	grid.set_cell_item(cell, next)
	return 1


static func _material_index(value: Variant) -> int:
	var material_name := ""
	if value is String:
		material_name = str(value).get_slice(".", str(value).count("."))
	else:
		var material_data: Dictionary = preload("res://addons/rbxl_importer/material_cache.gd").resolve_material_enum(value)
		material_name = str(material_data.get("name", "Ground"))
	if material_name == "Air":
		return -1
	for index in range(MATERIALS.size()):
		if str(MATERIALS[index].name) == material_name:
			return index
	return 1 # Map non-terrain materials to the neutral Ground voxel.


static func _finish_edit(terrain: Node, grid: GridMap) -> void:
	var cells: Array = []
	for cell in grid.get_used_cells():
		cells.append([cell.x, cell.y, cell.z, grid.get_cell_item(cell)])
	cells.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2])
	)
	var properties: Dictionary = terrain.get_meta("roblox_properties", {}).duplicate(true) if terrain.get_meta("roblox_properties", {}) is Dictionary else {}
	properties["CellSize"] = grid.cell_size.x
	properties["Cells"] = cells
	properties["MaterialNames"] = MATERIALS.map(func(item: Dictionary): return str(item.name))
	terrain.set_meta("roblox_properties", properties)
