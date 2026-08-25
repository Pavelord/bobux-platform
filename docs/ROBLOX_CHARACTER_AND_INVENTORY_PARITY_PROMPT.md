# Bobux Roblox-Like Runtime and Studio Contract

Use this document as the implementation prompt and acceptance contract for all
future work in `C:\robloxclone`. It replaces vague requests to "copy Roblox"
with behavior that can be implemented, saved, loaded, profiled, and tested.

Bobux must provide original code and assets with Roblox-like workflows and API
compatibility. Do not copy proprietary Roblox source code, bundled assets, or
branding. Compatibility means matching documented behavior and data semantics.

## Objective

Build one scalable platform composed of:

1. Bobux Studio 2.0 for authoring places, hierarchy, properties, GUI, scripts,
   terrain, characters, models, and tools.
2. A shared Roblox-like DataModel used by Studio preview, playtest, exported
   maps, the dedicated server, and clients.
3. An authority-first multiplayer runtime with predictable character movement,
   camera behavior, inventory, GUI, scripting, and replication.
4. A staged `.rbxl/.rbxlx` compatibility pipeline that maps supported Roblox
   instances onto native Bobux runtime objects without exposing storage assets
   in Workspace or silently replacing unsupported objects.

## Hard Rules

- Work in `scripts/place_editor/studio.gd`; do not develop the old editor under
  `exiting_game`.
- The server is authoritative for world state, health, tools, and persistence.
- Studio preview and runtime must consume the same manifest contract.
- A visible button is enabled only when it performs a real operation.
- Unsupported imported behavior must produce a structured diagnostic. Never
  report success after silently dropping an object, asset, or script.
- Large maps load incrementally with progress and cancellation. Do not block the
  main thread for network downloads or bulk instance construction.
- Every authored feature survives save, reopen, playtest, and publish.
- Do not deploy from this task unless the user explicitly requests deployment.

## Canonical DataModel

`addons/roblox_studio/roblox_data_model.gd` is the authoring source of truth.
The following services are canonical and appear in this Explorer order:

- Workspace
- Players
- Lighting
- MaterialService
- ReplicatedFirst
- ReplicatedStorage
- ServerScriptService
- ServerStorage
- StarterGui
- StarterPack
- StarterPlayer
- Teams
- SoundService
- TextChatService

Runtime-only query services include RunService, TweenService, Debris,
CollectionService, UserInputService, ContextActionService, MarketplaceService,
BadgeService, InsertService, and PhysicsService.

Every instance has:

- stable `roblox_ref` identity;
- `roblox_class`, Name, Parent, Archivable, Tags, and Attributes;
- class-specific properties in `roblox_properties`;
- a deterministic parent relationship in the manifest;
- a clear client, server, or shared execution domain.

Workspace is the visible 3D world. ReplicatedStorage and ServerStorage are
libraries, not hidden piles of physical parts. Scripts clone templates from
storage into Workspace when required.

## Studio Shell

The Studio shell must remain usable at 1280x720, 1920x1080, and common laptop
scales without horizontal page scrolling. The central viewport receives the
remaining space between docked panels.

Required functional areas:

- File: new, open/import, save, save as, publish, close.
- Edit: undo, redo, cut, copy, paste, duplicate, delete, group, lock, anchor,
  select all.
- View/Window: zoom, full screen, viewport grid, wireframe, GUI preview,
  collision preview, focus selection, screenshot, audio mute, Explorer,
  Properties, Toolbox, Assets, Output, Command Bar, and Insert Object.
- Test: play, pause/resume, stop, viewport capture, and runtime diagnostics.
- Home/Model transform tools: exactly one of Select, Move, Scale, Rotate, or
  Transform is active. Gizmos modify the complete selection and commit one undo
  snapshot per drag.

No toolbar action may be accepted based only on a status label changing. Its
result must be observable in the live DataModel and persisted manifest.

## Explorer Contract

`addons/roblox_studio/roblox_explorer.gd` renders the live DataModel.

- Services use fixed canonical order.
- Children use their real parent hierarchy and stable identity.
- Filtering keeps matching ancestors visible.
- Expansion state survives refreshes.
- F2 rename, duplicate, delete, context insertion, and drag-and-drop reparent
  operate on the underlying node.
- Helper nodes used for collision, selection, and editor visuals never appear.
- Imported storage content stays under its source service.
- A selected Explorer row and a selected viewport object represent the same
  selection.

Acceptance: `tools/validate_studio_explorer_workflow.gd` must pass.

## Properties Contract

`addons/roblox_studio/roblox_properties.gd` edits live objects and writes the
same values to `roblox_properties` for persistence.

Minimum supported classes and fields:

- Part classes: Color/BrickColor, Material, MaterialVariant, Transparency,
  Reflectance, Shape, Position, Orientation, Size, Anchored, CanCollide,
  CanTouch, CanQuery, CastShadow, Massless, Locked.
