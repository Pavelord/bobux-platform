@tool
class_name RobloxExplorer
extends RefCounted

## Recursive Explorer builder for Bobux Studio.
##
## Walks the live RobloxDataModel node tree and produces a Tree hierarchy that
## matches Roblox Studio's Explorer panel:
##   - Top-level services (Workspace, Players, Lighting, ...) in fixed order.
##   - Each service's children recursed to full depth.
##   - Per-item metadata stores the node instance_id so selection/edits route
##     back to the real node.
##   - Collapsed/expanded state is preserved across rebuilds (Roblox Studio
##     does this; the previous Bobux explorer lost it every refresh).
##   - Icons are picked from a class-name → icon-key table so the tree reads
##     like Roblox (Part, Script, Folder, …) instead of generic Godot icons.

const ROBLOX_CLASS_META := "roblox_class"
const SERVICE_ORDER := [
	"Workspace", "Players", "Lighting", "MaterialService", "ReplicatedFirst",
	"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui",
	"StarterPack", "StarterPlayer", "Teams", "SoundService", "TextChatService",
]

# Query-only services are available to scripts through DataModel but Roblox
# Studio does not show them as editable Explorer roots.
const API_ONLY_SERVICES := [
	"RunService", "TweenService", "Debris", "CollectionService",
	"UserInputService", "ContextActionService", "MarketplaceService",
	"BadgeService", "InsertService", "PhysicsService",
]

## TreeItem metadata key that records the Roblox class so context menus and the
## Properties panel can switch on it without re-querying the node.
const META_CLASS_KEY := "roblox_explorer_class"
const META_NODE_ID_KEY := "roblox_explorer_node_id"
const META_IS_SERVICE_KEY := "roblox_explorer_is_service"

