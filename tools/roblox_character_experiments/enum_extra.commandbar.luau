-- Supplementary native Enum observations. Own data only, no scene mutation.
local h=game:GetService("HttpService")
local id=h:GenerateGUID(false)
local function safe(value)
    if value==nil then return {is_nil=true,type="nil"} end
    if typeof(value)=="EnumItem" then
        return {type="EnumItem",Name=value.Name,Value=value.Value,EnumType=tostring(value.EnumType)}
    end
    if type(value)=="table" then
        local names={}
        for _,item in ipairs(value) do table.insert(names,tostring(item)) end
        return {type="table",items=names}
    end
    return {type=typeof(value),value=tostring(value)}
end
local cases={
    {"negative_fraction_half",function()return Enum.HumanoidStateType:FromValue(-0.5)end},
    {"negative_fraction_one_half",function()return Enum.HumanoidStateType:FromValue(-1.5)end},
    {"alias_FromName_Blacklist",function()return Enum.RaycastFilterType:FromName("Blacklist")end},
    {"alias_FromName_Whitelist",function()return Enum.RaycastFilterType:FromName("Whitelist")end},
    {"FromValue_other_enum_receiver",function()return Enum.Material.FromValue(Enum.CameraType,6)end},
    {"GetEnumItems_other_enum_receiver",function()return Enum.Material.GetEnumItems(Enum.CameraType)end},
}
for seq,case in ipairs(cases) do
    local result=table.pack(pcall(case[2]))
    local row={schema=1,run_id=id,seq=seq,id=case[1],ok=result[1],status="OBSERVED",returns={}}
    if result[1] then
        row.return_count=result.n-1
        for i=2,result.n do table.insert(row.returns,safe(result[i])) end
    else row.error=tostring(result[2]) end
    print("ENUM_EXTRA_JSON "..h:JSONEncode(row))
end
print("ENUM_EXTRA_DONE "..h:JSONEncode({run_id=id,records=#cases,studio_version=version(),date_utc=DateTime.now():ToIsoDate()}))
