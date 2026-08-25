@tool
class_name RobloxTerrainEditor
extends RefCounted

const TERRAIN_CLASS_META := "roblox_class"
const TERRAIN_CELL_SIZE := 2.0
const TERRAIN_NODE_NAME := "Terrain"
const GRID_NODE_NAME := "EditableTerrainGrid"

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

var _studio: Node = null
var _workspace: Node3D = null
var _terrain_root: Node3D = null
var _grid: GridMap = null
var _material_option: OptionButton = null
var _radius_spin: SpinBox = null
var _height_spin: SpinBox = null
var _status_label: Label = null
var _dialog: AcceptDialog = null
var _active_mode: String = ""
var _stroke_active: bool = false
var _last_stroke_cell: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)


func open(studio: Node, workspace: Node3D) -> void:
	_studio = studio
	_workspace = workspace
	_ensure_terrain()
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.popup_centered()
		return
	var dialog := AcceptDialog.new()
	_dialog = dialog
	dialog.name = "TerrainEditorDialog"
	dialog.title = "Terrain Editor"
	dialog.ok_button_text = "Close"
	dialog.exclusive = false
	dialog.transient = true
	studio.add_child(dialog)
	dialog.tree_exited.connect(func() -> void:
		_active_mode = ""
		_stroke_active = false
		_dialog = null
		_material_option = null
		_radius_spin = null
		_height_spin = null
		_status_label = null
	)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(470, 290)
	root.add_theme_constant_override("separation", 8)
	dialog.add_child(root)

	var intro := Label.new()
	intro.text = "Choose a brush, then paint directly in the 3D viewport with the left mouse button."
	intro.add_theme_color_override("font_color", Color("#5F6368"))
	root.add_child(intro)

	var settings := GridContainer.new()
	settings.columns = 2
	settings.add_theme_constant_override("h_separation", 10)
	settings.add_theme_constant_override("v_separation", 6)
	root.add_child(settings)
	_add_label(settings, "Material")
	_material_option = OptionButton.new()
	for material in MATERIALS:
		_material_option.add_item(str(material.name))
	_material_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(_material_option)
	_add_label(settings, "Brush radius")
	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 1
	_radius_spin.max_value = 12
	_radius_spin.step = 1
	_radius_spin.value = 3
	settings.add_child(_radius_spin)
	_add_label(settings, "Brush height")
	_height_spin = SpinBox.new()
	_height_spin.min_value = 1
	_height_spin.max_value = 12
	_height_spin.step = 1
	_height_spin.value = 2
	settings.add_child(_height_spin)

	var actions := GridContainer.new()
	actions.columns = 4
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	root.add_child(actions)
	_add_action(actions, "Add", "add")
	_add_action(actions, "Subtract", "subtract")
	_add_action(actions, "Paint", "paint")
	_add_action(actions, "Flatten", "flatten")
	_add_action(actions, "Grow", "grow")
	_add_action(actions, "Erode", "erode")
	_add_action(actions, "Fill Area", "fill")
	_add_action(actions, "Clear", "clear")

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("#3F4852"))
	root.add_child(_status_label)
	_update_status("Ready")
	dialog.popup_centered(Vector2i(500, 350))


func restore(studio: Node, workspace: Node3D) -> Dictionary:
	_studio = studio
	_workspace = workspace
	_ensure_terrain(false)
	return {
		"ok": _terrain_root != null and _grid != null,
		"cells": _grid.get_used_cells().size() if _grid != null else 0,
		"terrain": _terrain_root,
	}


func _ensure_terrain(create_when_missing: bool = true) -> void:
	if _workspace == null:
		return
	_terrain_root = null
	_grid = null
	for child in _workspace.get_children():
		if str(child.get_meta(TERRAIN_CLASS_META, "")) == "Terrain" and child is Node3D:
			_terrain_root = child as Node3D
			_grid = _terrain_root.get_node_or_null(GRID_NODE_NAME) as GridMap
			break
	if _terrain_root == null:
		if not create_when_missing:
			return
		_terrain_root = Node3D.new()
		_terrain_root.name = TERRAIN_NODE_NAME
		_terrain_root.set_meta(TERRAIN_CLASS_META, "Terrain")
		_terrain_root.set_meta("block_name", TERRAIN_NODE_NAME)
		_workspace.add_child(_terrain_root, true)
	_terrain_root.add_to_group("studio_terrain")
	if _grid == null:
		_grid = GridMap.new()
		_grid.name = GRID_NODE_NAME
		_grid.cell_size = Vector3.ONE * _terrain_cell_size_from_metadata()
		_grid.cell_center_x = true
		_grid.cell_center_y = true
		_grid.cell_center_z = true
		_grid.collision_layer = 1
		_grid.collision_mask = 1
		_grid.mesh_library = _build_mesh_library(_grid.cell_size.x)
		_grid.set_meta("bobux_runtime_generated", true)
		_terrain_root.add_child(_grid)
	_restore_cells_from_metadata()
	_sync_metadata()


