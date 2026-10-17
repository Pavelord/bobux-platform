extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var engine: Node = root.get_node_or_null("LuaScriptEngine")
	if engine == null or not ClassDB.class_exists("LuaAPI"):
		push_error("[studio_authoring] LuaScriptEngine or LuaAPI is unavailable")
		quit(2)
		return

	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	workspace.set_meta("roblox_stud_scale", 0.5)
	root.add_child(workspace)
	var script_node := Node.new()
	script_node.name = "AuthoringProbe"
	script_node.set_meta("roblox_class", "Script")
	workspace.add_child(script_node)

	var source := """
local terrain = workspace.Terrain
terrain:Clear()
terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(8, 4, 8), Enum.Material.Grass)
assert(terrain:CountCells() > 0, 'FillBlock did not create terrain cells')
terrain:FillBall(Vector3.new(8, 0, 0), 4, Enum.Material.Rock)
terrain:FillCylinder(CFrame.new(-8, 0, 0), 8, 4, Enum.Material.Sand)
terrain:FillWedge(CFrame.new(0, 8, 0), Vector3.new(8, 8, 8), Enum.Material.Ground)
terrain:FillRegion(Region3.new(Vector3.new(-4, -4, -4), Vector3.new(4, 4, 4)), 4, Enum.Material.Grass)
assert(terrain:CountCells() > 8, 'Terrain shape methods did not add cells')
local cell = terrain:WorldToCell(Vector3.new(0, 0, 8))
local center = terrain:CellCenterToWorld(cell.X, cell.Y, cell.Z)
local corner = terrain:CellCornerToWorld(cell.X, cell.Y, cell.Z)
assert(typeof(cell) == 'Vector3' and typeof(center) == 'Vector3', 'Terrain cell conversion failed')
assert(cell.X == 0 and cell.Y == 0 and cell.Z == 2, 'Terrain Z-axis cell conversion is reversed')
assert((center - Vector3.new(2, 2, 6)).Magnitude < 0.1, 'CellCenterToWorld returned the wrong voxel center')
assert((corner - Vector3.new(0, 0, 4)).Magnitude < 0.1, 'CellCornerToWorld returned the wrong voxel corner')
local count_before_air = terrain:CountCells()
terrain:FillBall(Vector3.new(0, 0, 0), 4, Enum.Material.Air)
assert(terrain:CountCells() < count_before_air, 'Enum.Material.Air did not clear terrain cells')

local part = Instance.new('Part')
part.Anchored = true
part.Parent = workspace
local tween = game:GetService('TweenService'):Create(part, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {
    Position = Vector3.new(8, 0, 0)
})
tween:Play()
task.wait(0.14)
assert((part.Position - Vector3.new(8, 0, 0)).Magnitude < 0.2, 'TweenService did not move the part')

local sound = Instance.new('Sound')
sound.SoundId = 'res://RobloxAudioPack_2018/SFX/action_jump.mp3'
sound.Volume = 0.05
sound.Parent = part
sound:Play()
task.wait(0.03)
assert(sound.Playing, 'Sound:Play did not start the attached sound')
assert(sound.Parent == part, 'Sound was not parented to the moving part')
sound:Stop()
workspace:SetAttribute('AuthoringProbeDone', terrain:CountCells())
"""
	var start_result: Dictionary = engine.start_script(source, script_node, {"retain": true})
	var deadline := Time.get_ticks_msec() + 8000
	while not workspace.has_meta("attribute_AuthoringProbeDone") and Time.get_ticks_msec() < deadline:
		await process_frame

	var done := workspace.has_meta("attribute_AuthoringProbeDone")
	var cell_count := int(workspace.get_meta("attribute_AuthoringProbeDone", 0))
	var terrain_node := workspace.get_node_or_null("Terrain")
	var terrain_grid := terrain_node.get_node_or_null("EditableTerrainGrid") as GridMap if terrain_node != null else null
	var terrain_properties: Dictionary = terrain_node.get_meta("roblox_properties", {}) if terrain_node != null else {}
	var saved_cells: Variant = terrain_properties.get("Cells", [])
	var runtime_errors: Dictionary = engine.get_runtime_diagnostics()
	var ok := bool(start_result.get("ok", false)) and done and cell_count > 8 and int(runtime_errors.get("failed", 0)) == 0
	ok = ok and terrain_grid != null and terrain_grid.get_used_cells().size() == cell_count
	ok = ok and saved_cells is Array and saved_cells.size() == cell_count
	print("[studio_authoring] ok=", ok, " start=", start_result, " cells=", cell_count,
		" saved_cells=", saved_cells.size() if saved_cells is Array else -1, " diagnostics=", runtime_errors)
	_stop_audio_players(workspace)
	engine.stop_all_scripts(workspace)
	workspace.queue_free()
	await process_frame
	engine.release_stopped_script_states()
	preload("res://addons/roblox_runtime/roblox_sound_runtime.gd").streams.clear()
	await process_frame
	await process_frame
	quit(0 if ok else 1)


func _stop_audio_players(root_node: Node) -> void:
	if root_node is AudioStreamPlayer:
		(root_node as AudioStreamPlayer).stop()
		(root_node as AudioStreamPlayer).stream = null
	elif root_node is AudioStreamPlayer3D:
		(root_node as AudioStreamPlayer3D).stop()
		(root_node as AudioStreamPlayer3D).stream = null
	for child in root_node.get_children():
		_stop_audio_players(child)
