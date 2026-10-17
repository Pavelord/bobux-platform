-- LocalScript. Captures the spawned vanilla R6 parts and Humanoid settings.
local Players = game:GetService("Players")

local COLUMNS = {
	"part", "size_x", "size_y", "size_z", "can_collide", "can_query", "massless",
	"rel_x", "rel_y", "rel_z", "rel_r00", "rel_r01", "rel_r02",
	"rel_r10", "rel_r11", "rel_r12", "rel_r20", "rel_r21", "rel_r22",
}

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

local function dump_character(character)
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	local allowed = {
		["HumanoidRootPart"] = true, ["Torso"] = true, ["Head"] = true,
		["Left Arm"] = true, ["Right Arm"] = true,
		["Left Leg"] = true, ["Right Leg"] = true,
	}
	print("R6PART_COLUMNS," .. table.concat(COLUMNS, ","))
	local collision_type = "UNAVAILABLE"
	local ok, value = pcall(function()
		return humanoid.CollisionType
	end)
	if ok then collision_type = tostring(value) end
	print("R6PART_META," .. table.concat({
		csv("CollisionType"), csv(collision_type),
		csv("HipHeight"), number(humanoid.HipHeight),
		csv("RigType"), csv(humanoid.RigType.Name),
		csv("HumanoidState"), csv(humanoid:GetState().Name),
	}, ","))
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and allowed[part.Name] then
			local relative = root.CFrame:ToObjectSpace(part.CFrame)
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relative:GetComponents()
			local size = part.Size
			local fields = {
				csv(part.Name), number(size.X), number(size.Y), number(size.Z),
				tostring(part.CanCollide), tostring(part.CanQuery), tostring(part.Massless),
				number(x), number(y), number(z), number(r00), number(r01), number(r02),
				number(r10), number(r11), number(r12), number(r20), number(r21), number(r22),
			}
			print("R6PART," .. table.concat(fields, ","))
		end
	end
end

local player = Players.LocalPlayer
if player.Character then
	task.spawn(dump_character, player.Character)
end
player.CharacterAdded:Connect(dump_character)