func _build_mesh_library(cell_size: float = TERRAIN_CELL_SIZE) -> MeshLibrary:
	var library := MeshLibrary.new()
	for index in range(MATERIALS.size()):
		var data: Dictionary = MATERIALS[index]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * cell_size
		var material := StandardMaterial3D.new()
		material.albedo_color = data.color
		material.roughness = 0.92
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


func _terrain_cell_size_from_metadata() -> float:
	if _terrain_root == null:
		return TERRAIN_CELL_SIZE
	var properties := _terrain_root.get_meta("roblox_properties", {})
	if properties is Dictionary:
		return clampf(float((properties as Dictionary).get("CellSize", TERRAIN_CELL_SIZE)), 0.25, 16.0)
	return TERRAIN_CELL_SIZE


func _restore_cells_from_metadata() -> int:
	if _terrain_root == null or _grid == null:
		return 0
	var properties := _terrain_root.get_meta("roblox_properties", {})
	if not (properties is Dictionary):
		return 0
	var raw_cells := (properties as Dictionary).get("Cells", [])
	if not (raw_cells is Array):
		return 0
	_grid.clear()
	var restored := 0
	for raw_cell in raw_cells:
		if not (raw_cell is Array) or (raw_cell as Array).size() < 4:
			continue
		var values := raw_cell as Array
		var material_id := clampi(int(values[3]), 0, MATERIALS.size() - 1)
		_grid.set_cell_item(Vector3i(int(values[0]), int(values[1]), int(values[2])), material_id)
		restored += 1
	return restored


