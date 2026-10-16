-- Bobux-authored ordinary-spawn observations. Never read stock Source or asset IDs.
local M={}
M.starterKeys={"LoadCharacterAppearance","LuaCharacterController","AutoJumpEnabled","CharacterWalkSpeed","CharacterJumpPower","CharacterJumpHeight","CharacterUseJumpPower","CharacterMaxSlopeAngle","CharacterBreakJointsOnDeath","CameraMinZoomDistance","CameraMaxZoomDistance","CameraMode"}
M.playerKeys={"AutoJumpEnabled","CameraMinZoomDistance","CameraMaxZoomDistance","CameraMode","DevComputerMovementMode","DevTouchMovementMode"}
M.humanoidKeys={"Health","MaxHealth","WalkSpeed","JumpPower","JumpHeight","UseJumpPower","HipHeight","MaxSlopeAngle","AutoJumpEnabled","AutoRotate","BreakJointsOnDeath","RequiresNeck","RigType","EvaluateStateMachine","AutomaticScalingEnabled","PlatformStand","Sit","FloorMaterial","CameraOffset"}
function M.reason(value)
    local text=tostring(value):gsub("rbxassetid://%d+","[asset-id-redacted]"):gsub("https?://[^%s]+","[url-redacted]")
    return text:sub(1,1200)
end
function M.safe(value)
    local kind=typeof(value)
    if kind=="EnumItem" then return {type=kind,Name=value.Name,Value=value.Value,EnumType=tostring(value.EnumType)} end
    if kind=="Vector3" then return {value.X,value.Y,value.Z} end
    if kind=="number" and (value~=value or math.abs(value)==math.huge) then return {type=kind,value=tostring(value)} end
    if value==nil then return {is_nil=true} end
    if kind=="number" or kind=="boolean" or kind=="string" then return value end
    return {type=kind,status="NOT_OBSERVABLE",reason="outside the registered scalar/enum property schema"}
end
function M.props(instance,keys)
    local values={}
    if not instance then return {status="NOT_OBSERVABLE",reason="instance not present at observation time"} end
    for _,key in ipairs(keys) do
        local ok,value=pcall(function()return instance[key]end)
        -- A measured false is a value, not the failure arm of an and/or idiom.
        if ok then values[key]=M.safe(value)
        else values[key]={status="NOT_OBSERVABLE",reason=M.reason(value)} end
    end
    return values
end
function M.contamination(starter)
    local matches={}
    for _,item in ipairs(starter:GetDescendants()) do
        if item.Name=="StarterCharacter" or item.Name=="StarterHumanoid" or item:IsA("Humanoid") then
            table.insert(matches,{name=item.Name,class=item.ClassName,path=item:GetFullName()})
        end
    end
    return {status=#matches==0 and "OBSERVED_ABSENT" or "BLOCKED",matches=matches}
end
function M.inventory(container)
    local values={}
    if not container then return {status="NOT_OBSERVABLE",reason="container not present"} end
    for _,item in ipairs(container:GetDescendants()) do
        if item:IsA("LuaSourceContainer") then
            table.insert(values,{name=item.Name,class=item.ClassName,path=item:GetFullName(),is_own_probe=item.Name=="OrdinarySpawnMeasurement",metadata=M.props(item,{"Enabled","Disabled","RunContext"}),source_policy="Source never accessed"})
        end
    end
    table.sort(values,function(a,b)return a.path<b.path end)
    return values
end
function M.character(character)
    if not character then return {status="NOT_OBSERVABLE",reason="Character not present"} end
    local humanoid=character:FindFirstChildOfClass("Humanoid")
    local parts,joints={},{}
    for _,item in ipairs(character:GetDescendants()) do
        if item:IsA("BasePart") then
            table.insert(parts,{name=item.Name,class=item.ClassName})
        elseif item:IsA("JointInstance") or item:IsA("Constraint") then
            table.insert(joints,{name=item.Name,class=item.ClassName})
        end
    end
    local function order(a,b)return a.name==b.name and a.class<b.class or a.name<b.name end
    table.sort(parts,order);table.sort(joints,order)
    local stateOK,state=pcall(function()return humanoid and humanoid:GetState()end)
    return {humanoid=M.props(humanoid,M.humanoidKeys),state=stateOK and M.safe(state) or {status="NOT_OBSERVABLE",reason=M.reason(state)},
        actual_rig=humanoid and humanoid.RigType.Name or "NOT_OBSERVABLE",has_humanoid=humanoid~=nil,
        has_hrp=character:FindFirstChild("HumanoidRootPart")~=nil,has_animator=humanoid and humanoid:FindFirstChildOfClass("Animator")~=nil or false,
        has_animate=character:FindFirstChild("Animate")~=nil,parts=parts,part_count=#parts,joints=joints,joint_count=#joints}
end
function M.rollouts()
    return {AvatarJointUpgrade={status="NOT_OBSERVABLE",reason="No registered public readable rollout field; no hidden settings queried"},
        ClassicDeath={status="NOT_OBSERVABLE",reason="No registered public readable rollout field; no hidden settings queried"}}
end
return M
