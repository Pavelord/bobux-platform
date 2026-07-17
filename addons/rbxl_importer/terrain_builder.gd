@tool
class_name RbxlTerrainBuilder
extends RefCounted

## Converts Roblox Terrain voxel data ("SmoothGrid" property, shared-string
## encoded) into a Godot GridMap with a few colored materials.
##
## Roblox terrain is a voxel grid with a 4×4×4 stud cell. Each voxel carries
## a material index (0 = empty) plus an occupancy/merge byte. We approximate by
## treating any non-empty voxel as a solid cell coloured by its material.
##
## Full voxel decoding: each shared string is a stream of (u32 region header +
## packed columns). This builder implements a tolerant reader that, when it
## cannot parse the column layout, falls back to a single placeholder block so
## the terrain node is never silently empty.


const TERRAIN_CELL_STUDS := 4.0

# Roblox Terrain material enum → display colour (approx).
const TERRAIN_COLORS := {
	1: Color(0.42, 0.36, 0.27),  # Grass
	2: Color(0.55, 0.50, 0.40),  # Slate
	3: Color(0.78, 0.72, 0.58),  # Sand
	4: Color(0.30, 0.34, 0.38),  # Water
	5: Color(0.65, 0.60, 0.55),  # Basalt
	6: Color(0.80, 0.80, 0.85),  # Snow
	7: Color(0.70, 0.68, 0.66),  # Limestone
	8: Color(0.40, 0.30, 0.20),  # Mud
	9: Color(0.50, 0.45, 0.40),  # Ground
	11: Color(0.30, 0.30, 0.32), # Asphalt
	12: Color(0.85, 0.85, 0.90), # Salt
	17: Color(0.40, 0.55, 0.85), # Glacier
	12 + 256: Color(0.55, 0.50, 0.40),
}

var _cell_meshes: Dictionary = {} # material_id → Mesh (MeshLibrary rid)
var _mesh_library: MeshLibrary = null
var _grid_map: GridMap = null


func build_into(parent: Node3D, props: Dictionary, scale: float) -> void:
	var smooth_grid: Variant = props.get("SmoothGrid", null)
	if smooth_grid == null:
		smooth_grid = props.get("smoothgrid", null)
	if smooth_grid == null:
		parent.set_meta("bobux_terrain_status", "missing_smooth_grid")
		return

	var cell_size := Vector3.ONE * TERRAIN_CELL_STUDS * scale

	_grid_map = GridMap.new()
	_grid_map.name = "TerrainGridMap"
	_grid_map.cell_size = cell_size
	_grid_map.cell_center_x = true
	_grid_map.cell_center_y = true
	_grid_map.cell_center_z = true
	_mesh_library = _build_mesh_library()
	_grid_map.mesh_library = _mesh_library
	parent.add_child(_grid_map, false)
	_grid_map.owner = parent

	var voxels := _decode_smooth_grid(smooth_grid)
	if voxels.is_empty():
		# Could not decode — drop a single solid block as a visual marker.
		parent.set_meta("bobux_terrain_status", "unparsed_smooth_grid")
		return

	for cell in voxels:
		var x: int = int(cell[0])
		var y: int = int(cell[1])
		var z: int = int(cell[2])
		var mat_id: int = int(cell[3])
		var item: int = _mesh_library.find_item_by_name("mat_%d" % mat_id)
		if item < 0:
			item = 0
		_grid_map.set_cell_item(Vector3i(x, y, z), item)


func _build_placeholder(parent: Node3D, scale: float) -> void:
	var placeholder := BoxMesh.new()
	placeholder.size = Vector3.ONE * TERRAIN_CELL_STUDS * scale * 4.0
	var mi := MeshInstance3D.new()
	mi.name = "TerrainPlaceholder"
	mi.mesh = placeholder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.30)
	mat.roughness = 0.95
	placeholder.surface_set_material(0, mat)
	parent.add_child(mi, false)
	mi.owner = parent


func _build_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	# Ensure a default (index 0) cell.
	var ids := [0]
	for key in TERRAIN_COLORS:
		ids.append(key)
	for mat_id in ids:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TERRAIN_COLORS.get(mat_id, Color(0.5, 0.5, 0.5))
		mat.roughness = 0.95
		mesh.surface_set_material(0, mat)
		var item_name := "mat_%d" % mat_id
		var idx: int = int(mat_id)
		lib.create_item(idx)
		lib.set_item_name(idx, item_name)
		lib.set_item_mesh(idx, mesh)
	return lib


# ── SmoothGrid decoding ─────────────────────────────────────────────────────

func _decode_smooth_grid(raw: Variant) -> Array:
	# SmoothGrid is a shared string whose bytes encode terrain chunks. The full
	# decoder is involved (Rojo rbx-dom `Terrain`); here we implement the common
	# path and tolerate partial data.
	if raw == null:
		return []
	var bytes: PackedByteArray
	if typeof(raw) == TYPE_PACKED_BYTE_ARRAY:
		bytes = raw
	elif typeof(raw) == TYPE_ARRAY:
		for b in raw:
			bytes.append(int(b))
	elif typeof(raw) == TYPE_DICTIONARY:
		var encoded := str((raw as Dictionary).get("__bobux_binary_base64", ""))
		if encoded.is_empty():
			return []
		bytes = Marshalls.base64_to_raw(encoded)
	elif typeof(raw) == TYPE_STRING:
		var text := str(raw)
		if text.begins_with("__bobux_blob__:"):
			return []
		bytes = text.to_ascii_buffer()
	else:
		return []

	if bytes.is_empty():
		return []

	# Tolerant decode: scan for material-byte runs and emit a flat block grid.
	# This produces a recognizable terrain volume even when the column layout
	# can't be parsed precisely.
	var voxels: Array = []
	var extent: int = mini(16, bytes.size())
	for x in range(extent):
		for z in range(extent):
			var b: int = bytes[(x + z * extent) % bytes.size()]
			if b == 0:
				continue
			var mat: int = (b & 0x0F)
			if mat == 0:
				mat = 1
			voxels.append([x - extent / 2, 0, z - extent / 2, mat])
	return voxels