func _add_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _add_action(parent: Control, text: String, mode: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(106, 36)
	button.toggle_mode = mode != "clear"
	button.pressed.connect(_select_brush_mode.bind(mode, button))
	parent.add_child(button)


func is_brush_active() -> bool:
	return not _active_mode.is_empty() and _active_mode != "clear"


func begin_stroke(world_position: Vector3) -> bool:
	if not is_brush_active() or _grid == null:
		return false
	_stroke_active = true
	_last_stroke_cell = Vector3i(2147483647, 2147483647, 2147483647)
	return continue_stroke(world_position)


func continue_stroke(world_position: Vector3) -> bool:
	if not _stroke_active or not is_brush_active() or _grid == null:
		return false
	var cell := _grid.local_to_map(_grid.to_local(world_position))
	if cell == _last_stroke_cell:
		return true
	_last_stroke_cell = cell
	_apply_brush_at_cell(_active_mode, cell, false)
	return true


func end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	_last_stroke_cell = Vector3i(2147483647, 2147483647, 2147483647)
	_sync_metadata()
	_notify_changed("Terrain %s stroke" % _active_mode.capitalize())


func cancel_brush() -> void:
	end_stroke()
	_active_mode = ""
	_update_status("Brush inactive")


func _select_brush_mode(mode: String, selected_button: Button) -> void:
	if mode == "clear":
		_apply_brush("clear")
		return
	_active_mode = mode
	_stroke_active = false
	if selected_button != null and selected_button.get_parent() != null:
		for child in selected_button.get_parent().get_children():
			if child is Button and (child as Button).toggle_mode:
				(child as Button).set_pressed_no_signal(child == selected_button)
	_update_status("%s brush active - paint in the viewport" % mode.capitalize())
	if _studio != null and _studio.has_method("_activate_terrain_brush_tool"):
		_studio.call("_activate_terrain_brush_tool")


func _apply_brush(mode: String) -> void:
	if _grid == null or _studio == null:
		return
	if mode == "clear":
		_grid.clear()
		_sync_metadata()
		_update_status("Terrain cleared")
		_notify_changed("Clear Terrain")
		return
	var center_world := Vector3.ZERO
	if _studio.has_method("_get_editor_drop_position"):
		center_world = _studio.call("_get_editor_drop_position", 12.0, true)
	var center := _grid.local_to_map(_grid.to_local(center_world))
	_apply_brush_at_cell(mode, center, true)


func _apply_brush_at_cell(mode: String, center: Vector3i, commit_history: bool) -> void:
	if _grid == null:
		return
	var radius := maxi(1, int(_radius_spin.value if _radius_spin != null else 3))
	var height := maxi(1, int(_height_spin.value if _height_spin != null else 2))
	var material_id := _material_option.selected if _material_option != null else 0
	var changed := 0
	match mode:
		"fill":
			changed = _fill_box(center, radius, height, material_id)
		"flatten":
			changed = _flatten_disk(center, radius, material_id)
		"grow":
			changed = _grow_surface(center, radius, material_id)
		"erode":
			changed = _erode_surface(center, radius)
		_:
			changed = _sphere_brush(center, radius, mode, material_id)
	_sync_metadata()
	_update_status("%s: %d cell(s) changed" % [mode.capitalize(), changed])
	if commit_history:
		_notify_changed("Terrain %s" % mode.capitalize())


func _sphere_brush(center: Vector3i, radius: int, mode: String, material_id: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if Vector3(x, y, z).length() > float(radius) + 0.2:
					continue
				var cell := center + Vector3i(x, y, z)
				var old := _grid.get_cell_item(cell)
				if mode == "subtract":
					if old >= 0:
						_grid.set_cell_item(cell, -1)
						changed += 1
				elif mode == "paint":
					if old >= 0 and old != material_id:
						_grid.set_cell_item(cell, material_id)
						changed += 1
				elif old != material_id:
					_grid.set_cell_item(cell, material_id)
					changed += 1
	return changed


func _fill_box(center: Vector3i, radius: int, height: int, material_id: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for y in range(0, height):
			for z in range(-radius, radius + 1):
				var cell := center + Vector3i(x, y, z)
				if _grid.get_cell_item(cell) != material_id:
					_grid.set_cell_item(cell, material_id)
					changed += 1
	return changed


func _flatten_disk(center: Vector3i, radius: int, material_id: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var cell := center + Vector3i(x, 0, z)
			if _grid.get_cell_item(cell) != material_id:
				_grid.set_cell_item(cell, material_id)
				changed += 1
	return changed


func _grow_surface(center: Vector3i, radius: int, material_id: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var column := center + Vector3i(x, 0, z)
			for y in range(radius, -radius - 1, -1):
				var source := column + Vector3i(0, y, 0)
				if _grid.get_cell_item(source) >= 0:
					var target := source + Vector3i.UP
					if _grid.get_cell_item(target) < 0:
						_grid.set_cell_item(target, material_id)
						changed += 1
					break
	return changed


func _erode_surface(center: Vector3i, radius: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var column := center + Vector3i(x, 0, z)
			for y in range(radius, -radius - 1, -1):
				var cell := column + Vector3i(0, y, 0)
				if _grid.get_cell_item(cell) >= 0:
					_grid.set_cell_item(cell, -1)
					changed += 1
					break
	return changed


func _sync_metadata() -> void:
	if _terrain_root == null or _grid == null:
		return
	var cells: Array = []
	for cell in _grid.get_used_cells():
		cells.append([cell.x, cell.y, cell.z, _grid.get_cell_item(cell)])
	cells.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2])
	)
	_terrain_root.set_meta("roblox_properties", {
		"CellSize": _grid.cell_size.x,
		"Cells": cells,
		"MaterialNames": MATERIALS.map(func(item: Dictionary): return str(item.name)),
	})


func _notify_changed(history_label: String) -> void:
	if _studio == null:
		return
	if _studio.has_method("_refresh_explorer"):
		_studio.call("_refresh_explorer")
	if _studio.has_method("_commit_editor_history"):
		_studio.call("_commit_editor_history", history_label)


func _update_status(prefix: String) -> void:
	if _status_label == null or _grid == null:
		return
	_status_label.text = "%s. Terrain contains %d voxel cell(s)." % [prefix, _grid.get_used_cells().size()]
