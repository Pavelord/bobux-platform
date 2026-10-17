-- Bobux-authored supplementary probe: paste into CLIENT Command Bar after raw export.
-- No stock script Source/assets copied. All pcall outcomes are observed facts, not PASS.
-- Every Humanoid case uses an independent disposable target, never Player.Character.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
assert(player and player.Character,"CLIENT Play Command Bar required")
local liveHumanoid=player.Character:FindFirstChildOfClass("Humanoid")
assert(liveHumanoid,"live Player.Character Humanoid required")
local runID=HttpService:GenerateGUID(false)
local previous=ReplicatedStorage:FindFirstChild("EnumCoercionTelemetry")
if previous then previous:Destroy() end
local output=Instance.new("Folder")
output.Name,output.Parent="EnumCoercionTelemetry",ReplicatedStorage
output:SetAttribute("run_id",runID)
local rows={}
local started=os.clock()
local function safe(v,depth)
    depth=depth or 0
    local t=typeof(v)
    if t=="nil" then return {type=t,is_nil=true} end
    if t=="number" and (v~=v or math.abs(v)==math.huge) then return {type=t,value=tostring(v)} end
    if t=="number" or t=="string" or t=="boolean" then return {type=t,value=v} end
    if t=="EnumItem" then return {type=t,lua_type=type(v),Name=v.Name,Value=v.Value,EnumType=tostring(v.EnumType),tostring=tostring(v)} end
    if t=="Enum" or t=="Enums" then return {type=t,lua_type=type(v),tostring=tostring(v)} end
    if t=="Instance" then return {type=t,class=v.ClassName,name=v.Name,path=v:GetFullName()} end
    if t=="table" and depth<3 then
        local list={}
        for key,value in pairs(v) do table.insert(list,{key=safe(key,depth+1),value=safe(value,depth+1)}) end
        return {type=t,entries=list}
    end
    return {type=t,lua_type=type(v),tostring=tostring(v)}
end
local function attempt(id,context,args,fn,getter)
    local packed=table.pack(pcall(fn))
    local row={id=id,context=context,args={},ok=packed[1],returns={},wall_s=os.clock()-started,status="OBSERVED"}
    for i=1,args.n or #args do table.insert(row.args,safe(args[i])) end
    if packed[1] then
        row.return_count=packed.n-1
        for i=2,packed.n do table.insert(row.returns,safe(packed[i])) end
    else row.error=tostring(packed[2]) end
    if getter then
        local ok,value=pcall(getter)
        row.getter=ok and safe(value) or {status="NOT_OBSERVABLE",reason=tostring(value)}
    end
    table.insert(rows,row)
    return row
end
local function values(item,wrong)
    return {
        {id="valid_enum",value=item}, {id="valid_number",value=item.Value},
        {id="valid_name",value=item.Name}, {id="full_name_string",value=tostring(item)},
        {id="numeric_string",value=tostring(item.Value)}, {id="wrong_domain",value=wrong},
        {id="fractional",value=item.Value+0.5}, {id="negative_number",value=-1}, {id="invalid_number",value=999999},
        {id="invalid_name",value="BOBUX_NONEXISTENT_ITEM"}, {id="nil",value=nil},
        {id="boolean",value=false}, {id="table",value={}},
        {id="nan",value=0/0}, {id="positive_inf",value=math.huge}, {id="negative_inf",value=-math.huge},
    }
end
local diagnostic=Instance.new("Folder")
diagnostic.Name,diagnostic.Parent="EnumCoercionDisposableFixtures",workspace
local template
local templateOK,templateResult=pcall(function()
    local description=Instance.new("HumanoidDescription")
    local ok,result=pcall(function()
        return Players:CreateHumanoidModelFromDescriptionAsync(description,liveHumanoid.RigType)
    end)
    description:Destroy()
    if not ok then error(result) end
    return result
end)
if templateOK then
    template=templateResult
    template.Name="EmptyDescriptionEnumFixtureTemplate"
    for _,item in ipairs(template:GetDescendants()) do
        if item:IsA("LuaSourceContainer") then item:Destroy()
        elseif item:IsA("BasePart") then item.Anchored=true;item.CanCollide=false;item.CanTouch=false end
    end
else
    table.insert(rows,{id="disposable_rig_factory",status="BLOCKED",reason=tostring(templateResult)})
end
local function cloneRig()
    assert(template,"disposable official empty-description rig unavailable")
    local clone=template:Clone()
    assert(clone,"disposable rig clone failed")
    clone.Name="DisposableRig"
    for _,item in ipairs(clone:GetDescendants()) do
        if item:IsA("LuaSourceContainer") then item:Destroy()
        elseif item:IsA("BasePart") then item.Anchored=true;item.CanCollide=false;item.CanTouch=false end
    end
    clone:PivotTo(CFrame.new(160,20,0))
    clone.Parent=diagnostic
    return clone
