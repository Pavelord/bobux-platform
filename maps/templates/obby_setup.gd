extends Node3D

func _ready() -> void:
	_create_collisions(self)

func _create_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var shape = node.mesh.create_trimesh_shape()
		if shape:
			var static_body = StaticBody3D.new()
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = shape
			static_body.add_child(collision_shape)
			node.add_child(static_body)
	
	for child in node.get_children():
		_create_collisions(child)
