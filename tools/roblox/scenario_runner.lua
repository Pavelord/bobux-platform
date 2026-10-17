-- LocalScript. Add a StringValue child named ScenarioData and paste tools/scenarios.json into Value.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local data_value = script:WaitForChild("ScenarioData")
local data = HttpService:JSONDecode(data_value.Value)
local course = Instance.new("Folder")
course.Name = "R6TraceCourse"
course.Parent = Workspace

local function vec3(values)
	return Vector3.new(values[1], values[2], values[3])
end

for _, fixture in ipairs(data.course.parts) do
	local part = Instance.new(fixture.kind or "Part")
	part.Name = fixture.name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.Size = vec3(fixture.size)
	local degrees = vec3(fixture.rotation_deg or {0, 0, 0})
	part.CFrame = CFrame.new(vec3(fixture.position)) * CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
	part.Material = Enum.Material.Plastic
	part.Parent = course
end

local function current_character()
	local character = player.Character or player.CharacterAdded:Wait()
	return character, character:WaitForChild("HumanoidRootPart"), character:WaitForChild("Humanoid")
end

for scenario_index, scenario in ipairs(data.scenarios) do
	local character, root, humanoid = current_character()
	Workspace:SetAttribute("R6Scenario", "")
	humanoid:Move(Vector3.zero, false)
	humanoid.Jump = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(vec3(scenario.spawn))
	RunService.Stepped:Wait()
	Workspace:SetAttribute("R6Scenario", scenario.name)
	print("R6SCENARIO_BEGIN," .. scenario.name .. "," .. tostring(scenario_index) .. "/" .. tostring(#data.scenarios))
	for _, command in ipairs(scenario.commands) do
		local move = vec3(command.move or {0, 0, 0})
		local climb_axis = command.climb_axis or 0
		local direction = Vector3.new(move.X, climb_axis, move.Z)
		for tick = 1, command.ticks do
			humanoid:Move(direction, false)
			humanoid.Jump = command.jump == true and tick == 1
			RunService.Stepped:Wait()
		end
	end
	humanoid:Move(Vector3.zero, false)
	humanoid.Jump = false
	Workspace:SetAttribute("R6Scenario", "")
	print("R6SCENARIO_END," .. scenario.name)
end

print("R6SCENARIO_RUN_COMPLETE," .. tostring(#data.scenarios))
