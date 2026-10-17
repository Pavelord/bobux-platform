local parity = PROFILE_PARITY
local h = workspace.Player.Humanoid
local state_type = Enum.HumanoidStateType
local function state(value, name, id)
    if parity then
        assert(typeof(value) == 'EnumItem' and type(value) == 'userdata')
        assert(value == state_type[name] and value.Value == id and value.EnumType == state_type)
    else
        assert(type(value) == 'number' and value == id,'legacy state expected '..name..'/'..id..', got '..type(value)..'/'..tostring(value))
    end
end
state(h:GetState(), 'Running', 8)
state(state_type.Running, 'Running', 8)
if parity then
    assert(typeof(Enum)=='Enums' and typeof(state_type)=='Enum')
    assert(tostring(state_type)=='HumanoidStateType' and tostring(Enum)=='Enums')
    assert(state_type.Running ~= 8 and state_type.Freefall ~= Enum.CameraType.Custom)
    local keys = {[state_type.Running]='canonical'}
    assert(keys[h:GetState()]=='canonical' and keys[8]==nil)
    assert(not pcall(function() state_type.Running.Value=55 end))
    assert(not pcall(function() return state_type.MISSING end))
    assert(not pcall(function() return state_type.Running+1 end))
    assert(not pcall(function() return state_type.Running<state_type.Climbing end))
    assert(not pcall(function() h:ChangeState(Enum.CameraType.Custom) end))
    assert(not pcall(function() h:SetStateEnabled({},false) end))
    assert(not pcall(function() h:GetStateEnabled(math.huge) end))
    local missing_ok,missing_error=pcall(function() h:GetStateEnabled() end)
    assert(not missing_ok and string.find(tostring(missing_error),'Argument 1 missing or nil',1,true))
    assert(not pcall(function() h:SetStateEnabled(state_type.Jumping) end))
    assert(not pcall(function() h:SetStateEnabled(nil,false) end))
    assert(select('#',h:ChangeState(nil))==0)
    -- Explicit scope guard, not a claim of native opaque-string parity.
    local ok, problem=pcall(function() h:SetStateEnabled('8',false) end)
    assert(not ok and string.find(problem,'not implemented',1,true))
    local remote=Instance.new('RemoteEvent',workspace)
    local function must_reject(fn)
        local ok, problem=pcall(fn)
        assert(not ok and string.find(problem,'remote enum transport is not implemented',1,true))
    end
    must_reject(function() remote:FireServer(state_type.Running) end)
    local send=remote.FireServer
    must_reject(function() send(remote,{nested={state_type.Running}}) end)
    local cycle={};cycle.self=cycle;cycle.item=state_type.Running
    must_reject(function() remote:FireServer(cycle) end)
end
local m=require(workspace.RoomModule)
assert(m==require(workspace.RoomModule))
m.count+=1
assert(m.count==1) -- module table/cache is local to this actual VM
state(m.get(h),'Running',8)
local connections={}
local calls={connect=0,extracted=0,lower=0,once=0,wait=0,lowerwait=0,module=0,enabled=0}
connections[#connections+1]=h.StateChanged:Connect(function(old,new)
    state(old,'Running',8);state(new,'Freefall',5)
    calls.connect+=1
    state(h:GetState(),'Freefall',5)
end)
local signal=h.StateChanged
local connect=signal.Connect
connections[#connections+1]=connect(signal,function(old,new)
    state(old,'Running',8);state(new,'Freefall',5);calls.extracted+=1
end)
local function lower_callback(old,new)
    state(old,'Running',8);state(new,'Freefall',5);calls.lower+=1
end
if parity then
    local lower=signal.connect
    connections[#connections+1]=lower(signal,lower_callback)
else
    connections[#connections+1]=signal:connect(lower_callback)
end
local once=signal.Once
connections[#connections+1]=once(signal,function(old,new)
    state(old,'Running',8);state(new,'Freefall',5);calls.once+=1
end)
connections[#connections+1]=m.connect(h,function(old,new)
    state(old,'Running',8);state(new,'Freefall',5);calls.module+=1
end)
connections[#connections+1]=h.StateEnabledChanged:Connect(function(item,enabled)
    state(item,'Jumping',3);assert(type(enabled)=='boolean');calls.enabled+=1
end)
connections[#connections+1]=h.Changed:Connect(function(...)
    assert(select('#',...)==3)
    local first,second,third=...
    assert(first==3 and second==false and third==nil)
    script:SetAttribute('TrailingNilConnect',true)
end)
task.spawn(function()
    local packed=table.pack(h.Changed:Wait())
    assert(packed.n==3 and packed[1]==3 and packed[2]==false and packed[3]==nil)
    script:SetAttribute('TrailingNilWait',true)
end)
task.spawn(function()
    local old,new
    if parity then
        local wait_method=signal.Wait
        old,new=wait_method(signal)
    else old,new=signal:Wait() end
    state(old,'Running',8);state(new,'Freefall',5);calls.wait+=1
end)
task.spawn(function()
    local old,new
    if parity then
        local wait_method=signal.wait
        old,new=wait_method(signal)
    else old,new=signal:wait() end
    state(old,'Running',8);state(new,'Freefall',5);calls.lowerwait+=1
end)
task.spawn(function()
    local item,enabled=h.StateEnabledChanged:Wait()
    state(item,'Jumping',3);assert(enabled==false)
    script:SetAttribute('EnabledWait',true)
end)
local task_count=0
local function task_finished()
    task_count+=1
    if task_count==6 then script:SetAttribute('TasksDone',true) end
end
local function after_yield()
    task.wait(0)
    state(h:GetState(),'Running',8)
    state(m.get(h),'Running',8)
    task_finished()
end
task.spawn(after_yield)
task.defer(after_yield)
task.delay(0.001,after_yield)
local thread=coroutine.create(function()
    coroutine.yield()
    state(h:GetState(),'Running',8)
    task_finished()
end)
assert(coroutine.resume(thread))
assert(coroutine.resume(thread))
coroutine.wrap(function() state(h:GetState(),'Running',8);task_finished() end)()
m.coroutine(h,function(value) state(value,'Running',8);task_finished() end)
saved={h=h,state=state,calls=calls,module=m,connections=connections}
function check_tasks() assert(task_count==6) end
function check_events(expected)
    assert(calls.connect==expected and calls.extracted==expected and calls.lower==expected and calls.module==expected)
    assert(calls.once==1 and calls.wait==1 and calls.lowerwait==1 and calls.enabled==2)
end
function disconnect_all()
    for _,connection in ipairs(connections) do connection:Disconnect() end
end
function check_profile()
    state(h:GetState(),'Freefall',5)
    state(m.get(h),'Freefall',5)
end
script:SetAttribute('Ready',true)
