# Bobux Legacy Cleanup Audit

Last updated: 2026-06-11.

This file exists so the next clean Codex session does not mistake old deployment
paths for active game systems.

## Active Runtime

- Client: Godot project at the repository root.
- API/backend: `services/bobux_api/server.js`.
- Multiplayer: active Godot dedicated WebSocket server launched with
  `server/server_main.gd`.
- Public API URL: `http://109.71.245.162/api`.
- Public WebSocket URL: `ws://109.71.245.162/ws`.
- Database/storage: PocketBase on the VPS, accessed through the Bobux API.

## Keep For Compatibility

- `autoload/cloud_api.gd`: active Bobux API wrapper. The file keeps a few
  legacy cache/session filenames only so old local sessions can migrate safely;
  it must not be reconnected to Supabase.
- `autoload/supabase_client.gd`: compatibility shim for old callers. Do not add
  new Supabase behavior here; route new API calls through `CloudAPI`.
- `project.godot` autoload name `SupabaseClient`: keep until every old caller is
  migrated.

## Treat As Legacy / Do Not Extend

- `exiting_game/`: old mirrored deployment folder. Current deploy/export scripts
  exclude it. Do not sync or edit it.
- `supabase/`: old migrations/policies. Do not apply automatically.
- `render.yaml`: removed on 2026-06-11.
- `docs/free_hosting_guide.md` and `docs/huggingface_setup.md`: removed on 2026-06-11.
- `tools/sync_exiting_game.ps1`: removed on 2026-06-11.
- `tools/deploy_hf_dedicated_space.py`: removed on 2026-06-11.

## Active But Legacy-Named

- `server/server_main.gd`: active Godot dedicated WebSocket entry point. It now
  uses Bobux API/service-key naming and is launched by `ops/vps/deploy_remote.sh`.
  Do not delete it.
- `docker-entrypoint.sh`, `Dockerfile`, and `ops/vps/deploy_remote.sh`: deployment
  helpers with older Godot-server assumptions. Audit before removing.

## Safe Cleanup Already Done

- Emergency avatar rollback disables the unstable avatar decal layer in
  `scripts/player/player.gd` via `ENABLE_AVATAR_DECAL_LAYER = false`.
- Saved face/badge/shirt/pants metadata is preserved; only the broken visual
  projection layer is hidden.
- Avatar body-part UI highlighting now checks for freed controls before styling.
- Windows and Android export presets exclude backend, legacy Supabase, docs,
  tools, launcher, and deployment folders from client builds.
- Obsolete Render/HuggingFace hosting docs and `render.yaml` were removed.
- Obsolete `exiting_game` sync and HuggingFace deploy tools were removed.
- Old Supabase/Render environment fallbacks were removed from the active
  dedicated server path; use `BOBUX_API_URL`, `BOBUX_REST_BASE_URL`,
  `BOBUX_SERVICE_KEY`, and `PUBLIC_SERVER_WS_URL`.
- One-off root helper files (`test.py`, `_fix_cache.py`, `build_ui.py`,
  `test_rpc.gd.uid`) were removed because no active script references them.
- Temporary root `tmp_*.log` files may be deleted at any time.

## Next Cleanup Steps

1. Migrate remaining callers away from the `SupabaseClient` autoload name.
2. Replace legacy local auth/session cache filenames after old exported builds
   no longer need migration compatibility.
3. Delete `supabase/` after confirming there are no needed historical migration
   notes inside it.
4. Remove or archive `exiting_game/` outside the project root so Godot stops
   warning about the nested `project.godot`.

## Do Not Do In A Blind Cleanup

- Do not delete `autoload/cloud_api.gd`; it is active despite old names.
- Do not delete `autoload/supabase_client.gd` until all references are migrated.
- Do not deploy a build until the user explicitly approves it.