- Model: Name, Parent, Archivable, PrimaryPart, Scale, WorldPivot,
  ModelStreamingMode.
- Humanoid: RigType, WalkSpeed, JumpPower, HipHeight, AutoRotate, Health,
  MaxHealth.
- BodyColors: all six R6 body colors with immediate viewport update.
- Tool: Enabled, RequiresHandle, CanBeDropped, ToolTip, TextureId, Grip vectors.
- GUI: Position, Size, Visible, ZIndex, Text, color and image properties.
- Sound: SoundId, Volume, PlaybackSpeed, Looped, Playing.
- Scripts: class, enabled state, source editor entry point.
- Value objects: typed Value field.
- Every Instance: editable Tags and typed Attributes.

An edit commits history and must survive `data_model.build_manifest()`.
Acceptance: `tools/validate_studio_properties_hierarchy.gd` must pass.

## Part and Model Authoring

The Part control offers Box, Sphere, Cylinder, Wedge, CornerWedge, Truss,
SpawnLocation, Checkpoint, and Teleport. Each shape has matching visible mesh,
selection mesh, and collision geometry. Part insertion targets the selected
compatible parent.

Local GLB/GLTF/OBJ assets retain mesh surfaces and authored materials. Models
keep hierarchy, local transforms, colors, textures, and a PrimaryPart. Missing
assets use a clearly marked diagnostic proxy carrying the original asset ID;
they must not silently become an ordinary white cube.

## Terrain

Terrain authoring uses `addons/roblox_studio/roblox_terrain_editor.gd` today.
It must support create/fill/add/subtract/smooth/paint operations, material
selection, brush size, undo, save, and runtime restore.

The current GridMap implementation is the stable fallback. A future smooth
voxel backend may use `Zylann/godot_voxel`, but it must be integrated behind the
same manifest schema and validated on desktop and Android before replacing the
fallback.

Acceptance: `tools/validate_terrain_persistence.gd` must pass.

## Script Runtime

The current compatibility boundary is `autoload/lua_script_engine.gd`.

- Script runs only in server/authority contexts.
- LocalScript runs only in permitted client containers: PlayerGui,
  PlayerScripts, Character, Backpack, and Tool descendants.
- ModuleScript executes once per environment and returns a cached value through
  `require`.
- Syntax validation happens before playtest; rejected scripts appear in Output.
- Instance operations, signals, remotes, services, vectors, CFrame, tables,
  tasks, TweenService, RunService, and common Humanoid/Tool APIs must have tests.
- Long-running scripts have instruction/time budgets and cannot freeze Studio.
- Script errors include script path, line, execution domain, and message.

The long-term engine may embed the open-source Luau compiler and VM. Do not swap
runtimes until the GDExtension passes the same compatibility test corpus and
sandbox boundaries as the current layer.

## Character and Humanoid

Authoring uses `addons/roblox_studio/roblox_character_factory.gd`. Runtime uses
`scripts/player/player.gd` and exposes a script-facing Model/Humanoid contract.

R6 minimum hierarchy:

- HumanoidRootPart
- Torso
- Head
- Left Arm / Right Arm
- Left Leg / Right Leg
- Humanoid with Animator
- Body Colors
- RootJoint, Neck, shoulders, and hips represented as Motor6D relationships

Humanoid state machine:

- Idle
- Running
- Jumping
- Freefall
- Climbing
- Swimming
- Seated
- PlatformStanding
- Dead

State transitions are derived from authoritative movement and emit compatible
signals once per transition. Health cannot exceed MaxHealth. Dead characters do
not accept movement until respawn.

## Movement Acceptance Contract

- Ground acceleration and deceleration are frame-rate independent.
- WalkSpeed drives horizontal target speed; sprint is a controlled multiplier.
- JumpPower/JumpHeight creates one server-authorized jump.
- Floor snap prevents micro-bounces on shallow steps.
- Auto-step climbs only obstacles below the configured step height and only
  when the upper clearance test succeeds.
- Truss/ladder climbing uses surface detection, vertical input, and a clean
  transition to Freefall when contact ends.
- Slope handling never adds energy or sends the body through geometry.
- Local visuals use interpolation; the physics body remains authoritative.
- Remote players use buffered snapshots and bounded extrapolation.

Acceptance: `tools/validate_player_climbing.gd` and the camera/network regression
suite must pass at 30, 60, 120, and 144 render FPS where supported.

## Camera and Shift Lock

- Camera input is sampled in the render/input loop.
- Character movement is applied in `_physics_process`.
- One interpolation system owns the rendered anchor; never combine manual and
  engine interpolation on the same transform.
- The camera rig is independent from the unsmoothed physics transform.
- Spring-arm collision prevents passing through walls without changing player
  physics.
- Shift lock moves the camera shoulder offset and rotates the local character
  toward camera yaw while preserving UI pointer input.
