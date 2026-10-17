extends RefCounted

## Opt-in Humanoid boundary; the motor and shared wrappers keep scalar IDs.
## Native coercion reference: c475020d-1687-4cb5-9b53-2ecbe4d5a2f7.
## Unmeasured receivers, bool casts and opaque strings are explicitly partial.
const REGISTRY = preload("res://addons/roblox_runtime/enums/roblox_enum_registry.gd")
const OWNER_META := &"bobux_enum_boundary_owner"
var registry: RefCounted
var _humanoid_classifier: Callable
var _transport_classifier: Callable
var _connections: Array[WeakRef] = []
var _connection_registrations := 0

func _init(registry_: RefCounted, classifier: Callable, transport_classifier: Callable) -> void:
	registry = registry_
	_humanoid_classifier = classifier
	_transport_classifier = transport_classifier

func kind(value: Variant) -> String:
	return registry.kind(value)

func is_humanoid(value: Variant) -> bool:
	return _humanoid_classifier.call(value)

func is_remote(value: Variant) -> bool:
	return _transport_classifier.call(value)

func track_connection(connection: Variant) -> Variant:
	if connection is Object and is_instance_valid(connection):
		_connection_registrations += 1
		if _connection_registrations % 64 == 0:
			var live: Array[WeakRef] = []
			for reference in _connections:
				var current: Variant = reference.get_ref()
				if current != null and bool(current.Connected): live.append(reference)
			_connections = live
		_connections.append(weakref(connection))
	return connection

func disconnect_connections() -> void:
	# Release Lua callables before the LuaAPI enters the teardown quarantine.
	for reference in _connections:
		var connection: Variant = reference.get_ref()
		if is_instance_valid(connection): connection.call("Disconnect")
	_connections.clear()

func state_item(value: Variant) -> Variant:
	var item: Variant = registry.to_boundary(value, "HumanoidStateType", REGISTRY.ROBLOX_PARITY_ENUM_ITEM)
	return item if item != null else _error("RobloxParity.EnumItem: backend returned an unknown HumanoidStateType")

func call_humanoid(method: String, tuple: Variant) -> Variant:
	var args: Array = tuple.to_array()
	if args.is_empty() or not is_humanoid(args[0]):
		return _error("RobloxParity.EnumItem: Humanoid receiver required (receiver coercion remains partial)")
	var receiver: Object = args[0]
	if method == "GetState": return state_item(receiver.call("GetState"))
	# Native checks argument 2 before argument 1 for SetStateEnabled.
	var enabled: Variant = null
	if method == "SetStateEnabled":
		if args.size() < 3 or args[2] == null: return _error("Argument 2 missing or nil")
		enabled = _enabled_argument(args[2])
		if enabled is Object: return enabled
	if args.size() < 2 or args[1] == null:
		if method == "ChangeState": return _empty_tuple()
		return _error("Argument 1 missing or nil")
	var state: Variant = _state_argument(args[1])
	if state is Object: return state
	match method:
		"ChangeState": receiver.call("ChangeState", state)
		"SetStateEnabled": receiver.call("SetStateEnabled", state, enabled)
		"GetStateEnabled": return receiver.call("GetStateEnabled", state)
		_: return _error("RobloxParity.EnumItem: unknown Humanoid method")
	return _empty_tuple()

func _state_argument(value: Variant) -> Variant:
	if kind(value) == "EnumItem":
		var scalar: Variant = registry.coerce(value, "HumanoidStateType")
		if scalar != null: return scalar
		var domain: Variant = value.enum_type()
		return _error("Unable to cast %s to HumanoidStateType" % (domain.name() if domain != null else "EnumItem"))
	if value is int or value is float:
		# Only measured canonical range and positive fractional truncation.
		if is_finite(float(value)) and float(value) >= 0.0 and float(value) < 19.0:
			var item: Variant = registry.item_from_value("HumanoidStateType", int(value))
			if item != null: return item.value()
		return _error("Unable to cast double to HumanoidStateType")
	if value is String:
		var item: Variant = registry.item("HumanoidStateType", value)
		if item != null: return item.value()
		# Native treats opaque strings unlike property setters; do not int().
		return _error("RobloxParity.EnumItem: noncanonical Humanoid state strings are not implemented")
	if value is bool: return _error("Unable to cast bool to HumanoidStateType")
	if value is Array or value is Dictionary: return _error("Unable to cast Array to HumanoidStateType")
	return _error("RobloxParity.EnumItem: Humanoid state input type is not implemented")

