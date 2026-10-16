-- Isolated native Player:LoadCharacterAsync experiment. No custom Character path.
local Players=game:GetService("Players")
local StarterPlayer=game:GetService("StarterPlayer")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local Common=require(ReplicatedStorage:WaitForChild("OrdinarySpawnCommon"))
local config=HttpService:JSONDecode(ReplicatedStorage.OrdinarySpawnConfig.Value)
local registration=HttpService:JSONDecode(ReplicatedStorage.OrdinarySpawnRegistration.Value)
local runID=HttpService:GenerateGUID(false)
local started=os.clock()
local folder=Instance.new("Folder");folder.Name="OrdinarySpawnServerTelemetry";folder:SetAttribute("run_id",runID);folder.Parent=ReplicatedStorage
local command=Instance.new("RemoteFunction");command.Name="OrdinarySpawnCommand";command.Parent=ReplicatedStorage
local sequence=0
local finished=false
local busy=false
local abort=false
local loaded=0
local generation=0
local activeCase="join"
local errors={}
local lines={}
local playerStates={}
local generations=setmetatable({},{__mode="k"})
local characterAddedAt=setmetatable({},{__mode="k"})
local lifecycleCounts={CharacterAdded=0,CharacterRemoving=0,CharacterAppearanceLoaded=0}
local windowComplete={}
local windowSnapshots={}
local expectedGenerations={}
local currentPlayer=nil
local function emit(kind,data)
    if finished then return end
    data=data or {};sequence+=1
    data.kind,data.schema,data.run_id,data.seq=kind,1,runID,sequence
    data.realm,data.wall_s,data.case="server",os.clock()-started,activeCase
    table.insert(lines,"CHARACTER_EXPERIMENT_JSON "..HttpService:JSONEncode(data).."\n")
end
local function blocked(reason)
    table.insert(errors,reason);emit("blocked",{status="BLOCKED",reason=reason})
