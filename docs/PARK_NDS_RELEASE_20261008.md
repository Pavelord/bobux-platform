# Park / NDS release audit — 2026-10-08

Target: akx0oto939gi501_bobux_park_krut. Published data has one LocalScript (BobuxKrutStory, about 3,200 lines), Roblox-style Lua running on Luau 0.719, plus the BobuxParty extension. Monster and cinematics use procedural CFrame animation, not uploaded Animation tracks. The file format proves Bobux publication but does not prove which editor or AI authored the source. No native engine modification by the map author is established.

Fixes: timestamp camera writes (not reads); Custom restores local camera rig and Scriptable retains scripted pose; explicit CameraType transitions in the park's capture/lobby script, removed forced post-cutscene CFrame repair; actual ScreenTouch activation with drag cancellation; decorative GUI does not consume input; independent watchdog per task and fair rotation; download authored sound assets in background, cancel pending play on Stop.

Asset audit: all 52 declared URLs respond 200. 22 meshes, 22 Ogg sounds, 6 mesh JSON files and 2 PNG atlases load/parse in Godot. This is not proof that every ending or every device renders perfectly.

NDS: both natural/narural published maps retain 7,483 Lighting template Parts and 64 authored color values. Server was serializing white renderer colors for spawned templates (790 white parts observed). Canonical Color now survives deferred geometry and serialization; Color/BrickColor mutations update that canonical state. Plain materials no longer multiply Part tint twice. Published Lighting-only settings now use Studio ambient/brightness/fog mapping.

Validation: camera/touch regression passes; watchdog intentionally times out one infinite task while all 12 siblings complete; exported Windows Luau smoke passes. Actual park entry with touch start: 8–10 seconds cached, no Luau errors after task/audio fixes. Native Android device unavailable; synthetic touch is not an on-device FPS test. Network still logs cross-room MultiplayerSpawner errors in some sessions; this architecture issue is not claimed resolved.

Production: 2 GiB swap was added after a confirmed VPS OOM kill. This mitigates process death, not CPU/rendering performance. Runtime source backup: /opt/bobux-runtime-backup-20261008T120544. Game source backup: /opt/bobux-api/data/park-camera-backup-20261008T100635Z.json. Source-only camera patch preserved map geometry/assets and checked the previous source before updating. PM2 bobux restarted after production color/lighting regression passed.

Release intended: Windows 0.1.48 build 53, Android 0.1.48-mobile build 53, launcher 0.1.18 build 20. See deployment logs before claiming publication. Linux is not rebuilt in this release.
