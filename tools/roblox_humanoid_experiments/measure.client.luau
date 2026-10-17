-- Black-box measurements in an ordinary Roblox Studio Play session.
-- Official public engine APIs only. The fixture's artificial values are logged.
-- PreSimulation and PostSimulation bracket one frame; they do not expose internal
-- solver substeps or a hypothetical exact impulse between them.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PREFIX = "HUMANOID_EXPERIMENT_JSON "
local runID = HttpService:GenerateGUID(false)
local startWall = os.clock()
local simTime = 0
local frame = 0
local sequence = 0
local allLines = {}
local summaries = {}
local failures = {}
local stage = "startup"
local active = nil
local humanoid, root, character
local move = Vector3.zero
local jumpRequested = false
local connections = {}
local previousCameraType, previousCameraCF
local originalGravity = workspace.Gravity
local telemetry = Instance.new("Folder")
telemetry.Name = "HumanoidExperimentTelemetry"
telemetry.Parent = ReplicatedStorage

local function vector(v) return {v.X, v.Y, v.Z} end
local function emit(kind, data)
	data = data or {}
	sequence += 1
	data.kind, data.schema, data.run_id = kind, 1, runID
	data.seq, data.wall_s, data.sim_s = sequence, os.clock() - startWall, simTime
	data.frame, data.case = frame, stage
	local line = PREFIX .. HttpService:JSONEncode(data)
	table.insert(allLines, line)
	-- Frame telemetry is retained in StringValue chunks; keep visible Output short.
	-- Numeric movement events can fire once per frame and are also retained silently.
	if kind == "case_result" or kind == "run_result" then
		-- Native Studio log lines can be truncated at ~4 KiB. Preserve the full
		-- object in raw chunks, while the visible one stays independently usable.
		local compact = table.clone(data)
		compact.state_events = nil
		if kind == "run_result" then
			compact.case_count = #data.cases
			compact.cases = nil
		else
			compact.request_before = nil
			compact.request_after = nil
			compact.landed = nil
			compact.landed_exit = nil
			compact.end_snapshot = nil
			compact.first_post_simulation = nil
			compact.back_extrapolation_note = nil
		end
		local short = PREFIX .. HttpService:JSONEncode(compact)
		if #short <= 800 then print(short) else
			print(PREFIX .. HttpService:JSONEncode({kind=kind, schema=1, run_id=runID, seq=sequence,
				case=stage, name=data.name, status=data.status, raw_in_telemetry_chunks=true}))
		end
	elseif kind ~= "frame" and kind ~= "humanoid_event" then
		if #line <= 800 then print(line) else
			print(PREFIX .. HttpService:JSONEncode({kind=kind, schema=1, run_id=runID, seq=sequence,
				case=stage, wall_s=data.wall_s, sim_s=simTime, raw_in_telemetry_chunks=true}))
		end
	end
	return data
end
local function fail(reason)
	table.insert(failures, {case=stage, reason=reason})
	emit("failure", {reason=reason})
end
local function snapshot()
	return {position=vector(root.Position), velocity=vector(root.AssemblyLinearVelocity),
		state=humanoid:GetState().Name, state_value=humanoid:GetState().Value,
		floor=humanoid.FloorMaterial.Name, move_direction=vector(humanoid.MoveDirection), jump=humanoid.Jump}
end
local function waitUntil(predicate, timeout, description)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if predicate() then return true end
		RunService.Heartbeat:Wait()
	end
	fail("timeout " .. tostring(timeout) .. "s: " .. description)
	return false
