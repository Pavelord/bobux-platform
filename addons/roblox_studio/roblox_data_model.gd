@tool
class_name RobloxDataModel
extends Node

## Live Roblox DataModel for Bobux Studio — NON-DESTRUCTIVE design.
##
## The DataModel is a SEPARATE node tree that mirrors the Roblox service
## hierarchy WITHOUT reparenting the studio's existing world container:
##
##   game (RobloxDataModel, plain Node, sibling of World3D)
##   ├── Players           (Node)
##   ├── Lighting          (Node)
##   ├── ReplicatedFirst   (Node)
##   ├── ReplicatedStorage (Node)
##   ├── ServerScriptService (Node)
##   ├── ServerStorage     (Node)
##   ├── StarterGui        (CanvasLayer — GUI preview)
##   ├── StarterPack       (Node)
##   ├── StarterPlayer     (Node) → StarterPlayerScripts
##   ├── Teams             (Node)
##   ├── SoundService      (Node)
##   └── TextChatService   (Node)
##
## Workspace is NOT a child of the DataModel. Instead the studio's
## `placement_parent` (the real "Blocks" container that holds every Part) is
## registered as a **workspace alias**. The Explorer recurses into that alias
## to display parts, but the node itself never moves — so the camera, physics
## picking, LuaScriptEngine path resolution, save/load and the RBXL importer
## all keep working unchanged.

const SERVICE_GROUP := "roblox_services"
const ROBLOX_CLASS_META := "roblox_class"

## Ordered list of Roblox services shown in the Explorer, matching the order
## Roblox Studio uses (top → bottom). Workspace is intentionally first.
const DEFAULT_SERVICES := [
	"Workspace",
	"Players",
	"Lighting",
	"MaterialService",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Teams",
	"SoundService",
	"TextChatService",
	"RunService",
	"TweenService",
	"Debris",
	"CollectionService",
	"UserInputService",
	"ContextActionService",
	"MarketplaceService",
	"BadgeService",
	"InsertService",
	"PhysicsService",
]

## Services that should exist as 3D nodes (so parts/decals/lights can live in
## world space). Everything else is a plain Node container. Workspace is
## excluded — it is aliased, not created.
const SERVICE_3D := ["Lighting"]

## Services that own GUI trees and render through a CanvasLayer overlay.
const SERVICE_CANVAS_LAYER := ["StarterGui"]

var workspace_alias: Node3D = null
var lighting: Node3D = null
var starter_gui: CanvasLayer = null
var starter_player: Node = null

var _services: Dictionary = {} # service_name -> Node
var _initialized: bool = false
var _authored_ref_counter: int = 0


func _ready() -> void:
	if not _initialized:
		_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	name = "RobloxDataModel"
	add_to_group(SERVICE_GROUP)
	set_meta(ROBLOX_CLASS_META, "DataModel")

	# Build every NON-Workspace service as a real node. Workspace is registered
	# separately via register_workspace_alias() so we never move placement_parent.
	for service_name in DEFAULT_SERVICES:
		if service_name == "Workspace":
			continue
		if _services.has(service_name) and is_instance_valid(_services[service_name]):
			continue
		if has_node(service_name):
			_services[service_name] = get_node(service_name)
			continue
		var node := _create_service_node(service_name)
		add_child(node, true)
		_services[service_name] = node

	lighting = _services.get("Lighting", null)
	starter_gui = _services.get("StarterGui", null)
	starter_player = _services.get("StarterPlayer", null)

	# StarterPlayer owns both script templates in Roblox. They are copied to the
	# local player's PlayerScripts and Character when a play session starts.
	if starter_player:
		for container_name in ["StarterPlayerScripts", "StarterCharacterScripts"]:
			if starter_player.has_node(container_name):
				continue
			var script_container := Node.new()
			script_container.name = container_name
			script_container.set_meta(ROBLOX_CLASS_META, container_name)
			starter_player.add_child(script_container)


func _create_service_node(service_name: String) -> Node:
	var node: Node
	if service_name in SERVICE_CANVAS_LAYER:
		node = CanvasLayer.new()
	elif service_name in SERVICE_3D:
		node = Node3D.new()
	else:
		node = Node.new()
	node.name = service_name
	node.set_meta(ROBLOX_CLASS_META, service_name)
	node.set_meta("is_roblox_service", true)
	node.add_to_group("roblox_service")
	return node


