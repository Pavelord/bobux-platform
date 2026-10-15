-- Own black-box probe only. Run in a Play Command Bar; never touches Player.Character.
-- Unparented Humanoids measure method conversion/receivers/enabled signals only.
-- ChangeState return/getter observations here do NOT establish physical state behavior.
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local EncodingService=game:GetService("EncodingService")
assert(RunService:IsRunning(),"Play required for the explicit two-Heartbeat observation window")
local runID=HttpService:GenerateGUID(false)
local started=os.clock()
local rows={}
local states=Enum.HumanoidStateType:GetEnumItems()
local running=Enum.HumanoidStateType.Running
local windowFrames=2
local function safe(v)
    local t=typeof(v)
    if t=="nil" then return {type=t,is_nil=true} end
    if t=="EnumItem" then return {type=t,Name=v.Name,Value=v.Value,EnumType=tostring(v.EnumType)} end
    if t=="Instance" then return {type=t,class=v.ClassName,name=v.Name} end
    if t=="string" or t=="boolean" then return {type=t,value=v} end
    if t=="number" then return {type=t,value=(v==v and math.abs(v)<math.huge) and v or tostring(v)} end
    return {type=t,lua_type=type(v)}
end
local function packedSafe(p)
    local out={n=p.n,values={}}
    for i=1,p.n do table.insert(out.values,safe(p[i])) end
    return out
end
local function call(fn)
    local result=table.pack(pcall(fn))
    local out={ok=result[1],returns={}}
    if result[1] then
        out.return_count=result.n-1
        for i=2,result.n do table.insert(out.returns,safe(result[i])) end
    else out.error=tostring(result[2]) end
    return out
