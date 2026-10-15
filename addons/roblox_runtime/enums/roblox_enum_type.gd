extends RefCounted

var lua_metatable: Variant = null
var _name: String
var _items: Array = []
var _by_name: Dictionary = {}
var _by_value: Dictionary = {}

func _init(type_name: String) -> void: _name = type_name
func name() -> String: return _name
func add_item(item: RefCounted) -> void:
	_items.append(item)
	_by_name[item.name()] = item
	_by_value[item.value()] = item
func add_alias(alias_name: String, canonical_name: String) -> void:
	if _by_name.has(canonical_name): _by_name[alias_name] = _by_name[canonical_name]

func from_name(item_name: String) -> Variant: return _by_name.get(item_name)
func from_value(item_value: int) -> Variant: return _by_value.get(item_value)

func __index(_lua: Variant, key: Variant) -> Variant:
	if str(key) == "GetEnumItems": return _method("_get_enum_items")
	if str(key) == "FromName": return _method("_from_name")
	if str(key) == "FromValue": return _method("_from_value")
	if _by_name.has(str(key)): return _by_name[str(key)]
	return _error('%s is not a valid member of "Enum.%s"' % [str(key), _name])

func _method(method_name: String) -> Variant:
	# Tuple preserves missing versus explicit nil and permits ignored extras.
	# Do not cache this binding: Callable -> self would form an owner cycle.
	var binding: Variant = ClassDB.instantiate("LuaCallableExtra")
	binding.set_info(Callable(self, method_name), 1, true, false)
	return binding

func _receiver(args: Array, method_name: String) -> Variant:
	if args.is_empty(): return _error("missing argument #1 to '%s' (Enum expected)" % method_name)
	var receiver: Variant = args[0]
	if not receiver is Object or not is_instance_valid(receiver) or receiver.get_script() != get_script():
		return _error("invalid argument #1 to '%s' (Enum expected, got %s)" % [method_name, lua_kind(receiver)])
	return receiver

func _get_enum_items(tuple: Variant) -> Variant:
	var args: Array = tuple.to_array()
	var receiver: Variant = _receiver(args, "GetEnumItems")
	if lua_kind(receiver) != "Enum": return receiver
	return receiver._items.duplicate()

func _from_name(tuple: Variant) -> Variant:
	var args: Array = tuple.to_array()
	var receiver: Variant = _receiver(args, "FromName")
	if lua_kind(receiver) != "Enum": return receiver
	if args.size() < 2: return _error("missing argument #2 to 'FromName' (string expected)")
	if not args[1] is String: return _error("invalid argument #2 to 'FromName' (string expected, got %s)" % lua_kind(args[1]))
	return receiver.from_name(args[1])

func _from_value(tuple: Variant) -> Variant:
	var args: Array = tuple.to_array()
	var receiver: Variant = _receiver(args, "FromValue")
	if lua_kind(receiver) != "Enum": return receiver
	if args.size() < 2: return _error("missing argument #2 to 'FromValue' (number expected)")
	var raw: Variant = args[1]
	if not raw is int and not raw is float: return _error("invalid argument #2 to 'FromValue' (number expected, got %s)" % lua_kind(raw))
	# Native probe observes fractional truncation and nil for NaN/Inf.
	# Out-of-int32 wrapping was not measured; no fabricated wrapped enum ID.
	if not is_finite(float(raw)) or float(raw) < -2147483648.0 or float(raw) >= 2147483648.0: return null
	return receiver.from_value(int(raw))

static func lua_kind(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "boolean"
		TYPE_INT, TYPE_FLOAT: return "number"
		TYPE_STRING, TYPE_STRING_NAME: return "string"
		TYPE_ARRAY, TYPE_DICTIONARY: return "table"
	if value is Object and is_instance_valid(value):
		var script_: Variant = value.get_script()
		if script_ == load("res://addons/roblox_runtime/enums/roblox_enum_item.gd"): return "EnumItem"
		if script_ == load("res://addons/roblox_runtime/enums/roblox_enum_type.gd"): return "Enum"
		if script_ == load("res://addons/roblox_runtime/enums/roblox_enums.gd"): return "Enums"
	return "userdata"

func __newindex(_lua: Variant, key: Variant, _value_to_set: Variant) -> Variant:
	return _error("%s is not a valid member of Enum" % str(key))
func __tostring(_lua: Variant = null) -> String: return _name
func __eq(_lua: Variant, other: Variant) -> bool: return self == other

func _error(message: String) -> Variant:
	var error_: Variant = ClassDB.instantiate("LuaError")
	error_.set_message(message)
	return error_
