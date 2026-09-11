extends RefCounted

const DEFAULT_JUMP_POWER := 53.15 # 7.2 studs at Workspace gravity 196.2.

static func normalize(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(true)
	# Old maps saved this preset for ascent gravity 72. At gravity 196.2 that
	# reduces height from 6.7 to 2.4 studs. Migrate only the complete old preset;
	# authored powers and Lua property assignments retain their literal values.
	if int(settings.get("movement_version", 1)) < 2 and is_equal_approx(float(settings.get("move_speed", 0)), 24.0) and is_equal_approx(float(settings.get("jump_velocity", 0)), 31.0) and is_equal_approx(float(settings.get("sprint_multiplier", 1.25)), 1.25):
		result["jump_velocity"] = DEFAULT_JUMP_POWER
	result["movement_version"] = 2
	return result
