extends RefCounted
class_name CharacterCollider

const SHAPE_NODES := {
	"HumanoidRootPart": "CollisionHumanoidRootPart",
	"Torso": "CollisionTorso",
	"Head": "CollisionHead",
	"Left Arm": "CollisionLeftArm",
	"Right Arm": "CollisionRightArm",
	"Left Leg": "CollisionLeftLeg",
	"Right Leg": "CollisionRightLeg",
}


static func configure(character: CharacterBody3D, config: HumanoidConfig) -> Dictionary:
	var measured_parts := _read_part_dump(str(config.value("Trace.PartDumpCsv", "")))
	var root_height := _resolve_hrp_height_from_parts(config, measured_parts)
	character.set_meta("roblox_hrp_height_above_body_origin", root_height)
	character.set_meta("roblox_hrp_height_source", "measured" if not measured_parts.is_empty() else config.source("Trace.HRPHeightAboveBodyOrigin"))
	var result := {}
	for part_name in SHAPE_NODES:
		var shape_node := character.get_node_or_null(SHAPE_NODES[part_name]) as CollisionShape3D
		if shape_node == null:
			shape_node = CollisionShape3D.new()
			shape_node.name = SHAPE_NODES[part_name]
			character.add_child(shape_node, true)
		var prefix: String = "R6." + str(part_name)
		var inner_box_key: String = "R6.InnerBox." + str(part_name) + ".Size"
		var measured: Dictionary = measured_parts.get(part_name, {})
		var collision_type := str(config.value("CollisionType"))
		var configured_size: Vector3 = config.value(prefix + ".Size")
		var inner_box_size: Vector3 = config.value(inner_box_key)
		var size: Vector3 = configured_size
		var size_source := config.source(prefix + ".Size")
		if collision_type == "InnerBox":
			size = inner_box_size
			size_source = config.source(inner_box_key)
		elif measured.has("size"):
			size = measured["size"]
			size_source = "measured"
		var part_offset: Vector3 = measured.get("position", config.value(prefix + ".RelativePosition", Vector3.ZERO))
		var can_collide := bool(measured.get("can_collide", config.value(prefix + ".CanCollide", false)))
		var box := BoxShape3D.new()
		box.size = size * float(character.get("world_stud_scale"))
		shape_node.shape = box
		shape_node.position = (Vector3(0.0, root_height, 0.0) + part_offset) * float(character.get("world_stud_scale"))
		shape_node.basis = measured.get("basis", Basis.IDENTITY)
		shape_node.disabled = not can_collide or bool(character.get("is_ui_preview"))
		shape_node.set_meta("roblox_part_name", part_name)
		shape_node.set_meta("humanoid_config_collision_type", collision_type)
		shape_node.set_meta("humanoid_config_size_source", size_source)
		shape_node.set_meta("humanoid_config_can_collide", can_collide)
		shape_node.set_meta("humanoid_config_can_collide_source", "measured" if measured.has("can_collide") else config.source(prefix + ".CanCollide"))
		result[part_name] = {"shape": shape_node, "can_collide": can_collide, "measured": measured.has("can_collide")}
	return result


static func resolve_hrp_height(config: HumanoidConfig) -> float:
	var measured_parts := _read_part_dump(str(config.value("Trace.PartDumpCsv", "")))
	return _resolve_hrp_height_from_parts(config, measured_parts)


static func _resolve_hrp_height_from_parts(config: HumanoidConfig, measured_parts: Dictionary) -> float:
	var lowest_part_bottom := INF
	for part_data in measured_parts.values():
		var size: Vector3 = part_data.get("size", Vector3.ZERO)
		var position: Vector3 = part_data.get("position", Vector3.ZERO)
		lowest_part_bottom = minf(lowest_part_bottom, position.y - size.y * 0.5)
	if is_finite(lowest_part_bottom) and lowest_part_bottom < 0.0:
		return -lowest_part_bottom
	return config.float_value("Trace.HRPHeightAboveBodyOrigin")


static func _read_part_dump(configured_path: String) -> Dictionary:
	var paths := PackedStringArray([configured_path, "res://tests/roblox_traces/part_dump.csv", "res://tests/roblox_traces/studio/part_dump.csv"])
	for path in paths:
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var header := _parse_csv_row(file.get_line())
		var columns := {}
		for index in range(header.size()):
			columns[header[index]] = index
		var result := {}
		while not file.eof_reached():
			var row := _parse_csv_row(file.get_line())
			if row.size() < header.size():
				continue
			var name := row[int(columns.get("part", -1))] if columns.has("part") else ""
			if not SHAPE_NODES.has(name):
				continue
			result[name] = {
				"size": Vector3(_number(row, columns, "size_x"), _number(row, columns, "size_y"), _number(row, columns, "size_z")),
				"position": Vector3(_number(row, columns, "rel_x"), _number(row, columns, "rel_y"), _number(row, columns, "rel_z")),
				"basis": _basis_from_row(row, columns),
				"can_collide": row[int(columns["can_collide"])].to_lower() == "true" if columns.has("can_collide") else false,
			}
		return result
	return {}


static func _number(row: PackedStringArray, columns: Dictionary, key: String) -> float:
	if not columns.has(key):
		return 0.0
	return float(row[int(columns[key])])


static func _basis_from_row(row: PackedStringArray, columns: Dictionary) -> Basis:
	var required := ["rel_r00", "rel_r01", "rel_r02", "rel_r10", "rel_r11", "rel_r12", "rel_r20", "rel_r21", "rel_r22"]
	for key in required:
		if not columns.has(key):
			return Basis.IDENTITY
	return Basis(
		Vector3(_number(row, columns, "rel_r00"), _number(row, columns, "rel_r10"), _number(row, columns, "rel_r20")),
		Vector3(_number(row, columns, "rel_r01"), _number(row, columns, "rel_r11"), _number(row, columns, "rel_r21")),
		Vector3(_number(row, columns, "rel_r02"), _number(row, columns, "rel_r12"), _number(row, columns, "rel_r22"))
	)


static func _parse_csv_row(line: String) -> PackedStringArray:
	var result := PackedStringArray()
	var field := ""
	var quoted := false
	var index := 0
	while index < line.length():
		var character := line.substr(index, 1)
		if character == "\"":
			if quoted and index + 1 < line.length() and line.substr(index + 1, 1) == "\"":
				field += "\""
				index += 1
			else:
				quoted = not quoted
		elif character == "," and not quoted:
			result.append(field)
			field = ""
		else:
			field += character
		index += 1
	result.append(field)
	return result
