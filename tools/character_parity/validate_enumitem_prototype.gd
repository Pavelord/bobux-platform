extends SceneTree

## Fast independent VM test. Does not change production enum bindings.
## Covers the value/boundary kernel; no claim of production Humanoid parity.
const REGISTRY = preload("res://addons/roblox_runtime/enums/roblox_enum_registry.gd")
const NATIVE_REFERENCE := "res://tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.raw.log"
const NATIVE_REFERENCE_SHA256 := "36226a4f7dde505e224e5fbccefb26c8584ffd4ef752a02f9d5e9a771243237b"
const NATIVE_RUN_ID := "56d7b7d5-beac-4f26-ba3e-d771a14ece51"
const COERCION_REFERENCE := "res://tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-coercion-run01.raw.json"
const COERCION_SHA256 := "bf6f00d2dd18a509353347852a76aec14ae5778e81e23eb2773923961e154e19"
const COERCION_RUN_ID := "c475020d-1687-4cb5-9b53-2ecbe4d5a2f7"
const EXTRA_REFERENCE := "res://tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-extra-run01.raw.json"
const EXTRA_SHA256 := "bf0cfd177f200ded653b4423d5acdbd99e346aa24cd582599c9bc4f9c1f56306"
const EXTRA_RUN_ID := "06e5b50d-dbad-4187-bf85-12d34a204bc8"
var checks: Array[Dictionary] = []

class PropertyFixture extends RefCounted:
	var lua_metatable: Variant = null
	var registry: Variant
	var profile: String
	var backing: Dictionary
	const DOMAINS := {"State": "HumanoidStateType", "CameraType": "CameraType", "Material": "Material", "Priority": "AnimationPriority"}
	func _init(registry_: RefCounted, profile_: String, values_: Dictionary) -> void:
		registry = registry_
		profile = profile_
		backing = values_
	func __index(_lua: Variant, key: Variant) -> Variant:
		if DOMAINS.has(str(key)):
			return registry.to_boundary(backing[str(key)], DOMAINS[str(key)], profile)
		return null
	func __newindex(_lua: Variant, key: Variant, value: Variant) -> Variant:
		if not DOMAINS.has(str(key)): return _error("Unknown fixture property")
		var scalar: Variant = registry.coerce(value, DOMAINS[str(key)], profile == "ExistingNumericEnums")
		if scalar == null: return _error("Wrong enum domain or invalid value")
		backing[str(key)] = scalar
		return null
	func _error(message: String) -> Variant:
		var error_: Variant = ClassDB.instantiate("LuaError")
		error_.set_message(message)
		return error_

func _initialize() -> void: run.call_deferred()

func record(name: String, ok: bool, details: String = "", provenance: String = "ENGINE_APPROXIMATION") -> void:
	checks.append({"name": name, "ok": ok, "details": details, "provenance": provenance})
	print("[enumitem-prototype] %s %s %s" % ["PASS" if ok else "FAIL", name, details])

func classify_enum(value: Variant) -> String:
	# Deliberately does not close over registry. Otherwise typeof alone would
	# keep it alive and conceal a missing VM metadata lease in the GC test.
	if value is Object and is_instance_valid(value):
		var script_: Variant = value.get_script()
		if script_ == REGISTRY.ITEM_SCRIPT: return "EnumItem"
		if script_ == REGISTRY.TYPE_SCRIPT: return "Enum"
		if script_ == REGISTRY.ROOT_SCRIPT: return "Enums"
	return ""