## Register the studio's world container as the Workspace WITHOUT reparenting
## it. The Explorer recurses into this node to display parts. The node itself
## keeps its original parent (World3D), so nothing else in the engine breaks.
func register_workspace_alias(world_container: Node3D) -> void:
	_initialize()
	workspace_alias = world_container
	# Tag the real container so the Explorer shows it as a Workspace row.
	if world_container != null:
		world_container.set_meta(ROBLOX_CLASS_META, "Workspace")
		world_container.set_meta("is_roblox_service", true)
		if not world_container.is_in_group("roblox_service"):
			world_container.add_to_group("roblox_service")
		_services["Workspace"] = world_container


## Return the Workspace node (= the studio placement_parent), or null.
func get_workspace() -> Node3D:
	return workspace_alias


func get_service(service_name: String) -> Node:
	if service_name == "Workspace":
		return workspace_alias
	return _services.get(service_name, null)


func has_service(service_name: String) -> bool:
	if service_name == "Workspace":
		return workspace_alias != null
	return _services.has(service_name)


## Ensure a service node exists (for services added dynamically, e.g. by the
## RBXL importer or Lua `GetService`). Returns the node.
func ensure_service(service_name: String) -> Node:
	_initialize()
	if service_name == "Workspace":
		return workspace_alias
	if _services.has(service_name):
		return _services[service_name]
	var node := _create_service_node(service_name)
	add_child(node, true)
	_services[service_name] = node
	if service_name == "Lighting" and lighting == null:
		lighting = node
	elif service_name == "StarterGui" and starter_gui == null:
		starter_gui = node
	return node


## Roblox-style GetService — returns the service node, creating it if needed.
func get_service_roblox(service_name: String) -> Node:
	return ensure_service(service_name)


func get_service_names() -> Array[String]:
	var names: Array[String] = []
	for service_name in DEFAULT_SERVICES:
		if has_service(service_name):
			names.append(service_name)
	for service_name_variant in _services.keys():
		var service_name := str(service_name_variant)
		if not names.has(service_name):
			names.append(service_name)
	return names


