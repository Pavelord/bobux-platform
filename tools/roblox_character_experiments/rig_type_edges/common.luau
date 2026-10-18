-- Own scalar telemetry helpers. No stock script, asset or keyframe access.
local M={}

function M.reason(value)
    local text=tostring(value):gsub("rbxassetid://%d+","[asset-id-redacted]"):gsub("https?://[^%s]+","[url-redacted]")
    return text:sub(1,1200)
end

function M.safe(value)
    local kind=typeof(value)
    if value==nil then return {type="nil",is_nil=true} end
    if kind=="EnumItem" then
        return {type=kind,lua_type=type(value),Name=value.Name,Value=value.Value,EnumType=tostring(value.EnumType),tostring=tostring(value)}
    end
    if kind=="number" then
        if value~=value then return {type=kind,special="nan"} end
        if value==math.huge then return {type=kind,special="positive_inf"} end
        if value==-math.huge then return {type=kind,special="negative_inf"} end
        return {type=kind,value=value}
    end
    if kind=="boolean" or kind=="string" then return {type=kind,value=value} end
    if kind=="table" then return {type=kind,empty=next(value)==nil,content_policy="No recursive table traversal"} end
    return {type=kind,status="NOT_OBSERVABLE",reason="outside registered scalar/enum input schema"}
end

function M.tuple(packed,first)
    local values={}
    for index=first or 1,packed.n do table.insert(values,M.safe(packed[index])) end
    return {count=packed.n-(first or 1)+1,values=values}
end

function M.getter(humanoid)
    local ok,value=pcall(function()return humanoid.RigType end)
    if ok then return {ok=true,value=M.safe(value)} end
    return {ok=false,status="NOT_OBSERVABLE",reason=M.reason(value)}
end

function M.matchesRig(observation,name)
    local value=observation.value
    local expected=({R6=0,R15=1})[name]
    return expected~=nil and observation.ok==true and type(value)=="table" and value.type=="EnumItem"
        and value.EnumType=="HumanoidRigType" and value.Name==name and value.Value==expected
end

function M.setter(humanoid,value)
    local packed=table.pack(pcall(function()humanoid.RigType=value end))
    if packed[1] then return {ok=true,returns=M.tuple(packed,2)} end
    return {ok=false,error=M.reason(packed[2])}
end

function M.argument(variant,target)
    local item=Enum.HumanoidRigType[target]
    if variant=="matching_enum" then return item end
    if variant=="number" then return item.Value end
    if variant=="bare_name" then return item.Name end
    if variant=="numeric_string" then return tostring(item.Value) end
    if variant=="positive_fraction" then return item.Value+0.5 end
    if variant=="negative_fraction" then return -0.5 end
    if variant=="wrong_domain" then return Enum.CameraType.Fixed end
    if variant=="full_name_string" then return tostring(item) end
    if variant=="nil" then return nil end
    if variant=="boolean_false" then return false end
    if variant=="boolean_true" then return true end
    if variant=="empty_table" then return {} end
    if variant=="negative_number" then return -1 end
    if variant=="invalid_number" then return 999999 end
    if variant=="invalid_name" then return "BOBUX_NONEXISTENT_ITEM" end
    if variant=="nan" then return 0/0 end
    if variant=="positive_inf" then return math.huge end
    if variant=="negative_inf" then return -math.huge end
    error("Unregistered own input variant: "..tostring(variant))
end

return M
