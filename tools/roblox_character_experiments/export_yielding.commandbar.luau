-- Our completed telemetry only. Yield between 50KB chunks to keep Studio responsive.
local h=game:GetService("HttpService")
local f=game:GetService("ReplicatedStorage"):FindFirstChild("CharacterExperimentTelemetry")
assert(f and f:GetAttribute("complete"),"autonomous measurement not finished")
local a=f:GetChildren()
table.sort(a,function(x,y)return x.Name<y.Name end)
task.spawn(function()
    for _,v in ipairs(a) do
        if v:IsA("StringValue") then
            for i=1,#v.Value,400 do
                print("CHARACTER_EXPORT_SMALL "..h:JSONEncode({n=v.Name,i=i,s=v.Value:sub(i,i+399),run_id=f:GetAttribute("run_id")}))
            end
            task.wait()
        end
    end
    print("CHARACTER_EXPORT_SMALL_DONE "..h:JSONEncode({run_id=f:GetAttribute("run_id"),bytes=f:GetAttribute("raw_bytes"),records=f:GetAttribute("records")}))
end)