func new_vm(registry: RefCounted, enum_binding: Variant, fixture: RefCounted, attach_owner: bool = true) -> Variant:
	var lua: Variant = ClassDB.instantiate("LuaAPI")
	if attach_owner: registry.attach_to_vm(lua)
	lua.set_use_callables(true)
	var err: Variant = lua.bind_libraries(PackedStringArray(["base", "table", "string", "math", "debug"]))
	if err != null:
		record("VM libraries", false, str(err.get_message()))
		return null
	lua.push_variant("Enum", enum_binding)
	lua.push_variant("fixture", fixture)
	var classifier: Variant = ClassDB.instantiate("LuaCallableExtra")
	classifier.set_info(Callable(self, "classify_enum"), 0, false, false)
	lua.push_variant("__prototype_kind", classifier)
	lua.push_variant("__prototype_enum_sample", registry.item("HumanoidStateType", "Jumping"))
	var setup_error: Variant = lua.do_string("""
local original_typeof = typeof or type
local enum_kind = __prototype_kind
typeof = function(value)
    local kind = enum_kind(value)
    if kind ~= '' then return kind end
    return original_typeof(value)
end
-- Only this isolated VM receives the shim. Native generic Object __lt/__le
-- return bool, so returning a GDScript LuaError cannot raise those errors.
local meta = debug.getmetatable(__prototype_enum_sample)
local index = meta.__index
local methods = {GetEnumItems=true, FromName=true, FromValue=true, GetEnums=true}
meta.__index = function(value, key)
    local member = index(value, key)
    local kind = enum_kind(value)
    if (kind == 'Enum' or kind == 'Enums') and methods[key] then
        return function(...) return member(...) end
    end
    return member
end
local function operand_type(value)
    local kind = enum_kind(value)
    return kind ~= '' and kind or type(value)
end
for key, operation in pairs({__add='add', __sub='sub', __mul='mul', __div='div'}) do
    local previous = meta[key]
    meta[key] = function(a, b)
        if enum_kind(a) == 'EnumItem' or enum_kind(b) == 'EnumItem' then
            error('attempt to perform arithmetic (' .. operation .. ') on ' .. operand_type(a) .. ' and ' .. operand_type(b), 0)
        end
        return previous(a, b)
    end
end
for key, operation in pairs({__lt='<', __le='<='}) do
    local previous = meta[key]
    meta[key] = function(a, b)
        if enum_kind(a) == 'EnumItem' or enum_kind(b) == 'EnumItem' then
            error('attempt to compare ' .. operand_type(a) .. ' ' .. operation .. ' ' .. operand_type(b), 0)
        end
        return previous(a, b)
    end
end
local unm, concat = meta.__unm, meta.__concat
meta.__unm = function(value)
    if enum_kind(value) == 'EnumItem' then error('attempt to perform arithmetic (unm) on EnumItem', 0) end
    return unm(value)
end
meta.__concat = function(a, b)
    if enum_kind(a) == 'EnumItem' or enum_kind(b) == 'EnumItem' then
        error('attempt to concatenate ' .. operand_type(a) .. ' with ' .. operand_type(b), 0)
    end
    return concat(a, b)
end
__prototype_kind = nil
__prototype_enum_sample = nil
debug = nil
""")
	if setup_error != null:
		record("VM typeof setup", false, str(setup_error.get_message()))
		return null
	return lua

func run_case(lua: Variant, name: String, source: String, provenance: String = "ENGINE_APPROXIMATION") -> void:
	var error_: Variant = lua.do_string(source)
	record(name, error_ == null, str(error_.get_message()) if error_ != null else "", provenance)

func native_reference() -> Dictionary:
	var digest := FileAccess.get_sha256(NATIVE_REFERENCE)
	if digest != NATIVE_REFERENCE_SHA256:
		record("immutable native reference SHA256", false, digest, "MEASURED")
		return {}
	var file := FileAccess.open(NATIVE_REFERENCE, FileAccess.READ)
	if file == null:
		record("native reference readable", false, NATIVE_REFERENCE, "MEASURED")
		return {}
	var reference: Dictionary = {}
	while not file.eof_reached():
		var line := file.get_line()
		if not line.begins_with("CHARACTER_EXPERIMENT_JSON "): continue
		var parsed: Variant = JSON.parse_string(line.trim_prefix("CHARACTER_EXPERIMENT_JSON "))
		if parsed is Dictionary and parsed.get("kind") == "a3_enum_probe":
			if not reference.is_empty():
				record("unique A3 native observation", false, "duplicate marker", "MEASURED")
				return {}
			reference = parsed
	var valid: bool = reference.get("run_id") == NATIVE_RUN_ID and reference.get("seq") == 2 and reference.get("families", []).size() == 6
	record("immutable native reference SHA256 and run identity", valid, digest, "MEASURED")
	return reference if valid else {}

