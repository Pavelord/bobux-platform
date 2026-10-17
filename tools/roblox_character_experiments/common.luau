-- Bobux-authored telemetry serialization. No stock Roblox source is copied.
local M = {}
function M.vec(v) return {v.X, v.Y, v.Z} end
function M.cf(v) return {v:GetComponents()} end
function M.safe(value)
    local t = typeof(value)
    if t == "EnumItem" then return {Name=value.Name, Value=value.Value, EnumType=tostring(value.EnumType), type=t, tostring=tostring(value)} end
    if t == "Vector3" then return M.vec(value) end
    if t == "CFrame" then return M.cf(value) end
    if t == "Instance" then return value:GetFullName() end
    if t == "PhysicalProperties" then return {Density=value.Density, Friction=value.Friction, Elasticity=value.Elasticity, FrictionWeight=value.FrictionWeight, ElasticityWeight=value.ElasticityWeight} end
    if t == "number" and (value ~= value or math.abs(value) == math.huge) then return tostring(value) end
    if value == nil then return {is_nil=true} end
    if t == "boolean" or t == "string" or t == "number" then return value end
    return {type=t, tostring=tostring(value)}
end
function M.props(instance, keys)
    local data = {}
    for _, key in ipairs(keys) do
        local ok, value = pcall(function() return instance[key] end)
        if ok then data[key] = M.safe(value)
        else data[key] = {status="NOT_OBSERVABLE", reason=tostring(value)} end
    end
    return data
end
M.humanoidKeys = {"Health","MaxHealth","WalkSpeed","JumpPower","JumpHeight","UseJumpPower","HipHeight","AutoRotate","AutoJumpEnabled","BreakJointsOnDeath","MaxSlopeAngle","RequiresNeck","EvaluateStateMachine","AutomaticScalingEnabled","PlatformStand","Sit","RigType","CameraOffset","DisplayName","NameDisplayDistance","HealthDisplayDistance","DisplayDistanceType","NameOcclusion","HealthDisplayType"}
M.starterKeys = {"LoadCharacterAppearance","AutoJumpEnabled","CharacterWalkSpeed","CharacterJumpPower","CharacterJumpHeight","CharacterUseJumpPower","CharacterMaxSlopeAngle","CharacterBreakJointsOnDeath","CameraMinZoomDistance","CameraMaxZoomDistance","CameraMode","LuaCharacterController"}
function M.humanoid(h)
    local data = M.props(h, M.humanoidKeys)
    data.enabled_states = {}
    for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
        local ok, result = pcall(function() return h:GetStateEnabled(state) end)
        if ok then data.enabled_states[state.Name] = result
        else data.enabled_states[state.Name] = {status="NOT_OBSERVABLE", reason=tostring(result)} end
    end
    return data
end
function M.parts(character, root)
    local data = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            local item = M.props(part, {"Size","CFrame","CanCollide","CanTouch","CanQuery","CollisionGroup","Massless","CustomPhysicalProperties","CurrentPhysicalProperties","AssemblyMass","AssemblyCenterOfMass","Anchored","Material","Transparency"})
            item.name, item.class = part.Name, part.ClassName
            if root then item.root_relative_cf = M.cf(root.CFrame:ToObjectSpace(part.CFrame)) end
            local ok, mass = pcall(function() return part:GetMass() end)
            item.mass = ok and mass or {status="NOT_OBSERVABLE", reason=tostring(mass)}
            table.insert(data, item)
        end
    end
    table.sort(data, function(a,b) return a.name < b.name end)
    return data
end
function M.inventory(container)
    local data = {}
    for _, item in ipairs(container:GetDescendants()) do
        if item:IsA("LuaSourceContainer") then
            local row = {path=item:GetFullName(), name=item.Name, class=item.ClassName,
                         metadata=M.props(item,{"Enabled","Disabled","RunContext"})}
            -- Ordinary LocalScripts cannot read Source. Never store it even if access changes.
            local ok, reason = pcall(function() local ignoredLength = #item.Source; return ignoredLength end)
            row.source_access = ok and "READABLE_BUT_NOT_RETAINED" or "BLOCKED"
            if not ok then row.source_reason = tostring(reason) end
            table.insert(data,row)
        end
    end
    table.sort(data,function(a,b) return a.path < b.path end)
    return data
end
return M
