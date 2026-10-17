-- Real Camera3D wrapper/backend contract. Native input cases are exported
-- unchanged from Studio 0.742 run c475020d-1687-4cb5-9b53-2ecbe4d5a2f7.
-- Camera movement algorithms and Changed event ordering are not claimed.
local current=workspace.CurrentCamera
assert(current~=nil,'actual player CurrentCamera unavailable')
local fresh=Instance.new('Camera',workspace)
fresh.Name='CameraTypeFresh'
local types=Enum.CameraType
local checks=0
local function check(ok,detail)
    assert(ok,detail or 'CameraType boundary mismatch')
    checks+=1
end
local function snapshot(camera)
    return __camera_backend_snapshot(camera)
end
local function unchanged(before,after)
    return before.pose==after.pose and before.type==after.type and before.value==after.value
        and before.has_value==after.has_value and before.top_level==after.top_level
        and before.arm_enabled==after.arm_enabled and before.write_marker==after.write_marker
end
local function exact_error(ok,problem,expected)
    check(not ok,'invalid CameraType assignment accepted')
    check(string.sub(tostring(problem),-#expected)==expected,tostring(problem))
end
check(current.CameraType==types.Custom,'existing player camera starts Custom')
check(fresh.CameraType==types.Fixed,'fresh Camera starts Fixed')
check(current:GetProperty('CameraType')==types.Custom)
check(fresh:GetProperty('CameraType')==types.Fixed)
check(__camera_legacy('read',current,nil),'legacy initial absent property unchanged')
check(__camera_legacy('read',fresh,nil),'legacy fresh absent property unchanged')
local routes={
    function(target,value) target.CameraType=value end,
    function(target,value) __bobux_set(target,'CameraType',value) end,
    function(target,value) check(target:SetProperty('CameraType',value)==true) end,
    function(target,value) local set=target.SetProperty;check(set('CameraType',value)==true) end,
}
local function restore(argument)
    if argument.type=='EnumItem' then return Enum[argument.EnumType][argument.Name] end
    if argument.type=='number' then
        if argument.value=='nan' then return 0/0 end
        if argument.value=='inf' then return math.huge end
        if argument.value=='-inf' then return -math.huge end
        return argument.value
    end
    if argument.type=='table' then return {} end
    if argument.type=='nil' then return nil end
    return argument.value
end
for _,row in ipairs(__camera_native_rows) do
    local target=row.context=='fresh' and fresh or current
    for _,assign in ipairs(routes) do
        target.CameraType=types.Fixed
        local before=snapshot(target)
        local ok,problem=pcall(assign,target,restore(row.args[1]))
        check(ok==row.ok,row.id..': outcome '..tostring(problem))
        if row.ok then
            check(target.CameraType==types.Scriptable,row.id..': canonical getter')
            local after=snapshot(target)
            check(after.type=='int' and after.value=='6',row.id..': scalar metadata')
            check(before.pose==after.pose,row.id..': synchronous pose preserved')
        else
            exact_error(ok,problem,row.error)
            check(unchanged(before,snapshot(target)),row.id..': invalid write mutated camera')
        end
    end
end
-- A cyclic value is rejected by each Lua entry before native table conversion.
local cyclic={};cyclic.self=cyclic
for _,assign in ipairs(routes) do
    local before=snapshot(current)
    local ok,problem=pcall(assign,current,cyclic)
    exact_error(ok,problem,'Unable to assign property CameraType. EnumItem, number, or string expected, got table')
    check(unchanged(before,snapshot(current)))
end
-- Backend storage from old scripts is normalized only on the typed getter;
-- the strict setter still rejects full Enum.* strings as observed natively.
for _,representation in ipairs({'Scriptable','Enum.CameraType.Scriptable','6',6}) do
    check(__camera_legacy('write',current,representation))
    check(current.CameraType==types.Scriptable)
    check(__camera_legacy('read',current,representation),'getter did not rewrite legacy metadata')
end
for _,item in ipairs(types:GetEnumItems()) do
    -- Domain round trips, not a claim of all eight native camera algorithms.
    current.CameraType=item
    check(current.CameraType==item)
    check(current:GetProperty('CameraType')==item)
    check(__camera_legacy('read',current,item.Value),'other VM receives stored scalar')
end
current.CameraType=types.Scriptable
local scripted=snapshot(current)
check(scripted.top_level==true and scripted.arm_enabled==false,'Scriptable controls actual SpringArm')
current.CameraType=types.Custom
local custom=snapshot(current)
check(custom.top_level==false and custom.arm_enabled==true,'Custom restores actual SpringArm')
check(custom.pose==scripted.pose,'mode restoration preserves synchronous pose')
check(__camera_legacy('read',current,5))
fresh.CameraType=types.Custom
check(fresh.CameraType==types.Custom and __camera_legacy('read',fresh,5),'fresh shared wrapper typed/numeric split')
local fake={ClassName='Camera'}
__bobux_set(fake,'CameraType',types.Scriptable)
check(fake.CameraType==types.Scriptable,'plain table bypasses genuine Camera classifier')
local before=snapshot(current)
local ok,problem=pcall(function() current.CameraType=1e30 end)
check(not ok and string.find(tostring(problem),'not implemented',1,true)~=nil,'unmeasured huge cast is explicit partial')
check(unchanged(before,snapshot(current)))
script:SetAttribute('CameraChecks',checks)
script:SetAttribute('CameraDone',true)
