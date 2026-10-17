extends RefCounted
## Standard seat inputs are associated with a server-selected Humanoid. The
## client never supplies an actor, an Occupant, or arbitrary seat properties.

static func is_seat(seat: Node) -> bool:
	return is_instance_valid(seat) and str(seat.get_meta("roblox_class", "")) in ["Seat", "VehicleSeat"]

static func occupant(seat: Node) -> Node:
	if not is_instance_valid(seat): return null
	var value: Variant = seat.get_meta("Occupant") if seat.has_meta("Occupant") else null
	if value is LuaScriptEngine.BobuxInstance: value = value.node
	return value if is_instance_valid(value) and value is Node else null

static func assigned_seat(character: Node) -> Node:
	if not is_instance_valid(character): return null
	var humanoid := character.get_node_or_null("Humanoid")
	if humanoid == null: return null
	var value: Variant = humanoid.get_meta("SeatPart") if humanoid.has_meta("SeatPart") else null
	if value is LuaScriptEngine.BobuxInstance: value = value.node
	return value if is_instance_valid(value) and value is Node else null

static func can_sit(seat: Node, character: Node, workspace: Node, contact: bool = false) -> bool:
	if not is_seat(seat) or not seat is Node3D or not character is Node3D or not is_instance_valid(workspace): return false
	if not seat.is_inside_tree() or seat.is_queued_for_deletion() or not workspace.is_ancestor_of(seat): return false
	var properties: Dictionary = seat.get_meta("roblox_properties", {})
	if bool(seat.get_meta("Disabled", seat.get_meta("disabled", properties.get("Disabled", false)))): return false
	if character.has_method("get_health") and float(character.call("get_health")) <= 0.0: return false
	var current := occupant(seat)
	if current != null and current.get_parent() != character: return false
	if not contact: return true # An authored server Sit may teleport a Humanoid.
	var scale := float(character.get_meta("roblox_stud_scale", workspace.get_meta("roblox_stud_scale", 1.0)))
	if not is_finite(scale) or scale <= 0.0: return false
	if not character.global_position.is_finite() or not seat.global_position.is_finite(): return false
	return character.global_position.distance_to(seat.global_position) <= 4.0 * scale + (seat as Node3D).global_basis.get_scale().length() * 0.5

static func can_drive(seat: Node, character: Node, workspace: Node, input: Vector2) -> bool:
	if not input.is_finite() or absf(input.x) > 1.0 or absf(input.y) > 1.0: return false
	if not can_sit(seat, character, workspace) or str(seat.get_meta("roblox_class", "")) != "VehicleSeat": return false
	var current := occupant(seat)
	return current != null and current.get_parent() == character and assigned_seat(character) == seat

static func apply_view(seat: Node, state: Dictionary, engine: Node) -> void:
	# Roblox Occupant itself is NotReplicated. Reconstruct the observable seat
	# attachment from Bobux's authoritative occupancy, even if an avatar arrives
	# after the seat's snapshot. Never interpret it as a client property write.
	var properties: Dictionary = seat.get_meta("roblox_properties", {})
	var peer := int(properties.get("BobuxSeatOccupantPeer", 0))
	var character: Variant = state.nodes.get("character:%d" % peer)
	var humanoid: Node = character.get_node_or_null("Humanoid") if is_instance_valid(character) else null
	var previous := occupant(seat)
	seat.set_meta("Occupant", humanoid)
	if previous == humanoid: return
	if previous != null and assigned_seat(previous.get_parent()) == seat:
		previous.set_meta("SeatPart", null)
		previous.set_meta("Sit", false)
	if humanoid != null:
		humanoid.set_meta("SeatPart", seat)
		humanoid.set_meta("Sit", true)
	engine.fire_roblox_instance_event(seat, "PropertyChanged_Occupant", [])
	engine.fire_roblox_instance_event(seat, "Changed", ["Occupant"])
