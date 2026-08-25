extends Node3D

var spawner_block: MeshInstance3D = null
var spawn_handler: Callable = Callable()
var room_id: String = ""
var trigger_height: float = 3.2
var trigger_mask: int = 0
var cooldown_msec: int = 1400
var spawn_zone_radius: float = 8.5

var _area: Area3D = null
func configure(block: MeshInstance3D, handler: Callable, collision_mask: int, p_trigger_height: float, p_cooldown_msec: int, p_spawn_zone_radius: float) -> void:
	spawner_block = block
	spawn_handler = handler
	trigger_mask = collision_mask
	trigger_height = p_trigger_height
	cooldown_msec = p_cooldown_msec
	spawn_zone_radius = p_spawn_zone_radius
	room_id = str(block.get_meta("room_id", "")).strip_edges() if block != null else ""
	_build_area()

func _build_area() -> void:
	if spawner_block == null or _area != null:
		return
	_area = Area3D.new()
	_area.name = "SpawnRequestArea"
	_area.monitoring = true
	_area.monitorable = true
	_area.collision_layer = 0
	_area.collision_mask = trigger_mask
	var area_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(
		maxf(2.0, spawner_block.scale.x + 1.0),
		maxf(trigger_height, spawner_block.scale.y + trigger_height),
		maxf(2.0, spawner_block.scale.z + 1.0)
	)
	area_shape.shape = trigger_box
	area_shape.position = Vector3(0.0, (trigger_box.size.y * 0.5) - (spawner_block.scale.y * 0.5), 0.0)
	_area.add_child(area_shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

func _on_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	# Intentionally no auto-spawn on touch. Main.gd handles an explicit
	# player E/interact request so joining a mode never creates a car by itself.
	return

func _is_spawn_zone_clear() -> bool:
	if spawner_block == null:
		return false
	var spawn_position := get_spawn_global_position()
	var tree := get_tree()
	if tree == null:
		return true
	for node in tree.get_nodes_in_group("chaos_cars"):
		if not (node is Node3D):
			continue
		var car := node as Node3D
		if not is_instance_valid(car):
			continue
		var car_room := str(car.get("room_id")).strip_edges()
		if not room_id.is_empty() and not car_room.is_empty() and car_room != room_id:
			continue
		if car.global_position.distance_to(spawn_position) <= spawn_zone_radius:
			return false
	return true

func get_spawn_global_position() -> Vector3:
	if spawner_block == null:
		return global_position
	return spawner_block.global_position + spawner_block.global_transform.basis.z.normalized() * 9.0 + Vector3.UP * ((spawner_block.scale.y * 0.5) + 1.35)
