extends RefCounted

static var cache: Dictionary = {}
const CELL := 16.0
static var full_builds := 0

static func is_part(node: Node) -> bool:
	return str(node.get_meta("roblox_class", "")) in ["Part", "MeshPart", "UnionOperation", "PartOperation", "NegateOperation", "WedgePart", "CornerWedgePart", "TrussPart", "Seat", "VehicleSeat", "SpawnLocation"]

static func _node_added(part: Node) -> void:
	if part is MeshInstance3D: invalidate(part)

static func _node_removed(part: Node) -> void:
	if part is MeshInstance3D:
		for index in cache.values(): _remove_part(index, part.get_instance_id())
	cache.erase(part.get_instance_id())

static func _visibility_changed(id: int) -> void:
	var part: Variant = instance_from_id(id)
	if is_instance_valid(part): invalidate(part)

static func _remove_part(index: Dictionary, id: int) -> void:
	for cell in index.cells.get(id, []):
		index.grid[cell].erase(id)
		if index.grid[cell].is_empty(): index.grid.erase(cell)
	index.large.erase(id)
	index.cells.erase(id)
	index.all.erase(id)
	index.dirty.erase(id)

static func invalidate(changed: Node = null) -> void:
	if changed == null:
		cache.clear()
		return
	if not changed is MeshInstance3D:
		for child in changed.get_children(): invalidate(child)
		return
	for index in cache.values(): index.dirty[changed.get_instance_id()] = true

static func bounds(part: Node3D) -> AABB:
	if bool(part.get_meta("bobux_character_part_proxy", false)):
		var size_: Vector3 = part.get_meta("Size", Vector3.ONE)
		return AABB(-size_ * 0.5, size_)

	# SpecialMesh changes the drawing, not the Part's contact/query volume.
	if str(part.get_meta("roblox_class", "")) in ["Part", "WedgePart", "CornerWedgePart", "TrussPart", "Seat", "VehicleSeat", "SpawnLocation"]:
		return AABB(-Vector3.ONE * 0.5, Vector3.ONE)
	return part.get_aabb() if part is MeshInstance3D else AABB(-Vector3.ONE * 0.5, Vector3.ONE)

static func _index_part(index: Dictionary, part: MeshInstance3D) -> void:
	var id := part.get_instance_id()
	_remove_part(index, id)
	if not part.visibility_changed.is_connected(_visibility_changed.bind(id)):
		part.visibility_changed.connect(_visibility_changed.bind(id))
	if part.mesh == null or not part.is_visible_in_tree() or part.is_queued_for_deletion() or not is_part(part): return
	index.all[id] = true
	var box: AABB = part.global_transform * bounds(part)
	var low := Vector3i((box.position / CELL).floor())
	var high := Vector3i((box.end / CELL).floor())
	var span := high - low + Vector3i.ONE
	if span.x * span.y * span.z > 512:
		index.large.append(id)
		return
	var cells: Array = []
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var bucket: Array = index.grid.get(cell, [])
				bucket.append(id)
				index.grid[cell] = bucket
				cells.append(cell)
	index.cells[id] = cells

static func _candidates(root: Node, center: Vector3, radius: float) -> Array:
	return _candidates_bounds(root, AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0))

static func _candidates_bounds(root: Node, query_bounds: AABB) -> Array:
	var id := root.get_instance_id()
	var index: Dictionary = cache.get(id, {})
	if index.is_empty():
		var tree := root.get_tree()
		if not tree.node_added.is_connected(_node_added):
			tree.node_added.connect(_node_added)
			tree.node_removed.connect(_node_removed)
		index = {"grid": {}, "large": [], "cells": {}, "dirty": {}, "all": {}}
		full_builds += 1
		for part in root.find_children("*", "MeshInstance3D", true, false):
			_index_part(index, part)
		cache[id] = index
	else:
		var dirty: Array = index.dirty.keys()
		index.dirty.clear()
		for part_id in dirty:
			var part: Variant = instance_from_id(part_id)
			if is_instance_valid(part) and (root == part or root.is_ancestor_of(part)): _index_part(index, part)
			else: _remove_part(index, part_id)
	var ids := {}
	for part_id in index.large: ids[part_id] = true
	var low := Vector3i((query_bounds.position / CELL).floor())
	var high := Vector3i((query_bounds.end / CELL).floor())
	var span := high - low + Vector3i.ONE
	if span.x * span.y * span.z > 4096:
		ids = index.all
	else:
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					for part_id in index.grid.get(Vector3i(x, y, z), []): ids[part_id] = true
	var result: Array = []
	for part_id in ids:
		var part: Variant = instance_from_id(part_id)
		if is_instance_valid(part) and not part.is_queued_for_deletion(): result.append(part)
	# CharacterBody lives beside the Workspace alias in Studio. Match its bound
	# Workspace ID, not the whole SceneTree (which may contain editor previews).
	for character in root.get_tree().get_nodes_in_group("roblox_live_characters"):
		if not is_instance_valid(character) or character.is_queued_for_deletion(): continue
		if not root.is_ancestor_of(character) and int(character.get_meta("bobux_workspace_instance_id", 0)) != root.get_instance_id(): continue
		for child in character.get_children():
			if child is Node3D and bool(child.get_meta("bobux_character_part_proxy", false)): result.append(child)
	return result

