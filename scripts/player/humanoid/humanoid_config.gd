extends Resource
class_name HumanoidConfig

## One registry for every Roblox Humanoid physics value used by this controller.
## Values and their provenance live together in humanoid_config.tres.
@export var values: Dictionary = {}
@export var sources: Dictionary = {}


func value(key: StringName, fallback: Variant = null) -> Variant:
	if values.has(key):
		return values[key]
	return values.get(String(key), fallback)


func float_value(key: StringName) -> float:
	var configured_value: Variant = value(key)
	var configured_type: int = typeof(configured_value)
	if configured_type != TYPE_FLOAT and configured_type != TYPE_INT:
		push_error(
			"HumanoidConfig value '%s' must be numeric (got %s); available keys: %s"
			% [String(key), type_string(configured_type), values.keys()]
		)
		return 0.0
	return configured_value * 1.0


func int_value(key: StringName) -> int:
	var configured_value: Variant = value(key)
	if typeof(configured_value) != TYPE_INT:
		push_error(
			"HumanoidConfig value '%s' must be an integer (got %s); available keys: %s"
			% [String(key), type_string(typeof(configured_value)), values.keys()]
		)
		return 0
	return configured_value


func source(key: StringName) -> String:
	return str(sources.get(String(key), "TODO_MEASURE"))


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	for required_key in [&"PhysicsFrequencyHz", &"WalkSpeed", &"JumpPower", &"Gravity", &"Motion.SafeMargin"]:
		if not values.has(required_key) and not values.has(String(required_key)):
			issues.append("Missing required value: %s" % String(required_key))
	for key in values:
		if not sources.has(key):
			issues.append("Missing provenance for %s" % key)
		elif not ["documented", "measured", "TODO_MEASURE"].has(str(sources[key])):
			issues.append("Invalid provenance for %s: %s" % [key, sources[key]])
	var floor_search := float(value("GroundSensor.SearchDistance", 0.0))
	var ground_offset := float(value("GroundController.GroundOffset", 0.0))
	if ground_offset >= floor_search:
		issues.append("GroundController.GroundOffset must be less than GroundSensor.SearchDistance")
	if not ["OuterBox", "InnerBox"].has(str(value("CollisionType", ""))):
		issues.append("CollisionType must be OuterBox or InnerBox")
	return issues
