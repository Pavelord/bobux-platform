@tool
class_name RbxlInstanceBuilder
extends RefCounted

## Builds a Godot node tree from an intermediate JSON (produced by
## `rbxl_converter.py`). Used by the EditorImportPlugin to emit a `.tscn`
## PackedScene. The runtime Place Editor uses `rbxl_runtime_importer.gd`
## instead, because it routes Roblox Parts through the editor's existing
## `_build_block_instance` machinery so they serialize into `map_data.json`.
##
## Coordinate conversion: Roblox is Y-up right-handed with +Z forward; Godot is
## Y-up right-handed with -Z forward. We flip Z on both the basis and origin.

const _Materials := preload("res://addons/rbxl_importer/material_cache.gd")
const _Wedges := preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")

const STUDS_TO_METERS := 0.5

var imported_instance_count: int = 0
var _mat_cache: Object = null
var _node_map: Dictionary = {} # referent_id (String) → Node
var _options: Dictionary = {}

## Optional callback the Place Editor can hook to turn each part into a Bobux
## "studio_parts" block instead of a free-form node. Signature:
##     (roblox_class, properties_dict, scale) -> Node
var custom_part_builder: Callable = Callable()


func build(json: Dictionary, options: Dictionary = {}) -> Node3D:
	_mat_cache = _Materials.new()
	_node_map.clear()
	imported_instance_count = 0
	_options = options

	var scale: float = float(options.get("scale_factor", STUDS_TO_METERS))
	var root := Node3D.new()
	root.name = "RobloxPlace"

	# First pass: create every instance (without parenting).
	var instances: Dictionary = json.get("instances", {})
	for ref_id in instances:
		var inst: Dictionary = instances[ref_id]
		var node: Node = _create_instance(inst, scale)
		if node == null:
			continue
		_node_map[ref_id] = node
		node.name = _safe_name(inst.get("properties", {}).get("Name", inst.get("class", "Instance")))
		imported_instance_count += 1

	# Second pass: wire up hierarchy from the PRNT edges.
	var merge_parts: bool = bool(options.get("merge_parts", false))
	var hierarchy: Array = json.get("hierarchy", [])
	var workspace_node: Node = _node_map.get(_find_workspace_ref(instances), root)

	for edge in hierarchy:
		var child_id := str(edge.get("child", ""))
		var parent_id := str(edge.get("parent", ""))
		var child: Node = _node_map.get(child_id)
		if child == null or not is_instance_valid(child):
			continue
		if child.get_parent() != null:
			continue # already attached

		if parent_id == "-1" or not _node_map.has(parent_id):
			root.add_child(child, false)
			child.owner = root
			continue

		var parent_node: Node = _node_map[parent_id]
		# Skip Workspace as an intermediate: when merge_parts is enabled, attach
		# Workspace's children directly to root to keep the tree flat.
		if merge_parts and _is_workspace(parent_node):
			root.add_child(child, false)
			child.owner = root
		else:
			parent_node.add_child(child, false)
			child.owner = root

	# Attach any nodes that never appeared in the hierarchy.
	for ref_id in _node_map:
		var node: Node = _node_map[ref_id]
		if node.get_parent() == null and is_instance_valid(node):
			root.add_child(node, false)
			node.owner = root

	return root


# ── Instance dispatch ────────────────────────────────────────────────────────

