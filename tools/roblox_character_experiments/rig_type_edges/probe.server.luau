-- Own native scalar probe. Targets are fresh disposable Humanoids only.
-- No Player Character, description/model factory, stock Source or assets used.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local Common=require(ReplicatedStorage:WaitForChild("RigTypeEdgesCommon"))
local config=HttpService:JSONDecode(ReplicatedStorage.RigTypeEdgesConfig.Value)
local registration=HttpService:JSONDecode(ReplicatedStorage.RigTypeEdgesRegistration.Value)
assert(not ReplicatedStorage:FindFirstChild("CharacterExperimentTelemetry"),"Own telemetry folder already exists; never overwrite a capture")
local folder=Instance.new("Folder")
folder.Name="CharacterExperimentTelemetry"
folder.Parent=ReplicatedStorage
local runID=HttpService:GenerateGUID(false)
folder:SetAttribute("run_id",runID)
local started=os.clock()
local sequence=0
local lines,errors,results={},{},{}
local finished=false
local activeCase="startup"
local activeHumanoid=nil
local activeConnections={}
local heartbeatIndex=0
local heartbeatSimElapsed=0
local lastHeartbeatDt=0
local heartbeatConnection=RunService.Heartbeat:Connect(function(dt)
    heartbeatIndex+=1
    heartbeatSimElapsed+=dt
    lastHeartbeatDt=dt
end)

local function clock()
    return {wall_s=os.clock()-started,heartbeat_index=heartbeatIndex,
        heartbeat_sim_elapsed_s=heartbeatSimElapsed,last_heartbeat_dt_sim_s=lastHeartbeatDt}
end

local function emit(kind,data)
    if finished then return nil end
    sequence+=1
    data=data or {}
    data.kind,data.schema,data.run_id,data.seq=kind,1,runID,sequence
    data.realm,data.case="server",activeCase
    data.clock=clock()
    table.insert(lines,"CHARACTER_EXPERIMENT_JSON "..HttpService:JSONEncode(data).."\n")
    return sequence
end

local function blocked(reason)
    table.insert(errors,reason)
    emit("blocked",{status="BLOCKED",reason=reason})
end

local function cleanup()
    for _,connection in ipairs(activeConnections) do connection:Disconnect() end
    activeConnections={}
    if activeHumanoid then activeHumanoid:Destroy();activeHumanoid=nil end
end

