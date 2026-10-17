extends RefCounted

var lua_metatable: Variant = null
var _enum_ref: WeakRef
var _name: String
var _value: int

func _init(enum_: RefCounted, item_name: String, item_value: int) -> void:
	_enum_ref = weakref(enum_)
	_name = item_name
	_value = item_value

func name() -> String: return _name
func value() -> int: return _value
func enum_type() -> Variant: return _enum_ref.get_ref()

func __index(_lua: Variant, key: Variant) -> Variant:
	match str(key):
		"Name": return _name
		"Value": return _value
		"EnumType": return enum_type()
	return _error('%s is not a valid member of "%s"' % [str(key), __tostring()])

func __newindex(_lua: Variant, key: Variant, _value_to_set: Variant) -> Variant:
	return _error("%s is not a valid member of EnumItem" % str(key))

func __tostring(_lua: Variant = null) -> String:
	var type_: Variant = enum_type()
	return "Enum.%s.%s" % [type_.name() if type_ != null else "<expired>", _name]

func __eq(_lua: Variant, other: Variant) -> bool:
	return self == other

func _error(message: String) -> Variant:
	var error_: Variant = ClassDB.instantiate("LuaError")
	error_.set_message(message)
	return error_
