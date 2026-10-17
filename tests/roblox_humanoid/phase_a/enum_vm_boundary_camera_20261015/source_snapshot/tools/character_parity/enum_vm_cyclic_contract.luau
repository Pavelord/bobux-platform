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
    {function() return h.GetState(t) end,"Expected ':' not '.' calling member function GetState"},
    {function() return h:GetStateEnabled(t) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:ChangeState(t) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:SetStateEnabled(t) end,'Argument 2 missing or nil'},
    {function() return h:SetStateEnabled(t,nil,t) end,'Argument 2 missing or nil'},
    {function() return h:SetStateEnabled(t,true) end,'Unable to cast Array to HumanoidStateType'},
    {function() return h:SetStateEnabled(family.Jumping,t) end,'Unable to cast Array to bool'},
}) do must_error(case[1],case[2]) end
assert(#Enum:GetEnums(t)==10);checks+=1
assert(#family:GetEnumItems(t)==17);checks+=1
assert(family:FromName('Running',t)==item);checks+=1
assert(family:FromValue(8.5,t)==item);checks+=1
assert(family.FromValue(Enum.CameraType,6,t)==Enum.CameraType.Scriptable);checks+=1
assert(h:GetState(t)==item);checks+=1
assert(h:GetStateEnabled(family.Jumping,t)==true);checks+=1
assert(select('#',h:ChangeState(nil,t))==0);checks+=1
local remote=Instance.new('RemoteEvent',workspace)
for _,namespace in ipairs({Enum,family}) do
    for _,operator in ipairs({
        {'add',function() return namespace+t end,function() return t+namespace end},
        {'sub',function() return namespace-t end,function() return t-namespace end},
        {'mul',function() return namespace*t end,function() return t*namespace end},
        {'div',function() return namespace/t end,function() return t/namespace end},
        {'<',function() return namespace<t end,function() return t<namespace end},
        {'<=',function() return namespace<=t end,function() return t<=namespace end},
        {'..',function() return namespace..t end,function() return t..namespace end},
        {'%',function() return namespace%t end,function() return t%namespace end},
        {'^',function() return namespace^t end,function() return t^namespace end},
    }) do
        local expected='RobloxParity.EnumItem: operator '..operator[1]..' on enum namespaces is not implemented'
        if operator[1]=='<' or operator[1]=='<=' then
            -- Luau rejects mixed userdata/table comparisons before __lt/__le,
            -- for namespace/type userdata just as for EnumItem above.
            must_error(operator[2],'attempt to compare userdata '..operator[1]..' table')
            must_error(operator[3],'attempt to compare table '..operator[1]..' userdata')
        else
            must_error(operator[2],expected)
            must_error(operator[3],expected)
        end
    end
    must_error(function() return -namespace end,'RobloxParity.EnumItem: operator unm on enum namespaces is not implemented')
    local transport_error='RobloxParity.EnumItem: remote enum transport is not implemented'
    must_error(function() remote:FireServer(namespace) end,transport_error)
    must_error(function() remote:FireServer({value=namespace}) end,transport_error)
    local nested={value=namespace};nested.self=nested
    must_error(function() remote:FireServer(nested) end,transport_error)
    local send=remote.FireServer
    must_error(function() send(remote,nested) end,transport_error)
end
remote:Destroy()
script:SetAttribute('CyclicChecks',checks)