func _create_instance(inst: Dictionary, scale: float) -> Node:
	var class_name_: String = inst.get("class", "")
	var props: Dictionary = inst.get("properties", {})

	# Runtime override: the Place Editor hooks here to produce "studio_parts".
	if custom_part_builder.is_valid():
		var is_part := _is_part_class(class_name_)
		if is_part:
			var custom: Node = custom_part_builder.call(class_name_, props, scale)
			if custom != null and is_instance_valid(custom):
				return custom

	match class_name_:
		"Part", "WedgePart", "CornerWedgePart", "TrussPart", "SpawnLocation", \
		"VehicleSeat", "Seat", "MeshPart", "UnionOperation", "NegateOperation", \
		"IntersectOperation":
			return _build_part(class_name_, props, scale)
		"Model", "Folder", "Configuration", "Workspace", "ReplicatedStorage", \
		"ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", \
		"Players", "Lighting", "SoundService", "Teams", "Chat":
			var n := Node3D.new()
			n.set_meta("roblox_class", class_name_)
			return n
		"Terrain":
			return _build_terrain(props, scale)
		"Script", "LocalScript", "ModuleScript":
			return _build_script_node(class_name_, props)
		"PointLight", "SpotLight", "SurfaceLight":
			return _build_light(class_name_, props, scale)
		"Lighting":
			if bool(_options.get("import_lighting", true)):
				return _build_lighting(props)
			return null
		"Sky":
			return _build_sky(props)
		"Atmosphere":
			return _build_atmosphere(props)
		"Camera":
			return _build_camera(props, scale)
		"BillboardGui", "ScreenGui", "SurfaceGui":
			return null # GUI handled on import elsewhere; skip in tscn path
		"Decal", "Texture":
			return null # handled by parent part
		"Sound":
			return _build_sound(props)
		"ParticleEmitter", "Fire", "Smoke", "Sparkles":
			return _build_particles(class_name_, props, scale)
		"Attachment":
			return _build_attachment(props, scale)
		"WeldConstraint", "Motor6D", "HingeConstraint", "BallSocketConstraint", \
		"SpringConstraint":
			return _build_constraint(class_name_, props)
		"SpecialMesh", "BlockMesh", "CylinderMesh":
			return null
		"Humanoid", "HumanoidDescription":
			var h := Node.new()
			h.set_meta("roblox_class", class_name_)
			return h
		_:
			var n := Node3D.new()
			n.set_meta("roblox_class", class_name_)
			return n


# ── Parts ───────────────────────────────────────────────────────────────────

func _build_part(class_name_: String, props: Dictionary, scale: float) -> Node:
	var size := _get_vector3(props, "Size", Vector3(4, 1.2, 2))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _get_part_mesh(class_name_, props, size * scale)
	mesh_instance.material_override = _mat_cache.get_part_material(props)
	mesh_instance.set_meta("roblox_class", class_name_)
	mesh_instance.set_meta("roblox_size", [size.x, size.y, size.z])

	var cf: Variant = _prop(props, "CFrame", null)
	var transform := _cframe_to_transform(cf, scale) if cf != null else Transform3D.IDENTITY
	mesh_instance.transform = transform

	var can_collide: bool = bool(_prop(props, "CanCollide", true))
	var anchored: bool = bool(_prop(props, "Anchored", true))

	var body: PhysicsBody3D
	if anchored:
		body = StaticBody3D.new()
	else:
		body = RigidBody3D.new()
	body.transform = transform
	# Clear the mesh instance transform since the body now carries it.
	mesh_instance.transform = Transform3D.IDENTITY

	var col := CollisionShape3D.new()
	col.shape = _get_collision_shape(class_name_, props, size * scale)
	col.disabled = not can_collide
	body.add_child(col, false)

	body.add_child(mesh_instance, false)
	mesh_instance.owner = body

	body.set_meta("roblox_class", class_name_)
	body.set_meta("anchored", anchored)
	body.set_meta("can_collide", can_collide)
	return body


func _get_part_mesh(class_name_: String, props: Dictionary, size: Vector3) -> Mesh:
	match class_name_:
		"Part":
			var shape_enum: int = int(_prop(props, "Shape", _prop(props, "shape", 1)))
			match shape_enum:
				1: # Block
					var m := BoxMesh.new()
					m.size = size
					return m
				0: # Ball
					var m := SphereMesh.new()
					m.radius = min(size.x, min(size.y, size.z)) * 0.5
					m.height = m.radius * 2.0
					return m
				2: # Cylinder (Roblox cylinders are oriented along X)
					var m := CylinderMesh.new()
					m.top_radius = size.z * 0.5
					m.bottom_radius = size.z * 0.5
					m.height = size.x
					return m
				_:
					var m := BoxMesh.new()
					m.size = size
					return m
		"WedgePart":
			return _Wedges.build_wedge(size)
		"CornerWedgePart":
			return _Wedges.build_corner_wedge(size)
		"TrussPart":
			return _Wedges.build_truss(size)
		"MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation":
			# Without the asset binary we approximate with a box of the same
			# bounding size; the runtime importer attaches the asset reference
			# as metadata so it can be fetched later.
			var m := BoxMesh.new()
			m.size = size
			return m
		"SpawnLocation", "VehicleSeat", "Seat":
			var m := BoxMesh.new()
			m.size = size
			return m
		_:
			var m := BoxMesh.new()
			m.size = size
			return m


