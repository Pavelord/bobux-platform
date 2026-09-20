#!/usr/bin/env python3
"""Assemble and execute-test the staged AppDir on a Linux builder before publishing."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

stage = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
assert stage.name.startswith('bobux-linux-smoke.') and stage.parent == Path('/tmp')
runtime = stage / 'appimage-runtime-x86_64'
assert hashlib.sha256(runtime.read_bytes()).hexdigest() == '1cc49bcf1e2ccd593c379adb17c9f85a36d619088296504de95b1d06215aebbf'
assert shutil.which('mksquashfs'), 'Install squashfs-tools on the Linux builder first'
subprocess.run(['mksquashfs', str(stage / 'Bobux'), str(stage / 'app.squashfs'), '-noappend', '-comp', 'gzip', '-processors', '1', '-no-progress'], check=True)
artifact = out / 'Bobux-x86_64.AppImage'
with artifact.open('wb') as target:
    for source in [runtime, stage / 'app.squashfs']:
        with source.open('rb') as stream:
            shutil.copyfileobj(stream, target)
artifact.chmod(0o755)
smoke = subprocess.run([str(artifact), '--headless', '--', '--verify-lua-runtime'], env={**os.environ, 'APPIMAGE_EXTRACT_AND_RUN': '1'}, capture_output=True, text=True, timeout=120)
assert smoke.returncode == 0 and 'BOBUX_LUA_SMOKE_OK' in smoke.stdout, (smoke.stdout + smoke.stderr)[-4000:]
manifest_path = out / 'desktop-latest.json'
manifest = json.loads(manifest_path.read_text())
with artifact.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
manifest['platforms']['linux'] = {'url': '/downloads/' + artifact.name, 'sha256': digest, 'size': artifact.stat().st_size, 'format': 'AppImage', 'architecture': 'x86_64', 'display': ['wayland', 'x11']}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print('APPIMAGE_LUA_SMOKE_OK', digest, artifact.stat().st_size)