func compare_native_observation(lua: Variant, reference: Dictionary) -> void:
	if reference.is_empty(): return
	lua.push_variant("nativeEnumRoot", {"lua_type": reference.enum_lua_type, "type": reference.enum_type, "tostring": reference.enum_tostring, "write": reference.enums_write})
	run_case(lua, "native root type strings and readonly error", """
assert(type(Enum) == nativeEnumRoot.lua_type)
assert(typeof(Enum) == nativeEnumRoot.type)
assert(tostring(Enum) == nativeEnumRoot.tostring)
local ok, reason = pcall(function() Enum.BOBUX_NONEXISTENT_ENUM = 0 end)
assert(ok == nativeEnumRoot.write.ok)
assert(tostring(reason) == nativeEnumRoot.write.reason)
""", "MEASURED")
	for family in reference.families:
		lua.push_variant("nativeEnumFamily", family)
		run_case(lua, "native observed %s order properties identity readonly" % family.name, """
local observed = nativeEnumFamily
local family = Enum[observed.name]
assert(type(family) == observed.lua_type)
assert(typeof(family) == observed.type)
assert(tostring(family) == observed.tostring)
local ok, reason = pcall(function() family.BOBUX_NONEXISTENT_ITEM = 0 end)
assert(ok == observed.family_write.ok)
assert(tostring(reason) == observed.family_write.reason)
local items = family:GetEnumItems()
assert(#items == #observed.items)
for index, expected in ipairs(observed.items) do
    local item = items[index]
    assert(item.Name == expected.Name and item.Value == expected.Value)
    assert(type(item) == expected.lua_type and typeof(item) == expected.type)
    assert(tostring(item) == expected.tostring)
    assert(tostring(item.EnumType) == expected.EnumType)
    assert((item.EnumType == family) == expected.family_identity)
    assert((item == family[item.Name]) == expected.identity_equal)
    assert((item == item.Value) == expected.number_equal)
    local nameOk, nameReason = pcall(function() item.Name = 'Changed' end)
    assert(nameOk == expected.name_write.ok)
    assert(tostring(nameReason) == expected.name_write.reason)
    local valueOk, valueReason = pcall(function() item.Value = 99 end)
    assert(valueOk == expected.value_write.ok)
    assert(tostring(valueReason) == expected.value_write.reason)
    assert(item.Name == expected.Name and item.Value == expected.Value)
end
""", "MEASURED")
	lua.push_variant("nativeEnumFamily", null)
	lua.push_variant("nativeEnumRoot", null)

func collect_vm(lua: Variant, name: String) -> void:
	var what := ClassDB.class_get_integer_constant("LuaAPI", "GC_COLLECT")
	var result: Variant = lua.configure_gc(what, 0)
	record(name, result == 0, "LuaAPI.configure_gc(GC_COLLECT) result=%s" % str(result))

func native_error_semantic(reason: String) -> String:
	# Source location depends on the caller; the native semantic error is kept.
	if reason.begins_with("CommandBar:"):
		var separator := reason.find(": ", "CommandBar:".length())
		if separator >= 0: return reason.substr(separator + 2)
	return reason

