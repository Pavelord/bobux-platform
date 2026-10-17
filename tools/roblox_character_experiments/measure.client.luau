-- Bobux-authored autonomous classic-Humanoid measurements, no native state forcing
-- during measured climbing. Input commands replace only Controls:Disable(), never Animate.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local StarterPlayer=game:GetService("StarterPlayer")
local Common=require(ReplicatedStorage:WaitForChild("CharacterExperimentCommon",15))
local player=Players.LocalPlayer
local mode=ReplicatedStorage:WaitForChild("CharacterExperimentMode",15).Value
local matrix=HttpService:JSONDecode(ReplicatedStorage:WaitForChild("CharacterExperimentMatrix",15).Value)
local serverFolder=ReplicatedStorage:WaitForChild("CharacterExperimentServerTelemetry",15)
local command=ReplicatedStorage:WaitForChild("CharacterExperimentCommand",15)
local runID=serverFolder:GetAttribute("run_id")
local folder=Instance.new("Folder")
folder.Name,folder.Parent="CharacterExperimentTelemetry",ReplicatedStorage
folder:SetAttribute("run_id",runID)
local wallStart=os.clock()
local seq,frame,simTime=0,0,0
local stage="startup"
local lines,results,errors,connections={},{},{},{}
local characterConnections={}
local characterGeneration=0
local h,root,character,controls
local move=Vector3.zero
local sensors={}
local active=nil
local done=false
local camera=workspace.CurrentCamera
local previousCameraType=camera.CameraType
local previousCameraCF=camera.CFrame

local function emit(kind,data)
    data=data or {}
    seq+=1
    data.kind,data.schema,data.run_id,data.seq=kind,1,runID,seq
    data.case,data.frame,data.wall_s,data.sim_s=stage,frame,os.clock()-wallStart,simTime
    data.character_generation=characterGeneration
    local encoded="CHARACTER_EXPERIMENT_JSON "..HttpService:JSONEncode(data)
    table.insert(lines,encoded)
    if kind~="frame" and kind~="pose" and kind~="render_frame" and kind~="state_event" and kind~="sensor_event" then
        local short={kind=kind,run_id=runID,seq=seq,case=stage,status=data.status,raw_in_telemetry_chunks=true,
            count=data.count,climbing=data.climbing,reason=data.reason,wall_s=data.wall_s}
        print("CHARACTER_EXPERIMENT_JSON "..HttpService:JSONEncode(short))
    end
end
local function blocked(reason)
    table.insert(errors,{case=stage,reason=reason})
    emit("blocked",{status="BLOCKED",reason=reason})
