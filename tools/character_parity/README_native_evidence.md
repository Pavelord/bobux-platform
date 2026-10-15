# Byte-exact native evidence archives

Run from `C:\robloxclone`. This helper stores our own UTF-8 telemetry in one Zstd frame and a JSON sidecar. It does not modify the original raw file or assign a parity result.

```powershell
python tools/character_parity/native_evidence_archive.py pack tests/roblox_humanoid/phase_a/example.raw.log --output tests/roblox_humanoid/phase_a/example.raw.log.zstd --manifest tests/roblox_humanoid/phase_a/example.raw.log.zstd.json
python tools/character_parity/native_evidence_archive.py unpack tests/roblox_humanoid/phase_a/example.raw.log.zstd --manifest tests/roblox_humanoid/phase_a/example.raw.log.zstd.json --output .codex-tmp/character_parity/example-restored.raw.log
```

Use actual evidence filenames and a fresh output destination with an existing parent directory. All explicit paths must resolve inside the workspace, including through existing symlinks. Paths inside a manifest are never used as destinations. Existing files are refused. There are no recursive operations.

The sidecar records raw SHA256/bytes, packed SHA256/bytes, Zstd level 3, content-size/checksum/single-frame policy and package version. Unpack verifies hashes, strict UTF-8, exact frame content size and the 128 MiB raw cap; unknown-size frames, extra frames and trailing data are refused. Restore to a new path, then point the analysis tool at that restored raw file. Keep the immutable original where it is already saved; committing the `.zstd` and `.json` does not require committing the large plaintext.

Tiny tests (run only after the current native/Godot measurement window is closed):

```powershell
python -m unittest discover -s tools/character_parity -p test_native_evidence_archive.py -v
```
