extends RefCounted

var lua_metatable: Variant = null
var _types: Dictionary

func _init(types: Dictionary) -> void: _types = types.duplicate()
func __index(_lua: Variant, key: Variant) -> Variant:
	if str(key) == "GetEnums":
		var binding: Variant = ClassDB.instantiate("LuaCallableExtra")
		binding.set_info(Callable(self, "_get_enums"), 1, true, false)
		return binding
	if _types.has(str(key)): return _types[str(key)]
	return _error('%s is not a valid member of "Enum"' % str(key))
func _get_enums(tuple: Variant) -> Variant:
	var args: Array = tuple.to_array()
	if args.is_empty(): return _error("missing argument #1 to 'GetEnums' (Enums expected)")
	var receiver: Variant = args[0]
	if not receiver is Object or not is_instance_valid(receiver) or receiver.get_script() != get_script():
		return _error("invalid argument #1 to 'GetEnums' (Enums expected, got %s)" % load("res://addons/roblox_runtime/enums/roblox_enum_type.gd").lua_kind(receiver))
	var names: Array = receiver._types.keys()
	names.sort()
	var values: Array = []
	for name_ in names: values.append(receiver._types[name_])
	return values
func __newindex(_lua: Variant, key: Variant, _value_to_set: Variant) -> Variant:
	return _error("%s is not a valid member of Enums" % str(key))
func __tostring(_lua: Variant = null) -> String: return "Enums"
func __eq(_lua: Variant, other: Variant) -> bool: return self == other
func _error(message: String) -> Variant:
	var error_: Variant = ClassDB.instantiate("LuaError")
	error_.set_message(message)
	return error_