end
local function flush()
    local raw=table.concat(lines,"\n").."\n"
    for _,child in ipairs(folder:GetChildren()) do child:Destroy() end
    for i=1,#raw,50000 do
        local value=Instance.new("StringValue")
        value.Name=string.format("%06d",math.floor((i-1)/50000)+1)
        value.Value=raw:sub(i,i+49999)
        value.Parent=folder
    end
    folder:SetAttribute("raw_bytes",#raw)
    folder:SetAttribute("records",seq)
end
local function finish(reason)
    if done then return end
    done=true
    active=nil
    move=Vector3.zero
    if h and h.Parent then pcall(function()h:Move(Vector3.zero,false)end) end
    for _,connection in ipairs(connections) do connection:Disconnect() end
    for _,connection in ipairs(characterConnections) do connection:Disconnect() end
    if controls then pcall(function() controls:Enable() end) end
    camera.CameraType,camera.CFrame=previousCameraType,previousCameraCF
    local serverRows={}
    for _,value in ipairs(serverFolder:GetChildren()) do
        if value:IsA("StringValue") then table.insert(serverRows,{name=value.Name,json=value.Value}) end
    end
    table.sort(serverRows,function(a,b)return a.name<b.name end)
    for _,record in ipairs(serverRows) do
        local ok,data=pcall(function()return HttpService:JSONDecode(record.json)end)
        if ok then emit("server_record",{server=data}) else blocked("invalid server JSON "..record.name) end
    end
    emit("run_result",{status=#errors==0 and "OBSERVED" or "BLOCKED",reason=reason,cases=results,errors=errors,count=#results,
        no_parity_pass_claim=true,coverage="Foundation inventory / preregistered minimal climbing only; phases A-J not complete"})
    flush()
    folder:SetAttribute("complete",true)
    folder:SetAttribute("status",#errors==0 and "OBSERVED" or "BLOCKED")
    task.spawn(function() pcall(function()command:InvokeServer("finish")end) end)
    print("CHARACTER_EXPERIMENT_DONE "..HttpService:JSONEncode({run_id=runID,records=seq,raw_bytes=folder:GetAttribute("raw_bytes"),cases=#results,status=folder:GetAttribute("status")}))
end
local function waitUntil(predicate,seconds,description)
    local deadline=os.clock()+seconds
    while not done and os.clock()<deadline do
        if predicate() then return true end
        RunService.Heartbeat:Wait()
    end
    if not done then blocked("timeout "..seconds.."s: "..description) end
    return false
end
local function waitSim(seconds)
    local deadline=simTime+seconds
    local wallDeadline=os.clock()+seconds*6+10
    while not done and simTime<deadline and os.clock()<wallDeadline do
        if active and active.lifecycle_failure then return false end
        RunService.Heartbeat:Wait()
    end
    if not done and simTime<deadline then blocked("simulation callback stalled") end
    return not done and simTime>=deadline
end
local function characterAlive()
    return character~=nil and character.Parent~=nil and player.Character==character
        and h~=nil and h.Parent~=nil and h:IsDescendantOf(character) and h.Health>0
        and h:GetState()~=Enum.HumanoidStateType.Dead
        and root~=nil and root.Parent~=nil and root:IsDescendantOf(character)
        and root:IsDescendantOf(workspace)
end
local function stopMovement()
    -- Clear the input command before any teleport/freefall outside measured time.
    move=Vector3.zero
    if h and h.Parent then pcall(function()h:Move(Vector3.zero,false)end) end
end
local function disconnectCharacter()
    for _,connection in ipairs(characterConnections) do connection:Disconnect() end
    table.clear(characterConnections)
    for _,sensor in ipairs(sensors) do pcall(function()sensor:Destroy()end) end
    table.clear(sensors)
    h,root,character=nil,nil,nil
end
local function connectCharacter()
    character=player.Character
    if not character then return false end
    h,root=character:WaitForChild("Humanoid",15),character:WaitForChild("HumanoidRootPart",15)
    if not h or not root then blocked("native character missing Humanoid/HRP");return false end
    characterGeneration+=1
    local thisCharacter,thisRoot,thisHumanoid,thisGeneration=character,root,h,characterGeneration
    table.insert(characterConnections,h.StateChanged:Connect(function(old,new)
        if done or thisGeneration~=characterGeneration or not thisRoot.Parent then return end
        emit("state_event",{old=Common.safe(old),new=Common.safe(new),velocity=Common.vec(thisRoot.AssemblyLinearVelocity)})
        if active then
            table.insert(active.states,{old=old.Name,new=new.Name,sim_s=simTime,wall_s=os.clock()-wallStart,frame=frame})
            emit("state_collision_snapshot",{state=Common.safe(new),parts=Common.parts(thisCharacter,thisRoot),
                hidden_solver_contacts="NOT_OBSERVABLE; public body flags/mass/physical properties only"})
        end
    end))
    table.insert(characterConnections,thisHumanoid.Climbing:Connect(function(speed)
        if done or thisGeneration~=characterGeneration then return end
        if active then table.insert(active.climb_events,{sim_s=simTime,speed=speed,frame=frame}) end
    end))
    emit("character_connected",{generation=characterGeneration,rig=h.RigType.Name,
        health=h.Health,character_path=character:GetFullName(),native_factory=character:GetAttribute("ExperimentRigSource")})
    return true
end
local function loadProfile(rig,modified)
    active=nil
    stopMovement()
    local oldCharacter=player.Character
    disconnectCharacter()
    local invokeFinished=false
    local ok,result,reason
    task.spawn(function()
        ok,result,reason=pcall(function()return command:InvokeServer("load",rig,modified)end)
        invokeFinished=true
    end)
    if not waitUntil(function()return invokeFinished end,matrix.durations.native_load_wall_s or 20,"bounded native spawn RPC") then return false end
    if done then return false end
    if not ok or not result then blocked("native spawn: "..tostring(reason or result));return false end
    if not waitUntil(function()
        return player.Character and player.Character~=oldCharacter and player.Character:GetAttribute("ExperimentProfile")== (modified and "modified" or "default")
            and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").RigType==Enum.HumanoidRigType[rig]
    end,15,"requested replicated "..rig) then return false end
    if not connectCharacter() then return false end
    if not characterAlive() then blocked("native spawn produced a dead/detached Character");return false end
    if not waitUntil(function()return character:FindFirstChild("Animate")~=nil end,15,"standard Animate installed by native LoadCharacterAsync") then return false end
    local animationScript=character:FindFirstChild("Animate")
    -- Retain the engine-installed instances only INSIDE this transient Play session
    -- so the Command Bar can inspect R6 and R15 after autonomous run completion.
    -- No Source serialization/export and no stock script code enters the repo.
    local stockCache=ReplicatedStorage:FindFirstChild("CharacterExperimentStockMetadataCache") or Instance.new("Folder")
    stockCache.Name,stockCache.Parent="CharacterExperimentStockMetadataCache",ReplicatedStorage
    local rigCache=stockCache:FindFirstChild(rig) or Instance.new("Folder")
    rigCache.Name,rigCache.Parent=rig,stockCache
    if not rigCache:FindFirstChild("Animate") then
        local copy=animationScript:Clone()
        copy.Parent=rigCache
    end
    local isEnabled=Common.props(animationScript,{"Enabled","Disabled"})
    emit("standard_scripts",{rig=rig,profile=modified and "modified" or "default",character=Common.inventory(character),player_scripts=Common.inventory(player.PlayerScripts),
        animate_state=isEnabled,standard_animation_source_copied=false,
        health_script="Observed inventory decides presence; absence is not silently replaced"})
    local module=player.PlayerScripts:WaitForChild("PlayerModule",15)
    if not module then blocked("standard PlayerModule missing");return false end
    local controlOK,value=pcall(function()return require(module):GetControls()end)
    if not controlOK then blocked("public PlayerModule GetControls: "..tostring(value));return false end
    controls=value
    controls:Disable()
    emit("interference",{controls="Public PlayerModule:GetControls():Disable(); scripted world-space Humanoid:Move replaces physical input only",
        standard_animate="kept installed and enabled",standard_sounds="kept installed; inventory records actual implementation",auto_jump="unmodified inherited field",camera="Scriptable observation framing; does not drive motor"})
    return true
end
local function enumProbe()
    local data={enum_type=typeof(Enum),enum_lua_type=type(Enum),enum_tostring=tostring(Enum),families={}}
    for _,name in ipairs({"HumanoidStateType","AnimationPriority","CameraType","Material","SensorMode","SensorUpdateType"}) do
        local family=Enum[name]
        local row={name=name,type=typeof(family),lua_type=type(family),tostring=tostring(family),items={}}
        local list=family:GetEnumItems()
        for _,item in ipairs(list) do
            local itemRow=Common.safe(item)
            itemRow.lua_type=type(item)
            itemRow.identity_equal=(item==family[item.Name])
            itemRow.number_equal=(item==item.Value)
            itemRow.family_identity=(item.EnumType==family)
            local ok,reason=pcall(function()item.Name="BOBUX_MUTATION_PROBE"end)
            itemRow.name_write={ok=ok,reason=not ok and tostring(reason) or nil}
            ok,reason=pcall(function()item.Value=-123456 end)
            itemRow.value_write={ok=ok,reason=not ok and tostring(reason) or nil}
            table.insert(row.items,itemRow)
        end
        local ok,reason=pcall(function()family.BOBUX_NONEXISTENT_ITEM=123 end)
        row.family_write={ok=ok,reason=not ok and tostring(reason) or nil}
        table.insert(data.families,row)
    end
    local ok,reason=pcall(function()Enum.BOBUX_NONEXISTENT_ENUM={}end)
    data.enums_write={ok=ok,reason=not ok and tostring(reason) or nil}
    emit("a3_enum_probe",data)
end
local function jointConfig()
    local joints={}
    for _,joint in ipairs(character:GetDescendants()) do
        if joint:IsA("Motor6D") then
            table.insert(joints,{name=joint.Name,path=joint:GetFullName(),C0=Common.cf(joint.C0),C1=Common.cf(joint.C1),
                Transform=Common.cf(joint.Transform),part0=joint.Part0 and joint.Part0.Name,part1=joint.Part1 and joint.Part1.Name})
        end
    end
    table.sort(joints,function(a,b)return a.path<b.path end)
    return joints
end
local function pose()
    local motors,parts,tracks={},{},{}
    for _,item in ipairs(character:GetDescendants()) do
        if item:IsA("Motor6D") then table.insert(motors,{name=item.Name,Transform=Common.cf(item.Transform)})
        elseif item:IsA("BasePart") then table.insert(parts,{name=item.Name,CFrame=Common.cf(item.CFrame)}) end
    end
    local animator=h:FindFirstChildOfClass("Animator")
    if animator then
        for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
            table.insert(tracks,{name=track.Name,TimePosition=track.TimePosition,Length=track.Length,Speed=track.Speed,
                WeightCurrent=track.WeightCurrent,WeightTarget=track.WeightTarget,Priority=Common.safe(track.Priority),Looped=track.Looped,IsPlaying=track.IsPlaying,
                animation_id="NOT_COPIED",reason="Only timing/weight/priority aggregates observed; original assets and keyframes not exported"})
        end
    end
    return {motors=motors,parts=parts,tracks=tracks}
end
local function sensorSnapshot()
    local out={}
    for _,sensor in ipairs(sensors) do
        local ok,data=pcall(function()
            return {name=sensor.Name,mode=sensor.SensorMode.Name,SensedPart=sensor.SensedPart and sensor.SensedPart:GetFullName() or false,
                HitNormal=Common.vec(sensor.HitNormal),HitFrame=Common.cf(sensor.HitFrame),SensedMaterial=sensor.SensedMaterial.Name,
                UpdateType=sensor.UpdateType.Name}
        end)
        table.insert(out,ok and data or {name=sensor.Name,status="NOT_OBSERVABLE",reason=tostring(data)})
    end
    return out
end
local function attachSensors()
    for _,name in ipairs({"Ladder","ClassicLadder"}) do
        local ok,sensor=pcall(function()
            local s=Instance.new("ControllerPartSensor")
            s.Name="Diagnostic"..name
            emit("sensor_defaults",{mode=name,properties=Common.props(s,{"SearchDistance","LadderSearchHeight","LadderSearchOffset","SensorMode","UpdateType"})})
            s.SensorMode=Enum.SensorMode[name]
            s.UpdateType=Enum.SensorUpdateType.OnRead
            for _,key in ipairs({"SearchDistance","LadderSearchHeight","LadderSearchOffset"}) do s[key]=matrix.sensor_settings[key] end
            s.Parent=root
            return s
        end)
        if ok then
            table.insert(sensors,sensor)
            emit("sensor_setup",{mode=name,properties=Common.props(sensor,{"SearchDistance","LadderSearchHeight","LadderSearchOffset","SensorMode","UpdateType"}),
                no_force_consumer=true,no_ControllerManager=true,settings_provenance=matrix.sensor_settings.provenance})
        else blocked("diagnostic "..name.." sensor unavailable: "..tostring(sensor)) end
    end
end
local function record(phase,dt)
    if not active or not h or not root or done then return end
    if not characterAlive() then
        if not active.lifecycle_failure then
            active.lifecycle_failure="Character died, detached or lost HumanoidRootPart during measured window"
            blocked(active.lifecycle_failure)
        end
        stopMovement()
        return
    end
    local row={phase=phase,dt_sim_s=dt,position=Common.vec(root.Position),CFrame=Common.cf(root.CFrame),
        linear_velocity=Common.vec(root.AssemblyLinearVelocity),angular_velocity=Common.vec(root.AssemblyAngularVelocity),
        state=Common.safe(h:GetState()),MoveDirection=Common.vec(h.MoveDirection),FloorMaterial=Common.safe(h.FloorMaterial),
        sensors=sensorSnapshot(),input=Common.vec(move)}
    emit("frame",row)
    if phase=="PostSimulation" then
        active.post_count+=1
        active.max_y=math.max(active.max_y,root.Position.Y)
        if h:GetState()==Enum.HumanoidStateType.Climbing then
            table.insert(active.climb_vy,root.AssemblyLinearVelocity.Y)
        end
        if frame%4==0 then
            local data=pose()
            data.sample_cadence="every fourth PreSimulation/PostSimulation callback frame (~15Hz at60fps); not solver substeps"
            emit("pose",data)
        end
    end
end
table.insert(connections,RunService.PreSimulation:Connect(function(dt)
    frame+=1
    simTime+=dt
    if characterAlive() and not done then h:Move(move,false) end
    record("PreSimulation",dt)
end))
table.insert(connections,RunService.PostSimulation:Connect(function(dt)record("PostSimulation",dt)end))
table.insert(connections,RunService.PreRender:Connect(function(dt)
    if active and not done then
        emit("render_frame",{dt_render_s=dt,camera_cf=Common.cf(camera.CFrame),
            viewport={camera.ViewportSize.X,camera.ViewportSize.Y},render_sequence_index=frame})
    end
end))

task.delay(matrix.durations.global_wall_s,function()
    if not done then blocked("global hard wall-clock stop reached; remaining cases BLOCKED");finish("global timeout") end
end)
local function phaseA()
    enumProbe()
    for _,rig in ipairs({"R6","R15"}) do
        for _,modified in ipairs({false,true}) do
            stage="a2_"..rig.."_"..(modified and "modified" or "default")
            if not loadProfile(rig,modified) then return end
            for repeatIndex=1,5 do
                emit("a2_native_getters",{rig=rig,profile=modified and "modified" or "default",repeat_index=repeatIndex,
                    repeat_kind="five replicated getter observations of one native spawn, not independent spawns",
                    properties=Common.humanoid(h),parts=Common.parts(character,root),
                    starter_player=Common.props(StarterPlayer,Common.starterKeys),
                    player_properties=Common.props(player,{"AutoJumpEnabled","CameraMinZoomDistance","CameraMaxZoomDistance","CameraMode"})})
                waitSim(0.1)
            end
            active={post_count=0,max_y=root.Position.Y,climb_vy={},states={},climb_events={}}
            camera.CameraType=Enum.CameraType.Scriptable
            camera.CFrame=CFrame.lookAt(root.Position+Vector3.new(10,5,13),root.Position)
            waitSim(1)
            move=Vector3.new(0,0,-1)
            waitSim(1.5)
            move=Vector3.zero
            waitSim(0.5)
            local tracks=pose().tracks
            emit("a4_animation_observation",{rig=rig,profile=modified and "modified" or "default",tracks=tracks,joints=jointConfig(),
                source_read="BLOCKED for ordinary LocalScript; use stock-metadata Command Bar helper for privileged public Source only"})
            active=nil
            table.insert(results,{case=stage,status="OBSERVED",getters=5,rig=rig,profile=modified and "modified" or "default"})
        end
    end
end
local function resetAt(x,z)
    active=nil
    stopMovement()
    if not characterAlive() then return false,"invalid Character before reset" end
    h.Sit=false
    h.PlatformStand=false
    h.Jump=false
    root.Anchored=true
    local desired=CFrame.lookAt(Vector3.new(x,4,z),Vector3.new(x,4,z-10))
    local relation=character:GetPivot():ToObjectSpace(root.CFrame)
    character:PivotTo(desired*relation:Inverse())
    root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
    RunService.Heartbeat:Wait()
    if not characterAlive() then return false,"Character became invalid during anchored reset" end
    root.Anchored=false
    -- Only reset uses Freefall, before the measured window. Never force Climbing.
    h:ChangeState(Enum.HumanoidStateType.Freefall)
    local deadline=os.clock()+matrix.durations.settle_wall_s
    local settled=false
    while not done and os.clock()<deadline do
        if not characterAlive() then return false,"Character became invalid while settling" end
        if h.FloorMaterial~=Enum.Material.Air and root.AssemblyLinearVelocity.Magnitude<0.25
            and h:GetState()~=Enum.HumanoidStateType.Landed then settled=true;break end
        RunService.Heartbeat:Wait()
    end
    if not settled then return false,"quiet standing timeout "..matrix.durations.settle_wall_s.."s" end
    if not waitSim(0.3) or not characterAlive() then return false,"Character lost during post-settle guard" end
    return true,nil
end
local function climb()
    if not loadProfile("R6",false) then return end
    attachSensors()
    for _,case in ipairs(matrix.cases) do
        if done then return end
        stage=case.id
        if not characterAlive() then
            emit("life_recovery",{reason="invalid/dead/detached Character before case",before_measured_window=true,requested_rig="R6"})
            if not loadProfile("R6",false) then
                table.insert(results,{case=stage,status="BLOCKED",reason="bounded native life recovery failed"})
                return
            end
            attachSensors()
        end
        h.WalkSpeed=case.WalkSpeed
        workspace.Gravity=196.2
        local config=matrix.fixture_geometry[case.geometry]
        local depth=case.geometry=="smooth_tall_block" or case.geometry=="single_ledge"
        local startZ=depth and 8 or 5
        local resetOK,resetReason=resetAt(config.x,startZ)
        if done then return end
        -- Retry only a lost life during preprocessing, never a measured case.
        if not resetOK and not done and not characterAlive() then
            emit("life_recovery",{reason=resetReason,before_measured_window=true,requested_rig="R6"})
            if loadProfile("R6",false) then
                attachSensors()
                h.WalkSpeed=case.WalkSpeed
                resetOK,resetReason=resetAt(config.x,startZ)
            end
        end
        if done then return end
        if not resetOK then
            blocked("case reset failed: "..tostring(resetReason))
            local result={case=stage,status="BLOCKED",parameters=case,reason=resetReason,measured_window_started=false}
            table.insert(results,result)
            emit("case_result",result)
        else
            active={states={},climb_events={},climb_vy={},post_count=0,start_sim=simTime,start_wall=os.clock(),start_y=root.Position.Y,max_y=root.Position.Y}
            emit("case_begin",{parameters=case,properties=Common.humanoid(h),parts=Common.parts(character,root),joints=jointConfig(),
                actual_geometry=Common.parts(workspace.CharacterExperimentGeometry[case.geometry],nil),
                states_forced_in_measured_window=false,jump_requested=false,gravity=workspace.Gravity})
            camera.CameraType=Enum.CameraType.Scriptable
            camera.CFrame=CFrame.lookAt(Vector3.new(config.x+15,13,17),Vector3.new(config.x,10,0))
            move=Vector3.new(0,0,-1)
            local windowComplete=waitSim(matrix.durations.active_sim_s)
            if done then return end
            stopMovement()
            local a=active
            active=nil
            if a then
                table.sort(a.climb_vy)
                local climbing=#a.climb_vy>0
                local valid=windowComplete and characterAlive() and not a.lifecycle_failure
                if not valid and not a.lifecycle_failure then blocked("measured window incomplete or Character invalid") end
                local result={case=stage,status=valid and "OBSERVED" or "BLOCKED",parameters=case,climbing=climbing,climbing_samples=#a.climb_vy,
                    reason=not valid and (a.lifecycle_failure or "measured window incomplete or Character invalid") or nil,
                    measured_window_complete=windowComplete,character_generation=characterGeneration,
                    vertical_speed_median=climbing and a.climb_vy[math.ceil(#a.climb_vy/2)] or nil,
                    max_root_rise=a.max_y-a.start_y,states=a.states,climb_events=a.climb_events,
                    post_frames=a.post_count,duration_sim_s=simTime-a.start_sim,duration_wall_s=os.clock()-a.start_wall,
                    conclusion="Observed behavior; no expected state imposed and no production calibration/PASS claim"}
                if case.geometry=="truss" and not climbing then
                    result.status="BLOCKED"
                    blocked("Truss positive control produced no Climbing; do not interpret ordinary-Part negatives as proof")
                end
                table.insert(results,result)
                emit("case_result",result)
            end
        end
        -- Checkpoint means interrupted tests retain completed raw data.
        if #results%5==0 then flush() end
    end
end

emit("run_manifest",{mode=mode,studio_version=version(),date_utc=DateTime.now():ToIsoDate(),units={position="studs",velocity="studs/s",time="seconds"},
    matrix=matrix,wall_clock="os.clock",simulation_clock="sum of PreSimulation dt",solver_substeps="NOT_OBSERVABLE",
    standard_profile="classic Humanoid Legacy; CCL excluded",visual_capture="Stable Scriptable camera frames and poses recorded; actual rendered video/images must be captured outside this autonomous LocalScript",
    tolerances_preregistered=true,splits_preregistered=true})
local ok,reason=xpcall(function()
    if mode=="phase_a" then phaseA() elseif mode=="climb_baseline" then climb() else error("unknown mode "..mode) end
end,debug.traceback)
if not ok then blocked(tostring(reason)) end
finish(ok and "autonomous matrix completed" or "script exception")
