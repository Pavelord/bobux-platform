-- LocalScript. Emits marked CSV rows to Studio Output; it never writes files.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local COLUMNS = {
	"scenario", "t", "dt", "px", "py", "pz", "vx", "vy", "vz",
	"state", "floor_material", "mx", "my", "mz", "jump", "edge_overhang_studs",
}

local function csv(value)
	local text = tostring(value)
	if string.find(text, '[,\"\r\n]') then
		return '"' .. string.gsub(text, '"', '""') .. '"'
	end
	return text
end

local function format_number(value)
	return string.format("%.9f", value)
end

local player = Players.LocalPlayer
local started_at = os.clock()
local last_state = nil
local last_floor = nil
local last_support_part = nil
local last_move_direction = Vector3.zero
local pending_overhang = ""

print("R6TRACE_COLUMNS," .. table.concat(COLUMNS, ","))

local function find_support(character, root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	local ray_length = root.Size.Y + 2
	local result = workspace:Raycast(root.Position, Vector3.new(0, -ray_length, 0), params)
	return result and result.Instance or nil
end

local function measure_foot_overhang(support, character, move_direction)
	if not support or not support:IsA("BasePart") or move_direction.Magnitude < 0.001 then
		return ""
	end
	local local_direction = support.CFrame:VectorToObjectSpace(move_direction.Unit)
	local maximum_overhang = -math.huge
	local found_foot = false
	for _, part_name in ipairs({"Left Leg", "Right Leg"}) do
		local foot = character:FindFirstChild(part_name)
		if foot and foot:IsA("BasePart") then
			found_foot = true
			local local_position = support.CFrame:PointToObjectSpace(foot.Position)
			if math.abs(local_direction.X) > 0.001 then
				local sign = math.sign(local_direction.X)
				local support_extent = math.abs(local_direction.X) * foot.Size.X * 0.5 + math.abs(local_direction.Z) * foot.Size.Z * 0.5
				maximum_overhang = math.max(maximum_overhang, sign * (local_position.X + sign * support_extent) - support.Size.X * 0.5)
			end
			if math.abs(local_direction.Z) > 0.001 then
				local sign = math.sign(local_direction.Z)
				local support_extent = math.abs(local_direction.X) * foot.Size.X * 0.5 + math.abs(local_direction.Z) * foot.Size.Z * 0.5
				maximum_overhang = math.max(maximum_overhang, sign * (local_position.Z + sign * support_extent) - support.Size.Z * 0.5)
			end
		end
	end
	if not found_foot then
		return ""
	end
	return format_number(math.max(maximum_overhang, 0))
end

RunService.Stepped:Connect(function(_time, dt)
	local scenario = workspace:GetAttribute("R6Scenario")
	if typeof(scenario) ~= "string" or scenario == "" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local state = humanoid:GetState().Name
	local floor_material = humanoid.FloorMaterial.Name
	local move_direction = humanoid.MoveDirection
	if floor_material ~= "Air" then
		last_support_part = find_support(character, root) or last_support_part
		last_move_direction = move_direction.Magnitude > 0.001 and move_direction or last_move_direction
	elseif last_floor ~= "Air" and floor_material == "Air" and (state == "Freefall" or state == "FallingDown") then
		pending_overhang = measure_foot_overhang(last_support_part, character, last_move_direction)
	end
	local overhang = pending_overhang
	if floor_material ~= "Air" then
		overhang = ""
		pending_overhang = ""
	end
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local fields = {
		csv(scenario), format_number(os.clock() - started_at), format_number(dt),
		format_number(position.X), format_number(position.Y), format_number(position.Z),
		format_number(velocity.X), format_number(velocity.Y), format_number(velocity.Z),
		csv(state), csv(floor_material), format_number(move_direction.X),
		format_number(move_direction.Y), format_number(move_direction.Z),
		tostring(humanoid.Jump), overhang,
	}
	print("R6TRACE," .. table.concat(fields, ","))
	last_state = state
	last_floor = floor_material
end)
