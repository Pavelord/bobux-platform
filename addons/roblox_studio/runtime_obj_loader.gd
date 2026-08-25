@tool
class_name RuntimeObjLoader
extends RefCounted

const MAX_OBJ_BYTES: int = 128 * 1024 * 1024

static func load_mesh(source_path: String) -> ArrayMesh:
	if source_path.strip_edges().is_empty() or not FileAccess.file_exists(source_path):
		return null
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_OBJ_BYTES:
		if file != null:
			file.close()
		return null
	var source := file.get_as_text()
	file.close()
	var positions: Array[Vector3] = []
	var texcoords: Array[Vector2] = []
	var normals: Array[Vector3] = []
	var vertex_colors: Array[Color] = []
	var faces_by_material: Dictionary = {}
	var material_order: Array[String] = []
	var current_material := "__default__"
	var material_library := ""
	_register_material_bucket(faces_by_material, material_order, current_material)
	for raw_line in source.split("\n", false):
		var line := str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var tokens := line.split(" ", false)
		if tokens.is_empty():
			continue
		match str(tokens[0]):
			"v":
				if tokens.size() >= 4:
					positions.append(Vector3(float(tokens[1]), float(tokens[2]), float(tokens[3])))
					vertex_colors.append(Color(float(tokens[4]), float(tokens[5]), float(tokens[6])) if tokens.size() >= 7 else Color.WHITE)
			"vt":
				if tokens.size() >= 3:
					texcoords.append(Vector2(float(tokens[1]), 1.0 - float(tokens[2])))
			"vn":
				if tokens.size() >= 4:
					normals.append(Vector3(float(tokens[1]), float(tokens[2]), float(tokens[3])).normalized())
			"usemtl":
				current_material = line.trim_prefix("usemtl").strip_edges()
				if current_material.is_empty():
					current_material = "__default__"
				_register_material_bucket(faces_by_material, material_order, current_material)
			"mtllib":
				material_library = line.trim_prefix("mtllib").strip_edges()
			"f":
				if tokens.size() >= 4:
					var face: Array[Vector3i] = []
					for token_index in range(1, tokens.size()):
						face.append(_parse_face_vertex(str(tokens[token_index]), positions.size(), texcoords.size(), normals.size()))
					(faces_by_material[current_material] as Array).append(face)
			_:
				continue
	if positions.is_empty():
		return null
	var materials := _load_material_library(source_path.get_base_dir().path_join(material_library)) if not material_library.is_empty() else {}
	var mesh := ArrayMesh.new()
	for material_name in material_order:
		var faces: Array = faces_by_material.get(material_name, [])
		if faces.is_empty():
			continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_complete_normals := true
		var surface_vertex_count := 0
		for face_variant in faces:
			var face := face_variant as Array
			if face.size() < 3:
				continue
			for corner_index in range(1, face.size() - 1):
				for vertex_ref in [face[0], face[corner_index], face[corner_index + 1]]:
					var ref := vertex_ref as Vector3i
					if ref.x < 0 or ref.x >= positions.size():
						continue
					if ref.z >= 0 and ref.z < normals.size():
						surface.set_normal(normals[ref.z])
					else:
						has_complete_normals = false
					if ref.y >= 0 and ref.y < texcoords.size():
						surface.set_uv(texcoords[ref.y])
					if ref.x < vertex_colors.size():
						surface.set_color(vertex_colors[ref.x])
					surface.add_vertex(positions[ref.x])
					surface_vertex_count += 1
		if surface_vertex_count < 3:
			continue
		if not has_complete_normals:
			surface.generate_normals()
		var material := materials.get(material_name, _make_material(Color.WHITE)) as Material
		surface.set_material(material)
		surface.commit(mesh)
	return mesh if mesh.get_surface_count() > 0 else null

static func _register_material_bucket(faces_by_material: Dictionary, order: Array[String], material_name: String) -> void:
	if faces_by_material.has(material_name):
		return
	faces_by_material[material_name] = []
	order.append(material_name)

static func _parse_face_vertex(token: String, position_count: int, uv_count: int, normal_count: int) -> Vector3i:
	var fields := token.split("/", true)
	return Vector3i(
		_resolve_obj_index(str(fields[0]) if fields.size() > 0 else "", position_count),
		_resolve_obj_index(str(fields[1]) if fields.size() > 1 else "", uv_count),
		_resolve_obj_index(str(fields[2]) if fields.size() > 2 else "", normal_count)
	)

static func _resolve_obj_index(raw: String, count: int) -> int:
	if raw.is_empty() or not raw.is_valid_int():
		return -1
	var parsed := int(raw)
	return parsed - 1 if parsed > 0 else count + parsed

static func _load_material_library(mtl_path: String) -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(mtl_path):
		return result
	var file := FileAccess.open(mtl_path, FileAccess.READ)
	if file == null:
		return result
	var source := file.get_as_text()
	file.close()
	var current_name := ""
	var current_color := Color.WHITE
	var current_alpha := 1.0
	var current_texture := ""
	for raw_line in source.split("\n", false):
		var line := str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var tokens := line.split(" ", false)
		match str(tokens[0]) if not tokens.is_empty() else "":
			"newmtl":
				if not current_name.is_empty():
					result[current_name] = _make_material(Color(current_color.r, current_color.g, current_color.b, current_alpha), mtl_path.get_base_dir().path_join(current_texture))
				current_name = line.trim_prefix("newmtl").strip_edges()
				current_color = Color.WHITE
				current_alpha = 1.0
				current_texture = ""
			"Kd":
				if tokens.size() >= 4:
					current_color = Color(float(tokens[1]), float(tokens[2]), float(tokens[3]))
			"d":
				if tokens.size() >= 2:
					current_alpha = clampf(float(tokens[1]), 0.0, 1.0)
			"Tr":
				if tokens.size() >= 2:
					current_alpha = 1.0 - clampf(float(tokens[1]), 0.0, 1.0)
			"map_Kd":
				current_texture = line.trim_prefix("map_Kd").strip_edges()
			_:
				continue
	if not current_name.is_empty():
		result[current_name] = _make_material(Color(current_color.r, current_color.g, current_color.b, current_alpha), mtl_path.get_base_dir().path_join(current_texture))
	return result

static func _make_material(color: Color, texture_path: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.72
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not texture_path.is_empty() and FileAccess.file_exists(texture_path):
		var image := Image.new()
		if image.load(texture_path) == OK:
			material.albedo_texture = ImageTexture.create_from_image(image)
	return material
