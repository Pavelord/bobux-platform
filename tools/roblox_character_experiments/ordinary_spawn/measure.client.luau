-- Bobux-authored paired client observations. Standard controls/Animate remain intact.
local Players=game:GetService("Players")
local StarterPlayer=game:GetService("StarterPlayer")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local Common=require(ReplicatedStorage:WaitForChild("OrdinarySpawnCommon",15))
local config=HttpService:JSONDecode(ReplicatedStorage:WaitForChild("OrdinarySpawnConfig",15).Value)
local registration=HttpService:JSONDecode(ReplicatedStorage:WaitForChild("OrdinarySpawnRegistration",15).Value)
local serverFolder=ReplicatedStorage:WaitForChild("OrdinarySpawnServerTelemetry",15)
local command=ReplicatedStorage:WaitForChild("OrdinarySpawnCommand",15)
local runID=serverFolder:GetAttribute("run_id")
local started=os.clock()
local folder=Instance.new("Folder");folder.Name="CharacterExperimentTelemetry";folder:SetAttribute("run_id",runID);folder.Parent=ReplicatedStorage
local sequence=0
local done=false
local finishing=false
local stage="join"
local lines,errors,results={},{},{}
local snapshots={}
local connections={}
local generations=setmetatable({},{__mode="k"})
local characterAddedAt=setmetatable({},{__mode="k"})
local lifecycleCounts={CharacterAdded=0,CharacterRemoving=0,CharacterAppearanceLoaded=0}
local localGeneration=0
local function emit(kind,data)
    if done then return end
    data=data or {};sequence+=1
    data.kind,data.schema,data.run_id,data.seq=kind,1,runID,sequence
    data.realm,data.wall_s,data.case="client",os.clock()-started,stage
    table.insert(lines,"CHARACTER_EXPERIMENT_JSON "..HttpService:JSONEncode(data).."\n")
end
local function blocked(reason)
    table.insert(errors,reason);emit("blocked",{status="BLOCKED",reason=reason})
end
local function invoke(operation,index,limit)
    local complete,ok,response=false,false,nil
    task.spawn(function()ok,response=pcall(function()return command:InvokeServer(operation,index)end);complete=true end)
    local deadline=os.clock()+(limit or 22)
    while not complete and not done and os.clock()<deadline do RunService.Heartbeat:Wait() end
    if not complete then return {ok=false,error="remote operation watchdog: "..operation} end
    return ok and response or {ok=false,error=Common.reason(response)}