local function finish(reason)
    if finished then return end
    cleanup()
    heartbeatConnection:Disconnect()
    emit("run_result",{status=#errors==0 and "OBSERVED" or "BLOCKED",reason=reason,
        count=#results,planned_cases=#registration.cases,errors=errors,cases=results,
        independent_play_sessions=1,disposable_instances_are_not_independent_Play_sessions=true,
        no_parity_pass_claim=true,no_physical_rig_claim=true})
    finished=true
    local raw=table.concat(lines)
    for index=1,#raw,50000 do
        local value=Instance.new("StringValue")
        value.Name=string.format("%06d",math.floor((index-1)/50000)+1)
        value.Value=raw:sub(index,index+49999)
        value.Parent=folder
    end
    folder:SetAttribute("raw_bytes",#raw)
    folder:SetAttribute("records",sequence)
    folder:SetAttribute("status",#errors==0 and "OBSERVED" or "BLOCKED")
    folder:SetAttribute("complete",true)
    print("CHARACTER_EXPERIMENT_DONE "..HttpService:JSONEncode({run_id=runID,records=sequence,
        raw_bytes=#raw,cases=#results,status=folder:GetAttribute("status")}))
end

local function waitHeartbeat()
    local before=clock()
    local dt=RunService.Heartbeat:Wait()
    if finished then error("Own probe already finalized") end
    return {before=before,after=clock(),wait_callback_dt_sim_s=dt}
end

local function parameters(case)
    return {id=case.id,ordinal=case.ordinal,context=case.context,baseline=case.baseline,
        target=case.target,variant=case.variant,rig=case.target,split=config.split,
        path="FRESH_SCALAR_HUMANOID_ONLY"}
end

local function runCase(case)
    activeCase=case.id
    local params=parameters(case)
    emit("case_begin",{parameters=params,
        fresh_default_policy="The following new Humanoid's fresh RigType is an observation; R6 is not an asserted fixture input"})
    local humanoid=Instance.new("Humanoid")
    activeHumanoid=humanoid
    humanoid.Name="OwnRigTypeEdgeTarget"
    local freshUnparented=Common.getter(humanoid)
    if case.context=="fresh_workspace" then humanoid.Parent=workspace
    elseif case.context~="fresh_unparented" then error("Unregistered own context") end
    local freshContext=Common.getter(humanoid)
    emit("rig_type_fresh_observation",{parameters=params,unparented_getter=freshUnparented,
        context_getter=freshContext,fresh_default_policy="Native fresh RigType is observed; R6 is not an asserted fixture input",
        parent_policy=case.context=="fresh_workspace" and "Humanoid parent is Workspace; no Model, skeleton or body parts" or "Humanoid is unparented"})
    local baselineCallBefore=clock()
    local baselineSet=Common.setter(humanoid,Enum.HumanoidRigType[case.baseline])
    local baselineCallAfter=clock()
    local baselineImmediate=Common.getter(humanoid)
    local baselineWait=waitHeartbeat()
    local baselineSettled=Common.getter(humanoid)
    local baselineValid=freshUnparented.ok and freshContext.ok and baselineSet.ok and Common.matchesRig(baselineImmediate,case.baseline)
        and Common.matchesRig(baselineSettled,case.baseline)
    local baselineSeq=emit("rig_type_baseline_result",{parameters=params,setter=baselineSet,
        setter_call_before=baselineCallBefore,setter_call_after=baselineCallAfter,
        getter_immediate=baselineImmediate,getter_after_settle=baselineSettled,
        settle_Heartbeat=baselineWait,exact_tag_name_value_verified=baselineValid,
        baseline_signals_policy="Measured signal listeners attach only after baseline preparation and one settle Heartbeat"})
    if not baselineValid then
        local reason="Own baseline setter/getter unavailable or exact requested baseline not observed; no retry and no target setter"
        blocked(reason)
        local result={case=case.id,status="BLOCKED",parameters=params,reason=reason,
            baseline_seq=baselineSeq,target_setter_status="NOT_RUN",no_physical_rig_claim=true}
        table.insert(results,result);emit("case_result",result);cleanup();return
    end
    local counts={property_changed=0,changed_total=0,changed_rig_type=0}
    local eventSeqs={}
    local phase="before_setter"
    local eventOverflow=false
    local function copyCounts()
        return {property_changed=counts.property_changed,changed_total=counts.changed_total,
            changed_rig_type=counts.changed_rig_type}
    end
    local function event(signal,packed)
        -- A previously queued callback cannot become telemetry for a later
        -- case after cleanup/Disconnect and a new target have been installed.
        if finished or activeHumanoid~=humanoid then return end
        if signal=="GetPropertyChangedSignal" then counts.property_changed+=1
        else
            counts.changed_total+=1
            if packed[1]=="RigType" then counts.changed_rig_type+=1 end
        end
        if #eventSeqs>=registration.limits.recorded_events_per_case then
            if not eventOverflow then
                eventOverflow=true;blocked("Own event-record cap exceeded; counts retained, event stream incomplete")
            end
            return
        end
        table.insert(eventSeqs,emit("rig_type_event",{parameters=params,signal=signal,phase=phase,
            arguments=Common.tuple(packed),getter=Common.getter(humanoid),counts=copyCounts()}))
    end
    table.insert(activeConnections,humanoid:GetPropertyChangedSignal("RigType"):Connect(function(...)
        event("GetPropertyChangedSignal",table.pack(...))
    end))
    table.insert(activeConnections,humanoid.Changed:Connect(function(...)
        event("Changed",table.pack(...))
    end))
    local observations={}
    local missingGetter=false
    local function observe(point,wait)
        local getter=Common.getter(humanoid)
        if not getter.ok then missingGetter=true end
        local seq=emit("rig_type_observation",{parameters=params,point=point,phase=phase,
            getter=getter,counts=copyCounts(),Heartbeat_wait=wait})
        table.insert(observations,{point=point,seq=seq})
    end
    observe("before_setter")
    local argument=Common.argument(case.variant,case.target)
    local input=Common.safe(argument)
    local attemptSeq=emit("rig_type_setter_attempt",{parameters=params,input=input,
        target_policy="Target labels select the input basis, never an asserted resulting getter"})
    phase="setter_call"
    local callBefore=clock()
    local setter=Common.setter(humanoid,argument)
    local callAfter=clock()
    phase="after_setter_return"
    local returnSeq=emit("rig_type_setter_return",{parameters=params,input=input,setter=setter,
        setter_call_before=callBefore,setter_call_after=callAfter,
        counts=copyCounts(),getter=Common.getter(humanoid)})
    observe("immediate_after_setter")
    for ordinal=1,registration.observation_Heartbeats_after_setter do
        local wait=waitHeartbeat()
        phase="after_Heartbeat_"..tostring(ordinal)
        observe(phase,wait)
    end
    if missingGetter then blocked("Measured getter unavailable in required observation window") end
    local result={case=case.id,status=(eventOverflow or missingGetter) and "BLOCKED" or "OBSERVED",
        parameters=params,baseline_seq=baselineSeq,setter_attempt_seq=attemptSeq,setter_return_seq=returnSeq,
        observation_seqs=observations,event_seqs=eventSeqs,final_counts=copyCounts(),setter_ok=setter.ok,
        setter_error_is_an_observation=true,event_stream_truncated=eventOverflow,
        no_physical_rig_claim=true,no_parity_pass_claim=true}
    table.insert(results,result);emit("case_result",result)
    cleanup()
end

emit("run_manifest",{mode="rig_type_edges_a3",studio_version=version(),date_utc=DateTime.now():ToIsoDate(),
    config=config,registration=registration,units={wall="os.clock seconds since own probe start",
        simulation="Actual Heartbeat dt and accumulated callback dt; no fixed framerate assumed",
        render="NOT_OBSERVABLE server-only; no render-time claim"},
    source_policy="Only own fresh Humanoids and own telemetry; no stock Source, assets, keyframes or Player.Character access",
    scope="Scalar getter/coercion/event observations only; no physical rig/skeleton/Player behavior interpretation",
    fresh_default_policy="Fresh getter is observed for every instance; an R6 result is never asserted as a fixture input",
    event_policy="Event timestamps and ordering are observations. Counts are not presumed; delayed callbacks outside the two-Heartbeat window are not ruled out."})

task.delay(registration.timeouts.session_wall_s,function()
    if not finished then blocked("Own session watchdog reached; partial capture retained, no retry");finish("watchdog") end
end)
task.defer(function()
    for _,case in ipairs(registration.cases) do
        if finished then return end
        local ok,reason=xpcall(function()runCase(case)end,function(value)return Common.reason(value)end)
        if not ok and not finished then
            blocked("Own case probe error: "..reason)
            local result={case=case.id,status="BLOCKED",parameters=parameters(case),reason=reason,
                target_setter_status="NOT_OBSERVABLE after probe exception",no_physical_rig_claim=true}
            table.insert(results,result);emit("case_result",result);cleanup()
        end
    end
    if not finished then finish("All preregistered fresh scalar cases attempted exactly once") end
end)