end
local function add(row)
    row.seq=#rows+1
    row.run_id=runID
    row.status="OBSERVED"
    rows[#rows+1]=row
end
local function flags(h,raw)
    local out={canonical={}}
    for _,state in ipairs(states) do
        out.canonical[#out.canonical+1]={Name=state.Name,Value=state.Value,result=call(function() return h:GetStateEnabled(state) end)}
    end
    out.raw_getter=call(function() return h:GetStateEnabled(raw) end)
    out.state_getter=call(function() return h:GetState() end)
    return out
end
local function drain()
    local elapsed={}
    for i=1,windowFrames do elapsed[i]=RunService.Heartbeat:Wait() end
    return elapsed
end
local function watch(h,label,events,phase)
    return h.StateEnabledChanged:Connect(function(...)
        events[#events+1]={seq=#events+1,humanoid=label,phase=phase.value,wall_s=os.clock()-started,args=packedSafe(table.pack(...))}
    end)
end
add({kind="manifest",schema=1,date_utc=DateTime.now():ToIsoDate(),studio_version=version(),
    fixture="fresh unparented Humanoids and one unparented wrong-class Part per method case",
    policy="Own methods/signals only; no Player.Character, Source, assets, settings, or scene mutation",
    interpretation="Method conversion and enabled flags only; ChangeState physical behavior NOT_OBSERVABLE in this fixture",
    signal_window={heartbeats=windowFrames,scope="immediate + bounded subsequent Heartbeats; no claim about callbacks beyond window"}})
local enabledCases={
    {id="numeric_string",value="8"},
    {id="full_enum_string",value="Enum.HumanoidStateType.Running"},
    {id="unknown_string",value="BOBUX_NONEXISTENT_ITEM"},
    {id="canonical_name_control",value="Running"},
    {id="canonical_item_control",value=running},
    {id="canonical_number_control",value=8},
}
for _,case in ipairs(enabledCases) do
    local h=Instance.new("Humanoid")
    h.Name="OwnEnabledCase_"..case.id
    local events={}
    local phase={value="before"}
    local connection=watch(h,"target",events,phase)
    local row={kind="enabled_string",id=case.id,raw_arg=safe(case.value),before=flags(h,case.value),operations={},events=events}
    for _,enabled in ipairs({false,true}) do
        local operation={enabled=enabled,event_start=#events}
        phase.value=enabled and "set_true_immediate" or "set_false_immediate"
        operation.call=call(function() h:SetStateEnabled(case.value,enabled) end)
        operation.immediate=flags(h,case.value)
        operation.events_after_immediate=#events
        phase.value=enabled and "set_true_window" or "set_false_window"
        operation.heartbeat_dt=drain()
        operation.after_window=flags(h,case.value)
        operation.events_after_window=#events
        row.operations[#row.operations+1]=operation
    end
    connection:Disconnect()
    h:Destroy()
    add(row)
end
local methods={"ChangeState","GetState","GetStateEnabled","SetStateEnabled"}
local function validArgs(method)
    if method=="GetState" then return table.pack() end
    if method=="SetStateEnabled" then return table.pack(running,false) end
    return table.pack(running)
end
local arities={
    {id="missing",args=table.pack()},
    {id="one_nil",args=table.pack(nil)},
    {id="state_only",args=table.pack(running)},
    {id="state_nil",args=table.pack(running,nil)},
    {id="state_false",args=table.pack(running,false)},
    {id="state_true",args=table.pack(running,true)},
    {id="state_false_trailing_nil",args=table.pack(running,false,nil)},
    {id="state_false_extra",args=table.pack(running,false,"OWN_EXTRA")},
    {id="nil_false",args=table.pack(nil,false)},
    {id="nil_nil",args=table.pack(nil,nil)},
    {id="nil_false_extra",args=table.pack(nil,false,"OWN_EXTRA")},
    {id="state_nil_extra",args=table.pack(running,nil,"OWN_EXTRA")},
}
local receivers={"correct","other_humanoid","omitted","shifted","explicit_nil","table","part","number","enum_item"}
local function methodCase(method,category,id,args,receiverKind)
    local target=Instance.new("Humanoid")
    local other=Instance.new("Humanoid")
    local wrongPart=Instance.new("Part")
    target.Name="OwnMethodTarget"
    other.Name="OwnMethodOther"
    wrongPart.Name="OwnWrongReceiver"
    local events={}
    local phase={value="before"}
    local connections={watch(target,"target",events,phase),watch(other,"other",events,phase)}
    local fn=target[method]
    local row={kind="method_call",method=method,category=category,id=id,method_value=safe(fn),args=packedSafe(args),
        receiver=receiverKind,before={target=flags(target,running),other=flags(other,running)},events=events}
    local receiver=target
    if receiverKind=="other_humanoid" then receiver=other
    elseif receiverKind=="explicit_nil" then receiver=nil
    elseif receiverKind=="table" then receiver={}
    elseif receiverKind=="part" then receiver=wrongPart
    elseif receiverKind=="number" then receiver=8
    elseif receiverKind=="enum_item" then receiver=running end
    row.receiver_value=safe(receiver)
    phase.value="invoke_immediate"
    row.call=call(function()
        if receiverKind=="omitted" then return fn() end
        if receiverKind=="shifted" then return fn(table.unpack(args,1,args.n)) end
        return fn(receiver,table.unpack(args,1,args.n))
    end)
    row.immediate={target=flags(target,running),other=flags(other,running)}
    row.events_after_immediate=#events
    phase.value="invoke_window"
    row.heartbeat_dt=drain()
    row.after_window={target=flags(target,running),other=flags(other,running)}
    row.events_after_window=#events
    for _,connection in ipairs(connections) do connection:Disconnect() end
    target:Destroy()
    other:Destroy()
    wrongPart:Destroy()
    add(row)
end
for _,method in ipairs(methods) do
    for _,receiver in ipairs(receivers) do methodCase(method,"receiver",receiver,validArgs(method),receiver) end
    for _,case in ipairs(arities) do methodCase(method,"arity",case.id,case.args,"correct") end
end
local raw=HttpService:JSONEncode({schema=1,kind="humanoid_edge_results",run_id=runID,rows=rows,
    no_expected_outcomes=true,status="OBSERVED",date_utc=DateTime.now():ToIsoDate(),studio_version=version(),
    enabled_cases=#enabledCases,receiver_cases=#methods*#receivers,arity_cases=#methods*#arities,
    wall_seconds=os.clock()-started})
local rawBuffer=buffer.fromstring(raw)
local hash=EncodingService:ComputeBufferHash(rawBuffer,Enum.HashAlgorithm.Sha256)
assert(buffer.len(hash)==32,"unexpected SHA256 length")
local hex={}
for i=0,31 do hex[#hex+1]=string.format("%02x",buffer.readu8(hash,i)) end
local encoded=buffer.tostring(EncodingService:Base64Encode(rawBuffer))
local packets=0
local maxLineBytes=0
for offset=1,#encoded,400 do
    packets+=1
    local line="HUMANOID_EDGE_EXPORT "..HttpService:JSONEncode({schema=1,run_id=runID,seq=packets,i=offset,s=encoded:sub(offset,offset+399)})
    assert(#line<=700,"own export line exceeds 700 bytes")
    maxLineBytes=math.max(maxLineBytes,#line)
    print(line)
    if packets%64==0 then task.wait() end
end
local done="HUMANOID_EDGE_DONE "..HttpService:JSONEncode({schema=1,run_id=runID,records=#rows,packets=packets,
    raw_bytes=#raw,encoded_bytes=#encoded,raw_sha256=table.concat(hex),encoding="base64",packet_bytes=400,
    max_export_line_bytes=maxLineBytes,status="OBSERVED",enabled_cases=#enabledCases,receiver_cases=#methods*#receivers,
    arity_cases=#methods*#arities,date_utc=DateTime.now():ToIsoDate(),studio_version=version()})
assert(#done<=700,"own completion line exceeds 700 bytes")
print(done)
