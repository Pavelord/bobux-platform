# Bobux Cloud Development Guide

This repository is the Bobux platform monorepo. It contains the Godot client,
multiplayer server, Bobux Studio, launcher, API compatibility service, assets,
deployment tooling, and documentation.

## Start Here

Read these files before editing:

1. `README.md`
2. `docs/CODEX_HANDOFF_CURRENT_ARCHITECTURE.md`
3. `docs/LEGACY_CLEANUP_AUDIT.md`

Primary code:

- `scripts/`, `scenes/`, `autoload/`: Godot client and Studio.
- `server/server_main.gd`: dedicated multiplayer server.
- `services/bobux_api/`: HTTP API in front of PocketBase.
- `addons/rbxl_importer/`: Roblox place import pipeline.
- `launcher/`: Windows launcher source.
- `tools/`: validation, packaging, and deployment scripts.

The `game/` and `exiting_game/` directories are linked Git repositories. After
cloning, initialize them with:

```bash
git submodule update --init --recursive
```

## Cloud Rules

- Never commit `.env` files, credentials, signing keys, PocketBase data, caches,
  generated releases, or downloaded third-party reference repositories.
- Never deploy or modify the live VPS unless the user explicitly asks for a
  release in the current task.
- The server is authoritative for accounts, inventory, catalog, avatar outfits,
  places, sessions, and multiplayer state.
- Preserve user changes and avoid broad rewrites unrelated to the current task.
- Keep Windows and Android behavior aligned when changing shared UI or runtime
  code.

## Validation

Use the project-provided checks that cover the changed area. Useful entry points
include:

```powershell
godot --headless --path . --editor --quit
powershell -ExecutionPolicy Bypass -File tools\deploy_bobux_release.ps1 -LocalOnly
```

The release script can be expensive and may require local Godot export
templates. In a Linux cloud environment, prefer parse/static tests and explain
which Windows or Android checks still need the release machine.

## Release Safety

Production release files and versions must be generated together. Do not update
only a launcher manifest or upload only an executable. A release is complete
only after the Windows package, launcher, Android APK, manifests, checksums, and
server endpoints all agree and smoke tests pass.

Cloud releases run through the `Bobux Release` GitHub Actions workflow. Never
request, print, or replace its signing/deployment secrets. For a production
release:

1. Merge the tested source to `main`.
2. Dispatch `Bobux Release` with `deploy_production=true`.
3. Let the workflow resolve the next build numbers unless an explicit recovery
   build is required.
4. Confirm the production switch and approve the `production` environment if
   the repository plan asks for approval.
5. Confirm the workflow's post-deploy health checks and GitHub Release.

See `docs/CLOUD_RELEASES.md` for the phone workflow and recovery procedure.
