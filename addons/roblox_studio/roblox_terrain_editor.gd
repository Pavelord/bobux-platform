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
var _cell_size_spin: SpinBox = null
var _width_spin: SpinBox = null
var _depth_spin: SpinBox = null
var _seed_spin: SpinBox = null
var _status_label: Label = null
var _dialog: AcceptDialog = null
var _active_mode: String = ""
var _stroke_active: bool = false
var _stroke_changed: bool = false
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
	dialog.title = "Terrain Studio"
	dialog.ok_button_text = "Close"
	dialog.exclusive = false
	dialog.transient = true
	var dialog_panel := StyleBoxFlat.new()
	dialog_panel.bg_color = Color("#F6F9FD")
	dialog_panel.border_color = Color("#C8D9E8")
	dialog_panel.set_border_width_all(1)
	dialog_panel.set_corner_radius_all(8)
	dialog_panel.content_margin_left = 14
	dialog_panel.content_margin_right = 14
	dialog_panel.content_margin_top = 10
	dialog_panel.content_margin_bottom = 12
	dialog.add_theme_stylebox_override("panel", dialog_panel)
	dialog.add_theme_color_override("title_color", Color("#20364E"))
	studio.add_child(dialog)
	dialog.tree_exited.connect(func() -> void:
		_active_mode = ""
		_stroke_active = false
		_dialog = null
		_material_option = null
		_radius_spin = null
		_height_spin = null
		_cell_size_spin = null
		_width_spin = null
		_depth_spin = null
		_seed_spin = null
		_status_label = null
	)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(570, 470)
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
	_style_field(_material_option)
	settings.add_child(_material_option)
	_add_label(settings, "Brush radius")
	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 1
	_radius_spin.max_value = 12
	_radius_spin.step = 1
	_radius_spin.value = 3
	_style_field(_radius_spin)
	settings.add_child(_radius_spin)
	_add_label(settings, "Brush height")
	_height_spin = SpinBox.new()
	_height_spin.min_value = 1
	_height_spin.max_value = 12
	_height_spin.step = 1
	_height_spin.value = 2
	_style_field(_height_spin)
	settings.add_child(_height_spin)
	_add_label(settings, "Voxel size")
	_cell_size_spin = SpinBox.new()
	_cell_size_spin.min_value = 1
	_cell_size_spin.max_value = 8
	_cell_size_spin.step = 1
	_cell_size_spin.value = int(round(_grid.cell_size.x))
	_cell_size_spin.value_changed.connect(_on_cell_size_changed)
	_style_field(_cell_size_spin)
	settings.add_child(_cell_size_spin)

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

	var generator_title := Label.new()
	generator_title.text = "Generate terrain"
	generator_title.add_theme_font_size_override("font_size", 15)
	generator_title.add_theme_color_override("font_color", Color("#1F5F94"))
	root.add_child(generator_title)
	var generator_settings := GridContainer.new()
	generator_settings.columns = 4
	generator_settings.add_theme_constant_override("h_separation", 8)
	root.add_child(generator_settings)
	_add_label(generator_settings, "Width")
	_width_spin = _make_generator_spin(8, 64, 32)
	generator_settings.add_child(_width_spin)
	_add_label(generator_settings, "Depth")
	_depth_spin = _make_generator_spin(8, 64, 32)
	generator_settings.add_child(_depth_spin)
	_add_label(generator_settings, "Seed")
	_seed_spin = _make_generator_spin(0, 999999, 1)
	generator_settings.add_child(_seed_spin)
	var presets := HBoxContainer.new()
	root.add_child(presets)
	for preset in [["Flat", "flat"], ["Hills", "hills"], ["Islands", "islands"]]:
		var generate_button := Button.new()
		generate_button.text = str(preset[0])
		generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(generate_button, true)
		generate_button.pressed.connect(func() -> void:
			generate(str(preset[1]), int(_width_spin.value), int(_depth_spin.value), int(_height_spin.value), int(_seed_spin.value))
		)
		presets.add_child(generate_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("#3F4852"))
	root.add_child(_status_label)
	_update_status("Ready")
	dialog.popup_centered(Vector2i(600, 540))


func restore(studio: Node, workspace: Node3D) -> Dictionary:
	_studio = studio
	_workspace = workspace
	_ensure_terrain(false)
	return {
		"ok": _terrain_root != null and _grid != null,
		"cells": _grid.get_used_cells().size() if _grid != null else 0,
		"terrain": _terrain_root,
	}


