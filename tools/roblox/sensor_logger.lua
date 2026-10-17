-- LocalScript. Adds diagnostic sensors to a live HumanoidRootPart without a ControllerManager.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local function csv(value)
	local text = tostring(value)
	if string.find(text, '[,\"\r\n]') then
		return '"' .. string.gsub(text, '"', '""') .. '"'
	end
	return text
end

local function number(value)
	return string.format("%.9f", value)
end

local player = Players.LocalPlayer
local generation = 0
local step_connection = nil

local function setup(character)
	generation += 1
	local current_generation = generation
	if step_connection then
		step_connection:Disconnect()
		step_connection = nil
	end
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	local sensors = {}
	local status = {}
	for _, spec in ipairs({{"Floor", 2}, {"Ladder", 1}}) do
		local name, distance = spec[1], spec[2]
		local ok, sensor_or_error = pcall(function()
			local sensor = Instance.new("ControllerPartSensor")
			sensor.Name = "R6Trace" .. name .. "Sensor"
			sensor.SensorMode = if name == "Floor" then Enum.SensorMode.Floor else Enum.SensorMode.Ladder
			sensor.SearchDistance = distance
			sensor.Parent = root
			return sensor
		end)
		if ok then
			sensors[name] = sensor_or_error
			status[name] = "CREATED"
		else
			status[name] = "CREATE_ERROR:" .. tostring(sensor_or_error)
		end
	end
	print("R6SENSOR_COLUMNS,scenario,t,dt,sensor_mode,sensed_part,hit_x,hit_y,hit_z,normal_x,normal_y,normal_z,distance,status,fallback_part,fallback_x,fallback_y,fallback_z")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = false
	step_connection = RunService.Stepped:Connect(function(_time, dt)
		if generation ~= current_generation or not character.Parent then return end
		local scenario = workspace:GetAttribute("R6Scenario") or ""
		for _, name in ipairs({"Floor", "Ladder"}) do
			local sensor = sensors[name]
			local sensed_part, hit_position, hit_normal, distance = nil, root.Position, Vector3.zero, -1
			local read_status = status[name]
			if sensor then
				local ok, sensed_result, position_result, normal_result = pcall(function()
					local part = sensor.SensedPart
					local frame = sensor.HitFrame
					return part, frame.Position, sensor.HitNormal
				end)
				if ok then
					sensed_part, hit_position, hit_normal = sensed_result, position_result, normal_result
					if sensed_part then distance = (hit_position - root.Position).Magnitude end
					read_status = "OK"
				else
					read_status = "READ_ERROR:" .. tostring(sensed_result)
				end
			end
			local fallback = nil
			local direction = if name == "Floor" then Vector3.new(0, -(root.Size.Y + 2), 0) else root.CFrame.LookVector
			local fallback_hit = Workspace:Raycast(root.Position, direction, params)
			if fallback_hit then fallback = fallback_hit.Instance end
			local fields = {
				csv(scenario), number(os.clock()), number(dt), csv(name), csv(sensed_part and sensed_part:GetFullName() or ""),
				number(hit_position.X), number(hit_position.Y), number(hit_position.Z),
				number(hit_normal.X), number(hit_normal.Y), number(hit_normal.Z),
				number(distance), csv(read_status), csv(fallback and fallback:GetFullName() or ""),
				fallback_hit and number(fallback_hit.Position.X) or "", fallback_hit and number(fallback_hit.Position.Y) or "", fallback_hit and number(fallback_hit.Position.Z) or "",
			}
			print("R6SENSOR," .. table.concat(fields, ","))
		end
	end)
	print("R6SENSOR_STATUS,HumanoidState=" .. humanoid:GetState().Name .. ",Floor=" .. status.Floor .. ",Ladder=" .. status.Ladder)
end

if player.Character then task.spawn(setup, player.Character) end
player.CharacterAdded:Connect(setup)
