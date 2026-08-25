# Bobux Project Handoff

Bobux is a Godot 4 multiplayer game with a Roblox-inspired lobby, place editor,
avatar customization, launcher/updater, and a dedicated VPS backend.

This repository is in an emergency stabilization phase. Do not deploy a new build
until the lobby starts reliably, the login flow works, and the avatar preview no
longer freezes the client.

## Current Live Stack

- Client: Godot 4.6.x project in this repository.
- Main scene: `res://scenes/login/login.tscn`.
- API: Node/Express compatibility API in `services/bobux_api/server.js`.
- Database: PocketBase on the VPS, accessed only by the API.
- Multiplayer: Godot dedicated WebSocket server launched through
  `server/server_main.gd` on the VPS.
- Public API URL: `http://109.71.245.162/api`.
- WebSocket URL: `ws://109.71.245.162/ws`.
- Launcher manifest: `game/launcher/latest.json`.

## Important Naming Warning

`autoload/cloud_api.gd` is still named `CloudAPI`, but it is the Bobux
PocketBase/VPS compatibility client now. New code should call this layer, not
Supabase directly.

`autoload/supabase_client.gd` is a legacy shim kept only so old scenes do not
crash. Do not add new dependencies on it.

`exiting_game/` is no longer part of the active release flow. Do not sync into it
or edit it unless a future migration explicitly brings it back.

## Avatar Clothing Pipeline

The avatar decal layer is enabled again in `scripts/player/player.gd`.
Classic shirt and pants templates are cropped with a small edge bleed so the
textures cover the blocky body pieces cleanly, and lobby/profile/friends
previews render the same equipped clothing state as the in-game avatar.

## Key Files

- `scripts/lobby/lobby.gd`: main lobby UI, home sections, profile popups, develop hub, catalog entry points.
- `scripts/lobby/avatar_ui.gd`: avatar customization UI and cloud inventory loading.
- `scripts/player/player.gd`: runtime character controller, avatar preview, chat bubble, visual decals.
- `scripts/main/main.gd`: in-game runtime, map loading, room behavior, teleport/destructible logic.
- `server/server_main.gd`: active dedicated WebSocket server entry point used by VPS deploy.
- `scripts/place_editor/studio.gd`: place editor and publish pipeline.
- `scripts/place_editor/model_editor.gd`: model editor and import/publish work.
- `autoload/cloud_api.gd`: Bobux API client and cache/download/upload compatibility layer.
- `autoload/client_network.gd`: WebSocket client and matchmaking transport.
- `services/bobux_api/server.js`: current production API over PocketBase and local storage.
- `deploy_vps.ps1`: Windows deployment helper. Do not run during stabilization unless the user explicitly says to release.

## Safe Next Steps

1. Fix startup/lobby crashes first.
2. Keep avatar decals disabled until a clean template renderer exists.
3. Remove legacy references only after replacing all callers.
4. Validate in the editor before exporting.
5. Only then build Windows/APK and update launcher manifests.

For a more detailed map of current technical debt and cleanup priorities, see
`docs/CODEX_HANDOFF_CURRENT_ARCHITECTURE.md` and
`docs/LEGACY_CLEANUP_AUDIT.md`.