## Class name → Godot EditorIcons theme name. When the EditorIcons theme is
## unavailable (exported build) we fall back to no icon, keeping text readable.
const CLASS_ICON := {
	"DataModel": "Window",
	"Workspace": "Node3D",
	"Players": "MultiplayerSpawn",
	"Lighting": "DirectionalLight3D",
	"MaterialService": "Material",
	"ReplicatedFirst": "FileSystem",
	"ReplicatedStorage": "Folder",
	"ServerScriptService": "Script",
	"ServerStorage": "Folder",
	"StarterGui": "Control",
	"StarterPack": "Backpack",
	"StarterPlayer": "CharacterBody3D",
	"StarterPlayerScripts": "Script",
	"StarterCharacterScripts": "Script",
	"Player": "CharacterBody3D",
	"PlayerScripts": "Script",
	"PlayerGui": "Control",
	"Backpack": "Backpack",
	"Teams": "ListSelect",
	"SoundService": "AudioStreamPlayer",
	"TextChatService": "ChatBubble",
	"RunService": "Timer",
	"TweenService": "Animation",
	"Debris": "Timer",
	"CollectionService": "Groups",
	"UserInputService": "InputEvent",
	"ContextActionService": "InputEventAction",
	"MarketplaceService": "AssetLib",
	"BadgeService": "StatusSuccess",
	"InsertService": "Add",
	"PhysicsService": "PhysicsMaterial",

	"Part": "MeshInstance3D",
	"TrussPart": "MeshInstance3D",
	"WedgePart": "MeshInstance3D",
	"CornerWedgePart": "MeshInstance3D",
	"MeshPart": "MeshInstance3D",
	"SpawnLocation": "Marker3D",
	"Seat": "Marker3D",
	"VehicleSeat": "Marker3D",
	"UnionOperation": "MeshInstance3D",
	"NegateOperation": "MeshInstance3D",
	"IntersectOperation": "MeshInstance3D",

	"Model": "Node3D",
	"Folder": "Folder",
	"Configuration": "Folder",
	"Tool": "Backpack",
	"Accessory": "BoneAttachment3D",

	"Script": "Script",
	"LocalScript": "Script",
	"ModuleScript": "ScriptCreateDialog",

	"PointLight": "OmniLight3D",
	"SpotLight": "SpotLight3D",
	"SurfaceLight": "DirectionalLight3D",

	"Sound": "AudioStreamPlayer3D",
	"ParticleEmitter": "GPUParticles3D",
	"Fire": "GPUParticles3D",
	"Smoke": "GPUParticles3D",
	"Sparkles": "GPUParticles3D",

	"Camera": "Camera3D",
	"Attachment": "Position3D",

	"ScreenGui": "Control",
	"SurfaceGui": "Control",
	"BillboardGui": "Control",
	"Frame": "Panel",
	"TextLabel": "Label",
	"TextButton": "Button",
	"TextBox": "LineEdit",
	"ImageLabel": "TextureRect",
	"ImageButton": "TextureButton",
	"ScrollingFrame": "ScrollContainer",

	"RemoteEvent": "Signal",
	"BindableEvent": "Signal",
	"RemoteFunction": "FuncRef",
	"BindableFunction": "FuncRef",

	"BoolValue": "bool",
	"IntValue": "int",
	"NumberValue": "float",
	"StringValue": "String",
	"Vector3Value": "Vector3",
	"ObjectValue": "Object",
	"Color3Value": "Color",
	"CFrameValue": "Transform3D",
	"BrickColorValue": "ColorPick",

	"Sky": "Sky",
	"Atmosphere": "WorldEnvironment",
	"BloomEffect": "WorldEnvironment",
	"SunRaysEffect": "WorldEnvironment",
	"Terrain": "GridMap",
	"Humanoid": "CharacterBody3D",
	"Animator": "AnimationPlayer",
	"BodyColors": "ColorPick",
	"HumanoidDescription": "ResourcePreloader",
	"AnimationController": "AnimationPlayer",
	"Motor6D": "BoneAttachment3D",
	"WeldConstraint": "BoneAttachment3D",
	"Weld": "BoneAttachment3D",
	"HingeConstraint": "HingeJoint3D",
	"BallSocketConstraint": "ConeTwistJoint3D",
	"SpringConstraint": "SpringJoint3D",

	"SelectionBox": "MeshInstance3D",
	"Decal": "Decal",
	"Texture": "TextureRect",
	"SpecialMesh": "MeshInstance3D",
	"BlockMesh": "MeshInstance3D",
	"CylinderMesh": "MeshInstance3D",
}


var _collapsed: Dictionary = {} # node_path (String) -> bool
var _expanded_once: Dictionary = {} # node_path (String) -> bool (seen at least once)
var _filter_text: String = ""
var _runtime_icon_cache: Dictionary = {}
var show_runtime: bool = false


func set_filter_text(text: String) -> void:
	_filter_text = text.strip_edges().to_lower()


## Build the entire Explorer tree from `data_model` into `tree`.
## Returns the hidden root TreeItem.
func rebuild(tree: Tree, data_model: Node) -> TreeItem:
	if tree == null or data_model == null:
		return null
	_record_expanded_state(tree)
	tree.clear()
	tree.columns = 2
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 78)
	tree.hide_root = true
	var hidden_root := tree.create_item()

	# Services in fixed Roblox order.
	for service_name in SERVICE_ORDER:
		var service: Node = null
		if data_model.has_method("get_service"):
			var resolved_service: Variant = data_model.call("get_service", service_name)
			if resolved_service is Node:
				service = resolved_service as Node
		else:
			service = data_model.get_node_or_null(service_name)
		if service == null:
			continue
		if not _subtree_matches_filter(service):
			continue
		var item := _create_item(hidden_root, service, service_name, true)
		_recurse(item, service, data_model.get_path_to(service))
	# Any extra services not in the canonical list, in declaration order.
	for child in data_model.get_children():
		if child.name in SERVICE_ORDER:
			continue
		if child.name in API_ONLY_SERVICES:
			continue
		if not bool(child.get_meta("is_roblox_service", false)):
			continue
		if not _subtree_matches_filter(child):
			continue
		var item := _create_item(hidden_root, child, str(child.name), true)
		_recurse(item, child, data_model.get_path_to(child))
	return hidden_root


