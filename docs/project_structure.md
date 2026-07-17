# Suggested project structure

This MVP keeps the current files small, but it also leaves obvious places for larger systems later.

## Current runtime folders

- `res://autoload/`
  - Small shared state such as selected lobby options and the next launch mode.
- `res://scenes/lobby/`
  - The front-end lobby menu with color selection and place selection.
- `res://scenes/main/`
  - Main world scene, runtime HUD, and multiplayer spawner.
- `res://scenes/player/`
  - The reusable player avatar scene, including its third-person camera rig.
- `res://scripts/lobby/`
  - Lobby UI logic, color picking, host or join selection, and scene launch.
- `res://scripts/main/`
  - Session setup, spawn registration, network events, and world session flow.
- `res://scripts/player/`
  - Character movement, orbit camera, procedural animation, and multiplayer state sync.

## Good next folders

- `res://scenes/place_editor/`
  - Future building tools, palette UI, save or load editor scenes.
- `res://scripts/place_editor/`
  - Brush logic, grid snapping, selection, copy, paste, and serialization helpers.
- `res://services/database_auth/`
  - Future HTTP or WebSocket bridge code for accounts, sessions, and cloud saves.
- `res://services/database_auth/api/`
  - Small wrappers around login, profile, inventory, and place save endpoints.
- `res://assets/`
  - Shared materials, icons, audio, and later retro props.
- `res://autoload/`
  - Optional global singletons later, such as `GameSession`, `PlayerProfile`, or `PlaceRepository`.
- `res://tests/`
  - Future lightweight gameplay and networking tests.

## Suggested growth path

1. Keep gameplay scenes inside `scenes/` and reusable logic inside `scripts/`.
2. Add editor-only building tools under `place_editor` so they do not mix with runtime player code.
3. Put remote data access under `services/database_auth` so networking gameplay and backend auth stay separate.
4. If the project grows, split the current `main.gd` into `network_manager.gd`, `menu_controller.gd`, and `camera_controller.gd`.
