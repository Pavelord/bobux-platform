# Halloween update trailer

`UpdateTrailer` plays the bundled `assets/video/bobux_halloween_2026.ogv` from the authenticated lobby. A black overlay appears before the first lobby frame, fades into the movie, and returns to the lobby after the ending or Skip. The Halloween home card also offers replay.

The premiere is acknowledged per account and release in `user://events/update_trailers.json` after completion or deliberate skipping. A decoder failure leaves it unacknowledged for the next visit. Returning from a mode does not replay it. Manual replay is always available.

The video is Ogg Theora/Vorbis, 1280×720 at 30 fps, encoded from the finished Godot trailer. It travels with the application and requires no HTTP request or external media plugin. A full-screen aspect container preserves 16:9 on landscape and portrait devices. The covered lobby, including avatar SubViewports, suspends rendering while networking continues. Mobile background/resume pauses and resumes the movie; a watchdog releases failed playback.

Source trailer: `C:/BobuxHalloweenTrailer/renders/Bobux_Halloween_Update.mp4`, SHA-256 `3cd93ee32dc82337950dd06b6ec0cd6a1409ba6a42e051c55295895bb0fcfe2a`.

Local validation:

```powershell
Godot --path C:/robloxclone --script res://tools/validate_update_trailer.gd
```

The graphical probe uses the real decoder through the complete movie, verifies transitions, account-specific acknowledgement, duplicate-click protection, replay, background pause, portrait layout, and Skip. `--headless` runs persistence checks without trying to show a premiere. Performance probes can pass `-- --skip-update-trailer`.

No deployment is performed by this integration. The next released client includes the movie with its normal export.