func compare_native_coercion(lua: Variant) -> void:
	var digest := FileAccess.get_sha256(COERCION_REFERENCE)
	if digest != COERCION_SHA256:
		record("immutable native coercion reference SHA256", false, digest, "MEASURED")
		return
	var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(COERCION_REFERENCE))
	if not reference is Dictionary or reference.get("run_id") != COERCION_RUN_ID or reference.get("rows", []).size() != 543:
		record("native coercion reference identity", false, "run/row mismatch", "MEASURED")
		return
	record("immutable native coercion reference SHA256 and run identity", true, digest, "MEASURED")
	var family_cases: Dictionary = {}
	var root_subset: Array = []
	var root_and_item_cases: Dictionary = {}
	for row in reference.rows:
		var id: String = row.get("id", "")
		if row.get("context") == "enum" and (id.contains("_FromValue_") or id.contains("_FromName_") or id.contains("_GetEnumItems_")):
			var family: String = id.get_slice("_", 0)
			if not family_cases.has(family): family_cases[family] = []
			var case_: Dictionary = row.duplicate()
			case_["semantic_error"] = native_error_semantic(row.get("error", ""))
			family_cases[family].append(case_)
		if id == "root_GetEnums":
			for entry in row.returns[0].entries:
				for field in entry.value.entries:
					if field.key.get("value") == "tostring" and REGISTRY.DEFINITIONS.has(field.value.value): root_subset.append(field.value.value)
		if id.begins_with("operator_") or id.begins_with("raycast_alias_") or id in ["root_GetEnums_wrong_self", "root_existing_enum_write", "root_missing_enum_write", "family_existing_item_write", "item_EnumType_write", "item_Name_write", "item_Value_write", "item_missing_write", "item_missing_read", "family_missing_read", "root_missing_read"]:
			var case_: Dictionary = row.duplicate()
			case_["semantic_error"] = native_error_semantic(row.get("error", ""))
			root_and_item_cases[id] = case_
	lua.push_variant("nativeRestoreSource", "")
	run_case(lua, "native coercion restore tagged own observations", """
function nativeRestore(v)
    if v.type == 'nil' then return nil end
    if v.type == 'EnumItem' then return Enum[v.EnumType][v.Name] end
    if v.type == 'Enum' then return Enum[v.tostring] end
    if v.type == 'table' then
        local result = {}
        for _, entry in ipairs(v.entries) do result[nativeRestore(entry.key)] = nativeRestore(entry.value) end
        return result
    end
    if v.type == 'number' then
        if v.value == 'nan' then return 0/0 end
        if v.value == 'inf' then return math.huge end
        if v.value == '-inf' then return -math.huge end
    end
    return v.value
end
function nativeAssertResult(actual, expected)
    if expected.type == 'table' then
        local restored = nativeRestore(expected)
        for key, value in pairs(restored) do assert(actual[key] == value) end
        assert(#actual == #restored)
    else
        assert(actual == nativeRestore(expected))
    end
end
""", "MEASURED")
	for family in family_cases:
		lua.push_variant("nativeMethodCases", family_cases[family])
		run_case(lua, "native observed %s FromName FromValue arity errors" % family, """
for _, observed in ipairs(nativeMethodCases) do
    local name, method = observed.id:match('^([^_]+)_([^_]+)_')
    local receiver = Enum[name]
    local args = {}
    for i, value in ipairs(observed.args) do args[i] = nativeRestore(value) end
    local callback = receiver[method]
    local ok, actual
    if observed.id:match('_wrong_self$') then
        ok, actual = pcall(callback, table.unpack(args, 1, #observed.args))
    else
        ok, actual = pcall(callback, receiver, table.unpack(args, 1, #observed.args))
    end
    assert(ok == observed.ok, observed.id .. ': pcall outcome')
    if ok then nativeAssertResult(actual, observed.returns[1])
    else assert(tostring(actual) == observed.semantic_error, observed.id .. ': ' .. tostring(actual)) end
end
""", "MEASURED")
	lua.push_variant("nativeRootSubset", root_subset)
	run_case(lua, "native GetEnums alphabetic covered subset (648 full types not implemented)", """
local subset = Enum:GetEnums()
assert(#subset == #nativeRootSubset and #subset == 7)
for i, expected in ipairs(nativeRootSubset) do assert(tostring(subset[i]) == expected) end
assert(#Enum:GetEnums(123) == #subset)
""", "MEASURED")
	lua.push_variant("nativeOperatorCases", root_and_item_cases)
	run_case(lua, "native item aliases readonly reads operators and root receiver", """
local item = Enum.HumanoidStateType.Running
local operations = {
 root_GetEnums_wrong_self = function() return Enum.GetEnums({}) end,
 root_existing_enum_write = function() Enum.Material = Enum.HumanoidStateType end,
 root_missing_enum_write = function() Enum.BOBUX_MISSING = 1 end,
 family_existing_item_write = function() Enum.Material.Plastic = Enum.Material.Neon end,
 item_EnumType_write = function() item.EnumType = Enum.Material end,
 item_Name_write = function() item.Name = 'Changed' end,
 item_Value_write = function() item.Value = 17 end,
 item_missing_write = function() item.BOBUX_MISSING = 123 end,
 item_missing_read = function() return item.BOBUX_MISSING end,
 family_missing_read = function() return Enum.Material.BOBUX_MISSING end,
 root_missing_read = function() return Enum.BOBUX_MISSING end,
 operator_sub = function() return item - 1 end,
 operator_unary_minus = function() return -item end,
 operator_unknown_item_read = function() return Enum.HumanoidStateType.BOBUX_MISSING end,
 operator_enum_family_equal = function() return item.EnumType == Enum.HumanoidStateType end,
 operator_div = function() return item / 2 end,
 operator_same_number_wrong_domain_equal = function() return Enum.HumanoidStateType.Freefall == Enum.CameraType.Custom end,
 operator_tonumber = function() return tonumber(item) end,
 operator_item_number_equal = function() return item == 8 end,
 operator_mul = function() return item * 2 end,
 operator_concat = function() return 'item=' .. item end,
 operator_wrong_domain_equal = function() return item == Enum.CameraType.Custom end,
 operator_same_item_equal = function() return item == Enum.HumanoidStateType.Running end,
 operator_less_equal = function() return item <= Enum.HumanoidStateType.Climbing end,
 operator_less = function() return item < Enum.HumanoidStateType.Climbing end,
 operator_add = function() return item + 1 end,
 raycast_alias_Blacklist = function() return Enum.RaycastFilterType.Blacklist end,
 raycast_alias_Whitelist = function() return Enum.RaycastFilterType.Whitelist end,
 raycast_alias_Exclude = function() return Enum.RaycastFilterType.Exclude end,
 raycast_alias_Include = function() return Enum.RaycastFilterType.Include end,
}
local getters = {
 root_existing_enum_write = function() return Enum.Material end,
 family_existing_item_write = function() return Enum.Material.Plastic end,
 item_EnumType_write = function() return item.EnumType end,
 item_Name_write = function() return item.Name end,
 item_Value_write = function() return item.Value end,
}
for id, observed in pairs(nativeOperatorCases) do
    assert(operations[id], id)
    local ok, actual = pcall(operations[id])
    assert(ok == observed.ok, id .. ': pcall outcome')
    if ok then nativeAssertResult(actual, observed.returns[1])
    else assert(tostring(actual) == observed.semantic_error, id .. ': ' .. tostring(actual)) end
    if observed.getter then nativeAssertResult(getters[id](), observed.getter) end
end
""", "MEASURED")
	for global_ in ["nativeRestore", "nativeAssertResult", "nativeMethodCases", "nativeRootSubset", "nativeOperatorCases", "nativeRestoreSource"]: lua.push_variant(global_, null)