func _get_collision_shape(class_name_: String, props: Dictionary, size: Vector3) -> Shape3D:
	match class_name_:
		"Part":
			var shape_enum: int = int(_prop(props, "Shape", _prop(props, "shape", 1)))
			match shape_enum:
				0: # Ball
					var s := SphereShape3D.new()
					s.radius = min(size.x, min(size.y, size.z)) * 0.5
					return s
				2: # Cylinder
					var s := CylinderShape3D.new()
					s.radius = size.z * 0.5
					s.height = size.x
					return s
				_:
					var s := BoxShape3D.new()
					s.size = size
					return s
		_:
			var s := BoxShape3D.new()
			s.size = size
			return s


# ── Coordinate / property conversions ───────────────────────────────────────

func _cframe_to_transform(cf: Variant, scale: float) -> Transform3D:
	if cf == null:
		return Transform3D.IDENTITY
	var cfd: Dictionary = cf if cf is Dictionary else {}
	var pos: Array = cfd.get("position", [0.0, 0.0, 0.0])
	var rot: Array = cfd.get("rotation", [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])

	# Convert Roblox's Z-forward basis into Godot's -Z-forward basis: S * R * S.
	var r0: Array = rot[0] if rot.size() > 0 else [1.0, 0.0, 0.0]
	var r1: Array = rot[1] if rot.size() > 1 else [0.0, 1.0, 0.0]
	var r2: Array = rot[2] if rot.size() > 2 else [0.0, 0.0, 1.0]
	var basis := Basis(
		Vector3(r0[0], r1[0], -r2[0]),
		Vector3(r0[1], r1[1], -r2[1]),
		Vector3(-r0[2], -r1[2], r2[2]))
	if absf(basis.determinant()) > 0.001:
		basis = basis.orthonormalized()
	var origin := Vector3(
		float(pos[0]) * scale,
		float(pos[1]) * scale,
		-float(pos[2]) * scale)
	return Transform3D(basis, origin)


