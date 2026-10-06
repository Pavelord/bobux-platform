extends RefCounted

# Explicit, versioned upgrades for known archived scripts. Never pattern-patch
# arbitrary user code. The original stays available in the imported manifest.
const NDS_CONTROLLER := "e1b44f72514c131463003838e736e8448a2c6a6e12499ae2c8e597670150350c"
const NDS_GUI := "b89e8c1ceeecb9e4a958b82c1f349676b02ab1b388f3927864a8c5731fd2541a"

static func upgrade(entry: Dictionary) -> void:
	var original := str(entry.get("source", ""))
	var source := original.replace("\r", "")
	var fingerprint := source.sha256_text()
	# Upgrade our own saved output, but never replace an author's edited script.
	# New outputs carry a checksum; v2 predates that and is matched exactly.
	if str(entry.get("compatibility_upgrade", "")).begins_with("natural-disasters-2011-"):
		var restored := {"source": str(entry.get("original_source", ""))}
		upgrade(restored)
		if not restored.has("compatibility_upgrade"):
			return
		var canonical := str(restored["source"]).replace("\r", "")
		var previous_v2 := canonical.replace("e.Visible=false\n\t\t\te.BlastRadius=7", "e.BlastRadius=7")
		var saved_fingerprint := str(entry.get("compatibility_source_sha256", ""))
		if fingerprint == saved_fingerprint or source == canonical or source == previous_v2:
			for key in ["source", "source_length", "original_source", "compatibility_upgrade", "compatibility_source_sha256"]:
				entry[key] = restored[key]
		return
	if fingerprint in [NDS_CONTROLLER, "2bb67779462ff774d4a302ee84d4b395771e55005df73c05eb38bd2ed0c25c4b"]:
		# The 2011 controller counted 30 wait() calls as a second. Keep the
		# simulation clock independent of rendering and cooperative script slices.
		source = source.replace("\twhile timer>0 do\n\t\twait(rate)\n\t\ta=a+1", "\tlocal phaseStarted=tick()\n\twhile timer>0 do\n\t\twait(rate)\n\t\tlocal previousFrame=a\n\t\ta=math.floor((tick()-phaseStarted)/rate)\n\t\ttimer=math.max(0,maxtimer-(tick()-phaseStarted))")
		source = source.replace("\t\t\ttimer=timer-1\n", "")
		source = source.replace("if a%30==0 then", "if math.floor(a/30)>math.floor(previousFrame/30) then")
		source = source.replace("if (a+15)%30==0 then", "if math.floor((a+15)/30)>math.floor((previousFrame+15)/30) then")
		# Updating each wave segment in a yielding Lua loop exposes half-moved
		# geometry. BulkMoveTo publishes the complete new pose in one operation.
		source = source.replace("\tfor _,Object in pairs(modl:GetChildren()) do\n\t\tObject.CFrame=goalcframe:toWorldSpace(centercframe:toObjectSpace(Object.CFrame))\n\tend", "\tlocal parts=modl:GetChildren()\n\tlocal frames={}\n\tfor i,Object in ipairs(parts) do\n\t\tframes[i]=goalcframe:toWorldSpace(centercframe:toObjectSpace(Object.CFrame))\n\tend\n\tgame.Workspace:BulkMoveTo(parts,frames)")
		# A 60-second crossing must not become several minutes on a slow device.
		source = source.replace("\t\tlocal wavepercentage=a/(maxtimer*30)", "\t\tlocal wavepercentage=math.min((tick()-waveStarted)/maxtimer,1)")
		source = source.replace("\ttsunamiwave=game.Lighting.TsunamiWave:clone()", "\tlocal waveStarted=tick()\n\ttsunamiwave=game.Lighting.TsunamiWave:clone()")
		if not source.contains("script:SetAttribute('DisasterName'"):
			source = source.replace("\tdisaster.Start()", "\tscript:SetAttribute('DisasterName',disaster.Name)\n\tscript.Status.Value='Disaster'\n\tdisaster.Start()")
		source = _upgrade_controller(source)
	elif fingerprint in [NDS_GUI, "54f722d4504a2fa9d719d5308481296f582095d16e4b227f9aa1887aa9a17af0"]:
		source = source.replace("fscp=1", "fscp=0")
		source = source.replace("tostring(list2[i])", "tostring(math.floor(list2[i]))")
		if not source.contains("DisasterAnnouncement"):

			source += """
-- Bobux archive upgrade: an announcement missing from this 2011 place file.
local announcement=Instance.new('TextLabel')
announcement.Name='DisasterAnnouncement'
announcement.Size=UDim2.new(0.8,0,0,54)
announcement.Position=UDim2.new(0.1,0,0.12,0)
announcement.BackgroundColor3=Color3.fromRGB(26,34,46)
announcement.BackgroundTransparency=0.15
announcement.TextColor3=Color3.fromRGB(255,225,100)
announcement.TextSize=26
announcement.TextWrapped=true
announcement.ZIndex=20
announcement.Visible=false
announcement.Parent=script.Parent
status.Changed:Connect(function()
    announcement.Visible=status.Value=='Disaster'
    if announcement.Visible then
        announcement.Text='Disaster: '..tostring(game.Workspace.Script:GetAttribute('DisasterName'))
    end
end)
"""
	elif fingerprint == "84ce42c8d122b97b7fe6808eacb889711b109f0311020a7d0d4012be5b03fbf1":
		source = """
-- Bobux archive upgrade: count genuine landings, not mid-air deceleration.
local character=script.Parent
local humanoid=character:WaitForChild('Humanoid')
local torso=character:WaitForChild('Torso')
local fastest=0
local wasAir=false
local lastHeight=torso.Position.Y
local lastTime=tick()
while character.Parent and humanoid.Health>0 do
    wait()
    local now=tick()
    local vertical=torso.Velocity.Y
    local height=torso.Position.Y
    local floor=tostring(humanoid.FloorMaterial)
    local inAir=floor=='Air' or floor=='Enum.Material.Air'
    -- A scripted teleport is not an impact, even when it ends on the ground.
    local teleported=math.abs(height-lastHeight)>math.max(12,(math.abs(fastest)+math.abs(vertical))*(now-lastTime)+6)
    if teleported then fastest=0 wasAir=false end
    if inAir then
        fastest=math.min(fastest,vertical)
    elseif wasAir then
        -- Ordinary jumps and small drops are safe. Damage scales gradually
        -- above a 25-stud fall; only a very large fall is immediately fatal.
        if fastest < -100 then humanoid:TakeDamage(math.min(100,(-fastest-100)/80*100)) end
        fastest=0
    else
        fastest=0
    end
    wasAir=inAir
    lastHeight=height
    lastTime=now
end
"""
	else:
		return
	entry["original_source"] = entry.get("original_source", original)
	entry["source"] = source
	entry["source_length"] = source.length()
	entry["compatibility_upgrade"] = "natural-disasters-2011-v7"
	entry["compatibility_source_sha256"] = source.sha256_text()