# Mesh bounding boxes, including non-collidable queryable Parts. Evaluate in
# part-local space so a rotated building doesn't become a huge world AABB.
static func in_radius(root: Node, position_: Vector3, radius: float, filters: Array, include: bool, max_parts: int, respect_collision: bool) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(root) or not root.is_inside_tree() or not is_finite(radius) or radius < 0: return result
	for candidate in _candidates(root, position_, radius):
		var part := candidate as Node3D
		if not part.is_inside_tree() or not part.is_visible_in_tree(): continue
		if not bool(part.get_meta("bobux_character_part_proxy", false)) and (not part is MeshInstance3D or part.mesh == null or (root != part and not root.is_ancestor_of(part))): continue
		var props: Dictionary = part.get_meta("roblox_properties", {})
		var property := "CanCollide" if respect_collision else "CanQuery"
		if not bool(part.get_meta("can_collide" if respect_collision else property, props.get(property, true))): continue
		var filtered := false
		for filter in filters:
			if is_instance_valid(filter) and (filter == part or filter.is_ancestor_of(part)): filtered = true; break
		if filtered != include: continue
		if is_zero_approx(part.global_basis.determinant()): continue
		var box := bounds(part)
		var local_point := part.to_local(position_)
		var closest := local_point.clamp(box.position, box.end)
		if part.to_global(closest).distance_squared_to(position_) > radius * radius: continue
		result.append(part)
		if max_parts > 0 and result.size() >= max_parts: break
	return result

static func in_box(root: Node, frame: Transform3D, size_: Vector3, filters: Array, include: bool, max_parts: int, respect_collision: bool) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(root) or not root.is_inside_tree() or not size_.is_finite() or not frame.is_finite(): return result
	var half := size_.abs() * 0.5
	var basis := frame.basis.orthonormalized()
	# A cyclone is tall and narrow. Its enclosing sphere used to query almost
	# the whole island and run 15 separating axes against every distant brick.
	var query_bounds := Transform3D(basis, frame.origin) * AABB(-half, half * 2.0)
	for candidate in _candidates_bounds(root, query_bounds):
		var part := candidate as Node3D
		if not part.is_inside_tree() or not part.is_visible_in_tree(): continue
		var box: AABB = bounds(part)
		if not query_bounds.grow(0.00001).intersects(part.global_transform * box): continue
		var props: Dictionary = part.get_meta("roblox_properties", {})
		var property := "CanCollide" if respect_collision else "CanQuery"
		if not bool(part.get_meta("can_collide" if respect_collision else property, props.get(property, true))): continue
		var filtered := false
		for filter in filters:
			if is_instance_valid(filter) and (filter == part or filter.is_ancestor_of(part)): filtered = true; break
		if filtered != include or is_zero_approx(part.global_basis.determinant()): continue
		var part_basis: Basis = part.global_basis.orthonormalized()
		var extent: Vector3 = box.size * part.global_basis.get_scale().abs() * 0.5
		var offset: Vector3 = part.to_global(box.get_center()) - frame.origin
		var axes: Array[Vector3] = [basis.x, basis.y, basis.z, part_basis.x, part_basis.y, part_basis.z]
		for first in [basis.x, basis.y, basis.z]:
			for second in [part_basis.x, part_basis.y, part_basis.z]:
				axes.append(first.cross(second))
		var overlap := true
		for axis in axes:
			if axis.length_squared() < 0.00000001: continue
			var a := absf(axis.dot(basis.x)) * half.x + absf(axis.dot(basis.y)) * half.y + absf(axis.dot(basis.z)) * half.z
			var b := absf(axis.dot(part_basis.x)) * extent.x + absf(axis.dot(part_basis.y)) * extent.y + absf(axis.dot(part_basis.z)) * extent.z
			if absf(axis.dot(offset)) > a + b + 0.00001:
				overlap = false
				break
		if overlap:
			result.append(part)
			if max_parts > 0 and result.size() >= max_parts: break
	return result


static func collision_shape(part: MeshInstance3D) -> Shape3D:
	var dimensions := (bounds(part).size * part.global_basis.get_scale().abs()).max(Vector3.ONE * 0.01)
	var kind := str(part.get_meta("roblox_class", "Part"))
	if kind in ["WedgePart", "CornerWedgePart"]:
		var builder := preload("res://addons/rbxl_importer/wedge_mesh_builder.gd")
		var mesh := builder.build_wedge(dimensions) if kind == "WedgePart" else builder.build_corner_wedge(dimensions)
		return mesh.create_convex_shape()
	var shape_name := str(part.get_meta("shape_type", ""))
	if shape_name in ["Sphere", "Ball"]:
		var sphere := SphereShape3D.new()
		sphere.radius = dimensions.x * 0.5
		return sphere
	if shape_name == "Cylinder":
		var cylinder := CylinderShape3D.new()
		cylinder.height = dimensions.y
		cylinder.radius = maxf(dimensions.x, dimensions.z) * 0.5
		return cylinder
	var box := BoxShape3D.new()
	box.size = dimensions
	return box
