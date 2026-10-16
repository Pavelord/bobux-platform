-- Executes our serializer only, not a mock of native Roblox inheritance.
local Common=require("./common")
local values={False=false,True=true,Zero=0,Empty=""}
local input=setmetatable({}, {__index=function(_,key)
    if key=="Error" then error("intentional own serializer test error") end
    return values[key]
end})
local observed=Common.props(input,{"False","True","Zero","Empty","Nil","Error"})
assert(type(observed.False)=="boolean" and observed.False==false,"successful false must remain a boolean")
assert(type(observed.True)=="boolean" and observed.True==true,"true preserved")
assert(type(observed.Zero)=="number" and observed.Zero==0,"zero preserved")
assert(observed.Empty=="","empty string preserved")
assert(type(observed.Nil)=="table" and observed.Nil.is_nil==true,"observed nil distinct from failure")
assert(type(observed.Error)=="table" and observed.Error.status=="NOT_OBSERVABLE" and string.find(observed.Error.reason,"intentional own serializer test error",1,true),"failed getter distinct from false/nil")
assert(Common.props(nil,{"False"}).status=="NOT_OBSERVABLE","missing instance distinct from present false")
print("ORDINARY_SERIALIZER_TEST PASS 7 own-data assertions; native inheritance NOT_RUN")