end
local function flush()
    local raw=table.concat(lines)
    for i=1,#raw,50000 do
        local value=Instance.new("StringValue");value.Name=string.format("%06d",math.floor((i-1)/50000)+1);value.Value=raw:sub(i,i+49999);value.Parent=folder
    end
    folder:SetAttribute("raw_bytes",#raw);folder:SetAttribute("records",sequence);folder:SetAttribute("status",#errors==0 and "OBSERVED" or "BLOCKED");folder:SetAttribute("complete",true)
end
local function finish(reason)
    if done or finishing then return end
    finishing=true
    local response=invoke("finish",nil,5)
    if not response or not response.ok then blocked("server finalization not confirmed") end
    local deadline=os.clock()+5
    local raw=""
    repeat
        local chunks=serverFolder:GetChildren();table.sort(chunks,function(a,b)return a.Name<b.Name end)
        local values={};for _,value in ipairs(chunks) do if value:IsA("StringValue") then table.insert(values,value.Value) end end
        raw=table.concat(values)
        if serverFolder:GetAttribute("complete") and #raw==serverFolder:GetAttribute("raw_bytes") then break end
        RunService.Heartbeat:Wait()
    until os.clock()>=deadline
    if not serverFolder:GetAttribute("complete") or #raw~=serverFolder:GetAttribute("raw_bytes") then
        blocked("server telemetry replication/completion missing")
    else
        local imported=0
        for line in raw:gmatch("[^\n]+") do
            local ok,row=pcall(function()return HttpService:JSONDecode(line:sub(#"CHARACTER_EXPERIMENT_JSON "+1))end)
            if ok then imported+=1;emit("server_record",{server=row}) else blocked("server telemetry JSON invalid") end
        end
        if imported~=serverFolder:GetAttribute("records") then blocked("server telemetry record count differs") end
        if serverFolder:GetAttribute("status")=="BLOCKED" then blocked("server recorded a blocked condition; inspect nested server rows") end
    end
    emit("run_result",{status=#errors==0 and "OBSERVED" or "BLOCKED",reason=reason,cases=results,count=#results,errors=errors,lifecycle_counts=lifecycleCounts,
        requested_rig=config.requested_rig,independent_play_session=config.session_index,initial_join_case=config.id,no_parity_pass_claim=true,
        scope="One Play session; ten native Character generations are repeated respawns, never ten independent joins"})
    done=true
    for _,connection in ipairs(connections) do connection:Disconnect() end
    flush()
    print("CHARACTER_EXPERIMENT_DONE "..HttpService:JSONEncode({run_id=runID,records=sequence,raw_bytes=folder:GetAttribute("raw_bytes"),cases=#results,status=folder:GetAttribute("status")}))
end
local function snapshot(character,point,token,age,callbackDt)
    local data={point=point,token=token,requested_age_s=age,character_generation=generations[character],server_generation=character:GetAttribute("OrdinarySpawnGeneration"),
        actual_age_wall_s=characterAddedAt[character] and os.clock()-characterAddedAt[character] or nil,callback_dt_sim_s=callbackDt,
        current_character_same=player.Character==character,starter_player=Common.props(StarterPlayer,Common.starterKeys),player_properties=Common.props(player,Common.playerKeys),
        character=Common.character(character),contamination=Common.contamination(StarterPlayer),rollouts=Common.rollouts()}
    snapshots[token]=snapshots[token] or {};snapshots[token][point]=data
    emit("a2_ordinary_snapshot",data)
end
local function connectCharacter(character)
    lifecycleCounts.CharacterAdded+=1
    localGeneration+=1;generations[character]=localGeneration
    local at=os.clock();local token=stage
    characterAddedAt[character]=at
    emit("a2_lifecycle",{event="CharacterAdded",token=token,character_generation=localGeneration})
    local seen={}
    local function milestone(item,already)
        local key
        if item:IsA("Humanoid") then key="Humanoid"
        elseif item.Name=="HumanoidRootPart" and item:IsA("BasePart") then key="HRP"
        elseif item:IsA("Animator") then key="Animator"
        elseif item.Name=="Animate" and item:IsA("LuaSourceContainer") then key="Animate" end
        if key and not seen[key] then seen[key]=true;emit("a2_milestone",{token=token,milestone=key,character_generation=generations[character],already_present_at_attachment=already,delay_wall_s=os.clock()-at,class=item.ClassName}) end
    end
    for _,item in ipairs(character:GetDescendants()) do milestone(item,true) end
    local descendants=character.DescendantAdded:Connect(function(item)milestone(item,false)end);table.insert(connections,descendants)
    snapshot(character,"CharacterAdded_immediate",token,0)
    RunService.PostSimulation:Once(function(dt)if not done then snapshot(character,"first_PostSimulation",token,nil,dt) end end)
    for _,age in ipairs(registration.snapshot_delays_wall_s) do
        task.delay(age,function()
            if done or finishing then return end
            snapshot(character,"after_"..tostring(age).."s",token,age)
            if age==3 then
                descendants:Disconnect()
                emit("a2_standard_script_inventory",{token=token,character_generation=generations[character],character_scripts=Common.inventory(character),player_scripts=Common.inventory(player:FindFirstChild("PlayerScripts"))})
            end
        end)
    end
end
emit("run_manifest",{mode="ordinary_spawn_a2",studio_version=version(),date_utc=DateTime.now():ToIsoDate(),config=config,registration=registration,
    units={time="seconds; wall=os.clock"},source_policy="Stock Source/assets/keyframes/IDs never accessed or exported; only public values and script inventory metadata",rollouts=Common.rollouts()})
table.insert(connections,player.CharacterAdded:Connect(connectCharacter))
table.insert(connections,player.CharacterRemoving:Connect(function(character)lifecycleCounts.CharacterRemoving+=1;emit("a2_lifecycle",{event="CharacterRemoving",character_generation=generations[character]})end))
table.insert(connections,player.CharacterAppearanceLoaded:Connect(function(character)lifecycleCounts.CharacterAppearanceLoaded+=1;emit("a2_lifecycle",{event="CharacterAppearanceLoaded",character_generation=generations[character],appearance_disabled_in_fixture=true})end))
emit("a2_client_probe_attached",{player_properties=Common.props(player,Common.playerKeys),starter_player=Common.props(StarterPlayer,Common.starterKeys),character_already_present=player.Character~=nil})
if player.Character then blocked("Character existed before client probe attached; controlled initial spawn not observed") end
task.delay(registration.timeouts.session_wall_s,function()if not done then blocked("global client session watchdog 300s");finish("watchdog") end end)
task.spawn(function()
    local ok,problem=xpcall(function()
        local ready=invoke("ready",nil,15)
        if not ready or not ready.ok or ready.run_id~=runID then blocked("server not ready or run mismatch");finish("blocked startup");return end
        if Common.contamination(StarterPlayer).status=="BLOCKED" then blocked("StarterCharacter/StarterHumanoid contamination");finish("blocked startup");return end
        for index=1,10 do
            if done or finishing then return end
            if index==6 then
                local changed=invoke("mutate_starter_only",nil,15)
                if not changed or not changed.ok then blocked("StarterPlayer-only mutation failed");finish("blocked mutation");return end
                emit("a2_after_join_mutation_confirmed",{starter_player=Common.props(StarterPlayer,Common.starterKeys),player_properties=Common.props(player,Common.playerKeys),character=Common.character(player.Character)})
            end
            stage="spawn_"..tostring(index)
            emit("case_begin",{parameters={rig=config.requested_rig,split=config.split,path="NATIVE_DEFAULT",spawn_index=index,phase=index<=5 and "prejoin_profile" or "post_join_mutation"}})
            local loaded=invoke("load",index,22)
            if not loaded or not loaded.ok then blocked(loaded and loaded.error or "load response missing");finish("blocked load");return end
            local deadline=os.clock()+registration.timeouts.snapshot_window_wall_s
            while not done and os.clock()<deadline and not (snapshots[stage] and snapshots[stage].after_3s) do RunService.Heartbeat:Wait() end
            local rows=snapshots[stage];local actual=rows and rows.after_3s and rows.after_3s.character.actual_rig or "NOT_OBSERVABLE"
            local status="OBSERVED";local reasons={}
            for _,point in ipairs(registration.required_snapshot_points) do
                if not rows or not rows[point] then table.insert(reasons,"missing client snapshot "..point) end
            end
            if actual~=config.requested_rig then table.insert(reasons,"requested rig "..config.requested_rig.." unavailable; actual "..actual.."; no custom rig fallback") end
            local last=rows and rows.after_3s
            if not last or not last.current_character_same or not last.character.has_humanoid or not last.character.has_hrp or type(last.character.humanoid.Health)~="number" or last.character.humanoid.Health<=0 then
                table.insert(reasons,"live Character/Humanoid/HRP missing or dead at +3s")
            end
            if localGeneration~=index or (last and last.server_generation~=loaded.generation) then table.insert(reasons,"client/server Character generation mismatch") end
            local barrier=invoke("barrier",stage,5)
            if not barrier or not barrier.ok or not barrier.complete then table.insert(reasons,"server +3s snapshot barrier incomplete") end
            if #reasons>0 then status="BLOCKED";blocked(table.concat(reasons,"; ")) end
            local result={case=stage,status=status,actual_rig=actual,server_generation=loaded.generation,local_generation=localGeneration,reason=#reasons>0 and table.concat(reasons,"; ") or nil,
                parameters={rig=config.requested_rig,split=config.split,path="NATIVE_DEFAULT",spawn_index=index,phase=index<=5 and "prejoin_profile" or "post_join_mutation"},no_parity_pass_claim=true}
            table.insert(results,result);emit("case_result",result)
        end
        finish("ten native loads completed")
    end,function(value)return Common.reason(value)end)
    if not ok then blocked("client probe error: "..problem);finish("probe error") end
end)
