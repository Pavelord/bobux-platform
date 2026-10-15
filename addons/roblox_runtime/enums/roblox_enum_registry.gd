extends RefCounted

## Isolated A3 prototype. Production LuaScriptEngine does not bind this yet.
## Values/order/type strings observed in official Studio 0.742.0.7421053.
## Source: tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.raw.log,
## run 56d7b7d5-beac-4f26-ba3e-d771a14ece51, kind a3_enum_probe.
## RaycastFilterType and aliases: studio-enum-coercion-run01.raw.json,
## run c475020d-1687-4cb5-9b53-2ecbe4d5a2f7, enum_identity/alias observations.
## Ten-domain order/items confirmed in Studio 0.743.0.7431133:
## 2026-10-15-studio-character-enums-run01.raw.json,
## run 664b4f14-6de7-42a1-95b3-2e80065d19ec; 99 canonical items.
## ExistingNumericEnums must remain the default for current production VMs.

const ITEM_SCRIPT = preload("res://addons/roblox_runtime/enums/roblox_enum_item.gd")
const TYPE_SCRIPT = preload("res://addons/roblox_runtime/enums/roblox_enum_type.gd")
const ROOT_SCRIPT = preload("res://addons/roblox_runtime/enums/roblox_enums.gd")
const EXISTING_NUMERIC_ENUMS := "ExistingNumericEnums"
const ROBLOX_PARITY_ENUM_ITEM := "RobloxParity.EnumItem"
const VM_OWNER_META := &"bobux_enum_registry_owner"

const DEFINITIONS := {
	"HumanoidStateType": [
		["FallingDown", 0], ["Ragdoll", 1], ["GettingUp", 2], ["Jumping", 3],
		["Swimming", 4], ["Freefall", 5], ["Flying", 6], ["Landed", 7],
		["Running", 8], ["RunningNoPhysics", 10], ["StrafingNoPhysics", 11],
		["Climbing", 12], ["Seated", 13], ["PlatformStanding", 14],
		["Dead", 15], ["Physics", 16], ["None", 18],
	],
	"HumanoidRigType": [["R6", 0], ["R15", 1]],
	"CameraType": [["Fixed", 0], ["Attach", 1], ["Watch", 2], ["Track", 3],
		["Follow", 4], ["Custom", 5], ["Scriptable", 6], ["Orbital", 7]],
	"CameraMode": [["Classic", 0], ["LockFirstPerson", 1]],
	"CoreGuiType": [["PlayerList", 0], ["Health", 1], ["Backpack", 2], ["Chat", 3],
		["All", 4], ["EmotesMenu", 5], ["SelfView", 6], ["Captures", 7],
		["AvatarSwitcher", 8], ["ExperienceShop", 9]],
	"AnimationPriority": [["Idle", 0], ["Movement", 1], ["Action", 2],
		["Action2", 3], ["Action3", 4], ["Action4", 5], ["Core", 1000]],
	"Material": [["Plastic", 256], ["SmoothPlastic", 272], ["Neon", 288],
		["Wood", 512], ["WoodPlanks", 528], ["Marble", 784], ["Basalt", 788],
		["Slate", 800], ["CrackedLava", 804], ["Concrete", 816], ["Limestone", 820],
		["Granite", 832], ["Pavement", 836], ["Brick", 848], ["Pebble", 864],
		["Cobblestone", 880], ["Rock", 896], ["Sandstone", 912],
		["CorrodedMetal", 1040], ["DiamondPlate", 1056], ["Foil", 1072],
		["Metal", 1088], ["Grass", 1280], ["LeafyGrass", 1284], ["Sand", 1296],
		["Fabric", 1312], ["Snow", 1328], ["Mud", 1344], ["Ground", 1360],
		["Asphalt", 1376], ["Salt", 1392], ["Ice", 1536], ["Glacier", 1552],
		["Glass", 1568], ["ForceField", 1584], ["Air", 1792], ["Water", 2048],
		["Cardboard", 2304], ["Carpet", 2305], ["CeramicTiles", 2306],
		["ClayRoofTiles", 2307], ["RoofShingles", 2308], ["Leather", 2309],
		["Plaster", 2310], ["Rubber", 2311]],
	"SensorMode": [["Floor", 0], ["Ladder", 1], ["ClassicFloor", 2], ["ClassicLadder", 3]],
	"SensorUpdateType": [["OnRead", 0], ["Manual", 1]],
	"RaycastFilterType": [["Exclude", 0], ["Include", 1]],
}
const ALIASES := {"RaycastFilterType": {"Blacklist": "Exclude", "Whitelist": "Include"}}
const SOURCES := {
	"HumanoidStateType": "https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType",
	"HumanoidRigType": "https://create.roblox.com/docs/reference/engine/enums/HumanoidRigType",
	"CameraType": "https://create.roblox.com/docs/reference/engine/enums/CameraType",
	"CameraMode": "https://create.roblox.com/docs/reference/engine/enums/CameraMode",
	"CoreGuiType": "https://create.roblox.com/docs/reference/engine/enums/CoreGuiType",
	"AnimationPriority": "https://create.roblox.com/docs/reference/engine/enums/AnimationPriority",
	"Material": "https://create.roblox.com/docs/reference/engine/enums/Material",
	"SensorMode": "https://create.roblox.com/docs/reference/engine/enums/SensorMode",
	"SensorUpdateType": "https://create.roblox.com/docs/reference/engine/enums/SensorUpdateType",
	"RaycastFilterType": "https://create.roblox.com/docs/reference/engine/enums/RaycastFilterType",
}

