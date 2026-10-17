-- Own A3 functional test design. NOT_RUN until its reference predicates have
-- been observed in Studio and a Bobux RobloxParity.EnumItem VM is wired.
-- Returns independent pcall results; a harness must not turn missing fixture
-- objects into PASS. No Roblox engine or PlayerModule source is copied.
local results = {}
local function check(name, callback)
    local ok, err = pcall(callback)
    table.insert(results, {name = name, ok = ok, error = ok and nil or tostring(err)})
end
local jump = Enum.HumanoidStateType.Jumping
local enumType = Enum.HumanoidStateType
check("item_userdata_typeof", function()
    assert(type(jump) == "userdata")
    assert(typeof(jump) == "EnumItem")
end)
check("item_properties", function()
    assert(jump.Name == "Jumping" and jump.Value == 3)
    assert(jump.EnumType == enumType)
end)
check("item_tostring", function()
    assert(tostring(jump) == "Enum.HumanoidStateType.Jumping")
end)
check("type_identity", function()
    assert(typeof(enumType) == "Enum")
    assert(typeof(Enum) == "Enums")
end)
check("equality_same_domain", function()
    assert(jump == Enum.HumanoidStateType.Jumping)
    assert(jump ~= Enum.HumanoidStateType.Freefall)
end)
check("equality_cross_domain_and_number", function()
    assert(jump ~= Enum.CameraType.Track)
    assert(jump ~= 3 and jump ~= "Jumping")
end)
check("table_key_singleton", function()
    local map = {[jump] = "jump"}
    assert(map[Enum.HumanoidStateType.Jumping] == "jump")
    assert(map[Enum.CameraType.Track] == nil and map[3] == nil)
end)
check("enumeration_lookup_identity", function()
    local items = enumType:GetEnumItems()
    assert(#items == 17)
    local count, seen = 0, {}
    for _, item in ipairs(items) do
        assert(typeof(item) == "EnumItem" and item.EnumType == enumType)
        assert(enumType[item.Name] == item)
        assert(not seen[item.Value])
        seen[item.Value] = true
        count += 1
    end
    assert(count == 17 and seen[3] and seen[18])
    assert(not seen[9] and not seen[17])
end)
check("enumeration_copy_isolation", function()
    local first = enumType:GetEnumItems()
    local expectedSize = #first
    first[1] = nil
    assert(#enumType:GetEnumItems() == expectedSize)
end)
check("item_readonly", function()
    assert(not pcall(function() jump.Name = "Changed" end))
    assert(not pcall(function() jump.Value = 99 end))
    assert(not pcall(function() jump.EnumType = Enum.Material end))
    assert(jump.Name == "Jumping" and jump.Value == 3 and jump.EnumType == enumType)
end)
check("type_readonly", function()
    assert(not pcall(function() enumType.Jumping = Enum.HumanoidStateType.Freefall end))
    assert(enumType.Jumping == jump)
end)
check("documented_camera_and_animation_values", function()
    assert(Enum.CameraType.Orbital.Value == 7)
    assert(Enum.AnimationPriority.Core.Value == 1000)
    assert(Enum.AnimationPriority.Action4.Value == 5)
end)
check("core_gui_corrected_values", function()
    assert(Enum.CoreGuiType.All.Value == 4)
    assert(Enum.CoreGuiType.EmotesMenu.Value == 5)
    assert(Enum.CoreGuiType.SelfView.Value == 6)
    assert(Enum.CoreGuiType.Captures.Value == 7)
end)

local h = Instance.new("Humanoid")
check("rig_getter", function()
    assert(typeof(h.RigType) == "EnumItem")
    assert(h.RigType == Enum.HumanoidRigType.R6)
end)
check("humanoid_state_round_trip", function()
    h:ChangeState(Enum.HumanoidStateType.Physics)
    assert(typeof(h:GetState()) == "EnumItem")
    assert(h:GetState() == Enum.HumanoidStateType.Physics)
end)
local events = {}
local connection = h.StateEnabledChanged:Connect(function(...)
    local args = table.pack(...)
    table.insert(events, args)
end)
check("humanoid_state_enabled_round_trip", function()
    h:SetStateEnabled(jump, false)
    assert(h:GetStateEnabled(jump) == false)
    h:SetStateEnabled(jump, false)
    h:SetStateEnabled(jump, true)
    h:SetStateEnabled(jump, true)
    assert(h:GetStateEnabled(jump) == true)
end)
task.wait()
check("state_enabled_event_enumitem_and_arity", function()
    assert(#events == 4)
    for i, args in ipairs(events) do
        assert(args.n == 2 and typeof(args[1]) == "EnumItem")
        assert(args[1] == jump and args[1].EnumType == enumType)
        assert(args[2] == (i > 2))
    end
end)
connection:Disconnect()
h:Destroy()

check("part_material_round_trip", function()
    local part = Instance.new("Part")
    part.Material = Enum.Material.Neon
    assert(part.Material == Enum.Material.Neon)
    assert(typeof(part.Material) == "EnumItem" and part.Material.Value == 288)
    part:Destroy()
end)
check("part_shape_round_trip", function()
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Ball
    assert(part.Shape == Enum.PartType.Ball)
    part:Destroy()
end)
check("raycast_params_round_trip", function()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    assert(params.FilterType == Enum.RaycastFilterType.Include)
    assert(typeof(params.FilterType) == "EnumItem")
end)
check("camera_type_round_trip", function()
    local camera = workspace.CurrentCamera
    assert(camera ~= nil, "fixture needs a real Camera")
    local old = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable
    local actual = camera.CameraType
    camera.CameraType = old
    assert(typeof(actual) == "EnumItem" and actual == Enum.CameraType.Scriptable)
end)
check("tween_info_enum_round_trip", function()
    local info = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    assert(info.EasingStyle == Enum.EasingStyle.Sine)
    assert(info.EasingDirection == Enum.EasingDirection.InOut)
end)
return results
