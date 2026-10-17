-- Standalone black-box fixture. No game source, client binaries or hidden API.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

Players.CharacterAutoLoads = false
local status = Instance.new("StringValue")
status.Name = "HumanoidExperimentSetup"
status.Value = "building"
status.Parent = ReplicatedStorage

local truss = Instance.new("TrussPart")
truss.Name = "ExperimentTruss"
truss.Size = Vector3.new(2, 48, 2)
truss.CFrame = CFrame.new(40, 24, 0)
truss.Anchored = true
truss.Parent = workspace

-- A real Terrain Water volume, not a Part whose Material happens to be Water.
workspace.Terrain:FillBlock(CFrame.new(-64, 16, 0), Vector3.new(64, 32, 64), Enum.Material.Water)

local function spawn(player)
	if player:GetAttribute("ExperimentSpawnStarted") then return end
	player:SetAttribute("ExperimentSpawnStarted", true)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok then
		status.Value = "failed: " .. tostring(result)
		warn("HUMANOID_EXPERIMENT_JSON " .. HttpService:JSONEncode({kind="setup_failure", reason=tostring(result)}))
		return
	end
	local character = result
	character.Name = player.Name
	character:SetAttribute("ExperimentRigSource", "Players:CreateHumanoidModelFromDescriptionAsync(empty HumanoidDescription, R6)")
	character:PivotTo(CFrame.new(0, 5, 0))
	player.Character = character
	character.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local ownerOK, ownerError = pcall(function() root:SetNetworkOwner(player) end)
		character:SetAttribute("ExperimentClientOwnership", ownerOK)
		if not ownerOK then
			warn("HUMANOID_EXPERIMENT_JSON " .. HttpService:JSONEncode({kind="setup_failure", reason="network ownership: " .. tostring(ownerError)}))
		end
	end
	status.Value = "ready"
end

Players.PlayerAdded:Connect(spawn)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(spawn, player) end