func compare_native_extra(lua: Variant) -> void:
	var digest := FileAccess.get_sha256(EXTRA_REFERENCE)
	if digest != EXTRA_SHA256:
		record("immutable native extra reference SHA256", false, digest, "MEASURED")
		return
	var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_REFERENCE))
	if not reference is Dictionary or reference.get("run_id") != EXTRA_RUN_ID or reference.get("rows", []).size() != 6:
		record("native extra reference identity", false, "run/row mismatch", "MEASURED")
		return
	record("immutable native extra reference SHA256 and run identity", true, digest, "MEASURED")
	lua.push_variant("nativeExtraCases", reference.rows)
	run_case(lua, "native negative fractions aliases and actual Enum receiver", """
local operations = {
 negative_fraction_half = function() return Enum.HumanoidStateType:FromValue(-0.5) end,
 negative_fraction_one_half = function() return Enum.HumanoidStateType:FromValue(-1.5) end,
 alias_FromName_Blacklist = function() return Enum.RaycastFilterType:FromName('Blacklist') end,
 alias_FromName_Whitelist = function() return Enum.RaycastFilterType:FromName('Whitelist') end,
 FromValue_other_enum_receiver = function() return Enum.Material.FromValue(Enum.CameraType,6) end,
 GetEnumItems_other_enum_receiver = function() return Enum.Material.GetEnumItems(Enum.CameraType) end,
}
for seq, observed in ipairs(nativeExtraCases) do
    assert(observed.seq == seq)
    local ok, actual = pcall(operations[observed.id])
    assert(ok == observed.ok, observed.id .. ': pcall outcome')
    assert(ok, observed.id .. ': ' .. tostring(actual))
    local expected = observed.returns[1]
    if expected.type == 'EnumItem' then
        assert(typeof(actual) == 'EnumItem' and actual == Enum[expected.EnumType][expected.Name])
        assert(actual.Value == expected.Value)
    elseif expected.type == 'nil' then
        assert(actual == nil)
    elseif expected.type == 'table' then
        assert(#actual == #expected.items)
        for i, item in ipairs(actual) do assert(tostring(item) == expected.items[i]) end
    else error('unknown own extra result schema') end
end
""", "MEASURED")
	lua.push_variant("nativeExtraCases", null)

func report_path() -> String:
	var path := "res://.codex-tmp/character_parity/enumitem-prototype-native-r02.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): path = arg.trim_prefix("--report=")
	return path