static func _upgrade_controller(source: String) -> String:
	# The original map walk recursively visited every island descendant in one
	# Lua resume. Large islands exceed Bobux's per-resume budget. Preserve the
	# original depth-first order but yield after a small batch of instances.
	var spread_begin := source.find("function spread(mdl,func)\n")
	var spread_end := source.find("\n\nmeteorstorm={}", spread_begin)
	if spread_begin >= 0 and spread_end > spread_begin:
		source = source.substr(0, spread_begin) + """function spread(mdl,func)
    if not mdl or mdl.Parent==nil then return end
    local pending={mdl}
    local processed=0
    while #pending>0 do
        local current=table.remove(pending)
        if current and current.Parent~=nil then
            func(current)
            local children=current:GetChildren()
            for i=#children,1,-1 do pending[#pending+1]=children[i] end
        end
        processed=processed+1
        if processed>=48 then
            processed=0
            wait()
        end
    end
end""" + source.substr(spread_end)
	# Initialise players already present when the controller starts, and do not
	# wait forever for Character to become nil in a respawnable Godot body.
	var begin := source.find("function onPlayerEntered(newPlayer)")
	var end := source.find("game.Players.ChildAdded:connect(onPlayerEntered)", begin)
	if begin >= 0 and end > begin:
		source = source.substr(0, begin) + """function onPlayerEntered(newPlayer)
    if not newPlayer:IsA('Player') then return end
    newPlayer.CharacterAdded:Connect(function() onPlayerRespawn('Character',newPlayer) end)
    onPlayerRespawn('Character',newPlayer)
end
for _,player in ipairs(game.Players:GetPlayers()) do onPlayerEntered(player) end
""" + source.substr(end)
	source = source.replace("local cs=script.CharacterScript:clone()", "local previous=player.Character:FindFirstChild('CharacterScript')\n\t\tif previous then previous:Destroy() end\n\t\tlocal cs=script.CharacterScript:clone()")
	source = source.replace("st.Parent=v.Character", "st.Parent=v.Character\n\t\t\t\t\t\tlocal connection\n\t\t\t\t\t\tconnection=h.Died:Connect(function() if st.Parent then st:Destroy() end connection:Disconnect() end)")
	# The archived models contain sub-stud gaps at old form-factor seams.
	source = source.replace("ns:MakeJoints()", "ns:SetAttribute('BobuxRepairLegacySeams',true)\n\tns:MakeJoints()")
	# A shuffle bag visits each island/disaster before repeating it.
	source = source.replace("local rs=math.random(1,#structures)", "local rs=archivePick(structures,'maps')")
	source = source.replace("local rd=math.random(1,#disasters)", "local rd=archivePick(disasters,'disasters')")
	# Run both players and debris every update; frame parity can otherwise
	# permanently starve one branch when time skips frames on a slow machine.
	source = source.replace("if a%2==0 then", "do")
	source = source.replace("\t\telse\n\t\t\tfor i,v in ipairs(game.Players:GetChildren())", "\t\tend\n\t\t do\n\t\t\tfor i,v in ipairs(game.Players:GetChildren())")
	# Query the cyclone volume instead of traversing the entire island in Lua
	# every frame. Otherwise script slicing leaves debris without sustained lift.
	source = source.replace("updatetornado(game.Workspace.Structure)", "for _,debris in ipairs(game.Workspace:GetPartBoundsInBox(CFrame.new(tornadopos+Vector3.new(0,maxhight/2,0)),Vector3.new(breakradius*2,maxhight,breakradius*2))) do if debris:IsDescendantOf(game.Workspace.Structure) then updatetornado(debris) end end")
	# Preserve the original velocity field, but read each Instance property once.
	# Scalar trig is equivalent to its CFrame construction and avoids dozens of
	# cross-language object allocations for every brick on every update.
	begin = source.find("function updatetornado(mdl)")
	end = source.find("\nfunction startfire(mdl)", begin)
	if begin >= 0 and end > begin:
		source = source.substr(0, begin) + TORNADO_UPDATE + source.substr(end)
	source = source.replace("if math.random(1,2)==1 then\n\t\t\t\t\t\t\tmdl:remove()", "if math.random(1,2)==1 and not mdl.Parent:FindFirstChild('Humanoid') then\n\t\t\t\t\t\t\tmdl:remove()")
	# A complete slab sweep covers the visible wave's travel since last update.
	begin = source.find("\t\tfor i=1,wavesegments do")
	end = source.find("\t\tif math.floor(a/30)", begin)
	if begin >= 0 and end > begin:
		source = source.substr(0, begin) + "\t\tarchiveWaveHit(tsunamiwave, tsunamicurrent, wavevec, wavespeed)\n" + source.substr(end)
	# Keep the authored explosion flash at the bolt's point of impact.
	source = source.replace("tp.Parent=game.Workspace.Structure", "tp.Parent=game.Workspace.Structure\n\tarchiveFunnel(tp)")
	return HELPERS + source

