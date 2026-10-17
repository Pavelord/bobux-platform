-- Bobux-authored Command Bar helper. Reads public Source inside official Studio.
-- Output contains ONLY extracted literal constants, dependency/API identifiers,
-- animation configuration values, and inventories. Never output Source/text lines.
local M={}
local function sourceWithoutCommentsOrStrings(source)
    local pieces,index,length={},1,#source
    local function replaceRange(first,last,token)
        local segment=source:sub(first,last)
        local _,newlines=segment:gsub("\n","")
        table.insert(pieces,token..string.rep("\n",newlines))
    end
    local function longBracketEnd(at)
        local level=source:sub(at):match("^%[(=*)%[")
        if not level then return nil end
        local close="]"..level.."]"
        local _,last=source:find(close,at+#level+2,true)
        return last or length
    end
    while index<=length do
        local char=source:sub(index,index)
        if source:sub(index,index+1)=="--" then
            local last=longBracketEnd(index+2)
            if not last then last=(source:find("\n",index+2,true) or (length+1))-1 end
            replaceRange(index,last," ")
            index=last+1
        elseif char=="'" or char=='"' or char=="`" then
            local first=index
            index+=1
            while index<=length do
                local current=source:sub(index,index)
                if current=="\\" then index+=2
                elseif current==char then index+=1;break
                else index+=1 end
            end
            replaceRange(first,index-1,"__NON_LITERAL__")
        else
            local last=char=="[" and longBracketEnd(index) or nil
            if last then
                replaceRange(index,last,"__NON_LITERAL__")
                index=last+1
            else
                table.insert(pieces,char)
                index+=1
            end
        end
    end
    return table.concat(pieces)
end
-- A literal must occupy the entire single-line RHS, followed only by whitespace
-- or a comment. Prefixes such as 1/100, 2*math.pi and 10^3 are NOT values.
-- Source and RHS text never leave this function; only exact scalar values and
-- declaration counts are retained. Repeated local names are scope-ambiguous.
local function exactLiteral(rhs)
    if rhs=="true" then return true,true end
    if rhs=="false" then return true,false end
    local decimal=rhs:match("^[%+%-]?%d+%.?%d*$")
        or rhs:match("^[%+%-]?%.%d+$")
        or rhs:match("^[%+%-]?%d+%.?%d*[eE][%+%-]?%d+$")
        or rhs:match("^[%+%-]?%.%d+[eE][%+%-]?%d+$")
    if not decimal then return false,nil end
    local value=tonumber(rhs)
    if value and value==value and math.abs(value)<1000000 then return true,value end
    return false,nil
end
local function extractLiteralMetadata(source)
    local declarations,candidates={},{}
    local nonliteral=0
    local code=sourceWithoutCommentsOrStrings(source)
    -- Count declarations anywhere, including inline scopes and typed declarations.
    -- Multiple-name declarations are not exported, but still make a same-named
    -- standalone candidate ambiguous. Conservative over-exclusion is safe.
    for first in code:gmatch("local%s+([%w_]+)") do declarations[first]=(declarations[first] or 0)+1 end
    for nameList in code:gmatch("local%s+([%w_,%s]+)%s*=") do
        local first=true
        for name in nameList:gmatch("[%w_]+") do
            if first then first=false else declarations[name]=(declarations[name] or 0)+1 end
        end
    end
    for sourceLine in code:gmatch("[^\r\n]+") do
        -- A numeric/boolean literal cannot contain '--'; all other RHSs are
        -- excluded. No string, table, function, asset identifier or expression
        -- is evaluated or exported.
        local line=sourceLine:gsub("%-%-.*$","")
        local name,rhs=line:match("^%s*local%s+([%w_]+)%s*=%s*(.-)%s*$")
        if name then
            local ok,value=exactLiteral(rhs)
            if ok then candidates[name]=value else nonliteral+=1 end
        end
    end
    local values,ambiguous={},{}
    for name,value in pairs(candidates) do
        if declarations[name]==1 then values[name]=value
        else table.insert(ambiguous,{name=name,declarations=declarations[name],status="EXCLUDED_SCOPE_AMBIGUITY"}) end
    end
    table.sort(ambiguous,function(a,b)return a.name<b.name end)
    return values,{version="standalone_single_line_literals_v2",status="EXACT_LITERAL_DECLARATIONS_ONLY",
        repeated_names=ambiguous,excluded_nonliteral_RHS=nonliteral,
        behavior_claim="Static exact local initializer literals, not runtime configuration or behavior proof; statements restricted to single-line standalone declarations"}
end
-- Public only for our own CLI regression fixture. Source/RHS remain local.
M.extractLiteralMetadata=extractLiteralMetadata
function M.capture()
    local Players=game:GetService("Players")
    local HttpService=game:GetService("HttpService")
    local ReplicatedStorage=game:GetService("ReplicatedStorage")
    local p=Players.LocalPlayer or Players:GetPlayers()[1]
    assert(p,"Play session required")
    local containers={p:FindFirstChild("PlayerScripts"),p.Character,ReplicatedStorage:FindFirstChild("CharacterExperimentStockMetadataCache")}
    local rows={}
    for _,container in ipairs(containers) do
        if container then
            for _,item in ipairs(container:GetDescendants()) do
                if item:IsA("LuaSourceContainer") and item.Name~="CharacterBlackBoxMeasurement" then
                    local ok,source=pcall(function() return item.Source end)
                    local row={path=item:GetFullName(),class=item.ClassName,status=ok and "OBSERVED" or "BLOCKED"}
                    if ok then
                        row.source_length=#source
                        row.literal_constants,row.literal_extraction=extractLiteralMetadata(source)
                        -- No function bodies, keyframe data, source excerpts, or animation asset IDs.
                        row.enum_identifiers={}
                        local seen={}
                        for value in source:gmatch("Enum%.[%w_]+%.[%w_]+") do if not seen[value] then seen[value]=true; table.insert(row.enum_identifiers,value) end end
                        table.sort(row.enum_identifiers)
                        row.dependencies={}
                        seen={}
                        for value in source:gmatch("WaitForChild%s*%(%s*['\"]([%w_]+)['\"]") do if not seen[value] then seen[value]=true;table.insert(row.dependencies,value) end end
                        for value in source:gmatch("GetService%s*%(%s*['\"]([%w_]+)['\"]") do if not seen[value] then seen[value]=true;table.insert(row.dependencies,value) end end
                        table.sort(row.dependencies)
                        row.public_method_identifiers={}
                        seen={}
                        for value in source:gmatch(":([%w_]+)%s*%(") do if not seen[value] then seen[value]=true;table.insert(row.public_method_identifiers,value) end end
                        table.sort(row.public_method_identifiers)
                        row.signal_identifiers={}
                        seen={}
                        for value in source:gmatch("%.([%w_]+):Connect%s*%(") do if not seen[value] then seen[value]=true;table.insert(row.signal_identifiers,value) end end
                        table.sort(row.signal_identifiers)
                    else row.reason=tostring(source) end
                    table.insert(rows,row)
                end
            end
        end
    end
    table.sort(rows,function(a,b)return a.path<b.path end)
    local data={kind="a4_standard_script_metadata",schema=2,extractor_version="standalone_single_line_literals_v2",studio_version=version(),date_utc=DateTime.now():ToIsoDate(),
        run_id=ReplicatedStorage.CharacterExperimentTelemetry:GetAttribute("run_id"),rig=p.Character:FindFirstChildOfClass("Humanoid").RigType.Name,
        source_policy="No Roblox script source copied, only public Source-derived constants and dependency/API identifier sets",scripts=rows}
    local folder=ReplicatedStorage:FindFirstChild("CharacterExperimentMetadata") or Instance.new("Folder")
    folder.Name,folder.Parent="CharacterExperimentMetadata",ReplicatedStorage
    local full=HttpService:JSONEncode(data)
    for _,child in ipairs(folder:GetChildren()) do child:Destroy() end
    for index=1,#full,400 do
        local v=Instance.new("StringValue")
        v.Name=string.format("%06d",index)
        v.Value=full:sub(index,index+399)
        v.Parent=folder
        print("CHARACTER_METADATA_EXPORT "..HttpService:JSONEncode({n=v.Name,s=v.Value}))
    end
    print("CHARACTER_METADATA_DONE "..HttpService:JSONEncode({rows=#rows,bytes=#full,rig=data.rig,run_id=data.run_id}))
    return {rows=#rows,bytes=#full,rig=data.rig}
end
return M