func run() -> void:
	if not ClassDB.class_exists("LuaAPI"):
		record("Native Luau VM", false, "LuaAPI extension unavailable")
		quit(2)
		return
	var registry = REGISTRY.new()
	var backing := {"State": 8, "CameraType": 5, "Material": 256, "Priority": 0}
	var parity_fixture := PropertyFixture.new(registry, REGISTRY.ROBLOX_PARITY_ENUM_ITEM, backing)
	var legacy_fixture := PropertyFixture.new(registry, REGISTRY.EXISTING_NUMERIC_ENUMS, backing)
	var engine := root.get_node("LuaScriptEngine")
	var parity: Variant = new_vm(registry, registry.enums(), parity_fixture)
	var legacy: Variant = new_vm(registry, engine._build_enum_proxy(), legacy_fixture)
	if parity == null or legacy == null:
		quit(2)
		return
	record("Native Luau version", str(parity.get_runtime_name()).contains("Luau"), str(parity.get_runtime_name()))
	var reference := native_reference()
	compare_native_observation(parity, reference)
	compare_native_coercion(parity)
	compare_native_extra(parity)
	run_case(parity, "Name Value EnumType", """
local item = Enum.HumanoidStateType.Jumping
assert(item.Name == 'Jumping' and item.Value == 3)
assert(item.EnumType == Enum.HumanoidStateType)
assert(Enum.Material.Neon.Value == 288)
assert(Enum.AnimationPriority.Core.Value == 1000)
""")
	run_case(parity, "userdata typeof tostring", """
assert(type(Enum.HumanoidStateType.Jumping) == 'userdata')
assert(typeof(Enum.HumanoidStateType.Jumping) == 'EnumItem')
assert(typeof(Enum.HumanoidStateType) == 'Enum')
assert(typeof(Enum) == 'Enums')
assert(tostring(Enum.Material.Neon) == 'Enum.Material.Neon')
assert(tostring(Enum.Material) == 'Material')
assert(tostring(Enum) == 'Enums')
assert(typeof(3) == 'number' and typeof({Value=3}) == 'table')
""")
	run_case(parity, "equal domains and unequal numeric values", """
assert(Enum.HumanoidStateType.Jumping == Enum.HumanoidStateType.Jumping)
assert(Enum.HumanoidStateType.Jumping ~= Enum.HumanoidStateType.Freefall)
assert(Enum.HumanoidStateType.Jumping ~= Enum.CameraType.Track)
assert(Enum.HumanoidStateType.Jumping ~= 3)
assert(Enum.HumanoidStateType.Jumping ~= 'Jumping')
""")
	run_case(parity, "table key identity", """
itemKeyTable = {[Enum.HumanoidStateType.Jumping] = 27}
assert(itemKeyTable[Enum.HumanoidStateType.Jumping] == 27)
assert(itemKeyTable[Enum.CameraType.Track] == nil)
assert(itemKeyTable[3] == nil)
""")
	parity.push_variant("injectedItem", registry.item("HumanoidStateType", "Jumping"))
	run_case(parity, "native push preserves userdata identity", "assert(injectedItem == Enum.HumanoidStateType.Jumping and itemKeyTable[injectedItem] == 27)")
	run_case(parity, "GetEnumItems sparse domain and singleton values", """
local items = Enum.HumanoidStateType:GetEnumItems()
assert(#items == 17)
local seen = {}
for _, item in ipairs(items) do
    assert(item.EnumType == Enum.HumanoidStateType and typeof(item) == 'EnumItem')
    assert(item == Enum.HumanoidStateType[item.Name])
    assert(not seen[item.Value])
    seen[item.Value] = true
end
assert(seen[0] and seen[3] and seen[18] and not seen[9] and not seen[17])
items[1] = nil
assert(#Enum.HumanoidStateType:GetEnumItems() == 17)
""")
	run_case(parity, "GetEnums returns real enum types", """
local enums = Enum:GetEnums()
assert(#enums == 7)
for _, enumType in ipairs(enums) do
    assert(typeof(enumType) == 'Enum' and #enumType:GetEnumItems() > 0)
end
enums[1] = nil
assert(#Enum:GetEnums() == 7)
""")
	run_case(parity, "FromName FromValue canonical identity and fractional truncation", """
assert(Enum.HumanoidStateType:FromName('Jumping') == Enum.HumanoidStateType.Jumping)
assert(Enum.HumanoidStateType:FromValue(3) == Enum.HumanoidStateType.Jumping)
assert(Enum.HumanoidStateType:FromValue(9) == nil)
assert(Enum.HumanoidStateType:FromValue(3.5) == Enum.HumanoidStateType.Jumping)
assert(Enum.HumanoidStateType:FromName('Missing') == nil)
""")
	run_case(parity, "read only item type root", """
local item = Enum.HumanoidStateType.Jumping
assert(not pcall(function() item.Name='Changed' end))
assert(not pcall(function() item.Value=99 end))
assert(not pcall(function() item.EnumType=Enum.Material end))
assert(not pcall(function() Enum.HumanoidStateType.Jumping=Enum.HumanoidStateType.Freefall end))
assert(not pcall(function() Enum.Material={} end))
assert(item.Name=='Jumping' and item.Value==3)
""")
	run_case(parity, "unknown member and internals unavailable", """
assert(not pcall(function() return Enum.HumanoidStateType.LedgeGrab end))
assert(not pcall(function() return Enum.Material.MissingMaterial end))
assert(not pcall(function() return Enum.MissingType end))
assert(not pcall(function() return Enum.Material.Neon._value end))
assert(not pcall(function() return Enum.Material.Neon.get_script end))
""")
	run_case(parity, "property fixture assignment round trip", """
fixture.State=Enum.HumanoidStateType.Freefall
fixture.CameraType=Enum.CameraType.Scriptable
fixture.Material=Enum.Material.Neon
fixture.Priority=Enum.AnimationPriority.Action
assert(fixture.State==Enum.HumanoidStateType.Freefall)
assert(fixture.CameraType==Enum.CameraType.Scriptable)
assert(fixture.Material==Enum.Material.Neon)
assert(fixture.Priority==Enum.AnimationPriority.Action)
""")
	record("boundary stores scalar IDs", backing == {"State": 5, "CameraType": 6, "Material": 288, "Priority": 2})
	run_case(parity, "fixture strict input policy (native coercion pending)", """
assert(not pcall(function() fixture.State=Enum.CameraType.Custom end))
assert(not pcall(function() fixture.State={Name='Freefall',Value=5} end))
assert(not pcall(function() fixture.State=5 end))
assert(not pcall(function() fixture.State=math.huge end))
assert(fixture.State==Enum.HumanoidStateType.Freefall)
""")
	run_case(legacy, "ExistingNumericEnums unchanged namespace and shared raw store", """
assert(Enum.HumanoidStateType.Jumping==3 and typeof(Enum.HumanoidStateType.Jumping)=='number')
assert(fixture.State==5 and fixture.Material==288 and fixture.CameraType==6)
fixture.State=8
fixture.Material=256
local map={[Enum.HumanoidStateType.Jumping]='numeric'}
assert(map[3]=='numeric')
legacyOnlyGlobal=42
""")
	run_case(parity, "two VM profile isolation on shared data", """
assert(legacyOnlyGlobal==nil)
assert(typeof(Enum.HumanoidStateType.Jumping)=='EnumItem')
assert(fixture.State==Enum.HumanoidStateType.Running)
assert(fixture.Material==Enum.Material.Plastic)
assert(itemKeyTable[Enum.HumanoidStateType.Jumping]==27)
""")
	var jump: Variant = registry.item("HumanoidStateType", "Jumping")
	record("strict and explicit numeric coercion", registry.coerce(jump, "HumanoidStateType") == 3 and registry.coerce(3, "HumanoidStateType") == null and registry.coerce(3, "HumanoidStateType", true) == 3 and registry.coerce(9, "HumanoidStateType", true) == null and registry.coerce(jump, "CameraType", true) == null)
	record("nonfinite and fractional numeric rejection", registry.item_from_value("HumanoidStateType", INF) == null and registry.item_from_value("HumanoidStateType", NAN) == null and registry.item_from_value("HumanoidStateType", 3.5) == null)
	record("unknown profile rejected without numeric fallback", registry.to_boundary(3, "HumanoidStateType", "TypoParityProfile") == null and registry.to_boundary(3, "HumanoidStateType", "") == null)
	legacy = null
	parity = null
	await process_frame
	await test_missing_owner_control()
	await test_registry_lifetime()
	var failed := 0
	for result in checks:
		if not result.ok: failed += 1
	var report := {"scope": "isolated EnumItem prototype, not production A3 completion", "checks": checks, "pass": checks.size() - failed, "fail": failed, "native_reference": {"path": NATIVE_REFERENCE, "sha256": NATIVE_REFERENCE_SHA256, "run_id": NATIVE_RUN_ID, "seq": 2, "observed_domains": 6, "observed_items": 83}, "coercion_reference": {"path": COERCION_REFERENCE, "sha256": COERCION_SHA256, "run_id": COERCION_RUN_ID, "rows": 543}, "extra_reference": {"path": EXTRA_REFERENCE, "sha256": EXTRA_SHA256, "run_id": EXTRA_RUN_ID, "rows": 6}, "not_observed": ["large numeric conversion boundaries", "function/Vector3 input conversion"], "not_implemented": ["GetEnums 648 complete domains", "native class-specific property/method input coercion in production", "production shared wrapper/event boundary", "require/task profile propagation", "network codec and negotiation"]}
	DirAccess.make_dir_recursive_absolute("res://.codex-tmp/character_parity")
	var destination := report_path()
	if FileAccess.file_exists(destination):
		push_error("Refusing to overwrite EnumItem test report: %s; use --report=<fresh path>" % destination)
		quit(2)
		return
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report, "\t"))
	print("[enumitem-prototype] PASS=%d FAIL=%d" % [checks.size() - failed, failed])
	quit(0 if failed == 0 else 1)