const TORNADO_UPDATE := """function updatetornado(mdl)
    if not mdl or not mdl.Parent then return end
    if not mdl:IsA('BasePart') then
        local humanoid=mdl:FindFirstChildOfClass('Humanoid')
        if humanoid then
            local torso=mdl:FindFirstChild('Torso') or mdl:FindFirstChild('HumanoidRootPart')
            if torso and humanoid.Health>0 then updatetornado(torso) end
            return
        end
        for _,child in ipairs(mdl:GetChildren()) do updatetornado(child) end
        return
    end
    if mdl.Anchored then return end
    local position=mdl.Position
    local x,y,z=position.X,position.Y,position.Z
    if y>=maxhight then return end
    local cx,cz=tornadopos.X,tornadopos.Z
    local dx,dz=x-cx,z-cz
    local dist=math.sqrt(dx*dx+dz*dz)
    if dist>=breakradius then return end
    local character=mdl.Parent:FindFirstChild('Humanoid')
    local tagged=mdl:FindFirstChild('TornadoTag')
    if not character and not tagged then mdl:BreakJoints() end
    local height=y/(maxhight-low)
    local radial=pull+(push-pull)*height
    if dist<cycloneradius then radial=push end
    local angle=math.atan2(dx,dz)+0.1
    local vx=cx+math.sin(angle)*(dist+radial)-x
    local vz=cz+math.cos(angle)*(dist+radial)-z
    local length=math.sqrt(vx*vx+vz*vz)
    if length>0 then vx,vz=vx/length,vz/length end
    local strength=math.min(1,1-math.max(0,(dist-cycloneradius)/(breakradius-cycloneradius))+0.1)
    local planar=strength*speed*(1+2*height)
    mdl.Velocity=Vector3.new(vx*planar,math.max(lift*(strength+height)*speed,45*strength),vz*planar)
    if not tagged then
        mdl.RotVelocity=Vector3.new(math.random(-2,2),3,math.random(-2,2))
        if math.random(1,2)==1 and not character then
            mdl:Destroy()
        else
            local tag=Instance.new('StringValue')
            tag.Name='TornadoTag'
            tag.Parent=mdl
        end
    end
end
"""