func _recurse(parent_item: TreeItem, parent_node: Node, parent_path: NodePath) -> void:
	for child in parent_node.get_children():
		if not show_runtime and bool(child.get_meta("bobux_runtime_generated", false)):
			continue
		if bool(child.get_meta("bobux_runtime_generated", false)) and not child.has_meta(ROBLOX_CLASS_META):
			continue
		if bool(child.get_meta("bobux_internal_editor_visual", false)):
			continue
		# Skip internal helper bodies (collision/selection) — they are owned by
		# the part, not part of the Roblox hierarchy.
		var cname := str(child.name)
		if cname in ["SelectionBody", "CollisionBody", "SpecialVisuals", "SelectionBody3D"]:
			continue
		var roblox_class := str(child.get_meta(ROBLOX_CLASS_META, _infer_class(child)))
		var display := _display_name(child, roblox_class)
		if not _node_or_descendants_match_filter(child, roblox_class, display):
			continue
		var item := _create_item(parent_item, child, display, false, roblox_class)
		var child_path := parent_node.get_path_to(child)
		_recurse(item, child, child_path)


func _create_item(parent_item: TreeItem, node: Node, display: String, is_service: bool, roblox_class: String = "") -> TreeItem:
	var item: TreeItem = parent_item.create_child()
	item.set_text(0, display)
	item.set_metadata(0, node.get_instance_id())
	item.set_meta(META_NODE_ID_KEY, node.get_instance_id())
	if roblox_class.is_empty():
		roblox_class = str(node.get_meta(ROBLOX_CLASS_META, _infer_class(node)))
	item.set_meta(META_CLASS_KEY, roblox_class)
	item.set_text(1, roblox_class if not is_service else "")
	item.set_custom_color(1, Color("#747B87"))
	item.set_selectable(1, false)
	item.set_meta(META_IS_SERVICE_KEY, is_service)
	var tooltip := "%s (%s)\n%s" % [display, roblox_class, str(node.get_path())]
	if roblox_class in ["Script", "LocalScript", "ModuleScript"]:
		tooltip += "\n" + {"Script": "Серверный код. Запуск через Play.", "LocalScript": "Код игрока. Запускается в PlayerGui, Backpack, PlayerScripts или Character.", "ModuleScript": "Модуль. Запускается через require()."}[roblox_class]
	item.set_tooltip_text(0, tooltip)
	_apply_icon(item, roblox_class)
	item.set_selectable(0, true)
	item.set_editable(0, false) # rename handled via dialog (F2), not inline edit

	# Preserve expansion state across rebuilds.
	var node_path := _stable_node_key(node)
	if _collapsed.has(node_path):
		item.collapsed = bool(_collapsed[node_path])
	elif not _expanded_once.has(node_path):
		# First time we see this node: collapse non-Workspace services by
		# default (matches Roblox Studio's initial Explorer state).
		item.collapsed = is_service and roblox_class != "Workspace"
	if not _filter_text.is_empty():
		item.collapsed = false
	_expanded_once[node_path] = true
	return item


func _node_or_descendants_match_filter(node: Node, roblox_class: String, display: String) -> bool:
	if _filter_text.is_empty():
		return true
	if _matches_filter(display, roblox_class):
		return true
	for child in node.get_children():
		if bool(child.get_meta("bobux_internal_editor_visual", false)):
			continue
		var cname := str(child.name)
		if cname in ["SelectionBody", "CollisionBody", "SpecialVisuals", "SelectionBody3D"]:
			continue
		if _subtree_matches_filter(child):
			return true
	return false