func _enabled_argument(value: Variant) -> Variant:
	if value is bool: return value
	if value is String and value == "false": return false
	if (value is int or value is float) and value == 0: return false
	if value is Array or value is Dictionary: return _error("Unable to cast Array to bool")
	return _error("RobloxParity.EnumItem: this enabled argument coercion is not implemented")

func _empty_tuple() -> Variant:
	var tuple: Variant = ClassDB.instantiate("LuaTuple")
	return tuple

func _error(message: String) -> Variant:
	var error_: Variant = ClassDB.instantiate("LuaError")
	error_.set_message(message)
	return error_

static func type_setup() -> String:
	return """
    local enum_kind = __bobux_enum_kind
    if enum_kind then
        local humanoid, invoke, state_item, remote = __bobux_enum_humanoid, __bobux_enum_call, __bobux_enum_state, __bobux_enum_remote
        local meta = getmeta(__bobux_enum_sample)
        local index = meta.__index
        local domains = setmetatable({}, {__mode='k'})
        local methods = {GetState=true, ChangeState=true, GetStateEnabled=true, SetStateEnabled=true}
        local enum_methods = {GetEnumItems=true, FromName=true, FromValue=true, GetEnums=true}
        local signals = {Connect='__bobux_connect', connect='__bobux_connect', Once='__bobux_once', Wait='__bobux_signal_wait', wait='__bobux_signal_wait'}
        local transports = {FireServer=true, FireClient=true, FireAllClients=true, InvokeServer=true, InvokeClient=true, DispatchPacked=true}
        local function value_kind(value)
            -- Native getVariant recursively converts tables before GDScript
            -- gets control. Classify userdata only, including error operands.
            if type(value)~='userdata' then return '' end
            return enum_kind(value)
        end
        local function operand_type(value)
            local kind=value_kind(value)
            return kind~='' and kind or type(value)
        end
        local function enum_method_call(member, key, ...)
            local count=select('#',...)
            local receiver,argument=...
            local expected=key=='GetEnums' and 'Enums' or 'Enum'
            if count==0 then
                error("missing argument #1 to '"..key.."' ("..expected.." expected)",0)
            end
            if value_kind(receiver)~=expected then
                error("invalid argument #1 to '"..key.."' ("..expected.." expected, got "..operand_type(receiver)..")",0)
            end
            if key=='GetEnums' or key=='GetEnumItems' then return member(receiver) end
            local argument_type=key=='FromName' and 'string' or 'number'
            if count<2 then
                error("missing argument #2 to '"..key.."' ("..argument_type.." expected)",0)
            end
            if type(argument)~=argument_type then
                error("invalid argument #2 to '"..key.."' ("..argument_type.." expected, got "..operand_type(argument)..")",0)
            end
            -- Native ignores extras. In particular, do not convert cycles in
            -- ignored args, wrong receivers, or invalid table arguments.
            return member(receiver,argument)
        end
        local function contains_enum(value, visited)
            -- Do not send Lua tables to a native classifier: getVariant walks
            -- tables and a cyclic payload would recurse before this guard.
            if value_kind(value) == 'EnumItem' then return true end
            if type(value) ~= 'table' or visited[value] then return false end
            visited[value] = true
            for k, v in pairs(value) do
                if contains_enum(k, visited) or contains_enum(v, visited) then return true end
            end
            return false
        end
        meta.__index = function(value, key)
            local kind = value_kind(value)
            if kind ~= '' then
                if type(key)~='string' then
                    error('RobloxParity.EnumItem: nonstring enum members are not implemented',0)
                end
                local member = index(value, key)
                if (kind == 'Enum' or kind == 'Enums') and enum_methods[key] then
                    return function(...) return enum_method_call(member,key,...) end
                end
                return member
            end
            if methods[key] and humanoid(value) then
                return function(...)
                    local count=select('#',...)
                    local receiver,state,enabled=...
                    if type(receiver)~='userdata' then
                        error('RobloxParity.EnumItem: Humanoid receiver required (receiver coercion remains partial)',0)
                    end
                    if key=='GetState' then return invoke(key,receiver) end
                    if key=='SetStateEnabled' then
                        if type(enabled)=='table' then error('Unable to cast Array to bool',0) end
                        if count<3 or enabled==nil then return invoke(key,receiver) end
                        if type(state)=='table' then error('Unable to cast Array to HumanoidStateType',0) end
                        return invoke(key,receiver,state,enabled)
                    end
                    if type(state)=='table' then error('Unable to cast Array to HumanoidStateType',0) end
                    if count<2 then return invoke(key,receiver) end
                    return invoke(key,receiver,state)
                end
            end
            local member = index(value, key)
            if (key == 'StateChanged' or key == 'StateEnabledChanged') and humanoid(value) then
                domains[member] = key == 'StateChanged' and {true,true} or {true,false}
            elseif signals[key] and domains[value] then
                return function(...) return _G[signals[key]](...) end
            elseif transports[key] and remote(value) then
                -- Until tagged codec + negotiation exist, fail before Object
                -- payloads reach the old serializer and silently become nil.
                return function(...)
                    for i=1,select('#',...) do
                        if contains_enum(select(i,...), {}) then
                            error('RobloxParity.EnumItem: remote enum transport is not implemented', 0)
                        end
                    end
                    return member(...)
                end
            end
            return member
        end
        local newindex, call = meta.__newindex, meta.__call
        meta.__newindex = function(value,key,replacement)
            if value_kind(value)~='' then
                if type(key)~='string' then
                    error('RobloxParity.EnumItem: nonstring enum members are not implemented',0)
                end
                -- All enum writes are readonly; kernel ignores the value.
                return newindex(value,key,nil)
            end
            return newindex(value,key,replacement)
        end
        meta.__call = function(value,...)
            if value_kind(value)~='' then
                error('RobloxParity.EnumItem: calling enum values is not implemented',0)
            end
            return call(value,...)
        end
        __bobux_enum_raw_member = function(value, key) return index(value, key) end
        __bobux_enum_signal_args = function(signal, packed)
            local schema = domains[signal]
            if schema then
                for i=1,math.min(#schema,packed.n) do
                    if schema[i] then packed[i] = state_item(packed[i]) end
                end
            end
            return packed
        end
        for key, operation in pairs({__add='add',__sub='sub',__mul='mul',__div='div'}) do
            local previous = meta[key]
            meta[key] = function(a,b)
                if value_kind(a)=='EnumItem' or value_kind(b)=='EnumItem' then
                    error('attempt to perform arithmetic ('..operation..') on '..operand_type(a)..' and '..operand_type(b),0)
                end
                return previous(a,b)
            end
        end
        for key, operation in pairs({__lt='<',__le='<='}) do
            local previous = meta[key]
            meta[key] = function(a,b)
                if value_kind(a)=='EnumItem' or value_kind(b)=='EnumItem' then
                    error('attempt to compare '..operand_type(a)..' '..operation..' '..operand_type(b),0)
                end
                return previous(a,b)
            end
        end
        local unm, concat = meta.__unm, meta.__concat
        meta.__unm = function(value)
            if value_kind(value)=='EnumItem' then error('attempt to perform arithmetic (unm) on EnumItem',0) end
            return unm(value)
        end
        meta.__concat = function(a,b)
            if value_kind(a)=='EnumItem' or value_kind(b)=='EnumItem' then
                error('attempt to concatenate '..operand_type(a)..' with '..operand_type(b),0)
            end
            return concat(a,b)
        end
        for key,operation in pairs({__mod='%',__pow='^',__idiv='//'}) do
            local previous=meta[key]
            meta[key]=function(a,b)
                if value_kind(a)=='EnumItem' or value_kind(b)=='EnumItem' then
                    error('RobloxParity.EnumItem: operator '..operation..' is not implemented',0)
                end
                return previous(a,b)
            end
        end
        __bobux_enum_kind, __bobux_enum_humanoid, __bobux_enum_call, __bobux_enum_state, __bobux_enum_sample, __bobux_enum_remote = nil,nil,nil,nil,nil,nil
    end
"""