## Create a Roblox-style instance under a parent node. Mirrors the subset of
## `Instance.new` behavior the studio Explorer needs. Returns the created node.
static func create_instance(class_name_: String, name_: String = "") -> Node:
	var node: Node = null
	match class_name_:
		"Part", "TrussPart", "SpawnLocation", "Seat", "VehicleSeat", \
		"WedgePart", "CornerWedgePart", "MeshPart", "UnionOperation", \
		"NegateOperation", "IntersectOperation":
			var mesh_instance := MeshInstance3D.new()
			var primitive := BoxMesh.new()
			primitive.size = Vector3.ONE
			mesh_instance.mesh = primitive
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.64, 0.64, 0.64, 1.0)
			mesh_instance.material_override = material
			node = mesh_instance
			node.set_meta("shape_type", "Box")
			node.add_to_group("studio_parts")
		"Model", "Folder", "Configuration", "Tool", "Accoutrement", "Accessory", "Terrain":
			node = Node3D.new()
		"Humanoid", "Animator", "BodyColors", "Motor6D", "Weld", "WeldConstraint", \
		"StarterPlayerScripts", "StarterCharacterScripts", "PlayerScripts", "Backpack", "PlayerGui":
			node = Node.new()
		"Script", "LocalScript", "ModuleScript":
			node = Node.new()
			node.add_to_group("bobux_scripts")
			node.set_meta("script_type", class_name_)
		"PointLight", "SpotLight", "SurfaceLight":
			node = OmniLight3D.new()
		"Sound":
			node = AudioStreamPlayer3D.new()
		"ParticleEmitter", "Fire", "Smoke", "Sparkles":
			node = GPUParticles3D.new()
		"Attachment":
			node = Node3D.new()
		"Camera":
			node = Camera3D.new()
		"ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup":
			node = Control.new()
			(node as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		"Frame":
			node = Panel.new()
		"TextLabel":
			node = Label.new()
		"TextButton":
			node = Button.new()
		"TextBox":
			node = LineEdit.new()
		"ImageLabel":
			node = TextureRect.new()
		"ImageButton":
			node = TextureButton.new()
		"ScrollingFrame":
			node = ScrollContainer.new()
		"UICorner", "UIStroke", "UIGradient", "UIPadding", "UIScale", \
		"UIListLayout", "UIGridLayout", "UITableLayout", "UIPageLayout", \
		"UIAspectRatioConstraint", "UISizeConstraint", "UITextSizeConstraint":
			node = Node.new()
		"RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction":
			node = Node.new()
		"BoolValue", "IntValue", "NumberValue", "StringValue", \
		"Vector3Value", "ObjectValue", "Color3Value", "CFrameValue", "BrickColorValue":
			node = Node.new()
		_:
			node = Node.new()
	node.set_meta(ROBLOX_CLASS_META, class_name_)
	node.name = name_ if not name_.is_empty() else class_name_
	if class_name_ in ["Tool", "HopperBin"]:
		node.add_to_group("roblox_tools")
		node.set_meta("inventory_source", true)
		node.set_meta("roblox_properties", {
			"Archivable": true,
			"CanBeDropped": true,
			"Enabled": true,
			"ManualActivationOnly": false,
			"RequiresHandle": true,
			"ToolTip": "",
			"TextureId": "",
			"GripPos": [0.0, 0.0, 0.0],
			"GripForward": [0.0, 0.0, -1.0],
			"GripRight": [1.0, 0.0, 0.0],
			"GripUp": [0.0, 1.0, 0.0],
		})
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_PASS
		if not class_name_ in ["ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup"]:
			control.position = Vector2(32, 32)
			control.size = Vector2(240, 120)
		node.set_meta("roblox_properties", {
			"Visible": true,
			"Enabled": true,
			"Position": {"x": {"scale": 0.0, "offset": control.position.x}, "y": {"scale": 0.0, "offset": control.position.y}},
			"Size": {"x": {"scale": 0.0, "offset": control.size.x}, "y": {"scale": 0.0, "offset": control.size.y}},
		})
	return node


## Determine which service an instance class should live under by default
## (used when adding instances via the Explorer context menu).
static func default_service_for_class(class_name_: String) -> String:
	match class_name_:
		"Script", "ModuleScript":
			return "ServerScriptService"
		"LocalScript":
			return "StarterPlayer"
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "TextLabel", \
		"TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame":
			return "StarterGui"
		"Tool", "HopperBin":
			return "StarterPack"
		"Part", "Model", "WedgePart", "MeshPart", "Folder", "TrussPart", \
		"SpawnLocation", "Seat", "VehicleSeat", "CornerWedgePart", \
		"UnionOperation", "NegateOperation", "IntersectOperation":
			return "Workspace"
		_:
			return "ReplicatedStorage"


## Walk the whole DataModel (services + the workspace alias) and return every
## node with the given Roblox class.
func find_all_of_class(class_name_: String) -> Array:
	var result: Array = []
	for service_name in _services.keys():
		var service: Node = _services[service_name]
		if service != null and is_instance_valid(service):
			_collect_by_class(service, class_name_, result)
	if workspace_alias != null and is_instance_valid(workspace_alias):
		_collect_by_class(workspace_alias, class_name_, result)
	return result


## Serialize the editable DataModel into the same manifest contract used by
## RBXL import and the game runtime. This is the single persistence boundary
## for authored Scripts, GUI, Tools, remotes, values and storage hierarchy.
func build_manifest(existing_manifest: Dictionary = {}) -> Dictionary:
	_initialize()
	var manifest := existing_manifest.duplicate(true)
	var services: Array[Dictionary] = []
	var scripts: Array[Dictionary] = []
	var gui: Array[Dictionary] = []
	var tools: Array[Dictionary] = []
	var instances: Array[Dictionary] = []
	var hierarchy_by_key: Dictionary = {}
	var existing_hierarchy: Array = manifest.get("hierarchy", []) if manifest.get("hierarchy", []) is Array else []
	for edge_variant in existing_hierarchy:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var child_ref := str(edge.get("child", "")).strip_edges()
		var parent_ref := str(edge.get("parent", "")).strip_edges()
		if not child_ref.is_empty():
			hierarchy_by_key["%s>%s" % [parent_ref, child_ref]] = {"parent": parent_ref, "child": child_ref}

	var existing_service_refs: Dictionary = {}
	var existing_services: Array = manifest.get("services", []) if manifest.get("services", []) is Array else []
	for service_variant in existing_services:
		if service_variant is Dictionary:
			var service_data: Dictionary = service_variant
			var service_name := str(service_data.get("name", service_data.get("class", ""))).strip_edges()
			var service_ref := str(service_data.get("ref", "")).strip_edges()
			if not service_name.is_empty() and not service_ref.is_empty():
				existing_service_refs[service_name] = service_ref

	for service_name in get_service_names():
		var service := get_service(service_name)
		if service == null or not is_instance_valid(service):
			continue
		var service_ref := str(existing_service_refs.get(service_name, "")).strip_edges()
		if service_ref.is_empty():
			service_ref = _ensure_node_ref(service)
		else:
			service.set_meta("roblox_ref", service_ref)
		services.append({
			"ref": service_ref,
			"class": service_name,
			"name": service_name,
			"parent_ref": "",
			"root_ref": service_ref,
			"root_class": service_name,
			"root_name": service_name,
		})
		_collect_manifest_children(service, service_ref, service_name, service_ref, scripts, gui, tools, instances, hierarchy_by_key)

	manifest["schema"] = "bobux.roblox_manifest.v2"
	manifest["services"] = services
	manifest["scripts"] = scripts
	manifest["gui"] = gui
	manifest["tools"] = tools
	manifest["instances"] = instances
	manifest["hierarchy"] = hierarchy_by_key.values()
	manifest["total_instances"] = services.size() + scripts.size() + gui.size() + tools.size() + instances.size()
	return manifest


func _collect_manifest_children(parent: Node, parent_ref: String, service_name: String, root_ref: String,
		scripts: Array[Dictionary], gui: Array[Dictionary], tools: Array[Dictionary],
		instances: Array[Dictionary], hierarchy_by_key: Dictionary) -> void:
	for child in parent.get_children():
		if _should_skip_serialized_node(child):
			continue
		var roblox_class := str(child.get_meta(ROBLOX_CLASS_META, _infer_roblox_class(child))).strip_edges()
		if roblox_class.is_empty():
			roblox_class = "Instance"
		var child_ref := _ensure_node_ref(child)
		var entry := _serialize_manifest_entry(child, roblox_class, child_ref, parent_ref, service_name, root_ref)
		var is_workspace_part := service_name == "Workspace" and child.is_in_group("studio_parts")
		if not is_workspace_part:
			if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
				scripts.append(entry)
			elif _is_gui_class(roblox_class):
				gui.append(entry)
			elif roblox_class in ["Tool", "HopperBin"]:
				tools.append(entry)
			else:
				instances.append(entry)
		var edge_key := "%s>%s" % [parent_ref, child_ref]
		hierarchy_by_key[edge_key] = {"parent": parent_ref, "child": child_ref}
		_collect_manifest_children(child, child_ref, service_name, root_ref, scripts, gui, tools, instances, hierarchy_by_key)


func _serialize_manifest_entry(node: Node, roblox_class: String, ref: String, parent_ref: String,
		service_name: String, root_ref: String) -> Dictionary:
	var entry := {
		"ref": ref,
		"class": roblox_class,
		"name": str(node.get_meta("block_name", node.name)),
		"parent_ref": parent_ref,
		"parent_class": str(node.get_parent().get_meta(ROBLOX_CLASS_META, _infer_roblox_class(node.get_parent()))) if node.get_parent() != null else "",
		"root_ref": root_ref,
		"root_class": service_name,
		"root_name": service_name,
		"service_name": service_name,
		"properties": _serialize_node_properties(node, roblox_class),
	}
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		var source := str(node.get_meta("code", node.get_meta("lua_source", "")))
		entry["source"] = source
		entry["source_length"] = source.length()
		entry["disabled"] = bool(node.get_meta("disabled", false))
	return entry


func _serialize_node_properties(node: Node, roblox_class: String) -> Dictionary:
	var properties: Dictionary = {}
	if node.get_meta("roblox_properties", {}) is Dictionary:
		properties = (node.get_meta("roblox_properties", {}) as Dictionary).duplicate(true)
	properties["Name"] = str(node.get_meta("block_name", node.name))
	if node is Node3D:
		var node_3d := node as Node3D
		properties["Position"] = [node_3d.position.x, node_3d.position.y, node_3d.position.z]
		properties["Rotation"] = [node_3d.rotation_degrees.x, node_3d.rotation_degrees.y, node_3d.rotation_degrees.z]
		properties["Size"] = [node_3d.scale.x, node_3d.scale.y, node_3d.scale.z]
	if node is Control:
		var control := node as Control
		properties["Visible"] = control.visible
		properties["Position"] = _udim2_from_control_vector(control.position)
		properties["Size"] = _udim2_from_control_vector(control.size)
		properties["AnchorPoint"] = [control.pivot_offset.x, control.pivot_offset.y]
		properties["Rotation"] = control.rotation_degrees
		properties["ZIndex"] = control.z_index
	if node is Label:
		properties["Text"] = (node as Label).text
	elif node is Button:
		properties["Text"] = (node as Button).text
	elif node is LineEdit:
		properties["Text"] = (node as LineEdit).text
	if roblox_class.ends_with("Value"):
		if node.has_meta("Value"):
			properties["Value"] = node.get_meta("Value")
		elif node.has_meta("value"):
			properties["Value"] = node.get_meta("value")
		else:
			properties["Value"] = null
	return properties


func _udim2_from_control_vector(value: Vector2) -> Dictionary:
	return {
		"x": {"scale": 0.0, "offset": value.x},
		"y": {"scale": 0.0, "offset": value.y},
	}


func _ensure_node_ref(node: Node) -> String:
	var ref := str(node.get_meta("roblox_ref", "")).strip_edges()
	if not ref.is_empty():
		return ref
	_authored_ref_counter += 1
	ref = "bobux_%d_%d" % [Time.get_ticks_usec(), _authored_ref_counter]
	node.set_meta("roblox_ref", ref)
	return ref


func _should_skip_serialized_node(node: Node) -> bool:
	if bool(node.get_meta("bobux_runtime_generated", false)):
		return true
	if node.name in ["SelectionBody", "CollisionBody", "SpecialVisuals", "SelectionBody3D"]:
		return true
	return false


func _infer_roblox_class(node: Node) -> String:
	if node == null:
		return "Instance"
	if node.is_in_group("bobux_scripts"):
		return str(node.get_meta("script_type", "Script"))
	if node.is_in_group("studio_parts") or node is MeshInstance3D:
		return str(node.get_meta("roblox_class", "Part"))
	if node is CanvasLayer:
		return "ScreenGui"
	if node is Button:
		return "TextButton"
	if node is Label:
		return "TextLabel"
	if node is LineEdit:
		return "TextBox"
	if node is TextureRect:
		return "ImageLabel"
	if node is TextureButton:
		return "ImageButton"
	if node is ScrollContainer:
		return "ScrollingFrame"
	if node is Control:
		return "Frame"
	if node is Node3D:
		return "Model"
	return "Instance"


func _is_gui_class(roblox_class: String) -> bool:
	return roblox_class in [
		"ScreenGui", "SurfaceGui", "BillboardGui", "CanvasGroup", "Frame",
		"TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton",
		"ScrollingFrame", "ViewportFrame", "VideoFrame", "UICorner", "UIStroke",
		"UIGradient", "UIPadding", "UIScale", "UIListLayout", "UIGridLayout",
		"UITableLayout", "UIPageLayout", "UIAspectRatioConstraint",
		"UISizeConstraint", "UITextSizeConstraint",
	]


func _collect_by_class(node: Node, class_name_: String, out: Array) -> void:
	if str(node.get_meta(ROBLOX_CLASS_META, "")) == class_name_:
		out.append(node)
	for child in node.get_children():
		_collect_by_class(child, class_name_, out)


## Reset the non-Workspace services to a clean state (used by RBXL import /
## New map). The workspace alias is left untouched — clearing parts is the
## studio's responsibility (it owns placement_parent).
func clear_services() -> void:
	_initialize()
	for service_name in _services.keys():
		if service_name == "Workspace":
			continue
		var service: Node = _services[service_name]
		if service == null or not is_instance_valid(service):
			continue
		for child in service.get_children():
			if is_instance_valid(child):
				service.remove_child(child)
				child.free()
	starter_player = _services.get("StarterPlayer", null)
	if starter_player != null and is_instance_valid(starter_player):
		for container_name in ["StarterPlayerScripts", "StarterCharacterScripts"]:
			if starter_player.has_node(container_name):
				continue
			var script_container := Node.new()
			script_container.name = container_name
			script_container.set_meta(ROBLOX_CLASS_META, container_name)
			starter_player.add_child(script_container)