func _subtree_matches_filter(node: Node) -> bool:
	if _filter_text.is_empty():
		return true
	var roblox_class := str(node.get_meta(ROBLOX_CLASS_META, _infer_class(node)))
	var display := _display_name(node, roblox_class)
	if _matches_filter(display, roblox_class):
		return true
	for child in node.get_children():
		if bool(child.get_meta("bobux_internal_editor_visual", false)):
			continue
		var cname := str(child.name)
		if cname in ["SelectionBody", "CollisionBody", "SpecialVisuals", "SelectionBody3D"]:
			continue
		if _subtree_matches_filter(child):
			return true
	return false


func _matches_filter(display: String, roblox_class: String) -> bool:
	if _filter_text.is_empty():
		return true
	var haystack := ("%s %s" % [display, roblox_class]).to_lower()
	return haystack.find(_filter_text) >= 0


func _display_name(node: Node, roblox_class: String) -> String:
	var name_: String = str(node.get_meta("block_name", node.name))
	if name_.is_empty():
		name_ = str(node.name)
	if name_.is_empty():
		name_ = roblox_class
	return name_


static func is_service_item_class(roblox_class: String) -> bool:
	return roblox_class in SERVICE_ORDER or roblox_class in API_ONLY_SERVICES or roblox_class == "DataModel"


func _infer_class(node: Node) -> String:
	# Fallback heuristics when no roblox_class meta is set.
	if node.is_in_group("studio_parts"):
		return "Part"
	if node.is_in_group("bobux_scripts"):
		return str(node.get_meta("script_type", "Script"))
	if node is MeshInstance3D:
		return "Part"
	if node is Camera3D:
		return "Camera"
	if node is OmniLight3D or node is SpotLight3D or node is DirectionalLight3D:
		return "Light"
	if node is AudioStreamPlayer3D:
		return "Sound"
	if node is GPUParticles3D:
		return "ParticleEmitter"
	if node is CanvasLayer or node is Control:
		return "GuiObject"
	if node is Node3D:
		return "Folder"
	return "Instance"


func _apply_icon(item: TreeItem, roblox_class: String) -> void:
	var icon_key: String = CLASS_ICON.get(roblox_class, "")
	# EditorIcons only exist inside the Godot editor — at runtime we leave the
	# exported build gets generated 16x16 class chips so the Explorer still
	# reads like Roblox Studio instead of a plain text tree.
	if not icon_key.is_empty() and (Engine.is_editor_hint() or has_editor_theme()):
		var tex: Texture2D = _get_editor_icon(icon_key)
		if tex != null:
			item.set_icon(0, tex)
			return
	var runtime_tex := _get_runtime_icon(roblox_class)
	if runtime_tex != null:
		item.set_icon(0, runtime_tex)


func has_editor_theme() -> bool:
	return Engine.is_editor_hint()


func _get_editor_icon(icon_key: String) -> Texture2D:
	# In an exported build there is no editor theme; this guard keeps the call
	# safe. We try the singleton first, then return null.
	var editor_interface := Engine.get_singleton("EditorInterface") if Engine.has_singleton("EditorInterface") else null
	if editor_interface == null:
		return null
	var gui: Control = editor_interface.get_editor_main_control() if editor_interface.has_method("get_editor_main_control") else null
	if gui == null:
		return null
	return gui.get_theme_icon(icon_key, "EditorIcons")