var _types: Dictionary = {}
var _root: RefCounted

func _init() -> void:
	for type_name in DEFINITIONS:
		var enum_type = TYPE_SCRIPT.new(str(type_name))
		for definition in DEFINITIONS[type_name]:
			enum_type.add_item(ITEM_SCRIPT.new(enum_type, str(definition[0]), int(definition[1])))
		for alias_name in ALIASES.get(type_name, {}):
			enum_type.add_alias(alias_name, ALIASES[type_name][alias_name])
		_types[type_name] = enum_type
	_root = ROOT_SCRIPT.new(_types)

func enums() -> RefCounted:
	return _root

func attach_to_vm(lua: Object) -> void:
	# VM owns registry until LuaAPI destructor has closed its native state.
	# Registry never owns a VM, and items use weak parent references, so there
	# is no RefCounted cycle. A retained native state retains this owner too.
	# Detached Godot items must carry their registry owner or be scalar/tagged.
	if is_instance_valid(lua): lua.set_meta(VM_OWNER_META, self)

func enum_type(type_name: String) -> Variant:
	return _types.get(type_name)

func item(type_name: String, item_name: String) -> Variant:
	var enum_: Variant = _types.get(type_name)
	return enum_.from_name(item_name) if enum_ != null else null

func item_from_value(type_name: String, value: Variant) -> Variant:
	if not value is int and not value is float: return null
	if not is_finite(float(value)) or float(int(value)) != float(value): return null
	var enum_: Variant = _types.get(type_name)
	return enum_.from_value(int(value)) if enum_ != null else null

func kind(value: Variant) -> String:
	if value is Object and is_instance_valid(value):
		var script_: Variant = value.get_script()
		if script_ == ITEM_SCRIPT: return "EnumItem"
		if script_ == TYPE_SCRIPT: return "Enum"
		if script_ == ROOT_SCRIPT: return "Enums"
	return ""

## Scalar identity kernel, not the class-specific native setter/method cast.
## Parity property setters also accept measured strings/fractions; Humanoid
## methods have different semantics. Implement those at a typed boundary.
func coerce(value: Variant, expected_domain: String, allow_legacy_numeric: bool = false) -> Variant:
	if kind(value) == "EnumItem":
		var expected_type: Variant = _types.get(expected_domain)
		# Do not accept another registry's arbitrary item or a mock table.
		return value.value() if value.enum_type() == expected_type and item(expected_domain, value.name()) == value else null
	if allow_legacy_numeric:
		var canonical: Variant = item_from_value(expected_domain, value)
		return canonical.value() if canonical != null else null
	return null

func to_boundary(value: Variant, expected_domain: String, profile: String) -> Variant:
	if profile not in [EXISTING_NUMERIC_ENUMS, ROBLOX_PARITY_ENUM_ITEM]: return null
	var canonical: Variant = item_from_value(expected_domain, value)
	if canonical == null: return null
	return canonical if profile == ROBLOX_PARITY_ENUM_ITEM else canonical.value()
