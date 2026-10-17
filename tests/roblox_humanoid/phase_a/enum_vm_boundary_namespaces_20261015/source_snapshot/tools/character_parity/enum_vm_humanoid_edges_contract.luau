-- Own production-VM checks against the saved 0.743 enabled/receiver probe.
-- No assertion about unparented physical ChangeState or fresh state defaults.
local h=workspace.Player.Humanoid
local states=Enum.HumanoidStateType:GetEnumItems()
local original={}
for _,state in ipairs(states) do original[state]=h:GetStateEnabled(state) end
local other=Instance.new('Humanoid')
local part=Instance.new('Part')
local checks=0
local function check(ok)
    assert(ok,'native Humanoid edge contract mismatch')
    checks+=1
end
local function fails(operation,expected)
    local ok,problem=pcall(operation)
    check(not ok and string.sub(tostring(problem),-#expected)==expected)
end
local bad_receivers={{},{value=part},{value=13},{value=Enum.HumanoidStateType.Running}}
-- A nil receiver is tested separately; the empty table remains a real table.
bad_receivers[1]={value={}}
for _,method in ipairs({'GetState','ChangeState','GetStateEnabled','SetStateEnabled'}) do
    local extracted=h[method]
    local expected="Expected ':' not '.' calling member function "..method
    fails(function() extracted(nil,Enum.HumanoidStateType.Running,false) end,expected)
    for _,entry in ipairs(bad_receivers) do
        fails(function() extracted(entry.value,Enum.HumanoidStateType.Running,false) end,expected)
    end
end
local setter,getter=h.SetStateEnabled,h.GetStateEnabled
check(select('#',setter(other,Enum.HumanoidStateType.Running,false))==0)
check(getter(other,Enum.HumanoidStateType.Running)==false)
check(h:GetStateEnabled(Enum.HumanoidStateType.Running)==original[Enum.HumanoidStateType.Running])
check(select('#',setter(other,'Running',true))==0)
check(getter(other,'Running')==true)
check(typeof(h.GetState(other))=='EnumItem')
check(select('#',h.ChangeState(other,Enum.HumanoidStateType.Physics))==0)
fails(function() getter(h) end,'Argument 1 missing or nil')
fails(function() setter(h,nil,false) end,'Argument 1 missing or nil')
fails(function() setter(h,nil,nil) end,'Argument 2 missing or nil')
fails(function() setter(h,Enum.HumanoidStateType.Running) end,'Argument 2 missing or nil')
local events=0
local connection=h.StateEnabledChanged:Connect(function() events+=1 end)
for _,raw in ipairs({'8','Enum.HumanoidStateType.Running','BOBUX_NONEXISTENT_ITEM'}) do
    check(getter(h,raw)==true)
    check(select('#',setter(h,raw,false))==0)
    check(getter(h,raw)==true)
    check(select('#',setter(h,raw,true))==0)
    for _,state in ipairs(states) do check(h:GetStateEnabled(state)==original[state]) end
end
task.spawn(function()
    task.wait(0.04)
    check(events==0)
    connection:Disconnect()
    other:Destroy()
    part:Destroy()
    script:SetAttribute('NativeEdgeChecks',checks)
    script:SetAttribute('NativeEdgesDone',true)
end)
