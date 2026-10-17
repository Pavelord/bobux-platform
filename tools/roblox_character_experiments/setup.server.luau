-- Clean standard classic Humanoid fixtures; no CCL or custom Animate implementation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local HttpService = game:GetService("HttpService")
local Common = require(ReplicatedStorage:WaitForChild("CharacterExperimentCommon"))
Players.CharacterAutoLoads = false
local matrix = HttpService:JSONDecode(ReplicatedStorage.CharacterExperimentMatrix.Value)
local mode = ReplicatedStorage.CharacterExperimentMode.Value
local runID = HttpService:GenerateGUID(false)
local folder = Instance.new("Folder")
folder.Name = "CharacterExperimentServerTelemetry"
folder:SetAttribute("run_id",runID)
folder.Parent = ReplicatedStorage
local status = Instance.new("StringValue")
status.Name, status.Value, status.Parent = "CharacterExperimentSetup", "building", ReplicatedStorage
local command = Instance.new("RemoteFunction")
command.Name, command.Parent = "CharacterExperimentCommand", ReplicatedStorage
local seq = 0
local function emit(kind,data)
    seq += 1
    data = data or {}
    data.kind, data.run_id, data.schema, data.server_seq = kind, runID, 1, seq
    local value = Instance.new("StringValue")
    value.Name = string.format("%06d",seq)
    value.Value = HttpService:JSONEncode(data)
    value.Parent = folder
end
local defaults = {}
for _, key in ipairs(Common.starterKeys) do
    local ok, value = pcall(function() return StarterPlayer[key] end)
    if ok then defaults[key]=value end
end
emit("server_manifest",{studio_version=version(),date_utc=DateTime.now():ToIsoDate(),
    gravity=workspace.Gravity, starter_player=Common.props(StarterPlayer,Common.starterKeys),
    controller_profile="classic Humanoid, explicit StarterPlayer.LuaCharacterController=Legacy",
    description_policy="Empty official HumanoidDescription, no animation/keyframe/audio/texture files exported",
    matrix=matrix})
local geometry = Instance.new("Folder")
geometry.Name, geometry.Parent = "CharacterExperimentGeometry", workspace
for name, config in pairs(matrix.fixture_geometry) do
    local model = Instance.new("Model")
    model.Name, model.Parent = name, geometry
    for _, record in ipairs(config.parts) do
        local part = Instance.new(record.class_name)
        part.Name, part.Size = record.name, Vector3.new(table.unpack(record.size))
        part.CFrame, part.Anchored = CFrame.new(table.unpack(record.pos)), true
        part.CanCollide, part.CanTouch, part.CanQuery = true, true, true
        part.Material = Enum.Material.Plastic
        part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        part.Parent = model
    end
end
emit("geometry",{parts=Common.parts(geometry,nil), units="studs", factory=matrix.fixture_geometry,
    fixture_scripts=0, truss_only_in_control_geometry=true})
for i=1,5 do
    local h = Instance.new("Humanoid")
    emit("a2_fresh_humanoid",{repeat_index=i,properties=Common.humanoid(h)})
    h:Destroy()
end
local templates = {}
local initialized = false
local function initialize()
    if initialized then return end
    initialized = true
    for _, rig in ipairs({"R6","R15"}) do
        for i=1,5 do
            local ok, model = pcall(function()
                return Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"),Enum.HumanoidRigType[rig])
            end)
            if not ok then emit("setup_blocked",{stage="official_description",rig=rig,repeat_index=i,reason=tostring(model)}); error(model) end
            local h, root = model:FindFirstChildOfClass("Humanoid"),model:FindFirstChild("HumanoidRootPart")
            emit("a2_official_model",{rig=rig,repeat_index=i,properties=Common.humanoid(h),parts=Common.parts(model,root),scripts=Common.inventory(model),
                source="Players:CreateHumanoidModelFromDescriptionAsync(empty HumanoidDescription, explicit rig)"})
            if i==1 then templates[rig]=model else model:Destroy() end
        end
    end
end
local modified = {CharacterWalkSpeed=23,CharacterJumpPower=61,CharacterJumpHeight=9,
    CharacterUseJumpPower=false,CharacterMaxSlopeAngle=37,CharacterBreakJointsOnDeath=false,
    CameraMinZoomDistance=2,CameraMaxZoomDistance=60,AutoJumpEnabled=false}
local function load(player,rig,isModified)
    initialize()
    for key,value in pairs(defaults) do
        if key ~= "LuaCharacterController" then pcall(function() StarterPlayer[key]=value end) end
    end
    if isModified then
        for key,value in pairs(modified) do
            local ok,reason = pcall(function() StarterPlayer[key]=value end)
            if not ok then emit("setup_blocked",{stage="modified_starter_player",property=key,reason=tostring(reason)}) end
        end
    end
    local previous = StarterPlayer:FindFirstChild("StarterCharacter")
    if previous then previous:Destroy() end
    local template = templates[rig]:Clone()
    template.Name = "StarterCharacter"
    template.Parent = StarterPlayer
    local ok,reason = pcall(function() player:LoadCharacterAsync() end)
    if not ok then emit("setup_blocked",{stage="native_spawn",rig=rig,reason=tostring(reason)}); return false,tostring(reason) end
    local character = player.Character
    if not character then return false,"LoadCharacterAsync returned without Character" end
    local h,root = character:WaitForChild("Humanoid",15),character:WaitForChild("HumanoidRootPart",15)
    if not h or not root then return false,"missing Humanoid/HRP" end
    if h.RigType ~= Enum.HumanoidRigType[rig] then return false,"wrong native rig "..h.RigType.Name end
    character:SetAttribute("ExperimentRigSource","officialDescription StarterCharacter + Player:LoadCharacterAsync; stock runtime scripts installed by engine")
    character:SetAttribute("ExperimentProfile",isModified and "modified" or "default")
    local relation=character:GetPivot():ToObjectSpace(root.CFrame)
    character:PivotTo(CFrame.new(mode=="phase_a" and -90 or 0,5,18)*relation:Inverse())
    local ownerOK,ownerReason=pcall(function() root:SetNetworkOwner(player) end)
    emit("a2_native_spawn",{rig=rig,modified=isModified,starter_player=Common.props(StarterPlayer,Common.starterKeys),
        player_properties=Common.props(player,{"AutoJumpEnabled","CameraMinZoomDistance","CameraMaxZoomDistance","CameraMode","DevComputerMovementMode","DevTouchMovementMode"}),
        properties=Common.humanoid(h),client_network_owner=ownerOK,owner_reason=ownerOK and nil or tostring(ownerReason)})
    return true
end
command.OnServerInvoke = function(player,operation,rig,flag)
    if operation=="load" and (rig=="R6" or rig=="R15") and type(flag)=="boolean" then
        status.Value="loading "..rig
        local ok,reason=load(player,rig,flag)
        status.Value=ok and "ready" or "BLOCKED "..tostring(reason)
        return ok,reason
    end
    if operation=="finish" then
        for key,value in pairs(defaults) do pcall(function() StarterPlayer[key]=value end) end
        status.Value="measurement completed"
        emit("server_finished",{player=player.Name})
        return true
    end
    return false,"unsupported fixture operation"
end
status.Value="ready for client"
