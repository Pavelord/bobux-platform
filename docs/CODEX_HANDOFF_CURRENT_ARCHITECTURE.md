# Bobux Current Architecture and Cleanup Map

Last updated: 2026-06-11.

This file exists so a fresh Codex thread can continue without inheriting the
confusion from old Supabase, Render, Hugging Face, and `exiting_game` paths.

## Release Rule

Do not upload a release while this branch is in stabilization. The user asked to
stop deploying broken builds. Make code changes locally, validate, then ask for
permission before running deploy scripts.

## Active Runtime

- Godot project root: `C:/robloxclone`
- App name: Bobux
- Main scene: `res://scenes/login/login.tscn`
- API base: `http://109.71.245.162/api`
- WebSocket: `ws://109.71.245.162/ws`
- Backend implementation: `services/bobux_api/server.js`
- Backend storage/database: PocketBase plus files on the VPS
- Multiplayer process: Godot headless dedicated server launched with
  `server/server_main.gd`

## Active Autoloads

- `GameState`: local game/session state.
- `UserSession`: logged-in user state and avatar snapshot.
- `Analytics`: lightweight event helper.
- `CloudAPI`: current Bobux API client despite the legacy name.
- `SupabaseClient`: legacy compatibility shim only.
- `MapManager`: map cache/download entry point.
- `NetworkManager`: WebSocket transport and room join flow.
- `MobileRuntime`: Android/mobile controls and runtime behavior.
- `LuaScriptEngine`: experimental script runtime.

## Active But Messy Areas

These paths are active and should be handled deliberately:

- `server/server_main.gd`: active Godot dedicated WebSocket entry point. It uses
  Bobux API/service-key naming and is launched by the VPS deploy scripts. Do not
  delete it.
- `docker-entrypoint.sh`, `Dockerfile`, and `ops/vps/deploy_remote.sh`: deployment
  helpers that may still start the Godot dedicated server. Audit before removal.

## Legacy/Archived Areas

These paths are not part of the intended active release path:

- `exiting_game/`: old deployment mirror. Current export/deploy scripts exclude it.
- `supabase/`: old SQL migrations and policies. Do not apply automatically.
- `render.yaml`: removed on 2026-06-11.
- `docs/free_hosting_guide.md` and `docs/huggingface_setup.md`: removed on 2026-06-11.
- `heartbeat_status.json`: legacy inactive heartbeat artifact updated to the VPS URL.

Do not delete these blindly until all code references are removed or a release
branch confirms they are unused. Marking them here prevents new work from
building on them accidentally.

## Current Emergency Fix

The unstable avatar decal projection layer is disabled by default:

```gdscript
const ENABLE_AVATAR_DECAL_LAYER: bool = false
const ENABLE_AVATAR_CLOTHING_DECALS: bool = false
```

File: `scripts/player/player.gd`

Why: template cropping and multi-decal projection are currently incorrect. They
make avatars ugly, make previews expensive, and risk freezing the lobby. Saved
face/badge/shirt/pants data remains in profiles so the future renderer can reuse it.

## Known High-Risk Systems

- Avatar clothing/template pipeline: needs a clean atlas renderer before release.
- Model editor import/publish: partially implemented, needs validation before public use.
- Catalog/avatar items: backend collections exist, UI is not production-grade yet.
- Lobby sections: many async refreshes exist; avoid adding more automatic network calls.
- Old compatibility names: `SupabaseClient` is only an autoload shim, not a live
  Supabase connection.

## Recommended Cleanup Order

1. Stabilize lobby startup and avatar preview.
2. Keep home/profile/friends previews lightweight.
3. Replace `SupabaseClient` callers with direct `CloudAPI` calls, then remove the shim.
4. Replace legacy local session/cache filenames after old exported builds no
   longer need migration compatibility.
5. Rewrite avatar clothes from a single atlas texture system, not many ad-hoc decals.
6. Rebuild model/catalog UI after the base game is stable.

## Validation Checklist Before Any Deploy

- Godot editor opens without parse errors.
- Login works with a real account.
- Lobby reaches Home without freezing.
- Avatar tab opens and can change body colors.
- Games list loads progressively and does not block the UI.
- Joining a known map succeeds.
- Returning to lobby clears mobile controls and game UI.
- Friend request send/receive works in lobby and in-game.
- Windows export version and launcher manifest build number are incremented.
- Android export version code is incremented if APK is built.

## Notes For The Next Codex Thread

- The user values speed, but broken releases hurt trust. Validate first.
- Do not sync or edit `exiting_game`.
- Do not reconnect Supabase.
- Do not deploy until the user explicitly says the local build is acceptable.
- Prefer small reversible stabilizing patches before large feature work.
