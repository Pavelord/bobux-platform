-- Own safety regression. Does not transfer these tables to native bindings.
-- Explicit partial cases below are not assertions of native error wording.
local t={};t.self=t;t[t]=t
local item=Enum.HumanoidStateType.Running
local family=Enum.HumanoidStateType
local h=workspace.Player.Humanoid
local checks=0
local function must_error(operation,expected)
    local ok,problem=pcall(operation)
    assert(not ok,'cyclic input unexpectedly accepted')
    problem=tostring(problem)
    assert(string.sub(problem,-#expected)==expected,problem)
    checks+=1
end
for _,case in ipairs({
    {function() return item+t end,'attempt to perform arithmetic (add) on EnumItem and table'},
    {function() return t+item end,'attempt to perform arithmetic (add) on table and EnumItem'},
    {function() return item-t end,'attempt to perform arithmetic (sub) on EnumItem and table'},
    {function() return t-item end,'attempt to perform arithmetic (sub) on table and EnumItem'},
    {function() return item*t end,'attempt to perform arithmetic (mul) on EnumItem and table'},
    {function() return t*item end,'attempt to perform arithmetic (mul) on table and EnumItem'},
    {function() return item/t end,'attempt to perform arithmetic (div) on EnumItem and table'},
    {function() return t/item end,'attempt to perform arithmetic (div) on table and EnumItem'},
    -- Luau 0.719 rejects these mixed types before dispatching __lt/__le.
    -- This is a VM safety check, not native Roblox error-label parity.
    {function() return item<t end,'attempt to compare userdata < table'},
    {function() return t<item end,'attempt to compare table < userdata'},
    {function() return item<=t end,'attempt to compare userdata <= table'},
    {function() return t<=item end,'attempt to compare table <= userdata'},
    {function() return item..t end,'attempt to concatenate EnumItem with table'},
    {function() return t..item end,'attempt to concatenate table with EnumItem'},
    {function() return item%t end,'RobloxParity.EnumItem: operator % is not implemented'},
    {function() return t%item end,'RobloxParity.EnumItem: operator % is not implemented'},
    {function() return item^t end,'RobloxParity.EnumItem: operator ^ is not implemented'},
    {function() return t^item end,'RobloxParity.EnumItem: operator ^ is not implemented'},
    {function() return item(t) end,'RobloxParity.EnumItem: calling enum values is not implemented'},
    {function() return family(t) end,'RobloxParity.EnumItem: calling enum values is not implemented'},
    {function() return Enum(t) end,'RobloxParity.EnumItem: calling enum values is not implemented'},
    {function() return item[t] end,'RobloxParity.EnumItem: nonstring enum members are not implemented'},
    {function() return family[t] end,'RobloxParity.EnumItem: nonstring enum members are not implemented'},
    {function() return Enum[t] end,'RobloxParity.EnumItem: nonstring enum members are not implemented'},
    {function() item[t]=t end,'RobloxParity.EnumItem: nonstring enum members are not implemented'},
    {function() item.Value=t end,'Value is not a valid member of EnumItem'},
    {function() family.Running=t end,'Running is not a valid member of Enum'},
    {function() Enum.HumanoidStateType=t end,'HumanoidStateType is not a valid member of Enums'},
    {function() return family.FromName(t,'Running') end,"invalid argument #1 to 'FromName' (Enum expected, got table)"},
    {function() return family:FromName(t) end,"invalid argument #2 to 'FromName' (string expected, got table)"},
    {function() return family:FromValue(t) end,"invalid argument #2 to 'FromValue' (number expected, got table)"},
    {function() return Enum.GetEnums(t) end,"invalid argument #1 to 'GetEnums' (Enums expected, got table)"},
    {function() return family.GetEnumItems(t) end,"invalid argument #1 to 'GetEnumItems' (Enum expected, got table)"},
    {function() return h.GetState(t) end,'RobloxParity.EnumItem: Humanoid receiver required (receiver coercion remains partial)'},
    {function() return h:GetStateEnabled(t) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:ChangeState(t) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:SetStateEnabled(t) end,'Argument 2 missing or nil'},
    {function() return h:SetStateEnabled(t,nil,t) end,'Argument 2 missing or nil'},
    {function() return h:SetStateEnabled(t,true) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:SetStateEnabled(family.Jumping,t) end,'Unable to cast Array to bool'},
}) do must_error(case[1],case[2]) end
assert(#Enum:GetEnums(t)==7);checks+=1
assert(#family:GetEnumItems(t)==17);checks+=1
assert(family:FromName('Running',t)==item);checks+=1
assert(family:FromValue(8.5,t)==item);checks+=1
assert(family.FromValue(Enum.CameraType,6,t)==Enum.CameraType.Scriptable);checks+=1
assert(h:GetState(t)==item);checks+=1
assert(h:GetStateEnabled(family.Jumping,t)==true);checks+=1
assert(select('#',h:ChangeState(nil,t))==0);checks+=1
script:SetAttribute('CyclicChecks',checks)