func _get_runtime_icon(roblox_class: String) -> Texture2D:
	if _runtime_icon_cache.has(roblox_class):
		return _runtime_icon_cache[roblox_class]
	var color := _runtime_icon_color(roblox_class)
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border := color.darkened(0.32)
	if roblox_class in ["Model", "Folder", "Configuration", "ReplicatedStorage", "ServerStorage", "StarterPack", "Backpack"]:
		_fill_icon_rect(image, Rect2i(2, 5, 12, 9), color)
		_fill_icon_rect(image, Rect2i(3, 3, 6, 3), color.lightened(0.08))
		_draw_icon_rect(image, Rect2i(2, 5, 12, 9), border)
		_draw_icon_line(image, Vector2i(3, 5), Vector2i(8, 5), border)
	elif roblox_class in ["Script", "LocalScript", "ModuleScript", "StarterPlayerScripts", "StarterCharacterScripts", "PlayerScripts"]:
		_fill_icon_rect(image, Rect2i(3, 1, 10, 14), color.lightened(0.22))
		_draw_icon_rect(image, Rect2i(3, 1, 10, 14), border)
		_fill_icon_rect(image, Rect2i(9, 1, 4, 4), Color.WHITE)
		for y in [6, 9, 12]:
			_draw_icon_line(image, Vector2i(5, y), Vector2i(11, y), border)
	elif roblox_class in ["Part", "TrussPart", "WedgePart", "CornerWedgePart", "MeshPart", "UnionOperation", "NegateOperation", "IntersectOperation"]:
		_fill_icon_rect(image, Rect2i(3, 4, 9, 9), color)
		_draw_icon_rect(image, Rect2i(3, 4, 9, 9), border)
		_draw_icon_line(image, Vector2i(3, 4), Vector2i(7, 1), border)
		_draw_icon_line(image, Vector2i(12, 4), Vector2i(7, 1), border)
		_draw_icon_line(image, Vector2i(12, 13), Vector2i(14, 10), border)
		_draw_icon_line(image, Vector2i(14, 10), Vector2i(14, 3), border)
		_draw_icon_line(image, Vector2i(14, 3), Vector2i(12, 4), border)
	elif roblox_class in ["PointLight", "SpotLight", "SurfaceLight", "Lighting"]:
		_fill_icon_rect(image, Rect2i(5, 4, 6, 7), color)
		_draw_icon_rect(image, Rect2i(5, 4, 6, 7), border)
		_draw_icon_line(image, Vector2i(6, 13), Vector2i(10, 13), border)
		for point in [Vector2i(8, 1), Vector2i(2, 7), Vector2i(14, 7)]:
			image.set_pixelv(point, color)
	elif roblox_class in ["RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction"]:
		_draw_icon_line(image, Vector2i(2, 8), Vector2i(13, 8), color)
		_draw_icon_line(image, Vector2i(9, 4), Vector2i(13, 8), color)
		_draw_icon_line(image, Vector2i(9, 12), Vector2i(13, 8), color)
		_fill_icon_rect(image, Rect2i(2, 6, 3, 5), color.lightened(0.12))
	elif roblox_class in ["SoundService", "Sound"]:
		_fill_icon_rect(image, Rect2i(3, 7, 4, 5), color)
		_draw_icon_line(image, Vector2i(7, 7), Vector2i(11, 4), color)
		_draw_icon_line(image, Vector2i(11, 4), Vector2i(11, 13), color)
		_draw_icon_line(image, Vector2i(11, 13), Vector2i(7, 11), color)
	else:
		_fill_icon_rect(image, Rect2i(4, 4, 8, 8), color)
		_draw_icon_rect(image, Rect2i(4, 4, 8, 8), border)
	var tex := ImageTexture.create_from_image(image)
	_runtime_icon_cache[roblox_class] = tex
	return tex

func _fill_icon_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
				image.set_pixel(x, y, color)

func _draw_icon_rect(image: Image, rect: Rect2i, color: Color) -> void:
	_draw_icon_line(image, rect.position, Vector2i(rect.end.x - 1, rect.position.y), color)
	_draw_icon_line(image, Vector2i(rect.position.x, rect.end.y - 1), Vector2i(rect.end.x - 1, rect.end.y - 1), color)
	_draw_icon_line(image, rect.position, Vector2i(rect.position.x, rect.end.y - 1), color)
	_draw_icon_line(image, Vector2i(rect.end.x - 1, rect.position.y), Vector2i(rect.end.x - 1, rect.end.y - 1), color)

func _draw_icon_line(image: Image, from: Vector2i, to: Vector2i, color: Color) -> void:
	var delta := to - from
	var steps := maxi(absi(delta.x), absi(delta.y))
	if steps <= 0:
		image.set_pixelv(from, color)
		return
	for step in range(steps + 1):
		var point := Vector2(from).lerp(Vector2(to), float(step) / float(steps)).round()
		if point.x >= 0 and point.x < image.get_width() and point.y >= 0 and point.y < image.get_height():
			image.set_pixelv(Vector2i(point), color)


