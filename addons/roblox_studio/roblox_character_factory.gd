@tool
class_name RobloxCharacterFactory
extends RefCounted

const FACE_TEXTURE := preload("res://assets/avatar/default_face.png")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")


static func create_r6(studio: Node, parent: Node3D, world_position: Vector3, character_name: String = "R6Character") -> Node3D:
	if studio == null or parent == null or not studio.has_method("_build_block_instance"):
		return null
	var root := Node3D.new()
	root.name = character_name
	root.set_meta("roblox_class", "Model")
	root.set_meta("block_name", character_name)
	root.set_meta("PrimaryPart", "HumanoidRootPart")
	root.add_to_group("studio_character_models")
	parent.add_child(root, true)
	root.global_position = world_position

	var specs := [
		["HumanoidRootPart", "Box", Vector3(0, 3.0, 0), Vector3(1.8, 2.0, 0.6), Color(1, 1, 1, 0.0)],
		["Torso", "Box", Vector3(0, 3.0, 0), Vector3(2.0, 2.0, 1.0), Color("#2E77BB")],
		["Head", "Cylinder", Vector3(0, 4.6, 0), Vector3(1.2, 0.6, 1.2), Color("#F4C542")],
		["Left Arm", "Box", Vector3(-1.5, 3.0, 0), Vector3(1.0, 2.0, 1.0), Color("#F4C542")],
		["Right Arm", "Box", Vector3(1.5, 3.0, 0), Vector3(1.0, 2.0, 1.0), Color("#F4C542")],
		["Left Leg", "Box", Vector3(-0.5, 1.0, 0), Vector3(1.0, 2.0, 1.0), Color("#4BAE32")],
		["Right Leg", "Box", Vector3(0.5, 1.0, 0), Vector3(1.0, 2.0, 1.0), Color("#4BAE32")],
	]
	var parts: Dictionary = {}
	for spec in specs:
		var part: MeshInstance3D = studio.call("_build_block_instance", str(spec[1]), spec[4], "Plastic", 1.0 if spec[0] == "HumanoidRootPart" else 0.0, spec[0] != "HumanoidRootPart", str(spec[0]))
		if part == null:
			continue
		part.name = str(spec[0])
		part.position = spec[2]
		part.scale = spec[3]
		part.set_meta("roblox_class", "Part")
		part.set_meta("anchored", true)
		part.set_meta("character_part", true)
		part.set_meta("bobux_character_contract_proxy", true)
		part.set_meta("roblox_properties", {
			"Name": str(spec[0]),
			"Anchored": true,
			"CanCollide": spec[0] != "HumanoidRootPart",
			"Size": [spec[3].x, spec[3].y, spec[3].z],
		})
		root.add_child(part, true)
		# Contract Parts stay editable in Explorer/Properties, while the visible
		# representation comes from the exact same scene used in Play Test.
		part.visible = false
		parts[spec[0]] = part

	var humanoid := Node.new()
	humanoid.name = "Humanoid"
	humanoid.set_meta("roblox_class", "Humanoid")
	humanoid.set_meta("roblox_properties", {
		"WalkSpeed": 16.0,
		"JumpPower": 50.0,
		"HipHeight": 2.0,
		"MaxHealth": 100.0,
		"Health": 100.0,
		"AutoRotate": true,
		"RigType": "R6",
	})
	root.add_child(humanoid, true)
	var animator := Node.new()
	animator.name = "Animator"
	animator.set_meta("roblox_class", "Animator")
	humanoid.add_child(animator, true)

	var body_colors := Node.new()
	body_colors.name = "Body Colors"
	body_colors.set_meta("roblox_class", "BodyColors")
	body_colors.set_meta("roblox_properties", {
		"HeadColor3": [0.957, 0.773, 0.259],
		"LeftArmColor3": [0.957, 0.773, 0.259],
		"RightArmColor3": [0.957, 0.773, 0.259],
		"TorsoColor3": [0.18, 0.467, 0.733],
		"LeftLegColor3": [0.294, 0.682, 0.196],
		"RightLegColor3": [0.294, 0.682, 0.196],
	})
	root.add_child(body_colors, true)

	var joints := [
		["RootJoint", "HumanoidRootPart", "Torso"],
		["Neck", "Torso", "Head"],
		["Left Shoulder", "Torso", "Left Arm"],
		["Right Shoulder", "Torso", "Right Arm"],
		["Left Hip", "Torso", "Left Leg"],
		["Right Hip", "Torso", "Right Leg"],
	]
	for joint_spec in joints:
		var joint := Node.new()
		joint.name = str(joint_spec[0])
		joint.set_meta("roblox_class", "Motor6D")
		joint.set_meta("Part0", str(joint_spec[1]))
		joint.set_meta("Part1", str(joint_spec[2]))
		var joint_parent: Node = parts.get(str(joint_spec[1]), root) as Node
		joint_parent.add_child(joint, true)

	if parts.has("Head"):
		_add_face(parts["Head"] as MeshInstance3D)
	_add_runtime_character_visual(root)
	return root


static func _add_runtime_character_visual(root: Node3D) -> void:
	if root == null or PLAYER_SCENE == null:
		return
	var preview := PLAYER_SCENE.instantiate() as CharacterBody3D
	if preview == null:
		return
	preview.name = "CharacterVisual"
	preview.set_meta("bobux_studio_character_preview", true)
	preview.set_meta("bobux_internal_editor_visual", true)
	preview.set_meta("bobux_default_character_preview", true)
	preview.set("is_ui_preview", true)
	preview.set("use_local_avatar_fallback", true)
	root.add_child(preview, true)
	preview.position = Vector3.ZERO
	preview.rotation = Vector3.ZERO
	var preview_camera := preview.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if preview_camera != null:
		preview_camera.current = false
	var label := preview.get_node_or_null("Visuals/NameLabel") as Label3D
	if label != null:
		label.visible = false
	preview.process_mode = Node.PROCESS_MODE_DISABLED


static func _add_face(head: MeshInstance3D) -> void:
	var face := MeshInstance3D.new()
	face.name = "face"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.88, 0.56)
	face.mesh = quad
	face.position = Vector3(0.0, -0.02, -0.505)
	face.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = FACE_TEXTURE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.05
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.surface_set_material(0, material)
	face.set_meta("roblox_class", "Decal")
	face.set_meta("Face", 5)
	face.set_meta("bobux_runtime_generated", true)
	head.add_child(face)