end
local function waitSeconds(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do RunService.Heartbeat:Wait() end
end
local function properties(h)
	local result = {}
	for _, key in ipairs({"Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "HipHeight",
		"AutoRotate", "AutoJumpEnabled", "BreakJointsOnDeath", "MaxSlopeAngle", "RequiresNeck", "EvaluateStateMachine",
		"AutomaticScalingEnabled", "PlatformStand", "Sit", "NameDisplayDistance", "HealthDisplayDistance"}) do
		local ok, value = pcall(function() return h[key] end)
		if ok then result[key] = value else result[key] = {unavailable=tostring(value)} end
	end
	result.RigType = h.RigType.Name
	return result
end
local function captureParts(label)
	local parts = {}
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then
			local offset = root.CFrame:PointToObjectSpace(part.Position)
			table.insert(parts, {name=part.Name, class=part.ClassName, size=vector(part.Size),
				root_relative_position=vector(offset), CanCollide=part.CanCollide, CanTouch=part.CanTouch,
				CanQuery=part.CanQuery, Massless=part.Massless, Transparency=part.Transparency,
				Anchored=part.Anchored, material=part.Material.Name, CollisionGroup=part.CollisionGroup})
		end
	end
	table.sort(parts, function(a,b) return a.name < b.name end)
	emit("r6_parts", {label=label, parts=parts, rig_source=character:GetAttribute("ExperimentRigSource")})
end

local function resetAt(position, lookTarget)
	active = nil
	move = Vector3.zero
	jumpRequested = false
	humanoid.Jump = false
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid:Move(Vector3.zero, false)
	root.Anchored = true
	local desiredRoot = lookTarget and CFrame.lookAt(position, lookTarget) or CFrame.new(position)
	-- Model pivot is not guaranteed to equal HRP.CFrame. Preserve the measured relation.
	local pivotToRoot = character:GetPivot():ToObjectSpace(root.CFrame)
	character:PivotTo(desiredRoot * pivotToRoot:Inverse())
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()
	root.Anchored = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	emit("reset", {snapshot=snapshot(), root_target=vector(position)})
end
local function settle()
	if not waitUntil(function()
		return humanoid.FloorMaterial ~= Enum.Material.Air
			and math.abs(root.AssemblyLinearVelocity.Y) < 0.15
			and humanoid:GetState() ~= Enum.HumanoidStateType.Landed
	end, 6, "grounded and outside Landed") then return false end
	-- Explicit post-Landed quiet period; no next jump is requested while airborne.
	waitSeconds(0.4)
	return true
end
local function beginCase(name, metadata)
	stage = name
	active = {metadata=metadata, frames={}, states={}, start_wall=os.clock(), start_wall_elapsed=os.clock()-startWall, start_sim=simTime,
		start_y=root.Position.Y, max_y=root.Position.Y, max_vy=-math.huge, landed=nil, landed_exit=nil,
		left_ground=false, first_post=nil, request_before=nil, request_after=nil}
	emit("case_begin", {parameters=metadata, snapshot=snapshot()})
end
local function finishCase(status)
	local a = active
	if not a then return end
	local result = {name=stage, status=status, parameters=a.metadata,
		start_y=a.start_y, apex_y=a.max_y, observed_apex_height=a.max_y-a.start_y,
		max_observed_vy=a.max_vy, request_before=a.request_before, request_after=a.request_after,
		first_post_simulation=a.first_post, state_events=a.states,
		landed=a.landed, landed_exit=a.landed_exit,
		landed_wall_duration=a.landed and a.landed_exit and (a.landed_exit.wall_s-a.landed.wall_s) or nil,
		landed_sim_duration=a.landed and a.landed_exit and (a.landed_exit.sim_s-a.landed.sim_s) or nil,
		duration_wall_s=os.clock()-a.start_wall, duration_sim_s=simTime-a.start_sim,
		frame_count=#a.frames, end_snapshot=snapshot()}
	if a.request_before and a.first_post then
		result.first_post_vy = a.first_post.velocity[2]
		result.ballistic_back_extrapolated_vy = a.first_post.velocity[2] + a.metadata.gravity*a.first_post.dt_sim_s
		result.back_extrapolation_note = "engineering estimate only; impulse timing and solver substeps not observed"
	end
	if a.metadata.measure_state then
		local values, horizontalValues, verticalValues, magnitudeValues, dtSum, weighted = {}, {}, {}, {}, 0, 0
		for _, sample in ipairs(a.frames) do
			if sample.state == a.metadata.measure_state and sample.wall_s-a.start_wall_elapsed >= a.metadata.warmup_s then
				local v=sample.velocity
				local magnitude=math.sqrt(v[1]^2+v[2]^2+v[3]^2)
				local speed=a.metadata.component == "vertical" and math.abs(v[2]) or magnitude
				table.insert(values, speed)
				table.insert(horizontalValues, math.sqrt(v[1]^2+v[3]^2))
				table.insert(verticalValues, v[2])
				table.insert(magnitudeValues, magnitude)
				dtSum += sample.dt_sim_s
				weighted += speed*sample.dt_sim_s
			end
		end
		table.sort(values)
		result.state_sample_count = #values
		if #values > 0 and dtSum > 0 then
			table.sort(horizontalValues)
			table.sort(verticalValues)
			table.sort(magnitudeValues)
			result.observed_horizontal_speed_median=horizontalValues[math.ceil(#values/2)]
			result.observed_vertical_velocity_median=verticalValues[math.ceil(#values/2)]
			result.observed_magnitude_speed_median=magnitudeValues[math.ceil(#values/2)]
			result.observed_speed_median = values[math.ceil(#values/2)]
			result.observed_speed_mean_dt_weighted = weighted/dtSum
			result.observed_speed_min = values[1]
			result.observed_speed_max = values[#values]
			result.observed_speed_ratio_to_WalkSpeed = result.observed_speed_median/a.metadata.WalkSpeed
		else
			result.status = "unmeasured"
			fail("no valid " .. a.metadata.measure_state .. " samples; no multiplier claimed")
		end
	end
	table.insert(summaries, result)
	emit("case_result", result)
	active = nil
end

local function jumpCase(usePower, value, gravity, repeatIndex)
	stage = string.format("jump_%s_%g_g%g_r%d", usePower and "power" or "height", value, gravity, repeatIndex)
	workspace.Gravity = gravity
	resetAt(Vector3.new(0, 4, 0))
	if not settle() then return end
	humanoid.UseJumpPower = usePower
	if usePower then humanoid.JumpPower = value else humanoid.JumpHeight = value end
	beginCase(stage, {type="jump", gravity=workspace.Gravity, UseJumpPower=usePower,
		JumpPower=humanoid.JumpPower, JumpHeight=humanoid.JumpHeight, repeat_index=repeatIndex,
		jump_request_method="Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) in PreSimulation; no velocity assignment"})
	jumpRequested = true
	local airborne = waitUntil(function() return active and active.left_ground end, 3, "jump leaves floor")
	local returned = airborne and waitUntil(function()
		return active and active.landed_exit ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	end, 8, "jump returns to ground after Landed")
	finishCase(returned and "measured" or "failed")
	waitSeconds(0.4)
end

local function dropCase(height, repeatIndex)
	workspace.Gravity = originalGravity
	stage = string.format("drop_%g_r%d", height, repeatIndex)
	resetAt(Vector3.new(0, 4, 0))
	if not settle() then return end
	local groundedY = root.Position.Y
	resetAt(Vector3.new(0, groundedY+height, 0))
	beginCase(stage, {type="drop", gravity=workspace.Gravity, requested_root_height_above_standing=height,
		grounded_root_y=groundedY, repeat_index=repeatIndex})
	local returned = waitUntil(function() return active and active.landed_exit ~= nil end, 8, "drop Landed then exit")
	finishCase(returned and "measured" or "failed")
	waitSeconds(0.4)
end

local function locomotionCase(kind, speed, repeatIndex, direction)
	workspace.Gravity = originalGravity
	stage = string.format("%s_ws%g_r%d", kind, speed, repeatIndex)
	humanoid.WalkSpeed = speed
	if kind == "climb" then
		resetAt(Vector3.new(40, 4, -4), Vector3.new(40, 4, 0))
		if not settle() then return end
	else
		resetAt(Vector3.new(-80, 16, 0), Vector3.new(-79, 16, 0))
	end
	local stateName = kind == "climb" and "Climbing" or "Swimming"
	beginCase(stage, {type=kind, gravity=workspace.Gravity, WalkSpeed=speed, repeat_index=repeatIndex,
		measure_state=stateName, component=kind == "climb" and "vertical" or "magnitude", warmup_s=0.5,
		input=vector(direction), relativeToCamera=false, fixture=kind == "climb" and "TrussPart" or "Terrain Water",
		water_volume_bounds=kind ~= "climb" and {minimum={-96,0,-32},maximum={-32,32,32}} or nil,
		water_start_root=kind ~= "climb" and vector(root.Position) or nil,
		forced_state=false})
	move = direction
	local entered = waitUntil(function() return humanoid:GetState().Name == stateName end, 5, "automatic " .. stateName .. " entry")
	if entered then waitSeconds(2.0) end
	move = Vector3.zero
	finishCase(entered and "measured" or "failed")
end

local function run()
	emit("run_begin", {studio=RunService:IsStudio(), client=RunService:IsClient(), engine_version=version(),
		gravity=workspace.Gravity, place_id=game.PlaceId, job_id=game.JobId,
		protocol="PreSimulation ChangeState(Jumping) / PostSimulation frame / StateChanged event; world-space Move(false); default PlayerModule controls disabled"})
	local fresh = Instance.new("Humanoid")
	emit("humanoid_defaults", {label="Instance.new Humanoid, before parenting or mutation", values=properties(fresh)})
	local enabledProbeEvents={}
	local enabledProbeConnection=fresh.StateEnabledChanged:Connect(function(...)
		local args={...}
		local event={argument_count=select("#",...), state_name=args[1].Name, state_value=args[1].Value,
			isEnabled=args[2], argument_types={typeof(args[1]),typeof(args[2])}}
		table.insert(enabledProbeEvents,event)
		emit("state_enabled_changed_probe_event",event)
	end)
	for callIndex,requested in ipairs({false,false,true,true}) do
		local countBefore=#enabledProbeEvents
		fresh:SetStateEnabled(Enum.HumanoidStateType.Jumping,requested)
		local countSynchronous=#enabledProbeEvents
		RunService.Heartbeat:Wait()
		emit("state_enabled_probe_call",{label="fresh unparented Instance.new Humanoid",call_index=callIndex,
			state="Jumping",requested=requested,GetStateEnabled=fresh:GetStateEnabled(Enum.HumanoidStateType.Jumping),
			event_count_before=countBefore,event_count_synchronous=countSynchronous,event_count_after_heartbeat=#enabledProbeEvents})
	end
	emit("state_enabled_probe_result",{label="fresh unparented Humanoid",requests={false,false,true,true},
		event_count=#enabledProbeEvents,events=enabledProbeEvents})
	enabledProbeConnection:Disconnect()
	fresh:Destroy()
	local enumItems = {}
	for _, item in ipairs(Enum.HumanoidStateType:GetEnumItems()) do table.insert(enumItems, {name=item.Name, value=item.Value}) end
	emit("enum_values", {enum="HumanoidStateType", values=enumItems})
	local player=Players.LocalPlayer
	if not waitUntil(function() return player.Character ~= nil end, 70, "server-created clean R6") then return end
	character=player.Character
	humanoid=character:WaitForChild("Humanoid", 10)
	root=character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then fail("character missing Humanoid or root") return end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then fail("fixture is not R6") return end
	-- Roblox inserts this ordinary, readable PlayerModule in every Play session.
	-- Its controls would otherwise write Humanoid.Jump=false after a one-frame
	-- scripted request. Disable their exported controls API, not engine physics.
	local playerScripts=player:WaitForChild("PlayerScripts", 10)
	local playerModule=playerScripts and playerScripts:WaitForChild("PlayerModule", 10)
	if not playerModule then fail("default Roblox PlayerModule absent; deterministic input unavailable") return end
	local controls=require(playerModule):GetControls()
	controls:Disable()
	emit("input_controller", {source="Roblox-inserted PlayerModule", controls_disabled=true,
		api="require(PlayerScripts.PlayerModule):GetControls():Disable()"})
	emit("humanoid_defaults", {label="empty-description R6 before test mutation", values=properties(humanoid),
		client_ownership=character:GetAttribute("ExperimentClientOwnership")})
	captureParts("before harness mutations")
	local camera=workspace.CurrentCamera
	previousCameraType,previousCameraCF=camera.CameraType,camera.CFrame
	emit("camera_player_defaults", {FieldOfView=camera.FieldOfView, CameraMinZoomDistance=player.CameraMinZoomDistance,
		CameraMaxZoomDistance=player.CameraMaxZoomDistance, CameraMode=player.CameraMode.Name,
		CameraType=camera.CameraType.Name})
	camera.CameraType=Enum.CameraType.Scriptable
	camera.CFrame=CFrame.lookAt(Vector3.new(15,20,28), Vector3.new(0,5,0))
	RunService:BindToRenderStep("HumanoidExperimentWorldMove", Enum.RenderPriority.Character.Value+1, function()
		if humanoid and root and root.Parent then humanoid:Move(move, false) end
	end)
	table.insert(connections, humanoid.StateChanged:Connect(function(old, new)
		local event=emit("state_changed", {old=old.Name, old_value=old.Value, new=new.Name, new_value=new.Value,
			snapshot=snapshot()})
		if active then
			table.insert(active.states, event)
			if new == Enum.HumanoidStateType.Landed then active.landed=event end
			if old == Enum.HumanoidStateType.Landed then active.landed_exit=event end
		end
	end))
	for _, name in ipairs({"Jumping", "FreeFalling", "FallingDown", "GettingUp", "Running", "Climbing", "Swimming", "HealthChanged"}) do
		table.insert(connections, humanoid[name]:Connect(function(value)
			emit("humanoid_event", {event=name, value=value, snapshot=snapshot()})
		end))
	end
	table.insert(connections, RunService.PreSimulation:Connect(function(dt)
		frame += 1
		if not active then return end
		if jumpRequested then
			active.request_before=snapshot()
			emit("jump_request_before", {snapshot=active.request_before, dt_sim_s=dt})
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			active.request_after=snapshot()
			emit("jump_request_after", {snapshot=active.request_after, dt_sim_s=dt})
			jumpRequested=false
		end
		local record=snapshot()
		record.phase,record.dt_sim_s="pre",dt
		emit("frame", record)
	end))
	table.insert(connections, RunService.PostSimulation:Connect(function(dt)
		simTime += dt
		if not active then return end
		local record=snapshot()
		record.phase,record.dt_sim_s="post",dt
		local entry=emit("frame", record)
		table.insert(active.frames, entry)
		active.max_y=math.max(active.max_y, root.Position.Y)
		active.max_vy=math.max(active.max_vy, root.AssemblyLinearVelocity.Y)
		if active.request_before and not active.first_post then active.first_post=entry end
		if humanoid.FloorMaterial == Enum.Material.Air or root.Position.Y > active.start_y+0.1 then active.left_ground=true end
	end))
	-- Quiet the fixture's autojump only AFTER recording real defaults.
	humanoid.AutoJumpEnabled=false
	if not settle() then return end
	captureParts("settled grounded before jump suite")
	for _, gravity in ipairs({196.2, 98.1, 50}) do
		for _, height in ipairs({7.2, 10, 15, 20}) do jumpCase(false, height, gravity, 1) end
		for _, power in ipairs({50, 70}) do jumpCase(true, power, gravity, 1) end
	end
	-- Five heights, with two repeats to retain variance rather than invent fixed timing.
	for _, height in ipairs({5, 10, 20, 40, 80}) do
		for repeatIndex=1,2 do dropCase(height, repeatIndex) end
	end
	for repeatIndex=1,3 do locomotionCase("climb",16,repeatIndex,Vector3.new(0,0,1)) end
	for repeatIndex=1,3 do locomotionCase("swim",16,repeatIndex,Vector3.new(1,0,0)) end
	locomotionCase("swim",24,1,Vector3.new(1,0,0))
end

local ok, err=xpcall(run, debug.traceback)
if not ok then fail("uncaught harness error: " .. tostring(err)) end
stage="complete"
workspace.Gravity=originalGravity
move=Vector3.zero
jumpRequested=false
RunService:UnbindFromRenderStep("HumanoidExperimentWorldMove")
for _, connection in ipairs(connections) do connection:Disconnect() end
if humanoid and root then
	humanoid:Move(Vector3.zero,false)
	humanoid.Jump=false
	root.Anchored=false
end
if previousCameraType then
	workspace.CurrentCamera.CameraType=previousCameraType
	workspace.CurrentCamera.CFrame=previousCameraCF
end
emit("run_result", {status=#failures==0 and "complete" or "completed_with_failures", cases=summaries, failures=failures,
	interpretation="All reported velocities are sampled, not an exact unobservable intra-step jump impulse."})
-- Preserve raw telemetry in ordinary replicated objects if Studio Output truncates.
-- These values live only in this separate Play session; no disk-writing APIs or plugins.
local chunk={}
local chunkSize=0
local chunkIndex=0
local function flush()
	if #chunk==0 then return end
	chunkIndex+=1
	local value=Instance.new("StringValue")
	value.Name=string.format("chunk_%04d",chunkIndex)
	value.Value=table.concat(chunk,"\n")
	value.Parent=telemetry
	chunk={}
	chunkSize=0
end
for _, line in ipairs(allLines) do
	if chunkSize+#line > 45000 then flush() end
	table.insert(chunk,line)
	chunkSize+=#line+1
end
flush()
telemetry:SetAttribute("RecordCount",#allLines)
telemetry:SetAttribute("RunID",runID)
telemetry:SetAttribute("Complete",true)
print("HUMANOID_EXPERIMENT_DONE " .. runID .. " records=" .. tostring(#allLines) .. " failures=" .. tostring(#failures))