func prepare(studio: Node, workspace: Node3D) -> void:
	_studio = studio
	_workspace = workspace
	_ensure_terrain(true)


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
		var material_path := "res://Roblox-Materials/PartsPre2022/%s/color.png" % str(data.name)
		if ResourceLoader.exists(material_path):
			material.albedo_texture = load(material_path) as Texture2D
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
	label.add_theme_color_override("font_color", Color("#42566B"))
	parent.add_child(label)


func _make_generator_spin(minimum: float, maximum: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size.x = 72
	_style_field(spin)
	return spin


func _on_cell_size_changed(value: float) -> void:
	if _grid == null or is_equal_approx(_grid.cell_size.x, value):
		return
	_grid.cell_size = Vector3.ONE * value
	_grid.mesh_library = _build_mesh_library(value)
	_sync_metadata()
	_update_status("Voxel size changed")
	_notify_changed("Resize Terrain Voxels")


func generate(preset: String, width: int, depth: int, max_height: int, seed_value: int) -> int:
	if _grid == null:
		return 0
	width = clampi(width, 8, 96)
	depth = clampi(depth, 8, 96)
	max_height = clampi(max_height, 1, 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	var fallback_material := _material_option.selected if _material_option != null else 0
	var surface_material := fallback_material
	var ground_material := _material_index_by_name("Ground")
	var placed := 0
	_grid.clear()
	for x in range(width):
		for z in range(depth):
			var column_height := 1
			match preset:
				"hills":
					var wave := (sin(float(x) * 0.19) + cos(float(z) * 0.17) + sin(float(x + z) * 0.11)) * 0.5
					column_height = clampi(roundi(3.0 + wave * max_height * 0.46 + rng.randf_range(-1.0, 1.0)), 1, max_height)
				"islands":
					var dx := (float(x) - float(width - 1) * 0.5) / maxf(1.0, float(width) * 0.5)
					var dz := (float(z) - float(depth - 1) * 0.5) / maxf(1.0, float(depth) * 0.5)
					var falloff := 1.0 - Vector2(dx, dz).length()
					if falloff <= 0.0 or rng.randf() < 0.025:
						continue
					column_height = clampi(roundi(1.0 + falloff * max_height + rng.randf_range(-1.2, 1.2)), 1, max_height)
			for layer in range(column_height):
				var material_id := fallback_material
				if layer == column_height - 1:
					material_id = surface_material
				elif layer < column_height - 1 and ground_material >= 0:
					material_id = ground_material
				_grid.set_cell_item(Vector3i(x - int(width / 2), layer, z - int(depth / 2)), material_id)
				placed += 1
	_sync_metadata()
	_update_status("Generated %s terrain: %d voxels" % [preset.capitalize(), placed])
	_notify_changed("Generate %s Terrain" % preset.capitalize())
	return placed


func _material_index_by_name(material_name: String) -> int:
	for index in range(MATERIALS.size()):
		if str(MATERIALS[index].name) == material_name:
			return index
	return -1


func _add_action(parent: Control, text: String, mode: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(106, 36)
	button.toggle_mode = mode != "clear"
	_style_button(button, false)
	button.pressed.connect(_select_brush_mode.bind(mode, button))
	parent.add_child(button)


func _style_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#0078D4") if accent else Color("#FFFFFF")
	normal.border_color = Color("#0067B8") if accent else Color("#B9C1CA")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#1688E5") if accent else Color("#EFF6FC")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#005A9E") if accent else Color("#DCEEFF")
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE if accent else Color("#263238"))
	button.add_theme_color_override("font_hover_color", Color.WHITE if accent else Color("#005A9E"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE if accent else Color("#164E78"))
	button.add_theme_stylebox_override("focus", _field_focus_style())
	button.add_theme_font_size_override("font_size", 12)


func _style_field(field: Control) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.WHITE
	normal.border_color = Color("#C8D5E1")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color("#77B6E6")
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color("#1686D9")
	focus.set_border_width_all(2)
	for style_name in ["normal", "pressed", "hover", "focus"]:
		var style: StyleBox = normal
		if style_name == "pressed": style = hover
		elif style_name == "hover": style = hover
		elif style_name == "focus": style = focus
		field.add_theme_stylebox_override(style_name, style)
	field.add_theme_color_override("font_color", Color("#24384D"))
	field.add_theme_color_override("font_hover_color", Color("#1E6FAF"))
	field.add_theme_color_override("font_focus_color", Color("#24384D"))
	field.add_theme_color_override("font_placeholder_color", Color("#8797A8"))
	for child in field.find_children("*", "LineEdit", true, false):
		var input := child as LineEdit
		input.add_theme_stylebox_override("normal", normal)
		input.add_theme_stylebox_override("focus", focus)
		input.add_theme_color_override("font_color", Color("#24384D"))
		input.add_theme_color_override("font_selected_color", Color.WHITE)
		input.add_theme_color_override("selection_color", Color("#4EA5E8"))


func _field_focus_style() -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.1, 0.53, 0.85, 0.08)
	focus.border_color = Color("#1686D9")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	return focus


func is_brush_active() -> bool:
	return not _active_mode.is_empty() and _active_mode != "clear"


func begin_stroke(world_position: Vector3) -> bool:
	if not is_brush_active() or _grid == null:
		return false
	_stroke_active = true
	_stroke_changed = false
	_last_stroke_cell = Vector3i(2147483647, 2147483647, 2147483647)
	return continue_stroke(world_position)


func continue_stroke(world_position: Vector3) -> bool:
	if not _stroke_active or not is_brush_active() or _grid == null:
		return false
	var cell := _grid.local_to_map(_grid.to_local(world_position))
	if cell == _last_stroke_cell:
		return true
	var sentinel := Vector3i(2147483647, 2147483647, 2147483647)
	if _last_stroke_cell != sentinel:
		var delta := cell - _last_stroke_cell
		var steps := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
		steps = mini(steps, 64)
		for step in range(1, steps + 1):
			var point := Vector3(_last_stroke_cell).lerp(Vector3(cell), float(step) / float(steps)).round()
			if _apply_brush_at_cell(_active_mode, Vector3i(point), false) > 0:
				_stroke_changed = true
	else:
		if _apply_brush_at_cell(_active_mode, cell, false) > 0:
			_stroke_changed = true
	_last_stroke_cell = cell
	return true


func end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	_last_stroke_cell = Vector3i(2147483647, 2147483647, 2147483647)
	if _stroke_changed:
		_sync_metadata()
		_notify_changed("Terrain %s stroke" % _active_mode.capitalize())
	_stroke_changed = false


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


func _apply_brush_at_cell(mode: String, center: Vector3i, commit_history: bool) -> int:
	if _grid == null:
		return 0
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
	if commit_history:
		_sync_metadata()
		_update_status("%s: %d cell(s) changed" % [mode.capitalize(), changed])
		_notify_changed("Terrain %s" % mode.capitalize())
	return changed


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
	var center_surface := _find_surface_cell(center.x, center.z, center.y)
	var target_y := center_surface.y if center_surface != Vector3i(2147483647, 2147483647, 2147483647) else center.y
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var surface := _find_surface_cell(center.x + x, center.z + z, center.y)
			var surface_y := surface.y if surface != Vector3i(2147483647, 2147483647, 2147483647) else target_y - 1
			if surface_y > target_y:
				for y in range(surface_y, target_y, -1):
					_grid.set_cell_item(Vector3i(center.x + x, y, center.z + z), -1)
					changed += 1
			elif surface_y < target_y:
				for y in range(surface_y + 1, target_y + 1):
					_grid.set_cell_item(Vector3i(center.x + x, y, center.z + z), material_id)
					changed += 1
	return changed


func _grow_surface(center: Vector3i, radius: int, material_id: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var source := _find_surface_cell(center.x + x, center.z + z, center.y)
			if source != Vector3i(2147483647, 2147483647, 2147483647):
				var target := source + Vector3i.UP
				if _grid.get_cell_item(target) < 0:
					_grid.set_cell_item(target, material_id)
					changed += 1
	return changed


func _erode_surface(center: Vector3i, radius: int) -> int:
	var changed := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if Vector2(x, z).length() > float(radius) + 0.2:
				continue
			var cell := _find_surface_cell(center.x + x, center.z + z, center.y)
			if cell != Vector3i(2147483647, 2147483647, 2147483647):
				_grid.set_cell_item(cell, -1)
				changed += 1
	return changed


func _find_surface_cell(x: int, z: int, around_y: int) -> Vector3i:
	for y in range(around_y + 64, around_y - 65, -1):
		var cell := Vector3i(x, y, z)
		if _grid.get_cell_item(cell) >= 0:
			return cell
	return Vector3i(2147483647, 2147483647, 2147483647)


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
