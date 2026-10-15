-- Own public Enum observations only. No world, Player.Character, Source or asset mutation.
local HttpService=game:GetService("HttpService")
local EncodingService=game:GetService("EncodingService")
local runID=HttpService:GenerateGUID(false)
local names={"HumanoidStateType","HumanoidRigType","AnimationPriority","CameraType","CameraMode","Material","CoreGuiType","SensorMode","SensorUpdateType","RaycastFilterType"}
local function item(value)
    if value==nil then return {type="nil",is_nil=true} end
    if typeof(value)~="EnumItem" then return {type=typeof(value),tostring=tostring(value)} end
    return {type=typeof(value),lua_type=type(value),Name=value.Name,Value=value.Value,EnumType=tostring(value.EnumType),tostring=tostring(value)}
end
local function observed(fn)
    local packed=table.pack(pcall(fn))
    local out={ok=packed[1],returns={}}
    if packed[1] then
        out.return_count=packed.n-1
        for i=2,packed.n do out.returns[#out.returns+1]=item(packed[i]) end
    else out.error=tostring(packed[2]) end
    return out
end
local families={}
local items=0
local blocked=0
for seq,name in ipairs(names) do
    local row={seq=seq,name=name,status="OBSERVED",items={}}
    local ok,reason=pcall(function()
        local family=Enum[name]
        row.type,row.lua_type,row.tostring=typeof(family),type(family),tostring(family)
        for order,value in ipairs(family:GetEnumItems()) do
            local valueRow=item(value)
            valueRow.order=order
            valueRow.identity_equal=(value==family[value.Name])
            valueRow.family_identity=(value.EnumType==family)
            row.items[#row.items+1]=valueRow
        end
    end)
    if not ok then row.status="BLOCKED";row.error=tostring(reason);blocked+=1 end
    row.item_count=#row.items
    items+=row.item_count
    families[#families+1]=row
end
local aliases={}
for seq,name in ipairs({"Blacklist","Whitelist"}) do
    aliases[#aliases+1]={seq=seq,domain="RaycastFilterType",alias=name,
        lookup=observed(function() return Enum.RaycastFilterType[name] end),
        from_name=observed(function() return Enum.RaycastFilterType:FromName(name) end)}
end
local rootCall=table.pack(pcall(function() return #Enum:GetEnums() end))
local root={ok=rootCall[1],type=typeof(Enum),lua_type=type(Enum),tostring=tostring(Enum)}
if rootCall[1] then root.count=rootCall[2] else root.error=tostring(rootCall[2]);blocked+=1 end
local payload={schema=1,kind="character_enum_domains",run_id=runID,date_utc=DateTime.now():ToIsoDate(),studio_version=version(),
    families=families,domain_count=#families,canonical_item_count=items,aliases=aliases,alias_count=#aliases,root=root,
    blocked_domains=blocked,status=blocked==0 and "OBSERVED" or "BLOCKED",no_expected_outcomes=true,
    policy="Own public enum values/order/identity/aliases; no Source/assets/keyframes; namespace count is not full item coverage"}
local raw=HttpService:JSONEncode(payload)
local rawBuffer=buffer.fromstring(raw)
local hash=EncodingService:ComputeBufferHash(rawBuffer,Enum.HashAlgorithm.Sha256)
assert(buffer.len(hash)==32,"unexpected public SHA256 length")
local hex={}
for i=0,31 do hex[#hex+1]=string.format("%02x",buffer.readu8(hash,i)) end
local encoded=buffer.tostring(EncodingService:Base64Encode(rawBuffer))
local packets,maxBytes=0,0
for offset=1,#encoded,400 do
    packets+=1
    local line="CHARACTER_ENUM_EXPORT "..HttpService:JSONEncode({schema=1,run_id=runID,seq=packets,i=offset,s=encoded:sub(offset,offset+399)})
    assert(#line<=700,"own marker exceeds 700 bytes")
    maxBytes=math.max(maxBytes,#line)
    print(line)
    if packets%64==0 then task.wait() end
end
local done="CHARACTER_ENUM_DONE "..HttpService:JSONEncode({schema=1,run_id=runID,encoding="base64",packet_bytes=400,packets=packets,
    raw_bytes=#raw,encoded_bytes=#encoded,raw_sha256=table.concat(hex),max_export_line_bytes=maxBytes,
    domain_count=#families,canonical_item_count=items,alias_count=#aliases,blocked_domains=blocked,status=payload.status,
    date_utc=payload.date_utc,studio_version=payload.studio_version})
assert(#done<=700,"own completion exceeds 700 bytes")
print(done)
