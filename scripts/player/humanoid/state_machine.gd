extends RefCounted
class_name HumanoidStateMachine

## IDs are the public Roblox HumanoidStateType enum, not animation pose IDs.
## Source: https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType
const STATE_NAMES := {
	0: "FallingDown", 1: "Ragdoll", 2: "GettingUp", 3: "Jumping",
	4: "Swimming", 5: "Freefall", 6: "Flying", 7: "Landed",
	8: "Running", 10: "RunningNoPhysics", 11: "StrafingNoPhysics",
	12: "Climbing", 13: "Seated", 14: "PlatformStanding", 15: "Dead",
	16: "Physics", 18: "None",
}
const STATES := {
	"FallingDown": 0, "Ragdoll": 1, "GettingUp": 2, "Jumping": 3,
	"Swimming": 4, "Freefall": 5, "Flying": 6, "Landed": 7,
	"Running": 8, "RunningNoPhysics": 10, "StrafingNoPhysics": 11,
	"Climbing": 12, "Seated": 13, "PlatformStanding": 14, "Dead": 15,
	"Physics": 16, "None": 18,
}

var state: int = 8
var landed_minimum_seconds: float = 1.0 / 30.0
var _landed_remaining: float = 0.0


func configure(config: HumanoidConfig) -> void:
	# Fixed-step retention approximates the Studio drop-trace median. The
	# measured range and calibration target live in humanoid_config.tres.
	landed_minimum_seconds = maxf(config.float_value("State.LandedMinimumSeconds"), 0.0)


static func state_name(value: int) -> String:
	return str(STATE_NAMES.get(value, "None"))


static func is_enabled(humanoid: Node, value: int) -> bool:
	return STATE_NAMES.has(value) and value != 18 and (
		not is_instance_valid(humanoid)
		or bool(humanoid.get_meta("bobux_state_enabled_%d" % value, true))
	)


func tick(delta: float) -> void:
	_landed_remaining = maxf(_landed_remaining - maxf(delta, 0.0), 0.0)


func transition(humanoid: Node, next_state: int, landing: bool = false) -> Array[int]:
	if landing and next_state in [8, 10] and is_enabled(humanoid, 7):
		_landed_remaining = landed_minimum_seconds
		next_state = 7
	elif state == 7 and _landed_remaining > 0.0 and next_state in [8, 10]:
		return []
	return _transition(humanoid, next_state)


func force_transition(humanoid: Node, next_state: int) -> Array[int]:
	if not is_enabled(humanoid, next_state):
		return []
	_landed_remaining = landed_minimum_seconds if next_state == 7 else 0.0
	return _transition(humanoid, next_state)


func _transition(humanoid: Node, next_state: int) -> Array[int]:
	if state == next_state or not is_enabled(humanoid, next_state):
		return []
	var previous := state
	state = next_state
	return [previous, state]