func _get_vector3(props: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var v: Variant = _prop(props, key, null)
	if v == null:
		return fallback
	if v is Array:
		var a := v as Array
		return Vector3(
			float(a[0]) if a.size() > 0 else fallback.x,
			float(a[1]) if a.size() > 1 else fallback.y,
			float(a[2]) if a.size() > 2 else fallback.z)
	if v is Vector3:
		return v
	return fallback


static func _prop(props: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if props.has(key):
		return props[key]
	var lower := key.to_lower()
	if props.has(lower):
		return props[lower]
	for candidate in props.keys():
		if str(candidate).to_lower() == lower:
			return props[candidate]
	return fallback


# ── Lighting / atmosphere / sky ─────────────────────────────────────────────

func _build_lighting(props: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Lighting"

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = float(props.get("Brightness", 2.0))
	sun.light_color = Color(1.0, 0.98, 0.95)
	sun.shadow_enabled = true
	var tod: String = props.get("TimeOfDay", "14:00:00")
	var hour := 14.0
	if tod.split(":").size() >= 1:
		hour = float(tod.split(":")[0])
	sun.rotation_degrees = Vector3(-(hour / 24.0) * 360.0 + 90.0, -45.0, 0.0)
	node.add_child(sun, false)
	sun.owner = node

	var env := Environment.new()
	env.ambient_light_color = _color(props.get("Ambient", [0.5, 0.5, 0.5]))
	env.ambient_light_energy = 1.0
	var fog_end := float(props.get("FogEnd", 100000.0))
	if fog_end < 100000.0:
		env.fog_enabled = true
		env.fog_light_color = _color(props.get("FogColor", [1.0, 1.0, 1.0]))
		env.fog_density = 1.0 / maxf(fog_end, 1.0)

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	node.add_child(we, false)
	we.owner = node
	return node


func _build_sky(props: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Sky"
	node.set_meta("roblox_class", "Sky")
	return node


func _build_atmosphere(props: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Atmosphere"
	node.set_meta("roblox_class", "Atmosphere")
	return node


func _build_light(class_name_: String, props: Dictionary, scale: float) -> Node:
	var color := _color(props.get("Color", [1.0, 1.0, 1.0]))
	var brightness := float(props.get("Brightness", 1.0))
	var range_val := float(props.get("Range", 16.0)) * scale

	match class_name_:
		"PointLight", "SurfaceLight":
			var l := OmniLight3D.new()
			l.light_color = color
			l.light_energy = brightness * 2.0
			l.omni_range = range_val
			return l
		"SpotLight":
			var l := SpotLight3D.new()
			l.light_color = color
			l.light_energy = brightness * 2.0
			l.spot_range = range_val
			l.spot_angle = float(props.get("Angle", 45.0))
			return l
		_:
			return OmniLight3D.new()


func _build_camera(props: Dictionary, scale: float) -> Node:
	var cam := Camera3D.new()
	var cf: Variant = props.get("CFrame", null)
	if cf != null:
		cam.transform = _cframe_to_transform(cf, scale)
	cam.fov = float(props.get("FieldOfView", 70.0))
	return cam


# ── Scripts / Lua stubs ─────────────────────────────────────────────────────

func _build_script_node(class_name_: String, props: Dictionary) -> Node:
	var node := Node.new()
	node.set_meta("roblox_class", class_name_)
	var lua_source: String = props.get("Source", "")
	if not lua_source.is_empty():
		node.set_meta("lua_source", lua_source)

	if bool(_options.get("import_scripts", true)) and not lua_source.is_empty():
		var script := GDScript.new()
		script.source_code = _lua_to_gdscript_stub(lua_source, class_name_)
		node.set_script(script)
	return node


func _lua_to_gdscript_stub(lua_source: String, script_type: String) -> String:
	var out := PackedStringArray([
		"# AUTO-GENERATED from Roblox Luau (%s)" % script_type,
		"# Original Lua source preserved in node metadata (\"lua_source\").",
		"extends Node",
		"",
	])
	for line in lua_source.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("--"):
			out.append("# " + t.substr(2))
		elif t.is_empty():
			out.append("")
		else:
			out.append("# " + t)
	return "\n".join(out)


# ── Terrain ─────────────────────────────────────────────────────────────────

func _build_terrain(props: Dictionary, scale: float) -> Node3D:
	var node := Node3D.new()
	node.name = "Terrain"
	node.set_meta("roblox_class", "Terrain")
	if bool(_options.get("import_terrain", true)):
		var terrain_builder_script: GDScript = load("res://addons/rbxl_importer/terrain_builder.gd")
		var terrain_builder: RefCounted = terrain_builder_script.new()
		terrain_builder.build_into(node, props, scale)
	return node


# ── Misc nodes ──────────────────────────────────────────────────────────────

func _build_attachment(props: Dictionary, scale: float) -> Node3D:
	var n := Node3D.new()
	n.set_meta("roblox_class", "Attachment")
	var cf: Variant = props.get("CFrame", null)
	if cf != null:
		n.transform = _cframe_to_transform(cf, scale)
	return n


func _build_constraint(class_name_: String, props: Dictionary) -> Node:
	var n := Node3D.new()
	n.set_meta("roblox_class", class_name_)
	return n


func _build_sound(props: Dictionary) -> Node:
	var n := Node3D.new()
	n.set_meta("roblox_class", "Sound")
	var s := AudioStreamPlayer3D.new()
	s.name = "AudioStreamPlayer3D"
	n.add_child(s, false)
	s.owner = n
	return n


func _build_particles(class_name_: String, props: Dictionary, scale: float) -> Node:
	var n := GPUParticles3D.new()
	n.amount = 16
	n.set_meta("roblox_class", class_name_)
	return n


# ── Helpers ─────────────────────────────────────────────────────────────────

static func _is_part_class(class_name_: String) -> bool:
	return class_name_ in [
		"Part", "WedgePart", "CornerWedgePart", "TrussPart",
		"SpawnLocation", "VehicleSeat", "Seat", "MeshPart",
		"UnionOperation", "NegateOperation", "IntersectOperation",
	]


static func _is_workspace(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return str(node.get_meta("roblox_class", "")) == "Workspace"


func _find_workspace_ref(instances: Dictionary) -> String:
	for ref_id in instances:
		if str(instances[ref_id].get("class", "")) == "Workspace":
			return ref_id
	return ""


static func _safe_name(raw: String) -> String:
	var n := raw.strip_edges()
	if n.is_empty():
		n = "Instance"
	# Godot node names cannot contain '/' or ':' and should be unique.
	return n.replace("/", "_").replace(":", "_")


func _color(value: Variant) -> Color:
	return _Materials._color_from_array(value)