end
local function finish(reason)
    if finished then return end
    emit("run_result",{status=#errors==0 and "OBSERVED" or "BLOCKED",reason=reason,loaded_characters=loaded,errors=errors,lifecycle_counts=lifecycleCounts,
        client_telemetry="NOT_OBSERVABLE in server-only fallback; use completed client export for paired realms",no_parity_pass_claim=true})
    finished=true;abort=true
    local raw=table.concat(lines)
    for i=1,#raw,50000 do
        local value=Instance.new("StringValue");value.Name=string.format("%06d",math.floor((i-1)/50000)+1);value.Value=raw:sub(i,i+49999);value.Parent=folder
    end
    folder:SetAttribute("raw_bytes",#raw);folder:SetAttribute("records",sequence);folder:SetAttribute("status",#errors==0 and "OBSERVED" or "BLOCKED");folder:SetAttribute("complete",true)
end
local function snapshot(player,character,point,token,age,callbackDt)
    local data={point=point,token=token,requested_age_s=age,character_generation=generations[character],
        actual_age_wall_s=characterAddedAt[character] and os.clock()-characterAddedAt[character] or nil,callback_dt_sim_s=callbackDt,
        current_character_same=character~=nil and player.Character==character,starter_player=Common.props(StarterPlayer,Common.starterKeys),
        player_properties=Common.props(player,Common.playerKeys),character=Common.character(character),contamination=Common.contamination(StarterPlayer),rollouts=Common.rollouts()}
    windowSnapshots[token]=windowSnapshots[token] or {};windowSnapshots[token][point]=data
    emit("a2_ordinary_snapshot",data)
end
local function validateWindow(token)
    local rows=windowSnapshots[token]
    local reasons={}
    for _,point in ipairs(registration.required_snapshot_points) do
        if not rows or not rows[point] then table.insert(reasons,"missing server snapshot "..point) end
    end
    local last=rows and rows.after_3s
    -- Early snapshots may truthfully lack Humanoid/HRP. Only +3s is readiness.
    if not last or last.character_generation~=expectedGenerations[token] or not last.current_character_same
        or not last.character.has_humanoid or not last.character.has_hrp
        or type(last.character.humanoid.Health)~="number" or last.character.humanoid.Health<=0 then
        table.insert(reasons,"server +3s Character generation/current instance/readiness mismatch")
    end
    windowComplete[token]=#reasons==0
    emit("a2_server_window_validation",{token=token,status=windowComplete[token] and "OBSERVED" or "BLOCKED",reasons=reasons,expected_generation=expectedGenerations[token]})
    if #reasons>0 then blocked(table.concat(reasons,"; ")) end
    return windowComplete[token],reasons
end
local function connectPlayer(player,attachment)
    if playerStates[player] then return end
    currentPlayer=currentPlayer or player
    if currentPlayer~=player then blocked("more than one Player; isolated single-client fixture required");return end
    playerStates[player]={}
    emit("a2_player_join",{attachment=attachment,initial_join_event_observed=attachment=="PlayerAdded",player_properties=Common.props(player,Common.playerKeys),
        starter_player=Common.props(StarterPlayer,Common.starterKeys),contamination=Common.contamination(StarterPlayer)})
    if attachment~="PlayerAdded" then blocked("Player existed before server probe attached: initial join event timing not observed") end
    player.CharacterRemoving:Connect(function(character)
        lifecycleCounts.CharacterRemoving+=1
        emit("a2_lifecycle",{event="CharacterRemoving",character_generation=generations[character],player_character_same=player.Character==character})
    end)
    player.CharacterAppearanceLoaded:Connect(function(character)
        lifecycleCounts.CharacterAppearanceLoaded+=1
        emit("a2_lifecycle",{event="CharacterAppearanceLoaded",character_generation=generations[character],appearance_disabled_in_fixture=true})
    end)
    player.CharacterAdded:Connect(function(character)
        lifecycleCounts.CharacterAdded+=1
        generation+=1;generations[character]=generation
        local observedAt=os.clock();local token=activeCase
        expectedGenerations[token]=generation
        characterAddedAt[character]=observedAt
        character:SetAttribute("OrdinarySpawnGeneration",generation)
        emit("a2_lifecycle",{event="CharacterAdded",character_generation=generation,token=token})
        local seen={}
        local function milestone(item,alreadyPresent)
            local key
            if item:IsA("Humanoid") then key="Humanoid"
            elseif item.Name=="HumanoidRootPart" and item:IsA("BasePart") then key="HRP"
            elseif item:IsA("Animator") then key="Animator"
            elseif item.Name=="Animate" and item:IsA("LuaSourceContainer") then key="Animate" end
            if key and not seen[key] then
                seen[key]=true;emit("a2_milestone",{milestone=key,already_present_at_attachment=alreadyPresent,delay_wall_s=os.clock()-observedAt,character_generation=generations[character],token=token,class=item.ClassName})
            end
        end
        for _,item in ipairs(character:GetDescendants()) do milestone(item,true) end
        local descendants=character.DescendantAdded:Connect(function(item)milestone(item,false)end)
        snapshot(player,character,"CharacterAdded_immediate",token,0)
        RunService.PostSimulation:Once(function(dt)snapshot(player,character,"first_PostSimulation",token,nil,dt)end)
        for _,age in ipairs(registration.snapshot_delays_wall_s) do
            task.delay(age,function()
                if finished then return end
                snapshot(player,character,"after_"..tostring(age).."s",token,age)
                if age==3 then
                    descendants:Disconnect()
                    emit("a2_standard_script_inventory",{token=token,character_generation=generations[character],character_scripts=Common.inventory(character),player_scripts=Common.inventory(player:FindFirstChild("PlayerScripts"))})
                end
            end)
        end
    end)
    if player.Character then blocked("Character existed before controlled native load; auto-spawn/fixture contamination") end
end
emit("run_manifest",{mode="ordinary_spawn_a2",studio_version=version(),date_utc=DateTime.now():ToIsoDate(),config=config,registration=registration,
    player_spawn_method="Player:LoadCharacterAsync()",character_auto_loads=Players.CharacterAutoLoads,starter_player=Common.props(StarterPlayer,Common.starterKeys),
    units={time="seconds; wall=os.clock; snapshot timing uses actual callbacks"},rollouts=Common.rollouts(),source_policy="Only own telemetry; no stock Source, keyframes or asset IDs accessed/exported",
    requested_avatar_setting={status="NOT_OBSERVABLE",reason="Fixture sets no rig/Avatar hidden setting. Native actual RigType is authoritative; mismatch is BLOCKED."}})
Players.PlayerAdded:Connect(function(player)connectPlayer(player,"PlayerAdded")end)
for _,player in ipairs(Players:GetPlayers()) do connectPlayer(player,"late_attach") end
if Players.CharacterAutoLoads then blocked("CharacterAutoLoads must already be false in place before Player joins");abort=true end
if Common.contamination(StarterPlayer).status=="BLOCKED" then blocked("StarterCharacter/StarterHumanoid contamination");abort=true end
for key,expected in pairs(config.prejoin_values) do
    local ok,actual=pcall(function()return StarterPlayer[key]end)
    local matches=ok and (type(expected)=="number" and type(actual)=="number" and math.abs(actual-expected)<=registration.tolerances.scalar_numeric_abs or type(expected)=="boolean" and actual==expected)
    if not matches then blocked("prejoin XML setting not observed: "..key);abort=true end
end
command.OnServerInvoke=function(player,operation,index)
    if currentPlayer~=player or not playerStates[player] then return {ok=false,error="unregistered Player"} end
    if operation=="ready" then return {ok=not abort,run_id=runID,config=config,loaded=loaded} end
    if operation=="finish" then finish("client requested finalization");return {ok=true} end
    if finished or abort then return {ok=false,error="session finished/aborted"} end
    if operation=="barrier" then
        local deadline=os.clock()+1
        local function allPoints()
            local rows=windowSnapshots[index]
            for _,point in ipairs(registration.required_snapshot_points) do if not rows or not rows[point] then return false end end
            return true
        end
        while not allPoints() and not finished and os.clock()<deadline do RunService.Heartbeat:Wait() end
        local complete,reasons=validateWindow(index)
        return {ok=true,complete=complete,reasons=reasons}
    end
    if operation=="mutate_starter_only" then
        if busy or loaded~=5 then return {ok=false,error="mutation requires exactly five completed native loads"} end
        snapshot(player,player.Character,"live_before_StarterPlayer_mutation","mutation",nil)
        for key,value in pairs(registration.post_join_values) do
            local ok,reason=pcall(function()StarterPlayer[key]=value end)
            emit("a2_starter_mutation",{property=key,requested=Common.safe(value),ok=ok,error=not ok and Common.reason(reason) or nil})
            if not ok then blocked("StarterPlayer mutation unavailable: "..key);abort=true end
        end
        snapshot(player,player.Character,"live_after_StarterPlayer_mutation","mutation",nil)
        return {ok=not abort}
    end
    if operation~="load" or busy or type(index)~="number" or index~=loaded+1 or index>10 then return {ok=false,error="invalid/sequential-only native load request"} end
    if index>1 and not windowComplete["spawn_"..tostring(index-1)] then return {ok=false,error="previous observation window incomplete"} end
    if Common.contamination(StarterPlayer).status=="BLOCKED" then blocked("custom Character contamination before native load");abort=true;return {ok=false,error="contamination"} end
    busy=true;activeCase="spawn_"..tostring(index)
    local before=player.Character;local complete=false;local succeeded=false;local problem
    emit("a2_load_request",{load_index=index,path="NATIVE_DEFAULT",phase=index<=5 and "prejoin_profile" or "after_StarterPlayer_only_mutation",player_properties=Common.props(player,Common.playerKeys),starter_player=Common.props(StarterPlayer,Common.starterKeys)})
    task.spawn(function()
        succeeded,problem=pcall(function()player:LoadCharacterAsync()end);complete=true
    end)
    local deadline=os.clock()+registration.timeouts.native_load_wall_s
    while not complete and not finished and os.clock()<deadline do RunService.Heartbeat:Wait() end
    busy=false
    if not complete or not succeeded then
        blocked(not complete and "LoadCharacterAsync watchdog 20s; no retries/next native calls" or Common.reason(problem));abort=true
        return {ok=false,error="native load failed/timed out"}
    end
    loaded+=1
    local character=player.Character
    if not character or character==before or not generations[character] then blocked("native load did not create a new observed Character");abort=true;return {ok=false,error="Character generation mismatch"} end
    emit("a2_load_return",{load_index=index,character_generation=generations[character],new_character=true,token=activeCase})
    return {ok=true,generation=generations[character],token=activeCase}
end
task.delay(registration.timeouts.session_wall_s,function()
    if not finished then blocked("global server session watchdog 300s");finish("watchdog") end
end)