func _runtime_icon_color(roblox_class: String) -> Color:
	if roblox_class in ["Workspace", "Camera"]:
		return Color("#4D8DFF")
	if roblox_class in ["Model", "Folder", "ReplicatedStorage", "ServerStorage", "StarterPack"]:
		return Color("#5CB85C")
	if roblox_class in ["Script", "ModuleScript"]:
		return Color("#D9A441")
	if roblox_class == "LocalScript":
		return Color("#3A7BD5")
	if roblox_class in ["RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction"]:
		return Color("#F27C38")
	if roblox_class in ["SpawnLocation", "StarterPlayer", "Player", "Humanoid"]:
		return Color("#48A868")
	if roblox_class in ["StarterPlayerScripts", "StarterCharacterScripts", "PlayerScripts"]:
		return Color("#3A7BD5")
	if roblox_class in ["Backpack", "Tool"]:
		return Color("#C58A2A")
	if roblox_class in ["PointLight", "SpotLight", "SurfaceLight", "Lighting"]:
		return Color("#F4D35E")
	if roblox_class in ["SoundService", "Sound"]:
		return Color("#3AAED8")
	if roblox_class == "Teams":
		return Color("#B05BD3")
	if roblox_class in ["ScreenGui", "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "TextBox"]:
		return Color("#9C6ADE")
	if roblox_class in ["ServerScriptService", "TextChatService"]:
		return Color("#777777")
	return Color("#A7A7A7")


## Remember which TreeItems were collapsed so we can restore them after a
## rebuild. Keyed by node path (stable across rebuilds, unlike TreeItem refs).
func _record_expanded_state(tree: Tree) -> void:
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	_walk_record(root, tree)


func _walk_record(item: TreeItem, tree: Tree) -> void:
	var node_id = item.get_meta(META_NODE_ID_KEY, -1)
	if node_id != null and int(node_id) > 0:
		var node := instance_from_id(int(node_id))
		if node != null and is_instance_valid(node):
			var node_path := _stable_node_key(node)
			_collapsed[node_path] = item.collapsed
	var child: TreeItem = item.get_first_child()
	while child != null:
		_walk_record(child, tree)
		child = child.get_next()


func _stable_node_key(node: Node) -> String:
	if node == null:
		return ""
	if node.is_inside_tree():
		return str(node.get_path())
	return "instance:%d" % node.get_instance_id()


## Find the TreeItem whose metadata node_id matches the given instance id.
func find_item_for_node(tree: Tree, node: Node) -> TreeItem:
	if tree == null or node == null:
		return null
	var target_id := node.get_instance_id()
	var root: TreeItem = tree.get_root()
	if root == null:
		return null
	return _find_recursive(root, target_id)


func _find_recursive(item: TreeItem, target_id: int) -> TreeItem:
	var id = item.get_meta(META_NODE_ID_KEY, -1)
	if id != null and int(id) == target_id:
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var found := _find_recursive(child, target_id)
		if found != null:
			return found
		child = child.get_next()
	return null


## Mark the rows for the given selected nodes in the tree (prefix-free,
## selection stays handled by the Tree's own selection; this just keeps the
## scroll position + highlights parents).
func sync_selection(tree: Tree, selected_nodes: Array) -> void:
	if tree == null:
		return
	tree.deselect_all()
	var ids: Dictionary = {}
	for node in selected_nodes:
		if node != null and is_instance_valid(node):
			ids[node.get_instance_id()] = true
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	_sync_recursive(root, ids)


func _sync_recursive(item: TreeItem, ids: Dictionary) -> void:
	var id = item.get_meta(META_NODE_ID_KEY, -1)
	if id != null and int(id) > 0 and ids.has(int(id)):
		item.select(0)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_sync_recursive(child, ids)
		child = child.get_next()
