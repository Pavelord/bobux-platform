# Bobux Launcher / Updater

## Release Flow

1. Export the main game as a Windows zip. The zip root must contain `Bobux.exe`, `.pck`, DLLs, and any required files.
2. Upload the zip to the Bobux VPS static update folder or another direct HTTPS
   mirror. Do not use Supabase Storage for new releases.
3. Publish a small JSON manifest:

```json
{
  "version": "0.1.0",
  "build": 1,
  "zip_url": "https://github.com/YOUR_USER/YOUR_REPO/releases/download/v0.1.0/Bobux-Windows.zip",
  "sha256": "optional-lowercase-sha256",
  "executable": "Bobux.exe",
  "notes": "Public build"
}
```

4. Export the launcher from `launcher/` as `BobuxLauncher.exe`.
5. Set `launcher/manifest_url` in `launcher/project.godot` before export or in your export preset.
6. Build the installer with Inno Setup using `tools/installer/bobux_launcher.iss`.

## Runtime Layout

The installer only installs the launcher:

```text
%LOCALAPPDATA%/BobuxLauncher/BobuxLauncher.exe
```

The launcher installs and updates the game here:

```text
%LOCALAPPDATA%/Bobux/Game/Bobux.exe
%LOCALAPPDATA%/Bobux/Game/version.json
```

This keeps updates user-local, avoids admin permissions, and lets the launcher replace the game files while the game is closed.

## Safety Rules

- The launcher rejects zip entries containing `../` or absolute paths.
- If `sha256` is present, the launcher verifies the downloaded zip before replacing the installed game.
- Updates extract into `_staging_game` first, then atomically replace the `Game` folder.
- The launcher remains separate from the game, so a broken game build does not break the updater.
