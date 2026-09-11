extends Node

# Preserve Instance hierarchy; the Godot joint only connects the corresponding
# physics bodies. Removal of the Roblox joint removes this adapter as well.
var joint: Generic6DOFJoint3D
var pending := false

func request_refresh() -> void:
	if pending: return
	pending = true
	call_deferred("_refresh")

func _ready() -> void:
	request_refresh()

func _refresh() -> void:
	pending = false
	if is_instance_valid(joint):
		remove_child(joint)
		joint.queue_free()
	joint = null
	var source := get_parent()
	if source == null or not source.is_inside_tree(): return
	var engine := get_tree().root.get_node_or_null("LuaScriptEngine")
	if engine == null: return
	var wrapper = engine.BobuxInstance.new(source)
	var first = wrapper._get(&"Part0")
	var second = wrapper._get(&"Part1")
	if first == null or second == null: return
	var a: Node = first.node
	var b: Node = second.node
	if not a is MeshInstance3D or not b is MeshInstance3D or a == b: return
	if not wrapper._is_node_under_workspace(a) or not wrapper._is_node_under_workspace(b): return
	if not bool(source.get_meta("Enabled", source.get_meta("roblox_properties", {}).get("Enabled", true))): return
	var physics := preload("res://addons/roblox_runtime/roblox_part_physics.gd")
	var body_a := physics.body_for(a, true)
	var body_b := physics.body_for(b, true)
	if body_a == null or body_b == null: return
	if str(source.get_meta("roblox_class", "")) != "WeldConstraint":
		var c0 = wrapper._get(&"C0")
		var c1 = wrapper._get(&"C1")
		var transform_ = wrapper._get(&"Transform")
		var desired: Transform3D = first._get(&"CFrame").transform * c0.transform * transform_.transform * c1.transform.affine_inverse()
		second._set(&"CFrame", engine.BobuxCFrame.new(desired))
	joint = Generic6DOFJoint3D.new()
	joint.set_meta("bobux_runtime_generated", true)
	add_child(joint)
	joint.global_transform = Transform3D(body_a.global_basis.orthonormalized(), body_b.global_position)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.exclude_nodes_from_collision = true
