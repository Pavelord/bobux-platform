# Bobux Release Checklist

This checklist is for the current Moscow VPS release path:

- Game server: `ws://109.71.245.162/ws`
- Bobux API: `http://109.71.245.162/api`
- Launcher manifest: `http://109.71.245.162/launcher/latest.json`
- Public download page: `http://109.71.245.162/`
- Database: PocketBase on the VPS, behind the Bobux API

Supabase is no longer the release dependency for new builds. Do not run old Supabase SQL unless you are deliberately testing legacy builds.

## 1. Local Validation

Run these before every release:

```powershell
& C:\robloxclone\.codex-tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\robloxclone --script res://tools/validate_runtime_load.gd
& C:\robloxclone\.codex-tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\robloxclone\launcher --script res://tools/validate_launcher_load.gd
```

Both commands must finish without parse errors.

## 2. Export Main Game

```powershell
$godot = "C:\robloxclone\.codex-tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe"
Remove-Item C:\robloxclone\dist\game -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path C:\robloxclone\dist\game -Force | Out-Null
& $godot --headless --path C:\robloxclone --export-release "Windows Desktop" C:\robloxclone\dist\game\Bobux.exe
Compress-Archive -Path C:\robloxclone\dist\game\* -DestinationPath C:\robloxclone\dist\Bobux-Windows.zip -Force
Get-FileHash C:\robloxclone\dist\Bobux-Windows.zip -Algorithm SHA256
```

Put that SHA256 into `C:\robloxclone\game\launcher\latest.json`.

## 3. Export Launcher

```powershell
$godot = "C:\robloxclone\.codex-tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe"
Remove-Item C:\robloxclone\launcher_export\windows -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path C:\robloxclone\launcher_export\windows -Force | Out-Null
& $godot --headless --path C:\robloxclone\launcher --export-release "Windows Desktop" C:\robloxclone\launcher_export\windows\BobuxLauncher.exe
Compress-Archive -Path C:\robloxclone\launcher_export\windows\* -DestinationPath C:\robloxclone\dist\BobuxLauncher-Windows.zip -Force
Get-FileHash C:\robloxclone\dist\BobuxLauncher-Windows.zip -Algorithm SHA256
```

Put the launcher ZIP SHA256 into the `launcher.sha256` field in `C:\robloxclone\game\launcher\latest.json`.

## 4. Manifest Format

Current format:

```json
{
  "version": "0.1.1",
  "build": 3,
  "zip_url": "http://109.71.245.162/downloads/Bobux-Windows.zip",
  "sha256": "GAME_ZIP_SHA256",
  "executable": "Bobux.exe",
  "mirrors": [
    "http://109.71.245.162/downloads/Bobux-Windows.zip"
  ],
  "launcher": {
    "version": "0.1.0",
    "build": 2,
    "zip_url": "http://109.71.245.162/downloads/BobuxLauncher-Windows.zip",
    "sha256": "LAUNCHER_ZIP_SHA256",
    "mirrors": [
      "http://109.71.245.162/downloads/BobuxLauncher-Windows.zip"
    ]
  }
}
```

Rules:

- Increase `build` every time the game ZIP changes.
- Increase `launcher.build` every time the launcher ZIP changes.
- Hash the ZIP file, not the `.exe` and not the `.pck`.
- The URL must download the file directly.

## 5. Deploy To VPS

Recommended from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\robloxclone\deploy_vps.ps1 -HeartbeatToken $env:BOBUX_SERVER_HEARTBEAT_TOKEN
```

If the scripted deploy is too slow, upload these exact files manually to the VPS:

```text
C:\robloxclone\dist\Bobux-Windows.zip -> /var/www/bobux/downloads/Bobux-Windows.zip
C:\robloxclone\dist\BobuxLauncher-Windows.zip -> /var/www/bobux/downloads/BobuxLauncher-Windows.zip
C:\robloxclone\dist\installer\BobuxSetup.exe -> /var/www/bobux/downloads/BobuxSetup.exe
C:\robloxclone\game\launcher\latest.json -> /var/www/bobux/launcher/latest.json
C:\robloxclone\game\launcher\latest.json -> /var/www/bobux/downloads/latest.json
```

Then restart services:

```bash
pm2 restart bobux-api --update-env
pm2 restart bobux --update-env
pm2 save
```

## 6. Compile Installer

Use Inno Setup:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" C:\robloxclone\tools\installer\bobux_launcher.iss
```

Output:

```text
C:\robloxclone\dist\installer\BobuxSetup.exe
```

This is the only file you should send to friends. The installer installs the launcher; the launcher downloads and updates the game.

## 7. Live Endpoint Checks

Open these URLs:

```text
http://109.71.245.162/
http://109.71.245.162/api/health
http://109.71.245.162/launcher/latest.json
http://109.71.245.162/downloads/BobuxSetup.exe
```

Expected:

- Page opens.
- API health returns JSON.
- Manifest JSON is the latest build.
- Setup download starts.

## 8. Required Multiplayer Smoke Test

1. Install using `BobuxSetup.exe`.
2. Launch Bobux from the desktop shortcut.
3. Confirm the launcher downloads the game and launches it.
4. Create account A.
5. Create account B on another PC or another Windows user.
6. Create a test mode from Develop.
7. Confirm it appears in Home/Games.
8. Join the same mode from both accounts.
9. Confirm both players enter the same room and see each other.
10. Send chat messages.
11. Publish a map with at least one music track.
12. Delete the map and confirm it disappears from Home, Games, Profile, and Continue Playing.

## 9. PocketBase Notes

PocketBase runs only on the server:

```text
127.0.0.1:8090
```

The game client should not connect to PocketBase directly. It talks to:

```text
http://109.71.245.162/api
```

The Bobux API owns auth, profiles, maps, active servers, friends, follows, and storage.

## 10. Emergency Checks

```bash
pm2 list
pm2 logs bobux --lines 80 --nostream
pm2 logs bobux-api --lines 80 --nostream
curl -i http://127.0.0.1:3000/api/health
curl -i http://127.0.0.1:8090/api/health
curl -i http://109.71.245.162/health
```

If launcher says hash mismatch:

```powershell
Get-FileHash C:\robloxclone\dist\Bobux-Windows.zip -Algorithm SHA256
Get-FileHash C:\robloxclone\dist\BobuxLauncher-Windows.zip -Algorithm SHA256
Get-Content C:\robloxclone\game\launcher\latest.json
```

The manifest hashes must match the ZIPs uploaded to `/var/www/bobux/downloads`.
