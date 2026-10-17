-- Entire source fixture below is Bobux-authored test input, never stock source.
local probe=require("./metadata_probe")
local values,info=probe.extractLiteralMetadata([====[
local decimal=0.31
local signed=-.5
local exponent=1e-6 -- trailing comment
local enabled=false
local prefix_div=1/100
local prefix_mul=2*math.pi
local prefix_pow=10^3
local prefix_and=true and false
local inline=0.2; local another=1
local repeatScope=0.1
do
 local repeatScope=0.2
end
local repeatNonliteral=4
do
 local repeatNonliteral=fn()
end
local repeatInline=4
do local repeatInline=3 end
local repeatMulti=4
local first,repeatMulti=fn()
-- local commented=1
--[=[
local blockComment=9
]=]
local text=[==[
local stringContent=7
]==]
local quoted="local shortStringContent=9"
local escaped="hi \" \n"
local interpolated=`local interpolationContent=1`
local array={1,2,3}
local hex=0x10
local assetNumber=123456789
local notFinite=1e999
]====])
local checked=0
local function check(condition,label)
    assert(condition,label)
    checked+=1
end
check(values.decimal==0.31,"decimal full literal")
check(values.signed==-0.5,"signed decimal")
check(values.exponent==1e-6,"scientific literal with comment")
check(values.enabled==false,"boolean false retained")
for _,name in ipairs({"prefix_div","prefix_mul","prefix_pow","prefix_and","inline","another","repeatScope","repeatNonliteral","repeatInline","repeatMulti","commented","blockComment","stringContent","shortStringContent","interpolationContent","array","hex","assetNumber","notFinite"}) do
    check(values[name]==nil,"must exclude "..name)
end
check(#info.repeated_names==4,"four ambiguous identifiers")
check(info.version=="standalone_single_line_literals_v2","version tag")
print("METADATA_LITERAL_TEST PASS="..checked.." FAIL=0")
