# Open-source architecture review

Bobux keeps gameplay authority, published assets, and player state in its own
server-backed runtime. External Godot projects are reviewed as focused design
references; they are not copied wholesale into the game because replacing the
existing network or inventory core would break Bobux map and account contracts.

## Integrated patterns

- `MarcoFazioRandom/Virtual-Joystick-Godot` (MIT): Bobux mobile controls now
  expose Fixed, Dynamic, and Following joystick placement modes plus a radial
  configurable dead zone. The implementation remains inside
  `autoload/mobile_runtime.gd` so touch ownership, camera blocking, sprint, and
  shift lock continue to use one input router.
- `developer-benny-zhu/godot-material-footsteps` (MIT): imported and native map
  collision bodies expose material metadata. The Humanoid resolves
  `FloorMaterial` from the actual floor collision, which can drive footsteps and
  Luau game logic without inspecting rendered pixels.
- `expressobits/inventory-system` (MIT): the useful separation between inventory
  state and presentation matches Bobux's existing Roblox inventory controller
  and hotbar. Bobux retains its server-owned item state and does not vendor a
  second competing inventory database.
- `devmoreir4/godot-3d-multiplayer-template`: networking and avatar replication
  patterns were compared with Bobux. Bobux retains its existing
  server-authoritative rooms, snapshots, chat, outfits, and inventory payloads.

## Reviewed but not copied

- `anandamous/ParkourCharacterController` is GPL-3.0. Bobux does not copy this
  code into the project. Its movement remains an original controller with
  climbing, mantling, swimming, seating, sprint, auto-step, and death breakup.
- Wall-running and rope examples are optional mechanics, not safe replacements
  for Roblox-compatible Humanoid behavior. They should be introduced as
  isolated Studio components only when a game creator enables them.
- Rollback netcode is not substituted for Bobux's room-authoritative model. A
  second synchronization core would create conflicting owners for transforms,
  tools, and checkpoints.

## Validation contracts

The repository includes executable Godot checks for mobile joystick modes,
authoritative map statistics, legacy map colors, canonical GLB materials, saved
mesh material round-trips, cloud map publishing, and runtime script loading.
These tests protect the compatibility layer while Studio features expand.