end
local manifest={kind="enum_coercion_manifest",schema=1,run_id=runID,studio_version=version(),date_utc=DateTime.now():ToIsoDate(),
    live_rig=liveHumanoid.RigType.Name,source_policy="Own probe only; no original animation assets, keyframes or script Source exported",
    contexts={fresh="unparented instance",live_workspace="independent anchored official empty-description rig; no stock scripts, no physical force interpretation"},
    player_character_policy="Read RigType only; no changes to Player.Character or its instances",
    animation_fixture="our identity-only local KeyframeSequence registered in Studio; never downloaded original animation",
    parity_status="NOT_CALIBRATED: outcomes are native conversion facts, not Bobux PASS results"}
table.insert(rows,manifest)
local fatal=false
local ok,reason=xpcall(function()
    for _,familyName in ipairs({"HumanoidStateType","AnimationPriority","CameraType","Material","SensorMode","RaycastFilterType"}) do
        local family=Enum[familyName]
        attempt("enum_identity_"..familyName,"enum",table.pack(family),function()
            return typeof(Enum),type(Enum),tostring(Enum),typeof(family),type(family),tostring(family),family:GetEnumItems()
        end)
        local first=family:GetEnumItems()[1]
        for _,method in ipairs({"FromValue","FromName"}) do
            local candidates=values(first,Enum.CameraType.Custom)
            for _,case in ipairs(candidates) do
                local value=case.value
                attempt(familyName.."_"..method.."_"..case.id,"enum",table.pack(value),function()return family[method](family,value)end)
            end
            attempt(familyName.."_"..method.."_missing","enum",table.pack(),function()return family[method](family)end)
            attempt(familyName.."_"..method.."_extra","enum",table.pack(method=="FromName" and first.Name or first.Value,"ignored_extra"),function()
                return family[method](family,method=="FromName" and first.Name or first.Value,"ignored_extra")
            end)
            attempt(familyName.."_"..method.."_wrong_self","enum",table.pack({},first.Value),function()
                return family[method]({},method=="FromName" and first.Name or first.Value)
            end)
        end
        attempt(familyName.."_GetEnumItems_extra","enum",table.pack(123),function()return family:GetEnumItems(123)end)
    end
    attempt("root_GetEnums","enums",table.pack(),function()
        local result={}
        for _,family in ipairs(Enum:GetEnums()) do table.insert(result,{type=typeof(family),tostring=tostring(family)}) end
        return result
    end)
    attempt("root_GetEnums_extra","enums",table.pack(123),function()return #Enum:GetEnums(123)end)
    attempt("root_GetEnums_wrong_self","enums",table.pack({}),function()return Enum.GetEnums({})end)
    attempt("root_existing_enum_write","enums",table.pack(Enum.Material),function()Enum.Material=Enum.HumanoidStateType end,function()return Enum.Material end)
    attempt("root_missing_enum_write","enums",table.pack("BOBUX_MISSING"),function()Enum.BOBUX_MISSING=1 end)
    attempt("family_existing_item_write","enum",table.pack(Enum.Material.Plastic),function()Enum.Material.Plastic=Enum.Material.Neon end,function()return Enum.Material.Plastic end)
    attempt("item_EnumType_write","enum_item",table.pack(Enum.Material),function()Enum.HumanoidStateType.Running.EnumType=Enum.Material end,function()return Enum.HumanoidStateType.Running.EnumType end)
    attempt("item_Name_write","enum_item",table.pack("Changed"),function()Enum.HumanoidStateType.Running.Name="Changed" end,function()return Enum.HumanoidStateType.Running.Name end)
    attempt("item_Value_write","enum_item",table.pack(17),function()Enum.HumanoidStateType.Running.Value=17 end,function()return Enum.HumanoidStateType.Running.Value end)
    attempt("item_missing_write","enum_item",table.pack(123),function()Enum.HumanoidStateType.Running.BOBUX_MISSING=123 end)
    attempt("item_missing_read","enum_item",table.pack(),function()return Enum.HumanoidStateType.Running.BOBUX_MISSING end)
    attempt("family_missing_read","enum",table.pack(),function()return Enum.Material.BOBUX_MISSING end)
    attempt("root_missing_read","enums",table.pack(),function()return Enum.BOBUX_MISSING end)
    for _,alias in ipairs({"Blacklist","Whitelist","Exclude","Include"}) do
        attempt("raycast_alias_"..alias,"enum",table.pack(alias),function()return Enum.RaycastFilterType[alias]end)
    end
    local a,b,c=Enum.HumanoidStateType.Running,Enum.HumanoidStateType.Climbing,Enum.CameraType.Custom
    local operators={
        add=function()return a+1 end,sub=function()return a-1 end,mul=function()return a*2 end,
        div=function()return a/2 end,unary_minus=function()return -a end,
        less=function()return a<b end,less_equal=function()return a<=b end,
        concat=function()return "item="..a end,tonumber=function()return tonumber(a)end,
        same_item_equal=function()return a==Enum.HumanoidStateType.Running end,
        item_number_equal=function()return a==a.Value end,wrong_domain_equal=function()return a==c end,
        same_number_wrong_domain_equal=function()return Enum.HumanoidStateType.Freefall==Enum.CameraType.Custom end,
        enum_family_equal=function()return a.EnumType==Enum.HumanoidStateType end,
        unknown_item_read=function()return Enum.HumanoidStateType.BOBUX_MISSING end,
    }
    for name,fn in pairs(operators) do attempt("operator_"..name,"enum_item",table.pack(a,b),fn) end

    local setters={
        {class="Camera",key="CameraType",valid=Enum.CameraType.Scriptable,wrong=Enum.HumanoidStateType.Swimming},
        {class="Part",key="Material",valid=Enum.Material.Plastic,wrong=Enum.CameraType.Custom},
        {class="Humanoid",key="RigType",valid=Enum.HumanoidRigType.R6,wrong=Enum.CameraType.Fixed},
    }
    for _,spec in ipairs(setters) do
        for _,context in ipairs({"fresh","live_workspace"}) do
            for _,case in ipairs(values(spec.valid,spec.wrong)) do
                local target,container
                if spec.class=="Humanoid" and context=="live_workspace" and not template then
                    table.insert(rows,{id=spec.class.."_"..spec.key.."_"..case.id,context=context,status="BLOCKED",reason="disposable rig factory unavailable"})
                    continue
                end
                if spec.class=="Humanoid" and context=="live_workspace" then
                    container=cloneRig();target=container:FindFirstChildOfClass("Humanoid")
                else
                    target=Instance.new(spec.class)
                    if context=="live_workspace" then target.Parent=diagnostic end
                end
                if target:IsA("BasePart") then target.Anchored=true;target.CanCollide=false;target.CanTouch=false end
                local value=case.value
                attempt(spec.class.."_"..spec.key.."_"..case.id,context,table.pack(value),function()target[spec.key]=value end,function()return target[spec.key]end)
                local cleanup=container or target
                cleanup:Destroy()
            end
        end
    end

    -- AnimationTrack is not Instance.new-creatable: use our own identity-only clip.
    local sequence=Instance.new("KeyframeSequence")
    sequence.Name="BobuxEnumPriorityIdentityFixture"
    for _,time in ipairs({0,0.1}) do
        local keyframe=Instance.new("Keyframe")
        keyframe.Time=time
        local pose=Instance.new("Pose")
        pose.Name="HumanoidRootPart"
        pose.CFrame=CFrame.identity
        pose.Parent=keyframe
        keyframe.Parent=sequence
    end
    local registerOK,content=pcall(function()return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(sequence)end)
    if registerOK then
        local animation=Instance.new("Animation")
        animation.Name="BobuxEnumPriorityIdentityFixture"
        animation.AnimationId=content
        for _,context in ipairs({"track_loaded_then_controller_detached","live_workspace"}) do
            local controller=Instance.new("AnimationController")
            local animator=Instance.new("Animator")
            animator.Parent=controller
            local model=Instance.new("Model")
            controller.Parent=model
            local part=Instance.new("Part")
            part.Name="HumanoidRootPart"
            part.Anchored,part.CanCollide,part.Parent=true,false,model
            model.Parent=diagnostic
            local loaded,track=pcall(function()return animator:LoadAnimation(animation)end)
            if loaded then
                if context=="track_loaded_then_controller_detached" then model.Parent=nil end
                for _,case in ipairs(values(Enum.AnimationPriority.Action,Enum.HumanoidStateType.Climbing)) do
                    local value=case.value
                    attempt("AnimationTrack_Priority_"..case.id,context,table.pack(value),function()track.Priority=value end,function()return track.Priority end)
                end
                attempt("AnimationTrack_Priority_Core",context,table.pack(Enum.AnimationPriority.Core),function()track.Priority=Enum.AnimationPriority.Core end,function()return track.Priority end)
                attempt("AnimationTrack_Priority_Core_number",context,table.pack(Enum.AnimationPriority.Core.Value),function()track.Priority=Enum.AnimationPriority.Core.Value end,function()return track.Priority end)
                track:Destroy()
            else table.insert(rows,{id="AnimationTrack_fixture_load",context=context,status="BLOCKED",reason=tostring(track)}) end
            model:Destroy()
        end
        animation:Destroy()
    else table.insert(rows,{id="AnimationTrack_fixture_register",status="BLOCKED",reason=tostring(content)}) end
    sequence:Destroy()

    local stateCandidates=values(Enum.HumanoidStateType.Running,Enum.CameraType.Custom)
    for _,context in ipairs({"fresh","live_workspace"}) do
        local function stateAttempt(id,method,args)
            if context=="live_workspace" and not template then
                table.insert(rows,{id=id,context=context,status="BLOCKED",reason="disposable rig factory unavailable"})
                return
            end
            local container=context=="live_workspace" and cloneRig() or nil
            local target=container and container:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid")
            local before={state=safe(target:GetState()),running_enabled=target:GetStateEnabled(Enum.HumanoidStateType.Running),health=target.Health}
            local row=attempt(id,context,args,function()return target[method](target,table.unpack(args,1,args.n))end,function()
                local enabled={}
                for _,state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do enabled[state.Name]=target:GetStateEnabled(state) end
                return {state=target:GetState(),enabled_states=enabled,health=target.Health}
            end)
            row.before=before
            if method=="ChangeState" and context=="live_workspace" then
                RunService.Heartbeat:Wait()
                attempt(id.."_after_heartbeat",context,args,function()return target:GetState(),target.Health end)
            end
            local cleanup=container or target
            cleanup:Destroy()
        end
        for _,method in ipairs({"ChangeState","GetStateEnabled","SetStateEnabled"}) do
            for _,case in ipairs(stateCandidates) do
                local args=method=="SetStateEnabled" and table.pack(case.value,false) or table.pack(case.value)
                stateAttempt("Humanoid_"..method.."_"..case.id,method,args)
            end
            stateAttempt("Humanoid_"..method.."_missing",method,table.pack())
            local extra=method=="SetStateEnabled" and table.pack(Enum.HumanoidStateType.Running,false,123) or table.pack(Enum.HumanoidStateType.Running,123)
            stateAttempt("Humanoid_"..method.."_extra",method,extra)
        end
        for i,args in ipairs({table.pack(nil),table.pack(Enum.HumanoidStateType.Running),
            table.pack(Enum.HumanoidStateType.Running,"false"),table.pack(Enum.HumanoidStateType.Running,0),
            table.pack(Enum.HumanoidStateType.Running,{}),table.pack(Enum.HumanoidStateType.Running,nil)}) do
            stateAttempt("Humanoid_SetStateEnabled_bool_arity_"..i,"SetStateEnabled",args)
        end
    end
end,debug.traceback)
if not ok then fatal=true;table.insert(rows,{id="probe_exception",status="BLOCKED",reason=tostring(reason)}) end
diagnostic:Destroy()
if template then template:Destroy() end
local blocked=0
for index,row in ipairs(rows) do
    row.seq,row.run_id=index,runID
    if row.status=="BLOCKED" then blocked+=1 end
end
local encoded=HttpService:JSONEncode({schema=1,kind="enum_coercion_results",run_id=runID,studio_version=version(),rows=rows,
    status=(fatal or blocked>0) and "BLOCKED" or "OBSERVED",blocked_rows=blocked,wall_seconds=os.clock()-started,no_expected_outcomes=true})
local index=1
while index<=#encoded do
    local ending=math.min(index+399,#encoded)
    -- Preserve UTF-8 boundaries so Command Bar export is valid for any DisplayName/error.
    while ending>=index and not utf8.len(encoded:sub(index,ending)) do ending-=1 end
    assert(ending>=index,"invalid UTF-8 in JSON export")
    local v=Instance.new("StringValue")
    v.Name=string.format("%06d",index)
    v.Value=encoded:sub(index,ending)
    v.Parent=output
    print("ENUM_COERCION_EXPORT "..HttpService:JSONEncode({run_id=runID,n=v.Name,i=index,s=v.Value}))
    index=ending+1
end
output:SetAttribute("complete",true)
output:SetAttribute("bytes",#encoded)
print("ENUM_COERCION_DONE "..HttpService:JSONEncode({run_id=runID,rows=#rows,bytes=#encoded,status=(fatal or blocked>0) and "BLOCKED" or "OBSERVED",blocked_rows=blocked}))
