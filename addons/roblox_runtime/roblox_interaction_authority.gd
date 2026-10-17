extends RefCounted
## Input identifies an existing interaction; its actor and range come from the
## server's room state. Never accept a client-supplied Player or position.

const Interaction = preload("res://addons/roblox_runtime/roblox_interaction_runtime.gd")

static func event_for(target: Node) -> String:
	if not is_instance_valid(target): return ""
	match str(target.get_meta("roblox_class", "")):
		"ProximityPrompt": return "Triggered"
		"ClickDetector": return "MouseClick"
	return ""

static func can_activate(target: Node, character: Node, workspace: Node, event_name: String) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(character) or not is_instance_valid(workspace): return false
	if not character is Node3D or not target.is_inside_tree() or target.is_queued_for_deletion(): return false
	if event_for(target) != event_name or not workspace.is_ancestor_of(target): return false
	var owner := target.get_parent()
	while owner != null and owner != workspace:
		if str(owner.get_meta("roblox_class", "")) in ["Backpack", "StarterPack", "ServerStorage"] or owner == character: return false
		owner = owner.get_parent()
	var properties: Dictionary = target.get_meta("roblox_properties", {})
	if event_name == "Triggered" and not bool(target.get_meta("Enabled", properties.get("Enabled", true))): return false
	if character.has_method("get_health") and float(character.call("get_health")) <= 0.0: return false
	var distance := float(target.get_meta("MaxActivationDistance", properties.get("MaxActivationDistance", 10.0 if event_name == "Triggered" else 32.0)))
	var scale := float(character.get_meta("roblox_stud_scale", workspace.get_meta("roblox_stud_scale", 1.0)))
	if not is_finite(distance) or not is_finite(scale) or distance < 0.0 or scale <= 0.0: return false
	var anchor := Interaction.prompt_position(target)
	var position := (character as Node3D).global_position
	if not position.is_finite() or not anchor.is_finite(): return false
	return position.distance_to(anchor) <= distance * scale