const HELPERS := """
-- Versioned Bobux archive corrections for this exact 2011 controller.
local archiveBags={}
local archiveLast={}
function archivePick(items,key)
    local bag=archiveBags[key]
    if not bag or #bag==0 then
        bag={}
        for i=1,#items do bag[i]=i end
        for i=#bag,2,-1 do local j=math.random(1,i) bag[i],bag[j]=bag[j],bag[i] end
        if #bag>1 and bag[#bag]==archiveLast[key] then bag[1],bag[#bag]=bag[#bag],bag[1] end
        archiveBags[key]=bag
    end
    local picked=table.remove(bag)
    archiveLast[key]=picked
    return picked
end
local archiveWavePrevious=nil
local archiveWaveObject=nil
local archiveWaveDamaged={}
local archiveWaveParts={}
function archiveWaveHit(wave,frame,direction,speed)
    if archiveWaveObject~=wave then
        archiveWaveObject=wave
        archiveWavePrevious=frame.Position
        archiveWaveDamaged={}
        archiveWaveParts={}
    end
    local moved=(frame.Position-archiveWavePrevious).Magnitude
    local center=(frame.Position+archiveWavePrevious)*0.5
    -- The authored wave extends -52.5..101.5 studs around Center, then is
    -- turned 180 degrees by cframemodel. Include the swept travel this frame.
    local volume=CFrame.new(center)*CFrame.Angles(0,waveangle,0)*CFrame.new(-24.5,0,0)
    local size=Vector3.new(154+moved,wavehight,wavelength)
    -- Process people before the potentially large list of destructible bricks.
    for _,player in ipairs(game.Players:GetPlayers()) do
        local character=player.Character
        local torso=character and character:FindFirstChild('Torso')
        local h=character and character:FindFirstChildOfClass('Humanoid')
        if torso and h and h.Health>0 and not archiveWaveDamaged[h] then
            local point=volume:PointToObjectSpace(torso.Position)
            if math.abs(point.X)<=size.X/2+1 and math.abs(point.Y)<=size.Y/2+2 and math.abs(point.Z)<=size.Z/2+1 then
                archiveWaveDamaged[h]=true
                h:TakeDamage(100)
                torso.Velocity=direction*-speed+Vector3.new(0,30,0)
            end
        end
    end
    local hits=game.Workspace:GetPartBoundsInBox(volume,size)
    for index,part in ipairs(hits) do
        if not archiveWaveParts[part] and not part.Anchored and not part:IsDescendantOf(wave) and part:IsDescendantOf(game.Workspace.Structure) then
            archiveWaveParts[part]=true
            part:BreakJoints()
            part.Velocity=direction*-speed+Vector3.new(0,20,0)
        end
        -- Destruction is bounded work. Yield between batches so a whole
        -- building cannot starve the network and trip the script watchdog.
        if index%16==0 then task.wait() end
    end
    archiveWavePrevious=frame.Position
end
function archiveFunnel(part)
    local old=part:FindFirstChildOfClass('Smoke')
    if old then old.Enabled=false end
    for i=0,5 do
        local ring=Instance.new('Part')
        ring.Name='FunnelLayer'
        ring.Size=Vector3.new(1,1,1)
        ring.Transparency=1
        ring.Anchored=true
        ring.CanCollide=false
        ring.CanQuery=false
        ring.Parent=part
        local smoke=Instance.new('Smoke')
        smoke.Size=16+i*9
        smoke.RiseVelocity=12
        smoke.Opacity=0.75
        smoke.Color=Color3.fromRGB(80+i*8,86+i*8,94+i*8)
        smoke.Parent=ring
    end
    local running
    running=game:GetService('RunService').Heartbeat:Connect(function()
        if not part.Parent then running:Disconnect() return end
        local i=0
        for _,ring in ipairs(part:GetChildren()) do
            if ring.Name=='FunnelLayer' then
                ring.CFrame=part.CFrame*CFrame.new(math.sin(tick()*3+i)*i, i*16, math.cos(tick()*3+i)*i)
                i=i+1
            end
        end
    end)
end
"""
