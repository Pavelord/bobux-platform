-- Bobux-authored telemetry export only. No HTTP, Source, settings or asset access.
-- Public API docs: https://create.roblox.com/docs/reference/engine/classes/EncodingService
local HttpService=game:GetService("HttpService")
local EncodingService=game:GetService("EncodingService")
local folder=game:GetService("ReplicatedStorage"):FindFirstChild("CharacterExperimentTelemetry")
assert(folder and folder:GetAttribute("complete"),"autonomous telemetry is incomplete")
local runID=folder:GetAttribute("run_id")
assert(type(runID)=="string" and #runID>0 and #runID<=64,"invalid own telemetry run_id")
local children=folder:GetChildren()
table.sort(children,function(a,b)return a.Name<b.Name end)
local parts={}
for _,child in ipairs(children) do
    assert(child:IsA("StringValue"),"unexpected own telemetry child")
    table.insert(parts,child.Value)
end
local raw=table.concat(parts)
local LIMIT=128*1024*1024
assert(#raw>0 and #raw<=LIMIT,"own telemetry exceeds raw size cap")
assert(#raw==folder:GetAttribute("raw_bytes"),"own telemetry raw_bytes mismatch")
local records=folder:GetAttribute("records")
assert(type(records)=="number" and records>=1 and records<=1000000 and records%1==0,"invalid own telemetry record count")
local input=buffer.fromstring(raw)
local function sha256Hex(value)
    local hash=EncodingService:ComputeBufferHash(value,Enum.HashAlgorithm.Sha256)
    assert(buffer.len(hash)==32,"unexpected public SHA256 buffer length")
    local bytes={}
    for i=0,31 do table.insert(bytes,string.format("%02x",buffer.readu8(hash,i))) end
    return table.concat(bytes)
end
local rawHash=sha256Hex(input)
local compressed=EncodingService:CompressBuffer(input,Enum.CompressionAlgorithm.Zstd,3)
assert(buffer.len(compressed)>0 and buffer.len(compressed)<=LIMIT,"compressed telemetry exceeds size cap")
local encoded=buffer.tostring(EncodingService:Base64Encode(compressed))
assert(#encoded==4*math.ceil(buffer.len(compressed)/3),"unexpected Base64 encoded length")
local packetBytes=700
local seq=0
for offset=1,#encoded,packetBytes do
    seq+=1
    print("CHARACTER_ZSTD_EXPORT "..HttpService:JSONEncode({schema=1,run_id=runID,seq=seq,i=offset,s=encoded:sub(offset,offset+packetBytes-1)}))
    if seq%64==0 then task.wait() end
end
print("CHARACTER_ZSTD_DONE "..HttpService:JSONEncode({schema=1,run_id=runID,encoding="base64",compression="zstd",compression_level=3,
    encoded_bytes=#encoded,compressed_bytes=buffer.len(compressed),raw_bytes=#raw,raw_records=records,packets=seq,packet_bytes=packetBytes,
    raw_sha256=rawHash,compressed_sha256=sha256Hex(compressed),
    codec_policy="Public EncodingService Zstd3/Base64/Sha256; byte-identical Bobux-authored telemetry only"}))