- Desktop and mobile use the same state, with different controls.

## Inventory and Tools

`addons/roblox_runtime/roblox_inventory_controller.gd` owns the local UI while
`LuaScriptEngine` and the server own Tool state.

Lifecycle:

1. StarterPack templates clone into Player.Backpack on spawn.
2. Hotbar and inventory show Backpack tools in stable slot order.
3. Equip reparents/attaches the Tool to Character and emits Equipped.
4. Activation emits Activated only for the equipped enabled Tool.
5. Unequip returns it to Backpack and emits Unequipped.
6. Death/respawn and room leave clean up runtime clones without modifying the
   StarterPack template.

Handle placement uses Tool grip metadata and the character hand attachment.
Server validates equip, activation rate, damage, drops, and ownership. Mobile
and desktop hotbars consume the same inventory state.

Acceptance: `tools/validate_roblox_inventory_runtime.gd` and
`tools/validate_studio_tool_authoring.gd` must pass.

## GUI Authoring and Runtime

StarterGui is previewed inside the Studio viewport and cloned into PlayerGui at
runtime. Support ScreenGui, Frame, TextLabel, TextButton, TextBox, ImageLabel,
ImageButton, ScrollingFrame, list/grid layouts, padding, corner, stroke, scale,
and size constraints.

UDim2 scale and offset remain separate. Do not flatten imported GUI to one
reference resolution. Apply AnchorPoint, clipping, ZIndex, visibility, safe
areas, and aspect constraints. Editor preview input must not leak into the 3D
camera when a GUI control consumes it.

## RBXL Compatibility Pipeline

Import is staged:

1. Parse instances, properties, hierarchy, shared strings, and scripts.
2. Validate finite transforms and reject corrupt values with ref/class context.
3. Build services and storage hierarchy without rendering hidden libraries.
4. Resolve assets from cache and authorized asset delivery.
5. Decode mesh geometry, normals, UVs, vertex colors, and textures.
6. Build Workspace in bounded batches with progress/cancellation.
7. Install GUI, tools, scripts, constraints, lighting, sky, and audio.
8. Produce a structured report for exact, deferred, proxy, skipped, and failed
   objects.

One coordinate conversion function owns position, basis handedness, rotation,
and scale. Mesh and CFrame conversions may not independently flip axes.

Private or unavailable assets remain diagnostic proxies with source IDs. Do not
invent textures or substitute unrelated models.

## Networking

- A room corresponds to one place/server instance.
- The server loads the place manifest and runs server scripts.
- Clients receive replicated Workspace and ReplicatedStorage state allowed by
  policy, then run local scripts.
- ServerStorage and ServerScriptService never replicate to clients.
- Character input is client-originated but server-validated.
- RemoteEvents have schemas, ownership checks, payload limits, and rate limits.
- Persistent profile and catalog writes go through the Bobux API; game clients
  do not write PocketBase directly.

## Performance Budgets

- Studio opens an empty place without recursive asset indexing.
- Toolbox scans are lazy and bounded.
- Imported instances build in batches and yield to the frame loop.
- Texture and mesh assets are cached by immutable ID/hash.
- Runtime avoids per-frame tree-wide searches and material duplication.
- UI lists virtualize or page large result sets.
- A failed network request never blocks the render thread.

## Required Regression Suite

Run with the bundled Godot 4.7 executable:

```powershell
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'C:\robloxclone' --quit-after 3
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_studio_functional_layer.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_new_studio_button_smoke.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_studio_explorer_workflow.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_studio_properties_hierarchy.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_studio_script_editor.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_studio_tool_authoring.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_player_climbing.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_terrain_persistence.gd'
& 'C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path 'C:\robloxclone' --script 'res://tools/validate_rbxl_intermediate_isolation.gd'
```

Also retain map-specific RBXL hierarchy, GUI, asset, and playtest tests. Add a
regression test for every bug that previously caused a crash, freeze, lost
property, wrong parent, or visible storage asset.

## Definition of Done

A feature is complete only when:

- its button/control performs the intended operation;
- the live DataModel changes correctly;
- Explorer and Properties reflect the same object;
- undo/redo works where applicable;
- save/reopen preserves it;
- playtest/runtime consumes it;
- desktop and mobile behavior is checked where relevant;
- automated tests cover success and failure paths;
- no new parser error, invalid callable, non-finite transform, or main-thread
  network wait appears in the Godot log.

## Reference Projects

- Luau compiler/VM: https://github.com/luau-lang/luau
- Roblox DOM formats: https://github.com/rojo-rbx/rbx-dom
- Rojo project model: https://github.com/rojo-rbx/rojo
- Godot voxel terrain: https://github.com/Zylann/godot_voxel

Treat these as specifications and implementation references. Pin versions,
review licenses, isolate integrations behind Bobux interfaces, and add tests
before introducing any external runtime dependency.