func test_missing_owner_control() -> void:
	# Negative control: prove that neither typeof nor an isolated kept item
	# secretly retains the registry. This is an ownership-kernel experiment,
	# not an assertion about Roblox's internal lifetime architecture.
	var registry: Variant = REGISTRY.new()
	var registry_weak: WeakRef = weakref(registry)
	var type_weak: WeakRef = weakref(registry.enum_type("HumanoidStateType"))
	var item_weak: WeakRef = weakref(registry.item("HumanoidStateType", "Jumping"))
	var lua: Variant = new_vm(registry, registry.enums(), null, false)
	if lua == null:
		record("missing owner negative control fixture", false)
		return
	run_case(lua, "missing owner control retains only item userdata", """
keep = Enum.HumanoidStateType.Jumping
Enum = nil
assert(typeof(keep) == 'EnumItem')
""")
	registry = null
	collect_vm(lua, "missing owner control actual full GC")
	await process_frame
	record("missing owner control expires registry and weak parent", registry_weak.get_ref() == null and type_weak.get_ref() == null and item_weak.get_ref() != null)
	run_case(lua, "missing owner control exposes no fabricated parent", "assert(keep.EnumType == nil and keep.Name == 'Jumping' and keep.Value == 3)")
	lua = null
	await process_frame
	record("missing owner control teardown releases isolated item", item_weak.get_ref() == null)

func test_registry_lifetime() -> void:
	var registry: Variant = REGISTRY.new()
	var registry_weak: WeakRef = weakref(registry)
	var type_weak: WeakRef = weakref(registry.enum_type("HumanoidStateType"))
	var item_weak: WeakRef = weakref(registry.item("HumanoidStateType", "Jumping"))
	var vm_a: Variant = new_vm(registry, registry.enums(), null)
	var vm_b: Variant = new_vm(registry, registry.enums(), null)
	if vm_a == null or vm_b == null:
		record("two parity VM lifetime fixture", false)
		return
	run_case(vm_a, "first parity VM retains item after namespace removed", """
keep = Enum.HumanoidStateType.Jumping
keys = {[keep] = 'first'}
Enum = nil
assert(typeof(keep) == 'EnumItem' and keep.EnumType:FromValue(3) == keep)
assert(keys[keep.EnumType.Jumping] == 'first')
""")
	run_case(vm_b, "second parity VM retains independent table keys", """
keep = Enum.HumanoidStateType.Jumping
keys = {[keep] = 'second'}
Enum = nil
assert(typeof(keep) == 'EnumItem' and keep.EnumType:FromValue(3) == keep)
assert(keys[keep.EnumType.Jumping] == 'second')
""")
	registry = null
	collect_vm(vm_a, "first parity VM actual full GC after globals removed")
	collect_vm(vm_b, "second parity VM actual full GC after globals removed")
	await process_frame
	record("VM owners retain registry type and item", registry_weak.get_ref() != null and type_weak.get_ref() != null and item_weak.get_ref() != null)
	run_case(vm_a, "live first parity VM after external owner released", """
assert(keep.EnumType.Jumping == keep and keys[keep.EnumType.Jumping] == 'first')
""")
	vm_a = null
	await process_frame
	record("second VM survives first VM teardown", registry_weak.get_ref() != null and type_weak.get_ref() != null)
	collect_vm(vm_b, "remaining parity VM actual full GC after first closed")
	run_case(vm_b, "live second parity VM after first closed", """
assert(typeof(keep.EnumType) == 'Enum')
assert(keep.EnumType.Jumping == keep and keys[keep.EnumType.Jumping] == 'second')
assert(tostring(keep) == 'Enum.HumanoidStateType.Jumping')
""")
	vm_b = null
	await process_frame
	record("last VM teardown releases registry graph without cycles", registry_weak.get_ref() == null and type_weak.get_ref() == null and item_weak.get_ref() == null)
